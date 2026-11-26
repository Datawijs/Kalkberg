-- =====================================================================
-- Kalkberg profiling - round 3: follow-up checks on open questions from round 2
-- Run from the project folder (the folder that contains 'profiling'), after round 2:
--   psql -U [username] -d kalkberg -f profiling/03-run-follow-up-checks.sql
--
-- Creates the checks in profiling/checks/follow_up.sql and exports each one to
-- profiling/results/round-3/<view>.csv. Bronze tables are only read, never changed.
-- Uses the helper function profiling.sfmc_timestamp, created in round 2.
-- =====================================================================

\set ON_ERROR_STOP on
\timing on

SET work_mem = '256MB';

\echo 'Creating the follow-up checks ...'
DO $$
DECLARE
    v record;
BEGIN
    FOR v IN SELECT table_name FROM information_schema.views WHERE table_schema = 'profiling' AND table_name LIKE 'f\_%' LOOP
        EXECUTE format('DROP VIEW IF EXISTS profiling.%I CASCADE', v.table_name);
    END LOOP;
END;
$$;

\ir checks/follow_up.sql

\echo 'Running the checks and exporting the results to profiling/results/round-3/ ...'
\copy (SELECT * FROM profiling.f_01_order_totals_not_adding_up) TO 'profiling/results/round-3/f_01_order_totals_not_adding_up.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.f_02_order_total_difference_examples) TO 'profiling/results/round-3/f_02_order_total_difference_examples.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.f_03_manual_orders_without_test_customer) TO 'profiling/results/round-3/f_03_manual_orders_without_test_customer.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.f_04_ga4_value_definition_by_month) TO 'profiling/results/round-3/f_04_ga4_value_definition_by_month.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.f_05_duplicate_sends) TO 'profiling/results/round-3/f_05_duplicate_sends.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.f_06_other_subscriber_keys) TO 'profiling/results/round-3/f_06_other_subscriber_keys.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.f_07_ga4_user_id_by_month) TO 'profiling/results/round-3/f_07_ga4_user_id_by_month.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\echo 'Done.'
