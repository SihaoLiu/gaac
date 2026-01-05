#!/bin/bash
#
# Validate /work-on-issue arguments
# Input: issue number
#

set -euo pipefail

ISSUE_NUMBER="${1:-}"

if [ -z "$ISSUE_NUMBER" ]; then
    echo "❌ Error: No issue number provided"
    echo ""
    echo "Usage: /work-on-issue <issue-number>"
    echo ""
    echo "Examples:"
    echo "  /work-on-issue 42"
    echo "  /work-on-issue 123"
    exit 1
fi

# Validate issue number format
if ! [[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "❌ Error: Issue number must be a positive integer"
    echo "   Got: $ISSUE_NUMBER"
    exit 1
fi

if [ "$ISSUE_NUMBER" -le 0 ]; then
    echo "❌ Error: Issue number must be greater than 0"
    exit 1
fi

# Check issue exists and get details
echo "Checking issue #$ISSUE_NUMBER..."

ISSUE_JSON=$(gh issue view "$ISSUE_NUMBER" --json number,state,title,labels,body 2>/dev/null || echo "")

if [ -z "$ISSUE_JSON" ]; then
    echo "❌ Error: Issue #$ISSUE_NUMBER not found or inaccessible"
    echo ""
    echo "Possible causes:"
    echo "  - Issue doesn't exist"
    echo "  - Repository is private and gh is not authenticated"
    echo "  - Network connectivity issue"
    echo ""
    echo "Try: gh issue view $ISSUE_NUMBER"
    exit 1
fi

# Parse issue details
ISSUE_STATE=$(echo "$ISSUE_JSON" | jq -r '.state')
ISSUE_TITLE=$(echo "$ISSUE_JSON" | jq -r '.title')
ISSUE_LABELS=$(echo "$ISSUE_JSON" | jq -r '.labels[].name' 2>/dev/null | tr '\n' ', ' | sed 's/,$//')

echo "✓ Issue #$ISSUE_NUMBER found"
echo "  Title: $ISSUE_TITLE"
echo "  State: $ISSUE_STATE"
if [ -n "$ISSUE_LABELS" ]; then
    echo "  Labels: $ISSUE_LABELS"
fi

# Check if issue is closed
if [ "$ISSUE_STATE" = "CLOSED" ]; then
    echo ""
    echo "⚠️  Warning: Issue #$ISSUE_NUMBER is CLOSED"
    echo "   Continue anyway? The workflow will proceed, but consider reopening the issue."
    exit 2  # Exit code 2 = warning, ask for confirmation
fi

# Check for blocking dependencies
ISSUE_BODY=$(echo "$ISSUE_JSON" | jq -r '.body // ""')

# Look for dependency patterns
BLOCKED_BY=""
if echo "$ISSUE_BODY" | grep -qiE "blocked by #|depends on #|requires #|after #"; then
    BLOCKED_BY=$(echo "$ISSUE_BODY" | grep -oE "#[0-9]+" | sort -u | tr '\n' ' ')
fi

if [ -n "$BLOCKED_BY" ]; then
    echo ""
    echo "⚠️  Warning: Issue may have dependencies: $BLOCKED_BY"
    echo "   Verify these issues are resolved before proceeding."
fi

# Check current branch
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")

if [ -n "$CURRENT_BRANCH" ]; then
    echo ""
    echo "Current branch: $CURRENT_BRANCH"

    # Check if branch contains issue number
    if [[ "$CURRENT_BRANCH" == *"$ISSUE_NUMBER"* ]] || [[ "$CURRENT_BRANCH" == *"issue-$ISSUE_NUMBER"* ]]; then
        echo "✓ Branch name includes issue number"
    else
        echo "ℹ️  Tip: Consider using a branch name like 'issue-$ISSUE_NUMBER-description'"
    fi
fi

# Check for uncommitted changes
if ! git diff --quiet 2>/dev/null; then
    echo ""
    echo "⚠️  Warning: Uncommitted changes detected"
    echo "   Consider committing or stashing before starting work."
fi

echo ""
echo "✅ Validation passed"
exit 0
