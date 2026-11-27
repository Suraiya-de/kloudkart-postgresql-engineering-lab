-- ============================================================
-- Kloud Kart: Requirement 3
-- Low-stock roll-up through the nested category tree
--
-- Input:    the course schema and data.
-- Produces: public.low_stock_by_category(p_threshold integer)
-- Asserts:  one row per category plus one row for products with
--           no category; any tree depth is walked; parent cycles
--           terminate and are flagged; returns in milliseconds
--           (see docs/validation_evidence.md).
--
-- Low stock means stock_quantity <= p_threshold (default 5), so
-- zero and negative balances are included.
-- ============================================================

BEGIN;

-- The first deployed version created these two indexes; this
-- removes them where present. Measured plans showed neither was
-- used for a 94-category, 4,023-product roll-up, and each adds
-- write cost (docs/evidence/rollup_benchmark_2026-11-27.txt).
DROP INDEX IF EXISTS public.idx_categories_parent_id;
DROP INDEX IF EXISTS public.idx_products_category_id;

CREATE OR REPLACE FUNCTION public.low_stock_by_category(
    p_threshold integer DEFAULT 5
)
RETURNS TABLE (
    category_id integer,
    category_name text,
    total_products bigint,
    total_stock_units bigint,
    low_stock_products bigint,
    low_stock_units bigint,
    hierarchy_cycle_detected boolean,
    missing_parent_detected boolean
)
LANGUAGE sql
STABLE
AS $$
    -- Walk upwards from every category to each of its ancestors.
    -- The path array stops the walk the moment an ID repeats, so
    -- a parent cycle cannot recurse forever.
    WITH RECURSIVE category_walk AS (
        SELECT
            c.category_id AS descendant_id,
            c.category_id AS ancestor_id,
            c.parent_id,
            ARRAY[c.category_id] AS path,
            FALSE AS cycle_detected,
            (
                c.parent_id IS NOT NULL
                AND NOT EXISTS (
                    SELECT 1
                    FROM public.categories p
                    WHERE p.category_id = c.parent_id
                )
            ) AS missing_parent_detected
        FROM public.categories c

        UNION ALL

        SELECT
            cw.descendant_id,
            parent.category_id,
            parent.parent_id,
            cw.path || parent.category_id,
            parent.category_id = ANY(cw.path),
            (
                parent.parent_id IS NOT NULL
                AND NOT EXISTS (
                    SELECT 1
                    FROM public.categories p
                    WHERE p.category_id = parent.parent_id
                )
            )
        FROM category_walk cw
        JOIN public.categories parent
            ON parent.category_id = cw.parent_id
        WHERE NOT cw.cycle_detected
    ),

    -- Each (descendant, ancestor) pair once, so no product is
    -- counted twice under the same ancestor.
    category_ancestors AS (
        SELECT DISTINCT
            descendant_id,
            ancestor_id
        FROM category_walk
        WHERE NOT cycle_detected
    ),

    category_quality AS (
        SELECT
            descendant_id,
            BOOL_OR(cycle_detected) AS cycle_detected,
            BOOL_OR(missing_parent_detected) AS missing_parent_detected
        FROM category_walk
        GROUP BY descendant_id
    ),

    category_rollup AS (
        SELECT
            ca.ancestor_id,
            COUNT(p.product_id)::bigint AS total_products,
            COALESCE(SUM(p.stock_quantity), 0)::bigint AS total_stock_units,
            COUNT(p.product_id) FILTER (
                WHERE p.stock_quantity <= p_threshold
            )::bigint AS low_stock_products,
            COALESCE(
                SUM(p.stock_quantity) FILTER (
                    WHERE p.stock_quantity <= p_threshold
                ),
                0
            )::bigint AS low_stock_units,
            BOOL_OR(cq.cycle_detected) AS hierarchy_cycle_detected,
            BOOL_OR(cq.missing_parent_detected) AS missing_parent_detected
        FROM category_ancestors ca
        JOIN category_quality cq
            ON cq.descendant_id = ca.descendant_id
        LEFT JOIN public.products p
            ON p.category_id = ca.descendant_id
        GROUP BY ca.ancestor_id
    )

    SELECT
        c.category_id,
        c.category_name,
        COALESCE(cr.total_products, 0),
        COALESCE(cr.total_stock_units, 0),
        COALESCE(cr.low_stock_products, 0),
        COALESCE(cr.low_stock_units, 0),
        COALESCE(cr.hierarchy_cycle_detected, FALSE),
        COALESCE(cr.missing_parent_detected, FALSE)
    FROM public.categories c
    LEFT JOIN category_rollup cr
        ON cr.ancestor_id = c.category_id

    UNION ALL

    -- Products with no category would otherwise be invisible.
    SELECT
        NULL::integer,
        '(no category assigned)',
        COUNT(*)::bigint,
        COALESCE(SUM(p.stock_quantity), 0)::bigint,
        COUNT(*) FILTER (WHERE p.stock_quantity <= p_threshold)::bigint,
        COALESCE(
            SUM(p.stock_quantity) FILTER (
                WHERE p.stock_quantity <= p_threshold
            ),
            0
        )::bigint,
        FALSE,
        FALSE
    FROM public.products p
    WHERE p.category_id IS NULL

    ORDER BY 1 NULLS LAST;
$$;

COMMIT;
