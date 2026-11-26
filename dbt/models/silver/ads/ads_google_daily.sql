{#-
    Google Ads campaign report, one row per day and campaign.
    AD-01  the 4 total rows ('Total: Account', ...) are left out: only rows where day is a date
    AD-02  numbers in US notation with thousands separators ('1,000.25') -> numeric
    X-01   conversions are Google's own, attributed by Google: shown next to the shop, never added up
-#}
SELECT
    btrim(day)::date                          AS report_date,
    btrim(campaign)                           AS campaign_name,
    btrim(campaign_type)                      AS campaign_type,
    'paid_search'                             AS channel_key,
    btrim(currency_code)                      AS currency,
    {{ us_number('cost', 'numeric(12, 2)') }} AS cost,
    {{ us_number('impressions', 'integer') }} AS impressions,
    {{ us_number('clicks', 'integer') }}      AS clicks,
    {{ us_number('conversions', 'numeric(12, 2)') }} AS platform_conversions,
    {{ us_number('conv_value', 'numeric(12, 2)') }}  AS platform_conversion_value
FROM {{ source('ads', 'google_ads_campaign_report') }}
WHERE btrim(day) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
