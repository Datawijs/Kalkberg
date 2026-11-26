-- Gold must not lose or invent revenue: per month, the orders and revenue in fct_orders equal the
-- real (non-test) orders in silver, and the order lines add up to the order totals within the
-- rounding differences of SH-12.
WITH gold AS (
    SELECT date_trunc('month', order_date) AS month, count(*) AS orders, sum(order_total) AS revenue
    FROM {{ ref('fct_orders') }}
    GROUP BY 1
),
silver AS (
    SELECT date_trunc('month', order_date) AS month, count(*) AS orders, sum(order_total) AS revenue
    FROM {{ ref('shop_orders') }}
    WHERE NOT is_test
    GROUP BY 1
),
lines AS (
    SELECT date_trunc('month', l.order_date) AS month,
           sum(l.net_amount) AS line_amount
    FROM {{ ref('fct_order_lines') }} AS l
    GROUP BY 1
),
orders_excl_shipping AS (
    SELECT date_trunc('month', order_date) AS month, sum(order_total - shipping_fee) AS amount, count(*) AS orders
    FROM {{ ref('fct_orders') }}
    GROUP BY 1
)
SELECT s.month, s.orders AS silver_orders, g.orders AS gold_orders, s.revenue AS silver_revenue, g.revenue AS gold_revenue,
       l.line_amount, o.amount AS order_amount_excl_shipping
FROM silver AS s
FULL OUTER JOIN gold AS g USING (month)
LEFT JOIN lines AS l USING (month)
LEFT JOIN orders_excl_shipping AS o USING (month)
WHERE g.orders IS DISTINCT FROM s.orders
   OR g.revenue IS DISTINCT FROM s.revenue
   OR abs(l.line_amount - o.amount) > 0.05 * o.orders
