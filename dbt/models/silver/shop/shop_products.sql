{#-
    Products.
    SH-13: names trimmed. Products that share a name stay separate (each has its own sales history);
           product_name_key and has_duplicate_name let reports combine them where that matters.
-#}
WITH products AS (
    SELECT
        product_id,
        btrim(product_name) AS product_name,
        lower(btrim(product_name)) AS product_name_key,
        brand_id,
        category_id,
        launched_at,
        discontinued_at,
        is_active
    FROM {{ source('shop', 'products') }}
)

SELECT
    *,
    count(*) OVER (PARTITION BY product_name_key) > 1 AS has_duplicate_name
FROM products
