{#-
    Order lines, one row per line of a real order (test orders left out, SH-05).
    Amounts:
      gross_amount            quantity x unit price, incl. VAT
      discount_amount         line discount, incl. VAT (code or automatic promotion)
      net_amount              what the customer paid for the line, incl. VAT
      net_amount_excl_vat     idem, excl. VAT: the basis for margin
      refund_amount(_excl_vat) refunded through returns
      cost_amount             quantity x purchase cost (excl. VAT)
      cost_amount_after_returns  cost of the items the customer kept: refunded items go back in stock
      gross_margin            net_amount_excl_vat - refund_amount_excl_vat - cost_amount_after_returns
    Gift cards (F6) are not revenue until used: is_gift_card, and they have no margin.
    Costs are today's purchase costs; the source has no cost history (SH-14).
-#}
WITH orders AS (
    SELECT *
    FROM {{ ref('shop_orders') }}
    WHERE NOT is_test
),

returns AS (
    SELECT
        order_line_id,
        count(*)                                                       AS return_requests,
        coalesce(sum(quantity) FILTER (WHERE status = 'refunded'), 0)  AS returned_quantity,
        sum(refund_amount)                                             AS refund_amount,
        string_agg(DISTINCT reason, ', ' ORDER BY reason)              AS return_reasons
    FROM {{ ref('shop_returns') }}
    GROUP BY order_line_id
),

lines AS (
    SELECT
        l.*,
        o.order_number,
        o.order_date,
        o.person_key,
        o.status,
        o.shipping_country_code,
        p.product_id,
        p.vat_class,
        p.is_gift_card,
        p.current_unit_cost          AS unit_cost,
        p.is_unit_cost_estimated,
        vr.vat_rate,
        coalesce(r.return_requests, 0)    AS return_requests,
        coalesce(r.returned_quantity, 0)  AS returned_quantity,
        coalesce(r.refund_amount, 0)      AS refund_amount,
        r.return_reasons
    FROM {{ ref('shop_order_lines') }} AS l
    JOIN orders AS o USING (order_id)
    JOIN {{ ref('dim_product') }} AS p USING (variant_id)
    JOIN {{ ref('vat_rates') }} AS vr
      ON vr.country_code = o.shipping_country_code AND vr.vat_class = p.vat_class
    LEFT JOIN returns AS r USING (order_line_id)
)

SELECT
    order_line_id,
    order_id,
    order_number,
    order_date,
    person_key,
    variant_id,
    product_id,
    shipping_country_code,
    status = 'cancelled'                                        AS is_cancelled,
    is_gift_card,
    -- C5: the same product in more than one size or colour in one order
    count(*) OVER (PARTITION BY order_id, product_id) > 1       AS is_multi_variant_order,
    quantity,
    unit_price,
    quantity * unit_price                                       AS gross_amount,
    discount_amount,
    line_total                                                  AS net_amount,
    vat_class,
    vat_rate,
    {{ excl_vat('line_total', 'vat_rate') }}                    AS net_amount_excl_vat,
    return_requests,
    returned_quantity,
    return_reasons,
    refund_amount,
    {{ excl_vat('refund_amount', 'vat_rate') }}                 AS refund_amount_excl_vat,
    unit_cost,
    is_unit_cost_estimated,
    CASE WHEN NOT is_gift_card THEN quantity * unit_cost END    AS cost_amount,
    CASE WHEN NOT is_gift_card THEN (quantity - returned_quantity) * unit_cost END AS cost_amount_after_returns,
    CASE
        WHEN NOT is_gift_card AND unit_cost IS NOT NULL
        THEN {{ excl_vat('line_total', 'vat_rate') }} - {{ excl_vat('refund_amount', 'vat_rate') }}
             - (quantity - returned_quantity) * unit_cost
    END                                                         AS gross_margin
FROM lines
