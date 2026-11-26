# Technical Decisions and Trade-offs

## 1. Introduction

This document explains the key technical decisions made while implementing the four PostgreSQL engineering requirements for Kloud Kart.

The solutions were designed around the existing database structure and observed data-quality issues. The implementation prioritises transaction safety, accurate reporting, query performance, hierarchy visibility and inventory traceability without making assumptions that could damage existing data.

## 2. Concurrency-Safe Order Placement

**Implementation:** `sql/solutions/01_place_order.sql`

### Decision: Conditional stock updates

The `place_order()` function uses a conditional `UPDATE` to deduct stock only when sufficient inventory is available.

The update checks the available quantity and performs the deduction as one database operation.

This prevents two concurrent transactions from successfully purchasing the same final units.

### Why this approach was selected

A separate operation that first reads the stock quantity and then updates it could allow concurrent transactions to observe the same available stock before either transaction completes its update.

The conditional update makes the stock check and deduction atomic. PostgreSQL's row-level locking ensures competing updates are handled safely.

### Transaction handling

Order creation, order-item insertion, inventory deduction and inventory-log insertion are performed within the function's transaction context.

This ensures that a failed operation does not leave a partially created order or an inventory deduction without its corresponding records.

### Identifier generation

Sequences were introduced for the order, order-item and inventory-log identifiers because the original tables did not have suitable automatic identifier defaults.

The sequences were initialised using existing maximum identifiers to avoid collisions with existing records.

### Alternatives considered

- **Read stock, then update:** Not selected because the separate read and write create a concurrency risk unless additional locking and validation are used.
- **Application-side stock validation:** Not selected as the primary protection because database-level enforcement is more reliable when multiple clients access the database.
- **Explicit table locking:** Not selected because it would unnecessarily restrict unrelated order operations.

### Trade-offs and limitations

The implementation uses PostgreSQL row-level locking, which allows transactions involving different products to proceed independently.

The function uses `pending` as the initial order status because the supplied database does not establish a payment-confirmation workflow.

The function does not implement payment processing or order cancellation and refund workflows.

The supplied concurrency test was passed, including the 400-buyer, 50-unit contention scenario.

## 3. Customer Spending Report

**Implementation:** `sql/solutions/02_customer_spending_report.sql`

### Decision: A database view with common table expressions

The customer spending report is implemented as a PostgreSQL view using CTEs to separate eligibility filtering, customer aggregation, ranking and monthly reporting.

This makes the reporting logic easier to inspect and maintain.

### Customer eligibility

The report recognises both `complete` and `completed` as completed order statuses.

This addresses the inconsistent status representations found during the data diagnosis.

The report also:

- Excludes future-dated orders.
- Uses a rolling trailing 12-month timestamp window.
- Excludes orders without a valid matching customer.
- Excludes orders with a NULL total amount.

These rules prevent questionable records from silently affecting customer spending totals.

### Decision: Partial covering index

A partial index was created on the order date and customer identifier, including the total amount.

The index is restricted to eligible completed statuses and non-NULL order dates.

This reduces the index entries relevant to the report and can reduce the need to retrieve values directly from the table.

### Why this approach was selected

A full index would include orders that the report does not use.

The partial index focuses on the records relevant to the report, while the included total amount can help PostgreSQL satisfy parts of the query using an index-only scan.

`EXPLAIN ANALYZE` was used to inspect the execution plan and performance.

### Alternatives considered

- **A full index on all orders:** Not selected because it would index many records excluded from this report.
- **A materialized view:** Not selected because the report uses a rolling time window and a regular view avoids the need for a separate refresh process.
- **Calculating the report entirely in application code:** Not selected because aggregation and ranking are naturally handled by PostgreSQL and should remain close to the data.

### Trade-offs and limitations

The report generates calendar-month values covering the rolling 12-month timestamp window. Because the window can begin and end partway through a month, it can contain portions of 13 calendar months.

The view calculates its reporting window dynamically when queried.

Its performance may change as the database grows, so execution plans should be reviewed periodically.

## 4. Recursive Low-Stock Category Reporting

**Implementation:** `sql/solutions/03_low_stock_category_rollup.sql`

### Decision: Recursive common table expression

The `low_stock_by_category()` function uses a recursive CTE to traverse category relationships and aggregate product stock through category ancestors.

