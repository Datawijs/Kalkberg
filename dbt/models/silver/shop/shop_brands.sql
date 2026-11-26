-- Brands. Clean in bronze; carried to silver unchanged so gold only reads from silver.
SELECT
    brand_id,
    btrim(brand_name) AS brand_name,
    is_own_brand
FROM {{ source('shop', 'brands') }}
