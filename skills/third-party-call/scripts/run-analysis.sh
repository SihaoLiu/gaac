#!/bin/bash
#
# Run general analysis using external model (Codex preferred, Claude fallback)
# Used for design analysis, synthesis, and independent review
#

set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Parse arguments
PROMPT_FILE=""
PROMPT_TEXT=""
OUTPUT_FILE=""
CONTEXT_FILES=""
TOOL=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --prompt-file|-p)
            PROMPT_FILE="$2"
            shift 2
            ;;
        --prompt)
            PROMPT_TEXT="$2"
            shift 2
            ;;
        --output-file|-o)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --context-files|-c)
            CONTEXT_FILES="$2"
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

# Validate input
if [ -z "$PROMPT_FILE" ] && [ -z "$PROMPT_TEXT" ]; then
    echo "Usage: run-analysis.sh --prompt-file prompt.md --output-file output.md" >&2
    echo "       run-analysis.sh --prompt 'Your prompt' --output-file output.md" >&2
    exit 3
fi

OUTPUT_FILE="${OUTPUT_FILE:-$PROJECT_ROOT/.claude/analysis-$(date +%s).md}"

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

echo "=== External Analysis ==="
echo "Tool: $TOOL"
echo "Output: $OUTPUT_FILE"
echo ""

# Build the full prompt
FULL_PROMPT_FILE=$(mktemp)

# Add prompt content
if [ -n "$PROMPT_FILE" ] && [ -f "$PROMPT_FILE" ]; then
    cat "$PROMPT_FILE" > "$FULL_PROMPT_FILE"
elif [ -n "$PROMPT_TEXT" ]; then
    echo "$PROMPT_TEXT" > "$FULL_PROMPT_FILE"
fi

# Add context files if specified
if [ -n "$CONTEXT_FILES" ]; then
    echo "" >> "$FULL_PROMPT_FILE"
    echo "## Context Files" >> "$FULL_PROMPT_FILE"
    echo "" >> "$FULL_PROMPT_FILE"

    # Expand glob pattern
    for file in $CONTEXT_FILES; do
        if [ -f "$file" ]; then
            echo "### $(basename "$file")" >> "$FULL_PROMPT_FILE"
            echo '```' >> "$FULL_PROMPT_FILE"
            head -200 "$file" >> "$FULL_PROMPT_FILE"  # Limit to first 200 lines
            if [ $(wc -l < "$file") -gt 200 ]; then
                echo "... (truncated, $(wc -l < "$file") total lines)" >> "$FULL_PROMPT_FILE"
            fi
            echo '```' >> "$FULL_PROMPT_FILE"
            echo "" >> "$FULL_PROMPT_FILE"
        fi
    done
fi

PROMPT_LINES=$(wc -l < "$FULL_PROMPT_FILE")
echo "Prompt: $PROMPT_LINES lines"
echo ""

echo "Running $TOOL for analysis..."

TIMEOUT="${CODEX_TIMEOUT:-600}"

if [ "$TOOL" = "codex" ]; then
    timeout "$TIMEOUT" codex exec \
        -m gpt-5.2-codex \
        -c model_reasoning_effort=xhigh \
        --enable web_search_request \
        -s read-only \
        -o "$OUTPUT_FILE" \
        -C "$PROJECT_ROOT" \
        < "$FULL_PROMPT_FILE" 2>/dev/null

    EXIT_CODE=$?
else
    TIMEOUT="${CLAUDE_TIMEOUT:-300}"
    timeout "$TIMEOUT" claude -p \
        --model opus \
        --permission-mode bypassPermissions \
        --tools "Read,Grep,Glob,WebSearch,WebFetch" \
        --allowedTools "Read,Grep,Glob,WebSearch,WebFetch" \
        < "$FULL_PROMPT_FILE" > "$OUTPUT_FILE" 2>/dev/null

    EXIT_CODE=$?
fi

# Cleanup function to remove temp file
cleanup() {
    rm -f "$FULL_PROMPT_FILE"
}
trap cleanup EXIT

if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ $TOOL execution failed (exit code: $EXIT_CODE)" >&2

    # Try fallback if using codex
    if [ "$TOOL" = "codex" ] && command -v claude &>/dev/null; then
        echo "Trying Claude fallback..."
        TOOL="claude"
        timeout "${CLAUDE_TIMEOUT:-300}" claude -p \
            --model opus \
            --permission-mode bypassPermissions \
            --tools "Read,Grep,Glob,WebSearch,WebFetch" \
            --allowedTools "Read,Grep,Glob,WebSearch,WebFetch" \
            < "$FULL_PROMPT_FILE" > "$OUTPUT_FILE" 2>/dev/null
        EXIT_CODE=$?
    fi

    if [ $EXIT_CODE -ne 0 ]; then
        exit 2
    fi
fi

if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
    WORD_COUNT=$(wc -w < "$OUTPUT_FILE")
    LINE_COUNT=$(wc -l < "$OUTPUT_FILE")

    echo ""
    echo "=== Analysis Complete ==="
    echo "Output: $OUTPUT_FILE"
    echo "Size: $LINE_COUNT lines, $WORD_COUNT words"

    echo ""
    echo "JSON_OUTPUT:"
    jq -n \
        --arg file "$OUTPUT_FILE" \
        --arg tool "$TOOL" \
        --arg lines "$LINE_COUNT" \
        --arg words "$WORD_COUNT" \
        '{output_file: $file, tool: $tool, line_count: $lines, word_count: $words}'
    exit 0
else
    echo "❌ No output generated" >&2
    exit 2
fi
