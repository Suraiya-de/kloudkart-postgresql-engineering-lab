
-- Kloud Kart: Initial data integrity checks
-- These checks investigate potential problems.
-- They do not modify or clean any data.

SELECT
    'orphan_categories' AS check_name,
    COUNT(*) AS violation_count
FROM categories c
LEFT JOIN categories p
    ON c.parent_id = p.category_id
WHERE c.parent_id IS NOT NULL
  AND p.category_id IS NULL

UNION ALL

SELECT
    'orphan_products' AS check_name,
    COUNT(*) AS violation_count
FROM products p
LEFT JOIN categories c
    ON p.category_id = c.category_id
WHERE p.category_id IS NOT NULL
  AND c.category_id IS NULL

UNION ALL

SELECT
    'orphan_orders' AS check_name,
    COUNT(*) AS violation_count
FROM orders o
LEFT JOIN customers c
    ON o.customer_id = c.customer_id
WHERE o.customer_id IS NOT NULL
  AND c.customer_id IS NULL

UNION ALL

SELECT
    'orphan_order_items_orders' AS check_name,
    COUNT(*) AS violation_count
FROM order_items oi
LEFT JOIN orders o
    ON oi.order_id = o.order_id
WHERE oi.order_id IS NOT NULL
  AND o.order_id IS NULL

UNION ALL

SELECT
    'orphan_order_items_products' AS check_name,
    COUNT(*) AS violation_count
FROM order_items oi
LEFT JOIN products p
    ON oi.product_id = p.product_id
WHERE oi.product_id IS NOT NULL
  AND p.product_id IS NULL

UNION ALL

SELECT
    'orphan_inventory_logs' AS check_name,
    COUNT(*) AS violation_count
FROM inventory_log il
LEFT JOIN products p
    ON il.product_id = p.product_id
WHERE il.product_id IS NOT NULL
  AND p.product_id IS NULL

UNION ALL

SELECT
    'negative_product_prices' AS check_name,
    COUNT(*) AS violation_count
FROM products
WHERE price < 0

UNION ALL

SELECT
    'invalid_order_quantities' AS check_name,
    COUNT(*) AS violation_count
FROM order_items
WHERE quantity <= 0;
