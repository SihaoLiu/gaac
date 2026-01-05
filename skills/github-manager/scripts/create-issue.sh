#!/bin/bash
#
# Create GitHub Issue with GAAC format
# Supports SWE-bench style templates
#

set -euo pipefail

# Parse arguments
TITLE=""
BODY_FILE=""
BODY_TEXT=""
LABELS=""
ASSIGNEE="@me"

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
        --labels)
            LABELS="$2"
            shift 2
            ;;
        --assignee)
            ASSIGNEE="$2"
            shift 2
            ;;
        --no-assignee)
            ASSIGNEE=""
            shift
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
    BODY="## Problem Statement
[To be filled]

## Expected Behavior
[To be filled]

## Acceptance Criteria
- [ ] TBD

## Test Plan
\`\`\`
[Test commands]
\`\`\`
"
fi

# Build gh issue create command
CMD="gh issue create --title"
CMD="$CMD \"$TITLE\""
CMD="$CMD --body \"\$BODY\""

if [ -n "$LABELS" ]; then
    # Convert comma-separated labels to multiple --label flags
    IFS=',' read -ra LABEL_ARRAY <<< "$LABELS"
    for label in "${LABEL_ARRAY[@]}"; do
        CMD="$CMD --label \"$label\""
    done
fi

if [ -n "$ASSIGNEE" ]; then
    CMD="$CMD --assignee $ASSIGNEE"
fi

# Create the issue
echo "Creating issue: $TITLE"
ISSUE_URL=$(gh issue create --title "$TITLE" --body "$BODY" ${LABELS:+--label "$LABELS"} ${ASSIGNEE:+--assignee "$ASSIGNEE"})

if [ -n "$ISSUE_URL" ]; then
    # Extract issue number from URL
    ISSUE_NUMBER=$(echo "$ISSUE_URL" | grep -oE '[0-9]+$')
    echo "✓ Issue created: #$ISSUE_NUMBER"
    echo "  URL: $ISSUE_URL"

    # Output JSON for programmatic use
    echo ""
    echo "JSON_OUTPUT:"
    jq -n --arg number "$ISSUE_NUMBER" --arg url "$ISSUE_URL" --arg title "$TITLE" \
        '{issue_number: $number, url: $url, title: $title}'
else
    echo "❌ Failed to create issue" >&2
    exit 1
fi
