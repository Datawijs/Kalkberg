-- =====================================================================
-- Kalkberg profiling - round 2: targeted checks on shop (webshop database)
-- Created by 02-run-targeted-checks.sql. Every check is a view in the profiling schema.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Countries
-- ---------------------------------------------------------------------
CREATE VIEW profiling.shop_01_country_notations AS
SELECT 'customers.country_code' AS column_name, country_code AS value, count(*) AS row_count
FROM shop.customers
GROUP BY country_code
UNION ALL
SELECT 'orders.shipping_country', shipping_country, count(*)
FROM shop.orders
GROUP BY shipping_country
ORDER BY column_name, row_count DESC;
COMMENT ON VIEW profiling.shop_01_country_notations IS 'Which notations are used for countries?';

-- ---------------------------------------------------------------------
-- Customers: identity and personal data
-- ---------------------------------------------------------------------
CREATE VIEW profiling.shop_02_customer_email_duplicates AS
WITH c AS (
    SELECT email, lower(btrim(email)) AS email_normalised
    FROM shop.customers
)
SELECT count(*)                                           AS customer_accounts,
       count(*) FILTER (WHERE email <> email_normalised)  AS emails_with_uppercase_or_spaces,
       count(DISTINCT email_normalised)                   AS distinct_normalised_emails,
       count(*) - count(DISTINCT email_normalised)        AS accounts_sharing_an_email
FROM c;
COMMENT ON VIEW profiling.shop_02_customer_email_duplicates IS 'Do several accounts share the same email address once case and spaces are ignored?';

CREATE VIEW profiling.shop_03_possible_duplicate_people AS
WITH p AS (
    SELECT lower(btrim(first_name)) AS first_name, lower(btrim(last_name)) AS last_name, birth_date, btrim(postal_code) AS postal_code
    FROM shop.customers
    WHERE birth_date IS NOT NULL AND birth_date <> DATE '1900-01-01'
), g AS (
    SELECT count(*) AS accounts
    FROM p
    GROUP BY first_name, last_name, birth_date, postal_code
    HAVING count(*) > 1
)
SELECT accounts AS accounts_per_person, count(*) AS people, sum(accounts) AS accounts
FROM g
GROUP BY accounts
ORDER BY accounts;
COMMENT ON VIEW profiling.shop_03_possible_duplicate_people IS 'How many people seem to have more than one account (same name, birth date and postal code)?';

CREATE VIEW profiling.shop_04_duplicate_people_examples AS
WITH p AS (
    SELECT c.*,
           count(*) OVER (PARTITION BY lower(btrim(first_name)), lower(btrim(last_name)), birth_date, btrim(postal_code)) AS accounts,
           dense_rank() OVER (ORDER BY lower(btrim(last_name)), lower(btrim(first_name)), birth_date, btrim(postal_code)) AS person
    FROM shop.customers AS c
    WHERE birth_date IS NOT NULL AND birth_date <> DATE '1900-01-01'
)
SELECT customer_id, first_name, last_name, email, birth_date, postal_code, city, country_code, created_at,
       (SELECT count(*) FROM shop.orders AS o WHERE o.customer_id = p.customer_id) AS orders
FROM p
WHERE accounts > 1
  AND person IN (SELECT DISTINCT person FROM p WHERE accounts > 1 ORDER BY person LIMIT 15)
ORDER BY person, created_at;
COMMENT ON VIEW profiling.shop_04_duplicate_people_examples IS 'Examples of people with more than one account';

CREATE VIEW profiling.shop_05_test_record_indicators AS
SELECT 'customers: first or last name contains "test"' AS indicator, count(*) AS row_count
FROM shop.customers WHERE first_name ILIKE '%test%' OR last_name ILIKE '%test%'
UNION ALL
SELECT 'customers: email contains "test"', count(*)
FROM shop.customers WHERE email ILIKE '%test%'
UNION ALL
SELECT 'customers: email on a kalkberg domain', count(*)
FROM shop.customers WHERE email ILIKE '%@kalkberg%'
UNION ALL
SELECT 'customers: last name is "Account"', count(*)
FROM shop.customers WHERE btrim(last_name) ILIKE 'account'
UNION ALL
SELECT 'orders: discount code TEST100 (any notation)', count(*)
FROM shop.orders WHERE upper(btrim(discount_code)) = 'TEST100'
UNION ALL
SELECT 'orders: payment method Manual', count(*)
FROM shop.orders WHERE payment_method = 'Manual'
UNION ALL
SELECT 'orders: order total 0.00', count(*)
FROM shop.orders WHERE order_total = 0;
COMMENT ON VIEW profiling.shop_05_test_record_indicators IS 'How many records look like test data?';

