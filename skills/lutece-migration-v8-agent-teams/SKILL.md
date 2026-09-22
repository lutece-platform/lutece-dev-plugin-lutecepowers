---
name: lutece-migration-v8-agent-teams
description: "Use when migrating a Lutece plugin, module or library of any version before 8 to v8: Spring to CDI, javax to jakarta, XML context to JSON, templates, tests. Script-heavy, JSON-driven task decomposition run by teammates or subagents, with a sequential fallback. Triggers on 'migrate to v8', 'migration v7 v8', 'CDI migration'."
---

# Lutece Migration to v8 — Agent Teams Orchestrator

## Purpose

Migrates any Lutece plugin/module/library from any version before 8 to v8 with a team of teammates. The Lead (you) orchestrates, specialized teammates execute in parallel, and bash scripts handle all mechanical work.

**Prerequisites:** subagent or teammate dispatch, or the sequential fallback (`using-lutecepowers`, section Subagents and teams).

---

## PHASE A — Scan (Lead executes directly)

### A.1 — Verify Lutece project
Confirm the current directory is a Lutece project (pom.xml with lutece-plugin/module/library packaging).

### A.2 — Run scanner
```bash
mkdir -p .migration
bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/scan-project.sh . > .migration/scan.json
```

Keep the migration's own scratch out of the diff, once, now — a reviewer should never see it, and
`git add -A` at the end would otherwise stage it. The e2e bench (`e2e/`) is part of it: a local test tool,
never committed with the plugin:

```bash
# a file not ending with a newline would glue the first entry to its last line, silently
[ -s .gitignore ] && [ -n "$(tail -c1 .gitignore)" ] && echo >> .gitignore
for p in 'target/' 'logs/' 'java.io.tmpdir/' '.migration/' '*.log' 'e2e/'; do
  grep -qxF "$p" .gitignore 2>/dev/null || echo "$p" >> .gitignore
done
```

### A.3 — Display summary
Read `.migration/scan.json` and show the user:
- Project type, artifact, version
- Migration scope (SMALL/MEDIUM/LARGE)
- Total migration points
- Recommended teammate count
- Persistence base (`summary.persistence`): `hasJpa` → the JPA model is kept on the EclipseLink of the container (`patterns/persistence-patterns.md` §1); `hasSpringJdbc` → Spring JDBC kept as a library (§9)

### A.4 — Dependency v8 check (BLOCKER)
For every Lutece dependency in `scan.json`:
1. If `v8Status: "available"` → OK (already cloned in `~/.lutece-references/`); `latestRelease` / `latestSnapshot` are the published versions the pom will name
2. If `v8Status: "published"` → the artefact exists in the Lutece repositories at the versions listed; clone its sources into `~/.lutece-references/` as the `dependency-references` rule says (the clone, not an edit of the hook)
3. If `v8Status: "to-resolve"` → nothing found locally nor published: find the repository and check its v8 branch (`dependency-references` rule; v8 lives on `develop`, the pom parent must be `8.x`)
4. If a dependency has NO v8 version → **STOP**. Do not proceed. Report to user.
5. **Clone missing dependencies** — for each dependency confirmed v8 but not yet in `~/.lutece-references/`, clone it there yourself (`dependency-references` rule); adding it to the `REPOS` list of `${LUTECEPOWERS_ROOT}/hooks/sync-references` is the lead's job, afterwards, outside the migrated repository. The hook (it clones `develop` and fetches the v7 branches). Teammates can then search reference sources for ALL dependencies, not just the repositories listed in the hook.

---

## PHASE B — Task Decomposition (Lead executes directly)

```bash
bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/task-splitter.sh .migration/scan.json .migration
```

Read the output to know how many teammates to spawn.

---

## PHASE C — Spawn Teammates

From here the lead only orchestrates and never edits files (on Claude Code with Agent Teams: Shift+Tab). On a harness without dispatch, execute the teammates below yourself, one after the other, in the Phase D order.

### Always spawn:
1. **Config Migrator** (1 teammate)
   - Instructions: `${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/teammates/config-migrator.md`
   - Task file: `.migration/tasks-config.json`
   - Sole owner of `webapp/WEB-INF/web.xml` and of the `*_context.xml` files (deleted by it once the Java Migrators are done)

2. **Verifier** (1 teammate)
   - Instructions: `${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/teammates/verifier.md`
   - Starts monitoring immediately, builds only after all others complete; strictly read-only

