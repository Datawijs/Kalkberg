-- =====================================================================
-- Kalkberg profiling - round 2: targeted checks on ads (Google Ads and Meta Ads reports)
-- Created by 02-run-targeted-checks.sql. Every check is a view in the profiling schema.
-- =====================================================================

CREATE VIEW profiling.ads_01_google_non_data_rows AS
SELECT *
FROM ads.google_ads_campaign_report
WHERE day !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$';
COMMENT ON VIEW profiling.ads_01_google_non_data_rows IS 'Rows in the Google Ads report that are not a day of data';

CREATE VIEW profiling.ads_02_number_notation AS
WITH v AS (
    SELECT 'google.cost' AS column_name, cost AS value FROM ads.google_ads_campaign_report WHERE day ~ '^[0-9]{4}-'
    UNION ALL SELECT 'google.impressions', impressions FROM ads.google_ads_campaign_report WHERE day ~ '^[0-9]{4}-'
    UNION ALL SELECT 'google.clicks',      clicks      FROM ads.google_ads_campaign_report WHERE day ~ '^[0-9]{4}-'
    UNION ALL SELECT 'google.conversions', conversions FROM ads.google_ads_campaign_report WHERE day ~ '^[0-9]{4}-'
    UNION ALL SELECT 'google.conv_value',  conv_value  FROM ads.google_ads_campaign_report WHERE day ~ '^[0-9]{4}-'
    UNION ALL SELECT 'meta.amount_spent_eur',           amount_spent_eur           FROM ads.meta_ads_report
    UNION ALL SELECT 'meta.impressions',                impressions                FROM ads.meta_ads_report
    UNION ALL SELECT 'meta.reach',                      reach                      FROM ads.meta_ads_report
    UNION ALL SELECT 'meta.link_clicks',                link_clicks                FROM ads.meta_ads_report
    UNION ALL SELECT 'meta.purchases',                  purchases                  FROM ads.meta_ads_report
    UNION ALL SELECT 'meta.purchases_conversion_value', purchases_conversion_value FROM ads.meta_ads_report
), c AS (
    SELECT column_name, value,
           CASE
               WHEN value IS NULL                                        THEN 'empty'
               WHEN value ~ '^[0-9]+(\.[0-9]+)?$'                        THEN 'plain number'
               WHEN value ~ '^[0-9]{1,3}(,[0-9]{3})+(\.[0-9]+)?$'        THEN 'with thousands separator'
               ELSE 'other'
           END AS notation
    FROM v
)
SELECT column_name, notation, count(*) AS row_count, min(value) AS example
FROM c
GROUP BY column_name, notation
ORDER BY column_name, notation;
COMMENT ON VIEW profiling.ads_02_number_notation IS 'Which number notations are used in the ad reports (data rows only)?';

CREATE VIEW profiling.ads_03_grain AS
SELECT 'google: more than one row per day and campaign' AS rule, count(*) AS row_count
FROM (SELECT day, campaign FROM ads.google_ads_campaign_report WHERE day ~ '^[0-9]{4}-' GROUP BY 1, 2 HAVING count(*) > 1) AS d
UNION ALL
SELECT 'meta: more than one row per day, campaign and ad set', count(*)
FROM (SELECT reporting_starts, campaign_name, ad_set_name FROM ads.meta_ads_report GROUP BY 1, 2, 3 HAVING count(*) > 1) AS d
UNION ALL
SELECT 'meta: reporting_starts differs from reporting_ends', count(*)
FROM ads.meta_ads_report WHERE reporting_starts <> reporting_ends
UNION ALL
SELECT 'meta: ad set name used in more than one campaign', count(*)
FROM (SELECT ad_set_name FROM ads.meta_ads_report GROUP BY 1 HAVING count(DISTINCT campaign_name) > 1) AS d;
COMMENT ON VIEW profiling.ads_03_grain IS 'What is one row in each ad report, and is that grain respected?';

CREATE VIEW profiling.ads_04_meta_missing_purchases AS
SELECT *
FROM ads.meta_ads_report
WHERE purchases IS NULL
ORDER BY reporting_starts;
COMMENT ON VIEW profiling.ads_04_meta_missing_purchases IS 'Meta rows without a purchases value';

CREATE VIEW profiling.ads_05_campaign_coverage AS
SELECT 'Google Ads' AS platform, campaign, campaign_type AS detail,
       min(day::date) AS first_day, max(day::date) AS last_day,
       count(DISTINCT day) AS days_with_data,
       (max(day::date) - min(day::date) + 1) - count(DISTINCT day) AS days_missing_in_between
FROM ads.google_ads_campaign_report
WHERE day ~ '^[0-9]{4}-'
GROUP BY campaign, campaign_type
UNION ALL
SELECT 'Meta Ads', campaign_name, string_agg(DISTINCT ad_set_name, ', '),
       min(reporting_starts::date), max(reporting_starts::date),
       count(DISTINCT reporting_starts),
       (max(reporting_starts::date) - min(reporting_starts::date) + 1) - count(DISTINCT reporting_starts)
FROM ads.meta_ads_report
GROUP BY campaign_name
ORDER BY platform, first_day, campaign;
COMMENT ON VIEW profiling.ads_05_campaign_coverage IS 'Which period does each campaign cover, and are there gaps?';