CREATE VIEW profiling.shop_06_test_customer_examples AS
SELECT c.customer_id, c.first_name, c.last_name, c.email, c.created_at,
       count(o.order_id) AS orders, sum(o.order_total) AS order_total_sum,
       string_agg(DISTINCT o.payment_method, ', ') AS payment_methods,
       string_agg(DISTINCT o.discount_code, ', ') AS discount_codes
FROM shop.customers AS c
LEFT JOIN shop.orders AS o ON o.customer_id = c.customer_id
WHERE c.first_name ILIKE '%test%' OR c.last_name ILIKE '%test%' OR c.email ILIKE '%test%'
   OR c.email ILIKE '%@kalkberg%' OR btrim(c.last_name) ILIKE 'account'
GROUP BY c.customer_id
ORDER BY c.customer_id;
COMMENT ON VIEW profiling.shop_06_test_customer_examples IS 'Customers that look like test accounts, with their orders';

CREATE VIEW profiling.shop_07_test_order_overlap AS
WITH test_customers AS (
    SELECT customer_id
    FROM shop.customers
    WHERE first_name ILIKE '%test%' OR last_name ILIKE '%test%' OR email ILIKE '%test%'
       OR email ILIKE '%@kalkberg%' OR btrim(last_name) ILIKE 'account'
)
SELECT coalesce(upper(btrim(o.discount_code)) = 'TEST100', false) AS code_test100,
       o.payment_method = 'Manual'                                AS payment_manual,
       o.order_total = 0                                          AS total_zero,
       t.customer_id IS NOT NULL                                  AS test_like_customer,
       o.status,
       count(*)                                                   AS orders
FROM shop.orders AS o
LEFT JOIN test_customers AS t ON t.customer_id = o.customer_id
WHERE upper(btrim(o.discount_code)) = 'TEST100' OR o.payment_method = 'Manual' OR o.order_total = 0
   OR t.customer_id IS NOT NULL
GROUP BY 1, 2, 3, 4, 5
ORDER BY orders DESC;
COMMENT ON VIEW profiling.shop_07_test_order_overlap IS 'Do the test indicators on orders point to the same orders?';

CREATE VIEW profiling.shop_08_name_notation AS
SELECT 'first_name' AS column_name,
       count(*) AS row_count,
       count(*) FILTER (WHERE first_name <> btrim(first_name))                                 AS leading_or_trailing_spaces,
       count(*) FILTER (WHERE first_name = lower(first_name) AND first_name <> upper(first_name)) AS all_lowercase,
       count(*) FILTER (WHERE first_name = upper(first_name) AND first_name <> lower(first_name)) AS all_uppercase
FROM shop.customers
UNION ALL
SELECT 'last_name',
       count(*),
       count(*) FILTER (WHERE last_name <> btrim(last_name)),
       count(*) FILTER (WHERE last_name = lower(last_name) AND last_name <> upper(last_name)),
       count(*) FILTER (WHERE last_name = upper(last_name) AND last_name <> lower(last_name))
FROM shop.customers;
COMMENT ON VIEW profiling.shop_08_name_notation IS 'How consistently are names written?';

CREATE VIEW profiling.shop_09_phone_formats AS
SELECT regexp_replace(phone, '[0-9]', '9', 'g') AS phone_pattern, count(*) AS row_count, min(phone) AS example
FROM shop.customers
GROUP BY 1
ORDER BY row_count DESC;
COMMENT ON VIEW profiling.shop_09_phone_formats IS 'Which phone number notations are used (every digit shown as 9)?';

CREATE VIEW profiling.shop_10_birth_dates AS
SELECT CASE
           WHEN birth_date IS NULL                                        THEN 'missing'
           WHEN birth_date = DATE '1900-01-01'                            THEN '1900-01-01'
           WHEN birth_date > created_at::date                             THEN 'after account creation'
           WHEN age(created_at::date, birth_date) < interval '14 years'   THEN 'younger than 14 at sign-up'
           WHEN age(created_at::date, birth_date) > interval '100 years'  THEN 'older than 100 at sign-up'
           ELSE 'plausible'
       END AS bucket,
       count(*) AS customers,
       min(birth_date) AS min_birth_date,
       max(birth_date) AS max_birth_date
FROM shop.customers
GROUP BY 1
ORDER BY customers DESC;
COMMENT ON VIEW profiling.shop_10_birth_dates IS 'How plausible are the birth dates?';

