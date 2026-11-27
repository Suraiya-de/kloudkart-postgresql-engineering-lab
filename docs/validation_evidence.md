# Validation Evidence

## Evidence status

Audit date: 2026-11-27.

No database connection or database test was run for this review. `psql` is not installed in the inspected workspace. The tracked repository contains no course schema, training dataset, `race_test.py`, query-plan output, benchmark log, or test log. The current target server's PostgreSQL version is therefore unknown. The optional Compose configuration specifies PostgreSQL 18, but that does not establish the version of the course server.

The repository's earlier README and technical-decision text recorded successful tests and plan inspection. Those statements are historical claims only: the original commands, conditions, output, duration and plans are unavailable here, so this document does not treat them as verified results.

| Item | Evidence available in this repository | Status |
|---|---|---|
| PostgreSQL version | Compose image is `postgres:18`; no result from the course server | Course server not verified |
| 400-buyer, 50-unit concurrency test | Previously claimed in `technical_decisions.md`; no script or output tracked | Not independently verified |
| 400 orders in 10 seconds | No timed result or workload log tracked | Not verified |
| Spending report row count | No database result tracked | Not measured |
| Monitoring check count | SQL source defines 12 `UNION ALL` checks | 12 defined statically; runtime view not executed here |
| Report `EXPLAIN ANALYZE` and before/after timings | No plans or timing output tracked | Not verified |
| Recursive cycle/missing-parent test | SQL implements path-based detection; no execution output tracked | Not run here |
| Inventory rollback test | Function source updates stock and inserts a log in one call; no failure-injection result tracked | Not verified |
| Compose health check | Configured in `compose.yaml`; no health output tracked | Not verified |

The `zero_stock` row is an INFO availability signal, not a data defect by itself. It is retained as a useful operational indicator; the view still defines 12 checks.

The figures 210 affected orders and 190 distinct missing customer IDs are the verified figures supplied for this submission review. Other data findings in the diagnosis (including 14 negative-stock products, cycle members 9001/9002 and 37 products with NULL category IDs) are explicitly labeled as previously observed and require fresh-load verification.

## Connect to the existing course database

Use the database name and user supplied with the course resources. These PowerShell variables target the existing server on localhost port 5432; PostgreSQL prompts for a password if needed.

```powershell
$env:PGHOST = "127.0.0.1"
$env:PGPORT = "5432"
$env:PGDATABASE = "<course-provided-database>"
$env:PGUSER = "<course-provided-user>"
psql -X -v ON_ERROR_STOP=1 -c "SELECT current_database(), current_setting('server_version');"
```

Obtain the authorized schema, dataset and race-test script from the course assignment materials. They are not tracked here. The schema is described as containing destructive `DROP TABLE` statements; only load it into a fresh database when the course explicitly authorizes that target. Do not reinitialize a populated assignment database. The data file format and the race-test command-line options cannot be specified without the external files.

## Repeatable report measurements

Run measurements only on a disposable copy with the authorized schema/data and the customer-spending view installed. Do not drop the report index on a shared or production database. Keep the dataset, PostgreSQL settings, query, and session conditions the same for both plans.

With the view and index present, capture the indexed plan:

```sql
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, SUMMARY)
SELECT * FROM public.customer_spending_report;
```

For the no-index baseline, run the same plan in a transaction and roll it back so the named index is restored:

```sql
BEGIN;
DROP INDEX IF EXISTS public.idx_orders_completed_spending;
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, SUMMARY)
SELECT * FROM public.customer_spending_report;
ROLLBACK;
```

Record the complete plans, planning and execution times, buffer statistics, PostgreSQL version, and dataset row counts. Repeat the paired measurements several times on the same disposable database and report the individual runs or a stated summary method; do not infer a speedup from a plan alone.

Capture actual report rows and customers with:

```sql
SELECT
    COUNT(*) AS report_rows,
    COUNT(DISTINCT customer_id) AS report_customers
FROM public.customer_spending_report;
```

