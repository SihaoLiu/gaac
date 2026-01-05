#!/bin/bash
#
# Fetch PR comments for resolution
# Categorizes by priority and provides structured output
#

set -euo pipefail

# Parse arguments
PR_NUMBER=""
OUTPUT_FORMAT="text"  # or "json"

while [[ $# -gt 0 ]]; do
    case $1 in
        --pr-number)
            PR_NUMBER="$2"
            shift 2
            ;;
        --format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        *)
            if [ -z "$PR_NUMBER" ]; then
                PR_NUMBER="$1"
            fi
            shift
            ;;
    esac
done

# Auto-detect PR number if not provided
if [ -z "$PR_NUMBER" ]; then
    CURRENT_BRANCH=$(git branch --show-current)
    PR_INFO=$(gh pr list --head "$CURRENT_BRANCH" --json number --jq '.[0].number' 2>/dev/null || echo "")
    if [ -n "$PR_INFO" ]; then
        PR_NUMBER="$PR_INFO"
        echo "Auto-detected PR: #$PR_NUMBER" >&2
    else
        echo "❌ Error: No PR number provided and couldn't auto-detect" >&2
        exit 1
    fi
fi

# Fetch PR review comments (code review comments)
REVIEW_COMMENTS=$(gh api "repos/{owner}/{repo}/pulls/$PR_NUMBER/comments" 2>/dev/null || echo "[]")

# Fetch PR issue comments (general discussion)
ISSUE_COMMENTS=$(gh api "repos/{owner}/{repo}/issues/$PR_NUMBER/comments" 2>/dev/null || echo "[]")

# Fetch PR reviews
REVIEWS=$(gh api "repos/{owner}/{repo}/pulls/$PR_NUMBER/reviews" 2>/dev/null || echo "[]")

# Process and categorize comments
BLOCKING=()
HIGH=()
MEDIUM=()
LOW=()

# Function to categorize comment
categorize_comment() {
    local body="$1"
    local author="$2"
    local type="$3"
    local id="$4"

    # Check for blocking indicators
    if echo "$body" | grep -qiE "block|must|required|critical|security|vulnerability"; then
        echo "BLOCKING"
    elif echo "$body" | grep -qiE "bug|error|incorrect|wrong|fix|issue"; then
        echo "HIGH"
    elif echo "$body" | grep -qiE "should|consider|suggest|improve|better"; then
        echo "MEDIUM"
    else
        echo "LOW"
    fi
}

# Process review comments (inline code comments)
if [ "$REVIEW_COMMENTS" != "[]" ]; then
    while IFS= read -r comment; do
        BODY=$(echo "$comment" | jq -r '.body')
        AUTHOR=$(echo "$comment" | jq -r '.user.login')
        ID=$(echo "$comment" | jq -r '.id')
        PATH=$(echo "$comment" | jq -r '.path')
        LINE=$(echo "$comment" | jq -r '.line // .original_line // "N/A"')

        PRIORITY=$(categorize_comment "$BODY" "$AUTHOR" "review" "$ID")

        COMMENT_OBJ=$(jq -n \
            --arg id "$ID" \
            --arg author "$AUTHOR" \
            --arg body "$BODY" \
            --arg path "$PATH" \
            --arg line "$LINE" \
            --arg type "review" \
            --arg priority "$PRIORITY" \
            '{id: $id, author: $author, body: $body, path: $path, line: $line, type: $type, priority: $priority}')

        case "$PRIORITY" in
            BLOCKING) BLOCKING+=("$COMMENT_OBJ") ;;
            HIGH) HIGH+=("$COMMENT_OBJ") ;;
            MEDIUM) MEDIUM+=("$COMMENT_OBJ") ;;
            LOW) LOW+=("$COMMENT_OBJ") ;;
        esac
    done < <(echo "$REVIEW_COMMENTS" | jq -c '.[]')
fi

