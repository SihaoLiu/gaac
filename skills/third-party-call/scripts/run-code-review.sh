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

# ========================================
# Run External Review
# ========================================

echo "Running code review..."

# Check model configuration
CODE_REVIEWER_MODEL=""
if [ -f "$CONFIG_HELPER" ]; then
    CODE_REVIEWER_MODEL=$(bash "$CONFIG_HELPER" get "gaac.models.code_reviewer" 2>/dev/null || echo "")
fi

REVIEW_OUTPUT=""
TOOL_USED=""

# Try codex first (preferred)
if command -v codex &>/dev/null; then
    echo "  Using codex for review..."

    # Parse model config (format: tool:model:reasoning)
    CODEX_MODEL="gpt-5.2-codex"
    CODEX_REASONING="xhigh"
    if [ -n "$CODE_REVIEWER_MODEL" ] && [[ "$CODE_REVIEWER_MODEL" == codex:* ]]; then
        CODEX_MODEL=$(echo "$CODE_REVIEWER_MODEL" | cut -d: -f2)
        CODEX_REASONING=$(echo "$CODE_REVIEWER_MODEL" | cut -d: -f3)
    fi

    # Set timeout (10 minutes)
    TIMEOUT_CMD=""
    if command -v timeout &>/dev/null; then
        TIMEOUT_CMD="timeout 600"
    fi

    REVIEW_OUTPUT=$($TIMEOUT_CMD codex \
        --model "$CODEX_MODEL" \
        --reasoning "$CODEX_REASONING" \
        --approval-mode full-auto \
        "$(cat "$TEMP_INPUT")" 2>/dev/null || echo "")

    if [ -n "$REVIEW_OUTPUT" ]; then
        TOOL_USED="codex"
    fi
fi

# Fallback to claude
if [ -z "$REVIEW_OUTPUT" ] && command -v claude &>/dev/null; then
    echo "  Falling back to claude for review..."

    # Parse model config for claude
    CLAUDE_MODEL="opus"
    if [ -n "$CODE_REVIEWER_MODEL" ] && [[ "$CODE_REVIEWER_MODEL" == claude:* ]]; then
        CLAUDE_MODEL=$(echo "$CODE_REVIEWER_MODEL" | cut -d: -f2)
    fi

    # Check fallback config
    FALLBACK_MODEL=$(bash "$CONFIG_HELPER" get "gaac.models.code_reviewer_fallback" 2>/dev/null || echo "claude:opus")
    if [ -z "$CLAUDE_MODEL" ] || [ "$CLAUDE_MODEL" = "opus" ]; then
        CLAUDE_MODEL=$(echo "$FALLBACK_MODEL" | cut -d: -f2)
    fi

    TIMEOUT_CMD=""
    if command -v timeout &>/dev/null; then
        TIMEOUT_CMD="timeout 600"
    fi

    REVIEW_OUTPUT=$($TIMEOUT_CMD claude --print --model "$CLAUDE_MODEL" < "$TEMP_INPUT" 2>/dev/null || echo "")

    if [ -n "$REVIEW_OUTPUT" ]; then
        TOOL_USED="claude"
    fi
fi

rm -f "$TEMP_INPUT"

# ========================================
# Process Review Output
# ========================================

if [ -z "$REVIEW_OUTPUT" ]; then
    echo "❌ Error: Code review failed - no external tools available" >&2
    exit 1
fi

echo "  Review completed using $TOOL_USED"

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
