{#-
    Ad platform performance (PM1, PM5, PM6), one row per day, platform, campaign and ad set
    (Google Ads has no ad sets in the report).
    X-01  platform_conversions and platform_conversion_value are the platform's own, attributed by its
          own rules. Show them next to the shop's orders, never add them up.
    AD-03 Meta purchases missing on some days stay unknown.
-#}
SELECT
    report_date,
    'Google Ads'                                          AS platform,
    channel_key,
    {{ campaign_key('channel_key', 'campaign_name') }}    AS campaign_key,
    NULL::text                                            AS ad_set_name,
    cost,
    impressions,
    NULL::integer                                         AS reach,
    clicks,
    platform_conversions,
    platform_conversion_value,
    false                                                 AS is_conversions_missing
FROM {{ ref('ads_google_daily') }}

UNION ALL

SELECT
    report_date,
    'Meta',
    channel_key,
    {{ campaign_key('channel_key', 'campaign_name') }},
    ad_set_name,
    cost,
    impressions,
    reach,
    clicks,
    platform_conversions,
    platform_conversion_value,
    is_purchases_missing
FROM {{ ref('ads_meta_daily') }}
