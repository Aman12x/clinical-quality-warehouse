-- a stay flagged as readmitted must have its next unplanned admission inside the window, after discharge
select r.encounter_id
from {{ ref('mart_readmissions') }} r
join {{ ref('int_inpatient_stays') }} s using (encounter_id)
where r.readmitted_30d
  and not (s.next_unplanned_admitted_at > s.discharged_at
           and s.next_unplanned_admitted_at <= s.discharged_at + interval 30 day)
