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
- Negative product prices, negative stock and zero stock.
- Invalid order quantities.
- Nonstandard or inconsistently formatted order statuses.

Each check reports a name, violation count, severity, description and check timestamp. The view reads the current database state without modifying source records.

### Deploying the Monitoring View

The following example uses the manual Docker container named `kloudkart`:

```powershell
docker cp .\sql\diagnostics\data_quality_monitoring.sql kloudkart:/tmp/
```

Connect to PostgreSQL:

```powershell
docker exec -it kloudkart psql -U postgres -d kloudkart_lab
```

Execute the SQL file:

```sql
\i /tmp/data_quality_monitoring.sql
```

When using Docker Compose instead, copy the file into the Compose container:

```powershell
docker cp .\sql\diagnostics\data_quality_monitoring.sql kloudkart-compose:/tmp/
```

Connect to the Compose database:

```powershell
docker compose exec db psql -U postgres -d kloudkart_lab
```

Execute the file:

```sql
\i /tmp/data_quality_monitoring.sql
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

- PostgreSQL 18
- Docker and Docker Compose
- SQL
- Python
- Git and GitHub

## Database Setup

The project supports two ways to run PostgreSQL: Docker Compose (recommended) and a manual Docker container.

### Option 1: Docker Compose (Recommended)

The repository includes a `compose.yaml` configuration for running PostgreSQL 18 with persistent storage and a health check.

**1. Configure environment variables**

Copy the example environment file:

```powershell
Copy-Item .\.env.example .\.env
```

Edit `.env` and set a local PostgreSQL password:

```dotenv
POSTGRES_PASSWORD=your-local-password
POSTGRES_PORT=5433
```

The `.env` file contains local credentials and must never be committed to Git. The repository includes `.env.example` as a template.

**2. Start PostgreSQL**

```powershell
docker compose up -d
```

**3. Check container health**

```powershell
docker compose ps
```

The database container should report a healthy status.

**4. Connect to PostgreSQL**

```powershell
docker compose exec db psql -U postgres -d kloudkart_lab
```

The Compose service uses PostgreSQL 18, exposes port `5433` on the host by default and stores database files in the named Docker volume `kloudkart_data`.

**5. Stop the service**

```powershell
docker compose down
```

This stops and removes the Compose container and network while preserving the named database volume. Do not use `docker compose down -v` unless you intentionally want to delete the persistent database volume.

**Important:** Docker Compose creates a fresh database. It does not automatically load the Kloud Kart training dataset or the completed SQL solutions. Load the authorised training schema and data before running the project scripts. Review the supplied schema first because it contains destructive `DROP TABLE` statements.

### Option 2: Manual Docker Setup

Alternatively, PostgreSQL can be started manually using Docker:

```powershell
docker run -d --name kloudkart -e POSTGRES_PASSWORD=kloudkart -p 5432:5432 postgres:18 -c max_connections=500
```

Connect to the database:

```powershell
docker exec -it kloudkart psql -U postgres -d kloudkart_lab
```

**Important:** The manual Docker container and the Docker Compose service are separate database environments. The manual container uses host port `5432`, while the Compose service uses host port `5433` by default. They do not share database contents or storage.

The supplied schema contains destructive `DROP TABLE` statements. Do not rerun it against a populated database unless you intend to recreate the database and its contents.

## Running the SQL Solutions

The SQL solution files can be copied into either running PostgreSQL container.

### Using Manual Docker

The following commands use the manual Docker container named `kloudkart`:

```powershell
docker cp .\sql\solutions\01_place_order.sql kloudkart:/tmp/
docker cp .\sql\solutions\02_customer_spending_report.sql kloudkart:/tmp/
docker cp .\sql\solutions\03_low_stock_category_rollup.sql kloudkart:/tmp/
docker cp .\sql\solutions\04_auditable_inventory_movements.sql kloudkart:/tmp/
```

Connect to PostgreSQL:

```powershell
docker exec -it kloudkart psql -U postgres -d kloudkart_lab
```

Execute the files:

```sql
\i /tmp/01_place_order.sql
\i /tmp/02_customer_spending_report.sql
\i /tmp/03_low_stock_category_rollup.sql
\i /tmp/04_auditable_inventory_movements.sql
```

### Using Docker Compose

Copy the SQL solution files into the Compose container named `kloudkart-compose`:

```powershell
docker cp .\sql\solutions\01_place_order.sql kloudkart-compose:/tmp/
docker cp .\sql\solutions\02_customer_spending_report.sql kloudkart-compose:/tmp/
docker cp .\sql\solutions\03_low_stock_category_rollup.sql kloudkart-compose:/tmp/
docker cp .\sql\solutions\04_auditable_inventory_movements.sql kloudkart-compose:/tmp/
```

Connect to PostgreSQL:

```powershell
docker compose exec db psql -U postgres -d kloudkart_lab
```

Execute the files:

```sql
\i /tmp/01_place_order.sql
\i /tmp/02_customer_spending_report.sql
\i /tmp/03_low_stock_category_rollup.sql
\i /tmp/04_auditable_inventory_movements.sql
```

The monitoring view is deployed separately using the instructions in the Additional Improvement section.

**Note:** These commands demonstrate how to deploy the project SQL files. They do not initialise the training dataset. The required schema and authorised training data must be loaded into the target database first.

## Testing and Validation

The implementations were tested against the supplied database.

- Concurrent order placement was tested for overselling prevention, stock protection and transaction consistency.
- Customer spending reports were checked for ranking, totals, monthly breakdowns and query performance.
- Recursive category reporting was checked against the known hierarchy cycle and missing parent.
- Inventory movements were tested for valid adjustments, invalid reasons, stock protection and transaction rollback.
- The data-quality monitoring view was executed and verified against 12 checks, including the original integrity checks and additional stock and status checks.

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
- [x] Final end-to-end validation and submission review.
- [x] Docker Compose PostgreSQL setup.

## Project Status

All four core SQL requirements have been implemented and tested. The data diagnosis, technical decisions and business memo are documented. An additional reusable data-quality monitoring view has been implemented and verified with 12 checks.

The Docker Compose configuration has also been added and verified with PostgreSQL 18, persistent storage and a passing container health check.

Final database validation and repository review are complete.