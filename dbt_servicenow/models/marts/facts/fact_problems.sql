-- fact_problems.sql
-- ServiceNow problem management fact table.
-- Root cause investigation tracking.

with problems as (
    select * from {{ ref('stg_servicenow__problems') }}
),

users as (
    select user_key, full_name, department
    from {{ ref('dim_user') }}
)

select
    p.problem_id         as problem_key,
    p.problem_number,
    p.assigned_to_id     as assigned_to_key,
    p.assignment_group,
    p.short_description,
    p.priority,
    p.urgency,
    p.impact,
    p.state,
    p.is_known_error,
    p.created_at         as created_date,

    -- Assignee context
    u.full_name          as assigned_to_name,
    u.department         as assigned_to_department,

    p._source_loaded_at,
    p._source_system
from problems p
left join users u
    on p.assigned_to_id = u.user_key
