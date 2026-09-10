# Working on Lutecepowers

This repository is a plugin for coding agents (Claude Code, Codex, Cursor, Grok Build, OpenCode) that helps develop and migrate Lutece 8 plugins. Its content is prose the agents read, so precision matters more than volume.

## Ground truth

- What Lutece 8 really does lives in `~/.lutece-references/` (cloned by `hooks/sync-references`). A statement in a skill, rule or pattern is right when the reference code does it, wrong otherwise. Verify by grep before writing.
- Versions are never hardcoded: the parent POM is the latest released `lutece-global-pom` 8.x read from the release repository (`rules/dependency-convergence.md`).
- Only coding agents verified with a live session are declared as supported (README). No manifest, install command or claim for a tool that was not exercised.

## Single source per topic

- `rules/*.md` are canonical for their path scope (DAO, service, web, templates, SQL, POM, tests). Skills and patterns link to them instead of repeating.
- `skills/using-lutecepowers/SKILL.md` is injected at every session start: shared paragraphs (plugin root, references, team rules) live there once.
- Generated files, never edited by hand: `rules-cursor/*.mdc` (`scripts/build-cursor-rules.sh`) and the skills and rules tables of `README.md` and `skills/using-lutecepowers/SKILL.md` (`scripts/build-tables.sh`).

## Writing rules

- Skills follow the Agent Skills format: frontmatter `name` (= directory), `description` starting with "Use when", optional `license`, `compatibility`, `metadata`. No Claude-only frontmatter or tool names; say "ask the user", "dispatch a subagent".
- English, minimal, present tense. No history prose. Scripts: one doc comment above each function, no comments inside.
- Skills never commit; only the migration Verifier builds; one owner per file in orchestrated skills.

## Before finishing

```bash
bash scripts/build-cursor-rules.sh
bash scripts/build-tables.sh
bash tests/hooks/test-session-start.sh
claude plugin validate .
```

Manifest versions move together: `bash scripts/bump-version.sh <X.Y.Z>` (checked by `--check`).
