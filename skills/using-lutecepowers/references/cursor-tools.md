# Cursor tool mapping

Cursor's agent tool surface is Claude Code compatible for files, shell and search. Specifics:

| Action | Cursor equivalent |
|---|---|
| Invoke a skill | Native skill loading (skills are listed with their description) |
| Path-scoped rules | Native. The plugin ships `rules-cursor/*.mdc` with `globs`, Cursor applies them automatically |
| Dispatch a subagent / teammate | Cursor subagents when available (plugin `agents/*.md`); otherwise run teammates sequentially inline |
| Plugin root | Printed and substituted in the injected context. The hook `env` field only reaches later hooks, not your shell |