-- ---------------------------------------------------------------------
-- Orders: numbering and timestamps
-- ---------------------------------------------------------------------
CREATE VIEW profiling.shop_11_order_number_formats AS
SELECT regexp_replace(order_number, '[0-9]', '9', 'g') AS order_number_pattern,
       count(*) AS orders,
       min(order_number) AS min_order_number, max(order_number) AS max_order_number,
       min(order_id) AS min_order_id, max(order_id) AS max_order_id,
       min(created_at) AS first_created_at, max(created_at) AS last_created_at
FROM shop.orders
GROUP BY 1
ORDER BY first_created_at;
COMMENT ON VIEW profiling.shop_11_order_number_formats IS 'Which order number formats exist, and when were they used?';

CREATE VIEW profiling.shop_12_order_time_vs_ga4 AS
WITH purchase AS (
    SELECT DISTINCT ON (transaction_id)
           transaction_id,
           to_timestamp(event_timestamp::bigint / 1000000.0) AT TIME ZONE 'UTC' AS purchase_utc
    FROM ga4.events
    WHERE event_name = 'purchase'
    ORDER BY transaction_id, event_timestamp::bigint
)
SELECT date_trunc('month', o.created_at)::date                                AS order_month,
       round(extract(epoch FROM o.created_at - p.purchase_utc) / 3600.0)::int AS hours_shop_minus_ga4_utc,
       count(*)                                                                AS orders
FROM shop.orders AS o
JOIN purchase AS p ON p.transaction_id = o.order_number
GROUP BY 1, 2
ORDER BY 1, 2;
COMMENT ON VIEW profiling.shop_12_order_time_vs_ga4 IS 'Difference in hours between the order timestamp in the shop and the GA4 purchase timestamp (UTC), per month';

CREATE VIEW profiling.shop_13_hour_of_day_by_period AS
WITH t AS (
    SELECT 'orders.created_at' AS column_name, created_at AS ts FROM shop.orders
    UNION ALL
    SELECT 'customers.created_at', created_at FROM shop.customers
    UNION ALL
    SELECT 'returns.requested_at', requested_at FROM shop.returns
), p AS (
    SELECT column_name,
           CASE WHEN ts < TIMESTAMP '2024-09-02' THEN 'before 2024-09-02' ELSE 'from 2024-09-02' END AS period,
           extract(hour FROM ts)::int AS hour_of_day
    FROM t
)
SELECT column_name, period, hour_of_day, count(*) AS row_count,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY column_name, period), 2) AS share_pct
FROM p
GROUP BY column_name, period, hour_of_day
ORDER BY column_name, period, hour_of_day;
COMMENT ON VIEW profiling.shop_13_hour_of_day_by_period IS 'Hour-of-day profile of shop timestamps before and after the platform migration';

CREATE VIEW profiling.shop_14_orders_before_signup AS
SELECT CASE WHEN o.created_at < TIMESTAMP '2024-09-02' THEN 'before 2024-09-02' ELSE 'from 2024-09-02' END AS period,
       count(*)                                              AS orders_with_account,
       count(*) FILTER (WHERE o.created_at < c.created_at)   AS orders_before_account_creation,
       max(c.created_at - o.created_at) FILTER (WHERE o.created_at < c.created_at) AS largest_gap
FROM shop.orders AS o
JOIN shop.customers AS c ON c.customer_id = o.customer_id
GROUP BY 1
ORDER BY 1;
COMMENT ON VIEW profiling.shop_14_orders_before_signup IS 'Are there orders that were placed before the customer account was created?';

-- ---------------------------------------------------------------------
-- Orders: amounts, guests, discount codes, statuses
-- ---------------------------------------------------------------------
CREATE VIEW profiling.shop_15_order_amounts AS
WITH l AS (
    SELECT order_id,
           sum(quantity * unit_price) AS gross,
           sum(discount_amount)       AS discount,
           sum(line_total)            AS net,
           count(*) FILTER (WHERE line_total <> quantity * unit_price - discount_amount) AS lines_not_adding_up
    FROM shop.order_lines
    GROUP BY order_id
)
SELECT count(*)                                                                      AS orders,
       count(*) FILTER (WHERE l.order_id IS NULL)                                    AS orders_without_lines,
       count(*) FILTER (WHERE o.subtotal <> l.gross)                                 AS subtotal_not_sum_of_quantity_x_price,
       count(*) FILTER (WHERE o.subtotal <> l.net)                                   AS subtotal_not_sum_of_line_totals,
       count(*) FILTER (WHERE o.discount_total <> l.discount)                        AS discount_not_sum_of_line_discounts,
       count(*) FILTER (WHERE o.order_total <> o.subtotal - o.discount_total + o.shipping_fee) AS total_not_subtotal_minus_discount_plus_shipping,
       count(*) FILTER (WHERE o.order_total <> o.subtotal + o.shipping_fee)          AS total_not_subtotal_plus_shipping,
       sum(l.lines_not_adding_up)                                                    AS lines_where_total_is_not_qty_x_price_minus_discount
