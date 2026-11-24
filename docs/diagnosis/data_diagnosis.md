# Kloud Kart Data Diagnosis

## 1. Project Context

Kloud Kart Ltd. is an e-commerce business operating in Accra, Ghana. This investigation examines the existing PostgreSQL database supplied for the Kloud Kart engineering lab.

The purpose of this diagnosis is to identify existing data-integrity and consistency problems, determine their scale, explain their potential business impact, and recommend appropriate actions.

The investigation was performed against the supplied database before making any data modifications.

## 2. Investigation Approach

The investigation covered six database tables:

- `categories`
- `products`
- `customers`
- `orders`
- `order_items`
- `inventory_log`

The following techniques were used:

- Table row-count checks.
- Sample record inspection.
- Table structure inspection.
- `LEFT JOIN` queries to identify missing referenced records.
- Aggregate queries to quantify affected records.
- Date-range analysis to understand the period covered by affected records.
- Grouping and normalisation of order statuses to identify inconsistent representations.

The read-only integrity checks are included in `sql/diagnostics/integrity_checks.sql`. They investigate potential problems without modifying or cleaning the source data.

### 2.1 Schema Design Observations

The supplied schema defines primary keys for the six tables but does not enforce the relationships between them using foreign-key constraints.

The relationships that should be considered for enforcement include:

- `categories.parent_id` referencing `categories.category_id`.
- `products.category_id` referencing `categories.category_id`.
- `orders.customer_id` referencing `customers.customer_id`.
- `order_items.order_id` referencing `orders.order_id`.
- `order_items.product_id` referencing `products.product_id`.
- `inventory_log.product_id` referencing `products.product_id`.

Without these constraints, PostgreSQL does not automatically prevent a record from referencing a non-existent parent record.

This is a structural weakness that permits referential-integrity problems to enter the database. However, the absence of foreign keys alone does not establish the cause of every missing reference found during this investigation.

## 3. Summary of Findings

| Finding | Affected records | Priority |
|---|---:|---|
| Order items referencing missing orders | 692 | High |
| Orders referencing missing customers | 210 | High |
| Inventory logs referencing missing products | 120 | High |
| Category referencing missing parent | 1 | Medium |
| Inconsistent order status representations | 15 distinct raw representations | Medium |

The initial checks also found:

- No products referencing missing categories.
- No order items referencing missing products.
- No negative product prices.
- No order items with quantities less than or equal to zero.

These zero-count results only establish that the specific conditions tested were not found. They do not prove that every aspect of those tables is valid.

## 4. Costing Assumptions and Business Impact

The investigation identified integrity faults that could affect Kloud Kart's reporting, reconciliation and inventory operations. Since actual staff costs and the precise financial consequences of each fault were not provided, the investigation uses explicit estimates to approximate the effort required to investigate the affected records.

These estimates are assumptions for prioritisation, not confirmed company expenses or financial losses.

### 4.1 Costing Assumptions

For the orphan-record findings, I assume:

- Investigating one affected record takes approximately 5 minutes.
- The estimated staff cost is 30 cost units per hour.
- For inconsistent statuses, reviewing one distinct raw status representation takes approximately 10 minutes because the review involves confirming its business meaning rather than investigating an individual transaction.

These are illustrative assumptions, not confirmed Kloud Kart payroll figures.

The calculation for orphan records is:

`Investigation cost = (Affected records × 5 / 60) × 30`

For inconsistent statuses:

`Investigation cost = (Distinct raw representations × 10 / 60) × 30`

The estimates measure investigation effort only. They do not include the cost of repairing records, implementing database constraints, lost sales or other operational consequences.

### 4.2 Estimated Investigation Costs

| Integrity fault | Investigation units | Estimated cost |
|---|---:|---:|
| Order items referencing missing orders | 692 records | 1,730 |
| Orders referencing missing customers | 210 records | 525 |
| Inventory logs referencing missing products | 120 records | 300 |
| Inconsistent order status representations | 15 representations | 75 |
| Category referencing a missing parent | 1 record | 2.50 |

The estimates indicate that investigating the missing-order references requires the greatest effort, followed by missing-customer references and missing-product inventory logs.

