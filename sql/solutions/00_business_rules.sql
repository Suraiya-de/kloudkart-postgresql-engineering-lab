-- ============================================================
-- Kloud Kart: Business rules shared by every script
--
-- Input:    the course schema.
-- Produces: public.is_sale_status(text)
--           public.is_cancelled_status(text)
--           public.is_standard_status(text)
-- Asserts:  nothing is read or changed; this only defines rules,
--           so it can run before the diagnosis without touching
--           the data.
--
-- Every script that needs to classify an order status calls one
-- of these functions: the diagnosis, the report, the monitoring
-- view, the verification tests and the benchmark. They cannot
-- drift apart, and a change of rule is made here only.
-- ============================================================

\set ON_ERROR_STOP on

BEGIN;

-- A sale is an order whose status, ignoring case and surrounding
-- spaces, is 'completed' or 'complete'. 'complete' is included
-- because it matches the four spellings of 'completed' in volume,
-- value and date range (data diagnosis 3.2). If the business
-- confirms a different rule, change this list only.
CREATE OR REPLACE FUNCTION public.is_sale_status(p_status text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT LOWER(BTRIM(p_status)) IN ('completed', 'complete');
$$;

-- A cancelled order, in either spelling found in the data
-- ('cancelled' and 'canceled'), ignoring case and spaces.
CREATE OR REPLACE FUNCTION public.is_cancelled_status(p_status text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT LOWER(BTRIM(p_status)) IN ('cancelled', 'canceled');
$$;

-- The agreed status vocabulary, written exactly: lower case, no
-- spaces, one spelling each. Anything else (including 'complete',
-- 'canceled' and every capitalised or padded variant) is reported
-- by the monitoring view as non-standard.
CREATE OR REPLACE FUNCTION public.is_standard_status(p_status text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT p_status IN (
        'pending', 'shipped', 'completed', 'cancelled', 'refunded'
    );
$$;

COMMIT;
