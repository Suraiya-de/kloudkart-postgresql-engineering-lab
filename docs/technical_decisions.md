# Technical Decisions and Trade-offs

This document explains how each of Nana's four requirements was met, what was rejected and why, and every point where the brief left a decision open. Measurements come from a fresh load on a laptop; the raw output is in [`docs/evidence/`](evidence/) and summarised in [Validation Evidence](validation_evidence.md).

## 1. Summary

| Requirement | Mechanism | Measured result |
|---|---|---|
| No overselling | `place_order()`: one conditional `UPDATE` that checks and deducts stock together, plus a `CHECK (stock_quantity >= 0)` backstop | Course race test passed 3/3; 400 orders on one product in 3.8-4.3 s, none oversold |
| Fast Monday report | `customer_spending_report(p_as_of)`: one set-based pass with window functions | 40,420 customers in 1.64 s (median), against about 4 hours for the per-customer approach |
| Low-stock roll-up | `low_stock_by_category()`: recursive walk of any depth with a cycle guard | 4-6 ms |
| Proof of what happened | Every inventory function writes `inventory_log`; a trigger logs any other update to a product's stock | Verified by `sql/tests/verify_solution.sql` |

## 2. Stopping the overselling

**Implementation:** [`sql/solutions/01_place_order.sql`](../sql/solutions/01_place_order.sql)

### How it works

The check and the deduction are one statement:

```sql
UPDATE products
SET stock_quantity = stock_quantity - p_quantity
WHERE product_id = p_product_id
  AND stock_quantity >= p_quantity;
```

When two buyers arrive together, the first `UPDATE` takes the product row's lock. The second waits. When the first commits, PostgreSQL re-evaluates the second buyer's `WHERE` clause against the new committed stock (the standard `READ COMMITTED` re-check). With the last unit gone, the condition is false, no row is updated, and the function returns `success = false` with "Out of stock". Nobody receives an error, and nobody gets a unit that does not exist.

The order, its line and its `inventory_log` row are written in the same transaction as the deduction, so there is never an order without its stock movement or a movement without its order.

### Defence in depth

`products_stock_non_negative` is a `CHECK (stock_quantity >= 0)` constraint added `NOT VALID`. It applies to every new write, from any source, without rejecting the 14 historical negative balances, which are evidence to reconcile rather than overwrite (diagnosis 3.4). If a future code path forgets the conditional update, the database refuses the write instead of overselling.

Side effect for Nana's team: until those 14 products are corrected, any edit to them (even a price change) fails while their stock is still negative. That is deliberate, because it forces the correction to happen first.

### Would triggers alone have fixed it?

No, not as triggers are usually proposed. The usual suggestion is a trigger on `order_items` that reads the stock and raises an error if it is too low. That is a read followed by a write: two buyers both read "1 left", both pass the check, and both deduct. That is exactly the race that oversold the best-seller twice. A trigger runs inside the same racing transactions; it adds no ordering of its own.

A trigger *can* be made correct by putting the same conditional `UPDATE` inside it, but then the trigger is not what fixed anything; the conditional update is. And a trigger can only refuse by raising an error, which reaches the customer as a failure, not the clear "out of stock" Nana promised. The course test treats such an error as a failed test.

Triggers are the right tool for the other half of the problem, the audit trail (section 5), and they are used there.

### Alternatives rejected

| Alternative | Why not |
|---|---|
| Read stock, then update | The race that caused the overselling. |
| `SELECT ... FOR UPDATE`, then update | Correct, but two statements where one does the job, and the lock is held for longer. |
| `SERIALIZABLE` isolation | Correct, but losing buyers get serialisation failures that must be retried. Under a 400-buyer spike most would retry repeatedly, and the course test fails if one reaches the client. |
| Advisory locks | Correct, but a second locking scheme that every future code path must remember to use. |
| `FOR UPDATE NOWAIT` or `SKIP LOCKED` | Would tell buyers "out of stock" while stock remains, just because someone else was mid-purchase. |
| Locking the whole products table | Would make a flash sale on one product block every other product. |
| Checking stock in the application | Several application servers would each need to coordinate; the database is the one place all of them share. |

