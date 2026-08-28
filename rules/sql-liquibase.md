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

Example (`update_db_appointment_3.0.8-4.0.0.sql`):

```sql
-- liquibase formatted sql
-- changeset appointment:update_db_appointment_3.0.8-4.0.0.sql
-- preconditions onFail:MARK_RAN onError:WARN
CREATE TABLE IF NOT EXISTS appointment_slot_hold ( ... );
ALTER TABLE appointment_slot ADD CONSTRAINT chk_... CHECK ( ... );
```

## Rules

- **`changeset` author = plugin name** ; **id = the exact file name** (with `.sql`). Together with the file **path**, they form the identity Liquibase tracks in `DATABASECHANGELOG` — the triple `(ID, AUTHOR, FILENAME)`.
- **Never change the author, the id or the content of an already-shipped changeset.** Changing the author or the path replays it; changing the content raises `ValidationFailedException` and aborts the whole startup migration. Any content fix goes into a **new** file. One consequence: after a plugin rename, the changesets keep an author bearing the **former** plugin name — see `sql-rename.md`.
- The header is **mandatory on NEW files too** — when you add an upgrade script or edit `create_db`, match the header already present on the sibling files.
- Editing **inside** an existing changeset file (e.g. adding a table/constraint to `create_db_*.sql`) needs **no new header** — it stays one changeset. Adding a **new file** always needs its own header.
- `IF NOT EXISTS` / idempotent DDL is good practice (re-run safety), but does **not** replace the header.
- **The third header line protects nothing on its own.** `-- preconditions onFail:MARK_RAN onError:WARN` declares *how* to react to a precondition, not a precondition. Without an actual check below it, the changeset runs unconditionally. To make a script genuinely re-run safe, add a real one:

  ```sql
  -- preconditions onFail:MARK_RAN onError:WARN
  -- precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=database() AND table_name='my_table' AND column_name='my_column'
  ALTER TABLE my_table ADD COLUMN my_column SMALLINT;
  ```

  Keep the policy line everywhere for consistency, but do not read it as a safety net — most scripts of the estate carry it with no condition attached, which is why replaying a non-idempotent `init_*` breaks the startup instead of being marked as ran.
- Don't declare `ON DELETE CASCADE` to clean child tables — the house convention is a **restrictive FK + explicit `deleteByIdForm`/`deleteByIdSlot`** chained in the service (see `FormService.removeForm`).

## Why it bites only in v8

v7 installs SQL via the Ant `build.xml` (runs every plugin `.sql` regardless of header), so a missing header **works in v7 and on a fresh v7 base**. v8 (Liberty/cluster, `LIQUIBASE_ENABLED_AT_STARTUP`) deploys **only** Liquibase-managed changesets → the same file silently fails to create its tables.

## Common Error

| Symptom | Cause | Fix |
|---|---|---|
| Plugin tables missing after v8 startup, **no exception** in app log | A plugin `.sql` lacks the `-- liquibase formatted sql` header | Add the 3-line header to that file |
| Log: `LiquibaseRunner files not managed by liquibase are sql/plugins/<x>/...` | That exact file has no/invalid header | Add/fix the header |
| Works in v7 fresh install, not in v8 cluster | Relying on the Ant build instead of Liquibase changesets | Header every `.sql` |
| Creation script replayed on an existing site, `Duplicate entry` or `DROP TABLE` | A SQL directory was renamed, changing the changeset identity | `logicalFilePath` on the changeset line — see `sql-rename.md` |
| `ValidationFailedException`, `1 changesets check sum` | The content of an already-shipped changeset was edited | Revert it, ship the change in a new file |

## How to verify

Every `.sql` under `src/sql` must have `-- liquibase formatted sql` as its first non-empty line:

```bash
for f in $(find src/sql -name '*.sql'); do head -1 "$f" | grep -q 'liquibase formatted sql' || echo "MISSING HEADER: $f"; done
```
