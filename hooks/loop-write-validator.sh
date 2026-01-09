#!/bin/bash
#
# PreToolUse Hook: Validate and correct Write paths for loop-with-codex-review
#
# This hook intercepts Write tool calls and ensures summary files are written
# to the correct absolute path within the project's .gaac-loop.local directory.
#
# Problem: Claude sometimes hallucinates paths during long conversations,
# writing to ~/.gaac-loop.local/ instead of $PROJECT_ROOT/.gaac-loop.local/
#
# Solution: This hook detects loop-related files and auto-corrects the path.
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

# Check if it's a loop file we care about (summary, prompt, or state files)
if ! echo "$FILE_PATH" | grep -qE 'round-[0-9]+-summary\.md$|round-[0-9]+-prompt\.md$|state\.md$'; then
    # Not a recognized loop file pattern, allow normally
    exit 0
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

# ========================================
# Extract and Validate Path Components
# ========================================

# Extract the timestamp and filename from the path Claude is trying to write to
# Pattern: .gaac-loop.local/<timestamp>/<filename>
TIMESTAMP_AND_FILE=""
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

# Extract actual timestamp from active loop directory
ACTIVE_TIMESTAMP=$(basename "$ACTIVE_LOOP_DIR")

# ========================================
# Build Correct Path
# ========================================

# The correct path should be: $ACTIVE_LOOP_DIR/$CLAUDE_FILENAME
# We preserve Claude's filename but use the active loop's directory
CORRECT_PATH="$ACTIVE_LOOP_DIR/$CLAUDE_FILENAME"

# Check if the path is already correct
if [[ "$FILE_PATH" == "$CORRECT_PATH" ]]; then
    # Path is correct, allow normally
    exit 0
fi

# ========================================
# Auto-Correct the Path
# ========================================

# Output JSON to auto-approve with corrected path
# This allows the write to proceed with the correct absolute path

CONTENT=$(echo "$HOOK_INPUT" | jq -r '.tool_input.content // ""')

# Build the corrected output
# Note: We need to re-encode content properly for JSON
REASON="Path corrected from $FILE_PATH to $CORRECT_PATH"
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
