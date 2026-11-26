{#-
    GA4 traffic report, one row per day, source / medium, campaign, device and country. Typed.
    This is the source for sessions, users and conversion rates (GA-08).
    GA-01..03  channel and campaign through ga4_traffic_sources
    GA-04      country -> ISO code; US, UK and (not set) flagged through is_shipping_country
    GA-05      the purchases in this report include purchases sent twice. Take purchases and revenue
               from ga4_events instead; the columns are kept with a _reported suffix as evidence.
-#}
SELECT
    to_date(d.date, 'YYYYMMDD')                                  AS traffic_date,
    split_part(d.session_source_medium, ' / ', 1)                AS source,
    split_part(d.session_source_medium, ' / ', 2)                AS medium,
    d.session_campaign                                           AS campaign,
    t.channel_key,
    t.campaign_name,
    t.campaign_issue,
    t.influencer_creator,
    lower(btrim(d.device_category))                              AS device_category,
    c.country_code,
    co.is_shipping_country,
    d.sessions::integer                                          AS sessions,
    d.total_users::integer                                       AS total_users,
    d.new_users::integer                                         AS new_users,
    d.engaged_sessions::integer                                  AS engaged_sessions,
    d.add_to_carts::integer                                      AS add_to_carts,
    d.checkouts::integer                                         AS checkouts,
    d.ecommerce_purchases::integer                               AS ecommerce_purchases_reported,
    d.purchase_revenue::numeric(12, 2)                           AS purchase_revenue_reported
FROM {{ source('ga4', 'daily_traffic') }} AS d
LEFT JOIN {{ ref('ga4_traffic_sources') }} AS t
       ON t.source IS NOT DISTINCT FROM split_part(d.session_source_medium, ' / ', 1)
      AND t.medium IS NOT DISTINCT FROM split_part(d.session_source_medium, ' / ', 2)
      AND t.campaign IS NOT DISTINCT FROM d.session_campaign
LEFT JOIN {{ ref('map_country') }} AS c
       ON c.notation = lower(btrim(d.country))
LEFT JOIN {{ ref('countries') }} AS co
       ON co.country_code = c.country_code
