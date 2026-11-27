{#-
    Order lines, one row per line of a real order. The lines themselves (amounts, returns, cost and
    margin) are built in int_order_lines; this model adds the order's channel and campaign from
    fct_orders, so the lines can be split by channel without a relationship between two facts in
    Power BI (F2: margin per category and channel, see docs/07-semantic-model.md).
-#}
SELECT
    l.*,
    o.order_channel_key,
    o.order_campaign_key
FROM {{ ref('int_order_lines') }} AS l
JOIN {{ ref('fct_orders') }} AS o USING (order_id)
