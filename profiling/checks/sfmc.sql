-- =====================================================================
-- Kalkberg profiling - round 2: targeted checks on sfmc (Marketing Cloud data views)
-- Created by 02-run-targeted-checks.sql. Every check is a view in the profiling schema.
-- =====================================================================

-- Marketing Cloud writes timestamps as 'M/D/YYYY h:mm:ss AM'. This helper reads them
-- as they are written, without assuming a time zone (finding the time zone is one of the checks).
-- to_timestamp interprets its input in the session time zone; fixing that to UTC inside the
-- function and converting back with AT TIME ZONE 'UTC' returns exactly the written clock time.
CREATE OR REPLACE FUNCTION profiling.sfmc_timestamp(p_value text)
RETURNS timestamp
LANGUAGE sql IMMUTABLE STRICT
SET timezone = 'UTC'
AS $$
    SELECT to_timestamp(p_value, 'MM/DD/YYYY HH12:MI:SS AM') AT TIME ZONE 'UTC'
$$;
COMMENT ON FUNCTION profiling.sfmc_timestamp(text) IS 'Reads a Marketing Cloud timestamp (M/D/YYYY h:mm:ss AM) as written, without time zone';

-- ---------------------------------------------------------------------
-- Timestamps
-- ---------------------------------------------------------------------
CREATE VIEW profiling.sfmc_01_timestamp_notation AS
WITH v AS (
    SELECT 'sent.event_date' AS column_name, event_date AS value FROM sfmc.sent
    UNION ALL SELECT 'opens.event_date',           event_date         FROM sfmc.opens
    UNION ALL SELECT 'clicks.event_date',          event_date         FROM sfmc.clicks
    UNION ALL SELECT 'bounces.event_date',         event_date         FROM sfmc.bounces
    UNION ALL SELECT 'unsubscribes.event_date',    event_date         FROM sfmc.unsubscribes
    UNION ALL SELECT 'subscribers.date_joined',    date_joined        FROM sfmc.subscribers
    UNION ALL SELECT 'subscribers.date_unsubscribed', date_unsubscribed FROM sfmc.subscribers
    UNION ALL SELECT 'subscribers.date_undeliverable', date_undeliverable FROM sfmc.subscribers
    UNION ALL SELECT 'jobs.sched_time',            sched_time         FROM sfmc.jobs
    UNION ALL SELECT 'jobs.pickup_time',           pickup_time        FROM sfmc.jobs
    UNION ALL SELECT 'jobs.delivered_time',        delivered_time     FROM sfmc.jobs
), c AS (
    SELECT column_name, value,
           value ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4} [0-9]{1,2}:[0-9]{2}:[0-9]{2} (AM|PM)$' AS us_notation
    FROM v
    WHERE value IS NOT NULL
)
SELECT column_name,
       count(*)                                                                         AS filled,
       count(*) FILTER (WHERE us_notation)                                              AS m_d_yyyy_h_mm_ss_ampm,
       count(*) FILTER (WHERE us_notation AND split_part(value, '/', 1)::int > 12)      AS first_number_above_12,
       count(*) FILTER (WHERE us_notation AND split_part(value, '/', 2)::int > 12)      AS second_number_above_12,
       min(profiling.sfmc_timestamp(value)) FILTER (WHERE us_notation)                  AS earliest,
       max(profiling.sfmc_timestamp(value)) FILTER (WHERE us_notation)                  AS latest
FROM c
GROUP BY column_name
ORDER BY column_name;
COMMENT ON VIEW profiling.sfmc_01_timestamp_notation IS 'Which timestamp notation does Marketing Cloud use, and which period do the tables cover?';

