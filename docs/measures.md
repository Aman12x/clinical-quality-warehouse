# Measure definitions

Every measure is computed per calendar measurement year in `marts.mart_quality_measures`
(grain: one row per `measure_id` x `measurement_year`). Years run from 2015 to the last
complete year in the extract. "Active patient" = had any encounter in the year and was
alive at the start of it.

| measure_id | Denominator | Numerator | Notes |
|---|---|---|---|
| `readmission_30d_unplanned` | Eligible index stays discharged in the year | Index stays followed by an unplanned acute inpatient admission within 30 days of discharge | See index-stay rules below |
| `ed_visits_per_1000_patients` | Active patients in the year | Emergency encounters in the year | Rate reported per 1,000 |
| `hba1c_poor_control_gt9` | Active patients aged 18-75 with diabetes (SNOMED 44054006) onset on or before the year | Latest HbA1c (LOINC 4548-4) in the year is above 9.0%, **or no HbA1c was taken** | Inverse measure: lower is better |
| `hba1c_control_lt8` | Same as above | Latest HbA1c in the year is below 8.0% | |
| `bp_control_lt140_90` | Active patients aged 18-85 with hypertension (SNOMED 59621000) onset on or before the year | Latest reading in the year with both systolic (LOINC 8480-6) under 140 and diastolic (LOINC 8462-4) under 90 | Systolic and diastolic must come from the same reading |

## Index stays and readmissions (`mart_readmissions`)

An inpatient stay is an **index stay** when all of these hold:

1. **Unplanned.** Planned stays are excluded, following the CMS planned-readmission idea:
   - the encounter type is a scheduled program (`seeds/planned_admission_types.csv`), or
   - the stay contains an always-planned procedure: chemotherapy, radiation, dialysis
     (`seeds/planned_procedure_codes.csv`).
2. **Acute.** Length of stay is 30 days or less. Longer stays in Synthea are long-term
   residency, not acute hospital care.
3. **Alive at discharge.**
4. **Full follow-up observable.** Discharge is at least 30 days before the end of the extract.

A **readmission** is the next inpatient admission for the same patient that is itself
unplanned and acute, starting after discharge and within 30 days. Planned admissions
never count as readmissions.

## Reference data

Code lists live in dbt seeds so they are versioned and reviewable:

- `chronic_condition_codes.csv`: SNOMED codes grouped into diabetes, hypertension,
  heart failure, coronary heart disease, chronic kidney disease, COPD
- `planned_admission_types.csv`, `planned_procedure_codes.csv`: planned-stay rules

## Limitations

These are simplified versions of HEDIS/CMS logic for a teaching warehouse: no
continuous-enrollment requirement, no hospice or exclusion-diagnosis carve-outs, and no
transfer handling. The data is Synthea-generated, so rates describe the simulator, not a
real population.
