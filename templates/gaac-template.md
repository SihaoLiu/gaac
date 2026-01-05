# GAAC Configuration Template

> **IMPORTANT**: Copy this file to `.claude/rules/gaac.md` in your project and configure the values below.

---

## Project Identity

**Project Name**: [Your Project Name]

**GitHub Repository URL**: [e.g., git@github.com:YourOrg/your-project.git or https://github.com/YourOrg/your-project]

**GitHub Project Board URL**: [e.g., https://github.com/orgs/YourOrg/projects/1 or https://github.com/users/YourName/projects/1]

---

## Tag System

GAAC uses a three-level tagging system for organizing issues and PRs: `[Area][SubArea][IssueRef]`

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

### File-to-Tag Mapping

Map file paths to L1/L2 tags for automatic tag inference:

```
src/core/**          -> [Core]
src/api/**           -> [API]
src/ui/**            -> [UI]
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

**MAX_RALPH_WIGGUM_ITER**: `10` (default, can be overridden via environment variable)

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
