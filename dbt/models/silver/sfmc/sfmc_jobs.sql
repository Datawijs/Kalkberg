{#-
    Marketing Cloud email jobs, one row per job: one newsletter or campaign email in one language, or one
    journey email per year and language.
    MC-01, MC-02  timestamps -> UTC and Belgian local time
    utm_campaign is the campaign that the links in the email carry, so that email traffic in GA4 can be
    linked back to the email (sfmc_10).
-#}
WITH jobs AS (
    SELECT
        j.*,
        btrim(j.email_name) AS email_name_clean,
        CASE
            WHEN btrim(j.job_type) = 'TriggeredSend' THEN 'journey'
            WHEN btrim(j.category) = 'Newsletter' THEN 'newsletter'
            WHEN btrim(j.category) = 'Campaign' THEN 'campaign'
            ELSE 'other'
        END AS send_type
    FROM {{ source('sfmc', 'jobs') }} AS j
)

SELECT
    btrim(j.job_id)                                      AS job_id,
    btrim(j.email_id)                                    AS email_id,
    j.email_name_clean                                   AS email_name,
    -- Without the language suffix (and, for journeys, the year): the same email in every language
    regexp_replace(j.email_name_clean, '(_[0-9]{4})?_[A-Z]{2}$', '') AS email_base_name,
    lower(substring(j.email_name_clean from '_([A-Z]{2})$')) AS email_language,
    j.send_type,
    btrim(j.category)                                    AS category,
    btrim(j.job_type)                                    AS job_type,
    btrim(j.job_status)                                  AS job_status,
    btrim(j.email_subject)                               AS email_subject,
    js.journey_name,
    js.journey_step,
    coalesce(js.utm_campaign,
             lower(regexp_replace(j.email_name_clean, '_[A-Z]{2}$', ''))) AS utm_campaign,
    nullif(btrim(j.triggered_send_customer_key), '')     AS triggered_send_customer_key,
    {{ sfmc_timestamp_columns('j.sched_time', 'scheduled_at') }},
    {{ sfmc_timestamp_columns('j.pickup_time', 'picked_up_at') }},
    {{ sfmc_timestamp_columns('j.delivered_time', 'delivered_at') }}
FROM jobs AS j
LEFT JOIN {{ ref('sfmc_journeys') }} AS js
       ON js.triggered_send_customer_key = btrim(j.triggered_send_customer_key)
