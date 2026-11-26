{#-
    Returns, one row per return request of a real order (C5, F4).
    SH-03  only dates: the time of a return carries no information. Durations are in days.
    The refund date is not in the source. For refunded returns the refund follows the receipt of the
    parcel, so days_order_to_refund counts to received_date.
-#}
SELECT
    r.return_id,
    r.order_line_id,
    l.order_id,
    l.order_number,
    l.order_date,
    l.person_key,
    l.variant_id,
    l.product_id,
    l.shipping_country_code,
    l.is_multi_variant_order,
    r.requested_date,
    r.received_date,
    r.requested_date - l.order_date                                  AS days_order_to_request,
    CASE WHEN r.status = 'refunded' THEN r.received_date - l.order_date END AS days_order_to_refund,
    r.quantity,
    r.reason,
    r.status,
    r.refund_amount,
    {{ excl_vat('r.refund_amount', 'l.vat_rate') }}                  AS refund_amount_excl_vat
FROM {{ ref('shop_returns') }} AS r
JOIN {{ ref('fct_order_lines') }} AS l USING (order_line_id)
