# GitHub Project Board Integration

This guide defines how GAAC integrates with GitHub Projects.

## Core Principle

**Only Issues are tracked in the Project board.**

PRs are NOT added to the project directly. They are linked via `Resolves #N` syntax which automatically updates the issue status when the PR is merged.

## Adding Issues to Project

When creating an issue via GAAC commands, it MUST be added to the project board.

### Required Steps

1. Create the issue via `gh issue create`
2. Get the issue URL
3. Add to project via `gh project item-add`

### Script Usage

```bash
bash "$CLAUDE_PLUGIN_ROOT/skills/github-manager/scripts/add-to-project.sh" \
    --issue-number <N>
```

### Permissions

Adding items to a GitHub Project requires the `project` scope:

```bash
gh auth refresh -s project
```

If permissions are missing:
1. Inform user about the permission requirement
2. Provide the manual fallback (add via GitHub web UI)
3. Continue with other operations

## Project Field Updates

Optional: If the project has custom fields, GAAC can update them.

### Supported Fields (from gaac.md)

| Field | Purpose | Example Values |
|-------|---------|----------------|
| Status | Issue status | Backlog, In Progress, Done |
| Priority | Issue priority | P0, P1, P2, P3 |
| Effort | Size estimate | XS, S, M, L, XL |
| Component | L1 tag | Core, API, UI |
| Subarea | L2 tag | Auth, Data, Cache |

### Configuration

In `.claude/rules/gaac.md`:

```
gaac.project_fields.status: Status
gaac.project_fields.priority: Priority
gaac.project_fields.effort: Effort
gaac.project_fields.l1: Component
gaac.project_fields.l2: Subarea
```

If these keys are not configured, GAAC will only add issues to the project without updating fields.

## Workflow Integration

### /research-idea-to-spec
- Creates issue → Adds to project

### /refine-spec-to-arch
- Does NOT add PRs to project
- Links PR to issue via `Resolves #N`

### /plan-arch-to-issues
- Creates multiple issues → Adds each to project

### /work-on-issue
- Does NOT add PRs to project
- Links PR to issue via `Resolves #N`
- Issue status updates automatically when PR merges

## Error Handling

If project board integration fails:

1. **Permission Error**: Guide user to run `gh auth refresh -s project`
2. **Project Not Found**: Verify `gaac.project_url` is correct
3. **Rate Limiting**: Retry with exponential backoff
4. **Network Error**: Log warning, continue with other operations

Project board integration failures should NOT block issue/PR creation.
