-- ============================================================================
-- DCIM CURATED LAYER — Dynamic Tables
-- ============================================================================
-- Creates Dynamic Tables in CURATED_DEV for each DCIM source system.
-- Each Dynamic Table applies business-friendly naming, SCD6 current-record
-- filtering (WHERE "_IS_CURRENT" = TRUE), and appropriate target lag.
--
-- Schema Structure:
--   CURATED_DEV.SERVICENOW  — ServiceNow asset/CMDB dimensions and facts
--   CURATED_DEV.WORKDAY_DCIM — Workday technician workforce dimensions and facts
--   CURATED_DEV.TELEMETRY   — Network observability telemetry facts
--
-- PREREQUISITES:
--   - sql/05_curated_layer.sql executed (CURATED_DEV database and shared schemas)
--   - 01_dcim_schemas.sql executed (RAW_DEV schemas)
--   - 02_dcim_load_data.sql executed (data loaded into RAW_DEV)
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE CURATED_DEV;
USE WAREHOUSE COMPUTE_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- CREATE DCIM SCHEMAS IN CURATED_DEV
-- ═══════════════════════════════════════════════════════════════════════════

CREATE SCHEMA IF NOT EXISTS CURATED_DEV.SERVICENOW
    COMMENT = 'ServiceNow CMDB/DCIM curated dimensions and facts';

CREATE SCHEMA IF NOT EXISTS CURATED_DEV.WORKDAY_DCIM
    COMMENT = 'Workday HCM data center workforce curated dimensions and facts';

CREATE SCHEMA IF NOT EXISTS CURATED_DEV.TELEMETRY
    COMMENT = 'Network observability telemetry curated facts';

-- ═══════════════════════════════════════════════════════════════════════════
-- SERVICENOW DYNAMIC TABLES
-- ═══════════════════════════════════════════════════════════════════════════

-- DIM_DATA_CENTER: Global data center facilities
CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.SERVICENOW.DIM_DATA_CENTER
    TARGET_LAG = '1 hour'
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'ServiceNow data center facilities — current state from SCD6'
AS
SELECT
    "data_center_id"             AS DATA_CENTER_ID,
    "current_dc_name"            AS DC_NAME,
    "current_region"             AS REGION,
    "current_tier"               AS TIER,
    "current_power_capacity_mw"  AS POWER_CAPACITY_MW,
    "current_sla_tier"           AS SLA_TIER,
    "campus_id"                  AS CAMPUS_ID,
    "original_dc_name"           AS ORIGINAL_DC_NAME,
    "original_region"            AS ORIGINAL_REGION,
    "_VALID_FROM"                AS VALID_FROM,
    "_VERSION"                   AS VERSION,
    "_SOURCE_SYSTEM"             AS SOURCE_SYSTEM,
    "_LOADED_AT"                 AS LOADED_AT
FROM RAW_DEV.SERVICENOW.DATA_CENTERS
WHERE "_IS_CURRENT" = TRUE;

-- DIM_HALL: Halls within data centers
CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.SERVICENOW.DIM_HALL
    TARGET_LAG = '1 hour'
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'ServiceNow data center halls — current state from SCD6'
AS
SELECT
    "hall_id"                    AS HALL_ID,
    "data_center_id"             AS DATA_CENTER_ID,
    "current_hall_name"          AS HALL_NAME,
    "current_floor_area_sqft"    AS FLOOR_AREA_SQFT,
    "current_cooling_capacity_kw" AS COOLING_CAPACITY_KW,
    "original_hall_name"         AS ORIGINAL_HALL_NAME,
    "_VALID_FROM"                AS VALID_FROM,
    "_VERSION"                   AS VERSION,
    "_SOURCE_SYSTEM"             AS SOURCE_SYSTEM,
    "_LOADED_AT"                 AS LOADED_AT
FROM RAW_DEV.SERVICENOW.HALLS
WHERE "_IS_CURRENT" = TRUE;

