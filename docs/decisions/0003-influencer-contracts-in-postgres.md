# 0003: Land the influencer contracts in PostgreSQL, keep budget and targets in Power Query

**Status:** accepted

## Context

`marketing_budget.xlsx` has three kinds of sheets:

| Sheet(s) | Content |
| --- | --- |
| `Budget 2023` … `Budget 2026` | Planned marketing spend per channel and month |
| `Targets` | Revenue and new-customer targets per month |
| `Influencer contracts` | Per creator: platform, discount code, contract start and end, monthly fee |

The budget and targets are only used to compare plans with actuals in the report. The contracts sheet is different: it's the only place that links a **discount code** to a **creator** and a **period**. The SQL pipeline needs that link to:

- assign orders with an influencer code to the right creator and channel,
- determine which channel brought in each new customer (for CAC and lifetime value per channel),
- build influencer touchpoints for the attribution models,
- calculate the monthly influencer fees as marketing cost.

## Options considered

1. **Everything in Power Query.** This keeps the whole workbook in one place, but pushes the code-to-creator rule into DAX. Acquisition channel and lifetime value per channel would then be hard to calculate, and no other tool could reuse them.
2. **A dbt seed** (a CSV copy of the sheet in the repository). This is simple, but it creates a second copy that drifts as soon as Marketing adds a contract.
3. **Read the sheet from the workbook into a bronze table.** The workbook stays the single source of truth, and the SQL layers can use the data.

## Decision

Option 3. [`ingestion/load_influencer_contracts.py`](../../ingestion/load_influencer_contracts.py) reads the *Influencer contracts* sheet into `budget.influencer_contracts` (all text, with load metadata). The budget and target sheets stay in Power Query.

## Consequences

- Business rules that depend on contracts (such as which channel an order belongs to) are defined once, in SQL, and are tested.
- The workbook is now read by two pipelines. The loader checks the sheet's header, so a layout change in this sheet is caught at load time.
- One extra step after every regeneration of the database (see [00-setup.md](../00-setup.md)).
- Seeds remain the right tool for small, static mappings that *we* own, such as the mapping from budget channel names to `dim_channel`.
