-- ============================================================
-- Kloud Kart: Requirement 2
-- Monday customer-spending report
--
-- Input:    the course schema and data; public.is_sale_status()
--           from 00_business_rules.sql.
-- Produces: public.customer_spending_report(p_as_of timestamp)
--           public.customer_spending_top100 (view)
-- Asserts:  one row per customer per month for the 12 calendar
--           months ending in the as-of month; for every customer
--           the final running_total equals total_spent; the full
--           report returns in under two seconds on a laptop (see
--           docs/evidence/report_benchmark_2026-11-27.txt).
--
-- Definitions (see docs/technical_decisions.md, section 3):
--   * A sale is an order for which is_sale_status(status) is true:
--     the status, ignoring case and spaces, is 'completed' or
--     'complete'.
--   * Spend is orders.total_amount, the amount charged at
--     checkout, not the sum of order lines.
--   * total_spent and order_count cover every completed order up
--     to p_as_of. Orders dated after p_as_of are excluded.
--   * running_total starts from the customer's spend before the
--     12-month window, so the last month equals total_spent.
--   * Orders whose customer does not exist cannot be attributed
--     and are excluded; the diagnosis quantifies them.
--   * Customers with no sale up to p_as_of still get their 12
--     rows, with zero spend, zero orders and a zero running total.
-- ============================================================

\set ON_ERROR_STOP on

BEGIN;

-- Makes the script re-runnable, and replaces the view and index
-- of the first deployed version where that version is present.
DROP VIEW IF EXISTS public.customer_spending_top100;
DROP VIEW IF EXISTS public.customer_spending_report;

-- No supporting index is created. A partial covering index made
-- the full report only 11% faster (1,635 ms to 1,459 ms), while
-- every index on orders adds work to each flash-sale insert.
-- See docs/evidence/report_benchmark_2026-11-27.txt.
DROP INDEX IF EXISTS public.idx_orders_completed_spending;

CREATE OR REPLACE FUNCTION public.customer_spending_report(
    p_as_of timestamp DEFAULT LOCALTIMESTAMP
)
RETURNS TABLE (
    spend_rank bigint,
    customer_id integer,
    full_name text,
    total_spent numeric,
    order_count bigint,
    spending_month date,
    monthly_spend numeric,
    running_total numeric
)
LANGUAGE sql
STABLE
AS $$
    WITH completed_orders AS (
        SELECT
            o.customer_id,
            o.order_date,
            o.total_amount
        FROM public.orders o
        WHERE public.is_sale_status(o.status)
          AND o.order_date <= p_as_of
          AND o.total_amount IS NOT NULL
    ),

    report_months AS (
        SELECT GENERATE_SERIES(
            DATE_TRUNC('month', p_as_of) - INTERVAL '11 months',
            DATE_TRUNC('month', p_as_of),
            INTERVAL '1 month'
        )::date AS spending_month
    ),

    -- One pass over the orders: lifetime totals and monthly
    -- spend inside the window are computed together.
    customer_orders AS (
        SELECT
            co.customer_id,
            SUM(co.total_amount) AS total_spent,
            COUNT(*) AS order_count,
            SUM(co.total_amount) FILTER (
                WHERE co.order_date
                    < DATE_TRUNC('month', p_as_of) - INTERVAL '11 months'
            ) AS spent_before_window
        FROM completed_orders co
        GROUP BY co.customer_id
    ),

    customer_totals AS (
        SELECT
            ROW_NUMBER() OVER (
                ORDER BY COALESCE(cord.total_spent, 0) DESC, c.customer_id
            ) AS spend_rank,
            c.customer_id,
            c.full_name,
            COALESCE(cord.total_spent, 0) AS total_spent,
            COALESCE(cord.order_count, 0) AS order_count,
            COALESCE(cord.spent_before_window, 0) AS spent_before_window
        FROM public.customers c
        LEFT JOIN customer_orders cord
            ON cord.customer_id = c.customer_id
    ),

    monthly_spend AS (
        SELECT
            co.customer_id,
            DATE_TRUNC('month', co.order_date)::date AS spending_month,
            SUM(co.total_amount) AS monthly_spend
        FROM completed_orders co
        WHERE co.order_date
            >= DATE_TRUNC('month', p_as_of) - INTERVAL '11 months'
        GROUP BY
            co.customer_id,
            DATE_TRUNC('month', co.order_date)::date
    )

    SELECT
        ct.spend_rank,
        ct.customer_id,
        ct.full_name,
        ct.total_spent,
        ct.order_count,
        rm.spending_month,
        COALESCE(ms.monthly_spend, 0) AS monthly_spend,
        ct.spent_before_window
            + SUM(COALESCE(ms.monthly_spend, 0)) OVER (
                PARTITION BY ct.customer_id
                ORDER BY rm.spending_month
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS running_total
    FROM customer_totals ct
    CROSS JOIN report_months rm
    LEFT JOIN monthly_spend ms
        ON ms.customer_id = ct.customer_id
       AND ms.spending_month = rm.spending_month
    ORDER BY ct.spend_rank, rm.spending_month;
$$;

-- Top 100 customers as of today, ready to open.
CREATE VIEW public.customer_spending_top100 AS
SELECT *
FROM public.customer_spending_report()
WHERE spend_rank <= 100;

COMMIT;
