# Issue and PR Format Guidelines

This guide defines GAAC-standard issue and PR formats. Component tags come from `.claude/rules/gaac.md`.

## Title Tag Rules

Use a hierarchical tag system: `[L1][L2][L3]`

- **L1 (Component)**: **Required** - major area (Core, API, UI, etc.)
- **L2 (SubArea)**: Optional - feature within L1
- **L3 (SubSubArea)**: Optional - specific focus within L2
- **[Issue #N]**: Required in PR titles, optional in commits, not used in issue titles

### Constraints

- L2 requires L1 (cannot have `[L2]` alone)
- L3 requires L1 and L2 (cannot have `[L1][L3]`)
- `[Issue #N]` appears AFTER all L-tags

### Valid Tag Combinations

| Format | Valid | Example |
|--------|-------|---------|
| `[L1]` | ✅ | `[Docs] Update guide` |
| `[L1][L2]` | ✅ | `[Core][Auth] Add login` |
| `[L1][L2][L3]` | ✅ | `[Core][Auth][OAuth] Add provider` |
| `[L2]` | ❌ | (missing L1) |
| `[L1][L3]` | ❌ | (missing L2) |

## Issue Title Format

```
[L1] <Brief description>            # L1 only
[L1][L2] <Brief description>        # L1 + L2
[L1][L2][L3] <Brief description>    # Full (rare)
```

Examples:
- `[Docs] Update installation guide`
- `[Core][Data] Fix memory leak in parser`
- `[API][REST][Rate] Add rate limiting endpoint`

## PR Title Format

```
[L1][Issue #N] <Brief description>
[L1][L2][Issue #N] <Brief description>
[L1][L2][L3][Issue #N] <Brief description>
[L1][Issue #789,#456] <Brief description>   # Multiple issues
```

**Note**: PRs MUST include `[Issue #N]` to link to the resolved issue.

**Why `[Issue #N]` in PR title?** When the PR is merged, the issue number becomes visible in git blame and file history, allowing users to navigate directly from a file's commit history to the related issue without going through the PR first.

Examples:
- `[Docs][Issue #42] Update installation guide`
- `[Core][Data][Issue #42] Fix memory leak in parser`
- `[API][REST][Issue #15] Add rate limiting endpoint`
- `[Core][Issue #42,#43] Fix caching and error handling`

### Multiple Issues (Rare Exception)

The default is **one issue per PR**. However, when issues have **chicken-egg dependencies** (implementing A requires B and vice versa), a single PR may resolve both:

- **Title**: `[L1][Issue #789,#456] Description` (L1 still required)
- **Body**: Must have separate resolves for GitHub auto-linking:
  ```
  Resolves #789, resolves #456
  ```

This is rare and should only be used when issues are truly interdependent.

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
