# GAAC - GitHub as a Context

**Current Version: 1.1.5**

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

## Quick Start: Iterative Development with Codex Review

The `loop-with-codex-review` command demonstrates GAAC's core philosophy: **Iteration over Perfection**. Inspired by the [Ralph Wiggum technique](https://ghuntley.com/ralph/), it creates an iterative feedback loop where Claude implements your plan while Codex independently reviews the work, ensuring quality through continuous refinement.

### How It Works

```mermaid
flowchart LR
    Plan["Your Plan<br/>(plan.md)"] --> Claude["Claude Implements<br/>& Summarizes"]
    Claude --> Codex["Codex Reviews<br/>& Critiques"]
    Codex -->|Feedback Loop| Claude
    Codex -->|COMPLETE or max iterations| Done((Done))
```

### Step 1: Create Your Plan

Use Claude's plan mode to design your implementation. Save the plan to a markdown file:

```bash
# In Claude Code, enter plan mode and describe your task
# Claude will create a detailed plan
# Save the plan to a file, e.g., docs/my-feature-plan.md
```

Your plan file should contain:
- Clear description of what to implement
- Acceptance criteria
- Technical approach (optional but helpful)
- At least 5 lines of content

### Step 2: Run the Loop

```bash
# Basic usage - runs up to 42 iterations
/gaac:loop-with-codex-review docs/my-feature-plan.md

# Limit iterations
/gaac:loop-with-codex-review docs/my-feature-plan.md --max 10

# Run until Codex says COMPLETE (use with caution)
/gaac:loop-with-codex-review docs/my-feature-plan.md --infinite
```

### Step 3: Monitor Progress

All iteration artifacts are saved in `.gaac-loop.local/<timestamp>/`:

```bash
# View current round
cat .gaac-loop.local/*/state.md

# View Claude's latest summary
cat .gaac-loop.local/*/round-*-summary.md | tail -50

# View Codex's review feedback
cat .gaac-loop.local/*/round-*-review-result.md | tail -50
```

### Step 4: Cancel If Needed

```bash
/gaac:cancel-loop-with-codex
```

### Prerequisites

- `codex` CLI must be installed and available in PATH
- Plan file must exist and have at least 5 lines

This simplified workflow captures GAAC's essence: let AI iterate until quality is achieved, with independent review ensuring nothing is missed.

## Installation

### Option 1: Install from Git Marketplace (Recommended)

Start Claude Code and run the following commands:

```bash
# Add the marketplace
/plugin marketplace add git@github.com:SihaoLiu/gaac.git

# Install the plugin
/plugin install gaac@gaac-marketplace
```

### Option 2: Local Development / Testing

If you have the plugin cloned locally:

```bash
# Start Claude Code with the plugin directory
claude --plugin-dir /path/to/gaac
```

### Verify Installation

Run `/plugin` in Claude Code and check the **Installed** tab to confirm the plugin is active.

## Configuration

After installation, copy the configuration template to your project's `.claude/rules/` directory.

### For Marketplace Installation

```bash
cp ~/.claude/plugins/marketplaces/gaac-marketplace/templates/gaac-template.md .claude/rules/gaac.md
```

### For Local Installation

```bash
cp /path/to/gaac/templates/gaac-template.md .claude/rules/gaac.md
```

### Configure gaac.md

Edit `.claude/rules/gaac.md` and configure the following:
- GitHub repository URL
- GitHub project board URL
- L1/L2 tag system for your project
- Documentation paths
- Build and test commands

## Workflow Overview

GAAC implements a five-stage development workflow from idea to merged PR:

```
Research → Architecture → Planning → Implementation → Close
   ↓           ↓            ↓            ↓              ↓
draft-*.md  arch-*.md    Issues      PR Created     PR Merged
```

