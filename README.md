# Kloud Kart PostgreSQL Engineering Lab

A PostgreSQL engineering project focused on data integrity, transaction safety, query optimisation, hierarchical reporting, auditable inventory management, and reusable data-quality monitoring.

## Project Overview

Kloud Kart Ltd. is an e-commerce business operating in Accra, Ghana. This project investigates an existing PostgreSQL database, documents its data-quality issues, and implements solutions to four database engineering requirements, together with an additional data-quality monitoring improvement.

## Business Requirements

1. Prevent inventory overselling when multiple customers attempt to purchase the last available unit.
2. Generate customer spending reports with rankings, order counts, monthly spending and running totals.
3. Provide low-stock visibility across nested product categories.
4. Maintain an auditable record of inventory movements.

## Implemented Solutions

| Requirement | SQL File | Description |
|---|---|---|
| Concurrency-safe order placement | `01_place_order.sql` | Atomically deducts stock and creates an order, order item and inventory log entry. |
| Customer spending report | `02_customer_spending_report.sql` | Provides customer rankings, spending totals, monthly breakdowns and running totals. |
| Recursive low-stock reporting | `03_low_stock_category_rollup.sql` | Aggregates product stock through category ancestors and flags hierarchy defects. |
| Auditable inventory movements | `04_auditable_inventory_movements.sql` | Records controlled stock adjustments and corresponding audit entries transactionally. |

## Additional Improvement: Data Quality Monitoring

The project includes a reusable database view, `public.data_quality_monitoring`, defined in `sql/diagnostics/data_quality_monitoring.sql`.

The view provides 12 monitoring checks covering:

- Missing category parents and circular category relationships.
- Orders, order items and inventory logs referencing missing records.
- Negative product prices and stock, plus a separate zero-stock availability signal.
- Invalid order quantities.
- Nonstandard or inconsistently formatted order statuses.

Each check reports a name, violation count, severity, description and check timestamp. The view reads the current database state without modifying source records.

The `zero_stock` result is an `INFO` availability signal because zero stock can be legitimate; negative stock remains a data-quality concern.

### Deploying the Monitoring View

