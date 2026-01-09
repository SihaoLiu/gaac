---
description: "Cancel active loop-with-codex-review"
allowed-tools: ["Bash(ls .gaac-loop.local/*/state.md:*)", "Bash(rm .gaac-loop.local/*/state.md)", "Bash(cat .gaac-loop.local/*/state.md)", "Read"]
hide-from-slash-command-tool: "true"
---

# Cancel Loop with Codex Review

To cancel the active loop:

1. Check if any loop is active by looking for state files:

```bash
ls .gaac-loop.local/*/state.md 2>/dev/null || echo "NO_LOOP"
```

2. **If NO_LOOP**: Say "No active loop-with-codex-review found."

3. **If state file(s) found**:
   - Read the state file to get the current round number
   - Remove the state file(s) using: `rm .gaac-loop.local/*/state.md`
   - Report: "Cancelled loop-with-codex-review (was at round N of M)"

The loop directory with summaries and review results will be preserved for reference.
