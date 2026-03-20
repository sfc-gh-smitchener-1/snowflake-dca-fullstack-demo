-- stg_servicenow__incidents.sql
-- Staging model for ServiceNow incident table.

with source as (
    select * from {{ source('servicenow_raw', 'INCIDENT') }}
    where "_IS_CURRENT" = true
),

renamed as (
    select
        "sys_id"              as incident_id,
        "number"              as incident_number,
        "caller_id"           as caller_id,
        "assigned_to"         as assigned_to_id,
        "assignment_group"    as assignment_group,
        "short_description"   as short_description,
        "description"         as description,
        "priority"            as priority,
        "urgency"             as urgency,
        "impact"              as impact,
        "state"               as state,
        "state_display"       as state_display,
        "category"            as category,
        "subcategory"         as subcategory,
        "opened_at"           as opened_at,
        "resolved_at"         as resolved_at,
        "closed_at"           as closed_at,
        datediff(
            'minute',
            "opened_at",
            coalesce("resolved_at", current_timestamp())
        )                     as time_to_resolve_minutes,
        "active"              as is_active,
        "_LOADED_AT"          as _source_loaded_at,
        "_SOURCE_SYSTEM"      as _source_system
    from source
)

select * from renamed
