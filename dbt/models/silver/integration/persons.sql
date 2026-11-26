{#-
    People, one row per person_key (SH-06, SH-07, MC-03, X-02).
    A person can have several shop accounts, place guest orders and have several subscriber records.
    MC-03  is_reachable: at least one of the person's subscriber records is active
    SH-05  is_test: one of the person's accounts or guest orders is test data
    X-02   has_opt_in_mismatch: subscribed in Marketing Cloud, but no account with marketing opt-in
-#}
WITH accounts AS (
    SELECT
        person_key,
        count(*)                          AS shop_accounts,
        min(customer_id)                  AS first_customer_id,
        min(created_at_utc)               AS first_account_created_at_utc,
        bool_or(is_test)                  AS has_test_account,
        bool_or(marketing_opt_in)         AS has_marketing_opt_in
    FROM {{ ref('shop_customers') }}
    GROUP BY person_key
),

guest_orders AS (
    SELECT person_key, count(*) AS guest_orders, bool_or(is_test) AS has_test_order
    FROM {{ ref('shop_orders') }}
    WHERE is_guest_order
    GROUP BY person_key
),

subscriptions AS (
    SELECT
        person_key,
        count(*)                             AS subscriber_records,
        bool_or(status = 'Active')           AS is_reachable,
        bool_or(has_email_domain_typo)       AS has_email_domain_typo,
        min(joined_at_utc)                   AS first_subscribed_at_utc
    FROM {{ ref('sfmc_subscribers') }}
    GROUP BY person_key
),

people AS (
    SELECT DISTINCT person_key FROM {{ ref('person_identities') }}
)

SELECT
    p.person_key,
    a.first_customer_id,
    coalesce(a.shop_accounts, 0)                     AS shop_accounts,
    coalesce(g.guest_orders, 0)                      AS guest_orders,
    coalesce(s.subscriber_records, 0)                AS subscriber_records,
    a.person_key IS NOT NULL                         AS has_shop_account,
    s.person_key IS NOT NULL                         AS is_subscriber,
    coalesce(s.is_reachable, false)                  AS is_reachable,
    coalesce(s.has_email_domain_typo, false)         AS has_email_domain_typo,
    coalesce(a.has_marketing_opt_in, false)          AS has_marketing_opt_in,
    s.person_key IS NOT NULL AND a.person_key IS NOT NULL
        AND NOT coalesce(a.has_marketing_opt_in, false) AS has_opt_in_mismatch,
    a.first_account_created_at_utc,
    s.first_subscribed_at_utc,
    coalesce(a.has_test_account, false) OR coalesce(g.has_test_order, false) AS is_test
FROM people AS p
LEFT JOIN accounts AS a USING (person_key)
LEFT JOIN guest_orders AS g USING (person_key)
LEFT JOIN subscriptions AS s USING (person_key)