```mermaid
flowchart LR
    subgraph Stage1[Stage 1: Research]
        R["research-idea-to-spec"]
    end

    subgraph Stage2[Stage 2: Architecture]
        A["refine-spec-to-arch"]
    end

    subgraph Stage3[Stage 3: Planning]
        P["plan-arch-to-issues"]
    end

    subgraph Stage4[Stage 4: Implementation]
        W["work-on-issue"]
    end

    subgraph Stage5[Stage 5: Close]
        C["close-pr"]
    end

    Stage1 -->|draft-*.md + Issue| Stage2
    Stage2 -->|arch-*.md PR + impl-*.md| Stage3
    Stage3 -->|GitHub Issues| Stage4
    Stage4 -->|PR Created| Stage5
    Stage5 -->|Merged| Done((Done))
```

---

### Stage 1: `/research-idea-to-spec`

Transform ideas into draft specifications through multi-source research and three-party discussion.

```mermaid
flowchart TB
    Start(["research-idea-to-spec"]) --> P0

    subgraph P0[Phase 0: Validation]
        IV[init-validator]
    end

    subgraph P1[Phase 1: Idea Capture]
        IC[Parse Input]
        DD[Determine Docs Dir]
        IC --> DD
    end

    subgraph P2[Phase 2: Multi-Source Research]
        WR[Web Research<br/>gemini/WebSearch]
        GR[GitHub Research<br/>gh issue/pr list]
        DR[Documentation Research<br/>Grep docs/]
        CR[Codebase Exploration<br/>Task:Explore]
    end

    subgraph P3[Phase 3: Three-Party Discussion]
        subgraph S31[3.1 Proposers - Parallel]
            CP[Claude Proposer<br/>Sonnet]
            GP[Gemini Proposer<br/>optional]
        end
        CHK[3.2 Checker<br/>Opus]
        ANA[3.3 Analyzer<br/>Codex/Opus]
        UG[3.4 User Gate]
        CP --> CHK
        GP --> CHK
        CHK --> ANA
        ANA --> UG
        UG -->|REVISE| S31
    end

    subgraph P4[Phase 4: Draft Generation]
        DG[Generate draft-*.md]
        SC[Size Check<br/>docs-refactor]
        DG --> SC
    end

    subgraph P5[Phase 5: Issue Creation]
        CI[github-manager<br/>create-issue]
        AP[github-manager<br/>add-to-project]
        CI --> AP
    end

    subgraph P6[Phase 6: Summary]
        SUM[Output Summary]
    end

    P0 --> P1
    P1 --> P2
    P2 --> P3
    P3 -->|APPROVED| P4
    P3 -->|ABANDONED| Stop((Stop))
    P4 --> P5
    P5 --> P6
```

**Output**: `draft-*.md` (unstaged) + GitHub Issue (added to project)

---

### Stage 2: `/refine-spec-to-arch`

Refine drafts into architecture documents and implementation plans.

```mermaid
flowchart TB
    Start(["refine-spec-to-arch"]) --> P0

    subgraph P0[Phase 0: Validation]
        IV2[init-validator]
    end

    subgraph P05[Phase 0.5: Auto-Create Issue]
        ACI[Create Issue if not provided]
        ATP[Add to Project]
        ACI --> ATP
    end

    subgraph P1[Phase 1: Draft Analysis]
        RD[Read Draft]
        IU[Identify Uncertainties]
        RC[Check Related Context]
        RD --> IU --> RC
    end

    subgraph P2[Phase 2: Interactive Refinement]
        IC2[Iterative Clarification<br/>AskUserQuestion]
        TPE[Third-Party Evaluation<br/>third-party-call]
        UA[User Approval]
        IC2 --> TPE --> UA
        UA -->|REVISE| IC2
    end

    subgraph P3[Phase 3: Architecture Doc]
        GA[Generate arch-*.md]
        SC3[Size Check]
        SP3[Split if needed<br/>docs-refactor]
        GA --> SC3 --> SP3
    end

    subgraph P4[Phase 4: Implementation Plan]
        GI[Generate impl-*.md]
        SC4[Size Check]
        SP4[Split if needed]
        GI --> SC4 --> SP4
    end

    subgraph P5[Phase 5: Version Control]
        FB[Create Feature Branch]
        CM[Commit arch-*.md<br/>github-manager]
        PS[Push Branch]
        PR[Create PR<br/>github-manager]
        FB --> CM --> PS --> PR
    end

    subgraph P6[Phase 6: Summary]
        SUM2[Output Summary]
    end

    P0 --> P05
    P05 --> P1
    P1 --> P2
    P2 -->|APPROVED| P3
    P2 -->|STOP| Stop2((Stop))
    P3 --> P4
    P4 --> P5
    P5 --> P6
```

