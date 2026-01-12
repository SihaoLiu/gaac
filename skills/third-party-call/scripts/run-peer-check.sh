#!/bin/bash
#
# Run peer code review using external model (Codex preferred, Claude fallback)
# Returns structured review with PASS/NEEDS_WORK status
#

set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source portable timeout wrapper
source "$PLUGIN_ROOT/scripts/portable-timeout.sh"

# Parse arguments
ISSUE_NUMBER=""
OUTPUT_FILE=""
TOOL=""  # Auto-detect if not specified

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
        --tool|-t)
            TOOL="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [ -z "$ISSUE_NUMBER" ]; then
    echo "Usage: run-peer-check.sh --issue-number 42 [--output-file output.md]" >&2
    exit 3
fi

OUTPUT_FILE="${OUTPUT_FILE:-$PROJECT_ROOT/.claude/peer-check-$ISSUE_NUMBER.md}"

# Auto-detect tool
if [ -z "$TOOL" ]; then
    if command -v codex &>/dev/null; then
        TOOL="codex"
    elif command -v claude &>/dev/null; then
        TOOL="claude"
    else
        echo "❌ Error: Neither codex nor claude is available" >&2
        exit 1
    fi
fi

echo "=== Peer Code Review ==="
echo "Issue: #$ISSUE_NUMBER"
echo "Tool: $TOOL"
echo "Output: $OUTPUT_FILE"
echo ""

# Get issue details
ISSUE_JSON=$(gh issue view "$ISSUE_NUMBER" --json title,body 2>/dev/null || echo "")
if [ -z "$ISSUE_JSON" ]; then
    echo "❌ Error: Could not fetch issue #$ISSUE_NUMBER" >&2
    exit 3
fi

ISSUE_TITLE=$(echo "$ISSUE_JSON" | jq -r '.title')
ISSUE_BODY=$(echo "$ISSUE_JSON" | jq -r '.body // ""')

# Get current diff
DIFF=$(git diff --stat 2>/dev/null || echo "No changes")
DIFF_DETAIL=$(git diff 2>/dev/null | head -500 || echo "")

# Build prompt
PROMPT_FILE=$(mktemp)
cat > "$PROMPT_FILE" << EOF
# Peer Code Review Request

You are an independent code reviewer. Review the following changes for issue #$ISSUE_NUMBER.

## Issue: $ISSUE_TITLE

$ISSUE_BODY

## Changes to Review

\`\`\`diff
$DIFF_DETAIL
\`\`\`

## Review Instructions

1. **Correctness**: Do the changes correctly address the issue requirements?
2. **Bugs**: Are there any obvious bugs or logic errors?
3. **Security**: Are there any security vulnerabilities?
4. **Edge Cases**: Are edge cases handled?
5. **Code Quality**: Is the code clean and maintainable?

## Output Format

Provide your review in this exact format:

### Status: [PASS|NEEDS_WORK]

### Summary
[1-2 sentence summary of the review]

### Findings

#### Critical (must fix)
- [Finding 1]
- [Finding 2]

#### Important (should fix)
- [Finding 1]

#### Minor (consider)
- [Finding 1]

### Recommendation
[Your recommendation for next steps]
EOF

echo "Running $TOOL for peer review..."

TIMEOUT="${CODEX_TIMEOUT:-5400}"

if [ "$TOOL" = "codex" ]; then
    # Run Codex with portable timeout
    run_with_timeout "$TIMEOUT" codex exec \
        -m gpt-5.2-codex \
        -c model_reasoning_effort=high \
        -s read-only \
        -o "$OUTPUT_FILE" \
        -C "$PROJECT_ROOT" \
        < "$PROMPT_FILE" 2>/dev/null

    EXIT_CODE=$?
else
    # Run Claude with portable timeout
    TIMEOUT="${CLAUDE_TIMEOUT:-300}"
    run_with_timeout "$TIMEOUT" claude -p \
        --model opus \
        --permission-mode bypassPermissions \
        --tools "Read,Grep,Glob" \
        --allowedTools "Read,Grep,Glob" \
        < "$PROMPT_FILE" > "$OUTPUT_FILE" 2>/dev/null

    EXIT_CODE=$?
fi

rm -f "$PROMPT_FILE"

if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ $TOOL execution failed (exit code: $EXIT_CODE)" >&2
    exit 2
fi

# Parse result
if [ -f "$OUTPUT_FILE" ]; then
    STATUS=$(grep -i "Status:" "$OUTPUT_FILE" | head -1 | grep -oE "PASS|NEEDS_WORK" || echo "UNKNOWN")

    echo ""
    echo "=== Review Complete ==="
    echo "Status: $STATUS"
    echo "Full review: $OUTPUT_FILE"

    # Output JSON
    echo ""
    echo "JSON_OUTPUT:"
    jq -n \
        --arg status "$STATUS" \
        --arg file "$OUTPUT_FILE" \
        --arg issue "$ISSUE_NUMBER" \
        --arg tool "$TOOL" \
        '{status: $status, output_file: $file, issue: $issue, tool: $tool}'

    if [ "$STATUS" = "NEEDS_WORK" ]; then
        exit 0  # Success but needs work
    else
        exit 0  # Success and passed
    fi
else
    echo "❌ No output file generated" >&2
    exit 2
fi
