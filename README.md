# Kloud Kart PostgreSQL Engineering Lab

A PostgreSQL engineering project focused on data integrity, transaction safety, query optimisation, hierarchical reporting, and auditable inventory management.

## Project Overview

Kloud Kart Ltd. is an e-commerce business operating in Accra, Ghana. This project investigates an existing PostgreSQL database, documents its data-quality issues, and implements solutions to four database engineering requirements.

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
KloudKart-PostgreSQL-Engineering-Lab/
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
|   |-- solutions/
|       |-- 01_place_order.sql
|       |-- 02_customer_spending_report.sql
|       |-- 03_low_stock_category_rollup.sql
|       |-- 04_auditable_inventory_movements.sql
|
|-- README.md
|-- .gitignore
```

## Technology Stack

- PostgreSQL 18
- Docker
- SQL
- Python
- Git and GitHub

## Database Setup

The lab database was run in a Docker container using PostgreSQL.

Example container setup:

```powershell
docker run -d --name kloudkart -e POSTGRES_PASSWORD=kloudkart -p 5432:5432 postgres:18 -c max_connections=500
```

Connect to the database:

```powershell
docker exec -it kloudkart psql -U postgres -d kloudkart_lab
```

**Important:** The supplied schema contains destructive `DROP TABLE` statements. Do not rerun it against a populated database unless you intend to recreate the database and its contents.

## Running the SQL Solutions

The SQL solution files can be copied into the running PostgreSQL container.

Example:

```powershell
docker cp .\sql\solutions\01_place_order.sql kloudkart:/tmp/
```

Repeat for the other solution files:

```powershell
docker cp .\sql\solutions\02_customer_spending_report.sql kloudkart:/tmp/
docker cp .\sql\solutions\03_low_stock_category_rollup.sql kloudkart:/tmp/
docker cp .\sql\solutions\04_auditable_inventory_movements.sql kloudkart:/tmp/
```

Connect to PostgreSQL and execute the files:

```sql
\i /tmp/01_place_order.sql
\i /tmp/02_customer_spending_report.sql
\i /tmp/03_low_stock_category_rollup.sql
\i /tmp/04_auditable_inventory_movements.sql
```

## Testing and Validation

The implementations were tested against the supplied database.

- Concurrent order placement was tested for overselling prevention, stock protection and transaction consistency.
- Customer spending reports were checked for ranking, totals, monthly breakdowns and query performance.
- Recursive category reporting was checked against the known hierarchy cycle and missing parent.
- Inventory movements were tested for valid adjustments, invalid reasons, stock protection and transaction rollback.

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
- [ ] Additional implemented improvement.
- [ ] Final end-to-end validation and submission review.

## Project Status

The four core SQL requirements have been implemented and tested. The data diagnosis, technical decisions and business memo are documented.

The remaining work focuses on one additional implemented improvement and final submission validation.