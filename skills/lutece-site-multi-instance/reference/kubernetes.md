# Kubernetes and the database

Prerequisites of the cluster, sizing and probes, database connections, memory and time zone. The values are measured; the
templates carry them.

- A Service exposing **5701** for the pods of the site (name = `hz.service-name`), `publishNotReadyAddresses` not required.
- RBAC: the pod service account may `get`/`list` `endpoints`, `pods`, `services` (and `endpointslices` in `discovery.k8s.io`)
  in its namespace (`templates/kubernetes-rbac.yaml`).
- `terminationGracePeriodSeconds` above `hazelcast.graceful.shutdown.max.wait` (45 s → 60 s), a readiness probe and a short
  `preStop` so that the pod leaves the Service before OpenLiberty stops (otherwise `The cache closed` errors during shutdown).
  Measured behind ingress-nginx, 10 k6 users, one rolling restart of 2 replicas: 24 and 11 errors 502 with the 30 s default and
  no `preStop`, 0 and 0 with 60 s and a 10 s `preStop`.
- Session affinity (recommended, see `SKILL.md`): measured with k6 through ingress-nginx, 2 replicas of 2 CPU, an 11-step
  declaration form, 10 min per rate, a new route cookie per declaration (affinity-mode `balanced`, load stays even):

  | Declarations/min | Affinity | p50 / p95 / p99 | Server time per declaration (p50) | CPU per request | Failures |
  |---|---|---|---|---|---|
  | 90 | no | 103 / 372 / 694 ms | 1.64 s | 116 ms | 0 |
  | 90 | yes | 86 / 289 / 530 ms | 1.36 s | 92 ms | 0 |
  | 150 | no | 203 / 708 / 977 ms | 3.38 s | 111 ms | 0 |
  | 150 | yes | 138 / 542 / 777 ms | 2.28 s | 98 ms | 0 |

  The ingress cookie must have its own name. Named `JSESSIONID` (as the OpenLiberty session cookie,
  same path), the first response carries two `JSESSIONID` cookies, the browser keeps the OpenLiberty one and the ingress no longer
  finds its route: 6 new sessions out of 10 changed pod right after their first request (minikube). Harmless with the session in
  Hazelcast, a lost session without it. With its own cookie (`lutece-route`), 10 out of 10 stayed on their pod.
  Another load balancer: a cookie it inserts in the first response (HAProxy `cookie … insert`), not a hash of `JSESSIONID`
  (`hash $cookie_JSESSIONID`): the request without cookie lands anywhere, the next ones hash to another replica. Without
  affinity the back office confirmations fail whatever `writeContents` (token set in session by the confirmation page, the OK
  posted to the other replica first; Playwright on 2 Hazelcast members behind nginx).
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
  must cover every replica, rolling update surge and autoscaling maximum included. OpenLiberty allows 50 per replica by default:
  bound it (`<connectionManager maxPoolSize="…"/>` on the data source; 12 held up to saturation with 3 replicas and up to 40
  threads per replica) or size the limit on replicas x pool.
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
- Pod sizes (measured on minikube, form journey without think time, 1 replica, database not limiting, before the load
  campaign that set the thread pool): 2 CPUs and 4 threads reached about
  25 req/s (CPU throttled), 4 CPUs and 7 threads 58 req/s, 8 CPUs and 13 threads above 80 req/s with under 5 CPUs used: past
  6 CPUs, add replicas rather than CPUs. Start in 30 s at every size; without uploads a pod stayed under 900 Mi. Uploads drive
  the memory: an uploaded file stays in the Hazelcast session (plus its backup copy on another member) until the journey ends
  or the session expires, so abandoned uploads stay 30 min; 20 users uploading 1 to 5 MB files added about 450 Mi per pod
  (3 replicas). Sizes: 1 / 2 CPUs and 1536 Mi, 2 / 4 CPUs and 3 Gi, 3 / 6 CPUs and 4 Gi (request / limit, memory request =
  limit), threads 12 for 2 CPUs (measured), measured under the target load for the larger sizes (start at 6 per CPU). OpenJ9 sizes its default heap on the limit (limit - 512 MB up to 2 GB, 75 % above): no `-Xmx`.
- One replica against two (measured on minikube, 11-step declaration form, k6 arrival rate with 1 to 3 s of think time per
  step, 10 min per rate, pods of 1 / 2 CPUs): one replica (local Ehcache) held 60 declarations/min (p99 1.4 s) and saturated
  at 90 (p50 3.3 s, 4 % of the declarations failed) and 120 (25 % failed); two replicas behind the ingress, without affinity,
  held 120 (p99 0.63 s) and 150 (p99 0.98 s) with no failure. Without affinity a replica spends 30 to 50 % more CPU per request
  than the single instance, whose requests skip the ingress and keep the session in memory.
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
  The short connect timeout is what bounds the failover: a killed pod no longer answers, and a load balancer that keeps
  sending to it with a long connect timeout holds every request routed there (measured on podman, 3 replicas, 45 users,
  `kill -9` of one: nginx with a 60 s connect timeout and no ejection, 4.5 % of journeys failed, p99 36.6 s; with a 2 s
  connect timeout and the dead node ejected for 10 s, 1.7 %, p99 2.5 s). Lowering the Hazelcast heartbeat
  (`hazelcast.max.no.heartbeat.seconds` 10, `hazelcast.heartbeat.interval.seconds` 2) changed nothing (3.7 %, p99 37.8 s):
  keep the Hazelcast defaults. With another load balancer in front of the pods, set the same short connect timeout and a
  retry on connection errors only.
