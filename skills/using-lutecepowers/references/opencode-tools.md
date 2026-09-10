# OpenCode tool mapping

| Action | OpenCode equivalent |
|---|---|
| Read a file | `read` |
| Create / edit a file | `write`, `edit`, `apply_patch` |
| Run a shell command | `bash` |
| Search | `grep`, `glob` |
| Fetch a URL / search the web | `webfetch`, `websearch` |
| Invoke a skill | native `skill` tool |
| Dispatch a subagent / teammate | `task` with a subagent type; otherwise run teammates sequentially inline |
| Track tasks | `todowrite` |
| Ask the user | `question` |

Notes:

- OpenCode does not load Claude Code plugins. Lutecepowers is loaded by the in-process plugin `.opencode/plugins/lutecepowers.js`, which registers `skills/` and injects this bootstrap.
- The plugin root is printed in the injected context.
- Path-scoped rules are not automatic. Read `${LUTECEPOWERS_ROOT}/rules/<rule>.md` before editing a matching file.
