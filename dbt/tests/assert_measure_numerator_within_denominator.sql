-- proportion measures can never have more events than eligible patients/stays
select * from {{ ref('mart_quality_measures') }}
where rate_unit = 'proportion' and numerator > denominator
