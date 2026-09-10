---
name: lutece-scalability-v8
description: "Use after a v7 to v8 migration to make a Lutece plugin horizontally scalable and prove it: scans scalability anti-patterns, fixes them, deploys a real 3-instance cluster (Liberty, MariaDB, nginx, Hazelcast) and verifies through UI end-to-end tests. Triggers on 'scalability', 'cluster', 'multi-instance', 'horizontal scaling'."
---

# Lutece Scalability v8 — Consolidate & Prove (Agent Teams)

## Purpose

Takes a **v8-compliant** Lutece plugin and makes it **scalable for multi-instance/cluster** deployment, then **proves it empirically** in a real 3-instance cluster.

Unlike migration (largely mechanical), scalability is mostly **semantic** — it needs judgment. So this skill is: **scan (detect) → triage (drop false positives) → reproduce (observe each real defect — RED) → fix (intelligent teammates + patterns) → PROVE (same reproduction, now GREEN, in the real cluster)**. The empirical red→green loop is the heart of the skill: **a scanner finding is never a bug until it has been observed failing, and a fix is never "done" until that same observation turns green.**

**Prerequisites:** a harness that can dispatch subagents or teammates. On Claude Code, Agent Teams is experimental and needs `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`; plain subagents also work. Without any dispatch tool, run the teammates yourself sequentially in the dependency order below (see `using-lutecepowers`, section Subagents and teams). Also required: Docker + Compose; JDK 21; Maven; access to the Lutece Maven repos (or a populated `~/.m2`).