### Flash-sale behaviour

Marketing expects about 400 orders in ten seconds on one product. Every buyer of that product queues on one row lock, so the question is whether the queue drains in time.

| Test | Result |
|---|---|
| Course race test, 400 buyers for 50 units, 3 runs | 50 sold, 350 refused, 0 errors; 4.8-6.9 s |
| `scripts/flash_sale_benchmark.py`, 400 buyers for 400 units, 3 runs | 400 sold, 0 errors, 400 log rows; 3.8-4.3 s; median wait 2.0-2.6 s, slowest buyer 3.8-4.3 s |

What survives: correctness under any level of contention, and 400 orders in under five seconds on a laptop. What would fail first is not the locking but the connections. The test opens 400 database connections at once; PostgreSQL's default limit is 100, and the lab server was configured with 500 to run it. In production the application must use a connection pool (a few dozen connections serving many buyers), so buyers wait in the pool's queue rather than being refused a connection. That is a configuration task for Nana's developers, not new infrastructure, and it is listed in the memo as unverified.

### Other decisions

- **New orders start as `pending`.** The brief describes no payment step. Because the report counts only completed orders, an order placed today appears in the report once it is marked completed.
- **ID sequences.** The supplied tables have no ID generators. Sequences start after the highest existing ID, so no historical row is reused.

## 3. The Monday report

**Implementation:** [`sql/solutions/02_customer_spending_report.sql`](../sql/solutions/02_customer_spending_report.sql)

### Shape

`customer_spending_report(p_as_of)` returns one row per customer per month for the 12 calendar months ending in the report month: 485,040 rows for 40,420 customers. Each row carries the customer's rank, total spent, order count, that month's spend and the running total. `customer_spending_top100` is a view of the top 100 as of today.

Ranking, totals, monthly spend and running totals come from one pass over the orders, using an aggregate with `FILTER` and two window functions, instead of a separate lookup for each customer and month.

### Why it was slow, and why a bigger server would not fix it

The usual hand-built version of this report computes each figure with its own lookup: for each of 40,420 customers, for each of 12 months, find that customer's orders. Without an index, each lookup reads all 159,384 orders. That is roughly 485,000 table scans.

| Version | Time |
|---|---|
| Per-customer lookups, no index | 34.0 s per 100 customers, so about 4 hours for all customers (extrapolated) |
| Per-customer lookups, index on customer | 52 ms per 100 customers, about 21 s for all (extrapolated) |
| **Set-based, as shipped** | **1.64 s for all customers (median of 5)** |
| Set-based plus a covering index | 1.46 s (11% faster) |
| Set-based with more sort memory | 1.67 s (not faster) |

Adwoa's actual query was not supplied, so the first row is a reconstruction of the usual shape, not her code. It is slower than her 40 minutes, so her query is probably less naive, but it has the same shape of cost. The point holds whatever the exact query: a server twice as fast turns 4 hours into 2, or 40 minutes into 20. The cost grows with customers times months times orders, and Kloud Kart is growing on all three. The fix is to stop asking the database the same question 485,000 times, and that costs nothing.

### Knowing when to stop

- **No index was added for the report.** A covering index saved about 180 ms on a once-a-week report, but every index on `orders` is extra work on every insert, including 400 inserts in ten seconds during a flash sale. The trade is not worth it.
- **No memory tuning.** The plan shows the sorts spilling to disk, but keeping them in memory made the report no faster. The remaining time is real work on 485,040 output rows.
- **No materialised (pre-computed) copy.** At under two seconds there is nothing to cache, and a cached copy can be stale on the Monday it matters.

### Decisions the brief left open

