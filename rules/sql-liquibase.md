---
description: "Lutece 8 SQL: every plugin .sql (create_db, init_db, init_core, upgrade) MUST carry the Liquibase formatted-sql header, otherwise the schema silently fails to deploy in v8"
paths:
  - "**/sql/**/*.sql"
---

# SQL & Liquibase — Lutece 8

## The Golden Rule

In Lutece 8 the database is deployed by **plugin-liquibase**, which scans the classpath (`includeAll path="sql"`) and runs each plugin `.sql` as a **Liquibase formatted-SQL changeset**. A `.sql` file **without the Liquibase header is "not managed by liquibase"** and is silently skipped — and a single skipped/unparseable file aborts the whole plugin's migration.

**Every `.sql` file under `src/sql/plugins/<plugin>/` (create_db, init_db, init_core, AND every upgrade script) MUST start with this 3-line header:**

```sql
-- liquibase formatted sql
-- changeset <plugin>:<exact-file-name>.sql
-- preconditions onFail:MARK_RAN onError:WARN
```

Example (`update_db_myplugin-1.0.0-2.0.0.sql`):

```sql
-- liquibase formatted sql
-- changeset myplugin:update_db_myplugin-1.0.0-2.0.0.sql
-- preconditions onFail:MARK_RAN onError:WARN
CREATE TABLE IF NOT EXISTS my_table_hold ( ... );
ALTER TABLE my_table ADD CONSTRAINT chk_... CHECK ( ... );
```

## Rules

- **`changeset` author = plugin name** (the `<name>` of `webapp/WEB-INF/plugins/<plugin>.xml`, which is the artifactId without its `plugin-`/`module-`/`library-` prefix, e.g. `forms`, `workflow-forms`; never the parent artifactId) ; **id = the exact file name** (with `.sql`). `add-liquibase-headers.sh` derives it that way. Together with the file **path**, they form the identity Liquibase tracks in `DATABASECHANGELOG` — the triple `(ID, AUTHOR, FILENAME)`.
- **Never change the author, the id or the path of an already-shipped changeset** — they are the identity Liquibase tracks, and changing any of them replays it. One consequence: after a plugin rename, the changesets keep an author bearing the **former** plugin name — see `sql-rename.md`.
- **Editing the content of an already-shipped changeset is fatal as soon as the file is still part of the changelog for that run.** Being *included* is enough to be *validated*: Liquibase finds the row by its triple, compares `MD5SUM`, and raises `ValidationFailedException` before executing anything — the changeset is not replayed, it is refused. `TestIncludeAllFilter` excludes `create_*` / `init_*` files only once `core.plugins.status.<plugin>.version` is recorded, so on a plugin whose metadata is consistent the edit is invisible and reaches new installs only. That is the house practice and it holds — until a site has no version key: `No plugin metadata for <x>`, a datastore restored without those rows, or the first startup after a rename, where the key is written at the *end* of the run while the creation script is still included.
- The header is **mandatory on NEW files too** — when you add an upgrade script or edit `create_db`, match the header already present on the sibling files.
- Editing **inside** an existing changeset file needs **no new header** — it stays one changeset, which is exactly the trap above. To change what a creation script produces, **append a new changeset** to the same file: a checksum is computed per changeset, not per file, so the existing one keeps its identity and its fingerprint. Adding a **new file** always needs its own header.
- `IF NOT EXISTS` / idempotent DDL is good practice (re-run safety), but does **not** replace the header.
- **The third header line protects nothing on its own.** `-- preconditions onFail:MARK_RAN onError:WARN` declares *how* to react to a precondition, not a precondition. Without an actual check below it, the changeset runs unconditionally. To make a script genuinely re-run safe, add a real one:

  ```sql
  -- preconditions onFail:MARK_RAN onError:WARN
  -- precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=database() AND table_name='my_table' AND column_name='my_column'
  ALTER TABLE my_table ADD COLUMN my_column SMALLINT;
  ```

  Keep the policy line everywhere for consistency, but do not read it as a safety net — most scripts of the estate carry it with no condition attached, which is why replaying a non-idempotent `init_*` breaks the startup instead of being marked as ran.
