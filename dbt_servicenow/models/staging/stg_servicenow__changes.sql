-- stg_servicenow__changes.sql
-- Staging model for ServiceNow change_request table.

with source as (
    select * from {{ source('servicenow_raw', 'CHANGE_REQUEST') }}
    where "_IS_CURRENT" = true
),

renamed as (
    select
        "sys_id"              as change_id,
        "number"              as change_number,
        "assigned_to"         as assigned_to_id,
        "short_description"   as short_description,
        "description"         as description,
        "risk"                as risk,
        "impact"              as impact,
        "state"               as state,
        "type"                as change_type,
        "start_date"          as planned_start_date,
        "end_date"            as planned_end_date,
        "sys_created_on"      as created_at,
        "_LOADED_AT"          as _source_loaded_at,
        "_SOURCE_SYSTEM"      as _source_system
    from source
)

select * from renamed
