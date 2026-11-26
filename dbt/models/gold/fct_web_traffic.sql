{#-
    Website traffic and conversion (PM10, PM1), one row per day, channel, campaign, device and country.
      sessions ... checkouts       from the GA4 traffic report: the only source with all sessions (GA-08)
      purchases, purchase_value    from the GA4 events, with purchases sent twice counted once (GA-05).
                                   The traffic report's own purchases are not used.
    GA-04  is_shipping_country: leave the US, the UK and unknown countries out of conversion rates.
    GA-06  GA4 only sees visitors who accept cookies: use these numbers for rates and shares, the shop
           for orders and revenue.
-#}
WITH traffic AS (
    SELECT
        traffic_date                                       AS traffic_date,
        channel_key,
        {{ campaign_key('channel_key', 'campaign_name') }} AS campaign_key,
        device_category,
        country_code,
        sum(sessions)          AS sessions,
        sum(total_users)       AS users,
        sum(new_users)         AS new_users,
        sum(engaged_sessions)  AS engaged_sessions,
        sum(add_to_carts)      AS add_to_carts,
        sum(checkouts)         AS checkouts
    FROM {{ ref('ga4_daily_traffic') }}
    GROUP BY 1, 2, 3, 4, 5
),

purchases AS (
    SELECT
        session_date                                       AS traffic_date,
        channel_key,
        {{ campaign_key('channel_key', 'campaign_name') }} AS campaign_key,
        device_category,
        country_code,
        sum(purchases)         AS purchases,
        sum(purchase_value)    AS purchase_value
    FROM {{ ref('ga4_sessions') }}
    WHERE purchases > 0
    GROUP BY 1, 2, 3, 4, 5
)

SELECT
    coalesce(t.traffic_date, p.traffic_date)       AS traffic_date,
    coalesce(t.channel_key, p.channel_key)         AS channel_key,
    coalesce(t.campaign_key, p.campaign_key)       AS campaign_key,
    coalesce(t.device_category, p.device_category) AS device_category,
    coalesce(t.country_code, p.country_code)       AS country_code,
    c.is_shipping_country,
    coalesce(t.sessions, 0)                        AS sessions,
    coalesce(t.users, 0)                           AS users,
    coalesce(t.new_users, 0)                       AS new_users,
    coalesce(t.engaged_sessions, 0)                AS engaged_sessions,
    coalesce(t.add_to_carts, 0)                    AS add_to_carts,
    coalesce(t.checkouts, 0)                       AS checkouts,
    coalesce(p.purchases, 0)                       AS purchases,
    coalesce(p.purchase_value, 0)                  AS purchase_value
FROM traffic AS t
FULL OUTER JOIN purchases AS p
  ON p.traffic_date = t.traffic_date
 AND p.channel_key = t.channel_key
 AND coalesce(p.campaign_key, '') = coalesce(t.campaign_key, '')
 AND p.device_category = t.device_category
 AND p.country_code = t.country_code
JOIN {{ ref('dim_country') }} AS c
  ON c.country_code = coalesce(t.country_code, p.country_code)
