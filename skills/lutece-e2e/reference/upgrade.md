# Bench — proving the database upgrade (`lpe2e upgrade`)

A migration proven on a fresh database has never proven its **schema upgrade**: a migration that changes a table and
ships no `update_db_<plugin>-<v7>-<v8>.sql` is green on every fresh-install bench and breaks every existing site.
`lpe2e upgrade` plays the upgrade the way the environments will: the previous version's database, brought under
Liquibase as they will bring it, taken over by the bench site, then the suites on that database.

```
lpe2e upgrade
```

## Contents
- What it plays
- What it reports
- Configuration
- A migration is proven on data
- Traps

## What it plays

1. **The previous version's database**, on the bench's database of the shared MariaDB, one of:
   - **v7** (a plugin with `E2E_V7_REF`, a site with `E2E_V7_WAR`): `tools/gen-site7.sh` assembles the artefact
     before its migration on a Lutece 7 site — the git ref `E2E_V7_REF` in a disposable worktree, `lutece-site-pom`
     `E2E_V7_SITE_POM`, core `E2E_V7_CORE`, the extra artefacts of `E2E_V7_PLUGINS` at their v7 versions, the
     plugin-liquibase of the v7 line (`tools/latest-lutece.py snapshot --line 7`). The site is cached under
     `~/.lutecepowers-e2e/sites7/<key>` (the v7 sources, the `E2E_V7_*` settings, the bench files that shape it). Its
     Ant build creates the schema (`harness/tomcat/entrypoint.sh`), then the bench seed runs with `E2E_VERSION=v7`
     (`harness/db/seed-*.sql`, plus `seed7-*.sql` for rows only the v7 schema needs), and the portlet types a v7
     plugin installation registers (`tools/v7-portlet-types.py`).
   - **a recette dump** (`E2E_V7_DUMP`, `.sql` or `.sql.gz`): loaded instead; only the admin account gets the bench's
     password on that copy.
   - **the previous Lutece 8 version** (`E2E_BEFORE_WAR`, a war or an exploded site built the way the bench site is):
     started by the bench's Liberty on a fresh database, where its own Liquibase creates the schema, then seeded.
