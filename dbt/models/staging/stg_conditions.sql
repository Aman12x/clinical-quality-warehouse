select
    patient                          as patient_id,
    encounter                        as encounter_id,
    code                             as snomed_code,
    description                      as condition_description,
    cast("start" as date)            as onset_date,
    cast(nullif("stop", '') as date) as resolved_date
from {{ source('raw', 'conditions') }}
