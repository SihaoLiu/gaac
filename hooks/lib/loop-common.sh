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
# Only checks the newest directory - older directories are ignored even if they have state.md
# This prevents "zombie" loops from being revived after abnormal exits
# Outputs the directory path to stdout, or empty string if none found
find_active_loop() {
    local loop_base_dir="$1"

    if [[ ! -d "$loop_base_dir" ]]; then
        echo ""
        return
    fi

    # Get the newest directory (by timestamp name, descending)
    local newest_dir
    newest_dir=$(ls -1d "$loop_base_dir"/*/ 2>/dev/null | sort -r | head -1)

    if [[ -n "$newest_dir" ]] && [[ -f "${newest_dir}state.md" ]]; then
        # Remove trailing slash to avoid double slashes in paths
        echo "${newest_dir%/}"
    else
        echo ""
    fi
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

# Standard message for blocking state file modifications
state_file_blocked_message() {
    cat << 'EOF'
# State File Modification Blocked

You cannot modify `state.md`. This file is managed by the loop system.

The state file contains:
- Current round number
- Max iterations
- Codex configuration

Modifying it would corrupt the loop state.
EOF
}

# Standard message for blocking summary file modifications via Bash
# Usage: summary_bash_blocked_message "$correct_summary_path"
summary_bash_blocked_message() {
    local correct_path="$1"

    cat << EOF
# Bash Write Blocked: Use Write or Edit Tool

Do not use Bash commands to modify summary files.

**Use the Write or Edit tool instead**: \`$correct_path\`

Bash commands like cat, echo, sed, awk, etc. bypass the validation hooks.
Please use the proper tools to ensure correct round number validation.
EOF
}

# Standard message for blocking goal-tracker modifications via Bash in Round 0
# Usage: goal_tracker_bash_blocked_message "$correct_goal_tracker_path"
goal_tracker_bash_blocked_message() {
    local correct_path="$1"

    cat << EOF
# Bash Write Blocked: Use Write or Edit Tool

Do not use Bash commands to modify goal-tracker.md.

**Use the Write or Edit tool instead**: \`$correct_path\`

Bash commands like cat, echo, sed, awk, etc. bypass the validation hooks.
Please use the proper tools to modify the Goal Tracker.
EOF
}

# Check if a path (lowercase) targets goal-tracker.md
is_goal_tracker_path() {
    local path_lower="$1"
    echo "$path_lower" | grep -qE 'goal-tracker\.md$'
}

# Check if a path (lowercase) targets state.md
is_state_file_path() {
    local path_lower="$1"
    echo "$path_lower" | grep -qE 'state\.md$'
}

# Check if a path is inside .gaac-loop.local directory
is_in_gaac_loop_dir() {
    local path="$1"
    echo "$path" | grep -q '\.gaac-loop\.local/'
}

# Check if a shell command attempts to modify a file matching the given pattern
# Usage: command_modifies_file "$command_lower" "goal-tracker\.md"
# Returns 0 if the command tries to modify the file, 1 otherwise
command_modifies_file() {
    local command_lower="$1"
    local file_pattern="$2"

    local patterns=(
        ">[[:space:]]*[^[:space:]]*${file_pattern}"
        "tee[[:space:]]+(-a[[:space:]]+)?[^[:space:]]*${file_pattern}"
        "sed[[:space:]]+-i[^|]*${file_pattern}"
        "awk[[:space:]]+-i[[:space:]]+inplace[^|]*${file_pattern}"
        "perl[[:space:]]+-[^[:space:]]*i[^|]*${file_pattern}"
        "(mv|cp)[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]*${file_pattern}"
        "dd[[:space:]].*of=[^[:space:]]*${file_pattern}"
    )

    for pattern in "${patterns[@]}"; do
        if echo "$command_lower" | grep -qE "$pattern"; then
            return 0
        fi
    done
    return 1
}

# ========================================
# Module Rules Loading Functions
# ========================================

# Module rules file name
MODULE_RULES_FILENAME="MODULE_RULES.md"

# Find all MODULE_RULES.md files from a file's directory up to project root
# Usage: find_module_rules_for_file "/path/to/file.js" "/project/root"
# Outputs newline-separated list of rule file paths (from most specific to root)
find_module_rules_for_file() {
    local file_path="$1"
    local project_root="$2"

    # Get the directory containing the file
    local current_dir
    if [[ -f "$file_path" ]]; then
        current_dir=$(dirname "$file_path")
    else
        current_dir="$file_path"
    fi

    # Normalize paths to absolute
    current_dir=$(cd "$current_dir" 2>/dev/null && pwd) || return
    project_root=$(cd "$project_root" 2>/dev/null && pwd) || return

    local rules_files=""

    # Walk up from file's directory to project root
    while [[ "$current_dir" == "$project_root"* ]]; do
        local rules_file="$current_dir/$MODULE_RULES_FILENAME"
        if [[ -f "$rules_file" ]]; then
            if [[ -n "$rules_files" ]]; then
                rules_files="$rules_files"$'\n'"$rules_file"
            else
                rules_files="$rules_file"
            fi
        fi

        # Move to parent directory
        local parent_dir
        parent_dir=$(dirname "$current_dir")

        # Stop if we've reached the project root or can't go higher
        if [[ "$current_dir" == "$project_root" ]] || [[ "$parent_dir" == "$current_dir" ]]; then
            break
        fi

        current_dir="$parent_dir"
    done

    echo "$rules_files"
}

# Collect all unique MODULE_RULES.md files for files changed according to git status
# Usage: collect_module_rules_for_git_changes "/project/root"
# Outputs newline-separated list of unique rule file paths
collect_module_rules_for_git_changes() {
    local project_root="$1"

    # Get list of changed files from git status
    local git_status
    git_status=$(cd "$project_root" && git status --porcelain 2>/dev/null) || return

    local all_rules=""
    local seen_rules=""

    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Extract filename (skip first 3 chars: "XY ")
        local filename="${line#???}"

        # Handle renames: "old -> new" format
        case "$filename" in
            *" -> "*) filename="${filename##* -> }" ;;
        esac

        # Skip deleted files
        [[ ! -e "$project_root/$filename" ]] && continue

        # Find module rules for this file
        local rules
        rules=$(find_module_rules_for_file "$project_root/$filename" "$project_root")

        # Add unique rules to the collection
        while IFS= read -r rule_file; do
            [[ -z "$rule_file" ]] && continue

            # Check if already seen (simple dedup)
            if [[ "$seen_rules" != *"$rule_file"* ]]; then
                seen_rules="$seen_rules:$rule_file"
                if [[ -n "$all_rules" ]]; then
                    all_rules="$all_rules"$'\n'"$rule_file"
                else
                    all_rules="$rule_file"
                fi
            fi
        done <<< "$rules"
    done <<< "$git_status"

    echo "$all_rules"
}

# Build module rules section for Codex review prompt
# Usage: build_module_rules_prompt_section "/project/root"
# Outputs formatted markdown section with all relevant module rules
build_module_rules_prompt_section() {
    local project_root="$1"

    # Collect all relevant module rules
    local rules_files
    rules_files=$(collect_module_rules_for_git_changes "$project_root")

    # If no rules found, return empty
    if [[ -z "$rules_files" ]]; then
        return
    fi

    # Count number of rules files
    local rules_count
    rules_count=$(echo "$rules_files" | grep -c '^' || echo "0")

    # Build the prompt section
    cat << 'RULES_HEADER'
## Module Rules (Per-Module Code Ownership Standards)

**CRITICAL**: The following module-specific rules define the acceptance standards for code changes.
As a reviewer, you must adopt a **"selfish module owner"** stance for each module:

- You are **extremely unwilling** to accept changes that violate a module's core principles
- You are **extremely unwilling** to accept changes that increase a module's conceptual complexity
- You are **extremely unwilling** to accept changes that harm a module's long-term maintainability
- Only **exceptionally strong justification** can override these concerns

For each modified file, the relevant module rules apply hierarchically (from most specific directory to root).

RULES_HEADER

    echo "### Applicable Module Rules ($rules_count rule file(s) found)"
    echo ""

    # Include each rules file
    while IFS= read -r rule_file; do
        [[ -z "$rule_file" ]] && continue

        # Get relative path from project root
        local rel_path="${rule_file#$project_root/}"

        echo "#### Rules from \`$rel_path\`"
        echo ""
        echo "\`\`\`markdown"
        cat "$rule_file"
        echo "\`\`\`"
        echo ""
    done <<< "$rules_files"

    cat << 'RULES_FOOTER'
### Review Instructions for Module Rules

When reviewing changes, for each modified module:
1. **Identify** which MODULE_RULES.md files apply to the changed files
2. **Verify** the changes comply with each applicable rule
3. **Flag violations** as high-priority issues requiring immediate attention
4. **Require justification** for any rule exceptions (document in your review)
5. **Be skeptical** of changes that "temporarily" violate rules - temporary often becomes permanent

RULES_FOOTER
}

# Standard message for blocking goal-tracker modifications after Round 0
# Usage: goal_tracker_blocked_message "$current_round" "$summary_file_path"
goal_tracker_blocked_message() {
    local current_round="$1"
    local summary_file="$2"

    cat << EOF
# Goal Tracker Modification Blocked (Round ${current_round})

After Round 0, **only Codex can modify the Goal Tracker**.

You CANNOT directly modify \`goal-tracker.md\` via Write, Edit, or Bash commands.

## How to Request Changes

Include a **"Goal Tracker Update Request"** section in your summary file:
\`$summary_file\`

Use this format:
\`\`\`markdown
## Goal Tracker Update Request

### Requested Changes:
- [E.g., "Mark Task X as completed with evidence: tests pass"]
- [E.g., "Add to Open Issues: discovered Y needs addressing"]
- [E.g., "Plan Evolution: changed approach from A to B because..."]

### Justification:
[Explain why these changes are needed and how they serve the Ultimate Goal]
\`\`\`

Codex will review your request and update the Goal Tracker if the changes are justified.
EOF
}
