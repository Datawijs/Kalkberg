"""Generate the Kalkberg dataset.

Run with ``python generate_data.py``. The script prompts for the output folder
and optionally loads the generated files into PostgreSQL using ``psql``.
"""
import argparse
from dataclasses import dataclass
import getpass
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from kalkberg import config
from kalkberg.main import run


SQL_DIR = Path(__file__).resolve().parent / "sql"


@dataclass(frozen=True)
class PostgreSQLSettings:
    host: str
    port: int
    database: str
    maintenance_database: str
    username: str
    password: str


def prompt_yes_no(question, default=False):
    hint = "Y/n" if default else "y/N"
    while True:
        answer = input(f"{question} [{hint}]: ").strip().lower()
        if not answer:
            return default
        if answer in ("y", "yes"):
            return True
        if answer in ("n", "no"):
            return False
        print("Please answer yes or no.")


def prompt_absolute_path(default):
    while True:
        value = input(f"Absolute data folder [{default}]: ").strip()
        path = Path(value).expanduser() if value else default
        if path.is_absolute():
            return path.resolve()
        print("Please enter an absolute path.")


def prompt_required(question, default=None):
    while True:
        prompt = f"{question} [{default}]" if default is not None else question
        value = input(f"{prompt}: ").strip()
        if value:
            return value
        if default is not None:
            return default
        print("This value is required.")


def prompt_port():
    while True:
        value = prompt_required("PostgreSQL port", "5432")
        try:
            port = int(value)
        except ValueError:
            print("Please enter a valid port number.")
            continue
        if 1 <= port <= 65535:
            return port
        print("Port must be between 1 and 65535.")


def prompt_postgresql_settings():
    host = prompt_required("PostgreSQL host", "localhost")
    port = prompt_port()
    while True:
        database = prompt_required("Database name", "kalkberg")
        if re.fullmatch(r"[a-z_][a-z0-9_]{0,62}", database):
            break
        print(
            "Use 1-63 lowercase letters, digits, or underscores; "
            "start with a letter or underscore."
        )
    maintenance_database = prompt_required("Maintenance database", "postgres")
    if maintenance_database == database:
        raise ValueError("The maintenance database must be different from the database being recreated.")
    username = prompt_required("PostgreSQL username")
    password = getpass.getpass("PostgreSQL password (input hidden): ")

    return PostgreSQLSettings(
        host, port, database, maintenance_database, username, password
    )


def _psql_command(psql, settings, database):
    return [
        psql,
        "-X",
        "-w",
        "-v",
        "ON_ERROR_STOP=1",
        "-h",
        settings.host,
        "-p",
        str(settings.port),
        "-U",
        settings.username,
        "-d",
        database,
    ]


def _run_psql(command, password, *args):
    environment = os.environ.copy()
    environment["PGPASSWORD"] = password
    try:
        subprocess.run(
            command + list(args),
            check=True,
            env=environment,
        )
    except subprocess.CalledProcessError as error:
        raise RuntimeError(
            f"PostgreSQL command failed with exit code {error.returncode}."
        ) from error


def verify_postgresql(settings):
    psql = shutil.which("psql")
    if psql is None:
        raise RuntimeError(
            "Could not find psql. Install PostgreSQL command-line tools and try again."
        )
    maintenance_command = _psql_command(psql, settings, settings.maintenance_database)
    _run_psql(maintenance_command, settings.password, "-c", "SELECT 1")
    return psql


def _render_create_database_sql(path, database):
    sql = path.read_text(encoding="utf-8")
    return re.sub(r"\bkalkberg\b", database, sql)


def _render_load_sql(path, data_dir):
    sql = path.read_text(encoding="utf-8")
    if "'data/" not in sql:
        raise ValueError(f"No data paths found in SQL loader: {path}")
    quoted_data_dir = data_dir.resolve().as_posix().replace("'", "''")
    return sql.replace("'data/", f"'{quoted_data_dir}/")


def load_postgresql(settings, data_dir, psql):
    maintenance_command = _psql_command(psql, settings, settings.maintenance_database)
    target_command = _psql_command(psql, settings, settings.database)

    with tempfile.TemporaryDirectory(prefix="kalkberg-sql-") as temp_dir:
        temp_dir = Path(temp_dir)
        create_database_sql = temp_dir / "00-create-db.sql"
        create_database_sql.write_text(
            _render_create_database_sql(SQL_DIR / "00-create-db.sql", settings.database),
            encoding="utf-8",
        )
        load_sql = temp_dir / "02-load-raw-data.sql"
        load_sql.write_text(
            _render_load_sql(SQL_DIR / "02-load-raw-data.sql", data_dir),
            encoding="utf-8",
        )

        print(f"Creating database {settings.database} ...")
        _run_psql(
            maintenance_command,
            settings.password,
            "-f",
            str(create_database_sql),
        )
        print("Running 01-create-tables.sql ...")
        _run_psql(
            target_command,
            settings.password,
            "-f",
            str(SQL_DIR / "01-create-tables.sql"),
        )

        print("Loading generated CSV files ...")
        _run_psql(target_command, settings.password, "-f", str(load_sql))
        print("Checking loaded row counts ...")
        _run_psql(
            target_command,
            settings.password,
            "-f",
            str(SQL_DIR / "03-row-check.sql"),
        )


def main():
    parser = argparse.ArgumentParser(description="Generate the Kalkberg demo dataset")
    parser.add_argument(
        "--out",
        type=Path,
        default=config.OUTPUT_DIR,
        help="suggested output folder (the script still prompts for the location)",
    )
    args = parser.parse_args()

    output_dir = prompt_absolute_path(args.out.resolve())
    settings = None
    psql = None
    if prompt_yes_no("Load the generated data into PostgreSQL?"):
        settings = prompt_postgresql_settings()
        if not prompt_yes_no(
            f"This will drop and recreate database {settings.database} if it exists. Continue?"
        ):
            print("PostgreSQL loading skipped; generating files only.")
            settings = None
        else:
            try:
                psql = verify_postgresql(settings)
            except RuntimeError as error:
                parser.error(str(error))

    output_dir.mkdir(parents=True, exist_ok=True)
    print(f"Generating data in {output_dir} ...")
    run(output_dir)
    if settings is not None:
        if psql is None:
            raise RuntimeError("PostgreSQL was selected but psql was not initialized.")
        load_postgresql(settings, output_dir, psql)


if __name__ == "__main__":
    main()
