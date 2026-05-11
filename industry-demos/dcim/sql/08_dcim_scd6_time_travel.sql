-- ============================================================================
-- DCIM KNOWLEDGE GRAPH — SCD TYPE 6 TIME TRAVEL
-- ============================================================================
-- Leverages SCD Type 6 (hybrid) columns in ServiceNow dimension tables to
-- reconstruct infrastructure state at any point in time and provide a
-- complete change audit trail.
--
-- SCD6 columns in RAW data:
--   current_<attr>    — the present value
--   historical_<attr> — the value at _VALID_FROM time
--   original_<attr>   — the value at first insert
--   _VALID_FROM, _VALID_TO, _IS_CURRENT, _VERSION
--
-- Prerequisites: scripts 01-02 deployed, DCIM data loaded
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE DCA_DEMO;
USE SCHEMA GOVERNANCE;
USE WAREHOUSE COMPUTE_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 1: SP_DCIM_TIME_TRAVEL
-- ═══════════════════════════════════════════════════════════════════════════
-- Reconstructs infrastructure state at any historical timestamp using
-- SCD Type 6 versioned records. Shows current vs historical vs original
-- state and computes drift from initial installation.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_DCIM_TIME_TRAVEL(p_timestamp TIMESTAMP_NTZ)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_switch_count INTEGER DEFAULT 0;
    v_rack_count INTEGER DEFAULT 0;
    v_dc_count INTEGER DEFAULT 0;
    v_total INTEGER DEFAULT 0;
