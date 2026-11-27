-- ============================================================
-- Kloud Kart: Improvement beyond the brief
-- Reusable data-quality monitoring view
--
-- Input:    solutions 01-04 (uses low_stock_by_category()).
-- Produces: public.data_quality_monitoring, one row per check.
-- Asserts:  read-only; on a fresh load every count matches the
--           data diagnosis (see docs/validation_evidence.md).
--
-- Counts are per check. Some checks overlap, so the counts must
-- not be added together as a number of distinct bad records.
-- ============================================================

BEGIN;

-- Dropped and recreated so the script can be re-run, including
-- over the first deployed version, which had fewer columns.
DROP VIEW IF EXISTS public.data_quality_monitoring;

CREATE VIEW public.data_quality_monitoring AS

WITH category_health AS (
    SELECT *
    FROM public.low_stock_by_category(5)
),

ledger_balance AS (
    SELECT
        il.product_id,
        SUM(il.change_qty) AS ledger_stock
    FROM public.inventory_log il
    GROUP BY il.product_id
),

order_line_totals AS (
    SELECT
        oi.order_id,
        SUM(oi.quantity * oi.unit_price) AS line_total,
        BOOL_OR(oi.unit_price IS NULL) AS has_missing_price
    FROM public.order_items oi
    GROUP BY oi.order_id
),

checks AS (
    SELECT
        'stock_ledger_mismatch'::text AS check_name,
        COUNT(*)::bigint AS violation_count,
        'HIGH'::text AS severity,
        'Products whose stock differs from the sum of their inventory movements'::text
            AS description
    FROM public.products p
    LEFT JOIN ledger_balance lb
        ON lb.product_id = p.product_id
    WHERE p.stock_quantity IS DISTINCT FROM COALESCE(lb.ledger_stock, 0)

    UNION ALL

    SELECT
        'negative_stock',
        COUNT(*),
        'HIGH',
        'Products with stock below zero (sold units that did not exist)'
    FROM public.products
    WHERE stock_quantity < 0

    UNION ALL

    SELECT
        'order_total_mismatch',
        COUNT(*),
        'HIGH',
        'Orders whose total differs from the sum of their order lines'
    FROM public.orders o
    JOIN order_line_totals olt
        ON olt.order_id = o.order_id
    WHERE olt.has_missing_price
       OR o.total_amount IS DISTINCT FROM olt.line_total

    UNION ALL

    SELECT
        'orphan_orders',
        COUNT(*),
        'HIGH',
        'Orders referencing missing customers'
    FROM public.orders o
    WHERE o.customer_id IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM public.customers c
          WHERE c.customer_id = o.customer_id
      )

    UNION ALL

    SELECT
        'orphan_order_items_orders',
        COUNT(*),
        'HIGH',
        'Order items referencing missing orders'
    FROM public.order_items oi
    WHERE oi.order_id IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM public.orders o
          WHERE o.order_id = oi.order_id
      )

    UNION ALL

    SELECT
        'unlogged_stock_updates',
        COUNT(*),
        'HIGH',
        'Stock changes made outside the inventory functions (caught by the audit trigger)'
    FROM public.inventory_log
    WHERE reason = 'unlogged_update'

    UNION ALL

    SELECT
        'nonstandard_order_statuses',
        COUNT(*),
        'MEDIUM',
        'Orders whose status is not exactly one of the standard lower-case values'
    FROM public.orders
    WHERE status IS NULL
       OR status NOT IN (
           'pending', 'shipped', 'completed', 'cancelled', 'refunded'
       )

    UNION ALL

    SELECT
        'future_dated_orders',
        COUNT(*),
        'MEDIUM',
        'Orders dated after now; they will enter reports silently on that date'
    FROM public.orders
    WHERE order_date > LOCALTIMESTAMP

    UNION ALL

    SELECT
        'implausible_order_quantities',
        COUNT(*),
        'MEDIUM',
        'Order lines with quantity of 100 or more (999 and 9999 are keying errors)'
    FROM public.order_items
    WHERE quantity >= 100

    UNION ALL

    SELECT
        'duplicate_order_lines',
        COALESCE(SUM(line_count - 1), 0)::bigint,
        'MEDIUM',
        'Extra order lines repeating the same order, product, quantity and price'
    FROM (
        SELECT COUNT(*) AS line_count
        FROM public.order_items
        GROUP BY order_id, product_id, quantity, unit_price
        HAVING COUNT(*) > 1
    ) duplicate_groups

    UNION ALL

    SELECT
        'duplicate_customer_emails',
        COUNT(*),
        'MEDIUM',
        'Email addresses shared by more than one customer record'
    FROM (
        SELECT 1
        FROM public.customers
        WHERE email IS NOT NULL
        GROUP BY LOWER(BTRIM(email))
        HAVING COUNT(*) > 1
    ) duplicate_emails

    UNION ALL

    SELECT
        'orphan_inventory_logs',
        COUNT(*),
        'MEDIUM',
        'Inventory movements referencing missing products'
    FROM public.inventory_log il
    WHERE il.product_id IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM public.products p
          WHERE p.product_id = il.product_id
      )

    UNION ALL

    SELECT
        'products_without_category',
        COUNT(*),
        'MEDIUM',
        'Products with no category, reported separately by the low-stock roll-up'
    FROM public.products
    WHERE category_id IS NULL

    UNION ALL

    SELECT
        'categories_affected_by_cycles',
        COUNT(*),
        'MEDIUM',
        'Categories whose parent chain loops back on itself'
    FROM category_health
    WHERE hierarchy_cycle_detected

    UNION ALL

    SELECT
        'categories_with_missing_parents',
        COUNT(*),
        'LOW',
        'Categories whose parent category does not exist'
    FROM category_health
    WHERE missing_parent_detected

    UNION ALL

    SELECT
        'orphan_order_items_products',
        COUNT(*),
        'LOW',
        'Order items referencing missing products'
    FROM public.order_items oi
    WHERE oi.product_id IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM public.products p
          WHERE p.product_id = oi.product_id
      )

    UNION ALL

    SELECT
        'invalid_order_quantities',
        COUNT(*),
        'LOW',
        'Order items with zero or negative quantities'
    FROM public.order_items
    WHERE quantity <= 0

    UNION ALL

    SELECT
        'negative_product_prices',
        COUNT(*),
        'LOW',
        'Products with prices below zero'
    FROM public.products
    WHERE price < 0

    UNION ALL

    SELECT
        'zero_stock',
        COUNT(*),
        'INFO',
        'Products at zero stock; an availability signal, not a data defect'
    FROM public.products
    WHERE stock_quantity = 0
)

SELECT
    check_name,
    violation_count,
    severity,
    CASE severity
        WHEN 'HIGH' THEN 1
        WHEN 'MEDIUM' THEN 2
        WHEN 'LOW' THEN 3
        ELSE 4
    END AS severity_rank,
    description,
    CURRENT_TIMESTAMP AS checked_at
FROM checks;

COMMIT;
