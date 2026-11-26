{#-
    Product variants (one per size or colour).
    SH-14: a variant without purchase cost gets the median cost of the other variants of the same
           product, marked as estimated. Without any known cost in the product, the cost stays unknown.
-#}
WITH variants AS (
    SELECT
        variant_id,
        product_id,
        btrim(sku)        AS sku,
        btrim(size_label) AS size_label,
        list_price,
        unit_cost
    FROM {{ source('shop', 'product_variants') }}
),

product_median_cost AS (
    SELECT
        product_id,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY unit_cost) AS median_unit_cost
    FROM variants
    WHERE unit_cost IS NOT NULL
    GROUP BY product_id
)

SELECT
    v.variant_id,
    v.product_id,
    v.sku,
    v.size_label,
    v.list_price,
    v.unit_cost                                                     AS unit_cost_source,
    coalesce(v.unit_cost, round(m.median_unit_cost::numeric, 2))    AS unit_cost,
    v.unit_cost IS NULL AND m.median_unit_cost IS NOT NULL          AS is_unit_cost_estimated
FROM variants AS v
LEFT JOIN product_median_cost AS m USING (product_id)
