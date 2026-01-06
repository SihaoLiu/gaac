---
description: Update related issues after PR merge (wrapper for update-related-issues.sh)
argument-hint: <issue-or-pr-number>
allowed-tools: Bash(bash $CLAUDE_PLUGIN_ROOT/skills/github-manager/scripts/*:*), Bash(gh pr view:*), Bash(gh pr list:*), Bash(gh issue view:*), Bash(gh repo view:*), Read
---

# /update-related-issues

Update related issues after a PR has been merged. This is a convenience wrapper that accepts either a PR number or an issue number.

## Context

- Repository: !`gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || echo "unknown"`
- Argument: $1

## Usage

```
/update-related-issues 123        # PR number
/update-related-issues 42         # Issue number (finds associated PR)
```

**Note**: Input must be a numeric PR or issue number (no leading #).

---

## Phase 1: Determine Type

First, check if the argument is a PR or an issue:

### 1.1 Check if PR Exists

```bash
gh pr view $1 --json number,state,mergedAt 2>/dev/null
```

If this succeeds, the argument is a PR number - proceed to Phase 2.

### 1.2 If Not a PR, Treat as Issue

If the PR check fails, the argument is likely an issue number.

Try to find a merged PR that resolves this issue:

```bash
# Search for merged PRs that resolve this issue
gh pr list --state merged --search "resolves #$1" --json number,title --limit 5

# Also try alternative patterns
gh pr list --state merged --search "fixes #$1" --json number,title --limit 5
gh pr list --state merged --search "closes #$1" --json number,title --limit 5
```

If a merged PR is found, use that PR number. If multiple are found, use the most recent.

If no merged PR is found, inform the user:

```
No merged PR found that resolves issue #$1.

To update related issues, please provide the PR number directly:
  /update-related-issues <pr-number>

Or merge a PR that includes "Resolves #$1" in its description first.
```

---

## Phase 2: Execute Update

Once a valid merged PR number is determined, call the update script:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-manager/scripts/update-related-issues.sh" \
    --pr <pr-number>
```

---

## Phase 3: Report Results

Report the actions taken:

| Action | Count |
|--------|-------|
| Issues closed | N |
| Related issues notified | N |
| Dependent issues notified | N |
| Cascade closures | N |

### Next Steps

If there were errors or warnings, list them for the user to review.