Connect to the existing course-provided PostgreSQL database as described in [Database Setup](#database-setup). Deploy solution 03 first because the view calls `public.low_stock_by_category()`:

```powershell
psql -v ON_ERROR_STOP=1 -f .\sql\diagnostics\data_quality_monitoring.sql
```

Query the monitoring results:

```sql
SELECT *
FROM public.data_quality_monitoring
ORDER BY severity, check_name;
```

Summarise the results by severity:

```sql
SELECT
    severity,
    COUNT(*) AS checks_run,
    SUM(violation_count) AS total_violations,
    COUNT(*) FILTER (
        WHERE violation_count > 0
    ) AS checks_with_issues
FROM public.data_quality_monitoring
GROUP BY severity
ORDER BY severity;
```

The monitoring view complements the original integrity checks. Its violation counts are reported per check and should not be interpreted as unique affected records.

## Data Diagnosis

The initial investigation covered six tables:

- `categories`
- `customers`
- `products`
- `orders`
- `order_items`
- `inventory_log`

The diagnosis identified referential-integrity problems, inconsistent order statuses, negative stock quantities, and category hierarchy defects.

See [Data Diagnosis](docs/diagnosis/data_diagnosis.md) for the findings, business implications, assumptions and investigation limitations.

## Technical Documentation

- [Technical Decisions and Trade-offs](docs/technical_decisions.md) – explains the implementation approaches, alternatives, assumptions and limitations.
- [Business Memo](docs/business_memo.md) – summarises the important findings, business implications and recommendations.

## Repository Structure

```text
kloudkart-postgresql-engineering-lab/
|
|-- docs/
|   |-- diagnosis/
|   |   |-- data_diagnosis.md
|   |-- technical_decisions.md
|   |-- business_memo.md
|   |-- validation_evidence.md
|
|-- sql/
|   |-- diagnostics/
|   |   |-- integrity_checks.sql
|   |   |-- data_quality_monitoring.sql
|   |-- solutions/
|       |-- 01_place_order.sql
|       |-- 02_customer_spending_report.sql
|       |-- 03_low_stock_category_rollup.sql
|       |-- 04_auditable_inventory_movements.sql
|
|-- compose.yaml
|-- .env.example
|-- .gitignore
|-- README.md
```

## Technology Stack

- PostgreSQL (optional Compose configuration targets version 18; course server version is not recorded here)
- Docker and Docker Compose
- SQL
- Git and GitHub

## Database Setup

The assignment targets the existing course-provided PostgreSQL server on `127.0.0.1:5432`; the Compose database is not required and does not contain the course data.

Obtain the authorized schema, dataset and `race_test.py` from the course assignment materials. They are not included in this repository. Use the course instructions for their exact download and load format. The supplied schema is described as containing destructive `DROP TABLE` statements: do not load or rerun it against an existing populated database. Only initialize a database when the course explicitly directs you to use a fresh, authorized target.

Set the database and user names to the values provided for your course database, then connect. `psql` will prompt for a password when required; do not put a real password in a command or commit it.

```powershell
$env:PGHOST = "127.0.0.1"
$env:PGPORT = "5432"
$env:PGDATABASE = "<course-provided-database>"
$env:PGUSER = "<course-provided-user>"
psql -v ON_ERROR_STOP=1 -c "SELECT current_database(), version();"
```

If the course specifically instructs you to load an SQL schema into a fresh authorized target, first set `PGDATABASE` to the course-provided fresh target name. Then use the downloaded schema path:

```powershell
$courseSchema = "C:\path\to\course\schema.sql"
psql -v ON_ERROR_STOP=1 -f $courseSchema
```

Load the dataset only with the course-provided import procedure, since its file format and table mapping are not present here.

The repository keeps `compose.yaml` and `.env.example` only as an optional isolated local PostgreSQL environment. It starts an empty database and is not the submission target. Do not start it when working against the existing course server.

## Running the SQL Solutions

The customer spending report uses a rolling 12-month timestamp window. Since its boundary dates can fall partway through calendar months, the monthly output can include 13 calendar-month labels, with partial months at the start and end.

Run the read-only baseline checks, then deploy the solutions in dependency order against the existing authorized database. Open PowerShell in the repository root and set the connection variables described in [Database Setup](#database-setup).

**1. Run baseline integrity checks (read-only):**

```powershell
psql -v ON_ERROR_STOP=1 -f .\sql\diagnostics\integrity_checks.sql
```

**2. Deploy the four solution scripts in this order:**

```powershell
psql -v ON_ERROR_STOP=1 -f .\sql\solutions\01_place_order.sql
psql -v ON_ERROR_STOP=1 -f .\sql\solutions\02_customer_spending_report.sql
psql -v ON_ERROR_STOP=1 -f .\sql\solutions\03_low_stock_category_rollup.sql
psql -v ON_ERROR_STOP=1 -f .\sql\solutions\04_auditable_inventory_movements.sql
```

Solution 03 creates `public.low_stock_by_category()`, which the monitoring view requires. Deploy the view after solution 03:

```powershell
psql -v ON_ERROR_STOP=1 -f .\sql\diagnostics\data_quality_monitoring.sql
```

These scripts expect the course-provided tables and data to be loaded already. Solution 01 initializes sequences from existing identifiers; run deployment only on the authorized lab database. It is not a schema/data loader. The external `race_test.py` is not tracked; obtain it from course materials and use its documented invocation and connection settings on the designated test database only. It creates orders and changes stock.

## Testing and Validation

The repository does not contain test scripts, database output, execution plans or benchmark logs. See [Validation Evidence](docs/validation_evidence.md) for the evidence inventory and repeatable procedures. No runtime result is claimed here.

## Data Handling

The original training data contains customer-related information and is not included in this repository.

Do not commit customer data, database dumps, credentials or other sensitive information.

Reproducing the investigation requires authorised access to the supplied training resources.

## Project Progress

- [x] Initial database investigation and data diagnosis.
- [x] Concurrency-safe order placement.
- [x] Customer spending report and query optimisation.
- [x] Recursive low-stock category reporting.
- [x] Auditable inventory movement function.
- [x] Technical decisions and trade-offs documentation.
- [x] Business memo.
- [x] Additional data-quality monitoring improvement.
- [ ] Final end-to-end validation evidence recorded.
- [x] Docker Compose PostgreSQL setup.

## Project Status

All four core SQL solution scripts and the additional data-quality monitoring view are present. Runtime test and performance evidence remains unverified in this repository; see [Validation Evidence](docs/validation_evidence.md).

The optional Compose configuration is separate from the course database and is not required for submission.
