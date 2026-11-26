{#-
    Calendar, one row per day. Covers the budget years 2023 to 2026, so plans and actuals share it.
    All dates in gold are Belgian dates.
-#}
WITH days AS (
    SELECT generate_series(
               DATE '{{ var("calendar_start_date") }}',
               DATE '{{ var("calendar_end_date") }}',
               interval '1 day')::date AS date
),

data_period AS (
    SELECT min(order_date) AS first_date, max(order_date) AS last_date
    FROM {{ ref('shop_orders') }}
)

SELECT
    d.date,
    extract(year FROM d.date)::integer                    AS year,
    extract(quarter FROM d.date)::integer                 AS quarter_number,
    'Q' || extract(quarter FROM d.date)                   AS quarter,
    extract(month FROM d.date)::integer                   AS month_number,
    to_char(d.date, 'FMMonth')                            AS month_name,
    to_char(d.date, 'Mon')                                AS month_short,
    date_trunc('month', d.date)::date                     AS month_start,
    to_char(d.date, 'YYYY-MM')                            AS year_month,
    extract(isoyear FROM d.date)::integer                 AS iso_year,
    extract(week FROM d.date)::integer                    AS iso_week,
    extract(isodow FROM d.date)::integer                  AS weekday_number,
    to_char(d.date, 'FMDay')                              AS weekday_name,
    extract(isodow FROM d.date) IN (6, 7)                 AS is_weekend,
    extract(day FROM d.date)::integer                     AS day_of_month,
    d.date BETWEEN p.first_date AND p.last_date           AS is_in_data_period,
    -- The whole month has data; months outside the data period, or cut off by it, are not complete
    date_trunc('month', d.date)::date >= date_trunc('month', p.first_date)::date
        AND (date_trunc('month', d.date) + interval '1 month - 1 day')::date <= p.last_date AS is_complete_month,
    pr.promotion_name,
    pr.promotion_type,
    pr.promotion_name IS NOT NULL                         AS is_promotion_day
FROM days AS d
CROSS JOIN data_period AS p
LEFT JOIN {{ ref('promotion_periods') }} AS pr
       ON d.date BETWEEN pr.start_date AND pr.end_date
