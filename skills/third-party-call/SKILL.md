---
name: third-party-call
description: Unified interface for calling external AI tools (Claude CLI, Codex, Gemini) in non-interactive mode. Use for independent code review, idea proposal, design analysis, and other tasks requiring fresh context. Centralizes all third-party tool configuration and permissions.
allowed-tools: Bash, Read, Write
---

# Third-Party Call Skill

This skill provides a unified interface for invoking external AI tools in GAAC workflows. It manages:

1. **Tool Detection**: Check which tools are available
2. **Invocation Wrapper**: Consistent interface for all tools
3. **Security Controls**: Read-only access, sandboxing
4. **Output Capture**: Structured output handling

## Purpose

External tools provide:
- **Fresh Context**: No conversation history bias
- **Independent Perspective**: Different model, different thinking
- **Specialized Capabilities**: Web search (Gemini), deep reasoning (Codex)

## Supported Tools

| Tool | Primary Use | Detection |
|------|-------------|-----------|
| `codex` | Code review, analysis | `which codex` |
| `claude` | Fallback for codex | `which claude` |
| `gemini` | Web research, proposals | `which gemini` |

## Scripts

### Check Available Tools

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/third-party-call/scripts/check-tools.sh"
```

### Run Analysis (Codex/Claude)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/third-party-call/scripts/run-analysis.sh" \
    --prompt-file ./prompt.md \
    --output-file ./output.md \
    --tool codex \
    --context-files "src/**/*.ts"
```

### Run Web Research (Gemini)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/third-party-call/scripts/run-web-research.sh" \
    --topic "React state management best practices 2024" \
    --output-file ./research.md
```

### Run Peer Check

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/third-party-call/scripts/run-peer-check.sh" \
    --issue-number 42 \
    --output-file ./peer-review.md
```

### Run Code Review (Independent Scoring)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/third-party-call/scripts/run-code-review.sh" \
    --issue-number 42 \
    --output-file ./code-review.md
```

Outputs structured markers: `<!-- GAAC_REVIEW_SCORE: NN -->` and `<!-- GAAC_REVIEW_ASSESSMENT: ... -->`

## Role-Based Model Configuration

Model configuration is read from `gaac.md`. The `--role` parameter determines which model config to use:

| Role | gaac.md Key | Default | Purpose |
|------|-------------|---------|---------|
| `analyzer` | `gaac.models.analyzer` | `codex:gpt-5.2-codex:high` | Synthesis and analysis |
| `analyzer` (fallback) | `gaac.models.analyzer_fallback` | `claude:opus` | Fallback for analyzer |
| `checker` | `gaac.models.checker` | `claude:opus` | Critical checking |
| `proposer` | `gaac.models.proposer` | `claude:sonnet` | Creative proposals |
| `proposer_secondary` | `gaac.models.proposer_secondary` | `gemini:gemini-3-pro-preview` | Secondary proposer (Gemini) |
| `code_reviewer` | `gaac.models.code_reviewer` | `codex:gpt-5.2-codex:high` | Independent code review |
| `code_reviewer` (fallback) | `gaac.models.code_reviewer_fallback` | `claude:opus` | Fallback for code review |

**Usage:**
```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/third-party-call/scripts/run-analysis.sh" \
    --role analyzer \
    --prompt-file ./prompt.md \
    --output-file ./output.md
```

**Model Config Format:** `tool:model:reasoning` (e.g., `codex:gpt-5.2-codex:high`)

## Prompts

| Prompt | Purpose |
|--------|---------|
| `prompts/CODE_REVIEWER_PROMPT.md` | 100-point scoring rubric for code review |
| `prompts/CHECKER_PROMPT.md` | Critical checker for proposer-checker-analyzer debates |

## Tool Configurations

### Codex (Preferred for Analysis)

```bash
codex exec \
    -m gpt-5.2-codex \
    -c model_reasoning_effort=high \
    --enable web_search_request \
    -s read-only \
    -o "$OUTPUT_FILE" \
    -C "$PROJECT_ROOT" \
    < prompt.txt
