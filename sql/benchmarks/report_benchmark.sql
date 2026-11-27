-- ============================================================
-- Kloud Kart: Monday report, before and after
--
-- Input:    a fresh load with solutions 00 and 02 deployed. Every
--           variant uses public.is_sale_status(), so all five
--           measure the same definition of a sale.
-- Produces: EXPLAIN ANALYZE timings for five variants, recorded
--           in docs/evidence/report_benchmark_2026-11-27.txt.
-- Asserts:  nothing; this is a measurement.
--
-- Run only on a disposable copy: it creates and drops indexes
-- and changes work_mem for the session. With the Compose setup
-- in the README:
--
--     docker compose cp sql/. db:/tmp/sql
--     docker compose exec db psql -U postgres -d kloudkart_lab \
--         -f /tmp/sql/benchmarks/report_benchmark.sql
-- ============================================================

\set ON_ERROR_STOP on
\pset pager off

-- Remove benchmark indexes left behind by an interrupted run.
DROP INDEX IF EXISTS bench_orders_customer;
DROP INDEX IF EXISTS bench_orders_completed;
\set as_of '''2026-08-31 23:59:59'''

SELECT version();

-- ------------------------------------------------------------
-- A. Naive report: one correlated lookup per figure, per
--    customer, per month. Run on 100 customers and extrapolated,
--    because the full run takes hours.
-- ------------------------------------------------------------

CREATE TEMP TABLE sample_customers AS
SELECT customer_id
FROM customers
ORDER BY customer_id
LIMIT 100;

ANALYZE sample_customers;

\echo '==== A. Naive report, 100 customers, no index'
EXPLAIN (ANALYZE, SUMMARY, TIMING OFF, COSTS OFF)
WITH months AS (
    SELECT generate_series(
        date_trunc('month', :as_of::timestamp) - interval '11 months',
        date_trunc('month', :as_of::timestamp),
        interval '1 month'
    )::date AS m
)
SELECT
    c.customer_id,
    c.full_name,
    (SELECT SUM(total_amount) FROM orders o
     WHERE o.customer_id = c.customer_id
       AND public.is_sale_status(o.status)
       AND o.order_date <= :as_of::timestamp) AS total_spent,
    (SELECT COUNT(*) FROM orders o
     WHERE o.customer_id = c.customer_id
       AND public.is_sale_status(o.status)
       AND o.order_date <= :as_of::timestamp) AS order_count,
    months.m,
    (SELECT COALESCE(SUM(total_amount), 0) FROM orders o
     WHERE o.customer_id = c.customer_id
       AND public.is_sale_status(o.status)
       AND o.order_date >= months.m
       AND o.order_date < months.m + interval '1 month') AS monthly_spend,
    (SELECT COALESCE(SUM(total_amount), 0) FROM orders o
     WHERE o.customer_id = c.customer_id
       AND public.is_sale_status(o.status)
       AND o.order_date < months.m + interval '1 month') AS running_total
FROM customers c
JOIN sample_customers s USING (customer_id)
CROSS JOIN months;

-- ------------------------------------------------------------
-- B. The same naive report with an index on orders(customer_id).
-- ------------------------------------------------------------

CREATE INDEX bench_orders_customer ON orders (customer_id);
ANALYZE orders;

\echo '==== B. Naive report, 100 customers, index on orders(customer_id)'
EXPLAIN (ANALYZE, SUMMARY, TIMING OFF, COSTS OFF)
WITH months AS (
    SELECT generate_series(
        date_trunc('month', :as_of::timestamp) - interval '11 months',
        date_trunc('month', :as_of::timestamp),
        interval '1 month'
    )::date AS m
)
SELECT
    c.customer_id,
    c.full_name,
    (SELECT SUM(total_amount) FROM orders o
     WHERE o.customer_id = c.customer_id
       AND public.is_sale_status(o.status)
       AND o.order_date <= :as_of::timestamp) AS total_spent,
    (SELECT COUNT(*) FROM orders o
     WHERE o.customer_id = c.customer_id
       AND public.is_sale_status(o.status)
       AND o.order_date <= :as_of::timestamp) AS order_count,
    months.m,
    (SELECT COALESCE(SUM(total_amount), 0) FROM orders o
     WHERE o.customer_id = c.customer_id
       AND public.is_sale_status(o.status)
       AND o.order_date >= months.m
       AND o.order_date < months.m + interval '1 month') AS monthly_spend,
    (SELECT COALESCE(SUM(total_amount), 0) FROM orders o
     WHERE o.customer_id = c.customer_id
       AND public.is_sale_status(o.status)
       AND o.order_date < months.m + interval '1 month') AS running_total
