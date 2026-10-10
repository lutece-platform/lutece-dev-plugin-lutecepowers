---
name: lutece-site-multi-instance
description: "Configure a Lutece 8 SITE (OpenLiberty container image) to run as several replicas: HTTP session and Lutece cache in Hazelcast, Quartz daemons, plugins.dat, Liquibase, Kubernetes prerequisites. Site configuration only (no plugin code). Use when a site must be deployed with more than one replica."
user-invocable: true
---

# Lutece 8 site — multi-instance configuration

## Scope

Configures a **site** (`packaging lutece-site`, OpenLiberty image) for N replicas behind a load balancer. It does not change plugin
code: plugin defects found on the way are reported (see *Plugin prerequisites*), the plugin work belongs to `lutece-scalability-v8`.

Imposed choices:
- **HTTP session**: OpenLiberty `sessionCache-1.0` over an **embedded Hazelcast member** (one member per pod, in-line topology).
- **Lutece cache** (JCache): **Hazelcast client** connected to the member of its own pod, with a **near cache**.
- **Daemons**: `plugin-quartz-scheduler` (clustered Quartz), exclusive daemons declared per id.
- No session affinity is required (it remains possible).

Configure only: the skill writes the files and checks them statically. Proving the cluster (two instances, node switch, failover)
is a separate step; the verification list at the end gives the checks.

## Before writing anything

1. Read the site: `pom.xml` (parent, BOM/starters or plugin list), `src/main/liberty/config/*` (server.xml, server.env,
   bootstrap.properties, jvm.options), `Dockerfile`, `webapp/WEB-INF/conf/override/*.properties`, `webapp/WEB-INF/plugins/plugins.dat`.
2. Note the site name (cluster name, Kubernetes service name), the database, the plugins.
3. Check the *Plugin prerequisites* table against the versions the site resolves (`mvn dependency:tree` or the war `WEB-INF/lib`).
4. Ask the user only what cannot be read: the Kubernetes service name of the Hazelcast port if it is imposed by the chart, the
   Hazelcast version if the organisation pins one.

## Files to write

Templates are in `templates/`; replace `<site>` with the site code. Keep the user's existing comments language.

| File | Template | Purpose |
|---|---|---|
| `pom.xml` | `pom-profiles.xml` | Profile `cluster` active by default (`!local`): Hazelcast runtime, Ehcache `provided`; profile `local` (`-Dlocal`): no Hazelcast, `liberty.bootstrap.cluster.config=none.xml` |
| `src/main/liberty/config/server.xml` | `server-xml-snippet.xml` | Includes `cluster.xml` through the `cluster.config` variable (optional include) |
| `src/main/liberty/config/cluster.xml` | `cluster.xml` | `sessionCache-1.0`, session library, `httpSessionCache`, Lutece cache provider variables |
| `src/main/liberty/config/hazelcast-config-api-mode.yaml` | same name | Member: cluster name, graceful shutdown, immediate cache invalidations, fixed port, Kubernetes discovery |
| `src/main/liberty/config/hazelcast-client-config-api-mode.yaml` | same name | Client of the Lutece cache: own pod member, near cache |
| `src/main/liberty/config/jvm.options` | `jvm.options` | Member provider type, service name, Hazelcast `--add-opens` |
| `webapp/WEB-INF/conf/override/<profiles>.properties` | `quartz-daemons.properties` | Exclusive daemons (`disallowedClusterConcurrentExecution`) |
| `webapp/WEB-INF/plugins/plugins.dat` | generated | Plugins installed on a fresh database |
| `Dockerfile` | `Dockerfile` | Configuration copied, war copied, `configure.sh` |
| Kubernetes (chart) | `kubernetes-rbac.yaml` | Service on 5701, Role/RoleBinding for the discovery |
| Kubernetes (chart) | `kubernetes-deployment.yaml` | Replicas, probes, preStop, grace period, CPU limit above request |

### Rules that are easy to get wrong (all observed)

- **Session library = every jar of the war**, not the Hazelcast jar alone. The members also host the Lutece caches created by the
  clients; to migrate a partition they must resolve Lutece types (`DataEntity`…). With the Hazelcast jar only: `Could not resolve
  type`, rebalancing aborted, sessions lost on rolling restart.
- **`writeContents="GET_AND_SET_ATTRIBUTES"`** is mandatory: the default only replicates `setAttribute`; `@SessionScoped` beans
  modified in place (multi-step forms) are lost on a node switch while login keeps working, which hides the problem.
- **`-Dhazelcast.jcache.provider.type=member`** in `jvm.options` (JVM system property): without it the provider loaded by
  `sessionCache-1.0` starts as a client and there is no member.
- **`include` location**: a variable used in an `<include location>` must come from `bootstrap.properties`
  (`liberty.bootstrap.*` in the pom), not from `configDropins`.
- **`server.env` overrides the container environment**: never put an environment-specific value there (e.g. `OTEL_SDK_DISABLED`);
  the deployment could not change it.
