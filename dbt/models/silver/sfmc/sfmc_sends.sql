{#-
    Marketing Cloud sends, one row per send.
    MC-01, MC-02  timestamps -> UTC and Belgian local time
    MC-07         a send is identified by job, subscriber and send time (send_key): journey emails go
                  to the same person many times, and every one of them is a real send
-#}
{{ config(indexes=[{'columns': ['job_id', 'subscriber_id']}]) }}

WITH sends AS (
    SELECT
        btrim(job_id)        AS job_id,
        btrim(subscriber_id) AS subscriber_id,
        btrim(batch_id)      AS batch_id,
        btrim(list_id)       AS list_id,
        lower(btrim(domain)) AS email_domain,
        {{ sfmc_timestamp_to_utc('event_date') }} AS sent_at_utc
    FROM {{ source('sfmc', 'sent') }}
)

SELECT
    job_id || '-' || subscriber_id || '-' || to_char(sent_at_utc, 'YYYYMMDDHH24MISS') AS send_key,
    job_id,
    subscriber_id,
    batch_id,
    list_id,
    email_domain,
    coalesce(email_domain = 'icloud.com', false) AS is_icloud_address,
    sent_at_utc,
    {{ utc_to_local('sent_at_utc') }}            AS sent_at_local,
    ({{ utc_to_local('sent_at_utc') }})::date    AS sent_date
FROM sends
