-- ============================================================
-- Kloud Kart: Solution verification
--
-- Input:    a fresh load with solutions 00-04 and the monitoring
--           view deployed (run_all.sql does this).
-- Produces: one NOTICE per passed assertion; stops on the first
--           failure.
-- Asserts:  report and roll-up reconcile with independent
--           queries; order placement, inventory movements, the
--           audit trigger and the stock constraint behave as
--           documented. Every write is rolled back.
--
-- Expected values are derived from the data, not hard-coded, so
-- the assertions hold for any extract, including a clean one.
--
-- Section 3 runs inside BEGIN ... ROLLBACK. Its negative-stock
-- test catches check_violation in a PL/pgSQL EXCEPTION block,
-- which runs the failing statement in its own subtransaction.
-- PostgreSQL rolls back only that subtransaction, so the outer
-- transaction is never left aborted (documented behaviour in
-- every supported version); the final ROLLBACK then discards all
-- of section 3's writes.
--
-- The concurrency guarantee is proven separately by the course
-- race_test.py; see docs/validation_evidence.md.
-- ============================================================

\set ON_ERROR_STOP on
\pset pager off

-- ------------------------------------------------------------
-- 1. Customer spending report (as of the end of the extract)
-- ------------------------------------------------------------

DO $$
DECLARE
    v_as_of constant timestamp := '2026-08-31 23:59:59';
    v_customers bigint;
    v_rows bigint;
    v_unreconciled bigint;
    v_report_total numeric;
    v_independent_total numeric;
    v_top100_rows bigint;
    v_top100_customers bigint;
BEGIN
    SELECT COUNT(*) INTO v_customers FROM public.customers;

    SELECT
        COUNT(*),
        COUNT(*) FILTER (
            WHERE spending_month = DATE '2026-08-01'
              AND running_total <> total_spent
        ),
        SUM(total_spent) FILTER (WHERE spending_month = DATE '2026-08-01')
    INTO v_rows, v_unreconciled, v_report_total
    FROM public.customer_spending_report(v_as_of);

    IF v_rows <> v_customers * 12 THEN
        RAISE EXCEPTION 'Report has % rows, expected % (12 per customer)',
            v_rows, v_customers * 12;
    END IF;
    RAISE NOTICE 'PASS report: % rows = 12 months x % customers',
        v_rows, v_customers;

    IF v_unreconciled <> 0 THEN
        RAISE EXCEPTION '% customers whose final running_total <> total_spent',
            v_unreconciled;
    END IF;
    RAISE NOTICE 'PASS report: every final running_total equals total_spent';

    SELECT SUM(o.total_amount)
    INTO v_independent_total
    FROM public.orders o
    WHERE public.is_sale_status(o.status)
      AND o.order_date <= v_as_of
      AND EXISTS (
          SELECT 1 FROM public.customers c WHERE c.customer_id = o.customer_id
      );

    IF v_report_total IS DISTINCT FROM v_independent_total THEN
        RAISE EXCEPTION 'Report total % <> independent total %',
            v_report_total, v_independent_total;
    END IF;
    RAISE NOTICE 'PASS report: total spend % matches an independent sum',
        v_report_total;

    SELECT COUNT(*), COUNT(DISTINCT customer_id)
    INTO v_top100_rows, v_top100_customers
    FROM public.customer_spending_top100;

    IF v_top100_customers <> LEAST(100, v_customers)
       OR v_top100_rows <> 12 * v_top100_customers THEN
        RAISE EXCEPTION 'Top-100 view has % rows for % customers, expected 12 rows for each of % customers',
            v_top100_rows, v_top100_customers, LEAST(100, v_customers);
    END IF;
    RAISE NOTICE 'PASS report: top-100 view returns % customers x 12 months',
        v_top100_customers;
END;
$$;

-- ------------------------------------------------------------
-- 2. Low-stock category roll-up
-- ------------------------------------------------------------

DO $$
DECLARE
    v_from_roots bigint;
    v_cycle_only bigint;
    v_all_products bigint;
    v_rollup_electronics bigint;
    v_independent_electronics bigint;
    v_cycle_flags bigint;
    v_missing_parent_flags bigint;
    v_expected_cycle_flags bigint;
    v_expected_missing_parent_flags bigint;