- Don't declare `ON DELETE CASCADE` to clean child tables — the house convention is a **restrictive FK + explicit `deleteByIdForm`/`deleteByIdSlot`** chained in the service.
- **A changeset id is never reused.** A changeset already played elsewhere is repaired by a `-pre` changeset inserted before it, guarded by a `DATABASECHANGELOG` precondition, and left untouched itself:

  ```sql
  -- changeset myplugin:update_db_myplugin-1.0.0-2.0.0-rev5-pre.sql
  -- preconditions onFail:MARK_RAN onError:WARN
  -- precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM DATABASECHANGELOG WHERE ID = 'update_db_myplugin-1.0.0-2.0.0-rev5.sql'
  DELETE FROM my_table WHERE my_key = 'my.new.key';
  ```

  Reference: `lutece-core/src/sql/upgrade/update_db_lutece_core-8.0.1-8.0.2.sql` (`-rev5-pre`, `-rev7-pre`).
- **A released `update_*` script is never edited: roll forward.** A site that already played it is not repaired by a new body, so the fix goes in a new changeset of the next upgrade script, an `UPDATE` when the data can be corrected in place rather than a delete and re-insert (it keeps the rows that reference it). Edit a released upgrade only when its damage cannot be undone afterwards (a customised value it overwrites), and say so in the changeset comment; the sites that already played it are then out of reach, so add the recovery changeset too whenever one is possible.
- **A plugin never reuses a core id** (an admin right `CORE_*`, a datastore key the core owns): the core's upgrade scripts run after the plugin's (`sql/plugins` sorts before `sql/upgrade`, and `runAfter:core` is refused), so a core script that removes its own row removes the plugin's for good. Give it the plugin prefix, and rename the rows of existing sites with an `UPDATE` changeset (it keeps the users who hold the right).
- **`create_*` / `init_*` scripts describe a fresh install** and may be edited: plugin-liquibase includes them only on an empty database or for a new plugin, never on a site that already has the component.
- **No `-- validCheckSum:` outside `prerun_db_*`.** plugin-liquibase filters the files by version before Liquibase sees them: an `init_*` or an `update_*` older than the installed version is not in the changelog, so its checksum is never compared and the directive does nothing, except hiding a changed body from the one case that does replay it (an unstable or snapshot version equal to the installed one, `liquibase.accept.*.versions=true`). Only the `prerun_db_*` files run at every start, unfiltered: there a changed body needs it.

## One small changeset per concern

Liquibase runs a changeset as one unit and records it only when every statement passed. On MyISAM tables nothing is
rolled back: a statement that fails leaves the ones before it applied and the ones after it never run, and the next
start fails again at the same place. A long changeset that stops midway leaves a site that neither the old nor the
new version can read.

Split an upgrade by concern, and put the fragile part last, guarded:

```sql
-- changeset myplugin:update_db_myplugin-1.0.0-2.0.0.sql
-- preconditions onFail:MARK_RAN onError:WARN
ALTER TABLE ...;

-- changeset myplugin:update_db_myplugin-1.0.0-2.0.0-rev1.sql
-- preconditions onFail:MARK_RAN onError:WARN
-- precondition-sql-check expectedResult:3 SELECT COUNT(1) from INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA=database() AND TABLE_NAME IN ('core_style_mode_stylesheet','core_stylesheet','core_style');
DELETE FROM core_style_mode_stylesheet WHERE id_style = 200;
```

`expectedResult` is the number of tables the statements need. When the count differs the changeset is marked as ran
and the update goes on. Check `XT03`.

## Tables another plugin owns

`core_style`, `core_stylesheet` and `core_style_mode_stylesheet` belong to plugin-xmltransformer, not to the core. A
plugin that writes to them:

- **ports its portlet to HTML and removes those statements** when it can
  (`skills/lutece-migration-v8-agent-teams/patterns/mvc-patterns.md` §10). Check `XT01`.
