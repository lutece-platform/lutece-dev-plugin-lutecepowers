---
name: lutece-update-plugin
description: "Use when bringing a Lutece plugin, module or library to the Lutece level lutecepowers supports, whatever its starting point: migrating from v7 or older (Spring to CDI, javax to jakarta, XML context, templates, tests), or updating a v8 project to the current level (parent, deprecated API, checks, bench). The scripts report every checkable finding with what to do, one agent makes every change, a read-only reviewer and the e2e bench prove the result. Triggers when the user asks to migrate or update the whole plugin, module or library: 'migrate to v8', 'upgrade to Lutece 8', 'migration v7 v8', 'CDI migration', 'passer en v8', 'montée de version', 'mise à niveau v8', 'migrer le plugin', 'mettre à jour le plugin'."
metadata:
  summary: "Update a plugin, module or library to Lutece 8, from any version."
---

# Lutece update

One job whatever the starting point: bring the artefact to the supported Lutece level (`tools/v8-floor.conf`). The
scripts report everything checkable; you make every change, alone and in order. One command carries the toolkit:
`tools/lutece-check.sh` (every check, each finding with what to do; `--explain CODE` for one check). A rename a check
names across many files (javax → jakarta, an annotation) is one `sed` over `src/`, then the check again. An update is
sequential (the Java needs the pom, the JSP need the beans): do it yourself, never split it between parallel agents.
Two subagents only, one after the other: the reviewer (Phase E) and the e2e bench (Phase F).

## PHASE A — Scan: where the artefact starts

```bash
mkdir -p .migration
bash ${LUTECEPOWERS_ROOT}/hooks/setup-rules . >/dev/null
bash ${LUTECEPOWERS_ROOT}/tools/scan-project.sh . > .migration/scan.json
[ -s .gitignore ] && [ -n "$(tail -c1 .gitignore)" ] && echo >> .gitignore
for p in 'target/' 'logs/' 'java.io.tmpdir/' '.migration/' '*.log' 'e2e/'; do grep -qxF "$p" .gitignore 2>/dev/null || echo "$p" >> .gitignore; done
```

From here on the Lutece 8 rules apply, whatever the starting version: before editing a file, read the rule of
`${LUTECEPOWERS_ROOT}/rules/` that matches it (`.claude/rules/` holds them on Claude Code from the next session).

`project.type` `site` (packaging `lutece-site`: a site, a pack, a theme) is not updated here: follow the
`lutece-update-site` skill, which checks what the site ships and hands its plugins back to this one when they need an
update. For the other types, `summary.start` says the path: `pre-v8` (a parent before 8: the full update, a v7 database to take over) or `v8` (a
v8 parent: align it on the supported level, no database to take over). Show the user the type, artifact, version,
start, scope and persistence base (`summary.persistence`: JPA stays on the container's EclipseLink,
`patterns/persistence-patterns.md`).

**Dependencies (blocker).** For each Lutece dependency of the scan: `available` (in `~/.lutece-references/`) or
`published` is fine; clone a published one into `~/.lutece-references/` (`dependency-references` rule); `to-resolve`
means finding its repository and its v8 branch (`develop`, parent `8.x`). A dependency with no v8 version: **stop**
and tell the user.

## PHASE B — First check

```bash
bash ${LUTECEPOWERS_ROOT}/tools/lutece-check.sh .
```

It lists every finding by code: that list is the work of the steps.

## PHASE C — The steps

| Step | File (`steps/`) | Scope | Codes it answers |
|---|---|---|---|
| 1 | `1-config.md` | pom, beans.xml, descriptors, web.xml, Spring context files, SQL, properties | V8FLOOR, PM*, PV*, WB*, SP03, SQ*, PT*, XT*, I18N* |
| 2 | `2-java.md` | `src/java`: the Spring context to CDI, what the checks name, the designs a script cannot choose | JX*, SP*, DL*, EV*, CA*, DP*, DA*, JP*, CD*, MV*, ST*, HM*, XS*, CS*, TL*, LG*, GI*, PI*, RL*, PD*, WG*, JS04 |
| 3 | `3-templates.md` | JSP, admin and skin templates, JavaScript | TM*, TD*, JS*, VL* |
| 4 | `4-tests.md` | `src/test` | TS*, PM13 |

LE01 (a file whose line endings the work converted) belongs to no step: write files in any convention and run `tools/restore-line-endings.sh .` before each check, it puts every changed file back to the endings HEAD has in one pass; no conversion by hand.

- **`pre-v8`**: every step, in this order.
- **`v8`**: only the steps with a finding of `lutece-check.sh` in their scope, in this order; a step with none is
  skipped. A `V8FLOOR` refusal is step 1 (parent and core range).

Search `~/.lutece-references/` before writing any pattern (each clone carries its v7 branches). After each file,
`bash ${LUTECEPOWERS_ROOT}/tools/verify-file.sh --brief <file>` and fix what it reports; after each step,
`bash ${LUTECEPOWERS_ROOT}/tools/lutece-check.sh .`. A code you do not know: `lutece-check.sh --explain CODE`. Change
what the level requires, nothing else: no line-ending conversion, no reflow, no "modernising" what compiles.

