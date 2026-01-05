# GAAC - GitHub as a Context

A Claude Code plugin that implements the "GitHub as a Context" methodology for AI-native software development. GAAC uses GitHub's native features (Issues, PRs, Projects) as persistent context storage for LLM coding agents, providing a structured workflow from research to implementation.

## Core Philosophy

**GitHub as Context**: Instead of relying on local files for persistent context, GAAC leverages GitHub's existing infrastructure:
- **Issues** for tracking research, architecture, and implementation tasks
- **Pull Requests** for code review and integration
- **Projects** for progress tracking and organization
- **Comments** for discussion and decisions

This approach provides:
- Persistent context that survives session boundaries
- Collaboration between human and AI developers
- Audit trail of all decisions
- Integration with existing GitHub workflows

## Installation

```bash
# Install the plugin
claude /plugin install /path/to/gaac

# Or from git (when published)
claude /plugin install SihaoLiu/gaac
```

## Configuration

After installation, copy the template to your project:

```bash
cp path/to/gaac/templates/gaac-template.md .claude/rules/gaac.md
```

Configure the following in `gaac.md`:
- GitHub repository URL
- GitHub project board URL
- L1/L2 tag system for your project
- Documentation paths
- Build and test commands

## Workflow Overview

GAAC implements a four-stage development workflow:

```
Research → Architecture → Planning → Implementation
   ↓           ↓            ↓            ↓
 draft-*.md  arch-*.md    Issues     PR + Merge
```

### Stage 1: Research (`/research-idea-to-spec`)

Transform ideas into draft specifications:
- Web research for prior art
- GitHub search for related work
- Documentation and codebase exploration
- Three-party discussion (proposer-checker-analyzer)

**Output**: `draft-*.md` (unstaged) + GitHub Issue

### Stage 2: Architecture (`/refine-spec-to-arch`)

Refine drafts into complete architecture:
- Interactive clarification of uncertainties
- Third-party evaluation
- Architecture document generation
- Implementation plan creation

**Output**: `arch-*.md` (committed, PR) + `impl-*.md` (unstaged)

### Stage 3: Planning (`/plan-arch-to-issues`)

Convert plans into actionable issues:
- Test-driven development approach
- SWE-bench format issues
- Size-appropriate task breakdown
- Dependency mapping

**Output**: Multiple GitHub Issues (added to project)

### Stage 4: Implementation (`/work-on-issue`)

Complete issue resolution with review loops:
- Test-first development
- Ralph-Wiggum style iteration
- Three-stage code review
- Automatic PR creation

**Output**: PR resolving the issue

## Commands

| Command | Purpose |
|---------|---------|
| `/research-idea-to-spec <idea>` | Transform idea into draft specification |
| `/refine-spec-to-arch <draft.md>` | Create architecture and implementation plans |
| `/plan-arch-to-issues <impl-*.md>` | Generate test-driven GitHub issues |
| `/work-on-issue <number>` | Implement issue with review loops |
| `/git-commit [message]` | Create commit with GAAC format |
| `/resolve-pr-comment [pr]` | Resolve PR review feedback |

## Skills

| Skill | Purpose |
|-------|---------|
| `init-validator` | Validate prerequisites and arguments |
| `github-manager` | GitHub operations (issues, PRs, projects) |
| `docs-refactor` | Document splitting and link validation |
| `third-party-call` | External AI tool invocation |

## Ralph-Wiggum Integration

The `/work-on-issue` command includes Ralph-Wiggum style iteration for the review phase:

1. Implementation complete → Enter review loop
2. Self-check → Peer-check → Self-review
3. If any check fails, Stop hook blocks exit
4. Claude receives issues and continues fixing
5. Loop until review passes or max iterations

Configuration:
- `MAX_RALPH_WIGGUM_ITER` environment variable (default: 10)
- Completion keyword: `WORK_ON_ISSUE_<N>_DONE`

## Prerequisites

Required tools:
- `gh` - GitHub CLI (authenticated)
- `jq` - JSON processor

Optional tools:
- `codex` - OpenAI Codex CLI (for peer review)
- `gemini` - Google Gemini CLI (for web research)

Check prerequisites:
```bash
bash <gaac-plugin>/skills/init-validator/scripts/check-prerequisites.sh
```

## Directory Structure

```
gaac/
├── .claude-plugin/
│   └── plugin.json          # Plugin manifest
├── commands/                 # Slash commands
│   ├── research-idea-to-spec.md
│   ├── refine-spec-to-arch.md
│   ├── plan-arch-to-issues.md
│   ├── work-on-issue.md
│   ├── git-commit.md
│   └── resolve-pr-comment.md
├── skills/                   # Skills with scripts
│   ├── init-validator/
│   ├── github-manager/
│   ├── docs-refactor/
│   └── third-party-call/
├── hooks/                    # Lifecycle hooks
│   ├── hooks.json
│   └── stop-hook.sh
├── templates/
│   └── gaac-template.md      # Configuration template
└── README.md
```

## Design Principles

1. **Skills over Agents**: Prefer skills with scripts over sub-agents for deterministic behavior
2. **GitHub as Source of Truth**: All persistent state in GitHub, not local files
3. **Test-Driven Development**: Write tests before implementation
4. **Iteration over Perfection**: Use review loops to refine work
5. **Size-Appropriate PRs**: Target ~300 lines per PR
6. **Document Size Limits**: Max 1500 lines per document

## License

MIT

## Credits

- Ralph Wiggum technique: [Geoffrey Huntley](https://ghuntley.com/ralph/)
- Claude Code: [Anthropic](https://github.com/anthropics/claude-code)
