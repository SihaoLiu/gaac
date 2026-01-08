---
description: Resolve PR review comments in priority order
argument-hint: [pr-number]
allowed-tools: Bash(bash $CLAUDE_PLUGIN_ROOT/scripts/*:*), Bash(bash $CLAUDE_PLUGIN_ROOT/skills/github-manager/scripts/*:*), Bash(git status:*), Bash(git diff:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(git branch:*), Bash(gh repo view:*), Bash(gh pr view:*), Bash(gh pr list:*), Bash(gh api:*), Read, Write, Edit, Glob, Grep, Task, AskUserQuestion, TodoWrite
---

# /resolve-pr-comment

Fetch and resolve PR review comments in priority order. Handles blocking, high, medium, and low priority feedback systematically.

## Context

- Repository: !`gh repo view --json nameWithOwner -q '.nameWithOwner'`
- Current branch: !`git branch --show-current`
- PR number: $1

---

## Phase 1: Fetch Comments

### 1.1 Identify PR

If PR number provided:
```bash
gh pr view $1 --json number,url,state
```

If not provided, detect from current branch:
```bash
gh pr list --head "$(git branch --show-current)" --json number,url --jq '.[0]'
```

### 1.2 Fetch All Comments

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-manager/scripts/get-pr-comments.sh" \
    --pr-number <number> \
    --format json
```

### 1.3 Categorize by Priority

Comments are categorized as:

| Priority | Criteria | Action |
|----------|----------|--------|
| **BLOCKING** | "block", "must", "required", "critical", "security" | Must fix |
| **HIGH** | "bug", "error", "incorrect", "wrong", "fix" | Should fix |
| **MEDIUM** | "should", "consider", "suggest", "improve" | Consider |
| **LOW** | Style, docs, minor suggestions | Optional |

---

## Phase 2: Present Summary

### 2.1 Show Comment Counts

```
=== PR #<N> Review Comments ===

BLOCKING: X comments (must resolve)
HIGH: Y comments (should resolve)
MEDIUM: Z comments (consider)
LOW: W comments (optional)

Total: X+Y+Z+W comments
```

### 2.2 Ask User Preference

Use AskUserQuestion:

**Question**: "How would you like to resolve comments?"

**Options**:
1. **All** - Resolve all comments (BLOCKING + HIGH + MEDIUM + LOW)
2. **Required** - BLOCKING and HIGH only
3. **Blocking only** - Only BLOCKING comments
4. **Select** - Choose specific comments

---

## Phase 3: Resolve Comments

### 3.1 Processing Order

Process in priority order:
1. BLOCKING (always first)
2. HIGH
3. MEDIUM
4. LOW

### 3.2 For Each Comment

Track with TodoWrite. For each comment:

1. **Read the comment** - Understand what's being requested
2. **Locate the code** - Find the relevant file and line
3. **Make the change** - Use Edit tool
4. **Verify** - Ensure change addresses the feedback
5. **Mark as done** - Update todo

### 3.3 Comment Types

**Code review comments** (on specific lines):
- Edit the specific line/section mentioned
- Consider context around the line
- Follow suggestion or implement alternative

**General review comments** (overall feedback):
- May require broader changes
- Address each point mentioned

**Requested changes** (from formal review):
- Highest priority
- Must be addressed for approval

---

## Phase 4: Verification

### 4.1 Run Tests

After making changes:
```bash
# Run quick test command from gaac.md
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gaac-config.sh" run-quick-test
```

If tests fail, fix the issues before proceeding.

### 4.2 Build Check

```bash
# Run quick build command from gaac.md (if configured)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gaac-config.sh" run-quick-build 2>/dev/null || echo "Build not configured"
```

### 4.3 Self-Review

Verify each resolved comment:
- Change addresses the feedback
- No regressions introduced
- Code still follows conventions

---

## Phase 5: Commit and Push

### 5.1 Stage Changes

```bash
git add -A
git diff --cached --stat
```

### 5.2 Create Commit

Commit message format (reference the issue the PR resolves):

```
[L1][L2][Issue #N] Address review feedback

- Resolved: <brief list of changes>
- BLOCKING: <count> fixed
- HIGH: <count> fixed
- MEDIUM: <count> fixed
- LOW: <count> fixed

Issue: #N (from PR's "Resolves #N")
```

Note: Get issue number from the PR's linked issue (the one in PR title `[Issue #N]`)

### 5.3 Push

```bash
git push
```

---

## Phase 6: Update PR

### 6.1 Add Resolution Comment

Use post-comment.sh for attribution support:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-manager/scripts/post-comment.sh" \
    --type pr --number <number> --body "## Review Feedback Addressed

Resolved the following comments:

### BLOCKING
- [x] <comment summary 1>
- [x] <comment summary 2>

### HIGH
- [x] <comment summary>

### MEDIUM
- [x] <comment summary>

---
Ready for re-review."
```

### 6.2 Request Re-Review

If there were blocking comments:

```bash
gh pr review <number> --comment --body "@reviewer Ready for re-review. All blocking issues addressed."
```

---

## Phase 7: Summary

| Category | Resolved | Skipped |
|----------|----------|---------|
| BLOCKING | X | 0 |
| HIGH | Y | 0 |
| MEDIUM | Z | N |
| LOW | W | M |

**Status**: All required comments resolved

**Next steps**:
- Wait for re-review
- Run `/resolve-pr-comment` again if more feedback

---

## Notes

- BLOCKING comments must always be resolved
- User can choose to skip MEDIUM/LOW comments
- Each resolution is tracked via TodoWrite
- Changes are committed together
- PR is automatically updated with resolution summary