## PHASE D — Build

```bash
bash ${LUTECEPOWERS_ROOT}/tools/final-gate.sh . --no-e2e
```

One build with the compiler warnings and the unit tests read from surefire (BUILD SUCCESS means nothing: the parent
sets `testFailureIgnore`), then the checks. `verify-migration.sh` stops with exit 2 when the project does not assemble:
read the Maven error it printed (a dependency that does not resolve, a half-updated pom). Five build-fix rounds on the
same error, then stop and show the user the full log (`/tmp/final-gate-<project>-build.log`). The frequent causes:

| Symptom | Fix |
|---|---|
| `cannot find symbol` on a Spring or `javax` type | the Java of step 2 |
| `final class cannot be proxied` | drop `final` on that class only; legal when the bean is resolved by its interface |
| `UnsatisfiedResolutionException` in a Home static initializer | `beans.xml` missing from the archive, or excluded by `.gitignore` (ST05) |
| `@Inject` field null in a test | the bean is not annotated in production code |
| `NullPointerException` in `getModel( )` | `@Inject Models` (`patterns/cdi-patterns.md` §16) |

## PHASE E — Reviewer

When `final-gate.sh . --no-e2e` is green, dispatch a read-only subagent: instructions
`${LUTECEPOWERS_ROOT}/agents/lutece-v8-reviewer.md`, "review this project for v8 compliance, modify nothing", with
`${LUTECEPOWERS_ROOT}` replaced by its literal path. It returns its report without writing a file: save it as
`.migration/report-reviewer.md`. Fix its FAIL items, run Phase D again, review again; fix its WARN items too.

## PHASE F — e2e bench

Unit tests cover almost none of a plugin; the defects that hurt are on screen. Dispatch one subagent: "invoke the
`lutece-e2e` skill on this project and follow it (it reuses an existing `e2e/`), fixing with `lpe2e watch` running;
fix in the plugin or in `e2e/` what the bench proves, and report each fix", with the literal
`${LUTECEPOWERS_ROOT}`. While it runs you edit nothing: the project has one writer at a time. Every red scenario is
attributed, to the plugin or to the core, with the evidence; a core defect the plugin must not work around (an
`@Action` run on GET without its token) keeps its scenario with `core_defect:` and goes into the hand-over, never into
a guard of the plugin. A fix the bench forced inside `e2e/` is a defect of `lutece-e2e`: report it.

## PHASE G — Gate loop

`touch .migration/gate-required` (the Stop hook then refuses to end a turn while the gate is red), then:

```bash
bash ${LUTECEPOWERS_ROOT}/tools/final-gate.sh .
```

It reuses a green bench run and upgrade (`lpe2e upgrade`, the v7 database taken over) of the same sources instead of
playing them again, and plays upgrade only when the bench knows a pre-v8 ancestor. The upgrade proves the v7 data
kept only through a witness asserted with the `v7_witness` step (lutece-e2e, `reference/upgrade.md`): a row of
`seed7-*.sql` with a value written in the query, exactly 1 when the core changeset 7.9.9-8.0.0 says the database was
born in v7, exactly 0 otherwise. Read what is red, fix it at the source (never an allowlist entry, a deleted
assertion or a scenario rewritten to expect the defect), run the gate again in full. A WARN does not block the gate,
and is fixed all the same: the gate lists each one; one stays only when its fix is impossible or outside the plugin (a
core defect, a choice of the user), with that reason in the hand-over. The only other way out of a red is a defect
attributed with evidence to something the plugin cannot fix (a core defect), carried into the hand-over. The same red
back a third time after three different fixes: stop and ask, the diagnosis is wrong.

When the gate passes: check no Spring context file remains under `webapp/`, then give the user the start, the gate
result, the reviewer verdict, the e2e counts with each red attributed, each WARN kept with its reason, the files
changed, and the files git does not track yet (`git status --porcelain | grep '^??'`), to stage with `git add -A`,
never `git commit -a` (a new `beans.xml` left out fails at the next clone). **Never commit.**

## Judgement a script cannot make

- **JPA entities**: an `equals`/`hashCode` over a collection, a new object attached to a relation without `cascade =
  PERSIST` before a flush: fine with Hibernate, broken with EclipseLink (`persistence-patterns.md` §6).
- **`ShutdownService`** implementations: a `@PreDestroy` method on the bean when `process()` does real cleanup; drop the
  interface when it does nothing. Case by case: `getName()` may be used elsewhere.

## Patterns (`patterns/`, load on demand)

| File | When |
|---|---|
| `cdi-patterns.md` | scopes, injection, producers, Models, Pager (Java, always) |
| `deprecation-fixes.md`, `core-8x-moves.md` | what replaces a deprecated or moved API |
| `mvc-patterns.md` | JspBean, XPage, portlet (HTML port §10, CSRF §11) |
| `events-patterns.md`, `cache-patterns.md`, `rest-patterns.md`, `json-patterns.md`, `fileupload-patterns.md`, `persistence-patterns.md` | when the scan flags them |
| `rules/sql-liquibase.md` (repository root) | SQL changesets and upgrade scripts |
