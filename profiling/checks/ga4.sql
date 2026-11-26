-- =====================================================================
-- Kalkberg profiling - round 2: targeted checks on ga4 (Google Analytics 4 exports)
-- Created by 02-run-targeted-checks.sql. Every check is a view in the profiling schema.
-- event_timestamp is in microseconds since 1970-01-01 UTC.
-- =====================================================================

CREATE VIEW profiling.ga4_01_fields_per_event AS
SELECT event_name,
       count(*)               AS events,
       count(user_id)         AS with_user_id,
       count(source)          AS with_source,
       count(medium)          AS with_medium,
       count(campaign)        AS with_campaign,
       count(page_location)   AS with_page_location,
       count(transaction_id)  AS with_transaction_id,
       count(value)           AS with_value
FROM ga4.events
GROUP BY event_name
ORDER BY events DESC;
COMMENT ON VIEW profiling.ga4_01_fields_per_event IS 'Which fields are filled for which event?';

CREATE VIEW profiling.ga4_02_event_date_vs_timestamp AS
WITH e AS (
    SELECT event_date,
           to_timestamp(event_timestamp::bigint / 1000000.0) AS ts
    FROM ga4.events
)
SELECT CASE
           WHEN event_date = to_char(ts AT TIME ZONE 'Europe/Brussels', 'YYYYMMDD')
            AND event_date = to_char(ts AT TIME ZONE 'UTC', 'YYYYMMDD')            THEN 'same date in UTC and Brussels time'
           WHEN event_date = to_char(ts AT TIME ZONE 'Europe/Brussels', 'YYYYMMDD') THEN 'matches the Brussels date only'
           WHEN event_date = to_char(ts AT TIME ZONE 'UTC', 'YYYYMMDD')             THEN 'matches the UTC date only'
           ELSE 'matches neither'
       END AS event_date_vs_timestamp,
       count(*) AS events,
       count(*) FILTER (WHERE event_date > '20261031') AS events_dated_after_2026_10_31
FROM e
GROUP BY 1
ORDER BY events DESC;
COMMENT ON VIEW profiling.ga4_02_event_date_vs_timestamp IS 'In which time zone is event_date expressed?';

CREATE VIEW profiling.ga4_03_duplicate_purchases AS
WITH p AS (
    SELECT transaction_id,
           count(*)                                                     AS purchase_events,
           max(event_timestamp::bigint) - min(event_timestamp::bigint)  AS span_microseconds,
           count(DISTINCT user_pseudo_id)                               AS devices,
           count(DISTINCT ga_session_id)                                AS sessions,
           count(DISTINCT value)                                        AS distinct_values
    FROM ga4.events
    WHERE event_name = 'purchase'
    GROUP BY transaction_id
)
SELECT purchase_events,
       CASE
           WHEN purchase_events = 1               THEN '-'
           WHEN span_microseconds < 60000000      THEN 'within 1 minute'
           WHEN span_microseconds < 3600000000    THEN 'within 1 hour'
           WHEN span_microseconds < 86400000000   THEN 'within 1 day'
           ELSE 'more than 1 day apart'
       END AS time_between_first_and_last,
       devices, sessions, distinct_values,
       count(*) AS transactions
FROM p
GROUP BY 1, 2, 3, 4, 5
ORDER BY 1, transactions DESC;
COMMENT ON VIEW profiling.ga4_03_duplicate_purchases IS 'Are purchases sent to GA4 more than once for the same transaction?';

CREATE VIEW profiling.ga4_04_purchases_vs_shop_orders AS
WITH p AS (
    SELECT DISTINCT transaction_id FROM ga4.events WHERE event_name = 'purchase'
)
SELECT date_trunc('month', o.created_at)::date                         AS order_month,
       count(*)                                                        AS shop_orders,
       count(p.transaction_id)                                         AS with_ga4_purchase,
       round(100.0 * count(p.transaction_id) / count(*), 1)            AS pct_with_ga4_purchase
FROM shop.orders AS o
LEFT JOIN p ON p.transaction_id = o.order_number
GROUP BY 1
ORDER BY 1;
COMMENT ON VIEW profiling.ga4_04_purchases_vs_shop_orders IS 'Which share of shop orders can be found in GA4, per month?';

CREATE VIEW profiling.ga4_05_transactions_without_order AS
WITH p AS (
    SELECT transaction_id, min(event_date) AS event_date
    FROM ga4.events
    WHERE event_name = 'purchase'
    GROUP BY transaction_id
)
SELECT regexp_replace(p.transaction_id, '[0-9]', '9', 'g') AS transaction_id_pattern,
       o.order_id IS NOT NULL                              AS found_in_shop,
       count(*)                                            AS transactions,
       min(p.transaction_id)                               AS example,
       min(p.event_date)                                   AS first_event_date,
       max(p.event_date)                                   AS last_event_date
