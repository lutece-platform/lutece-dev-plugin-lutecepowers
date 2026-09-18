# Bench — proving a migration, and running against a deployed instance

Read for `run.sh compare` (the v7 leg, the upgrade path) and `run.sh external`. An artefact written for v8 never runs compare.

## Contents
- Before / after — the artefact in v7, then in v8 on the same database
- An instance already deployed

## Before / after — the artefact in v7, then in v8 on the same database

A migration proven on a fresh database has never proven its **schema upgrade**: a migration that changes a
table and ships no `update_db_<plugin>-<v7>-<v8>.sql` is green on every fresh-install bench and breaks every
existing site. `run.sh compare` closes that hole and, on the way, puts the two versions face to face.

```
./e2e/run.sh compare
```

1. `tools/gen-site7.sh` assembles the artefact **before** its migration on a Lutece 7 site: the git ref the
   clone still carries (`E2E_V7_REF`, `HEAD` while the migration is only staged) in a worktree, built with plain
   `mvn` (`E2E_MVN7` for a developer keeping separate v7 settings), `lutece-site-pom` `E2E_V7_SITE_POM`
   (7.0.8), core `E2E_V7_CORE` (7.1.9), extra artefacts at their v7 versions in `E2E_V7_PLUGINS`. The schema is
   created the v7 way — the Ant build shipped under `WEB-INF/sql` — at the container's first start
   (`harness/Dockerfile.tomcat`, Tomcat 9 / Java 11, `harness/tomcat/entrypoint.sh`).
2. v7 up on a fresh database, seed (`--no-deps`: the v8 container must stay down), inventory, discover, the
   suites with `E2E_VERSION=v7`, report — frozen under `artifacts/v7/`.
3. **The v8 site takes over the same database.** `plugin-liquibase` includes nothing on a base without
   `DATABASECHANGELOG`, so one start in migration mode (`LIQUIBASE_MIGRATION_MODE=true`) creates the table and
   records the *deployed* versions — which would skip every v7→v8 upgrade script. The recorded versions are then
   reset to the v7 ones (`harness/site7/target/versions.properties`) and the site starts normally: that is a
   site already followed by Liquibase in v7, the only path where Liquibase performs the upgrade itself.
   `artifacts/liquibase-changesets.txt` and `liquibase-versions-after.txt` say what ran.
4. Suites with `E2E_VERSION=v8`, report — `artifacts/v8/`. Then `tools/compare.py` pairs the two runs **by
   function, not by url**: a migration to MVC turns `ModifyMyEntity.jsp?id=1` into
   `ManageMyEntities.jsp?view=modifyMyEntity&id=1`, and the reader wants those two on one card, v7 left, v8
   right — not one "disparu" and one "nouveau". The function of a url is its `view`/`action` parameter when it
   has one, else the JSP name, without the Do/Get/Confirm prefixes; screens that differ only by their ids are
   variants of one function, folded under the representative. Verdict per function — régression, corrigé,
   rendu différent, nouveau, disparu, v8 seulement, inchangé — in `artifacts/compare.md` and `compare.html`
   (every function with its two screenshots, the unchanged ones included: the point is the human review).

**The same parcours on both legs.** A scenario is written once and plays on both versions; where the
migration changed a url or a selector, the step value is a per-version mapping:

```yaml
- goto: {v7: jsp/admin/plugins/myplugin/ModifyMyEntity.jsp?plugin_name=myplugin&id=1, v8: jsp/admin/plugins/myplugin/ManageMyEntities.jsp?view=modifyMyEntity&id=1}
- submit: {v7: 'form[action*="DoModifyMyEntity.jsp"]', v8: 'form[action*="ManageMyEntities.jsp"]'}
```

`versions: [v8]` remains for a function that did not exist before the migration; it is reported "v8
seulement", never as a regression fixed by v8. Do not use it to dodge a v7 url: a scenario skipped on the v7
leg proves nothing about the migration.

