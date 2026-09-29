select
    patient                          as patient_id,
    nullif(encounter, '')            as encounter_id,
    cast("date" as timestamp)        as observed_at,
    code                             as loinc_code,
    description                      as observation_description,
    try_cast(value as double)        as value_numeric,
    units
from {{ source('raw', 'observations') }}
where type = 'numeric'
