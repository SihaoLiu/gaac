#!/bin/bash
#
# PreToolUse Hook: Validate Read access for loop-with-codex-review files
#
# This hook intercepts Read tool calls and prevents Claude from reading
# wrong round's prompt or summary files, which can cause confusion.
#
# Problem: Claude sometimes tries to read old round files (e.g., round-2-prompt.md
# when current round is 4), which may contain outdated information.
#
# Solution: Block reading wrong round files with a helpful message that suggests
# using `cat` command if the information is really needed.
#

set -euo pipefail

# ========================================
# Read Hook Input
# ========================================

HOOK_INPUT=$(cat)

# Parse the JSON input using jq
TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name // ""')

# Only process Read tool calls
if [[ "$TOOL_NAME" != "Read" ]]; then
    exit 0
fi

FILE_PATH=$(echo "$HOOK_INPUT" | jq -r '.tool_input.file_path // ""')

# ========================================
# Check if this is a loop-related file
# ========================================

# Pattern: anything that contains .gaac-loop.local and round-*-summary.md or round-*-prompt.md
if ! echo "$FILE_PATH" | grep -q '\.gaac-loop\.local/'; then
    # Not a loop file, allow normally
    exit 0
fi

# Check if it's a round-specific file (prompt or summary)
if ! echo "$FILE_PATH" | grep -qE 'round-[0-9]+-(summary|prompt)\.md$'; then
    # Not a round file we care about (could be state.md, codex logs, etc.)
    exit 0
fi

# ========================================
# Find Active Loop Directory
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
            echo "${dir%/}"
            return
        fi
    done
    echo ""
}

ACTIVE_LOOP_DIR=$(find_active_loop)

# If no active loop, allow the read
if [[ -z "$ACTIVE_LOOP_DIR" ]]; then
    exit 0
fi

STATE_FILE="$ACTIVE_LOOP_DIR/state.md"

# ========================================
# Extract Round Number from state.md
# ========================================

FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE" 2>/dev/null || echo "")
CURRENT_ROUND=$(echo "$FRONTMATTER" | grep '^current_round:' | sed 's/current_round: *//' | tr -d ' ')
CURRENT_ROUND="${CURRENT_ROUND:-0}"

# ========================================
# Extract Round Number from File Path
# ========================================

if [[ "$FILE_PATH" =~ round-([0-9]+)-(summary|prompt)\.md$ ]]; then
    CLAUDE_ROUND="${BASH_REMATCH[1]}"
    FILE_TYPE="${BASH_REMATCH[2]}"
else
    # Can't extract round, allow normally
    exit 0
fi

# ========================================
# Validate Round Number
# ========================================

# Allow reading current round files
if [[ "$CLAUDE_ROUND" == "$CURRENT_ROUND" ]]; then
    exit 0
fi

# Block reading wrong round files
REASON="# Wrong Round File

You are trying to read \`round-${CLAUDE_ROUND}-${FILE_TYPE}.md\`, but the current round is **${CURRENT_ROUND}**.

**Current round files**:
- Prompt: \`$ACTIVE_LOOP_DIR/round-${CURRENT_ROUND}-prompt.md\`
- Summary: \`$ACTIVE_LOOP_DIR/round-${CURRENT_ROUND}-summary.md\`

Information in other rounds' files may be **outdated or irrelevant** to your current task.

If you absolutely need to read old round files for reference, you can use the \`cat\` command in Bash:
\`\`\`bash
cat $FILE_PATH
\`\`\`

However, please focus on the current round's requirements and avoid confusion from old context."

echo "$REASON" >&2
exit 2