- **otherwise declares plugin-xmltransformer** in its pom, and puts `-- lutece runAfter:xmltransformer` as the second
  line of every install script that writes to those tables, so they exist when the script runs. Check `XT02`. The
  same header serves any dependency on another plugin's tables (`runAfter:genericattributes` for entry types).

In both cases the upgrade scripts that touch those tables get the guarded changeset above: they run on every site
that migrates, including the ones where the tables do not exist.

## Adding AUTO_INCREMENT to an existing column

MariaDB and MySQL renumber a 0 into the next value when a column becomes AUTO_INCREMENT. A reference row shipped with
id 0 then collides with id 1:

    ALTER TABLE causes auto_increment resequencing, resulting in duplicate entry '1' for key 'PRIMARY'

The ALTER goes in a changeset restricted to those engines, after the mode that keeps 0 as a value:

```sql
-- changeset myplugin:update_db_myplugin-1.0.0-2.0.0-mariaDB-mySQL.sql dbms:mariadb,mysql
SET SESSION sql_mode='NO_AUTO_VALUE_ON_ZERO';
ALTER TABLE my_table MODIFY COLUMN id_my_table int AUTO_INCREMENT;
```

PostgreSQL gets its own changeset (`dbms:postgresql`) with `GENERATED BY DEFAULT AS IDENTITY` and a `setval` on the
sequence. Check `SQ03`.

## The file name is parsed — digits only in the versions

`SqlPathInfo` (library-sql-utils) recognises an upgrade script by a regular expression whose two versions are
`[0-9]+(\.[0-9]+)*`: `sql/plugins/<plugin>/upgrade/update_db_<plugin>-<from>-<to>.sql`, `sql/upgrade/update_db_lutece_core-<from>-<to>.sql`.
The directory is part of the match: an upgrade script under `plugins/<plugin>/plugin/` is dropped as well, that
directory is for the install scripts (`create_db_`, `init_db_`). Check `SQ06`.
A name that does not match parses to `null` and the file is **dropped silently, twice**: the lutece-maven-plugin
does not copy it to `WEB-INF/classes/sql/` at assembly, and `plugin-liquibase` would not include it at startup.
No log line names it — the include log only lists files the parser understood.

Rules that follow:
- **versions in a script name are digits and dots only** — no `x`, no `SNAPSHOT`, no `beta`;
- a migration that changes a schema ships `update_db_<plugin>-<v7 version>-<v8 version>.sql` with a real
  version on both sides; only the destination is compared to the installed version, the source documents;
- a major switch is named `<prev>.9.9-<new>`, as the core's `update_db_lutece_core-7.9.9-8.0.0.sql`;
- after `lutece:site-assembly`, compare `src/sql` with `WEB-INF/classes/sql`: a file missing there is a file
  Liquibase will never see. `run.sh compare` (lutece-e2e) prints that difference.

## The failure mode is the whole webapp

`db/changelog.xml` holds a single `<includeAll>` for the entire webapp, so every plugin is deployed by one `update()` call: one refused changeset fails all of them. `LiquibaseRunnerContext.setComponentVersion` only appends to an in-memory list, and `LiquibaseRunnerContext.close()` — which writes every `core.plugins.status.<plugin>.version` through `DatastoreService.setDataValue` — is reached only after a successful `update()`. A failed startup therefore records no version key at all, `LiquibaseRunner` rethrows a `RuntimeException` and `isCriticalService()` returns `true`: **Lutece does not start**, and this is not scoped to the guilty plugin.

The next startup reads the same inputs and fails identically. It cannot heal itself, since the mechanism that would have recorded the version is the one that failed. Unblocking means fixing `MD5SUM` by hand or running `clearCheckSums` — on every site.

## Changing what a creation script produces

Append a changeset instead of editing the shipped one:

```sql
-- changeset <plugin>:create_db_<plugin>-rev1.sql
-- preconditions onFail:MARK_RAN onError:WARN
-- precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = database() AND table_name = 'my_table' AND column_name = 'my_column'
ALTER TABLE my_table ADD COLUMN my_column VARCHAR(350);
```