**Output**: `arch-*.md` (committed, PR created) + `impl-*.md` (unstaged)

---

### Stage 3: `/plan-arch-to-issues`

Convert implementation plans into test-driven GitHub issues.

```mermaid
flowchart TB
    Start(["plan-arch-to-issues"]) --> P0

    subgraph P0[Phase 0: Validation]
        IV3[init-validator]
    end

    subgraph P1[Phase 1: Plan Analysis]
        LI[Locate impl-*.md files]
        RA[Read Architecture anchor<br/>arch-*.md]
        MT[Map Plan to Tasks]
        LI --> RA --> MT
    end

    subgraph P2[Phase 2: Interactive Refinement]
        PT[Present Task Breakdown]
        RD2[Refine Details<br/>AskUserQuestion]
        FT[Finalize Task List]
        PT --> RD2 --> FT
    end

    subgraph P3[Phase 3: Issue Generation]
        SWE[Generate SWE-Bench Format]
        SG[Size Guidelines<br/>~300 lines/issue]
        DM[Dependency Mapping]
        SWE --> SG --> DM
    end

    subgraph P4[Phase 4: Issue Creation]
        direction TB
        CI1[Create Issue 1<br/>github-manager]
        CI2[Create Issue 2]
        CIN[Create Issue N]
        AP4[Add All to Project]
        UD[Update Dependencies]
        CI1 --> CI2 --> CIN --> AP4 --> UD
    end

    subgraph P5[Phase 5: Summary]
        IS[Issue Summary Table]
        IO[Implementation Order]
        NS[Next Steps]
        IS --> IO --> NS
    end

    P0 --> P1
    P1 --> P2
    P2 --> P3
    P3 --> P4
    P4 --> P5
```

**Output**: Multiple GitHub Issues (SWE-bench format, added to project, with dependencies)

---

### Stage 4: `/work-on-issue`

Complete end-to-end issue resolution with Ralph-Wiggum enhanced review loops.

```mermaid
flowchart TB
    Start(["work-on-issue"]) --> P0

    subgraph P0[Phase 0: Validation]
        IV4[init-validator]
    end

    subgraph P1[Phase 1: Issue Analysis]
        FI[Fetch Issue Details]
        AA[Analyze Acceptance Criteria]
        UC[Understand Codebase Context]
        FI --> AA --> UC
    end

    subgraph P2[Phase 2: Planning]
        EP[EnterPlanMode]
        DP[Design Implementation]
        XP[ExitPlanMode]
        EP --> DP --> XP
    end

    subgraph P3[Phase 3: TDD - Tests First]
        WT[Write Failing Tests]
        VF[Verify Tests Fail]
        WT --> VF
    end

    subgraph P4[Phase 4: Implementation]
        IS4[Initialize State File]
        IMP[Implement Changes]
        QT[Quick Test]
        QB[Quick Build]
        SM[Size Monitor<br/>warn if >600 lines]
        IS4 --> IMP --> QT --> QB --> SM
    end

    subgraph P5[Phase 5: Review Loop - Ralph-Wiggum]
        SC5[5.1 Self-Check]
        PC5[5.2 Peer-Check<br/>third-party-call]
        FT5[5.2a Full Test Suite]
        CR5[5.3 Code-Reviewer<br/>third-party-call]
        RR5[5.4 Review Result<br/>score >= 81?]
        LT5[5.5 Lint Check<br/>optional]
        SC5 --> PC5 --> FT5 --> CR5 --> RR5
        RR5 -->|FAIL| SC5
        RR5 -->|PASS| LT5
    end

    subgraph P6[Phase 6: Commit & Push]
        GC6[git commit<br/>github-manager]
        GP6[git push]
        GC6 --> GP6
    end

    subgraph P7[Phase 7: Pull Request]
        CPR[Create PR<br/>github-manager]
        CPR --> Done7
    end

    subgraph P8[Phase 8: Completion]
        CS[Clean State File]
        FS[Final Summary]
        CS --> FS
    end

    P0 --> P1
    P1 --> P2
    P2 --> P3
    P3 --> P4
    P4 --> P5
    P5 -->|Stop Hook blocks if incomplete| P5
    LT5 --> P6
    P6 --> P7
    Done7([PR Created]) --> P8
```

