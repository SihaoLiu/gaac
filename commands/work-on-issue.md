---
description: Complete end-to-end workflow to resolve a GitHub issue with Ralph-Wiggum enhanced review loops
argument-hint: <issue-number>
allowed-tools: Bash(bash $CLAUDE_PLUGIN_ROOT/scripts/*:*), Bash(bash $CLAUDE_PLUGIN_ROOT/skills/init-validator/scripts/*:*), Bash(bash $CLAUDE_PLUGIN_ROOT/skills/github-manager/scripts/*:*), Bash(bash $CLAUDE_PLUGIN_ROOT/skills/third-party-call/scripts/*:*), Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*), Bash(git checkout:*), Bash(git fetch:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(git rebase:*), Bash(gh issue view:*), Bash(gh issue comment:*), Bash(gh pr create:*), Bash(gh pr view:*), Bash(gh pr list:*), Bash(gh pr comment:*), Bash(gh api:*), Bash(mkdir -p:*), Bash(rm -f:*), Bash(cat:*), Bash(sleep:*), Read, Write, Edit, Glob, Grep, Task, AskUserQuestion, TodoWrite, EnterPlanMode
---

# /work-on-issue

Complete end-to-end workflow to resolve a GitHub issue. Includes test-driven development, multi-stage code review with Ralph-Wiggum style iteration, and automatic PR creation.

## Context

- Repository: !`gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || echo "unknown"`
- Current branch: !`git branch --show-current`
- Issue number: $1
- Max iterations: !`echo "${MAX_RALPH_WIGGUM_ITER:-50}"`

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
# Run quick test command from gaac.md config
# Tests should fail at this point (TDD approach)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gaac-config.sh" run-quick-test || {
    echo "Tests failed (expected for TDD)"
}
```

If `gaac.quick_test` is not configured, ask user what test command to use.

---

## Phase 4: Implementation

### 4.1 Initialize Review Loop State

Create state file for Stop hook integration:

```bash
mkdir -p "$CLAUDE_PROJECT_DIR/.claude"
ISSUE_NUM="$1"
MAX_ITER="${MAX_RALPH_WIGGUM_ITER:-50}"
SESSION_ID="${CLAUDE_SESSION_ID:-$(date +%s)}"
cat > "$CLAUDE_PROJECT_DIR/.claude/work-on-issue.state" << EOF
---
active: true
issue_number: ${ISSUE_NUM}
phase: implementation
review_iteration: 0
max_iterations: ${MAX_ITER}
completion_keyword: WORK_ON_ISSUE_${ISSUE_NUM}_DONE
session_id: ${SESSION_ID}
---
Work-on-issue state for #${ISSUE_NUM}
EOF
```

**IMPORTANT**: Variables MUST expand in the state file. Use double-quoted heredoc (`<< EOF`), NOT single-quoted (`<< 'EOF'`).

**Session Isolation**: The `session_id` field ensures the Stop hook only affects this session, not other Claude Code sessions in the same project.

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
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gaac-config.sh" run-quick-test
```

If tests fail, fix the issues before proceeding to Phase 5.

### 4.3.1 Run Build (optional)

If `gaac.quick_build` is configured:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gaac-config.sh" run-quick-build
```

Verify tests pass and build succeeds.

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

Run external code review for quick feedback:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/third-party-call/scripts/run-peer-check.sh" \
    --issue-number $1 \
    --output-file ".claude/peer-review-$1.md"
```

**Status:** PASS or NEEDS_WORK

If NEEDS_WORK: Review findings, fix issues, repeat from 5.1.

### 5.2a Full Test Suite (Regression Check)

After peer-check passes, run the full test suite to ensure no regressions:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gaac-config.sh" run-full-test
```

This runs the command configured in `gaac.full_test` (e.g., `make test`, `npm test`, `cargo test --all`).

**Purpose**: Verify that the current changes don't break any existing tests. This catches regressions that quick tests might miss.

**If tests fail**:
1. Analyze which tests failed
2. Determine if failure is caused by your changes or pre-existing
3. Fix the issues
4. Repeat from 5.1

**If `gaac.full_test` is not configured**: Ask user what command to use, then proceed.

### 5.3 Code-Reviewer (Independent Scoring) - MANDATORY

After peer-check passes, run the independent code-reviewer for formal scoring:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/third-party-call/scripts/run-code-review.sh" \
    --issue-number $1 \
    --output-file ".claude/code-review-$1.md"
```

This stage:
- Uses external model (codex preferred, claude fallback)
- Applies the 100-point scoring rubric
- Outputs structured markers for stop hook detection

**Scoring Categories:**
- Code Quality: 25 points
- Correctness & Logic: 25 points
- Security & Safety: 20 points
- Performance & Efficiency: 15 points
- Testing & Documentation: 15 points

**Assessment Mapping:**
- 90-100: "Approve"
- 81-89: "Approve with Minor Suggestion"
- 70-80: "Major changes needed"
- 0-69: "Reject"

**Requirements to Pass:**
- Score >= 81
- Assessment = "Approve" OR "Approve with Minor Suggestion"

If code-review outputs issues, fix them and repeat from 5.1.

### 5.4 Review Result

**If all stages pass (score >= 81 AND assessment is Approve/Approve with Minor):**

Update state file:
```bash
echo "phase: review_passed" >> "$CLAUDE_PROJECT_DIR/.claude/work-on-issue.state"
```

Output the structured markers:
```
<!-- GAAC_REVIEW_SCORE: 85 -->
<!-- GAAC_REVIEW_ASSESSMENT: Approve with Minor Suggestion -->
```

Proceed to Phase 6.

**If any stage fails:**

The Stop hook will detect incomplete review and block exit with a reason containing the issues found. This creates the Ralph-Wiggum iteration loop.

Fix the issues and continue (the Stop hook feeds back the prompt).

### 5.5 Lint/Format Check (Optional)

Before committing, run linter/formatter if configured:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gaac-config.sh" run-lint
```

This runs the command configured in `gaac.lint` (e.g., `npm run lint:fix`, `cargo fmt && cargo clippy`, `make lint`).

**Purpose**: Ensure code follows project formatting standards before commit.

**If lint fails**:
1. Review the lint errors/warnings
2. Fix formatting issues (or apply auto-fix if available)
3. Verify fixes don't break functionality
4. Repeat from 5.1 if significant changes were made

**If `gaac.lint` is not configured**: Skip this step (it's optional). The script will output "SKIP" and continue.

**Note**: This step is optional. If your project doesn't use a linter or the linter is run via pre-commit hooks, you can leave `gaac.lint` unconfigured.

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

**IMPORTANT**: After PR creation, output the structured marker for reliable detection:

```
<!-- GAAC_PR_CREATED: 123 -->
```

Replace `123` with the actual PR number returned by `gh pr create`.

---

## Phase 8: Completion

### 8.1 Update Issue

Add completion comment using post-comment.sh for attribution support:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-manager/scripts/post-comment.sh" \
    --type issue --number $1 --body "Implementation complete. PR: #<pr-number>"
```

### 8.2 Output Completion Keyword

**IMPORTANT**: Output the completion keyword using XML tags to signal the Stop hook:

```
<gaac-complete>WORK_ON_ISSUE_<issue-number>_DONE</gaac-complete>
```

For example, for issue #42, output: `<gaac-complete>WORK_ON_ISSUE_42_DONE</gaac-complete>`

This tells the Stop hook that the work is complete and allows normal exit.

**Why XML tags?** Using explicit XML tags prevents accidental matches when the keyword appears in code, comments, or log output. The Stop hook uses Perl to reliably extract content from these tags.

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

1. State file tracks: issue number, current phase, iteration count, session ID
2. During Phase 5, if review fails, attempting to exit triggers the hook
3. Hook blocks exit and sends failure reason back with extracted issues
4. Claude continues with fixes
5. When review passes, completion keyword signals success
6. Max iterations prevents infinite loops (default: 50)

### Structured Markers for Reliable Detection

The Stop hook recognizes these structured markers in your output:

| Marker | Format | Purpose |
|--------|--------|---------|
| **Completion** | `<gaac-complete>KEYWORD</gaac-complete>` | Signal task complete |
| **Review Score** | `<!-- GAAC_REVIEW_SCORE: NN -->` | Report self-review score |
| **PR Created** | `<!-- GAAC_PR_CREATED: N -->` | Report PR number |
| **Issue** | `<!-- GAAC_ISSUE: description -->` | Report specific issue |

### Completion Keyword

The Stop hook looks for: `<gaac-complete>WORK_ON_ISSUE_<ISSUE_NUMBER>_DONE</gaac-complete>`

Only output this when ALL of the following are true:
- All acceptance criteria met
- All tests pass
- Self-review score >= 81 (output as `<!-- GAAC_REVIEW_SCORE: NN -->`)
- Peer-check passed
- PR created successfully (output as `<!-- GAAC_PR_CREATED: N -->`)

---

## Notes

- Use TodoWrite throughout to track progress
- The Stop hook creates Ralph-Wiggum style iteration automatically
- Size warnings at 600+ lines, but no automatic stop
- Test-driven: write tests before implementation
- **Completion keyword MUST use XML tags**: `<gaac-complete>KEYWORD</gaac-complete>`
- **Review score MUST use structured marker**: `<!-- GAAC_REVIEW_SCORE: NN -->`
- **PR number MUST use structured marker**: `<!-- GAAC_PR_CREATED: N -->`
- Session isolation prevents hook from affecting other Claude sessions in the same project
