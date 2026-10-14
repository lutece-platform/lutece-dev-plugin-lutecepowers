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
- No session affinity is required. It remains useful: it limits node switches, so the session limits of the plugins below only
  show on a failure or a restart; its cookie must not be named `JSESSIONID` (see *Kubernetes prerequisites*).

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
| `pom.xml` | `pom-profiles.xml` | Hazelcast repository (required for the Hazelcast version of the template), `plugin-quartz-scheduler` dependency, profile `cluster` active by default (`!local`): Hazelcast runtime, Ehcache `provided`; profile `local` (`-Dlocal`): no Hazelcast, `liberty.bootstrap.cluster.config=none.xml` |
| `src/main/liberty/config/server.xml` | `server-xml-snippet.xml` | Merged into the site file (same ids: `defaultHttpEndpoint`, `jdbcLib`): `cluster.xml` include through the `cluster.config` variable, executor, `persistTimeout`, `remoteIp` |
| `src/main/liberty/config/cluster.xml` | `cluster.xml` | `sessionCache-1.0`, session library, `httpSessionCache`, Lutece cache provider variables |
| `src/main/liberty/config/hazelcast-config-api-mode.yaml` | same name | Member: cluster name, graceful shutdown, immediate cache invalidations, fixed port, Kubernetes discovery |
| `src/main/liberty/config/hazelcast-client-config-api-mode.yaml` | same name | Client of the Lutece cache: own pod member, near cache |
| `src/main/liberty/config/jvm.options` | `jvm.options` | Member provider type, service name, Hazelcast `--add-opens` |
| `webapp/WEB-INF/conf/override/quartz-daemons.properties` | same name | Clustered scheduler on (`quartzscheduler.cluster.enable=true`), exclusive daemons (`disallowedClusterConcurrentExecution`) |
| `webapp/WEB-INF/plugins/plugins.dat` | generated | Plugins installed on a fresh database |
| `Dockerfile` | `Dockerfile` | Configuration copied, war copied, `configure.sh` |
| Kubernetes (chart) | `kubernetes-rbac.yaml` | Service account of the pods, Service on 5701, Role/RoleBinding for the discovery |
| Kubernetes (chart) | `kubernetes-service.yaml` | Service of the site, ReadWriteMany volume of the Forms index |
| Kubernetes (chart) | `kubernetes-deployment.yaml` | Replicas, probes, preStop, grace period, CPU limit above request, Liquibase off, Forms index path |
| Kubernetes (chart) | `kubernetes-ingress.yaml` | Optional affinity (own cookie), replay on connection errors only |

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
- **No member-side `cache:` configuration for the Lutece caches**: the client creates a declared cache as soon as Lutece asks for
  it by name, bypassing the enabled/disabled state Lutece keeps in database.
- **`hazelcast.shutdownhook.enabled: false`** on the member: the default JVM hook closes the member while OpenLiberty still
  serves the requests in flight (`The cache closed`, 500 errors during a rolling update, measured on minikube: 16 errors on
  7,300 requests, 0 without the hook). OpenLiberty then closes the member gracefully when it stops `sessionCache-1.0`.
- **Liberty thread pool bounded to the CPU limit** (`<executor coreThreads="${executor.threads}" maxThreads="${executor.threads}"/>`,
  `executor.threads` set in `server.xml` by the site for the CPU limit of its deployment: the right count also depends on the
  site, through its wait / compute ratio. An `EXECUTOR_THREADS` environment variable overrides it: keep it out of the
  deployment, except to adjust a release whose CPU limit changed before the site is rebuilt). Unbounded, Liberty grows the
  pool up to 12 threads for 2 CPUs: the extra threads compete for the CPU quota, each request costs twice the CPU and the
  throughput of one replica falls as the load rises (k6, 40 users: 13.5 req/s bounded to 4, 5 to 8 req/s unbounded; 6 threads
  already halve it). Size it with threads = CPU x (1 + wait / compute): Forms requests wait 0.4 to 0.6 of their compute time
  (database 23 %, Hazelcast 6 %, files 4 % of the samples of busy request threads), more with a slow outgoing call (GRU):
  4 threads for 2 CPUs, 7 for 4, 10 for 6.
- **`persistTimeout` above the load balancer keep-alive** (`<httpOptions persistTimeout="75s"/>` in `server.xml`): Liberty closes
  idle connections after 30 s, ingress-nginx reuses its upstream connections up to 60 s; a POST sent on a connection Liberty has
  just closed gets a 502, nginx does not retry it (seen once in 7,500 k6 journeys).
