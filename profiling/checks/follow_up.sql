-- =====================================================================
-- Kalkberg profiling - round 3: follow-up checks on open questions from round 2
-- Created by 03-run-follow-up-checks.sql. Every check is a view in the profiling schema.
-- =====================================================================

CREATE VIEW profiling.f_01_order_totals_not_adding_up AS
WITH o AS (
    SELECT o.*,
           o.order_total - (o.subtotal - o.discount_total + o.shipping_fee) AS difference,
           EXISTS (SELECT 1
                   FROM shop.order_lines AS l
                   JOIN shop.product_variants AS v USING (variant_id)
                   JOIN shop.products AS p USING (product_id)
                   JOIN shop.categories AS c USING (category_id)
                   WHERE l.order_id = o.order_id AND c.category_name = 'Gift cards') AS has_gift_card_line
    FROM shop.orders AS o
    WHERE o.order_total <> o.subtotal - o.discount_total + o.shipping_fee
)
SELECT CASE WHEN created_at < TIMESTAMP '2024-09-02' THEN 'before 2024-09-02' ELSE 'from 2024-09-02' END AS period,
       status,
       payment_method,
       discount_code IS NOT NULL                                     AS has_discount_code,
       has_gift_card_line,
       CASE WHEN difference > 0 THEN 'total higher' ELSE 'total lower' END AS direction,
       count(*)                                                      AS orders,
       min(difference)                                               AS min_difference,
       max(difference)                                               AS max_difference,
       min(order_number)                                             AS example_order
FROM o
GROUP BY 1, 2, 3, 4, 5, 6
ORDER BY orders DESC;
COMMENT ON VIEW profiling.f_01_order_totals_not_adding_up IS 'What do the orders whose total is not subtotal - discount + shipping have in common?';

CREATE VIEW profiling.f_02_order_total_difference_examples AS
SELECT o.order_number, o.created_at, o.status, o.payment_method, o.discount_code,
       o.subtotal, o.discount_total, o.shipping_fee, o.order_total,
       o.order_total - (o.subtotal - o.discount_total + o.shipping_fee) AS difference,
       (SELECT string_agg(l.quantity || ' x ' || l.unit_price || ' - ' || l.discount_amount || ' = ' || l.line_total, ' | ')
        FROM shop.order_lines AS l WHERE l.order_id = o.order_id) AS lines
FROM shop.orders AS o
WHERE o.order_total <> o.subtotal - o.discount_total + o.shipping_fee
ORDER BY o.order_id
LIMIT 40;
COMMENT ON VIEW profiling.f_02_order_total_difference_examples IS 'Examples of orders whose total does not add up';

CREATE VIEW profiling.f_03_manual_orders_without_test_customer AS
SELECT o.order_number, o.created_at, o.customer_id, o.guest_email, o.status, o.discount_code,
       o.subtotal, o.discount_total, o.shipping_fee, o.order_total,
       c.first_name, c.last_name, c.email
FROM shop.orders AS o
LEFT JOIN shop.customers AS c ON c.customer_id = o.customer_id
WHERE o.payment_method = 'Manual'
  AND NOT coalesce(c.first_name ILIKE '%test%' OR c.last_name ILIKE '%test%' OR c.email ILIKE '%test%'
                   OR c.email ILIKE '%@kalkberg%' OR btrim(c.last_name) ILIKE 'account', false)
ORDER BY o.created_at;
COMMENT ON VIEW profiling.f_03_manual_orders_without_test_customer IS 'Orders paid "Manual" that do not belong to a test-like customer';

