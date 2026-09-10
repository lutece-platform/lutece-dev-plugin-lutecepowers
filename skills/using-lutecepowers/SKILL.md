---
name: using-lutecepowers
description: Use at the start of every session in a Lutece project, before any other action. Explains which Lutece skills, rules, reference sources and build commands exist, and how to reach them from your harness. Triggers on any Lutece 8 plugin, module, library or site work, on any v7 to v8 migration, and whenever a pom.xml declares lutece-plugin, lutece-module, lutece-library or lutece-site packaging.
license: MIT
compatibility: Works on any harness that loads Agent Skills. Subagent and team dispatch are optional and degrade to sequential execution.
metadata:
  author: Lutece
  homepage: https://github.com/lutece-platform/lutece-dev-plugin-lutecepowers
---

# Using Lutecepowers

Lutecepowers is a set of skills, path-scoped rules, reference sources and scripts for **Lutece 8** development. The content is the same on every harness. Only the way you invoke a skill or dispatch a subagent changes, see [Harness adaptation](#harness-adaptation).

## Mandatory reads

1. **Before writing any Lutece code** (bean, service, DAO, XPage, daemon, template): load the `lutece-patterns` skill.
2. **Before editing a file matching a rule glob** (table below): read that rule file. On Claude Code the rules are also loaded automatically from `.claude/rules/`.
3. **Before writing any non-trivial pattern**: search `~/.lutece-references/` for an existing implementation (Read, Grep, Glob). The references are the living truth. They are cloned and updated in the background at session start, and each one also carries its v7 branches (`develop_core7`, `master_core7`; `develop7.x` for lutece-core) to compare a pattern before and after migration.

## Plugin root

Skills, agents and scripts refer to the installed plugin directory as `${LUTECEPOWERS_ROOT}`.

- The session-start hook prints the absolute value at the top of the context it injects and substitutes it in this text. On Claude Code it is also exported to your shell.
- If the variable is not set in your shell, substitute the literal path from the injected context.
- Every script also resolves the root from its own location, so `bash "${LUTECEPOWERS_ROOT}/skills/<skill>/scripts/<script>.sh"` works as soon as the path is right.
- Fallback when nothing is injected: `find ~ -maxdepth 7 -path '*/skills/using-lutecepowers/SKILL.md' 2>/dev/null | head -1`, then take the directory two levels up.
- When you dispatch a subagent or teammate, write the literal path into its prompt. A subagent does not see this context.

## Skills

<!-- skills:start -->
| Skill | Use when |
|---|---|
| `lutece-brainstorming` | Use before any creative Lutece work: a new plugin, a new feature, a new screen, or a behaviour change. Explores intent, requirements and design with the user before any implementation. Triggers on 'I want to build', 'add a feature', 'new plugin', 'how should we design'. |
| `lutece-cache` | Use when adding, fixing or reviewing a cache in a Lutece 8 plugin: AbstractCacheableService, CDI initialization, cache keys, invalidation through CDI events. Triggers on 'cache', 'cacheable', 'invalidate', 'CacheService'. |
| `lutece-dao` | Use when creating, modifying or reviewing a Lutece 8 DAO, Home or business class: DAOUtil lifecycle, SQL constants, Home static facade, CDI lookup, collection types, interface conventions. Must be consulted before touching anything under a business package. |
| `lutece-elasticdata` | Use when creating or modifying an Elasticsearch DataSource module for Lutece 8: DataSource and DataObject interfaces, CDI auto-discovery, @ConfigProperty injection, batch processing, two-daemon indexing, incremental updates through CDI events. Triggers on 'elasticdata', 'Elasticsearch', 'DataSource module'. |
| `lutece-lucene-indexer` | Use when adding plugin-internal Lucene search to a Lutece 8 plugin: custom index, indexing daemon, CDI events, batch processing. Triggers on 'Lucene', 'full-text search inside the plugin', 'indexer'. |
| `lutece-migration-v8-agent-teams` | Use when migrating a Lutece v7 plugin, module or library to v8: Spring to CDI, javax to jakarta, XML context to JSON, templates, tests. Script-heavy, JSON-driven task decomposition run by teammates or subagents, with a sequential fallback. Triggers on 'migrate to v8', 'migration v7 v8', 'CDI migration'. |
| `lutece-patterns` | Use before writing or reviewing any Lutece 8 code (CRUD, JspBean, XPage, service, DAO, daemon, template) and when answering questions about Lutece 8 architecture, layered design or coding conventions. Canonical patterns extracted from lutece-core. |
| `lutece-rbac` | Use when adding or reviewing permissions in a Lutece 8 plugin: RBAC entity permissions, ResourceIdService, plugin.xml declaration, JspBean authorization checks. Triggers on 'RBAC', 'permission', 'right', 'authorization', 'ResourceIdService'. |
| `lutece-scalability-v8` | Use after a v7 to v8 migration to make a Lutece plugin horizontally scalable and prove it: scans scalability anti-patterns, fixes them, deploys a real 3-instance cluster (Liberty, MariaDB, nginx, Hazelcast) and verifies through UI end-to-end tests. Triggers on 'scalability', 'cluster', 'multi-instance', 'horizontal scaling'. |
| `lutece-solr-indexer` | Use when creating or modifying a Solr search module for Lutece 8: SolrIndexer interface, CDI auto-discovery, SolrItem dynamic fields, batch indexing, incremental updates through CDI events. Triggers on 'Solr', 'search module', 'SolrIndexer'. |
| `lutece-update-template-bo` | Use when the user asks to migrate, convert or update a Lutece Back Office (admin) template to the BO FreeMarker macros from lutece-core (Tabler theme). Takes the template path as argument. |
| `lutece-update-template-fo` | Use when the user asks to migrate, convert or update a Lutece Front Office (skin) template to the FO FreeMarker macros from lutece-core. Takes the template path as argument. |
| `lutece-v8-review` | Use when the user asks to review, audit, check or verify a Lutece plugin, module or library for v8 compliance or conformity, or after a v7 to v8 migration before delivering. Read-only. Dispatches the lutece-v8-reviewer instructions as a subagent, or follows them inline on a harness without dispatch. |
| `lutece-workflow` | Use when creating or modifying a Lutece 8 workflow module: tasks, CDI producers, task components, templates, configuration DAOs. Triggers on 'workflow', 'task', 'workflow module', 'TaskComponent'. |
<!-- skills:end -->

The reviewer procedure itself is `${LUTECEPOWERS_ROOT}/agents/lutece-v8-reviewer.md`, also registered as a native agent where the harness loads `agents/`.

## Rules

Rules are short constraints that apply to files matching a glob. Source files live in `${LUTECEPOWERS_ROOT}/rules/`. Tables below are generated from the skill and rule frontmatter (`scripts/build-tables.sh`).

<!-- rules:start -->
| Rule | Applies to | Constraint |
|---|---|---|
| `dao-patterns` | `**/business/**/*.java` | Lutece 8 DAO/Home constraints: DAOUtil lifecycle, SQL constants, Home facade, CDI lookup |
| `dependency-references` | always | When a task involves a dependency (Lutece or external), ensure its source/docs are available for exploration |
| `java-conventions` | `**/*.java` | Lutece 8 global Java conventions: Jakarta EE, CDI, forbidden patterns |
| `jsp-admin` | `**/*.jsp` | Lutece 8 JSP constraints: admin feature JSP boilerplate, bean naming, errorPage |
| `messages-properties` | always | Lutece 8 i18n constraints: no prefix in .properties, prefix in Java/templates, key naming |
| `plugin-descriptor` | `**/plugins/*.xml` | Lutece 8 plugin.xml constraints: mandatory tags, icon-url, core-version-dependency, admin-feature declaration |
| `service-layer` | `**/service/**/*.java` | Lutece 8 service layer constraints: CDI scopes, injection, events, configuration |
| `sql-liquibase` | `**/sql/**/*.sql` | Lutece 8 SQL: every plugin .sql (create_db, init_db, init_core, upgrade) MUST carry the Liquibase formatted-sql header, otherwise the schema silently fails to deploy in v8 |
| `sql-rename` | `**/sql/**/*.sql`, `**/WEB-INF/plugins/*.xml` | Renaming a SQL directory or a plugin: logicalFilePath goes on the changeset line (not the file header), or existing sites replay their creation scripts and lose data |
| `template-back-office` | `**/templates/admin/**/*.html` | Lutece 8 Freemarker constraints: layout macros, form components, JSP paths, i18n |
| `template-front-office` | `**/templates/skin/**/*.html` | Lutece 8 front-office (skin/site) templates: Bootstrap 5, vanilla JS, core modules |
| `testing` | `**/test/**/*.java`, `pom.xml` | Lutece 8 build and test commands, JUnit 5 conventions, test base classes |
| `web-bean` | `**/web/**/*.java` | Lutece 8 JspBean/XPage constraints: CDI annotations, CRUD lifecycle, security tokens, pagination |
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

## Subagents and teams

Two skills (`lutece-migration-v8-agent-teams`, `lutece-scalability-v8`) are written as a lead orchestrating **teammates** described in `teammates/*.md` files.

- **Harness with a team or subagent tool**: dispatch one subagent per teammate with the spawn template given in the skill. On Claude Code, Agent Teams is experimental and needs `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`; without it, use regular subagents.
- **Harness without dispatch**: run the teammates yourself, sequentially, in the dependency order the skill gives. Read each teammate file, execute it fully, then move to the next. Never invent a tool call.

## Harness adaptation

Skills name actions (read a file, run a command, invoke a skill, dispatch a subagent). Map them to your tools with the reference for your harness:

- Codex: `references/codex-tools.md`
- Cursor: `references/cursor-tools.md`
- OpenCode: `references/opencode-tools.md`
- Claude Code, Grok Build: native tool surface, no mapping needed.

User instructions (CLAUDE.md, AGENTS.md, direct requests) take precedence over skills, which override default behaviour.
