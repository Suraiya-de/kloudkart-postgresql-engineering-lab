-- ============================================================
-- Kloud Kart: run everything, top to bottom
--
-- Run against a database where the course schema.sql and
-- load.sql have just been executed. With the Compose setup in
-- the README:
--
--     docker compose cp sql/. db:/tmp/sql
--     docker compose exec db psql -U postgres -d kloudkart_lab \
--         -v ON_ERROR_STOP=1 -f /tmp/sql/run_all.sql
--
-- With a local psql client, from the repository root:
--
--     psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/run_all.sql
--
-- Stage order follows the engagement: diagnose the untouched
-- data first, then deploy the solutions, then verify them.
-- ============================================================

\set ON_ERROR_STOP on
\timing on

\echo '== 1. Diagnosis (read-only, on the untouched load)'
\ir diagnostics/integrity_checks.sql

\echo '== 2. Order placement'
\ir solutions/01_place_order.sql

\echo '== 3. Customer spending report'
\ir solutions/02_customer_spending_report.sql

\echo '== 4. Low-stock category roll-up'
\ir solutions/03_low_stock_category_rollup.sql

\echo '== 5. Auditable inventory movements'
\ir solutions/04_auditable_inventory_movements.sql

\echo '== 6. Data-quality monitoring view'
\ir diagnostics/data_quality_monitoring.sql

\echo '== 7. Verification'
\ir tests/verify_solution.sql