**Read a "corrigé" before believing it.** A green v8 against a red v7 means the migration fixed something *only
when the same parcours really ran on both sides*. Four things make a v7 leg fail for reasons that have nothing to
do with the artefact, and each one turns every affected function into a false "corrigé": the bench's probe missing
from the v7 site or not compiling there (never import a servlet class in it), the bench's properties not reaching
the v7 container (they do now, same `app.env`), the stand-ins not started on that leg, and a scenario written
against a v8 form that has no v7 equivalent (`versions: [v8]`, or per-version values). Before writing a
"corrigé" in a hand-over, open the v7 failure and check it is the plugin's, not the bench's.

**Name the form you submit.** `submit: 'form'` takes the first form of the page; in the Lutece 7 admin layout
that is the header's accessibility form (`DoModifyAccessibilityMode.jsp`), and the scenario silently posts
nothing while v8, whose layout has no such form, passes — a false "corrigé". Always `form[action*="ManageX.jsp"]`.

**Never edit a scenario while `compare` runs.** The two legs read the scenario files from disk one after the
other; a selector changed between them makes the v7 leg fail and the v8 leg pass, and the report prints a
"corrigé" that is only the edit. Stop the run, edit, start it again.

**Same sample on both sides.** The crawl keeps `MAX_PER_PATH` variants per *screen* — JSP path plus `view`
— not per JSP path, or the twenty views of one `ManageX.jsp` would share one quota that a v7 JSP-per-view gets
each, and the v8 leg would look poorer than the v7 one for no reason.

**What Liquibase will never see.** `tools/liquibase-visibility.sh` (run at every `build`) lists the SQL files
of the assembled site that are absent from `WEB-INF/classes/sql`: unparseable name (versions must be digits and
dots — `SqlPathInfo`), or no `-- liquibase formatted sql` first line. The core itself ships one:
`update_db_lutece_core-7.1.x-8.0.0.sql`, the whole 7 → 8 schema step, dropped at assembly because of the `x` —
a 7.1.x site upgraded under Liquibase gets no front office (`globalTheme is null`). `compare` applies such
scripts by hand before the v8 start and prints `HAND-APPLIED` for each: the bench shows the plugin on a
migrated base, the finding goes to the core.

**The site around the artefact replays its own upgrades too.** The v8 site takes over a v7 database, so every
plugin assembled with it runs its v7→v8 scripts — including the ones the bench added for its own comfort. One
unguarded `DELETE` in any of them stops the whole start (`plugin-mylutece`'s `update_db_core_mylutece-5.0.0-5.0.1.sql`
deletes rows from `core_style*`, which the core's 7→8 step has already dropped: `globalTheme is null`, empty
site). `compare` therefore runs **without** the bench's front-office authentication, except when the artefact
under test depends on mylutece itself or the bench names it in `E2E_PLUGINS`: there the module is the subject
or a fixture the scenarios sign in with, and it stays (`E2E_MYLUTECE_FORCE=1` keeps it for any other reason).
A bench keeps `E2E_PLUGINS` to what the artefact really needs.

**The v7 side is not neutral either.** A v7 plugin's `init_core` may target tables a later 7.x core dropped
(a portlet plugin writes its XSL style into `core_style*`, removed in core 7.1.9): pick `E2E_V7_CORE` where
the plugin as shipped actually runs, and read `artifacts/v7/logs7/ant-dbinit.log` — the Ant build continues on
SQL errors.

## An instance already deployed

`./e2e/run.sh external` runs the suites against a site that runs elsewhere — a recette, a preprod — from
`E2E_BASE_URL`, with `E2E_DB_*` when the sql oracles may reach its database. No build, no stack, no seed, and
the forms fuzzer stays off: it posts every form it finds. The scenarios still create their `{{rand}}` rows
there, so run it on an instance meant to receive them. The inventory still comes from the sources, so the
coverage is measured the same way.

