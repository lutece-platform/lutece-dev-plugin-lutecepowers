# Pattern — Externalized config (MicroProfile) & cluster robustness

> Reference: lutece-core `LuteceConfigSource` / `LuteceOverrideConfigSource` (config), `plugin-health` (probes).

## Externalized config (12-factor)
MicroProfile ordinal hierarchy (highest wins): **system props 400 > env 300 > override/ 250 > base WEB-INF/conf 150 > META-INF/microprofile-config.properties 100** (canonical table: `rules/service-layer.md`).

- DO: put plugin defaults in `src/main/resources/META-INF/microprofile-config.properties`; read via `@ConfigProperty` / `AppPropertiesService` (MicroProfile-backed → overridable by env/`-D`); expose every infra value (URL, host, path, datasource, timeout) as a **per-instance overridable property**.
- DON'T: hardcode a path (`new File("/var/...")`), a URL (`"http://..."`), a datasource name, a timeout; put a library's defaults in the core WAR; put an index/file under `java.io.tmpdir` (JVM-local) — use a **shared volume** in a cluster.

## Cluster robustness
- **Container HTTP streams**: never `flush()/close()` nor try-with-resources on `response.getOutputStream()/getWriter()` (owned by the container). TWR only on streams you open. Don't swallow `IOException` → rethrow (`AppException`). Guard writes/headers with `if(!response.isCommitted())`.
- **Thread-local**: always `ThreadLocal.remove()` in `finally`, **never** `set(null)` (leak + bleed across requests on a thread pool).
- **Determinism**: CDI guarantees no iteration order on `Instance`; any ordered registration (menus, providers, listeners) must impose an explicit order (`priority` + sort) → identical behaviour on every node.
- **Readiness/Liveness**: expose MicroProfile Health probes (`plugin-health`) for the orchestrator.
- **Shared resources**: search index, filestore, async exports → **shared volume** (NFS/PV) or DB blob, never a node's local disk.

## v8 scalability ecosystem (infra components, not code-axes)
These are **separate deployable components** of the v8 scalability toolkit — depend on / deploy them rather than reinventing them. (Lutece `lutece-platform` org.)
- `lutece-tech-plugin-liquibase` — auto-builds the schema at startup; `DATABASECHANGELOGLOCK` serialises instances. The harness uses it (migrator pattern).
- `lutece-tech-plugin-health` + `tech-module-rest-healthcheck` — MicroProfile Health probes (`/health/ready`, `/health/live`) for the orchestrator/LB.
- `lutece-tech-plugin-quartz-scheduler` — DB-backed clustered scheduling (see distributed-lock.md, "Daemons").
- `lutece-tech-library-configsource-vault` — MicroProfile ConfigSource backed by HashiCorp Vault (centralised secrets, stateless instances).
- `lutece-tech-library-core-utils` — `ServletLocalVariables.remove()` (thread-local hygiene).
- Distributed cache + session = **Hazelcast** wired into core's JSR-107 layer + Liberty `sessionCache-1.0` (see the harness; there is no standalone "hazelcast plugin").
- Do not use `plugin-hacluster` (node registry + REST): cluster-wide state goes through Hazelcast and the database.
