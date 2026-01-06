# GAAC Configuration Template

> **IMPORTANT**: Copy this file to `.claude/rules/gaac.md` in your project and configure the values below.

> **Note**: This file lives in YOUR project's `.claude/rules/` directory, not in the GAAC plugin.
> The GAAC plugin provides commands and skills; project-specific configuration stays here in your repository.

---

## Machine-Readable Keys (Required)

These keys are parsed by GAAC scripts. Keep the `gaac.*:` prefix intact.

```
gaac.repo_url: <git@github.com:org/repo.git or https://github.com/org/repo>
gaac.project_url: <https://github.com/orgs/ORG/projects/N or https://github.com/users/USER/projects/N>
gaac.tags.l1: [Core][API][UI][Infra][Docs][Tests]
gaac.tags.l2: [Auth][Data][Cache][Forms][Users][Settings]
gaac.tags.l3: [OAuth][JWT][Profile][Validation]
gaac.file_mappings: src/core/**:[Core], src/api/**:[API], docs/**:[Docs], tests/**:[Tests]
gaac.docs_paths: docs, docs/architecture, docs/draft
gaac.quick_test: <command to run fast local tests>
gaac.quick_build: <command to run fast local build>
gaac.default_branch: main
gaac.merge_strategy: squash

# Model Configuration (for three-agent debate and code review)
gaac.models.code_reviewer: codex:gpt-5.2-codex:xhigh
gaac.models.code_reviewer_fallback: claude:opus
gaac.models.proposer: claude:sonnet
gaac.models.proposer_secondary: gemini:gemini-3-pro-preview
gaac.models.checker: claude:opus
gaac.models.analyzer: codex:gpt-5.2-codex:xhigh
gaac.models.analyzer_fallback: claude:opus
```

**File Mappings Format**: `pattern:[Tag], pattern:[Tag]` - Maps file paths to L1 tags for automatic inference. New mappings are auto-appended when unmatched paths are encountered.

---

## Project Identity

**Project Name**: [Your Project Name]