### Conditionally spawn:
3. **Java Migrator(s)** (1-3, based on `scan.json` recommendation)
   - Instructions: `${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/teammates/java-migrator.md`
   - Task files: `.migration/tasks-java-0.json`, `.migration/tasks-java-1.json`, `.migration/tasks-java-2.json`
   - Each gets a DISTINCT file partition — no overlap
   - Java Migrator 0 also owns `.migration/tasks-java-homes.json` (Home and interface files, excluded from the other partitions)

4. **Template Migrator** (0-1, if templates/JSP exist) — sole owner of the templates and of the `core_admin_right` icon
   - Instructions: `${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/teammates/template-migrator.md`
   - Task file: `.migration/tasks-template.json`
   - Two passes on the same files: the mechanical one (`migrate-template-mechanical.sh --no-webxml`, web.xml belongs to the Config Migrator, then the JSPs), then the design one — assemble, scan, apply the back-office and front-office rule sets, prove each file by parsing and rendering

5. **Test Migrator** (0-1, if test files exist)
   - Instructions: `${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/teammates/test-migrator.md`
   - Task file: `.migration/tasks-test.json`

### Spawn instructions template
When spawning each teammate, provide the text below **with `${LUTECEPOWERS_ROOT}` replaced by the literal absolute path** from your session context. A teammate does not see that context and may have no such shell variable.
```
LUTECEPOWERS_ROOT=${LUTECEPOWERS_ROOT} (export it in your shell before running any script)
Read your instruction file at [path to teammates/*.md].
Read your task assignment at [path to .migration/tasks-*.json] (Java Migrator 0: also .migration/tasks-java-homes.json).
Execute all steps in your instructions. Use scripts from ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/.
Pattern files are at ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/patterns/ — load only when needed.
Reference implementations: always search ~/.lutece-references/ before writing any new pattern; each clone also carries the v7 branches (see using-lutecepowers, Mandatory reads) to compare a pattern before and after migration.
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
              ├──→ Template Migrator ─┐ (blocked by ALL Java Migrators: mechanical pass, then design pass)
              └──→ Test Migrator ──────┤ (blocked by Config + at least 1 Java Migrator)
                                       │
                                       └──→ Verifier: Final Build (blocked by ALL above)
```

- Config Migrator runs first (POM, beans.xml, web.xml, context XML catalog)
- Java Migrators start after Config completes (they need context-beans.json)
- Config Migrator deletes the `*_context.xml` files once ALL Java Migrators complete
- Template Migrator starts after ALL Java Migrators complete (needs @Named bean names)
- Test Migrator starts after Config + at least 1 Java Migrator complete
- Verifier monitors continuously but only builds after ALL others complete

---

## PHASE E — Monitoring

Teammate answers travel through a channel that truncates and may arrive late: every teammate also writes
`.migration/report-<teammate>.md` (what it changed, what it could not, what the next one must know) when it
finishes, and the Lead reads **those files**, not the channel, to decide the next phase.

While teammates work:

1. Check task list progress every ~30 seconds
2. Run progress report periodically:
   ```bash
   bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/progress-report.sh .
   ```
3. **If a teammate is stuck** (same task > 5 min): ask it for status
4. **If a teammate reports a blocker**: investigate and either reassign, advise, or fix the blocker
5. **If the Verifier reports increasing FAILs**: pause the responsible teammate and investigate

---

## PHASE F — V8 Reviewer (Lead spawns as teammate)

When the Verifier reports compile **BUILD SUCCESS**, **0 failures and 0 errors in `target/surefire-reports/*.txt`** (the global-pom sets `testFailureIgnore=true`, so BUILD SUCCESS alone says nothing about the tests) and **verify-migration.sh: 0 FAIL**, spawn a **Reviewer teammate**:

```
LUTECEPOWERS_ROOT=${LUTECEPOWERS_ROOT} (literal path, export it in your shell)
Read your instruction file at ${LUTECEPOWERS_ROOT}/agents/lutece-v8-reviewer.md.
Review this project for v8 compliance. Do NOT modify any files.
Reference implementations: ~/.lutece-references/
```

**Why a teammate?** The Lead does not edit or review files itself after Phase B. The reviewer runs as a read-only teammate (or a read-only subagent, or inline when no dispatch exists) and reports findings without modifying files.

Process the reviewer's findings:
- **FAIL items**: Assign fixes to the appropriate teammate. Re-spawn reviewer after fixes.
- **WARN items**: Attempt to fix via teammates but do not block on WARNs.
- **All FAIL resolved**: Proceed to Phase G.

