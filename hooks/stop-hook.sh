#!/bin/bash
#
# GAAC Stop Hook - Ralph-Wiggum Style Review Iteration
#
# This hook intercepts exit attempts during /work-on-issue workflows.
# If the review hasn't passed, it blocks the exit and feeds issues back
# to continue the implementation/review loop.
#
# State file: .claude/work-on-issue.state
# Completion format: <gaac-complete>WORK_ON_ISSUE_<N>_DONE</gaac-complete>
# Review score format: <!-- GAAC_REVIEW_SCORE: NN -->
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
SESSION_ID=$(echo "$FRONTMATTER" | grep '^session_id:' | sed 's/session_id: *//' | tr -d ' ')

# Default values
ITERATION="${ITERATION:-0}"
MAX_ITERATIONS="${MAX_ITERATIONS:-50}"

# If not active, allow exit
if [ "$ACTIVE" != "true" ]; then
    exit 0
fi

# Session isolation: check if this session matches (if session tracking enabled)
if [ -n "$SESSION_ID" ] && [ -n "${CLAUDE_SESSION_ID:-}" ]; then
    if [ "$SESSION_ID" != "$CLAUDE_SESSION_ID" ]; then
        # Different session - allow exit without affecting state
        exit 0
    fi
fi

# Validate numeric fields
if [[ ! "$ITERATION" =~ ^[0-9]+$ ]]; then
    echo "Warning: State file corrupted (iteration), stopping" >&2
    rm -f "$STATE_FILE"
    exit 0
fi

if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
    MAX_ITERATIONS=50
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
# Extract All Status Markers First
# ========================================

# Extract completion keyword from XML tags (REQUIRED format)
# Format: <gaac-complete>WORK_ON_ISSUE_42_DONE</gaac-complete>
COMPLETION_DETECTED=false
COMPLETION_TEXT=""
if [ -n "$COMPLETION_KEYWORD" ]; then
    # Use Perl for reliable multiline XML tag extraction (same as official ralph-wiggum)
    COMPLETION_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -pe 's/.*?<gaac-complete>(.*?)<\/gaac-complete>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")

    if [ -n "$COMPLETION_TEXT" ] && [ "$COMPLETION_TEXT" = "$COMPLETION_KEYWORD" ]; then
        COMPLETION_DETECTED=true
    fi
fi

