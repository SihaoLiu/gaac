#!/bin/bash
#
# Run web research using Gemini (Google search powered)
# Falls back gracefully if Gemini is not available
#

set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Parse arguments
TOPIC=""
OUTPUT_FILE=""
CONTEXT_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --topic|-t)
            TOPIC="$2"
            shift 2
            ;;
        --output-file|-o)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --context|-c)
            CONTEXT_FILE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [ -z "$TOPIC" ]; then
    echo "Usage: run-web-research.sh --topic 'research topic' [--output-file output.md]" >&2
    exit 3
fi

OUTPUT_FILE="${OUTPUT_FILE:-$PROJECT_ROOT/.claude/web-research-$(date +%s).md}"

# Check if Gemini is available
if ! command -v gemini &>/dev/null; then
    echo "⚠️  Gemini CLI not available. Web research skipped." >&2
    echo ""
    echo "To enable web research:"
    echo "  1. Install Gemini CLI"
    echo "  2. Authenticate: gemini auth login"
    echo ""
    exit 1
fi

echo "=== Web Research ==="
echo "Topic: $TOPIC"
echo "Output: $OUTPUT_FILE"
echo ""

# Create temporary settings file for read-only access
TEMP_SETTINGS=$(mktemp)
cat > "$TEMP_SETTINGS" << EOF
{
  "tools": {
    "core": ["list_directory", "read_file", "glob", "search_file_content", "web_fetch", "google_web_search"],
    "allowed": ["list_directory", "read_file", "glob", "search_file_content", "web_fetch", "google_web_search"],
    "exclude": ["write_file", "replace", "run_shell_command", "write_todos", "save_memory"]
  },
  "useSmartEdit": false,
  "useWriteTodos": false
}
EOF

# Build context
CONTEXT=""
if [ -n "$CONTEXT_FILE" ] && [ -f "$CONTEXT_FILE" ]; then
    CONTEXT=$(cat "$CONTEXT_FILE")
fi

# Build prompt
PROMPT="# Web Research Request

## Topic
$TOPIC

${CONTEXT:+## Additional Context
$CONTEXT
}

## Instructions

1. Use Google web search to find relevant information
2. Look for:
   - Recent developments (last 1-2 years)
   - Best practices
   - Common solutions
   - Known issues or pitfalls
3. Synthesize findings into a structured report

## Output Format

### Summary
[Key takeaways in 2-3 bullet points]

### Web Search Findings

#### Source 1: [Title]
- URL: [link]
- Key points: [summary]

#### Source 2: [Title]
- URL: [link]
- Key points: [summary]

[Continue for all relevant sources]

### Analysis
[Your analysis of the findings and how they relate to the topic]

### Recommendations
[Actionable recommendations based on research]
"

echo "Running Gemini web research..."

TIMEOUT="${GEMINI_TIMEOUT:-300}"

# Run Gemini
GEMINI_CLI_SYSTEM_SETTINGS_PATH="$TEMP_SETTINGS" \
timeout "$TIMEOUT" gemini \
    --output-format json \
    --approval-mode yolo \
    "$PROMPT" > "${OUTPUT_FILE}.json" 2>/dev/null

EXIT_CODE=$?

rm -f "$TEMP_SETTINGS"

if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ Gemini execution failed (exit code: $EXIT_CODE)" >&2
    rm -f "${OUTPUT_FILE}.json"
    exit 2
fi

# Extract response from JSON
if [ -f "${OUTPUT_FILE}.json" ]; then
    # Try jq first, fall back to python
    if command -v jq &>/dev/null; then
        jq -r '.response // .text // .content // .' "${OUTPUT_FILE}.json" > "$OUTPUT_FILE" 2>/dev/null || \
            cat "${OUTPUT_FILE}.json" > "$OUTPUT_FILE"
    elif command -v python3 &>/dev/null; then
        python3 -c "import json, sys; d=json.load(sys.stdin); print(d.get('response', d.get('text', json.dumps(d))))" \
            < "${OUTPUT_FILE}.json" > "$OUTPUT_FILE" 2>/dev/null || \
            cat "${OUTPUT_FILE}.json" > "$OUTPUT_FILE"
    else
        cat "${OUTPUT_FILE}.json" > "$OUTPUT_FILE"
    fi

    rm -f "${OUTPUT_FILE}.json"
fi

if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
    WORD_COUNT=$(wc -w < "$OUTPUT_FILE")
    echo ""
    echo "=== Research Complete ==="
    echo "Output: $OUTPUT_FILE ($WORD_COUNT words)"

    echo ""
    echo "JSON_OUTPUT:"
    jq -n \
        --arg topic "$TOPIC" \
        --arg file "$OUTPUT_FILE" \
        --arg words "$WORD_COUNT" \
        '{topic: $topic, output_file: $file, word_count: $words}'
    exit 0
else
    echo "❌ No output generated" >&2
    exit 2
fi
