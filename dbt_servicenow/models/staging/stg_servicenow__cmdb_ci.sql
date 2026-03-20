-- stg_servicenow__cmdb_ci.sql
-- Staging model for ServiceNow CMDB configuration items.

with source as (
    select * from {{ source('servicenow_raw', 'CMDB_CI') }}
    where "_IS_CURRENT" = true
),

renamed as (
    select
        "sys_id"              as ci_id,
        sha2("sys_id", 256)   as ci_id_hash,
        "name"                as ci_name,
        "sys_class_name"      as ci_class,
        "short_description"   as description,
        "manufacturer"        as manufacturer,
        "model_id"            as model_id,
        "serial_number"       as serial_number,
        "asset_tag"           as asset_tag,
        "ip_address"          as ip_address,
        "mac_address"         as mac_address,
        "install_status"      as install_status,
        "operational_status"  as operational_status,
        "location"            as location,
        "department"          as department,
        "assigned_to"         as assigned_to_id,
        "vendor"              as vendor,
        "cost"                as cost,
        "sys_created_on"      as created_at,
        "_LOADED_AT"          as _source_loaded_at,
        "_SOURCE_SYSTEM"      as _source_system
    from source
)

select * from renamed
