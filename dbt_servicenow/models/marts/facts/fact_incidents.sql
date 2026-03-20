-- fact_incidents.sql
-- ServiceNow incident fact table.
-- Enriched with SLA breach detection and resolution metrics.
-- Uses ref() to establish lineage to the user dimension.

with incidents as (
    select * from {{ ref('stg_servicenow__incidents') }}
),

users as (
    select user_key, full_name, department
    from {{ ref('dim_user') }}
)

select
    i.incident_id        as incident_key,
    i.incident_number,
    i.caller_id          as caller_key,
    i.assigned_to_id     as assigned_to_key,
    i.assignment_group,
    i.short_description,
    i.description,
    i.priority,
    i.urgency,
    i.impact,
    i.state,
    i.state_display,
    i.category,
    i.subcategory,
    i.opened_at,
    i.resolved_at,
    i.closed_at,
    i.time_to_resolve_minutes,

    -- SLA breach detection: P1 = 4hr, P2 = 8hr, P3 = 24hr, P4 = 72hr
    case
        when i.priority in ('1', '1 - Critical')
            and i.time_to_resolve_minutes > 240 then true
        when i.priority in ('2', '2 - High')
            and i.time_to_resolve_minutes > 480 then true
        when i.priority in ('3', '3 - Moderate')
            and i.time_to_resolve_minutes > 1440 then true
        when i.priority in ('4', '4 - Low')
            and i.time_to_resolve_minutes > 4320 then true
        else false
    end as is_sla_breached,

    -- Assignee context (from dim_user via ref)
    u.full_name          as assigned_to_name,
    u.department         as assigned_to_department,

    i.is_active,
    i._source_loaded_at,
    i._source_system
from incidents i
left join users u
    on i.assigned_to_id = u.user_key
