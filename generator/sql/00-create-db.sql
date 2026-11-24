DROP DATABASE IF EXISTS kalkberg;

CREATE DATABASE kalkberg
    WITH ENCODING 'UTF8'
    TEMPLATE template0;

COMMENT ON DATABASE kalkberg IS 'Kalkberg (fictional climbing webshop) - raw source data for the Power BI showcase';