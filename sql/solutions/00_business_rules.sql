-- ============================================================
-- Kloud Kart: Business rules shared by every script
--
-- Input:    the course schema.
-- Produces: public.is_sale_status(text)
-- Asserts:  nothing is read or changed; this only defines rules,
--           so it can run before the diagnosis without touching
--           the data.
--
-- Every script that needs to know which orders are sales calls
-- this function: the diagnosis, the report, the verification
-- tests and the benchmark. They cannot drift apart, and a change
-- of rule is made here only.
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

COMMIT;
