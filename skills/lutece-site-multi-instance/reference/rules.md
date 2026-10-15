# Rules, with the evidence

Each rule was observed on minikube or podman with two or three replicas behind ingress-nginx, unless stated.

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
  it by name, bypassing the enabled/disabled state Lutece keeps in database. A `"*"` entry also matches the session caches of
  OpenLiberty: on a cluster started from zero, `SESN0307E Incompatible cache key types` and the application does not start;
  a rolling restart hides it, the running members keeping the session caches already created (verified on minikube).
- **The Lutece cache settings do not reach Hazelcast**: sizes and lifetimes of `caches.properties` and of
  `core.cache.status.*` only apply to Ehcache. With the Hazelcast client every Lutece cache is eternal, 10,000 entries LRU
  (verified: `formsCacheService` and its 24 h TTL included). A `time-to-live-seconds` on the near cache does not change that:
  the near cache reloads the entry from the member, which still holds it.
- **Near cache required**: without it every cache read is a network call (k6, 16 users, 2 replicas: 2.2 req/s and 1.7 s of CPU
  per request, against 37.6 req/s and 73 ms with it). `in-memory-format: OBJECT` returns the same instance to every reader of
  the pod (Ehcache returns a copy): code that modifies an object read from a cache changes it for the concurrent requests of the
  pod; `BINARY` copies at each read for about a third more CPU per request (97 ms against 73 ms).
- **Cache screen of the back office**: reset only. Enabling or disabling a cache acts on the replica that receives the request,
  is not saved in database, and disabling clears the shared cache: verified, a value written through the disabled replica
  stayed stale on the other one, and on both after it was enabled again.
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
  `false` (`templates/kubernetes-migration.yaml`). With `false` everywhere, a fresh database gets no table.
  A replica killed during a migration leaves `DATABASECHANGELOGLOCK` locked: stop every replica, release the lock, start
  one replica.
- **`plugins.dat`**: on a fresh database only the plugins listed there are installed (one line per `<name>` of the war descriptors plus `core_extensions`; keep `installed=0` only for a plugin the site wants off). A dependency may ship its own file that
  overwrites the core one: the site ships its own (`<plugin>.installed=1` per plugin; names with spaces cannot be listed).
  Generate it from the assembled war with `site_check.py plugins-dat <war>`; SI40-SI44 compare it with the war.
- **Forms Lucene index on a shared volume** (`ReadWriteMany`, mounted on the parent directory `/opt/data/lucene`, with
  `forms.internalIndexer.lucene.indexInWebapp=false`, the plugin default, and
  `-Dforms.internalIndexer.lucene.indexPath=/opt/data/lucene/plugins/forms/index` in `JVM_ARGS`: the default path,
  `java.io.tmpdir/plugins/forms/index`, is local to the pod; `fsGroup: 0` lets OpenLiberty, user 1001 group 0, write). Not optional: the back office authorization on a form response searches the
  local index, so with one index per pod the response detail shows "access denied" as soon as the request changes pod (verified on
  minikube).
- **Data changed outside Lutece** (SQL script, restore): the Lutece caches live in Hazelcast and survive a rolling restart
  as long as one member stays up. Reset them from the back office (system, caches: applies to the whole cluster) or stop
  every replica. Verified: a form inserted in SQL after the form list was cached stayed invisible to the Forms indexer
  ("associated form not found") across a rolling restart, and was found after the reset.
- **Quartz**: `quartzscheduler.cluster.enable=true` (the plugin ships `false`: without it no clustered scheduler starts and
  the daemons declared exclusive still run on every replica, verified in the plugin source), and every daemon that acts on
  shared state (database, mails, workflow, purges) listed with its `daemon-id` (from `core.xml` and each plugin `.xml`).
  A daemon working on a resource of its own pod stays local: the core search `indexer` (one index per pod) and
  `threadLauncherDaemon`. `site_check.py check --war` lists the daemons of the war left on every replica (INFO SI66).
  Classification of the daemons of a Forms site (core, forms, workflow, mylutece-database, accesscontrol, filegenerator):

  | Daemon | Plugin | Exclusive | Why |
  |---|---|---|---|
  | `mailSender` | core | yes | sends the mail queue |
  | `anonymizationDaemon`, `accountLifeTimeDaemon` | core | yes | update the admin users |
  | `indexer` | core | no | core search index, one per pod (`search.lucene.indexPath`) |
  | `threadLauncherDaemon` | core | no | runs the threads queued by its own pod |
  | `formsIndexerDaemon` | forms | yes | indexes the responses into the shared index (it also takes the database lock) |
  | `formsBackupPurgeDaemon` | forms | yes | purges in database |
  | `automaticActionDaemon`, `archiveDaemon`, `chooseStateActionDaemon`, `changeStateDaemon` | workflow | yes | run workflow actions: twice means the tasks repeated |
  | `notifyHistoryCleanerDaemon` | workflow-notifygru | yes | purges in database |
  | `databaseAnonymizationDaemon`, `databaseAccountLifeTimeDaemon` | mylutece-database | yes | update the users, send mails |
  | `userControllerCodeDataDaemon` | accesscontrol | yes | purges in database |
  | `temporaryfilesDaemon` | filegenerator | yes | purges the generated files, stored in database | The logs show `Lutece clustered job scheduler started.` and `qrtz_SCHEDULER_STATE` one row per
  replica.