**Review Loop Detail** (Ralph-Wiggum Enhanced):

```mermaid
flowchart LR
    subgraph ReviewLoop[Phase 5: Review Loop]
        SC[Self-Check] --> PC[Peer-Check<br/>External Model]
        PC --> FT[Full Test<br/>Regression]
        FT --> CR[Code-Reviewer<br/>Score 0-100]
        CR --> RR{Score >= 81<br/>AND<br/>Assessment OK?}
        RR -->|NO| FIX[Fix Issues]
        FIX --> SC
        RR -->|YES| LINT[Lint Check]
    end

    subgraph StopHook[Stop Hook]
        SH[stop-hook.sh]
        SH -->|Block + Reason| FIX
    end

    LINT --> DONE((Continue))
```

**Output**: PR resolving the issue (linked with `Resolves #N`)

---

### Stage 5: `/close-pr`

Merge PR with validation and update all related issues.

```mermaid
flowchart TB
    Start(["close-pr"]) --> P0

    subgraph P0[Phase 0: Validation]
        CA[Check Arguments]
        VP[Verify PR Exists]
        CA --> VP
    end

    subgraph P1[Phase 1: PR Status Check]
        FD[Fetch PR Details]
        VS[Validate State]
        VS --> VC{Checks Pass?}
        FD --> VS
    end

    subgraph P2[Phase 2: Execute Merge]
        MS[Read Merge Strategy<br/>from gaac.md]
        EM[Execute Merge<br/>github-manager]
        DB[Delete Branch]
        MS --> EM --> DB
    end

    subgraph P3[Phase 3: Update Issues]
        UI[update-related-issues<br/>github-manager]
        RI[Close Resolved Issues]
        NI[Notify Related Issues]
        ND[Notify Dependents]
        UI --> RI --> NI --> ND
    end

    subgraph P4[Phase 4: Summary]
        RS[Results Summary]
        NS4[Next Steps]
        RS --> NS4
    end

    P0 --> P1
    VC -->|NO: Draft/Conflict/CI Fail| Stop5((Stop))
    VC -->|YES| P2
    P2 --> P3
    P3 --> P4
```

**Output**: PR merged, issues closed/notified, branch deleted

---

## Complete Workflow Integration

```mermaid
flowchart TB
    subgraph Idea[Idea]
        I[Text or Markdown]
    end

    subgraph S1[Stage 1: Research]
        R1["research-idea-to-spec"]
        R1 --> D1[draft-*.md]
        R1 --> I1[GitHub Issue]
    end

    subgraph S2[Stage 2: Architecture]
        R2["refine-spec-to-arch"]
        R2 --> A2[arch-*.md PR]
        R2 --> IP2[impl-*.md]
    end

    subgraph S3[Stage 3: Planning]
        R3["plan-arch-to-issues"]
        R3 --> IS3[Issue #1]
        R3 --> IS4[Issue #2]
        R3 --> IS5[Issue #N]
    end

    subgraph S4[Stage 4: Implementation]
        R4["work-on-issue"]
        R4 --> PR4[PR #M]
    end

    subgraph S5[Stage 5: Close]
        R5["close-pr"]
        R5 --> M5[Merged]
    end

    Idea --> S1
    D1 --> R2
    I1 -.->|tracks| S2
    IP2 --> R3
    A2 -.->|anchor| S3
    IS3 --> R4
    IS4 --> R4
    IS5 --> R4
    PR4 --> R5
    M5 -->|Next Issue| R4
```