-- DIM_RACK: 42U racks in halls
CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.SERVICENOW.DIM_RACK
    TARGET_LAG = '1 hour'
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'ServiceNow racks — current state from SCD6'
AS
SELECT
    "rack_id"                    AS RACK_ID,
    "hall_id"                    AS HALL_ID,
    "current_rack_name"          AS RACK_NAME,
    "current_power_allocation_kw" AS POWER_ALLOCATION_KW,
    "current_load_pct"           AS LOAD_PCT,
    "original_power_allocation_kw" AS ORIGINAL_POWER_ALLOCATION_KW,
    "_VALID_FROM"                AS VALID_FROM,
    "_VERSION"                   AS VERSION,
    "_SOURCE_SYSTEM"             AS SOURCE_SYSTEM,
    "_LOADED_AT"                 AS LOADED_AT
FROM RAW_DEV.SERVICENOW.RACKS
WHERE "_IS_CURRENT" = TRUE;

-- DIM_SWITCH: Spine/leaf/ToR switches (near real-time for operational use)
CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.SERVICENOW.DIM_SWITCH
    TARGET_LAG = '5 minutes'
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'ServiceNow switches — near real-time current state from SCD6'
AS
SELECT
    "switch_id"                  AS SWITCH_ID,
    "current_rack_id"            AS RACK_ID,
    "current_switch_name"        AS SWITCH_NAME,
    "current_model"              AS MODEL,
    "current_firmware_version"   AS FIRMWARE_VERSION,
    "install_date"               AS INSTALL_DATE,
    "switch_type"                AS SWITCH_TYPE,
    "current_sla_tier"           AS SLA_TIER,
    "original_rack_id"           AS ORIGINAL_RACK_ID,
    "original_firmware_version"  AS ORIGINAL_FIRMWARE_VERSION,
    "_VALID_FROM"                AS VALID_FROM,
    "_VERSION"                   AS VERSION,
    "_SOURCE_SYSTEM"             AS SOURCE_SYSTEM,
    "_LOADED_AT"                 AS LOADED_AT
FROM RAW_DEV.SERVICENOW.SWITCHES
WHERE "_IS_CURRENT" = TRUE;

-- FACT_INCIDENTS: INC tickets (events are immutable — no _IS_CURRENT filter)
CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.SERVICENOW.FACT_INCIDENTS
    TARGET_LAG = '5 minutes'
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'ServiceNow incidents — all tickets (immutable events)'
AS
SELECT
    "incident_id"                AS INCIDENT_ID,
    "switch_id"                  AS SWITCH_ID,
    "priority"                   AS PRIORITY,
    "category"                   AS CATEGORY,
    "status"                     AS STATUS,
    "assigned_technician_id"     AS ASSIGNED_TECHNICIAN_ID,
    "opened_at"                  AS OPENED_AT,
    "resolved_at"                AS RESOLVED_AT,
    "resolution_time_minutes"    AS RESOLUTION_TIME_MINUTES,
    "description"                AS DESCRIPTION,
    "sla_tier"                   AS SLA_TIER,
    "_SOURCE_SYSTEM"             AS SOURCE_SYSTEM,
    "_LOADED_AT"                 AS LOADED_AT
FROM RAW_DEV.SERVICENOW.INCIDENTS;

-- FACT_CHANGE_REQUESTS: CHG tickets for firmware upgrades, rack moves, decommissions
CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.SERVICENOW.FACT_CHANGE_REQUESTS
    TARGET_LAG = '15 minutes'
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'ServiceNow change requests — firmware upgrades, rack moves, decommissions'
AS
SELECT
    "change_id"                  AS CHANGE_ID,
    "switch_id"                  AS SWITCH_ID,
    "change_type"                AS CHANGE_TYPE,
    "status"                     AS STATUS,
    "priority"                   AS PRIORITY,
    "requested_by"               AS REQUESTED_BY,
    "assigned_to"                AS ASSIGNED_TO,
    "planned_start"              AS PLANNED_START,
    "planned_end"                AS PLANNED_END,
    "actual_start"               AS ACTUAL_START,
    "actual_end"                 AS ACTUAL_END,
    "description"                AS DESCRIPTION,
    "_SOURCE_SYSTEM"             AS SOURCE_SYSTEM,
    "_LOADED_AT"                 AS LOADED_AT
