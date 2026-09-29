-- One row per inpatient stay, flagged planned/acute, with the patient's next
-- unplanned acute admission. Planned logic follows the CMS planned-readmission idea:
-- scheduled treatment programs and stays containing always-planned procedures
-- (chemotherapy, radiation, dialysis) are planned. Stays over 30 days are
-- long-term residency, not acute care.
with planned_by_procedure as (
    select distinct p.encounter_id
    from {{ ref('stg_procedures') }} p
    join {{ ref('planned_procedure_codes') }} c
      on p.snomed_code = cast(c.snomed_code as varchar)
),
stays as (
    select
        e.encounter_id,
        e.patient_id,
        e.started_at                    as admitted_at,
        e.ended_at                      as discharged_at,
        e.encounter_description,
        e.total_claim_cost,
        date_diff('hour', e.started_at, e.ended_at) / 24.0 as length_of_stay_days,
        (t.encounter_description is not null or pp.encounter_id is not null) as is_planned
    from {{ ref('stg_encounters') }} e
    left join {{ ref('planned_admission_types') }} t using (encounter_description)
    left join planned_by_procedure pp using (encounter_id)
    where e.encounter_class = 'inpatient'
)
select
    *,
    length_of_stay_days <= 30 as is_acute,
    (
        select min(s2.admitted_at)
        from stays s2
        where s2.patient_id = stays.patient_id
          and s2.admitted_at > stays.discharged_at
          and not s2.is_planned
          and s2.length_of_stay_days <= 30
    ) as next_unplanned_admitted_at
from stays
