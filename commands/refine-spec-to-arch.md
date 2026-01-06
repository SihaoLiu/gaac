---
description: Refine draft specifications into architecture documents and implementation plans
argument-hint: <draft-*.md file path> [issue-number]
allowed-tools: Bash(bash $CLAUDE_PLUGIN_ROOT/skills/init-validator/scripts/*:*), Bash(bash $CLAUDE_PLUGIN_ROOT/skills/github-manager/scripts/*:*), Bash(bash $CLAUDE_PLUGIN_ROOT/skills/third-party-call/scripts/*:*), Bash(bash $CLAUDE_PLUGIN_ROOT/skills/docs-refactor/scripts/*:*), Bash(gh issue view:*), Bash(gh issue comment:*), Bash(gh pr create:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(git branch:*), Bash(git checkout:*), Bash(mkdir -p:*), Read, Write, Edit, Glob, Grep, Task, AskUserQuestion, TodoWrite, EnterPlanMode
---

# /refine-spec-to-arch

Refine a draft specification into complete architecture documents and implementation plans through interactive discussion and third-party evaluation.

## Context

- Repository: !`gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || echo "unknown"`
- Current branch: !`git branch --show-current`
- Draft file: $1
- Issue number: $2 (or auto-created in Phase 0.5 if not provided)

---

## Phase 0: Validation

Run prerequisite check:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/init-validator/scripts/check-prerequisites.sh"
```

Validate inputs:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/init-validator/scripts/validate-refine.sh" "$1" "$2"
```

**If validation fails**: Display error and stop.

---

## Phase 0.5: Auto-Create Issue (if not provided)

If no issue number was provided, automatically create one from the draft:

### 0.5.1 Extract Issue Details from Draft

Read the draft file and extract:
- **Title**: Use draft filename or first heading
- **Summary**: First paragraph or section

```bash
# Extract topic from filename
DRAFT_BASENAME=$(basename "$1" .md)
TOPIC_NAME=$(echo "$DRAFT_BASENAME" | sed 's/^draft-//' | tr '-' ' ' | sed 's/\b\(.\)/\u\1/g')

# Read first heading as potential title
FIRST_HEADING=$(grep -m1 '^#' "$1" | sed 's/^#* *//')
ISSUE_TITLE="${FIRST_HEADING:-Architecture: $TOPIC_NAME}"
```

### 0.5.2 Create Issue

```bash
ISSUE_URL=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/github-manager/scripts/create-issue.sh" \
    --title "[Docs] $ISSUE_TITLE" \
    --body "## Problem Statement

This issue tracks the architecture refinement for: $TOPIC_NAME

## Source Draft

See: \`$1\`

## Acceptance Criteria

- [ ] Architecture document created and reviewed
- [ ] Implementation plan generated
- [ ] Ready for /plan-arch-to-issues

---
*Created automatically by /refine-spec-to-arch*" \
    --labels "documentation,architecture")

# Extract issue number from URL
ISSUE_NUMBER=$(echo "$ISSUE_URL" | grep -oE '[0-9]+$')
echo "Created issue #$ISSUE_NUMBER: $ISSUE_URL"
```

### 0.5.3 Add to Project Board

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-manager/scripts/add-to-project.sh" \
    --item-number "$ISSUE_NUMBER"
```

**Store the issue number for later phases** (use $ISSUE_NUMBER instead of $2).

---

## Phase 1: Draft Analysis

### 1.0 Determine Docs Directories

Get docs paths from gaac.md configuration:

```bash
# Use gaac-config.sh helpers to get correct paths (avoids duplication like docs/draft/draft)
DOCS_ROOT=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/gaac-config.sh" docs-base _)
DOCS_ROOT="${DOCS_ROOT:-docs}"
DRAFT_DIR=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/gaac-config.sh" draft-dir _)
DRAFT_DIR="${DRAFT_DIR:-${DOCS_ROOT}/draft}"
ARCH_DIR=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/gaac-config.sh" arch-dir _)
ARCH_DIR="${ARCH_DIR:-${DOCS_ROOT}/architecture}"
mkdir -p "$(pwd)/${DRAFT_DIR}" "$(pwd)/${ARCH_DIR}"
```

### 1.1 Read Draft Document

Read the draft document completely using Read tool.

### 1.2 Identify Uncertainties

Extract and list:
- Open questions mentioned in the draft
- Ambiguous design decisions
- Missing details
- Undefined scope boundaries
- Unclear interfaces

### 1.3 Check Related Context

Fetch issue details (using stored $ISSUE_NUMBER from Phase 0.5 or provided $2):
```bash
# Use ISSUE_NUMBER from Phase 0.5 if auto-created, otherwise use $2
ISSUE_NUM="${ISSUE_NUMBER:-$2}"
if [ -n "$ISSUE_NUM" ]; then
    gh issue view "$ISSUE_NUM" --json title,body,comments
fi
```

Search for related documentation and code.

---

## Phase 2: Interactive Refinement

### 2.1 Iterative Clarification

For each uncertainty identified, use AskUserQuestion to clarify:

Present the uncertainty and ask for guidance. Options should include:
1. Specific choice (with description)
2. Alternative choice
3. "Let me think" - provide more context
4. "Not important" - skip this detail

### 2.2 Third-Party Evaluation

After initial clarification, run external evaluation:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/third-party-call/scripts/run-analysis.sh" \
    --prompt-file "<prompt with draft + clarifications>" \
    --context-files "${DOCS_ROOT}/**/*.md" \
    --output-file "./${DRAFT_DIR}/evaluation_<topic>.md"
```

The evaluation should check:
- Consistency with existing architecture
- Technical feasibility
- Potential conflicts
- Missing considerations

### 2.3 Final User Approval

Present evaluation results and ask for final approval:

**Options**:
1. **Approve** - Proceed to document generation
2. **Revise** - Provide additional feedback
3. **Stop** - Pause for more research

---

## Phase 3: Architecture Document Generation

### 3.1 Create Architecture Document

Generate `arch-<topic>.md` with complete architectural specification:

```markdown
# <Feature> Architecture

## Overview
[Complete, unambiguous description]

## Design Goals
1. [Goal 1]
2. [Goal 2]

## Architecture

### Component Diagram
[Description of components and their relationships]

### Data Flow
[How data moves through the system]

### API/Interfaces
[Detailed interface specifications]

## Implementation Constraints
- [Constraint 1]
- [Constraint 2]

## Dependencies
- [Existing component X]
- [Library Y]

## Testing Strategy
- Unit tests: [scope]
- Integration tests: [scope]

## Migration/Rollout
[If applicable]

## References
- [Related architecture docs]
- [Issue #N]

---
*Architecture document for Issue #<N>*
*Generated by GAAC /refine-spec-to-arch on <date>*
```

### 3.2 Size Check

Check document size:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/docs-refactor/scripts/check-doc-sizes.sh"
```

If arch document exceeds 1500 lines, split it:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/docs-refactor/scripts/split-document.sh" \
    --input "./${ARCH_DIR}/arch-<topic>.md" \
    --max-lines 1000
```

---

## Phase 4: Implementation Plan Generation

### 4.1 Create Implementation Plan

Generate `impl-<topic>.md` with detailed implementation steps:

```markdown
# <Feature> Implementation Plan

## Overview
[Brief summary linking to architecture]

## Prerequisites
- [ ] Architecture document reviewed: [link]
- [ ] Dependencies available

## Implementation Phases

### Phase 1: Foundation
**Estimated scope**: ~X lines

#### Tasks
1. [Task 1]
   - Files: `path/to/file.ts`
   - Changes: [description]
2. [Task 2]

#### Tests
- [ ] [Test case 1]
- [ ] [Test case 2]

#### Acceptance Criteria
- [ ] [Criterion 1]
- [ ] [Criterion 2]

### Phase 2: Core Implementation
[Similar structure]

### Phase 3: Integration
[Similar structure]

## Test-Driven Approach

For each phase:
1. Write failing tests first
2. Implement to pass tests
3. Refactor if needed

### Test Outline

```
tests/
├── unit/
│   └── <feature>/
│       ├── test_component1.ts
│       └── test_component2.ts
└── integration/
    └── test_<feature>_integration.ts
```

## Rollback Plan
[If implementation fails]

## References
- Architecture: [link to arch doc]
- Issue: #N

---
*Implementation plan for Issue #<N>*
*Generated by GAAC /refine-spec-to-arch on <date>*
```

### 4.2 Size Check and Split

If impl document exceeds limits, split by phase or topic.

---

## Phase 5: Version Control Integration

### 5.1 Create Feature Branch (if not exists)

```bash
git checkout -b docs/arch-<topic>-<issue>
```

### 5.2 Commit Architecture Documents

Only commit arch-*.md files (impl-*.md stays unstaged):

```bash
git add "${ARCH_DIR}/arch-"*.md
```

Create commit using github-manager:

```bash
# Use ISSUE_NUM from Phase 1.3
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-manager/scripts/create-commit.sh" \
    --issue "$ISSUE_NUM" \
    --message "Add architecture document for <feature>"
```

### 5.3 Push and Create PR

```bash
git push -u origin $(git branch --show-current)
```

Create PR for architecture review:

```bash
# Use L1/L2 from gaac.md; [Issue #N] required for PR titles
# Use ISSUE_NUM from Phase 1.3
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-manager/scripts/create-pr.sh" \
    --title "[Docs][Issue #$ISSUE_NUM] <Feature> architecture" \
    --body-file "<pr body with summary>" \
    --resolves "$ISSUE_NUM"
```

---

## Phase 6: Summary

### Outputs Created:

1. **Architecture documents**: `${ARCH_DIR}/arch-<topic>*.md`
   - Committed and pushed
   - PR created: #<pr-number>

2. **Implementation plans**: `${DRAFT_DIR}/impl-<topic>*.md`
   - Remain **unstaged** locally
   - Ready for `/plan-arch-to-issues`

3. **Draft document**: `${DRAFT_DIR}/draft-<topic>.md`
   - Can be archived or deleted

### Next Steps:

1. Wait for architecture PR review and merge
2. Run `/plan-arch-to-issues ./${DRAFT_DIR}/impl-*.md` to create implementation issues

---

## Notes

- Architecture documents are committed because they become project documentation
- Implementation plans remain local until converted to issues
- The three-party evaluation ensures design quality
- All design decisions should be explicitly documented
- Use EnterPlanMode for complex architectural decisions
- Maintain links between arch and impl documents
