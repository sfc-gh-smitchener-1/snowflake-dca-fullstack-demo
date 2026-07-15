-- ============================================================================
-- DATA CONTRACTS ON SNOWFLAKE HORIZON — 03 SCHEMA CONTRACTS
-- ============================================================================
--
-- The SCHEMA enforcement layer. Snowflake does not gate DDL against a contract
-- natively, so schema contracts work by:
--   1. CAPTURE  — fingerprint the contracted shape into SCHEMA_FINGERPRINT
--                 (from INFORMATION_SCHEMA.COLUMNS at contract creation)
--   2. DETECT   — diff the live schema vs the fingerprint to find drift:
--                   • DROPPED_COLUMN   (breaking)
--                   • TYPE_CHANGED     (breaking)
--                   • NULLABILITY_TIGHTENED / RELAXED
--                   • ADDED_COLUMN     (additive — allowed if EVOLVING)
--   3. CLASSIFY — breaking vs additive per CONTRACT.SCHEMA_STABILITY
--
-- The enforcement decision (BLOCK vs ALERT) is made in 07_enforcement.sql,
-- which calls DETECT_SCHEMA_DRIFT and acts on the result.
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE WAREHOUSE TRANSFORM_WH;
USE SCHEMA GOVERNANCE.DATA_CONTRACTS;

