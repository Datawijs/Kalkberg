-- =====================================================================
-- Kalkberg profiling - round 2: targeted checks
-- Run from the project folder (the folder that contains 'profiling'):
--   psql -U [username] -d kalkberg -f profiling/02-run-targeted-checks.sql
--
-- Creates every check in profiling/checks/ as a view in the profiling schema, then
-- exports each view to profiling/results/round-2/<view>.csv. The exports run the
-- checks, so this takes a while; the Marketing Cloud checks are the slowest.
-- Bronze tables are only read, never changed.
-- =====================================================================

\set ON_ERROR_STOP on
\timing on

\ir 00-create-profiling-objects.sql

-- More memory per sort and hash makes the large joins a lot faster (this session only)
SET work_mem = '256MB';

\echo 'Creating the checks ...'
-- Drop earlier versions of the checks, so a changed check can be recreated
DO $$
DECLARE
    v record;
BEGIN
    FOR v IN SELECT table_name FROM information_schema.views WHERE table_schema = 'profiling' LOOP
        EXECUTE format('DROP VIEW IF EXISTS profiling.%I CASCADE', v.table_name);
    END LOOP;
END;
$$;

\ir checks/shop.sql
\ir checks/ads.sql
\ir checks/ga4.sql
\ir checks/sfmc.sql
\ir checks/cross_source.sql

\echo 'Running the checks and exporting the results to profiling/results/round-2/ ...'

\echo 'shop ...'
\copy (SELECT * FROM profiling.shop_01_country_notations) TO 'profiling/results/round-2/shop_01_country_notations.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.shop_02_customer_email_duplicates) TO 'profiling/results/round-2/shop_02_customer_email_duplicates.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.shop_03_possible_duplicate_people) TO 'profiling/results/round-2/shop_03_possible_duplicate_people.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.shop_04_duplicate_people_examples) TO 'profiling/results/round-2/shop_04_duplicate_people_examples.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.shop_05_test_record_indicators) TO 'profiling/results/round-2/shop_05_test_record_indicators.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.shop_06_test_customer_examples) TO 'profiling/results/round-2/shop_06_test_customer_examples.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.shop_07_test_order_overlap) TO 'profiling/results/round-2/shop_07_test_order_overlap.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.shop_08_name_notation) TO 'profiling/results/round-2/shop_08_name_notation.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.shop_09_phone_formats) TO 'profiling/results/round-2/shop_09_phone_formats.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.shop_10_birth_dates) TO 'profiling/results/round-2/shop_10_birth_dates.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.shop_11_order_number_formats) TO 'profiling/results/round-2/shop_11_order_number_formats.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.shop_12_order_time_vs_ga4) TO 'profiling/results/round-2/shop_12_order_time_vs_ga4.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.shop_13_hour_of_day_by_period) TO 'profiling/results/round-2/shop_13_hour_of_day_by_period.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.shop_14_orders_before_signup) TO 'profiling/results/round-2/shop_14_orders_before_signup.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.shop_15_order_amounts) TO 'profiling/results/round-2/shop_15_order_amounts.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.shop_16_guest_orders) TO 'profiling/results/round-2/shop_16_guest_orders.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.shop_17_discount_codes) TO 'profiling/results/round-2/shop_17_discount_codes.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.shop_18_order_status_vs_returns) TO 'profiling/results/round-2/shop_18_order_status_vs_returns.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.shop_19_open_order_age) TO 'profiling/results/round-2/shop_19_open_order_age.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.shop_20_returns_consistency) TO 'profiling/results/round-2/shop_20_returns_consistency.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.shop_21_catalogue_consistency) TO 'profiling/results/round-2/shop_21_catalogue_consistency.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.shop_22_catalogue_examples) TO 'profiling/results/round-2/shop_22_catalogue_examples.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\echo 'ads ...'
\copy (SELECT * FROM profiling.ads_01_google_non_data_rows) TO 'profiling/results/round-2/ads_01_google_non_data_rows.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.ads_02_number_notation) TO 'profiling/results/round-2/ads_02_number_notation.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.ads_03_grain) TO 'profiling/results/round-2/ads_03_grain.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.ads_04_meta_missing_purchases) TO 'profiling/results/round-2/ads_04_meta_missing_purchases.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.ads_05_campaign_coverage) TO 'profiling/results/round-2/ads_05_campaign_coverage.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\echo 'ga4 ...'
\copy (SELECT * FROM profiling.ga4_01_fields_per_event) TO 'profiling/results/round-2/ga4_01_fields_per_event.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.ga4_02_event_date_vs_timestamp) TO 'profiling/results/round-2/ga4_02_event_date_vs_timestamp.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.ga4_03_duplicate_purchases) TO 'profiling/results/round-2/ga4_03_duplicate_purchases.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.ga4_04_purchases_vs_shop_orders) TO 'profiling/results/round-2/ga4_04_purchases_vs_shop_orders.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.ga4_05_transactions_without_order) TO 'profiling/results/round-2/ga4_05_transactions_without_order.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.ga4_06_purchase_value_vs_order) TO 'profiling/results/round-2/ga4_06_purchase_value_vs_order.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.ga4_07_user_id_vs_customers) TO 'profiling/results/round-2/ga4_07_user_id_vs_customers.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.ga4_08_traffic_sources) TO 'profiling/results/round-2/ga4_08_traffic_sources.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.ga4_09_country_quality) TO 'profiling/results/round-2/ga4_09_country_quality.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.ga4_10_daily_traffic_vs_events) TO 'profiling/results/round-2/ga4_10_daily_traffic_vs_events.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\echo 'sfmc ...'
\copy (SELECT * FROM profiling.sfmc_01_timestamp_notation) TO 'profiling/results/round-2/sfmc_01_timestamp_notation.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.sfmc_02_hour_of_day) TO 'profiling/results/round-2/sfmc_02_hour_of_day.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.sfmc_03_click_vs_ga4_session) TO 'profiling/results/round-2/sfmc_03_click_vs_ga4_session.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.sfmc_04_subscriber_keys) TO 'profiling/results/round-2/sfmc_04_subscriber_keys.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.sfmc_05_duplicate_subscribers) TO 'profiling/results/round-2/sfmc_05_duplicate_subscribers.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.sfmc_06_email_domains) TO 'profiling/results/round-2/sfmc_06_email_domains.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.sfmc_07_referential_integrity) TO 'profiling/results/round-2/sfmc_07_referential_integrity.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.sfmc_08_open_delay) TO 'profiling/results/round-2/sfmc_08_open_delay.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.sfmc_09_rates_by_domain) TO 'profiling/results/round-2/sfmc_09_rates_by_domain.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.sfmc_10_click_url_tags) TO 'profiling/results/round-2/sfmc_10_click_url_tags.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\echo 'cross_source ...'
\copy (SELECT * FROM profiling.x_01_monthly_orders_by_source) TO 'profiling/results/round-2/x_01_monthly_orders_by_source.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.x_02_customers_vs_subscribers) TO 'profiling/results/round-2/x_02_customers_vs_subscribers.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\echo 'Done.'
