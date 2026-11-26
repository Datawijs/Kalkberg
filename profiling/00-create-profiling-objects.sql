-- =====================================================================
-- Kalkberg profiling - objects used to profile the bronze layer
-- Run in the kalkberg database (01-profile-all-tables.sql runs this script for you):
--   psql -U [username] -d kalkberg -v ON_ERROR_STOP=1 -f profiling/00-create-profiling-objects.sql
--
-- Schema
--   profiling : a workbench for analysing the bronze data. It is not a medallion layer:
--               nothing downstream reads from it, and it can be dropped at any time.
--
-- Bronze tables are only read, never changed.
-- =====================================================================

SET client_min_messages = warning;

CREATE SCHEMA IF NOT EXISTS profiling;
COMMENT ON SCHEMA profiling IS 'Workbench for profiling the bronze layer - not part of the medallion layers';

-- ---------------------------------------------------------------------
-- Result tables
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS profiling.table_profile (
    table_schema         text         NOT NULL,
    table_name           text         NOT NULL,
    row_count            bigint       NOT NULL,
    duplicate_row_count  bigint       NOT NULL,   -- rows that are an exact copy of another row
    profiled_at          timestamptz  NOT NULL DEFAULT now(),
    PRIMARY KEY (table_schema, table_name)
);

CREATE TABLE IF NOT EXISTS profiling.column_profile (
    table_schema          text         NOT NULL,
    table_name            text         NOT NULL,
    column_name           text         NOT NULL,
    ordinal_position      integer      NOT NULL,
    data_type             text         NOT NULL,
    row_count             bigint       NOT NULL,
    null_count            bigint       NOT NULL,
    empty_count           bigint       NOT NULL,   -- ''
    distinct_count        bigint       NOT NULL,
    min_value             text,                    -- text columns: alphabetical order
    max_value             text,
    min_length            integer,
    max_length            integer,
    untrimmed_count       bigint       NOT NULL,   -- leading or trailing whitespace
    has_uppercase_count   bigint       NOT NULL,
    has_lowercase_count   bigint       NOT NULL,
    -- How many values match a format (computed on the text representation of every value)
    integer_count         bigint       NOT NULL,   -- 123, -5
    decimal_point_count   bigint       NOT NULL,   -- 12.50
    decimal_comma_count   bigint       NOT NULL,   -- 12,50
    iso_date_count        bigint       NOT NULL,   -- 2024-01-31
    iso_datetime_count    bigint       NOT NULL,   -- 2024-01-31 14:05[:00], 2024-01-31T14:05
    other_date_count      bigint       NOT NULL,   -- 31/01/2024, 1-31-24, 31.01.2024
    profiled_at           timestamptz  NOT NULL DEFAULT now(),
    PRIMARY KEY (table_schema, table_name, column_name)
);

CREATE TABLE IF NOT EXISTS profiling.top_values (
    table_schema     text           NOT NULL,
    table_name       text           NOT NULL,
    column_name      text           NOT NULL,
    value_rank       integer        NOT NULL,   -- 1 = most frequent
    value            text,                      -- NULL is listed as a value too; long values cut at 200 characters
    value_count      bigint         NOT NULL,
    value_share_pct  numeric(5,2)   NOT NULL,
    PRIMARY KEY (table_schema, table_name, column_name, value_rank)
);

-- ---------------------------------------------------------------------
-- profiling.profile_table: profile one table (replaces earlier results for that table)
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE profiling.profile_table(p_schema text, p_table text, p_top_n integer DEFAULT 25)
LANGUAGE plpgsql AS $procedure$
DECLARE
    c          record;
    v_as_text  text;   -- the column as text: used for counts, lengths and formats
    v_min_max  text;   -- the column used for min/max (typed columns keep their own order)
