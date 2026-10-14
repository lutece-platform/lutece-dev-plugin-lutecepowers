# How lutecepowers works

The detail behind the [README](../README.md): prerequisites, installation per coding agent, what runs at session
start, the hooks, every skill and rule, the orchestrated workflows and the known limits.

## Prerequisites

Linux, or Windows through WSL 2: native Windows and Git Bash are not supported. Keep the projects in the Linux file system (`~/…`), never under `/mnt/c`. `tools/doctor.sh` checks all of this. On Windows, from an administrator PowerShell, run `wsl --install -d Ubuntu-24.04`, then work inside the distribution.

On Ubuntu 24.04:

```bash
sudo apt install git python3-yaml openjdk-21-jdk-headless nodejs curl zip unzip
curl -s "https://get.sdkman.io" | bash
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk install maven
```

- The Maven of apt is 3.8 on Ubuntu 24.04; SDKMAN installs 3.9 (not 4). The Lutece POMs declare their Maven repository: no `settings.xml` is needed.
- node checks the plugin's scripts (JS07); without it, JS07 reports NOT EVALUATED. PyYAML is read by the e2e bench.
- WSL puts the Windows PATH after the Linux one: `command -v mvn` must print a Linux path, not one under `/mnt/c`.
- In WSL, the e2e bench needs Docker Desktop (WSL 2 backend) with the distribution ticked in Settings > Resources > WSL integration.

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
3. On Claude Code, when the current directory is a Lutece 8 Maven project, copies the rules into `.claude/rules/` so they load automatically by path; a project whose Lutece parent or lutece-core is below 8 (`tools/lutece-level.py`) gets none, and loses the copies of an earlier session, unless it carries `.migration/`. It also exports `LUTECEPOWERS_ROOT` to the shell.
4. In a Lutece project, shows the user one line for the project and its Lutece level (`tools/start-banner.py`), the command to run (`lutece-update-plugin` or `lutece-update-site` below Lutece 8, else `lutece-checkup`), then one line per blocking finding of `tools/doctor.sh` with its fix, also told to the agent.

The reference sync runs at most once per hour, six repositories at a time.

The script takes the coding agent name as an optional argument (Cursor and OpenCode pass it), otherwise detects it from its environment, and emits the output shape that agent expects (`hookSpecificOutput.additionalContext` for Claude Code and Codex; `additional_context` for Cursor).

Coding agents without a usable session hook load the bootstrap another way: OpenCode through an in-process plugin that runs the same hook script and injects its output into the first user message, Grok through the skill description alone.

## Other hooks

- `hooks/verify-edit` (after each edit, Claude Code): runs `tools/verify-file.sh` on the edited file of a Lutece project and hands back, at once, the FAIL and WARN lines the edit added to the committed version. A file that already broke checks, a project whose sources still carry Lutece 7 code, or a project below Lutece 8, gets one non-blocking note per session: leave it unless the user asks, and ask at the end whether to run the update skill. While a project carries `.migration/`, every finding of the edited file comes back. Files under the e2e folder of a project (the bench, never shipped) are left alone.
- `hooks/check-result` (on the first prompt, Claude Code): once the background `lutece-check.sh --quick` is done, shows its first lines to the user and all of it to the agent, as existing debt to leave unless asked.
- `hooks/migration-gate` (Stop, Claude Code): while a project carries `.migration/gate-required`, refuses to end the turn until a full `final-gate.sh` passes.

## Skills

