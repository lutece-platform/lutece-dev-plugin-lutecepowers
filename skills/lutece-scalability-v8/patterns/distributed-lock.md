# Pattern — Concurrency on a contended resource (CAS vs distributed lock) & ID generation

> The most critical axis for any plugin managing a **contended resource**: slots, quotas, stock, counters. Reference: `lutece-form-plugin-forms` (`FormService.saveFormUnderQuotaLock`, `LockDAO`/`forms_lucene_lock`). Forbidden everywhere: `synchronized`, `ReentrantLock`, `Collections.synchronized`, in-memory counter — they **do not cross the JVM boundary**.

## Choose the primitive by the data model (decide this FIRST)
Two correct, cluster-safe primitives. Both rest on the same atomic-conditional-UPDATE + rows-affected trick; pick by **how capacity is represented**:

| The resource exposes… | Use | Why |
|---|---|---|
| a **counter column** (`nb_remaining_places`, `stock`, `quota_left`) | **atomic CAS UPDATE** *(preferred)* | the guarded decrement IS the operation — lock-free, one statement, no lock table/TTL/heartbeat |
| only a **`COUNT(*)`** of rows (no counter to decrement) | **DB distributed lock** | you must serialise the "count → decide → insert" critical section explicitly |

> Don't reach for the distributed lock by default. forms locks because its quota is a `COUNT(*)` — there is nothing to decrement atomically. If your table has a counter, the CAS is strictly simpler and faster; the lock would be pure overhead.

## Primitive A — atomic compare-and-set on the counter (counter-based resources)
The InnoDB **row lock** taken by the UPDATE *is* the serialisation — no application lock needed.
```sql
-- "compare" = the WHERE guard, "set" = the decrement, atomic = single statement
UPDATE <plugin>_slot
   SET nb_remaining_places = nb_remaining_places - ?,
       nb_places_taken     = nb_places_taken + ?
 WHERE id_slot = ? AND nb_remaining_places >= ?;     -- rowCount==1 => booked ; 0 => full
```
```java
int n = daoUtil.executeUpdate();           // or check getReturnedRowCount()
if (n == 0) throw new SlotFullException();  // guard failed: another node took the last place
```
- ⚠️ **Never** split into `SELECT remaining; if(ok) UPDATE` — that read-modify-write has a TOCTOU race (another node slips in between). The guard MUST live inside the UPDATE's `WHERE`.
- No special config: default InnoDB (row-level locking) + a single statement is enough. No isolation tuning, no lock table.
- Symmetric release on cancel: `SET remaining = remaining + ?, taken = taken - ? WHERE id = ?`.

## Anti-pattern (single-instance, breaks in a cluster)
```java
private static final ConcurrentMap<Integer, Lock> _locks = new ConcurrentHashMap<>();   // JVM-local map
Lock l = _locks.computeIfAbsent(idSlot, k -> new ReentrantLock());
l.lock(); try { /* check capacity then decrement */ } finally { l.unlock(); }
```
Each JVM has its own map → two nodes book the same slot → **double-booking**.

## Primitive B — DB distributed lock (COUNT(*)-based resources)

**Match the lock to the critical section's lifetime — decide B1 vs B2 FIRST:**

| Critical section | Primitive | Why |
|---|---|---|
| **short** — a few statements inside ONE request/transaction (e.g. `MAX+1` → set-not-current → insert; count → decide → insert) | **B1 — transactional row lock (`SELECT … FOR UPDATE`)** | held only for the tx, **auto-released on commit/rollback — including on node crash** (the DB rolls back). No TTL, no heartbeat, no orphan-lock failure mode. Prefer this. |
| **long / cross-request** — a single-writer role that outlives one request and whose holder could die mid-work (daemon, Lucene indexer, batch) | **B2 — TTL lease lock (forms `LockDAO`)** | needs `expired_date` + heartbeat so a dead holder's lock eventually frees. Only here is the TTL machinery justified. |

> Don't copy the forms TTL lease onto a short section: a crashed holder would block the resource until the TTL expires, and you'd carry heartbeat/uuid code for nothing. Conversely, `SELECT … FOR UPDATE` can't guard a role that spans many requests (the tx can't stay open). The forms `LockDAO` is a **lease for the indexer**, not a generic lock — pick by lifetime, not by familiarity.

### B1 — transactional row lock (short critical section)
Lock the **existing row** the operation is scoped to (the entity being edited, the slot being booked) — often **no lock table is needed**. All statements run on the transaction's connection (Lutece binds it per-thread), so the `FOR UPDATE` lock holds until commit and serialises concurrent writers to that row **cluster-wide** (shared DB), while different rows don't block each other.
```java
TransactionManager.beginTransaction( plugin );
try {
    _dao.lockEntity( entityId, plugin );          // SELECT <pk> FROM <table> WHERE <pk>=? FOR UPDATE
    // ... the short critical section: read-decide-write, all on this tx ...
    TransactionManager.commitTransaction( plugin );
} catch ( Exception e ) {
    TransactionManager.rollBack( plugin );        // lock released here too (and on crash)
    throw new AppException( e.getMessage(), e );
}
```
Reference: `TransactionManager` in `lutece-core` (`fr.paris.lutece.util.sql`); usage in forms `FormResponseService`. Empirically: N concurrent writers on the same row → exactly N ordered writes, invariant intact (vs. lost writes / broken invariant without the lock — reproduce it, see SKILL Phase A.4).

