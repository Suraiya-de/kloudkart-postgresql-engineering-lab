-- ============================================================
-- Kloud Kart: Data diagnosis checks
--
-- Input:    the course schema and data, loaded fresh, before any
--           solution script runs.
-- Produces: the figures quoted in docs/diagnosis/data_diagnosis.md.
-- Asserts:  read-only; nothing is modified or cleaned.
--
-- Output 1 lists every finding with its affected rows, distinct
-- keys and recorded value. Outputs 2-4 give the breakdowns the
-- diagnosis relies on; output 5 costs each finding against the
-- Monday report and stock figures.
--
-- future_dated_orders compares with the time of the run, so its
-- count falls as those dates pass. The diagnosis quotes the run
-- of 27 November 2026.
-- ============================================================

\pset pager off

-- ------------------------------------------------------------
-- Output 1: findings
-- ------------------------------------------------------------

WITH RECURSIVE category_walk AS (
    SELECT
        c.category_id AS start_id,
        c.category_id AS current_id,
        c.parent_id,
        ARRAY[c.category_id] AS path,
        FALSE AS cycle_detected
    FROM public.categories c

    UNION ALL

    SELECT
        cw.start_id,
        parent.category_id,
        parent.parent_id,
        cw.path || parent.category_id,
        parent.category_id = ANY(cw.path)
    FROM category_walk cw
    JOIN public.categories parent
        ON parent.category_id = cw.parent_id
    WHERE NOT cw.cycle_detected
),

cycle_members AS (
    SELECT DISTINCT cycle_node.category_id
    FROM category_walk cw
    CROSS JOIN LATERAL unnest(
        cw.path[array_position(cw.path, cw.current_id):cardinality(cw.path)]
    ) AS cycle_node(category_id)
    WHERE cw.cycle_detected
),

ledger_balance AS (
    SELECT product_id, SUM(change_qty) AS ledger_stock
    FROM public.inventory_log
    GROUP BY product_id
),

order_line_totals AS (
    SELECT
        order_id,
        SUM(quantity * unit_price) AS line_total,
        BOOL_OR(unit_price IS NULL) AS has_missing_price
    FROM public.order_items
    GROUP BY order_id
)

SELECT
    'stock_ledger_mismatch' AS check_name,
    COUNT(*) AS affected_rows,
    COUNT(*) AS distinct_keys,
    SUM(ABS(p.stock_quantity - COALESCE(lb.ledger_stock, 0))) AS recorded_value
FROM public.products p
LEFT JOIN ledger_balance lb
    ON lb.product_id = p.product_id
WHERE p.stock_quantity IS DISTINCT FROM COALESCE(lb.ledger_stock, 0)

UNION ALL

SELECT
    'negative_stock',
    COUNT(*),
    COUNT(*),
    SUM(stock_quantity)
FROM public.products
WHERE stock_quantity < 0

UNION ALL

SELECT
    'order_total_mismatch',
    COUNT(*),
    COUNT(*),
    SUM(ABS(o.total_amount - COALESCE(olt.line_total, 0)))
FROM public.orders o
JOIN order_line_totals olt
    ON olt.order_id = o.order_id
WHERE olt.has_missing_price
   OR o.total_amount IS DISTINCT FROM olt.line_total

UNION ALL

SELECT
    'complete_status_excluded_by_exact_match',
    COUNT(*),
    COUNT(DISTINCT customer_id),
    SUM(total_amount)
FROM public.orders
WHERE LOWER(BTRIM(status)) = 'complete'

UNION ALL

SELECT
    'orphan_orders',
    COUNT(*),
    COUNT(DISTINCT o.customer_id),
    SUM(o.total_amount)
FROM public.orders o
WHERE o.customer_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM public.customers c WHERE c.customer_id = o.customer_id
  )

UNION ALL

SELECT
    'orphan_order_items_orders',
    COUNT(*),
    COUNT(DISTINCT oi.order_id),
    SUM(oi.quantity * oi.unit_price)
FROM public.order_items oi
WHERE oi.order_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM public.orders o WHERE o.order_id = oi.order_id
  )

UNION ALL

SELECT
    'future_dated_orders',
    COUNT(*),
    COUNT(*),
    SUM(total_amount)
FROM public.orders
WHERE order_date > LOCALTIMESTAMP

UNION ALL

SELECT
    'implausible_order_quantities',
    COUNT(*),
    COUNT(DISTINCT order_id),
    SUM(quantity)
FROM public.order_items
WHERE quantity >= 100

UNION ALL

SELECT
    'duplicate_order_lines',
    SUM(line_count - 1),
    COUNT(*),
    SUM((line_count - 1) * quantity * unit_price)
