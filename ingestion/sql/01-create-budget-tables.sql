-- =====================================================================
-- Kalkberg ingestion - budget workbook: bronze tables
-- Run in the kalkberg database:
--   psql -U postgres -d kalkberg -v ON_ERROR_STOP=1 -f sql/01-create-budget-tables.sql
--
-- Schema
--   budget : sheets of data/budget/marketing_budget.xlsx that the SQL pipeline needs, landed as-is (all text)
-- Only the 'Influencer contracts' sheet is landed here. The budget and target sheets are
-- handled in Power BI (Power Query) on purpose.
--
-- The table is only created when it does not exist yet. That way, re-running the
-- ingestion never drops the silver/gold objects that are built on top of it.
-- load_influencer_contracts.py empties and reloads the table on every run.
-- =====================================================================

SET client_min_messages = warning;

CREATE SCHEMA IF NOT EXISTS budget;

CREATE TABLE IF NOT EXISTS budget.influencer_contracts (
    creator          text,
    platform         text,
    discount_code    text,
    start_date       text,
    end_date         text,
    monthly_fee_eur  text,
    remarks          text,
    -- load metadata
    _source_file     text         NOT NULL,
    _sheet_name      text         NOT NULL,
    _row_number      integer      NOT NULL,
    _loaded_at       timestamptz  NOT NULL DEFAULT now()
);

COMMENT ON SCHEMA budget IS 'Marketing budget workbook (maintained by hand by Marketing) - landed as-is';
COMMENT ON TABLE budget.influencer_contracts IS 'Sheet "Influencer contracts" of marketing_budget.xlsx, one row per sheet row';
COMMENT ON COLUMN budget.influencer_contracts.start_date IS 'Excel date cell, written as YYYY-MM-DD text';
COMMENT ON COLUMN budget.influencer_contracts.end_date IS 'Excel date cell, written as YYYY-MM-DD text';
COMMENT ON COLUMN budget.influencer_contracts._source_file IS 'File name of the workbook this row was read from';
COMMENT ON COLUMN budget.influencer_contracts._sheet_name IS 'Worksheet this row was read from';
COMMENT ON COLUMN budget.influencer_contracts._row_number IS 'Row number in the worksheet (header = row 1)';
COMMENT ON COLUMN budget.influencer_contracts._loaded_at IS 'Moment the row was loaded';
