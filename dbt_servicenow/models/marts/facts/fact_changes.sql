-- fact_changes.sql
-- ServiceNow change request fact table.
-- Tracks planned changes to IT services with risk assessment.

with changes as (
    select * from {{ ref('stg_servicenow__changes') }}
),

users as (
    select user_key, full_name, department
    from {{ ref('dim_user') }}
)

select
    c.change_id          as change_key,
    c.change_number,
    c.assigned_to_id     as assigned_to_key,
    c.short_description,
    c.description,
    c.risk,
    c.impact,
    c.state,
    c.change_type,
    c.planned_start_date,
    c.planned_end_date,
    c.created_at         as created_date,

    -- Assignee context
    u.full_name          as assigned_to_name,
    u.department         as assigned_to_department,

    c._source_loaded_at,
    c._source_system
from changes c
left join users u
    on c.assigned_to_id = u.user_key
