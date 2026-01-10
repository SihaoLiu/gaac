#!/bin/zsh
# gaac.sh - GAAC (Git-Assisted AI Coding) shell utilities
# Part of rc.d configuration

# Monitor the latest Codex run log from .gaac-loop.local
# Automatically switches to newer logs when they appear
# Features a fixed status bar at the top showing session info
_gaac_monitor_codex() {
    local loop_dir=".gaac-loop.local"
    local current_file=""
    local current_session_dir=""
    local check_interval=2  # seconds between checking for new files
    local status_bar_height=10  # number of lines for status bar (goal tracker + git status)

    # Check if .gaac-loop.local exists
    if [[ ! -d "$loop_dir" ]]; then
        echo "Error: $loop_dir directory not found in current directory"
        echo "Are you in a project with an active gaac loop?"
        return 1
    fi

    # Function to find the latest session directory
    _find_latest_session() {
        local latest_session=""
        for session_dir in "$loop_dir"/*(/N); do
            local session_name="${session_dir:t}"
            if [[ "$session_name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]; then
                if [[ -z "$latest_session" ]] || [[ "$session_name" > "${latest_session:t}" ]]; then
                    latest_session="$session_dir"
                fi
            fi
        done
        echo "$latest_session"
    }

    # Function to find the latest codex log file
    # Log files are now in $HOME/.cache/gaac/<sanitized-project-path>/<timestamp>/ to avoid context pollution
    _find_latest_codex_log() {
        local latest=""
        local latest_session=""
        local latest_round=-1
        local cache_base="$HOME/.cache/gaac"

        # Get current project's absolute path and sanitize it
        # This matches the sanitization in loop-codex-stop-hook.sh
        local project_root="$(pwd)"
        local sanitized_project=$(echo "$project_root" | sed 's/[^a-zA-Z0-9._-]/-/g' | sed 's/--*/-/g')
        local project_cache_dir="$cache_base/$sanitized_project"

        # First, find valid session timestamps from local .gaac-loop.local
        for session_dir in "$loop_dir"/*(/N); do
            local session_name="${session_dir:t}"
            if [[ ! "$session_name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]; then
                continue
            fi

            # Look for log files in the project-specific cache directory with matching timestamp
            local cache_dir="$project_cache_dir/$session_name"
            if [[ ! -d "$cache_dir" ]]; then
                continue
            fi

            for log_file in "$cache_dir"/round-*-codex-run.log(N); do
                if [[ -f "$log_file" ]]; then
                    local basename="${log_file:t}"
                    local round_num="${basename#round-}"
                    round_num="${round_num%%-codex-run.log}"

                    if [[ -z "$latest" ]] || \
                       [[ "$session_name" > "$latest_session" ]] || \
                       [[ "$session_name" == "$latest_session" && "$round_num" -gt "$latest_round" ]]; then
                        latest="$log_file"
                        latest_session="$session_name"
                        latest_round="$round_num"
                    fi
                fi
            done
        done

        echo "$latest"
    }

    # Parse state.md and return values
    _parse_state_md() {
        local state_file="$1"
        if [[ ! -f "$state_file" ]]; then
            echo "N/A|N/A|N/A|N/A|N/A|N/A"
            return
        fi

        local current_round=$(grep -E "^current_round:" "$state_file" 2>/dev/null | sed 's/current_round: *//')
        local max_iterations=$(grep -E "^max_iterations:" "$state_file" 2>/dev/null | sed 's/max_iterations: *//')
        local codex_model=$(grep -E "^codex_model:" "$state_file" 2>/dev/null | sed 's/codex_model: *//')
        local codex_effort=$(grep -E "^codex_effort:" "$state_file" 2>/dev/null | sed 's/codex_effort: *//')
        local started_at=$(grep -E "^started_at:" "$state_file" 2>/dev/null | sed 's/started_at: *//')
        local plan_file=$(grep -E "^plan_file:" "$state_file" 2>/dev/null | sed 's/plan_file: *//')

        echo "${current_round:-N/A}|${max_iterations:-N/A}|${codex_model:-N/A}|${codex_effort:-N/A}|${started_at:-N/A}|${plan_file:-N/A}"
    }

    # Parse goal-tracker.md and return summary values
    # Returns: total_acs|completed_acs|active_tasks|completed_tasks|deferred_tasks|open_issues|goal_summary
    _parse_goal_tracker() {
        local tracker_file="$1"
        if [[ ! -f "$tracker_file" ]]; then
            echo "0|0|0|0|0|0|No goal tracker"
            return
        fi

        # Helper: count table rows in a section (excludes headers starting with | *Header or |-)
        _count_section_rows() {
            local section_start="$1"
            local section_end="$2"
            local extra_filter="${3:-}"
            sed -n "/${section_start}/,/${section_end}/p" "$tracker_file" \
                | grep -E '^\|[^|]+\|' \
                | grep -v '^\| *[A-Za-z]* *|' \
                | grep -v '^\|-' \
                ${extra_filter:+| grep -E "$extra_filter"} \
                | wc -l | tr -d ' '
        }

        # Count Acceptance Criteria (rows starting with | AC in the AC section)
        local total_acs=$(sed -n '/### Acceptance Criteria/,/^---$/p' "$tracker_file" | grep -cE '^\|\s*AC' || echo 0)

        # Count Active Tasks (pending + in_progress status)
        local active_tasks=$(sed -n '/#### Active Tasks/,/^###/p' "$tracker_file" | grep -cE '^\|[^|]+\|[^|]+\|[^|]*(pending|in_progress)[^|]*\|' || echo 0)

        # Count Completed tasks (table rows in Completed section, excluding header)
        local completed_tasks=$(_count_section_rows '### Completed and Verified' '^###')
        completed_tasks=${completed_tasks:-0}

        # Count verified ACs (unique AC entries in Completed section)
        local completed_acs=$(sed -n '/### Completed and Verified/,/^###/p' "$tracker_file" \
            | grep -oE '^\|\s*AC[0-9]+' | sort -u | wc -l | tr -d ' ')
        completed_acs=${completed_acs:-0}

        # Count Deferred tasks
        local deferred_tasks=$(_count_section_rows '### Explicitly Deferred' '^###')
        deferred_tasks=${deferred_tasks:-0}

        # Count Open Issues
        local open_issues=$(_count_section_rows '### Open Issues' '^$')
        open_issues=${open_issues:-0}

        # Extract Ultimate Goal summary (first content line after heading)
        local goal_summary=$(sed -n '/### Ultimate Goal/,/^###/p' "$tracker_file" \
            | grep -v '^###' | grep -v '^$' | grep -v '^\[To be' \
            | head -1 | sed 's/^[[:space:]]*//' | cut -c1-60)
        goal_summary="${goal_summary:-No goal defined}"

        echo "${total_acs}|${completed_acs}|${active_tasks}|${completed_tasks}|${deferred_tasks}|${open_issues}|${goal_summary}"
    }

    # Parse git status and return summary values
    # Returns: modified|added|deleted|untracked|insertions|deletions
    _parse_git_status() {
        # Check if we're in a git repo
        if ! git rev-parse --git-dir &>/dev/null 2>&1; then
            echo "0|0|0|0|0|0|not a git repo"
            return
        fi

        # Get porcelain status (fast, machine-readable)
        local git_status_output=$(git status --porcelain 2>/dev/null)

        # Count file states from status output
        local modified=0 added=0 deleted=0 untracked=0

        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local xy="${line:0:2}"
            case "$xy" in
                "??") ((untracked++)) ;;
                "A "* | " A"* | "AM"*) ((added++)) ;;
                "D "* | " D"*) ((deleted++)) ;;
                "M "* | " M"* | "MM"*) ((modified++)) ;;
                "R "* | " R"*) ((modified++)) ;;  # Renamed counts as modified
                *)
                    # Handle other cases (staged + unstaged combinations)
                    [[ "${xy:0:1}" == "M" || "${xy:1:1}" == "M" ]] && ((modified++))
                    [[ "${xy:0:1}" == "A" ]] && ((added++))
                    [[ "${xy:0:1}" == "D" || "${xy:1:1}" == "D" ]] && ((deleted++))
                    ;;
            esac
        done <<< "$git_status_output"

        # Get line changes (insertions/deletions) - diff of staged + unstaged
        local diffstat=$(git diff --shortstat HEAD 2>/dev/null || git diff --shortstat 2>/dev/null)
        local insertions=0 deletions=0

        if [[ -n "$diffstat" ]]; then
            # Parse: " 3 files changed, 45 insertions(+), 12 deletions(-)"
            insertions=$(echo "$diffstat" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo 0)
            deletions=$(echo "$diffstat" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo 0)
        fi
        insertions=${insertions:-0}
        deletions=${deletions:-0}

        echo "${modified}|${added}|${deleted}|${untracked}|${insertions}|${deletions}"
    }

    # Draw the status bar at the top
    _draw_status_bar() {
        local session_dir="$1"
        local log_file="$2"
        local state_file="$session_dir/state.md"
        local goal_tracker_file="$session_dir/goal-tracker.md"
        local term_width=$(tput cols)

        # Parse state.md into array (zsh array splitting on |)
        local -a state_parts
        state_parts=("${(@s:|:)$(_parse_state_md "$state_file")}")
        local current_round="${state_parts[1]}"
        local max_iterations="${state_parts[2]}"
        local codex_model="${state_parts[3]}"
        local codex_effort="${state_parts[4]}"
        local started_at="${state_parts[5]}"
        local plan_file="${state_parts[6]}"

        # Parse goal-tracker.md into array
        local -a goal_parts
        goal_parts=("${(@s:|:)$(_parse_goal_tracker "$goal_tracker_file")}")
        local total_acs="${goal_parts[1]}"
        local completed_acs="${goal_parts[2]}"
        local active_tasks="${goal_parts[3]}"
        local completed_tasks="${goal_parts[4]}"
        local deferred_tasks="${goal_parts[5]}"
        local open_issues="${goal_parts[6]}"
        local goal_summary="${goal_parts[7]}"

        # Parse git status into array
        local -a git_parts
        git_parts=("${(@s:|:)$(_parse_git_status)}")
        local git_modified="${git_parts[1]}"
        local git_added="${git_parts[2]}"
        local git_deleted="${git_parts[3]}"
        local git_untracked="${git_parts[4]}"
        local git_insertions="${git_parts[5]}"
        local git_deletions="${git_parts[6]}"

        # Format started_at for display
        local start_display="$started_at"
        if [[ "$started_at" != "N/A" ]]; then
            # Convert ISO format to more readable format
            start_display=$(echo "$started_at" | sed 's/T/ /; s/Z/ UTC/')
        fi

        # Truncate strings for display (label column is ~10 chars)
        local max_display_len=$((term_width - 12))
        local plan_display="$plan_file"
        local goal_display="$goal_summary"
        [[ ${#plan_file} -gt $max_display_len ]] && plan_display="...${plan_file: -$((max_display_len - 3))}"
        [[ ${#goal_summary} -gt $max_display_len ]] && goal_display="${goal_summary:0:$((max_display_len - 3))}..."

        # Save cursor position and move to top
        tput sc
        tput cup 0 0

        # ANSI color codes
        local green="\033[1;32m" yellow="\033[1;33m" cyan="\033[1;36m"
        local magenta="\033[1;35m" red="\033[1;31m" reset="\033[0m"
        local bg="\033[44m" bold="\033[1m" dim="\033[2m"
        local blue="\033[1;34m"

        # Clear status bar area (10 lines)
        tput cup 0 0
        for _ in {1..10}; do printf "%-${term_width}s\n" ""; done

        # Draw header and session info
        tput cup 0 0
        printf "${bg}${bold}%-${term_width}s${reset}\n" " GAAC Loop Monitor"
        printf "${cyan}Session:${reset}  ${session_dir:t}    ${cyan}Started:${reset} ${start_display}\n"
        printf "${green}Round:${reset}    ${bold}${current_round}${reset} / ${max_iterations}    ${yellow}Model:${reset} ${codex_model} (${codex_effort})\n"

        # Goal tracker progress line (color based on completion status)
        local ac_color="${green}"
        [[ "$completed_acs" -lt "$total_acs" ]] && ac_color="${yellow}"
        local issue_color="${dim}"
        [[ "$open_issues" -gt 0 ]] && issue_color="${red}"

        printf "${magenta}Goal:${reset}     ${goal_display}\n"
        printf "${magenta}Progress:${reset} ${ac_color}ACs: ${completed_acs}/${total_acs}${reset}  ${cyan}Tasks: ${active_tasks} active, ${completed_tasks} done${reset}"
        [[ "$deferred_tasks" -gt 0 ]] && printf "  ${yellow}${deferred_tasks} deferred${reset}"
        [[ "$open_issues" -gt 0 ]] && printf "  ${issue_color}Issues: ${open_issues}${reset}"
        printf "\n"

        # Git status line
        local git_total=$((git_modified + git_added + git_deleted))
        printf "${blue}Git:${reset}      "
        if [[ "$git_total" -eq 0 && "$git_untracked" -eq 0 ]]; then
            printf "${dim}clean${reset}"
        else
            [[ "$git_modified" -gt 0 ]] && printf "${yellow}~${git_modified}${reset} "
            [[ "$git_added" -gt 0 ]] && printf "${green}+${git_added}${reset} "
            [[ "$git_deleted" -gt 0 ]] && printf "${red}-${git_deleted}${reset} "
            [[ "$git_untracked" -gt 0 ]] && printf "${dim}?${git_untracked}${reset} "
            printf " ${green}+${git_insertions}${reset}/${red}-${git_deletions}${reset} lines"
        fi
        printf "\n"

        printf "${cyan}Plan:${reset}     ${plan_display}\n"
        printf "${cyan}Log:${reset}      ${log_file}\n"
        printf "%.s─" $(seq 1 $term_width)
        printf "\n"

        # Restore cursor position
        tput rc
    }

    # Setup terminal for split view
    _setup_terminal() {
        # Clear screen
        clear
        # Set scroll region (leave top lines for status bar)
        printf "\033[${status_bar_height};%dr" $(tput lines)
        # Move cursor to scroll region
        tput cup $status_bar_height 0
    }

    # Restore terminal to normal
    _restore_terminal() {
        # Reset scroll region to full screen
        printf "\033[r"
        # Move to bottom
        tput cup $(tput lines) 0
    }

    # Track PIDs for cleanup
    local tail_pid=""
    local monitor_running=true
    local cleanup_done=false

    # Cleanup function - called by TRAPINT
    _cleanup() {
        # Prevent multiple cleanup calls
        [[ "$cleanup_done" == "true" ]] && return
        cleanup_done=true
        monitor_running=false

        # Remove trap functions immediately to prevent re-triggering
        unfunction TRAPINT TRAPTERM 2>/dev/null

        # Kill background processes
        if [[ -n "$tail_pid" ]] && kill -0 $tail_pid 2>/dev/null; then
            kill $tail_pid 2>/dev/null
            wait $tail_pid 2>/dev/null
        fi

        _restore_terminal
        echo ""
        echo "Stopped monitoring."
    }

    # Use zsh TRAPINT function for reliable signal handling
    # Return 128+signal per Unix convention (130 for SIGINT, 143 for SIGTERM)
    TRAPINT() {
        _cleanup
        return $(( 128 + $1 ))
    }
    TRAPTERM() {
        _cleanup
        return $(( 128 + $1 ))
    }

    # Find initial file
    current_file=$(_find_latest_codex_log)
    current_session_dir=$(_find_latest_session)

    if [[ -z "$current_file" ]]; then
        echo "No codex-run.log files found. Waiting for first log..."
        while [[ -z "$current_file" ]] && [[ "$monitor_running" == "true" ]]; do
            sleep "$check_interval"
            current_file=$(_find_latest_codex_log)
            current_session_dir=$(_find_latest_session)
        done
        [[ "$monitor_running" != "true" ]] && { unfunction TRAPINT TRAPTERM 2>/dev/null; return 0; }
    fi

    # Setup terminal
    _setup_terminal

    # Track last read position for incremental reading
    local last_size=0
    local file_size=0

    # Main monitoring loop
    while [[ "$monitor_running" == "true" ]]; do
        # Draw status bar (check flag before expensive operation)
        [[ "$monitor_running" != "true" ]] && break
        _draw_status_bar "$current_session_dir" "$current_file"
        [[ "$monitor_running" != "true" ]] && break

        # Move cursor to scroll region
        tput cup $status_bar_height 0

        # Get initial file size
        last_size=$(stat -c%s "$current_file" 2>/dev/null || stat -f%z "$current_file" 2>/dev/null || echo 0)

        # Show existing content (last 50 lines)
        [[ "$monitor_running" != "true" ]] && break
        tail -n 50 "$current_file" 2>/dev/null

        # Incremental monitoring loop
        while [[ "$monitor_running" == "true" ]]; do
            sleep 0.5  # Check more frequently for smoother output
            [[ "$monitor_running" != "true" ]] && break

            # Update status bar (check flag before expensive operation)
            [[ "$monitor_running" != "true" ]] && break
            _draw_status_bar "$current_session_dir" "$current_file"
            [[ "$monitor_running" != "true" ]] && break

            # Check for new content in current file
            file_size=$(stat -c%s "$current_file" 2>/dev/null || stat -f%z "$current_file" 2>/dev/null || echo 0)
            if [[ "$file_size" -gt "$last_size" ]]; then
                # Read and display new content
                [[ "$monitor_running" != "true" ]] && break
                tail -c +$((last_size + 1)) "$current_file" 2>/dev/null
                last_size="$file_size"
            fi
            [[ "$monitor_running" != "true" ]] && break

            # Check for newer log files
            local latest=$(_find_latest_codex_log)
            [[ "$monitor_running" != "true" ]] && break
            local latest_session=$(_find_latest_session)
            [[ "$monitor_running" != "true" ]] && break

            if [[ "$latest" != "$current_file" && -n "$latest" ]]; then
                # New file found
                current_file="$latest"
                current_session_dir="$latest_session"

                # Clear scroll region and notify
                tput cup $status_bar_height 0
                tput ed
                printf "\n==> Switching to newer log: %s\n\n" "$current_file"

                # Reset for new file
                last_size=0
                break
            fi
        done
    done

    # Reset trap functions
    unfunction TRAPINT TRAPTERM 2>/dev/null
}

# Main gaac function
gaac() {
    local cmd="$1"
    shift

    case "$cmd" in
        monitor)
            local target="$1"
            case "$target" in
                codex)
                    _gaac_monitor_codex
                    ;;
                *)
                    echo "Usage: gaac monitor codex"
                    echo ""
                    echo "Monitor the latest Codex run log from .gaac-loop.local"
                    echo "Features:"
                    echo "  - Fixed status bar showing session info, round progress, model config"
                    echo "  - Goal tracker summary: Ultimate Goal, AC progress, task status"
                    echo "  - Real-time log output in scrollable area below"
                    echo "  - Automatically switches to newer logs when they appear"
                    return 1
                    ;;
            esac
            ;;
        *)
            echo "Usage: gaac <command> [args]"
            echo ""
            echo "Commands:"
            echo "  monitor codex    Monitor the latest Codex run log"
            return 1
            ;;
    esac
}
