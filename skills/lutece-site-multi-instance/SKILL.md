---
name: lutece-site-multi-instance
description: "Use when a Lutece 8 site (packaging lutece-site, OpenLiberty container image) must run as several replicas behind a load balancer, on Kubernetes or elsewhere: shared HTTP session and Lutece cache (Hazelcast, the tested setup, or another store), clustered Quartz daemons, plugins.dat, Liquibase from one replica, shared Forms index, probes, rolling updates. Site configuration and deployment only; the code of a plugin belongs to lutece-scalability-v8. Triggers on 'site multi-instance', 'plusieurs réplicas', 'plusieurs instances du site', 'site en cluster', 'session partagée', 'Hazelcast', 'déployer le site sur Kubernetes', 'replicas'."
metadata:
  summary: "Configure a site to run as several replicas, and check it."
---

# Lutece 8 site — several replicas

## Scope

Configures a **site** (`packaging lutece-site`, OpenLiberty image) for N replicas behind a load balancer: the files of the
site, the Kubernetes manifests, and the checks. It does not change plugin code: a plugin defect found on the way is reported
(`reference/plugin-prerequisites.md`); fixing a plugin is `lutece-scalability-v8`.

Two things must be shared between the replicas: the HTTP session and the Lutece cache. This skill writes **one way** of
doing it, the one tested with Lutece:

- **HTTP session**: OpenLiberty `sessionCache-1.0` over a **Hazelcast member embedded in each pod**.
- **Lutece cache** (JCache): a **Hazelcast client** connected to the member of its own pod, with a **near cache**.

Other stores fit OpenLiberty and Lutece: sessions in a database (`sessionDatabase-1.0`), another JCache provider
(Infinispan, Redis through Redisson, a separate Hazelcast cluster). They are not tested with Lutece; when the user wants
one, follow `reference/session-options.md` (OpenLiberty documentation links) and keep every other rule below.

Session affinity is not required. It still limits node switches; its cookie must not be named `JSESSIONID`.

## Before writing anything

1. Read the site: `pom.xml`, `src/main/liberty/config/*`, `Dockerfile`, `webapp/WEB-INF/conf/override/*.properties`,
   `webapp/WEB-INF/plugins/plugins.dat`.
2. Note the site code (`<site>` in the templates: cluster name, Kubernetes names), the database, the plugins.
3. Check `reference/plugin-prerequisites.md` against the versions the site resolves (the war `WEB-INF/lib`).
4. Ask the user only what cannot be read: the session store if not Hazelcast, the Kubernetes service name of the Hazelcast
   port and the Hazelcast version if the organisation imposes them, the ReadWriteMany storage class.

## Files to write

Templates are in `templates/`: replace `<site>`, `<registry>/<site>:<version>`, `<host>`. Keep the comments language of
the site. A template marked *merge* goes into the existing file; the others are copied.

| File | Template | Content |
|---|---|---|
| `pom.xml` (merge) | `pom-profiles.xml` | Hazelcast repository, `plugin-quartz-scheduler`, profile `cluster` (default: Hazelcast, Ehcache `provided`), profile `local` (`-Dlocal`: no `cluster.xml`) |
| `src/main/liberty/config/server.xml` (merge) | `server-xml-snippet.xml` | `cluster.xml` include, `persistTimeout`, `remoteIp`, bounded executor, `maxPoolSize` on the existing data source |
| `src/main/liberty/config/cluster.xml` | same name | `sessionCache-1.0`, session library, `httpSessionCache`, Lutece cache provider |
| `src/main/liberty/config/hazelcast-config-api-mode.yaml` | same name | Member: cluster name, graceful shutdown, JVM hook off, immediate invalidations, fixed port, Kubernetes discovery |
| `src/main/liberty/config/hazelcast-client-config-api-mode.yaml` | same name | Client of the Lutece cache: member of its own pod, near cache |
| `src/main/liberty/config/jvm.options` (merge) | `jvm.options` | Member provider type, Hazelcast service name, `--add-opens` |
| `webapp/WEB-INF/conf/override/quartz-daemons.properties` | same name | `quartzscheduler.cluster.enable=true`, exclusive daemons, Forms lock lease |
| `webapp/WEB-INF/plugins/plugins.dat` | `site_check.py plugins-dat <war>` | Plugins installed on a fresh database |
| `Dockerfile` | same name | Configuration, war, `configure.sh` (expanded war) |
| Kubernetes | `kubernetes-rbac.yaml` | Service account, Service on 5701, Role/RoleBinding for the discovery |
| Kubernetes | `kubernetes-service.yaml` | Service of the site, ReadWriteMany volume of the Forms index |
| Kubernetes | `kubernetes-migration.yaml` | One-replica Liquibase run, before the replicas |
| Kubernetes | `kubernetes-deployment.yaml` | Replicas, sizes, probes, preStop, grace period, Liquibase off, Forms index path |
| Kubernetes | `kubernetes-ingress.yaml` | Replay on connection errors only, optional affinity, context root |

