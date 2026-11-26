-- M1: a new customer is a person's first order that was not cancelled. Every customer in dim_customer
-- has exactly one such order, and their first order date is that order's date.
SELECT c.person_key, c.first_order_date, count(o.order_id) AS first_orders
FROM {{ ref('dim_customer') }} AS c
LEFT JOIN {{ ref('fct_orders') }} AS o
       ON o.person_key = c.person_key AND o.is_new_customer_order
WHERE c.is_customer
GROUP BY c.person_key, c.first_order_date
HAVING count(o.order_id) <> 1 OR min(o.order_date) <> c.first_order_date
