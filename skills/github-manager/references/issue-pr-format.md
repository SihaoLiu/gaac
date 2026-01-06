# Issue and PR Format Guidelines

This guide defines GAAC-standard issue and PR formats. Component tags come from `.claude/rules/gaac.md`.

## Title Tag Rules

Use up to three tags in order: `[L1][L2][L3]`.

- L2 requires L1
- L3 requires L1 and L2
- `[Issue #N]` appears in PR titles, after L-tags

### Examples

```
[Core][Auth] Add cache invalidation
[Core][Auth][Web] Add cache invalidation
[Core][Auth][Web][Issue #123] Add cache invalidation
```

## Issue Title Format

```
[L1][L2][L3] <Brief description>
```

Examples:
- `[Core][Data] Fix memory leak in parser`
- `[API][REST] Add rate limiting endpoint`
- `[Docs] Update installation guide`

## PR Title Format

```
[L1][L2][L3][Issue #N] <Brief description>
```

Examples:
- `[Core][Data][Issue #42] Fix memory leak in parser`
- `[API][REST][Issue #15] Add rate limiting endpoint`

## Issue Body (SWE-bench Style)

Required sections:

1. **Problem Statement** - Clear description of what needs to be solved
2. **Expected Behavior** - What should happen when implemented
3. **Acceptance Criteria** - Checkboxes for completion verification
4. **Test Plan** - Commands and expected outputs (FAIL_TO_PASS tests)
5. **Design Reference** - Link to architecture documentation

Optional sections:

- **Observed Behavior** - For bugs, what currently happens
- **Interface Specification** - For API changes
- **Dependencies** - Links to blocking/related issues
- **Implementation Hints** - Relevant files and approach suggestions

## PR Body

Required sections:

1. **Summary** - Brief overview (MUST include `Resolves #N` for auto-linking)
2. **Changes Made** - List of modifications
3. **Test Plan** - How changes were verified
4. **Related Issues** - Cross-references

### Resolves Syntax

Use `Resolves #N` (not `Closes #N` or `Fixes #N`) for consistency:

```markdown
## Summary

Resolves #42

This PR adds cache invalidation...
```

For multiple issues:
```markdown
Resolves #42, resolves #43
```

## Size Guidelines

- **Recommended**: < 300 lines changed per PR
- **Acceptable**: < 600 lines changed
- **Warning threshold**: > 800 lines (notify user)

If a change is too large, split into multiple issues and PRs.
