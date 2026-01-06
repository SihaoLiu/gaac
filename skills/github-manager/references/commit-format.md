# Commit Message Format Guidelines

This guide defines GAAC-standard commit message formats.

## Basic Format

```
[L1][L2] Brief summary (50 chars max)

Detailed description of the change.
Explain the "why" not just the "what".

[type] /path/to/file1.ext : What changed
[type] /path/to/file2.ext : What changed

Resolves #N
```

## Tag Types

| Type | Purpose |
|------|---------|
| `[add]` | New file or feature |
| `[update]` | Modification to existing code |
| `[fix]` | Bug fix |
| `[refactor]` | Code restructuring (no behavior change) |
| `[docs]` | Documentation only |
| `[test]` | Test additions or changes |
| `[delete]` | Removed files |

## Component Tags

Use L1/L2 tags from your project's `gaac.md`:

```
[Core][Auth] Add OAuth2 support
[API][REST] Fix rate limiting bug
[Docs] Update installation guide
```

## Examples

### Simple Change

```
[Core][Data] Fix memory leak in parser

The DataParser class was not releasing buffers after
processing large files, causing memory growth over time.

[fix] /src/core/data/parser.ts : Release buffer in finally block

Resolves #42
```

### Multi-file Change

```
[API][REST] Add rate limiting endpoint

Implement configurable rate limiting with Redis backend.
Default: 100 requests per minute per IP.

[add] /src/api/middleware/rate-limiter.ts : Rate limiting middleware
[add] /src/api/config/rate-limits.ts : Configuration schema
[update] /src/api/routes/index.ts : Apply middleware
[add] /tests/api/rate-limiter.test.ts : Unit tests

Resolves #15
```

### Documentation Only

```
[Docs] Update installation guide

Add troubleshooting section for common issues.
Clarify Node.js version requirements.

[docs] /docs/installation.md : Add troubleshooting
[docs] /README.md : Update version badge
```

## L1/L2 Tag Inference

When creating commits, infer tags from changed files using the file-to-tag mapping in `gaac.md`:

```
src/core/**    -> [Core]
src/api/**     -> [API]
docs/**        -> [Docs]
tests/**       -> [Tests]
```

## What NOT to Include

- Time estimates or planning references
- Phrases like "Step 1", "Week 2", "Phase 3"
- Author attribution (handled by git)
- AI/tool attribution (not allowed)

## Multi-Issue Commits

For changes affecting multiple issues:

```
[Core][Cache] Refactor cache invalidation

Unified cache invalidation logic across all stores.

[refactor] /src/core/cache/invalidator.ts : Extract common logic
[update] /src/core/cache/redis.ts : Use unified invalidator
[update] /src/core/cache/memory.ts : Use unified invalidator

Resolves #42, resolves #43
```
