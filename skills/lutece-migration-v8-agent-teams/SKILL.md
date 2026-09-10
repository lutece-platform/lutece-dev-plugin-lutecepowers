---
name: lutece-migration-v8-agent-teams
description: "Use when migrating a Lutece v7 plugin, module or library to v8: Spring to CDI, javax to jakarta, XML context to JSON, templates, tests. Script-heavy, JSON-driven task decomposition run by teammates or subagents, with a sequential fallback. Triggers on 'migrate to v8', 'migration v7 v8', 'CDI migration'."
---

# Lutece Migration v7→v8 — Agent Teams Orchestrator

## Purpose

Migrates any Lutece plugin/module/library from v7 to v8 using **Agent Teams (Swarm Mode)**. The Team Lead (you) orchestrates, specialized teammates execute in parallel, and bash scripts handle all mechanical work.

**Prerequisites:** a harness that can dispatch subagents or teammates. On Claude Code, Agent Teams is experimental and needs `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`; plain subagents also work. Without any dispatch tool, run the teammates yourself sequentially in the dependency order below (see `using-lutecepowers`, section Subagents and teams).

---

## PHASE A — Scan (Lead executes directly)

### A.1 — Verify Lutece project
Confirm the current directory is a Lutece project (pom.xml with lutece-plugin/module/library packaging).

### A.2 — Run scanner
```bash
mkdir -p .migration
bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/scan-project.sh . > .migration/scan.json
```

### A.3 — Display summary
Read `.migration/scan.json` and show the user:
- Project type, artifact, version
- Migration scope (SMALL/MEDIUM/LARGE)
- Total migration points
- Recommended teammate count

### A.4 — Dependency v8 check (BLOCKER)
For every Lutece dependency in `scan.json`:
1. If `v8Status: "available"` → OK (already cloned in `~/.lutece-references/`)
2. If `v8Status: "unknown"` → Search GitHub orgs `lutece-platform` and `lutece-secteur-public` for v8 branch
3. Branch priority: `develop_core8` > `develop8` > `develop8.x` > `develop`
4. If a dependency has NO v8 version → **STOP**. Do not proceed. Report to user.
5. **Clone missing dependencies** — For each dependency confirmed v8 but not yet in `~/.lutece-references/`:
   ```bash
   git clone -q --branch <v8_branch> --single-branch https://github.com/<org>/<artifactId>.git ~/.lutece-references/<artifactId>
   ```
   This ensures teammates can search reference sources for ALL dependencies, not just the 21 pre-cloned repos.

---

## PHASE B — Task Decomposition (Lead executes directly)

```bash
bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/task-splitter.sh .migration/scan.json .migration
```

Read the output to know how many teammates to spawn.

---

## PHASE C — Spawn Teammates

On Claude Code with Agent Teams, switch to **Delegate Mode** (Shift+Tab). From this point, you orchestrate only — never implement. On a harness without dispatch, execute the teammates below yourself, one after the other, in the Phase D order.

### Always spawn:
1. **Config Migrator** (1 teammate)
   - Instructions: `${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/teammates/config-migrator.md`
   - Task file: `.migration/tasks-config.json`

2. **Verifier** (1 teammate)
   - Instructions: `${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/teammates/verifier.md`
   - Starts monitoring immediately, builds only after all others complete

### Conditionally spawn:
3. **Java Migrator(s)** (1-3, based on `scan.json` recommendation)
   - Instructions: `${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/teammates/java-migrator.md`
   - Task files: `.migration/tasks-java-0.json`, `.migration/tasks-java-1.json`, `.migration/tasks-java-2.json`
   - Each gets a DISTINCT file partition — no overlap

4. **Template Migrator** (0-1, if templates/JSP exist)
   - Instructions: `${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/teammates/template-migrator.md`
   - Task file: `.migration/tasks-template.json`

