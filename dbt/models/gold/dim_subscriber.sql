{#-
    Marketing Cloud subscriber records (E1, E7). One row per record; person_key counts people (MC-03).
    The dates make the list size on any day possible: joined before it, not unsubscribed or
    undeliverable before it.
-#}
SELECT
    s.subscriber_id,
    s.person_key,
    s.subscriber_key_type,
    s.status,
    s.language,
    s.locale_country_code,
    s.is_shop_customer,
    s.is_icloud_address,
    s.has_email_domain_typo,
    s.joined_at_local::date            AS joined_date,
    s.unsubscribed_at_local::date      AS unsubscribed_date,
    s.undeliverable_at_local::date     AS undeliverable_date
FROM {{ ref('sfmc_subscribers') }} AS s
JOIN {{ ref('persons') }} AS p USING (person_key)
WHERE NOT p.is_test