FROM RAW_DEV.SERVICENOW.CHANGE_REQUESTS;

-- ═══════════════════════════════════════════════════════════════════════════
-- WORKDAY DCIM DYNAMIC TABLES
-- ═══════════════════════════════════════════════════════════════════════════

-- DIM_TECHNICIAN: Data center operations technicians
CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.WORKDAY_DCIM.DIM_TECHNICIAN
    TARGET_LAG = '1 hour'
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'Workday data center technicians — current state from SCD6'
AS
SELECT
    "worker_id"                  AS WORKER_ID,
    "first_name"                 AS FIRST_NAME,
    "last_name"                  AS LAST_NAME,
    "job_title"                  AS JOB_TITLE,
    "hire_date"                  AS HIRE_DATE,
    "current_campus_assignment"  AS CAMPUS_ASSIGNMENT,
    "current_team_id"            AS TEAM_ID,
    "shift_pattern"              AS SHIFT_PATTERN,
    "original_campus_assignment" AS ORIGINAL_CAMPUS_ASSIGNMENT,
    "original_team_id"           AS ORIGINAL_TEAM_ID,
    "_VALID_FROM"                AS VALID_FROM,
    "_VERSION"                   AS VERSION,
    "_SOURCE_SYSTEM"             AS SOURCE_SYSTEM,
    "_LOADED_AT"                 AS LOADED_AT
FROM RAW_DEV.WORKDAY_DCIM.TECHNICIANS
WHERE "_IS_CURRENT" = TRUE;

-- DIM_CERTIFICATION: Technician certifications
CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.WORKDAY_DCIM.DIM_CERTIFICATION
    TARGET_LAG = '1 hour'
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'Workday technician certifications — current state from SCD6'
AS
SELECT
    "cert_id"                    AS CERT_ID,
    "worker_id"                  AS WORKER_ID,
    "cert_type"                  AS CERT_TYPE,
    "issue_date"                 AS ISSUE_DATE,
    "expiry_date"                AS EXPIRY_DATE,
    "current_status"             AS STATUS,
    "current_ce_hours"           AS CE_HOURS,
    "original_status"            AS ORIGINAL_STATUS,
    "_VALID_FROM"                AS VALID_FROM,
    "_VERSION"                   AS VERSION,
    "_SOURCE_SYSTEM"             AS SOURCE_SYSTEM,
    "_LOADED_AT"                 AS LOADED_AT
FROM RAW_DEV.WORKDAY_DCIM.CERTIFICATIONS
WHERE "_IS_CURRENT" = TRUE;

-- FACT_SHIFTS: Technician shift schedules
CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.WORKDAY_DCIM.FACT_SHIFTS
    TARGET_LAG = '15 minutes'
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'Workday technician shifts — schedule and hours worked'
AS
SELECT
    "shift_id"                   AS SHIFT_ID,
    "worker_id"                  AS WORKER_ID,
    "campus_id"                  AS CAMPUS_ID,
    "shift_date"                 AS SHIFT_DATE,
    "start_time"                 AS START_TIME,
    "end_time"                   AS END_TIME,
    "hours_worked"               AS HOURS_WORKED,
    "shift_type"                 AS SHIFT_TYPE,
    "_SOURCE_SYSTEM"             AS SOURCE_SYSTEM,
    "_LOADED_AT"                 AS LOADED_AT
FROM RAW_DEV.WORKDAY_DCIM.SHIFTS;

-- FACT_SKILL_ASSIGNMENTS: Technician skill proficiency
CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.WORKDAY_DCIM.FACT_SKILL_ASSIGNMENTS
    TARGET_LAG = '1 hour'
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'Workday technician skill assignments and proficiency levels'
AS
SELECT
    "skill_id"                   AS SKILL_ID,
    "worker_id"                  AS WORKER_ID,
    "skill_type"                 AS SKILL_TYPE,
    "proficiency_level"          AS PROFICIENCY_LEVEL,
    "last_assessed_date"         AS LAST_ASSESSED_DATE,
    "_SOURCE_SYSTEM"             AS SOURCE_SYSTEM,
    "_LOADED_AT"                 AS LOADED_AT
