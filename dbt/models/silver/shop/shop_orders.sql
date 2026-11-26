{#-
    Orders, one row per order.
    SH-01  shipping country -> ISO code
    SH-02  created_at -> UTC and Belgian local time; order_date is the Belgian date
    SH-04  order_number stays the business key; platform shows the old or new platform. The format of
           the order number tells the platform, and with it the time zone of created_at (SH-02)
    SH-05  test orders flagged (is_test): placed by a test account, with payment method Manual,
           or by a guest with a test email address; gold leaves them out
    SH-07  guest orders get the person_key of the account with the same email address
    SH-11  discount codes trimmed and uppercased, with their type and, for influencer codes, the creator
    SH-12  order_total stays the revenue amount; total_rounding_difference shows the cents it differs
    GA-07  order_total_excl_shipping is the amount to compare with GA4's purchase value
-#}
WITH orders AS (
    SELECT
        o.*,
        o.order_number ~ '^KB[0-9]+$'               AS is_old_platform,
        {{ shop_timestamp_to_utc('o.created_at', "o.order_number ~ '^KB[0-9]+$'") }} AS created_at_utc_calc,
        {{ normalise_code('o.discount_code') }}     AS discount_code_normalised,
        {{ normalise_email('o.guest_email') }}      AS guest_email_normalised
    FROM {{ source('shop', 'orders') }} AS o
),

orders_with_local_time AS (
    SELECT
        *,
        {{ utc_to_local('created_at_utc_calc') }} AS created_at_local_calc
    FROM orders
)

SELECT
    o.order_id,
    o.order_number,
    CASE WHEN o.is_old_platform THEN 'old' ELSE 'new' END AS platform,
    o.customer_id,
    o.guest_email_normalised,
    o.customer_id IS NULL                                  AS is_guest_order,
    coalesce(pa.person_key, pg.person_key)                 AS person_key,
    o.created_at_utc_calc                                  AS created_at_utc,
    o.created_at_local_calc                                AS created_at_local,
    o.created_at_local_calc::date                          AS order_date,
    o.status,
    o.currency,
    o.subtotal,
    o.discount_total,
    o.shipping_fee,
    o.order_total,
    o.order_total - o.shipping_fee                         AS order_total_excl_shipping,
    o.order_total - (o.subtotal - o.discount_total + o.shipping_fee) AS total_rounding_difference,
    o.discount_code_normalised                             AS discount_code,
    CASE
        WHEN o.discount_code_normalised IS NULL THEN NULL
        WHEN ic.discount_code IS NOT NULL THEN 'influencer'
        ELSE coalesce(dc.code_type, 'other')
    END                                                    AS discount_code_type,
    ic.creator                                             AS influencer_creator,
    btrim(o.payment_method)                                AS payment_method,
    mc.country_code                                        AS shipping_country_code,
    {{ clean_text('o.shipping_postal_code') }}             AS shipping_postal_code,
    {{ clean_text('o.shipping_city') }}                    AS shipping_city,
    coalesce(c.is_test, false)
        OR coalesce(btrim(o.payment_method) = 'Manual', false)
        OR {{ is_test_email('o.guest_email') }}            AS is_test
FROM orders_with_local_time AS o
LEFT JOIN {{ ref('shop_customers') }} AS c
       ON c.customer_id = o.customer_id
LEFT JOIN {{ ref('person_identities') }} AS pa
       ON pa.identity_type = 'shop_account' AND pa.identity_id = o.customer_id::text
LEFT JOIN {{ ref('person_identities') }} AS pg
       ON pg.identity_type = 'guest_email' AND pg.identity_id = o.guest_email_normalised AND o.customer_id IS NULL
LEFT JOIN {{ ref('discount_codes') }} AS dc
       ON dc.discount_code = o.discount_code_normalised
LEFT JOIN {{ ref('budget_influencer_contracts') }} AS ic
       ON ic.discount_code = o.discount_code_normalised
      AND o.created_at_local_calc::date BETWEEN ic.contract_start_date AND ic.code_valid_until
LEFT JOIN {{ ref('map_country') }} AS mc
       ON mc.notation = lower(btrim(o.shipping_country))
