"""Land the 'Influencer contracts' sheet of the marketing budget workbook in PostgreSQL.

Run with ``python load_influencer_contracts.py`` after the generator has loaded the
raw data. The script prompts for the workbook and the database connection, then:

1. creates the bronze table ``budget.influencer_contracts`` if it does not exist,
2. reads the sheet and converts every cell to text (dates as YYYY-MM-DD),
3. empties the table and loads the rows in one transaction with ``psql \\copy``,
4. checks that the number of rows in the table equals the number of rows read.

No cleaning happens here: that is the job of the silver layer.
"""
import argparse
import csv
from dataclasses import dataclass
from datetime import date, datetime, time
import getpass
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

import openpyxl


PROJECT_DIR = Path(__file__).resolve().parents[1]
SQL_DIR = Path(__file__).resolve().parent / "sql"
DEFAULT_WORKBOOK = PROJECT_DIR / "data" / "budget" / "marketing_budget.xlsx"

SHEET_NAME = "Influencer contracts"
TABLE_NAME = "budget.influencer_contracts"
# Header as Marketing typed it in the sheet -> column name in the bronze table
EXPECTED_HEADER = ["Creator", "Platform", "Discount code", "Start", "End", "Monthly fee (EUR)", "Remarks"]
DATA_COLUMNS = ["creator", "platform", "discount_code", "start_date", "end_date", "monthly_fee_eur", "remarks"]
METADATA_COLUMNS = ["_source_file", "_sheet_name", "_row_number"]


@dataclass(frozen=True)
class PostgreSQLSettings:
    host: str
    port: int
    database: str
    username: str
    password: str


# ---------------------------------------------------------------------
# Reading the workbook
# ---------------------------------------------------------------------
def cell_to_text(value):
    """Convert an Excel cell value to the text that is stored in bronze.

    Empty cells become None (NULL). Dates become ISO text; other values are written
    as they are, without any formatting or trimming.
    """
    if value is None:
        return None
    if isinstance(value, datetime):
        if value.time() == time(0, 0):
            return value.date().isoformat()
        return value.isoformat(sep=" ")
    if isinstance(value, (date, time)):
        return value.isoformat()
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def _trim_trailing_empty(values):
    values = list(values)
    while values and values[-1] is None:
        values.pop()
    return values


def read_contract_rows(workbook_path, sheet_name=SHEET_NAME):
    """Return the sheet's data rows as ``(row_number, [text values])``.

    Fails when the sheet is missing or its header is not the expected one, so a
    changed layout is noticed at load time instead of in a report. Completely
    empty rows are skipped.
    """
    workbook = openpyxl.load_workbook(workbook_path, read_only=True, data_only=True)
    try:
        if sheet_name not in workbook.sheetnames:
            raise ValueError(f"Sheet '{sheet_name}' not found in {workbook_path.name}. "
                             f"Available sheets: {', '.join(workbook.sheetnames)}")
        rows = workbook[sheet_name].iter_rows(values_only=True)
        header = _trim_trailing_empty(next(rows, []))
        if header != EXPECTED_HEADER:
            raise ValueError(f"Unexpected header in sheet '{sheet_name}': {header}. "
                             f"Expected: {EXPECTED_HEADER}")

        result = []
        for row_number, values in enumerate(rows, start=2):
            values = _trim_trailing_empty(values)
            if not values:
                continue
            if len(values) > len(EXPECTED_HEADER):
                raise ValueError(f"Row {row_number} in sheet '{sheet_name}' has values outside the "
                                 f"expected {len(EXPECTED_HEADER)} columns: {values}")
            values += [None] * (len(EXPECTED_HEADER) - len(values))
            result.append((row_number, [cell_to_text(v) for v in values]))
        return result
    finally:
        workbook.close()


def write_csv(rows, path, source_file, sheet_name=SHEET_NAME):
    """Write the rows plus load metadata as a CSV file that ``\\copy`` can read."""
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(DATA_COLUMNS + METADATA_COLUMNS)
        for row_number, values in rows:
            writer.writerow(values + [source_file, sheet_name, row_number])


# ---------------------------------------------------------------------
# Loading into PostgreSQL
# ---------------------------------------------------------------------
def render_load_sql(csv_path):
    """SQL that empties the bronze table and loads the CSV file (run as one transaction)."""
    quoted_path = csv_path.resolve().as_posix().replace("'", "''")
    columns = ", ".join(DATA_COLUMNS + METADATA_COLUMNS)
    return (
        f"TRUNCATE {TABLE_NAME};\n"
        f"\\copy {TABLE_NAME} ({columns}) FROM '{quoted_path}' "
        f"WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')\n"
    )


