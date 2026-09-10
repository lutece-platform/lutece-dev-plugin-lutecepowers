---
name: lutece-v8-review
description: "Use when the user asks to review, audit, check or verify a Lutece plugin, module or library for v8 compliance or conformity, or after a v7 to v8 migration before delivering. Read-only. Dispatches the lutece-v8-reviewer instructions as a subagent, or follows them inline on a harness without dispatch."
license: MIT
compatibility: Any harness. Subagent dispatch optional.
---

# Lutece v8 review

Read-only compliance review of the current Lutece 8 project. The full procedure lives in `${LUTECEPOWERS_ROOT}/agents/lutece-v8-reviewer.md`. This skill only decides how to run it on your harness.

## Steps

1. Resolve the plugin root (`LUTECEPOWERS_ROOT` from the session context, or the fallback in `using-lutecepowers`).
2. Read `${LUTECEPOWERS_ROOT}/agents/lutece-v8-reviewer.md`.
3. Run it:
   - **Harness with a native agent named `lutece-v8-reviewer`** (Claude Code, Cursor, Grok): invoke that agent on the current directory.
   - **Harness with a generic subagent tool** (Codex `spawn_agent`, OpenCode `task`): dispatch one subagent whose prompt starts with `LUTECEPOWERS_ROOT=<literal absolute path>` (the subagent does not see your session context), then the whole file content, then: "Review the project in <absolute path>. Do NOT modify any files. Reference implementations: ~/.lutece-references/."
   - **No dispatch**: follow the file yourself, step by step, without modifying any source file.
4. Return the report in the format defined at the end of that file. Never fix anything unless the user asks after reading the report.