- **Client address behind the ingress** (`<remoteIp />` in the `httpEndpoint`): without it `getRemoteAddr()` returns the
  ingress address for every user, and the upload DOS Guard of the core (`lutece.upload.dosguard.minInterval`, one upload
  above 10 KB every 2 s per address) throttles all users together: 387 of 411 uploads refused (500) for 10 users with
  distinct addresses on minikube, 0 with `remoteIp`. Liberty reads `X-Forwarded-For` only from a proxy in the private ranges
  (default `proxies`); ingress-nginx replaces a client-supplied `X-Forwarded-For` by default, so a forged header changes
  nothing (verified). With a load balancer in front of the ingress, `use-forwarded-headers` must be set on ingress-nginx.
- **`hazelcast.cache.invalidation.batch.enabled: false`** on the member: otherwise near-cache invalidations are batched and a
  change takes seconds to be visible on the other replicas.
- **Liquibase**: run migrations from one instance only. Disable at startup with `-Dliquibase.enabled.at.startup=false` in
  `JVM_ARGS` (the `LIQUIBASE_*` environment names are reserved by Liquibase; a system property wins over `conf/override`).
  On a fresh database and after each new war: one replica with `true`, wait until it is ready, then the replicas with
  `false` (procedure at the top of `kubernetes-deployment.yaml`). With `false` everywhere, a fresh database gets no table.
  A replica killed during a migration leaves `DATABASECHANGELOGLOCK` locked: stop every replica, release the lock, start
  one replica.
- **`plugins.dat`**: on a fresh database only the plugins listed there are installed (one line per `<name>` of the war descriptors plus `core_extensions`; keep `installed=0` only for a plugin the site wants off). A dependency may ship its own file that
  overwrites the core one: the site ships its own (`<plugin>.installed=1` per plugin; names with spaces cannot be listed).
  Remove the plugins taken out of the pom: `check-site.sh` warns about the names missing from the assembled war (`target/`).
- **Forms Lucene index on a shared volume** (`ReadWriteMany`, mounted on the parent directory `/opt/data/lucene`, with
  `forms.internalIndexer.lucene.indexInWebapp=false`, the plugin default, and
  `-Dforms.internalIndexer.lucene.indexPath=/opt/data/lucene/plugins/forms/index` in `JVM_ARGS`: the default path,
  `java.io.tmpdir/plugins/forms/index`, is local to the pod; `fsGroup: 0` lets OpenLiberty, user 1001 group 0, write). Not optional: the back office authorization on a form response searches the
  local index, so with one index per pod the response detail shows "access denied" as soon as the request changes pod (verified on
  minikube).
- **Quartz**: `quartzscheduler.cluster.enable=true` (the plugin ships `false`: without it no clustered scheduler starts and
  the daemons declared exclusive still run on every replica, verified in the plugin source), and every daemon that acts on
  shared state (database, mails, workflow, purges) listed with its `daemon-id` (from `core.xml` and each plugin `.xml`).
  A daemon working on a resource of its own pod stays local: the core search `indexer` (one index per pod) and
  `threadLauncherDaemon`. The logs show `Lutece clustered job scheduler started.` and `qrtz_SCHEDULER_STATE` one row per
  replica.

## Plugin prerequisites (report, do not patch)

Check the resolved versions. Each line was reproduced with two replicas behind nginx, except the workflow lines (found by
review, covered by the plugin-workflow tests).

