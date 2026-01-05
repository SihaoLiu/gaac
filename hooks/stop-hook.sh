#!/bin/bash
#
# GAAC Stop Hook - Ralph-Wiggum Style Review Iteration
#
# This hook intercepts exit attempts during /work-on-issue workflows.
# If the review hasn't passed, it blocks the exit and feeds issues back
# to continue the implementation/review loop.
#
# State file: .claude/work-on-issue.state
# Completion keyword: WORK_ON_ISSUE_<N>_DONE
#

set -euo pipefail

# Read hook input from stdin
HOOK_INPUT=$(cat)

# Prevent recursive invocation
STOP_HOOK_ACTIVE=$(echo "$HOOK_INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

# Get project root
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# State file for /work-on-issue
STATE_FILE="$PROJECT_ROOT/.claude/work-on-issue.state"

# If no state file exists, allow exit
if [ ! -f "$STATE_FILE" ]; then
    exit 0
fi

# Parse state file frontmatter (YAML between ---)
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE" 2>/dev/null || echo "")

# Extract values
ACTIVE=$(echo "$FRONTMATTER" | grep '^active:' | sed 's/active: *//' | tr -d ' ')
ISSUE_NUMBER=$(echo "$FRONTMATTER" | grep '^issue_number:' | sed 's/issue_number: *//' | tr -d ' ')
PHASE=$(echo "$FRONTMATTER" | grep '^phase:' | sed 's/phase: *//' | tr -d ' ')
ITERATION=$(echo "$FRONTMATTER" | grep '^review_iteration:' | sed 's/review_iteration: *//' | tr -d ' ')
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//' | tr -d ' ')
COMPLETION_KEYWORD=$(echo "$FRONTMATTER" | grep '^completion_keyword:' | sed 's/completion_keyword: *//')

# Default values
ITERATION="${ITERATION:-0}"
MAX_ITERATIONS="${MAX_ITERATIONS:-10}"

# If not active, allow exit
if [ "$ACTIVE" != "true" ]; then
    exit 0
fi

# Validate numeric fields
if [[ ! "$ITERATION" =~ ^[0-9]+$ ]]; then
    echo "Warning: State file corrupted (iteration), stopping" >&2
    rm -f "$STATE_FILE"
    exit 0
fi

if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
    MAX_ITERATIONS=10
fi

# Check max iterations
if [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
    echo "GAAC: Max review iterations ($MAX_ITERATIONS) reached" >&2
    echo "Allowing exit - manual review recommended" >&2
    rm -f "$STATE_FILE"
    exit 0
fi

# Get transcript path from hook input
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    echo "Warning: Cannot read transcript, allowing exit" >&2
    rm -f "$STATE_FILE"
    exit 0
fi

# Read last assistant message from transcript
LAST_OUTPUT=""
if grep -q '"role":"assistant"' "$TRANSCRIPT_PATH" 2>/dev/null; then
    LAST_LINE=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" | tail -1)
    LAST_OUTPUT=$(echo "$LAST_LINE" | jq -r '
        .message.content |
        map(select(.type == "text")) |
        map(.text) |
        join("\n")
    ' 2>/dev/null || echo "")
fi

if [ -z "$LAST_OUTPUT" ]; then
    echo "Warning: No assistant output found, allowing exit" >&2
    rm -f "$STATE_FILE"
    exit 0
fi

# ========================================
# Check Completion Criteria
# ========================================

# Check for completion keyword (e.g., WORK_ON_ISSUE_42_DONE)
if [ -n "$COMPLETION_KEYWORD" ]; then
    if echo "$LAST_OUTPUT" | grep -qF "$COMPLETION_KEYWORD"; then
        echo "GAAC: Completion keyword detected: $COMPLETION_KEYWORD" >&2
        rm -f "$STATE_FILE"
        exit 0
    fi
fi

# Check for review passed markers
REVIEW_PASSED=false

# Pattern 1: Review score >= 81
REVIEW_SCORE=""
if echo "$LAST_OUTPUT" | grep -qiE "score[:\s]*[0-9]+|review.*score|self-review"; then
    REVIEW_SCORE=$(echo "$LAST_OUTPUT" | grep -oiE "score[:\s]*[0-9]+" | grep -oE "[0-9]+" | tail -1 || echo "")
fi

if [ -n "$REVIEW_SCORE" ] && [ "$REVIEW_SCORE" -ge 81 ] 2>/dev/null; then
    # Also need to check if PR was created
    if echo "$LAST_OUTPUT" | grep -qiE "pr.*created|created.*pr|pull request.*#[0-9]+"; then
        REVIEW_PASSED=true
        echo "GAAC: Review passed (score $REVIEW_SCORE >= 81) and PR created" >&2
    fi
fi

# Pattern 2: Phase 6+ completed markers
if echo "$LAST_OUTPUT" | grep -qiE "phase 6.*complete|phase 7|commit.*success|pushed.*remote"; then
    REVIEW_PASSED=true
    echo "GAAC: Phase completion marker detected" >&2
fi

# Pattern 3: All acceptance criteria checked
if echo "$LAST_OUTPUT" | grep -qiE "all acceptance criteria.*met|acceptance criteria:.*\[x\].*\[x\]"; then
    if echo "$LAST_OUTPUT" | grep -qiE "tests.*pass|all tests.*pass"; then
        REVIEW_PASSED=true
        echo "GAAC: Acceptance criteria and tests passed" >&2
    fi
fi

# If review passed, clean up and allow exit
if [ "$REVIEW_PASSED" = true ]; then
    rm -f "$STATE_FILE"
    exit 0
fi

# ========================================
# Review Not Complete - Extract Issues and Block
# ========================================

NEXT_ITERATION=$((ITERATION + 1))

# Extract issues from output
ISSUES=""

# Check for self-check failures
if echo "$LAST_OUTPUT" | grep -qiE "self-check.*incomplete|incomplete.*status|\[ \]"; then
    SELF_CHECK_ISSUES=$(echo "$LAST_OUTPUT" | grep -E "\[ \]|incomplete|TODO|FIXME" | head -10 || echo "")
    if [ -n "$SELF_CHECK_ISSUES" ]; then
        ISSUES="${ISSUES}

### Self-Check Issues
$SELF_CHECK_ISSUES"
    fi
fi

# Check for peer-check failures
if echo "$LAST_OUTPUT" | grep -qiE "peer-check.*needs.work|NEEDS_WORK|peer.*review.*fail"; then
    PEER_CHECK_ISSUES=$(echo "$LAST_OUTPUT" | grep -iA10 "peer-check\|NEEDS_WORK\|findings" | head -15 || echo "")
    if [ -n "$PEER_CHECK_ISSUES" ]; then
        ISSUES="${ISSUES}

### Peer-Check Issues
$PEER_CHECK_ISSUES"
    fi
fi

# Check for review score < 81
if [ -n "$REVIEW_SCORE" ] && [ "$REVIEW_SCORE" -lt 81 ] 2>/dev/null; then
    CODE_REVIEW_ISSUES=$(echo "$LAST_OUTPUT" | grep -iA15 "score\|review\|issues found" | head -20 || echo "")
    ISSUES="${ISSUES}

### Review Score: $REVIEW_SCORE/100 (need >= 81)
$CODE_REVIEW_ISSUES"
fi

# Check for test failures
if echo "$LAST_OUTPUT" | grep -qiE "test.*fail|failing.*test|error.*test"; then
    TEST_ISSUES=$(echo "$LAST_OUTPUT" | grep -iA5 "test.*fail\|error" | head -10 || echo "")
    if [ -n "$TEST_ISSUES" ]; then
        ISSUES="${ISSUES}

### Test Failures
$TEST_ISSUES"
    fi
fi

# If no specific issues found, use generic message
if [ -z "$(echo "$ISSUES" | tr -d '[:space:]')" ]; then
    ISSUES="

The implementation or review is not yet complete. Please ensure:

1. **Self-Check**: All acceptance criteria met, no TODOs left
2. **Tests**: All tests pass
3. **Peer-Check**: External review passed (PASS status)
4. **Review Score**: Self-review score >= 81
5. **PR**: Pull request created successfully

When complete, output: $COMPLETION_KEYWORD"
fi

# Update iteration in state file
TEMP_FILE="${STATE_FILE}.tmp.$$"
sed "s/^review_iteration: .*/review_iteration: $NEXT_ITERATION/" "$STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$STATE_FILE"

# Build reason to send back to Claude
REASON="# GAAC Review Loop - Iteration $NEXT_ITERATION of $MAX_ITERATIONS

## Issue: #$ISSUE_NUMBER

The work-on-issue workflow cannot complete because the review phase has not passed.

## Issues Found
$ISSUES

## Required Actions

1. Fix the issues identified above
2. Re-run the review checks (self-check → peer-check → self-review)
3. Ensure review score >= 81
4. Create PR if not yet created
5. Output completion keyword when done: \`$COMPLETION_KEYWORD\`

## Current Status

- **Iteration**: $NEXT_ITERATION of $MAX_ITERATIONS
- **Phase**: Review loop (Phase 5)
- **Issue**: #$ISSUE_NUMBER

Continue with the fixes and complete the review."

# System message for status line
SYSTEM_MSG="GAAC: Review iteration $NEXT_ITERATION/$MAX_ITERATIONS for issue #$ISSUE_NUMBER"

# Output JSON to block stop and send issues back
jq -n \
    --arg reason "$REASON" \
    --arg msg "$SYSTEM_MSG" \
    '{
        "decision": "block",
        "reason": $reason,
        "systemMessage": $msg
    }'

exit 0