The 7 scalability axes (observed in core/forms, the architect's work) are documented under `patterns/`. Always read the real references in `~/.lutece-references/` before writing any new pattern.

---

## PHASE A — Scan (Lead executes directly)

### A.0 — Verify v8 compliance (FIRST)
Check that the plugin is **already v8-compliant**:
```bash
mvn -B clean verify -DskipTests
```
If the build **FAILS**, stop. Ask the user: *"The plugin does not build on v8. Please run `lutece-migration-v8-agent-teams` first, then re-run this skill."* — scalability work cannot begin until migration is complete and the code compiles.

If the build **SUCCEEDS**, proceed to A.1.

### A.1 — Scope the analysis (ASK the user)
Scalability defects often live in a plugin's **modules or related plugins**, not the core repo — and the highest-risk one (a reminder/notification **daemon** that would fire once per node) typically sits in a module. But those modules/dependents may be in **separate repositories**, possibly across different hosts/orgs (GitHub `lutece-platform`, `lutece-secteur-public`, an internal GitLab, …). The agent **cannot reliably discover them** and must NOT guess from a naming convention or assume they are local.

So, before scanning, **ask the user**: *"Should the analysis cover only this plugin, or also its modules / related plugins? If so, where are they (local paths, or repos to clone)?"* Then scan **each confirmed target** with `scan-scalability.sh <dir>` and aggregate the results. If the user says "this plugin only", proceed — but state in the final report that modules were out of scope.

### A.2 — Run the scanner (on EACH target from A.1)
```bash
mkdir -p .scalability
# the plugin itself:
bash ${LUTECEPOWERS_ROOT}/skills/lutece-scalability-v8/scripts/scan-scalability.sh . > .scalability/scan.json
# and one file per additional module/related repo the user confirmed in A.0:
# bash .../scan-scalability.sh <module-dir> > .scalability/scan-<module>.json
```

### A.3 — Show the summary
Read `.scalability/scan.json` and present, per axis, the count + sample files. Flag the **high-risk** axes:
- `1-locks` / `1-id` — contended resource (slot, quota, stock). Highest priority. Pick the primitive by the data model: **counter column → atomic CAS UPDATE** (preferred, lock-free); **`COUNT(*)` → DB distributed lock**. Don't lock by default (`patterns/distributed-lock.md`).
- `3-singleton` / `3-cdi-static` — mutable static state diverging across nodes.
- `2-session` / `2-nonserial` — non-serializable / heavy session state, `Future`/`Timer` in session.
- `2-sessionscoped` — stateful `@SessionScoped`/`@ConversationScoped` beans: whole graph `Serializable` + passivation test, **and** the cluster MUST run Liberty `writeContents="GET_AND_SET_ATTRIBUTES"` — the default does not replicate in-place bean mutations, invisible until a node switch (`patterns/serialization-session.md`).
- `4-cache` — JVM-local cache.
- `5-config` / `6-streams` / `6-threadlocal` — hardcoded config, container streams, thread-locals.

A finding count is a **review pointer**, not an auto-fix list — scalability fixes require judgment.

---

## PHASE A.4 — Triage & empirical confirmation (RED-before-fix) — Lead executes directly

**The scanner over-reports. Most findings are false positives.** Never plan a fix on a raw count. For **every** finding, first read the real code and assign a verdict; then, for each *genuine* defect, **observe it failing** before anyone touches it. No fix on an unobserved bug.

### A.4.1 — Triage: drop false positives (with a stated reason)
Common false positives (all observed in real plugins) — classify and discard, recording the reason in the report:

| Axis | Looks like | Why it is usually a FALSE POSITIVE |
|------|-----------|-------------------------------------|
| `3-singleton` | `getInstance()` calls | Calls to **core** services (`SecurityService`, `PluginService`, `AppPropertiesService`…) are standard. Only an **own** `getInstance()` returning an instance that holds **mutable static state** is a defect. |
| `3-singleton` | `private static X _dao = CDI.current().select(...).get()` | The **Home pattern** — an effectively-immutable reference resolved once at class-load. Not divergent state. |
| `4-cache` | `new HashMap<>()` / `new ArrayList<>()` | **Method-local** collections are per-request stack variables, GC'd, never shared across nodes. Only a **field**-level or `static` mutable collection is state. |
| `4-cache` | a service extending `AbstractCacheableService` | Already JCache-backed → **cluster-capable** when Hazelcast is on. The concern is **invalidation completeness + proving distribution** (Phase F), *not* a rewrite. |
| `2-session` | `List<String>` / other `Serializable` light values in session | Fine. Only **non-`Serializable`** or **heavy/`Future`/`Timer`/`Thread`** session state is a defect. |
| `1-id` | `SELECT MAX(...)` | A defect **only** when the value becomes a contended business key. A PK filled by `RETURN_GENERATED_KEYS` (DB auto-increment) is fine. |

Also check the **highest-risk axis the scanner cannot see**: a **daemon** (`extends AbstractDaemon`, `@Scheduled`, plugin.xml `<daemon>`) that would fire **once per node** — grep for it explicitly. If none, say so.

### A.4.2 — Reproduce each genuine defect **in the cluster, through the UI** (capture a RED trace) — MANDATORY before Phase B

**The empirical proof of this skill is a browser-driven end-to-end test against the real 3-node cluster — full stop.** A scalability finding is confirmed only when the *real user flow*, driven through the *real UI* (Playwright via nginx), makes the invariant break on the **unfixed baseline**. This is non-negotiable and it is the same test that must later turn GREEN.

**Stand the cluster up NOW — do not wait for Phase F.** The cluster is built once, on the pre-fix baseline, and lives through the whole red→green loop (repro RED → fix → redeploy → repro GREEN → failover). Concretely, in this phase:

1. Generate + boot the cluster on the **current, unfixed** code (`gen-test-site.sh` → `docker compose up -d`; see Phase F.1–F.4 for the mechanics and the mandatory docker-log read). The baseline must be truly unfixed and fresh: `docker compose down -v` any stale `lutece-*` cluster, and `git stash` any uncommitted fix (pop it back in Phase B). If the flow needs a logged-in FO user, enable the mylutece block in the generated `pom.xml` + the FO seed in `db/post-init.sql` (boot gotchas: `harness/README.md` § "Boot & seed").
2. **Smoke-check logins before writing the e2e** — BO `admin/adminadmin`, plus the seeded FO user if any.
3. **Write the e2e that drives the real user flow** for each confirmed defect and store it under the plugin's `e2e/` (it is a durable, committable artifact — see retention rule). **Copy `harness/e2e_skeleton.py`** into the plugin's `e2e/` and adapt the CONFIG block, the arm/submit steps to the actual contended flow (often a form submit, but it can be any UI action — AJAX button, wizard step, link) and the RED condition — do not rewrite the scaffolding (login FO/BO, X-Upstream capture, concurrent gather, DB-via-docker-exec, log scan are already correct there). It MUST:
   - go **through the UI over nginx** (round-robin, no sticky) — real login, real navigation, real form submit — exactly what a user does; log `X-Upstream` per request to prove steps hit **different nodes**;
   - drive the contended operation **concurrently** (N real browser/API clients on one resource) — e.g. N users editing/saving the same page at once;
   - **assert against the DB** (source of truth), and read the **docker logs** for the server-side evidence (constraint violation, lost write, broken invariant, exception).
4. Run it on the baseline → it must be **RED** (invariant broken). Persist the run output. **This RED — in the cluster, through the UI — is the entry ticket to Phase B.**

> **What does NOT count as the RED (or the GREEN):** a raw-SQL/JDBC replay, a direct DAO/service call, a `pg.request.post` that bypasses the UI, a unit test. These may be used *privately by the agent as a 10-second smoke-check to orient itself*, but they are **never** the proof, **never** presented in the report as RED/GREEN, and **never** a substitute for the UI e2e. If you find yourself proving scalability with a standalone SQL script, stop — that is the exact shortcut this rule forbids.

> A genuine finding that **cannot be reproduced through the UI in the cluster** is downgraded to *theoretical* and noted — do not spend a teammate on it. (Rare pure-infra concerns — e.g. Hazelcast cluster formation — are checked by `cluster-verify.sh`, not by a user flow; state which is which.)

The fix's job is to turn **that exact e2e** from RED to GREEN.

---

## PHASE B — Plan (Lead executes directly)

Plan fixes for the **confirmed (reproduced) defects only** — never for raw scan counts. Map confirmed defects → axes → teammates. Decide how many teammates (1 per non-empty axis group; merge small ones). Write a short plan per teammate listing the files it owns (no overlap — file ownership) **and the RED reproduction its fix must turn GREEN.**

---

## PHASE C — Spawn Teammates

On Claude Code with Agent Teams, switch to **Delegate Mode**. From here, orchestrate only — never modify files. On a harness without dispatch, execute the teammates below yourself, one after the other, in the Phase D order.

Spawn the teammates whose axes have findings:

| Teammate | Instructions | Axes |
|---|---|---|
| Locks & Concurrency | `teammates/locks-concurrency.md` | `1-locks`, `1-id` |
| CDI scopes & singletons | `teammates/cdi-scopes.md` | `3-singleton`, `3-cdi-static`, `4-cache` |
| Serialization & session | `teammates/serialization-session.md` | `2-session`, `2-nonserial` |
| Config & robustness | `teammates/config-robustness.md` | `5-config`, `6-streams`, `6-threadlocal` |
| Verifier | `teammates/verifier.md` | builds + runs the cluster test |

### Spawn template
Replace `${LUTECEPOWERS_ROOT}` by the literal absolute path from your session context before sending; a teammate does not see that context.
```
LUTECEPOWERS_ROOT=${LUTECEPOWERS_ROOT} (export it in your shell before running any script)
Read your instruction file at ${LUTECEPOWERS_ROOT}/skills/lutece-scalability-v8/teammates/<file>.md.
Your findings are in .scalability/scan.json (your axes only). Own only your assigned files.
Patterns: ${LUTECEPOWERS_ROOT}/skills/lutece-scalability-v8/patterns/ — load only what you need.
Reference-first: ALWAYS read ~/.lutece-references/ (especially lutece-form-plugin-forms and lutece-core) before writing any pattern.
Run verify-file.sh after each file you change. Never commit.
```

---

## PHASE D — Dependencies

```
CDI scopes & singletons ─┐
Serialization & session ─┤ (run first — locks/config may depend on the new beans)
                         │
   Locks & Concurrency ──┤ (DB lock often uses a CDI-managed LockDAO/Home)
   Config & robustness ──┘
                         │
                         └──→ Verifier: redeploy fix into the ALREADY-STANDING cluster (built in A.4.2)
                              and re-run the RED UI e2e → GREEN + failover (after ALL fixers complete)
```
> The cluster is stood up once in **A.4.2** (for the RED baseline) and reused here for the GREEN — it is not first created in Phase F.

---

## PHASE E — Monitor

- Check task progress periodically.
- A teammate stuck > 5 min → ask for status via mailbox.
- A teammate reports a blocker → investigate, advise, or reassign.

---

## PHASE F — Turn the RED e2e GREEN on the cluster (Verifier)

**The cluster is already standing from Phase A.4.2, and the UI e2e already went RED on the baseline.** Phase F's job is to **redeploy the fixed code into that same cluster and re-run the same UI e2e until it is GREEN**, then prove failover. Same cluster, same test, before → after. Do NOT prove the fix with anything other than that UI e2e (see A.4.2's "what does NOT count").

