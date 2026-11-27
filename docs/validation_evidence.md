# Validation Evidence

Every result in this repository's documentation comes from one of the runs below. Raw output is kept in [`docs/evidence/`](evidence/), unedited apart from a header describing the run.

## Environment

| Item | Value |
|---|---|
| Date | 27 November 2026 |
| Machine | Windows 11 laptop, Docker Desktop |
| PostgreSQL | 18.7 in a container (8 vCPU, 16 GB visible) |
| Settings | `shared_buffers` 128MB, `work_mem` 4MB, `max_connections` 500, time zone UTC |
| Python | 3.15.2 with `psycopg2-binary` 2.9.13 |
| Database | `kloudkart_audit`, a scratch database created empty and loaded with `course/schema.sql` and `course/load.sql`. A separate database was used so the existing `kloudkart_lab` database was not reset; schema, data and scripts are the same as in the README's Compose setup, which names it `kloudkart_lab` |

| Table | Rows after load |
|---|---:|
| categories | 94 |
| products | 4,023 |
| customers | 40,420 |
| orders | 159,384 |
| order_items | 336,559 |
| inventory_log | 282,352 |

## Results

| Check | Result | Evidence |
|---|---|---|
| Diagnosis queries on the untouched load | All figures in the data diagnosis reproduced | [fresh_load_verification](evidence/fresh_load_verification_2026-11-27.txt) |
| `sql/run_all.sql` from a fresh load | Exit code 0 on the first run and on a re-run; every script deployed without error | [fresh_load_verification](evidence/fresh_load_verification_2026-11-27.txt) |
| Report: 12 rows per customer | 485,040 rows for 40,420 customers | [fresh_load_verification](evidence/fresh_load_verification_2026-11-27.txt) |
| Report: final running total equals total spent | True for every customer | [fresh_load_verification](evidence/fresh_load_verification_2026-11-27.txt) |
| Report: total against an independent sum, as of the latest sale on or before the run (7 October 2026) | 339,184,984.53 both ways | [fresh_load_verification](evidence/fresh_load_verification_2026-11-27.txt) |
| Roll-up: largest root category (Electronics) against an independent walk | 1,238 products both ways | [fresh_load_verification](evidence/fresh_load_verification_2026-11-27.txt) |
| Roll-up: coverage | Roots + uncategorised + cycle members = 4,023 products | [fresh_load_verification](evidence/fresh_load_verification_2026-11-27.txt) |
| Oversized order | Refused with "Out of stock"; stock unchanged | [fresh_load_verification](evidence/fresh_load_verification_2026-11-27.txt) |
| Restock | One log row, no duplicate from the trigger | [fresh_load_verification](evidence/fresh_load_verification_2026-11-27.txt) |
| Refused movement | Stock and log unchanged | [fresh_load_verification](evidence/fresh_load_verification_2026-11-27.txt) |
| Direct stock update | Logged as `unlogged_update` | [fresh_load_verification](evidence/fresh_load_verification_2026-11-27.txt) |
| Write of negative stock | Rejected by the check constraint | [fresh_load_verification](evidence/fresh_load_verification_2026-11-27.txt) |
| Course `race_test.py`, unmodified, final code | PASSED 3/3; flash-sale test 4.90 s, 6.88 s, 4.75 s | [race_test_final_code](evidence/race_test_final_code_2026-11-27.txt) |
| 400 orders on one product | 400 sold, 0 errors, 400 log rows, stock 0; 3.78-4.33 s over 3 runs, timed from release of all 400 connections | [flash_sale_400_orders](evidence/flash_sale_400_orders_2026-11-27.txt) |
| Report before and after | About 4 hours (extrapolated) to 1.64 s | [report_benchmark](evidence/report_benchmark_2026-11-27.txt) |
| Roll-up timing and index use | 3.7-6.0 ms; neither former index used | [rollup_benchmark](evidence/rollup_benchmark_2026-11-27.txt) |
| Clean-up after all race and flash-sale runs | No fixture products left; no `unlogged_update` rows; orders, order items and log back to their loaded counts | [flash_sale_400_orders](evidence/flash_sale_400_orders_2026-11-27.txt) |

Timings were re-recorded after the final changes, on a busier laptop than an earlier run the same morning (shipped report median 1.38 s then, 1.64 s now). Absolute times vary with machine load; every comparison in the evidence is between variants measured in the same run.

## What is not verified

- **Production load.** All timings are from one laptop. The flash-sale result depends on the application sharing a small pool of connections (see technical decisions, section 2), which was not tested.
- **Adwoa's original query.** The "before" timing is a reconstruction of the usual per-customer report, run on 100 customers and extrapolated, not her actual query run in full.
- **The business meaning of `complete`.** The data supports treating it as completed; the business has not confirmed it.

## Reproducing the results

Follow [Running the project](../README.md#running-the-project) in the README: steps 2 to 4 load the data, run `sql/run_all.sql` and run both concurrency tests, on Windows, macOS or Linux. The report benchmark then runs the same way:

```bash
docker compose exec db psql -U postgres -d kloudkart_lab -f /tmp/sql/benchmarks/report_benchmark.sql
```

[`sql/benchmarks/report_benchmark.sql`](../sql/benchmarks/report_benchmark.sql) compares five variants: naive with and without an index, set-based with and without a covering index, and set-based with more sort memory. Run it only on a disposable copy, because it creates and drops indexes.
