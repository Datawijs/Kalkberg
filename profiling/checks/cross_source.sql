-- =====================================================================
-- Kalkberg profiling - round 2: checks across sources
-- Created by 02-run-targeted-checks.sql. Every check is a view in the profiling schema.
-- Numbers are read as simply as possible (thousands separators removed); this is a
-- first comparison, not the final definition of any metric.
-- =====================================================================

CREATE VIEW profiling.x_01_monthly_orders_by_source AS
WITH shop_orders AS (
    SELECT to_char(created_at, 'YYYY-MM')                          AS month,
           count(*)                                                AS shop_orders,
           count(*) FILTER (WHERE status <> 'cancelled')           AS shop_orders_not_cancelled,
           sum(order_total) FILTER (WHERE status <> 'cancelled')   AS shop_order_total
    FROM shop.orders
    GROUP BY 1
), ga4_purchases AS (
    SELECT to_char(to_date(event_date, 'YYYYMMDD'), 'YYYY-MM')     AS month,
           count(DISTINCT transaction_id)                          AS ga4_transactions,
           sum(value::numeric)                                     AS ga4_purchase_value
    FROM ga4.events
    WHERE event_name = 'purchase'
    GROUP BY 1
), google AS (
    SELECT left(day, 7)                                            AS month,
           sum(replace(cost, ',', '')::numeric)                    AS google_cost,
           sum(replace(conversions, ',', '')::numeric)             AS google_conversions,
           sum(replace(conv_value, ',', '')::numeric)              AS google_conv_value
    FROM ads.google_ads_campaign_report
    WHERE day ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    GROUP BY 1
), meta AS (
    SELECT left(reporting_starts, 7)                               AS month,
           sum(amount_spent_eur::numeric)                          AS meta_cost,
           sum(coalesce(purchases, '0')::int)                      AS meta_purchases,
           sum(purchases_conversion_value::numeric)                AS meta_purchase_value
    FROM ads.meta_ads_report
    GROUP BY 1
)
SELECT *
FROM shop_orders
FULL JOIN ga4_purchases USING (month)
FULL JOIN google USING (month)
FULL JOIN meta USING (month)
ORDER BY month;
COMMENT ON VIEW profiling.x_01_monthly_orders_by_source IS 'Orders and revenue per month as reported by the shop, GA4, Google Ads and Meta';

CREATE VIEW profiling.x_02_customers_vs_subscribers AS
WITH k AS (
    SELECT DISTINCT subscriber_key FROM sfmc.subscribers WHERE subscriber_key ~ '^[0-9]+$'
), e AS (
    SELECT DISTINCT lower(btrim(email_address)) AS email FROM sfmc.subscribers
)
SELECT c.marketing_opt_in,
       k.subscriber_key IS NOT NULL  AS subscriber_with_customer_id_as_key,
       e.email IS NOT NULL           AS subscriber_with_same_email,
       count(*)                      AS customers
FROM shop.customers AS c
LEFT JOIN k ON k.subscriber_key = c.customer_id::text
LEFT JOIN e ON e.email = lower(btrim(c.email))
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
COMMENT ON VIEW profiling.x_02_customers_vs_subscribers IS 'How do shop customers link to Marketing Cloud subscribers?';
