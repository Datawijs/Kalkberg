from datetime import date, datetime
from pathlib import Path
import tempfile
import unittest

import openpyxl

import load_influencer_contracts as loader


def _make_workbook(path, rows, sheet_name=loader.SHEET_NAME):
    workbook = openpyxl.Workbook()
    sheet = workbook.active
    sheet.title = sheet_name
    for row in rows:
        sheet.append(row)
    workbook.save(path)


class CellToTextTests(unittest.TestCase):
    def test_dates_become_iso_text(self):
        self.assertEqual(loader.cell_to_text(datetime(2024, 1, 15)), "2024-01-15")
        self.assertEqual(loader.cell_to_text(date(2024, 1, 15)), "2024-01-15")
        self.assertEqual(loader.cell_to_text(datetime(2024, 1, 15, 9, 30)), "2024-01-15 09:30:00")

    def test_other_values_are_kept_as_they_are(self):
        self.assertIsNone(loader.cell_to_text(None))
        self.assertEqual(loader.cell_to_text(1500), "1500")
        self.assertEqual(loader.cell_to_text(1500.0), "1500")
        self.assertEqual(loader.cell_to_text(1500.5), "1500.5")
        self.assertEqual(loader.cell_to_text("  LENA15 "), "  LENA15 ")


class ReadContractRowsTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.path = Path(self.temp_dir.name) / "budget.xlsx"

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_reads_rows_with_sheet_row_numbers_and_skips_empty_rows(self):
        _make_workbook(self.path, [
            loader.EXPECTED_HEADER,
            ["lena.sends", "Instagram", "LENA15", datetime(2024, 1, 15), datetime(2024, 12, 31), 1500, "note"],
            [None] * 7,
            ["crimp_kid", "TikTok", "CRIMP15"],
        ])
        rows = loader.read_contract_rows(self.path)
        self.assertEqual(rows, [
            (2, ["lena.sends", "Instagram", "LENA15", "2024-01-15", "2024-12-31", "1500", "note"]),
            (4, ["crimp_kid", "TikTok", "CRIMP15", None, None, None, None]),
        ])

    def test_unexpected_header_fails(self):
        _make_workbook(self.path, [["Creator", "Platform", "Code"]])
        with self.assertRaisesRegex(ValueError, "Unexpected header"):
            loader.read_contract_rows(self.path)

    def test_missing_sheet_fails(self):
        _make_workbook(self.path, [loader.EXPECTED_HEADER], sheet_name="Other")
        with self.assertRaisesRegex(ValueError, "not found"):
            loader.read_contract_rows(self.path)

    def test_values_outside_the_expected_columns_fail(self):
        _make_workbook(self.path, [loader.EXPECTED_HEADER, ["a", "b", "c", "d", "e", "f", "g", "extra"]])
        with self.assertRaisesRegex(ValueError, "outside the expected"):
            loader.read_contract_rows(self.path)

    @unittest.skipUnless(loader.DEFAULT_WORKBOOK.is_file(), "generated workbook not available")
    def test_generated_workbook_matches_the_expected_layout(self):
        rows = loader.read_contract_rows(loader.DEFAULT_WORKBOOK)
        self.assertGreater(len(rows), 0)


class LoadSqlTests(unittest.TestCase):
    def test_csv_contains_metadata_columns(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "out.csv"
            loader.write_csv([(2, ["a", None, "c", "d", "e", "f", "g"])], path, "budget.xlsx")
            lines = path.read_text(encoding="utf-8").splitlines()
        self.assertEqual(lines[0], ",".join(loader.DATA_COLUMNS + loader.METADATA_COLUMNS))
        self.assertEqual(lines[1], f"a,,c,d,e,f,g,budget.xlsx,{loader.SHEET_NAME},2")

    def test_load_sql_truncates_and_quotes_apostrophes(self):
        csv_path = Path.cwd() / "Kalkberg's data" / "contracts.csv"
        sql = loader.render_load_sql(csv_path)
        expected = csv_path.resolve().as_posix().replace("'", "''")
        self.assertTrue(sql.startswith(f"TRUNCATE {loader.TABLE_NAME};"))
        self.assertIn(f"FROM '{expected}'", sql)


if __name__ == "__main__":
    unittest.main()
