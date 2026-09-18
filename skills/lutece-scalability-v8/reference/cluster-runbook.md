# Scalability — cluster runbook

How to stand the 3-node cluster up, what to read in the logs, how to redeploy and how to prove failover.
The method — triage, RED before fix, the UI e2e as the only proof — stays in SKILL.md.

## Contents
- Standing the baseline cluster up (PHASE A.4.2)
- Redeploying the fix and proving it (PHASE F)

## Standing the baseline cluster up (PHASE A.4.2)

1. Generate + boot the cluster on the **current, unfixed** code (`gen-test-site.sh` → `docker compose up -d`; steps 1 to 4 of the next section carry the mechanics and the mandatory docker-log read). The baseline must be truly unfixed and fresh: `docker compose down -v` any stale `lutece-*` cluster, and `git stash` any uncommitted fix (pop it back in Phase B). If the flow needs a logged-in FO user, enable the mylutece block in the generated `pom.xml` + the FO seed in `db/post-init.sql` (boot gotchas: `harness/README.md` § "Boot & seed").
2. **Smoke-check logins before writing the e2e** — BO `admin/adminadmin`, plus the seeded FO user if any.
3. **Write the e2e that drives the real user flow** for each confirmed defect and store it under the plugin's `e2e/` (it is a durable, committable artifact — see retention rule). **Copy `harness/e2e_skeleton.py`** into the plugin's `e2e/` and adapt the CONFIG block, the arm/submit steps to the actual contended flow (often a form submit, but it can be any UI action — AJAX button, wizard step, link) and the RED condition — do not rewrite the scaffolding (login FO/BO, X-Upstream capture, concurrent gather, DB-via-docker-exec, log scan are already correct there). It MUST:
   - go **through the UI over nginx** (round-robin, no sticky) — real login, real navigation, real form submit — exactly what a user does; log `X-Upstream` per request to prove steps hit **different nodes**;
   - drive the contended operation **concurrently** (N real browser/API clients on one resource) — e.g. N users editing/saving the same page at once;
   - **assert against the DB** (source of truth), and read the **docker logs** for the server-side evidence (constraint violation, lost write, broken invariant, exception).
4. Run it on the baseline → it must be **RED** (invariant broken). Persist the run output under `e2e/artifacts/`. **This RED — in the cluster, through the UI — is the entry ticket to Phase B.**


## Redeploying the fix and proving it (PHASE F)

The Verifier (`teammates/verifier.md`):

1. `mvn -B clean install` the **fixed** plugin, then **redeploy into the standing cluster** and restart the app nodes (rebuild the war + `docker compose up -d --build`, or restart the containers so the new classes load). If the cluster is not up (fresh run), generate + boot it first:
   ```bash
   bash ${LUTECEPOWERS_ROOT}/skills/lutece-scalability-v8/scripts/gen-test-site.sh \
        --local . --enable <plugin-names> --out e2e/.scalability-test
   ( cd e2e/.scalability-test && docker compose up -d )
   ```
2. Wait for the 3 apps ready + dbinit.
3. **READ THE DOCKER LOGS — ESSENTIAL, BEFORE the functional test.** Never trust a green-looking boot; `docker compose logs` and confirm, on every node:
   - the plugin-under-test's **own schema was deployed** — its changesets appear in the logs / `DATABASECHANGELOG`. If absent, look for `LiquibaseRunner files not managed by liquibase are <file>` → that `.sql` is **missing its `-- liquibase formatted sql` header** (see the `sql-liquibase` rule). A plugin whose SQL silently didn't deploy invalidates the whole test.
   - **no startup exception / stack trace / `WELD-` / `SRCFG` / `Failed to serialize`**. In particular Hazelcast forms **two distinct member groups** (HTTP-session vs JCache, different class loaders) — they MUST have different `cluster-name`s, else partition migration fails with `Failed to serialize ...MigrationOperation` (see harness `hazelcast.xml` / `hazelcast-session.xml`).
   - `cluster-verify.sh` health (3 instances, shared DB, single Liquibase migration, both Hazelcast groups formed, session replicated):
   ```bash
   LOCK_TABLE=<plugin>_lock bash ${LUTECEPOWERS_ROOT}/skills/lutece-scalability-v8/scripts/cluster-verify.sh e2e/.scalability-test
   ```
4. **Re-run the A.4.2 UI e2e — it must now be GREEN. This IS the proof.** Run the **exact same** browser-driven e2e that went RED on the baseline, unchanged, against the redeployed cluster. It drives the *real* functional operation **concurrently through the UI over nginx** (requests hit different nodes with replicated sessions) — e.g. N concurrent clients book/reserve/consume the same limited resource (capacity M) → **exactly M succeed, never more**, counters never drift; N concurrent edits of the same page → no lost write, invariant intact. **Drive through the UI; assert against the DB** — the DB is the source of truth (never trust the UI's rendered text as the assertion), but the *actions* must go through the UI/nginx, not a raw SQL/API shortcut. A pass = that same e2e, RED before the fix, is GREEN after, end-to-end (real Java, real HTTP, real multi-node).
   - **If the flow is a stateful multi-step wizard (`@SessionScoped`), this also proves session replication of the CDI bean** — the single thing `cluster-verify.sh` cannot prove (its admin-auth check is a false-green; see sections 6 and 7 of the `cluster-verify.sh` output). The flow completing end-to-end while its steps are served by *different* nodes (log the upstream per step) IS the proof. If a step returns "session lost" / "form no longer valid" while a different node served the previous step → it's the Liberty `writeContents` default (see `patterns/serialization-session.md`), and the harness e2e gotchas in `harness/README.md` apply (expect_navigation, cookie overlay, domcontentloaded).
5. **FAILOVER proof (resilience — kill a node mid-flow).** Round-robin proves the state *crosses* live nodes; a node-kill proves it *survives the death* of the node that created it (Hazelcast backup promotion) — a distinct axis. For a stateful flow: reach the mid-point (e.g. the recap, state now in session), identify the node that served it (`X-Upstream`), **`docker kill` that node**, then complete the operation → it must finish on a SURVIVOR (nginx skips the dead upstream; retry once, the first request may hit it before nginx marks it down) and the result must be in the DB. The killed node's peers should log only "removing connection to [dead]" warnings, no errors. Restart it afterwards and confirm it rejoins the mesh. (Reference artifact: a plugin-specific `e2e/failover_*.py` driving its real flow.)
6. **READ THE DOCKER LOGS AGAIN — ESSENTIAL, AFTER the test.** Re-`docker compose logs` and confirm the concurrent load produced **no 500 / no exception / no serialization or lock error**. A test that "passed" while the logs were full of errors did not pass.
7. On FAIL, route the fix to the responsible teammate and re-run.
8. Teardown: stop the containers to free resources (`docker compose down` — omit `-v` if you want the DB state kept for inspection). **KEEP all generated files on disk** (the cluster dir + the `e2e/` UI tests are the deliverable) — see the artifact-retention rule below. Stop any throwaway smoke-check DB the agent may have spun up.

