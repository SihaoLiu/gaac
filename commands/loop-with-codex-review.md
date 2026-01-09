---
description: "Start iterative loop with Codex review"
argument-hint: "<path/to/plan.md> [--max N] [--codex-model MODEL:EFFORT] [--codex-timeout SECONDS]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop-with-codex.sh:*)"]
hide-from-slash-command-tool: "true"
---

# Ralph Loop with Codex Review

Execute the setup script to initialize the loop:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop-with-codex.sh" $ARGUMENTS
```

This command starts an iterative development loop where:

1. You work on the implementation plan provided
2. Write a summary of your work to the specified summary file
3. When you try to exit, Codex reviews your summary
4. If Codex finds issues, you receive feedback and continue
5. If Codex outputs "COMPLETE", the loop ends

## Important Rules

1. **Write summaries**: Always write your work summary to the specified file before exiting
2. **Be thorough**: Include details about what was implemented, files changed, and tests added
3. **No cheating**: Do not try to exit the loop by editing state files or running cancel commands
4. **Trust the process**: Codex's feedback helps improve the implementation

## Stopping the Loop

- Reach the maximum iteration count
- Codex confirms completion with "COMPLETE"
- User runs `/gaac:cancel-loop-with-codex`
