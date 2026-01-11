# GAAC Introduction
This is a Claude Code plugin that leverages the Github-as-a-Context methodology. Use `/loop-with-codex-review` for iterative development with Codex review, and `/work-on-issue` for end-to-end issue resolution.

# GAAC Project Rules
- Everything about this project, including but not limited to implementations, comments, tests and documentations should be in English. No Emoji or CJK char is allowed.
- **MANDATORY**: Every commit MUST include a version bump in `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and `README.md` (the "Current Version" line). This applies to ALL commits without exception - bug fixes, features, documentation changes, etc. Increment the patch version (e.g., 1.0.1 -> 1.0.2) for each commit.
- Every `git push` or `git commit` MUST confirm with user first, MUST NOT commit or push to remote without check with user.
- Version number must be in format of `X.Y.Z` where X/Y/Z is numeric number. Version MUST NOT include anything other than `X.Y.Z`. For example, a good version is `9.732.42`; Bad version examples (MUST NOT USE): `3.22.7-alpha` (extra "-alpha" string), `9.77.2 (2026-01-07)` (useless date/timestamp).
