{#-
    Orders, one row per real order (test orders left out, SH-05).

    Revenue amounts (all from the shop, the source of truth: X-01):
      order_total            what the customer paid, incl. VAT and shipping (SH-12: the shop's own total)
      gift_card_amount       part of order_total that is a gift card sale (F6: not revenue until used)
      refund_amount          refunded through returns
      net_revenue            order_total - refund_amount
      *_excl_vat             the same amounts without VAT, for margin and finance
      gross_margin           product margin of the lines + shipping fee (excl. VAT). The cost of shipping
                             is not in any source.

    Customer:
      customer_order_number  1 for the person's first order, 2 for the second, ... (cancelled orders: NULL)
      is_new_customer_order  the person's first order (M1, M5)

    Channel (three views, so they can be compared, PM7):
      code_channel_key       influencer or affiliate, from the discount code
      last_click_channel_key last non-direct GA4 session before the order, 'direct' when there is only
                             direct traffic, NULL when GA4 has no session (GA-06)
      order_channel_key      the order's channel: the discount code first (the partner is paid for it),
                             then the last non-direct click, then direct, otherwise 'unattributed'
-#}
WITH orders AS (
    SELECT *
    FROM {{ ref('shop_orders') }}
    WHERE NOT is_test
),

lines AS (
    SELECT
        order_id,
        count(*)                                                     AS order_lines,
        sum(quantity)                                                AS items,
        sum(net_amount) FILTER (WHERE is_gift_card)                  AS gift_card_amount,
        sum(net_amount_excl_vat) FILTER (WHERE NOT is_gift_card)     AS merchandise_excl_vat,
        sum(refund_amount_excl_vat)                                  AS refund_amount_excl_vat,
        sum(cost_amount_after_returns)                               AS cost_amount_after_returns,
        sum(gross_margin)                                            AS product_margin,
        bool_or(is_unit_cost_estimated)                              AS has_estimated_cost,
        bool_or(unit_cost IS NULL AND NOT is_gift_card)              AS has_unknown_cost,
        bool_or(discount_amount > 0)                                 AS has_line_discount
    FROM {{ ref('fct_order_lines') }}
    GROUP BY order_id
),

returns AS (
    SELECT l.order_id, sum(r.refund_amount) AS refund_amount
    FROM {{ ref('shop_returns') }} AS r
    JOIN {{ ref('shop_order_lines') }} AS l USING (order_line_id)
    GROUP BY l.order_id
),

ga4_orders AS (
    SELECT DISTINCT transaction_id AS order_number
    FROM {{ ref('ga4_events') }}
    WHERE event_name = 'purchase'
),

journeys AS (
    SELECT
        order_id,
        count(*) FILTER (WHERE touchpoint_type = 'session')          AS sessions_in_journey,
        count(DISTINCT channel_key) FILTER (WHERE touchpoint_type = 'session') AS channels_in_journey,
        (array_agg(channel_key ORDER BY touchpoint_number DESC)
            FILTER (WHERE touchpoint_type = 'session' AND channel_key <> 'direct'))[1]  AS last_non_direct_channel_key,
        (array_agg(campaign_key ORDER BY touchpoint_number DESC)
            FILTER (WHERE touchpoint_type = 'session' AND channel_key <> 'direct'))[1]  AS last_non_direct_campaign_key,
        bool_or(touchpoint_type = 'session')                         AS has_session
    FROM {{ ref('fct_order_touchpoints') }}
    GROUP BY order_id
),

sequenced AS (
    SELECT
        o.*,
        CASE WHEN o.status <> 'cancelled' THEN
            row_number() OVER (PARTITION BY o.person_key, o.status = 'cancelled' ORDER BY o.created_at_utc)
        END AS customer_order_number,
        CASE WHEN o.status <> 'cancelled' THEN
            lag(o.order_date) OVER (PARTITION BY o.person_key, o.status = 'cancelled' ORDER BY o.created_at_utc)
        END AS previous_order_date
    FROM orders AS o
)

SELECT
    o.order_id,
    o.order_number,
    o.order_date,
    o.created_at_local,
    o.person_key,
    o.customer_id,
    o.is_guest_order,
    o.platform,
    o.status,
    o.status = 'cancelled'                                           AS is_cancelled,
    o.customer_order_number,
    o.customer_order_number = 1                                      AS is_new_customer_order,
    o.order_date - o.previous_order_date                             AS days_since_previous_order,
    o.shipping_country_code,
    o.shipping_postal_code,
    o.shipping_city,
    o.payment_method,
    o.discount_code,
    CASE
        WHEN o.discount_code_type IS NOT NULL THEN o.discount_code_type
        WHEN l.has_line_discount THEN 'automatic'
    END                                                              AS discount_type,
    o.influencer_creator,

    -- Channel
    CASE o.discount_code_type WHEN 'influencer' THEN 'influencer' WHEN 'affiliate' THEN 'affiliate' END AS code_channel_key,
    CASE
        WHEN j.last_non_direct_channel_key IS NOT NULL THEN j.last_non_direct_channel_key
        WHEN j.has_session THEN 'direct'
    END                                                              AS last_click_channel_key,
    CASE
        WHEN o.discount_code_type = 'influencer' THEN 'influencer'
        WHEN o.discount_code_type = 'affiliate' THEN 'affiliate'
        WHEN j.last_non_direct_channel_key IS NOT NULL THEN j.last_non_direct_channel_key
        WHEN j.has_session THEN 'direct'
        ELSE 'unattributed'
    END                                                              AS order_channel_key,
    CASE
        WHEN o.discount_code_type = 'influencer' THEN {{ campaign_key("'influencer'", 'o.influencer_creator') }}
        WHEN o.discount_code_type = 'affiliate' THEN NULL
        ELSE j.last_non_direct_campaign_key
    END                                                              AS order_campaign_key,
    CASE
        WHEN o.discount_code_type IN ('influencer', 'affiliate') THEN 'discount code'
        WHEN j.last_non_direct_channel_key IS NOT NULL THEN 'last non-direct click'
        WHEN j.has_session THEN 'direct'
        ELSE 'not tracked'
    END                                                              AS order_channel_source,
    g.order_number IS NOT NULL                                       AS is_tracked_in_ga4,
    coalesce(j.sessions_in_journey, 0)                               AS sessions_in_journey,
    coalesce(j.channels_in_journey, 0)                               AS channels_in_journey,

    -- Amounts incl. VAT
    l.order_lines,
    l.items,
    o.subtotal                                                       AS gross_amount,
    o.discount_total                                                 AS discount_amount,
    o.shipping_fee,
    o.order_total,
    o.order_total_excl_shipping,
    coalesce(l.gift_card_amount, 0)                                  AS gift_card_amount,
    coalesce(r.refund_amount, 0)                                     AS refund_amount,
    o.order_total - coalesce(r.refund_amount, 0)                     AS net_revenue,

    -- Amounts excl. VAT
    coalesce(l.merchandise_excl_vat, 0)                              AS merchandise_excl_vat,
    {{ excl_vat('o.shipping_fee', 'vs.vat_rate') }}                  AS shipping_fee_excl_vat,
    coalesce(l.refund_amount_excl_vat, 0)                            AS refund_amount_excl_vat,
    coalesce(l.cost_amount_after_returns, 0)                         AS cost_amount_after_returns,
    l.product_margin + {{ excl_vat('o.shipping_fee', 'vs.vat_rate') }} AS gross_margin,
    coalesce(l.has_estimated_cost, false)                            AS has_estimated_cost,
    coalesce(l.has_unknown_cost, false)                              AS has_unknown_cost
FROM sequenced AS o
JOIN lines AS l USING (order_id)
LEFT JOIN returns AS r USING (order_id)
LEFT JOIN ga4_orders AS g USING (order_number)
LEFT JOIN journeys AS j USING (order_id)
JOIN {{ ref('vat_rates') }} AS vs
  ON vs.country_code = o.shipping_country_code AND vs.vat_class = 'standard'
