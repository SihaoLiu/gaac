---
description: Transform ideas into draft specifications with multi-source research
argument-hint: <idea text or markdown file path>
allowed-tools: Bash(bash $CLAUDE_PLUGIN_ROOT/skills/init-validator/scripts/*:*), Bash(bash $CLAUDE_PLUGIN_ROOT/skills/github-manager/scripts/*:*), Bash(bash $CLAUDE_PLUGIN_ROOT/skills/third-party-call/scripts/*:*), Bash(gh repo view:*), Bash(gh issue view:*), Bash(gh issue create:*), Bash(gh api:*), Bash(git branch:*), Bash(mkdir -p:*), Bash(date:*), Read, Write, Edit, Glob, Grep, WebSearch, WebFetch, Task, AskUserQuestion, TodoWrite
---

# /research-idea-to-spec

Transform an idea (text or markdown file) into a draft specification document through multi-source research and three-party discussion.

## Context

- Repository: !`gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || echo "unknown"`
- Current branch: !`git branch --show-current`
- Input: $ARGUMENTS

---

## Phase 0: Validation

Run prerequisite check:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/init-validator/scripts/check-prerequisites.sh"
```

Validate input argument (use $ARGUMENTS to preserve multi-word input):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/init-validator/scripts/validate-research.sh" "$ARGUMENTS"
```

**If validation fails**: Display error and stop.

---

## Phase 1: Idea Capture

### 1.1 Parse Input

If input is a file path (ends with `.md` or starts with `./` or `/`):
- Read the file content using Read tool
- Extract the main idea and any existing structure

If input is text:
- Use the text directly as the idea description

### 1.2 Determine Docs Directory

Get docs paths from gaac.md configuration:

```bash
# Use gaac-config.sh helpers to get correct paths (avoids duplication like docs/draft/draft)
DOCS_ROOT=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/gaac-config.sh" docs-base _)
DOCS_ROOT="${DOCS_ROOT:-docs}"
DRAFT_DIR=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/gaac-config.sh" draft-dir _)
DRAFT_DIR="${DRAFT_DIR:-${DOCS_ROOT}/draft}"
mkdir -p "$(pwd)/${DRAFT_DIR}"
```

All draft files will be created in `${DRAFT_DIR}/`.

### 1.3 Generate Topic Slug

Create a short, descriptive slug from the idea (e.g., "memory-addressing", "auth-flow").

---

## Phase 2: Multi-Source Research

Research the idea from multiple sources to gather comprehensive context.

### 2.1 Web Research (Optional)

If `gemini` is available, run web research for prior art and best practices:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/third-party-call/scripts/run-web-research.sh" \
    --topic "<idea summary for web search>" \
    --output-file "./${DRAFT_DIR}/research_web_<topic>.md"
```

If gemini is not available, use WebSearch and WebFetch tools directly.

### 2.2 GitHub Research

Search existing issues and PRs for related work:

```bash
gh issue list --search "<keywords from idea>" --json number,title,state --limit 10
gh pr list --search "<keywords from idea>" --json number,title,state --limit 10
```

Check GitHub project for related items if configured in gaac.md.

### 2.3 Documentation Research

Search local documentation for related topics:
- Use Grep to search docs folders for relevant keywords
- Read related architecture documents
- Note any existing patterns or conventions

### 2.4 Codebase Exploration

Use Task tool with `subagent_type=Explore` to understand:
- Existing implementations of similar features
- Code patterns and conventions
- Potential integration points

---

## Phase 3: Three-Party Discussion (Proposer-Checker-Analyzer)

Implement multi-perspective analysis using a formal proposer-checker-analyzer debate pattern.

**Model Configuration** (from gaac.md):
- `gaac.models.proposer`: claude:sonnet (primary)
- `gaac.models.proposer_secondary`: gemini:gemini-3-pro-preview (optional)
- `gaac.models.checker`: claude:opus (single checker)
- `gaac.models.analyzer`: codex:gpt-5.2-codex:xhigh → claude:opus (fallback)

### 3.1 Proposer Stage (Parallel)

**Claude Proposer** (Sonnet - main context):
Generate creative proposals based on all gathered research. Output to `./${DRAFT_DIR}/proposer_claude_<topic>.md`:
- Multiple implementation approaches
- Trade-offs and alternatives
- Integration with existing architecture
- Potential risks and mitigations

**Gemini Proposer** (optional, if available):
```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/third-party-call/scripts/run-analysis.sh" \
    --role proposer_secondary \
    --prompt "Design approaches for: <idea summary>" \
    --context-files "./${DRAFT_DIR}/research_*.md" \
    --output-file "./${DRAFT_DIR}/proposer_gemini_<topic>.md"
```

Note: Uses `gaac.models.proposer_secondary` (default: gemini:gemini-3-pro-preview). If Gemini is not available, skip this step. The Claude proposer is sufficient.

### 3.2 Checker Stage (Critical Review)

Run the critical checker (Claude Opus) to evaluate combined proposer outputs:

```bash
# Combine proposer outputs
cat ./${DRAFT_DIR}/proposer_*_<topic>.md > ./${DRAFT_DIR}/combined_proposals_<topic>.md

# Run critical checker with CHECKER_PROMPT
bash "${CLAUDE_PLUGIN_ROOT}/skills/third-party-call/scripts/run-analysis.sh" \
    --role checker \
    --prompt-file "${CLAUDE_PLUGIN_ROOT}/skills/third-party-call/prompts/CHECKER_PROMPT.md" \
    --context-files "./${DRAFT_DIR}/combined_proposals_<topic>.md" \
    --output-file "./${DRAFT_DIR}/checker_<topic>.md"
```

The checker will:
- Verify claims against evidence
- Find logical flaws in proposals
- Challenge unstated assumptions
- Classify issues as: CRITICAL FLAWS, SIGNIFICANT CONCERNS, MINOR OBSERVATIONS, UNVERIFIED CLAIMS

**If checker finds CRITICAL FLAWS**: Address them before proceeding.

### 3.3 Analyzer Stage (Independent Synthesis)

Run independent analyzer (Codex xhigh preferred, Claude Opus fallback) to synthesize all inputs:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/third-party-call/scripts/run-analysis.sh" \
    --role analyzer \
    --prompt "Synthesize the proposals and checker critique into a coherent recommendation.
              Resolve conflicts, incorporate valid criticisms, and provide a clear direction.
              Output a structured recommendation with rationale." \
    --context-files "./${DRAFT_DIR}/combined_proposals_<topic>.md,./${DRAFT_DIR}/checker_<topic>.md" \
    --output-file "./${DRAFT_DIR}/analysis_<topic>.md"
```

If external tools fail, perform synthesis internally using the current context.

### 3.4 User Review Gate

Present synthesized analysis to user using AskUserQuestion:

**Summary to present**:
- Key recommendation from analyzer
- Critical issues identified by checker (if any)
- Unresolved concerns

**Question**: "Based on the three-party analysis, here is the proposed direction. Do you want to proceed?"

**Options**:
1. **Proceed** - Continue to draft specification
2. **Revise** - Provide feedback for another round
3. **Abandon** - Stop the workflow

If **Revise**: Incorporate feedback and repeat from Phase 3.1.
If **Abandon**: Clean up and exit.

---

## Phase 4: Draft Generation

### 4.1 Create Draft Document

Generate `draft-<topic>.md` in `${DRAFT_DIR}/` (determined from gaac.md configuration in Phase 1.2).

Draft structure:
```markdown
# <Idea Title>

## Overview
[High-level description of the idea]

## Motivation
[Why this is needed, what problem it solves]

## Background
[Context from research - web, GitHub, docs, codebase]

## Proposed Approach
[Recommended approach from three-party discussion]

### Key Design Decisions
- [Decision 1]
- [Decision 2]

### Alternatives Considered
- [Alternative 1]: [why not chosen]
- [Alternative 2]: [why not chosen]

## Scope
### In Scope
- [Item 1]
- [Item 2]

### Out of Scope
- [Item 1]
- [Item 2]

## Open Questions
- [Question 1]
- [Question 2]

## References
- [Web source 1]
- [Related issue #N]
- [Architecture doc link]

---
*Generated by GAAC /research-idea-to-spec on <date>*
```

### 4.2 Size Check

Verify draft is within recommended limits (1000-1500 lines max).

If too large, use docs-refactor skill to split.

---

## Phase 5: Issue Creation

### 5.1 Create GitHub Issue

Create a tracking issue for this idea:

```bash
# Infer L1 from the idea topic (e.g., [Core], [API], [Docs], etc.)
# L2 is optional - use only if there's a clear sub-area
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-manager/scripts/create-issue.sh" \
    --title "[L1] <Idea Title>" \
    --body-file "<generated issue body>" \
    --labels "research,draft,L1:Component"
```

Examples:
- `[Core] Add caching layer` (L1 only)
- `[Core][Cache] Add Redis backend` (L1 + L2 when sub-area is clear)

Issue body should include:
- Brief summary of the idea
- Link to draft document (relative path)
- Key points from the analysis
- Next steps (refinement)

### 5.2 Add to Project

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-manager/scripts/add-to-project.sh" \
    --item-number <issue number>
```

---

## Phase 6: Summary

Present summary to user:

### Outputs Created:
1. **Draft document**: `${DRAFT_DIR}/draft-<topic>.md` (unstaged)
2. **GitHub Issue**: #<number> - tracking this research
3. **Research artifacts**: (in `${DRAFT_DIR}/`, can be deleted)

### Next Steps:
- Review the draft document
- Run `/refine-spec-to-arch draft-<topic>.md` to create architecture documents

---

## Notes

- The draft document remains **unstaged** - user decides whether to commit
- Research artifacts (web research, proposals, analysis) can be deleted after review
- The GitHub issue provides persistent tracking regardless of local file state
- Use TodoWrite to track progress through phases
- Size target: draft should be under 1000 lines, max 1500 lines
