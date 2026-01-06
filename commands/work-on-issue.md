---
description: Complete end-to-end workflow to resolve a GitHub issue with Ralph-Wiggum enhanced review loops
argument-hint: <issue-number>
allowed-tools: Bash(bash $CLAUDE_PLUGIN_ROOT/skills/init-validator/scripts/*:*), Bash(bash $CLAUDE_PLUGIN_ROOT/skills/github-manager/scripts/*:*), Bash(bash $CLAUDE_PLUGIN_ROOT/skills/third-party-call/scripts/*:*), Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*), Bash(git checkout:*), Bash(git fetch:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(git rebase:*), Bash(gh issue view:*), Bash(gh issue comment:*), Bash(gh pr create:*), Bash(gh pr view:*), Bash(gh pr list:*), Bash(gh pr comment:*), Bash(gh api:*), Bash(mkdir -p:*), Bash(rm -f:*), Bash(cat:*), Bash(sleep:*), Read, Write, Edit, Glob, Grep, Task, AskUserQuestion, TodoWrite, EnterPlanMode
---

# /work-on-issue

Complete end-to-end workflow to resolve a GitHub issue. Includes test-driven development, multi-stage code review with Ralph-Wiggum style iteration, and automatic PR creation.

## Context

- Repository: !`gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || echo "unknown"`
- Current branch: !`git branch --show-current`
- Issue number: $1
- Max iterations: !`echo "${MAX_RALPH_WIGGUM_ITER:-10}"`

---

## Phase 0: Validation

Run prerequisite check:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/init-validator/scripts/check-prerequisites.sh"
```

Validate issue:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/init-validator/scripts/validate-work.sh" "$1"
```

**If validation fails (exit 1)**: Display error and stop.
**If warning (exit 2)**: Ask user to confirm continuation.

---

## Phase 1: Issue Analysis

### 1.1 Fetch Issue Details

```bash
gh issue view $1 --json title,body,labels,comments,assignees
```

### 1.2 Parse Issue Structure

Extract from issue body:
- Problem statement
- Expected behavior
- Acceptance criteria
- Test plan (tests to write first)
- Implementation hints
- Dependencies

### 1.3 Check Dependencies

If issue has "Depends on: #N" references:
- Verify dependent issues are closed
- If not, ask user whether to proceed

### 1.4 Context Gathering

Use Task with `subagent_type=Explore` to understand:
- Related code areas
- Similar implementations
- Test patterns

---

## Phase 2: Planning

### 2.1 Enter Plan Mode

Use EnterPlanMode to create implementation plan.

Plan should include:
- Files to create/modify
- Step-by-step approach
- Test strategy (TDD)
- Estimated lines changed

### 2.2 User Approval

Present plan and get approval via AskUserQuestion.

### 2.3 Create Branch (if needed)

```bash
BRANCH_NAME="issue-$1-$(echo "$ISSUE_TITLE" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | head -c 30)"
git checkout -b "$BRANCH_NAME" 2>/dev/null || git checkout "$BRANCH_NAME"
```

---

## Phase 3: Test-Driven Development

### 3.1 Write Tests First

Based on "Test Plan" section in issue:
1. Create test files
2. Write test cases that will fail
3. Verify tests fail as expected

This ensures clear acceptance criteria.

### 3.2 Run Initial Tests

```bash
# Run test command from gaac.md config
# Tests should fail at this point
```

---

## Phase 4: Implementation

### 4.1 Initialize Review Loop State

Create state file for Stop hook integration:

```bash
mkdir -p "$CLAUDE_PROJECT_DIR/.claude"
ISSUE_NUM="$1"
MAX_ITER="${MAX_RALPH_WIGGUM_ITER:-10}"
cat > "$CLAUDE_PROJECT_DIR/.claude/work-on-issue.state" << EOF
---
active: true
issue_number: ${ISSUE_NUM}
phase: implementation
review_iteration: 0
max_iterations: ${MAX_ITER}
completion_keyword: WORK_ON_ISSUE_${ISSUE_NUM}_DONE
---
Work-on-issue state for #${ISSUE_NUM}
EOF
```

**IMPORTANT**: Variables MUST expand in the state file. Use double-quoted heredoc (`<< EOF`), NOT single-quoted (`<< 'EOF'`).

### 4.2 Implement Changes

Follow the approved plan:
1. Create/modify files as planned
2. Use Edit/Write tools
3. Track progress with TodoWrite
4. Run incremental builds

### 4.3 Run Tests

After implementation:
```bash
# Run quick test command from gaac.md
```

Verify tests pass.

### 4.4 Size Monitoring

Check changes size:

```bash
git diff --stat | tail -1
```

| Lines Changed | Status | Action |
|--------------|--------|--------|
| < 300 | Ideal | Continue |
| 300-600 | Acceptable | Continue with note |
| 600-800 | Warning | Notify user, continue |
| > 800 | Large | Notify user, recommend split |

If > 800 lines: Inform user but do NOT stop automatically.

---

## Phase 5: Three-Stage Review (Ralph-Wiggum Enhanced)

This phase uses the Stop hook for automatic iteration. The hook will block exit and continue the review loop until all stages pass.

### 5.1 Self-Check

Verify implementation completeness:

**Checklist:**
- [ ] All acceptance criteria met
- [ ] Tests pass
- [ ] No TODOs or placeholders left
- [ ] Build succeeds with no new warnings
- [ ] Code follows project conventions

**Status:** COMPLETE or INCOMPLETE

If INCOMPLETE: List what's missing and fix.

### 5.2 Peer-Check (External Model)

Run external code review:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/third-party-call/scripts/run-peer-check.sh" \
    --issue-number $1 \
    --output-file ".claude/peer-review-$1.md"
```

**Status:** PASS or NEEDS_WORK

If NEEDS_WORK: Review findings, fix issues, repeat from 5.1.

### 5.3 Final Self-Review

After peer-check passes:

Perform comprehensive review covering:
- Correctness against issue requirements
- Edge case handling
- Error handling
- Security considerations
- Performance implications

Assign a score (0-100). Target: >= 81.

### 5.4 Review Result

**If all stages pass (score >= 81):**

Update state file:
```bash
echo "phase: review_passed" >> "$CLAUDE_PROJECT_DIR/.claude/work-on-issue.state"
```

Proceed to Phase 6.

**If any stage fails:**

The Stop hook will detect incomplete review and block exit with a reason containing the issues found. This creates the Ralph-Wiggum iteration loop.

Fix the issues and continue (the Stop hook feeds back the prompt).

---

## Phase 6: Commit and Push

### 6.1 Clean Up State

```bash
rm -f "$CLAUDE_PROJECT_DIR/.claude/work-on-issue.state"
```

### 6.2 Stage and Commit

```bash
git add -A
```

Create commit:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-manager/scripts/create-commit.sh" \
    --issue $1 \
    --message "<commit message based on changes>"
```

### 6.3 Rebase on Default Branch

```bash
git fetch origin
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
git rebase "origin/$DEFAULT_BRANCH"
```

If conflicts: resolve, re-run Phase 5.

### 6.4 Push

```bash
git push -u origin $(git branch --show-current)
```

---

## Phase 7: Pull Request

### 7.1 Check for Existing PR

```bash
gh pr list --head "$(git branch --show-current)" --json number,url
```

### 7.2 Create or Update PR

If no PR exists:

```bash
# L1 required, L2 optional; [Issue #N] required in PR titles
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-manager/scripts/create-pr.sh" \
    --title "[L1][Issue #$1] <Feature description>" \
    --resolves $1
```

Examples:
- `[Core][Issue #42] Add caching layer`
- `[Core][Cache][Issue #42] Add Redis backend` (with L2 if sub-area clear)

If PR exists: Just push (PR updates automatically).

---

## Phase 8: Completion

### 8.1 Update Issue

Add completion comment:

```bash
gh issue comment $1 --body "Implementation complete. PR: #<pr-number>"
```

### 8.2 Output Completion Keyword

**IMPORTANT**: Output the completion keyword to signal the Stop hook:

```
WORK_ON_ISSUE_<issue-number>_DONE
```

For example, for issue #42, output: `WORK_ON_ISSUE_42_DONE`

This tells the Stop hook that the work is complete and allows normal exit.

### 8.3 Final Summary

| Item | Status |
|------|--------|
| Issue | #$1 |
| Branch | <branch-name> |
| PR | #<pr-number> |
| Lines changed | <N> |
| Tests | Passing |
| Review score | <score>/100 |

**Next steps:**
- Wait for PR review
- Use `/resolve-pr-comment` if feedback received

---

## Stop Hook Integration

The `/work-on-issue` command integrates with the Stop hook to create automatic review iteration:

1. State file tracks: issue number, current phase, iteration count
2. During Phase 5, if review fails, attempting to exit triggers the hook
3. Hook blocks exit and sends failure reason back
4. Claude continues with fixes
5. When review passes, completion keyword signals success
6. Max iterations prevents infinite loops (default: 10)

### Completion Keyword

The Stop hook looks for: `WORK_ON_ISSUE_<ISSUE_NUMBER>_DONE`

Only output this when ALL of the following are true:
- All acceptance criteria met
- All tests pass
- Self-review score >= 81
- Peer-check passed
- PR created successfully

---

## Notes

- Use TodoWrite throughout to track progress
- The Stop hook creates Ralph-Wiggum style iteration automatically
- Size warnings at 600+ lines, but no automatic stop
- Test-driven: write tests before implementation
- Completion keyword is MANDATORY for proper exit
