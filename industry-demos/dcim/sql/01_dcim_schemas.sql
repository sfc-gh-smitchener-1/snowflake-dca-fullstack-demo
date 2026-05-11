-- ============================================================================
-- DCIM SOURCE SYSTEM SCHEMAS
-- ============================================================================
-- Creates DCIM-specific schemas in RAW_DEV for the three source systems:
--   - SERVICENOW:   ServiceNow CMDB/DCIM asset data
--   - WORKDAY_DCIM: Workday HCM data center operations workforce
--   - TELEMETRY:    Network observability telemetry
--
-- PREREQUISITES:
--   - sql/01_setup.sql executed (databases, roles exist)
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE RAW_DEV;
USE WAREHOUSE INGEST_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- DCIM SOURCE SYSTEM SCHEMAS
-- ═══════════════════════════════════════════════════════════════════════════

-- ServiceNow CMDB/DCIM asset data (data centers, racks, switches, incidents)
CREATE SCHEMA IF NOT EXISTS RAW_DEV.SERVICENOW
    COMMENT = 'ServiceNow CMDB/DCIM asset data (data centers, racks, switches, incidents)';

-- Workday HCM data center operations workforce (technicians, certs, shifts)
CREATE SCHEMA IF NOT EXISTS RAW_DEV.WORKDAY_DCIM
    COMMENT = 'Workday HCM data center operations workforce (technicians, certs, shifts)';

-- Network observability telemetry (port metrics, switch health, environmental)
CREATE SCHEMA IF NOT EXISTS RAW_DEV.TELEMETRY
    COMMENT = 'Network observability telemetry (port metrics, switch health, environmental)';

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS — DATA_ENGINEER and DATA_STEWARD access
-- ═══════════════════════════════════════════════════════════════════════════

-- DATA_ENGINEER: full control on DCIM schemas
GRANT ALL ON SCHEMA RAW_DEV.SERVICENOW TO ROLE DATA_ENGINEER;
GRANT ALL ON SCHEMA RAW_DEV.WORKDAY_DCIM TO ROLE DATA_ENGINEER;
GRANT ALL ON SCHEMA RAW_DEV.TELEMETRY TO ROLE DATA_ENGINEER;

-- DATA_STEWARD: read-only
GRANT USAGE ON SCHEMA RAW_DEV.SERVICENOW TO ROLE DATA_STEWARD;
GRANT USAGE ON SCHEMA RAW_DEV.WORKDAY_DCIM TO ROLE DATA_STEWARD;
GRANT USAGE ON SCHEMA RAW_DEV.TELEMETRY TO ROLE DATA_STEWARD;

GRANT SELECT ON ALL TABLES IN SCHEMA RAW_DEV.SERVICENOW TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL TABLES IN SCHEMA RAW_DEV.WORKDAY_DCIM TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL TABLES IN SCHEMA RAW_DEV.TELEMETRY TO ROLE DATA_STEWARD;

GRANT SELECT ON FUTURE TABLES IN SCHEMA RAW_DEV.SERVICENOW TO ROLE DATA_STEWARD;
GRANT SELECT ON FUTURE TABLES IN SCHEMA RAW_DEV.WORKDAY_DCIM TO ROLE DATA_STEWARD;
GRANT SELECT ON FUTURE TABLES IN SCHEMA RAW_DEV.TELEMETRY TO ROLE DATA_STEWARD;

SELECT '01_dcim_schemas.sql completed successfully' AS STATUS;
