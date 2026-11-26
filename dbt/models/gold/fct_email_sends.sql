{#-
    Email sends with what happened to them (E2, E3, E5, E6, E8), one row per send (MC-07).
      is_delivered   not bounced
      opens, clicks  all events linked to this send; is_opened / is_clicked when there is at least one
      is_icloud_address  opens of these addresses are mostly automatic (MC-06): report open rates with
                         and without them, and prefer clicks
      first_opened_at_local, first_clicked_at_local  for the time of day and weekday (E8)

    Email revenue (E3): an order belongs to the send in which the customer last clicked, when that
    click was at most 72 hours before the order. Every order belongs to at most one send.
-#}
WITH opens AS (
    SELECT send_key, count(*) AS opens, min(opened_at_local) AS first_opened_at_local
    FROM {{ ref('sfmc_opens') }}
    GROUP BY send_key
),

clicks AS (
    SELECT send_key, count(*) AS clicks, min(clicked_at_local) AS first_clicked_at_local
    FROM {{ ref('sfmc_clicks') }}
    GROUP BY send_key
),

bounces AS (
    SELECT send_key, min(bounce_category) AS bounce_category
    FROM {{ ref('sfmc_bounces') }}
    GROUP BY send_key
),

unsubscribes AS (
    SELECT DISTINCT send_key
    FROM {{ ref('sfmc_unsubscribes') }}
),

person_clicks AS (
    SELECT c.send_key, c.clicked_at_utc, s.person_key
    FROM {{ ref('sfmc_clicks') }} AS c
    JOIN {{ ref('sfmc_subscribers') }} AS s USING (subscriber_id)
),

orders AS (
    SELECT o.order_id, o.person_key, s.created_at_utc, o.order_total, o.net_revenue, o.is_new_customer_order
    FROM {{ ref('fct_orders') }} AS o
    JOIN {{ ref('shop_orders') }} AS s USING (order_id)
    WHERE NOT o.is_cancelled
),

order_last_click AS (
    SELECT DISTINCT ON (o.order_id)
        o.order_id, c.send_key, o.order_total, o.net_revenue, o.is_new_customer_order
    FROM orders AS o
    JOIN person_clicks AS c
      ON c.person_key = o.person_key
     AND c.clicked_at_utc BETWEEN o.created_at_utc - interval '{{ var("email_attribution_hours") }} hours'
                              AND o.created_at_utc
    ORDER BY o.order_id, c.clicked_at_utc DESC
),

email_orders AS (
    SELECT
        send_key,
        count(*)                                     AS attributed_orders,
        count(*) FILTER (WHERE is_new_customer_order) AS attributed_new_customer_orders,
        sum(order_total)                             AS attributed_revenue,
        sum(net_revenue)                             AS attributed_net_revenue
    FROM order_last_click
    GROUP BY send_key
)

SELECT
    s.send_key,
    s.job_id,
    s.subscriber_id,
    sub.person_key,
    s.sent_date,
    s.sent_at_local,
    s.is_icloud_address,
    b.send_key IS NULL                              AS is_delivered,
    b.send_key IS NOT NULL                          AS is_bounced,
    b.bounce_category,
    coalesce(o.opens, 0)                            AS opens,
    o.send_key IS NOT NULL                          AS is_opened,
    o.first_opened_at_local,
    coalesce(c.clicks, 0)                           AS clicks,
    c.send_key IS NOT NULL                          AS is_clicked,
    c.first_clicked_at_local,
    u.send_key IS NOT NULL                          AS is_unsubscribed,
    coalesce(e.attributed_orders, 0)                AS attributed_orders,
    coalesce(e.attributed_new_customer_orders, 0)   AS attributed_new_customer_orders,
    coalesce(e.attributed_revenue, 0)               AS attributed_revenue,
    coalesce(e.attributed_net_revenue, 0)           AS attributed_net_revenue
FROM {{ ref('sfmc_sends') }} AS s
JOIN {{ ref('sfmc_subscribers') }} AS sub USING (subscriber_id)
JOIN {{ ref('persons') }} AS p ON p.person_key = sub.person_key AND NOT p.is_test
LEFT JOIN opens AS o USING (send_key)
LEFT JOIN clicks AS c USING (send_key)
LEFT JOIN bounces AS b USING (send_key)
LEFT JOIN unsubscribes AS u USING (send_key)
LEFT JOIN email_orders AS e USING (send_key)
