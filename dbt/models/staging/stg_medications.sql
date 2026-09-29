select
    patient                              as patient_id,
    encounter                            as encounter_id,
    code                                 as rxnorm_code,
    description                          as medication_description,
    cast("start" as timestamp)           as started_at,
    cast(nullif("stop", '') as timestamp) as stopped_at,
    cast(dispenses as integer)           as dispenses,
    cast(totalcost as double)            as total_cost
from {{ source('raw', 'medications') }}
