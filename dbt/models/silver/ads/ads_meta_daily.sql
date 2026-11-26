{#-
    Meta Ads report, one row per day, campaign and ad set.
    AD-03  purchases missing on 6 days stay unknown (NULL), they are not replaced with 0;
           is_purchases_missing flags them
    AD-04  ad set names are not unique: an ad set is identified by campaign + ad set name (ad_set_key)
    X-01   purchases are Meta's own, attributed by Meta: shown next to the shop, never added up
-#}
SELECT
    btrim(reporting_starts)::date                        AS report_date,
    btrim(campaign_name)                                 AS campaign_name,
    btrim(ad_set_name)                                   AS ad_set_name,
    btrim(campaign_name) || ' / ' || btrim(ad_set_name)  AS ad_set_key,
    'paid_social'                                        AS channel_key,
    'EUR'                                                AS currency,
    nullif(btrim(amount_spent_eur), '')::numeric(12, 2)  AS cost,
    nullif(btrim(impressions), '')::integer              AS impressions,
    nullif(btrim(reach), '')::integer                    AS reach,
    nullif(btrim(link_clicks), '')::integer              AS clicks,
    nullif(btrim(purchases), '')::integer                AS platform_conversions,
    nullif(btrim(purchases_conversion_value), '')::numeric(12, 2) AS platform_conversion_value,
    nullif(btrim(purchases), '') IS NULL                 AS is_purchases_missing
FROM {{ source('ads', 'meta_ads_report') }}
