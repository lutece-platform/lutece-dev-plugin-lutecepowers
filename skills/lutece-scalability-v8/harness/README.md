# Scalability test harness — 3-instance Lutece v8 cluster

A proven, parameterized cluster used to **empirically verify** a plugin's scalability.
`../scripts/gen-test-site.sh` templates this harness for a given plugin (injects the plugin
dependency into `pom.xml.tpl` and enables it in `plugins.dat.tpl`, fetches Hazelcast, builds the war).

## Topology
```
            nginx :8080 (round-robin, no sticky)
                 |
   app1 (migrator) ── app2 ── app3      3x Open Liberty (core + plugin), Hazelcast members
                 |  jdbc/portal
             mariadb :3306 (shared DB)
   shared volume: /opt/lutece/shared (Lucene index, filestore)
```

## Parent and BOM versions
- Parent `lutece-site-pom` **8.0.1**: the latest release in `fr/paris/lutece/tools/lutece-site-pom/maven-metadata.xml` on `dev.lutece.paris.fr/maven_repository`. Never a SNAPSHOT parent.
- `fr.paris.lutece.starters:lutece-bom` **8.0.0-SNAPSHOT**: the only release is `8.0.0-RC-01` (same metadata file under `starters/lutece-bom`), so the snapshot repository stays declared and the import keeps the SNAPSHOT until a final BOM is released. Re-check the metadata before changing it.

## How it works (and the gotchas it bakes in)
- **Build**: Lutece `lutece-site` packaging; assembled with `mvn -Pdev clean package lutece:site-assembly`, then the exploded webapp is `jar`-ed into `lutece.war`. The `lutece-maven-plugin` assembly lifecycle is only active under an env profile (`-Pdev`).
- **DB / schema**: empty MariaDB + **plugin-liquibase** (`LIQUIBASE_ENABLED_AT_STARTUP`) builds the schema on first boot. **Migrator pattern**: only `app1` has Liquibase enabled + a healthcheck; `app2`/`app3` start once `app1` is healthy (Liquibase disabled) → no concurrent first-run race.
- **Datasource**: Lutece uses the Liberty JNDI datasource via `webapp/WEB-INF/conf/db.properties` (`ManagedConnectionService` + `portal.ds=jdbc/portal`), configured in `server.xml`.
- **Plugin activation**: `webapp/WEB-INF/plugins/plugins.dat` (v8 defaults plugins to NOT installed; we set `<name>.installed=1`).
- **Level 2 — distributed cache**: `hazelcast` dependency + `com.hazelcast.cache.HazelcastMemberCachingProvider` + `hazelcast.xml` (cluster `lutece-cache`, port **5703**, tcp-ip app1/2/3). Env vars in compose. This member is loaded from the **WAR** class loader.
- **Level 2 — session replication**: Liberty `sessionCache-1.0` + Hazelcast (`server.xml` cacheManager + `JCacheLib` → `hazelcast-session.xml`, cluster `lutece-session`, port **5701**). The Hazelcast jar is at **server level** (sessionCache inits before the war). `jvm.options` forces `-Dhazelcast.jcache.provider.type=member`. nginx is **round-robin** (no `ip_hash`). **CRITICAL**: `<httpSessionCache>` sets `writeContents="GET_AND_SET_ATTRIBUTES"` — the Liberty default `ONLY_SET_ATTRIBUTES` does NOT replicate in-place mutations of `@SessionScoped` CDI beans, so stateful wizards silently break on node switch while plain `setAttribute` (admin auth) still replicates and hides it.
- **Two SEPARATE Hazelcast clusters, on purpose**: each JVM runs two Hazelcast members — the JCache one (WAR class loader, `lutece-cache`/5703) and the session one (server lib class loader, `lutece-session`/5701). They MUST NOT share a cluster: a single cluster spanning both class loaders makes partition-migration operations cross the class-loader boundary and fail with `Failed to serialize com.hazelcast.internal.partition.operation.MigrationOperation`. Distinct cluster-name + distinct port per concern keeps each cluster class-loader-homogeneous.
- **nginx forwards `Host` WITH the port** (`proxy_set_header Host $http_host`, not `$host`): Lutece builds absolute redirect URLs from the `Host` header. With `$host` (no port) every redirect points to `http://<name>/` (port 80) → a browser following it (admin login, any `do*` action, Playwright) gets `ERR_CONNECTION_REFUSED`. `$http_host` keeps `localhost:8080` so redirects work. Essential for any redirect-based / browser-driven (Playwright) test.
- **Shared index**: the volume is mounted on the **parent** `/opt/lutece/shared` (not on `forms-index` itself) because the indexer swaps the index dir via `Files.move` (rename fails EBUSY on a mount point).
- **dbinit**: one-shot service applying `db/post-init.sql` after migration (clears the default admin password expiry so `admin/adminadmin` logs in without the password-change wall — used by the session-replication check).

