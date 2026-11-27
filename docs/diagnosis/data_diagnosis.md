# Kloud Kart Data Diagnosis

## 1. Scope and method

This diagnosis covers the six tables in the course extract: `categories`, `products`, `customers`, `orders`, `order_items` and `inventory_log`.

Every figure below was produced on 27 November 2026 against a database created empty and loaded with the course `schema.sql` and `load.sql`, before any solution script ran. The queries are in [`sql/diagnostics/integrity_checks.sql`](../../sql/diagnostics/integrity_checks.sql); their output is recorded in [`fresh_load_verification_2026-11-27.txt`](../evidence/fresh_load_verification_2026-11-27.txt).

| Table | Rows |
|---|---:|
| categories | 94 |
| products | 4,023 |
| customers | 40,420 |
| orders | 159,384 |
| order_items | 336,559 |
| inventory_log | 282,352 |

The extract runs from 2 August 2025 to 31 August 2026. Twenty-four orders are dated later; 15 of them are still in the future on the date of this diagnosis, 27 November 2026 (section 3.8). Money values are as recorded; the extract does not state a currency.

### What the schema permits

Reading `schema.sql` before the data shows what can go wrong. There are primary keys and nothing else: no foreign keys, no `NOT NULL`, no `CHECK` constraints, no unique email, and `status` and `reason` are free text. Every relationship, every quantity and every status is enforced only by whichever application wrote it. Each finding below is something this schema allowed.

### How each finding is costed

Each fault is costed against a figure Nana or Adwoa actually uses: the Monday report's total spend and top-100 list, units of stock, and the value of sales that cannot be traced. The report figures are measured as of 31 August 2026, the end of the extract, and include only completed orders from known customers (total spend 339,176,836.88 across 111,190 orders).

## 2. Ranking by danger

Danger means how badly the fault misleads a decision or harms a customer if left alone, not how many rows it touches.

| Rank | Finding | Size | What it costs Nana if uncorrected |
|---:|---|---|---|
| 1 | Stock does not match the movement ledger | 144 products, 2,553 units | Stock counts cannot be trusted; 49 of these products are at low stock, where a wrong count turns directly into overselling. |
| 2 | "complete" treated as a different status from "completed" | 22,285 orders, 68.09M (68.00M within the report) | A report that misses it understates customer spend by 20% and gets 24 of the top 100 customers wrong. |
| 3 | Order totals disagree with their order lines | 2,426 orders, 5.29M absolute difference | Revenue depends on which column is summed: 1.27M difference inside the Monday report's scope alone. |
| 4 | Negative stock | 14 products, 27 units | Units were sold that did not exist: the overselling Nana described, already in the data. |
| 5 | Orders whose customer does not exist | 210 orders, 665,180.61 | 144 completed orders worth 388,780.89 are missing from every customer's total. |
| 6 | Order lines whose order does not exist | 692 lines, 826,327.80 | Product sales include lines that belong to no order and no customer. |
| 7 | Duplicate order lines and keying errors | 578 extra lines (941,247.62); 6 lines with 999 or 9999 units | Units sold and line revenue are overstated; 23,988 phantom units in six lines. |
| 8 | Orders dated in the future | 15 orders, 12 completed worth 35,600.61 | They enter the report silently on their date; the first on 4 December 2026. |
| 9 | Duplicate customer records | 533 email addresses on 1,068 records, 8.82M spend split | Spend is split across several records; on this data it changes only one top-100 place. |
| 10 | Stock movements for products that do not exist | 120 movements, 111 products | 120 units left stock with no traceable product, a gap in the audit trail. |
| 11 | Products with no category | 37 products, 3,112 units | Invisible in any category roll-up, including 12 low-stock products. |
| 12 | Category tree defects | 1 cycle (2 categories, 6 products); 1 missing parent (0 products) | Ambiguous totals for the six products under the cycle; no current effect from the missing parent. |

The first four threaten the two things Nana asked about: whether stock can be trusted, and whether the Monday report is right. Findings 5 to 8 distort specific numbers by amounts that can be stated. Findings 9 to 12 are real but small on this data.

## 3. Findings

### 3.1 Stock does not match the movement ledger (rank 1)

**What is wrong.** For 3,879 of 4,023 products, `stock_quantity` equals the sum of that product's `inventory_log` movements exactly. For the other 144 it does not:

| Direction | Products | Net units | Gap per product |
|---|---:|---:|---|
| Stock below ledger (units left without a record) | 122 | -2,464 | 3 to 56 |
| Stock above ledger (units arrived without a record) | 22 | +89 | 3 to 6 |

**How it was found.** Each product's stock was compared with `SUM(change_qty)` from its movements (`stock_ledger_mismatch`, output 3).

**Why it matters.** Because 96% of products reconcile to the unit, the ledger is evidently how stock is meant to be kept; the 144 exceptions are stock changed without a record. That is exactly Nana's complaint that "stock counts no longer match reality", and it is the gap a trail is meant to close. Valued at current prices the unexplained units are worth 3,865,699.34. Forty-nine of the products are at five units or fewer; seven show sellable stock although their ledger says none is left.

