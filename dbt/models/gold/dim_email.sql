{#-
    Emails, one row per Marketing Cloud job: one newsletter or campaign email in one language, or one
    journey email per year and language (E2, E3, E9).
-#}
SELECT
    j.job_id,
    j.email_name,
    j.email_base_name,
    j.email_language,
    j.send_type,
    j.journey_name,
    j.journey_step,
    j.email_subject,
    j.utm_campaign,
    {{ campaign_key("'email'", 'j.utm_campaign') }} AS campaign_key,
    j.delivered_at_local::date                      AS delivered_date
FROM {{ ref('sfmc_jobs') }} AS j