FROM (
    SELECT order_id, quantity, unit_price, COUNT(*) AS line_count
    FROM public.order_items
    GROUP BY order_id, product_id, quantity, unit_price
    HAVING COUNT(*) > 1
) duplicate_groups

UNION ALL

SELECT
    'duplicate_customer_emails',
    SUM(record_count),
    COUNT(*),
    NULL
FROM (
    SELECT LOWER(BTRIM(email)) AS email_key, COUNT(*) AS record_count
    FROM public.customers
    WHERE email IS NOT NULL
    GROUP BY LOWER(BTRIM(email))
    HAVING COUNT(*) > 1
) duplicate_emails

UNION ALL

SELECT
    'orphan_inventory_logs',
    COUNT(*),
    COUNT(DISTINCT il.product_id),
    SUM(il.change_qty)
FROM public.inventory_log il
WHERE il.product_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM public.products p WHERE p.product_id = il.product_id
  )

UNION ALL

SELECT
    'products_without_category',
    COUNT(*),
    COUNT(*),
    SUM(stock_quantity)
FROM public.products
WHERE category_id IS NULL

UNION ALL

SELECT
    'categories_in_parent_cycles',
    COUNT(*),
    COUNT(*),
    NULL
FROM cycle_members

UNION ALL

SELECT
    'orphan_categories',
    COUNT(*),
    COUNT(DISTINCT c.parent_id),
    NULL
FROM public.categories c
WHERE c.parent_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM public.categories p WHERE p.category_id = c.parent_id
  )

UNION ALL

SELECT
    'orphan_products',
    COUNT(*),
    COUNT(DISTINCT p.category_id),
    NULL
FROM public.products p
WHERE p.category_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM public.categories c WHERE c.category_id = p.category_id
  )

UNION ALL

SELECT
    'orphan_order_items_products',
    COUNT(*),
    COUNT(DISTINCT oi.product_id),
    NULL
FROM public.order_items oi
WHERE oi.product_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM public.products p WHERE p.product_id = oi.product_id
  )

UNION ALL

SELECT
    'negative_product_prices',
    COUNT(*),
    COUNT(*),
    NULL
FROM public.products
WHERE price < 0

UNION ALL

SELECT
    'invalid_order_quantities',
    COUNT(*),
    COUNT(*),
    NULL
FROM public.order_items
WHERE quantity <= 0;

-- ------------------------------------------------------------
-- Output 2: order status spellings, with value per spelling.
-- 'complete' has the same volume, value and date range as the
-- four spellings of 'completed'.
-- ------------------------------------------------------------

SELECT
    LOWER(BTRIM(status)) AS normalised_status,
    COUNT(DISTINCT status) AS raw_spellings,
    COUNT(*) AS orders,
    SUM(total_amount) AS recorded_value,
    ROUND(AVG(total_amount), 2) AS average_order_value,
    MIN(order_date)::date AS first_order,
    MAX(order_date)::date AS last_order
FROM public.orders
GROUP BY LOWER(BTRIM(status))
ORDER BY orders DESC;

-- ------------------------------------------------------------
-- Output 3: stock versus movement ledger, by direction.
-- ------------------------------------------------------------

WITH ledger_balance AS (
    SELECT product_id, SUM(change_qty) AS ledger_stock
    FROM public.inventory_log
    GROUP BY product_id
)
SELECT
    CASE
        WHEN p.stock_quantity < lb.ledger_stock
            THEN 'stock below ledger (units left without a record)'
        ELSE 'stock above ledger (units arrived without a record)'
    END AS direction,
    COUNT(*) AS products,
    SUM(p.stock_quantity - lb.ledger_stock) AS net_units,
    MIN(p.stock_quantity - lb.ledger_stock) AS smallest_gap,
    MAX(p.stock_quantity - lb.ledger_stock) AS largest_gap
FROM public.products p
JOIN ledger_balance lb
    ON lb.product_id = p.product_id
WHERE p.stock_quantity <> lb.ledger_stock
GROUP BY 1
ORDER BY 1;

-- ------------------------------------------------------------
-- Output 4: order total versus order lines, by direction.
-- ------------------------------------------------------------

WITH order_line_totals AS (
    SELECT
        order_id,
        SUM(quantity * unit_price) AS line_total,
        BOOL_OR(unit_price IS NULL) AS has_missing_price
    FROM public.order_items
    GROUP BY order_id
)
SELECT
    CASE
        WHEN olt.has_missing_price THEN 'a line has no unit price'
        WHEN o.total_amount < olt.line_total THEN 'total below lines'
        ELSE 'total above lines'
    END AS direction,
    COUNT(*) AS orders,
    SUM(o.total_amount - COALESCE(olt.line_total, 0)) AS net_difference
