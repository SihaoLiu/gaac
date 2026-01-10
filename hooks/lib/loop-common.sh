#!/bin/bash
#
# Common functions for loop-with-codex-review hooks
#
# This library provides shared functionality used by:
# - loop-read-validator.sh
# - loop-write-validator.sh
# - loop-bash-validator.sh
#

# Find the most recent active loop directory
# Outputs the directory path to stdout, or empty string if none found
find_active_loop() {
    local loop_base_dir="$1"

    if [[ ! -d "$loop_base_dir" ]]; then
        echo ""
        return
    fi

    # Find directories with state.md, sorted by name (timestamp) descending
    for dir in $(ls -1dr "$loop_base_dir"/*/ 2>/dev/null); do
        if [[ -f "$dir/state.md" ]]; then
            echo "${dir%/}"
            return
        fi
    done
    echo ""
}

# Extract current round number from state.md
# Outputs the round number to stdout, defaults to 0
get_current_round() {
    local state_file="$1"

    local frontmatter
    frontmatter=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$state_file" 2>/dev/null || echo "")

    local current_round
    current_round=$(echo "$frontmatter" | grep '^current_round:' | sed 's/current_round: *//' | tr -d ' ')

    echo "${current_round:-0}"
}

# Convert a string to lowercase
to_lower() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

# Check if a path (lowercase) matches a round file pattern
# Usage: is_round_file "$lowercase_path" "summary|prompt|todos"
is_round_file_type() {
    local path_lower="$1"
    local file_type="$2"

    echo "$path_lower" | grep -qE "round-[0-9]+-${file_type}\\.md\$"
}

# Extract round number from a filename
# Usage: extract_round_number "round-5-summary.md"
# Outputs the round number or empty string
extract_round_number() {
    local filename="$1"
    local filename_lower
    filename_lower=$(to_lower "$filename")

    if [[ "$filename_lower" =~ round-([0-9]+)-(summary|prompt|todos)\.md$ ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

# Standard message for blocking todos file access
# Usage: todos_blocked_message "Read|Write|Bash"
todos_blocked_message() {
    local action="$1"

    cat << 'EOF'
# Todos File Access Blocked

Do NOT create or access `round-*-todos.md` files.

**Use the native TodoWrite tool instead.**

The native todo tools provide proper state tracking visible in the UI and
integration with Claude Code's task management system.
EOF
}

# Standard message for blocking prompt file writes
prompt_write_blocked_message() {
    cat << 'EOF'
# Prompt File Write Blocked

You cannot write to `round-*-prompt.md` files.

**Prompt files contain instructions FROM Codex TO you (Claude).**

You cannot modify your own instructions. Your job is to:
1. Read the current round's prompt file for instructions
2. Execute the tasks described in the prompt
3. Write your results to the summary file

If the prompt contains errors, document this in your summary file.
EOF
}