-- ----------------------------------------------------------------------------
-- CAPTURE_SCHEMA_FINGERPRINT
-- Populate SCHEMA_FINGERPRINT for a binding from live INFORMATION_SCHEMA.
-- Call at contract creation, or after an approved version bump.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE CAPTURE_SCHEMA_FINGERPRINT(P_BINDING_ID VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_db       VARCHAR;
    v_schema   VARCHAR;
    v_table    VARCHAR;
    v_cid      VARCHAR;
    v_ver      VARCHAR;
    v_count    INTEGER;
BEGIN
    SELECT OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME, CONTRACT_ID, CONTRACT_VERSION
      INTO v_db, v_schema, v_table, v_cid, v_ver
      FROM CONTRACT_BINDING
     WHERE BINDING_ID = :P_BINDING_ID;

    -- Clear any prior fingerprint for this binding
    DELETE FROM SCHEMA_FINGERPRINT WHERE BINDING_ID = :P_BINDING_ID;

    -- Capture from the object's INFORMATION_SCHEMA (per-database view)
    EXECUTE IMMEDIATE
        'INSERT INTO GOVERNANCE.DATA_CONTRACTS.SCHEMA_FINGERPRINT ' ||
        '(FINGERPRINT_ID, CONTRACT_ID, CONTRACT_VERSION, BINDING_ID, COLUMN_NAME, ' ||
        ' ORDINAL_POSITION, DATA_TYPE, IS_NULLABLE, NUMERIC_PRECISION, NUMERIC_SCALE, ' ||
        ' CHARACTER_MAX_LENGTH, IS_REQUIRED_BY_CONTRACT) ' ||
        'SELECT ''FP-'' || ''' || :P_BINDING_ID || ''' || ''-'' || COLUMN_NAME, ' ||
        '   ''' || v_cid || ''', ''' || v_ver || ''', ''' || :P_BINDING_ID || ''', ' ||
        '   COLUMN_NAME, ORDINAL_POSITION, DATA_TYPE, ' ||
        '   IFF(IS_NULLABLE = ''YES'', TRUE, FALSE), ' ||
        '   NUMERIC_PRECISION, NUMERIC_SCALE, CHARACTER_MAXIMUM_LENGTH, ' ||
        '   IFF(COLUMN_NAME NOT LIKE ''\\_%'' ESCAPE ''\\'', TRUE, FALSE) ' ||
        'FROM ' || v_db || '.INFORMATION_SCHEMA.COLUMNS ' ||
        'WHERE TABLE_SCHEMA = ''' || v_schema || ''' AND TABLE_NAME = ''' || v_table || '''';

    SELECT COUNT(*) INTO v_count FROM SCHEMA_FINGERPRINT WHERE BINDING_ID = :P_BINDING_ID;
    RETURN 'Captured ' || v_count || ' columns for binding ' || :P_BINDING_ID
        || ' (' || v_db || '.' || v_schema || '.' || v_table || ')';
END;
$$;

-- ----------------------------------------------------------------------------
-- DETECT_SCHEMA_DRIFT
-- Diff the live schema against the stored fingerprint. Returns a VARIANT with
-- classified changes. Does NOT enforce — enforcement lives in 07.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE DETECT_SCHEMA_DRIFT(P_BINDING_ID VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_db       VARCHAR;
    v_schema   VARCHAR;
    v_table    VARCHAR;
    v_stability VARCHAR;
    res        VARIANT;
BEGIN
    SELECT b.OBJECT_DATABASE, b.OBJECT_SCHEMA, b.OBJECT_NAME, c.SCHEMA_STABILITY
      INTO v_db, v_schema, v_table, v_stability
      FROM CONTRACT_BINDING b
      JOIN CONTRACT c
        ON b.CONTRACT_ID = c.CONTRACT_ID AND b.CONTRACT_VERSION = c.CONTRACT_VERSION
     WHERE b.BINDING_ID = :P_BINDING_ID;

    -- Build a live-schema CTE from INFORMATION_SCHEMA and diff against fingerprint.
    LET drift RESULTSET := (EXECUTE IMMEDIATE
        'WITH live AS ( ' ||
        '  SELECT COLUMN_NAME, ORDINAL_POSITION, DATA_TYPE, ' ||
        '         IFF(IS_NULLABLE = ''YES'', TRUE, FALSE) AS IS_NULLABLE ' ||
        '  FROM ' || v_db || '.INFORMATION_SCHEMA.COLUMNS ' ||
        '  WHERE TABLE_SCHEMA = ''' || v_schema || ''' AND TABLE_NAME = ''' || v_table || ''' ), ' ||
        'contract AS ( ' ||
        '  SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, IS_REQUIRED_BY_CONTRACT ' ||
        '  FROM GOVERNANCE.DATA_CONTRACTS.SCHEMA_FINGERPRINT ' ||
        '  WHERE BINDING_ID = ''' || :P_BINDING_ID || ''' ) ' ||
        'SELECT ' ||
        '  contract.COLUMN_NAME AS contract_col, live.COLUMN_NAME AS live_col, ' ||
        '  contract.DATA_TYPE AS contract_type, live.DATA_TYPE AS live_type, ' ||
        '  contract.IS_NULLABLE AS contract_nullable, live.IS_NULLABLE AS live_nullable, ' ||
        '  contract.IS_REQUIRED_BY_CONTRACT AS required, ' ||
        '  CASE ' ||
        '    WHEN live.COLUMN_NAME IS NULL AND contract.IS_REQUIRED_BY_CONTRACT THEN ''DROPPED_REQUIRED_COLUMN'' ' ||
        '    WHEN live.COLUMN_NAME IS NULL THEN ''DROPPED_OPTIONAL_COLUMN'' ' ||
        '    WHEN contract.COLUMN_NAME IS NULL THEN ''ADDED_COLUMN'' ' ||
        '    WHEN contract.DATA_TYPE != live.DATA_TYPE THEN ''TYPE_CHANGED'' ' ||
        '    WHEN contract.IS_NULLABLE = TRUE AND live.IS_NULLABLE = FALSE THEN ''NULLABILITY_TIGHTENED'' ' ||
        '    WHEN contract.IS_NULLABLE = FALSE AND live.IS_NULLABLE = TRUE THEN ''NULLABILITY_RELAXED'' ' ||
        '    ELSE ''UNCHANGED'' ' ||
        '  END AS change_type ' ||
        'FROM contract FULL OUTER JOIN live ON contract.COLUMN_NAME = live.COLUMN_NAME');

    -- Aggregate the diff into a classified summary
    LET agg RESULTSET := (
        SELECT
            OBJECT_CONSTRUCT(
                'binding_id', :P_BINDING_ID,
                'object', :v_db || '.' || :v_schema || '.' || :v_table,
                'schema_stability', :v_stability,
                'checked_at', CURRENT_TIMESTAMP()::VARCHAR,
                'dropped_required', COUNT_IF(change_type = 'DROPPED_REQUIRED_COLUMN'),
                'dropped_optional', COUNT_IF(change_type = 'DROPPED_OPTIONAL_COLUMN'),
                'type_changed',     COUNT_IF(change_type = 'TYPE_CHANGED'),
                'nullability_tightened', COUNT_IF(change_type = 'NULLABILITY_TIGHTENED'),
                'nullability_relaxed',   COUNT_IF(change_type = 'NULLABILITY_RELAXED'),
                'added_columns',    COUNT_IF(change_type = 'ADDED_COLUMN'),
                'breaking_changes', COUNT_IF(change_type IN ('DROPPED_REQUIRED_COLUMN','TYPE_CHANGED','NULLABILITY_TIGHTENED')),
                'is_breaking',      COUNT_IF(change_type IN ('DROPPED_REQUIRED_COLUMN','TYPE_CHANGED','NULLABILITY_TIGHTENED')) > 0,
                'changes', ARRAY_AGG(
                    IFF(change_type != 'UNCHANGED',
                        OBJECT_CONSTRUCT(
                            'column', COALESCE(contract_col, live_col),
                            'change', change_type,
                            'contract_type', contract_type,
                            'live_type', live_type
                        ), NULL)
                )
            ) AS drift_summary
        FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
    );

    FOR row_var IN agg DO
        res := row_var.drift_summary;
    END FOR;

    RETURN res;
END;
$$;

-- ----------------------------------------------------------------------------
-- Grants
-- ----------------------------------------------------------------------------
GRANT USAGE ON PROCEDURE CAPTURE_SCHEMA_FINGERPRINT(VARCHAR) TO ROLE DATA_ENGINEER;
GRANT USAGE ON PROCEDURE DETECT_SCHEMA_DRIFT(VARCHAR) TO ROLE DATA_ENGINEER;
GRANT USAGE ON PROCEDURE CAPTURE_SCHEMA_FINGERPRINT(VARCHAR) TO ROLE DATA_STEWARD;
GRANT USAGE ON PROCEDURE DETECT_SCHEMA_DRIFT(VARCHAR) TO ROLE DATA_STEWARD;

SELECT '✓ Schema contract procedures created (CAPTURE_SCHEMA_FINGERPRINT, DETECT_SCHEMA_DRIFT)' AS STATUS;
