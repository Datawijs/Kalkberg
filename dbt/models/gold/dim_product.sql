{#-
    Products at the level they are sold: one row per variant (size or colour), with its product,
    brand and category.
    SH-13  products with the same name stay separate; product_name_key combines them where needed
    SH-14  estimated purchase costs are marked
-#}
SELECT
    v.variant_id,
    v.sku,
    v.size_label,
    p.product_id,
    p.product_name,
    p.product_name_key,
    p.has_duplicate_name,
    b.brand_name,
    b.is_own_brand,
    c.category_name,
    c.parent_category,
    CASE
        WHEN c.category_name = 'Gift cards' THEN 'none'
        WHEN c.category_name = 'Books & guides' THEN 'reduced'
        ELSE 'standard'
    END                              AS vat_class,
    c.category_name = 'Gift cards'   AS is_gift_card,
    v.list_price                     AS current_list_price,
    v.unit_cost                      AS current_unit_cost,
    v.is_unit_cost_estimated,
    p.launched_at                    AS launched_date,
    p.discontinued_at                AS discontinued_date,
    p.is_active
FROM {{ ref('shop_product_variants') }} AS v
JOIN {{ ref('shop_products') }} AS p USING (product_id)
JOIN {{ ref('shop_brands') }} AS b USING (brand_id)
JOIN {{ ref('shop_categories') }} AS c USING (category_id)