FROM p
LEFT JOIN shop.orders AS o ON o.order_number = p.transaction_id
GROUP BY 1, 2
ORDER BY 1, 2;
COMMENT ON VIEW profiling.ga4_05_transactions_without_order IS 'Can every GA4 transaction be found in the shop?';

CREATE VIEW profiling.ga4_06_purchase_value_vs_order AS
WITH p AS (
    SELECT DISTINCT ON (transaction_id) transaction_id, value::numeric AS value
    FROM ga4.events
    WHERE event_name = 'purchase'
    ORDER BY transaction_id, event_timestamp::bigint
)
SELECT CASE
           WHEN o.order_id IS NULL                                     THEN 'no matching order'
           WHEN p.value = o.order_total                                THEN 'equals order_total'
           WHEN p.value = o.order_total - o.shipping_fee               THEN 'equals order_total - shipping_fee'
           WHEN p.value = o.subtotal                                   THEN 'equals subtotal'
           ELSE 'other'
       END AS ga4_value,
       count(*) AS transactions,
       sum(p.value) AS ga4_value_sum,
       sum(o.order_total) AS shop_order_total_sum
FROM p
LEFT JOIN shop.orders AS o ON o.order_number = p.transaction_id
GROUP BY 1
ORDER BY transactions DESC;
COMMENT ON VIEW profiling.ga4_06_purchase_value_vs_order IS 'Which shop amount does the GA4 purchase value correspond to?';

CREATE VIEW profiling.ga4_07_user_id_vs_customers AS
WITH u AS (
    SELECT DISTINCT user_id FROM ga4.events WHERE user_id IS NOT NULL
)
SELECT count(*)                                                   AS distinct_user_ids,
       count(*) FILTER (WHERE user_id !~ '^[0-9]+$')              AS not_numeric,
       count(c.customer_id)                                       AS matching_a_customer_id
FROM u
LEFT JOIN shop.customers AS c ON c.customer_id::text = u.user_id;
COMMENT ON VIEW profiling.ga4_07_user_id_vs_customers IS 'Is the GA4 user_id the shop customer_id?';

CREATE VIEW profiling.ga4_08_traffic_sources AS
SELECT session_source_medium,
       session_campaign,
       sum(sessions::int)           AS sessions,
       sum(ecommerce_purchases::int) AS purchases,
       min(date)                    AS first_date,
       max(date)                    AS last_date
FROM ga4.daily_traffic
GROUP BY 1, 2
ORDER BY session_source_medium, sessions DESC;
COMMENT ON VIEW profiling.ga4_08_traffic_sources IS 'Every source / medium / campaign combination in the daily traffic report';

CREATE VIEW profiling.ga4_09_country_quality AS
SELECT country,
       sum(sessions::int)                                                    AS sessions,
       sum(engaged_sessions::int)                                            AS engaged_sessions,
       round(100.0 * sum(engaged_sessions::int) / sum(sessions::int), 1)     AS engagement_rate_pct,
       sum(add_to_carts::int)                                                AS add_to_carts,
       sum(ecommerce_purchases::int)                                         AS purchases,
       round(100.0 * sum(ecommerce_purchases::int) / sum(sessions::int), 2)  AS conversion_rate_pct,
       sum(purchase_revenue::numeric)                                        AS revenue
FROM ga4.daily_traffic
GROUP BY country
ORDER BY sessions DESC;
COMMENT ON VIEW profiling.ga4_09_country_quality IS 'How does traffic from each country behave?';

CREATE VIEW profiling.ga4_10_daily_traffic_vs_events AS
WITH d AS (
    SELECT left(date, 6)                    AS month,
           sum(sessions::int)               AS report_sessions,
           sum(ecommerce_purchases::int)    AS report_purchases,
           sum(purchase_revenue::numeric)   AS report_revenue
    FROM ga4.daily_traffic
    GROUP BY 1
), e AS (
    SELECT left(event_date, 6)                                                   AS month,
           count(*) FILTER (WHERE event_name = 'session_start')                  AS session_start_events,
           count(*) FILTER (WHERE event_name = 'purchase')                       AS purchase_events,
           count(DISTINCT transaction_id) FILTER (WHERE event_name = 'purchase') AS distinct_transactions,
           sum(value::numeric) FILTER (WHERE event_name = 'purchase')            AS purchase_value
    FROM ga4.events
    GROUP BY 1
)
SELECT *
FROM d
FULL JOIN e USING (month)
ORDER BY month;
COMMENT ON VIEW profiling.ga4_10_daily_traffic_vs_events IS 'Do the daily traffic report and the event export tell the same story, per month?';
