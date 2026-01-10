#!/bin/bash
#
# PreToolUse Hook: Validate Bash commands for loop-with-codex-review
#
# Blocks attempts to bypass Write hook using shell redirection:
# - cat/echo/printf > round-*-*.md
# - tee round-*-*.md
#

set -euo pipefail

# Load shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/loop-common.sh"

# ========================================
# Parse Hook Input
# ========================================

HOOK_INPUT=$(cat)
TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name // ""')

if [[ "$TOOL_NAME" != "Bash" ]]; then
    exit 0
fi

COMMAND=$(echo "$HOOK_INPUT" | jq -r '.tool_input.command // ""')
COMMAND_LOWER=$(to_lower "$COMMAND")

# ========================================
# Detect Writes to Loop Files
# ========================================

# Pattern for round files (case-insensitive via lowercase command)
ROUND_FILE_PATTERN='round-[0-9]+-\(summary\|todos\|prompt\)\.md'

TARGET_FILE=""
FILE_TYPE=""

# Check for redirection patterns: > or >> to round-*-*.md
if echo "$COMMAND_LOWER" | grep -qE ">[[:space:]]*[^[:space:]]*round-[0-9]+-(summary|todos|prompt)\.md"; then
    TARGET_FILE=$(echo "$COMMAND_LOWER" | grep -oE "[^[:space:]]*round-[0-9]+-(summary|todos|prompt)\.md" | head -1)
fi

# Check for tee command
if [[ -z "$TARGET_FILE" ]] && echo "$COMMAND_LOWER" | grep -qE "tee[[:space:]]+(-a[[:space:]]+)?[^[:space:]]*round-[0-9]+-(summary|todos|prompt)\.md"; then
    TARGET_FILE=$(echo "$COMMAND_LOWER" | grep -oE "[^[:space:]]*round-[0-9]+-(summary|todos|prompt)\.md" | head -1)
fi

if [[ -z "$TARGET_FILE" ]]; then
    exit 0
fi

# Determine file type
if echo "$TARGET_FILE" | grep -qE 'summary\.md$'; then
    FILE_TYPE="summary"
elif echo "$TARGET_FILE" | grep -qE 'todos\.md$'; then
    FILE_TYPE="todos"
elif echo "$TARGET_FILE" | grep -qE 'prompt\.md$'; then
    FILE_TYPE="prompt"
fi

# ========================================
# Block Todos Files
# ========================================

if [[ "$FILE_TYPE" == "todos" ]]; then
    todos_blocked_message "Bash" >&2
    exit 2
fi

# ========================================
# Find Active Loop and Current Round
# ========================================

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
LOOP_BASE_DIR="$PROJECT_ROOT/.gaac-loop.local"
ACTIVE_LOOP_DIR=$(find_active_loop "$LOOP_BASE_DIR")

if [[ -z "$ACTIVE_LOOP_DIR" ]]; then
    exit 0
fi

CURRENT_ROUND=$(get_current_round "$ACTIVE_LOOP_DIR/state.md")

# ========================================
# Extract and Validate Round Number
# ========================================

CLAUDE_ROUND=""
if [[ "$TARGET_FILE" =~ round-([0-9]+)-(summary|todos|prompt)\.md ]]; then
    CLAUDE_ROUND="${BASH_REMATCH[1]}"
fi

CORRECT_PATH="$ACTIVE_LOOP_DIR/round-${CURRENT_ROUND}-${FILE_TYPE}.md"

if [[ -n "$CLAUDE_ROUND" ]] && [[ "$CLAUDE_ROUND" != "$CURRENT_ROUND" ]]; then
    cat >&2 << EOF
# Bash Write Blocked: Wrong Round Number

You are trying to write to \`round-${CLAUDE_ROUND}-${FILE_TYPE}.md\`, but the current round is **${CURRENT_ROUND}**.

**Use the Write tool with**: \`$CORRECT_PATH\`

Do NOT bypass Write validation with Bash commands.
EOF
    exit 2
fi

# Block any Bash write to loop files (use Write tool instead)
cat >&2 << EOF
# Bash Write Blocked: Use Write Tool

Do not use Bash to write ${FILE_TYPE} files.

**Use the Write tool with**: \`$CORRECT_PATH\`
EOF
exit 2
