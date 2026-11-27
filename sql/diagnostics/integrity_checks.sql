
-- Kloud Kart: Initial data integrity checks
-- These checks investigate potential problems.
-- They do not modify or clean any data.

WITH RECURSIVE category_walk (
    start_id,
    current_id,
    parent_id,
    path,
    cycle_detected
) AS (
    SELECT
        c.category_id,
        c.category_id,
        c.parent_id,
        ARRAY[c.category_id],
        FALSE
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
        cw.path[
            array_position(cw.path, cw.current_id):cardinality(cw.path)
        ]
    ) AS cycle_node(category_id)
    WHERE cw.cycle_detected
)

SELECT
    'orphan_categories' AS check_name,
    COUNT(*) AS violation_count
FROM public.categories c
LEFT JOIN public.categories p
    ON c.parent_id = p.category_id
WHERE c.parent_id IS NOT NULL
  AND p.category_id IS NULL

UNION ALL

SELECT
    'orphan_products' AS check_name,
    COUNT(*) AS violation_count
FROM public.products p
LEFT JOIN public.categories c
    ON p.category_id = c.category_id
WHERE p.category_id IS NOT NULL
  AND c.category_id IS NULL

UNION ALL

SELECT
    'orphan_orders' AS check_name,
    COUNT(*) AS violation_count
FROM public.orders o
LEFT JOIN public.customers c
    ON o.customer_id = c.customer_id
WHERE o.customer_id IS NOT NULL
  AND c.customer_id IS NULL

UNION ALL

SELECT
    'orphan_order_items_orders' AS check_name,
    COUNT(*) AS violation_count
FROM public.order_items oi
LEFT JOIN public.orders o
    ON oi.order_id = o.order_id
WHERE oi.order_id IS NOT NULL
  AND o.order_id IS NULL

UNION ALL

SELECT
    'orphan_order_items_products' AS check_name,
    COUNT(*) AS violation_count
FROM public.order_items oi
LEFT JOIN public.products p
    ON oi.product_id = p.product_id
WHERE oi.product_id IS NOT NULL
  AND p.product_id IS NULL

UNION ALL

SELECT
    'orphan_inventory_logs' AS check_name,
    COUNT(*) AS violation_count
FROM public.inventory_log il
LEFT JOIN public.products p
    ON il.product_id = p.product_id
WHERE il.product_id IS NOT NULL
  AND p.product_id IS NULL

UNION ALL

SELECT
    'negative_product_prices' AS check_name,
    COUNT(*) AS violation_count
FROM public.products
WHERE price < 0

UNION ALL

SELECT
    'invalid_order_quantities' AS check_name,
    COUNT(*) AS violation_count
FROM public.order_items
WHERE quantity <= 0

UNION ALL

SELECT
    'negative_stock' AS check_name,
    COUNT(*) AS violation_count
FROM public.products
WHERE stock_quantity < 0

UNION ALL

SELECT
    'products_without_category' AS check_name,
    COUNT(*) AS violation_count
FROM public.products
WHERE category_id IS NULL

UNION ALL

SELECT
    'categories_in_parent_cycles' AS check_name,
    COUNT(*) AS violation_count
FROM cycle_members;
