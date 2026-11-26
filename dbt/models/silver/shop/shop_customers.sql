{#-
    Shop accounts, one row per account (customer_id). People are in person_identities / persons.
    SH-01  country notations -> ISO code
    SH-02  created_at -> UTC and Belgian local time. Accounts have no platform marker like the order
           number, but customer_id follows the order of creation. At the migration the clock jumps back
           (from Belgian time to UTC), so the first account whose created_at is earlier than that of the
           account before it is the first account of the new platform.
    SH-05  test accounts flagged (is_test); gold leaves them out
    SH-06  person_key: accounts of the same person share it
    SH-08  names trimmed (names don't go to gold)
    SH-09  phone numbers not carried over (not used in any analysis)
    SH-10  placeholder and impossible birth dates -> NULL, with the reason
    MC-05  email domains with a typo flagged
-#}
WITH clock_jumps AS (
    SELECT
        customer_id,
        created_at < lag(created_at) OVER (ORDER BY customer_id) AS is_clock_jump
    FROM {{ source('shop', 'customers') }}
    WHERE created_at BETWEEN DATE '{{ var("shop_migration_date") }}' - 1 AND DATE '{{ var("shop_migration_date") }}' + 1
),

first_new_platform_account AS (
    SELECT min(customer_id) AS customer_id
    FROM clock_jumps
    WHERE is_clock_jump
),

customers AS (
    SELECT
        c.*,
        c.customer_id < f.customer_id AS is_old_platform,
        {{ shop_timestamp_to_utc('c.created_at', 'c.customer_id < f.customer_id') }} AS created_at_utc_calc
    FROM {{ source('shop', 'customers') }} AS c
    CROSS JOIN first_new_platform_account AS f
)

SELECT
    c.customer_id,
    p.person_key,
    {{ normalise_email('c.email') }}                         AS email_normalised,
    split_part({{ normalise_email('c.email') }}, '@', 2)     AS email_domain,
    t.typo_domain IS NOT NULL                                AS has_email_domain_typo,
    {{ clean_text('c.first_name') }}                         AS first_name,
    {{ clean_text('c.last_name') }}                          AS last_name,
    {{ clean_birth_date('c.birth_date', 'c.created_at') }}   AS birth_date,
    CASE
        WHEN c.birth_date IS NULL THEN 'missing'
        WHEN c.birth_date = DATE '1900-01-01' THEN 'placeholder 01/01/1900'
        WHEN c.birth_date > c.created_at::date THEN 'after account creation'
        WHEN age(c.created_at::date, c.birth_date) < interval '14 years' THEN 'younger than 14 at sign-up'
    END                                                      AS birth_date_issue,
    lower({{ clean_text('c.preferred_language') }})          AS preferred_language,
    {{ clean_text('c.postal_code') }}                        AS postal_code,
    {{ clean_text('c.city') }}                               AS city,
    m.country_code,
    c.marketing_opt_in,
    c.created_at_utc_calc                                    AS created_at_utc,
    {{ utc_to_local('c.created_at_utc_calc') }}              AS created_at_local,
    ({{ utc_to_local('c.created_at_utc_calc') }})::date      AS created_date,
    CASE WHEN c.is_old_platform THEN 'old' ELSE 'new' END AS platform,
    {{ is_test_email('c.email') }} OR {{ is_test_name('c.first_name', 'c.last_name') }} AS is_test
FROM customers AS c
LEFT JOIN {{ ref('person_identities') }} AS p
       ON p.identity_type = 'shop_account' AND p.identity_id = c.customer_id::text
LEFT JOIN {{ ref('map_country') }} AS m
       ON m.notation = lower(btrim(c.country_code))
LEFT JOIN {{ ref('email_domain_typos') }} AS t
       ON t.typo_domain = split_part({{ normalise_email('c.email') }}, '@', 2)
