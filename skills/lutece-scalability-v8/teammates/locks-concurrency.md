# Teammate — Locks & Concurrency

> `${LUTECEPOWERS_ROOT}` below is the plugin root given in your spawn prompt. If the variable is not set in your shell, `export LUTECEPOWERS_ROOT=<that path>` before running any script.

## Role
Replace any JVM-local coordination of a contended resource with the **right cluster-safe primitive** (atomic CAS on a counter, or a DB distributed lock), and make ID generation safe.

## Inputs
- Findings for axes `1-locks` and `1-id` from the scan (`.scalability/scan.json`).
- Pattern: `${SKILL}/patterns/distributed-lock.md`.
- Real references **to read first**: `~/.lutece-references/lutece-form-plugin-forms` → `LockDAO`, `forms_lucene_lock` (DDL under `src/sql/...`), `FormService.saveFormUnderQuotaLock`, `FormsInstanceId`.

## Procedure
1. For each class managing a shared resource (slot, quota, stock, counter): identify the critical section (check + write), and **choose the primitive by the data model** (`patterns/distributed-lock.md`):
   - **counter column exists** (`nb_remaining_places`, `stock`…) → **atomic CAS UPDATE** (preferred): `UPDATE … SET remaining=remaining-? WHERE id=? AND remaining>=?`; `rowCount==0` → typed `FullException`. No lock table. Add a `CHECK (remaining + taken = capacity)` invariant (deploy target MariaDB ≥ 10.2.1 / MySQL ≥ 8.0.16). **Done — skip steps 2-4.**
   - **capacity is a `COUNT(*)`** (no counter) → DB distributed lock (steps 2-4).
2. (lock path) Create the lock table `<plugin>_lock` (DDL + seed row(s)) in a plugin SQL script (with a Liquibase header if the project uses it).
3. (lock path) Implement a `LockDAO`/`LockManager` modeled on forms: atomic acquire (`UPDATE ... WHERE free OR expired`, `rowCount==1`), heartbeat, release by uuid, DB-side clock.
4. (lock path) Wrap the decision: `acquire → tx → RE-COUNT in DB → write → commit → release`; under sustained contention, **refuse** (typed exception), do not write without a guard.
5. IDs: remove any `SELECT MAX(+1)` → DB auto-increment/sequence or a `UNIQUE` constraint; add the unique constraint as a last line of defence (double-click).
6. "Run-once" daemon → take the lock at the top of `run()`.
7. **Add a concurrency test** for the lock: N threads (or an `ExecutorService` + `CountDownLatch`) racing to `acquireLock(sameName)` → assert exactly **one** succeeds, others get `LockException`/false; test expiry (TTL) reclaim and release. Note: there is **no upstream reference test** for the forms lock (it's untested in core/forms) — so this is a NEW test, and the **primary empirical proof remains the cluster harness** (`LOCK_TABLE=...` in `cluster-verify.sh`, which observes `is_locked=1` on a single instance under load).

## Constraints
- **Reference-first**: invent no pattern — copy the forms mechanics.
- Touch only the files in your partition (file ownership). Run `verify-file.sh` after each file.
- **Never commit.**
