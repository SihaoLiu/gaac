---
name: docs-refactor
description: Document refactoring skill for splitting large markdown files and validating internal links. Use when documents exceed 1000-1500 lines or when checking documentation integrity. Ensures atomic document structure with proper cross-references.
allowed-tools: Bash, Read, Write
---

# Docs Refactor Skill

This skill handles document management for GAAC workflows:

1. **Document Splitting**: Split large markdown files while maintaining logical coherence
2. **Link Validation**: Verify all internal markdown links are valid
3. **Cross-Reference Management**: Add proper links between split documents

## When to Use

- When a draft/arch/impl document exceeds 1000 lines (recommended) or 1500 lines (maximum)
- Before committing documentation changes
- To validate documentation integrity

## Document Size Guidelines

| Size | Status | Action |
|------|--------|--------|
| < 1000 lines | Good | No action needed |
| 1000-1500 lines | Warning | Consider splitting |
| > 1500 lines | Required | Must split |

## Scripts

### Check Document Sizes

Check sizes of all markdown documents in the docs folder:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/docs-refactor/scripts/check-doc-sizes.sh"
```

### Split Document

Split a large document into multiple smaller documents:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/docs-refactor/scripts/split-document.sh" \
    --input ./docs/draft/impl-large-feature.md \
    --max-lines 1000
```

### Validate Links

Validate all internal links in documentation:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/docs-refactor/scripts/validate-links.sh"
```

## Splitting Strategy

### Principles

1. **Atomic Sections**: Each split document should cover a complete logical unit
2. **No Redundancy**: Don't duplicate content across split documents
3. **Clear Handoffs**: Add "Continued in..." and "Continued from..." links
4. **Preserve Structure**: Maintain heading hierarchy within each split

### Naming Convention

When splitting `impl-feature.md`:
- `impl-feature-overview.md` - Introduction and overview
- `impl-feature-part1.md` - First major section
- `impl-feature-part2.md` - Second major section
- etc.

Or by topic:
- `impl-feature-api.md` - API-related implementation
- `impl-feature-data.md` - Data layer implementation
- `impl-feature-ui.md` - UI implementation

### Cross-Reference Format

At the end of a split document:

```markdown
---

**Next:** [Part 2: Data Layer](./impl-feature-part2.md)

**Related:**
- [Architecture Overview](../architecture/arch-feature.md)
- [API Reference](./impl-feature-api.md)
```

At the start of a continuation:

```markdown
> **Continued from:** [Part 1: Overview](./impl-feature-part1.md)

---
```

## Link Validation

### Supported Link Types

- `[text](./relative/path.md)` - Relative path links
- `[text](./path.md#section-id)` - Links with section anchors
- `[text](#local-section)` - In-document section links

### Validation Checks

1. **File Existence**: Target file exists
2. **Section Existence**: Target section (after #) exists in file
3. **Bidirectional Links**: If A links to B, suggest B links back to A

### Common Issues

| Issue | Resolution |
|-------|------------|
| Broken file link | Update path or create missing file |
| Broken section link | Update anchor or add section heading |
| Orphan document | Add links from related documents |

## Integration with GAAC Workflows

### /refine-spec-to-arch

After generating `arch-*.md` and `impl-*.md`:

1. Check sizes of generated documents
2. Split if needed using `split-document.sh`
3. Validate links with `validate-links.sh`

### /plan-arch-to-issues

Before creating issues:

1. Validate all impl-*.md links work
2. Ensure arch documents are properly referenced

## Files in This Skill

| File | Purpose |
|------|---------|
| `SKILL.md` | This documentation |
| `scripts/check-doc-sizes.sh` | Report document sizes |
| `scripts/split-document.sh` | Split large documents |
| `scripts/validate-links.sh` | Validate markdown links |

## Best Practices

1. **Split early** - Don't wait until documents are 1500+ lines
2. **Use meaningful names** - Split by topic, not arbitrary numbers
3. **Validate regularly** - Run link validation before commits
4. **Maintain index** - Keep a main document that links to all parts
