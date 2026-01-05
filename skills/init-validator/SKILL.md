---
name: init-validator
description: Validates GAAC prerequisites and command arguments. Checks for required tools (gh, jq), validates gaac.md configuration, and validates input arguments for all GAAC slash commands. Use before starting any GAAC workflow.
allowed-tools: Bash, Read
---

# Init Validator Skill

This skill validates the prerequisites for using GAAC workflows and validates input arguments for each slash command.

## Purpose

1. **Prerequisite Validation**: Check that required tools are installed (gh, jq)
2. **Configuration Validation**: Verify `.claude/rules/gaac.md` exists and is properly configured
3. **Argument Validation**: Validate inputs for each GAAC command

## Scripts

### Check Prerequisites

Run this script to validate all GAAC prerequisites:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/init-validator/scripts/check-prerequisites.sh"
```

**Exit codes:**
- `0`: All prerequisites met
- `1`: Missing required tool
- `2`: gaac.md not found or invalid

### Validate Command Arguments

Each command has its own validation script:

```bash
# For /research-idea-to-spec
bash "${CLAUDE_PLUGIN_ROOT}/skills/init-validator/scripts/validate-research.sh" "$1"

# For /refine-spec-to-arch
bash "${CLAUDE_PLUGIN_ROOT}/skills/init-validator/scripts/validate-refine.sh" "$1" "$2"

# For /plan-arch-to-issues
bash "${CLAUDE_PLUGIN_ROOT}/skills/init-validator/scripts/validate-plan.sh" "$1"

# For /work-on-issue
bash "${CLAUDE_PLUGIN_ROOT}/skills/init-validator/scripts/validate-work.sh" "$1"
```

## Validation Details

### Required Tools

| Tool | Purpose | Check Command |
|------|---------|---------------|
| `gh` | GitHub CLI for issue/PR/project operations | `gh --version` |
| `jq` | JSON parsing for API responses | `jq --version` |

### Optional Tools

| Tool | Purpose | Check Command |
|------|---------|---------------|
| `codex` | External code review (preferred) | `which codex` |
| `gemini` | Web-enhanced research | `which gemini` |

### gaac.md Configuration

The validator checks `.claude/rules/gaac.md` for:
- File existence
- GitHub repository URL present
- GitHub project URL present
- At least one L1 tag defined
- At least one documentation path defined
- Build command defined
- Test command defined

### Command-Specific Validation

#### /research-idea-to-spec

- Input: idea text or markdown file path
- If file path: check file exists and is readable
- If text: ensure non-empty

#### /refine-spec-to-arch

- Input 1: draft-*.md file path
- Input 2: issue number (optional, inferred from draft filename)
- Check draft file exists
- Validate issue number format if provided

#### /plan-arch-to-issues

- Input: glob pattern for impl-*.md files
- Check at least one matching file exists
- Verify arch-*.md files exist (as anchor)

#### /work-on-issue

- Input: issue number
- Validate issue number is positive integer
- Verify issue exists via `gh issue view`
- Check issue is open (warn if closed)
- Check for blocking dependencies

## Integration

Run prerequisite check at the start of any GAAC command:

```bash
# In command markdown
!`bash "${CLAUDE_PLUGIN_ROOT}/skills/init-validator/scripts/check-prerequisites.sh"`
```

If prerequisites fail, stop the workflow and display the error message.
