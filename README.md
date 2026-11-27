# Kalkberg

This project is meant as a showcase for Datawijs. It shows how we handle data projects: from raw exports, through a medallion architecture (bronze, silver, gold), to a Power BI report that answers the business questions in [context.md](context.md).

Please note that this data is synthetic. Kalkberg, its brands, creators, affiliate partners and customers are completely fictional. The exports are built to look and behave like the real thing, including the kind of problems you could encounter in real data. There is deliberately no list of those problems: finding them is part of the work.

## What you will find in this repo

```code
README.md                           --> Explains how to use this project
context.md                          --> Provides information about the fictional company and its requests
generator/                          --> Code to generate the data used for this project (plays the source systems)
ingestion/                          --> Loads the influencer contracts from the budget workbook into PostgreSQL
profiling/                          --> SQL to profile the raw data, and the results it produced
dbt/                                --> dbt project that builds the silver and gold layers
powerbi/                            --> Power BI project (.pbip): semantic model and report
docs/                               --> Step-by-step guide on what we did, how and why
```

The full walkthrough starts in [docs/README.md](docs/README.md).

## Quick start

You need Python and PostgreSQL (including the `psql` command-line tool). See [docs/00-setup.md](docs/00-setup.md) for the versions we used and more detail.

### 1. Generate the data

From the `generator` folder, run:

```shell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python generate_data.py
```

The script asks for an absolute output folder; keep the default (the `data` folder in the project) so the other steps find the files. It can optionally load the generated CSV files into PostgreSQL. For that, have the database connection details ready.

> [!WARNING]
> Confirming the PostgreSQL load drops and recreates the selected database before loading the data.

### 2. Load the influencer contracts

The marketing budget workbook (`data/budget/marketing_budget.xlsx`) is not loaded by the generator. One of its sheets, *Influencer contracts*, is needed in PostgreSQL. From the `ingestion` folder, run:

```shell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python load_influencer_contracts.py
```

The script asks for the workbook path and the database connection, and loads the sheet into `budget.influencer_contracts`. The other sheets of the workbook are handled in Power BI.

> [!IMPORTANT]
> Run this script again every time the generator has recreated the database.

### 3. Build the silver and gold layers

The silver and gold layers are built with dbt from the `dbt` folder. dbt needs Python 3.13 and reads the database connection from the `DBT_PG_*` environment variables; [docs/00-setup.md](docs/00-setup.md#3-build-silver-and-gold) explains how to set both up. Then run:

```shell
cd dbt
.venv\Scripts\Activate.ps1
dbt build
```

### 4. Open the Power BI project

Open `powerbi/kalkberg.pbip` in Power BI Desktop, set the parameters (database and budget workbook path) under **Transform data > Edit parameters**, and refresh. [docs/00-setup.md](docs/00-setup.md#4-open-the-power-bi-project) has the details.
