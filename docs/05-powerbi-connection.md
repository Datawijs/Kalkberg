# Step 5: Connecting Power BI to the gold layer

## What

This step creates the Power BI file and loads the gold layer into it. It sets up the file, the table names and the query groups, not the model: no relationships, measures or visuals yet. Those follow in step 7, after the budget medallion of step 6.

The result lives in [`powerbi/`](../powerbi/):

```code
powerbi/
  kalkberg.pbip                     --> Opens the project in Power BI Desktop
  kalkberg.SemanticModel/           --> The semantic model, as TMDL text files
    definition/
      expressions.tmdl              --> The parameters (server, database, budget file)
      model.tmdl                    --> Model-wide settings
      tables/                       --> One file per table, with its columns and Power Query code
  kalkberg.Report/                  --> The report, as PBIR JSON files
```

The model holds the 17 gold tables (9 facts, 8 dimensions, see [step 4](04-gold.md#the-tables)), all in **Import** mode. Every table is a plain read of its gold table: no transformations in Power Query, because the business rules already sit in gold.

## How

### 1. General settings (once per machine)

These live under **File > Options and settings > Options > GLOBAL**. Some only apply to files that are created *after* the change, so set them before creating the file.

| Section | Setting | Value |
| --- | --- | --- |
| Preview features | Power BI Project (.pbip) save option, TMDL and PBIR (when still listed as preview) | On |
| Regional settings | Application language | English |
| Regional settings | Model language | English |
| Data Load | Type detection | According to each file's setting |
| Data Load | Auto date/time for new files | Off |
| Power Query Editor | Display the formula bar, Enable M IntelliSense | On |
| Security | Require user approval for new native database queries | On |
| Privacy | Privacy levels | Combine data according to each file's Privacy Level settings |
| Auto recovery | Store auto recovery information | On |

> SCREENSHOT PLACEHOLDER: the GLOBAL > Data Load page of the Options dialog, with *Auto date/time for new files* switched off.

### 2. Creating the project

A new file is saved straight away with **File > Save as**, type **Power BI Project (\*.pbip)**, as `powerbi/kalkberg.pbip`. That creates the folders above. The model is stored as TMDL and the report as PBIR, both plain text.

Two files in the `.pbi` folders are local only and are excluded in the project's [`.gitignore`](../.gitignore):

| File | Holds | Why it's not in git |
| --- | --- | --- |
| `.pbi/cache.abf` | The loaded data | Large, and it's data, not code. Anyone can rebuild it with a refresh. |
| `.pbi/localSettings.json` | Personal settings of the person who opened the file | Differs per machine |

### 3. File settings (once for this file)

These live under **File > Options and settings > Options > CURRENT FILE**.

| Section | Setting | Value |
| --- | --- | --- |
| Regional settings | Locale for import | Dutch (Belgium) |
| Data Load | Type detection | Never detect column types and headers for unstructured sources |
| Data Load | Import relationships from data sources on first load | Off |
| Data Load | Update or delete relationships when refreshing data | Off |
| Data Load | Autodetect new relationships after data is loaded | Off |
| Data Load | Auto date/time | Off |
| Data Load | Parallel loading of tables | Default |
| Privacy | Privacy levels | Combine data according to your Privacy Level settings for each source |

Once the sources exist, both get the **Organizational** privacy level in **File > Options and settings > Data source settings**: the PostgreSQL database and the budget workbook.

The locale for import controls how Power Query reads text as dates and numbers. Dutch (Belgium) reads them in the Belgian notation (`31/03/2026`, `1.234,56`), which is what the budget workbook uses. It's separate from the locale the report *shows* values in, which is English (Belgium) (see the [conventions](README.md#conventions-in-these-documents)). The one difference to watch: month names written out as text are read in Dutch (`maart`, not `March`).

Some of these settings can be checked in the TMDL files. In [`model.tmdl`](../powerbi/kalkberg.SemanticModel/definition/model.tmdl), `sourceQueryCulture: nl-BE` is the locale for import, `__PBI_TimeIntelligenceEnabled = 0` means auto date/time is off, and the model has no relationships yet.

### 4. Parameters

The connection details are Power Query parameters (group `_params`), so that someone who clones the project changes them in one place instead of in every query. That's the same idea as the `DBT_PG_*` environment variables for dbt.

| Parameter | Value in the project | Used for |
| --- | --- | --- |
| `pg_server` | `localhost` | PostgreSQL server |
| `pg_database` | `kalkberg` | PostgreSQL database |
| `budget_file` | `C:\path\to\kalkberg\data\budget\marketing_budget.xlsx` | The budget medallion (step 6) |

Change them in **Transform data > Edit parameters**. Power BI needs an absolute path for the workbook, so `budget_file` always has to be set after cloning: the committed value is the path on the machine where the project was built.

### 5. Connecting to gold

**Get data > PostgreSQL database**, with `pg_server` and `pg_database` as server and database, **Import** as the data connectivity mode, then all tables from the `gold` schema.

> SCREENSHOT PLACEHOLDER: the Navigator with the 17 tables of the `gold` schema selected.

Every table gets the same two-step query:

```powerquery
let
  Source = PostgreSQL.Database(pg_server, pg_database),
  #"Navigation 1" = Source{[Schema = "gold", Item = "fct_orders"]}[Data]
in
  #"Navigation 1"
```

**Credentials.** Use **Database** authentication with the same PostgreSQL user that dbt uses. Power BI Desktop stores the credentials encrypted, per Windows user, on the machine itself. They're never in the project files, so they never reach git: only the server and database names are committed. Manage or remove them in **File > Options and settings > Data source settings**.

> [!NOTE]
> A local PostgreSQL without SSL makes Power BI ask whether to connect without encryption. That's fine for a database on your own machine, but not for a hosted database.

### 6. Table names

Power BI names every table after its schema and table (`gold fct_orders`, ...). Each one is renamed in the Power Query editor to a business name in PascalCase, without the schema or the `fct_`/`dim_` prefix:

| Gold table | Power BI table | | Gold table | Power BI table |
| --- | --- | --- | --- | --- |
| `fct_orders` | `Orders` | | `dim_date` | `Date` |
| `fct_order_lines` | `OrderLines` | | `dim_customer` | `Customer` |
| `fct_returns` | `Returns` | | `dim_product` | `Product` |
| `fct_order_touchpoints` | `OrderTouchpoints` | | `dim_channel` | `Channel` |
| `fct_customer_rfm_monthly` | `CustomerMonthlyRFM` | | `dim_campaign` | `Campaign` |
| `fct_marketing_spend` | `MarketingSpend` | | `dim_country` | `Country` |
| `fct_ad_performance` | `AdPerformance` | | `dim_email` | `Email` |
| `fct_web_traffic` | `WebTraffic` | | `dim_subscriber` | `Subscriber` |
| `fct_email_sends` | `EmailSends` | | | |

Facts are named in the plural (they hold many orders, sends, ...), dimensions in the singular (each row describes one customer, one product, ...). Renaming only changes the query's name: the navigation step still reads `Schema = "gold", Item = "fct_orders"`, so the link with PostgreSQL stays the same.

### 7. Query groups

The queries are organised in query groups (folders in the Power Query editor), by medallion layer:

```code
_params                             --> pg_server, pg_database, budget_file
01_Bronze                           --> Budget sheets as delivered (step 6), not loaded
02_Silver                           --> Budget sheets cleaned (step 6), not loaded
03_Gold
  Dimensions                        --> The 8 gold dimensions
  Facts                             --> The 9 gold facts, and later the budget and targets (step 6)
  Helpers                           --> Added in step 6: the parts MarketingSpend is combined from, not loaded
```

The PostgreSQL tables only appear in `03_Gold`: their bronze and silver layers were built in PostgreSQL with dbt (steps 1 to 4), so Power Query only reads the result. Only the budget sheets pass through all three groups. The rule that follows is simple: **every query in `03_Gold` is loaded into the model, and nothing outside it is**.

> SCREENSHOT PLACEHOLDER: the Queries pane of the Power Query editor, with the groups `_params`, `01_Bronze`, `02_Silver` and `03_Gold` (Dimensions, Facts) expanded.

In TMDL, the groups are declared in [`model.tmdl`](../powerbi/kalkberg.SemanticModel/definition/model.tmdl) (`queryGroup 03_Gold\Facts`, ...), and every table names its group in its partition.

## Why

### Why a Power BI Project (.pbip) instead of a .pbix

A `.pbix` is a binary file: git can store it, but can't show what changed. A `.pbip` stores the model and the report as text, so every change to a table, relationship, measure or query shows up in a diff and can be reviewed, just like the dbt models. See [decision 0006](decisions/0006-power-bi-project-format.md).

### Why Import mode

The gold layer is small enough to load completely: the largest table, `fct_email_sends`, has 4,5 million rows. Import gives fast visuals and the full range of DAX. DirectQuery would send a query to PostgreSQL for every visual, which helps for very large or real-time data, neither of which applies here. A refresh after `dbt build` is enough.

### Why no auto date/time and no automatic relationships

Gold already has a calendar (`dim_date`, with promotion periods) and a designed star schema. Auto date/time would add a hidden date table for every date column: a bigger model, and a second calendar that competes with `dim_date`. Autodetected relationships are guesses based on column names. Both are things we want to decide and document ourselves in step 7.

### Why no transformations in Power Query

Every business rule is decided in gold (see [step 4](04-gold.md#why-decide-business-rules-in-gold-not-in-dax)). If Power Query changed the gold tables, the same number could mean something different in PostgreSQL and in the report. The only Power Query work in this project is the budget medallion in step 6, for data that doesn't come from PostgreSQL ([decision 0001](decisions/0001-medallion-in-two-tools.md)).

### Why business names without prefixes

The table names are what report builders see in the field list, and what every DAX measure refers to: `SUM(Orders[revenue])` reads better than `SUM('gold fct_orders'[revenue])`. The schema adds nothing in the model, because every table comes from gold. The `fct_`/`dim_` prefixes are useful in SQL, where many tables sit side by side, but in Power BI the model diagram shows which tables are facts and which are dimensions. PascalCase without spaces means the names never need quotes in DAX.

The tables were renamed now, before there are relationships, measures or visuals that refer to them, so the later steps never see the old names.

### Why query groups by layer

The groups follow the same medallion as the rest of the project, so the Power Query editor shows the budget's path from bronze to gold. A split by source (PostgreSQL, budget workbook) was considered, but would put the PostgreSQL tables in a folder of their own while they're gold like the budget's end result. Within `03_Gold`, the split in dimensions and facts keeps 17 (and later more) queries easy to scan. The numbers in the group names keep the layers in their logical order.

### Why parameters

Without them the server and database name would be written in 17 queries, and the workbook path in every budget query. With parameters, moving to another machine or database is three values in one dialog.

## Checking the connection

After **Refresh**, the row count of every table in Power BI must match [step 4](04-gold.md#the-tables), for example 400.792 rows in `Orders` and 1.461 in `Date`. The row count of a table is shown in the status bar of the table view.

> SCREENSHOT PLACEHOLDER: the table view of `Orders`, with the row count in the status bar.

## Next step

[Step 6: the budget medallion in Power Query](06-budget-medallion.md).
