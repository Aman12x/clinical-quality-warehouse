-- Yearly clinical quality measures, one row per measure per measurement year.
-- Definitions (denominator, numerator, exclusions) are documented in docs/measures.md.
with years as (
    select distinct extract(year from started_at) as measurement_year
    from {{ ref('stg_encounters') }}
    where extract(year from started_at) between 2015
      and (select extract(year from max(ended_at)) - 1 from {{ ref('stg_encounters') }})
),
active_patients as (   -- patient had any encounter in the year
    select distinct extract(year from started_at) as measurement_year, patient_id
    from {{ ref('stg_encounters') }}
),
patient_age as (
    select a.measurement_year, a.patient_id,
           a.measurement_year - extract(year from p.birth_date) as age_end_of_year
    from active_patients a
    join {{ ref('stg_patients') }} p using (patient_id)
    where p.death_date is null or extract(year from p.death_date) > a.measurement_year
),
chronic as (
    select patient_id, condition_group, extract(year from first_onset_date) as onset_year
    from {{ ref('int_patient_chronic_conditions') }}
),

-- readmission
readmit as (
    select discharge_year as measurement_year,
           count(*) as denominator,
           count(*) filter (where readmitted_30d) as numerator
    from {{ ref('mart_readmissions') }}
    group by 1
),

-- ED utilization per 1,000 active patients
ed as (
    select y.measurement_year,
           (select count(*) from active_patients a where a.measurement_year = y.measurement_year) as denominator,
           (select count(*) from {{ ref('stg_encounters') }} e
             where e.encounter_class = 'emergency'
               and extract(year from e.started_at) = y.measurement_year) as numerator
    from years y
),

-- diabetes: latest HbA1c (LOINC 4548-4) in the year
diabetic_denominator as (
    select pa.measurement_year, pa.patient_id
    from patient_age pa
    join chronic c on c.patient_id = pa.patient_id and c.condition_group = 'diabetes'
    where c.onset_year <= pa.measurement_year and pa.age_end_of_year between 18 and 75
),
latest_a1c as (
    select patient_id, extract(year from observed_at) as measurement_year,
           arg_max(value_numeric, observed_at) as a1c
    from {{ ref('stg_observations') }}
    where loinc_code = '4548-4'
    group by 1, 2
),
a1c as (
    select d.measurement_year,
           count(*) as denominator,
           count(*) filter (where l.a1c is null or l.a1c > 9.0) as poor_control,
           count(*) filter (where l.a1c < 8.0)                   as controlled
    from diabetic_denominator d
    left join latest_a1c l using (patient_id, measurement_year)
    group by 1
),

-- hypertension: latest same-reading systolic (8480-6) and diastolic (8462-4)
hypertensive_denominator as (
    select pa.measurement_year, pa.patient_id
    from patient_age pa
    join chronic c on c.patient_id = pa.patient_id and c.condition_group = 'hypertension'
    where c.onset_year <= pa.measurement_year and pa.age_end_of_year between 18 and 85
),
bp_readings as (
    select patient_id, observed_at,
           max(value_numeric) filter (where loinc_code = '8480-6') as systolic,
           max(value_numeric) filter (where loinc_code = '8462-4') as diastolic
    from {{ ref('stg_observations') }}
    where loinc_code in ('8480-6', '8462-4')
    group by 1, 2
),
latest_bp as (
    select patient_id, extract(year from observed_at) as measurement_year,
           arg_max(systolic, observed_at)  as systolic,
           arg_max(diastolic, observed_at) as diastolic
    from bp_readings
    where systolic is not null and diastolic is not null
    group by 1, 2
),
bp as (
    select h.measurement_year,
           count(*) as denominator,
           count(*) filter (where b.systolic < 140 and b.diastolic < 90) as numerator
    from hypertensive_denominator h
    left join latest_bp b using (patient_id, measurement_year)
    group by 1
),

unioned as (
    select 'readmission_30d_unplanned' as measure_id, measurement_year, numerator, denominator, 'proportion' as rate_unit from readmit
    union all
    select 'ed_visits_per_1000_patients', measurement_year, numerator, denominator, 'per_1000' from ed
    union all
    select 'hba1c_poor_control_gt9', measurement_year, poor_control, denominator, 'proportion' from a1c
    union all
    select 'hba1c_control_lt8', measurement_year, controlled, denominator, 'proportion' from a1c
    union all
    select 'bp_control_lt140_90', measurement_year, numerator, denominator, 'proportion' from bp
)
select
    u.measure_id,
    cast(u.measurement_year as integer) as measurement_year,
    u.numerator,
    u.denominator,
    case when u.denominator = 0 then null
         when u.rate_unit = 'per_1000' then round(1000.0 * u.numerator / u.denominator, 1)
         else round(1.0 * u.numerator / u.denominator, 4) end as rate,
    u.rate_unit
from unioned u
where u.measurement_year in (select measurement_year from years)
