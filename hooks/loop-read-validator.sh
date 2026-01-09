#!/bin/bash
#
# PreToolUse Hook: Validate Read access for loop-with-codex-review files
#
# This hook intercepts Read tool calls and prevents Claude from reading
# wrong round's prompt or summary files, which can cause confusion.
#
# Problem 1: Claude sometimes tries to read old round files (e.g., round-2-prompt.md
# when current round is 4), which may contain outdated information.
#
# Problem 2: Claude sometimes tries to read round files from wrong locations
# (e.g., .claude/round-9-summary.md instead of .gaac-loop.local/)
#
# Problem 3: Claude sometimes tries to read from old session directories
# (e.g., .gaac-loop.local/2026-01-08_10-00-00/ when active is 2026-01-09_12-00-00/)
#
# Solution: Block reading wrong files with a helpful message that suggests
# using `cat` command if really needed.
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

# Check if it's a round file (regardless of path)
IS_ROUND_FILE=false
CLAUDE_FILENAME=""
if echo "$FILE_PATH" | grep -qE 'round-[0-9]+-(summary|prompt)\.md$'; then
    IS_ROUND_FILE=true
    CLAUDE_FILENAME=$(basename "$FILE_PATH")
fi

# Check if path contains .gaac-loop.local
IN_GAAC_LOOP_DIR=false
if echo "$FILE_PATH" | grep -q '\.gaac-loop\.local/'; then
    IN_GAAC_LOOP_DIR=true
fi

# If not a round file, allow normally
if [[ "$IS_ROUND_FILE" == "false" ]]; then
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

if [[ "$CLAUDE_FILENAME" =~ ^round-([0-9]+)-(summary|prompt)\.md$ ]]; then
    CLAUDE_ROUND="${BASH_REMATCH[1]}"
    FILE_TYPE="${BASH_REMATCH[2]}"
else
    # Can't extract round, allow normally
    exit 0
fi

# ========================================
# Handle Files Outside .gaac-loop.local
# ========================================

if [[ "$IN_GAAC_LOOP_DIR" == "false" ]]; then
    # Claude is trying to read a round file from wrong location
    CORRECT_PATH="$ACTIVE_LOOP_DIR/round-${CURRENT_ROUND}-${FILE_TYPE}.md"

    REASON="# Wrong File Location

You are trying to read \`$FILE_PATH\`, but loop files are located in \`$ACTIVE_LOOP_DIR/\`.

**Current round files**:
- Prompt: \`$ACTIVE_LOOP_DIR/round-${CURRENT_ROUND}-prompt.md\`
- Summary: \`$ACTIVE_LOOP_DIR/round-${CURRENT_ROUND}-summary.md\`

The file you're trying to read is in the wrong location and may contain stale or incorrect data.

If you need the current round's ${FILE_TYPE}, read:
\`\`\`
$CORRECT_PATH
\`\`\`

If you absolutely need to read this file for reference, you can use the \`cat\` command in Bash:
\`\`\`bash
cat $FILE_PATH
\`\`\`"

    echo "$REASON" >&2
    exit 2
fi

# ========================================
# Validate Round Number
# ========================================

if [[ "$CLAUDE_ROUND" != "$CURRENT_ROUND" ]]; then
    # Wrong round number
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
fi

# ========================================
# Validate Directory Path (timestamp directory)
# ========================================

# Build the correct path for comparison
CORRECT_PATH="$ACTIVE_LOOP_DIR/$CLAUDE_FILENAME"

# Check if the path matches the active loop directory
if [[ "$FILE_PATH" != "$CORRECT_PATH" ]]; then
    # Wrong directory (e.g., old session timestamp or home directory hallucination)
    REASON="# Wrong Directory Path

You are trying to read:
\`\`\`
$FILE_PATH
\`\`\`

But the active loop directory is:
\`\`\`
$ACTIVE_LOOP_DIR/
\`\`\`

**Correct path**:
\`\`\`
$CORRECT_PATH
\`\`\`

You may be reading from an old session. Please read from the correct path above.

If you absolutely need to read this file for reference, you can use the \`cat\` command in Bash:
\`\`\`bash
cat $FILE_PATH
\`\`\`"

    echo "$REASON" >&2
    exit 2
fi

# Path is correct, allow the read
exit 0
