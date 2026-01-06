#!/bin/bash
#
# Create git commit with GAAC format
# Follows project conventions and adds proper metadata
# Uses gaac-config.sh for tag inference and auto-appends new mappings
#

set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
GAAC_CONFIG="$PROJECT_ROOT/.claude/rules/gaac.md"

# Find config helper
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HELPER="${SCRIPT_DIR}/../../../scripts/gaac-config.sh"

# Parse arguments
ISSUE=""
MESSAGE=""
FILES=""
ALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --issue|-i)
            ISSUE="$2"
            shift 2
            ;;
        --message|-m)
            MESSAGE="$2"
            shift 2
            ;;
        --files|-f)
            FILES="$2"
            shift 2
            ;;
        --all|-a)
            ALL=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Validate message
if [ -z "$MESSAGE" ]; then
    echo "❌ Error: --message is required" >&2
    echo "Usage: create-commit.sh --message 'Commit message' [--issue 42] [--all]" >&2
    exit 1
fi

# Check for changes to commit
if [ "$ALL" = true ]; then
    git add -A
elif [ -n "$FILES" ]; then
    git add $FILES
fi

# Check if there are staged changes
if git diff --cached --quiet; then
    echo "⚠️  No staged changes to commit" >&2
    echo "   Use --all to stage all changes, or stage files manually first" >&2
    exit 1
fi

# Get changed files for L1/L2 inference
CHANGED_FILES=$(git diff --cached --name-only)

# Try to infer L1 tag from changed files using gaac-config.sh
L1_TAG=""
L2_TAG=""
INFERRED_FROM=""
NEW_MAPPING_NEEDED=false

if [ -f "$GAAC_CONFIG" ] && [ -f "$CONFIG_HELPER" ]; then
    # Get the first changed file to infer tag
    FIRST_FILE=$(echo "$CHANGED_FILES" | head -1)
    if [ -n "$FIRST_FILE" ]; then
        INFERRED=$(bash "$CONFIG_HELPER" infer-tag "$FIRST_FILE" 2>/dev/null || echo "")
        if [ -n "$INFERRED" ]; then
            # Extract tag name from [Tag] format
            L1_TAG=$(echo "$INFERRED" | tr -d '[]')
            INFERRED_FROM="$FIRST_FILE"

            # Check if this was from file mappings or heuristics
            MAPPINGS=$(bash "$CONFIG_HELPER" get-file-mappings 2>/dev/null || echo "")
            if [ -z "$MAPPINGS" ] || ! echo "$MAPPINGS" | grep -q "$L1_TAG"; then
                # Heuristic inference - consider auto-appending
                # Get the base directory of the first file for the pattern
                BASE_DIR=$(dirname "$FIRST_FILE" | cut -d'/' -f1-2)
                if [ -n "$BASE_DIR" ] && [ "$BASE_DIR" != "." ]; then
                    NEW_MAPPING_NEEDED=true
                    NEW_PATTERN="${BASE_DIR}/**"
                fi
            fi
        fi
    fi
else
    # Fallback: Simple inference if config helper not available
    if echo "$CHANGED_FILES" | grep -qE "^docs/"; then
        L1_TAG="Docs"
    elif echo "$CHANGED_FILES" | grep -qE "^tests?/"; then
        L1_TAG="Tests"
    elif echo "$CHANGED_FILES" | grep -qE "^src/api/|^api/"; then
        L1_TAG="API"
    elif echo "$CHANGED_FILES" | grep -qE "^src/ui/|^ui/|^frontend/"; then
        L1_TAG="UI"
    elif echo "$CHANGED_FILES" | grep -qE "^src/core/|^core/|^lib/"; then
        L1_TAG="Core"
    elif echo "$CHANGED_FILES" | grep -qE "^\.github/|^\.claude/|^config/"; then
        L1_TAG="Infra"
    fi
fi

# Build commit message
COMMIT_MSG=""

# Add tags if available
if [ -n "$L1_TAG" ]; then
    COMMIT_MSG="[$L1_TAG]"
    if [ -n "$L2_TAG" ]; then
        COMMIT_MSG="$COMMIT_MSG[$L2_TAG]"
    fi
fi

# Add issue reference if provided (use [Issue #N] format per GAAC standard)
if [ -n "$ISSUE" ]; then
    COMMIT_MSG="$COMMIT_MSG[Issue #$ISSUE]"
fi

# Add message
if [ -n "$COMMIT_MSG" ]; then
    COMMIT_MSG="$COMMIT_MSG $MESSAGE"
else
    COMMIT_MSG="$MESSAGE"
fi

# Show what will be committed
echo "=== Commit Preview ==="
echo ""
echo "Message: $COMMIT_MSG"
echo ""
echo "Files:"
echo "$CHANGED_FILES" | sed 's/^/  /'
echo ""

# Get diff stats
STATS=$(git diff --cached --stat | tail -1)
echo "Stats: $STATS"
echo ""

# Create the commit
git commit -m "$COMMIT_MSG"

COMMIT_HASH=$(git rev-parse HEAD)
SHORT_HASH=$(git rev-parse --short HEAD)

echo ""
echo "✓ Commit created: $SHORT_HASH"
echo "  Full hash: $COMMIT_HASH"

# Auto-append new file mapping if needed
if [ "$NEW_MAPPING_NEEDED" = true ] && [ -n "${NEW_PATTERN:-}" ] && [ -n "$L1_TAG" ]; then
    echo ""
    echo "Auto-appending file mapping: ${NEW_PATTERN}:[$L1_TAG]"
    bash "$CONFIG_HELPER" append-file-mapping "$NEW_PATTERN" "[$L1_TAG]" 2>/dev/null || true
fi

# Output JSON for programmatic use
echo ""
echo "JSON_OUTPUT:"
jq -n \
    --arg hash "$COMMIT_HASH" \
    --arg short "$SHORT_HASH" \
    --arg message "$COMMIT_MSG" \
    --arg issue "${ISSUE:-null}" \
    --arg inferred_tag "${L1_TAG:-null}" \
    --arg mapping_added "${NEW_MAPPING_NEEDED}" \
    '{commit_hash: $hash, short_hash: $short, message: $message, issue: $issue, inferred_tag: $inferred_tag, mapping_added: ($mapping_added == "true")}'