FROM public.orders o
JOIN order_line_totals olt
    ON olt.order_id = o.order_id
WHERE olt.has_missing_price
   OR o.total_amount IS DISTINCT FROM olt.line_total
GROUP BY 1
ORDER BY 1;

-- ------------------------------------------------------------
-- Output 5: cost of each finding against the figures Nana and
-- Adwoa use. Report figures are as of 31 August 2026, the end of
-- the extract, and use the report's definition of a sale:
-- completed or complete, known customer, dated on or before the
-- report date.
-- ------------------------------------------------------------

\set report_date '''2026-08-31 23:59:59'''

-- 5a. Report total, and what it would be under narrower rules.
SELECT
    COUNT(*) FILTER (
        WHERE LOWER(BTRIM(o.status)) IN ('completed', 'complete')
    ) AS report_orders,
    SUM(o.total_amount) FILTER (
        WHERE LOWER(BTRIM(o.status)) IN ('completed', 'complete')
    ) AS report_total,
    SUM(o.total_amount) FILTER (
        WHERE LOWER(BTRIM(o.status)) = 'completed'
    ) AS total_without_complete,
    COUNT(*) FILTER (WHERE o.status = 'completed') AS exact_match_orders,
    SUM(o.total_amount) FILTER (
        WHERE o.status = 'completed'
    ) AS exact_match_total
FROM public.orders o
WHERE o.order_date <= :report_date::timestamp
  AND EXISTS (
      SELECT 1 FROM public.customers c WHERE c.customer_id = o.customer_id
  );

-- 5b. Top-100 customers replaced if 'complete' were excluded.
WITH with_complete AS (
    SELECT o.customer_id
    FROM public.orders o
    JOIN public.customers c USING (customer_id)
    WHERE LOWER(BTRIM(o.status)) IN ('completed', 'complete')
      AND o.order_date <= :report_date::timestamp
    GROUP BY o.customer_id
    ORDER BY SUM(o.total_amount) DESC, o.customer_id
    LIMIT 100
),
without_complete AS (
    SELECT o.customer_id
    FROM public.orders o
    JOIN public.customers c USING (customer_id)
    WHERE LOWER(BTRIM(o.status)) = 'completed'
      AND o.order_date <= :report_date::timestamp
    GROUP BY o.customer_id
    ORDER BY SUM(o.total_amount) DESC, o.customer_id
    LIMIT 100
)
SELECT COUNT(*) AS top100_customers_replaced
FROM with_complete
WHERE customer_id NOT IN (SELECT customer_id FROM without_complete);

-- 5c. Completed sales missing from the report because the
--     customer does not exist.
SELECT
    COUNT(*) AS unattributable_sales,
    SUM(o.total_amount) AS unattributable_value
FROM public.orders o
WHERE LOWER(BTRIM(o.status)) IN ('completed', 'complete')
  AND o.order_date <= :report_date::timestamp
  AND NOT EXISTS (
      SELECT 1 FROM public.customers c WHERE c.customer_id = o.customer_id
  );

-- 5d. Order totals against lines: mismatches inside the report,
--     the change if lines were summed instead, and how many
--     mismatches a duplicated line fully explains.
WITH line_totals AS (
    SELECT
        order_id,
        SUM(quantity * unit_price) AS line_total,
        BOOL_OR(unit_price IS NULL) AS has_missing_price
    FROM public.order_items
    GROUP BY order_id
),
deduplicated_totals AS (
    SELECT order_id, SUM(quantity * unit_price) AS line_total
    FROM (
        SELECT DISTINCT order_id, product_id, quantity, unit_price
        FROM public.order_items
    ) distinct_lines
    GROUP BY order_id
),
mismatches AS (
    SELECT
        o.total_amount,
        lt.line_total,
        lt.has_missing_price,
        dt.line_total AS deduplicated_total,
        LOWER(BTRIM(o.status)) IN ('completed', 'complete')
            AND o.order_date <= :report_date::timestamp
            AND EXISTS (
                SELECT 1 FROM public.customers c
                WHERE c.customer_id = o.customer_id
            ) AS in_report
    FROM public.orders o
    JOIN line_totals lt USING (order_id)
    JOIN deduplicated_totals dt USING (order_id)
    WHERE lt.has_missing_price
       OR o.total_amount IS DISTINCT FROM lt.line_total
)
SELECT
    COUNT(*) FILTER (WHERE in_report) AS mismatches_in_report,
    SUM(total_amount - line_total) FILTER (
        WHERE in_report AND NOT has_missing_price
    ) AS report_change_if_lines_used,
    COUNT(*) FILTER (
        WHERE total_amount = deduplicated_total
    ) AS explained_by_duplicate_line
