#!/bin/bash
#
# Stop Hook for ralph-loop-with-codex-review
#
# Intercepts Claude's exit attempts and uses Codex to review work.
# If Codex doesn't confirm completion, blocks exit and feeds review back.
#
# State directory: .gaac-loop.local/<timestamp>/
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
DEFAULT_CODEX_TIMEOUT=5400

# ========================================
# Read Hook Input
# ========================================

HOOK_INPUT=$(cat)

# NOTE: We intentionally do NOT check stop_hook_active here.
# For iterative loops, stop_hook_active will be true when Claude is continuing
# from a previous blocked stop. We WANT to run Codex review each iteration.
# Loop termination is controlled by:
# - No active loop directory (no state.md) -> exit early below
# - Codex outputs "COMPLETE" -> allow exit
# - current_round >= max_iterations -> allow exit

# ========================================
# Find Active Loop
# ========================================

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
LOOP_BASE_DIR="$PROJECT_ROOT/.gaac-loop.local"

# Find the most recent active loop directory
find_active_loop() {
    if [[ ! -d "$LOOP_BASE_DIR" ]]; then
        echo ""
        return
    fi

    # Find directories with state.md, sorted by name (timestamp) descending
    for dir in $(ls -1dr "$LOOP_BASE_DIR"/*/ 2>/dev/null); do
        if [[ -f "$dir/state.md" ]]; then
            # Remove trailing slash to avoid double slashes in paths
            echo "${dir%/}"
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
STATE_CODEX_TIMEOUT=$(echo "$FRONTMATTER" | grep '^codex_timeout:' | sed 's/codex_timeout: *//' | tr -d ' ')
PLAN_FILE=$(echo "$FRONTMATTER" | grep '^plan_file:' | sed 's/plan_file: *//')

# Defaults
CURRENT_ROUND="${CURRENT_ROUND:-0}"
MAX_ITERATIONS="${MAX_ITERATIONS:-10}"
CODEX_MODEL="${CODEX_MODEL:-$DEFAULT_CODEX_MODEL}"
CODEX_EFFORT="${CODEX_EFFORT:-$DEFAULT_CODEX_EFFORT}"
# Timeout priority: state file > env var > default
CODEX_TIMEOUT="${STATE_CODEX_TIMEOUT:-${CODEX_TIMEOUT:-$DEFAULT_CODEX_TIMEOUT}}"

# Validate numeric fields
if [[ ! "$CURRENT_ROUND" =~ ^[0-9]+$ ]]; then
    echo "Warning: State file corrupted (current_round), stopping loop" >&2
    rm -f "$STATE_FILE"
    exit 0
fi

# max_iterations can be "inf" for infinite mode or a number
if [[ "$MAX_ITERATIONS" != "inf" ]] && [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
    MAX_ITERATIONS=42
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

# Skip max iteration check if in infinite mode
if [[ "$MAX_ITERATIONS" != "inf" ]] && [[ $NEXT_ROUND -gt $MAX_ITERATIONS ]]; then
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
Based on @$PROMPT_FILE, Claude claims to have completed the work. Please conduct a thorough critical review to verify this.

---
Below is Claude's summary of the work completed:
<!-- CLAUDE's WORK SUMMARY START -->
$SUMMARY_CONTENT
<!-- CLAUDE's WORK SUMMARY  END  -->
---

Requirements:
- Your task is to conduct a deep critical review, focusing on finding implementation issues and identifying gaps between "plan-design" and actual implementation.
- Relevant top-level guidance documents, phased implementation plans, and other important documentation and implementation references are located under @$DOCS_PATH.
- If Claude planned to defer any tasks to future phases in its summary, DO NOT follow its lead. Instead, you should force Claude to complete ALL tasks as planned. 
  - Such deferred tasks are considered incomplete work and should be flagged in your review comments, requiring Claude to address them. 
  - If Claude planned to defer any tasks, please explore the codebase in-depth and draft a detailed implementation plan. This plan should be included in your review comments for Claude to follow.
  - Your review should be meticulous and skeptical. Look for any discrepancies, missing features, incomplete implementations.
- If Claude does not plan to defer any tasks, but honestly admits that some tasks are still pending (not yet completed), you should also include those pending tasks in your review.
  - Your review should elaborate on those unfinished tasks, explore the codebase, and draft an implementation plan.
  - A good engineering implementation plan should be **singular, directive, and definitive**, rather than discussing multiple possible implementation options.
  - The implementation plan should be **unambiguous**, internally consistent, and coherent from beginning to end, so that **Claude can execute the work accurately and without error**.
- In short, your review comments can include: problems/findings/blockers; claims that don't match reality; implementation plans for deferred work (to be implemented now); implementation plans for unfinished work.
- If after your investigation the actual situation does not match what Claude claims to have completed, or there is pending work to be done, output your review comments to @$REVIEW_RESULT_FILE.
- If after your investigation the actual situation matches what Claude claims, and there is no deferred or unfinished work, output your review result to the same file, and ensure the last line contains only the single word COMPLETE.
- The word COMPLETE on the last line will stop Claude.
EOF

# ========================================
# Run Codex Review
# ========================================

echo "Running Codex review for round $CURRENT_ROUND..." >&2

# Debug log files go to $HOME/.cache/gaac/<timestamp>/ to avoid polluting project dir
# This prevents Claude and Codex from reading these debug files during their work
LOOP_TIMESTAMP=$(basename "$LOOP_DIR")
CACHE_DIR="$HOME/.cache/gaac/$LOOP_TIMESTAMP"
mkdir -p "$CACHE_DIR"

CODEX_CMD_FILE="$CACHE_DIR/round-${CURRENT_ROUND}-codex-run.cmd"
CODEX_STDOUT_FILE="$CACHE_DIR/round-${CURRENT_ROUND}-codex-run.out"
CODEX_STDERR_FILE="$CACHE_DIR/round-${CURRENT_ROUND}-codex-run.log"

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

# Build Codex command arguments
# Note: codex exec reads prompt from stdin, writes to stdout, and we use -w to write to file
CODEX_ARGS=("-m" "$CODEX_MODEL")
if [[ -n "$CODEX_EFFORT" ]]; then
    CODEX_ARGS+=("-c" "model_reasoning_effort=${CODEX_EFFORT}")
fi
CODEX_ARGS+=("--full-auto" "-C" "$PROJECT_ROOT")

# Save the command for debugging
CODEX_PROMPT_CONTENT=$(cat "$REVIEW_PROMPT_FILE")
{
    echo "# Codex invocation debug info"
    echo "# Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# Working directory: $PROJECT_ROOT"
    echo "# Timeout: $CODEX_TIMEOUT seconds"
    echo ""
    echo "codex exec ${CODEX_ARGS[*]} \"<prompt>\""
    echo ""
    echo "# Prompt content:"
    echo "$CODEX_PROMPT_CONTENT"
} > "$CODEX_CMD_FILE"

echo "Codex command saved to: $CODEX_CMD_FILE" >&2
echo "Running codex exec with timeout ${CODEX_TIMEOUT}s..." >&2

CODEX_EXIT_CODE=0
run_with_timeout "$CODEX_TIMEOUT" codex exec "${CODEX_ARGS[@]}" "$CODEX_PROMPT_CONTENT" \
    > "$CODEX_STDOUT_FILE" 2> "$CODEX_STDERR_FILE" || CODEX_EXIT_CODE=$?

echo "Codex exit code: $CODEX_EXIT_CODE" >&2
echo "Codex stdout saved to: $CODEX_STDOUT_FILE" >&2
echo "Codex stderr saved to: $CODEX_STDERR_FILE" >&2

# Check if Codex created the review result file (it should write to workspace)
# If not, check if it wrote to stdout
if [[ ! -f "$REVIEW_RESULT_FILE" ]]; then
    # Codex might have written output to stdout instead
    if [[ -s "$CODEX_STDOUT_FILE" ]]; then
        echo "Codex output found in stdout, copying to review result file..." >&2
        cp "$CODEX_STDOUT_FILE" "$REVIEW_RESULT_FILE"
    fi
fi

# ========================================
# Check Codex Output
# ========================================

if [[ ! -f "$REVIEW_RESULT_FILE" ]]; then
    echo "Error: Codex did not create review result file" >&2

    # Read stderr for error details
    STDERR_CONTENT=""
    if [[ -f "$CODEX_STDERR_FILE" ]]; then
        STDERR_CONTENT=$(tail -50 "$CODEX_STDERR_FILE" 2>/dev/null || echo "(unable to read stderr)")
    fi

    REASON="# Codex Review Failed

The Codex review process failed to produce output.

**Exit Code**: $CODEX_EXIT_CODE
**Review Result File**: $REVIEW_RESULT_FILE (not created)

**Debug Files**:
- Command: $CODEX_CMD_FILE
- Stdout: $CODEX_STDOUT_FILE
- Stderr: $CODEX_STDERR_FILE

**Stderr (last 50 lines)**:
\`\`\`
$STDERR_CONTENT
\`\`\`

Please check the debug files for more details. The system will attempt another review when you exit."

    jq -n \
        --arg reason "$REASON" \
        --arg msg "Loop: Codex review failed for round $CURRENT_ROUND (exit code: $CODEX_EXIT_CODE)" \
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
Your work is not finished. Read and execute the below with ultrathink.

For all tasks that need to be completed, please create Todos to track each item in order of importance.
You are strictly prohibited from only addressing the most important issues - you MUST create Todos for ALL discovered issues and attempt to resolve each one.

---
Below is Codex's review result:
<!-- CODEX's REVIEW RESULT START -->
$REVIEW_CONTENT
<!-- CODEX's REVIEW RESULT  END  -->
---

Note: You MUST NOT try to exit the \`ralph-loop-with-codex-review\` loop by lying, editing the loop state file, or executing \`cancel-loop-with-codex\`.

After completing the work, please:
1. Commit your changes with a descriptive commit message
2. Push the commit to the remote repository
3. Write your work summary into @$NEXT_SUMMARY_FILE
EOF

# Build system message
if [[ "$MAX_ITERATIONS" == "inf" ]]; then
    SYSTEM_MSG="Loop: Round $NEXT_ROUND (infinite mode) - Codex found issues to address"
else
    SYSTEM_MSG="Loop: Round $NEXT_ROUND/$MAX_ITERATIONS - Codex found issues to address"
fi

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
