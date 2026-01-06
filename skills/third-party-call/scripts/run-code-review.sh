#!/bin/bash
#
# Run Independent Code Review
#
# Uses external model (codex preferred, claude fallback) to perform
# an independent scoring review of code changes.
#
# Usage:
#   run-code-review.sh --issue-number <N> [--output-file <path>]
#

set -euo pipefail

# Parse arguments
ISSUE_NUMBER=""
OUTPUT_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --issue-number|-i)
            ISSUE_NUMBER="$2"
            shift 2
            ;;
        --output-file|-o)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [ -z "$ISSUE_NUMBER" ]; then
    echo "Usage: run-code-review.sh --issue-number <N> [--output-file <path>]" >&2
    exit 1
fi

# Setup paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT_FILE="$SCRIPT_DIR/../prompts/CODE_REVIEWER_PROMPT.md"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
CONFIG_HELPER="$SCRIPT_DIR/../../../scripts/gaac-config.sh"

# Default output file
if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="$PROJECT_ROOT/.claude/code-review-$ISSUE_NUMBER.md"
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

# ========================================
# Get Code Changes
# ========================================

echo "Gathering code changes for issue #$ISSUE_NUMBER..."

# Get default branch
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main")

# Generate diff
DIFF=$(git diff "origin/$DEFAULT_BRANCH"...HEAD 2>/dev/null || git diff HEAD~1 2>/dev/null || echo "")

if [ -z "$DIFF" ]; then
    echo "No changes to review"
    echo "PASS" > "$OUTPUT_FILE"
    exit 0
fi

# Get changed files
CHANGED_FILES=$(git diff --name-only "origin/$DEFAULT_BRANCH"...HEAD 2>/dev/null || git diff --name-only HEAD~1 2>/dev/null || echo "")

# Get issue context
ISSUE_TITLE=$(gh issue view "$ISSUE_NUMBER" --json title --jq '.title' 2>/dev/null || echo "Issue #$ISSUE_NUMBER")

echo "  Issue: $ISSUE_TITLE"
echo "  Changed files: $(echo "$CHANGED_FILES" | wc -l)"

# ========================================
# Build Review Input
# ========================================

REVIEW_INPUT="# Code Review Request

## Context
- **Issue**: #$ISSUE_NUMBER - $ISSUE_TITLE
- **Branch**: $(git branch --show-current)
- **Files Changed**: $(echo "$CHANGED_FILES" | wc -l)

