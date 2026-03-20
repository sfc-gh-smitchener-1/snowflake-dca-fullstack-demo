-- assert_no_orphaned_incidents.sql
-- Custom dbt test: ensures every incident has a valid caller in dim_user.
-- This demonstrates dbt's ability to enforce referential integrity
-- that would otherwise require a data contract in the DCA architecture.

with orphaned as (
    select
        f.incident_key,
        f.incident_number,
        f.caller_key
    from {{ ref('fact_incidents') }} f
    left join {{ ref('dim_user') }} u
        on f.caller_key = u.user_key
    where f.caller_key is not null
      and u.user_key is null
)

select * from orphaned
