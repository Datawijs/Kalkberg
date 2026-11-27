# Step 0: Setup

## What

This step covers the tools we use and how to rebuild the project from scratch, from an empty machine to a PostgreSQL database with all the raw data.

## Tools

| Tool | Used for | Version used |
| --- | --- | --- |
| Python | Generating the data and loading the budget workbook | 3.15 |
| Python for dbt | Running dbt, in its own virtual environment | 3.13 (x64) |
| PostgreSQL (incl. `psql`) | The database that holds the bronze, silver and gold layers | 19 |
| dbt (`dbt-postgres`) | Building the silver and gold layers | dbt Core 1.12, `dbt-postgres` 1.11 |
| `uv` | Installing the Python version that dbt needs | 0.13 |
| Power BI Desktop | Budget medallion, semantic model and report | 2.160.1151.0 64-bit (November 2026) |

### Why these tools

- **PostgreSQL** is a full, free relational database that runs locally, so anyone can reproduce the project without a cloud subscription. Everything we do in it (schemas, views, SQL transformations) works the same way on a cloud data warehouse.
- **`psql` with `\copy`** is the fastest simple way to load large CSV files: about 20 million rows in a few minutes, with no extra Python database driver.
- **Python** is only used where SQL can't do the job: generating the fictional data, and reading an Excel sheet that `psql` can't open.
- **dbt** builds silver and gold from plain SQL, and adds the order of building, tests, documentation and lineage. See [step 3](03-silver.md#why-dbt).
- **Power BI Desktop** is free, and saved as a Power BI Project (`.pbip`) its model and report are text files that git can track. See [decision 0006](decisions/0006-power-bi-project-format.md).

## How to reproduce the project

All commands below are for PowerShell and start from the project folder.

### 1. Generate the data and load it into PostgreSQL

```powershell
cd generator
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python generate_data.py
```

The script asks for:

1. **The output folder** (an absolute path). The default is the `data` folder in the project, which is where the rest of the project expects it.
2. **Whether to load the data into PostgreSQL.** Answer *yes*, then enter host, port, database name (`kalkberg`), maintenance database (`postgres`), username and password.

> [!WARNING]
> Loading drops and recreates the whole database, including everything that was built on top of the raw data (the budget schema, and later the silver and gold layers). After regenerating, always repeat steps 2 and 3.

The generator ends by printing a row count per table. Compare it with the counts the generator printed while writing the files.

![Terminal output of the generator's row check: a table of the 19 bronze tables and their row counts, from 9 rows in shop.brands to 4.454.934 rows in sfmc.sent](img/00-generator-row-check.png)

### 2. Land the influencer contracts

```powershell
cd ingestion
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python load_influencer_contracts.py
```

The script asks for the path of `marketing_budget.xlsx` (default: `data/budget/marketing_budget.xlsx` in the project) and the database connection. It ends with a row-count check. See [step 1](01-bronze.md#2-the-influencer-contracts-sheet) for what it does and why.

![Terminal output of load_influencer_contracts.py: 5 rows read from the Influencer contracts sheet, the table created, TRUNCATE TABLE and COPY 5, and the final check "budget.influencer_contracts: 5 rows - OK"](img/00-ingestion-output.png)

### 3. Build silver and gold

dbt runs from the `dbt` folder, in its own virtual environment.

> [!NOTE]
> dbt doesn't support Python 3.15 yet, and one of its dependencies has no ready-made package for Windows on ARM. That's why the dbt folder uses Python 3.13, installed with [`uv`](https://docs.astral.sh/uv/). On Windows on ARM, take the x64 build (the line below); on other machines, `--python 3.13` is enough.

```powershell
cd dbt
uv venv --python cpython-3.13-windows-x86_64-none .venv
uv pip install --python .venv\Scripts\python.exe -r requirements.txt
```

dbt reads the database connection from environment variables, so no password is stored in the project ([`dbt/profiles.yml`](../dbt/profiles.yml)). Set them once for your Windows user:

```powershell
setx DBT_PG_USER "[username]"
setx DBT_PG_PASSWORD "[password]"
# Only when they differ from the defaults localhost, 5432 and kalkberg:
setx DBT_PG_HOST "[host]"
setx DBT_PG_PORT "[port]"
setx DBT_PG_DBNAME "[database]"
```

`setx` only affects terminals that are opened afterwards. Then, in a new terminal:

```powershell
cd dbt
.venv\Scripts\Activate.ps1
dbt debug     # checks the connection
dbt build     # seeds, models and tests
```

`dbt build` creates the `silver` and `gold` schemas and ends with a summary line; every test must pass. See [step 3](03-silver.md#2-building-silver) and [step 4](04-gold.md#1-building-gold).

### 4. Open the Power BI project

Power BI Desktop needs a few general settings before the project is opened; [step 5](05-powerbi-connection.md#1-general-settings-once-per-machine) lists them. Then:

1. Open `powerbi/kalkberg.pbip`. A clone contains no data, so the tables are empty.
2. **Transform data > Edit parameters**: check `pg_server` and `pg_database`, and set `p_BudgetFile` to the absolute path of `data/budget/marketing_budget.xlsx` on your machine.
3. **Refresh**. Power BI asks for the PostgreSQL credentials once: choose **Database** and enter the same user as for dbt. They're stored encrypted for your Windows user, not in the project.

See [step 5](05-powerbi-connection.md) for the file settings and how to check the result.

## Running the tests

Both Python folders have unit tests that don't need a database:

```powershell
cd generator;  .venv\Scripts\python -m unittest; cd ..
cd ingestion;  .venv\Scripts\python -m unittest; cd ..
```

## Order of work after a regeneration

```
python generator/generate_data.py               # source systems + bronze (drops the database)
python ingestion/load_influencer_contracts.py   # budget.influencer_contracts
cd dbt; dbt build                               # silver + gold
# Power BI Desktop: open powerbi/kalkberg.pbip and Refresh
```
