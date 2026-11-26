-- =====================================================================
-- Kalkberg profiling - round 1: a generic profile of every bronze table
-- Run from the project folder (the folder that contains 'profiling'):
--   psql -U [username] -d kalkberg -f profiling/01-profile-all-tables.sql
--
-- Profiles every column of every table in the bronze schemas and exports the
-- results to profiling/results/round-1/*.csv. Takes a while on the large GA4 and
-- Marketing Cloud tables; progress is printed per table.
-- =====================================================================

\set ON_ERROR_STOP on
\timing on

\ir 00-create-profiling-objects.sql

-- More memory per sort makes COUNT(DISTINCT ...) on millions of rows a lot faster (this session only)
SET work_mem = '256MB';
SET client_min_messages = notice;

\echo 'Profiling bronze tables ...'
CALL profiling.profile_tables(ARRAY['shop', 'ga4', 'sfmc', 'ads', 'budget']);

\echo 'Exporting results to profiling/results/round-1/ ...'
\copy (SELECT * FROM profiling.table_profile  ORDER BY table_schema, table_name) TO 'profiling/results/round-1/table_profile.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.column_profile ORDER BY table_schema, table_name, ordinal_position) TO 'profiling/results/round-1/column_profile.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy (SELECT * FROM profiling.top_values     ORDER BY table_schema, table_name, column_name, value_rank) TO 'profiling/results/round-1/top_values.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

\echo 'Done.'