# Process reviews with body text
if [ "$REVIEWS" != "[]" ]; then
    while IFS= read -r review; do
        STATE=$(echo "$review" | jq -r '.state')
        BODY=$(echo "$review" | jq -r '.body // ""')
        AUTHOR=$(echo "$review" | jq -r '.user.login')
        ID=$(echo "$review" | jq -r '.id')

        # Skip empty reviews
        if [ -z "$BODY" ] || [ "$BODY" = "null" ]; then
            continue
        fi

        # Changes requested is always high priority
        if [ "$STATE" = "CHANGES_REQUESTED" ]; then
            PRIORITY="BLOCKING"
        else
            PRIORITY=$(categorize_comment "$BODY" "$AUTHOR" "review_body" "$ID")
        fi

        COMMENT_OBJ=$(jq -n \
            --arg id "$ID" \
            --arg author "$AUTHOR" \
            --arg body "$BODY" \
            --arg state "$STATE" \
            --arg type "review_body" \
            --arg priority "$PRIORITY" \
            '{id: $id, author: $author, body: $body, state: $state, type: $type, priority: $priority}')

        case "$PRIORITY" in
            BLOCKING) BLOCKING+=("$COMMENT_OBJ") ;;
            HIGH) HIGH+=("$COMMENT_OBJ") ;;
            MEDIUM) MEDIUM+=("$COMMENT_OBJ") ;;
            LOW) LOW+=("$COMMENT_OBJ") ;;
        esac
    done < <(echo "$REVIEWS" | jq -c '.[]')
fi

# Output based on format
if [ "$OUTPUT_FORMAT" = "json" ]; then
    # Build JSON output
    ALL_BLOCKING=$(printf '%s\n' "${BLOCKING[@]}" 2>/dev/null | jq -s '.' || echo "[]")
    ALL_HIGH=$(printf '%s\n' "${HIGH[@]}" 2>/dev/null | jq -s '.' || echo "[]")
    ALL_MEDIUM=$(printf '%s\n' "${MEDIUM[@]}" 2>/dev/null | jq -s '.' || echo "[]")
    ALL_LOW=$(printf '%s\n' "${LOW[@]}" 2>/dev/null | jq -s '.' || echo "[]")

    jq -n \
        --arg pr "$PR_NUMBER" \
        --argjson blocking "$ALL_BLOCKING" \
        --argjson high "$ALL_HIGH" \
        --argjson medium "$ALL_MEDIUM" \
        --argjson low "$ALL_LOW" \
        '{
            pr_number: $pr,
            total: (($blocking | length) + ($high | length) + ($medium | length) + ($low | length)),
            blocking: $blocking,
            high: $high,
            medium: $medium,
            low: $low
        }'
else
    # Text output
    TOTAL=$((${#BLOCKING[@]} + ${#HIGH[@]} + ${#MEDIUM[@]} + ${#LOW[@]}))
    echo "=== PR #$PR_NUMBER Comments ($TOTAL total) ==="
    echo ""

    if [ ${#BLOCKING[@]} -gt 0 ]; then
        echo "### BLOCKING (${#BLOCKING[@]}) ###"
        for c in "${BLOCKING[@]}"; do
            AUTHOR=$(echo "$c" | jq -r '.author')
            BODY=$(echo "$c" | jq -r '.body' | head -3)
            PATH=$(echo "$c" | jq -r '.path // ""')
            echo "- @$AUTHOR${PATH:+ in $PATH}"
            echo "  $BODY"
            echo ""
        done
    fi

    if [ ${#HIGH[@]} -gt 0 ]; then
        echo "### HIGH (${#HIGH[@]}) ###"
        for c in "${HIGH[@]}"; do
            AUTHOR=$(echo "$c" | jq -r '.author')
            BODY=$(echo "$c" | jq -r '.body' | head -3)
            PATH=$(echo "$c" | jq -r '.path // ""')
            echo "- @$AUTHOR${PATH:+ in $PATH}"
            echo "  $BODY"
            echo ""
        done
    fi

    if [ ${#MEDIUM[@]} -gt 0 ]; then
        echo "### MEDIUM (${#MEDIUM[@]}) ###"
        for c in "${MEDIUM[@]}"; do
            AUTHOR=$(echo "$c" | jq -r '.author')
            BODY=$(echo "$c" | jq -r '.body' | head -2)
            echo "- @$AUTHOR: $BODY"
        done
        echo ""
    fi

    if [ ${#LOW[@]} -gt 0 ]; then
        echo "### LOW (${#LOW[@]}) ###"
        for c in "${LOW[@]}"; do
            AUTHOR=$(echo "$c" | jq -r '.author')
            BODY=$(echo "$c" | jq -r '.body' | head -1)
            echo "- @$AUTHOR: $(echo "$BODY" | cut -c1-80)..."
        done
    fi

    if [ $TOTAL -eq 0 ]; then
        echo "No comments to resolve."
    fi
fi
