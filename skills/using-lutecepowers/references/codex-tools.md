# Codex tool mapping

Skills name actions. On Codex (CLI and ChatGPT app) they resolve as follows.

| Action | Codex equivalent |
|---|---|
| Invoke a skill | Native skill discovery: mention `$lutece-patterns` (CLI) or `@lutece-patterns` (ChatGPT), or let Codex invoke it implicitly |
| Read, create, edit a file | Your native file tools (`apply_patch` for edits) |
| Run a shell command | Your native shell tool |
| Dispatch a subagent / teammate | `spawn_agent` (multi-agent is enabled by default); wait with `wait_agent`, message with `send_input`; give each child the teammate file path and the spawn template from the skill |
| Track tasks | `plan` tool (update_plan) |
| Ask the user | `request_user_input` |

Notes:

- Codex runs the plugin `hooks/hooks.json`, so the Lutecepowers bootstrap and the reference sync happen at `SessionStart`.
- The plugin root is printed in the injected context. Codex caches plugins under `~/.codex/plugins/cache/<marketplace>/lutecepowers-v8/<version>/`.
- Path-scoped rules are not automatic on Codex. Read `${LUTECEPOWERS_ROOT}/rules/<rule>.md` before editing a matching file.
