# Bench — proving a migration, and running against a deployed instance

Read for `run.sh compare` (the v7 leg, the upgrade path) and `run.sh external`. An artefact written for v8 never runs compare.

## Contents
- Before / after — the artefact in v7, then in v8 on the same database
- Before / after — my working tree against HEAD
- An instance already deployed
- compare invalidates the visual review

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

**A migration is proven on data.** The v7 base must hold what a site in production holds: the artefact's business
rows, written in the v7 schema, in `harness/db/seed-<name>-data.sql` with fixed ids and `INSERT IGNORE` (a fresh v8
bench gets them from the seed; on compare the v7 leg creates them, the v8 site migrates them, and the seed replayed
after the takeover leaves them as they are). Scenarios then start from those ids: the migrated record opens,
reads back with its children, still accepts the everyday actions. Phase 2 counts the rows the seed adds to the
artefact's own tables (those its `plugin/create*.sql` creates) and warns when there are none: the migration is then
proven on the schema only. Two v7 traps to know when writing that seed: `ant all` runs the plugins in alphabetical
order (the entrypoint replays the init scripts once every table exists), and a file row needs its `origin` (a v7
core ≥ 7.0.7 refuses a file whose origin is NULL, and its upgrade backfills none).

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
from the v7 site or not compiling there (never import a servlet class in it), the bench's configuration not reaching
the v7 site (a literal of a Spring context, `reference/external-systems.md`), the stand-ins not started on that leg, and a scenario written
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
dots — `SqlPathInfo`), or no `-- liquibase formatted sql` first line. `compare` applies such upgrade scripts by
hand before the v8 start and prints `HAND-APPLIED` for each: the bench shows the plugin on a migrated base, and
the file is reported to the artefact that ships it.

**The site around the artefact replays its own upgrades too.** The v8 site takes over a v7 database, so every
plugin assembled with it runs its v7→v8 scripts — including the ones the bench added for its own comfort. One
statement without a precondition on a table an earlier step dropped stops the whole start, and the failure is
not the artefact's. A bench keeps `E2E_PLUGINS` to what the artefact really needs, and reads
`artifacts/logs/unhealthy-*.log` for the changeset that stopped.

**The v7 side is not neutral either.** A v7 plugin's `init_core` may target tables a later 7.x core dropped
(a portlet plugin writes its XSL style into `core_style*`, removed in core 7.1.9): pick `E2E_V7_CORE` where
the plugin as shipped actually runs, and read `artifacts/v7/logs7/ant-dbinit.log` — the Ant build continues on
SQL errors.

## Before / after — my working tree against HEAD

`compare` answers "does the v8 artefact behave like the v7 one". A different question comes up as soon as you
change a shared file: **did my change break a screen that worked?** The bench answers it too, with two runs and
no guesswork.

```bash
git worktree add --detach <scratch>/before HEAD      # the state before, as a second checkout
bash <skill>/scripts/init-e2e.sh <scratch>/before --target core --name <name>-avant
sed -i 's/^E2E_PORT=.*/E2E_PORT=22180/;s/^E2E_DB_PORT=.*/E2E_DB_PORT=17406/;s/^E2E_MAIL_PORT=.*/E2E_MAIL_PORT=22125/' <scratch>/before/e2e/e2e.conf
cd <scratch>/before/e2e && ./run.sh build && ./run.sh up && ./run.sh inventory && ./run.sh discover && ./run.sh test
```

Then compare the two `artifacts/junit-*.xml`, **on the tests present in both runs only**: a crawl follows the
links the pages render, so a fix that restores a link adds screens and the two runs do not cover the same set.
Counting "51 failures before, 53 after" out of different totals says nothing.

```python
import xml.etree.ElementTree as ET, glob, os
def load(d):
    return {tc.get("name"): any(c.tag in ("failure","error") for c in tc)
            for f in glob.glob(os.path.join(d,"junit-*.xml"))
            for tc in ET.parse(f).getroot().iter("testcase")}
a, b = load("<before>/e2e/artifacts"), load("<after>/e2e/artifacts")
common = set(a) & set(b)
print("régressions:", sorted(n for n in common if not a[n] and b[n]))
print("corrigés   :", sorted(n for n in common if a[n] and not b[n]))
```

An empty regression list on a few hundred common tests is the only statement worth making about a change to a
shared macro or a shared script. Remember that `run.sh build` on the second bench installs **that** version in
`~/.m2` too: restore the published build when both runs are done (see the skill's prerequisites).

## An instance already deployed

`./e2e/run.sh external` runs the suites against a site that runs elsewhere — a recette, a preprod — from
`E2E_BASE_URL`, with `E2E_DB_*` when the sql oracles may reach its database. No build, no stack, no seed, and
the forms fuzzer stays off: it posts every form it finds. The scenarios still create their `{{rand}}` rows
there, so run it on an instance meant to receive them. The inventory still comes from the sources, so the
coverage is measured the same way.

## compare invalidates the visual review

`run.sh compare` rewrites `artifacts/` with its two legs: the captures of the previous normal run are gone and
`review-todo.md` no longer lists them. Run `compare` first, then the normal run whose captures the review judges.
A v7-leg failure caused by the v7 bench itself (a table the old dependency lacks, an SQL error of the v7 stack) is not
a v8 fix: read `compare.md`'s "corrigé" lines against the v7 log before claiming one.
