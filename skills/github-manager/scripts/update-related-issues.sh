#!/bin/bash
#
# Update Related Issues After PR Merge
#
# Parses PR for resolved/related issues and updates them accordingly:
# - Resolved issues (Resolves/Fixes/Closes #N): Add completion comment, close
# - Related issues (Related: #N, See: #N): Add progress comment
# - Dependent issues: Notify that dependency is resolved
#
# Usage:
#   update-related-issues.sh --pr <number>
#   update-related-issues.sh --pr <number> --dry-run
#

set -euo pipefail

# Parse arguments
PR_NUMBER=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --pr)
            PR_NUMBER="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [ -z "$PR_NUMBER" ]; then
    echo "Usage: update-related-issues.sh --pr <number> [--dry-run]" >&2
    exit 1
fi

# ========================================
# Fetch PR Details
# ========================================

echo "Fetching PR #$PR_NUMBER..."
PR_DATA=$(gh pr view "$PR_NUMBER" --json title,body,state,mergedAt,mergeCommit,url 2>/dev/null || echo "{}")

if [ -z "$PR_DATA" ] || [ "$PR_DATA" = "{}" ]; then
    echo "❌ Error: PR #$PR_NUMBER not found" >&2
    exit 1
fi

PR_TITLE=$(echo "$PR_DATA" | jq -r '.title // ""')
PR_BODY=$(echo "$PR_DATA" | jq -r '.body // ""')
PR_STATE=$(echo "$PR_DATA" | jq -r '.state // ""')
PR_MERGED_AT=$(echo "$PR_DATA" | jq -r '.mergedAt // ""')
PR_URL=$(echo "$PR_DATA" | jq -r '.url // ""')
PR_COMMIT=$(echo "$PR_DATA" | jq -r '.mergeCommit.oid // ""' | head -c 7)

echo "  Title: $PR_TITLE"
echo "  State: $PR_STATE"

# ========================================
# Parse Issue References
# ========================================

# Initialize arrays
RESOLVED_ISSUES=()
RELATED_ISSUES=()

# Extract from PR title: [Issue #N] pattern
TITLE_ISSUES=$(echo "$PR_TITLE" | grep -oE '\[Issue #[0-9,]+\]' | grep -oE '[0-9]+' || true)
for issue in $TITLE_ISSUES; do
    RESOLVED_ISSUES+=("$issue")
done

# Extract from PR body: Resolves/Fixes/Closes #N patterns
BODY_RESOLVED=$(echo "$PR_BODY" | grep -oiE '(resolves?|fixes?|closes?)[[:space:]]*#[0-9]+' | grep -oE '[0-9]+' || true)
for issue in $BODY_RESOLVED; do
    # Avoid duplicates
    if [[ ! " ${RESOLVED_ISSUES[*]} " =~ " ${issue} " ]]; then
        RESOLVED_ISSUES+=("$issue")
    fi
done

# Extract related issues: Related: #N, See: #N, Ref: #N patterns
BODY_RELATED=$(echo "$PR_BODY" | grep -oiE '(related|see|ref|depends on)[[:space:]]*:?[[:space:]]*#[0-9]+' | grep -oE '[0-9]+' || true)
for issue in $BODY_RELATED; do
    # Avoid duplicates and don't add if already resolved
    if [[ ! " ${RESOLVED_ISSUES[*]} " =~ " ${issue} " ]] && [[ ! " ${RELATED_ISSUES[*]} " =~ " ${issue} " ]]; then
        RELATED_ISSUES+=("$issue")
    fi
done

# Extract any other #N references not in resolved/related
ALL_REFS=$(echo "$PR_BODY" | grep -oE '#[0-9]+' | grep -oE '[0-9]+' || true)
for issue in $ALL_REFS; do
    if [[ ! " ${RESOLVED_ISSUES[*]} " =~ " ${issue} " ]] && [[ ! " ${RELATED_ISSUES[*]} " =~ " ${issue} " ]]; then
        RELATED_ISSUES+=("$issue")
    fi
done

echo ""
echo "Found references:"
echo "  Resolved: ${RESOLVED_ISSUES[*]:-none}"
echo "  Related: ${RELATED_ISSUES[*]:-none}"

# ========================================
# Process Resolved Issues
# ========================================

ACTIONS_TAKEN=()

for issue in "${RESOLVED_ISSUES[@]}"; do
    echo ""
    echo "Processing resolved issue #$issue..."

    # Verify issue exists
    ISSUE_DATA=$(gh issue view "$issue" --json state,title,url 2>/dev/null || echo "{}")
    if [ -z "$ISSUE_DATA" ] || [ "$ISSUE_DATA" = "{}" ]; then
        echo "  ⚠️  Issue #$issue not found, skipping"
        continue
    fi

    ISSUE_STATE=$(echo "$ISSUE_DATA" | jq -r '.state // ""')
    ISSUE_TITLE=$(echo "$ISSUE_DATA" | jq -r '.title // ""')

    echo "  Title: $ISSUE_TITLE"
    echo "  State: $ISSUE_STATE"

    if [ "$ISSUE_STATE" = "CLOSED" ]; then
        echo "  Issue already closed, skipping"
        continue
    fi

    # Build completion comment
    COMMENT="## ✅ Resolved by PR #$PR_NUMBER

This issue has been resolved by the following pull request:

