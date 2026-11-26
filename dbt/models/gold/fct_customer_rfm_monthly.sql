{#-
    RFM segments over time (C3): one row per customer and month, from the month of their first order
    up to the last month of the data. Every row describes the customer at the end of that month.

    Recency    days since the last order
    Frequency  orders so far
    Monetary   net revenue so far
    Scores are on fixed thresholds instead of quintiles, so that a score means the same in every month
    and a customer only changes segment when their behaviour changes. The thresholds come from the
    distribution over all customers (docs/04-gold.md).

    Segment, on recency and frequency:
      Champions        R 4-5, F 4-5     bought recently and often
      Loyal customers  R 3-5, F 3-5
      New customers    R 4-5, F 1       first order in the last 90 days
      Promising        R 4-5, F 2
      Need attention   R 3,   F 1-2
      At risk          R 2,   F 3-5     used to buy often, nothing for 6 to 12 months
      Hibernating      R 2,   F 1-2
      Lost             R 1              nothing for more than a year
-#}
WITH orders AS (
    SELECT person_key, date_trunc('month', order_date)::date AS order_month, order_date, net_revenue
    FROM {{ ref('fct_orders') }}
    WHERE NOT is_cancelled
),

monthly AS (
    SELECT person_key, order_month, count(*) AS orders, sum(net_revenue) AS net_revenue,
           max(order_date) AS last_order_date
    FROM orders
    GROUP BY person_key, order_month
),

months AS (
    SELECT c.person_key, gs::date AS month_start
    FROM {{ ref('dim_customer') }} AS c
    CROSS JOIN LATERAL generate_series(
        c.cohort_month,
        (SELECT date_trunc('month', max(order_date)) FROM {{ ref('fct_orders') }}),
        interval '1 month') AS gs
    WHERE c.is_customer
),

running AS (
    SELECT
        m.person_key,
        m.month_start,
        (m.month_start + interval '1 month - 1 day')::date                         AS snapshot_date,
        sum(coalesce(mo.orders, 0)) OVER w                                          AS frequency,
        sum(coalesce(mo.net_revenue, 0)) OVER w                                     AS monetary,
        max(mo.last_order_date) OVER w                                              AS last_order_date
    FROM months AS m
    LEFT JOIN monthly AS mo
           ON mo.person_key = m.person_key AND mo.order_month = m.month_start
    WINDOW w AS (PARTITION BY m.person_key ORDER BY m.month_start ROWS UNBOUNDED PRECEDING)
),

scored AS (
    SELECT
        *,
        snapshot_date - last_order_date AS recency_days,
        CASE
            WHEN snapshot_date - last_order_date <= 30 THEN 5
            WHEN snapshot_date - last_order_date <= 90 THEN 4
            WHEN snapshot_date - last_order_date <= 180 THEN 3
            WHEN snapshot_date - last_order_date <= 365 THEN 2
            ELSE 1
        END AS recency_score,
        CASE
            WHEN frequency >= 6 THEN 5
            WHEN frequency >= 4 THEN 4
            WHEN frequency = 3 THEN 3
            WHEN frequency = 2 THEN 2
            ELSE 1
        END AS frequency_score,
        CASE
            WHEN monetary >= 550 THEN 5
            WHEN monetary >= 240 THEN 4
            WHEN monetary >= 130 THEN 3
            WHEN monetary >= 70 THEN 2
            ELSE 1
        END AS monetary_score
    FROM running
),

segmented AS (
    SELECT
        *,
        CASE
            WHEN recency_score >= 4 AND frequency_score >= 4 THEN 'Champions'
            WHEN recency_score >= 3 AND frequency_score >= 3 THEN 'Loyal customers'
            WHEN recency_score >= 4 AND frequency_score = 1 THEN 'New customers'
            WHEN recency_score >= 4 THEN 'Promising'
            WHEN recency_score = 3 THEN 'Need attention'
            WHEN recency_score = 2 AND frequency_score >= 3 THEN 'At risk'
            WHEN recency_score = 2 THEN 'Hibernating'
            ELSE 'Lost'
        END AS segment
    FROM scored
)

SELECT
    person_key,
    snapshot_date,
    month_start,
    recency_days,
    frequency,
    monetary,
    recency_score,
    frequency_score,
    monetary_score,
    recency_score::text || frequency_score::text || monetary_score::text AS rfm_code,
    segment,
    CASE segment
        WHEN 'Champions' THEN 1 WHEN 'Loyal customers' THEN 2 WHEN 'New customers' THEN 3
        WHEN 'Promising' THEN 4 WHEN 'Need attention' THEN 5 WHEN 'At risk' THEN 6
        WHEN 'Hibernating' THEN 7 ELSE 8
    END AS segment_sort_order,
    lag(segment) OVER (PARTITION BY person_key ORDER BY month_start) AS previous_segment
FROM segmented