BEGIN
    SELECT
        SUM(r.total_products) FILTER (
            WHERE r.category_id IS NULL
               OR r.category_id IN (
                   SELECT category_id FROM public.categories WHERE parent_id IS NULL
               )
        ),
        COUNT(*) FILTER (WHERE r.hierarchy_cycle_detected),
        COUNT(*) FILTER (WHERE r.missing_parent_detected)
    INTO v_from_roots, v_cycle_flags, v_missing_parent_flags
    FROM public.low_stock_by_category(5) r;

    -- Products under a cycle have no root; count them once.
    SELECT COUNT(*)
    INTO v_cycle_only
    FROM public.products p
    WHERE p.category_id IN (
        SELECT category_id
        FROM public.low_stock_by_category(5)
        WHERE hierarchy_cycle_detected
    );

    SELECT COUNT(*) INTO v_all_products FROM public.products;

    IF v_from_roots + v_cycle_only <> v_all_products THEN
        RAISE EXCEPTION 'Roll-up covers % products, table has %',
            v_from_roots + v_cycle_only, v_all_products;
    END IF;
    RAISE NOTICE 'PASS roll-up: roots + uncategorised + cycle members = % products',
        v_all_products;

    SELECT total_products
    INTO v_rollup_electronics
    FROM public.low_stock_by_category(5)
    WHERE category_name = 'Electronics';

    WITH RECURSIVE subtree AS (
        SELECT category_id
        FROM public.categories
        WHERE category_name = 'Electronics'
        UNION
        SELECT c.category_id
        FROM public.categories c
        JOIN subtree s ON c.parent_id = s.category_id
    )
    SELECT COUNT(*)
    INTO v_independent_electronics
    FROM public.products
    WHERE category_id IN (SELECT category_id FROM subtree);

    IF v_rollup_electronics <> v_independent_electronics THEN
        RAISE EXCEPTION 'Electronics roll-up % <> independent count %',
            v_rollup_electronics, v_independent_electronics;
    END IF;
    RAISE NOTICE 'PASS roll-up: Electronics (% products) matches a top-down walk',
        v_rollup_electronics;

    -- Independent count of the same defects, using PostgreSQL's
    -- built-in CYCLE clause instead of the roll-up's path array.
    -- A category is affected if its upward walk revisits a
    -- category, or ends at a parent that does not exist.
    WITH RECURSIVE walk (start_id, category_id, parent_id) AS (
        SELECT category_id, category_id, parent_id
        FROM public.categories

        UNION ALL

        SELECT w.start_id, c.category_id, c.parent_id
        FROM walk w
        JOIN public.categories c
            ON c.category_id = w.parent_id
    ) CYCLE category_id SET is_cycle USING visited
    SELECT
        COUNT(DISTINCT start_id) FILTER (WHERE is_cycle),
        COUNT(DISTINCT start_id) FILTER (
            WHERE NOT is_cycle
              AND parent_id IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1
                  FROM public.categories p
                  WHERE p.category_id = walk.parent_id
              )
        )
    INTO v_expected_cycle_flags, v_expected_missing_parent_flags
    FROM walk;

    IF v_cycle_flags <> v_expected_cycle_flags
       OR v_missing_parent_flags <> v_expected_missing_parent_flags THEN
        RAISE EXCEPTION 'Roll-up flags cycle % / missing parent %, independent walk finds % / %',
            v_cycle_flags, v_missing_parent_flags,
            v_expected_cycle_flags, v_expected_missing_parent_flags;
    END IF;
    RAISE NOTICE 'PASS roll-up: % cycle and % missing-parent categories flagged, matching an independent walk; query terminated',
        v_cycle_flags, v_missing_parent_flags;
END;
$$;

-- ------------------------------------------------------------
-- 3. Writes: order placement, movements, trigger, constraint.
--    Everything below is rolled back.
-- ------------------------------------------------------------

BEGIN;

DO $$
DECLARE
    v_product_id integer;
    v_customer_id integer;
    v_stock integer;
    v_log_before bigint;
    v_log_after bigint;
    v_result record;