FROM RAW_DEV.WORKDAY_DCIM.SKILL_ASSIGNMENTS;

-- ═══════════════════════════════════════════════════════════════════════════
-- TELEMETRY DYNAMIC TABLES
-- ═══════════════════════════════════════════════════════════════════════════

-- FACT_PORT_METRICS: Port-level 5-minute interval telemetry (near real-time)
CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.TELEMETRY.FACT_PORT_METRICS
    TARGET_LAG = '1 minute'
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'Network port metrics — near real-time 5-minute interval telemetry'
AS
SELECT
    "metric_id"                  AS METRIC_ID,
    "port_id"                    AS PORT_ID,
    "switch_id"                  AS SWITCH_ID,
    "timestamp"                  AS METRIC_TIMESTAMP,
    "bytes_in"                   AS BYTES_IN,
    "bytes_out"                  AS BYTES_OUT,
    "packets_in"                 AS PACKETS_IN,
    "packets_out"                AS PACKETS_OUT,
    "crc_errors"                 AS CRC_ERRORS,
    "input_errors"               AS INPUT_ERRORS,
    "output_errors"              AS OUTPUT_ERRORS,
    "utilization_pct"            AS UTILIZATION_PCT,
    "link_status"                AS LINK_STATUS,
    "_SOURCE_SYSTEM"             AS SOURCE_SYSTEM,
    "_LOADED_AT"                 AS LOADED_AT
FROM RAW_DEV.TELEMETRY.PORT_METRICS;

-- FACT_SWITCH_HEALTH: Switch-level health metrics (near real-time)
CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.TELEMETRY.FACT_SWITCH_HEALTH
    TARGET_LAG = '1 minute'
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'Switch health metrics — near real-time CPU, memory, temperature, errors'
AS
SELECT
    "metric_id"                  AS METRIC_ID,
    "switch_id"                  AS SWITCH_ID,
    "timestamp"                  AS METRIC_TIMESTAMP,
    "cpu_utilization"            AS CPU_UTILIZATION,
    "memory_utilization"         AS MEMORY_UTILIZATION,
    "temperature_celsius"        AS TEMPERATURE_CELSIUS,
    "fan_status"                 AS FAN_STATUS,
    "power_draw_watts"           AS POWER_DRAW_WATTS,
    "uptime_seconds"             AS UPTIME_SECONDS,
    "bgp_peers_established"      AS BGP_PEERS_ESTABLISHED,
    "bgp_peers_total"            AS BGP_PEERS_TOTAL,
    "error_rate_pct"             AS ERROR_RATE_PCT,
    "_SOURCE_SYSTEM"             AS SOURCE_SYSTEM,
    "_LOADED_AT"                 AS LOADED_AT
FROM RAW_DEV.TELEMETRY.SWITCH_HEALTH;

-- FACT_ENVIRONMENTAL: DC environmental monitoring sensors
CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.TELEMETRY.FACT_ENVIRONMENTAL
    TARGET_LAG = '5 minutes'
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'Environmental sensors — temperature, humidity, power, cooling efficiency'
AS
SELECT
    "sensor_id"                  AS SENSOR_ID,
    "data_center_id"             AS DATA_CENTER_ID,
    "hall_id"                    AS HALL_ID,
    "rack_id"                    AS RACK_ID,
    "timestamp"                  AS METRIC_TIMESTAMP,
    "temperature_celsius"        AS TEMPERATURE_CELSIUS,
    "humidity_pct"               AS HUMIDITY_PCT,
    "power_draw_kw"              AS POWER_DRAW_KW,
    "cooling_efficiency_pue"     AS COOLING_EFFICIENCY_PUE,
    "airflow_cfm"                AS AIRFLOW_CFM,
    "_SOURCE_SYSTEM"             AS SOURCE_SYSTEM,
    "_LOADED_AT"                 AS LOADED_AT
FROM RAW_DEV.TELEMETRY.ENVIRONMENTAL_SENSORS;

