-- Earliest onset of each chronic condition group per patient.
select
    c.patient_id,
    r.condition_group,
    min(c.onset_date) as first_onset_date
from {{ ref('stg_conditions') }} c
join {{ ref('chronic_condition_codes') }} r
  on c.snomed_code = cast(r.snomed_code as varchar)
group by 1, 2
