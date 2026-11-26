-- GA-05: a purchase sent twice must be kept once.
SELECT transaction_id, count(*) AS purchase_events
FROM {{ ref('ga4_events') }}
WHERE event_name = 'purchase'
GROUP BY transaction_id
HAVING count(*) > 1
