"""
load_raw.py
-----------
Loads Workload.csv into the DuckDB database as the 'workload' table.

Run this whenever Workload.csv is updated, before running 'dbt run'.

Usage (from project root):
    python scripts/load_raw.py
"""

import duckdb
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DB_PATH      = PROJECT_ROOT / "data" / "workload.duckdb"
CSV_PATH     = PROJECT_ROOT / "data" / "Workload.csv"


def load_raw():
    if not CSV_PATH.exists():
        raise FileNotFoundError(f"CSV not found: {CSV_PATH}")

    print(f"Connecting to {DB_PATH}")
    con = duckdb.connect(str(DB_PATH))

    print(f"Loading {CSV_PATH} → workload table")
    con.execute("DROP TABLE IF EXISTS workload")
    con.execute(f"CREATE TABLE workload AS SELECT * FROM read_csv_auto('{CSV_PATH.as_posix()}')")

    row_count = con.execute("SELECT COUNT(*) FROM workload").fetchone()[0]
    con.close()

    print(f"Done. {row_count} rows loaded.")


if __name__ == "__main__":
    load_raw()