---

## PHASE G — e2e bench (Lead, through the `lutece-e2e` skill)

A migration that compiles and whose unit tests pass has proved nothing about the screens. Unit tests cover almost
none of a Lutece plugin, and the defects that hurt are the ones they cannot see: a portlet rendering an empty
string, a form the browser closes because it is nested where HTML forbids it, a screen answering 500 on an unknown
id.

**Invoke the `lutece-e2e` skill on the project** and follow it. It materialises `e2e/`, runs the stack, inventories
every screen and action, and reports. One command afterwards: `KEEP=1 ./e2e/run.sh`.

Read its report with the migration in mind:

- **Every red scenario is attributed** — to the plugin, or to the core, with the evidence. A red nobody explains is
  a red nobody keeps.
- **A green suite is not a proof.** Check that the front-office assertion targets the portlet's own markup and not a
  text the site menu also carries, and that screens are opened with the parameters they require. Both traps produce
  green runs that prove nothing; `lutece-e2e` documents them.
- **A fix the bench forced you to make inside `e2e/` is a defect of `lutece-e2e`**, not of the plugin. Report it so
  it goes back into that skill.

Then fix what it found, and go to Phase H. The gate runs the bench again.

---

## PHASE H — Fix and re-verify until the gate passes

**This phase is a loop, not a checkpoint.** Run the gate, fix what is red, run it again. Keep going until it
passes. A migration is done when the gate says so, never when someone judges the remaining red acceptable.

```bash
bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/final-gate.sh .
```

Each turn of the loop:

1. **Read what is red**, and only that. The gate names the check, the failing test or the failing suite.
2. **Fix it at the source.** Never silence it: an allowlist entry, a deleted assertion or a scenario rewritten to
   expect the defect all turn the gate green while the defect stays.
3. **Run the gate again, in full.** A fix invalidates more than it touches: a ported portlet breaks the tests that
   asserted on its old rendering, a fixed defect turns the scenario pinning it red.

**The only way out other than green** is a red you attribute, with evidence, to something the plugin cannot fix: a
core defect, or a missing capability of the container. Name it, prove it, and carry it into the hand-over as an open
item.

**Stop the loop and ask** when the same red comes back a third time after three different fixes. That is a sign the
diagnosis is wrong, not the fix, and another round will not find it.

The gate passes when ALL of the following are true:
- Compile **BUILD SUCCESS**, **0 compiler warning in the plugin's sources** (`-Dmaven.compiler.showWarnings=true -Dmaven.compiler.showDeprecation=true`: deprecation, unchecked, rawtypes, serial… all fixed, never suppressed), and surefire reports with 0 failures and 0 errors
- **verify-migration.sh**: 0 FAIL
- **Reviewer agent**: all FAIL items resolved
- **e2e bench** (Phase G): every suite green, or every red attributed to a defect outside the plugin

Then:
1. Ask the Config Migrator to delete the remaining `*_context.xml` files, then the Verifier to run the final sweep and remove `.migration/`
2. Present the migration summary to the user:
   - `verify-migration.sh` results (PASS/FAIL/WARN counts)
   - Compile result (`mvn clean install -Dmaven.test.skip=true`)
   - Test result (`mvn clean lutece:exploded antrun:run -Dlutece-test-hsql test`): tests run, failures, errors, skipped from `target/surefire-reports/*.txt`
   - Reviewer agent verdict (PASS/FAIL/WARN counts)
   - e2e bench: suite counts and what each remaining red is attributed to
   - List of files modified
3. **Run the gate, do not hand-check.** `bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/final-gate.sh .` re-measures the checks, the unit tests read from surefire and the e2e bench, and refuses the migration while any of them is red. Run it after **every** batch of fixes, not once at the end: a fix to a portlet invalidates the tests that asserted on its old rendering, and a fix to a defect turns the scenario pinning it red. Drop `.migration/gate-required` in the project at the start of the migration and the plugin's Stop hook will not let a turn end while the gate is red.
4. **List the files the migration created and that git does not track yet** (`git status --porcelain | grep '^??'`), and tell the user to stage them with `git add -A`, never `git commit -a`. `beans.xml` and the test `microprofile-config.properties` are new files: `commit -a` silently leaves them out, and the plugin then fails at the next clone with `UnsatisfiedResolutionException` in the Home static initializer. `ST05` fails while they are untracked.
5. Clean up the team
6. **STOP.** Do NOT commit. The user decides when and how to commit.

