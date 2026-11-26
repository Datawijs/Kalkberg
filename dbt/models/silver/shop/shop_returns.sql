{#-
    Returns, one row per return request.
    SH-03: the time of day of a return carries no information, so only the dates are kept.
           Durations are counted in days.
-#}
SELECT
    return_id,
    order_line_id,
    requested_at::date AS requested_date,
    received_at::date  AS received_date,
    quantity,
    btrim(reason)      AS reason,
    status,
    refund_amount
FROM {{ source('shop', 'returns') }}