The Verifier (`teammates/verifier.md`):
1. `mvn -B clean install` the **fixed** plugin, then **redeploy into the standing cluster** and restart the app nodes (rebuild the war + `docker compose up -d --build`, or restart the containers so the new classes load). If the cluster is not up (fresh run), generate + boot it first:
   ```bash
   bash ${LUTECEPOWERS_ROOT}/skills/lutece-scalability-v8/scripts/gen-test-site.sh \
        --local . --enable <plugin-names> --out e2e/.scalability-test
   ( cd e2e/.scalability-test && docker compose up -d )
   ```
2. Wait for the 3 apps ready + dbinit.
3. (kept as step 4 below — read the logs before re-running the e2e.)
4. **READ THE DOCKER LOGS — ESSENTIAL, BEFORE the functional test.** Never trust a green-looking boot; `docker compose logs` and confirm, on every node:
   - the plugin-under-test's **own schema was deployed** — its changesets appear in the logs / `DATABASECHANGELOG`. If absent, look for `LiquibaseRunner files not managed by liquibase are <file>` → that `.sql` is **missing its `-- liquibase formatted sql` header** (see the `sql-liquibase` rule). A plugin whose SQL silently didn't deploy invalidates the whole test.
   - **no startup exception / stack trace / `WELD-` / `SRCFG` / `Failed to serialize`**. In particular Hazelcast forms **two distinct member groups** (HTTP-session vs JCache, different class loaders) — they MUST have different `cluster-name`s, else partition migration fails with `Failed to serialize ...MigrationOperation` (see harness `hazelcast.xml` / `hazelcast-session.xml`).
   - `cluster-verify.sh` health (3 instances, shared DB, single Liquibase migration, both Hazelcast groups formed, session replicated):
   ```bash
   LOCK_TABLE=<plugin>_lock bash ${LUTECEPOWERS_ROOT}/skills/lutece-scalability-v8/scripts/cluster-verify.sh e2e/.scalability-test
   ```
