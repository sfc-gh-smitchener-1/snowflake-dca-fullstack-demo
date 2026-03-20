-- fact_requests.sql
-- ServiceNow service catalog request fact table.

with requests as (
    select * from {{ ref('stg_servicenow__requests') }}
),

users as (
    select user_key, full_name, department
    from {{ ref('dim_user') }}
)

select
    r.request_id         as request_key,
    r.request_number,
    r.requested_for_id   as requested_for_key,
    r.opened_by_id       as opened_by_key,
    r.short_description,
    r.state,
    r.stage,
    r.price,
    r.created_at         as created_date,

    -- Requester context
    u.full_name          as requested_for_name,
    u.department         as requested_for_department,

    r._source_loaded_at,
    r._source_system
from requests r
left join users u
    on r.requested_for_id = u.user_key
