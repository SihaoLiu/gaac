---
description: Convert implementation plans into test-driven GitHub issues
argument-hint: <impl-*.md file pattern or path>
allowed-tools: Bash(bash $CLAUDE_PLUGIN_ROOT/scripts/*:*), Bash(bash $CLAUDE_PLUGIN_ROOT/skills/init-validator/scripts/*:*), Bash(bash $CLAUDE_PLUGIN_ROOT/skills/github-manager/scripts/*:*), Bash(bash $CLAUDE_PLUGIN_ROOT/skills/docs-refactor/scripts/*:*), Bash(git branch:*), Bash(gh repo view:*), Bash(gh issue view:*), Bash(gh issue create:*), Bash(gh issue list:*), Bash(gh api:*), Read, Write, Glob, Grep, Task, AskUserQuestion, TodoWrite
---

# /plan-arch-to-issues

Convert implementation plans into well-defined, test-driven GitHub issues following the SWE-bench format. Each issue should be implementable by a developer familiar with the codebase.

## Context

- Repository: !`gh repo view --json nameWithOwner -q '.nameWithOwner'`
- Current branch: !`git branch --show-current`
- Implementation plan pattern: $ARGUMENTS

---

## Phase 0: Validation

Run prerequisite check:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/init-validator/scripts/check-prerequisites.sh"
```

Validate inputs (use $ARGUMENTS to preserve paths with spaces):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/init-validator/scripts/validate-plan.sh" "$ARGUMENTS"
```

**If validation fails**: Display error and stop.

---

## Phase 1: Plan Analysis

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
```

### 1.1 Locate Implementation Plan(s)

Find implementation plan files. If user provided a path/pattern, use it; otherwise scan DRAFT_DIR:

```bash
# User can provide specific path(s) or pattern(s)
if [ -n "$ARGUMENTS" ]; then
    # Check if it's a file path
    if [ -f "$ARGUMENTS" ]; then
        IMPL_FILES="$ARGUMENTS"
    # Check if it's a directory
    elif [ -d "$ARGUMENTS" ]; then
        IMPL_FILES=$(find "$ARGUMENTS" -name "impl-*.md" -type f 2>/dev/null)
    # Try as a glob pattern
    else
        IMPL_FILES=$(find . -path "$ARGUMENTS" -name "impl-*.md" 2>/dev/null || ls $ARGUMENTS 2>/dev/null || echo "")
    fi
else
    # Default: scan DRAFT_DIR
    IMPL_FILES=$(find "${DRAFT_DIR}" -name "impl-*.md" -type f 2>/dev/null)
fi

if [ -z "$IMPL_FILES" ]; then
    echo "No implementation plan files found"
    exit 1
fi

echo "Found implementation plans:"
echo "$IMPL_FILES"
```

Read each file completely. These may have been split, so read all parts.

### 1.2 Read Architecture Anchor

Find and read corresponding arch-*.md files:

```bash
find "${ARCH_DIR}" -name "arch-*.md" -type f
```

Architecture documents provide the design context for implementation.

### 1.3 Map Plan to Tasks

For each implementation plan:
1. Identify distinct phases/sections
2. Estimate scope of each section (lines of code)
3. Identify dependencies between sections
4. Note test requirements

---

## Phase 2: Interactive Refinement

### 2.1 Present Task Breakdown

For each identified task, present to user:
- Task description
- Estimated scope
- Dependencies
- Associated tests

### 2.2 Refine Details

Use AskUserQuestion to clarify:
- "Is this task scope appropriate?" (Target: ~300 lines, max 600)
- "Should this be split further?"
- "Are dependencies correctly identified?"
- "Any additional acceptance criteria?"

### 2.3 Finalize Task List

Create final list of tasks with:
- Clear boundaries
- Correct ordering
- Complete acceptance criteria

---

## Phase 3: Issue Generation

### 3.1 Issue Template (SWE-Bench Format)

For each task, generate an issue following this format:

```markdown
## Problem Statement

[Clear description of what needs to be implemented]

**Context**: This issue is part of [Feature Name] implementation.
**Architecture Reference**: [Link to arch-*.md]
**Implementation Plan Reference**: [Link to impl-*.md section]

## Expected Behavior

When this issue is complete:
- [Specific behavior 1]
- [Specific behavior 2]

## Acceptance Criteria

- [ ] [Criterion 1]
- [ ] [Criterion 2]
- [ ] All tests pass
- [ ] No new warnings
- [ ] Code reviewed

## Test Plan (Test-Driven Development)

### Tests to Write FIRST

Before implementing, create these test files/cases:

```[language]
// File: tests/[path]
describe('[component]', () => {
  it('[behavior]', () => {
    // Test case outline
  });
});
```

### Expected Test Output

```
[Expected test results when implementation is complete]
```

## Implementation Hints

### Files to Create/Modify
- `path/to/new/file.ts` - [purpose]
- `path/to/existing/file.ts` - [changes needed]

### Approach
1. [Step 1]
2. [Step 2]
3. [Step 3]

### Patterns to Follow
- See `existing/similar/code.ts` for reference
- Use existing [utility/pattern]

## Dependencies

- **Depends on**: #[N] - [brief description]
- **Blocks**: #[M] - [brief description]

## Scope

**Target size**: ~[X] lines changed
**Estimated complexity**: [Low/Medium/High]

---

**Labels**: `L1:[Component]`, `L2:[SubArea]`, `implementation`
```

### 3.2 Size Guidelines

| Target | Lines Changed | Action |
|--------|--------------|--------|
| Ideal | < 300 | Create single issue |
| Acceptable | 300-600 | Single issue with warning |
| Too large | > 600 | Split into multiple issues |

If a task is too large, split it into:
- Setup/infrastructure issue
- Core implementation issue(s)
- Integration/cleanup issue

### 3.3 Dependency Mapping

Ensure correct dependency ordering:
1. Foundation issues first (no dependencies)
2. Core issues depend on foundation
3. Integration issues depend on core

Use "Depends on: #N" in issue body for clear linking.

---

## Phase 4: Issue Creation

### 4.1 Create Issues in Order

Create issues starting with those that have no dependencies:

```bash
# L1 required, L2/L3 optional - use when sub-area is clear
# Use labels for workflow stage (implementation)
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-manager/scripts/create-issue.sh" \
    --title "[L1] <Task Title>" \
    --body "<generated body>" \  # or use --body-file if created in temporary file
    --labels "implementation,L1:Component"
```

Examples:
- `[Core] Setup cache infrastructure` (L1 only)
- `[Core][Cache] Implement Redis adapter` (L1 + L2)
- `[Core][Cache][TTL] Add expiration logic` (L1 + L2 + L3, rare)

Capture issue numbers for dependency linking.

### 4.2 Update Dependency References

After all issues are created, update issue bodies with correct issue numbers using post-comment.sh:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-manager/scripts/post-comment.sh" \
    --type issue --number <number> --body "Dependencies: Depends on #<actual-number>"
```

### 4.3 Add to Project Board

For each created issue:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/github-manager/scripts/add-to-project.sh" \
    --item-number <issue-number>
```

---

## Phase 5: Summary

### Created Issues

| # | Title | Depends On | Scope |
|---|-------|------------|-------|
| 1 | [Title] | - | ~X lines |
| 2 | [Title] | #1 | ~Y lines |
| ... | ... | ... | ... |

### Implementation Order

Recommended order for `/work-on-issue`:

1. #[first] - Foundation
2. #[second] - Core (depends on #first)
3. #[third] - Integration (depends on #second)

### Next Steps

Start implementation with:
```
/work-on-issue <first-issue-number>
```

---

## Test-Driven Development Reminder

Each issue includes a "Tests to Write FIRST" section.

**Workflow for each issue:**
1. Write the tests (they should fail)
2. Implement the feature
3. Run tests (they should pass)
4. Refactor if needed
5. Submit PR

This ensures:
- Clear acceptance criteria
- Testable requirements
- Quality implementation

---

## Notes

- Issues are created in dependency order
- Each issue is immediately added to the project board
- Implementation plans can be archived after issues are created
- Use TodoWrite to track issue creation progress
- All issues should be actionable by someone familiar with the codebase
- Target ~300 lines per issue for manageable PRs