| Stage | Command | Input | Output |
|-------|---------|-------|--------|
| 1 | `/research-idea-to-spec` | Idea text/file | `draft-*.md` + Issue |
| 2 | `/refine-spec-to-arch` | `draft-*.md` | `arch-*.md` (PR) + `impl-*.md` |
| 3 | `/plan-arch-to-issues` | `impl-*.md` | Multiple Issues |
| 4 | `/work-on-issue` | Issue # | PR (linked to issue) |
| 5 | `/close-pr` | PR # | Merged + Issues closed |

## Commands

| Command | Purpose |
|---------|---------|
| `/research-idea-to-spec <idea>` | Transform idea into draft specification |
| `/refine-spec-to-arch <draft.md>` | Create architecture and implementation plans |
| `/plan-arch-to-issues <impl-*.md>` | Generate test-driven GitHub issues |
| `/work-on-issue <number>` | Implement issue with review loops |
| `/git-commit [message]` | Create commit with GAAC format |
| `/resolve-pr-comment [pr]` | Resolve PR review feedback |
| `/update-related-issues <number>` | Update related issues after PR merge |

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

### Configuration

- `MAX_RALPH_WIGGUM_ITER` environment variable (default: 50)
- Session isolation via `CLAUDE_SESSION_ID`

### Structured Markers

The Stop hook uses explicit markers for reliable detection:

| Marker | Format | Purpose |
|--------|--------|---------|
| Completion | `<gaac-complete>KEYWORD</gaac-complete>` | Signal task complete |
| Review Score | `<!-- GAAC_REVIEW_SCORE: NN -->` | Report self-review score |
| PR Created | `<!-- GAAC_PR_CREATED: N -->` | Report PR number |
| Issue | `<!-- GAAC_ISSUE: description -->` | Report specific issue |

Example completion: `<gaac-complete>WORK_ON_ISSUE_42_DONE</gaac-complete>`

## Project Board Integration

### Project Field Auto-Fill

When issues are added to the project board, GAAC can automatically set field values:

```
gaac.project_fields: Status=Todo, Priority=Medium, Effort=S
```

Supported field types:
- **Single Select**: Value must match an existing option name
- **Text**: Any string value
- **Number**: Numeric value (e.g., `StoryPoints=3`)
- **Date**: YYYY-MM-DD format

### Comment Attribution

GAAC can add an attribution prefix to all AI-generated issue and PR comments:

```
gaac.comment_attribution_prefix: *[Comment by Claude Code AI Agent]*
```

Use `--no-attribution` in scripts to skip the prefix when needed.

## Document Management

The `docs-refactor` skill provides document management capabilities:

| Feature | Script | Description |
|---------|--------|-------------|
| Size check | `check-doc-sizes.sh` | Report document sizes |
| Split | `split-document.sh` | Split large documents |
| Validate | `validate-links.sh` | Check all internal links |
| Move/Rename | `move-doc.sh` | Move document with link updates |

### Document Move/Rename

Move or rename a markdown document while automatically updating all links:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/docs-refactor/scripts/move-doc.sh" \
    --from ./docs/old.md --to ./docs/new.md

# Preview with dry-run
bash "${CLAUDE_PLUGIN_ROOT}/skills/docs-refactor/scripts/move-doc.sh" \
    --from ./docs/old.md --to ./docs/new.md --dry-run
```

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

## What GAAC Does NOT Replace

The GAAC plugin provides methodology and commands, but does NOT replace your project's:

- **`.claude/rules/`**: Your project-specific rules and context (including gaac.md)
- **`CLAUDE.md`**: Project-level instructions and memories
- **`settings.json`**: Local IDE/Claude settings
- **Project hooks/**: Any project-specific hooks (GAAC hooks are additive)

GAAC is a methodology layer on top of your existing Claude Code setup. The `gaac.md` configuration file must live in your project's `.claude/rules/` directory.

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
