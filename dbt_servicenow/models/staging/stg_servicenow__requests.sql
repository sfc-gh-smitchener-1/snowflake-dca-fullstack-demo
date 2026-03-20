-- stg_servicenow__requests.sql
-- Staging model for ServiceNow service catalog requests.

with source as (
    select * from {{ source('servicenow_raw', 'SC_REQUEST') }}
    where "_IS_CURRENT" = true
),

renamed as (
    select
        "sys_id"              as request_id,
        "number"              as request_number,
        "requested_for"       as requested_for_id,
        "opened_by"           as opened_by_id,
        "short_description"   as short_description,
        "request_state"       as state,
        "stage"               as stage,
        "price"               as price,
        "sys_created_on"      as created_at,
        "_LOADED_AT"          as _source_loaded_at,
        "_SOURCE_SYSTEM"      as _source_system
    from source
)

select * from renamed
