#!/bin/bash
#
# Merge PR with GAAC validation
#
# Validates PR is ready to merge (non-draft, CI green) and executes merge
# with configurable strategy.
#
# Usage:
#   merge-pr.sh --pr <number> [--strategy <squash|merge|rebase>]
#

set -euo pipefail

# Parse arguments
PR_NUMBER=""
STRATEGY=""
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --pr)
            PR_NUMBER="$2"
            shift 2
            ;;
        --strategy)
            STRATEGY="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [ -z "$PR_NUMBER" ]; then
    echo "Usage: merge-pr.sh --pr <number> [--strategy <squash|merge|rebase>]" >&2
    exit 1
fi

# Setup paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HELPER="$SCRIPT_DIR/../../../scripts/gaac-config.sh"

# Get merge strategy from config if not specified
if [ -z "$STRATEGY" ]; then
    if [ -f "$CONFIG_HELPER" ]; then
        STRATEGY=$(bash "$CONFIG_HELPER" get "gaac.merge_strategy" 2>/dev/null || echo "")
    fi
    # Default to squash
    STRATEGY="${STRATEGY:-squash}"
fi

# Validate strategy
case "$STRATEGY" in
    squash|merge|rebase)
        ;;
    *)
        echo "Invalid merge strategy: $STRATEGY (must be: squash, merge, or rebase)" >&2
        exit 1
        ;;
esac

echo "=== Merge PR #$PR_NUMBER ==="
echo ""

# ========================================
# Fetch PR Details
# ========================================

echo "Fetching PR details..."
PR_DATA=$(gh pr view "$PR_NUMBER" --json title,state,isDraft,mergeable,mergeStateStatus,statusCheckRollup,headRefName,baseRefName,url 2>/dev/null || echo "{}")

if [ -z "$PR_DATA" ] || [ "$PR_DATA" = "{}" ]; then
    echo "❌ Error: PR #$PR_NUMBER not found" >&2
    exit 1
fi

PR_TITLE=$(echo "$PR_DATA" | jq -r '.title // ""')
PR_STATE=$(echo "$PR_DATA" | jq -r '.state // ""')
PR_IS_DRAFT=$(echo "$PR_DATA" | jq -r '.isDraft // false')
PR_MERGEABLE=$(echo "$PR_DATA" | jq -r '.mergeable // ""')
PR_MERGE_STATUS=$(echo "$PR_DATA" | jq -r '.mergeStateStatus // ""')
PR_HEAD=$(echo "$PR_DATA" | jq -r '.headRefName // ""')
PR_BASE=$(echo "$PR_DATA" | jq -r '.baseRefName // ""')
PR_URL=$(echo "$PR_DATA" | jq -r '.url // ""')

echo "  Title: $PR_TITLE"
echo "  State: $PR_STATE"
echo "  Draft: $PR_IS_DRAFT"
echo "  Mergeable: $PR_MERGEABLE"
echo "  Merge Status: $PR_MERGE_STATUS"
echo "  Branch: $PR_HEAD -> $PR_BASE"
echo ""

# ========================================
# Validation
# ========================================

ERRORS=()

# Check if PR is open
if [ "$PR_STATE" != "OPEN" ]; then
    ERRORS+=("PR is not open (state: $PR_STATE)")
fi

# Check if PR is draft
if [ "$PR_IS_DRAFT" = "true" ]; then
    ERRORS+=("PR is still a draft")
fi

# Check if PR is mergeable
if [ "$PR_MERGEABLE" = "CONFLICTING" ]; then
    ERRORS+=("PR has merge conflicts")
fi

# Check CI status
echo "Checking CI status..."
CI_STATUS=$(echo "$PR_DATA" | jq -r '.statusCheckRollup // []')
CI_COUNT=$(echo "$CI_STATUS" | jq 'length')

if [ "$CI_COUNT" -gt 0 ]; then
    # Check if any checks failed
    FAILED_CHECKS=$(echo "$CI_STATUS" | jq -r '.[] | select(.conclusion == "FAILURE") | .name' 2>/dev/null || echo "")
    PENDING_CHECKS=$(echo "$CI_STATUS" | jq -r '.[] | select(.status == "IN_PROGRESS" or .status == "QUEUED") | .name' 2>/dev/null || echo "")

    if [ -n "$FAILED_CHECKS" ]; then
        ERRORS+=("CI checks failed: $(echo "$FAILED_CHECKS" | tr '\n' ', ')")
    fi

    if [ -n "$PENDING_CHECKS" ] && [ "$FORCE" != "true" ]; then
        ERRORS+=("CI checks pending: $(echo "$PENDING_CHECKS" | tr '\n' ', ')")
    fi

    # Count passed checks
    PASSED_COUNT=$(echo "$CI_STATUS" | jq '[.[] | select(.conclusion == "SUCCESS")] | length')
    echo "  CI: $PASSED_COUNT/$CI_COUNT checks passed"
else
    echo "  CI: No status checks found"
fi

echo ""

# Report errors
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo "❌ Cannot merge - validation failed:"
    for err in "${ERRORS[@]}"; do
        echo "   - $err"
    done
    echo ""

    if [ "$FORCE" = "true" ]; then
        echo "⚠️  Force flag set - attempting merge anyway..."
    else
        exit 1
    fi
fi

# ========================================
# Execute Merge
# ========================================

echo "Merging PR with --$STRATEGY strategy..."
echo ""

if gh pr merge "$PR_NUMBER" "--$STRATEGY" --delete-branch; then
    echo ""
    echo "✅ PR #$PR_NUMBER merged successfully"
    echo "   Strategy: $STRATEGY"
    echo "   Branch deleted: $PR_HEAD"

    # Output JSON for programmatic use
    echo ""
    echo "JSON_OUTPUT:"
    jq -n \
        --arg pr "$PR_NUMBER" \
        --arg title "$PR_TITLE" \
        --arg strategy "$STRATEGY" \
        --arg url "$PR_URL" \
        --arg base "$PR_BASE" \
        --arg head "$PR_HEAD" \
        '{
            pr_number: $pr,
            title: $title,
            strategy: $strategy,
            url: $url,
            base_branch: $base,
            head_branch: $head,
            merged: true
        }'
else
    echo ""
    echo "❌ Merge failed" >&2
    exit 1
fi
