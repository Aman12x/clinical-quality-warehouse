# Clinical Quality Warehouse

A clinical quality analytics warehouse built on [Synthea](https://github.com/synthetichealth/synthea)
EHR data. Raw patient, encounter, condition, observation, medication and procedure extracts
are loaded into DuckDB and modeled with dbt into marts for:

- **30-day unplanned readmission**, with CMS-style planned-stay exclusions
- **ED utilization** per 1,000 active patients
- **HbA1c control** for patients with diabetes (poor control above 9%, control below 8%)
- **Blood pressure control** (under 140/90) for patients with hypertension

A Python model then predicts 30-day readmission risk at admission from the same mart.

Measure definitions, index-stay rules and limitations are in [docs/measures.md](docs/measures.md).

## Pipeline

```
Synthea CSV extract
  -> scripts/load_raw.py          raw.*            faithful all-varchar copy
  -> dbt staging                  staging.stg_*    typed, renamed, one model per source
  -> dbt intermediate             int_inpatient_stays, int_patient_chronic_conditions
  -> dbt marts                    mart_readmissions, mart_quality_measures
  -> scripts/reconcile.py         source vs warehouse row counts and claim-cost totals
  -> scripts/train_readmission.py readmission risk model -> results/readmission_model.json
```

Code lists (chronic-condition SNOMED codes, planned admission types, planned procedures)
are dbt seeds, so every clinical rule is versioned and reviewable.

## Data quality

- dbt tests: primary-key uniqueness, not-null keys, encounter -> patient referential
  integrity, accepted encounter classes and measure ids, one row per measure and year,
  numerator never above denominator, readmissions always inside the 30-day window.
- `scripts/reconcile.py` checks that every source CSV row reaches the raw table and the
  staging view, and that the encounter claim-cost total survives typing. It exits
  non-zero on any mismatch.

## Run it

```bash
make setup          # uv venv + requirements
make data           # 1,171-patient Synthea sample (what CI uses)
make all            # load -> dbt build -> reconcile -> model
```

To model a larger population, `make generate` runs Synthea (Java 8+) for 5,000 patients
with a fixed seed, then point the loader at it:

```bash
SYNTHEA_CSV_DIR=data/synthea_out/csv make all
```

CI (GitHub Actions) runs the load, the dbt build with all tests, and the reconciliation
on the sample on every push.
