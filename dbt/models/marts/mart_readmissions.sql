-- One row per eligible index stay with its 30-day unplanned readmission flag and
-- the patient context known at admission (the features for the risk model).
{% set window = var('readmission_window_days') %}
with data_end as (
    select max(ended_at) as data_end_at from {{ ref('stg_encounters') }}
),
eligible as (
    select s.*, p.gender, p.birth_date, p.death_date
    from {{ ref('int_inpatient_stays') }} s
    join {{ ref('stg_patients') }} p using (patient_id)
    cross join data_end d
    where not s.is_planned and s.is_acute
      -- alive at discharge
      and (p.death_date is null or p.death_date > cast(s.discharged_at as date))
      -- a full follow-up window must be observable
      and s.discharged_at + interval {{ window }} day <= d.data_end_at
)
select
    e.encounter_id,
    e.patient_id,
    e.admitted_at,
    e.discharged_at,
    extract(year from e.discharged_at)                          as discharge_year,
    e.encounter_description,
    e.gender,
    date_diff('year', e.birth_date, cast(e.admitted_at as date)) as age_at_admit,
    e.length_of_stay_days,
    e.total_claim_cost,
    (
        select count(*) from {{ ref('int_inpatient_stays') }} x
        where x.patient_id = e.patient_id
          and x.admitted_at < e.admitted_at
          and x.admitted_at >= e.admitted_at - interval 365 day
    ) as prior_inpatient_365d,
    (
        select count(*) from {{ ref('stg_encounters') }} x
        where x.patient_id = e.patient_id and x.encounter_class = 'emergency'
          and x.started_at < e.admitted_at
          and x.started_at >= e.admitted_at - interval 180 day
    ) as ed_visits_180d,
    (
        select count(*) from {{ ref('stg_medications') }} m
        where m.patient_id = e.patient_id
          and m.started_at <= e.admitted_at
          and (m.stopped_at is null or m.stopped_at > e.admitted_at)
    ) as active_medications_at_admit,
    {% for grp in ['diabetes', 'hypertension', 'heart_failure', 'coronary_heart_disease', 'chronic_kidney_disease', 'copd'] %}
    exists (
        select 1 from {{ ref('int_patient_chronic_conditions') }} c
        where c.patient_id = e.patient_id and c.condition_group = '{{ grp }}'
          and c.first_onset_date <= cast(e.admitted_at as date)
    ) as has_{{ grp }},
    {% endfor %}
    coalesce(
        e.next_unplanned_admitted_at <= e.discharged_at + interval {{ window }} day,
        false
    ) as readmitted_30d
from eligible e
