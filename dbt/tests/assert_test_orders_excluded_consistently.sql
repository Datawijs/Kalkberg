-- SH-05: every order of a test person is a test order, and every test order belongs to a test person,
-- so that gold can leave them out on either level and get the same result.
SELECT o.order_number, o.is_test AS order_is_test, p.is_test AS person_is_test
FROM {{ ref('shop_orders') }} AS o
JOIN {{ ref('persons') }} AS p USING (person_key)
WHERE o.is_test <> p.is_test
