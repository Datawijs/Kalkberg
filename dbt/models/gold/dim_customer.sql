{#-
    Customers and subscribers: one row per person (decision 0004), test people left out (SH-05).
    A person without orders is a subscriber or an account holder who never bought.

    Acquisition (M4, M6, PM9): the channel, campaign and discount type of the person's first order.
    Cohort (C2): the month of the first order.
    Lifetime value (M6): net revenue and gross margin (before shipping costs) in the first 12 and 24 months after the first
    order, counted from the first order date. is_clv_12m_complete is false when the first order is less
    than 12 months before the end of the data, so the value can't be compared yet.
-#}
WITH people AS (
    SELECT *
    FROM {{ ref('persons') }}
    WHERE NOT is_test
),

orders AS (
    SELECT *
    FROM {{ ref('fct_orders') }}
    WHERE NOT is_cancelled
),

data_end AS (
    SELECT max(order_date) AS last_date FROM {{ ref('fct_orders') }}
),

first_orders AS (
    SELECT person_key, order_id, order_date, order_channel_key, order_campaign_key, order_channel_source,
           discount_type, shipping_country_code, shipping_city, shipping_postal_code, is_guest_order
    FROM orders
    WHERE customer_order_number = 1
),

lifetime AS (
    SELECT
        o.person_key,
        count(*)                                                                 AS lifetime_orders,
        max(o.order_date)                                                        AS last_order_date,
        sum(o.net_revenue)                                                       AS lifetime_net_revenue,
        sum(o.net_revenue)  FILTER (WHERE o.order_date < f.order_date + 365)     AS clv_12m_net_revenue,
        sum(o.net_revenue)  FILTER (WHERE o.order_date < f.order_date + 730)     AS clv_24m_net_revenue,
        sum(o.gross_margin_before_shipping_cost) FILTER (WHERE o.order_date < f.order_date + 365) AS clv_12m_gross_margin,
        sum(o.gross_margin_before_shipping_cost) FILTER (WHERE o.order_date < f.order_date + 730) AS clv_24m_gross_margin,
        count(*)            FILTER (WHERE o.order_date < f.order_date + 365)     AS orders_first_12m
    FROM orders AS o
    JOIN first_orders AS f USING (person_key)
    GROUP BY o.person_key
),

accounts AS (
    SELECT
        person_key,
        (array_agg(preferred_language ORDER BY created_at_utc DESC))[1] AS preferred_language,
        (array_agg(country_code ORDER BY created_at_utc DESC))[1]       AS account_country_code
    FROM {{ ref('shop_customers') }}
    GROUP BY person_key
),

subscriptions AS (
    SELECT person_key, (array_agg(language ORDER BY joined_at_utc DESC))[1] AS subscriber_language
    FROM {{ ref('sfmc_subscribers') }}
    GROUP BY person_key
)

SELECT
    p.person_key,
    CASE
        WHEN f.person_key IS NOT NULL THEN 'customer'
        WHEN p.has_shop_account THEN 'account without order'
        ELSE 'subscriber only'
    END                                                         AS person_type,
    f.person_key IS NOT NULL                                    AS is_customer,
    p.has_shop_account,
    p.shop_accounts,
    p.is_subscriber,
    p.is_reachable,
    p.has_email_domain_typo,
    p.has_marketing_opt_in,
    p.has_opt_in_mismatch,
    coalesce(f.shipping_country_code, a.account_country_code)  AS country_code,
    f.shipping_city                                             AS first_order_city,
    f.shipping_postal_code                                      AS first_order_postal_code,
    coalesce(a.preferred_language, s.subscriber_language)       AS language,

    -- Acquisition and cohort
    f.order_id                                                  AS first_order_id,
    f.order_date                                                AS first_order_date,
    date_trunc('month', f.order_date)::date                     AS cohort_month,
    f.order_channel_key                                         AS acquisition_channel_key,
    f.order_campaign_key                                        AS acquisition_campaign_key,
    f.order_channel_source                                      AS acquisition_channel_source,
    f.discount_type                                             AS acquisition_discount_type,
    f.is_guest_order                                            AS first_order_as_guest,

    -- Lifetime
    coalesce(l.lifetime_orders, 0)                              AS lifetime_orders,
    l.last_order_date,
    l.lifetime_net_revenue,
    l.orders_first_12m,
    l.clv_12m_net_revenue,
    l.clv_24m_net_revenue,
    l.clv_12m_gross_margin,
    l.clv_24m_gross_margin,
    coalesce(f.order_date + 365 <= d.last_date + 1, false)      AS is_clv_12m_complete,
    coalesce(f.order_date + 730 <= d.last_date + 1, false)      AS is_clv_24m_complete
FROM people AS p
CROSS JOIN data_end AS d
LEFT JOIN first_orders AS f USING (person_key)
LEFT JOIN lifetime AS l USING (person_key)
LEFT JOIN accounts AS a USING (person_key)
LEFT JOIN subscriptions AS s USING (person_key)