-- FACT_ALERTS: Threshold-crossing alerts (near real-time)
CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.TELEMETRY.FACT_ALERTS
    TARGET_LAG = '1 minute'
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'Telemetry alerts — threshold crossings from ports, switches, environment'
AS
SELECT
    "alert_id"                   AS ALERT_ID,
    "source_type"                AS SOURCE_TYPE,
    "source_id"                  AS SOURCE_ID,
    "timestamp"                  AS ALERT_TIMESTAMP,
    "severity"                   AS SEVERITY,
    "alert_type"                 AS ALERT_TYPE,
    "description"                AS DESCRIPTION,
    "acknowledged"               AS ACKNOWLEDGED,
    "acknowledged_by"            AS ACKNOWLEDGED_BY,
    "resolution_time_minutes"    AS RESOLUTION_TIME_MINUTES,
    "_SOURCE_SYSTEM"             AS SOURCE_SYSTEM,
    "_LOADED_AT"                 AS LOADED_AT
FROM RAW_DEV.TELEMETRY.ALERTS;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS — Allow downstream consumers to read curated tables
-- ═══════════════════════════════════════════════════════════════════════════

GRANT USAGE ON SCHEMA CURATED_DEV.SERVICENOW TO ROLE DATA_STEWARD;
GRANT USAGE ON SCHEMA CURATED_DEV.WORKDAY_DCIM TO ROLE DATA_STEWARD;
GRANT USAGE ON SCHEMA CURATED_DEV.TELEMETRY TO ROLE DATA_STEWARD;

GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA CURATED_DEV.SERVICENOW TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA CURATED_DEV.WORKDAY_DCIM TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA CURATED_DEV.TELEMETRY TO ROLE DATA_STEWARD;

GRANT SELECT ON FUTURE DYNAMIC TABLES IN SCHEMA CURATED_DEV.SERVICENOW TO ROLE DATA_STEWARD;
GRANT SELECT ON FUTURE DYNAMIC TABLES IN SCHEMA CURATED_DEV.WORKDAY_DCIM TO ROLE DATA_STEWARD;
GRANT SELECT ON FUTURE DYNAMIC TABLES IN SCHEMA CURATED_DEV.TELEMETRY TO ROLE DATA_STEWARD;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT
    TABLE_SCHEMA,
    TABLE_NAME,
    COMMENT
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_CATALOG = 'CURATED_DEV'
  AND TABLE_SCHEMA IN ('SERVICENOW', 'WORKDAY_DCIM', 'TELEMETRY')
  AND TABLE_TYPE = 'DYNAMIC TABLE'
ORDER BY TABLE_SCHEMA, TABLE_NAME;

-- ═══════════════════════════════════════════════════════════════════════════
-- SIEMENS DCIM DYNAMIC TABLES (Acquired Portfolio — 2,000 Data Centers)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE SCHEMA IF NOT EXISTS CURATED_DEV.SIEMENS_DCIM
    COMMENT = 'Siemens Desigo CC acquired portfolio — curated dimensions and facts';

-- DIM_FACILITY: Siemens data center facilities (acquired estate)
CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.SIEMENS_DCIM.DIM_FACILITY
    TARGET_LAG = '1 hour'
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'Siemens facilities (Standorte) — current state from SCD6'
AS
SELECT
    "facility_id"                AS FACILITY_ID,
    "current_standort_name"      AS FACILITY_NAME,
    "gebaeude_typ"               AS BUILDING_TYPE,
    "region"                     AS REGION,
    "country"                    AS COUNTRY,
    "city"                       AS CITY,
    "tier_level"                 AS TIER_LEVEL,
    "total_power_mw"             AS TOTAL_POWER_MW,
    "total_cooling_mw"           AS TOTAL_COOLING_MW,
    "rack_capacity"              AS RACK_CAPACITY,
    "commissioning_date"         AS COMMISSIONING_DATE,
    "acquisition_date"           AS ACQUISITION_DATE,
    "original_standort_name"     AS ORIGINAL_FACILITY_NAME,
    "_VALID_FROM"                AS VALID_FROM,
    "_VERSION"                   AS VERSION,
    "_SOURCE_SYSTEM"             AS SOURCE_SYSTEM,
    "_LOADED_AT"                 AS LOADED_AT
