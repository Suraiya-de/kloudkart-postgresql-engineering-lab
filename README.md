# Kloud Kart PostgreSQL Engineering Lab

Kloud Kart Ltd. is an e-commerce company in Accra running on a single PostgreSQL server. This project diagnoses its data, stops it overselling stock, makes the Monday customer-spending report run in seconds, rolls low stock up through the category tree, and leaves an audit trail of every stock movement, all on the existing server with no new infrastructure.

## Deliverables

| Brief deliverable | Where |
|---|---|
| Data diagnosis, ranked by danger | [docs/diagnosis/data_diagnosis.md](docs/diagnosis/data_diagnosis.md) |
| Working SQL solution | [sql/](sql/), run in order by [sql/run_all.sql](sql/run_all.sql) |
| Key decisions and their trade-offs | [docs/technical_decisions.md](docs/technical_decisions.md) |
| One-page memo to Nana | [docs/business_memo.md](docs/business_memo.md) |
| Improvement beyond the brief | Data-quality monitoring view, [sql/diagnostics/data_quality_monitoring.sql](sql/diagnostics/data_quality_monitoring.sql) |
| Test and benchmark evidence | [docs/validation_evidence.md](docs/validation_evidence.md) and [docs/evidence/](docs/evidence/) |

## Results

Measured on a laptop against a fresh load of the course data (159,384 orders, 40,420 customers).

| Nana's criterion | Result |
|---|---|
| No overselling | Course `race_test.py` passed unmodified, 3 runs out of 3. 400 buyers for one product: 400 orders in 3.3-3.4 s, none oversold, no errors. |
| Fast Monday report | Every customer, 12 months, running totals and ranking in 1.38 s, against about 3 hours for a per-customer version. |
| Low stock at a glance | Full category roll-up, any depth, in about 4 ms. |
| Proof of what happened | Every change to a product's stock writes an `inventory_log` row, including changes made outside the provided functions. |

## Repository structure

```text
.
|-- README.md
|-- compose.yaml                      Local PostgreSQL 18 for running the project
|-- .env.example                      Template for the local database password and port
|-- .gitattributes                    Line-ending normalisation
|-- .gitignore                        Keeps data, credentials and dumps out of Git
|-- requirements.txt                  Python dependency for the race test and benchmark
|-- course/                           Course files, unmodified (see course/README.md)
|   |-- README.md                     Provenance, SHA-256 hashes, where the CSVs go
|   |-- schema.sql                    Kloud Kart's schema as supplied
|   |-- load.sql                      Loads the CSVs from course/data/
|   |-- race_test.py                  The concurrency test place_order() must pass
|   |-- data/                         The six CSVs; git-ignored, not committed
|-- docs/
|   |-- business_memo.md
|   |-- technical_decisions.md
|   |-- validation_evidence.md
|   |-- diagnosis/
|   |   |-- data_diagnosis.md
|   |-- evidence/
|       |-- fresh_load_verification_2026-11-27.txt
|       |-- race_test_final_code_2026-11-27.txt
|       |-- race_test_2026-11-27.txt
|       |-- flash_sale_400_orders_2026-11-27.txt
|       |-- report_benchmark_2026-11-27.txt
|       |-- rollup_benchmark_2026-11-27.txt
|-- scripts/
|   |-- flash_sale_benchmark.py       400 concurrent orders on one product
|-- sql/
    |-- run_all.sql                   Runs every stage below in order
    |-- diagnostics/
    |   |-- integrity_checks.sql      Diagnosis queries (read-only)
    |   |-- data_quality_monitoring.sql
    |-- solutions/
    |   |-- 01_place_order.sql
    |   |-- 02_customer_spending_report.sql
    |   |-- 03_low_stock_category_rollup.sql
    |   |-- 04_auditable_inventory_movements.sql
    |-- tests/
    |   |-- verify_solution.sql       Assertions; all writes rolled back
    |-- benchmarks/
        |-- report_benchmark.sql      Before-and-after report timings
```

The course's `schema.sql`, `load.sql` and `race_test.py` are in `course/`, byte-for-byte as supplied. The six CSV files are not committed because they contain customer records; copy them from the course bundle into `course/data/`.

## Running the project

Tested with Docker Desktop, PostgreSQL 18.7 and Python 3.15.2. The commands use `psql` inside the database container, so no local PostgreSQL client is needed.