**What to do.** Count the 144 products physically, record the result through `record_inventory_movement()` with reason `correction`, and use the new audit trigger (solution 04) so a stock change can no longer happen without a ledger row. Do not overwrite the balances from the ledger: either side could be the wrong one.

### 3.2 "complete" is a spelling of "completed" (rank 2)

**What is wrong.** `orders.status` holds 15 spellings of seven values. Most are case or space variants (`'completed'`, `'Completed'`, `'COMPLETED'`, `' completed'`), which `LOWER(BTRIM(status))` resolves. Two are different words: `complete` and `canceled`.

| Normalised status | Spellings | Orders | Average value | First and last order |
|---|---:|---:|---:|---|
| completed | 4 | 89,066 | 3,048.56 | 2 Aug 2025 to 20 Aug 2027 |
| complete | 1 | 22,285 | 3,055.27 | 2 Aug 2025 to 11 May 2027 |

**Decision.** `complete` is treated as completed. Each of the four spellings of `completed` holds 22,091 to 22,395 orders; `complete` holds 22,285, with the same average value and the same first order date. It behaves as a fifth spelling, not a separate stage. `canceled` is likewise read as `cancelled`; it affects no report.

**Why it matters.** Excluding `complete` drops the Monday report from 339.18M to 271.18M (20.0%) and replaces 24 of the top 100 customers. An exact `status = 'completed'` filter is worse still: it finds 22,044 of 111,190 sales (19.8%), worth 19.6% of the true spend.

**Cost if this decision is wrong.** If `complete` turns out to mean something else (for example, "delivered but not paid"), the report overstates spend by 68.00M as of 31 August 2026. That is why it is listed in the memo as an assumption to confirm, and why a single line in solution 02 controls it.

**What to do.** Agree one vocabulary of statuses, convert existing rows, and add a check constraint so new spellings cannot be written.

### 3.3 Order totals disagree with their order lines (rank 3)

**What is wrong.** For 2,426 orders, `total_amount` differs from `SUM(quantity * unit_price)` of the order's lines:

| Direction | Orders | Net difference |
|---|---:|---:|
| Total below lines | 1,341 | -3,215,549.76 |
| Total above lines | 938 | +545,448.22 |
| A line has no unit price | 147 | -730,592.36 |

**How it was found.** Output 4 of `integrity_checks.sql` (`order_total_mismatch`).

**Which side is right.** Often the total. In 526 of the orders, the total matches the lines once a duplicated line is removed, and the six keying-error orders have totals consistent with one unit rather than 999 or 9999 (both in 3.7). In those cases the total is right and the lines are wrong. The rest cannot be settled from the data: a lower total could be a discount, a higher one a delivery charge.

**Decision.** The Monday report uses `total_amount`, the amount charged at checkout, which the schema says the application writes. This also keeps duplicate lines and keying errors out of customer spend. Product-level analysis that sums lines would inherit the errors in 3.6 and 3.7.

**Why it matters.** Within the report's scope, 1,717 completed orders disagree; summing lines instead of totals would change the report by 1.27M. Two analysts using different columns would publish different revenue for the same week.

### 3.4 Negative stock: overselling already happened (rank 4)

**What is wrong.** Fourteen products have stock below zero, 27 units in total, worth 20,627.76 at current prices.

**How it was found.** `negative_stock`. For 13 of the 14, the negative figure equals the ledger sum, so these are recorded sales of units that did not exist. They are the overselling Nana described, not a typing error. The fourteenth (product 6295) shows -1 against a ledger of +3 and is also in 3.1.

**What to do.** Do not reset them to zero; the negative balance is the evidence of what was oversold. Reconcile each against a physical count and record the correction through `record_inventory_movement()`. The new constraint in solution 01 prevents any further negative balance from being written.

### 3.5 Orders whose customer does not exist (rank 5)

**What is wrong.** 210 orders worth 665,180.61 reference 190 customer IDs that are not in `customers`. They span 2 September 2025 to 31 August 2026 and every status.

**Why it matters.** 144 of them are completed sales worth 388,780.89. They cannot be attributed to anyone, so they are excluded from the Monday report. That is the right call for a per-customer report, but the business's total sales are 388,780.89 higher than the sum of customer totals.

**What to do.** Find the missing customer records from the source system before adding a foreign key. Do not reassign the orders by guesswork.

### 3.6 Order lines whose order does not exist (rank 6)

**What is wrong.** 692 order lines worth 826,327.80 reference 689 order IDs not in `orders`. Nobody can say who bought them, when, or whether they were paid for.

**Why it matters.** Any product-sales or units-sold figure built from `order_items` includes them. The Monday report, which works from order totals, does not.

**What to do.** Recover the parent orders if they exist upstream; otherwise quarantine the lines from product reporting. Add a foreign key once resolved.

### 3.7 Duplicate order lines and keying errors (rank 7)

**What is wrong.**

