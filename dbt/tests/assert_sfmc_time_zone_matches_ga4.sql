-- MC-02: after adding 6 hours, an email click and the GA4 email session that it started must be the same
-- moment. Clicks and sessions of the same person within 12 hours of each other are paired. Fails when
-- fewer than 90% of the pairs are within 5 minutes, in any month.
WITH clicks AS (
    SELECT s.person_key, c.clicked_at_utc
    FROM {{ ref('sfmc_clicks') }} AS c
    JOIN {{ ref('sfmc_subscribers') }} AS s USING (subscriber_id)
),
pairs AS (
    SELECT c.clicked_at_utc, abs(extract(epoch FROM g.started_at_utc - c.clicked_at_utc)) AS seconds_apart
    FROM clicks AS c
    JOIN {{ ref('ga4_sessions') }} AS g
      ON g.person_key = c.person_key
     AND g.channel_key = 'email'
     AND g.started_at_utc BETWEEN c.clicked_at_utc - interval '12 hours' AND c.clicked_at_utc + interval '12 hours'
)
SELECT date_trunc('month', clicked_at_utc)::date AS click_month,
       count(*) AS pairs,
       avg((seconds_apart <= 300)::int) AS share_within_5_minutes
FROM pairs
GROUP BY 1
HAVING avg((seconds_apart <= 300)::int) < 0.90
