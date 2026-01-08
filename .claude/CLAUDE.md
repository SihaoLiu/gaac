# GAAC Introduction
This is a Claude Code plugin, that leverage Github-as-a-Context methodology. Also use ralph-loop to iteratively implement and work on issues.

# GAAC Project Rules
- Everything about this project, including but not limited to implementations, comments, tests and documentations should be in English. No Emoji or CJK char is allowed.
- **MANDATORY**: Every commit MUST include a version bump in both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`. This applies to ALL commits without exception - bug fixes, features, documentation changes, etc. Increment the patch version (e.g., 1.0.1 -> 1.0.2) for each commit.
- Version number must be in format of `X.Y.Z` where X/Y/Z is numeric number. Version MUST NOT include anything other than `X.Y.Z`. For example, a good version is `9.732.42`; Bad version examples (MUST NOT USE): `3.22.7-alpha` (extra "-alpha" string), `9.77.2 (2026-01-07)` (useless date/timestamp).
