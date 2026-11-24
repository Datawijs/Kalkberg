import io
from contextlib import redirect_stdout
from pathlib import Path
import unittest
from unittest.mock import patch

import generate_data


class GenerateDataTests(unittest.TestCase):
    def test_output_folder_prompt_retries_relative_paths(self):
        default = Path.cwd()
        with patch("builtins.input", side_effect=["relative\\folder", str(default)]):
            with redirect_stdout(io.StringIO()):
                output = generate_data.prompt_absolute_path(default)
        self.assertEqual(output, default.resolve())

    def test_loader_uses_absolute_data_paths_and_quotes_apostrophes(self):
        data_dir = Path.cwd() / "Kalkberg's data"
        sql = generate_data._render_load_sql(
            generate_data.SQL_DIR / "02-load-raw-data.sql", data_dir
        )
        expected_root = data_dir.resolve().as_posix().replace("'", "''")
        self.assertIn(f"FROM '{expected_root}/shop/categories.csv'", sql)
        self.assertNotIn("'data/", sql)

    def test_database_script_uses_selected_database_name(self):
        sql = generate_data._render_create_database_sql(
            generate_data.SQL_DIR / "00-create-db.sql", "demo_db"
        )
        self.assertIn("DROP DATABASE IF EXISTS demo_db;", sql)
        self.assertIn("CREATE DATABASE demo_db", sql)
        self.assertNotIn("DATABASE kalkberg", sql)


if __name__ == "__main__":
    unittest.main()