BEGIN

    -- Reconstruct state at the given timestamp for all SCD6 entities
    CREATE OR REPLACE TABLE DCA_DEMO.GOVERNANCE.DCIM_HISTORICAL_SNAPSHOTS AS

    -- ═════════════════════════════════════════════════
    -- SWITCHES at point in time
    -- ═════════════════════════════════════════════════
    SELECT
        MD5('SWITCH_' || SWITCH_ID || '_' || :p_timestamp::VARCHAR) AS snapshot_id,
        :p_timestamp AS snapshot_timestamp,
        'SWITCH' AS entity_type,
        SWITCH_ID AS entity_id,
        COALESCE(MODEL, 'Unknown') AS entity_name,
        -- Current state (latest known values)
        OBJECT_CONSTRUCT(
            'rack_id', CURRENT_RACK_ID,
            'firmware_version', CURRENT_FIRMWARE_VERSION,
            'status', CURRENT_STATUS,
            'model', MODEL
        ) AS current_state,
        -- Historical state (values at the snapshot timestamp)
        OBJECT_CONSTRUCT(
            'rack_id', HISTORICAL_RACK_ID,
            'firmware_version', HISTORICAL_FIRMWARE_VERSION,
            'status', HISTORICAL_STATUS,
            'model', MODEL
        ) AS historical_state,
        -- Original state (values at first installation)
        OBJECT_CONSTRUCT(
            'rack_id', ORIGINAL_RACK_ID,
            'firmware_version', ORIGINAL_FIRMWARE_VERSION,
            'status', ORIGINAL_STATUS,
            'model', MODEL
        ) AS original_state,
        "_VERSION" AS changes_since_original,
        "_VALID_FROM" AS last_change_date,
        CURRENT_TIMESTAMP() AS created_at
    FROM RAW_DEV.SERVICENOW.SWITCHES
    WHERE "_VALID_FROM" <= :p_timestamp
      AND "_VALID_TO" > :p_timestamp

    UNION ALL

    -- ═════════════════════════════════════════════════
    -- RACKS at point in time
    -- ═════════════════════════════════════════════════
    SELECT
        MD5('RACK_' || RACK_ID || '_' || :p_timestamp::VARCHAR) AS snapshot_id,
        :p_timestamp AS snapshot_timestamp,
        'RACK' AS entity_type,
        RACK_ID AS entity_id,
        COALESCE(RACK_NAME, 'Rack-' || RACK_ID) AS entity_name,
        OBJECT_CONSTRUCT(
            'hall_id', CURRENT_HALL_ID,
            'power_allocation_kw', CURRENT_POWER_ALLOCATION_KW,
            'status', CURRENT_STATUS
        ) AS current_state,
        OBJECT_CONSTRUCT(
            'hall_id', HISTORICAL_HALL_ID,
            'power_allocation_kw', HISTORICAL_POWER_ALLOCATION_KW,
            'status', HISTORICAL_STATUS
        ) AS historical_state,
        OBJECT_CONSTRUCT(
            'hall_id', ORIGINAL_HALL_ID,
            'power_allocation_kw', ORIGINAL_POWER_ALLOCATION_KW,
            'status', ORIGINAL_STATUS
        ) AS original_state,
        "_VERSION" AS changes_since_original,
        "_VALID_FROM" AS last_change_date,
        CURRENT_TIMESTAMP() AS created_at
    FROM RAW_DEV.SERVICENOW.RACKS
    WHERE "_VALID_FROM" <= :p_timestamp
      AND "_VALID_TO" > :p_timestamp

    UNION ALL

    -- ═════════════════════════════════════════════════
    -- DATA CENTERS at point in time
    -- ═════════════════════════════════════════════════
    SELECT
        MD5('DC_' || DATA_CENTER_ID || '_' || :p_timestamp::VARCHAR) AS snapshot_id,
        :p_timestamp AS snapshot_timestamp,
        'DATA_CENTER' AS entity_type,
        DATA_CENTER_ID AS entity_id,
        COALESCE(DC_NAME, 'DC-' || DATA_CENTER_ID) AS entity_name,
        OBJECT_CONSTRUCT(
            'tier', CURRENT_TIER,
            'power_capacity_mw', CURRENT_POWER_CAPACITY_MW,
            'status', CURRENT_STATUS
        ) AS current_state,
        OBJECT_CONSTRUCT(
            'tier', HISTORICAL_TIER,
            'power_capacity_mw', HISTORICAL_POWER_CAPACITY_MW,
            'status', HISTORICAL_STATUS
        ) AS historical_state,
        OBJECT_CONSTRUCT(
            'tier', ORIGINAL_TIER,
            'power_capacity_mw', ORIGINAL_POWER_CAPACITY_MW,
            'status', ORIGINAL_STATUS
        ) AS original_state,
        "_VERSION" AS changes_since_original,
        "_VALID_FROM" AS last_change_date,
        CURRENT_TIMESTAMP() AS created_at
    FROM RAW_DEV.SERVICENOW.DATA_CENTERS
    WHERE "_VALID_FROM" <= :p_timestamp
      AND "_VALID_TO" > :p_timestamp;

    -- Count results
    SELECT COUNT(*) INTO :v_switch_count
    FROM DCA_DEMO.GOVERNANCE.DCIM_HISTORICAL_SNAPSHOTS
    WHERE entity_type = 'SWITCH';

    SELECT COUNT(*) INTO :v_rack_count
    FROM DCA_DEMO.GOVERNANCE.DCIM_HISTORICAL_SNAPSHOTS
    WHERE entity_type = 'RACK';

    SELECT COUNT(*) INTO :v_dc_count
    FROM DCA_DEMO.GOVERNANCE.DCIM_HISTORICAL_SNAPSHOTS
    WHERE entity_type = 'DATA_CENTER';

    LET v_total := :v_switch_count + :v_rack_count + :v_dc_count;

    RETURN 'Time travel snapshot at ' || :p_timestamp || ': '
        || :v_total || ' entities (Switches=' || :v_switch_count
        || ', Racks=' || :v_rack_count
        || ', Data Centers=' || :v_dc_count || ')';
END;