BEGIN
    SELECT product_id, stock_quantity
    INTO v_product_id, v_stock
    FROM public.products
    WHERE stock_quantity >= 10
    ORDER BY product_id
    LIMIT 1;

    IF v_product_id IS NULL THEN
        RAISE EXCEPTION 'Verification needs a product with at least 10 units in stock; none exists in this load';
    END IF;

    SELECT MIN(customer_id) INTO v_customer_id FROM public.customers;

    IF v_customer_id IS NULL THEN
        RAISE EXCEPTION 'Verification needs at least one customer; the customers table is empty';
    END IF;

    -- 3a. Asking for more than exists is refused, stock untouched.
    SELECT * INTO v_result
    FROM public.place_order(v_customer_id, v_product_id, v_stock + 1);

    IF v_result.success OR v_result.message NOT ILIKE '%out of stock%'
       OR (SELECT stock_quantity FROM public.products
           WHERE product_id = v_product_id) <> v_stock THEN
        RAISE EXCEPTION 'Oversized order was not refused cleanly: %',
            v_result.message;
    END IF;
    RAISE NOTICE 'PASS place_order: oversized request refused with "%"',
        v_result.message;

    -- 3b. A successful order writes exactly one log row.
    SELECT COUNT(*) INTO v_log_before
    FROM public.inventory_log WHERE product_id = v_product_id;

    SELECT * INTO v_result
    FROM public.place_order(v_customer_id, v_product_id, 2);

    SELECT COUNT(*) INTO v_log_after
    FROM public.inventory_log WHERE product_id = v_product_id;

    IF NOT v_result.success OR v_log_after - v_log_before <> 1 THEN
        RAISE EXCEPTION 'Order placed % with % new log rows',
            v_result.success, v_log_after - v_log_before;
    END IF;
    RAISE NOTICE 'PASS place_order: order % placed, exactly one movement logged',
        v_result.order_id;

    -- 3c. A restock writes exactly one log row (no trigger duplicate).
    v_log_before := v_log_after;

    SELECT * INTO v_result
    FROM public.record_inventory_movement(
        v_product_id, 5, 'restock', 'Verification restock'
    );

    SELECT COUNT(*) INTO v_log_after
    FROM public.inventory_log WHERE product_id = v_product_id;

    IF NOT v_result.success OR v_log_after - v_log_before <> 1 THEN
        RAISE EXCEPTION 'Restock % with % new log rows',
            v_result.success, v_log_after - v_log_before;
    END IF;
    RAISE NOTICE 'PASS record_inventory_movement: restock logged once';

    -- 3d. A refused movement changes nothing.
    v_log_before := v_log_after;
    v_stock := (SELECT stock_quantity FROM public.products
                WHERE product_id = v_product_id);

    SELECT * INTO v_result
    FROM public.record_inventory_movement(
        v_product_id, -(v_stock + 1), 'damage', 'Verification over-deduction'
    );

    SELECT COUNT(*) INTO v_log_after
    FROM public.inventory_log WHERE product_id = v_product_id;

    IF v_result.success
       OR v_log_after <> v_log_before
       OR (SELECT stock_quantity FROM public.products
           WHERE product_id = v_product_id) <> v_stock THEN
        RAISE EXCEPTION 'Refused movement left a change behind';
    END IF;
    RAISE NOTICE 'PASS record_inventory_movement: refused movement left stock and log unchanged';

    -- 3e. A direct UPDATE is caught by the audit trigger.
    v_log_before := v_log_after;

    UPDATE public.products
    SET stock_quantity = stock_quantity - 1
    WHERE product_id = v_product_id;

    IF NOT EXISTS (
        SELECT 1
        FROM public.inventory_log
        WHERE product_id = v_product_id
          AND reason = 'unlogged_update'
          AND change_qty = -1
    ) THEN
        RAISE EXCEPTION 'Direct stock update was not logged';
    END IF;
    RAISE NOTICE 'PASS audit trigger: direct UPDATE recorded as unlogged_update';

    -- 3f. Stock can no longer be written below zero.
    BEGIN
        UPDATE public.products
        SET stock_quantity = -1
        WHERE product_id = v_product_id;

        RAISE EXCEPTION 'Negative stock was accepted';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS constraint: negative stock rejected';
    END;
END;
$$;

ROLLBACK;

-- ------------------------------------------------------------
-- 4. Monitoring view output, for the evidence log.
-- ------------------------------------------------------------

SELECT
    severity,
    check_name,
    violation_count,
    description
FROM public.data_quality_monitoring
ORDER BY severity_rank, violation_count DESC, check_name;