CREATE VIEW profiling.sfmc_02_hour_of_day AS
WITH t AS (
    SELECT 'jobs.delivered_time (newsletters)' AS column_name, profiling.sfmc_timestamp(j.delivered_time) AS ts
    FROM sfmc.jobs AS j WHERE j.category = 'Newsletter'
    UNION ALL
    SELECT 'opens.event_date', profiling.sfmc_timestamp(event_date) FROM sfmc.opens
    UNION ALL
    SELECT 'clicks.event_date', profiling.sfmc_timestamp(event_date) FROM sfmc.clicks
)
SELECT column_name, extract(hour FROM ts)::int AS hour_as_written, count(*) AS row_count,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY column_name), 2) AS share_pct
FROM t
GROUP BY 1, 2
ORDER BY 1, 2;
COMMENT ON VIEW profiling.sfmc_02_hour_of_day IS 'At what hour (as written) are newsletters delivered, opened and clicked?';

CREATE VIEW profiling.sfmc_03_click_vs_ga4_session AS
WITH c AS (
    SELECT subscriber_key, profiling.sfmc_timestamp(event_date) AS click_time
    FROM sfmc.clicks
    WHERE subscriber_key ~ '^[0-9]+$'
), s AS (
    SELECT user_id, to_timestamp(event_timestamp::bigint / 1000000.0) AT TIME ZONE 'UTC' AS session_utc
    FROM ga4.events
    WHERE event_name = 'session_start' AND user_id IS NOT NULL AND lower(medium) = 'email'
)
SELECT date_trunc('month', c.click_time)::date                                  AS click_month,
       round(extract(epoch FROM s.session_utc - c.click_time) / 3600.0)::int    AS hours_ga4_utc_minus_sfmc,
       count(*)                                                                 AS pairs
FROM c
JOIN s ON s.user_id = c.subscriber_key
      AND s.session_utc BETWEEN c.click_time - interval '12 hours' AND c.click_time + interval '12 hours'
GROUP BY 1, 2
ORDER BY 1, 2;
COMMENT ON VIEW profiling.sfmc_03_click_vs_ga4_session IS 'Hours between an email click (as written by SFMC) and email sessions of the same customer in GA4 (UTC)';

-- ---------------------------------------------------------------------
-- Subscribers
-- ---------------------------------------------------------------------
CREATE VIEW profiling.sfmc_04_subscriber_keys AS
WITH s AS (
    SELECT subscriber_key, lower(btrim(email_address)) AS email, subscriber_key ~ '^[0-9]+$' AS numeric_key
    FROM sfmc.subscribers
), c AS (
    SELECT customer_id::text AS customer_key, lower(btrim(email)) AS email FROM shop.customers
)
SELECT count(*)                                                                    AS subscribers,
       count(DISTINCT subscriber_key)                                              AS distinct_subscriber_keys,
       count(DISTINCT email)                                                       AS distinct_normalised_emails,
       count(*) FILTER (WHERE numeric_key)                                         AS numeric_keys,
       count(*) FILTER (WHERE subscriber_key LIKE '%@%')                           AS email_keys,
       count(*) FILTER (WHERE NOT numeric_key AND subscriber_key NOT LIKE '%@%')   AS other_keys,
       count(*) FILTER (WHERE numeric_key AND subscriber_key IN (SELECT customer_key FROM c)) AS numeric_keys_matching_a_customer_id,
       count(*) FILTER (WHERE email IN (SELECT email FROM c))                      AS emails_matching_a_customer,
       count(*) FILTER (WHERE subscriber_key LIKE '%@%' AND lower(btrim(subscriber_key)) <> email) AS email_key_differs_from_email_address
FROM s;
COMMENT ON VIEW profiling.sfmc_04_subscriber_keys IS 'What is the subscriber key, and how does it link to shop customers?';

