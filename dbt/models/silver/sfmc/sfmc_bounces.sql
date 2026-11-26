{#-
    Marketing Cloud bounces, one row per bounce.
    MC-01, MC-02  timestamps -> UTC and Belgian local time
    MC-05         has_email_domain_typo: every send to these addresses bounces
    MC-07         every bounce is linked to the send just before it (send_key)
-#}
WITH events AS (
    SELECT
        row_number() OVER (ORDER BY btrim(job_id), btrim(subscriber_id), {{ sfmc_parse_timestamp('event_date') }}, is_unique) AS event_id,
        btrim(job_id)              AS job_id,
        btrim(subscriber_id)       AS subscriber_id,
        lower(btrim(domain))       AS email_domain,
        btrim(bounce_category)     AS bounce_category,
        btrim(bounce_subcategory)  AS bounce_subcategory,
        btrim(bounce_type)         AS bounce_type,
        btrim(smtp_bounce_reason)  AS smtp_bounce_reason,
        coalesce(btrim(is_unique) = 'True', false) AS is_unique,
        {{ sfmc_timestamp_to_utc('event_date') }} AS event_at_utc
    FROM {{ source('sfmc', 'bounces') }}
)

SELECT
    e.event_id                             AS bounce_id,
    l.send_key,
    e.job_id,
    e.subscriber_id,
    e.email_domain,
    t.typo_domain IS NOT NULL              AS has_email_domain_typo,
    e.bounce_category,
    e.bounce_subcategory,
    e.bounce_type,
    e.smtp_bounce_reason,
    e.is_unique,
    e.event_at_utc                         AS bounced_at_utc,
    {{ utc_to_local('e.event_at_utc') }}   AS bounced_at_local
FROM events AS e
LEFT JOIN {{ sfmc_link_to_send('events') }} AS l USING (event_id)
LEFT JOIN {{ ref('email_domain_typos') }} AS t
       ON t.typo_domain = e.email_domain
