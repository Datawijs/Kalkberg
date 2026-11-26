{#-
    Marketing Cloud opens, one row per open.
    MC-01, MC-02  timestamps -> UTC and Belgian local time
    MC-06         is_icloud_address: Apple Mail Privacy Protection opens these emails automatically, so
                  reports show opens with and without them, and use clicks as the main engagement measure
    MC-07         every open is linked to the send just before it (send_key)
-#}
WITH events AS (
    SELECT
        row_number() OVER (ORDER BY btrim(job_id), btrim(subscriber_id), {{ sfmc_parse_timestamp('event_date') }}, is_unique) AS event_id,
        btrim(job_id)              AS job_id,
        btrim(subscriber_id)       AS subscriber_id,
        lower(btrim(domain))       AS email_domain,
        coalesce(btrim(is_unique) = 'True', false) AS is_unique,
        {{ sfmc_timestamp_to_utc('event_date') }} AS event_at_utc
    FROM {{ source('sfmc', 'opens') }}
)

SELECT
    e.event_id                                     AS open_id,
    l.send_key,
    e.job_id,
    e.subscriber_id,
    e.email_domain,
    coalesce(e.email_domain = 'icloud.com', false) AS is_icloud_address,
    e.is_unique,
    e.event_at_utc                                 AS opened_at_utc,
    {{ utc_to_local('e.event_at_utc') }}           AS opened_at_local,
    e.event_at_utc - l.sent_at_utc                 AS time_since_send
FROM events AS e
LEFT JOIN {{ sfmc_link_to_send('events') }} AS l USING (event_id)
