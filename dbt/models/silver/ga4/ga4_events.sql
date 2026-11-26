{#-
    GA4 events, typed, one row per event.
    GA-05  a purchase sent twice (same transaction) is kept once: the first event
    GA-08  the export only covers sessions with shopping activity; see ga4_sessions
    The traffic source is only filled on session_start (ga4_01): use session_key to join ga4_sessions.
-#}
WITH events AS (
    SELECT
        e.*,
        {{ ga4_micros_to_utc('e.event_timestamp') }} AS event_at_utc_calc,
        CASE
            WHEN e.event_name = 'purchase' THEN
                row_number() OVER (PARTITION BY e.event_name, e.transaction_id ORDER BY e.event_timestamp::bigint)
        END AS purchase_sequence
    FROM {{ source('ga4', 'events') }} AS e
)

SELECT
    event_name,
    to_date(event_date, 'YYYYMMDD')                    AS event_date,
    event_at_utc_calc                                  AS event_at_utc,
    {{ utc_to_local('event_at_utc_calc') }}            AS event_at_local,
    user_pseudo_id || '.' || ga_session_id             AS session_key,
    user_pseudo_id,
    nullif(btrim(user_id), '')::integer                AS customer_id,
    ga_session_id::bigint                              AS ga_session_id,
    nullif(btrim(transaction_id), '')                  AS transaction_id,
    nullif(btrim(value), '')::numeric(10, 2)           AS purchase_value,
    nullif(btrim(currency), '')                        AS currency
FROM events
WHERE purchase_sequence IS NULL OR purchase_sequence = 1
