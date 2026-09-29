-- Synthea v2 exports a single DATE column; v3 exports START/STOP. Support both.
{% set cols = adapter.get_columns_in_relation(source('raw', 'procedures')) | map(attribute='name') | map('lower') | list %}
select
    patient                  as patient_id,
    encounter                as encounter_id,
    cast({{ '"start"' if 'start' in cols else '"date"' }} as timestamp) as performed_at,
    code                     as snomed_code,
    description              as procedure_description
from {{ source('raw', 'procedures') }}
