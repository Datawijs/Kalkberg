# 0006: Save the Power BI file as a Power BI Project (.pbip)

**Status:** accepted

## Context

Everything else in this project is text in git: SQL, dbt models, Python, documentation. Every change can be reviewed in a diff. A Power BI file holds just as much logic (Power Query code, relationships, DAX measures) and should be just as reviewable.

## Options considered

1. **A `.pbix` file.** The default format: one binary file that also contains the data. Git can store it, but can't show what changed, and every refresh makes the file change.
2. **A Power BI Project (`.pbip`)**, with the semantic model in TMDL and the report in PBIR. Everything is plain text, and the data stays in a local cache that isn't committed.

## Decision

Option 2. The project is [`powerbi/kalkberg.pbip`](../../powerbi/kalkberg.pbip). The local files `.pbi/cache.abf` (the data) and `.pbi/localSettings.json` are excluded in `.gitignore`.

## Consequences

- Every change to the model or the report shows up in a diff, table by table and measure by measure.
- A clone contains no data. After opening the project, set the parameters, enter the credentials and refresh ([step 5](../05-powerbi-connection.md)).
- To share the report as a single file, Power BI Desktop can still save a copy as `.pbix`.
