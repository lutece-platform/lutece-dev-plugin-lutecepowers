---
name: using-lutecepowers
description: Use at the start of every session in a Lutece project, before any other action. Explains which Lutece skills, rules, reference sources and build commands exist, and how to reach them from your harness. Triggers on any Lutece 8 plugin, module, library or site work, on any migration to v8, and whenever a pom.xml declares lutece-plugin, lutece-module, lutece-library or lutece-site packaging.
license: MIT
compatibility: Works on any harness that loads Agent Skills. Subagent and team dispatch are optional and degrade to sequential execution.
metadata:
  author: Lutece
  homepage: https://github.com/lutece-platform/lutece-dev-plugin-lutecepowers
---

# Using Lutecepowers

Lutecepowers is a set of skills, path-scoped rules, reference sources and scripts for **Lutece 8** development. The content is the same on every harness. Only the way you invoke a skill or dispatch a subagent changes, see [Harness adaptation](#harness-adaptation).

## Scope

- Do the task the user asked and what it needs to pass (a build or a test it is about), nothing wider.
- The user asks to migrate or update the whole project: load `lutece-update-plugin` (a site: `lutece-update-site`).
- Lutece 8 debt the task does not need (a project below Lutece 8, code the checks already reject): leave it unless the
  user asks, never fix it piece by piece on your own. End your answer by asking, in the user's language, whether to run
  `lutece-update-plugin` (a site: `lutece-update-site`) on the whole project; load it only when the user says yes.
- A project's Lutece version is the one its poms declare (Lutece parent, lutece-core), never what its imports suggest.
  Below 8 and not being updated, work in its own version: the reads, rules and checks below describe Lutece 8.

## Mandatory reads

On a Lutece 8 project, and during an update to it:

1. **Before writing any Lutece code** (bean, service, DAO, XPage, daemon, template): load the `lutece-patterns` skill.
2. **Before editing a file matching a rule glob** (table below): read that rule file. On Claude Code the rules are also loaded automatically from `.claude/rules/`.
3. **Before writing any non-trivial pattern**: search `~/.lutece-references/` for an existing implementation. The references are the living truth. They are cloned and updated in the background at session start from the `develop` branch (where v8 lives), and each one also carries the v7 branches that exist upstream (`develop_core7`, `master_core7`; `develop7.x` and `master7.x` for lutece-core), listed by `git branch -r`, to compare a pattern before and after migration. Repositories born in v8 have none. The list of repositories is the `REPOS` array of `${LUTECEPOWERS_ROOT}/hooks/sync-references`.

## Plugin root

Skills, agents and scripts refer to the installed plugin directory as `${LUTECEPOWERS_ROOT}`.

- The session-start hook prints the absolute value at the top of the context it injects and substitutes it in this text. On Claude Code it is also exported to your shell.
- If the variable is not set in your shell, substitute the literal path from the injected context.
- Every script also resolves the root from its own location, so `bash "${LUTECEPOWERS_ROOT}/tools/<script>.sh"` works as soon as the path is right.
- Fallback when nothing is injected: `find ~ -maxdepth 7 -path '*/skills/using-lutecepowers/SKILL.md' 2>/dev/null | head -1`, then take the directory containing `skills/`.
- When you dispatch a subagent or teammate, write the literal path into its prompt. A subagent does not see this context.

## Toolkit

One command checks any Lutece project, a v7 one to migrate as a v8 one:

- `bash ${LUTECEPOWERS_ROOT}/tools/lutece-check.sh <project>` runs every check and prints only the findings of this
  project, each with what to do; `--explain CODE` says what a check proves and how to fix it.
- `bash ${LUTECEPOWERS_ROOT}/tools/doctor.sh <project>` checks the machine (Linux or WSL 2, the project outside
  `/mnt/c`, the Linux java and Maven 3.9, git line endings, Docker): run it when the user asks for the doctor, and
  before any work when a build or a bench fails for a reason outside the project.

On Claude Code, every edit of a Lutece file is checked at once: what the edit breaks comes back to you, fix it; what
the file or the project already broke comes as a note (see Scope). What a script reports is not repeated in the skills.

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

The reviewer procedure itself is `${LUTECEPOWERS_ROOT}/agents/lutece-v8-reviewer.md`, also registered as a native agent where the harness loads `agents/`.

## Rules

Rules are short constraints that apply to files matching a glob. Source files live in `${LUTECEPOWERS_ROOT}/rules/`. Tables below are generated from the skill and rule frontmatter (`scripts/build-tables.sh`).

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

Delivery by harness:

- **Claude Code**: the hook copies the rules into `.claude/rules/` of the Lutece project. They load automatically by path (Grok reads that directory too, but does not run the hook).
- **Cursor**: shipped as native `.mdc` rules with `globs`.
- **Other harnesses**: nothing is automatic. Read the rule before touching a matching file.

## Build and test

```bash
# Compile only
mvn clean install -Dmaven.test.skip=true
# Full build with tests (exploded webapp + HSQL are required)
mvn clean lutece:exploded antrun:run -Dlutece-test-hsql test -q
```

Never run plain `mvn test`. Lutece tests need the `lutece:exploded antrun:run` goals first.

## Long-running commands

Never wait on a command. Anything that may take more than about 30 seconds (a build, the e2e bench, a test suite, a
series of measurements) starts in the background and is followed by events: one line per result as soon as it exists,
one per failure signature (error, stack trace, unhealthy, a server start that fails), and a silence detector that
reports a hang after a few seconds without output. Meanwhile, work on something else that does not touch what is
running. Never poll with sleeps, never block the session on a foreground wait.

- Split a series so each result streams on its own (one event per run), and stop the job at the first event that shows
  it is lost, instead of letting it run to its timeout.
- Stop a background job by its id or its pid, never by a name pattern (`pkill -f`): the pattern also matches the
  command that runs it.
- Prefer a tool that reports its outcome itself (the bench's `watch-boot.sh` ends on READY, FAIL or HANG) over a fixed
  timeout.

## Subagents and teams

`lutece-update-plugin` runs in one agent and dispatches two read-only or self-contained subagents, one after the other (the reviewer, the e2e bench). `lutece-scalability-v8` is written as a lead orchestrating **teammates** described in `teammates/*.md` files.

- **Harness with a team or subagent tool**: dispatch one subagent per teammate with the spawn template given in the skill. On Claude Code, Agent Teams is experimental and needs `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`; without it, use regular subagents.
- **Harness without dispatch**: run the subagent or teammate instructions yourself, sequentially, in the order the skill gives. Read each file, execute it fully, then move to the next. Never invent a tool call.

Rules shared by every skill: a project has one writer at a time; no skill ever creates a git commit.

## Harness adaptation

Skills name actions (read a file, run a command, invoke a skill, dispatch a subagent). Map them to your tools with the reference for your harness:

- Codex: `references/codex-tools.md`
- Cursor: `references/cursor-tools.md`
- OpenCode: `references/opencode-tools.md`
- Claude Code, Grok Build: native tool surface, no mapping needed.

User instructions (CLAUDE.md, AGENTS.md, direct requests) take precedence over skills, which override default behaviour.
