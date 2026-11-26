-- SH-02: shop_customers relies on customer_id following the order of creation, with exactly one jump
-- back in time: the switch from Belgian time to UTC at the migration. Fails if there is any other jump,
-- in accounts or orders.
WITH jumps AS (
    SELECT 'customers' AS table_name, customer_id AS id, created_at,
           lag(created_at) OVER (ORDER BY customer_id) AS previous_created_at
    FROM {{ source('shop', 'customers') }}
    UNION ALL
    SELECT 'orders', order_id, created_at,
           lag(created_at) OVER (ORDER BY order_id)
    FROM {{ source('shop', 'orders') }}
)
SELECT table_name, count(*) AS jumps_back_in_time
FROM jumps
WHERE created_at < previous_created_at
GROUP BY table_name
HAVING count(*) <> 1