The current view can emit up to 13 monthly rows per selected customer (at most 1,300 rows for 100 customers); this is a structural upper bound, not an observed row count.

## Repeatable concurrency and functional checks

Obtain `race_test.py` and its documented dependencies/options from the course materials. Run it only against a designated disposable/test database and the test product/data it specifies: the test creates orders and changes stock. Once the invocation is known, measure wall time in PowerShell as follows, replacing the path and adding only the arguments documented by that script:

```powershell
$raceTest = "C:|path\to\course\race_test.py"
$timer = [System.Diagnostics.Stopwatch]::StartNew()
python $raceTest
$exitCode = $LASTEXITCODE
$timer.Stop()
[pscustomobject]@{
    ExitCode = $exitCode
    ElapsedMilliseconds = $timer.ElapsedMilliseconds
}
```

Preserve the script output and record request count, successful orders, rejected out-of-stock requests, final stock, and elapsed time. The `python` command above assumes the course script's default invocation; its actual arguments and connection configuration remain unknown until the file is obtained.

After deploying solution 03 and the monitoring view, capture the runtime check count and total per-check violations with:

```sql
SELECT
    COUNT(*) AS monitoring_checks,
    SUM(violation_count) AS summed_per_check_violations
FROM public.data_quality_monitoring;
```

The check rows overlap by design in some cases, so the violation sum is not a distinct-record count. Inspect recursive edge cases with:

```sql
SELECT
    category_id,
    hierarchy_cycle_detected,
    missing_parent_detected
FROM public.low_stock_by_category(5)
WHERE hierarchy_cycle_detected
   OR missing_parent_detected
ORDER BY category_id;
```

No actual report counts, monitoring output, recursive results, concurrency duration, or inventory rollback result is available to enter here yet. Add results only after recording the genuine command/query, test conditions and output.

---

## Runtime validation update - 2026-11-27

This section supersedes the earlier audit statement that no database test had been run. The earlier audit describes the state before this runtime validation.

### Verified database environment

| Item | Result |
|---|---|
| Database | kloudkart_lab |
| PostgreSQL | 18.7 |
| Database user | postgres |
| max_connections | 500 |
| Sessions before test | 9 |
| Categories | 94 |
| Products | 4,023 |
| Customers | 40,420 |
| Orders | 159,384 |
| Order items | 336,559 |
| Inventory log | 282,352 |
| Deployed order function | public.place_order(bigint,bigint,integer) |

### Course concurrency test - PASSED

The supplied race_test.py was executed against kloudkart_lab.

| Scenario | Actual result |
|---|---|
| Two buyers competing for one unit, 25 rounds | 25/25 rounds passed; exactly one winner per round |
| Flash sale, 400 concurrent buyers and 50 units | 50 sold; 350 refused; 0 errors |
| Flash-sale duration reported by test | 6.95 seconds |
| Request exceeding available stock | Rejected; stock untouched |
| Inventory audit after contention | 5 sales; 5 movements recorded |
| Python process exit code | 0 |
| Overall result | PASSED |

The 400-attempt test completed below the assignment's 10-second target. This result applies to the tested workload and environment.

Original output: [race_test_2026-11-27.txt](evidence/race_test_2026-11-27.txt). The course-provided test script remains external to this repository.

### Post-test cleanup

A query against public.products found zero remaining rows with product_name matching RACE TEST FIXTURE%. The race-test fixtures were cleaned up.

### Remaining validation work

| Item | Status |
|---|---|
| Order-placement concurrency | Passed |
| Insufficient-stock handling | Passed |
| Inventory movements during tested sales | Passed |
| Race-test fixture cleanup | Verified |
| Customer spending report row count | Not yet measured |
| Report execution plans and before/after timings | Not yet measured |
| Monitoring view runtime output | Not yet verified; 12 checks defined in SQL source |
| Recursive cycle and missing-parent runtime checks | Not yet verified |
| Inventory movement rollback on induced failure | Not yet verified |

The concurrency test does not establish that every other SQL solution has passed runtime validation.
