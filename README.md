
# Kloud Kart PostgreSQL Engineering Lab

A PostgreSQL engineering project focused on data integrity, transaction safety, query optimisation, hierarchical reporting, and auditable inventory management.

## Project Overview

Kloud Kart Ltd. is an e-commerce business operating in Accra, Ghana. This project investigates an existing PostgreSQL database and implements solutions to four database engineering requirements.

## Business Requirements

1. Prevent inventory overselling when multiple customers attempt to purchase the last available unit.
2. Generate customer spending reports with rankings, order counts, monthly spending and running totals.
3. Provide low-stock visibility across arbitrarily nested product categories.
4. Maintain an auditable record of inventory movements.

## Implemented Solutions

| Requirement | SQL implementation | Description |
|---|---|---|
| Concurrency-safe order placement | `01_place_order.sql` | Atomically deducts stock and creates an order, order item and inventory log entry. |
| Customer spending report | `02_customer_spending_report.sql` | Provides customer rankings, spending totals, monthly breakdowns and running totals. |
| Recursive low-stock reporting | `03_low_stock_category_rollup.sql` | Aggregates product stock through category ancestors and flags hierarchy defects. |
| Auditable inventory movements | `04_auditable_inventory_movements.sql` | Records controlled stock adjustments and their audit entries in one transaction. |

## Data Diagnosis

The initial investigation covered six tables:

- `categories`
- `customers`
- `products`
- `orders`
- `order_items`
- `inventory_log`

The diagnosis identified referential-integrity problems, inconsistent order statuses, and category hierarchy defects.

See [Data Diagnosis](docs/diagnosis/data_diagnosis.md) for the findings, business implications, assumptions and investigation limitations.

## Repository Structure

```text
KloudKart-PostgreSQL-Engineering-Lab/
│
├── docs/
│   └── diagnosis/
│       └── data_diagnosis.md
│
├── sql/
│   ├── diagnostics/
│   └── solutions/
│       ├── 01_place_order.sql
│       ├── 02_customer_spending_report.sql
│       ├── 03_low_stock_category_rollup.sql
│       └── 04_auditable_inventory_movements.sql
│
├── tests/
├── scripts/
├── evidence/
├── README.md
└── .gitignore
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
docker run -d --name kloudkart `
  -e POSTGRES_PASSWORD=kloudkart `
  -p 5432:5432 `
  postgres:18 `
  -c max_connections=500
```

Connect to the database:

```powershell
docker exec -it kloudkart psql -U postgres -d kloudkart_lab
```

The supplied training schema and data must be loaded before running the solution scripts.

**Important:** The supplied schema contains destructive table-drop statements. Do not rerun it against an existing populated database.

## Running the SQL Solutions

Copy each solution file into the running container:

```powershell
docker cp .\sql\solutions\01_place_order.sql kloudkart:/tmp/
docker cp .\sql\solutions\02_customer_spending_report.sql kloudkart:/tmp/
docker cp .\sql\solutions\03_low_stock_category_rollup.sql kloudkart:/tmp/
docker cp .\sql\solutions\04_auditable_inventory_movements.sql kloudkart:/tmp/
```

Connect to PostgreSQL and execute them in order:

```sql
\i /tmp/01_place_order.sql
\i /tmp/02_customer_spending_report.sql
\i /tmp/03_low_stock_category_rollup.sql
\i /tmp/04_auditable_inventory_movements.sql
```

The scripts are designed for the supplied lab schema and its existing data.

## Testing and Validation

The implementations were tested against the supplied database.

- Order placement passed the supplied concurrency race tests, including a 400-buyer, 50-unit contention test.
- Customer spending totals were checked against independently aggregated eligible orders.
- The customer spending query was evaluated using `EXPLAIN ANALYZE`.
- Recursive category reporting was checked against the known hierarchy cycle and missing parent.
- Inventory movements were tested for valid adjustments, invalid reasons, stock protection and transaction rollback.

Test evidence and final validation results should be documented as part of the submission.

## Data Handling

The original training data contains customer-related information and is not included in this repository.

The original CSV files are kept locally. Do not commit customer data, database dumps, credentials or other sensitive information.

Reproducing the investigation requires authorised access to the supplied training resources.

## Project Progress

- [x] Docker and PostgreSQL environment setup.
- [x] Database creation and initial schema loading.
- [x] Initial data-integrity checks.
- [x] Data diagnosis and business impact assessment.
- [x] Concurrency-safe order placement.
- [x] Customer spending report and query optimisation.
- [x] Recursive low-stock category reporting.
- [x] Auditable inventory movement function.
- [ ] Technical decisions and trade-offs documentation.
- [ ] Business memo.
- [ ] Additional implemented improvement.
- [ ] Final end-to-end validation and submission review.

## Project Status

The four core SQL requirements have been implemented, tested and committed on the `feature/kloudkart-sql-solution` branch.

The remaining work focuses on technical documentation, business communication, an additional improvement and final submission validation.
