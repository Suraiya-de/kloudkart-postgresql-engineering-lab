
-- Kloud Kart: Reusable Data Quality Monitoring View
-- Reports current data-quality issues without modifying source data.
-- Requires public.low_stock_by_category() from solution 03.

CREATE OR REPLACE VIEW public.data_quality_monitoring AS

WITH category_health AS (
    SELECT *
    FROM public.low_stock_by_category(5)
),

checks AS (

    SELECT
        'orphan_categories'::text AS check_name,
        COUNT(*)::bigint AS violation_count,
        'HIGH'::text AS severity,
        'Categories referencing missing parent categories'::text AS description
    FROM public.categories c
    LEFT JOIN public.categories p
        ON c.parent_id = p.category_id
    WHERE c.parent_id IS NOT NULL
      AND p.category_id IS NULL

    UNION ALL

    SELECT
        'orphan_orders',
        COUNT(*)::bigint,
        'HIGH',
        'Orders referencing missing customers'
    FROM public.orders o
    LEFT JOIN public.customers c
        ON o.customer_id = c.customer_id
    WHERE o.customer_id IS NOT NULL
      AND c.customer_id IS NULL

    UNION ALL

    SELECT
        'orphan_order_items',
        COUNT(*)::bigint,
        'HIGH',
        'Order items referencing missing orders'
    FROM public.order_items oi
    LEFT JOIN public.orders o
        ON oi.order_id = o.order_id
    WHERE oi.order_id IS NOT NULL
      AND o.order_id IS NULL


    UNION ALL

    SELECT
        'orphan_order_items_products',
        COUNT(*)::bigint,
        'HIGH',
        'Order items referencing missing products'
    FROM public.order_items oi
    LEFT JOIN public.products p
        ON oi.product_id = p.product_id
    WHERE oi.product_id IS NOT NULL
      AND p.product_id IS NULL

    UNION ALL

    SELECT
        'orphan_inventory_logs',
        COUNT(*)::bigint,
        'HIGH',
        'Inventory movements referencing missing products'
    FROM public.inventory_log il
    LEFT JOIN public.products p
        ON il.product_id = p.product_id
    WHERE il.product_id IS NOT NULL
      AND p.product_id IS NULL

    UNION ALL

    SELECT
        'negative_product_prices',
        COUNT(*)::bigint,
        'HIGH',
        'Products with prices below zero'
    FROM public.products
    WHERE price < 0

    UNION ALL

    SELECT
        'invalid_order_quantities',
        COUNT(*)::bigint,
        'HIGH',
        'Order items with zero or negative quantities'
    FROM public.order_items
    WHERE quantity <= 0

    UNION ALL

    SELECT
        'negative_stock',
        COUNT(*)::bigint,
        'HIGH',
        'Products with stock quantities below zero'
    FROM public.products
    WHERE stock_quantity < 0

    UNION ALL

    SELECT
        'zero_stock',
        COUNT(*)::bigint,
        'INFO',
        'Products at zero stock; availability signal, not necessarily a data defect'
    FROM public.products
    WHERE stock_quantity = 0

    UNION ALL

    SELECT
        'nonstandard_order_statuses',
        COUNT(*)::bigint,
        'MEDIUM',
        'Orders with null, non-standard, unconfirmed or non-normalised status values'
    FROM public.orders
    WHERE status IS NULL
       OR LOWER(BTRIM(status)) NOT IN (
           'pending',
           'shipped',
           'completed',
           'cancelled',
           'refunded'
       )
       OR status <> LOWER(BTRIM(status))

    UNION ALL

    SELECT
        'categories_affected_by_cycles',
        COUNT(*)::bigint,
        'HIGH',
        'Categories affected by circular parent relationships'
    FROM category_health
    WHERE hierarchy_cycle_detected

    UNION ALL

    SELECT
        'categories_with_missing_parents',
        COUNT(*)::bigint,
        'HIGH',
        'Categories affected by missing parent relationships'
    FROM category_health
    WHERE missing_parent_detected
)

SELECT
    check_name,
    violation_count,
    severity,
    description,
    CURRENT_TIMESTAMP AS checked_at
FROM checks;
