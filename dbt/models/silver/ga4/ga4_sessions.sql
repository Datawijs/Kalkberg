{#-
    GA4 sessions from the event export, one row per session (session_start).
    GA-01..03  channel and campaign through ga4_traffic_sources
    GA-04      country -> ISO code; US, UK and (not set) flagged through is_shipping_country
    GA-08      only sessions with shopping activity; total traffic and conversion rates come from
               ga4_daily_traffic
    The logged-in customer (user_id) can be set on any event of the session, so it is taken from all of them.
-#}
WITH session_starts AS (
    SELECT
        e.*,
        e.user_pseudo_id || '.' || e.ga_session_id AS session_key,
        {{ ga4_micros_to_utc('e.event_timestamp') }} AS started_at_utc_calc,
        row_number() OVER (PARTITION BY e.user_pseudo_id, e.ga_session_id ORDER BY e.event_timestamp::bigint) AS start_sequence
    FROM {{ source('ga4', 'events') }} AS e
    WHERE e.event_name = 'session_start'
),

session_activity AS (
    SELECT
        session_key,
        max(customer_id)                                         AS customer_id,
        count(*) FILTER (WHERE event_name = 'add_to_cart')       AS add_to_cart_events,
        count(*) FILTER (WHERE event_name = 'begin_checkout')    AS begin_checkout_events,
        count(*) FILTER (WHERE event_name = 'purchase')          AS purchases,
        sum(purchase_value) FILTER (WHERE event_name = 'purchase') AS purchase_value
    FROM {{ ref('ga4_events') }}
    GROUP BY session_key
)

SELECT
    s.session_key,
    s.user_pseudo_id,
    a.customer_id,
    p.person_key,
    s.ga_session_number::integer                     AS session_number,
    to_date(s.event_date, 'YYYYMMDD')                AS session_date,
    s.started_at_utc_calc                            AS started_at_utc,
    {{ utc_to_local('s.started_at_utc_calc') }}      AS started_at_local,
    s.source,
    s.medium,
    s.campaign,
    t.channel_key,
    t.campaign_name,
    t.campaign_issue,
    t.influencer_creator,
    nullif(btrim(s.page_location), '')               AS landing_page,
    lower(btrim(s.device_category))                  AS device_category,
    c.country_code,
    co.is_shipping_country,
    coalesce(a.add_to_cart_events, 0)                AS add_to_cart_events,
    coalesce(a.begin_checkout_events, 0)             AS begin_checkout_events,
    coalesce(a.purchases, 0)                         AS purchases,
    coalesce(a.purchase_value, 0)                    AS purchase_value
FROM session_starts AS s
LEFT JOIN session_activity AS a USING (session_key)
LEFT JOIN {{ ref('person_identities') }} AS p
       ON p.identity_type = 'shop_account' AND p.identity_id = a.customer_id::text
LEFT JOIN {{ ref('ga4_traffic_sources') }} AS t
       ON t.source IS NOT DISTINCT FROM s.source
      AND t.medium IS NOT DISTINCT FROM s.medium
      AND t.campaign IS NOT DISTINCT FROM s.campaign
LEFT JOIN {{ ref('map_country') }} AS c
       ON c.notation = lower(btrim(s.country))
LEFT JOIN {{ ref('countries') }} AS co
       ON co.country_code = c.country_code
WHERE s.start_sequence = 1
