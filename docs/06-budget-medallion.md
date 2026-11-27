# Step 6: The budget medallion in Power Query

## What

This step brings the marketing budget and the monthly targets into the model. Both come from the workbook `data/budget/marketing_budget.xlsx`, which Marketing maintains by hand. They pass through the same three layers as the PostgreSQL data, but this time in Power Query ([decision 0001](decisions/0001-medallion-in-two-tools.md)):

| Layer | Query group | Queries | Loaded into the model |
| --- | --- | --- | --- |
| Bronze | `01_Bronze` | `bronze_budget`, `bronze_targets` | No |
| Silver | `02_Silver` | `silver_budget`, `silver_targets` | No |
| Gold | `03_Gold\Facts` | `Budget`, `Targets`, and `MarketingSpend` extended | Yes |
| Gold | `03_Gold\Helpers` | `gold_marketing_spend`, `estimated_spend` | No |

The result is two fact tables:

| Table | Grain | Columns |
| --- | --- | --- |
| `Budget` | One row per channel and month | `month_start`, `channel_key`, `budget`, `original_budget` |
| `Targets` | One row per month | `month_start`, `revenue_target`, `new_customers_target`, `is_stretch_target` |

Together they answer the questions about plans and actuals in [context.md](../context.md): *are we on track against the targets* (M2), and *how does actual spend compare with the budget, including the revised Q4 2025 Meta budget* (F1).

