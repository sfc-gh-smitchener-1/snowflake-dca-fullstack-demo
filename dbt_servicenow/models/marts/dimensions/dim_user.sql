-- dim_user.sql
-- ServiceNow user dimension.
-- Equivalent to the Dynamic Tables DIM_USER in CURATED_DEV.SERVICENOW,
-- but managed by dbt with full test coverage and documentation.

with users as (
    select * from {{ ref('stg_servicenow__users') }}
)

select
    user_id          as user_key,
    user_id,
    user_id_hash,
    username,
    first_name,
    last_name,
    full_name,
    email,
    phone,
    job_title,
    department,
    location,
    manager_id,
    company,
    is_active,
    is_vip,
    created_at       as created_date,
    _source_loaded_at,
    _source_system
from users