The inconsistent statuses have a lower estimated initial review cost because the investigation can begin by examining the 15 distinct raw representations rather than manually reviewing every order.

### 4.3 Monetary Exposure Requiring Reconciliation

The investigation also identified the following recorded transaction values:

- **826,327.80** in order-item value associated with 692 order items referencing missing orders.
- **665,180.61** in recorded order value associated with 210 orders referencing missing customers.

The currency associated with these values has not been independently confirmed from the supplied schema or investigation evidence. They are therefore presented without assigning a currency.

These figures represent recorded transaction values associated with affected records. They are not confirmed financial losses.

The missing-order references may affect order reconciliation and product sales reporting. The missing-customer references may affect customer spending calculations, customer rankings and the accuracy of the Monday report.

The actual reporting distortion cannot be established from these values alone. It would require checking which reporting periods and calculations include the affected transactions.

### 4.4 Sensitivity Analysis

To test whether the investigation-cost ranking depends heavily on the assumed staff rate, the hourly cost is reduced by half, from 30 to 15 cost units.

| Integrity fault | Original estimate | Estimate at half the rate |
|---|---:|---:|
| Order items referencing missing orders | 1,730 | 865 |
| Orders referencing missing customers | 525 | 262.50 |
| Inventory logs referencing missing products | 300 | 150 |
| Inconsistent order status representations | 75 | 37.50 |
| Category referencing a missing parent | 2.50 | 1.25 |

The ranking remains unchanged when the assumed hourly rate is halved. This indicates that the investigation-effort ranking is stable under this assumption.

However, this ranking measures estimated investigation effort, not total business damage. The monetary exposure and operational consequences must also be considered when prioritising remediation.

### 4.5 Limitations of the Estimates

These estimates are preliminary because actual investigation times, staff costs and business losses were not supplied.

Further investigation is needed to establish:

- Whether the affected transactions appear in Nana's Monday customer-spending report.
- Whether missing product references affect stock reconciliation or sales reporting.
- Whether inconsistent order statuses cause records to be excluded from reports.
- Whether the missing category parent affects the low-stock category roll-up.
- The actual staff time and financial cost of repairing the identified problems.

The estimates should guide prioritisation and further investigation, rather than be presented as audited financial losses.

## 5. Detailed Findings

### 5.1 Order Items Referencing Missing Orders

**Priority: High**

**1. What is wrong**

The investigation identified 692 order-item records referencing 689 distinct order IDs that do not exist in the `orders` table.

| Measurement | Result |
|---|---:|
| Affected order items | 692 |
| Distinct missing order IDs | 689 |
| Total item quantity | 968 |
| Estimated item value | 826,327.80 |
| Lowest unit price | 5.27 |
| Highest unit price | 20,657.77 |

The currency associated with this recorded monetary value has not been independently confirmed from the supplied schema or investigation evidence.

**2. How it was found**

A `LEFT JOIN` was performed between `order_items` and `orders`. Records with a non-null `order_id` and no matching order were counted.

The estimated item value was calculated using:

`SUM(quantity * unit_price)`

**3. What it costs**

The estimated investigation cost is:

`(692 × 5 / 60) × 30 = 1,730 cost units`

The affected order items have a combined recorded value of 826,327.80 that cannot currently be reconciled through matching order records.

This can affect order-history reporting, sales analysis, reconciliation and investigations into customer purchases. The recorded item value is not necessarily lost revenue.

**4. What should be done**

Investigate the missing order IDs using authorised source records or transaction history. Recover valid records or references where possible. Introduce a foreign key after existing violations have been resolved.

The repair should be reviewed carefully because recreating or linking an order incorrectly could result in duplicate or misleading transaction records.

### 5.2 Orders Referencing Missing Customers

**Priority: High**

**1. What is wrong**

The investigation identified 210 orders referencing 190 distinct customer IDs that do not exist in the `customers` table.

| Measurement | Result |
|---|---:|
| Affected orders | 210 |
| Distinct missing customer IDs | 190 |
| Total recorded order value | 665,180.61 |
| Average order value | 3,167.53 |
| Smallest order value | 6.77 |
| Largest order value | 67,719.76 |
| Earliest affected order | 2025-09-02 11:04:52 |
| Latest affected order | 2026-08-31 12:36:13 |