| Component | Defect | Symptom | Fixed by |
|---|---|---|---|
| plugin-forms, module-forms-breadcrumbaccordion | Breadcrumb beans `@ApplicationScoped` without no-args constructor | "Your session has expired" on every node switch (`WELD-001435`) | protected no-args constructor |
| plugin-forms | `AbstractFormJsonService` (super class of `FormJsonService`), `PDFExport`, `PdfFullExport`, `CSVExport`, `LuceneLockManagerDB`, `LuceneFormSearchIndexer` without no-args constructor | Back office form creation fails when display and submission hit different replicas (`WELD-001435`, then `bean is null`); not reported at deployment nor on one replica | protected no-args constructors + hierarchy test |
| plugin-forms | Quota lock row never created; acquire query sets `is_locked=0` | Forms with quota refuse every response; quota exceeded under concurrency | `LockDAO` fix |
| lutece-core ≥ 8.0.2-beta-04 + plugin-forms | Admin actions checked by CSRF token from startup, step form posts several actions | Back office "add a response" fails at the first step (`Invalid security token`) | core checks an action under its `securityTokenAction`; forms shares one key |
| lutece-core | Admin MVC JSPs write after a redirect | OpenLiberty closes the keep-alive connection; behind ingress-nginx the next request gets a **502** | `MainFilter` discards the body after `sendRedirect` |
| lutece-core | Caches iterated on every page (security headers, plugin list), session attributes read ~10 times per page, CSRF tokens never trimmed | Most of the CPU and of the latency under load with Hazelcast | see the guide, section performance |
| plugin-htmlpage < 6.0.1 | Page include counts then lists the html page cache on every portal page, and the refresh clears the shared cache before reloading it; a created page keeps the id 0 | Every portal page iterates the whole cache over the network (and queries the database when the site has no html page); concurrent readers find the cache empty and reload it again | index entry of the cached ids read by key (near cache), refresh without clear, generated key read on insert |
| plugin-genericattributes | Asynchronous uploads kept in a static map of the instance | A file uploaded on one replica is missing when the form is submitted on another (silently: the response has no file) | uploads kept in the session (`SessionMultipartItem`, content copied only when the session is serialized) |
| module-workflow-upload | Same static map, keyed by the session id | Workflow "upload" task loses its files on a node switch, and after a login | same fix |
| plugin-genericattributes | Numbering entries counted in a static map | Two responses get the same number | counter table `genatt_entry_numbering`, incremented in database (upgrade script `3.0.2-3.0.3`, run by Liquibase) |
| plugin-htmltopdf | Builder bean keeps the HTML and a static renderer | Two concurrent PDF exports swap their contents (one replica is enough) | one rendering object per call |
| lutece-core | Mail queue: next mail selected then locked without check | The same mail sent twice if two replicas run `mailSender` | atomic lock; keep `mailSender` exclusive anyway |
| module-mylutece-database | `DatabaseUserParameterService` without non-private constructor | `WELD-001435` when a session moves to another replica | protected constructor |
| module-mylutece-oauth2 < 3.0.3 | Registry of the sessions to refresh kept per instance | A user update notified by the identity provider only reaches the sessions of the replica that receives it | version of each notified user in a Lutece cache (Hazelcast), the session keeps the version it has seen and refreshes the user when they differ |
| library-workflow-core < 4.0.2, plugin-workflow < 7.0.2 | Nothing prevents two requests from processing an action on the same resource at the same time (two agents on two replicas, an agent and the automatic action daemon) | The action runs twice, the tasks (notification, assignment) are repeated and the resource ends in a state computed from a stale one | resource claimed by a single conditional `UPDATE` on `workflow_resource_workflow.lock_date` (released after the action, expires after `workflow.resourceWorkflow.lockTimeout`, 300 s); a refused claim throws `ResourceWorkflowLockedException` (wrapped in `AppException` by the core) |
| plugin-forms < 4.0.2, workflow-rest < 3.0.0, actionsbatch < 2.0.0, alertforms < 3.0.1, extend-comment < 2.0.0, extend-feedback < 3.0.1, plugin-appointment < 4.0.0, module-appointment-alert < 4.0.0 | Callers of the workflow do not handle `ResourceWorkflowLockedException` | With the claim above, an action refused because another replica is processing the resource shows an error page instead of a message | catch the exception (or an `AppException` caused by it) and display "action in progress, try again" |

Plugin code storing per-item session attributes (one attribute per token, per uploaded file, created and removed at run time)
does not survive node switches with OpenLiberty `sessionCache`: an instance that already holds the session in memory misses
the attributes created on another instance (reproduced: a form step alternating 1-2-1-2 loses its state, an upload on one
instance is missing on the next step on the other). Keep one attribute per concern (a map) whose value changes; the remaining
limit is two concurrent requests of one session on two instances (last write wins).

Locks (`synchronized`) found on DAO inserts (workflow and its modules, extend, unittree, notifygru, mylutece-database) protect
nothing: keys are generated by the database. They only serialize the hot paths of one replica; removing them is safe.

Until a fixed version is deployed: session affinity at the load balancer, no form with a quota, no numbering entry, and no
attachment field.

## Kubernetes prerequisites

- A Service exposing **5701** for the pods of the site (name = `hz.service-name`), `publishNotReadyAddresses` not required.
- RBAC: the pod service account may `get`/`list` `endpoints`, `pods`, `services` (and `endpointslices` in `discovery.k8s.io`)
  in its namespace (`templates/kubernetes-rbac.yaml`).
