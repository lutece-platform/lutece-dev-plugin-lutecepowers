# Working on Lutecepowers

This repository is a plugin for coding agents (Claude Code, Codex, Cursor, Grok Build, OpenCode) that helps develop and migrate Lutece 8 plugins. Its content is prose the agents read, so precision matters more than volume.

## Ground truth

- What Lutece 8 really does lives in `~/.lutece-references/` (cloned by `hooks/sync-references`). A statement in a skill, rule or pattern is right when the reference code does it, wrong otherwise. Verify by grep before writing.
- Versions are never hardcoded: the parent POM is the latest released `lutece-global-pom` 8.x read from the release repository (`rules/dependency-convergence.md`).
- One supported Lutece 8 level, set once in `tools/v8-floor.conf` and enforced by `check-v8-floor.sh`. Everything written here describes that level; nothing describes, branches on or works around an older v8.
- Only coding agents verified with a live session are declared as supported (README). No manifest, install command or claim for a tool that was not exercised.

## Single source per topic

- `rules/*.md` are canonical for their path scope (DAO, service, web, templates, SQL, POM, tests). Skills and patterns link to them instead of repeating.
- `tools/` holds every script the skills, agents and hooks share; `tools/lutece-check.sh` is the entry point. A check lives in its script, its explanation in `tools/checks.md` (read by `lutece-check.sh --explain`); skills never list what a script reports.
- `skills/using-lutecepowers/SKILL.md` is injected at every session start: shared paragraphs (plugin root, references, team rules) live there once.
- Generated files, never edited by hand: `rules-cursor/*.mdc` (`scripts/build-cursor-rules.sh`), the skills and rules tables of `docs/how-it-works.md` and `skills/using-lutecepowers/SKILL.md`, and the skill list of `README.md`, built from the `metadata.summary` of each skill (`scripts/build-tables.sh`).

## Writing rules

- Skills follow the Agent Skills format: frontmatter `name` (= directory), `description` starting with "Use when", optional `license`, `compatibility`, `metadata`, of which `metadata.summary` is required: one short sentence, the line of the skill in the README. No Claude-only frontmatter or tool names; say "ask the user", "dispatch a subagent".
- English, minimal, present tense. No history prose. Scripts: one doc comment above each function, no comments inside.
- Skills never commit; a project has one writer at a time.

## Before finishing

```bash
bash scripts/build-cursor-rules.sh
bash scripts/build-tables.sh
bash tests/hooks/test-session-start.sh
bash tests/hooks/test-migration-gate.sh
bash tests/hooks/test-verify-edit.sh
bash tests/scripts/test-i18n-unused.sh
bash tests/scripts/test-template-rules.sh
bash tests/scripts/test-checkup.sh
bash tests/scripts/test-bundles.sh
bash tests/scripts/test-fix-i18n-bundles.sh
bash tests/scripts/test-e2e-dep-digest.sh
bash tests/scripts/test-server-log-oracle.sh
bash tests/scripts/test-fakes.sh
bash tests/scripts/test-coverage-keys.sh
bash tests/scripts/test-v8-floor.sh
bash tests/scripts/test-doctor.sh
bash tests/scripts/test-i18n-keys.sh
bash tests/scripts/test-version-tags.sh
bash tests/scripts/test-i18n-languages.sh
bash tests/scripts/test-sql-literal.sh
bash tests/scripts/test-structure-checks.sh
bash tests/scripts/test-grep-checks.sh
bash tests/scripts/test-line-endings.sh
bash tests/scripts/test-custom-checks-a.sh
bash tests/scripts/test-custom-checks-b.sh
bash tests/scripts/test-custom-checks-c.sh
bash tests/scripts/test-custom-checks-d.sh
bash tests/scripts/test-e2e-mvc-inheritance.sh
bash tests/scripts/test-seed-protection.sh
bash tests/scripts/test-v7-portlet-types.sh
bash tests/scripts/test-doc-links.sh
bash tests/scripts/test-server-errors-allow.sh
bash tests/scripts/test-sql-rights-checks.sh
bash tests/scripts/test-java-checks.sh
bash tests/scripts/test-python-resolver.sh
bash tests/scripts/test-portable.sh
bash tests/scripts/test-e2e-lock.sh
bash tests/scripts/test-e2e-selftest.sh
bash tests/scripts/test-e2e-hot-classes.sh
bash tests/scripts/test-e2e-watch.sh
bash tests/scripts/test-v7-witness.sh
bash tests/scripts/test-upgrade-settings.sh
bash tests/scripts/test-inventory-components.sh
bash tests/scripts/test-core-defect.sh
bash tests/scripts/test-source-key.sh
bash tests/scripts/test-site-checks.sh
bash tests/scripts/test-site-v7-leg.sh
bash tests/scripts/test-skill-dir.sh
bash tests/scripts/test-skipped-suites.sh
bash tests/scripts/test-gen-site-fresh.sh
bash tests/scripts/test-latest-lutece.sh
bash tests/scripts/test-upgrade.sh
bash tests/scripts/test-mem-guard.sh
bash tests/scripts/test-site-force.sh
bash tests/scripts/test-e2e-site-cache.sh
bash tests/scripts/test-e2e-src-digest.sh
bash tests/scripts/test-run-all-down.sh
claude plugin validate .
```

Manifest versions move together: `bash scripts/bump-version.sh <X.Y.Z>` (checked by `--check`).
