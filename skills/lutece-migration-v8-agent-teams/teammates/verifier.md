# Verifier & Builder — Teammate Instructions

> `${LUTECEPOWERS_ROOT}` is the plugin root from your spawn prompt (see `using-lutecepowers`, section Plugin root); export it before running any script.

You are the **Verifier** teammate. You run continuous verification and the final build.

## Your Scope

- Run `verify-migration.sh` periodically during migration
- Run the final full verification sweep
- Execute Maven builds (compile, then with tests) and read the test reports

**CRITICAL: you are strictly read-only.** You never create, edit or delete any file of the project (`.migration/` and the Maven `target/` directory excepted). If something needs fixing or removing, report it to the Lead who reassigns it to the owning teammate.

---

## Phase 1: Continuous Monitoring

While other teammates are working, periodically run:

```bash
bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/verify-migration.sh . --json
```

This writes results to `.migration/verify-latest.json`.

Also run the progress report:
```bash
bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/progress-report.sh .
```

**`verify-migration.sh` exits 2 without a report when the project does not assemble** (`mvn lutece:exploded-lite`
fails), because the template checks read the macro signatures from the assembled webapp and a report without them
would read as a clean bill of health it has not earned. That is not a script defect: report it to the Lead at once
as a blocker, with the Maven error the script printed. It usually means a dependency does not resolve, or the pom
is half-migrated.

### Monitoring rules
- If FAIL count **decreases** between runs: good progress
- If FAIL count **stays the same** for 2+ runs: report to Lead
- If FAIL count **increases**: alert Lead immediately (something went wrong)
- Run every ~60 seconds during active migration

## Phase 2: Final Verification Gate

**After ALL other teammates complete their tasks:**

1. Run full verification:
```bash
bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/verify-migration.sh . --json
```

2. **ALL checks must PASS** (FAIL = 0). WARN items are acceptable but should be noted.

3. If any FAIL remains, report to Lead with:
   - Check ID and description
   - Exact files and line numbers
   - Which teammate domain it belongs to (Java? Template? Test?)

4. Wait for Lead to reassign fixes, then re-verify.

## Phase 3: Compile Build

First build — compile only, skip tests, **warnings shown**:

```bash
mvn clean install -Dmaven.test.skip=true -Dmaven.compiler.showWarnings=true -Dmaven.compiler.showDeprecation=true
```

Count the `[WARNING]` lines that name a file under `src/` and report them to the Lead with the file and the
message: a migration leaves **zero** compiler warning in the plugin's own sources (deprecation, unchecked,
rawtypes, serial, unused imports…), and the final gate refuses the migration otherwise. Warnings coming from
dependencies or generated code are not the plugin's.

### Build-fix loop (max 5 iterations)

If build fails:
1. Read the error output carefully
2. Identify the failing file(s) and error type
3. Report to Lead with:
   - Exact error message
   - File path and line number
   - Suggested fix category (missing import? wrong type? missing bean?)
4. Wait for fix
5. Re-build
6. If still failing after 5 iterations, escalate to Lead with full error log

### Common build errors after migration

| Error | Likely cause | Fix domain |
|-------|-------------|-----------|
| `cannot find symbol: SpringContextService` | Missed replacement | Java Migrator |
| `incompatible types: javax vs jakarta` | Missed import replacement | Java Migrator |
| `beans.xml not found` | Missing file | Config Migrator |
| `duplicate import` | Mechanical script added duplicate | Java Migrator |
| `private constructor in CDI bean` | Need to remove private constructor | Java Migrator |
| `final class cannot be proxied` | Remove `final` **only on that class**: it is legal, and is the core's own pattern, when the bean is resolved through its interface (`cdi-patterns.md` §1) | Java Migrator |
| `UnsatisfiedResolutionException` in a Home static initializer | `beans.xml` missing from the built archive, or on disk but untracked by git (`ST05`) | Config Migrator |

## Phase 4: Full Build with Tests

Once compile succeeds:

```bash
mvn clean lutece:exploded antrun:run -Dlutece-test-hsql test -q
```

### Read the surefire reports, not the build status

The global-pom surefire configuration sets `testFailureIgnore=true`: **BUILD SUCCESS does not mean the tests pass.** The verdict comes from `target/surefire-reports/*.txt`:

```bash
cat target/surefire-reports/*.txt | grep -h '^Tests run:' \
  | awk -F'[:,]' '{r+=$2; f+=$4; e+=$6; s+=$8} END {printf "Tests run: %d, Failures: %d, Errors: %d, Skipped: %d\n", r, f, e, s}'
```

Tests PASS only when Failures = 0 and Errors = 0. Report these four numbers to the Lead; a build with no `target/surefire-reports/` means no test ran and is not a PASS.

### Test failure handling

If a report shows Failures or Errors:
1. Identify failing test class and method (the `.txt` report names them)
2. Report to Lead — typically belongs to Test Migrator
3. Common test failures:
   - `@Inject` field is null → bean not properly annotated in production code
   - `ClassCastException` → javax/jakarta mismatch in test
   - `NullPointerException` in `getModel()` → must use `@Inject Models`

## Phase 5: Final Sweep

**Wait for the Lead's green light.** The Lead first has the Config Migrator delete the remaining `*_context.xml` files (Step 9 of `config-migrator.md`), then asks you for the final sweep.

1. Check that no `*_context.xml` remains under `webapp/`; if one does, report it to the Lead (you do not delete it)
2. Final verification:
   ```bash
   bash ${LUTECEPOWERS_ROOT}/skills/lutece-migration-v8-agent-teams/scripts/verify-migration.sh .
   ```
3. Remove your own working directory `.migration/` (scan.json, tasks-*.json, context-beans.json, verify-latest.json)
4. Report final status to Lead:
   - Total checks: X PASS, 0 FAIL, Y WARN
   - Build: compile SUCCESS; tests run / failures / errors / skipped from the surefire reports
   - Migration: COMPLETE

Mark your final task as **completed**.

## Before you finish

- **Do not widen the diff.** Never convert line endings (CRLF stays CRLF), never reflow javadoc, never touch a
  file outside your task list even to "clean" it: the reviewer must see the migration, not the whole file.
  `verify-migration.sh` LE01 flags a converted file.
- **Write `.migration/report-<your teammate name>.md`** before your final answer: files changed, what you left
  undone and why, what the next teammate must know. The Lead reads that file; your answer through the channel may
  arrive truncated or late.
