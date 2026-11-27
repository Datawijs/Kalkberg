{#-
    Customer journeys and attribution weights, one row per order and touchpoint. The journeys and the
    weights are built in int_order_touchpoints; this model adds the order's date and amounts from
    fct_orders, so attributed revenue (weight x order amount) can be computed and shown in the month
    of the order without a relationship between two facts in Power BI (PM3, see
    docs/07-semantic-model.md).
      order_date          the date of the order the touchpoint led to (touchpoint_date is the session's)
      order_net_revenue   fct_orders.net_revenue: order_total - refunds, incl. VAT and shipping
      order_gross_margin  fct_orders.gross_margin_before_shipping_cost
-#}
SELECT
    t.*,
    o.order_date,
    o.net_revenue                         AS order_net_revenue,
    o.gross_margin_before_shipping_cost   AS order_gross_margin
FROM {{ ref('int_order_touchpoints') }} AS t
JOIN {{ ref('fct_orders') }} AS o USING (order_id)