The currency associated with these recorded monetary values has not been independently confirmed from the supplied schema or investigation evidence.

**2. How it was found**

A `LEFT JOIN` was performed between `orders` and `customers`. Orders with a non-null `customer_id` and no matching customer were counted.

**3. What it costs**

The estimated investigation cost is:

`(210 × 5 / 60) × 30 = 525 cost units`

The affected orders have a combined recorded value of 665,180.61 that cannot reliably be attributed to existing customer records.

This may affect Nana's Monday customer-spending report, customer purchase histories, customer rankings, customer segmentation and marketing analysis.

The affected orders include completed, pending, shipped, cancelled and refunded status representations. Therefore, the issue is not limited to one order status.

The combined order value is not confirmed financial loss.

**4. What should be done**

Investigate whether the missing customers were deleted, omitted during data loading or created through another business process. Recover valid customer records or references where possible. Introduce a foreign key after reconciliation.

Customer records should not be merged or recreated based only on assumptions because doing so could incorrectly attribute purchases to the wrong customer.

### 5.3 Inventory Logs Referencing Missing Products

**Priority: High**

**1. What is wrong**

The investigation identified 120 inventory log records referencing 111 distinct product IDs that do not exist in the `products` table.

| Measurement | Result |
|---|---:|
| Affected inventory logs | 120 |
| Distinct missing product IDs | 111 |
| Total quantity change | -120 |
| Recorded reason | sale |
| Earliest affected log | 2025-08-05 21:26:34 |
| Latest affected log | 2026-08-31 22:47:23 |

**2. How it was found**

A `LEFT JOIN` was performed between `inventory_log` and `products`. Records with a non-null `product_id` and no matching product were counted.

**3. What it costs**

The estimated investigation cost is:

`(120 × 5 / 60) × 30 = 300 cost units`

The 120 affected stock movements cannot be linked to valid product records. This weakens inventory auditing, stock reconciliation and product-level sales analysis.

All 120 affected records have the reason `sale` and a combined quantity change of -120.

The negative quantity change represents an outward stock movement and is not itself an integrity fault. The problem is that the affected movements reference products that cannot be found.

The monetary value of the affected stock movements cannot be established from the available product records because the referenced products are missing.

**4. What should be done**

Investigate the missing product references using historical product records and sales transactions. Restore valid references where possible and enforce a foreign key between `inventory_log.product_id` and `products.product_id`.

Care must be taken not to create duplicate products or assign stock movements to incorrect product records.

### 5.4 Category Referencing a Missing Parent

**Priority: Medium**

**1. What is wrong**

One category was found referencing a parent category that does not exist.

| Field | Value |
|---|---|
| Category ID | 9003 |
| Category name | Clearance |
| Missing parent ID | 8999 |
| Direct products | 0 |
| Child categories | 0 |

**2. How it was found**

A self-join was performed on the `categories` table to identify non-null parent IDs without matching category records.

**3. What it costs**

The estimated investigation cost is:

`(1 × 5 / 60) × 30 = 2.50 cost units`

The immediate measurable impact appears limited because the category currently has no direct products or child categories.

However, a broken parent relationship can affect category hierarchy traversal and low-stock reporting. Its future impact could increase if products or subcategories are added beneath it.

**4. What should be done**

Verify whether parent category 8999 was deleted or omitted during data loading. Restore the correct parent relationship or agree on an appropriate alternative.

The parent should not be assigned arbitrarily because an incorrect relationship could place the category under the wrong part of the hierarchy.

### 5.5 Inconsistent Order Statuses

**Priority: Medium**

**1. What is wrong**

The investigation identified inconsistent status representations in the `orders` table.

Grouping statuses after applying `LOWER(TRIM(status))` produced the following results:

| Normalised status | Order count | Different raw representations |
|---|---:|---:|
| completed | 89,066 | 4 |
| complete | 22,285 | 1 |
| pending | 16,009 | 2 |
| shipped | 12,848 | 2 |
| cancelled | 9,488 | 3 |
| refunded | 6,479 | 2 |
| canceled | 3,209 | 1 |