FROM customers c
JOIN sample_customers s USING (customer_id)
CROSS JOIN months;

DROP INDEX bench_orders_customer;
ANALYZE orders;

-- ------------------------------------------------------------
-- C. Set-based report (solution 02), all customers, 5 runs.
-- ------------------------------------------------------------

\echo '==== C. Set-based report, all customers, no extra index: 5 runs'
EXPLAIN (ANALYZE, SUMMARY, TIMING OFF, COSTS OFF) SELECT * FROM customer_spending_report(:as_of);
EXPLAIN (ANALYZE, SUMMARY, TIMING OFF, COSTS OFF) SELECT * FROM customer_spending_report(:as_of);
EXPLAIN (ANALYZE, SUMMARY, TIMING OFF, COSTS OFF) SELECT * FROM customer_spending_report(:as_of);
EXPLAIN (ANALYZE, SUMMARY, TIMING OFF, COSTS OFF) SELECT * FROM customer_spending_report(:as_of);
EXPLAIN (ANALYZE, SUMMARY, TIMING OFF, COSTS OFF) SELECT * FROM customer_spending_report(:as_of);

-- ------------------------------------------------------------
-- D. C plus a partial covering index on completed orders.
-- ------------------------------------------------------------

CREATE INDEX bench_orders_completed
    ON orders (customer_id, order_date)
    INCLUDE (total_amount)
    WHERE public.is_sale_status(status);
VACUUM ANALYZE orders;

\echo '==== D. Set-based report with a partial covering index: 5 runs'
EXPLAIN (ANALYZE, SUMMARY, TIMING OFF, COSTS OFF) SELECT * FROM customer_spending_report(:as_of);
EXPLAIN (ANALYZE, SUMMARY, TIMING OFF, COSTS OFF) SELECT * FROM customer_spending_report(:as_of);
EXPLAIN (ANALYZE, SUMMARY, TIMING OFF, COSTS OFF) SELECT * FROM customer_spending_report(:as_of);
EXPLAIN (ANALYZE, SUMMARY, TIMING OFF, COSTS OFF) SELECT * FROM customer_spending_report(:as_of);
EXPLAIN (ANALYZE, SUMMARY, TIMING OFF, COSTS OFF) SELECT * FROM customer_spending_report(:as_of);

DROP INDEX bench_orders_completed;
ANALYZE orders;

-- ------------------------------------------------------------
-- E. C with work_mem raised so the sorts stay in memory.
-- ------------------------------------------------------------

SET work_mem = '64MB';

\echo '==== E. Set-based report with work_mem 64MB: 5 runs'
EXPLAIN (ANALYZE, SUMMARY, TIMING OFF, COSTS OFF) SELECT * FROM customer_spending_report(:as_of);
EXPLAIN (ANALYZE, SUMMARY, TIMING OFF, COSTS OFF) SELECT * FROM customer_spending_report(:as_of);
EXPLAIN (ANALYZE, SUMMARY, TIMING OFF, COSTS OFF) SELECT * FROM customer_spending_report(:as_of);
EXPLAIN (ANALYZE, SUMMARY, TIMING OFF, COSTS OFF) SELECT * FROM customer_spending_report(:as_of);
EXPLAIN (ANALYZE, SUMMARY, TIMING OFF, COSTS OFF) SELECT * FROM customer_spending_report(:as_of);

RESET work_mem;