- `terminationGracePeriodSeconds` above `hazelcast.graceful.shutdown.max.wait` (45 s → 60 s), a readiness probe and a short
  `preStop` so that the pod leaves the Service before OpenLiberty stops (otherwise `The cache closed` errors during shutdown).
  Measured behind ingress-nginx, 10 k6 users, one rolling restart of 2 replicas: 24 and 11 errors 502 with the 30 s default and
  no `preStop`, 0 and 0 with 60 s and a 10 s `preStop`.
- Session affinity, when used: the ingress cookie must have its own name. Named `JSESSIONID` (as the OpenLiberty session cookie,
  same path), the first response carries two `JSESSIONID` cookies, the browser keeps the OpenLiberty one and the ingress no longer
  finds its route: 6 new sessions out of 10 changed pod right after their first request (minikube). Harmless with the session in
  Hazelcast, a lost session without it. With its own cookie (`lutece-route`), 10 out of 10 stayed on their pod.
- Probes and the database: readiness checks the database, liveness checks the webapp only (plugin-health:
  `application-liveness`, webapp loaded and no deadlock), startup probe about twice the slowest start (template: 3 min).
  Lutece reconnects by itself when the database comes back (verified: 9 s restart and 90 s outage, pages back at once), so
  a liveness on the database only restarts every replica at the same time, cold. A replica started while the database is
  down never loads its webapp (404 until restarted): the startup probe restarts it. `-XX:+ExitOnOutOfMemoryError` in
  `jvm.options` (OpenJ9: keep the default dump agents, the option is one of them).
- Probe timeouts: readiness `timeoutSeconds: 5`, liveness `timeoutSeconds: 10`, startup `timeoutSeconds: 5` (template). With the
  1 s default, the replica left alone with the whole load after the loss of the other one answered its health checks late (they
  wait in the bounded thread pool) and was killed by its liveness probe: one crash took both replicas down (reproduced on
  minikube); the startup probe times out while two replicas start together. No `initialDelaySeconds`: the startup probe holds
  the other probes until the webapp is started.
- Database connections: the limit of the application user (`max_user_connections`, `maxUserConnections` of mariadb-operator)
  must cover every replica, rolling update surge and autoscaling maximum included. The executor bounds the pool in practice
  (2 replicas of 4 threads under a saturating load: 11 connections), but OpenLiberty allows 50 per replica by default: bound it
  (`<connectionManager maxPoolSize="…"/>` on the data source) or size the limit on replicas x pool.
- Database memory: the InnoDB buffer pool plus the memory of the concurrent queries (sort buffers, temporary tables), not the
  number of connections. Measured on mariadb-operator (MariaDB 11.4, 256 MB buffer pool): 120 idle connections cost 18 MiB;
  10 heavy queries at once (group by on 400,000 computed rows) got `mariadbd` OOMKilled under a 512 Mi limit, then its liveness
  probe timed out and restarted it again; under 1 Gi, 20 of them passed. With a 512 MB buffer pool filled with data, 1536 Mi held
  20 and was OOMKilled at 40 (about 40 MB per heavy query). MariaDB keeps that memory after the load (856 MiB still allocated):
  size the limit on the peak, from the number of heavy queries the site may run at once (buffer pool + base + queries x 40 MB):
  1 Gi for 256 MB, 2 Gi for 512 MB, 4 Gi for 1 GB.
  For a site with heavy exports, `tmp_table_size` and `max_heap_table_size` at 8M send large temporary tables to disk sooner.
- Autoscaling on CPU only: a JVM does not give its memory back, an autoscaler on memory grows to its maximum and never scales
  down. New pods start cold (see the warm-up below).
- Forms Lucene lock lease `forms.index.writer.ms.timeout.lock=120000`: a lock left by a crashed replica blocks the indexing
  of every response until it expires (15 min by default); the lease is renewed every third of its duration while indexing.
- CPU limit above the request: OpenJ9 JIT uses about a third of 2 CPUs during the first minutes under load.
- Pod sizes (measured on minikube, form journey, 1 replica, database not limiting): 2 CPUs and 4 threads reached about
  25 req/s (CPU throttled), 4 CPUs and 7 threads 58 req/s, 8 CPUs and 13 threads above 80 req/s with under 5 CPUs used: past
  6 CPUs, add replicas rather than CPUs. Start in 30 s at every size; without uploads a pod stayed under 900 Mi. Uploads drive
  the memory: an uploaded file stays in the Hazelcast session (plus its backup copy on another member) until the journey ends
  or the session expires, so abandoned uploads stay 30 min; 20 users uploading 1 to 5 MB files added about 450 Mi per pod
  (3 replicas). Sizes: 1 / 2 CPUs and 1536 Mi, 2 / 4 CPUs and 3 Gi, 3 / 6 CPUs and 4 Gi (request / limit, memory request =
  limit), threads 4, 7 and 10. OpenJ9 sizes its default heap on the limit (limit - 512 MB up to 2 GB, 75 % above): no `-Xmx`.
