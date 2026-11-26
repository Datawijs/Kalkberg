-- Order lines. Clean in bronze (shop_15 and shop_20 found no problems); carried to silver unchanged.
SELECT
    order_line_id,
    order_id,
    variant_id,
    quantity,
    unit_price,
    discount_amount,
    line_total
FROM {{ source('shop', 'order_lines') }}