FROM shop.orders AS o
LEFT JOIN l ON l.order_id = o.order_id;
COMMENT ON VIEW profiling.shop_15_order_amounts IS 'Do the amounts on orders and order lines add up?';

CREATE VIEW profiling.shop_16_guest_orders AS
WITH accounts AS (
    SELECT DISTINCT lower(btrim(email)) AS email FROM shop.customers
), guest AS (
    SELECT lower(btrim(guest_email)) AS email FROM shop.orders WHERE customer_id IS NULL
), repeat_guests AS (
    SELECT email FROM guest GROUP BY email HAVING count(*) > 1
)
SELECT (SELECT count(*) FROM shop.orders WHERE customer_id IS NULL AND guest_email IS NULL)         AS orders_without_customer_or_email,
       (SELECT count(*) FROM shop.orders WHERE customer_id IS NOT NULL AND guest_email IS NOT NULL) AS orders_with_customer_and_guest_email,
       count(*)                                    AS guest_orders,
       count(DISTINCT g.email)                     AS distinct_guest_emails,
       (SELECT count(*) FROM repeat_guests)        AS guest_emails_with_more_than_one_order,
       count(*) FILTER (WHERE a.email IS NOT NULL) AS guest_orders_with_email_of_an_account,
       count(DISTINCT g.email) FILTER (WHERE a.email IS NOT NULL) AS guest_emails_that_have_an_account
FROM guest AS g
LEFT JOIN accounts AS a ON a.email = g.email;
COMMENT ON VIEW profiling.shop_16_guest_orders IS 'Who places orders without an account, and do they also have an account?';

CREATE VIEW profiling.shop_17_discount_codes AS
SELECT upper(btrim(o.discount_code))                       AS code_normalised,
       string_agg(DISTINCT '"' || o.discount_code || '"', ', ') AS notations,
       count(*)                                            AS orders,
       min(o.created_at)::date                             AS first_used,
       max(o.created_at)::date                             AS last_used,
       c.creator,
       c.start_date                                        AS contract_start,
       c.end_date                                          AS contract_end,
       count(*) FILTER (WHERE o.created_at::date < c.start_date::date)                     AS orders_before_contract_start,
       count(*) FILTER (WHERE o.created_at::date > c.end_date::date)                       AS orders_after_contract_end,
       count(*) FILTER (WHERE o.created_at::date > c.end_date::date + 14)                  AS orders_after_contract_end_plus_14_days
FROM shop.orders AS o
LEFT JOIN budget.influencer_contracts AS c ON upper(btrim(c.discount_code)) = upper(btrim(o.discount_code))
WHERE o.discount_code IS NOT NULL
GROUP BY 1, c.creator, c.start_date, c.end_date
ORDER BY orders DESC;
COMMENT ON VIEW profiling.shop_17_discount_codes IS 'Discount codes: notations, usage period and (for influencer codes) use outside the contract';

CREATE VIEW profiling.shop_18_order_status_vs_returns AS
WITH r AS (
    SELECT l.order_id, count(*) AS returns, sum(r.refund_amount) AS refunded
    FROM shop.returns AS r
    JOIN shop.order_lines AS l ON l.order_line_id = r.order_line_id
    GROUP BY l.order_id
)
SELECT o.status,
       r.order_id IS NOT NULL      AS has_returns,
       count(*)                    AS orders,
       sum(r.refunded)             AS refunded_via_returns
FROM shop.orders AS o
LEFT JOIN r ON r.order_id = o.order_id
GROUP BY 1, 2
ORDER BY 1, 2;
COMMENT ON VIEW profiling.shop_18_order_status_vs_returns IS 'Does the order status match the returns registered for the order?';

CREATE VIEW profiling.shop_19_open_order_age AS
SELECT status, date_trunc('month', created_at)::date AS order_month, count(*) AS orders
FROM shop.orders
WHERE status IN ('processing', 'shipped')
GROUP BY 1, 2
ORDER BY 1, 2;
COMMENT ON VIEW profiling.shop_19_open_order_age IS 'When were the orders that are still processing or shipped placed?';

