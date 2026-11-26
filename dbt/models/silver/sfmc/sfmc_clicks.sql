{#-
    Marketing Cloud clicks, one row per click.
    MC-01, MC-02  timestamps -> UTC and Belgian local time
    MC-07         every click is linked to the send just before it (send_key)
    The UTM parameters of the clicked link are split out, so a click can be matched with the GA4 session
    that followed it (D4).
-#}
WITH events AS (
    SELECT
        row_number() OVER (ORDER BY btrim(job_id), btrim(subscriber_id), {{ sfmc_parse_timestamp('event_date') }}, is_unique) AS event_id,
        btrim(job_id)              AS job_id,
        btrim(subscriber_id)       AS subscriber_id,
        lower(btrim(domain))       AS email_domain,
        btrim(url)                 AS url,
        btrim(link_name)           AS link_name,
        coalesce(btrim(is_unique) = 'True', false) AS is_unique,
        {{ sfmc_timestamp_to_utc('event_date') }} AS event_at_utc
    FROM {{ source('sfmc', 'clicks') }}
)

SELECT
    e.event_id                                         AS click_id,
    l.send_key,
    e.job_id,
    e.subscriber_id,
    e.email_domain,
    coalesce(e.email_domain = 'icloud.com', false)     AS is_icloud_address,
    e.is_unique,
    e.url,
    split_part(e.url, '?', 1)                          AS url_path,
    e.link_name,
    substring(e.url from '[?&]utm_source=([^&#]*)')    AS utm_source,
    substring(e.url from '[?&]utm_medium=([^&#]*)')    AS utm_medium,
    substring(e.url from '[?&]utm_campaign=([^&#]*)')  AS utm_campaign,
    e.event_at_utc                                     AS clicked_at_utc,
    {{ utc_to_local('e.event_at_utc') }}               AS clicked_at_local,
    e.event_at_utc - l.sent_at_utc                     AS time_since_send
FROM events AS e
LEFT JOIN {{ sfmc_link_to_send('events') }} AS l USING (event_id)