- Warm-up of a new pod (optional, measured): the shared class cache that `configure.sh` builds only holds the startup path. A
  layer trained on real traffic (container started with `-Xshareclasses:…,createLayer -Xscmx100m`, a few minutes of the site
  journeys, layer file copied into the image) halved the p95 of the first minute of the new pods during a rolling restart
  (5.4 s to 2.7 s, 2 pairs on minikube) and the time to ready on podman (68 s to 36 s). Needs a database at image build time.
  A cold JVM put under a saturating load at once can stay slow for minutes (1.2 req/s instead of 11 on podman): warm it with
  a lower load first. Liberty InstantOn (`beforeAppStart`) cut the startup CPU by 43 % but not the time to ready, the Lutece
  startup (database, Hazelcast) happening after the checkpoint; it needs CRIU capabilities at build and run time.
- Test clusters: the memory of the minikube container (`docker inspect minikube`, 4 GB by default) is not seen by Kubernetes.
  Three replicas of 1.6 GiB, or two plus the rolling update surge, make it swap and every latency measurement is wrong.
- Time zone set consistently or not at all. Lutece writes `java.sql.Timestamp` values through the MariaDB driver in the JVM time
  zone, the server reads them in its session time zone, while some columns are filled by `CURRENT_TIMESTAMP` on the server side.
  `TZ=Europe/Paris` on the pods alone (database in UTC) stores the dates written by Java 2 h in the future next to correct
  server-side dates (measured: new `forms_response.creation_date` at now + 2 h, new `forms_form.creation_date` correct). Either
  keep everything in UTC, or align the database with the pods (`TZ`, `-Duser.timezone`). Tested with mariadb-java-client 3.5,
  pods in `Europe/Paris`, server in UTC without time zone tables (`mysql.time_zone_name` empty, the default of mariadb-operator):
  - server time zone = pods: with mariadb-operator, `spec.timeZone: Europe/Paris` loads the tables and sets the default time
    zone, no JDBC option needed. The field is immutable: on an existing server, load the tables
    (`mariadb-tzinfo-to-sql /usr/share/zoneinfo | mariadb -u root -p mysql`) then set `default_time_zone=Europe/Paris` in
    `myCnf` (setting it without the tables stops the server from starting);
  - server kept in UTC: `connectionTimeZone=UTC&preserveInstants=true` on the JDBC URL, the driver converts (dates stored in
    UTC, shown in Paris time). `connectionTimeZone` alone has no effect; `connectionTimeZone=LOCAL&forceConnectionTimeZoneToSession=true`
    fails without the tables (`Unknown or incorrect time zone`).
  Either change on a database already in use shifts its past `TIMESTAMP` values written by Java (+1 or +2 h); the ones filled by
  `CURRENT_TIMESTAMP` become right, `DATETIME` columns do not move. Recompute the Java ones per column, after the switch:
  `UPDATE <table> SET <column> = CONVERT_TZ(<column>, 'Europe/Paris', 'UTC')` (verified).
  Dates computed by the browser (form availability "today") are local dates: with a UTC server a form published between
  00:00 and 02:00 Paris time is not listed until 02:00.
- Ingress replays a request on another pod when the connection to a pod fails, never a request already sent
  (`proxy-next-upstream: error timeout`, without `non_idempotent`; template). Real crash of one pod (SIGKILL) under 20 k6 users on
  minikube: 5.6 to 6.9 % of the journeys failed without the replay (502 on connection refused), 0 to 0.6 % with it; the remaining
  errors are POSTs that were in flight on the killed pod.

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
   With an attachment field: upload on one replica, submit on the other, the saved response has the file. Numbering entries:
   concurrent submissions on both replicas get distinct numbers.
3. Back office login on one replica, menu on the other; rights changed on one, visible on the other.
4. A site property changed on one replica is visible on the other within a second (near cache invalidation).
5. An exclusive daemon runs once per schedule across the cluster.
6. `kill -9` of one replica: sessions continue on the other; rolling restart (SIGTERM) of both replicas without session loss
   and without `migration` errors in the Hazelcast logs.
7. Under load behind the real ingress: no 502.