### 1. Start PostgreSQL

Copy `.env.example` to `.env` and set a local password, then start the database. It listens on `127.0.0.1:5433` and allows 500 connections, which the 400-buyer tests need.

macOS or Linux:

```bash
cp .env.example .env        # then edit POSTGRES_PASSWORD
docker compose up -d
```

Windows PowerShell:

```powershell
Copy-Item .env.example .env   # then edit POSTGRES_PASSWORD
docker compose up -d
```

### 2. Load the course data

Copy the six CSV files from the course bundle into `course/data/`, then load them. `schema.sql` drops and recreates the tables, so run it only on a database you intend to reset.

macOS or Linux (replace the path with the bundle's `data` folder):

```bash
mkdir -p course/data
cp /path/to/course-bundle/data/*.csv course/data/
docker compose cp course/. db:/tmp/course
docker compose exec -w /tmp/course db psql -U postgres -d kloudkart_lab -v ON_ERROR_STOP=1 -f schema.sql
docker compose exec -w /tmp/course db psql -U postgres -d kloudkart_lab -v ON_ERROR_STOP=1 -f load.sql
```

Windows PowerShell:

```powershell
New-Item -ItemType Directory -Force course\data
Copy-Item "C:\path\to\course-bundle\data\*.csv" course\data\
docker compose cp course/. db:/tmp/course
docker compose exec -w /tmp/course db psql -U postgres -d kloudkart_lab -v ON_ERROR_STOP=1 -f schema.sql
docker compose exec -w /tmp/course db psql -U postgres -d kloudkart_lab -v ON_ERROR_STOP=1 -f load.sql
```

In Git Bash on Windows, set `MSYS_NO_PATHCONV=1` first so `/tmp/course` is not rewritten as a Windows path.

### 3. Diagnose, deploy and verify

One script runs the diagnosis on the untouched data, deploys the four solutions and the monitoring view, then runs the assertions in `sql/tests/verify_solution.sql`. It stops at the first error or failed assertion.

```bash
docker compose cp sql/. db:/tmp/sql
docker compose exec db psql -U postgres -d kloudkart_lab -v ON_ERROR_STOP=1 -f /tmp/sql/run_all.sql
```

The same two commands work in PowerShell. The script can be run again; each stage replaces what it created.

### 4. Run the concurrency tests

macOS or Linux:

```bash
python3 -m pip install -r requirements.txt
set -a; . ./.env; set +a
export DATABASE_URL="postgresql://postgres:${POSTGRES_PASSWORD}@127.0.0.1:${POSTGRES_PORT:-5433}/kloudkart_lab"
python3 course/race_test.py
python3 scripts/flash_sale_benchmark.py
```

Windows PowerShell:

```powershell
py -m pip install -r requirements.txt
$env:DATABASE_URL = "postgresql://postgres:<your-password>@127.0.0.1:5433/kloudkart_lab"
py course\race_test.py
py scripts\flash_sale_benchmark.py
```

Both create their own fixture products and remove them afterwards.

## Using the solutions

Monday report for every customer, as of a given date (the course extract ends on 31 August 2026; without a date the report runs as of today):

```sql
SELECT *
FROM customer_spending_report('2026-08-31 23:59:59');

-- Top 100 as of today
SELECT * FROM customer_spending_top100;
```

Both return one row per customer per month, so `total_spent` and `order_count` repeat on each of a customer's 12 rows. Sum `monthly_spend`, or take one month's rows, rather than summing `total_spent`.

Low stock by category, with five units or fewer counted as low:

```sql
SELECT * FROM low_stock_by_category(5);
```

Placing an order and recording a restock:

```sql
SELECT * FROM place_order(100001, 5001, 1);
SELECT * FROM record_inventory_movement(5001, 20, 'restock', 'Delivery note 4471');
```

Weekly data-quality check, most serious first:

```sql
SELECT severity, check_name, violation_count, description
FROM data_quality_monitoring
ORDER BY severity_rank, violation_count DESC;
```

## Data handling

The course CSV files contain customer names, emails and phone numbers. They live in `course/data/`, which `.gitignore` excludes, and must not be committed, along with `.env`, database dumps and any other credentials. The evidence files contain counts, timings and query plans only.
