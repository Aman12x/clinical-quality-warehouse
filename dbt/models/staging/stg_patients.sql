select
    id                          as patient_id,
    cast(birthdate as date)     as birth_date,
    cast(nullif(deathdate, '') as date) as death_date,
    gender,
    race,
    ethnicity,
    state,
    county
from {{ source('raw', 'patients') }}
