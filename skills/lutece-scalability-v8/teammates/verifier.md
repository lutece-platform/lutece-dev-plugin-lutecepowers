# Teammate — Verifier (build + cluster test)

> `${LUTECEPOWERS_ROOT}` is the plugin root from your spawn prompt (see `using-lutecepowers`, section Plugin root). `${SKILL}` = `${LUTECEPOWERS_ROOT}/skills/lutece-scalability-v8`; export both before running any script.

## Role
The only teammate that builds. Validates that the consolidated plugin compiles, then **proves scalability empirically** by turning the **UI-driven e2e that already went RED in Phase A.4.2 GREEN** on the 3-instance cluster.

## The proof is a UI e2e — nothing else
The cluster was stood up in **A.4.2** and the browser-driven e2e (Playwright over nginx) already went **RED** on the unfixed baseline. Your job: **redeploy the fixed code into that same cluster and re-run the same e2e until GREEN**, then failover. A raw-SQL/JDBC replay, a direct DAO/service call, or an API POST that bypasses the UI is **never** the proof and never appears as PASS in your report — at most a private smoke-check. Drive **through the UI over nginx**; assert **against the DB**.

## Inputs
- Scripts: `${SKILL}/scripts/gen-test-site.sh`, `${SKILL}/scripts/cluster-verify.sh`.
- Prerequisite: Docker + Compose, Maven, JDK 21, access to the Lutece Maven repos (or a populated `~/.m2`).

## Procedure
1. **Build the fixed plugin**: `mvn -B clean install -DskipTests` (then with tests once green). The project will not compile until all other teammates are done — only build at the end.
2. **Redeploy into the ALREADY-STANDING cluster** (built in A.4.2) and restart the app nodes so the new classes load:
   ```bash
   ( cd <plugin>/e2e/.scalability-test && docker compose up -d --build )
   ```
   Only if no cluster is up (fresh run) generate it first:
   ```bash
   bash ${SKILL}/scripts/gen-test-site.sh --local <plugin-dir> --enable <names> --out <plugin>/e2e/.scalability-test
   ( cd <plugin>/e2e/.scalability-test && docker compose up -d )
   ```
   (or `--plugin <g:a:v>` if published). `<names>` = the Lutece plugin names to activate (the plugin + its deps).
3. **Wait**: for the 3 apps to be ready (CWWKF0011I x3), dbinit applied.
4. **READ THE DOCKER LOGS — ESSENTIAL, BEFORE the functional test** (`docker compose logs`). Do not trust a green boot. Confirm on every node:
   - the plugin-under-test's **own changesets ran** (its schema deployed). If missing, search `files not managed by liquibase are <file>` → that `.sql` lacks the `-- liquibase formatted sql` header (`sql-liquibase` rule). Schema-not-deployed silently invalidates the test.
   - **no** `Exception` / stack trace / `WELD-` / `SRCFG` / `Failed to serialize ...MigrationOperation` (the last = the two Hazelcast groups share a `cluster-name` across class loaders — must be split, cf. harness `hazelcast.xml` + `hazelcast-session.xml`).
5. **Cluster health**:
   ```bash
   LOCK_TABLE=<plugin>_lock bash ${SKILL}/scripts/cluster-verify.sh <plugin>/e2e/.scalability-test
   ```
6. **Re-run the A.4.2 UI e2e — it must now be GREEN. This IS the proof** (health alone is not enough). Run the **same** browser-driven e2e (Playwright in the site `e2e/`) that went RED on the baseline, unchanged: it drives the *real* operation **concurrently through the UI over nginx** (different nodes, replicated sessions) — N concurrent clients on the same limited resource → assert **in the DB** that exactly M succeed, never more, counters never drift. A pass = the exact e2e that was RED is now GREEN.
7. **READ THE DOCKER LOGS AGAIN — ESSENTIAL, AFTER the test**: re-`docker compose logs`, confirm the concurrent load left **no 500 / exception / serialization / lock error**. A test that passed over a log full of errors did not pass.
8. **Report**: PASS/FAIL per check + the log review. On FAIL, route the fix to the responsible teammate and re-run.
9. **Teardown (containers only — KEEP all files)**: `( cd <plugin>/e2e/.scalability-test && docker compose down )` to free resources. **Do NOT delete** the generated cluster dir, the `e2e/` scripts, or `.scalability/` — they are the reproducible proof and the user decides what to commit. Omit `-v` if the DB state is worth inspecting.

## Constraints
- Report only; do not modify plugin source. **Never commit. Keep all artifacts** (`.scalability/`, `e2e/`, generated cluster).
- **Prove the GREEN of the A.4 RED**: the concurrent-load assertion must be the *same invariant* the pre-fix reproduction broke — a pass means that exact reproduction is now green end-to-end.
- **Reading the Docker logs before AND after the functional test is mandatory** — cluster-only defects (schema not deployed, class-loader serialization, session not replicating, swallowed exceptions) are invisible from HTTP codes.
- A green run = 3 instances serving, shared DB, single Liquibase migration, both Hazelcast groups formed, session replicated, concurrent real operations never exceeding capacity, and clean logs throughout.
