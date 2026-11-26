{#-
    Marketing Cloud unsubscribes, one row per unsubscribe event.
    MC-01, MC-02  timestamps -> UTC and Belgian local time
    MC-07         every unsubscribe is linked to the send just before it (send_key)
-#}
WITH events AS (
    SELECT
        row_number() OVER (ORDER BY btrim(job_id), btrim(subscriber_id), {{ sfmc_parse_timestamp('event_date') }}, is_unique) AS event_id,
        btrim(job_id)              AS job_id,
        btrim(subscriber_id)       AS subscriber_id,
        lower(btrim(domain))       AS email_domain,
        coalesce(btrim(is_unique) = 'True', false) AS is_unique,
        {{ sfmc_timestamp_to_utc('event_date') }} AS event_at_utc
    FROM {{ source('sfmc', 'unsubscribes') }}
)

SELECT
    e.event_id                             AS unsubscribe_id,
    l.send_key,
    e.job_id,
    e.subscriber_id,
    e.email_domain,
    e.is_unique,
    e.event_at_utc                         AS unsubscribed_at_utc,
    {{ utc_to_local('e.event_at_utc') }}   AS unsubscribed_at_local
FROM events AS e
LEFT JOIN {{ sfmc_link_to_send('events') }} AS l USING (event_id)