## Driving a stateful FO flow through the cluster (Playwright) — gotchas
Proving no-overbooking/no-lost-state means driving a **multi-step** FO flow end-to-end through the
round-robin LB. Things that make a basic run fail until you know them:
- **`writeContents`**: see server.xml — without `GET_AND_SET_ATTRIBUTES` the wizard loses its state on
  a node switch and every submit bounces back ("session lost"). Fix the harness before blaming the app.
- **Wrap JS form submits in `expect_navigation`**: when you submit a form from `page.evaluate` (to hit
  the exact form among page widgets), the click and the subsequent load-wait race — the wait can resolve
  on the in-flight page and you read the *previous* step. `async with page.expect_navigation(...)` keeps them in sync.
- **Cookie banner (tarteaucitron)**: clicking "Tout accepter" triggers a **page reload** — if done right
  before a submit it cancels the click. Accept it **once** early, then for later steps just **remove** the
  overlay from the DOM (`[id^=tarteaucitron]`) without clicking (no reload).
- **`domcontentloaded`, not `networkidle`**: with N concurrent browsers and a short server-side TTL (a
  provisional hold), `networkidle` waits for full network silence and blows the TTL budget → spurious failures.
- **Prove it's really multi-node**: log `r.headers["x-upstream"]` (the harness nginx adds `X-Upstream`)
  per response — assert the steps are served by different nodes yet the flow completes. That is the proof.
- **Read the app's own field validation**: generic-attribute/identity fields can reject inputs (e.g. names
  with digits) — a validation bounce looks exactly like a state bug. Capture the re-rendered form, not just the URL.
- **Always read docker logs before AND after** (`docker logs --since <t> <node>`): the decisive evidence
  (e.g. the atomic guard rejecting over-capacity writes) is server-side, not in the browser.

## Boot & seed — gotchas
- **plugin-xmltransformer is mandatory** (in `pom.xml.tpl`, always enabled): it provides
  the legacy `core_style*` tables some plugins' core SQL still INSERTs into — without it
  the whole Liquibase run aborts and NO plugin schema deploys. Never pre-create tables
  by hand before the first migration: any pre-existing table defeats plugin-liquibase's
  empty-db detection and kills the migration.
- **FO authentication**: when the flow under test needs a logged-in LuteceUser, uncomment
  the mylutece block in `pom.xml.tpl`, add `mylutece,mylutece-database` to `--enable`, and
  uncomment the FO user seed in `db/post-init.sql` (grant the role the plugin checks).
  Login URL: `Portal.jsp?page=mylutece&action=login&auth_provider=mylutece-database`,
  fields `username`/`password`.
- **First boot**: if app1's migration outlasts the healthcheck, `docker compose up -d`
  exits with "dependency app1 unhealthy" and app2/app3/dbinit never start — re-run
  `docker compose up -d` once app1 is healthy. If it stays unhealthy, the migration
  failed: read its logs.
- **Waiting for health**: grep on `healthy` also matches **un**healthy — use
  `docker inspect -f '{{.State.Health.Status}}' lutece-app1`.
- **dbinit re-runs on every `up`**: keep `db/post-init.sql` idempotent (INSERT IGNORE).
- **e2e**: start from `e2e_skeleton.py` (copy into the plugin's `e2e/`, adapt the CONFIG
  block + form selectors). Same skeleton adapts to the failover proof: map the form's
  `X-Upstream` IP to its container, `docker kill` it before submit, retry the submit
  once (nginx may hit the dead upstream first), then `docker start` and assert rejoin.

## Usage
```bash
# from the plugin root:
bash ../scripts/gen-test-site.sh --local . --enable <plugin,deps> --out e2e/.scalability-test
( cd e2e/.scalability-test && docker compose up -d )
LOCK_TABLE=<plugin>_lock bash ../scripts/cluster-verify.sh e2e/.scalability-test
( cd e2e/.scalability-test && docker compose down -v )
```

> Kept on disk after the run: the generated `e2e/.scalability-test/` is part of the deliverable (see the artifact retention rule in `SKILL.md`); only the containers are torn down.
> Image base: `icr.io/appcafe/open-liberty:full-java21-openj9-ubi-minimal`.