| Decision | Choice | Cost if wrong |
|---|---|---|
| Which orders are sales | Status `completed` or `complete`, ignoring case and spaces (diagnosis 3.2) | If `complete` means something else, spend is overstated by 68.00M (as of 31 August 2026). The rule is defined once, in `is_sale_status()` (`sql/solutions/00_business_rules.sql`), and used by the report, the diagnosis, the tests and the benchmark. |
| Spend figure | `orders.total_amount`, the amount charged at checkout, not the sum of lines (diagnosis 3.3) | If finance defines revenue as the sum of lines, the report differs by 1.27M. |
| "Total spent" and "order count" | All completed orders up to the report date, not just the last 12 months | If Adwoa wants 12-month totals, the ranking changes; the monthly columns already give the 12-month view. |
| The 12 months | The 12 calendar months ending in the report month; the last month is month-to-date | A rolling 365-day window would split months at both ends, which is why the previous version showed 13 month labels. |
| Running total | Starts from the customer's spend before the window, so the final month equals total spent | Adwoa may have tracked it from zero; the monthly figures allow either. The match is a built-in check. |
| Report date | A parameter, defaulting to today | This extract ends on 31 August 2026, so as of today the months after August are almost entirely zero. `customer_spending_report('2026-08-31 23:59:59')` reproduces the report as of the end of the data, and any past Monday can be re-run. |
| Future-dated orders | Excluded until their date | They will appear when their date arrives (diagnosis 3.8). The monitoring view flags them. |
| Orders whose customer does not exist | Excluded | 388,780.89 of completed sales are not in any customer's total (diagnosis 3.5). |
| Customers with no orders | Included with zero | The report really is "every customer"; filter on `order_count > 0` if not wanted. |
| Ties in rank | Broken by customer ID, so the top 100 is always exactly 100 | Two customers with identical spend at position 100 and 101 are ordered arbitrarily but consistently. |
| Duplicate customer records | Not merged | One top-100 place is affected on this data (diagnosis 3.9). |

### Verification

`sql/tests/verify_solution.sql` asserts that the report has exactly 12 rows per customer, that every customer's final running total equals their total spent, and that the grand total equals an independent sum of the same orders. It derives its report date from the data (the latest sale on or before today), so it holds for any extract; on the course data that date is 7 October 2026 and the total 339,184,984.53.

## 4. Low-stock roll-up

**Implementation:** [`sql/solutions/03_low_stock_category_rollup.sql`](../sql/solutions/03_low_stock_category_rollup.sql)

`low_stock_by_category(p_threshold)` walks upwards from every category to each of its ancestors with a recursive query, then totals products and low-stock products (stock at or below the threshold, default 5) under every ancestor. Electronics therefore includes Phones, Phone Accessories and Cases, at whatever depth marketing adds next.

- **No hard-coded depth.** The recursion stops when a category has no parent.
- **Termination guard.** Each walk carries the list of categories already visited and stops the moment one repeats. The real cycle between categories 9001 and 9002 is flagged on both rows, not looped on.
- **No double counting.** Each (category, ancestor) pair is counted once, and products are joined only to their own category.
- **Nothing hidden.** Products with no category appear on a separate "no category assigned" line; categories with a missing parent are flagged.
- **Indexes removed.** The first deployed version created indexes on `categories.parent_id` and `products.category_id`. The measured plan used neither; with 94 categories and 4,023 products, reading the tables directly is faster. Both were dropped so they cost nothing on writes.

Verification: the largest root category (Electronics, 1,238 products) matches an independent top-down walk, the root categories plus the uncategorised line plus the cycle members add up to all 4,023 products, and the cycle and missing-parent flags match an independent walk using PostgreSQL's `CYCLE` clause. The roll-up runs in 4-6 ms.

Rejected: fixed-depth joins (break when marketing adds a level), a stored path or closure table (faster at millions of categories, but another structure the team must keep in step on every change), and silently repairing the cycle (the correct parent is a business decision).

## 5. The audit trail

