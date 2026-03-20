-- dim_cmdb_ci.sql
-- CMDB Configuration Item dimension.
-- IT asset and infrastructure inventory managed by dbt.

with cmdb as (
    select * from {{ ref('stg_servicenow__cmdb_ci') }}
)

select
    ci_id              as ci_key,
    ci_id,
    ci_id_hash,
    ci_name,
    ci_class,
    description,
    manufacturer,
    model_id,
    serial_number,
    asset_tag,
    ip_address,
    mac_address,
    install_status,
    operational_status,
    location,
    department,
    assigned_to_id     as assigned_to_key,
    vendor,
    cost,
    created_at         as created_date,
    _source_loaded_at,
    _source_system
from cmdb
