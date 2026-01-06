# GAAC Commit Message Format

## Format

```
[L1] Short description                      # L1 only
[L1][L2] Short description                  # L1 + L2
[L1][Issue #N] Short description            # L1 + issue ref
[L1][L2][Issue #N] Short description        # L1 + L2 + issue ref
[L1][L2][L3][Issue #N] Short description    # Full format
[L1][Issue #789,#456] Short description     # Multiple issues

- Detail point 1
- Detail point 2

Issue: #N
```

## Components

### Tags

- **L1 Tag**: Required - main component/area (e.g., `[Core]`, `[API]`, `[UI]`, `[Docs]`)
- **L2 Tag**: Optional - sub-area within L1 (e.g., `[Auth]`, `[Cache]`, `[Forms]`)
- **L3 Tag**: Optional - specific focus within L2
- **Issue Ref**: `[Issue #N]` - optional for commits, required for PR titles
- **Multiple Issues**: `[Issue #789,#456]` - when resolving multiple issues

### Subject Line

- Keep under 50 characters
- Use imperative mood ("Add", "Fix", "Update", not "Added", "Fixed")
- No period at the end
- Be specific about what changed

### Body (Optional)

- Separate from subject with blank line
- Wrap at 72 characters
- Explain what and why, not how
- Use bullet points for multiple changes

## Examples

### Simple fix (L1 + L2 + issue)
```
[Core][Cache][Issue #42] Fix race condition in cache invalidation

- Add mutex lock around cache write operations
- Update test to verify concurrent access

Issue: #42
```

### Documentation update (L1 + issue)
```
[Docs][Issue #15] Update API reference for v2 endpoints

- Add examples for new authentication flow
- Remove deprecated endpoints section

Issue: #15
```

### Feature addition (L1 + L2 + L3 + issue)
```
[API][Auth][OAuth][Issue #78] Add OAuth2 PKCE flow support

- Implement code verifier generation
- Add token exchange endpoint
- Update client SDK with new auth method

Issue: #78
```

### Multiple issues (rare - chicken-egg dependencies only)
```
[Core][Issue #42,#43] Fix interdependent cache and error handling

- Fix cache race condition (#42)
- Standardize error codes (#43)
- Both issues required each other's changes

Issues: #42, #43
```

Note: L1 tag is still required. Default is one issue per PR.

## Tag Inference

When creating commits, infer tags from changed files:

| File Pattern | L1 Tag |
|--------------|--------|
| `docs/**` | `[Docs]` |
| `tests/**`, `test/**` | `[Tests]` |
| `src/api/**`, `api/**` | `[API]` |
| `src/ui/**`, `ui/**`, `frontend/**` | `[UI]` |
| `src/core/**`, `core/**`, `lib/**` | `[Core]` |
| `.github/**`, `.claude/**`, `config/**` | `[Infra]` |

## Best Practices

1. **One commit per logical change** - Don't mix unrelated changes
2. **Reference issues** - Always include issue number when applicable
3. **Be specific** - "Fix bug" is bad, "Fix null pointer in cache lookup" is good
4. **Test before committing** - Ensure build and tests pass
