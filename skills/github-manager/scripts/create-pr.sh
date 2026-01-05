#!/bin/bash
#
# Create GitHub Pull Request with GAAC format
#

set -euo pipefail

# Parse arguments
TITLE=""
BODY_FILE=""
BODY_TEXT=""
RESOLVES=""
DRAFT=false
BASE_BRANCH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --title)
            TITLE="$2"
            shift 2
            ;;
        --body-file)
            BODY_FILE="$2"
            shift 2
            ;;
        --body)
            BODY_TEXT="$2"
            shift 2
            ;;
        --resolves)
            RESOLVES="$2"
            shift 2
            ;;
        --draft)
            DRAFT=true
            shift
            ;;
        --base)
            BASE_BRANCH="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$TITLE" ]; then
    echo "❌ Error: --title is required" >&2
    exit 1
fi

# Get body content
BODY=""
if [ -n "$BODY_FILE" ] && [ -f "$BODY_FILE" ]; then
    BODY=$(cat "$BODY_FILE")
elif [ -n "$BODY_TEXT" ]; then
    BODY="$BODY_TEXT"
else
    # Use default template
    BODY="## Summary
- [Change summary]

## Changes
- [List of changes]

## Test Plan
- [ ] Tests pass
- [ ] Manual testing completed

## Checklist
- [ ] Code follows project conventions
- [ ] Documentation updated if needed
"
fi

# Append resolves clause if provided
if [ -n "$RESOLVES" ]; then
    # Handle multiple issue numbers
    RESOLVES_CLAUSE=""
    IFS=',' read -ra ISSUE_ARRAY <<< "$RESOLVES"
    for issue in "${ISSUE_ARRAY[@]}"; do
        issue=$(echo "$issue" | tr -d ' ')
        if [ -n "$RESOLVES_CLAUSE" ]; then
            RESOLVES_CLAUSE="$RESOLVES_CLAUSE, resolves #$issue"
        else
            RESOLVES_CLAUSE="Resolves #$issue"
        fi
    done
    BODY="$BODY

$RESOLVES_CLAUSE"
fi

# Check if we need to push first
CURRENT_BRANCH=$(git branch --show-current)
UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "")

if [ -z "$UPSTREAM" ]; then
    echo "Pushing branch to remote..."
    git push -u origin "$CURRENT_BRANCH"
fi

# Check if PR already exists
EXISTING_PR=$(gh pr list --head "$CURRENT_BRANCH" --json number,url --jq '.[0]' 2>/dev/null || echo "")

if [ -n "$EXISTING_PR" ] && [ "$EXISTING_PR" != "null" ]; then
    PR_NUMBER=$(echo "$EXISTING_PR" | jq -r '.number')
    PR_URL=$(echo "$EXISTING_PR" | jq -r '.url')
    echo "ℹ️  PR already exists: #$PR_NUMBER"
    echo "   URL: $PR_URL"
    echo ""
    echo "Updating PR..."
    gh pr edit "$PR_NUMBER" --title "$TITLE" --body "$BODY"
    echo "✓ PR updated"

    echo ""
    echo "JSON_OUTPUT:"
    jq -n --arg number "$PR_NUMBER" --arg url "$PR_URL" --arg title "$TITLE" \
        '{pr_number: $number, url: $url, title: $title, action: "updated"}'
    exit 0
fi

# Build create command
PR_CMD="gh pr create"
PR_CMD="$PR_CMD --title \"$TITLE\""
PR_CMD="$PR_CMD --body \"\$BODY\""
PR_CMD="$PR_CMD --assignee @me"

if [ "$DRAFT" = true ]; then
    PR_CMD="$PR_CMD --draft"
fi

if [ -n "$BASE_BRANCH" ]; then
    PR_CMD="$PR_CMD --base \"$BASE_BRANCH\""
fi

# Create the PR
echo "Creating PR: $TITLE"
PR_URL=$(gh pr create --title "$TITLE" --body "$BODY" --assignee "@me" ${DRAFT:+--draft} ${BASE_BRANCH:+--base "$BASE_BRANCH"})

if [ -n "$PR_URL" ]; then
    PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$')
    echo "✓ PR created: #$PR_NUMBER"
    echo "  URL: $PR_URL"

    echo ""
    echo "JSON_OUTPUT:"
    jq -n --arg number "$PR_NUMBER" --arg url "$PR_URL" --arg title "$TITLE" \
        '{pr_number: $number, url: $url, title: $title, action: "created"}'
else
    echo "❌ Failed to create PR" >&2
    exit 1
fi
