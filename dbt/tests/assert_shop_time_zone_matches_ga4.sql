-- SH-02: after the time zone fix, the shop's order time and GA4's purchase time (always UTC) must be the
-- same moment. Fails when fewer than 99% of the orders that GA4 recorded are within 10 minutes of it,
-- in any month. Before the fix, the old platform was 1 or 2 hours off.
WITH pairs AS (
    SELECT o.order_date, abs(extract(epoch FROM o.created_at_utc - e.event_at_utc)) AS seconds_apart
    FROM {{ ref('shop_orders') }} AS o
    JOIN {{ ref('ga4_events') }} AS e
      ON e.transaction_id = o.order_number AND e.event_name = 'purchase'
)
SELECT date_trunc('month', order_date)::date AS order_month,
       count(*) AS orders_in_ga4,
       avg((seconds_apart <= 600)::int) AS share_within_10_minutes
FROM pairs
GROUP BY 1
HAVING avg((seconds_apart <= 600)::int) < 0.99