**PR**: [$PR_TITLE]($PR_URL)
**Merged**: ${PR_MERGED_AT:-pending}
${PR_COMMIT:+**Commit**: \`$PR_COMMIT\`}

---
*Automatically updated by GAAC*"

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY RUN] Would add comment and close issue"
        ACTIONS_TAKEN+=("{\"issue\": $issue, \"action\": \"would_close\", \"pr\": $PR_NUMBER}")
    else
        # Add comment
        gh issue comment "$issue" --body "$COMMENT" 2>/dev/null || {
            echo "  ⚠️  Failed to add comment to #$issue"
            continue
        }

        # Close issue
        gh issue close "$issue" 2>/dev/null || {
            echo "  ⚠️  Failed to close #$issue"
            continue
        }

        echo "  ✓ Issue #$issue closed with comment"
        ACTIONS_TAKEN+=("{\"issue\": $issue, \"action\": \"closed\", \"pr\": $PR_NUMBER}")
    fi
done

# ========================================
# Process Related Issues
# ========================================

for issue in "${RELATED_ISSUES[@]}"; do
    echo ""
    echo "Processing related issue #$issue..."

    # Verify issue exists
    ISSUE_DATA=$(gh issue view "$issue" --json state,title 2>/dev/null || echo "{}")
    if [ -z "$ISSUE_DATA" ] || [ "$ISSUE_DATA" = "{}" ]; then
        echo "  ⚠️  Issue #$issue not found, skipping"
        continue
    fi

    ISSUE_STATE=$(echo "$ISSUE_DATA" | jq -r '.state // ""')
    ISSUE_TITLE=$(echo "$ISSUE_DATA" | jq -r '.title // ""')

    echo "  Title: $ISSUE_TITLE"
    echo "  State: $ISSUE_STATE"

    if [ "$ISSUE_STATE" = "CLOSED" ]; then
        echo "  Issue already closed, skipping"
        continue
    fi

    # Build progress comment
    COMMENT="## 📝 Related PR Merged

A related pull request has been merged:

**PR**: #$PR_NUMBER - $PR_TITLE
${PR_MERGED_AT:+**Merged**: $PR_MERGED_AT}

This may affect or unblock work on this issue.

---
*Automatically updated by GAAC*"

    if [ "$DRY_RUN" = true ]; then
        echo "  [DRY RUN] Would add progress comment"
        ACTIONS_TAKEN+=("{\"issue\": $issue, \"action\": \"would_comment\", \"pr\": $PR_NUMBER}")
    else
        gh issue comment "$issue" --body "$COMMENT" 2>/dev/null || {
            echo "  ⚠️  Failed to add comment to #$issue"
            continue
        }

        echo "  ✓ Progress comment added to #$issue"
        ACTIONS_TAKEN+=("{\"issue\": $issue, \"action\": \"commented\", \"pr\": $PR_NUMBER}")
    fi
done

# ========================================
# Find Dependent Issues
# ========================================

echo ""
echo "Searching for dependent issues..."

for resolved in "${RESOLVED_ISSUES[@]}"; do
    # Search for issues that "Depend on: #N" this resolved issue
    DEPENDENT_ISSUES=$(gh issue list --state open --search "depends on #$resolved" --json number,title 2>/dev/null || echo "[]")

    while read -r dep_issue; do
        [ -z "$dep_issue" ] && continue
        DEP_NUM=$(echo "$dep_issue" | jq -r '.number')
        DEP_TITLE=$(echo "$dep_issue" | jq -r '.title')

        # Skip if already processed
        if [[ " ${RESOLVED_ISSUES[*]} " =~ " ${DEP_NUM} " ]] || [[ " ${RELATED_ISSUES[*]} " =~ " ${DEP_NUM} " ]]; then
            continue
        fi

        echo "  Found dependent: #$DEP_NUM - $DEP_TITLE"

        COMMENT="## 🔓 Dependency Resolved

A dependency of this issue has been resolved:

**Dependency**: #$resolved
**Resolved by**: PR #$PR_NUMBER

This issue may now be unblocked.

---
*Automatically updated by GAAC*"

        if [ "$DRY_RUN" = true ]; then
            echo "    [DRY RUN] Would notify dependency resolved"
            ACTIONS_TAKEN+=("{\"issue\": $DEP_NUM, \"action\": \"would_notify_unblocked\", \"dependency\": $resolved}")
        else
            gh issue comment "$DEP_NUM" --body "$COMMENT" 2>/dev/null || {
                echo "    ⚠️  Failed to notify #$DEP_NUM"
                continue
            }
            echo "    ✓ Notified #$DEP_NUM about unblocked dependency"
            ACTIONS_TAKEN+=("{\"issue\": $DEP_NUM, \"action\": \"notified_unblocked\", \"dependency\": $resolved}")
        fi
    done < <(echo "$DEPENDENT_ISSUES" | jq -c '.[]' 2>/dev/null || true)
done

# ========================================
# Summary
# ========================================

echo ""
echo "=== Summary ==="
echo "PR: #$PR_NUMBER"
echo "Resolved issues: ${#RESOLVED_ISSUES[@]}"
echo "Related issues: ${#RELATED_ISSUES[@]}"
echo "Actions taken: ${#ACTIONS_TAKEN[@]}"

# Output JSON for programmatic use
echo ""
echo "JSON_OUTPUT:"
jq -n \
    --arg pr "$PR_NUMBER" \
    --arg title "$PR_TITLE" \
    --argjson resolved "$(printf '%s\n' "${RESOLVED_ISSUES[@]:-}" | jq -R . | jq -s .)" \
    --argjson related "$(printf '%s\n' "${RELATED_ISSUES[@]:-}" | jq -R . | jq -s .)" \
    --argjson actions "[$(IFS=,; echo "${ACTIONS_TAKEN[*]:-}")]" \
    '{
        pr_number: $pr,
        pr_title: $title,
        resolved_issues: $resolved,
        related_issues: $related,
        actions: $actions
    }'
