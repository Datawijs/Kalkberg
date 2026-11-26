-- Product categories. Clean in bronze; carried to silver unchanged so gold only reads from silver.
SELECT
    category_id,
    btrim(category_name)   AS category_name,
    btrim(parent_category) AS parent_category
FROM {{ source('shop', 'categories') }}
