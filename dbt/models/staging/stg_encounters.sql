select
    id                                   as encounter_id,
    patient                              as patient_id,
    organization                         as organization_id,
    provider                             as provider_id,
    payer                                as payer_id,
    encounterclass                       as encounter_class,
    cast("start" as timestamp)           as started_at,
    cast("stop" as timestamp)            as ended_at,
    code                                 as encounter_code,
    description                          as encounter_description,
    cast(total_claim_cost as double)     as total_claim_cost,
    cast(payer_coverage as double)       as payer_coverage,
    nullif(reasoncode, '')               as reason_code,
    nullif(reasondescription, '')        as reason_description
from {{ source('raw', 'encounters') }}
