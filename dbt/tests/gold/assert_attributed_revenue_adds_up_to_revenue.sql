-- PM3: in every attribution model, the revenue attributed to the touchpoints (weight x order_net_revenue)
-- adds up to the net revenue of the orders that are not cancelled, per order month. This is what the
-- attribution measures in Power BI rely on.
WITH attributed AS (
    SELECT date_trunc('month', order_date)::date              AS order_month,
           sum(weight_first_click * order_net_revenue)       AS first_click,
           sum(weight_last_click * order_net_revenue)        AS last_click,
           sum(weight_linear * order_net_revenue)            AS linear,
           sum(weight_position_based * order_net_revenue)    AS position_based
    FROM {{ ref('fct_order_touchpoints') }}
    GROUP BY 1
),

revenue AS (
    SELECT date_trunc('month', order_date)::date AS order_month,
           sum(net_revenue)                      AS net_revenue
    FROM {{ ref('fct_orders') }}
    WHERE NOT is_cancelled
    GROUP BY 1
)

SELECT r.order_month, r.net_revenue, a.*
FROM revenue AS r
LEFT JOIN attributed AS a USING (order_month)
WHERE a.order_month IS NULL
   -- linear and position-based weights are rounded to 6 decimals: allow a cent per 10.000 euro
   OR abs(a.first_click - r.net_revenue) > 0.01
   OR abs(a.last_click - r.net_revenue) > 0.01
   OR abs(a.linear - r.net_revenue) > greatest(0.01, r.net_revenue * 0.000001)
   OR abs(a.position_based - r.net_revenue) > greatest(0.01, r.net_revenue * 0.000001)
