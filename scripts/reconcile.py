"""Reconcile the warehouse against the source CSV extract.

Checks, per table, that the source file row count equals the raw table and the
staging view, and that encounter claim-cost totals survive typing. Writes
results/reconciliation.json and exits non-zero on any mismatch.
"""
import csv
import json
import sys
from decimal import Decimal
import os
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
CSV_DIR = Path(os.environ.get("SYNTHEA_CSV_DIR", ROOT / "data" / "raw" / "csv"))
PAIRS = {  # source csv -> staging model
    "patients": "stg_patients", "encounters": "stg_encounters",
    "conditions": "stg_conditions", "medications": "stg_medications",
    "procedures": "stg_procedures",
}


def csv_rows(path: Path) -> int:
    with path.open(newline="", encoding="utf-8") as f:
        return sum(1 for _ in csv.reader(f)) - 1


def main() -> int:
    con = duckdb.connect(str(ROOT / "warehouse.duckdb"), read_only=True)
    checks, ok = [], True
    for src, stg in PAIRS.items():
        n_csv = csv_rows(CSV_DIR / f"{src}.csv")
        n_raw = con.execute(f"select count(*) from raw.{src}").fetchone()[0]
        n_stg = con.execute(f"select count(*) from staging.{stg}").fetchone()[0]
        passed = n_csv == n_raw == n_stg
        ok &= passed
        checks.append({"table": src, "csv_rows": n_csv, "raw_rows": n_raw,
                       "staging_rows": n_stg, "passed": passed})

    with (CSV_DIR / "encounters.csv").open(newline="", encoding="utf-8") as f:
        src_cost = sum(Decimal(r["TOTAL_CLAIM_COST"]) for r in csv.DictReader(f))
    wh_cost = con.execute("select sum(total_claim_cost) from staging.stg_encounters").fetchone()[0]
    diff = abs(float(src_cost) - wh_cost)
    passed = diff < 0.01
    ok &= passed
    checks.append({"check": "encounter total_claim_cost sum", "csv": float(src_cost),
                   "warehouse": wh_cost, "abs_diff": diff, "passed": passed})

    (ROOT / "results").mkdir(exist_ok=True)
    (ROOT / "results" / "reconciliation.json").write_text(
        json.dumps({"passed": ok, "checks": checks}, indent=2))
    for c in checks:
        print(("PASS " if c["passed"] else "FAIL ") + json.dumps(c))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