There are 15 distinct raw status representations across seven normalised groups.

**2. How it was found**

The query grouped records using `LOWER(TRIM(status))` and counted the distinct original status values.

**3. What it costs**

The estimated initial review cost is:

`(15 × 10 / 60) × 30 = 75 cost units`

This estimate assumes that each distinct raw representation takes approximately 10 minutes to review and classify.

Reports that filter by exact status values may omit records with different capitalisation or surrounding spaces.

The terms `complete` and `completed`, as well as `canceled` and `cancelled`, may represent equivalent business states, but this must be confirmed with the business before mapping them together.

The exact number of incorrectly classified orders and the resulting reporting distortion cannot yet be established without confirming the approved status definitions and examining the affected reports.

**4. What should be done**

Agree on an approved list of status values and define the meaning of each status. Review the existing representations, standardise records according to approved business rules, and enforce valid values using an appropriate database constraint or reference table.

The risk of this correction is that similar-looking values may have different business meanings. They should not be merged without confirmation.

## 6. Danger Ranking

The initial ranking below considers the available transaction exposure, operational consequences and estimated investigation effort. It is not a ranking of confirmed financial losses.

| Rank | Finding | Priority | Reason |
|---:|---|---|---|
| 1 | Order items referencing missing orders | High | 692 affected records and 826,327.80 in associated item value cannot be reconciled through their orders. |
| 2 | Orders referencing missing customers | High | 210 orders with a combined recorded value of 665,180.61 cannot reliably be attributed to customers, potentially affecting the Monday report. |
| 3 | Inventory logs referencing missing products | High | 120 stock movement records cannot be traced to valid products, weakening inventory auditing and reconciliation. |
| 4 | Inconsistent order statuses | Medium | Inconsistent values can produce incomplete or misleading reports if exact status filters are used. |
| 5 | Missing category parent | Medium | Breaks a hierarchy relationship, although no direct products or child categories are currently affected. |

The first two findings have the largest recorded monetary exposure and may affect important business reporting. The inventory-log issue is also important because it weakens the audit trail for stock movements.

The investigation-cost ranking is consistent when the assumed hourly rate is halved. However, the danger ranking also considers the business consequences of each fault, not simply the cost of investigating it.

## 7. Overall Recommendations

1. Investigate and reconcile orphan records using authorised historical records before deleting or changing any data.
2. Review the database relationships and introduce appropriate foreign-key constraints after resolving existing violations. Validate existing data before enforcing the constraints.
3. Establish an approved order-status vocabulary. Confirm the business meaning of similar values before standardising existing records, then enforce valid values using an appropriate database constraint or reference table.
4. Review and repair the category hierarchy, confirming the correct parent for category 9003.
5. Add validation to data-loading processes so missing references and invalid values are detected before entering operational tables.
6. Establish recurring data-quality checks to identify new integrity problems and monitor the quality of operational data.

## 8. Investigation Limitations

- The investigation used the supplied training dataset and schema.
- The business meaning of every unusual value has not yet been confirmed.
- The currency associated with the recorded monetary values has not been independently confirmed.
- Recorded order and item values are not proof of lost revenue.
- The cause of each missing reference has not yet been established.
- Investigation costs are based on stated assumptions, not actual company payroll or measured investigation times.
- The actual effect of the identified faults on Nana's reports has not yet been fully measured.
- No original records were deleted or modified as part of this diagnosis.
- The diagnosis does not yet include the implementation of corrective SQL solutions.

## 9. Conclusion

The investigation identified significant referential-integrity problems involving orders, customers, products and categories. It also found inconsistent order-status representations.

These problems can affect reporting accuracy, reconciliation, customer analysis, inventory auditing and category-based reporting.

The investigation quantified the affected records, identified associated transaction values, and estimated the effort required to investigate the problems using explicit assumptions. The estimates provide a starting point for prioritisation but should not be interpreted as confirmed financial losses.

The findings provide a baseline for the subsequent database engineering work. Any corrective changes should be supported by verified business rules, documented assumptions and repeatable tests.