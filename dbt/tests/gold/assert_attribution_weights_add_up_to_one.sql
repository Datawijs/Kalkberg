-- PM3: in every attribution model, the weights of an order's touchpoints add up to 1, and every
-- order that is not cancelled has a journey. Attributed revenue then always adds up to total revenue.
WITH weights AS (
    SELECT order_id,
           sum(weight_first_click) AS first_click, sum(weight_last_click) AS last_click,
           sum(weight_linear) AS linear, sum(weight_position_based) AS position_based
    FROM {{ ref('fct_order_touchpoints') }}
    GROUP BY order_id
)
SELECT o.order_id, w.*
FROM {{ ref('fct_orders') }} AS o
LEFT JOIN weights AS w USING (order_id)
WHERE NOT o.is_cancelled
  AND (w.order_id IS NULL
       OR abs(w.first_click - 1) > 0.0001 OR abs(w.last_click - 1) > 0.0001
       OR abs(w.linear - 1) > 0.0001 OR abs(w.position_based - 1) > 0.0001)