**Implementation:** [`sql/solutions/04_auditable_inventory_movements.sql`](../sql/solutions/04_auditable_inventory_movements.sql)

### Two layers

1. **The functions record why.** `place_order()` writes a `sale` row naming the order. `record_inventory_movement()` handles `restock`, `return`, `correction`, `damage` and `stock_take`, the reasons already in the data. It checks that the quantity's sign suits the reason, requires a note, locks the product row, and writes the stock change and its log row in one transaction. A refused movement changes nothing.
2. **The trigger records every other update.** `trg_products_stock_audit` fires on any update to an existing product's `stock_quantity`. If the change did not come through one of the functions, it writes an `unlogged_update` row with the database user and the before and after values. The functions set a transaction-local flag around their own update so they are not logged twice.

The second layer exists because of the diagnosis: 144 products drifted from their ledger (diagnosis 3.1) because something changed stock without writing a row. With the trigger in place, that cannot happen silently again.

### Choices

- **Log rather than block.** A trigger could forbid direct updates instead. During an incident, operations staff may need to fix a stock figure quickly; blocking them invites workarounds. Logging lets the fix happen and makes it visible, and the monitoring view counts `unlogged_update` rows every Monday.
- **Not trigger-only logging.** If the trigger wrote every row, it could not know whether a deduction was a sale, damage or a correction. The function knows, so it writes the row.
- **Limits.** The trigger covers updates only: opening stock on a newly created product and a deleted product leave no movement row (new products should be created at zero and stocked through a `restock`). The flag is a guard against mistakes, not against a database administrator determined to hide a change. The log records the database user, not the person behind the application. Rows in `inventory_log` can still be edited or deleted by anyone with table rights; the next step is to remove `UPDATE` and `DELETE` on that table from the application's database user.
- **Stock-takes.** The existing log has no field for a counted quantity, so `stock_take` records an event with zero change; a physical count that differs is recorded as a `correction`.

## 6. Schema changes left behind

Nana's team lives with these. Each is documented in its script header.

| Change | Script | Why | To undo |
|---|---|---|---|
| Sequences as defaults for `orders.order_id`, `order_items.order_item_id`, `inventory_log.log_id` | 01 | The tables had no ID generator | `ALTER COLUMN ... DROP DEFAULT` |
| `products_stock_non_negative` check, `NOT VALID` | 01 | Database-level backstop against overselling | `ALTER TABLE products DROP CONSTRAINT products_stock_non_negative` |
| `is_sale_status` function | 00 | One shared definition of a sale | `DROP FUNCTION` (after the report) |
| `place_order`, `customer_spending_report`, `low_stock_by_category`, `record_inventory_movement` functions | 01-04 | The four requirements | `DROP FUNCTION` |
| `customer_spending_top100` and `data_quality_monitoring` views | 02, monitoring | Ready-made views for Adwoa and Nana | `DROP VIEW` |
| `trg_products_stock_audit` trigger | 04 | Audit safety net | `DROP TRIGGER trg_products_stock_audit ON products` |
| Indexes from earlier versions dropped | 02, 03 | Measured to give no worthwhile benefit | Recreate if a future plan shows a need |

No foreign keys or `NOT NULL` constraints were added. Each would fail on the existing violations (diagnosis section 3) or force guessed repairs. They are recommended after the data is reconciled.

## 7. What a naive build would have cost later

- **Read-then-write order placement** passes a quiet-day demonstration and oversells under exactly the load a flash sale creates.
- **An exact `status = 'completed'` filter** reports 19.6% of real spend (one sale in five), with no error to warn anyone.
- **A top-100-only report** gives Adwoa no figure for the other 40,320 customers, so she keeps her spreadsheet.
- **A fixed three-join category query** silently drops products the day marketing adds a fourth level.
- **An audit trail written only by the functions** keeps drifting the way the extract already has, because any other update path leaves no record.
- **An index added "for the report"** taxes every flash-sale order to save 180 ms once a week.