CREATE VIEW profiling.shop_20_returns_consistency AS
WITH r AS (
    SELECT r.*, l.quantity AS line_quantity, l.line_total, o.created_at AS order_created_at, o.status AS order_status
    FROM shop.returns AS r
    JOIN shop.order_lines AS l ON l.order_line_id = r.order_line_id
    JOIN shop.orders AS o ON o.order_id = l.order_id
)
SELECT count(*)                                                              AS returns,
       count(*) FILTER (WHERE quantity > line_quantity)                      AS returned_more_than_ordered,
       count(*) FILTER (WHERE refund_amount > line_total)                    AS refund_more_than_line_total,
       count(*) FILTER (WHERE status = 'refunded' AND refund_amount = 0)     AS refunded_with_zero_amount,
       count(*) FILTER (WHERE status <> 'refunded' AND refund_amount > 0)    AS refund_amount_but_not_refunded,
       count(*) FILTER (WHERE received_at < requested_at)                    AS received_before_requested,
       count(*) FILTER (WHERE requested_at < order_created_at)               AS requested_before_order,
       count(*) FILTER (WHERE order_status = 'cancelled')                    AS returns_on_cancelled_orders
FROM r;
COMMENT ON VIEW profiling.shop_20_returns_consistency IS 'Are returns consistent with the order lines they belong to?';

-- ---------------------------------------------------------------------
-- Catalogue
-- ---------------------------------------------------------------------
CREATE VIEW profiling.shop_21_catalogue_consistency AS
WITH sales AS (
    SELECT l.variant_id, min(o.created_at)::date AS first_sold, max(o.created_at)::date AS last_sold
    FROM shop.order_lines AS l
    JOIN shop.orders AS o ON o.order_id = l.order_id
    GROUP BY l.variant_id
)
SELECT 'products: same name as another product (ignoring case and spaces)' AS rule, count(*) AS row_count
FROM shop.products AS p
WHERE (SELECT count(*) FROM shop.products AS q WHERE lower(btrim(q.product_name)) = lower(btrim(p.product_name))) > 1
UNION ALL
SELECT 'products: name with leading or trailing spaces', count(*)
FROM shop.products WHERE product_name <> btrim(product_name)
UNION ALL
SELECT 'products: discontinued_at filled but is_active = true', count(*)
FROM shop.products WHERE discontinued_at IS NOT NULL AND is_active
UNION ALL
SELECT 'products: discontinued_at empty but is_active = false', count(*)
FROM shop.products WHERE discontinued_at IS NULL AND NOT is_active
UNION ALL
SELECT 'variants: no unit_cost', count(*)
FROM shop.product_variants WHERE unit_cost IS NULL
UNION ALL
SELECT 'variants: never sold', count(*)
FROM shop.product_variants AS v WHERE NOT EXISTS (SELECT 1 FROM sales AS s WHERE s.variant_id = v.variant_id)
UNION ALL
SELECT 'variants: sold before the product was launched', count(*)
FROM sales AS s JOIN shop.product_variants AS v USING (variant_id) JOIN shop.products AS p USING (product_id)
WHERE s.first_sold < p.launched_at
UNION ALL
SELECT 'variants: sold after the product was discontinued', count(*)
FROM sales AS s JOIN shop.product_variants AS v USING (variant_id) JOIN shop.products AS p USING (product_id)
WHERE s.last_sold > p.discontinued_at
UNION ALL
SELECT 'variants: unit_cost higher than list_price', count(*)
FROM shop.product_variants WHERE unit_cost > list_price;
COMMENT ON VIEW profiling.shop_21_catalogue_consistency IS 'Is the product catalogue internally consistent?';

CREATE VIEW profiling.shop_22_catalogue_examples AS
SELECT 'same name as another product' AS finding, p.product_id, p.product_name, NULL::integer AS variant_id, NULL::text AS sku, cat.category_name
FROM shop.products AS p
JOIN shop.categories AS cat USING (category_id)
WHERE (SELECT count(*) FROM shop.products AS q WHERE lower(btrim(q.product_name)) = lower(btrim(p.product_name))) > 1
UNION ALL
SELECT 'variant without unit_cost', p.product_id, p.product_name, v.variant_id, v.sku, cat.category_name
FROM shop.product_variants AS v
JOIN shop.products AS p USING (product_id)
JOIN shop.categories AS cat USING (category_id)
WHERE v.unit_cost IS NULL
ORDER BY finding, product_name, variant_id;
COMMENT ON VIEW profiling.shop_22_catalogue_examples IS 'Products with a duplicate name and variants without a purchase cost';