CREATE VIEW profiling.sfmc_05_duplicate_subscribers AS
WITH s AS (
    SELECT subscriber_key, lower(btrim(email_address)) AS email, subscriber_key ~ '^[0-9]+$' AS numeric_key, status
    FROM sfmc.subscribers
), g AS (
    SELECT email,
           count(*)                              AS subscribers,
           count(*) FILTER (WHERE numeric_key)   AS with_numeric_key,
           count(DISTINCT subscriber_key)        AS distinct_keys,
           string_agg(DISTINCT status, ' + ')    AS statuses
    FROM s
    GROUP BY email
    HAVING count(*) > 1
)
SELECT subscribers AS subscribers_per_email, with_numeric_key, distinct_keys, statuses, count(*) AS email_addresses
FROM g
GROUP BY 1, 2, 3, 4
ORDER BY email_addresses DESC;
COMMENT ON VIEW profiling.sfmc_05_duplicate_subscribers IS 'Which email addresses appear on more than one subscriber, and how do those records differ?';

CREATE VIEW profiling.sfmc_06_email_domains AS
WITH s AS (
    SELECT split_part(lower(btrim(email_address)), '@', 2) AS domain, count(*) AS subscribers
    FROM sfmc.subscribers GROUP BY 1
), c AS (
    SELECT split_part(lower(btrim(email)), '@', 2) AS domain, count(*) AS customers
    FROM shop.customers GROUP BY 1
), o AS (
    SELECT split_part(lower(btrim(guest_email)), '@', 2) AS domain, count(*) AS guest_orders
    FROM shop.orders WHERE guest_email IS NOT NULL GROUP BY 1
)
SELECT domain, s.subscribers, c.customers, o.guest_orders
FROM s
FULL JOIN c USING (domain)
FULL JOIN o USING (domain)
ORDER BY coalesce(s.subscribers, 0) + coalesce(c.customers, 0) DESC;
COMMENT ON VIEW profiling.sfmc_06_email_domains IS 'Email domains in Marketing Cloud and in the shop';

-- ---------------------------------------------------------------------
-- Sends, opens and clicks
-- ---------------------------------------------------------------------
CREATE VIEW profiling.sfmc_07_referential_integrity AS
SELECT 'sent: job_id not in jobs' AS rule, count(*) AS row_count
FROM sfmc.sent AS s WHERE NOT EXISTS (SELECT 1 FROM sfmc.jobs AS j WHERE j.job_id = s.job_id)
UNION ALL
SELECT 'sent: subscriber_id not in subscribers', count(*)
FROM sfmc.sent AS s WHERE NOT EXISTS (SELECT 1 FROM sfmc.subscribers AS u WHERE u.subscriber_id = s.subscriber_id)
UNION ALL
SELECT 'sent: more than one row per job and subscriber', count(*)
FROM (SELECT job_id, subscriber_id FROM sfmc.sent GROUP BY 1, 2 HAVING count(*) > 1) AS d
UNION ALL
SELECT 'opens: no matching send (job + subscriber)', count(*)
FROM sfmc.opens AS o WHERE NOT EXISTS (SELECT 1 FROM sfmc.sent AS s WHERE s.job_id = o.job_id AND s.subscriber_id = o.subscriber_id)
UNION ALL
SELECT 'clicks: no matching send (job + subscriber)', count(*)
FROM sfmc.clicks AS c WHERE NOT EXISTS (SELECT 1 FROM sfmc.sent AS s WHERE s.job_id = c.job_id AND s.subscriber_id = c.subscriber_id)
UNION ALL
SELECT 'clicks: no matching open (job + subscriber)', count(*)
FROM sfmc.clicks AS c WHERE NOT EXISTS (SELECT 1 FROM sfmc.opens AS o WHERE o.job_id = c.job_id AND o.subscriber_id = c.subscriber_id)
UNION ALL
SELECT 'events: subscriber_key differs from the subscriber''s key', count(*)
FROM sfmc.sent AS s JOIN sfmc.subscribers AS u ON u.subscriber_id = s.subscriber_id WHERE u.subscriber_key <> s.subscriber_key
UNION ALL
SELECT 'subscribers: status Unsubscribed without unsubscribe event', count(*)
FROM sfmc.subscribers AS u WHERE u.status = 'Unsubscribed' AND NOT EXISTS (SELECT 1 FROM sfmc.unsubscribes AS x WHERE x.subscriber_id = u.subscriber_id)
UNION ALL
SELECT 'unsubscribes: subscriber status is not Unsubscribed', count(*)
FROM sfmc.unsubscribes AS x JOIN sfmc.subscribers AS u ON u.subscriber_id = x.subscriber_id WHERE u.status <> 'Unsubscribed';
COMMENT ON VIEW profiling.sfmc_07_referential_integrity IS 'Do the Marketing Cloud tables link up?';