<!-- skills:start -->
| Skill | Use when |
|---|---|
| `lutece-brainstorming` | Use before any creative Lutece work: a new plugin, a new feature, a new screen, or a behaviour change. Explores intent, requirements and design with the user before any implementation. Triggers on 'I want to build', 'add a feature', 'new plugin', 'how should we design'. |
| `lutece-cache` | Use when adding, fixing or reviewing a cache in a Lutece 8 plugin: AbstractCacheableService, CDI initialization, cache keys, invalidation through CDI events. Triggers on 'cache', 'cacheable', 'invalidate', 'CacheService'. |
| `lutece-checkup` | Use when the user wants the mechanical state of a Lutece 8 project (core, plugin, module, site) without changing it: runs every check script of the toolkit in one pass (verify-migration, template scanner, i18n keys, template parse), summarises the blocking and the warning findings, then asks the user what to do. Triggers on 'checkup', 'bilan', 'état du plugin', 'lance les contrôles', 'vérifie le projet', 'mechanical check'. |
| `lutece-e2e` | Use to give a Lutece 8 plugin, module or site an e2e bench run with one command (lpe2e) on the machine's shared e2e server: the latest Lutece 8 snapshots, Open Liberty and MariaDB kept warm, static + dynamic inventory of every back-office screen and action, Playwright suites (screens, YAML scenarios, forms) with a clean-console rule on warm browsers, server timings, SQL digests, JFR, a compact report, a hot loop (lpe2e watch) that applies a template or Java change in the running application and replays the tests it can break in seconds, and the database upgrade (lpe2e upgrade) lived as an environment lives it. Triggers on 'e2e', 'tests de bout en bout', 'Playwright', 'tester tous les écrans', 'banc de test', 'non-régression BO', 'prouver la migration'. |
| `lutece-elasticdata` | Use when creating or modifying an Elasticsearch DataSource module for Lutece 8: DataSource and DataObject interfaces, CDI auto-discovery, @ConfigProperty injection, batch processing, two-daemon indexing, incremental updates through CDI events. Triggers on 'elasticdata', 'Elasticsearch', 'DataSource module'. |
| `lutece-lucene-indexer` | Use when adding plugin-internal Lucene search to a Lutece 8 plugin: custom index, indexing daemon, CDI events, batch processing. Triggers on 'Lucene', 'full-text search inside the plugin', 'indexer'. |
| `lutece-patterns` | Use before writing or reviewing any Lutece 8 code (CRUD, JspBean, XPage, service, DAO, daemon, template) and when answering questions about Lutece 8 architecture, layered design or coding conventions. Canonical patterns extracted from lutece-core. |
| `lutece-rbac` | Use when adding or reviewing permissions in a Lutece 8 plugin: RBAC entity permissions, ResourceIdService, plugin.xml declaration, JspBean authorization checks. Triggers on 'RBAC', 'permission', 'right', 'authorization', 'ResourceIdService'. |
| `lutece-scalability-v8` | Use after a migration to v8 to make a Lutece plugin horizontally scalable and prove it: scans scalability anti-patterns, fixes them, deploys a real 3-instance cluster (Liberty, MariaDB, nginx, Hazelcast) and verifies through UI end-to-end tests. Plugin code only: configuring and deploying a site with several replicas is lutece-site-multi-instance. Triggers on 'scalability', 'cluster', 'multi-instance', 'horizontal scaling' for a plugin. |
| `lutece-site-multi-instance` | Use when a Lutece 8 site (packaging lutece-site, OpenLiberty container image) must run as several replicas behind a load balancer, on Kubernetes or elsewhere: shared HTTP session and Lutece cache (Hazelcast, the tested setup, or another store), clustered Quartz daemons, plugins.dat, Liquibase from one replica, shared Forms index, probes, rolling updates. Site configuration and deployment only; the code of a plugin belongs to lutece-scalability-v8. Triggers on 'site multi-instance', 'plusieurs réplicas', 'plusieurs instances du site', 'site en cluster', 'session partagée', 'Hazelcast', 'déployer le site sur Kubernetes', 'replicas'. |
| `lutece-solr-indexer` | Use when creating or modifying a Solr search module for Lutece 8: SolrIndexer interface, CDI auto-discovery, SolrItem dynamic fields, batch indexing, incremental updates through CDI events. Triggers on 'Solr', 'search module', 'SolrIndexer'. |
| `lutece-update-plugin` | Use when bringing a Lutece plugin, module or library to the Lutece level lutecepowers supports, whatever its starting point: migrating from v7 or older (Spring to CDI, javax to jakarta, XML context, templates, tests), or updating a v8 project to the current level (parent, deprecated API, checks, bench). The scripts report every checkable finding with what to do, one agent makes every change, a read-only reviewer and the e2e bench prove the result. Triggers when the user asks to migrate or update the whole plugin, module or library: 'migrate to v8', 'upgrade to Lutece 8', 'migration v7 v8', 'CDI migration', 'passer en v8', 'montée de version', 'mise à niveau v8', 'migrer le plugin', 'mettre à jour le plugin'. |
| `lutece-update-site` | Use when bringing a Lutece site (packaging lutece-site: a site, a pack or a theme) to the Lutece 8 level lutecepowers supports, whatever its starting point: migrating a v7 or older site, or updating a v8 site (parent, BOM, starter, pack). Checks first that every artefact the site ships has a Lutece 8 version and hands the missing ones to lutece-update-plugin; then proves that nothing the site configured, shipped or overrode is lost, by comparing the assembled site before and after and by running it. Triggers when the user asks to migrate or update the whole site: 'migrer un site', 'passer le site en v8', 'mettre à jour le site', 'montée de version du site', 'monter le pack', 'site v8', 'migrate site', 'update site'. |
| `lutece-update-template-bo` | Converts a Lutece Back Office (admin) template to the BO FreeMarker macros of lutece-core (Tabler theme). Discovers the macros from the core sources rather than from a fixed list, so it never goes stale, and applies the house rules that are not readable from the macro files: manageFeature versus table, the mandatory empty state, the page hierarchy, no offcanvas (a modal or a plain link), no inline form, and the e-mail templates that must never be converted. Takes the template path as argument. Triggers on 'migrer un template BO', 'convertir un template admin', 'macros BO', 'thème tabler', 'update back office template'. |
| `lutece-update-template-fo` | Converts a Lutece Front Office (skin) template to the FO FreeMarker macros of lutece-core. Discovers the macros from the core sources rather than from a fixed list, so it never goes stale, and applies the rules that are not readable from the macro files: the FO macros are never the Back Office ones, the FreeMarker syntax to use, Bootstrap 5 classes, and the jQuery that must become vanilla JS. Takes the template path as argument. Triggers on 'migrer un template FO', 'convertir un template skin', 'macros FO', 'front office template', 'update skin template'. |
| `lutece-v8-review` | Use when the user asks to review, audit, check or verify a Lutece plugin, module or library for v8 compliance or conformity, or after a migration to v8 before delivering. Read-only. Dispatches the lutece-v8-reviewer instructions as a subagent, or follows them inline on a harness without dispatch. |
| `lutece-workflow` | Use when creating or modifying a Lutece 8 workflow module: tasks, CDI producers, task components, templates, configuration DAOs. Triggers on 'workflow', 'task', 'workflow module', 'TaskComponent'. |
<!-- skills:end -->

