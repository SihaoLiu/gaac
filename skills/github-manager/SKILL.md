---
name: github-manager
description: Core GitHub integration skill for GAAC. Manages issues, PRs, project board integration, and PR comments. Provides templates and scripts for all GitHub operations. Use for any GitHub-related actions in GAAC workflows.
allowed-tools: Bash, Read, Write
---

# GitHub Manager Skill

This skill is the central hub for all GitHub operations in GAAC. It provides templates, scripts, and guidance for:

- Creating and managing issues
- Creating and managing pull requests
- Adding items to GitHub Projects
- Fetching and resolving PR comments
- Creating git commits

## Core Principle

**GitHub as Context**: GAAC uses GitHub's native features (Issues, PRs, Projects) as persistent context storage for LLM coding agents. This skill enables that bridge.

## Scripts

### Create Issue

Create a new issue using the SWE-bench format template:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-manager/scripts/create-issue.sh" \
    --title "[L1][L2] Issue title" \
    --body-file ./issue-body.md \
    --labels "L1:Component,L2:SubArea"
```

### Add to Project

Add an issue or PR to the GitHub Project board:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-manager/scripts/add-to-project.sh" \
    --item-number 42 \
    --item-type issue
```

### Create PR

Create a pull request with the standard template:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-manager/scripts/create-pr.sh" \
    --title "[L1][L2][Issue #N] Description" \
    --body-file ./pr-body.md \
    --resolves 42
```

### Get PR Comments

Fetch comments from a PR for resolution:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-manager/scripts/get-pr-comments.sh" \
    --pr-number 123 \
    --format json
```

### Create Commit

Create a git commit following the GAAC format:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-manager/scripts/create-commit.sh" \
    --issue 42 \
    --message "Add feature X implementation"
```

## Templates

### Issue Template (SWE-Bench Format)

Located at: `templates/issue-template.md`

```markdown
## Problem Statement
[Clear description of what needs to be solved]

## Expected Behavior
[What should happen when this is implemented]

## Current Behavior
[What currently happens, if applicable]

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2
- [ ] All tests pass

## Test Plan
```
[Test commands and expected results]
```

## Implementation Hints
[Optional guidance for implementation]

## Dependencies
- Depends on: #N (if any)
- Blocks: #M (if any)

## References
- Architecture doc: `docs/architecture/X.md`
- Related issue: #P
```

### PR Template

Located at: `templates/pr-template.md`

```markdown
## Summary
[1-3 bullet points describing the changes]

## Changes
- [Change 1]
- [Change 2]

## Test Plan
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Manual testing completed

## Checklist
- [ ] Code follows project conventions
- [ ] Documentation updated if needed
- [ ] No new warnings introduced

Resolves #N
```

### Commit Message Template

Located at: `templates/commit-template.md`

```
[L1][Issue #N] Short description            # L1 + issue
[L1][L2][Issue #N] Short description        # L1 + L2 + issue
[L1][Issue #789,#456] Short description     # L1 + multiple issues (rare)

- Detail 1
- Detail 2

Issue: #N
```

Note: L1 is required, L2/L3 optional. Multi-issue `[Issue #N,#M]` is rare (chicken-egg dependencies only).

## Project Board Integration

### Getting Project ID

```bash
# For organization project
gh api graphql -f query='
  query($org: String!, $number: Int!) {
    organization(login: $org) {
      projectV2(number: $number) { id }
    }
  }' -f org=OrgName -F number=1 --jq '.data.organization.projectV2.id'

# For user project
gh api graphql -f query='
  query($login: String!, $number: Int!) {
    user(login: $login) {
      projectV2(number: $number) { id }
    }
  }' -f login=Username -F number=1 --jq '.data.user.projectV2.id'
```

### Adding Item to Project

```bash
gh api graphql -f query='
  mutation($project: ID!, $content: ID!) {
    addProjectV2ItemByContentId(input: {projectId: $project, contentId: $content}) {
      item { id }
    }
  }' -f project=PROJECT_ID -f content=ISSUE_NODE_ID
```

### Getting Issue Node ID

```bash
gh issue view 42 --json id --jq '.id'
```

## Comment Priority for Resolution

When resolving PR comments, process in this order:

1. **Blocking** - Changes requested by maintainers
2. **High** - Security or correctness concerns
3. **Medium** - Code quality suggestions
4. **Low** - Style or documentation nits

## Error Handling

### Permission Errors

If project operations fail with permission error:

```bash
gh auth refresh -s project
```

### Rate Limiting

If GitHub API rate limit is hit:

```bash
gh api rate_limit --jq '.resources.core'
```

Wait for reset or use `--cache 1h` for read operations.

## Integration Points

| GAAC Command | GitHub Manager Usage |
|--------------|---------------------|
| `/research-idea-to-spec` | Create issue, add to project |
| `/refine-spec-to-arch` | Create PR for arch docs |
| `/plan-arch-to-issues` | Create multiple issues, add to project |
| `/work-on-issue` | Create PR, get/resolve comments |
| `/git-commit` | Create commit with proper format |
| `/resolve-pr-comment` | Get comments, update PR |

## Best Practices

1. **Always use templates** - Ensures consistency across issues and PRs
2. **Link issues and PRs** - Use "Resolves #N" for automatic linking
3. **Add to project immediately** - Every new issue should be on the project board
4. **Update related items** - When closing an issue, update related issues/PRs

## Files in This Skill

| File | Purpose |
|------|---------|
| `SKILL.md` | This documentation |
| `scripts/create-issue.sh` | Issue creation script |
| `scripts/create-pr.sh` | PR creation script |
| `scripts/add-to-project.sh` | Project board integration |
| `scripts/get-pr-comments.sh` | Fetch PR comments |
| `scripts/create-commit.sh` | Git commit creation |
| `templates/issue-template.md` | SWE-bench issue format |
| `templates/pr-template.md` | PR body template |
| `templates/commit-template.md` | Commit message format |