The Kubernetes templates are plain manifests: add the namespace and the image pull policy of the target, or turn them into
the templates of the organisation's chart.

## Rules that are easy to get wrong

Each one was observed; the evidence and the numbers are in `reference/rules.md` and `reference/kubernetes.md`.

- Session library = **every jar of the war**, and `writeContents="GET_AND_SET_ATTRIBUTES"`: otherwise partitions do not
  migrate, and `@SessionScoped` beans modified in place are lost on a node switch.
- `-Dhazelcast.jcache.provider.type=member` in `jvm.options`; no `cache:` section on the member (a `"*"` entry stops the
  application at the next full restart); JVM shutdown hook off and graceful shutdown on; near cache on the client, its
  invalidations not batched.
- Quartz: `quartzscheduler.cluster.enable=true` (the plugin ships `false`) and every daemon acting on shared state declared
  exclusive; the core `indexer` and `threadLauncherDaemon` stay local (table in `reference/rules.md`).
- Liquibase from one replica only: `-Dliquibase.enabled.at.startup=false` on the replicas, `kubernetes-migration.yaml`
  before them on a fresh database and before each new war.
- `plugins.dat` shipped by the site, generated from the war: a dependency's own file can disable plugins on a fresh database.
- Forms index on a ReadWriteMany volume (`indexPath` in `JVM_ARGS`, `fsGroup: 0`) and lock lease
  `forms.index.writer.ms.timeout.lock=120000`.
- Liberty: `persistTimeout` above the 60 s keep-alive of the load balancer, `<remoteIp/>` behind the ingress, executor
  bounded to the CPU limit (4 threads for 2 CPUs, 7 for 4, 10 for 6), `maxPoolSize` about 3 x threads; the database user
  limit covers (replicas + surge + migration run) x `maxPoolSize`.
- Kubernetes: preStop 10 s and grace period 60 s, startup probe, readiness on the database, liveness on the webapp only,
  probe timeouts 5 s / 10 s, CPU limit above the request, autoscaling on CPU only.
- Data changed outside Lutece (SQL, restore): reset the caches from the back office; a rolling restart keeps them, and with
  Hazelcast every Lutece cache is eternal (the sizes and lifetimes of `caches.properties` apply to Ehcache only). Never
  enable or disable a cache from the back office: it acts on one replica only.

## Checks

```bash
bash ${LUTECEPOWERS_ROOT}/tools/site-assemble.sh . --out .multi-instance/site
python3 ${LUTECEPOWERS_ROOT}/tools/site_check.py check . --war .multi-instance/site --k8s <manifests-or-chart-templates>
```

SI60-SI68 check the multi-instance configuration of the site, SI70-SI72 the manifests, SI40-SI44 `plugins.dat`. Every FAIL
is fixed before handing over; a WARN left is explained to the user.
`bash ${LUTECEPOWERS_ROOT}/tools/lutece-check.sh --explain SI66` explains a code.

## Proving it

Static checks do not prove the cluster. When the user asks for the proof, run `reference/verification.md`: a journey with
every step on another replica, concurrent numbering, back office session, cache invalidation, forced pod deletion and rolling
restart under load. Plain HTTP on a host other than `localhost` breaks the back office (CSP `upgrade-insecure-requests`):
test behind TLS or through `localhost`.

## References

- `reference/session-options.md`: Hazelcast and the other stores, OpenLiberty links.
- `reference/rules.md`: the rules with their evidence, the classification of the daemons.
- `reference/kubernetes.md`: cluster prerequisites, sizes, probes, database connections, memory and time zone.
- `reference/plugin-prerequisites.md`: plugin defects found with several replicas and their fixed versions.
- `reference/verification.md`: the runtime checks and how they were run.
