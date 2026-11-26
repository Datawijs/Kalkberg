{#-
    Campaigns of every channel, one row per channel and campaign name. The same campaign is called the
    same in GA4, the ad reports and Marketing Cloud after the cleaning in silver (GA-02), so one key
    links them: '<channel_key> | <campaign name>'.
      paid_search     Google Ads campaigns
      paid_social     Meta campaigns, plus 'Unknown (template not filled)' (GA-03)
      email           utm_campaign of newsletters, campaigns and journeys
      influencer      one campaign per creator
      affiliate       the affiliate partners' campaigns in GA4
-#}
WITH google AS (
    SELECT 'paid_search' AS channel_key, campaign_name, 'Google Ads' AS platform,
           min(campaign_type) AS campaign_type, min(report_date) AS first_date, max(report_date) AS last_date
    FROM {{ ref('ads_google_daily') }}
    GROUP BY campaign_name
),

meta AS (
    SELECT 'paid_social', campaign_name, 'Meta',
           CASE
               WHEN campaign_name ILIKE 'retargeting%' OR campaign_name ILIKE '%- retargeting' THEN 'Retargeting'
               ELSE 'Prospecting'
           END,
           min(report_date), max(report_date)
    FROM {{ ref('ads_meta_daily') }}
    GROUP BY campaign_name
),

email AS (
    SELECT 'email', utm_campaign, 'Marketing Cloud',
           initcap(min(send_type)),
           min(sent_date), max(sent_date)
    FROM {{ ref('sfmc_jobs') }} AS j
    LEFT JOIN (SELECT job_id, min(sent_date) AS sent_date FROM {{ ref('sfmc_sends') }} GROUP BY job_id) AS s USING (job_id)
    GROUP BY utm_campaign
),

influencer AS (
    SELECT 'influencer', creator, platform, 'Influencer contract', contract_start_date, contract_end_date
    FROM {{ ref('budget_influencer_contracts') }}
),

ga4_only AS (
    -- Campaigns that only GA4 knows, such as the affiliate pages and the unfilled Meta template
    SELECT DISTINCT t.channel_key, t.campaign_name, 'GA4' AS platform, NULL::text AS campaign_type,
           NULL::date AS first_date, NULL::date AS last_date
    FROM {{ ref('ga4_traffic_sources') }} AS t
    WHERE t.campaign_name IS NOT NULL
),

all_campaigns AS (
    SELECT * FROM google
    UNION ALL SELECT * FROM meta
    UNION ALL SELECT * FROM email
    UNION ALL SELECT * FROM influencer
    UNION ALL
    SELECT g.*
    FROM ga4_only AS g
    WHERE NOT EXISTS (
        SELECT 1 FROM (SELECT channel_key, campaign_name FROM google
                       UNION ALL SELECT 'paid_social', campaign_name FROM meta
                       UNION ALL SELECT 'email', utm_campaign FROM {{ ref('sfmc_jobs') }}
                       UNION ALL SELECT 'influencer', creator FROM {{ ref('budget_influencer_contracts') }}) AS k
        WHERE k.channel_key = g.channel_key AND k.campaign_name = g.campaign_name)
)

SELECT
    {{ campaign_key('channel_key', 'campaign_name') }} AS campaign_key,
    channel_key,
    campaign_name,
    platform,
    campaign_type,
    first_date,
    last_date
FROM all_campaigns
