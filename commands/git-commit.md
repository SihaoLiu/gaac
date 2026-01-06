---
description: Create a git commit following GAAC format with proper tags and issue references
argument-hint: [commit message]
allowed-tools: Bash(bash $CLAUDE_PLUGIN_ROOT/skills/github-manager/scripts/create-commit.sh:*), Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git add:*), Bash(git commit:*), Bash(gh issue view:*), Read, Write, Glob
---

# /git-commit

Create a git commit following GAAC format conventions. Automatically infers L1/L2 tags from changed files and includes proper issue references.

## Context

- Repository: !`gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || echo "unknown"`
- Current branch: !`git branch --show-current`
- Message (optional): $ARGUMENTS

---

## Phase 1: Gather Context

### 1.1 Check Git Status

```bash
git status
```

If no changes: Exit with message "No changes to commit".

### 1.2 Get Changed Files

```bash
# Staged changes
git diff --cached --name-only

# Unstaged changes
git diff --name-only
```

### 1.3 Get Diff Details

```bash
# For commit message context
git diff HEAD --stat
git diff HEAD
```

### 1.4 Check Recent Commits

```bash
# For style consistency
git log --oneline -10
```

---

## Phase 2: Infer Tags

### Tag Hierarchy

GAAC uses a flexible 3-level tag system: `[L1][L2][L3]`

- **L1 (Component)**: Major area (Core, API, UI, etc.)
- **L2 (SubArea)**: Feature within L1 (Auth, Data, Cache, etc.)
- **L3 (SubSubArea)**: Specific focus within L2 (optional)

Valid combinations: `[L1]`, `[L1][L2]`, `[L1][L2][L3]`
Invalid: `[L1][L3]` (cannot skip L2)

### 2.1 L1/L2 Tag Inference

Based on changed file paths:

| File Pattern | L1 Tag | Common L2 Tags |
|-------------|--------|----------------|
| `docs/**`, `*.md` | `[Docs]` | `[API]`, `[Guide]` |
| `tests/**`, `test/**`, `*_test.*` | `[Tests]` | `[Unit]`, `[E2E]` |
| `src/api/**`, `api/**` | `[API]` | `[Users]`, `[Auth]` |
| `src/ui/**`, `ui/**`, `frontend/**` | `[UI]` | `[Forms]`, `[Layout]` |
| `src/core/**`, `core/**`, `lib/**` | `[Core]` | `[Auth]`, `[Data]` |
| `.github/**`, `.claude/**`, `config/**` | `[Infra]` | `[CI]`, `[Config]` |
| `build/**`, `scripts/**`, `Makefile` | `[Build]` | `[Scripts]` |

If multiple patterns match, use the most specific or ask user. L3 tags are optional and used for highly specific changes.

### 2.2 Issue Reference

Try to extract issue number from:
1. Branch name (e.g., `issue-42-feature` → `#42`)
2. User-provided message
3. Ask user if unclear

---

## Phase 3: Compose Message

### 3.1 Format

```
[L1][L2] Short description        # No issue reference
[L1][L2][Issue #N] Short description  # With issue reference
[L1][L2][L3] Short description    # With L3 tag
[L1][L2][L3][Issue #N] Short description  # Full format

- Detail 1
- Detail 2

Issue: #N  (optional, in body)
```

### 3.2 Guidelines

- **Subject line**: Max 50 characters, imperative mood
- **Body**: Explain what and why, not how
- **Tags**: Inferred from files or provided by user
- **Issue reference**: Include if working on an issue

### 3.3 Use Provided Message

If user provided `$ARGUMENTS`:
- Use as the short description
- Add inferred tags as prefix
- Generate body from diff context

If no message provided:
- Generate message from diff analysis
- Present to user for confirmation

---

## Phase 4: Stage and Commit

### 4.1 Stage Changes

If there are unstaged changes, ask user:

**Options:**
1. **Stage all** - `git add -A`
2. **Stage tracked only** - `git add -u`
3. **Select files** - User specifies files
4. **Cancel** - Abort commit

### 4.2 Verify Staged

```bash
git diff --cached --stat
```

If nothing staged: Exit with message.

### 4.3 Create Commit

Use the github-manager create-commit.sh script for consistent formatting:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-manager/scripts/create-commit.sh" \
    --message "<composed commit message>" \
    --issue <issue-number-if-applicable>
```

Or manually with HEREDOC for proper formatting:

```bash
git commit -m "$(cat <<'EOF'
[L1][L2][#N] Short description

- Detail 1
- Detail 2

Issue: #N
EOF
)"
```

---

## Phase 5: Confirmation

### 5.1 Show Result

```bash
git log -1 --format=full
```

### 5.2 Summary

| Item | Value |
|------|-------|
| Commit | <short-hash> |
| Message | <first line> |
| Files | <count> files changed |
| Stats | +<N>/-<M> lines |

---

## Examples

### Simple commit (L1 + L2)
```
/git-commit Fix null pointer in cache lookup
```
Result: `[Core][Cache] Fix null pointer in cache lookup`

### With issue reference
```
/git-commit Fix null pointer in cache lookup
```
Result: `[Core][Cache][Issue #42] Fix null pointer in cache lookup`

### With L3 tag (specific focus)
```
/git-commit Add OAuth token refresh logic
```
Result: `[Core][Auth][OAuth] Add token refresh logic`

### Documentation commit
```
/git-commit Update API reference
```
Result: `[Docs][API] Update API reference`

### No message (auto-generate)
```
/git-commit
```
Claude analyzes diff and proposes: `[UI][Forms][Issue #15] Add validation to login form`

---

## Notes

- This command uses the `github-manager/scripts/create-commit.sh` skill
- Tags are inferred from file paths using gaac.md mappings
- Issue reference is inferred from branch name (e.g., `issue-42-*` → `#42`)
- Message follows GAAC commit format from `references/commit-format.md`
- Uses HEREDOC for multi-line messages to preserve formatting
