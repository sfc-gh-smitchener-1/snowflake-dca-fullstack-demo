-- stg_servicenow__users.sql
-- Staging model for ServiceNow sys_user table.
-- Renames columns to business-friendly names, filters to current records.

with source as (
    select * from {{ source('servicenow_raw', 'SYS_USER') }}
    where "_IS_CURRENT" = true
),

renamed as (
    select
        "sys_id"            as user_id,
        sha2("sys_id", 256) as user_id_hash,
        "user_name"         as username,
        "first_name"        as first_name,
        "last_name"         as last_name,
        "name"              as full_name,
        "email"             as email,
        "phone"             as phone,
        "title"             as job_title,
        "department"        as department,
        "location"          as location,
        "manager"           as manager_id,
        "company"           as company,
        "active"            as is_active,
        "vip"               as is_vip,
        "sys_created_on"    as created_at,
        "_LOADED_AT"        as _source_loaded_at,
        "_SOURCE_SYSTEM"    as _source_system
    from source
)

select * from renamed
