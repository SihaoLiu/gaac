#!/bin/bash
#
# Run general analysis using external model (Codex preferred, Claude fallback)
# Used for design analysis, synthesis, and independent review
#
# Model configuration is read from gaac.md:
#   gaac.models.analyzer: codex:gpt-5.2-codex:xhigh
#   gaac.models.analyzer_fallback: claude:opus
#

set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CONFIG_HELPER="$PLUGIN_ROOT/scripts/gaac-config.sh"

# Source portable timeout wrapper
source "$PLUGIN_ROOT/scripts/portable-timeout.sh"

# Parse arguments
PROMPT_FILE=""
PROMPT_TEXT=""
OUTPUT_FILE=""
CONTEXT_FILES=""
TOOL=""
MODEL_ROLE="analyzer"  # Can be: analyzer, checker, proposer

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
        --role|-r)
            MODEL_ROLE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# ========================================
# Read Model Configuration from gaac.md
# ========================================

# Model config format: tool:model:reasoning (e.g., codex:gpt-5.2-codex:xhigh)
get_model_config() {
    local role="$1"
    local fallback="$2"

    if [ -f "$CONFIG_HELPER" ]; then
        local config=$(bash "$CONFIG_HELPER" get "gaac.models.${role}" 2>/dev/null || echo "")
        if [ -n "$config" ] && [ "$config" != "MISSING" ]; then
            echo "$config"
            return
        fi
    fi
    echo "$fallback"
}

# Get model configuration based on role
case "$MODEL_ROLE" in
    analyzer)
        MODEL_CONFIG=$(get_model_config "analyzer" "codex:gpt-5.2-codex:xhigh")
        MODEL_FALLBACK=$(get_model_config "analyzer_fallback" "claude:opus")
        ;;
    checker)
        MODEL_CONFIG=$(get_model_config "checker" "claude:opus")
        MODEL_FALLBACK=""  # Single checker, no fallback chain
        ;;
    proposer)
        MODEL_CONFIG=$(get_model_config "proposer" "claude:sonnet")
        MODEL_FALLBACK=""  # Proposer doesn't need fallback
        ;;
    proposer_secondary)
        MODEL_CONFIG=$(get_model_config "proposer_secondary" "gemini:gemini-3-pro-preview")
        MODEL_FALLBACK=""  # Secondary proposer, no fallback
        ;;
    code_reviewer)
        MODEL_CONFIG=$(get_model_config "code_reviewer" "codex:gpt-5.2-codex:xhigh")
        MODEL_FALLBACK=$(get_model_config "code_reviewer_fallback" "claude:opus")
        ;;
    *)
        MODEL_CONFIG="codex:gpt-5.2-codex:xhigh"
        MODEL_FALLBACK="claude:opus"
        ;;
esac

# Parse model config
CONFIGURED_TOOL=$(echo "$MODEL_CONFIG" | cut -d: -f1)
CONFIGURED_MODEL=$(echo "$MODEL_CONFIG" | cut -d: -f2)
CONFIGURED_REASONING=$(echo "$MODEL_CONFIG" | cut -d: -f3)

# Override with command-line tool if specified
if [ -n "$TOOL" ]; then
    CONFIGURED_TOOL="$TOOL"
fi

# Validate input
if [ -z "$PROMPT_FILE" ] && [ -z "$PROMPT_TEXT" ]; then
    echo "Usage: run-analysis.sh --prompt-file prompt.md --output-file output.md" >&2
    echo "       run-analysis.sh --prompt 'Your prompt' --output-file output.md" >&2
    exit 3
fi

OUTPUT_FILE="${OUTPUT_FILE:-$PROJECT_ROOT/.claude/analysis-$(date +%s).md}"

# Use configured tool, verify it's available
TOOL="$CONFIGURED_TOOL"
if [ "$TOOL" = "codex" ] && ! command -v codex &>/dev/null; then
    echo "Configured tool 'codex' not available, checking fallback..."
    if [ -n "$MODEL_FALLBACK" ]; then
        TOOL=$(echo "$MODEL_FALLBACK" | cut -d: -f1)
        CONFIGURED_MODEL=$(echo "$MODEL_FALLBACK" | cut -d: -f2)
        CONFIGURED_REASONING=""
    elif command -v claude &>/dev/null; then
        TOOL="claude"
        CONFIGURED_MODEL="opus"
    else
        echo "❌ Error: Neither codex nor claude is available" >&2
        exit 1
    fi
