-- stg_servicenow__problems.sql
-- Staging model for ServiceNow problem table.

with source as (
    select * from {{ source('servicenow_raw', 'PROBLEM') }}
    where "_IS_CURRENT" = true
),

renamed as (
    select
        "sys_id"              as problem_id,
        "number"              as problem_number,
        "assigned_to"         as assigned_to_id,
        "assignment_group"    as assignment_group,
        "short_description"   as short_description,
        "priority"            as priority,
        "urgency"             as urgency,
        "impact"              as impact,
        "state"               as state,
        "known_error"         as is_known_error,
        "sys_created_on"      as created_at,
        "_LOADED_AT"          as _source_loaded_at,
        "_SOURCE_SYSTEM"      as _source_system
    from source
)

select * from renamed