BEGIN
    DELETE FROM profiling.table_profile  WHERE table_schema = p_schema AND table_name = p_table;
    DELETE FROM profiling.column_profile WHERE table_schema = p_schema AND table_name = p_table;
    DELETE FROM profiling.top_values     WHERE table_schema = p_schema AND table_name = p_table;

    -- Table level: row count and exact duplicate rows
    EXECUTE format(
        'INSERT INTO profiling.table_profile (table_schema, table_name, row_count, duplicate_row_count)
         SELECT %1$L, %2$L, count(*), count(*) - (SELECT count(*) FROM (SELECT DISTINCT * FROM %1$I.%2$I) AS d)
         FROM %1$I.%2$I',
        p_schema, p_table);

    FOR c IN
        SELECT column_name, ordinal_position, data_type
        FROM information_schema.columns
        WHERE table_schema = p_schema AND table_name = p_table
        ORDER BY ordinal_position
    LOOP
        v_as_text := format('%I::text', c.column_name);
        v_min_max := CASE WHEN c.data_type = 'boolean' THEN v_as_text ELSE quote_ident(c.column_name) END;

        -- Column level: completeness, cardinality, range, notation
        EXECUTE format($sql$
            INSERT INTO profiling.column_profile (
                table_schema, table_name, column_name, ordinal_position, data_type,
                row_count, null_count, empty_count, distinct_count,
                min_value, max_value, min_length, max_length,
                untrimmed_count, has_uppercase_count, has_lowercase_count,
                integer_count, decimal_point_count, decimal_comma_count,
                iso_date_count, iso_datetime_count, other_date_count)
            SELECT %1$L, %2$L, %3$L, %4$s, %5$L,
                   count(*),
                   count(*) - count(%6$s),
                   count(*) FILTER (WHERE %6$s = ''),
                   count(DISTINCT %6$s),
                   min(%7$s)::text,
                   max(%7$s)::text,
                   min(length(%6$s)),
                   max(length(%6$s)),
                   count(*) FILTER (WHERE %6$s ~ '^\s|\s$'),
                   count(*) FILTER (WHERE %6$s ~ '[A-Z]'),
                   count(*) FILTER (WHERE %6$s ~ '[a-z]'),
                   count(*) FILTER (WHERE %6$s ~ '^[+-]?[0-9]+$'),
                   count(*) FILTER (WHERE %6$s ~ '^[+-]?[0-9]*\.[0-9]+$'),
                   count(*) FILTER (WHERE %6$s ~ '^[+-]?[0-9]*,[0-9]+$'),
                   count(*) FILTER (WHERE %6$s ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'),
                   count(*) FILTER (WHERE %6$s ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}'),
                   count(*) FILTER (WHERE %6$s ~ '^[0-9]{1,2}[/.-][0-9]{1,2}[/.-][0-9]{2,4}')
            FROM %8$I.%9$I
            $sql$,
            p_schema, p_table, c.column_name, c.ordinal_position, c.data_type,
            v_as_text, v_min_max, p_schema, p_table);

        -- Most frequent values (ties in alphabetical order)
        EXECUTE format($sql$
            INSERT INTO profiling.top_values (
                table_schema, table_name, column_name, value_rank, value, value_count, value_share_pct)
            SELECT %1$L, %2$L, %3$L, value_rank, left(value, 200), value_count,
                   round(100.0 * value_count / total_count, 2)
            FROM (
                SELECT %4$s AS value,
                       count(*) AS value_count,
                       row_number() OVER (ORDER BY count(*) DESC, %4$s) AS value_rank,
                       sum(count(*)) OVER () AS total_count
                FROM %5$I.%6$I
                GROUP BY 1
            ) AS v
            WHERE value_rank <= %7$s
            $sql$,
            p_schema, p_table, c.column_name, v_as_text, p_schema, p_table, p_top_n);
    END LOOP;
END;
$procedure$;

-- ---------------------------------------------------------------------
-- profiling.profile_tables: profile every table in the given schemas
-- Commits after each table, so a long run keeps the results of finished tables.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE profiling.profile_tables(p_schemas text[])
LANGUAGE plpgsql AS $procedure$
DECLARE
    t          record;
    v_started  timestamptz;
BEGIN
    FOR t IN
        SELECT table_schema, table_name
        FROM information_schema.tables
        WHERE table_schema = ANY (p_schemas) AND table_type = 'BASE TABLE'
        ORDER BY table_schema, table_name
    LOOP
        v_started := clock_timestamp();
        CALL profiling.profile_table(t.table_schema, t.table_name);
        COMMIT;
        RAISE NOTICE '%.% profiled in %', t.table_schema, t.table_name,
                     date_trunc('second', clock_timestamp() - v_started);
    END LOOP;
END;
$procedure$;
