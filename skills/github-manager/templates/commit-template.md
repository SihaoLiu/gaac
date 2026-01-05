# GAAC Commit Message Format

## Format

```
[L1][L2][#N] Short description (50 chars max)

- Detail point 1
- Detail point 2

Issue: #N
```

## Components

### Tags

- **L1 Tag**: Main component/area (e.g., `[Core]`, `[API]`, `[UI]`, `[Docs]`)
- **L2 Tag**: Sub-area (optional, e.g., `[Auth]`, `[Cache]`, `[Forms]`)
- **Issue Ref**: `[#N]` where N is the issue number

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

### Simple fix
```
[Core][Cache][#42] Fix race condition in cache invalidation

- Add mutex lock around cache write operations
- Update test to verify concurrent access

Issue: #42
```

### Documentation update
```
[Docs][#15] Update API reference for v2 endpoints

- Add examples for new authentication flow
- Remove deprecated endpoints section

Issue: #15
```

### Feature addition
```
[API][Auth][#78] Add OAuth2 PKCE flow support

- Implement code verifier generation
- Add token exchange endpoint
- Update client SDK with new auth method

Issue: #78
```

### Multi-component change
```
[Core][API][#100] Refactor error handling system

- Standardize error codes across modules
- Add error context propagation
- Update API error responses

Issue: #100
```

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
