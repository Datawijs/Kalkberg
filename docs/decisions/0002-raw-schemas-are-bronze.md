# 0002: The raw schemas are the bronze layer

**Status:** accepted

## Context

The generator already loads every export into its own schema (`shop`, `ga4`, `sfmc`, `ads`): one table per file, every column as delivered, and file exports as `text`. A common medallion setup copies such data into a separate `bronze` schema first.

## Decision

The raw schemas *are* the bronze layer. We don't copy them, and we never change them by hand. The budget workbook gets its own raw schema (`budget`) following the same pattern. From step 3 onwards, dbt reads them as `sources`.

## Consequences

- No second copy of about 1,3 GB, and no extra load step that can fail or drift.
- The schema name tells you the source system, which is handy when tracing a number back.
- Silver and gold get their own schemas, so the layers stay clearly separated in the database.
- The generator drops and recreates the database on every load, so everything built on top (budget, silver, gold) has to be rebuilt afterwards. That order is documented in [00-setup.md](../00-setup.md).