- 578 extra order lines repeat an existing line exactly (same order, product, quantity and price), in 577 groups worth 941,247.62.
- Six lines have a quantity of 999 or 9999, against a normal range of 1 to 10. In three of the six orders the total matches exactly when the quantity is read as one (for example, quantity 999 at 20.13 on an order totalling 20.13); in all six the total is a small fraction of what the stated quantity would cost. The six lines state 23,994 units; read as one unit each, 23,988 of them were never sold. No stock movement of that size exists, so stock was not affected.

**Why it matters.** Units sold and line revenue are overstated wherever lines are summed. Customer spend is unaffected because it uses order totals.

**What to do.** Delete the duplicate lines and correct the six quantities to 1 after confirming against the source orders; add a sensible upper bound on quantity at checkout.

### 3.8 Orders dated in the future (rank 8)

**What is wrong.** 15 orders are dated between 4 December 2026 and 20 August 2027; their stock movements carry the same future timestamps. Twelve are completed, worth 35,600.61. The times are all on the whole minute, unlike the rest of the data, which suggests a manual entry or clock error. The schema's own comment on `order_date` ("No time zone. Nobody remembers why.") makes a time-zone or entry error likely.

**Why it matters.** The report excludes orders after its report date, so they cause no harm today. But each will enter the report silently on its date, the first on 4 December 2026, inflating a week nobody sold in.

**What to do.** Correct them from the source system; the monitoring view flags them until then.

### 3.9 Duplicate customer records (rank 9)

**What is wrong.** 533 email addresses are shared by more than one record: 531 by two records and 2 by three (1,068 records). In every case the records have the same name, differing only in capitalisation; the phone number always differs and the city differs in 206 cases. These look like the same person registered more than once, not a shared family address.

**Why it matters.** Their completed spend, 8.82M, is split across several IDs, so each part ranks lower than the customer really does. On this data the effect on the top 100 is small: merging would bring one customer into it.

**What to do.** Merge only after confirming identity (the schema says email "never was" unique, so it is not proof on its own).

### 3.10 Stock movements for products that do not exist (rank 10)

120 inventory movements, all sales of one unit, reference 111 product IDs that are not in `products`. Those units left stock with no product an auditor can trace. Recover the product records if they existed; otherwise mark the movements as unattributable.

### 3.11 Products with no category (rank 11)

37 products holding 3,112 units have no category. Twelve of them are at low stock. Any roll-up that starts from the category tree misses them, so solution 03 reports them on a separate "no category assigned" line. Assign categories from the product catalogue.

### 3.12 Category tree defects (rank 12)

- Categories 9001 (Seasonal Promotions) and 9002 (Promotions) are each other's parent. Their six products appear in both categories' totals; the roll-up flags both and its recursion stops on the repeat.
- Category 9003 (Clearance) points to parent 8999, which does not exist. It has no products or children today.

Marketing adds subcategories often, so both should be fixed at source and guarded by a foreign key.

## 4. Looks wrong, but is not

These were investigated and deliberately left alone.

| Observation | Why it is not a fault |
|---|---|
| 577 products at zero stock | Sold out. An availability signal, reported as `INFO` by the monitoring view. |
| Sales stored as negative `change_qty` | The schema's documented convention for stock leaving. |
| 4,116 order lines priced differently from today's price | `unit_price` is the price at the time of sale; prices change. |
| 768 customers with no orders | Registered, never bought. They appear in the report with zero spend. |
| Customers in Lagos and Abuja | Plausibly cross-border customers; nothing in the brief restricts delivery to Ghana. |
| 406 product names used more than once | Different product IDs, prices and stock; likely variants. |
| City spellings such as `accra`, `ACCRA`, `Accra` | Cosmetic. They matter only for a city report, which nobody has asked for. |

## 5. What could not be resolved

- **Which side is right in 3.1 and 3.3.** The data shows the disagreement; only a physical count or the payment records can settle it.
- **The ledger records fewer sale units than the order lines.** The ledger holds 412,645 units of sales; order lines hold 554,451 (500,656 excluding cancelled orders). Because 3,879 products reconcile exactly to the ledger, the ledger is treated as the stock record. Why some order lines never produced a stock movement (perhaps orders cancelled before dispatch) is not explained by the extract.
- **The meaning of `complete`.** Section 3.2 gives the evidence for the decision; only Nana's team can confirm it.
- **The currency.** Not stated anywhere in the extract.

## 6. Recommendations, in order

1. Count and correct the 144 products in 3.1 and the 14 in 3.4 through `record_inventory_movement()`, so every correction is itself on the trail.
2. Confirm that `complete` means completed, then standardise the status values and add a check constraint.
3. Decide with finance which figure is revenue, the order total or the sum of lines, and correct the 526 orders whose duplicate lines explain the gap.
4. Recover or quarantine the orphaned orders, lines and movements (3.5, 3.6, 3.10), then add foreign keys.
5. Correct the future dates, the keying errors and the category tree.
6. Run `SELECT * FROM data_quality_monitoring ORDER BY severity_rank, violation_count DESC;` each Monday before the report, so new problems are seen when they arrive rather than months later.