---

## Strict Rules

1. **Lead orchestrates only**: after Phase B the Lead never modifies files
2. **No builds before completion**: The project WILL NOT compile during migration. Only the Verifier builds.
3. **NEVER commit**: The skill must NEVER create git commits. Leave that to the user.
4. **Reference-First Rule**: `using-lutecepowers`, Mandatory reads — ALL teammates search `~/.lutece-references/` before writing new patterns
5. **File ownership**: Each file is owned by exactly one teammate. No two teammates touch the same file.
6. **Script-first**: Teammates run mechanical scripts FIRST, then apply intelligence to remaining issues
7. **Verify per-file**: Teammates run `verify-file.sh` after each file, not just at the end

## Manual review hotspots

The scan reports counts only — these patterns require human judgment, no mechanical sed:

- **JPA entities** (`persistence.hasJpa`) — `equals`/`hashCode` including a collection attribute, and a new object attached to a relation without `cascade = PERSIST` (inverse side included) before a flush: both pass with Hibernate and fail at runtime with EclipseLink (`persistence-patterns.md` §6). Only the e2e campaign on a fresh bench proves them.

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
| `migrate-template-mechanical.sh` | BO macros + null-safety (`--no-webxml` for the Template Migrator) | Template Migrator |
| `ensure-exploded.sh` | Assembles the project's webapp (`mvn lutece:exploded`): the precondition of every template analysis, and the source of the macro signatures, the icon font and the dependency templates | Template Migrator |
| `scan-template-design.py` | Design rules a macro-written template still breaks, per file with a kind (list, form, fragment, email, fo, sql); codes in its header; `--json`, `--flat`, `--warn-only` | Template Migrator, Verifier (TM08) |
| `check-template-parse.sh` | Parses every template with FreeMarker itself (a template that does not parse answers 500); project or single file | Template Migrator, Verifier (TM09), `verify-file.sh` |
| `check-i18n-keys.sh` | Every `#i18n` key of the project against the bundles the assembled webapp really carries, templates and Java alike; a key no bundle answers renders as an empty string, so the label is absent with nothing in the log. Separates the keys built from a variable and those owned by a plugin that is not here; assembles the project itself and stops with exit 2 when it cannot, because without the dependency bundles every key they own would be reported missing | Template Migrator, v8 Reviewer |
| `render-template.sh` | Renders templates offline with the real core macros and a lenient model (optional JSON model per template); counts the wrong-argument warning comments the core macros emit, resolves the `#i18n` keys against the assembled bundles and names those that answer nothing | Template Migrator |
| `extract-context-beans.sh` | Spring context XML → JSON catalog | Config Migrator |
| `verify-migration.sh` | every check of `verification/checks.md`, optional --json mode | Verifier |
| `verify-file.sh` | Per-file verification subset | All teammates |
| `final-gate.sh` | Postcondition: checks + compiler warnings + surefire + e2e, refuses a red migration (`--help`, `--no-e2e`) | Lead (Phase G, after every fix) |
| `add-liquibase-headers.sh` | Liquibase headers on SQL files | Config Migrator |
| `restore-line-endings.sh` | Restores the endings HEAD had on files the editor converted (check LE01) | Verifier |
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
| `fileupload-patterns.md` | FileItem→MultipartItem, jQuery upload widget → asynchronousupload | Java Migrators (if fileupload), Template Migrator (if upload_widget) |
| `json-patterns.md` | json-lib→Jackson | Java Migrators (if net.sf.json) |
| `deprecation-fixes.md` | What each deprecated API is replaced by (RBAC/workgroup `User` overloads, `getModel()`, `Strings.CS`, `getInstance()`, reflection, task signatures) | Java Migrators (always, short) |
| `core-8x-moves.md` | Core APIs that moved or shrank (XSL to plugin-xmltransformer, ContentService without cache, Parser in library-core-utils), reflection-instantiated classes | Java Migrators + Config Migrator (always, short) |
| `sql-liquibase.md` | Header, one small changeset per concern, precondition on tables another plugin owns, `runAfter`, AUTO_INCREMENT on a table shipped with an id 0, why the upgrade path is proven on a taken-over database | Config Migrator, Verifier |
| `persistence-patterns.md` | JPA kept on EclipseLink (`persistence-3.1`), JPQL/native SQL rules, entity rules, Spring JDBC as library | Java Migrators + Config Migrator (if `persistence.hasJpa` or `hasSpringJdbc`) |
