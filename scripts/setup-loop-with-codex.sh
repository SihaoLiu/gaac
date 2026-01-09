#!/bin/bash
#
# Setup script for ralph-loop-with-codex-review
#
# Creates state files for the loop that uses Codex to review Claude's work.
#
# Usage:
#   setup-loop-with-codex.sh <path/to/plan.md> [--max N] [--codex-model MODEL:EFFORT]
#

set -euo pipefail

# ========================================
# Default Configuration
# ========================================

# Default Codex model and reasoning effort
DEFAULT_CODEX_MODEL="gpt-5.2-codex"
DEFAULT_CODEX_EFFORT="xhigh"
DEFAULT_CODEX_TIMEOUT=5400
DEFAULT_MAX_ITERATIONS=42

# ========================================
# Parse Arguments
# ========================================

PLAN_FILE=""
MAX_ITERATIONS="$DEFAULT_MAX_ITERATIONS"
MAX_EXPLICITLY_SET=false
INFINITE_MODE=false
CODEX_MODEL="$DEFAULT_CODEX_MODEL"
CODEX_EFFORT="$DEFAULT_CODEX_EFFORT"
CODEX_TIMEOUT="$DEFAULT_CODEX_TIMEOUT"

show_help() {
    cat << 'HELP_EOF'
ralph-loop-with-codex-review - Iterative development with Codex review

USAGE:
  /gaac:ralph-loop-with-codex-review <path/to/plan.md> [OPTIONS]

ARGUMENTS:
  <path/to/plan.md>    Path to a markdown file containing the implementation plan
                       (must exist and have at least 5 lines)

OPTIONS:
  --max <N>            Maximum iterations before auto-stop (default: 42)
  --infinite           No iteration limit - run until Codex outputs COMPLETE
                       (cannot be used with --max, requires confirmation)
  --codex-model <MODEL:EFFORT>
                       Codex model and reasoning effort (default: gpt-5.2-codex:xhigh)
  --codex-timeout <SECONDS>
                       Timeout for each Codex review in seconds (default: 5400)
  -h, --help           Show this help message

DESCRIPTION:
  Starts a Ralph Loop with Codex review in your CURRENT session. Unlike
  the standard ralph-loop, this variant:

  1. Takes a markdown plan file as input (not a prompt string)
  2. Uses Codex to independently review Claude's work each iteration
  3. Continues until Codex confirms completion with "COMPLETE" or max iterations

  The flow:
  1. Claude works on the plan
  2. Claude writes a summary to round-N-summary.md
  3. On exit attempt, Codex reviews the summary
  4. If Codex finds issues, it blocks exit and sends feedback
  5. If Codex outputs "COMPLETE", the loop ends

EXAMPLES:
  /gaac:loop-with-codex-review docs/feature-plan.md
  /gaac:loop-with-codex-review docs/impl.md --max 20
  /gaac:loop-with-codex-review plan.md --infinite
  /gaac:loop-with-codex-review plan.md --codex-model gpt-5.2-codex:high
  /gaac:loop-with-codex-review plan.md --codex-timeout 7200  # 2 hour timeout

STOPPING:
  - /gaac:cancel-loop-with-codex   Cancel the active loop
  - Reach --max iterations
  - Codex outputs "COMPLETE" as final line of review

MONITORING:
  # View current state:
  cat .gaac-loop.local/*/state.md

  # View latest summary:
  cat .gaac-loop.local/*/round-*-summary.md | tail -50

  # View Codex review:
  cat .gaac-loop.local/*/round-*-review-result.md | tail -50
HELP_EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        --max)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --max requires a number argument" >&2
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                echo "Error: --max must be a positive integer, got: $2" >&2
                exit 1
            fi
            MAX_ITERATIONS="$2"
            MAX_EXPLICITLY_SET=true
            shift 2
            ;;
        --infinite)
            INFINITE_MODE=true
            shift
            ;;
        --codex-model)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --codex-model requires a MODEL:EFFORT argument" >&2
                exit 1
            fi
            # Parse MODEL:EFFORT format
            if [[ "$2" =~ ^([^:]+):([^:]+)$ ]]; then
                CODEX_MODEL="${BASH_REMATCH[1]}"
                CODEX_EFFORT="${BASH_REMATCH[2]}"
            else
                CODEX_MODEL="$2"
                CODEX_EFFORT="$DEFAULT_CODEX_EFFORT"
            fi
            shift 2
            ;;
        --codex-timeout)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --codex-timeout requires a number argument (seconds)" >&2
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                echo "Error: --codex-timeout must be a positive integer (seconds), got: $2" >&2
                exit 1
            fi
            CODEX_TIMEOUT="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
        *)
            if [[ -z "$PLAN_FILE" ]]; then
                PLAN_FILE="$1"
            else
                echo "Error: Multiple plan files specified" >&2
                echo "Only one plan file is allowed" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# ========================================
# Validate Option Conflicts
# ========================================

# Check for --max and --infinite conflict
if [[ "$INFINITE_MODE" == "true" ]] && [[ "$MAX_EXPLICITLY_SET" == "true" ]]; then
    echo "Error: --max and --infinite cannot be used together" >&2
    echo "" >&2
    echo "Use --max <N> for a finite iteration limit, or" >&2
    echo "Use --infinite for unlimited iterations until Codex confirms COMPLETE" >&2
    exit 1
fi

# If infinite mode, set max_iterations to inf and require confirmation
if [[ "$INFINITE_MODE" == "true" ]]; then
    MAX_ITERATIONS="inf"

    echo "==========================================="
    echo "WARNING: Infinite Mode Selected"
    echo "==========================================="
    echo ""
    echo "You have selected --infinite mode. This means:"
    echo "  - The loop will run until Codex outputs COMPLETE"
    echo "  - There is NO iteration limit"
    echo "  - This may consume a LARGE amount of tokens"
    echo "  - Both Claude and Codex will be called each iteration"
    echo ""
    echo "Are you sure you want to continue? (yes/no)"
    echo ""

    read -r CONFIRMATION

    if [[ "$CONFIRMATION" != "yes" ]]; then
        echo "" >&2
        echo "Cancelled. Use --max <N> for a safer finite limit." >&2
        exit 1
    fi

    echo ""
    echo "Infinite mode confirmed. Proceeding..."
    echo ""
fi

# ========================================
# Validate Prerequisites
# ========================================

# Check plan file is provided
if [[ -z "$PLAN_FILE" ]]; then
    echo "Error: No plan file provided" >&2
    echo "" >&2
    echo "Usage: /gaac:ralph-loop-with-codex-review <path/to/plan.md> [OPTIONS]" >&2
    echo "" >&2
    echo "For help: /gaac:ralph-loop-with-codex-review --help" >&2
    exit 1
fi

# Make path absolute if relative
if [[ ! "$PLAN_FILE" = /* ]]; then
    PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
    PLAN_FILE="$PROJECT_ROOT/$PLAN_FILE"
fi

# Check plan file exists
if [[ ! -f "$PLAN_FILE" ]]; then
    echo "Error: Plan file not found: $PLAN_FILE" >&2
    exit 1
fi

# Check plan file has at least 5 lines
LINE_COUNT=$(wc -l < "$PLAN_FILE" | tr -d ' ')
if [[ "$LINE_COUNT" -lt 5 ]]; then
    echo "Error: Plan is too simple (only $LINE_COUNT lines, need at least 5)" >&2
    echo "" >&2
    echo "The plan file should contain enough detail for implementation." >&2
    echo "Consider adding more context, acceptance criteria, or steps." >&2
    exit 1
fi

# Check codex is available
if ! command -v codex &>/dev/null; then
    echo "Error: ralph-loop-with-codex-review requires codex to run" >&2
    echo "" >&2
    echo "Please install Codex CLI: https://openai.com/codex" >&2
    exit 1
fi

# ========================================
# Setup State Directory
# ========================================

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
LOOP_BASE_DIR="$PROJECT_ROOT/.gaac-loop.local"

# Create timestamp for this loop session
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
LOOP_DIR="$LOOP_BASE_DIR/$TIMESTAMP"

mkdir -p "$LOOP_DIR"

# Get docs base path from gaac config if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HELPER="$SCRIPT_DIR/gaac-config.sh"
DOCS_PATH=""
if [[ -f "$CONFIG_HELPER" ]]; then
    DOCS_PATH=$(bash "$CONFIG_HELPER" docs-base 2>/dev/null || echo "")
fi
DOCS_PATH="${DOCS_PATH:-docs}"

# ========================================
# Create State File
# ========================================

cat > "$LOOP_DIR/state.md" << EOF
---
current_round: 0
max_iterations: $MAX_ITERATIONS
codex_model: $CODEX_MODEL
codex_effort: $CODEX_EFFORT
codex_timeout: $CODEX_TIMEOUT
plan_file: $PLAN_FILE
started_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
---
EOF

# ========================================
# Create Initial Prompt
# ========================================

SUMMARY_PATH="$LOOP_DIR/round-0-summary.md"

cat > "$LOOP_DIR/round-0-prompt.md" << EOF
Read and execute below with ultrathink

For all tasks that need to be completed, please create Todos to track each item in order of importance.
You are strictly prohibited from only addressing the most important issues - you MUST create Todos for ALL discovered issues and attempt to resolve each one.

$(cat "$PLAN_FILE")

Note: You MUST NOT try to exit \`ralph-loop-with-codex-review\` loop by lying or edit loop state file or try to execute \`cancel-loop-with-codex\`

After completing the work, please:
0. If you have access to the \`code-simplifier\` agent, use it to review and optimize the code you just wrote
1. Commit your changes with a descriptive commit message
2. Push the commit to the remote repository
3. Write your work summary into @$SUMMARY_PATH
EOF

# ========================================
# Output Setup Message
# ========================================

# Format max iterations for display
if [[ "$MAX_ITERATIONS" == "inf" ]]; then
    MAX_DISPLAY="unlimited (infinite mode)"
else
    MAX_DISPLAY="$MAX_ITERATIONS"
fi

cat << EOF
=== ralph-loop-with-codex-review activated ===

Plan File: $PLAN_FILE ($LINE_COUNT lines)
Max Iterations: $MAX_DISPLAY
Codex Model: $CODEX_MODEL
Codex Effort: $CODEX_EFFORT
Codex Timeout: ${CODEX_TIMEOUT}s
Loop Directory: $LOOP_DIR

The loop is now active. When you try to exit:
1. Codex will review your work summary
2. If issues are found, you'll receive feedback and continue
3. If Codex outputs "COMPLETE", the loop ends

To cancel: /gaac:cancel-loop-with-codex

---

EOF

# Output the initial prompt
cat "$LOOP_DIR/round-0-prompt.md"

echo ""
echo "==========================================="
echo "CRITICAL - Work Completion Requirements"
echo "==========================================="
echo ""
echo "When you complete your work, you MUST:"
echo ""
echo "1. COMMIT and PUSH your changes:"
echo "   - Create a commit with descriptive message"
echo "   - Push to the remote repository"
echo ""
echo "2. Write a detailed summary to:"
echo "   $SUMMARY_PATH"
echo ""
echo "   The summary should include:"
echo "   - What was implemented"
echo "   - Files created/modified"
echo "   - Tests added/passed"
echo "   - Any remaining items"
echo ""
echo "Codex will review this summary to determine if work is complete."
echo "==========================================="
