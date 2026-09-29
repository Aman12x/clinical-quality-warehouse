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

## Results (5,000-patient Synthea population, seed 42)

Generated with `make generate`: 5,637 patient records (including deceased) and 287,588 encounters. Reconciliation: all checks passed (`results/reconciliation.json`).

### Quality measures, measurement year 2025

| Measure | Numerator | Denominator | Rate |
|---|---|---|---|
| `bp_control_lt140_90` | 809 | 1,233 | 65.6% |
| `ed_visits_per_1000_patients` | 755 | 4,655 | 162.2 per 1,000 |
| `hba1c_control_lt8` | 251 | 255 | 98.4% |
| `hba1c_poor_control_gt9` | 2 | 255 | 0.8% |
| `readmission_30d_unplanned` | 1 | 102 | 1.0% |

All years: `results/quality_measures.csv`.

### Readmission risk model

2,693 eligible index stays from 1,172 patients, 43 readmitted within 30 days (base rate 1.6%). Readmissions are rare in Synthea, so every stay is scored out of fold with 5-fold cross-validation grouped by patient.

| Model | ROC-AUC (out of fold) | PR-AUC | ROC-AUC range across folds | Readmissions in top risk decile |
|---|---|---|---|---|
| logistic regression | 0.647 | 0.033 | 0.48-0.82 | 19% |
| gradient boosting | 0.744 | 0.056 | 0.63-0.92 | 44% |

With only 43 positive stays the fold-to-fold spread is wide, so treat these as a working baseline, not a validated clinical model. Full output: `results/readmission_model.json`.

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
