# Business Memo

**To:** Nana

**From:** Database Engineering Team

**Subject:** Kloud Kart Database Assessment and Recommended Improvements

## Executive Summary

The assessment of Kloud Kart's PostgreSQL database identified data-quality issues that could affect order reporting, inventory visibility and operational reliability. Four database improvements have also been implemented to strengthen order processing, customer spending reports and inventory management.

These findings indicate areas requiring attention. They should not automatically be interpreted as confirmed financial losses.

## Key Findings

**1. Order and customer data integrity**

The database contains 210 orders referencing 190 distinct missing customer IDs and 692 order-item records referencing 689 missing order IDs.

These records can affect the reliability of order reporting and make it difficult to trace some transactions to their associated customers or orders.

**2. Inconsistent order statuses**

Order statuses include inconsistent spellings such as `complete` and `completed`, and `canceled` and `cancelled`. The customer spending report currently includes only normalised `completed` orders; `complete` remains unconfirmed and is not combined with it.

This can cause reporting discrepancies when queries recognise only one spelling.

**3. Inventory data concerns**

The original investigation observed 14 products with negative stock and 577 products with zero stock. Zero stock can be legitimate and is not itself classified as a data defect. These counts need fresh-load verification before remediation.

There are also inventory movements referencing missing products. These issues reduce confidence in inventory visibility and should be investigated before stock figures are used for important operational decisions.

**4. Category hierarchy problems**

The original investigation observed a cycle between categories 9001 and 9002, and a separate category (9003) referencing missing parent 8999. It also recorded 37 products with NULL category IDs, which are omitted from category roll-ups. These findings need fresh-load verification.

These defects can affect category-based inventory reporting.

## Improvements Implemented

- **Safer order processing:** Order placement now protects stock from overselling when multiple customers attempt to purchase simultaneously.
- **Improved customer spending reports:** The reporting solution provides customer rankings, order counts, monthly spending and running totals.
- **Better inventory visibility:** Low-stock reporting traverses nested categories and identifies hierarchy defects.
- **Inventory auditability:** Controlled inventory adjustments update stock and create corresponding audit records within the same transaction.

The SQL implementations and monitoring view are included in the repository. Runtime test and performance evidence is not available in the current repository; see [Validation Evidence](validation_evidence.md).

## Business Recommendations

1. Investigate orphan records and establish the correct business treatment before attempting corrections.
2. Standardise order statuses across applications and reporting.
3. Investigate the 14 products with negative stock quantities and determine whether corrections are justified.
4. Confirm the correct parent categories and assign unclassified products only from authoritative records.
5. After reviewing existing exceptions, introduce appropriate foreign keys, NOT NULL constraints and validation rules.
6. Introduce recurring checks for orphan records, negative stock and inconsistent status values; treat zero stock as an availability signal unless business policy defines it otherwise.

## Conclusion

The assessment has established a clearer picture of the database's existing weaknesses and delivered four practical engineering improvements.

The next priority should be controlled remediation of the identified data-quality issues, followed by stronger database constraints and ongoing monitoring. This will help Kloud Kart improve confidence in its operational reports and inventory records while reducing the risk of similar issues recurring.
