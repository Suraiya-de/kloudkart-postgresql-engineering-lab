
-- ============================================================
-- Kloud Kart: Requirement 2
-- Customer spending report - trailing 12 months
-- ============================================================

BEGIN;

-- Index to support completed-order reporting.
DROP INDEX IF EXISTS public.idx_orders_completed_spending;

CREATE INDEX idx_orders_completed_spending
ON public.orders (order_date, customer_id)
INCLUDE (total_amount)
WHERE LOWER(TRIM(status)) = 'completed'
  AND order_date IS NOT NULL;


-- Customer spending report.
CREATE OR REPLACE VIEW public.customer_spending_report AS

WITH eligible_orders AS (
    SELECT
        o.customer_id,
        o.order_date,
        o.total_amount
    FROM public.orders o
    INNER JOIN public.customers c
        ON c.customer_id = o.customer_id
    WHERE LOWER(TRIM(o.status)) = 'completed'
      AND o.order_date >= CURRENT_TIMESTAMP - INTERVAL '12 months'
      AND o.order_date <= CURRENT_TIMESTAMP
      AND o.total_amount IS NOT NULL
),

customer_totals AS (
    SELECT
        customer_id,
        SUM(total_amount) AS total_spent,
        COUNT(*) AS order_count
    FROM eligible_orders
    GROUP BY customer_id
),

ranked_customers AS (
    SELECT
        customer_id,
        total_spent,
        order_count,
        ROW_NUMBER() OVER (
            ORDER BY total_spent DESC, customer_id
        ) AS customer_rank
    FROM customer_totals
),

top_customers AS (
    SELECT *
    FROM ranked_customers
    WHERE customer_rank <= 100
),

monthly_spending AS (
    SELECT
        customer_id,
        DATE_TRUNC('month', order_date)::date AS spending_month,
        SUM(total_amount) AS monthly_spend
    FROM eligible_orders
    WHERE customer_id IN (
        SELECT customer_id
        FROM top_customers
    )
    GROUP BY
        customer_id,
        DATE_TRUNC('month', order_date)::date
),

calendar_months AS (
    SELECT
        GENERATE_SERIES(
            DATE_TRUNC(
                'month',
                CURRENT_TIMESTAMP - INTERVAL '12 months'
            ),
            DATE_TRUNC('month', CURRENT_TIMESTAMP),
            INTERVAL '1 month'
        )::date AS spending_month
),

monthly_grid AS (
    SELECT
        tc.customer_id,
        tc.total_spent,
        tc.order_count,
        tc.customer_rank,
        cm.spending_month,
        COALESCE(ms.monthly_spend, 0) AS monthly_spend
    FROM top_customers tc
    CROSS JOIN calendar_months cm
    LEFT JOIN monthly_spending ms
        ON ms.customer_id = tc.customer_id
       AND ms.spending_month = cm.spending_month
)

SELECT
    mg.customer_rank,
    mg.customer_id,
    c.full_name,
    mg.total_spent,
    mg.order_count,
    mg.spending_month,
    mg.monthly_spend,
    SUM(mg.monthly_spend) OVER (
        PARTITION BY mg.customer_id
        ORDER BY mg.spending_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_total
FROM monthly_grid mg
INNER JOIN public.customers c
    ON c.customer_id = mg.customer_id;

COMMIT;
