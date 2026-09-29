"""Load the Synthea CSV export into the raw schema of the DuckDB warehouse."""
import os
from pathlib import Path
import duckdb

ROOT = Path(__file__).resolve().parents[1]
CSV_DIR = Path(os.environ.get("SYNTHEA_CSV_DIR", ROOT / "data" / "raw" / "csv"))
DB = ROOT / "warehouse.duckdb"
TABLES = ["patients", "encounters", "conditions", "observations", "medications",
          "providers", "organizations", "payers", "procedures"]


def main() -> None:
    con = duckdb.connect(str(DB))
    con.execute("create schema if not exists raw")
    for name in TABLES:
        path = CSV_DIR / f"{name}.csv"
        # all_varchar keeps the raw layer a faithful copy; typing happens in dbt staging
        con.execute(
            f"create or replace table raw.{name} as "
            f"select * from read_csv('{path}', header=true, all_varchar=true)"
        )
        n = con.execute(f"select count(*) from raw.{name}").fetchone()[0]
        print(f"raw.{name}: {n:,} rows")
    con.close()


if __name__ == "__main__":
    main()
