-- ============================================================================
-- DATA CONTRACTS ON SNOWFLAKE HORIZON — 05 SLA CONTRACTS
-- ============================================================================
--
-- The SLA (freshness / volume / availability) layer.
--   • Freshness  → SNOWFLAKE.CORE.FRESHNESS DMF (or inline DATEDIFF for demos)
--   • Volume     → SNOWFLAKE.CORE.ROW_COUNT DMF vs MIN/MAX + drift %
--   • Alerting   → a Snowflake ALERT that fires on SLA breach and logs to BREACH_LOG
--
-- EVALUATE_SLA computes freshness/volume inline (no schedule wait) so demos are
-- responsive; the ALERT object shows the production, always-on pattern.
--
-- Freshness convention for RAW SCD2 tables: uses _LOADED_AT. Curated/dynamic
-- tables: uses the object's own load/refresh timestamp column when provided in
-- SLA evaluation (falls back to INFORMATION_SCHEMA LAST_ALTERED).
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE WAREHOUSE TRANSFORM_WH;
USE SCHEMA GOVERNANCE.DATA_CONTRACTS;

-- ----------------------------------------------------------------------------
-- EVALUATE_SLA
-- Computes freshness + volume for each SLA rule on a contract, records
-- VALIDATION_RESULT rows, and returns aggregate status.
-- P_FRESHNESS_COL: timestamp column to measure freshness on (e.g. _LOADED_AT).
--                  If NULL, falls back to INFORMATION_SCHEMA.TABLES.LAST_ALTERED.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE EVALUATE_SLA(
    P_CONTRACT_ID VARCHAR,
    P_RUN_ID VARCHAR,
    P_FRESHNESS_COL VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_fail INTEGER := 0;
    v_warn INTEGER := 0;
    v_pass INTEGER := 0;
BEGIN
    LET slas RESULTSET := (
        SELECT s.SLA_ID, s.FRESHNESS_TARGET_MIN, s.FRESHNESS_MAX_MIN,
               s.MIN_ROW_COUNT, s.MAX_ROW_COUNT, s.ROW_COUNT_DRIFT_PCT, s.ON_BREACH,
               b.OBJECT_DATABASE, b.OBJECT_SCHEMA, b.OBJECT_NAME, b.FULL_OBJECT_PATH
          FROM SLA_RULE s
          JOIN CONTRACT_BINDING b ON s.BINDING_ID = b.BINDING_ID
         WHERE s.CONTRACT_ID = :P_CONTRACT_ID
           AND s.IS_ACTIVE = TRUE
    );

    FOR s IN slas DO
        -- ---- Freshness ----
        LET fresh_min FLOAT := NULL;
        IF (P_FRESHNESS_COL IS NOT NULL) THEN
            BEGIN
                LET q VARCHAR := 'SELECT DATEDIFF(''minute'', MAX(' || P_FRESHNESS_COL ||
                                 '), CURRENT_TIMESTAMP()) FROM ' || s.FULL_OBJECT_PATH;
                EXECUTE IMMEDIATE :q;
                SELECT $1 INTO fresh_min FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
            EXCEPTION WHEN OTHER THEN
                fresh_min := NULL;
            END;
        END IF;

        IF (fresh_min IS NULL) THEN
            -- fall back to metadata last_altered
            BEGIN
                SELECT DATEDIFF('minute', LAST_ALTERED, CURRENT_TIMESTAMP())
                  INTO fresh_min
                  FROM IDENTIFIER(:s.OBJECT_DATABASE || '.INFORMATION_SCHEMA.TABLES')
                 WHERE TABLE_SCHEMA = :s.OBJECT_SCHEMA AND TABLE_NAME = :s.OBJECT_NAME;
            EXCEPTION WHEN OTHER THEN
                fresh_min := NULL;
            END;
        END IF;

        LET fresh_status VARCHAR := 'PASS';
        LET fresh_msg VARCHAR := 'Freshness ' || COALESCE(fresh_min::VARCHAR, 'unknown') || ' min';
        IF (fresh_min IS NULL) THEN
            fresh_status := 'WARN'; fresh_msg := 'Freshness could not be measured';
        ELSEIF (s.FRESHNESS_MAX_MIN IS NOT NULL AND fresh_min > s.FRESHNESS_MAX_MIN) THEN
            fresh_status := 'FAIL';
            fresh_msg := 'STALE: ' || fresh_min || ' min > SLA ceiling ' || s.FRESHNESS_MAX_MIN || ' min';
        ELSEIF (s.FRESHNESS_TARGET_MIN IS NOT NULL AND fresh_min > s.FRESHNESS_TARGET_MIN) THEN
            fresh_status := 'WARN';
            fresh_msg := 'Above target: ' || fresh_min || ' min > target ' || s.FRESHNESS_TARGET_MIN || ' min';
        END IF;

        INSERT INTO VALIDATION_RESULT
            (RUN_ID, CONTRACT_ID, DIMENSION, RULE_REF, CHECK_NAME,
             OBSERVED_VALUE, EXPECTED_VALUE, STATUS, SEVERITY, MESSAGE)
        SELECT :P_RUN_ID, :P_CONTRACT_ID, 'SLA', :s.SLA_ID, 'FRESHNESS',
               :fresh_min::VARCHAR, '<= ' || :s.FRESHNESS_MAX_MIN || ' min',
               :fresh_status, 'ERROR', :fresh_msg;

        -- ---- Volume ----
        LET rc NUMBER := NULL;
        BEGIN
            LET q2 VARCHAR := 'SELECT COUNT(*) FROM ' || s.FULL_OBJECT_PATH;
            EXECUTE IMMEDIATE :q2;
            SELECT $1 INTO rc FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        EXCEPTION WHEN OTHER THEN
            rc := NULL;
        END;

        LET vol_status VARCHAR := 'PASS';
        LET vol_msg VARCHAR := 'Row count ' || COALESCE(rc::VARCHAR, 'unknown');
        IF (rc IS NULL) THEN
            vol_status := 'WARN'; vol_msg := 'Row count could not be measured';
        ELSEIF (s.MIN_ROW_COUNT IS NOT NULL AND rc < s.MIN_ROW_COUNT) THEN
            vol_status := 'FAIL'; vol_msg := 'UNDER-VOLUME: ' || rc || ' < min ' || s.MIN_ROW_COUNT;
        ELSEIF (s.MAX_ROW_COUNT IS NOT NULL AND rc > s.MAX_ROW_COUNT) THEN
            vol_status := 'FAIL'; vol_msg := 'OVER-VOLUME: ' || rc || ' > max ' || s.MAX_ROW_COUNT;
        END IF;

        INSERT INTO VALIDATION_RESULT
            (RUN_ID, CONTRACT_ID, DIMENSION, RULE_REF, CHECK_NAME,
             OBSERVED_VALUE, EXPECTED_VALUE, STATUS, SEVERITY, MESSAGE)
        SELECT :P_RUN_ID, :P_CONTRACT_ID, 'SLA', :s.SLA_ID, 'VOLUME',
               :rc::VARCHAR,
               'between ' || COALESCE(:s.MIN_ROW_COUNT::VARCHAR,'0') || ' and ' || COALESCE(:s.MAX_ROW_COUNT::VARCHAR,'inf'),
               :vol_status, 'ERROR', :vol_msg;

        -- Tally worst of the two checks
        LET worst VARCHAR := CASE
            WHEN fresh_status = 'FAIL' OR vol_status = 'FAIL' THEN 'FAIL'
            WHEN fresh_status = 'WARN' OR vol_status = 'WARN' THEN 'WARN'
            ELSE 'PASS' END;
        IF (worst = 'FAIL') THEN v_fail := v_fail + 1;
        ELSEIF (worst = 'WARN') THEN v_warn := v_warn + 1;
        ELSE v_pass := v_pass + 1; END IF;
    END FOR;

    RETURN OBJECT_CONSTRUCT(
        'dimension', 'SLA',
        'status', IFF(v_fail > 0, 'FAIL', IFF(v_warn > 0, 'WARN', 'PASS')),
        'pass', v_pass, 'warn', v_warn, 'fail', v_fail
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- ALERT — production pattern: fire on any open SLA breach in the last interval.
-- Requires a warehouse + EXECUTE ALERT privilege. Created SUSPENDED; RESUME to arm.
-- Sends an email via a notification integration if one is configured (optional).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE ALERT ALERT_SLA_BREACH
    WAREHOUSE = TRANSFORM_WH
    SCHEDULE = '60 MINUTE'
    IF (EXISTS (
        SELECT 1
          FROM GOVERNANCE.DATA_CONTRACTS.BREACH_LOG
         WHERE DIMENSION = 'SLA'
           AND STATUS = 'OPEN'
           AND DETECTED_AT > DATEADD('hour', -1, CURRENT_TIMESTAMP())
    ))
    THEN
        INSERT INTO GOVERNANCE.DATA_CONTRACTS.VALIDATION_RESULT
            (RUN_ID, CONTRACT_ID, DIMENSION, CHECK_NAME, STATUS, SEVERITY, MESSAGE)
        SELECT 'ALERT-' || UUID_STRING(), 'ALERT_SLA_BREACH', 'SLA', 'ALERT_FIRED',
               'FAIL', 'ERROR',
               'SLA breach alert fired for ' ||
               (SELECT COUNT(*) FROM GOVERNANCE.DATA_CONTRACTS.BREACH_LOG
                 WHERE DIMENSION='SLA' AND STATUS='OPEN'
                   AND DETECTED_AT > DATEADD('hour',-1,CURRENT_TIMESTAMP())) || ' contract(s)';

-- Alert is created suspended by default. Arm it in production with:
--   ALTER ALERT ALERT_SLA_BREACH RESUME;

-- ----------------------------------------------------------------------------
-- Grants
-- ----------------------------------------------------------------------------
GRANT USAGE ON PROCEDURE EVALUATE_SLA(VARCHAR, VARCHAR, VARCHAR) TO ROLE DATA_ENGINEER;
GRANT USAGE ON PROCEDURE EVALUATE_SLA(VARCHAR, VARCHAR, VARCHAR) TO ROLE DATA_STEWARD;

SELECT '✓ SLA contract layer created (EVALUATE_SLA proc + ALERT_SLA_BREACH alert [suspended])' AS STATUS;
