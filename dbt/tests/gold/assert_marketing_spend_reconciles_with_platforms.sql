-- The platform cost in fct_marketing_spend equals the cost in the ad reports, per month and platform.
WITH spend AS (
    SELECT date_trunc('month', spend_date) AS month, channel_key, sum(cost) AS cost
    FROM {{ ref('fct_marketing_spend') }}
    WHERE channel_key IN ('paid_search', 'paid_social')
    GROUP BY 1, 2
),
platforms AS (
    SELECT date_trunc('month', report_date) AS month, channel_key, sum(cost) AS cost
    FROM {{ ref('fct_ad_performance') }}
    GROUP BY 1, 2
)
SELECT *
FROM spend AS s
FULL OUTER JOIN platforms AS p USING (month, channel_key)
WHERE s.cost IS DISTINCT FROM p.cost
