select measure_id, measurement_year, count(*) as n
from {{ ref('mart_quality_measures') }}
group by 1, 2 having count(*) > 1
