-- generate_sla_thresholds.sql
-- Macro to generate SLA breach CASE expressions.
-- Demonstrates dbt's Jinja macro system for reusable business logic.

{% macro sla_breach_check(priority_column, minutes_column) %}
    case
        when {{ priority_column }} in ('1', '1 - Critical')
            and {{ minutes_column }} > 240 then true
        when {{ priority_column }} in ('2', '2 - High')
            and {{ minutes_column }} > 480 then true
        when {{ priority_column }} in ('3', '3 - Moderate')
            and {{ minutes_column }} > 1440 then true
        when {{ priority_column }} in ('4', '4 - Low')
            and {{ minutes_column }} > 4320 then true
        else false
    end
{% endmacro %}