### B2 — TTL lease lock (long-running single writer) — forms `LockDAO`
**Lock table** (one row = one named lock):
```sql
CREATE TABLE IF NOT EXISTS <plugin>_lock (
  lock_name     varchar(80)  NOT NULL,   -- e.g. 'reservation.slot.42'
  instance_name varchar(80),             -- holder = hostname-pid
  is_locked     boolean,
  date_begin    timestamp,
  expired_date  timestamp,               -- TTL: past it, the lock is considered abandoned
  uuid          varchar(50),             -- unique holder token (anti-steal)
  PRIMARY KEY (lock_name)
);
```
**Atomic acquire** (the DB serialises the UPDATE on the PK row; clock is 100% DB-side → no clock skew):
```sql
UPDATE <plugin>_lock
SET instance_name=?, is_locked=true, date_begin=CURRENT_TIMESTAMP,
    expired_date={fn TIMESTAMPADD(SQL_TSI_SECOND, ?, CURRENT_TIMESTAMP)}, uuid=?
WHERE lock_name=? AND (is_locked=false OR expired_date < CURRENT_TIMESTAMP);   -- rowCount==1 => acquired
```
**Heartbeat** (renew only if still ours AND not expired; 0 rows => lock lost => ABORT) and **release** (by uuid) — see the forms `LockDAO`.

**Capacity decision = acquire → tx → RE-COUNT in DB under the lock → insert → commit → release**:
```
acquireLock("reservation.slot."+id, TTL=30s)   // bounded retries, backoff
  └─ tx.begin
       int taken = countTakenSlots(idSlot);     // live COUNT in DB = single source of truth
       if (taken >= capacity) throw new FullException();
       insertReservation(...);
     commit
  └─ finally releaseLock
```
**Under sustained contention: REFUSE rather than write without a guard.**

## Defense in depth — DB invariant (CHECK constraint)
When the resource has counters, add a `CHECK` so the **database itself** rejects any incoherent write — even from a future bug, a manual SQL fix, or a missed code path. The CAS/lock prevent the race; the CHECK guarantees the counters can never drift.
```sql
ALTER TABLE <plugin>_slot
  ADD CONSTRAINT chk_<plugin>_slot_capacity
  CHECK (nb_remaining_places + nb_places_taken = max_capacity);
```
- Use the **equality invariant** (`remaining + taken = capacity`), not `remaining >= 0`: it stays true even under deliberate overbooking (an admin shrinks capacity → `remaining` goes negative) — you check *coherence*, not positivity. Audit every write path preserves it before adding the constraint (reconcile existing rows first in the upgrade script).
- ⚠️ **Prerequisite**: `CHECK` is only **enforced** on **MariaDB ≥ 10.2.1** / **MySQL ≥ 8.0.16**. Before, the clause is parsed but **silently ignored** → the safety net is absent without warning. State this as a deployment prerequisite.

## Provisional "hold" (reservation held while the user fills a form)
Never a `ScheduledFuture`/`Timer` in the session (JVM-local, lost on restart, invisible to peers). Materialise it as a **DB row with an expiry timestamp** + a session token, recompute "potential remaining = remaining − active holds", and let a **daemon sweep expired rows** (a plain `DELETE WHERE expired_date < now` is idempotent — no distributed lock needed for the sweep). See `serialization-session.md`.

## ID generation
- ❌ `SELECT MAX(id)+1` → two reads of the same max → PK collision.
- ✅ DB auto-increment / sequence, **or** a `UNIQUE(idSlot, idUser)` constraint (double-booking becomes a duplicate-key), **or** serialise via the lock above.

## Daemons in a cluster
No node election in core → a daemon runs on **every** instance. Two valid options for a "run-once-cluster-wide" job:
1. **DB distributed lock** (the pattern above): take the lock at the top of `run()`, bail out otherwise. Self-contained, no extra dependency.
2. **`lutece-tech-plugin-quartz-scheduler`**, a site choice: it replaces the core daemon executor for the whole site and, with `quartzscheduler.cluster.enable=true`, runs a daemon once cluster-wide from a JDBC store when `quartzscheduler.daemon.<id>.disallowedClusterConcurrentExecution=true`. The plugin keeps a plain daemon and never declares Quartz itself (`rules/java-conventions.md`). Without it, the core `DaemonScheduler` (`ManagedScheduledExecutorService`) runs every daemon on every node, so a run-once job needs option 1.

## Rules
- DO: **counter → atomic CAS UPDATE** (preferred); short critical section → **B1 transactional `SELECT … FOR UPDATE`** on the scoped row (no lock table, auto-released on commit/crash); long single-writer → **B2 TTL lease** (forms `LockDAO`) with re-read under the lock, **granular** lock name (`...slot.<id>`), DB-side clock, TTL+heartbeat, release in `finally` + cleanup on shutdown, pre-create the lock row; add a `CHECK` invariant on counters; `UNIQUE` as last line of defence (double-click).
- DON'T: `synchronized`/`ReentrantLock`/lock map for shared state; in-memory counter; `SELECT MAX+1`; read-modify-write decrement without a guard; reach for a distributed lock when a counter CAS would do; **use a TTL lease (B2) for a short single-request critical section** (B1 is simpler and has no orphan-lock failure mode).