5. **Test Migrator** (0-1, if test files exist)
   - Instructions: `${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/teammates/test-migrator.md`
   - Task file: `.migration/tasks-test.json`

### Spawn instructions template
When spawning each teammate, provide the text below **with `${LUTECEPOWERS_ROOT}` replaced by the literal absolute path** from your session context. A teammate does not see that context and may have no such shell variable.
```
LUTECEPOWERS_ROOT=${LUTECEPOWERS_ROOT} (export it in your shell before running any script)
Read your instruction file at [path to teammates/*.md].
Read your task assignment at [path to .migration/tasks-*.json].
Execute all steps in your instructions. Use scripts from ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/.
Pattern files are at ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/patterns/ — load only when needed.
Reference implementations: always search ~/.lutece-references/ before writing any new pattern.
To see how a pattern was migrated, compare with the v7 version of the same reference in `~/.lutece-references/`: the v7 code is on a `*_core7` branch (`develop_core7`, `master_core7`; lutece-core uses `develop7.x`), listed by `git branch -r`. Repositories born in v8 have none. Consult when stuck on a specific migration pattern.
Run verify-file.sh after each file you complete.
```

---

## PHASE D — Task Dependencies

Wire the dependency graph:

```
Config Migrator ──────────────────────────────────────── (no blockers, runs first)
    │
    ├──→ Java Migrator 0 ─┐
    ├──→ Java Migrator 1 ─┤ (blocked by Config Migrator)
    └──→ Java Migrator 2 ─┘
              │
              ├──→ Template Migrator ─┐ (blocked by ALL Java Migrators)
              └──→ Test Migrator ─────┤ (blocked by Config + at least 1 Java Migrator)
                                      │
                                      └──→ Verifier: Final Build (blocked by ALL above)
```

- Config Migrator runs first (POM, beans.xml, context XML catalog)
- Java Migrators start after Config completes (they need context-beans.json)
- Template Migrator starts after ALL Java Migrators complete (needs @Named bean names)
- Test Migrator starts after Config + at least 1 Java Migrator complete
- Verifier monitors continuously but only builds after ALL others complete

---

## PHASE E — Monitoring

While teammates work:

1. Check task list progress every ~30 seconds
2. Run progress report periodically:
   ```bash
   bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/progress-report.sh .
   ```
3. **If a teammate is stuck** (same task > 5 min): send a message via mailbox asking for status
4. **If a teammate reports a blocker**: investigate and either reassign, advise, or fix the blocker
5. **If the Verifier reports increasing FAILs**: pause the responsible teammate and investigate

---

## PHASE F — V8 Reviewer (Lead spawns as teammate)

When the Verifier reports **BUILD SUCCESS** (compile + tests) and **verify-migration.sh: 0 FAIL**, spawn a **Reviewer teammate**:

```
LUTECEPOWERS_ROOT=${LUTECEPOWERS_ROOT} (literal path, export it in your shell)
Read your instruction file at ${LUTECEPOWERS_ROOT}/agents/lutece-v8-reviewer.md.
Review this project for v8 compliance. Do NOT modify any files.
Reference implementations: ~/.lutece-references/
v7 versions of the references: `*_core7` branches in each repository under ~/.lutece-references/ (see `git branch -r`).
```

**Why a teammate?** In Delegate Mode the Lead can only spawn teammates. The reviewer runs as a read-only teammate (or a read-only subagent, or inline when no dispatch exists) and reports findings without modifying files.

Process the reviewer's findings:
- **FAIL items**: Assign fixes to the appropriate teammate. Re-spawn reviewer after fixes.
- **WARN items**: Attempt to fix via teammates but do not block on WARNs.
- **All FAIL resolved**: Proceed to Phase G.

---

## PHASE G — Final Gate

When ALL of the following are true:
- **BUILD SUCCESS** (both compile and tests)
- **verify-migration.sh**: 0 FAIL
- **Reviewer agent**: all FAIL items resolved

