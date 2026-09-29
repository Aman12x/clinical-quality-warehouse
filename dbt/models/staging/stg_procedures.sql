select
    patient                  as patient_id,
    encounter                as encounter_id,
    cast("date" as timestamp) as performed_at,
    code                     as snomed_code,
    description              as procedure_description
from {{ source('raw', 'procedures') }}