def _psql_command(psql, settings):
    return [psql, "-X", "-w", "-v", "ON_ERROR_STOP=1",
            "-h", settings.host, "-p", str(settings.port),
            "-U", settings.username, "-d", settings.database]


def _run_psql(command, password, *args, capture=False):
    environment = os.environ.copy()
    environment["PGPASSWORD"] = password
    try:
        completed = subprocess.run(command + list(args), check=True, env=environment,
                                   capture_output=capture, text=True)
    except subprocess.CalledProcessError as error:
        detail = f"\n{error.stderr.strip()}" if capture and error.stderr else ""
        raise RuntimeError(f"PostgreSQL command failed with exit code {error.returncode}.{detail}") from error
    return completed.stdout if capture else None


def load(settings, workbook_path, psql):
    command = _psql_command(psql, settings)

    print(f"Reading sheet '{SHEET_NAME}' from {workbook_path} ...")
    rows = read_contract_rows(workbook_path)
    print(f"  {len(rows)} rows read")

    print("Running 01-create-budget-tables.sql ...")
    _run_psql(command, settings.password, "-q", "-f", str(SQL_DIR / "01-create-budget-tables.sql"))

    with tempfile.TemporaryDirectory(prefix="kalkberg-ingestion-") as temp_dir:
        temp_dir = Path(temp_dir)
        csv_path = temp_dir / "influencer_contracts.csv"
        write_csv(rows, csv_path, workbook_path.name)
        load_sql = temp_dir / "02-load-influencer-contracts.sql"
        load_sql.write_text(render_load_sql(csv_path), encoding="utf-8")

        print(f"Loading {TABLE_NAME} ...")
        # --single-transaction: if anything fails, the previous contents stay in place
        _run_psql(command, settings.password, "--single-transaction", "-f", str(load_sql))

    print("Checking loaded row count ...")
    output = _run_psql(command, settings.password, "-At", "-c", f"SELECT count(*) FROM {TABLE_NAME}",
                       capture=True)
    loaded = int(output.strip())
    if loaded != len(rows):
        raise RuntimeError(f"{TABLE_NAME} holds {loaded} rows, but {len(rows)} rows were read from the sheet.")
    print(f"  {TABLE_NAME}: {loaded} rows - OK")


# ---------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------
def prompt_required(question, default=None):
    while True:
        prompt = f"{question} [{default}]" if default is not None else question
        value = input(f"{prompt}: ").strip()
        if value:
            return value
        if default is not None:
            return default
        print("This value is required.")


def prompt_workbook(default):
    while True:
        value = input(f"Absolute path to marketing_budget.xlsx [{default}]: ").strip().strip('"')
        path = Path(value).expanduser() if value else default
        if not path.is_absolute():
            print("Please enter an absolute path.")
        elif not path.is_file():
            print(f"File not found: {path}")
        else:
            return path.resolve()


def prompt_port():
    while True:
        value = prompt_required("PostgreSQL port", "5432")
        if value.isdigit() and 1 <= int(value) <= 65535:
            return int(value)
        print("Please enter a port number between 1 and 65535.")


def prompt_postgresql_settings():
    host = prompt_required("PostgreSQL host", "localhost")
    port = prompt_port()
    while True:
        database = prompt_required("Database name", "kalkberg")
        if re.fullmatch(r"[a-z_][a-z0-9_]{0,62}", database):
            break
        print("Use 1-63 lowercase letters, digits, or underscores; start with a letter or underscore.")
    username = prompt_required("PostgreSQL username")
    password = getpass.getpass("PostgreSQL password (input hidden): ")
    return PostgreSQLSettings(host, port, database, username, password)


def main():
    parser = argparse.ArgumentParser(description="Land the influencer contracts sheet in PostgreSQL")
    parser.add_argument("--workbook", type=Path, default=DEFAULT_WORKBOOK,
                        help="suggested path of marketing_budget.xlsx (the script still prompts)")
    args = parser.parse_args()

    workbook_path = prompt_workbook(args.workbook.resolve())
    settings = prompt_postgresql_settings()
    psql = shutil.which("psql")
    if psql is None:
        parser.error("Could not find psql. Install PostgreSQL command-line tools and try again.")
    try:
        load(settings, workbook_path, psql)
    except (RuntimeError, ValueError) as error:
        parser.exit(1, f"Error: {error}\n")


if __name__ == "__main__":
    main()
