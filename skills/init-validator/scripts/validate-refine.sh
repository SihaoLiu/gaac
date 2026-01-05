#!/bin/bash
#
# Validate /refine-spec-to-arch arguments
# Input 1: path to draft-*.md file
# Input 2: issue number (optional, can be inferred)
#

set -euo pipefail

DRAFT_FILE="${1:-}"
ISSUE_NUMBER="${2:-}"

if [ -z "$DRAFT_FILE" ]; then
    echo "❌ Error: No draft file provided"
    echo ""
    echo "Usage: /refine-spec-to-arch <draft-file.md> [issue-number]"
    echo ""
    echo "Examples:"
    echo "  /refine-spec-to-arch ./docs/draft/draft-memory-addressing.md"
    echo "  /refine-spec-to-arch ./docs/draft/draft-memory-addressing.md 42"
    exit 1
fi

# Check file exists
if [ ! -f "$DRAFT_FILE" ]; then
    echo "❌ Error: Draft file not found: $DRAFT_FILE"
    exit 1
fi

# Check file is readable
if [ ! -r "$DRAFT_FILE" ]; then
    echo "❌ Error: Draft file is not readable: $DRAFT_FILE"
    exit 1
fi

# Check filename pattern
BASENAME=$(basename "$DRAFT_FILE")
if [[ ! "$BASENAME" =~ ^draft-.+\.md$ ]]; then
    echo "⚠️  Warning: File name doesn't follow draft-*.md pattern"
    echo "   Expected: draft-<topic>.md"
    echo "   Got: $BASENAME"
fi

echo "✓ Draft file exists: $DRAFT_FILE"

# Check file size
LINE_COUNT=$(wc -l < "$DRAFT_FILE")
if [ "$LINE_COUNT" -lt 10 ]; then
    echo "⚠️  Warning: Draft file is very short ($LINE_COUNT lines)"
    echo "   Consider adding more detail before refinement."
elif [ "$LINE_COUNT" -gt 1500 ]; then
    echo "⚠️  Warning: Draft file is very long ($LINE_COUNT lines)"
    echo "   Architecture documents may need to be split."
fi
echo "✓ Draft file has $LINE_COUNT lines"

# Validate issue number if provided
if [ -n "$ISSUE_NUMBER" ]; then
    if ! [[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
        echo "❌ Error: Issue number must be a positive integer: $ISSUE_NUMBER"
        exit 1
    fi

    # Check issue exists
    if gh issue view "$ISSUE_NUMBER" --json number &>/dev/null; then
        ISSUE_STATE=$(gh issue view "$ISSUE_NUMBER" --json state --jq '.state')
        echo "✓ Issue #$ISSUE_NUMBER exists (state: $ISSUE_STATE)"

        if [ "$ISSUE_STATE" = "CLOSED" ]; then
            echo "⚠️  Warning: Issue #$ISSUE_NUMBER is closed"
        fi
    else
        echo "❌ Error: Issue #$ISSUE_NUMBER not found or inaccessible"
        exit 1
    fi
else
    echo "ℹ️  No issue number provided. Will create a new issue during workflow."
fi

echo ""
echo "✅ Validation passed"
exit 0