-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 2: SP_DCIM_CHANGE_AUDIT_TRAIL
-- ═══════════════════════════════════════════════════════════════════════════
-- Shows the full version history for any entity, detecting what changed
-- between each version using SCD6 historical vs current values.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_DCIM_CHANGE_AUDIT_TRAIL(p_entity_id VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_row_count INTEGER DEFAULT 0;
    v_entity_type VARCHAR DEFAULT '';
BEGIN

    -- Determine entity type by checking each table
    -- Check switches first (most common lookup)
    IF (EXISTS (SELECT 1 FROM RAW_DEV.SERVICENOW.SWITCHES WHERE SWITCH_ID = :p_entity_id)) THEN
        LET v_entity_type := 'SWITCH';

        CREATE OR REPLACE TABLE DCA_DEMO.GOVERNANCE.DCIM_AUDIT_TRAIL AS
        SELECT
            SWITCH_ID AS entity_id,
            'SWITCH' AS entity_type,
            "_VERSION" AS version_number,
            "_VALID_FROM" AS valid_from,
            "_VALID_TO" AS valid_to,
            "_IS_CURRENT" AS is_current,
            -- Detect what changed: compare historical (this version's value)
            -- to original (first version's value)
            OBJECT_CONSTRUCT_KEEP_NULL(
                'rack_id', CASE
                    WHEN HISTORICAL_RACK_ID != ORIGINAL_RACK_ID
                    THEN OBJECT_CONSTRUCT('from', ORIGINAL_RACK_ID, 'to', HISTORICAL_RACK_ID)
                    ELSE NULL
                END,
                'firmware_version', CASE
                    WHEN HISTORICAL_FIRMWARE_VERSION != ORIGINAL_FIRMWARE_VERSION
                    THEN OBJECT_CONSTRUCT('from', ORIGINAL_FIRMWARE_VERSION, 'to', HISTORICAL_FIRMWARE_VERSION)
                    ELSE NULL
                END,
                'status', CASE
                    WHEN HISTORICAL_STATUS != ORIGINAL_STATUS
                    THEN OBJECT_CONSTRUCT('from', ORIGINAL_STATUS, 'to', HISTORICAL_STATUS)
                    ELSE NULL
                END
            ) AS changed_attributes,
            '_SOURCE_SYSTEM' AS changed_by,
            CASE
                WHEN HISTORICAL_RACK_ID != ORIGINAL_RACK_ID THEN 'Rack relocation'
                WHEN HISTORICAL_FIRMWARE_VERSION != ORIGINAL_FIRMWARE_VERSION THEN 'Firmware upgrade'
                WHEN HISTORICAL_STATUS != ORIGINAL_STATUS THEN 'Status change'
                ELSE 'Initial record'
            END AS change_reason
        FROM RAW_DEV.SERVICENOW.SWITCHES
        WHERE SWITCH_ID = :p_entity_id
        ORDER BY "_VERSION";

    ELSEIF (EXISTS (SELECT 1 FROM RAW_DEV.SERVICENOW.RACKS WHERE RACK_ID = :p_entity_id)) THEN
        LET v_entity_type := 'RACK';

        CREATE OR REPLACE TABLE DCA_DEMO.GOVERNANCE.DCIM_AUDIT_TRAIL AS
        SELECT
            RACK_ID AS entity_id,
            'RACK' AS entity_type,
            "_VERSION" AS version_number,
            "_VALID_FROM" AS valid_from,
            "_VALID_TO" AS valid_to,
            "_IS_CURRENT" AS is_current,
            OBJECT_CONSTRUCT_KEEP_NULL(
                'hall_id', CASE
                    WHEN HISTORICAL_HALL_ID != ORIGINAL_HALL_ID
                    THEN OBJECT_CONSTRUCT('from', ORIGINAL_HALL_ID, 'to', HISTORICAL_HALL_ID)
                    ELSE NULL
                END,
                'power_allocation_kw', CASE
                    WHEN HISTORICAL_POWER_ALLOCATION_KW != ORIGINAL_POWER_ALLOCATION_KW
                    THEN OBJECT_CONSTRUCT('from', ORIGINAL_POWER_ALLOCATION_KW, 'to', HISTORICAL_POWER_ALLOCATION_KW)
                    ELSE NULL
                END,
                'status', CASE
                    WHEN HISTORICAL_STATUS != ORIGINAL_STATUS
                    THEN OBJECT_CONSTRUCT('from', ORIGINAL_STATUS, 'to', HISTORICAL_STATUS)
                    ELSE NULL
                END
            ) AS changed_attributes,
            '_SOURCE_SYSTEM' AS changed_by,
            CASE
                WHEN HISTORICAL_POWER_ALLOCATION_KW != ORIGINAL_POWER_ALLOCATION_KW THEN 'Power allocation change'
                WHEN HISTORICAL_HALL_ID != ORIGINAL_HALL_ID THEN 'Hall relocation'
                WHEN HISTORICAL_STATUS != ORIGINAL_STATUS THEN 'Status change'
                ELSE 'Initial record'
            END AS change_reason
        FROM RAW_DEV.SERVICENOW.RACKS
        WHERE RACK_ID = :p_entity_id
        ORDER BY "_VERSION";

    ELSEIF (EXISTS (SELECT 1 FROM RAW_DEV.SERVICENOW.DATA_CENTERS WHERE DATA_CENTER_ID = :p_entity_id)) THEN
        LET v_entity_type := 'DATA_CENTER';

        CREATE OR REPLACE TABLE DCA_DEMO.GOVERNANCE.DCIM_AUDIT_TRAIL AS
        SELECT
            DATA_CENTER_ID AS entity_id,
            'DATA_CENTER' AS entity_type,
            "_VERSION" AS version_number,
            "_VALID_FROM" AS valid_from,
            "_VALID_TO" AS valid_to,
            "_IS_CURRENT" AS is_current,
            OBJECT_CONSTRUCT_KEEP_NULL(
                'tier', CASE
                    WHEN HISTORICAL_TIER != ORIGINAL_TIER
                    THEN OBJECT_CONSTRUCT('from', ORIGINAL_TIER, 'to', HISTORICAL_TIER)
                    ELSE NULL
                END,
                'power_capacity_mw', CASE
                    WHEN HISTORICAL_POWER_CAPACITY_MW != ORIGINAL_POWER_CAPACITY_MW
                    THEN OBJECT_CONSTRUCT('from', ORIGINAL_POWER_CAPACITY_MW, 'to', HISTORICAL_POWER_CAPACITY_MW)
                    ELSE NULL
                END,
                'status', CASE
                    WHEN HISTORICAL_STATUS != ORIGINAL_STATUS
                    THEN OBJECT_CONSTRUCT('from', ORIGINAL_STATUS, 'to', HISTORICAL_STATUS)
                    ELSE NULL
                END
            ) AS changed_attributes,
            '_SOURCE_SYSTEM' AS changed_by,
            CASE
                WHEN HISTORICAL_TIER != ORIGINAL_TIER THEN 'Tier upgrade'
                WHEN HISTORICAL_POWER_CAPACITY_MW != ORIGINAL_POWER_CAPACITY_MW THEN 'Capacity change'
                WHEN HISTORICAL_STATUS != ORIGINAL_STATUS THEN 'Status change'
                ELSE 'Initial record'
            END AS change_reason
        FROM RAW_DEV.SERVICENOW.DATA_CENTERS
        WHERE DATA_CENTER_ID = :p_entity_id
        ORDER BY "_VERSION";

    ELSE
        RETURN 'Entity not found: ' || :p_entity_id || '. Searched SWITCHES, RACKS, DATA_CENTERS.';
    END IF;

    SELECT COUNT(*) INTO :v_row_count
    FROM DCA_DEMO.GOVERNANCE.DCIM_AUDIT_TRAIL;

    RETURN 'Audit trail for ' || :v_entity_type || ' ' || :p_entity_id
        || ': ' || :v_row_count || ' versions found.';
END;