**GitHub Repository URL**: [e.g., git@github.com:YourOrg/your-project.git or https://github.com/YourOrg/your-project]

**GitHub Project Board URL**: [e.g., https://github.com/orgs/YourOrg/projects/1 or https://github.com/users/YourName/projects/1]

---

## Tag System

GAAC uses a flexible three-level tagging system for organizing issues, commits, and PRs.

### Tag Format

Tags use a hierarchical structure: `[L1][L2][L3]`

- **L1 (Component)**: Primary component or major area
- **L2 (SubArea)**: Feature area within the L1 component
- **L3 (SubSubArea)**: Specific focus within L2 (optional)

### Allowed Tag Combinations

| Format | Example | Use Case |
|--------|---------|----------|
| `[L1]` | `[Core] Add utility` | Single component |
| `[L1][L2]` | `[Core][Auth] Add login` | Component + feature |
| `[L1][L2][L3]` | `[Core][Auth][OAuth] Add provider` | Full hierarchy |

### Constraint

**NOT ALLOWED**: `[L1][L3]` without L2 (SubSubArea requires SubArea, just as L2 requires L1)

### Issue Reference in Titles

The `[Issue #N]` tag appears AFTER L-tags and links PRs/commits to their source issue.

**Purpose**: When a PR is merged, the issue number in the title becomes visible in git blame/file history, allowing direct navigation to the related issue.

| Context | Format | Example |
|---------|--------|---------|
| **Issue title** | `[L1]` or `[L1][L2]` | `[Core][Auth] Add OAuth support` |
| **Commit** | `[L1][Issue #N]` (optional) | `[Core][Issue #42] Add login` |
| **PR title** | `[L1][Issue #N]` (required) | `[Core][Auth][Issue #42] Add OAuth support` |

### Multiple Issues (Rare Exception)

The default is one issue per PR. However, when issues have **chicken-egg dependencies** (e.g., implementing feature A requires feature B and vice versa), a single PR may resolve both:

```
[L1][Issue #789,#456] Combined fix for interdependent features
```

**Note**: L1 tag is still required. The PR body must contain separate `Resolves` lines:
```
Resolves #789, resolves #456
```

This does not violate the "one issue → one PR" principle; it's "multiple interdependent issues → one PR".

### Level 1 Tags (Area/Component)

Define your project's main areas/components. These represent major functional areas of your codebase.

Example tags:
- `[Core]` - Core functionality
- `[API]` - API layer
- `[UI]` - User interface
- `[Infra]` - Infrastructure
- `[Docs]` - Documentation
- `[Tests]` - Testing framework

**Your L1 Tags**:
- [ ] Define your L1 tags here

### Level 2 Tags (SubArea)

Define subcategories within each L1 area. These help further organize work.

Example for `[Core]`:
- `[Core][Auth]` - Authentication
- `[Core][Data]` - Data processing
- `[Core][Cache]` - Caching layer

**Your L2 Tags**:
- [ ] Define your L2 tags here

### Level 3 Tags (SubSubArea)

Define L3 tags as specific focuses within your L2 areas. L3 is optional and provides additional granularity when needed.

Example for `[Core][Auth]`:
- `[Core][Auth][OAuth]` - OAuth-specific authentication
- `[Core][Auth][JWT]` - JWT token handling
- `[Core][Auth][SAML]` - SAML integration

Example for `[API][Users]`:
- `[API][Users][Profile]` - User profile endpoints
- `[API][Users][Permissions]` - Permission management

**Your L3 Tags**:
- [ ] Define your L3 tags here (organized by L1/L2 parent)

### File-to-Tag Mapping

Map file paths to L1/L2/L3 tags for automatic tag inference:

```
src/core/**          -> [Core]
src/api/**           -> [API]
src/ui/**            -> [UI]
apps/web/**          -> [Web]
apps/cli/**          -> [CLI]
docs/**              -> [Docs]
tests/**             -> [Tests]
```

**Your File Mappings**:
- [ ] Define your file-to-tag mappings here

---

## Documentation Paths

Specify the folders containing your project's documentation. GAAC will search these paths when gathering context.

**Documentation Folders**:
- `docs/`
- `README.md`
- [ ] Add additional documentation paths here

**Draft/Work-in-Progress Folder**:
- `docs/draft/` (default location for draft-*.md, arch-*.md, impl-*.md files)

---

## Build Commands

### Full Build

Command to build the entire project from scratch:

```bash
# Example: make all, npm run build, cargo build --release
[Your full build command]
```

### Incremental Build

Command for quick incremental builds during development:

```bash
# Example: make, npm run build:fast, cargo build
[Your incremental build command]
```

### Quick Test

Command to run a fast test suite (unit tests, quick smoke tests):

```bash
# Example: make test-unit, npm test, cargo test
[Your quick test command]
```

### Full Test

Command to run the complete test suite:

```bash
# Example: make test, npm run test:all, cargo test --all-features
[Your full test command]
```

### Lint/Format

Command to check/fix code formatting:

```bash
# Example: make lint, npm run lint:fix, cargo fmt && cargo clippy
[Your lint command]
```

---

## Environment Setup

Commands needed to set up the development environment:

```bash
# Example: source venv/bin/activate, nvm use, module load ./env/project
[Your environment setup commands]
```

---

## GAAC Workflow Settings

### Ralph-Wiggum Iteration Limits

Maximum iterations for the review loop in `/work-on-issue`:

**MAX_RALPH_WIGGUM_ITER**: `50` (default, can be overridden via environment variable)

### Structured Markers (Stop Hook Detection)

The GAAC Stop hook uses explicit XML/HTML markers for reliable detection. When working on issues, output these markers:

| Marker | Format | When to Output |
|--------|--------|----------------|
| **Completion** | `<gaac-complete>WORK_ON_ISSUE_N_DONE</gaac-complete>` | When all criteria met |
| **Review Score** | `<!-- GAAC_REVIEW_SCORE: NN -->` | After self-review |
| **PR Created** | `<!-- GAAC_PR_CREATED: N -->` | After PR creation |
| **Issue Found** | `<!-- GAAC_ISSUE: description -->` | To report specific issues |

**Why markers?** Using explicit XML/HTML comments prevents accidental matches and ensures the Stop hook reliably detects completion signals.

### PR Size Guidelines

- **Recommended**: < 300 lines changed
- **Acceptable**: < 600 lines changed
- **Warning threshold**: > 800 lines changed (user notified but not blocked)

### Document Size Guidelines

- **Recommended**: < 1000 lines per document
- **Maximum**: 1500 lines per document (split if larger)

---

## Third-Party Tool Configuration

### Preferred External Tools

For independent code review and analysis, GAAC can use external tools. Configure your preferences:

**Code Review Tool** (for peer-check):
- `codex` (OpenAI Codex CLI) - preferred
- `claude` (Claude CLI) - fallback

**Web Search Tool** (for research):
- `gemini` (Google Gemini CLI) - optional, for web-enhanced proposals

### Tool Detection

GAAC will automatically detect available tools. Ensure they are installed and authenticated:

```bash
# Check tool availability
which gh    # GitHub CLI (required)
which jq    # JSON processor (required)
which codex # OpenAI Codex CLI (optional)
which gemini # Google Gemini CLI (optional)
```

---

## Custom Rules

Add any project-specific rules or conventions here:

### Code Style
- [ ] Define your code style preferences

### Commit Message Format
- [ ] Define your commit message conventions

### PR Review Requirements
- [ ] Define your PR review requirements

---

## Notes

- This file is loaded as a rule by Claude Code when using GAAC commands
- All paths are relative to the project root
- Environment variables referenced here should be set in your shell or `.env` file
- The GitHub Project board integration requires `gh auth refresh -s project` for project write access