FROM mismatches;

-- 5e. Future-dated completed sales waiting to enter the report,
--     and orders dated after the end of the extract.
SELECT
    COUNT(*) FILTER (
        WHERE order_date > LOCALTIMESTAMP
          AND LOWER(BTRIM(status)) IN ('completed', 'complete')
    ) AS future_completed_orders,
    SUM(total_amount) FILTER (
        WHERE order_date > LOCALTIMESTAMP
          AND LOWER(BTRIM(status)) IN ('completed', 'complete')
    ) AS future_completed_value,
    MIN(order_date) FILTER (
        WHERE order_date > LOCALTIMESTAMP
    )::date AS first_future_date,
    COUNT(*) FILTER (
        WHERE order_date > :report_date::timestamp
    ) AS orders_after_extract_end
FROM public.orders;

-- 5f. Duplicate customer records: spend split across them, effect
--     on the top 100, and how often the city also differs.
WITH customer_spend AS (
    SELECT
        c.customer_id,
        LOWER(BTRIM(c.email)) AS email_key,
        COALESCE(SUM(o.total_amount), 0) AS spend
    FROM public.customers c
    LEFT JOIN public.orders o
        ON o.customer_id = c.customer_id
       AND LOWER(BTRIM(o.status)) IN ('completed', 'complete')
       AND o.order_date <= :report_date::timestamp
    GROUP BY c.customer_id, LOWER(BTRIM(c.email))
),
shared_emails AS (
    SELECT email_key
    FROM customer_spend
    GROUP BY email_key
    HAVING COUNT(*) > 1
),
cut_off AS (
    SELECT spend
    FROM customer_spend
    ORDER BY spend DESC, customer_id
    LIMIT 1 OFFSET 99
),
merged AS (
    SELECT
        email_key,
        SUM(spend) AS merged_spend,
        MAX(spend) AS largest_part
    FROM customer_spend
    WHERE email_key IN (SELECT email_key FROM shared_emails)
    GROUP BY email_key
)
SELECT
    (SELECT SUM(spend)
     FROM customer_spend
     WHERE email_key IN (SELECT email_key FROM shared_emails)) AS split_spend,
    (SELECT COUNT(*)
     FROM merged, cut_off
     WHERE merged.merged_spend > cut_off.spend
       AND merged.largest_part < cut_off.spend) AS would_enter_top100_if_merged,
    (SELECT COUNT(*)
     FROM (
         SELECT 1
         FROM public.customers
         GROUP BY LOWER(BTRIM(email))
         HAVING COUNT(*) > 1
            AND COUNT(DISTINCT LOWER(BTRIM(city))) > 1
     ) differing_city) AS shared_emails_with_different_cities;

-- 5g. Stock: value of the ledger gap, gaps at low stock, products
--     showing stock the ledger says is gone, and units oversold.
WITH ledger_balance AS (
    SELECT product_id, SUM(change_qty) AS ledger_stock
    FROM public.inventory_log
    GROUP BY product_id
)
SELECT
    SUM(ABS(p.stock_quantity - lb.ledger_stock) * p.price) AS ledger_gap_value,
    COUNT(*) FILTER (WHERE p.stock_quantity <= 5) AS gaps_at_low_stock,
    COUNT(*) FILTER (
        WHERE lb.ledger_stock <= 0 AND p.stock_quantity > 0
    ) AS shows_stock_ledger_says_none,
    (SELECT SUM(-stock_quantity * price)
     FROM public.products
     WHERE stock_quantity < 0) AS oversold_value
FROM public.products p
JOIN ledger_balance lb USING (product_id)
WHERE p.stock_quantity <> lb.ledger_stock;

-- 5h. Checks behind "looks wrong, but is not" and the unresolved
--     ledger question.
SELECT
    (SELECT COUNT(*)
     FROM public.order_items oi
     JOIN public.products p USING (product_id)
     WHERE oi.unit_price <> p.price) AS lines_priced_differently_today,
    (SELECT COUNT(*)
     FROM public.customers c
     WHERE NOT EXISTS (
         SELECT 1 FROM public.orders o WHERE o.customer_id = c.customer_id
     )) AS customers_without_orders,
    (SELECT -SUM(change_qty)
     FROM public.inventory_log
     WHERE reason = 'sale') AS ledger_sale_units,
    (SELECT SUM(quantity) FROM public.order_items) AS order_line_units,
    (SELECT SUM(oi.quantity)
     FROM public.order_items oi
     JOIN public.orders o USING (order_id)
     WHERE LOWER(BTRIM(o.status)) NOT IN ('cancelled', 'canceled'))
        AS order_line_units_not_cancelled;
