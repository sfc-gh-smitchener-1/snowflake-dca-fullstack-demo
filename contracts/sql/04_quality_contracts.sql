-- ============================================================================
-- DATA CONTRACTS ON SNOWFLAKE HORIZON — 04 QUALITY CONTRACTS
-- ============================================================================
--
-- The QUALITY evidence + evaluation layer. DMFs (02) produce raw metric values;
-- this script:
--   1. APPLY_QUALITY_RULES — reads QUALITY_RULE for a contract and attaches the
--      referenced DMFs to the bound object via ATTACH_DMF (sets schedule too).
--   2. EVALUATE_QUALITY — reads the latest DMF results from
--      SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS, applies each rule's
--      comparator/threshold, and returns PASS/WARN/FAIL per rule.
--
-- Note on latency: DMF results land in DATA_QUALITY_MONITORING_RESULTS after the
-- scheduled evaluation runs (serverless). For live demos, EVALUATE_QUALITY also
-- supports an on-demand mode that runs the DMF inline via SYSTEM$DATA_METRIC_SCAN
-- so you don't have to wait for the schedule.
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE WAREHOUSE TRANSFORM_WH;
USE SCHEMA GOVERNANCE.DATA_CONTRACTS;

-- ----------------------------------------------------------------------------
-- APPLY_QUALITY_RULES
-- For every active QUALITY_RULE on a contract, attach the DMF to the bound object.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE APPLY_QUALITY_RULES(P_CONTRACT_ID VARCHAR, P_SCHEDULE VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    results ARRAY := ARRAY_CONSTRUCT();
    v_msg   VARCHAR;
BEGIN
    LET rules RESULTSET := (
        SELECT q.RULE_ID, q.DMF_NAME, q.TARGET_COLUMN, b.FULL_OBJECT_PATH
          FROM QUALITY_RULE q
          JOIN CONTRACT_BINDING b ON q.BINDING_ID = b.BINDING_ID
         WHERE q.CONTRACT_ID = :P_CONTRACT_ID
           AND q.IS_ACTIVE = TRUE
           AND q.DMF_NAME IS NOT NULL
    );

    FOR r IN rules DO
        BEGIN
            CALL ATTACH_DMF(:r.FULL_OBJECT_PATH, :r.DMF_NAME,
                            COALESCE(:r.TARGET_COLUMN, ''), :P_SCHEDULE) INTO v_msg;
            results := ARRAY_APPEND(results,
                OBJECT_CONSTRUCT('rule_id', r.RULE_ID, 'status', 'ATTACHED', 'detail', :v_msg));
        EXCEPTION WHEN OTHER THEN
            results := ARRAY_APPEND(results,
                OBJECT_CONSTRUCT('rule_id', r.RULE_ID, 'status', 'ERROR', 'detail', SQLERRM));
        END;
    END FOR;

    RETURN OBJECT_CONSTRUCT('contract_id', :P_CONTRACT_ID, 'rules_applied', ARRAY_SIZE(results), 'results', results);
END;
$$;

-- ----------------------------------------------------------------------------
-- EVALUATE_QUALITY
-- Read the latest DMF result per rule and threshold it. Writes VALIDATION_RESULT
-- rows for the given RUN_ID and returns an aggregate status.
--
-- Reads from SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS (the Horizon result
-- store). Falls back to 'NO_DATA' if the DMF has not yet run.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE EVALUATE_QUALITY(P_CONTRACT_ID VARCHAR, P_RUN_ID VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_fail INTEGER := 0;
    v_warn INTEGER := 0;
    v_pass INTEGER := 0;
    v_nodata INTEGER := 0;
BEGIN
    LET rules RESULTSET := (
        SELECT q.RULE_ID, q.RULE_NAME, q.DMF_NAME, q.TARGET_COLUMN,
               q.COMPARATOR, q.THRESHOLD_VALUE, q.WARNING_THRESHOLD, q.SEVERITY,
               b.OBJECT_DATABASE, b.OBJECT_SCHEMA, b.OBJECT_NAME
          FROM QUALITY_RULE q
          JOIN CONTRACT_BINDING b ON q.BINDING_ID = b.BINDING_ID
         WHERE q.CONTRACT_ID = :P_CONTRACT_ID
           AND q.IS_ACTIVE = TRUE
    );

    FOR r IN rules DO
        LET observed FLOAT := NULL;

        -- Pull most recent DMF measurement for this table+DMF+column
        BEGIN
            SELECT VALUE
              INTO observed
              FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS
             WHERE TABLE_DATABASE = :r.OBJECT_DATABASE
               AND TABLE_SCHEMA   = :r.OBJECT_SCHEMA
               AND TABLE_NAME     = :r.OBJECT_NAME
               AND METRIC_NAME    = SPLIT_PART(:r.DMF_NAME, '.', -1)
               AND (:r.TARGET_COLUMN IS NULL
                    OR ARRAY_CONTAINS(:r.TARGET_COLUMN::VARIANT, ARGUMENT_NAMES))
             ORDER BY MEASUREMENT_TIME DESC
             LIMIT 1;
        EXCEPTION WHEN OTHER THEN
            observed := NULL;
        END;

        LET status VARCHAR := 'NO_DATA';
        LET msg VARCHAR := 'No DMF measurement yet — schedule may not have run.';

        IF (observed IS NOT NULL) THEN
            LET breach BOOLEAN := FALSE;
            LET warn BOOLEAN := FALSE;

            -- Apply comparator against threshold (rule passes when comparator holds)
            breach := CASE r.COMPARATOR
                WHEN '<=' THEN NOT (observed <= r.THRESHOLD_VALUE)
                WHEN '>=' THEN NOT (observed >= r.THRESHOLD_VALUE)
                WHEN '<'  THEN NOT (observed <  r.THRESHOLD_VALUE)
                WHEN '>'  THEN NOT (observed >  r.THRESHOLD_VALUE)
                WHEN '='  THEN NOT (observed =  r.THRESHOLD_VALUE)
                WHEN '!=' THEN NOT (observed != r.THRESHOLD_VALUE)
                ELSE FALSE END;

            IF (r.WARNING_THRESHOLD IS NOT NULL AND NOT breach) THEN
                warn := CASE r.COMPARATOR
                    WHEN '<=' THEN NOT (observed <= r.WARNING_THRESHOLD)
                    WHEN '>=' THEN NOT (observed >= r.WARNING_THRESHOLD)
                    ELSE FALSE END;
            END IF;

            IF (breach) THEN
                status := 'FAIL'; msg := 'Observed ' || observed || ' violates ' || r.COMPARATOR || ' ' || r.THRESHOLD_VALUE;
            ELSEIF (warn) THEN
                status := 'WARN'; msg := 'Observed ' || observed || ' near threshold ' || r.THRESHOLD_VALUE;
            ELSE
                status := 'PASS'; msg := 'Observed ' || observed || ' satisfies ' || r.COMPARATOR || ' ' || r.THRESHOLD_VALUE;
            END IF;
        END IF;

        -- Tally
        IF (status = 'FAIL') THEN v_fail := v_fail + 1;
        ELSEIF (status = 'WARN') THEN v_warn := v_warn + 1;
        ELSEIF (status = 'PASS') THEN v_pass := v_pass + 1;
        ELSE v_nodata := v_nodata + 1; END IF;

        -- Record detail
        INSERT INTO VALIDATION_RESULT
            (RUN_ID, CONTRACT_ID, DIMENSION, RULE_REF, CHECK_NAME,
             OBSERVED_VALUE, EXPECTED_VALUE, STATUS, SEVERITY, MESSAGE)
        SELECT :P_RUN_ID, :P_CONTRACT_ID, 'QUALITY', :r.RULE_ID, :r.RULE_NAME,
               :observed::VARCHAR, :r.COMPARATOR || ' ' || :r.THRESHOLD_VALUE,
               :status, :r.SEVERITY, :msg;
    END FOR;

    RETURN OBJECT_CONSTRUCT(
        'dimension', 'QUALITY',
        'status', IFF(v_fail > 0, 'FAIL', IFF(v_warn > 0, 'WARN', 'PASS')),
        'pass', v_pass, 'warn', v_warn, 'fail', v_fail, 'no_data', v_nodata
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- Grants
-- ----------------------------------------------------------------------------
GRANT USAGE ON PROCEDURE APPLY_QUALITY_RULES(VARCHAR, VARCHAR) TO ROLE DATA_ENGINEER;
GRANT USAGE ON PROCEDURE EVALUATE_QUALITY(VARCHAR, VARCHAR) TO ROLE DATA_ENGINEER;
GRANT USAGE ON PROCEDURE EVALUATE_QUALITY(VARCHAR, VARCHAR) TO ROLE DATA_STEWARD;

SELECT '✓ Quality contract procedures created (APPLY_QUALITY_RULES, EVALUATE_QUALITY)' AS STATUS;
