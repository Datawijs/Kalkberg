-- SH-02, SH-04: the platform decides the time zone of a shop timestamp, so it must be right.
-- In UTC, every old-platform record must come before the migration (02/09/2024 00:00 Belgian time) and
-- every new-platform record after it.
WITH records AS (
    SELECT 'order ' || order_number AS record, platform, created_at_utc FROM {{ ref('shop_orders') }}
    UNION ALL
    SELECT 'account ' || customer_id, platform, created_at_utc FROM {{ ref('shop_customers') }}
)
SELECT *
FROM records
WHERE (platform = 'old') <> (created_at_utc < (TIMESTAMP '{{ var("shop_migration_date") }} 00:00' AT TIME ZONE '{{ var("local_time_zone") }}' AT TIME ZONE 'UTC'))
