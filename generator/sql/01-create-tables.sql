-- =====================================================================
-- Kalkberg demo data - step 1: raw tables
-- Run in the kalkberg database:
--   psql -U postgres -d kalkberg -v ON_ERROR_STOP=1 -f sql/01-create-tables.sql
--
-- Schemas
--   shop  : the webshop's operational (OLTP) database - typed columns, keys, constraints
--   ga4   : Google Analytics 4 exports, landed as-is (all text)
--   sfmc  : Salesforce Marketing Cloud data view exports, landed as-is (all text)
--   ads   : Google Ads and Meta Ads report downloads, landed as-is (all text)
-- The marketing budget is an Excel workbook and is not loaded here.
--
-- Re-running this script drops and recreates these raw tables (your own schemas are not touched).
-- =====================================================================

SET client_min_messages = warning;

CREATE SCHEMA IF NOT EXISTS shop;
CREATE SCHEMA IF NOT EXISTS ga4;
CREATE SCHEMA IF NOT EXISTS sfmc;
CREATE SCHEMA IF NOT EXISTS ads;

DROP TABLE IF EXISTS shop.returns, shop.order_lines, shop.orders, shop.customers,
                     shop.product_variants, shop.products, shop.brands, shop.categories CASCADE;

-- ---------------------------------------------------------------------
-- shop: webshop database
-- ---------------------------------------------------------------------
CREATE TABLE shop.categories (
    category_id      integer       PRIMARY KEY,
    category_name    varchar(100)  NOT NULL,
    parent_category  varchar(100)
);

CREATE TABLE shop.brands (
    brand_id      integer       PRIMARY KEY,
    brand_name    varchar(100)  NOT NULL,
    is_own_brand  boolean       NOT NULL
);

CREATE TABLE shop.products (
    product_id       integer       PRIMARY KEY,
    product_name     varchar(200)  NOT NULL,
    brand_id         integer       NOT NULL REFERENCES shop.brands (brand_id),
    category_id      integer       NOT NULL REFERENCES shop.categories (category_id),
    launched_at      date,
    discontinued_at  date,
    is_active        boolean       NOT NULL
);

CREATE TABLE shop.product_variants (
    variant_id  integer        PRIMARY KEY,
    product_id  integer        NOT NULL REFERENCES shop.products (product_id),
    sku         varchar(40)    NOT NULL UNIQUE,
    size_label  varchar(20),
    list_price  numeric(10,2)  NOT NULL,
    unit_cost   numeric(10,2)
);

CREATE TABLE shop.customers (
    customer_id         integer       PRIMARY KEY,
    email               varchar(254)  NOT NULL UNIQUE,
    first_name          varchar(100),
    last_name           varchar(100),
    phone               varchar(30),
    birth_date          date,
    preferred_language  varchar(5),
    postal_code         varchar(12),
    city                varchar(100),
    country_code        varchar(40),
    marketing_opt_in    boolean       NOT NULL,
    created_at          timestamp     NOT NULL
);

CREATE TABLE shop.orders (
    order_id              integer        PRIMARY KEY,
    order_number          varchar(20)    NOT NULL UNIQUE,
    customer_id           integer        REFERENCES shop.customers (customer_id),
    guest_email           varchar(254),
    created_at            timestamp      NOT NULL,
    status                varchar(20)    NOT NULL,
    currency              char(3)        NOT NULL,
    subtotal              numeric(10,2)  NOT NULL,
    discount_total        numeric(10,2)  NOT NULL,
    shipping_fee          numeric(10,2)  NOT NULL,
    order_total           numeric(10,2)  NOT NULL,
    discount_code         varchar(30),
    payment_method        varchar(30),
    shipping_country      varchar(40),
    shipping_postal_code  varchar(12),
    shipping_city         varchar(100)
);
CREATE INDEX ix_orders_customer ON shop.orders (customer_id);
CREATE INDEX ix_orders_created  ON shop.orders (created_at);

CREATE TABLE shop.order_lines (
    order_line_id    integer        PRIMARY KEY,
    order_id         integer        NOT NULL REFERENCES shop.orders (order_id),
    variant_id       integer        NOT NULL REFERENCES shop.product_variants (variant_id),
    quantity         integer        NOT NULL,
    unit_price       numeric(10,2)  NOT NULL,
    discount_amount  numeric(10,2)  NOT NULL,
    line_total       numeric(10,2)  NOT NULL
);
CREATE INDEX ix_order_lines_order   ON shop.order_lines (order_id);
CREATE INDEX ix_order_lines_variant ON shop.order_lines (variant_id);

CREATE TABLE shop.returns (
    return_id      integer        PRIMARY KEY,
    order_line_id  integer        NOT NULL REFERENCES shop.order_lines (order_line_id),
    requested_at   timestamp      NOT NULL,
    received_at    timestamp,
    quantity       integer        NOT NULL,
    reason         varchar(50),
    status         varchar(20)    NOT NULL,
    refund_amount  numeric(10,2)  NOT NULL
);
CREATE INDEX ix_returns_line ON shop.returns (order_line_id);

