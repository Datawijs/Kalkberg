{#-
    People instead of records (SH-06, SH-07, MC-03, MC-04, X-02).

    One row per identity that can belong to a person: a shop account, an email address used for a
    guest order, or a Marketing Cloud subscriber record. Every identity gets a person_key.

    How people are matched:
      1. Shop accounts with the same normalised email address are one person (SH-06).
      2. Shop accounts with the same first name, last name, birth date and postal code are one person,
         when the birth date is a real one (SH-06, SH-10).
      Rules 1 and 2 are applied together: if A matches B on email and B matches C on name, A, B and C
      are one person (connected components).
      3. A guest order or a subscriber with the email address of an account belongs to that account's
         person (SH-07, MC-03, X-02). Otherwise, everything with the same email address is one person.
    The subscriber key is never used to match: it isn't reliably a customer number (MC-04).

    person_key is a hash, so it carries no personal data into gold.
-#}

WITH RECURSIVE accounts AS (
    SELECT
        customer_id,
        {{ normalise_email('email') }} AS email_normalised,
        CASE
            WHEN {{ clean_birth_date('birth_date', 'created_at') }} IS NOT NULL
             AND nullif(btrim(first_name), '') IS NOT NULL
             AND nullif(btrim(last_name), '') IS NOT NULL
             AND nullif(btrim(postal_code), '') IS NOT NULL
            THEN concat_ws('|', lower(btrim(first_name)), lower(btrim(last_name)), birth_date, btrim(postal_code))
        END AS person_match_key
    FROM {{ source('shop', 'customers') }}
),

-- Two accounts are linked when they share an email address or a person match key
edges AS (
    SELECT a.customer_id AS from_id, b.customer_id AS to_id
    FROM accounts AS a
    JOIN accounts AS b ON b.email_normalised = a.email_normalised AND b.customer_id <> a.customer_id
    UNION
    SELECT a.customer_id, b.customer_id
    FROM accounts AS a
    JOIN accounts AS b ON b.person_match_key = a.person_match_key AND b.customer_id <> a.customer_id
),

-- Every account that can be reached from an account, directly or through other accounts
reachable (customer_id, linked_id) AS (
    SELECT customer_id, customer_id FROM accounts
    UNION
    SELECT r.customer_id, e.to_id
    FROM reachable AS r
    JOIN edges AS e ON e.from_id = r.linked_id
),

-- The lowest customer_id of the group anchors the person
account_person AS (
    SELECT customer_id, min(linked_id) AS anchor_customer_id
    FROM reachable
    GROUP BY customer_id
),

-- Email addresses that belong to an account; all accounts with one address are in the same group
account_emails AS (
    SELECT DISTINCT a.email_normalised, p.anchor_customer_id
    FROM accounts AS a
    JOIN account_person AS p USING (customer_id)
),

guest_emails AS (
    SELECT DISTINCT {{ normalise_email('guest_email') }} AS email_normalised
    FROM {{ source('shop', 'orders') }}
    WHERE customer_id IS NULL
      AND {{ normalise_email('guest_email') }} IS NOT NULL
),

subscribers AS (
    SELECT btrim(subscriber_id) AS subscriber_id, {{ normalise_email('email_address') }} AS email_normalised
    FROM {{ source('sfmc', 'subscribers') }}
),

identities AS (
    SELECT 'shop_account' AS identity_type, a.customer_id::text AS identity_id, a.email_normalised,
           p.anchor_customer_id
    FROM accounts AS a
    JOIN account_person AS p USING (customer_id)

    UNION ALL

    SELECT 'guest_email', g.email_normalised, g.email_normalised, ae.anchor_customer_id
    FROM guest_emails AS g
    LEFT JOIN account_emails AS ae USING (email_normalised)

    UNION ALL

    SELECT 'sfmc_subscriber', s.subscriber_id, s.email_normalised, ae.anchor_customer_id
    FROM subscribers AS s
    LEFT JOIN account_emails AS ae USING (email_normalised)
)

SELECT
    identity_type,
    identity_id,
    email_normalised,
    md5(CASE
            WHEN anchor_customer_id IS NOT NULL THEN 'account:' || anchor_customer_id
            WHEN email_normalised IS NOT NULL THEN 'email:' || email_normalised
            ELSE identity_type || ':' || identity_id
        END) AS person_key,
    anchor_customer_id,
    CASE
        WHEN anchor_customer_id IS NOT NULL THEN 'shop account'
        WHEN email_normalised IS NOT NULL THEN 'email address'
        ELSE 'none'
    END AS matched_on
FROM identities
