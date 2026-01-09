#!/bin/bash
#
# PreToolUse Hook: Validate and correct Write paths for loop-with-codex-review
#
# This hook intercepts Write tool calls and ensures summary files are written
# to the correct absolute path within the project's .gaac-loop.local directory.
#
# Problem 1: Claude sometimes hallucinates paths during long conversations,
# writing to ~/.gaac-loop.local/ instead of $PROJECT_ROOT/.gaac-loop.local/
#
# Problem 2: Claude sometimes writes to wrong round number (e.g., round-5-summary.md
# when current round is 4), causing the Codex review to fail.
#
# Solution: This hook detects loop-related files and:
# - Auto-corrects wrong directory paths
# - Validates round numbers and either corrects or rejects with guidance
#

set -euo pipefail

# ========================================
# Read Hook Input
# ========================================

HOOK_INPUT=$(cat)

# Parse the JSON input using jq
TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name // ""')

# Only process Write tool calls
if [[ "$TOOL_NAME" != "Write" ]]; then
    exit 0
fi

FILE_PATH=$(echo "$HOOK_INPUT" | jq -r '.tool_input.file_path // ""')

# ========================================
# Check if this is a loop-related file
# ========================================

# Pattern: anything that contains .gaac-loop.local and round-*-summary.md or round-*-prompt.md
# These are the files Claude writes during loop-with-codex-review
if ! echo "$FILE_PATH" | grep -q '\.gaac-loop\.local/'; then
    # Not a loop file, allow normally
    exit 0
fi

# Check if it's a loop file we care about (summary files only for round validation)
# We only validate round numbers for summary files, not prompt files (which are written by the hook)
IS_SUMMARY_FILE=false
if echo "$FILE_PATH" | grep -qE 'round-[0-9]+-summary\.md$'; then
    IS_SUMMARY_FILE=true
fi

# Allow non-summary loop files without round validation
if [[ "$IS_SUMMARY_FILE" == "false" ]]; then
    # For prompt files and state files, we don't validate round numbers
    # But we still validate the path
    if ! echo "$FILE_PATH" | grep -qE 'round-[0-9]+-prompt\.md$|state\.md$'; then
        exit 0
    fi
fi

# ========================================
# Find Active Loop Directory
# ========================================

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
LOOP_BASE_DIR="$PROJECT_ROOT/.gaac-loop.local"

# Find the most recent active loop directory (same logic as stop hook)
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

# If no active loop, allow the write (maybe Claude is cleaning up or something)
if [[ -z "$ACTIVE_LOOP_DIR" ]]; then
    exit 0
fi

STATE_FILE="$ACTIVE_LOOP_DIR/state.md"

# ========================================
# Extract and Validate Path Components
# ========================================

# Extract the timestamp and filename from the path Claude is trying to write to
# Pattern: .gaac-loop.local/<timestamp>/<filename>
if [[ "$FILE_PATH" =~ \.gaac-loop\.local/([0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2})/(.+)$ ]]; then
    CLAUDE_TIMESTAMP="${BASH_REMATCH[1]}"
    CLAUDE_FILENAME="${BASH_REMATCH[2]}"
elif [[ "$FILE_PATH" =~ \.gaac-loop\.local/(.+)$ ]]; then
    # Fallback: just extract everything after .gaac-loop.local/
    REMAINING="${BASH_REMATCH[1]}"
    # Try to split into timestamp/filename
    if [[ "$REMAINING" =~ ^([^/]+)/(.+)$ ]]; then
        CLAUDE_TIMESTAMP="${BASH_REMATCH[1]}"
        CLAUDE_FILENAME="${BASH_REMATCH[2]}"
    else
        # No timestamp, just a filename
        CLAUDE_TIMESTAMP=""
        CLAUDE_FILENAME="$REMAINING"
    fi
else
    # Can't parse the path, allow normally
    exit 0
fi

# ========================================
# Validate Round Number (for summary files)
# ========================================

CORRECT_FILENAME="$CLAUDE_FILENAME"
NEEDS_ROUND_CORRECTION=false

if [[ "$IS_SUMMARY_FILE" == "true" ]]; then
    # Extract round number from state.md
    FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE" 2>/dev/null || echo "")
    CURRENT_ROUND=$(echo "$FRONTMATTER" | grep '^current_round:' | sed 's/current_round: *//' | tr -d ' ')
    CURRENT_ROUND="${CURRENT_ROUND:-0}"

    # Extract round number from the filename Claude is trying to write
    if [[ "$CLAUDE_FILENAME" =~ ^round-([0-9]+)-summary\.md$ ]]; then
        CLAUDE_ROUND="${BASH_REMATCH[1]}"
    else
        # Can't extract round, allow normally
        CLAUDE_ROUND="$CURRENT_ROUND"
    fi

    # Check if round numbers match
    if [[ "$CLAUDE_ROUND" != "$CURRENT_ROUND" ]]; then
        CORRECT_FILENAME="round-${CURRENT_ROUND}-summary.md"
        CORRECT_SUMMARY_PATH="$ACTIVE_LOOP_DIR/$CORRECT_FILENAME"

        # Check if the correct summary file already exists
        if [[ -f "$CORRECT_SUMMARY_PATH" ]]; then
            # Summary for current round already exists
            # REJECT and tell Claude to read and update the existing file
            REASON="# Wrong Round Number

You are trying to write to \`round-${CLAUDE_ROUND}-summary.md\`, but the current round is **${CURRENT_ROUND}**.

The summary file for round ${CURRENT_ROUND} already exists at:
\`\`\`
$CORRECT_SUMMARY_PATH
\`\`\`

**Required Action**:
1. Read the existing summary file: \`$CORRECT_SUMMARY_PATH\`
2. Update it with your new progress instead of creating a new file
3. Do NOT increment the round number yourself - the loop hook manages round progression

Remember: Only write to \`round-${CURRENT_ROUND}-summary.md\`. The round number advances only after Codex review."

            echo "$REASON" >&2
            exit 2
        else
            # Summary doesn't exist yet, auto-correct the filename
            NEEDS_ROUND_CORRECTION=true
        fi
    fi
fi

# ========================================
# Build Correct Path
# ========================================

# The correct path should be: $ACTIVE_LOOP_DIR/$CORRECT_FILENAME
CORRECT_PATH="$ACTIVE_LOOP_DIR/$CORRECT_FILENAME"

# Check if everything is already correct (path and round)
if [[ "$FILE_PATH" == "$CORRECT_PATH" ]] && [[ "$NEEDS_ROUND_CORRECTION" == "false" ]]; then
    # Path and round are correct, allow normally
    exit 0
fi

# ========================================
# Auto-Correct the Path (and optionally round)
# ========================================

# Output JSON to auto-approve with corrected path
# This allows the write to proceed with the correct absolute path

CONTENT=$(echo "$HOOK_INPUT" | jq -r '.tool_input.content // ""')

# Build the reason message
if [[ "$NEEDS_ROUND_CORRECTION" == "true" ]]; then
    REASON="Path and round corrected: round-${CLAUDE_ROUND} -> round-${CURRENT_ROUND}, path: $FILE_PATH -> $CORRECT_PATH"
else
    REASON="Path corrected from $FILE_PATH to $CORRECT_PATH"
fi

# Build the corrected output
jq -n \
    --arg file_path "$CORRECT_PATH" \
    --arg content "$CONTENT" \
    --arg reason "$REASON" \
    '{
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": $reason,
            "updatedInput": {
                "file_path": $file_path,
                "content": $content
            }
        }
    }'

exit 0
