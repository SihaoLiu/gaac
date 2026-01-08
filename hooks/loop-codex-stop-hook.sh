#!/bin/bash
#
# Stop Hook for ralph-loop-with-codex-review
#
# Intercepts Claude's exit attempts and uses Codex to review work.
# If Codex doesn't confirm completion, blocks exit and feeds review back.
#
# State directory: .claude/gaac-loop.local/<timestamp>/
# State file: state.md (current_round, max_iterations, codex config)
# Summary file: round-N-summary.md (Claude's work summary)
# Review prompt: round-N-review-prompt.md (prompt sent to Codex)
# Review result: round-N-review-result.md (Codex's review)
#

set -euo pipefail

# ========================================
# Default Configuration
# ========================================

DEFAULT_CODEX_MODEL="gpt-5.2-codex"
DEFAULT_CODEX_EFFORT="xhigh"
CODEX_TIMEOUT="${CODEX_TIMEOUT:-600}"

# ========================================
# Read Hook Input
# ========================================

HOOK_INPUT=$(cat)

# Prevent recursive invocation
STOP_HOOK_ACTIVE=$(echo "$HOOK_INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
    exit 0
fi

# ========================================
# Find Active Loop
# ========================================

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
LOOP_BASE_DIR="$PROJECT_ROOT/.claude/gaac-loop.local"

# Find the most recent active loop directory
find_active_loop() {
    if [[ ! -d "$LOOP_BASE_DIR" ]]; then
        echo ""
        return
    fi

    # Find directories with state.md, sorted by name (timestamp) descending
    for dir in $(ls -1dr "$LOOP_BASE_DIR"/*/ 2>/dev/null); do
        if [[ -f "$dir/state.md" ]]; then
            echo "$dir"
            return
        fi
    done
    echo ""
}

LOOP_DIR=$(find_active_loop)

# If no active loop, allow exit
if [[ -z "$LOOP_DIR" ]]; then
    exit 0
fi

STATE_FILE="$LOOP_DIR/state.md"

# ========================================
# Parse State File
# ========================================

if [[ ! -f "$STATE_FILE" ]]; then
    exit 0
fi

# Extract frontmatter values
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE" 2>/dev/null || echo "")

CURRENT_ROUND=$(echo "$FRONTMATTER" | grep '^current_round:' | sed 's/current_round: *//' | tr -d ' ')
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//' | tr -d ' ')
CODEX_MODEL=$(echo "$FRONTMATTER" | grep '^codex_model:' | sed 's/codex_model: *//' | tr -d ' ')
CODEX_EFFORT=$(echo "$FRONTMATTER" | grep '^codex_effort:' | sed 's/codex_effort: *//' | tr -d ' ')
PLAN_FILE=$(echo "$FRONTMATTER" | grep '^plan_file:' | sed 's/plan_file: *//')

# Defaults
CURRENT_ROUND="${CURRENT_ROUND:-0}"
MAX_ITERATIONS="${MAX_ITERATIONS:-10}"
CODEX_MODEL="${CODEX_MODEL:-$DEFAULT_CODEX_MODEL}"
CODEX_EFFORT="${CODEX_EFFORT:-$DEFAULT_CODEX_EFFORT}"

# Validate numeric fields
if [[ ! "$CURRENT_ROUND" =~ ^[0-9]+$ ]]; then
    echo "Warning: State file corrupted (current_round), stopping loop" >&2
    rm -f "$STATE_FILE"
    exit 0
fi

if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
    MAX_ITERATIONS=10
fi

# ========================================
# Check Summary File Exists
# ========================================

SUMMARY_FILE="$LOOP_DIR/round-${CURRENT_ROUND}-summary.md"

if [[ ! -f "$SUMMARY_FILE" ]]; then
    # Summary file doesn't exist - Claude didn't write it
    # Block exit and remind Claude to write summary

    REASON="# Work Summary Missing

You attempted to exit without writing your work summary.

**Required Action**: Write your work summary to:
\`\`\`
$SUMMARY_FILE
\`\`\`

The summary should include:
- What was implemented
- Files created/modified
- Tests added/passed
- Any remaining items

After writing the summary, you may attempt to exit again."

    jq -n \
        --arg reason "$REASON" \
        --arg msg "Loop: Summary file missing for round $CURRENT_ROUND" \
        '{
            "decision": "block",
            "reason": $reason,
            "systemMessage": $msg
        }'
    exit 0
fi

# ========================================
# Check Max Iterations
# ========================================

NEXT_ROUND=$((CURRENT_ROUND + 1))

if [[ $NEXT_ROUND -gt $MAX_ITERATIONS ]]; then
    echo "ralph-loop-with-codex-review did not complete, but reached max iterations ($MAX_ITERATIONS). Exiting." >&2
    rm -f "$STATE_FILE"
    exit 0
fi

# ========================================
# Get Docs Path from Config
# ========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_HELPER="$PLUGIN_ROOT/scripts/gaac-config.sh"

DOCS_PATH=""
if [[ -f "$CONFIG_HELPER" ]]; then
    DOCS_PATH=$(bash "$CONFIG_HELPER" docs-base 2>/dev/null || echo "")
fi
DOCS_PATH="${DOCS_PATH:-docs}"

# ========================================
# Build Codex Review Prompt
# ========================================

PROMPT_FILE="$LOOP_DIR/round-${CURRENT_ROUND}-prompt.md"
REVIEW_PROMPT_FILE="$LOOP_DIR/round-${CURRENT_ROUND}-review-prompt.md"
REVIEW_RESULT_FILE="$LOOP_DIR/round-${CURRENT_ROUND}-review-result.md"

SUMMARY_CONTENT=$(cat "$SUMMARY_FILE")

cat > "$REVIEW_PROMPT_FILE" << EOF
Based on $PROMPT_FILE, Claude claims to have completed the work. Please conduct a thorough critical review to verify this.

---
Below is Claude's summary of the work completed:
$SUMMARY_CONTENT
---

Requirements:
- Your task is to conduct a deep critical review, focusing on finding implementation issues and identifying gaps between "plan-design" and actual implementation.
- Relevant top-level guidance documents, phased implementation plans, and other important documentation and implementation references are located under $DOCS_PATH.
- If after your investigation the actual situation does not match what Claude claims to have completed, output your review comments to $REVIEW_RESULT_FILE.
- If after your investigation the actual situation matches what Claude claims, output your review result to the same file, and ensure the last line contains only the single word COMPLETE.
EOF

# ========================================
# Run Codex Review
# ========================================

echo "Running Codex review for round $CURRENT_ROUND..." >&2

# Source portable timeout if available
TIMEOUT_SCRIPT="$PLUGIN_ROOT/scripts/portable-timeout.sh"
if [[ -f "$TIMEOUT_SCRIPT" ]]; then
    source "$TIMEOUT_SCRIPT"
else
    # Fallback: define run_with_timeout inline
    run_with_timeout() {
        local timeout_secs="$1"
        shift
        if command -v timeout &>/dev/null; then
            timeout "$timeout_secs" "$@"
        elif command -v gtimeout &>/dev/null; then
            gtimeout "$timeout_secs" "$@"
        else
            # No timeout command, just run directly
            "$@"
        fi
    }
fi

# Build Codex command
CODEX_ARGS=("-m" "$CODEX_MODEL")
if [[ -n "$CODEX_EFFORT" ]]; then
    CODEX_ARGS+=("-c" "model_reasoning_effort=${CODEX_EFFORT}")
fi
CODEX_ARGS+=("--enable" "web_search_request" "-s" "workspace-write" "-o" "$REVIEW_RESULT_FILE" "-C" "$PROJECT_ROOT")

CODEX_EXIT_CODE=0
run_with_timeout "$CODEX_TIMEOUT" codex exec "${CODEX_ARGS[@]}" < "$REVIEW_PROMPT_FILE" 2>/dev/null || CODEX_EXIT_CODE=$?

# ========================================
# Check Codex Output
# ========================================

if [[ ! -f "$REVIEW_RESULT_FILE" ]]; then
    echo "Error: Codex did not create review result file" >&2

    REASON="# Codex Review Failed

The Codex review process failed to produce output.

**Error**: Review result file was not created: $REVIEW_RESULT_FILE
**Exit Code**: $CODEX_EXIT_CODE

Please try again. The system will attempt another review when you exit."

    jq -n \
        --arg reason "$REASON" \
        --arg msg "Loop: Codex review failed for round $CURRENT_ROUND" \
        '{
            "decision": "block",
            "reason": $reason,
            "systemMessage": $msg
        }'
    exit 0
fi

# Read the review result
REVIEW_CONTENT=$(cat "$REVIEW_RESULT_FILE")

# Check if the last non-empty line is exactly "COMPLETE"
LAST_LINE=$(echo "$REVIEW_CONTENT" | grep -v '^[[:space:]]*$' | tail -1 | tr -d '[:space:]')

if [[ "$LAST_LINE" == "COMPLETE" ]]; then
    # Review passed - allow exit
    echo "Codex review passed. Loop complete!" >&2
    rm -f "$STATE_FILE"
    exit 0
fi

# ========================================
# Review Found Issues - Continue Loop
# ========================================

# Update state file for next round
TEMP_FILE="${STATE_FILE}.tmp.$$"
sed "s/^current_round: .*/current_round: $NEXT_ROUND/" "$STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$STATE_FILE"

# Create next round prompt
NEXT_PROMPT_FILE="$LOOP_DIR/round-${NEXT_ROUND}-prompt.md"
NEXT_SUMMARY_FILE="$LOOP_DIR/round-${NEXT_ROUND}-summary.md"

cat > "$NEXT_PROMPT_FILE" << EOF
Your work is not finished, read and execute below with ultrathink

$REVIEW_CONTENT

Note: You MUST NOT try to exit \`ralph-loop-with-codex-review\` loop by lying or edit loop state file or try to execute \`cancel-loop-with-codex\`

Please write your work summary into $NEXT_SUMMARY_FILE
EOF

# Build system message
SYSTEM_MSG="Loop: Round $NEXT_ROUND/$MAX_ITERATIONS - Codex found issues to address"

# Block exit and send review feedback
jq -n \
    --arg reason "$(cat "$NEXT_PROMPT_FILE")" \
    --arg msg "$SYSTEM_MSG" \
    '{
        "decision": "block",
        "reason": $reason,
        "systemMessage": $msg
    }'

exit 0