2. **One v7 start with plugin-liquibase** (v7 and dump without `DATABASECHANGELOG`): the v7 site in Tomcat 9 / Java 11
   (`lpe2e-<name>-app7`, port 8081 in the runner's network namespace), `liquibase.enabled.at.startup=true`. On a
   database Liquibase never followed it runs nothing: it creates `DATABASECHANGELOG` and records the version of every
   component whose SQL it sees. Stopped once Tomcat started. This is the documented way to bring a v7 site under
   Liquibase (`lutece-update-site`, `reference/database.md`).
3. **The bench site takes the database over.** By default one normal start, what a deployment does. With
   `E2E_TAKEOVER` (required for a site): the two passes of `reference/database.md` from the scripts
   `site_check.py takeover <v7 site> <v8 site> --out <dir>` wrote — `takeover-1-core.sql`, a start where only the core
   upgrades run, `takeover-2-components.sql`, then the normal start. Each pass is judged on its own console and on
   the Lutece logs it wrote: Liberty's output directory outlives the container, so every start empties its
   `logs/lutece/*.log` first (a stopped pass leaves its own under `artifacts/logs`). For a plugin, the two sites are
   `~/.lutecepowers-e2e/sites7/<key>/site` and `~/.lutecepowers-e2e/benches/<name>/site`.
   On a v7 database, the upgrade scripts Liquibase cannot see (`tools/liquibase-visibility.sh`: an unparseable name,
   no `-- liquibase formatted sql` first line) are applied by hand first and printed `HAND-APPLIED`: a site would have
   to do the same, and the file is a finding for the component that ships it.
4. **The suites** on the taken-over database, seeded again (`INSERT IGNORE` rows stay as migrated), as a normal run:
   discover, every suite, perf, report.

## What it reports

Under `artifacts/`, each printed as one line, and summed up in a section of `summary.md`. The files of a previous
upgrade are removed when a run starts:

| File | What |
|---|---|
| `liquibase-changesets.txt` | every changeset the takeover ran (`EXECTYPE FILENAME ID`) |
| `liquibase-versions-after.txt` | the component versions recorded after it |
| `datastore-v7.txt`, `datastore-v8.txt` | the settings of the site (advanced parameters, site properties, cache statuses, theme) before and after the takeover (`datastore-before.txt` for a v8 update) |
| `datastore-lost.txt` | the settings the takeover overwrote or removed: a key gone, a value no upgrade script explains; set them again after the upgrade |
| `datastore-defaults.txt` | the defaults the new version changes on purpose, for information: a value an upgrade script replaces (`UPDATE core_datastore SET entity_value = <new> WHERE entity_key = … AND entity_value = <old>`), or the previous install value turned into the new install value |
| `upgrade-disabled.txt` | plugins of the bench site the database leaves disabled (a renamed one that `plugins.dat` lists under its former name is one) |
| `upgrade-orphans.txt` | status keys of names no descriptor declares any more (the keys of a renamed plugin nobody moved) |
| `components-without-version.txt` | components the v7 site ships that the v7 start recorded no version for: the takeover installs them as new over their existing rows |
| `v7-liquibase-unmanaged.txt` | SQL files of the v7 site plugin-liquibase does not manage (no Liquibase header) |
| `liquibase-failure.txt` | the changeset and the reason when Liquibase stopped |
| `logs/v7-liquibase-start.log`, `logs7/ant-dbinit.log` | the v7 start and the Ant install |
| `logs/upgrade.json` | the facts above, read by `tools/report.py` for `summary.md` |

Exit code: **11** when the database upgrade failed, in the v7 preparation or in the takeover (the v7 start refused
or failed, a Liquibase changeset stopped, the bench site did not start on the database: the changeset and its reason
are printed); `summary.md` then says so and nothing else, and `artifacts/logs/upgrade.json` holds the same facts; otherwise the code of the suites, as
`lpe2e`. A green run stamps `artifacts/pass-upgrade`, which `tools/final-gate.sh` reuses. The bench is left as the
run found it: up when it ran before (a `KEEP=1 lpe2e`) or with `KEEP=1`, down otherwise.

## Configuration

In `e2e.conf`: `E2E_V7_REF`, `E2E_V7_SITE_POM`, `E2E_V7_CORE`, `E2E_V7_PLUGINS`, `E2E_V7_DEP_PINS` (a v7 range whose
top no longer compiles, pinned in the worktree), `E2E_V7_WAR` (a site's v7 war, `tools/site-assemble.sh` without
`--profile`: no value of a real environment enters the bench; it must carry plugin-liquibase of the v7 line, as the
environments will), `E2E_V7_DUMP`, `E2E_BEFORE_WAR`, `E2E_TAKEOVER` (a site), `E2E_V7_SAFE_RUN` (below). The bench's
property overrides (`harness/site/webapp/WEB-INF/conf/override`) and probe pages (`harness/site/webapp/jsp/e2e`) are
copied to the v7 site; `harness/src7-overlay/` is laid over the v7 worktree before its build, `harness/v7-overlay/`
over the assembled v7 site.

## A migration is proven on data

The v7 base must hold what a site in production holds: the artefact's business rows, written in the v7 schema, in
`harness/db/seed-<name>-data.sql` with fixed ids and `INSERT IGNORE` (a fresh v8 bench gets them from the seed; on
`upgrade` the v7 install creates them, the takeover migrates them, the seed replayed after leaves them as they are).
Scenarios then start from those ids: the migrated record opens, reads back with its children, still accepts the
everyday actions. Two v7 traps for that seed: `ant all` runs the plugins in alphabetical order (the entrypoint replays
the init scripts once every table exists), and a file row needs its `origin` (a v7 core ≥ 7.0.7 refuses a file whose
origin is NULL, and its upgrade backfills none).

**A witness proves the takeover kept the v7 data.** The same scenarios run on a fresh bench and on `upgrade`, so
the rows of `seed-*.sql` cannot tell the two apart. The witness is one row only the v7 database holds: a
`harness/db/seed7-<name>.sql` (replayed on the v7 install only, never after the takeover) with a fixed value. A
scenario asserts it with the `v7_witness` step:

```yaml
- v7_witness: "SELECT COUNT(*) FROM core_datastore WHERE entity_key='myplugin.e2e.v7.witness' AND entity_value='site v7 myplugin 1.2.5'"
- sql: {query: "SELECT title FROM myplugin_item WHERE id_item=1", expect_var: ...}   # {{v7}} is now 1 or 0
```

The count must be exactly 1 when the database was born in v7 and exactly 0 on a fresh install. Whether it was born
in v7 is read apart from the witness, from the core changeset `sql/upgrade/update_db_lutece_core-7.9.9-8.0.0.sql`
in `DATABASECHANGELOG`, and `lpe2e upgrade` from v7 requires that changeset. The query compares to a value written in
it. A witness built otherwise passes even when the takeover erased the data: two counts expected at 0, the witness
read back as its own reference, a value the scenario reads before comparing. After the step, `{{v7}}` (1 or 0)
selects the expected values of the migrated rows (`sql_set` with `IF({{v7}}=1, ..., ...)`).

## Traps

- **plugin-liquibase of the v7 line refuses a site with an SQL file it cannot manage** (`liquibase.safeRun=true`, the
  default): the v7 start stops on `LiquibaseRunner not ready to run`, the run ends with rc=11 and names the files. An
  environment meets the same refusal. Fix the file in its component, or set `E2E_V7_SAFE_RUN=false` with the reason
  in a comment, as an environment would start: the files are then reported, never silently skipped.
- **The v7 line of plugin-liquibase looks for `DATABASECHANGELOG` in every schema of the server**
  (`liquibase.first.run.request`; the v8 line looks in the connection's schema only). On a server holding another
  Lutece database already followed by Liquibase, it takes a never-followed database for a followed one and runs
  every create and init script on it. The bench confines the request to its schema; an environment sharing its
  MariaDB between sites sets the same property.
- **A component the v7 start recorded no version for is installed as new by the takeover**
  (`components-without-version.txt`): its create and init scripts run over its v7 rows, and a duplicate key stops the
  start. E.g. a plugin whose v7 SQL carries no Liquibase header: plugin-liquibase never sees it. The
  default run is then red, which is what a deployment would live; `E2E_TAKEOVER` with the scripts of
  `site_check.py takeover` (they set each component back to its v7 version) is the procedure that passes, and the
  scripts are handed over with the migration.
- **Every plugin of the bench site replays its own upgrades**, including the ones the bench added for its comfort. One
  statement without a precondition on a table an earlier step dropped stops the whole start, and the failure is not
  the artefact's. Keep `E2E_PLUGINS` to what the artefact needs, list the same plugins at their v7 versions in
  `E2E_V7_PLUGINS` (a plugin absent from the v7 site arrives as new on tables that may already exist), and read
  `liquibase-failure.txt`.
- **The v7 side is not neutral.** A v7 plugin's `init_core` may target tables a later 7.x core dropped (a portlet
  plugin writes its XSL style into `core_style*`, removed in core 7.1.9): pick `E2E_V7_CORE` where the plugin as
  shipped runs, and read `logs7/ant-dbinit.log` — the Ant build continues on SQL errors.
- **The v7 site builds against today's repositories.** A v7 pom with an open range resolves the newest matching
  artefact, which may not compile or may be built for Java 17 (`gen-site7.sh` names it): pin it in `E2E_V7_DEP_PINS`,
  never change the v7 sources to make them compile.
- **A site's takeover needs its two scripts.** Without them a database installed with Ant (an empty
  `DATABASECHANGELOG` for the components plugin-liquibase could not resolve) can lose tables, a creation script
  replaying its `DROP TABLE` (`rules/sql-rename.md`). To see the start without them, point `E2E_TAKEOVER` at a
  directory holding two empty files.
