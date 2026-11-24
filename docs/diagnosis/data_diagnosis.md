
# Kloud Kart Data Diagnosis

## 1. Project context

Kloud Kart Ltd. is an e-commerce business operating in Accra, Ghana. This investigation examines the existing PostgreSQL database supplied for the Kloud Kart engineering lab.

The purpose of this diagnosis is to identify existing data-integrity and consistency problems, determine their scale, explain their potential business impact, and recommend appropriate actions.

The investigation was performed against the supplied database before making any data modifications.

## 2. Investigation approach

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

The integrity checks were saved in `integrity_checks.sql`. They were read-only and did not modify the source data.

## 3. Summary of findings

| Finding | Affected records | Priority |
|---|---:|---|
| Order items referencing missing orders | 692 | High |
| Orders referencing missing customers | 210 | High |
| Inventory logs referencing missing products | 120 | High |
| Category referencing missing parent | 1 | Medium |
| Inconsistent order status representations | Multiple | Medium |

The initial checks also found:

- No products referencing missing categories.
- No order items referencing missing products.
- No negative product prices.
- No order items with quantities less than or equal to zero.

These zero-count results only establish that the specific conditions tested were not found. They do not prove that every aspect of those tables is valid.

## 4. Detailed findings

### 4.1 Order items referencing missing orders

**Priority: High**

The investigation identified 692 order-item records referencing 689 distinct order IDs that do not exist in the `orders` table.

| Measurement | Result |
|---|---:|
| Affected order items | 692 |
| Distinct missing order IDs | 689 |
| Total item quantity | 968 |
| Estimated item value | 826,327.80 |
| Lowest unit price | 5.27 |
| Highest unit price | 20,657.77 |

**Detection method**

A `LEFT JOIN` was performed between `order_items` and `orders`. Records with a non-null `order_id` and no matching order were counted.

**Potential business impact**

These order items cannot be connected to their corresponding order records. This can affect order-history reporting, sales analysis, reconciliation and investigations into customer purchases.

The estimated item value was calculated using:

`SUM(quantity * unit_price)`

This is the recorded value of the affected order items, not necessarily lost revenue.

**Recommended action**

Investigate the missing order IDs using authorised source records or transaction history. Recover valid records or references where possible. Introduce a foreign key after existing violations have been resolved.

### 4.2 Orders referencing missing customers

**Priority: High**

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

**Detection method**

A `LEFT JOIN` was performed between `orders` and `customers`. Orders with a non-null `customer_id` and no matching customer were counted.

**Potential business impact**

The affected orders cannot reliably be attributed to existing customer records. This may affect customer spending reports, customer purchase histories, customer segmentation and marketing analysis.

The combined order value is the recorded value associated with these orders. It should not be interpreted as confirmed financial loss.

The affected orders include completed, pending, shipped, cancelled and refunded status representations.

**Recommended action**

Investigate whether the missing customers were deleted, omitted during data loading or created through another business process. Recover valid customer records or references where possible. Introduce a foreign key after reconciliation.

### 4.3 Inventory logs referencing missing products

**Priority: High**

The investigation identified 120 inventory log records referencing 111 distinct product IDs that do not exist in the `products` table.

| Measurement | Result |
|---|---:|
| Affected inventory logs | 120 |
| Distinct missing product IDs | 111 |
| Total quantity change | -120 |
| Recorded reason | sale |
| Earliest affected log | 2025-08-05 21:26:34 |
| Latest affected log | 2026-08-31 22:47:23 |

**Detection method**

A `LEFT JOIN` was performed between `inventory_log` and `products`. Records with a non-null `product_id` and no matching product were counted.

**Potential business impact**

The affected stock movements cannot be linked to valid product records. This weakens inventory auditing, stock reconciliation and product-level sales analysis.

All 120 affected records have the reason `sale` and a combined quantity change of -120.

**Recommended action**

Investigate the missing product references using historical product records and sales transactions. Restore valid references where possible and enforce a foreign key between `inventory_log.product_id` and `products.product_id`.

### 4.4 Category referencing a missing parent

**Priority: Medium**

One category was found referencing a parent category that does not exist.

| Field | Value |
|---|---|
| Category ID | 9003 |
| Category name | Clearance |
| Missing parent ID | 8999 |
| Direct products | 0 |
| Child categories | 0 |

**Detection method**

A self-join was performed on the `categories` table to identify non-null parent IDs without matching category records.

**Potential business impact**

A broken parent relationship can affect category hierarchy traversal and low-stock reporting. The immediate impact appears limited because the category currently has no direct products or child categories.

**Recommended action**

Verify whether parent category 8999 was deleted or omitted during data loading. Restore the correct parent relationship or agree on an appropriate alternative.

### 4.5 Inconsistent order statuses

**Priority: Medium**

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

**Detection method**

The query grouped records using `LOWER(TRIM(status))` and counted the distinct original status values.

**Potential business impact**

Reports that filter by exact status values may omit records with different capitalisation or surrounding spaces.

The terms `complete` and `completed`, as well as `canceled` and `cancelled`, may represent equivalent business states, but this must be confirmed with the business before mapping them together.

**Recommended action**

Agree on an approved list of status values, define the meaning of each status, standardise existing records and enforce valid values using an appropriate database constraint or reference table.

## 5. Danger ranking

| Rank | Finding | Priority | Reason |
|---:|---|---|---|
| 1 | Order items referencing missing orders | High | 692 affected records and 826,327.80 in associated item value cannot be reconciled through their orders. |
| 2 | Orders referencing missing customers | High | 210 orders with a combined recorded value of 665,180.61 cannot reliably be attributed to customers. |
| 3 | Inventory logs referencing missing products | High | 120 stock movement records cannot be traced to valid products. |
| 4 | Inconsistent order statuses | Medium | Inconsistent values can produce incomplete or misleading reports. |
| 5 | Missing category parent | Medium | Breaks a hierarchy relationship, although no direct products or child categories are currently affected. |

This ranking is an initial assessment based on the available evidence. It does not establish actual financial losses.

## 6. Overall recommendations

1. Investigate and reconcile orphan records before deleting or changing any data.
2. Introduce appropriate foreign key constraints after resolving existing violations.
3. Standardise order statuses and enforce valid values.
4. Review and repair the category hierarchy.
5. Add validation to data-loading processes so invalid records are detected before entering production tables.
6. Establish recurring data-quality checks to identify new integrity problems.

## 7. Investigation limitations

- The investigation used the supplied training dataset and schema.
- The business meaning of every unusual value has not yet been confirmed.
- Recorded order and item values are not proof of lost revenue.
- The cause of each missing reference has not yet been established.
- No original records were deleted or modified as part of this diagnosis.
- The diagnosis does not yet include the implementation of corrective SQL solutions.

## 8. Conclusion

The investigation identified significant referential-integrity problems involving orders, customers, products and categories. It also found inconsistent order-status representations.

These problems can affect reporting accuracy, reconciliation, customer analysis, inventory auditing and category-based reporting.

The findings provide a baseline for the subsequent database engineering work. Any corrective changes should be supported by verified business rules, documented assumptions and repeatable tests.