fi

if [ "$TOOL" = "claude" ] && ! command -v claude &>/dev/null; then
    echo "❌ Error: claude is not available" >&2
    exit 1
fi

if [ "$TOOL" = "gemini" ] && ! command -v gemini &>/dev/null; then
    echo "❌ Error: gemini is not available" >&2
    exit 1
fi

echo "=== External Analysis ==="
echo "Role: $MODEL_ROLE"
echo "Tool: $TOOL"
echo "Model: ${CONFIGURED_MODEL:-default}"
[ -n "$CONFIGURED_REASONING" ] && echo "Reasoning: $CONFIGURED_REASONING"
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
EXIT_CODE=0

if [ "$TOOL" = "codex" ]; then
    # Build codex command with configured options
    CODEX_ARGS=("-m" "${CONFIGURED_MODEL:-gpt-5.2-codex}")
    if [ -n "$CONFIGURED_REASONING" ]; then
        CODEX_ARGS+=("-c" "model_reasoning_effort=${CONFIGURED_REASONING}")
    fi
    CODEX_ARGS+=("--enable" "web_search_request" "-s" "read-only" "-o" "$OUTPUT_FILE" "-C" "$PROJECT_ROOT")

    run_with_timeout "$TIMEOUT" codex exec "${CODEX_ARGS[@]}" < "$FULL_PROMPT_FILE" 2>/dev/null
    EXIT_CODE=$?

elif [ "$TOOL" = "claude" ]; then
    TIMEOUT="${CLAUDE_TIMEOUT:-300}"
    run_with_timeout "$TIMEOUT" claude -p \
        --model "${CONFIGURED_MODEL:-opus}" \
        --permission-mode bypassPermissions \
        --tools "Read,Grep,Glob,WebSearch,WebFetch" \
        --allowedTools "Read,Grep,Glob,WebSearch,WebFetch" \
        < "$FULL_PROMPT_FILE" > "$OUTPUT_FILE" 2>/dev/null
    EXIT_CODE=$?

elif [ "$TOOL" = "gemini" ]; then
    # Gemini support for proposer_secondary
    TIMEOUT="${GEMINI_TIMEOUT:-300}"
    run_with_timeout "$TIMEOUT" gemini \
        --model "${CONFIGURED_MODEL:-gemini-3-pro-preview}" \
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

    # Try configured fallback if available
    if [ -n "$MODEL_FALLBACK" ]; then
        FALLBACK_TOOL=$(echo "$MODEL_FALLBACK" | cut -d: -f1)
        FALLBACK_MODEL=$(echo "$MODEL_FALLBACK" | cut -d: -f2)

        if [ "$FALLBACK_TOOL" = "claude" ] && command -v claude &>/dev/null; then
            echo "Trying fallback: claude $FALLBACK_MODEL..."
            run_with_timeout "${CLAUDE_TIMEOUT:-300}" claude -p \
                --model "${FALLBACK_MODEL:-opus}" \
                --permission-mode bypassPermissions \
                --tools "Read,Grep,Glob,WebSearch,WebFetch" \
                --allowedTools "Read,Grep,Glob,WebSearch,WebFetch" \
                < "$FULL_PROMPT_FILE" > "$OUTPUT_FILE" 2>/dev/null
            EXIT_CODE=$?
            [ $EXIT_CODE -eq 0 ] && TOOL="claude"
        elif [ "$FALLBACK_TOOL" = "codex" ] && command -v codex &>/dev/null; then
            echo "Trying fallback: codex $FALLBACK_MODEL..."
            run_with_timeout "$TIMEOUT" codex exec \
                -m "${FALLBACK_MODEL:-gpt-5.2-codex}" \
                -s read-only \
                -o "$OUTPUT_FILE" \
                -C "$PROJECT_ROOT" \
                < "$FULL_PROMPT_FILE" 2>/dev/null
            EXIT_CODE=$?
            [ $EXIT_CODE -eq 0 ] && TOOL="codex"
        fi
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
