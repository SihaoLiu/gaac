#!/bin/bash
#
# Create git commit with GAAC format
# Follows project conventions and adds proper metadata
#

set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
GAAC_CONFIG="$PROJECT_ROOT/.claude/rules/gaac.md"

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

# Try to infer L1/L2 tags from changed files if gaac.md exists
L1_TAG=""
L2_TAG=""

if [ -f "$GAAC_CONFIG" ]; then
    # Simple inference based on common patterns
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

# Add issue reference if provided
if [ -n "$ISSUE" ]; then
    COMMIT_MSG="$COMMIT_MSG[#$ISSUE]"
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

# Output JSON for programmatic use
echo ""
echo "JSON_OUTPUT:"
jq -n \
    --arg hash "$COMMIT_HASH" \
    --arg short "$SHORT_HASH" \
    --arg message "$COMMIT_MSG" \
    --arg issue "${ISSUE:-null}" \
    '{commit_hash: $hash, short_hash: $short, message: $message, issue: $issue}'