- **No member-side `cache:` configuration for the Lutece caches**: the client creates a declared cache as soon as Lutece asks for
  it by name, bypassing the enabled/disabled state Lutece keeps in database.
- **`hazelcast.shutdownhook.enabled: false`** on the member: the default JVM hook closes the member while OpenLiberty still
  serves the requests in flight (`The cache closed`, 500 errors during a rolling update, measured on minikube: 16 errors on
  7,300 requests, 0 without the hook). OpenLiberty then closes the member gracefully when it stops `sessionCache-1.0`.
- **`hazelcast.cache.invalidation.batch.enabled: false`** on the member: otherwise near-cache invalidations are batched and a
  change takes seconds to be visible on the other replicas.
- **Liquibase**: run migrations from one instance only. Disable at startup with `-Dliquibase.enabled.at.startup=false` in
  `JVM_ARGS` (the `LIQUIBASE_*` environment names are reserved by Liquibase). A replica killed during a migration leaves
  `DATABASECHANGELOGLOCK` locked: stop every replica, release the lock, start one replica.
- **`plugins.dat`**: on a fresh database only the plugins listed there are installed. A dependency may ship its own file that
  overwrites the core one: the site ships its own (`<plugin>.installed=1` per plugin; names with spaces cannot be listed).
- **Lucene indexes** (forms internal indexer…): on a shared volume (`ReadWriteMany`), or one index per pod.
- **Quartz**: every daemon that must run once per cluster is listed with its `daemon-id` (from `core.xml` and each plugin `.xml`).

## Plugin prerequisites (report, do not patch)

Check the resolved versions. Each line was reproduced with two replicas behind nginx.

| Component | Defect | Symptom | Fixed by |
|---|---|---|---|
| plugin-forms, module-forms-breadcrumbaccordion | Breadcrumb beans `@ApplicationScoped` without no-args constructor | "Your session has expired" on every node switch (`WELD-001435`) | protected no-args constructor |
| plugin-forms | `AbstractFormJsonService` (super class of `FormJsonService`), `PDFExport`, `PdfFullExport`, `CSVExport`, `LuceneLockManagerDB`, `LuceneFormSearchIndexer` without no-args constructor | Back office form creation fails when display and submission hit different replicas (`WELD-001435`, then `bean is null`); not reported at deployment nor on one replica | protected no-args constructors + hierarchy test |
| plugin-forms | Quota lock row never created; acquire query sets `is_locked=0` | Forms with quota refuse every response; quota exceeded under concurrency | `LockDAO` fix |
| lutece-core ≥ 8.0.2-beta-04 + plugin-forms | Admin actions checked by CSRF token from startup, step form posts several actions | Back office "add a response" fails at the first step (`Invalid security token`) | core checks an action under its `securityTokenAction`; forms shares one key |
| lutece-core | Admin MVC JSPs write after a redirect | OpenLiberty closes the keep-alive connection; behind ingress-nginx the next request gets a **502** | `MainFilter` discards the body after `sendRedirect` |
| lutece-core, plugin-htmlpage | Caches iterated on every page (security headers, plugin list, html pages), session attributes read ~10 times per page, CSRF tokens never trimmed | Most of the CPU and of the latency under load with Hazelcast | see the guide, section performance |

Until a fixed version is deployed: session affinity at the load balancer and no form with a quota.

## Kubernetes prerequisites

- A Service exposing **5701** for the pods of the site (name = `hz.service-name`), `publishNotReadyAddresses` not required.
- RBAC: the pod service account may `get`/`list` `endpoints`, `pods`, `services` (and `endpointslices` in `discovery.k8s.io`)
  in its namespace (`templates/kubernetes-rbac.yaml`).
- `terminationGracePeriodSeconds` above `hazelcast.graceful.shutdown.max.wait` (45 s → 60 s), a readiness probe and a short
  `preStop` so that the pod leaves the Service before OpenLiberty stops (otherwise `The cache closed` errors during shutdown).
- CPU limit above the request: OpenJ9 JIT uses about a third of 2 CPUs during the first minutes under load.

## Static checks (run after writing)

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/lutece-site-multi-instance/scripts/check-site.sh <site-dir>
```
Every line must be `OK`; fix the `KO` lines before handing over.

## Runtime verification (when the user asks to prove it)

Over plain HTTP on a host other than `localhost` (a NodePort), the CSP `upgrade-insecure-requests` of the security headers makes the
browser load the resources over HTTPS and the back office breaks: test behind TLS or through `localhost` (port-forward, relay).

1. Two replicas start; the logs show `Members {size:2` and the client `Client Connectivity` to both members.
2. A multi-step form completed with each step served by a different replica (cookie or round robin): no "session expired".
3. Back office login on one replica, menu on the other; rights changed on one, visible on the other.
4. A site property changed on one replica is visible on the other within a second (near cache invalidation).
5. An exclusive daemon runs once per schedule across the cluster.
6. `kill -9` of one replica: sessions continue on the other; rolling restart (SIGTERM) of both replicas without session loss
   and without `migration` errors in the Hazelcast logs.
7. Under load behind the real ingress: no 502.
