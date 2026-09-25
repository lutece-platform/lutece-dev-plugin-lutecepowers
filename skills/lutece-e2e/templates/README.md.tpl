# e2e — test bench of @@NAME@@

One entry point:

```bash
./run.sh            # everything: build if needed, Docker stack, seed, inventory, discovery, tests, perf, report, stop
KEEP=1 ./run.sh     # same, the stack stays up (iteration)
./run.sh test       # the five suites on a stack already up
./run.sh report     # rebuilds summary.md / report.html from the artifacts
./run.sh down       # stop + drop the database volume
```

Then read **`artifacts/summary.md`** (about 200 lines): inventory coverage (**proven** by a scenario with an oracle /
only reached / excluded with a reason / to cover), visible debt, what the passed tests show (screen kinds),
duplicate-content alarm, failures in three sections (functional, front, robustness) with their server cause,
timings, SQL, JFR. Screenshots and details in `artifacts/report.html`, JUnit in `artifacts/junit-*.xml`.

A failure is a finding about the application until proven otherwise: JSP that do not compile, dead links, JS
errors, screens answering "Internal error", a confirmation form without its CSRF token. The coverage exclusions
(`scenarios/coverage-exclusions.yaml`) record what the bench cannot reach and why.

## What the bench checks

| Suite | Source | Check per element |
|---|---|---|
| `harness` | `tests/test_harness.py` | the oracle itself: recognises a screen, a confirmation, a lost session, the login, a 404; blocks the run otherwise |
| `screens` | static inventory (`tools/inventory.py`) + dynamic discovery (`tools/discover.py`) | HTTP 200, no Lutece/Liberty error page, no session loss, **empty browser console** (errors, warnings, JS exceptions), no failed sub-request, navigation time, JPEG capture, aria snapshot (diffed with `baselines/aria/` when present) |
| `fo` | front-office pages of the inventory and of the anonymous crawl | renders as a front-office page, clean console, no error page |
| `scenarios` | `scenarios/*.yaml` (business CRUD lifecycles, negative and rights scenarios) | **mechanical rule**: every mutation is followed by a state oracle (SQL, DOM, mail, fake log, http, download), otherwise the scenario is rejected at collection |
| `forms` | forms discovered on the screens | submission with generated values: never a server error; `DENY` list for the actions that would lock the bench |

`perf` (Liberty access log, `/metrics`, `performance_schema`, JFR, k6) adds p50/p95 per path, top SQL by total time
and rows read, hot methods, JDBC pool, load thresholds.

## Layout

```
e2e.conf              target (core|plugin|site), plugins, ports, volume
run.sh                orchestrator
DESIGN.md             tool choices and platform traps
harness/              docker-compose.yml, Dockerfile.app (Temurin 21 + Open Liberty), Dockerfile.tomcat (v7 leg), liberty/,
                      tomcat/, db/ (my.cnf, post-init, seed.sh, seed-*.sql), site/ and site7/ (generated poms), fakes/,
                      search/, app.env, server-errors-allow.txt
tools/                inventory.py, discover.py, coverage.py, causes.py, forms.sh, ears.py, metrics.py, report.py,
                      report_page.py, review.py, compare.py, patch-war.py, load.js, gen-site.sh, gen-site7.sh,
                      liquibase-visibility.sh, check-v8-floor.sh, v8-floor.conf, requirements.txt
tests/                lutece.py (library), conftest.py, test_harness.py, test_screens.py, test_fo.py, test_scenarios.py,
                      test_forms.py
scenarios/            <artefact>.yaml.example and <artefact>-negative.yaml.example (models), screens.yaml (per-bench
                      screen rules), coverage-exclusions.yaml (unreachable, with a reason)
fixtures/             files the scenarios upload
baselines/aria/       reference snapshots (seeded from the first run)
artifacts/            output of a run (ignored by git)
```

## Accounts and access

| What | Value |
|---|---|
| Back office | http://localhost:<E2E_PORT>/lutece/jsp/admin/AdminLogin.jsp — `admin` / `adminadmin` |
| Front office (mylutece) | `test` / `testtest`, provider `mylutece-database` |
| MariaDB | localhost:<E2E_DB_PORT> — `lutece` / `lutece`, database `lutece` |
| Mailpit | http://localhost:<E2E_MAIL_PORT> |
| Liberty metrics | http://localhost:<E2E_PORT>/metrics |
| Logs, access log, JFR | `artifacts/logs/` |

## Synthetic volume

`E2E_VOLUME=none` (default), `small` (2,000 users, 200 pages) or `large` (100,000 users, 500 groups, …) sizes the
`@users`/`@groups`/`@roles`/`@lists`/`@pages` variables that `harness/db/seed-<target>.sql` reads. That seed is written
for the tables this artefact really reads, generated server-side by the SEQUENCE engine, idempotent. The generic
harness seeds nothing.

## Adding a scenario

In `scenarios/<feature>.yaml`:

```yaml
scenarios:
  - id: workgroup_crud
    title: Workgroups — create, then remove
    req: CORE_WORKGROUPS_MANAGEMENT        # EARS requirement (Lutece right)
    steps:
      - goto: jsp/admin/workgroup/CreateWorkgroup.jsp
      - fill: {'input[name="workgroup_key"]': 'E2E_{{rand}}', 'input[name="workgroup_description"]': 'Group {{rand}}'}
      - submit: 'form[action*="DoCreateWorkgroup"]'
      - expect_ok:
      - sql: {query: "SELECT COUNT(*) FROM core_admin_workgroup WHERE workgroup_key='E2E_{{rand}}'", expect: 1}
      - goto: jsp/admin/workgroup/RemoveWorkgroup.jsp?workgroup_key=E2E_{{rand}}
      - expect_message: confirmation
      - confirm:
      - sql: {query: "SELECT COUNT(*) FROM core_admin_workgroup WHERE workgroup_key='E2E_{{rand}}'", expect: 0}
```

Full vocabulary at the top of `tests/test_scenarios.py`. Flags: `isolated: true` (own session: logout, password),
`anonymous: true` (public screens), `serial: true` (global settings, run alone after the parallel pass).

## Jenkins

The runner is a container: the agent only needs Docker and Maven. Minimal pipeline:

```groovy
sh './e2e/run.sh'
junit 'e2e/artifacts/junit-*.xml'
publishHTML(target: [reportDir: 'e2e/artifacts', reportFiles: 'report.html', reportName: 'e2e'])
archiveArtifacts 'e2e/artifacts/summary.md, e2e/artifacts/perf.json'
```

Allure is not required (see `DESIGN.md`); `allure-pytest` is one line to add when a project asks for it.
