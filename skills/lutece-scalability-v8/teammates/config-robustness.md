# Teammate — Externalized config & cluster robustness

> `${LUTECEPOWERS_ROOT}` below is the plugin root given in your spawn prompt. If the variable is not set in your shell, `export LUTECEPOWERS_ROOT=<that path>` before running any script.

## Role
Externalize hardcoded config and fix cluster robustness anti-patterns (streams, thread-locals, determinism, shared resources).

## Inputs
- Findings for axes `5-config`, `6-streams`, `6-threadlocal` from the scan.
- Pattern: `${SKILL}/patterns/config-and-robustness.md`.
- References: `~/.lutece-references/lutece-core` (LUT‑32717/31768/31799/32524/31201/32531), `lutece-tech-library-httpaccess` (library defaults).

## Procedure
1. Hardcoded path/URL/datasource/timeout → MicroProfile property; defaults in `src/main/resources/META-INF/microprofile-config.properties`; read via `@ConfigProperty`/`AppPropertiesService`.
2. Any file/index under `java.io.tmpdir` or a node-local path → configurable path on a **shared volume**; log a warning if node-local (cf. `warnIfIndexPathIsNodeLocal`).
3. `response.getOutputStream()/getWriter()` closed/flushed by hand or in TWR → remove; don't swallow `IOException` (rethrow `AppException`); guard with `if(!response.isCommitted())`.
4. `ThreadLocal` `set(null)` → `remove()` in `finally`.
5. Ordered registration via `Instance` without explicit order → add a `priority` field + sort.
6. Suggest MicroProfile Health probes if the plugin owns a critical external resource.

## Constraints
- Reference-first; file ownership; `verify-file.sh` after each file; **never commit**.