Then:
1. Ask the Verifier to run final cleanup (.migration/ removal, context XML deletion)
2. Present the migration summary to the user:
   - `verify-migration.sh` results (PASS/FAIL/WARN counts)
   - Build result (`mvn clean install` — compile + tests)
   - Number of test classes, tests run, tests passed/failed/skipped
   - Reviewer agent verdict (PASS/FAIL/WARN counts)
   - List of files modified
3. Clean up the team
4. **STOP.** Do NOT commit. The user decides when and how to commit.

---

## Strict Rules

1. **Delegate mode**: After Phase B, the Lead orchestrates only — never modifies files
2. **No builds before completion**: The project WILL NOT compile during migration. Only the Verifier builds.
3. **NEVER commit**: The skill must NEVER create git commits. Leave that to the user.
4. **Reference-First Rule**: ALL teammates must search `~/.lutece-references/` before writing new patterns
5. **File ownership**: Each file is owned by exactly one teammate. No two teammates touch the same file.
6. **Script-first**: Teammates run mechanical scripts FIRST, then apply intelligence to remaining issues
7. **Verify per-file**: Teammates run `verify-file.sh` after each file, not just at the end

## Manual review hotspots

The scan reports counts only — these patterns require human judgment, no mechanical sed:

- **`shutdownServiceImpls`** — Classes implementing `fr.paris.lutece.portal.service.init.ShutdownService`. With CDI-managed `@ApplicationScoped` beans, replace with Jakarta-native `@PreDestroy` on a shutdown method. **Drop the interface entirely if `process()` does nothing meaningful** (no real cleanup work). When real cleanup exists:
  ```java
  // Before
  public class XService implements ShutdownService {
      @Override public String getName() { return "XService"; }
      @Override public void process() { client.close(); }
  }
  // After
  public class XService {
      @PreDestroy void shutdown() { client.close(); }
  }
  ```
  Java Migrators handle this case-by-case. Don't auto-replace via sed — `getName()` may have legitimate uses elsewhere.

---

## Script Locations

All in `${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/`:

| Script | Purpose | Used by |
|--------|---------|---------|
| `scan-project.sh` | Full project scan → JSON | Lead (Phase A) |
| `task-splitter.sh` | JSON scan → per-teammate task files | Lead (Phase B) |
| `migrate-java-mechanical.sh` | javax→jakarta + Spring→CDI + net.sf.json imports | Java Migrators |
| `migrate-template-mechanical.sh` | BO macros + null-safety + namespace | Template Migrator |
| `extract-context-beans.sh` | Spring context XML → JSON catalog | Config Migrator |
| `verify-migration.sh` | 70+ checks, optional --json mode | Verifier |
| `verify-file.sh` | Per-file verification subset | All teammates |
| `add-liquibase-headers.sh` | Liquibase headers on SQL files | Config Migrator |
| `progress-report.sh` | Migration progress display | Lead (Phase E) |

## Pattern Locations

All in `${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/patterns/`:

| File | Content | Loaded by |
|------|---------|-----------|
| `cdi-patterns.md` | CDI scopes, injection, producers, singleton, Models, Pager, Key Imports | Java Migrators (always) |
| `events-patterns.md` | Event/listener migration | Java Migrators (if events) |
| `cache-patterns.md` | EhCache→JCache | Java Migrators (if cache) |
| `rest-patterns.md` | Jersey→JAX-RS, filters, providers | Java Migrators (if REST) |
| `mvc-patterns.md` | @RequestParam, CSRF auto-filter, @ModelAttribute | Java Migrators (if JspBean/XPage) |
| `template-macros.md` | v8 Freemarker macros, jQuery→vanilla JS | Template Migrator |
| `fileupload-patterns.md` | FileItem→MultipartItem | Java Migrators (if fileupload) |
| `json-patterns.md` | json-lib→Jackson | Java Migrators (if net.sf.json) |