FROM RAW_DEV.SIEMENS_DCIM.FACILITIES
WHERE "_IS_CURRENT" = TRUE;

-- DIM_ZONE: HVAC/cooling zones within facilities
CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.SIEMENS_DCIM.DIM_ZONE
    TARGET_LAG = '1 hour'
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'Siemens HVAC/cooling zones per facility'
AS
SELECT
    "zone_id"               AS ZONE_ID,
    "facility_id"           AS FACILITY_ID,
    "zone_name"             AS ZONE_NAME,
    "zone_type"             AS ZONE_TYPE,
    "floor_level"           AS FLOOR_LEVEL,
    "area_sqm"              AS AREA_SQM,
    "target_temp_celsius"   AS TARGET_TEMP_CELSIUS,
    "target_humidity_pct"   AS TARGET_HUMIDITY_PCT,
    "max_power_kw"          AS MAX_POWER_KW,
    "cooling_type"          AS COOLING_TYPE
FROM RAW_DEV.SIEMENS_DCIM.ZONES;

-- DIM_COOLING_LOOP: Chiller plants, CRAH/CRAC units
CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.SIEMENS_DCIM.DIM_COOLING_LOOP
    TARGET_LAG = '4 hours'
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'Siemens cooling loops — chillers, CRAH, CRAC, towers'
AS
SELECT
    "loop_id"               AS LOOP_ID,
    "facility_id"           AS FACILITY_ID,
    "zone_id"               AS ZONE_ID,
    "loop_type"             AS LOOP_TYPE,
    "capacity_kw"           AS CAPACITY_KW,
    "supply_temp_celsius"   AS SUPPLY_TEMP_CELSIUS,
    "return_temp_celsius"   AS RETURN_TEMP_CELSIUS,
    "flow_rate_lpm"         AS FLOW_RATE_LPM,
    "efficiency_cop"        AS EFFICIENCY_COP,
    "refrigerant_type"      AS REFRIGERANT_TYPE,
    "last_service_date"     AS LAST_SERVICE_DATE
FROM RAW_DEV.SIEMENS_DCIM.COOLING_LOOPS;

-- DIM_RACK_INVENTORY: Siemens rack tracking (overlaps ServiceNow — entity resolution)
CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.SIEMENS_DCIM.DIM_RACK_INVENTORY
    TARGET_LAG = '1 hour'
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'Siemens rack inventory — overlaps ServiceNow racks for entity resolution'
AS
SELECT
    "siemens_rack_id"              AS SIEMENS_RACK_ID,
    "facility_id"                  AS FACILITY_ID,
    "zone_id"                      AS ZONE_ID,
    "row_number"                   AS ROW_NUMBER,
    "position_in_row"              AS POSITION_IN_ROW,
    "u_capacity"                   AS U_CAPACITY,
    "u_used"                       AS U_USED,
    "power_allocation_kw"          AS POWER_ALLOCATION_KW,
    "weight_capacity_kg"           AS WEIGHT_CAPACITY_KG,
    "current_weight_kg"            AS CURRENT_WEIGHT_KG,
    "current_customer_name"        AS CUSTOMER_NAME,
    "original_customer_name"       AS ORIGINAL_CUSTOMER_NAME,
    "contract_id"                  AS CONTRACT_ID,
    "servicenow_correlation_id"    AS SERVICENOW_CORRELATION_ID,
    "_VALID_FROM"                  AS VALID_FROM,
    "_VERSION"                     AS VERSION,
    "_SOURCE_SYSTEM"               AS SOURCE_SYSTEM,
    "_LOADED_AT"                   AS LOADED_AT
FROM RAW_DEV.SIEMENS_DCIM.RACK_INVENTORY
WHERE "_IS_CURRENT" = TRUE;

