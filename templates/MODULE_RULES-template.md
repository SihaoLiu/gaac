# Module Rules Template

This template defines acceptance standards for a module. Place a `MODULE_RULES.md` file in any directory to enforce these standards during Codex review.

---

# Core Principles

Define the fundamental principles that this module must uphold. These are non-negotiable and any change violating them requires exceptional justification.

- [Principle 1: e.g., "This module handles X only - no Y logic allowed"]
- [Principle 2: e.g., "All public interfaces must be backward compatible"]
- [Principle 3: e.g., "External dependencies must be abstracted behind interfaces"]

# Acceptance Standards

Define measurable criteria for accepting changes to this module.

- [Standard 1: e.g., "Changes must not break existing functionality"]
- [Standard 2: e.g., "New features require corresponding test coverage"]
- [Standard 3: e.g., "Documentation must be updated for API changes"]

# Complexity Boundaries

Define limits to prevent the module from growing beyond its intended scope.

- [Boundary 1: e.g., "Maximum 500 lines per file"]
- [Boundary 2: e.g., "No more than 3 levels of inheritance"]
- [Boundary 3: e.g., "Dependencies limited to: X, Y, Z"]

# Change Review Checklist

Questions the reviewer should answer for any change to this module:

- [ ] Does this change align with the module's core principles?
- [ ] Does this change increase conceptual complexity? If so, is it justified?
- [ ] Will this change harm long-term maintainability?
- [ ] Are there simpler alternatives that achieve the same goal?
- [ ] Does this change require updates to related modules?

---

## Usage

1. Copy this template to your module directory as `MODULE_RULES.md`
2. Customize the principles, standards, and boundaries for your module
3. Remove this "Usage" section and the template header
4. Rules will be automatically loaded during Codex review

## Hierarchical Application

Rules apply hierarchically from the most specific directory to the project root:

- A file at `src/auth/login.js` will be reviewed against:
  1. `src/auth/MODULE_RULES.md` (if exists)
  2. `src/MODULE_RULES.md` (if exists)
  3. `MODULE_RULES.md` (project root, if exists)

More specific rules take precedence, but all applicable rules are considered.
