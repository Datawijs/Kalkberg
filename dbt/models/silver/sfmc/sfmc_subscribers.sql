{#-
    Marketing Cloud subscriber records, one row per record (subscriber_id).
    MC-01, MC-02  timestamps -> UTC and Belgian local time
    MC-03         person_key: records with the same email address are one person
    MC-04         subscriber_key_type shows what the key is; it is not used to link to the shop
    MC-05         email domains with a typo flagged (has_email_domain_typo)
    MC-06         icloud.com addresses flagged: their opens are mostly automatic
    X-02          is_shop_customer: the person also has a shop account (linked on email address)
-#}
SELECT
    btrim(s.subscriber_id)                                     AS subscriber_id,
    btrim(s.subscriber_key)                                    AS subscriber_key,
    CASE
        WHEN btrim(s.subscriber_key) ~ '^[0-9]+$' THEN 'customer number'
        WHEN btrim(s.subscriber_key) LIKE '%@%' THEN 'email address'
        WHEN btrim(s.subscriber_key) ~ '^[A-Z]{2}-[0-9]+$' THEN 'sign-up key'
        ELSE 'other'
    END                                                        AS subscriber_key_type,
    p.person_key,
    coalesce(p.matched_on = 'shop account', false)             AS is_shop_customer,
    {{ normalise_email('s.email_address') }}                   AS email_normalised,
    lower(btrim(s.domain))                                     AS email_domain,
    t.typo_domain IS NOT NULL                                  AS has_email_domain_typo,
    coalesce(lower(btrim(s.domain)) = 'icloud.com', false)     AS is_icloud_address,
    btrim(s.subscriber_type)                                   AS subscriber_type,
    btrim(s.status)                                            AS status,
    btrim(s.locale)                                            AS locale,
    lower(split_part(btrim(s.locale), '-', 1))                 AS language,
    upper(split_part(btrim(s.locale), '-', 2))                 AS locale_country_code,
    nullif(btrim(s.bounce_count), '')::integer                 AS bounce_count,
    {{ sfmc_timestamp_columns('s.date_joined', 'joined_at') }},
    {{ sfmc_timestamp_columns('s.date_unsubscribed', 'unsubscribed_at') }},
    {{ sfmc_timestamp_columns('s.date_undeliverable', 'undeliverable_at') }}
FROM {{ source('sfmc', 'subscribers') }} AS s
LEFT JOIN {{ ref('person_identities') }} AS p
       ON p.identity_type = 'sfmc_subscriber' AND p.identity_id = btrim(s.subscriber_id)
LEFT JOIN {{ ref('email_domain_typos') }} AS t
       ON t.typo_domain = lower(btrim(s.domain))