```

**Features:**
- Deep reasoning (`high` effort)
- Read-only sandbox
- Web search capability
- Output to file

### Claude (Fallback)

```bash
claude -p \
    --model opus \
    --permission-mode bypassPermissions \
    --tools "Read,Grep,Glob,WebSearch,WebFetch" \
    --allowedTools "Read,Grep,Glob,WebSearch,WebFetch" \
    < prompt.txt > output.md
```

**Features:**
- Read-only tools only
- Web search capability
- Output to stdout

### Gemini (Web Research)

```bash
GEMINI_CLI_SYSTEM_SETTINGS_PATH="$TEMP_SETTINGS" \
gemini \
    --output-format json \
    --approval-mode yolo \
    "prompt" > output.json
```

**Settings file:**
```json
{
  "tools": {
    "core": ["list_directory", "read_file", "glob", "search_file_content", "web_fetch", "google_web_search"],
    "exclude": ["write_file", "replace", "run_shell_command"]
  }
}
```

**Features:**
- Google-powered web search
- Read-only codebase access
- No file modifications

## Security Model

All external tools run with:

| Capability | Allowed | Enforced By |
|------------|---------|-------------|
| Read codebase | Yes | Tool config |
| Search codebase | Yes | Tool config |
| Web search | Yes | Tool config |
| Write files | No | Sandbox/tool exclusion |
| Execute commands | No | Sandbox/tool exclusion |

## Use Cases

### 1. Peer Code Review (Phase 6.2)

Uses Codex (or Claude fallback) to review implementation:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/third-party-call/scripts/run-peer-check.sh" --issue-number 42
```

Output: PASS/NEEDS_WORK with detailed findings

### 2. Design Proposal (Research Phase)

Uses Gemini for web-enhanced proposals:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/third-party-call/scripts/run-web-research.sh" \
    --topic "distributed cache invalidation patterns" \
    --output-file ./proposal.md
```

### 3. Independent Analysis (Refinement Phase)

Uses Codex/Claude for synthesizing multiple inputs:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/third-party-call/scripts/run-analysis.sh" \
    --prompt-file ./analysis-prompt.md \
    --context-files "./docs/draft/*.md" \
    --output-file ./synthesis.md
```

## Error Handling

| Exit Code | Meaning | Action |
|-----------|---------|--------|
| 0 | Success | Use output |
| 1 | Tool not available | Try fallback |
| 2 | Tool execution failed | Try fallback |
| 3 | Invalid input | Fix and retry |
| 4 | Timeout | Increase timeout or simplify |

## Timeout Configuration

| Tool | Default | Env Variable |
|------|---------|--------------|
| Codex | 5400s | `CODEX_TIMEOUT` |
| Claude | 300s | `CLAUDE_TIMEOUT` |
| Gemini | 300s | `GEMINI_TIMEOUT` |

## Integration Points

| GAAC Stage | Third-Party Usage |
|------------|-------------------|
| Research | Gemini for web proposals |
| Refinement | Codex/Claude for analysis |
| Planning | Codex for design review |
| Work | Peer-check for code review |

## Files in This Skill

| File | Purpose |
|------|---------|
| `SKILL.md` | This documentation |
| `scripts/check-tools.sh` | Detect available tools |
| `scripts/run-analysis.sh` | General analysis wrapper with role-based config |
| `scripts/run-web-research.sh` | Gemini web research |
| `scripts/run-peer-check.sh` | Quick feedback via external model |
| `scripts/run-code-review.sh` | Independent scoring review (mandatory) |
| `prompts/CODE_REVIEWER_PROMPT.md` | 100-point scoring rubric |
| `prompts/CHECKER_PROMPT.md` | Critical checker for debates |

## Best Practices

1. **Prefer Codex** - Better reasoning for code analysis
2. **Use Gemini for web** - Google search integration
3. **Always capture output** - Don't rely on stdout
4. **Set timeouts** - Prevent hanging
5. **Check exit codes** - Handle failures gracefully