CREATE VIEW profiling.f_04_ga4_value_definition_by_month AS
WITH p AS (
    SELECT DISTINCT ON (transaction_id) transaction_id, value::numeric AS value
    FROM ga4.events
    WHERE event_name = 'purchase'
    ORDER BY transaction_id, event_timestamp::bigint
)
SELECT date_trunc('month', o.created_at)::date AS order_month,
       count(*) FILTER (WHERE p.value = o.order_total AND o.shipping_fee > 0)   AS equals_total_incl_shipping,
       count(*) FILTER (WHERE p.value = o.order_total - o.shipping_fee AND o.shipping_fee > 0) AS equals_total_excl_shipping,
       count(*) FILTER (WHERE o.shipping_fee = 0 AND p.value = o.order_total)    AS free_shipping_equal,
       count(*) FILTER (WHERE p.value <> o.order_total AND p.value <> o.order_total - o.shipping_fee) AS other
FROM p
JOIN shop.orders AS o ON o.order_number = p.transaction_id
GROUP BY 1
ORDER BY 1;
COMMENT ON VIEW profiling.f_04_ga4_value_definition_by_month IS 'Does the GA4 purchase value include shipping, per month?';

CREATE VIEW profiling.f_05_duplicate_sends AS
WITH d AS (
    SELECT job_id, subscriber_id,
           count(*)                         AS rows_per_pair,
           count(DISTINCT event_date)       AS distinct_event_dates,
           count(DISTINCT batch_id)         AS distinct_batches,
           count(DISTINCT list_id)          AS distinct_lists,
           max(profiling.sfmc_timestamp(event_date)) - min(profiling.sfmc_timestamp(event_date)) AS time_between
    FROM sfmc.sent
    GROUP BY job_id, subscriber_id
    HAVING count(*) > 1
)
SELECT j.category, j.job_type,
       d.rows_per_pair, d.distinct_event_dates, d.distinct_batches, d.distinct_lists,
       CASE
           WHEN d.time_between = interval '0'          THEN 'same moment'
           WHEN d.time_between < interval '1 minute'   THEN '< 1 minute'
           WHEN d.time_between < interval '1 hour'     THEN '< 1 hour'
           WHEN d.time_between < interval '1 day'      THEN '< 1 day'
           ELSE '1 day or more'
       END AS time_between_sends,
       count(*) AS pairs,
       count(DISTINCT d.job_id) AS jobs
FROM d
JOIN sfmc.jobs AS j ON j.job_id = d.job_id
GROUP BY 1, 2, 3, 4, 5, 6, 7
ORDER BY pairs DESC;
COMMENT ON VIEW profiling.f_05_duplicate_sends IS 'What differs between send rows for the same job and subscriber?';

CREATE VIEW profiling.f_06_other_subscriber_keys AS
SELECT regexp_replace(regexp_replace(subscriber_key, '[0-9]', '9', 'g'), '[A-Za-z]', 'x', 'g') AS key_pattern,
       count(*)                AS subscribers,
       min(subscriber_key)     AS example_1,
       max(subscriber_key)     AS example_2,
       count(*) FILTER (WHERE lower(btrim(email_address)) IN (SELECT lower(btrim(email)) FROM shop.customers)) AS email_matches_a_customer,
       min(date_joined)        AS example_date_joined
FROM sfmc.subscribers
WHERE subscriber_key !~ '^[0-9]+$' AND subscriber_key NOT LIKE '%@%'
GROUP BY 1
ORDER BY subscribers DESC;
COMMENT ON VIEW profiling.f_06_other_subscriber_keys IS 'What are the subscriber keys that are neither a number nor an email address?';

CREATE VIEW profiling.f_07_ga4_user_id_by_month AS
SELECT left(event_date, 6) AS month,
       count(*) FILTER (WHERE event_name = 'session_start')                          AS session_starts,
       count(*) FILTER (WHERE event_name = 'session_start' AND user_id IS NOT NULL)  AS session_starts_with_user_id,
       count(*) FILTER (WHERE event_name = 'purchase')                               AS purchases,
       count(*) FILTER (WHERE event_name = 'purchase' AND user_id IS NOT NULL)       AS purchases_with_user_id
FROM ga4.events
GROUP BY 1
ORDER BY 1;
COMMENT ON VIEW profiling.f_07_ga4_user_id_by_month IS 'From when, and for which share of events, does GA4 know the logged-in customer?';