- id = the file name carrying a `-rev<n>` suffix, the convention already in use in the estate.
- **no `logicalFilePath`**, even in a renamed directory: a new changeset has no row to match and must register under its real path.
- author = the **current** plugin name, while the changesets around it keep the former one.
- a **real** precondition, scoped on the current schema through `database()`. On a server hosting several Lutece schemas, an unscoped `information_schema` count sees a sibling schema and would make a fresh install skip the `ALTER`.

It holds in the three branches of the filter: executed on an empty database, `MARK_RAN` on a site that already got the column from an `update_*` script, no effect on a second pass.

`-- validCheckSum: ANY` also silences a mismatch — on its own line, the attribute is ignored on the `changeset` line. But Liquibase does **not** rewrite the stored `MD5SUM`, so the directive can never be removed afterwards, and it disables the integrity check on scripts that usually begin with `DROP TABLE IF EXISTS`. Permanent debt, on the least forgiving file of the plugin.

## What the creation script gains, existing sites never get

A fresh bench runs `create_db_*.sql` and is green. An existing site runs only the `update_db_*` scripts newer
than its recorded version. So every column or table added to `create_db` during the migration needs its own
`update_db_<plugin>-<v7 version>-<v8 version>.sql` (digits and dots only in the versions), with a **real**
precondition scoped on the current schema:

```sql
-- liquibase formatted sql
-- changeset <plugin>:update_db_<plugin>-1.0.12-2.0.0.sql
-- preconditions onFail:MARK_RAN onError:WARN
-- precondition-sql-check expectedResult:0 SELECT COUNT(1) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=database() AND TABLE_NAME='my_table' AND COLUMN_NAME='my_column';
ALTER TABLE my_table ADD COLUMN my_column varchar(255) default '';
```

Do not trust an older upgrade that (re)creates the table: it created it as it was then, without the column
(an older upgrade recreates a history table as it was then, the v8 DAO writes a new column into it, every v7
base answers `Unknown column`). `verify-migration.sh` SQ02 diffs the
creation scripts against the last commit and fails on an addition no upgrade script covers; `run.sh compare`
of the e2e skill proves it on a real v7 base: the v7 site on a fresh database, then the v8 site taking it over. A
plugin proven only on a fresh database has not been proven where every deployment runs it.

The symptom hides: `DAOUtil.free` throws `NullPointerException` (`results` is null) inside the error path of
`executeUpdate`, so the visible stack is a NPE in `DAOUtil.free`, not the `SQLException`. Read the log for
`Unknown column` / `doesn't exist` a few lines above.

## Why it bites only in v8

v7 installs SQL via the Ant `build.xml` (runs every plugin `.sql` regardless of header), so a missing header **works in v7 and on a fresh v7 base**. v8 (Liberty/cluster, `LIQUIBASE_ENABLED_AT_STARTUP`) deploys **only** Liquibase-managed changesets → the same file silently fails to create its tables.

## Common Error

| Symptom | Cause | Fix |
|---|---|---|
| Plugin tables missing after v8 startup, **no exception** in app log | A plugin `.sql` lacks the `-- liquibase formatted sql` header | Add the 3-line header to that file |
| Log: `LiquibaseRunner files not managed by liquibase are sql/plugins/<x>/...` | That exact file has no/invalid header | Add/fix the header |
| Works in v7 fresh install, not in v8 cluster | Relying on the Ant build instead of Liquibase changesets | Header every `.sql` |
| Creation script replayed on an existing site, `Duplicate entry` or `DROP TABLE` | A SQL directory was renamed, changing the changeset identity | `logicalFilePath` on the changeset line — see `sql-rename.md` |
| `ValidationFailedException`, `1 changesets check sum`, **and the webapp does not start** | The content of an already-shipped changeset was edited, and the file is still included — no `core.plugins.status.<plugin>.version` | Append a new changeset instead of editing. Sites already broken need `MD5SUM` fixed or `clearCheckSums` |

## How to verify

Every `.sql` under `src/sql` must have `-- liquibase formatted sql` as its first non-empty line:

```bash
for f in $(find src/sql -name '*.sql'); do head -1 "$f" | grep -q 'liquibase formatted sql' || echo "MISSING HEADER: $f"; done
```