-- DIM_FIRE_SUPPRESSION: Fire protection systems
CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.SIEMENS_DCIM.DIM_FIRE_SUPPRESSION
    TARGET_LAG = '24 hours'
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'Siemens fire suppression systems (Brandschutz)'
AS
SELECT
    "system_id"             AS SYSTEM_ID,
    "facility_id"           AS FACILITY_ID,
    "zone_id"               AS ZONE_ID,
    "system_type"           AS SYSTEM_TYPE,
    "coverage_area_sqm"     AS COVERAGE_AREA_SQM,
    "last_inspection_date"  AS LAST_INSPECTION_DATE,
    "next_inspection_date"  AS NEXT_INSPECTION_DATE,
    "cylinder_pressure_bar" AS CYLINDER_PRESSURE_BAR,
    "agent_quantity_kg"     AS AGENT_QUANTITY_KG,
    "is_compliant"          AS IS_COMPLIANT
FROM RAW_DEV.SIEMENS_DCIM.FIRE_SUPPRESSION;

-- DIM_POWER_DISTRIBUTION_UNIT: PDUs, UPS, switchgear
CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.SIEMENS_DCIM.DIM_POWER_DISTRIBUTION_UNIT
    TARGET_LAG = '5 minutes'
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'Siemens power distribution — PDUs, UPS, ATS, switchgear'
AS
SELECT
    "pdu_id"                AS PDU_ID,
    "facility_id"           AS FACILITY_ID,
    "zone_id"               AS ZONE_ID,
    "equipment_type"        AS EQUIPMENT_TYPE,
    "model"                 AS MODEL,
    "capacity_kva"          AS CAPACITY_KVA,
    "current_load_pct"      AS CURRENT_LOAD_PCT,
    "redundancy"            AS REDUNDANCY,
    "phase"                 AS PHASE,
    "voltage"               AS VOLTAGE,
    "install_date"          AS INSTALL_DATE,
    "last_maintenance_date" AS LAST_MAINTENANCE_DATE
FROM RAW_DEV.SIEMENS_DCIM.POWER_DISTRIBUTION_UNITS;

-- FACT_BMS_SENSORS: Building Management System sensor readings
CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.SIEMENS_DCIM.FACT_BMS_SENSORS
    TARGET_LAG = '1 minute'
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'Siemens BMS sensor readings — near real-time'
AS
SELECT
    "reading_id"    AS READING_ID,
    "sensor_id"     AS SENSOR_ID,
    "facility_id"   AS FACILITY_ID,
    "zone_id"       AS ZONE_ID,
    "timestamp"     AS READING_TIMESTAMP,
    "sensor_type"   AS SENSOR_TYPE,
    "value"         AS SENSOR_VALUE,
    "unit"          AS UNIT,
    "quality"       AS QUALITY,
    "alarm_state"   AS ALARM_STATE
FROM RAW_DEV.SIEMENS_DCIM.BMS_SENSORS;

-- FACT_MAINTENANCE_ORDER: Siemens maintenance orders (Instandhaltungsaufträge)
CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.SIEMENS_DCIM.FACT_MAINTENANCE_ORDER
    TARGET_LAG = '5 minutes'
    WAREHOUSE = COMPUTE_WH
    COMMENT = 'Siemens maintenance orders — corrective, preventive, emergency'
AS
SELECT
    "order_id"          AS ORDER_ID,
    "facility_id"       AS FACILITY_ID,
    "zone_id"           AS ZONE_ID,
    "equipment_type"    AS EQUIPMENT_TYPE,
    "equipment_id"      AS EQUIPMENT_ID,
    "order_type"        AS ORDER_TYPE,
    "priority"          AS PRIORITY,
    "description"       AS DESCRIPTION,
    "assigned_team"     AS ASSIGNED_TEAM,
    "status"            AS STATUS,
    "created_at"        AS CREATED_AT,
    "scheduled_date"    AS SCHEDULED_DATE,
    "completed_at"      AS COMPLETED_AT,
    "resolution_hours"  AS RESOLUTION_HOURS
FROM RAW_DEV.SIEMENS_DCIM.MAINTENANCE_ORDERS;

SELECT '03_dcim_curated_layer.sql completed successfully' AS STATUS;