## Changed Files
\`\`\`
$CHANGED_FILES
\`\`\`

## Diff
\`\`\`diff
$DIFF
\`\`\`

---

$(cat "$PROMPT_FILE")
"

# Write input to temp file
TEMP_INPUT=$(mktemp)
echo "$REVIEW_INPUT" > "$TEMP_INPUT"

# Temp file for review output
TEMP_OUTPUT=$(mktemp)

# Temp file for capturing run-analysis.sh stdout (contains tool info)
TEMP_STDOUT=$(mktemp)

# ========================================
# Run External Review via run-analysis.sh
# ========================================

echo "Running code review..."

# Use run-analysis.sh with code_reviewer role for consistent tool invocation
RUN_ANALYSIS="$SCRIPT_DIR/run-analysis.sh"

if [ ! -f "$RUN_ANALYSIS" ]; then
    echo "❌ Error: run-analysis.sh not found at $RUN_ANALYSIS" >&2
    rm -f "$TEMP_INPUT" "$TEMP_OUTPUT" "$TEMP_STDOUT"
    exit 1
fi

# Initialize
REVIEW_OUTPUT=""
TOOL_USED="unknown"

# Run analysis with code_reviewer role (handles codex → claude fallback)
# Capture stdout to TEMP_STDOUT for parsing tool info
if bash "$RUN_ANALYSIS" \
    --role code_reviewer \
    --prompt-file "$TEMP_INPUT" \
    --output-file "$TEMP_OUTPUT" > "$TEMP_STDOUT" 2>&1; then

    if [ -f "$TEMP_OUTPUT" ] && [ -s "$TEMP_OUTPUT" ]; then
        REVIEW_OUTPUT=$(cat "$TEMP_OUTPUT")
    fi
fi

# Extract tool used from run-analysis.sh stdout
# run-analysis.sh outputs "Tool: codex/claude/gemini" and JSON_OUTPUT with tool field
if [ -f "$TEMP_STDOUT" ] && [ -s "$TEMP_STDOUT" ]; then
    # Try JSON_OUTPUT first (more reliable)
    TOOL_USED=$(grep -o '"tool":[[:space:]]*"[^"]*"' "$TEMP_STDOUT" | head -1 | grep -oE '"[^"]*"$' | tr -d '"' || true)

    # Fallback to "Tool: xxx" line
    if [ -z "$TOOL_USED" ]; then
        TOOL_USED=$(grep -oE '^Tool:[[:space:]]*[a-z]+' "$TEMP_STDOUT" | head -1 | awk '{print $2}' || echo "unknown")
    fi
fi

rm -f "$TEMP_INPUT" "$TEMP_OUTPUT" "$TEMP_STDOUT"

# ========================================
# Process Review Output
# ========================================

if [ -z "$REVIEW_OUTPUT" ]; then
    echo "❌ Error: Code review failed - external analysis returned no output" >&2
    exit 1
fi

echo "  Review completed"

# Extract score and assessment
REVIEW_SCORE=$(echo "$REVIEW_OUTPUT" | grep -oE 'Total:.*\[([0-9]+)/100\]' | grep -oE '[0-9]+' | head -1 || echo "")
REVIEW_ASSESSMENT=$(echo "$REVIEW_OUTPUT" | grep -oE 'Assessment:.*' | sed 's/Assessment:[[:space:]]*//' | head -1 || echo "")

# Fallback parsing if structured format not found
if [ -z "$REVIEW_SCORE" ]; then
    REVIEW_SCORE=$(echo "$REVIEW_OUTPUT" | grep -oiE '\[([0-9]+)/100\]' | grep -oE '[0-9]+' | head -1 || echo "0")
fi

if [ -z "$REVIEW_ASSESSMENT" ]; then
    # Infer assessment from score
    if [ -n "$REVIEW_SCORE" ]; then
        if [ "$REVIEW_SCORE" -ge 90 ]; then
            REVIEW_ASSESSMENT="Approve"
        elif [ "$REVIEW_SCORE" -ge 81 ]; then
            REVIEW_ASSESSMENT="Approve with Minor Suggestion"
        elif [ "$REVIEW_SCORE" -ge 70 ]; then
            REVIEW_ASSESSMENT="Major changes needed"
        else
            REVIEW_ASSESSMENT="Reject"
        fi
    fi
fi

# ========================================
# Write Output
# ========================================

{
    echo "# Code Review Results"
    echo ""
    echo "**Issue**: #$ISSUE_NUMBER - $ISSUE_TITLE"
    echo "**Reviewer**: $TOOL_USED"
    echo "**Date**: $(date -Iseconds)"
    echo ""
    echo "---"
    echo ""
    echo "$REVIEW_OUTPUT"
    echo ""
    echo "---"
    echo ""
    echo "## Structured Markers"
    echo ""
    echo "<!-- GAAC_REVIEW_SCORE: ${REVIEW_SCORE:-0} -->"
    echo "<!-- GAAC_REVIEW_ASSESSMENT: ${REVIEW_ASSESSMENT:-Unknown} -->"
} > "$OUTPUT_FILE"

echo ""
echo "=== Code Review Summary ==="
echo "Score: ${REVIEW_SCORE:-unknown}/100"
echo "Assessment: ${REVIEW_ASSESSMENT:-unknown}"
echo "Output: $OUTPUT_FILE"
echo ""

# Output structured markers to stdout for stop hook detection
echo "<!-- GAAC_REVIEW_SCORE: ${REVIEW_SCORE:-0} -->"
echo "<!-- GAAC_REVIEW_ASSESSMENT: ${REVIEW_ASSESSMENT:-Unknown} -->"

# Determine pass/fail
if [ -n "$REVIEW_SCORE" ] && [ "$REVIEW_SCORE" -ge 81 ]; then
    if [[ "$REVIEW_ASSESSMENT" == "Approve"* ]]; then
        echo ""
        echo "✓ PASS - Review passed (score $REVIEW_SCORE >= 81, assessment: $REVIEW_ASSESSMENT)"
        exit 0
    fi
fi

echo ""
echo "✗ NEEDS_WORK - Review did not pass (score: $REVIEW_SCORE, assessment: $REVIEW_ASSESSMENT)"
exit 0  # Don't fail the script, let the workflow handle it
