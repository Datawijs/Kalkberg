# 0001: Build the medallion in PostgreSQL *and* in Power Query

**Status:** accepted

## Context

Kalkberg's data comes from two very different kinds of sources:

- **System exports** (webshop, GA4, Marketing Cloud, ad platforms): large (about 20 million rows), produced by machines, refreshed the same way every time.
- **A hand-maintained Excel workbook** (`marketing_budget.xlsx`): small, owned by Marketing, with a layout that changes from year to year.

This project is also a showcase, so it should show that the medallion approach doesn't depend on one tool.

## Decision

- The system exports go through bronze, silver and gold in **PostgreSQL**. Bronze is loaded with `psql`; silver and gold are built with **dbt**.
- The budget and target sheets go through bronze, silver and gold in **Power Query**, inside Power BI Desktop, as three query groups. Only the gold queries are loaded into the model.
- Both pipelines meet in the semantic model through shared dimensions (`dim_date`, `dim_channel`) from the PostgreSQL gold layer.

## Consequences

- **SQL and dbt** handle volume, can be tested (`dbt test`), show lineage (`dbt docs`) and can be reused by any tool, not only Power BI.
- **Power Query** suits a small, business-owned file that an analyst may need to adapt quickly when Marketing changes the layout.
- There are two places where transformations happen. We limit the risk by mapping the budget's channel names onto the same `dim_channel` that the SQL pipeline uses, and by documenting both pipelines in the same structure.
- Power BI Desktop has no dataflows, so the Power Query medallion lives inside the report file. That's acceptable for one workbook. In a larger setup it would move to a dataflow or into the database.