The budget also fills a gap in the actual cost. Email and SEO have no actual cost in any source, so their budget counts as the actual cost, marked as an estimate ([step 4](04-gold.md#marketing-cost)). This step adds those rows to `MarketingSpend`, so every cost measure includes them.

The workbook's third kind of sheet, *Influencer contracts*, is not part of this step. It's loaded into PostgreSQL ([decision 0003](decisions/0003-influencer-contracts-in-postgres.md)).

## How

### 1. What is wrong with the sheets

The workbook was read before writing any query, the same way the PostgreSQL data was profiled in [step 2](02-profiling.md). The issues use the same decision words as the [issue register](02-profiling.md#issue-register).

| ID | Issue | Affects | Decision |
| --- | --- | --- | --- |
| BU-01 | **The table doesn't start in A1.** Every budget sheet opens with a title row and an owner/version row. The header (`Channel`, `Jan` … `Dec`, `FY total`, `Notes`) comes after them, and there are empty rows in the used range. | F1 | **Fix**: skip rows until the row whose first cell is `Channel`. |
| BU-02 | **Month headers in two notations.** 2023 to 2025 use text (`Jan`, `Feb`, …). 2026 uses real dates (01/01/2026, …). | F1 | **Fix**: find the months by column position (columns 2 to 13), not by header text. |
| BU-03 | **Months without a plan contain `-`.** January to October 2023, before the shop launched. | F1 | **Exclude**: no row for a month without a plan. A planned `0` is kept, because it is a real plan. |
| BU-04 | **Amounts stored as text.** A few cells hold text in Belgian notation instead of a number, such as `€ 71.250` (SEA, November 2024). | F1 | **Fix**: remove the euro sign and spaces and read the rest in the `nl-BE` notation. |
| BU-05 | **Totals inside the data.** A `TOTAL` row and an `FY total` column. | F1 | **Exclude**: totals are calculated by the model, not stored. They are used to check the result (see [checking](#checking-the-budget-medallion)). |
| BU-06 | **A revision as an extra row.** *Budget 2025* has a row `Paid Social (Meta) - REVISED Q4` with new values for October to December. Its note says it *replaces original Q4 values above (approved by CFO in Sept)*. | F1 | **Fix**: in silver, keep both versions, marked `original` and `revised`. In gold, the revised value becomes the budget. The original stays available in its own column. |
| BU-07 | **Budget channel names differ from the channel list.** The workbook uses names such as `SEA (Google Ads)` and `Affiliates (commission est.)`. | F1, M3, M4 | **Fix**: map them to `channel_key` through `Channel[budget_channel]`, which comes from the dbt seed [`channels.csv`](../dbt/seeds/channels.csv). |
| BU-08 | **Stretch targets in a comment.** The *Targets* sheet marks some months with the comment `stretch target`. | M2 | **Fix**: turn the comment into the boolean `is_stretch_target`. |

The *Targets* sheet is otherwise clean: one row per month from November 2023 to December 2026, with real dates and numbers.

### 2. Creating the queries

Every query is created in the Power Query editor (**Transform data**): right-click the query group, choose **New query > Blank query**, open the **Advanced Editor** and paste the code. Then rename the query. For bronze and silver, right-click the query and switch off **Enable load**.

All queries read the workbook through the `budget_file` parameter ([step 5](05-powerbi-connection.md#4-parameters)).

### 3. Bronze: the sheets as delivered

**`bronze_budget`** takes every sheet whose name starts with *Budget* and a space, with its contents as a nested table:

```powerquery
let
    Source = Excel.Workbook(File.Contents(budget_file), null, true),
    Sheets = Table.SelectRows(Source, each [Kind] = "Sheet" and Text.StartsWith([Name], "Budget ")),
    Result = Table.SelectColumns(Sheets, {"Name", "Data"})
in
    Result
```

**`bronze_targets`** takes the *Targets* sheet:

```powerquery
let
    Source = Excel.Workbook(File.Contents(budget_file), null, true),
    Targets = Source{[Item = "Targets", Kind = "Sheet"]}[Data]
in
    Targets
```

The two extra arguments of `Excel.Workbook` keep bronze honest. `null` doesn't promote any row to headers, so the columns are `Column1` to `Column15`. `true` delays type detection, so a text amount like `€ 71.250` stays visible as text instead of being turned into an error or a guess.

> SCREENSHOT PLACEHOLDER: `bronze_budget` in the Power Query editor, with the nested table of *Budget 2024* opened, showing the title rows and the text amount `€ 71.250`.

### 4. Silver: cleaned and in long format

**`silver_budget`** turns every sheet into one row per channel, month and version:

```powerquery
let
    // One budget sheet -> rows of (channel, month, raw amount)
    CleanSheet = (sheet as table, year as number) as table =>
        let
            FromHeader = Table.Skip(sheet, each [Column1] <> "Channel"),
            Header = FromHeader{0},
            CheckedLayout =
                if Header[Column14] = "FY total" and Header[Column15] = "Notes"
                then Table.Skip(FromHeader, 1)
                else error Error.Record("Layout changed", "Unexpected header in Budget " & Text.From(year)),
            Rows = Table.SelectRows(CheckedLayout, each [Column1] <> null and [Column1] <> "TOTAL"),
            MonthColumns = List.Transform({2..13}, each "Column" & Text.From(_)),
            Kept = Table.SelectColumns(Rows, {"Column1"} & MonthColumns),
            Unpivoted = Table.UnpivotOtherColumns(Kept, {"Column1"}, "month_column", "raw_amount"),
            WithMonth = Table.AddColumn(Unpivoted, "month_start",
                each #date(year, Number.From(Text.AfterDelimiter([month_column], "Column")) - 1, 1), type date)
        in
            WithMonth,

    // "-" means not planned; text amounts use Belgian notation ("€ 71.250")
    ToAmount = (value as any) as nullable number =>
        if value = null or value = "-" then null
        else if value is number then value
        else Number.From(Text.Trim(Text.Remove(value, {"€", "#(00A0)"})), "nl-BE"),

    WithYear = Table.AddColumn(bronze_budget, "year", each Number.From(Text.AfterDelimiter([Name], "Budget ")), Int64.Type),
    PerSheet = Table.AddColumn(WithYear, "rows", each CleanSheet([Data], [year])),
    Combined = Table.Combine(PerSheet[rows]),
    WithAmount = Table.AddColumn(Combined, "amount", each ToAmount([raw_amount]), Currency.Type),
    Planned = Table.SelectRows(WithAmount, each [amount] <> null),
    WithChannel = Table.AddColumn(Planned, "budget_channel",
        each Text.Trim(Text.BeforeDelimiter([Column1], " - REVISED")), type text),
    WithVersion = Table.AddColumn(WithChannel, "version",
        each if Text.Contains([Column1], " - REVISED") then "revised" else "original", type text),
    Result = Table.SelectColumns(WithVersion, {"month_start", "budget_channel", "version", "amount"})
in
    Result
```

Step by step, for every sheet:

1. Skip to the header row and check that the layout is still the expected one (BU-01).
2. Drop the empty rows and the `TOTAL` row, and keep the channel and the twelve month columns (BU-05).
3. Unpivot the months into rows, and build `month_start` from the year in the sheet name and the column position (BU-02).

Then, for all sheets together:

1. Convert the amounts and drop the months without a plan (BU-03, BU-04).
2. Split the revision row into the channel it belongs to and the version `revised` (BU-06).

**`silver_targets`** only needs a header check, readable column names and types:

```powerquery
let
    Promoted = Table.PromoteHeaders(bronze_targets, [PromoteAllScalars = true]),
    CheckedLayout =
        if Table.ColumnNames(Promoted) = {"Month", "Revenue target (EUR)", "New customers target", "Comment"}
        then Promoted
        else error Error.Record("Layout changed", "Unexpected header in the Targets sheet"),
    Renamed = Table.RenameColumns(CheckedLayout, {
        {"Month", "month_start"}, {"Revenue target (EUR)", "revenue_target"},
        {"New customers target", "new_customers_target"}, {"Comment", "comment"}}),
    Rows = Table.SelectRows(Renamed, each [month_start] <> null),
    Typed = Table.TransformColumnTypes(Rows, {
        {"month_start", type date}, {"revenue_target", Currency.Type},
        {"new_customers_target", Int64.Type}, {"comment", type text}})
in
    Typed
```

> SCREENSHOT PLACEHOLDER: `silver_budget` in the Power Query editor, filtered on `Paid Social (Meta)` and October to December 2025, showing an `original` and a `revised` row per month.

### 5. Gold: the facts

**`Budget`** applies the revision and adds the channel key:

```powerquery
let
    Original = Table.SelectRows(silver_budget, each [version] = "original"),
    Revised  = Table.SelectRows(silver_budget, each [version] = "revised"),
    // Business rule: a revision replaces the original value for that channel and month
    Joined = Table.NestedJoin(Original, {"budget_channel", "month_start"},
                              Revised,  {"budget_channel", "month_start"}, "revision", JoinKind.LeftOuter),
    WithRevision = Table.ExpandTableColumn(Joined, "revision", {"amount"}, {"revised_amount"}),
    WithBudget = Table.AddColumn(WithRevision, "budget",
        each if [revised_amount] <> null then [revised_amount] else [amount], Currency.Type),
    Renamed = Table.RenameColumns(WithBudget, {{"amount", "original_budget"}}),
    // Map budget channel names to the gold channel key (seed channels.csv -> dim_channel)
    WithKey = Table.NestedJoin(Renamed, {"budget_channel"}, Channel, {"budget_channel"}, "channel", JoinKind.LeftOuter),
    Expanded = Table.ExpandTableColumn(WithKey, "channel", {"channel_key"}),
    Checked =
        if List.Contains(Expanded[channel_key], null)
        then error Error.Record("Unmapped channel", "A budget channel has no match in Channel[budget_channel]")
        else Expanded,
    Result = Table.SelectColumns(Checked, {"month_start", "channel_key", "budget", "original_budget"}),
    Typed = Table.TransformColumnTypes(Result, {
        {"month_start", type date}, {"channel_key", type text},
        {"budget", Currency.Type}, {"original_budget", Currency.Type}})
in
    Typed
```

**`Targets`** turns the comment into a flag (BU-08):

```powerquery
let
    WithStretch = Table.AddColumn(silver_targets, "is_stretch_target",
        each [comment] <> null and Text.Lower(Text.Trim([comment])) = "stretch target", type logical),
    Result = Table.SelectColumns(WithStretch, {"month_start", "revenue_target", "new_customers_target", "is_stretch_target"})
in
    Result
```

Both queries live in `03_Gold\Facts`, with load switched on. After **Close & Apply** they appear in the model as `Budget` and `Targets`, and saving the project writes `Budget.tmdl` and `Targets.tmdl` to [`tables/`](../powerbi/kalkberg.SemanticModel/definition/tables/). The bronze and silver queries are not tables, so they're stored in [`expressions.tmdl`](../powerbi/kalkberg.SemanticModel/definition/expressions.tmdl), next to the parameters.

### 6. Email and SEO as estimated cost in `MarketingSpend`

`MarketingSpend` holds the actual cost from PostgreSQL: platform reports, contract fees and the affiliate commission estimate. Email (the Marketing Cloud licence) and SEO (the content agency) are fixed monthly fees without an invoice in any source. Step 4 decided that their budget counts as the actual cost, marked as an estimate. These rows are added here, because this is where the budget lives.

`MarketingSpend` then has two parts, each in its own query in a new group `03_Gold\Helpers`, with load switched off:

**`gold_marketing_spend`** is the plain read of gold that used to be the `MarketingSpend` query:

```powerquery
let
    Source = PostgreSQL.Database(pg_server, pg_database),
    #"Navigation 1" = Source{[Schema = "gold", Item = "fct_marketing_spend"]}[Data]
in
    #"Navigation 1"
```

**`estimated_spend`** turns the monthly email and SEO budget into daily cost, within the data period:

```powerquery
let
    // Email and SEO have no actual cost in any source: their budget counts as the actual cost (step 4)
    Channels = {"email", "organic_search"},
    DataDays = List.Transform(Table.SelectRows(Date, each [is_in_data_period])[date], Date.From),
    FirstDay = List.Min(DataDays),
    LastDay = List.Max(DataDays),
    Monthly = Table.SelectRows(Budget, each List.Contains(Channels, [channel_key]) and [budget] > 0),
    WithDays = Table.AddColumn(Monthly, "spend_date", each
        List.Select(
            List.Dates([month_start], Date.DaysInMonth([month_start]), #duration(1, 0, 0, 0)),
            (d) => d >= FirstDay and d <= LastDay)),
    Daily = Table.ExpandListColumn(WithDays, "spend_date"),
    InPeriod = Table.SelectRows(Daily, each [spend_date] <> null),
    WithCost = Table.AddColumn(InPeriod, "cost",
        each Number.Round([budget] / Date.DaysInMonth([month_start]), 2, RoundingMode.AwayFromZero), type number),
    WithCampaign = Table.AddColumn(WithCost, "campaign_key", each null, type nullable text),
    WithSource = Table.AddColumn(WithCampaign, "cost_source", each "budget estimate", type text),
    WithFlag = Table.AddColumn(WithSource, "is_estimated", each true, type logical),
    Result = Table.SelectColumns(WithFlag, {"spend_date", "channel_key", "campaign_key", "cost", "cost_source", "is_estimated"}),
    Typed = Table.TransformColumnTypes(Result, {{"spend_date", type date}})
in
    Typed
```

**`MarketingSpend`** (still in `03_Gold\Facts`, still loaded) only combines the two:

```powerquery
let
    Result = Table.Combine({gold_marketing_spend, estimated_spend})
in
    Result
```

The estimate follows the same rules as the influencer fees in gold: the monthly amount is spread evenly over the days of the month and rounded to cents. The months come from `Budget`, so the Q4 revision and the channel mapping are applied once. A month with a budget of 0 (SEO before April 2024) gets no rows: no fee, no cost.

> [!NOTE]
> `MarketingSpend` can't read PostgreSQL itself and also reference `estimated_spend`. Power Query refuses a query that both opens a data source and uses a query on another source, with the error *Formula.Firewall: Query 'MarketingSpend' references other queries or steps, so it may not directly access a data source*. That's why the plain read moved to `gold_marketing_spend`. `Budget` and `estimated_spend` follow the same rule: they only reference other queries and never open a source themselves.

The group rule from step 5 becomes: **every query in `03_Gold\Dimensions` and `03_Gold\Facts` is loaded, and nothing else**. `03_Gold\Helpers` holds the parts that a gold table is combined from.

### 7. Privacy levels

`Budget` is the first query that combines two data sources: the workbook (through `silver_budget`) and PostgreSQL (through `Channel`). `estimated_spend` and `MarketingSpend` do the same. Power Query only allows that when it knows the privacy level of both sources. As set up in [step 5](05-powerbi-connection.md#3-file-settings-once-for-this-file), both are **Organizational**: internal company data that may be combined with other internal data.

If the levels are missing, the editor shows a yellow bar *Information is required about data privacy*. Choose **Continue** and set both sources to **Organizational**, or set them in **File > Options and settings > Data source settings > Edit Permissions**.

> [!NOTE]
> Privacy levels are stored with the data source credentials on each machine, not in the project. After cloning, they have to be set once (see [00-setup.md](00-setup.md#4-open-the-power-bi-project)).

## Why

### Why the budget stays in Power Query

The budget and targets are only compared with actuals in the report. No SQL model needs them, so loading them into PostgreSQL would add a pipeline step without adding a use. Power Query reads the workbook directly, so the workbook stays the single source of truth. It also shows the same medallion thinking in a second tool, which is the point of [decision 0001](decisions/0001-medallion-in-two-tools.md). The influencer contracts are the exception, because the SQL layers need them ([decision 0003](decisions/0003-influencer-contracts-in-postgres.md)).

### Why bronze and silver are not loaded

They exist to make each step visible and traceable in the editor, not to be reported on. Loading them would put wide, half-cleaned tables in the field list, where someone could build a visual on them. The rule from [step 5](05-powerbi-connection.md#7-query-groups) still holds, with `03_Gold\Helpers` as the one addition: everything in `03_Gold\Dimensions` and `03_Gold\Facts` is loaded, and nothing else.

### Why find the header and the months by position

The sheets are typed by hand, and they already differ from year to year (BU-02). Searching for the `Channel` row survives an extra title row. Using the column position for the months survives `Jan` turning into a date. Promoting the header row would instead produce column names that change with the notation and with the locale.

### Why the layout checks

A hand-maintained workbook will change. Without a check, an extra column would silently shift every month by one. With the check, the refresh fails with a message that names the sheet. The *Influencer contracts* loader does the same for its sheet ([decision 0003](decisions/0003-influencer-contracts-in-postgres.md)). The channel check in gold works the same way for a new or renamed budget channel: it fails the refresh instead of producing a budget without a channel.

### Why the revision is applied in gold, not in silver

Silver cleans and keeps what the source says, and the source says two things: an original Q4 and a revised one. *Which one counts* is a business rule, and business rules are decided in gold ([step 4](04-gold.md#why-decide-business-rules-in-gold-not-in-dax)). Keeping `original_budget` next to `budget` lets the CFO question (F1) show both: the budget as it stands and the budget as it was first approved.

### Why the long format

The workbook has one column per month, which is easy to type but impossible to relate to a calendar. One row per channel and month matches the grain of `MarketingSpend`, so budget and actual spend share the `Date` and `Channel` dimensions in step 7.

### Why `month_start` on the first day of the month

The budget and the targets are monthly, and the calendar is daily. With the first day of the month as the date, both relate directly to `Date[date]`: a monthly value lands on one day of its month and every month-level visual sums it correctly. `Date` covers 2023 to 2026, the same years as the budget.

### Why the email and SEO estimate goes into `MarketingSpend`

Total marketing cost feeds the blended return (M3), CAC per channel (M4) and the comparison with the budget (F1). If email and SEO lived in a separate table, every one of those measures would have to add two tables together, and forgetting it once would make a channel look free. In `MarketingSpend` they are counted automatically, and `is_estimated` and `cost_source` keep them recognisable, just like the affiliate commission estimate. The price is that `MarketingSpend` is no longer a plain read of gold, as [step 5](05-powerbi-connection.md#why-no-transformations-in-power-query) promised for every table. The gold rows pass through unchanged, though. Only rows are added, and only from the budget, which has no other place to be combined with gold.

Only days within the data period get a cost. Outside it, there are no orders, sessions or other actual costs to compare with, and a budget-based cost there would show up as spend in months that haven't happened yet.

### Why convert text amounts with an explicit locale

`Number.From("71.250")` depends on the machine's locale: in English it reads as 71,25. Passing `"nl-BE"` always reads the Belgian notation of the workbook, whatever locale the person refreshing uses.

## Checking the budget medallion

The totals below were calculated directly from the workbook. After **Close & Apply**, check them in a table visual or in DAX query view.

| Check | Expected |
| --- | --- |
| Rows in `Budget` | 228 (12 in 2023, 72 in 2024, 2025 and 2026) |
| Sum of `original_budget` per year | 98.150 / 1.226.400 / 1.861.150 / 2.058.400, the same as the `TOTAL` rows |
| Sum of `budget` in 2025 | 1.912.400: the Meta revision adds 51.250 |
| `budget` for `paid_social`, October to December 2025 | 78.500 / 105.500 / 104.500 |
| Rows in `Targets` | 38 (November 2023 to December 2026) |
| Sum of `revenue_target` / `new_customers_target` | 47.606.000 / 143.140 |
| Months with `is_stretch_target` | 4 (November of every year) |
| Rows in `estimated_spend` | 2.040: 1.096 for `email`, 944 for `organic_search` (01/11/2023 to 31/10/2026) |
| Sum of `cost` in `estimated_spend` | 214.697,30: 106.198,00 for `email`, 108.499,30 for `organic_search` |
| Rows / sum of `cost` in `MarketingSpend` | 14.063 / 4.833.434,97 (gold: 12.023 / 4.618.737,67) |

The estimated cost is a few cents per month below the budget, because the daily amounts are rounded (2.950 / 30 days = 98,33 per day).

```dax
EVALUATE
GROUPBY (
    ADDCOLUMNS ( 'Budget', "year", YEAR ( 'Budget'[month_start] ) ),
    [year],
    "rows", SUMX ( CURRENTGROUP (), 1 ),
    "budget", SUMX ( CURRENTGROUP (), 'Budget'[budget] ),
    "original_budget", SUMX ( CURRENTGROUP (), 'Budget'[original_budget] )
)
ORDER BY [year]
```

> SCREENSHOT PLACEHOLDER: DAX query view with the budget totals per year.

## Next step

[Step 7: the semantic model and DAX measures](07-semantic-model.md).
