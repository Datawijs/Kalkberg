{#-
    MC-07: one send is identified by job, subscriber and send time, and a journey email can be sent to
    the same person many times. An open, click, bounce or unsubscribe belongs to the send of the same
    job and subscriber that came just before it.

    Sends and events are put on one time line per job and subscriber. Counting the sends along that line
    gives every event the number of the last send before it, and with it that send's key and time.
    An event at exactly the same moment as a send comes after it (is_event sorts sends first).

    events_cte must be a CTE with the columns event_id, job_id, subscriber_id and event_at_utc.
    Returns a subquery with event_id, send_key and sent_at_utc.
-#}
{% macro sfmc_link_to_send(events_cte) -%}
    (
        WITH timeline AS (
            SELECT s.job_id, s.subscriber_id, s.sent_at_utc AS at_utc, 0 AS is_event,
                   NULL::bigint AS event_id, s.send_key, s.sent_at_utc
            FROM {{ ref('sfmc_sends') }} AS s
            WHERE EXISTS (SELECT 1 FROM {{ events_cte }} AS e
                          WHERE e.job_id = s.job_id AND e.subscriber_id = s.subscriber_id)
            UNION ALL
            SELECT job_id, subscriber_id, event_at_utc, 1, event_id, NULL, NULL
            FROM {{ events_cte }}
        ),
        numbered AS (
            SELECT *,
                   count(send_key) OVER (PARTITION BY job_id, subscriber_id ORDER BY at_utc, is_event
                                         ROWS UNBOUNDED PRECEDING) AS send_number
            FROM timeline
        ),
        linked AS (
            SELECT *,
                   max(send_key)    OVER (PARTITION BY job_id, subscriber_id, send_number) AS linked_send_key,
                   max(sent_at_utc) OVER (PARTITION BY job_id, subscriber_id, send_number) AS linked_sent_at_utc
            FROM numbered
        )
        SELECT event_id, linked_send_key AS send_key, linked_sent_at_utc AS sent_at_utc
        FROM linked
        WHERE is_event = 1
    )
{%- endmacro %}