The default low-stock threshold is five units or fewer, while callers can supply another threshold.

### Why this approach was selected

The category structure can contain multiple levels. A fixed number of joins would limit the depth of the hierarchy and make future structural changes harder to accommodate.

A recursive CTE provides a flexible way to traverse arbitrarily nested parent-child relationships.

### Decision: Detect hierarchy defects

The existing data contains a cycle between categories 9001 and 9002, as well as a missing parent reference for category 9003.

The recursive traversal maintains a path of visited category identifiers. It uses that path to prevent endless traversal and flag cycles.

Missing parent relationships are also identified and reported.

### Indexing

Indexes were added to the category parent identifier and product category identifier to support hierarchy traversal and product aggregation.

### Alternatives considered

- **Fixed-depth joins:** Not selected because they would not reliably support arbitrary hierarchy depth.
- **Ignoring cycles:** Not selected because malformed hierarchy data could cause repeated traversal or misleading results.
- **Silently repairing category relationships:** Not selected because the correct parent relationships cannot be inferred safely from the available data.

### Trade-offs and limitations

Categories affected by the cycle are flagged so their totals can be interpreted carefully.

The six products directly associated with category 9001 can appear in the roll-ups for both cyclic categories. Therefore, totals across those categories must not be added as though they represent independent products.

The 37 products with NULL category identifiers are not included in category-based roll-ups.

The function reports the existing hierarchy defects rather than modifying the original category data.

## 5. Auditable Inventory Movements

**Implementation:** `sql/solutions/04_auditable_inventory_movements.sql`

### Decision: A controlled inventory movement function

The `record_inventory_movement()` function provides a controlled database operation for manual stock adjustments.

It supports the reasons:

- `restock`
- `return`
- `correction`
- `damage`
- `stock_take`

Sales are excluded because the `place_order()` function already handles sales-related stock deductions and audit entries.

### Decision: Validate movement reasons and quantities

The function checks that the movement reason is allowed and that the quantity sign is appropriate for that reason.

It also checks that the resulting stock quantity does not fall below zero or exceed the integer storage limit.

A product row is locked using `SELECT ... FOR UPDATE` before its stock is changed.

### Transaction handling

The product stock update and inventory-log insertion occur within the same transaction.

This ensures that the inventory balance and its corresponding audit record remain consistent if the operation fails.

### Alternatives considered

- **Allowing direct stock updates:** Not selected because direct updates can bypass validation and audit logging.
- **Using triggers for every stock change:** Not selected because the lab already has a dedicated order-placement workflow, and a controlled function provides an explicit interface for manual adjustments.
- **Allowing manual sales movements:** Not selected because this could duplicate or bypass the sales workflow.

### Trade-offs and limitations

The existing inventory log does not contain a physical-count field.

Consequently, a `stock_take` movement with a zero quantity records an audit event but does not replace the stock balance with a newly counted physical quantity.

A separate physical stock-count workflow would be needed to support that behaviour properly.

## 6. Existing Data Integrity and Constraint Decisions

The initial diagnosis identified orphan records, NULL values, inconsistent status representations and malformed category relationships.

Although adding foreign keys and NOT NULL constraints could strengthen the schema, applying them without addressing the existing violations would fail or risk inappropriate data changes.

For this reason, the implementation focuses on safe operations, explicit eligibility rules and reporting of known data-quality issues.

A separate data-cleaning and remediation process should be agreed before introducing stricter schema constraints.

## 7. Overall Engineering Principles

The implementation follows these principles:

1. **Protect existing data:** Avoid destructive changes and do not silently repair records without an established business rule.
2. **Enforce critical operations in the database:** Use transactions, conditional updates and row-level locking for inventory-sensitive operations.
3. **Make reporting rules explicit:** Define which records qualify for business metrics.
4. **Design for changing data structures:** Use recursive queries for hierarchical reporting.
5. **Preserve auditability:** Record inventory movements alongside stock changes.
6. **Validate with evidence:** Use concurrency tests, independent aggregate checks, execution plans and transaction rollback tests.

## 8. Conclusion

The four implementations address the main database engineering requirements while taking the existing data limitations into account.

The solutions prioritise safe inventory operations, transparent reporting, hierarchy defect visibility and traceable stock adjustments.

Further improvements should build on these foundations without compromising the integrity of the existing training data.