5. **Re-run the A.4.2 UI e2e — it must now be GREEN. This IS the proof.** Run the **exact same** browser-driven e2e that went RED on the baseline, unchanged, against the redeployed cluster. It drives the *real* functional operation **concurrently through the UI over nginx** (requests hit different nodes with replicated sessions) — e.g. N concurrent clients book/reserve/consume the same limited resource (capacity M) → **exactly M succeed, never more**, counters never drift; N concurrent edits of the same page → no lost write, invariant intact. **Drive through the UI; assert against the DB** — the DB is the source of truth (never trust the UI's rendered text as the assertion), but the *actions* must go through the UI/nginx, not a raw SQL/API shortcut. A pass = that same e2e, RED before the fix, is GREEN after, end-to-end (real Java, real HTTP, real multi-node).
   - **If the flow is a stateful multi-step wizard (`@SessionScoped`), this also proves session replication of the CDI bean** — the single thing `cluster-verify.sh` cannot prove (its admin-auth check is a false-green; see §6/§7). The flow completing end-to-end while its steps are served by *different* nodes (log the upstream per step) IS the proof. If a step returns "session lost" / "form no longer valid" while a different node served the previous step → it's the Liberty `writeContents` default (see `patterns/serialization-session.md`), and the harness e2e gotchas in `harness/README.md` apply (expect_navigation, cookie overlay, domcontentloaded).
6. **FAILOVER proof (resilience — kill a node mid-flow).** Round-robin proves the state *crosses* live nodes; a node-kill proves it *survives the death* of the node that created it (Hazelcast backup promotion) — a distinct axis. For a stateful flow: reach the mid-point (e.g. the recap, state now in session), identify the node that served it (`X-Upstream`), **`docker kill` that node**, then complete the operation → it must finish on a SURVIVOR (nginx skips the dead upstream; retry once, the first request may hit it before nginx marks it down) and the result must be in the DB. The killed node's peers should log only "removing connection to [dead]" warnings, no errors. Restart it afterwards and confirm it rejoins the mesh. (Reference artifact: a plugin-specific `e2e/failover_*.py` driving its real flow.)
7. **READ THE DOCKER LOGS AGAIN — ESSENTIAL, AFTER the test.** Re-`docker compose logs` and confirm the concurrent load produced **no 500 / no exception / no serialization or lock error**. A test that "passed" while the logs were full of errors did not pass.
8. On FAIL, route the fix to the responsible teammate and re-run.
9. Teardown: stop the containers to free resources (`docker compose down` — omit `-v` if you want the DB state kept for inspection). **KEEP all generated files on disk** (the cluster dir + the `e2e/` UI tests are the deliverable) — see the artifact-retention rule below. Stop any throwaway smoke-check DB the agent may have spun up.

> **Reading the Docker logs before AND after the functional test is a mandatory step, not optional.** Most cluster-only defects (schema not deployed, class-loader serialization, session not replicating, swallowed exceptions) are invisible from HTTP status codes and only show in the logs.

A green run proves: 3 instances serving, shared DB, single Liquibase migration, both Hazelcast groups formed, session replicated across nodes (no sticky) **and surviving a node kill** (failover), and — for a contended resource — that concurrent real operations never exceed capacity (no double-booking / oversell), with clean logs throughout.

---

## PHASE G — Review & Final Gate

1. When build + `cluster-verify.sh` are green, spawn the **v8 reviewer** (`${LUTECEPOWERS_ROOT}/agents/lutece-v8-reviewer.md`) read-only; resolve FAIL items via teammates.
2. Present the summary: scan deltas, triage verdicts (false positives dropped + reason), **RED→GREEN** reproduction results, build result, `cluster-verify.sh` PASS/FAIL, files modified.
3. **KEEP all artifacts** (see retention rule) — do NOT delete `.scalability/`. Disband the team only. **STOP. Never commit** — the user decides (they may then commit the `.scalability/` report, the `e2e/` scripts and the generated cluster).

### Artifact retention — keep everything
The reproductions and the generated cluster ARE the deliverable (a reproducible proof). Nothing is auto-deleted:
- `.scalability/scan*.json` — the scan(s), kept as the report.
- `.scalability/repro/` — the RED-before-fix reproduction scripts + their captured red/green output.
- `.scalability/report.md` — a short written summary (triage verdicts, RED→GREEN, files changed) — write it here.
- `e2e/.scalability-test/` — the generated 3-node cluster (`gen-test-site.sh --out` target); kept so the proof is re-runnable.
- `e2e/*.py` — the **UI-driven** concurrent-load / failover drivers (Playwright) — the primary deliverable.

Only **ephemeral runtime** is torn down: running containers (`docker compose down`) and any throwaway smoke-check DB. Leave every file in place; the user decides what to commit and adds `.gitignore` entries if they don't want the generated cluster tracked.

---

## Strict Rules

1. **Run after migration** — the plugin must already be v8-compliant and compile.
2. **Triage before planning** — a raw scan count is never a fix list. Drop every false positive with a stated reason (Phase A.4.1) first.
3. **RED before fix, in the cluster, through the UI** — a finding is not a bug until observed failing **via a browser-driven e2e (Playwright over nginx) against the real 3-node cluster** on the unfixed baseline (Phase A.4.2), before any teammate touches code. Unreproducible through the UI ⇒ downgrade to theoretical, don't fix.
3b. **UI e2e is the ONLY proof** — RED and GREEN are the *same* UI e2e, before and after the fix. A raw-SQL/JDBC replay, a direct DAO/service call, or an API POST that bypasses the UI is **never** the proof and never appears as RED/GREEN in the report — at most a private throwaway smoke-check. If you're proving scalability with a standalone script, you're doing it wrong.
4. **Delegate mode** after Phase B — the Lead orchestrates only.
5. **Reference-first** — copy the real mechanics from `~/.lutece-references/` (forms `LockDAO`/`forms_lucene_lock`, core CDI/serialization), never invent. Match the primitive to the lifetime: a **short critical section** (a few statements) → transactional `SELECT … FOR UPDATE` (auto-released on commit/crash, no orphan); a **long single-writer lease** (daemon/indexer) → the forms TTL `LockDAO`. Don't copy the TTL lease onto a short section.
6. **File ownership** — one file, one teammate.
7. **Prove, don't assume** — a fix is "done" only when the **same UI e2e that was RED turns GREEN** in the cluster (+ failover). Test **with Hazelcast on** (ehcache hides serialization bugs).
8. **No `@Deprecated`** (house rule) — when removing `getInstance()`, delete it and migrate callers; do not leave a deprecated bridge.
9. **Keep all artifacts** — never auto-delete `.scalability/`, `e2e/` scripts, or the generated cluster. Tear down only running containers.
10. **NEVER commit.**

---

## Script Locations
All in `${LUTECEPOWERS_ROOT}/skills/lutece-scalability-v8/scripts/`:

| Script | Purpose | Used by |
|--------|---------|---------|
| `scan-scalability.sh` | Scan 7-axis anti-patterns → JSON | Lead (A) |
| `verify-file.sh` | Per-file residual anti-pattern check | Fixer teammates |
| `gen-test-site.sh` | Generate a disposable 3-node Docker cluster for the plugin | Verifier (F) |
| `cluster-verify.sh` | Empirical scalability proofs against the running cluster | Verifier (F) |

## Pattern Locations
All in `${LUTECEPOWERS_ROOT}/skills/lutece-scalability-v8/patterns/`:

| File | Axis |
|------|------|
| `distributed-lock.md` | 1 — concurrency, contended resources, ID generation |
| `cdi-scopes.md` | 3 — static singletons → CDI beans |
| `serialization-session.md` | 2 — Serializable session/cache, session state |
| `cache-distributed.md` | 4 — JSR-107 / Hazelcast distributed cache |
| `config-and-robustness.md` | 5 & 6 — MicroProfile config, streams, thread-locals, determinism |

## Test Harness
`${LUTECEPOWERS_ROOT}/skills/lutece-scalability-v8/harness/` — a proven, parameterized 3-instance cluster (Liberty + MariaDB + nginx + Hazelcast, Liquibase migrator pattern, sessionCache session replication). `gen-test-site.sh` templates it for the plugin under test. See `harness/README.md`.
