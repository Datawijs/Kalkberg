-- =====================================================================
-- Kalkberg demo data - step 3: check that everything was loaded
-- Compare the counts with the row counts printed by the generator.
-- =====================================================================
SELECT 'shop.categories' AS table_name, count(*) AS row_count FROM shop.categories
UNION ALL SELECT 'shop.brands',            count(*) FROM shop.brands
UNION ALL SELECT 'shop.products',          count(*) FROM shop.products
UNION ALL SELECT 'shop.product_variants',  count(*) FROM shop.product_variants
UNION ALL SELECT 'shop.customers',         count(*) FROM shop.customers
UNION ALL SELECT 'shop.orders',            count(*) FROM shop.orders
UNION ALL SELECT 'shop.order_lines',       count(*) FROM shop.order_lines
UNION ALL SELECT 'shop.returns',           count(*) FROM shop.returns
UNION ALL SELECT 'ga4.events',             count(*) FROM ga4.events
UNION ALL SELECT 'ga4.daily_traffic',      count(*) FROM ga4.daily_traffic
UNION ALL SELECT 'sfmc.subscribers',       count(*) FROM sfmc.subscribers
UNION ALL SELECT 'sfmc.jobs',              count(*) FROM sfmc.jobs
UNION ALL SELECT 'sfmc.sent',              count(*) FROM sfmc.sent
UNION ALL SELECT 'sfmc.opens',             count(*) FROM sfmc.opens
UNION ALL SELECT 'sfmc.clicks',            count(*) FROM sfmc.clicks
UNION ALL SELECT 'sfmc.bounces',           count(*) FROM sfmc.bounces
UNION ALL SELECT 'sfmc.unsubscribes',      count(*) FROM sfmc.unsubscribes
UNION ALL SELECT 'ads.google_ads_campaign_report', count(*) FROM ads.google_ads_campaign_report
UNION ALL SELECT 'ads.meta_ads_report',    count(*) FROM ads.meta_ads_report
ORDER BY table_name;