# Extract review score
# Format: <!-- GAAC_REVIEW_SCORE: 85 -->
REVIEW_SCORE=""
if echo "$LAST_OUTPUT" | grep -qE 'GAAC_REVIEW_SCORE:[[:space:]]*[0-9]+'; then
    REVIEW_SCORE=$(echo "$LAST_OUTPUT" | grep -oE 'GAAC_REVIEW_SCORE:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | tail -1 || echo "")
fi

# Fallback: Try to extract from natural language (less reliable)
if [ -z "$REVIEW_SCORE" ]; then
    if echo "$LAST_OUTPUT" | grep -qiE "self-review.*score|review score|final score"; then
        REVIEW_SCORE=$(echo "$LAST_OUTPUT" | grep -iE "self-review.*score|review score|final score" | grep -oE '[0-9]+/100|score[[:space:]]*:?[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1 || echo "")
    fi
fi

# Extract review assessment
# Format: <!-- GAAC_REVIEW_ASSESSMENT: Approve with Minor Suggestion -->
REVIEW_ASSESSMENT=""
if echo "$LAST_OUTPUT" | grep -qE 'GAAC_REVIEW_ASSESSMENT:'; then
    REVIEW_ASSESSMENT=$(echo "$LAST_OUTPUT" | grep -oE 'GAAC_REVIEW_ASSESSMENT:[^>-]+' | sed 's/GAAC_REVIEW_ASSESSMENT:[[:space:]]*//' | sed 's/[[:space:]]*$//' | tail -1 || echo "")
fi

# Extract PR number (REQUIRED format)
# Format: <!-- GAAC_PR_CREATED: 123 -->
PR_NUMBER=""
if echo "$LAST_OUTPUT" | grep -qE 'GAAC_PR_CREATED:[[:space:]]*[0-9]+'; then
    PR_NUMBER=$(echo "$LAST_OUTPUT" | grep -oE 'GAAC_PR_CREATED:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | tail -1 || echo "")
fi

# ========================================
# Evaluate Completion Criteria
# ========================================

# Valid assessments for passing
VALID_ASSESSMENTS="Approve|Approve with Minor Suggestion"

# Check individual criteria
SCORE_PASSES=false
ASSESSMENT_PASSES=false
PR_CREATED=false

if [ -n "$REVIEW_SCORE" ] && [ "$REVIEW_SCORE" -ge 81 ] 2>/dev/null; then
    SCORE_PASSES=true
fi

if [ -n "$REVIEW_ASSESSMENT" ] && echo "$REVIEW_ASSESSMENT" | grep -qE "^($VALID_ASSESSMENTS)$"; then
    ASSESSMENT_PASSES=true
fi

if [ -n "$PR_NUMBER" ]; then
    PR_CREATED=true
fi

# ========================================
# Final Decision: ALL criteria must pass
# ========================================

# For completion, we require ALL of:
# 1. Completion keyword detected (Claude explicitly says it's done)
# 2. Review score >= 81
# 3. Assessment is Approve or Approve with Minor Suggestion
# 4. PR has been created

ALL_CRITERIA_MET=false

if [ "$COMPLETION_DETECTED" = true ] && [ "$SCORE_PASSES" = true ] && [ "$ASSESSMENT_PASSES" = true ] && [ "$PR_CREATED" = true ]; then
    ALL_CRITERIA_MET=true
    echo "GAAC: All completion criteria met:" >&2
    echo "  - Completion keyword: <gaac-complete>$COMPLETION_KEYWORD</gaac-complete>" >&2
    echo "  - Review score: $REVIEW_SCORE/100 (>= 81)" >&2
    echo "  - Assessment: $REVIEW_ASSESSMENT" >&2
    echo "  - PR: #$PR_NUMBER" >&2
    rm -f "$STATE_FILE"
    exit 0
fi

# ========================================
# Review Not Complete - Extract Issues and Block
# ========================================

NEXT_ITERATION=$((ITERATION + 1))

# Extract issues from output using multiple patterns
ISSUES=""

# Check for structured GAAC issue markers first
# Format: <!-- GAAC_ISSUE: description -->
if echo "$LAST_OUTPUT" | grep -qE 'GAAC_ISSUE:'; then
    STRUCTURED_ISSUES=$(echo "$LAST_OUTPUT" | grep -oE 'GAAC_ISSUE:[^>]+' | sed 's/GAAC_ISSUE:[[:space:]]*/- /' || echo "")
    if [ -n "$STRUCTURED_ISSUES" ]; then
        ISSUES="${ISSUES}

### Identified Issues
$STRUCTURED_ISSUES"
    fi
fi

# Check for self-check failures
if echo "$LAST_OUTPUT" | grep -qiE "self-check.*incomplete|self-check.*fail|incomplete.*status|\[ \][[:space:]]*[A-Z]"; then
    SELF_CHECK_ISSUES=$(echo "$LAST_OUTPUT" | grep -E "\[ \][[:space:]]+[A-Za-z]|self-check.*:.*incomplete|TODO:|FIXME:" | head -10 || echo "")
    if [ -n "$SELF_CHECK_ISSUES" ]; then
        ISSUES="${ISSUES}

### Self-Check Issues
\`\`\`
$SELF_CHECK_ISSUES
\`\`\`"
    fi
fi

# Check for peer-check failures
if echo "$LAST_OUTPUT" | grep -qiE "peer-check.*needs.work|NEEDS_WORK|peer.*review.*fail|peer-check.*fail"; then
    PEER_CHECK_ISSUES=$(echo "$LAST_OUTPUT" | grep -iA10 "peer-check\|NEEDS_WORK\|findings\|issues found" | head -15 || echo "")
    if [ -n "$PEER_CHECK_ISSUES" ]; then
        ISSUES="${ISSUES}

### Peer-Check Issues
\`\`\`
$PEER_CHECK_ISSUES
\`\`\`"
    fi
fi

# Check for review score < 81
if [ -n "$REVIEW_SCORE" ] && [ "$REVIEW_SCORE" -lt 81 ] 2>/dev/null; then
    CODE_REVIEW_ISSUES=$(echo "$LAST_OUTPUT" | grep -iA15 "review score\|self-review\|issues found\|improvements needed" | head -20 || echo "")
    ISSUES="${ISSUES}

### Review Score: $REVIEW_SCORE/100 (need >= 81)
\`\`\`
$CODE_REVIEW_ISSUES
\`\`\`"
fi

# Check for assessment not passing (even if score >= 81)
if [ -n "$REVIEW_ASSESSMENT" ] && ! echo "$REVIEW_ASSESSMENT" | grep -qE "^(Approve|Approve with Minor Suggestion)$"; then
    ISSUES="${ISSUES}

### Assessment Not Passing
**Assessment**: $REVIEW_ASSESSMENT
**Score**: ${REVIEW_SCORE:-unknown}/100

The assessment must be 'Approve' or 'Approve with Minor Suggestion' to pass.
Current assessment indicates issues that need to be addressed."
fi

# Check for missing assessment (score exists but no assessment)
if [ -n "$REVIEW_SCORE" ] && [ "$REVIEW_SCORE" -ge 81 ] 2>/dev/null && [ -z "$REVIEW_ASSESSMENT" ]; then
    ISSUES="${ISSUES}

### Missing Assessment Marker
**Score**: $REVIEW_SCORE/100 (meets threshold)

The code-reviewer must output an assessment marker. Please run the code-reviewer:
\`\`\`
bash \"\${CLAUDE_PLUGIN_ROOT}/skills/third-party-call/scripts/run-code-review.sh\" --issue-number $ISSUE_NUMBER
\`\`\`

Expected output: \`<!-- GAAC_REVIEW_ASSESSMENT: Approve -->\` or \`<!-- GAAC_REVIEW_ASSESSMENT: Approve with Minor Suggestion -->\`"
fi

# Check for test failures
if echo "$LAST_OUTPUT" | grep -qiE "test.*fail|failing.*test|error.*test|tests?:[[:space:]]*[0-9]+[[:space:]]*fail"; then
    TEST_ISSUES=$(echo "$LAST_OUTPUT" | grep -iB2 -A5 "test.*fail\|FAIL\|error.*test" | head -15 || echo "")
    if [ -n "$TEST_ISSUES" ]; then
        ISSUES="${ISSUES}

### Test Failures
\`\`\`
$TEST_ISSUES
\`\`\`"
    fi
fi

# Check for build failures
if echo "$LAST_OUTPUT" | grep -qiE "build.*fail|compile.*error|compilation.*fail"; then
    BUILD_ISSUES=$(echo "$LAST_OUTPUT" | grep -iB2 -A5 "build.*fail\|compile.*error\|error:" | head -15 || echo "")
    if [ -n "$BUILD_ISSUES" ]; then
        ISSUES="${ISSUES}

### Build Failures
\`\`\`
$BUILD_ISSUES
\`\`\`"
    fi
fi

# Check for missing PR marker
if [ "$PR_CREATED" = false ]; then
    ISSUES="${ISSUES}

### Missing PR Marker
No \`<!-- GAAC_PR_CREATED: N -->\` marker found. Please:
1. Create a PR if not done:
\`\`\`
bash \"\${CLAUDE_PLUGIN_ROOT}/skills/github-manager/scripts/create-pr.sh\" --title \"[Issue #$ISSUE_NUMBER] ...\" --resolves $ISSUE_NUMBER
\`\`\`
2. Output the marker with the PR number: \`<!-- GAAC_PR_CREATED: N -->\`"
fi

# Special case: completion keyword detected but other criteria missing
if [ "$COMPLETION_DETECTED" = true ]; then
    MISSING_CRITERIA=""
    if [ "$SCORE_PASSES" = false ]; then
        if [ -n "$REVIEW_SCORE" ]; then
            MISSING_CRITERIA="${MISSING_CRITERIA}\n- Review score: $REVIEW_SCORE/100 (need >= 81)"
        else
            MISSING_CRITERIA="${MISSING_CRITERIA}\n- Review score: NOT FOUND (need >= 81)"
        fi
    fi
    if [ "$ASSESSMENT_PASSES" = false ]; then
        if [ -n "$REVIEW_ASSESSMENT" ]; then
            MISSING_CRITERIA="${MISSING_CRITERIA}\n- Assessment: '$REVIEW_ASSESSMENT' (need 'Approve' or 'Approve with Minor Suggestion')"
        else
            MISSING_CRITERIA="${MISSING_CRITERIA}\n- Assessment: NOT FOUND"
        fi
    fi
    if [ "$PR_CREATED" = false ]; then
        MISSING_CRITERIA="${MISSING_CRITERIA}\n- PR: NOT CREATED"
    fi

    if [ -n "$MISSING_CRITERIA" ]; then
        ISSUES="${ISSUES}

### Completion Keyword Detected But Criteria Not Met
You output \`<gaac-complete>$COMPLETION_KEYWORD</gaac-complete>\` but the following criteria are not satisfied:
$(echo -e "$MISSING_CRITERIA")

**You cannot complete until ALL criteria are met.** Please:
1. Run code-review if not done: \`bash \"\${CLAUDE_PLUGIN_ROOT}/skills/third-party-call/scripts/run-code-review.sh\" --issue-number $ISSUE_NUMBER\`
2. Ensure score >= 81 and assessment is 'Approve' or 'Approve with Minor Suggestion'
3. Create PR if not done and output: \`<!-- GAAC_PR_CREATED: N -->\`
4. Output the structured markers for each criterion"
    fi
fi

# If no specific issues found, provide guidance
if [ -z "$(echo "$ISSUES" | tr -d '[:space:]')" ]; then
    ISSUES="

No specific issues were extracted from the output. Please ensure:

1. **Self-Check**: All acceptance criteria met, no TODOs left
2. **Tests**: All tests pass
3. **Peer-Check**: External review passed (PASS status)
4. **Code-Review**: Run code-reviewer and get score >= 81 with 'Approve' or 'Approve with Minor Suggestion' assessment
5. **PR**: Pull request created with marker output

**Required Output Markers (all are mandatory):**
- \`<!-- GAAC_REVIEW_SCORE: NN -->\` (score from code-reviewer, need >= 81)
- \`<!-- GAAC_REVIEW_ASSESSMENT: Approve -->\` or \`<!-- GAAC_REVIEW_ASSESSMENT: Approve with Minor Suggestion -->\`
- \`<!-- GAAC_PR_CREATED: N -->\` (PR number from gh pr create)
- \`<gaac-complete>$COMPLETION_KEYWORD</gaac-complete>\` (only when ALL above are satisfied)"
fi

# Update iteration in state file
TEMP_FILE="${STATE_FILE}.tmp.$$"
sed "s/^review_iteration: .*/review_iteration: $NEXT_ITERATION/" "$STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$STATE_FILE"

# Build current status summary (based on structured markers only)
STATUS_SUMMARY="- **Completion Keyword** \`<gaac-complete>...</gaac-complete>\`: $([ "$COMPLETION_DETECTED" = true ] && echo "Detected ✓" || echo "Not detected ✗")
- **Review Score** \`<!-- GAAC_REVIEW_SCORE: N -->\`: $([ -n "$REVIEW_SCORE" ] && echo "$REVIEW_SCORE/100 $([ "$SCORE_PASSES" = true ] && echo '✓' || echo '✗ need >= 81')" || echo "Not found ✗")
- **Assessment** \`<!-- GAAC_REVIEW_ASSESSMENT: ... -->\`: $([ -n "$REVIEW_ASSESSMENT" ] && echo "$REVIEW_ASSESSMENT $([ "$ASSESSMENT_PASSES" = true ] && echo '✓' || echo '✗')" || echo "Not found ✗")
- **PR Marker** \`<!-- GAAC_PR_CREATED: N -->\`: $([ "$PR_CREATED" = true ] && echo "#$PR_NUMBER ✓" || echo "Not found ✗")"

# Build reason to send back to Claude
REASON="# GAAC Review Loop - Iteration $NEXT_ITERATION of $MAX_ITERATIONS

## Issue: #$ISSUE_NUMBER

The work-on-issue workflow cannot complete because **ALL completion criteria must be satisfied**.

## Current Criteria Status
$STATUS_SUMMARY

## Issues Found
$ISSUES

## Required Actions

1. Fix any issues identified above
2. Run code-reviewer: \`bash \"\${CLAUDE_PLUGIN_ROOT}/skills/third-party-call/scripts/run-code-review.sh\" --issue-number $ISSUE_NUMBER\`
3. Ensure output includes: \`<!-- GAAC_REVIEW_SCORE: NN -->\` (need >= 81)
4. Ensure output includes: \`<!-- GAAC_REVIEW_ASSESSMENT: Approve -->\` or \`<!-- GAAC_REVIEW_ASSESSMENT: Approve with Minor Suggestion -->\`
5. Create PR if not done: \`bash \"\${CLAUDE_PLUGIN_ROOT}/skills/github-manager/scripts/create-pr.sh\" --resolves $ISSUE_NUMBER\`
6. Ensure output includes: \`<!-- GAAC_PR_CREATED: N -->\`
7. **ONLY when ALL above are satisfied**, output: \`<gaac-complete>$COMPLETION_KEYWORD</gaac-complete>\`

## Important
The Stop hook will block exit until ALL structured markers are present:
- \`<!-- GAAC_REVIEW_SCORE: N -->\` with N >= 81
- \`<!-- GAAC_REVIEW_ASSESSMENT: Approve -->\` or \`<!-- GAAC_REVIEW_ASSESSMENT: Approve with Minor Suggestion -->\`
- \`<!-- GAAC_PR_CREATED: N -->\`
- \`<gaac-complete>$COMPLETION_KEYWORD</gaac-complete>\`

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