## Agent

| Agent | Description |
|-------|-------------|
| `lutece-v8-reviewer` | Read-only compliance reviewer. Runs `scan-project.sh` and `verify-migration.sh`, then semantic analysis (CDI scopes, singletons, producers), then a full build with tests read from the surefire reports. Structured PASS/WARN/FAIL report. Frontmatter limited to `name` and `description` so any coding agent that reads `agents/` loads it; the `lutece-v8-review` skill drives it elsewhere. |

## Rules

Short constraints applied to files matching a glob. Source of truth: `rules/*.md` (Claude Code format, `paths:` frontmatter). `rules-cursor/*.mdc` and the tables below are generated from it (`scripts/build-cursor-rules.sh`, `scripts/build-tables.sh`).

<!-- rules:start -->
| Rule | Applies to | Constraint |
|---|---|---|
| `dao-patterns` | `**/business/**/*.java` | Lutece 8 DAO/Home constraints: DAOUtil lifecycle, generated keys, SQL constants, Home facade, CDI lookup |
| `dependency-convergence` | `pom.xml` | Lutece 8 dependency convergence: latest released global-pom 8.x as parent, Jakarta EE 10 pins, which test artifacts the parent manages, enforcer rules |
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

How subagents and teammates run on each coding agent is described once, in the `using-lutecepowers` skill (section Subagents and teams). No skill ever commits.

### Update (`lutece-update-plugin`)

Brings a plugin, module or library to the supported Lutece level whatever its starting point: a pre-v8 artefact gets
the full migration and the takeover of its v7 database, a v8 one is aligned on the current level. One agent, in a
fixed order; the scripts report every checkable finding with what to do, the agent makes every change.

| Phase | What |
|-------|------|
| A — Scan | `scan-project.sh` → JSON inventory, starting point (`pre-v8` or `v8`), dependency v8 check |
| B — First check | `lutece-check.sh`: every finding by code, the work of the steps |
| C — Steps | config, Java, templates, tests (`steps/*.md`): all of them from pre-v8, only those with a finding from v8 |
| D — Build | `final-gate.sh --no-e2e`: 0 compiler warning, 0 failures and 0 errors in the surefire reports, 0 FAIL |
| E — Review | `lutece-v8-reviewer`, a read-only subagent |
| F — e2e bench | `lutece-e2e` (`lpe2e`, fixes through `lpe2e watch`), one subagent |
| G — Gate loop | `final-gate.sh` until green, every WARN fixed or justified |

Scripts (`tools/`): `lutece-check.sh`, `scan-project.sh`, `final-gate.sh`, `verify-migration.sh` (100+ checks, `--json`), `verify-file.sh`, and what they call.

### Scalability (`lutece-scalability-v8`)

Scans seven scalability axes, reproduces each defect through a UI end-to-end test on a real cluster, fixes it, and proves the fix by turning that test green.

## Known limits

- The `lutece-v8-reviewer` agent keeps only `name` and `description` so every coding agent loads it. Its read-only guarantee is therefore in the prompt, not enforced by a tool allowlist.
- Grok Build 1.0.13 discovers the plugin hooks but does not execute them, so the reference sync and the rules copy do not run there. Skills still trigger from their descriptions.
- Codex runs its own sandbox (bwrap). Inside another sandbox, run `codex exec --dangerously-bypass-approvals-and-sandbox` or the scan scripts fail to start.
