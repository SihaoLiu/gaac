---
description: Merge a pull request with validation and update related issues
argument-hint: <pr-number>
allowed-tools: Bash(bash $CLAUDE_PLUGIN_ROOT/skills/init-validator/scripts/*:*), Bash(bash $CLAUDE_PLUGIN_ROOT/skills/github-manager/scripts/*:*), Bash(git status:*), Bash(git fetch:*), Bash(git branch:*), Bash(gh pr view:*), Bash(gh pr list:*), Bash(gh issue view:*), Read
---

# /close-pr

Merge a pull request with validation checks (non-draft, CI green) and update all related issues.

## Context

- Repository: !`gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || echo "unknown"`
- PR number: $1
- Merge strategy: !`bash "${CLAUDE_PLUGIN_ROOT}/scripts/gaac-config.sh" get "gaac.merge_strategy" 2>/dev/null || echo "squash"`

---

## Phase 0: Validation

### 0.1 Check Arguments

```bash
if [ -z "$1" ]; then
    echo "Error: PR number required"
    echo "Usage: /close-pr <pr-number>"
    exit 1
fi
```

### 0.2 Verify PR Exists

```bash
gh pr view $1 --json number,state,title 2>/dev/null || {
    echo "Error: PR #$1 not found"
    exit 1
}
```

---

## Phase 1: PR Status Check

### 1.1 Fetch PR Details

```bash
gh pr view $1 --json title,state,isDraft,mergeable,mergeStateStatus,statusCheckRollup,headRefName,baseRefName,url
```

### 1.2 Validate PR State

Check the following conditions:
- PR is OPEN (not already merged or closed)
- PR is NOT a draft
- PR has no merge conflicts (mergeable != CONFLICTING)
- CI checks are passing (no FAILURE in statusCheckRollup)

**If any condition fails**: Display error and stop.

**If CI checks are pending**: Display warning and stop. User should wait for CI to complete or manually merge if needed.

---

## Phase 2: Execute Merge

### 2.1 Run Merge Script

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-manager/scripts/merge-pr.sh" \
    --pr $1
```

The script will:
- Read merge strategy from gaac.md (default: squash)
- Validate PR is ready
- Execute `gh pr merge --$STRATEGY --delete-branch`
- Output merge confirmation

**If merge fails**: Display error and stop.

---

## Phase 3: Update Related Issues

### 3.1 Run Update Script

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-manager/scripts/update-related-issues.sh" \
    --pr $1
```

This will:
- Parse PR for `Resolves #N`, `Fixes #N`, `Closes #N` patterns
- Add completion comment to resolved issues
- Close resolved issues
- Notify related issues with progress comment
- Notify dependent issues that blockers have been resolved

---

## Phase 4: Summary

### 4.1 Display Results

| Item | Status |
|------|--------|
| PR | #$1 merged |
| Strategy | <merge-strategy> |
| Branch | <deleted-branch> |
| Issues resolved | #N, #M, ... |
| Issues notified | #X, #Y, ... |

### 4.2 Next Steps

- Resolved issues have been closed
- Dependent issues have been notified
- Branch has been deleted

---

## Error Handling

### Merge Conflicts

If the PR has merge conflicts:
1. Checkout the branch locally
2. Rebase on the default branch
3. Push the updated branch
4. Re-run `/close-pr`

### CI Failures

If CI checks are failing:
1. Review the failing checks
2. Fix the issues on the PR branch
3. Wait for CI to pass
4. Re-run `/close-pr`

### Permission Errors

If merge fails with permission error:
- Ensure you have write access to the repository
- Check if branch protection rules require specific approvals

---

## Notes

- Merge strategy is read from `gaac.merge_strategy` in gaac.md
- Default strategy is `squash` if not configured
- Branch is automatically deleted after successful merge
- CI checks must pass before merging (no bypass option)
