{#-
    One row per combination of source, medium and campaign that GA4 reports, in the event export
    or in the traffic report, with the channel and campaign it belongs to.
    GA-01  every source / medium spelling -> one channel (seed map_traffic_source). A campaign that is
           an influencer's name always means the influencer channel, also when the medium is 'social'.
    GA-02  both naming styles of Meta campaigns -> the campaign name used in Meta; lena_sends -> lena.sends
    GA-03  the unfilled template {{ '{{campaign.name}}' }} -> 'Unknown (template not filled)'
-#}
WITH combinations AS (
    SELECT DISTINCT source, medium, campaign
    FROM {{ source('ga4', 'events') }}
    WHERE event_name = 'session_start'
    UNION
    SELECT DISTINCT
        split_part(session_source_medium, ' / ', 1),
        split_part(session_source_medium, ' / ', 2),
        session_campaign
    FROM {{ source('ga4', 'daily_traffic') }}
),

normalised AS (
    SELECT
        source,
        medium,
        campaign,
        lower(btrim(source))   AS source_normalised,
        lower(btrim(medium))   AS medium_normalised,
        {{ name_key('campaign') }} AS campaign_key
    FROM combinations
),

meta_campaigns AS (
    SELECT DISTINCT btrim(campaign_name) AS campaign_name, {{ name_key('campaign_name') }} AS campaign_key
    FROM {{ source('ads', 'meta_ads_report') }}
),

google_campaigns AS (
    SELECT DISTINCT btrim(campaign) AS campaign_name
    FROM {{ source('ads', 'google_ads_campaign_report') }}
),

mapped AS (
    SELECT
        n.*,
        CASE WHEN ic.creator IS NOT NULL THEN 'influencer' ELSE m.channel_key END AS channel_key,
        ic.creator,
        mc.campaign_name AS meta_campaign_name,
        gc.campaign_name AS google_campaign_name
    FROM normalised AS n
    LEFT JOIN {{ ref('map_traffic_source') }} AS m
           ON m.source = n.source_normalised AND m.medium = n.medium_normalised
    LEFT JOIN {{ ref('budget_influencer_contracts') }} AS ic
           ON ic.creator_key = n.campaign_key
    LEFT JOIN meta_campaigns AS mc
           ON mc.campaign_key = n.campaign_key
    LEFT JOIN google_campaigns AS gc
           ON gc.campaign_name = btrim(n.campaign)
)

SELECT
    source,
    medium,
    campaign,
    source_normalised,
    medium_normalised,
    channel_key,
    CASE
        WHEN btrim(campaign) = '{{ "{{campaign.name}}" }}' THEN 'Unknown (template not filled)'
        WHEN channel_key = 'influencer' THEN creator
        WHEN channel_key = 'paid_social' THEN coalesce(meta_campaign_name, btrim(campaign))
        WHEN channel_key = 'paid_search' THEN coalesce(google_campaign_name, btrim(campaign))
        WHEN channel_key = 'email' THEN lower(btrim(campaign))
        WHEN btrim(campaign) IN ('(direct)', '(organic)', '(referral)', '(not set)', '') THEN NULL
        ELSE btrim(campaign)
    END AS campaign_name,
    CASE
        WHEN btrim(campaign) = '{{ "{{campaign.name}}" }}' THEN 'template not filled'
        WHEN channel_key = 'paid_social' AND meta_campaign_name IS NULL THEN 'not found in Meta'
        WHEN channel_key = 'paid_search' AND google_campaign_name IS NULL THEN 'not found in Google Ads'
    END AS campaign_issue,
    creator AS influencer_creator
FROM mapped
