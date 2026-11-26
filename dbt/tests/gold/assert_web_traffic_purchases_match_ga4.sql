-- GA-05: fct_web_traffic takes its purchases from the deduplicated GA4 events, so it holds every
-- GA4 purchase exactly once.
SELECT (SELECT sum(purchases) FROM {{ ref('fct_web_traffic') }}) AS traffic_purchases,
       (SELECT count(*) FROM {{ ref('ga4_events') }} WHERE event_name = 'purchase') AS ga4_purchases
WHERE (SELECT sum(purchases) FROM {{ ref('fct_web_traffic') }})
      <> (SELECT count(*) FROM {{ ref('ga4_events') }} WHERE event_name = 'purchase')
