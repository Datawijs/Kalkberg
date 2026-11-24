-- =====================================================================
-- Kalkberg demo data - step 2: load the CSV files
-- Run from the project folder (the folder that contains 'data' and 'sql'):
--   psql -U postgres -d kalkberg -v ON_ERROR_STOP=1 -f sql/02_load_raw_data.sql
-- \copy reads the files on the client side, so paths are relative to the current folder.
-- Loading takes a few minutes (about 20 million rows in total).
-- =====================================================================

\timing on

TRUNCATE shop.returns, shop.order_lines, shop.orders, shop.customers,
         shop.product_variants, shop.products, shop.brands, shop.categories;

\echo 'Loading shop ...'
\copy shop.categories       FROM 'data/shop/categories.csv'       WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy shop.brands           FROM 'data/shop/brands.csv'           WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy shop.products         FROM 'data/shop/products.csv'         WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy shop.product_variants FROM 'data/shop/product_variants.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy shop.customers        FROM 'data/shop/customers.csv'        WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy shop.orders           FROM 'data/shop/orders.csv'           WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy shop.order_lines      FROM 'data/shop/order_lines.csv'      WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy shop.returns          FROM 'data/shop/returns.csv'          WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\echo 'Loading ga4 ...'
TRUNCATE ga4.events, ga4.daily_traffic;
\copy ga4.events        FROM 'data/ga4/events.csv'        WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy ga4.daily_traffic FROM 'data/ga4/daily_traffic.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\echo 'Loading sfmc ...'
TRUNCATE sfmc.subscribers, sfmc.jobs, sfmc.sent, sfmc.opens, sfmc.clicks, sfmc.bounces, sfmc.unsubscribes;
\copy sfmc.subscribers  FROM 'data/sfmc/subscribers.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy sfmc.jobs         FROM 'data/sfmc/job.csv'         WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy sfmc.sent         FROM 'data/sfmc/sent.csv'        WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy sfmc.opens        FROM 'data/sfmc/open.csv'        WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy sfmc.clicks       FROM 'data/sfmc/click.csv'       WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy sfmc.bounces      FROM 'data/sfmc/bounce.csv'      WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy sfmc.unsubscribes FROM 'data/sfmc/unsubscribe.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\echo 'Loading ads ...'
TRUNCATE ads.google_ads_campaign_report, ads.meta_ads_report;
\copy ads.google_ads_campaign_report FROM 'data/ads/google_ads_campaign_report.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy ads.meta_ads_report            FROM 'data/ads/meta_ads_report.csv'            WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

ANALYZE;
\echo 'Done. Run sql/03_row_counts.sql to check the result.'