CREATE VIEW profiling.sfmc_08_open_delay AS
WITH s AS (
    SELECT job_id, subscriber_id, min(profiling.sfmc_timestamp(event_date)) AS sent_time
    FROM sfmc.sent
    GROUP BY job_id, subscriber_id
), o AS (
    SELECT o.domain, o.is_unique, profiling.sfmc_timestamp(o.event_date) AS open_time, s.sent_time
    FROM sfmc.opens AS o
    LEFT JOIN s ON s.job_id = o.job_id AND s.subscriber_id = o.subscriber_id
)
SELECT domain,
       CASE
           WHEN sent_time IS NULL                              THEN 'no send found'
           WHEN open_time < sent_time                          THEN 'before the send'
           WHEN open_time < sent_time + interval '10 seconds'  THEN '< 10 seconds'
           WHEN open_time < sent_time + interval '1 minute'    THEN '10 seconds - 1 minute'
           WHEN open_time < sent_time + interval '1 hour'      THEN '1 minute - 1 hour'
           WHEN open_time < sent_time + interval '1 day'       THEN '1 hour - 1 day'
           ELSE '1 day or more'
       END AS time_after_send,
       count(*)                                    AS opens,
       count(*) FILTER (WHERE is_unique = 'True')  AS unique_opens
FROM o
GROUP BY 1, 2
ORDER BY 1, 2;
COMMENT ON VIEW profiling.sfmc_08_open_delay IS 'How soon after the send do opens happen, per email domain?';

CREATE VIEW profiling.sfmc_09_rates_by_domain AS
WITH s AS (
    SELECT domain, count(*) AS sent FROM sfmc.sent GROUP BY domain
), o AS (
    SELECT domain, count(*) FILTER (WHERE is_unique = 'True') AS unique_opens FROM sfmc.opens GROUP BY domain
), c AS (
    SELECT domain, count(*) FILTER (WHERE is_unique = 'True') AS unique_clicks FROM sfmc.clicks GROUP BY domain
), b AS (
    SELECT domain, count(*) AS bounces FROM sfmc.bounces GROUP BY domain
)
SELECT domain, s.sent, b.bounces, o.unique_opens, c.unique_clicks,
       round(100.0 * o.unique_opens  / s.sent, 1) AS open_rate_pct,
       round(100.0 * c.unique_clicks / s.sent, 2) AS click_rate_pct,
       round(100.0 * b.bounces       / s.sent, 2) AS bounce_rate_pct
FROM s
LEFT JOIN o USING (domain)
LEFT JOIN c USING (domain)
LEFT JOIN b USING (domain)
ORDER BY s.sent DESC;
COMMENT ON VIEW profiling.sfmc_09_rates_by_domain IS 'Open, click and bounce rates per email domain';

CREATE VIEW profiling.sfmc_10_click_url_tags AS
SELECT substring(url FROM 'utm_source=([^&#]*)')   AS utm_source,
       substring(url FROM 'utm_medium=([^&#]*)')   AS utm_medium,
       substring(url FROM 'utm_campaign=([^&#]*)') AS utm_campaign,
       count(*)                                    AS clicks,
       count(DISTINCT job_id)                      AS jobs,
       min(url)                                    AS example_url
FROM sfmc.clicks
GROUP BY 1, 2, 3
ORDER BY clicks DESC;
COMMENT ON VIEW profiling.sfmc_10_click_url_tags IS 'Which UTM tags do the links in the emails carry?';