COMMENT ON SCHEMA shop IS 'Operational database of the Kalkberg webshop (platform migration on 2024-09-02)';
COMMENT ON COLUMN shop.orders.created_at IS 'Order timestamp as stored by the webshop platform';
COMMENT ON COLUMN shop.orders.guest_email IS 'Only filled for orders placed without an account';
COMMENT ON COLUMN shop.product_variants.list_price IS 'Current list price incl. VAT';
COMMENT ON COLUMN shop.product_variants.unit_cost IS 'Current purchase cost excl. VAT';

-- ---------------------------------------------------------------------
-- ga4: Google Analytics 4 exports (landed as text)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS ga4.events, ga4.daily_traffic;

CREATE TABLE ga4.events (
    event_date         text,
    event_timestamp    text,
    event_name         text,
    user_pseudo_id     text,
    user_id            text,
    ga_session_id      text,
    ga_session_number  text,
    source             text,
    medium             text,
    campaign           text,
    page_location      text,
    device_category    text,
    country            text,
    transaction_id     text,
    value              text,
    currency           text
);

CREATE TABLE ga4.daily_traffic (
    date                   text,
    session_source_medium  text,
    session_campaign       text,
    device_category        text,
    country                text,
    sessions               text,
    total_users            text,
    new_users              text,
    engaged_sessions       text,
    add_to_carts           text,
    checkouts              text,
    ecommerce_purchases    text,
    purchase_revenue       text
);

-- ---------------------------------------------------------------------
-- sfmc: Marketing Cloud data views (landed as text)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS sfmc.subscribers, sfmc.jobs, sfmc.sent, sfmc.opens, sfmc.clicks, sfmc.bounces, sfmc.unsubscribes;

CREATE TABLE sfmc.subscribers (
    subscriber_id       text,
    date_undeliverable  text,
    date_joined         text,
    date_unsubscribed   text,
    domain              text,
    email_address       text,
    bounce_count        text,
    subscriber_key      text,
    subscriber_type     text,
    status              text,
    locale              text
);

CREATE TABLE sfmc.jobs (
    job_id                               text,
    email_id                             text,
    account_id                           text,
    from_name                            text,
    from_email                           text,
    sched_time                           text,
    pickup_time                          text,
    delivered_time                       text,
    job_type                             text,
    job_status                           text,
    email_name                           text,
    email_subject                        text,
    category                             text,
    triggerer_send_definition_object_id  text,
    triggered_send_customer_key          text
);

CREATE TABLE sfmc.sent (
    account_id                           text,
    oyb_account_id                       text,
    job_id                               text,
    list_id                              text,
    batch_id                             text,
    subscriber_id                        text,
    subscriber_key                       text,
    event_date                           text,
    domain                               text,
    triggerer_send_definition_object_id  text,
    triggered_send_customer_key          text
);

CREATE TABLE sfmc.opens (
    account_id                           text,
    oyb_account_id                       text,
    job_id                               text,
    list_id                              text,
    batch_id                             text,
    subscriber_id                        text,
    subscriber_key                       text,
    event_date                           text,
    domain                               text,
    is_unique                            text,
    triggerer_send_definition_object_id  text,
    triggered_send_customer_key          text
);

CREATE TABLE sfmc.clicks (
    account_id                           text,
    oyb_account_id                       text,
    job_id                               text,
    list_id                              text,
    batch_id                             text,
    subscriber_id                        text,
    subscriber_key                       text,
    event_date                           text,
    domain                               text,
    url                                  text,
    link_name                            text,
    link_content                         text,
    is_unique                            text,
    triggerer_send_definition_object_id  text,
    triggered_send_customer_key          text
);

CREATE TABLE sfmc.bounces (
    account_id                           text,
    oyb_account_id                       text,
    job_id                               text,
    list_id                              text,
    batch_id                             text,
    subscriber_id                        text,
    subscriber_key                       text,
    event_date                           text,
    domain                               text,
    bounce_category                      text,
    bounce_subcategory                   text,
    bounce_type                          text,
    smtp_bounce_reason                   text,
    is_unique                            text,
    triggerer_send_definition_object_id  text,
    triggered_send_customer_key          text
);

CREATE TABLE sfmc.unsubscribes (
    account_id      text,
    oyb_account_id  text,
    job_id          text,
    list_id         text,
    batch_id        text,
    subscriber_id   text,
    subscriber_key  text,
    event_date      text,
    domain          text,
    is_unique       text
);

-- ---------------------------------------------------------------------
-- ads: ad platform report downloads (landed as text)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS ads.google_ads_campaign_report, ads.meta_ads_report;

CREATE TABLE ads.google_ads_campaign_report (
    day            text,
    campaign       text,
    campaign_type  text,
    currency_code  text,
    cost           text,
    impressions    text,
    clicks         text,
    conversions    text,
    conv_value     text
);

CREATE TABLE ads.meta_ads_report (
    reporting_starts            text,
    reporting_ends              text,
    campaign_name               text,
    ad_set_name                 text,
    amount_spent_eur            text,
    impressions                 text,
    reach                       text,
    link_clicks                 text,
    purchases                   text,
    purchases_conversion_value  text
);
