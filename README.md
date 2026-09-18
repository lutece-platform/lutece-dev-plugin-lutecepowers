# Lutecepowers

**Lutece 8** development toolkit for coding agents: skills, path-scoped rules, reference sources, and orchestrated workflows for migration to v8 and scalability proofs.

One content tree, several coding agents. Skills follow the open [Agent Skills](https://agentskills.io) format. Supported coding agents are the ones verified with a live session: Claude Code, Codex, Cursor, Grok Build and OpenCode.

## Installation

Install once per coding agent you use.

### Claude Code

```
/plugin marketplace add lutece-platform/lutece-dev-plugin-lutecepowers
/plugin install lutecepowers-v8@lutece-plugins
```

Local development: `claude --plugin-dir /path/to/lutecepowers`.

### Codex (CLI and app)

```bash
codex plugin marketplace add https://github.com/lutece-platform/lutece-dev-plugin-lutecepowers
codex plugin add lutecepowers-v8@lutece-plugins
```

Then start a new thread. `/plugins` lists installed plugins.

### Cursor

```bash
git clone https://github.com/lutece-platform/lutece-dev-plugin-lutecepowers
cursor-agent --plugin-dir /path/to/lutecepowers
```

Verified with Cursor CLI. Marketplace publication (`/add-plugin`) is not done yet.

### Grok Build

```bash
grok plugin install https://github.com/lutece-platform/lutece-dev-plugin-lutecepowers --trust
```

### OpenCode

```bash
git clone https://github.com/lutece-platform/lutece-dev-plugin-lutecepowers ~/.config/opencode/lutece-dev-plugin-lutecepowers
mkdir -p ~/.config/opencode/plugins
ln -s ~/.config/opencode/lutece-dev-plugin-lutecepowers/.opencode/plugins/lutecepowers.js ~/.config/opencode/plugins/lutecepowers.js
```

OpenCode loads every plugin file found in `~/.config/opencode/plugins/`. Requires `bash` on the PATH.

## What happens at session start

A single hook script, `hooks/session-start`, runs on every coding agent that supports session hooks. It:

1. Injects the `using-lutecepowers` skill as context, with the absolute plugin root substituted for `LUTECEPOWERS_ROOT`. Fires on startup, clear and compact, not on resume, so a resumed session is not charged twice.
2. Clones or updates the Lutece v8 reference repositories listed in `hooks/sync-references` into `~/.lutece-references/` in the background (branch `develop`, plus the v7 branches of each repository).
3. On Claude Code, when the current directory is a Lutece Maven project, copies the rules into `.claude/rules/` so they load automatically by path. It also exports `LUTECEPOWERS_ROOT` to the shell.

The reference sync runs at most once per hour, six repositories at a time.

The script takes the coding agent name as an optional argument (Cursor and OpenCode pass it), otherwise detects it from its environment, and emits the output shape that agent expects (`hookSpecificOutput.additionalContext` for Claude Code and Codex; `additional_context` for Cursor).

Coding agents without a usable session hook load the bootstrap another way: OpenCode through an in-process plugin that runs the same hook script and injects its output into the first user message, Grok through the skill description alone.

## Skills

<!-- skills:start -->
| Skill | Use when |
|---|---|
| `lutece-brainstorming` | Use before any creative Lutece work: a new plugin, a new feature, a new screen, or a behaviour change. Explores intent, requirements and design with the user before any implementation. Triggers on 'I want to build', 'add a feature', 'new plugin', 'how should we design'. |
| `lutece-cache` | Use when adding, fixing or reviewing a cache in a Lutece 8 plugin: AbstractCacheableService, CDI initialization, cache keys, invalidation through CDI events. Triggers on 'cache', 'cacheable', 'invalidate', 'CacheService'. |
| `lutece-dao` | Use when creating, modifying or reviewing a Lutece 8 DAO, Home or business class: DAOUtil lifecycle, SQL constants, Home static facade, CDI lookup, collection types, interface conventions. Must be consulted before touching anything under a business package. |
| `lutece-e2e` | Use to give any Lutece 8 core, plugin, module or site an e2e/ bench that runs with one command: isolated Docker stack (Open Liberty HotSpot, MariaDB instrumented), synthetic volume, static + dynamic inventory of every back-office screen and action, Playwright suites (screens, YAML scenarios, forms) with a clean-console rule, server timings, SQL digests, JFR, k6, and a compact report. Also proves a migration's upgrade path: `run.sh compare` builds the artefact before its migration on a v7 site, then the v8 one on that same database, so a missing update_db script is caught instead of hidden by a fresh install. Triggers on 'e2e', 'tests de bout en bout', 'Playwright', 'tester tous les écrans', 'banc de test', 'non-régression BO', 'prouver la migration', 'chemin de mise à jour'. |
| `lutece-elasticdata` | Use when creating or modifying an Elasticsearch DataSource module for Lutece 8: DataSource and DataObject interfaces, CDI auto-discovery, @ConfigProperty injection, batch processing, two-daemon indexing, incremental updates through CDI events. Triggers on 'elasticdata', 'Elasticsearch', 'DataSource module'. |
| `lutece-lucene-indexer` | Use when adding plugin-internal Lucene search to a Lutece 8 plugin: custom index, indexing daemon, CDI events, batch processing. Triggers on 'Lucene', 'full-text search inside the plugin', 'indexer'. |
| `lutece-migration-v8-agent-teams` | Use when migrating a Lutece plugin, module or library of any version before 8 to v8: Spring to CDI, javax to jakarta, XML context to JSON, templates, tests. Script-heavy, JSON-driven task decomposition run by teammates or subagents, with a sequential fallback. Triggers on 'migrate to v8', 'migration v7 v8', 'CDI migration'. |
| `lutece-patterns` | Use before writing or reviewing any Lutece 8 code (CRUD, JspBean, XPage, service, DAO, daemon, template) and when answering questions about Lutece 8 architecture, layered design or coding conventions. Canonical patterns extracted from lutece-core. |
| `lutece-rbac` | Use when adding or reviewing permissions in a Lutece 8 plugin: RBAC entity permissions, ResourceIdService, plugin.xml declaration, JspBean authorization checks. Triggers on 'RBAC', 'permission', 'right', 'authorization', 'ResourceIdService'. |
| `lutece-scalability-v8` | Use after a migration to v8 to make a Lutece plugin horizontally scalable and prove it: scans scalability anti-patterns, fixes them, deploys a real 3-instance cluster (Liberty, MariaDB, nginx, Hazelcast) and verifies through UI end-to-end tests. Triggers on 'scalability', 'cluster', 'multi-instance', 'horizontal scaling'. |
| `lutece-solr-indexer` | Use when creating or modifying a Solr search module for Lutece 8: SolrIndexer interface, CDI auto-discovery, SolrItem dynamic fields, batch indexing, incremental updates through CDI events. Triggers on 'Solr', 'search module', 'SolrIndexer'. |
| `lutece-update-template-bo` | Converts a Lutece Back Office (admin) template to the BO FreeMarker macros of lutece-core (Tabler theme). Discovers the macros from the core sources rather than from a fixed list, so it never goes stale, and applies the house rules that are not readable from the macro files: manageFeature versus table, the mandatory empty state, the page hierarchy, the offcanvas navigation rule, and the e-mail templates that must never be converted. Takes the template path as argument. Triggers on 'migrer un template BO', 'convertir un template admin', 'macros BO', 'thème tabler', 'update back office template'. |
| `lutece-update-template-fo` | Converts a Lutece Front Office (skin) template to the FO FreeMarker macros of lutece-core. Discovers the macros from the core sources rather than from a fixed list, so it never goes stale, and applies the rules that are not readable from the macro files: the FO macros are never the Back Office ones, the FreeMarker syntax to use, Bootstrap 5 classes, and the jQuery that must become vanilla JS. Takes the template path as argument. Triggers on 'migrer un template FO', 'convertir un template skin', 'macros FO', 'front office template', 'update skin template'. |
| `lutece-v8-review` | Use when the user asks to review, audit, check or verify a Lutece plugin, module or library for v8 compliance or conformity, or after a migration to v8 before delivering. Read-only. Dispatches the lutece-v8-reviewer instructions as a subagent, or follows them inline on a harness without dispatch. |
| `lutece-workflow` | Use when creating or modifying a Lutece 8 workflow module: tasks, CDI producers, task components, templates, configuration DAOs. Triggers on 'workflow', 'task', 'workflow module', 'TaskComponent'. |
<!-- skills:end -->

## Agent

| Agent | Description |
|-------|-------------|
| `lutece-v8-reviewer` | Read-only compliance reviewer. Runs `scan-project.sh` and `verify-migration.sh`, then semantic analysis (CDI scopes, singletons, producers, cache guards), then a full build with tests read from the surefire reports. Structured PASS/WARN/FAIL report. Frontmatter limited to `name` and `description` so any coding agent that reads `agents/` loads it; the `lutece-v8-review` skill drives it elsewhere. |

## Rules

Short constraints applied to files matching a glob. Source of truth: `rules/*.md` (Claude Code format, `paths:` frontmatter). `rules-cursor/*.mdc` and the tables below are generated from it (`scripts/build-cursor-rules.sh`, `scripts/build-tables.sh`).

<!-- rules:start -->
| Rule | Applies to | Constraint |
|---|---|---|
| `dao-patterns` | `**/business/**/*.java` | Lutece 8 DAO/Home constraints: DAOUtil lifecycle, generated keys, SQL constants, Home facade, CDI lookup |
| `dependency-convergence` | `pom.xml` | Lutece 8 dependency convergence: latest released global-pom 8.x as parent, Jakarta EE 10 pins, which test artifacts each parent manages, enforcer rules from 8.0.2 |
| `dependency-references` | always | When a task involves a dependency (Lutece or external), ensure its source/docs are available for exploration |
| `java-conventions` | `**/*.java` | Lutece 8 global Java conventions: Jakarta EE, CDI, forbidden patterns |
| `jsp-admin` | `**/*.jsp` | Lutece 8 JSP constraints: admin feature JSP boilerplate, bean naming, errorPage, no init() for MVC beans |
| `messages-properties` | always | Lutece 8 i18n constraints: no prefix in .properties, prefix in Java/templates, key naming |
| `plugin-descriptor` | `**/plugins/*.xml` | Lutece 8 plugin.xml constraints: structure, icon-url, core-version-dependency, admin-feature and application declaration |
| `rest-resource` | `**/rs/**/*.java`, `**/rest/**/*.java` | Lutece 8 JAX-RS resources: application path, securing endpoints per resource, and how a bench tests them |
| `service-layer` | `**/service/**/*.java` | Lutece 8 service layer constraints: CDI scopes, injection, getInstance removal, events, configuration |
| `sql-liquibase` | `**/sql/**/*.sql` | Lutece 8 SQL: every plugin .sql (create_db, init_db, init_core, upgrade) MUST carry the Liquibase formatted-sql header, otherwise the schema silently fails to deploy in v8 |
| `sql-rename` | `**/sql/**/*.sql`, `**/WEB-INF/plugins/*.xml` | Renaming a SQL directory or a plugin: logicalFilePath goes on the changeset line (not the file header), or existing sites replay their creation scripts and lose data |
| `template-back-office` | `**/templates/admin/**/*.html` | Lutece 8 Freemarker constraints: layout macros, list layout (@manageFeature / @table), form components, messages, i18n, vanilla JS |
| `template-front-office` | `**/templates/skin/**/*.html` | Lutece 8 front-office (skin/site) templates: FO macros (c*), Bootstrap 5, vanilla JS, messages null-safety |
| `testing` | `**/test/**/*.java`, `pom.xml` | Lutece 8 build and test commands, JUnit 5 conventions, test base classes |
| `web-bean` | `**/web/**/*.java` | Lutece 8 JspBean/XPage constraints: CDI annotations, @Controller attributes, CRUD lifecycle, CSRF policy, Models, pagination |
<!-- rules:end -->

## Orchestrated workflows

Two skills are written as a lead that dispatches teammates described in `teammates/*.md`. How they run on each coding agent is described once, in the `using-lutecepowers` skill (section Subagents and teams). The lead never edits files after dispatch, only the verifier builds, and no skill ever commits.

### Migration (`lutece-migration-v8-agent-teams`)

| Phase | What | Who |
|-------|------|-----|
| A — Scan | `scan-project.sh` → JSON inventory, dependency v8 check | lead |
| B — Task decomposition | `task-splitter.sh` → per-teammate JSON task files | lead |
| C — Dispatch | config-migrator, java-migrator (×1-3), template-migrator, test-migrator, verifier | lead |
| D — Dependencies | config → java → template + test → verifier final build | lead |
| E — Monitoring | `progress-report.sh`, blocker resolution | lead |
| F — Final gate | 0 FAIL on `verify-migration.sh`, compile success, 0 failures and 0 errors in the surefire reports, `lutece-v8-reviewer` | verifier + lead |

Scripts (`skills/lutece-migration-v8-agent-teams/scripts/`): `scan-project.sh`, `task-splitter.sh`, `migrate-java-mechanical.sh`, `migrate-template-mechanical.sh`, `extract-context-beans.sh`, `verify-migration.sh` (78 checks, `--json`), `verify-file.sh`, `add-liquibase-headers.sh`, `progress-report.sh`.

### Scalability (`lutece-scalability-v8`)

Scans seven scalability axes, reproduces each defect through a UI end-to-end test on a real cluster, fixes it, and proves the fix by turning that test green.

## Known limits

- The `lutece-v8-reviewer` agent keeps only `name` and `description` so every coding agent loads it. Its read-only guarantee is therefore in the prompt, not enforced by a tool allowlist.
- Grok Build 1.0.13 discovers the plugin hooks but does not execute them, so the reference sync and the rules copy do not run there. Skills still trigger from their descriptions.
- Codex runs its own sandbox (bwrap). Inside another sandbox, run `codex exec --dangerously-bypass-approvals-and-sandbox` or the scan scripts fail to start.
