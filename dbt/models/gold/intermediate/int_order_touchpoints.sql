{#-
    Customer journeys and attribution (PM3, PM4). One row per order and touchpoint.
    Intermediate: fct_orders derives the order's channel from it, and fct_order_touchpoints adds the
    order's date and amounts on top.

    The touchpoints of an order are the GA4 sessions of the same person (logged in) or the same
    browser (user_pseudo_id of the purchase session) that started at most 30 days before the order
    and after the person's previous order. GA4 only sees sessions with consent (GA-06) and the event
    export only holds sessions with shopping activity (GA-08), so journeys are a lower bound.

    An order without any session gets one touchpoint 'no session' with the order's own channel
    (discount code or 'unattributed'), so that the weights of every model add up to 1 per order and
    attributed revenue always adds up to total revenue.

    Weights per attribution model:
      first click      100% to the first touchpoint
      last click       100% to the last touchpoint
      linear           equal shares
      position based   40% first, 40% last, 20% shared by the ones in between (50/50 with two)
-#}
WITH orders AS (
    SELECT
        o.order_id,
        o.order_number,
        o.person_key,
        o.created_at_utc,
        o.discount_code_type,
        o.influencer_creator,
        lag(o.created_at_utc) OVER (PARTITION BY o.person_key ORDER BY o.created_at_utc) AS previous_order_at_utc,
        row_number() OVER (PARTITION BY o.person_key ORDER BY o.created_at_utc) = 1     AS is_first_order
    FROM {{ ref('shop_orders') }} AS o
    WHERE NOT o.is_test AND o.status <> 'cancelled'
),

purchase_browsers AS (
    SELECT DISTINCT e.transaction_id AS order_number, s.user_pseudo_id
    FROM {{ ref('ga4_events') }} AS e
    JOIN {{ ref('ga4_sessions') }} AS s USING (session_key)
    WHERE e.event_name = 'purchase'
),

candidate_sessions AS (
    -- Sessions of the same person
    SELECT o.order_id, s.session_key
    FROM orders AS o
    JOIN {{ ref('ga4_sessions') }} AS s ON s.person_key = o.person_key
    WHERE s.started_at_utc BETWEEN o.created_at_utc - interval '{{ var("attribution_lookback_days") }} days'
                               AND o.created_at_utc + interval '10 minutes'
      AND (o.previous_order_at_utc IS NULL OR s.started_at_utc > o.previous_order_at_utc)
    UNION
    -- Sessions of the browser the order was placed with
    SELECT o.order_id, s.session_key
    FROM orders AS o
    JOIN purchase_browsers AS pb USING (order_number)
    JOIN {{ ref('ga4_sessions') }} AS s ON s.user_pseudo_id = pb.user_pseudo_id
    WHERE s.started_at_utc BETWEEN o.created_at_utc - interval '{{ var("attribution_lookback_days") }} days'
                               AND o.created_at_utc + interval '10 minutes'
      AND (o.previous_order_at_utc IS NULL OR s.started_at_utc > o.previous_order_at_utc)
),

session_touchpoints AS (
    SELECT
        c.order_id,
        'session'                    AS touchpoint_type,
        s.session_key,
        s.started_at_utc,
        s.started_at_local,
        s.session_date               AS touchpoint_date,
        s.channel_key,
        {{ campaign_key('s.channel_key', 's.campaign_name') }} AS campaign_key,
        s.device_category,
        s.country_code,
        s.purchases > 0              AS is_purchase_session
    FROM candidate_sessions AS c
    JOIN {{ ref('ga4_sessions') }} AS s USING (session_key)
),

no_session_touchpoints AS (
    SELECT
        o.order_id,
        'no session'                 AS touchpoint_type,
        NULL::text                   AS session_key,
        o.created_at_utc             AS started_at_utc,
        {{ utc_to_local('o.created_at_utc') }} AS started_at_local,
        ({{ utc_to_local('o.created_at_utc') }})::date AS touchpoint_date,
        CASE o.discount_code_type
            WHEN 'influencer' THEN 'influencer'
            WHEN 'affiliate' THEN 'affiliate'
            ELSE 'unattributed'
        END                          AS channel_key,
        CASE o.discount_code_type
            WHEN 'influencer' THEN {{ campaign_key("'influencer'", 'o.influencer_creator') }}
        END                          AS campaign_key,
        NULL::text                   AS device_category,
        NULL::text                   AS country_code,
        false                        AS is_purchase_session
    FROM orders AS o
    WHERE NOT EXISTS (SELECT 1 FROM candidate_sessions AS c WHERE c.order_id = o.order_id)
),

touchpoints AS (
    SELECT * FROM session_touchpoints
    UNION ALL
    SELECT * FROM no_session_touchpoints
),

numbered AS (
    SELECT
        t.*,
        row_number() OVER (PARTITION BY t.order_id ORDER BY t.started_at_utc, t.session_key) AS touchpoint_number,
        count(*) OVER (PARTITION BY t.order_id)                                             AS touchpoints_in_journey
    FROM touchpoints AS t
)

SELECT
    n.order_id || '-' || n.touchpoint_number                AS touchpoint_id,
    n.order_id,
    o.order_number,
    o.person_key,
    o.is_first_order,
    n.touchpoint_type,
    n.session_key,
    n.touchpoint_number,
    n.touchpoints_in_journey,
    n.touchpoint_date,
    n.started_at_local,
    round(extract(epoch FROM o.created_at_utc - n.started_at_utc) / 86400.0, 2) AS days_before_order,
    n.channel_key,
    n.campaign_key,
    n.device_category,
    n.country_code,
    n.is_purchase_session,
    (n.touchpoint_number = 1)::int::numeric                 AS weight_first_click,
    (n.touchpoint_number = n.touchpoints_in_journey)::int::numeric AS weight_last_click,
    round(1.0 / n.touchpoints_in_journey, 6)                AS weight_linear,
    CASE
        WHEN n.touchpoints_in_journey = 1 THEN 1.0
        WHEN n.touchpoints_in_journey = 2 THEN 0.5
        WHEN n.touchpoint_number IN (1, n.touchpoints_in_journey) THEN 0.4
        ELSE round(0.2 / (n.touchpoints_in_journey - 2), 6)
    END                                                     AS weight_position_based
FROM numbered AS n
JOIN orders AS o USING (order_id)
