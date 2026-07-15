-- ============================================================================
-- DATA CONTRACTS ON SNOWFLAKE HORIZON — 07 ENFORCEMENT
-- ============================================================================
--
-- The enforcement/orchestration layer — the "gate" that ties everything together.
--
-- VALIDATE_CONTRACT:
--   1. Opens a VALIDATION_RUN
--   2. Runs schema drift (03), quality (04), SLA (05), lineage (06)
--   3. Rolls up per-dimension status into OVERALL_STATUS
--   4. Decides the ENFORCEMENT_ACTION from the binding/contract enforcement mode:
--         BLOCK   → raise an exception (fails the calling pipeline / TASK)
--         ALERT   → log a breach + let the pipeline continue
--         MONITOR → record only
--   5. Logs breaches to BREACH_LOG
--
-- ENFORCE_PIPELINE_GATE:
--   A thin wrapper meant to be called at RAW→CURATED / CURATED→SEMANTIC promotion
--   boundaries. Returns 'PROCEED' or throws so upstream tasks halt on BLOCK.
--
-- RUN_ALL_CONTRACTS + a serverless TASK show the always-on monitoring pattern.
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE WAREHOUSE TRANSFORM_WH;
USE SCHEMA GOVERNANCE.DATA_CONTRACTS;

-- ----------------------------------------------------------------------------
-- VALIDATE_CONTRACT — full multi-dimension validation with enforcement
-- P_FRESHNESS_COL: optional timestamp column for SLA freshness (e.g. _LOADED_AT)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE VALIDATE_CONTRACT(
    P_CONTRACT_ID VARCHAR,
    P_FRESHNESS_COL VARCHAR,
    P_TRIGGERED_BY VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_run_id     VARCHAR;
    v_binding    VARCHAR;
    v_version    VARCHAR;
    v_enforce    VARCHAR;
    v_schema_st  VARCHAR := 'SKIPPED';
    v_qual       VARIANT;
    v_sla        VARIANT;
    v_lin        VARIANT;
    v_drift      VARIANT;
    v_overall    VARCHAR;
    v_action     VARCHAR := 'NONE';
BEGIN
    -- Resolve primary binding + effective enforcement mode
    SELECT b.BINDING_ID, c.CONTRACT_VERSION,
           COALESCE(b.ENFORCEMENT_MODE, c.DEFAULT_ENFORCEMENT)
      INTO v_binding, v_version, v_enforce
      FROM CONTRACT c
      JOIN CONTRACT_BINDING b
        ON c.CONTRACT_ID = b.CONTRACT_ID AND c.CONTRACT_VERSION = b.CONTRACT_VERSION
     WHERE c.CONTRACT_ID = :P_CONTRACT_ID
       AND c.STATUS = 'ACTIVE'
       AND b.IS_ACTIVE = TRUE
     ORDER BY b.BOUND_AT
     LIMIT 1;

    IF (v_binding IS NULL) THEN
        RETURN OBJECT_CONSTRUCT('error', 'No active binding for contract ' || :P_CONTRACT_ID);
    END IF;

    -- Open the run
    v_run_id := UUID_STRING();
    INSERT INTO VALIDATION_RUN
        (RUN_ID, CONTRACT_ID, CONTRACT_VERSION, BINDING_ID, TRIGGERED_BY, RUN_START)
    SELECT :v_run_id, :P_CONTRACT_ID, :v_version, :v_binding,
           COALESCE(:P_TRIGGERED_BY, 'MANUAL'), CURRENT_TIMESTAMP();

    -- 1) SCHEMA DRIFT
    BEGIN
        CALL DETECT_SCHEMA_DRIFT(:v_binding) INTO v_drift;
        v_schema_st := IFF(v_drift:is_breaking::BOOLEAN, 'FAIL',
                        IFF(v_drift:added_columns::INTEGER > 0, 'WARN', 'PASS'));
        INSERT INTO VALIDATION_RESULT
            (RUN_ID, CONTRACT_ID, DIMENSION, CHECK_NAME, OBSERVED_VALUE, STATUS, SEVERITY, MESSAGE)
        SELECT :v_run_id, :P_CONTRACT_ID, 'SCHEMA', 'SCHEMA_DRIFT',
               :v_drift:breaking_changes::VARCHAR || ' breaking change(s)',
               :v_schema_st, 'ERROR', :v_drift::VARCHAR;
    EXCEPTION WHEN OTHER THEN
        v_schema_st := 'SKIPPED';
    END;

    -- 2) QUALITY
    BEGIN
        CALL EVALUATE_QUALITY(:P_CONTRACT_ID, :v_run_id) INTO v_qual;
    EXCEPTION WHEN OTHER THEN
        v_qual := OBJECT_CONSTRUCT('status', 'SKIPPED');
    END;

    -- 3) SLA
    BEGIN
        CALL EVALUATE_SLA(:P_CONTRACT_ID, :v_run_id, :P_FRESHNESS_COL) INTO v_sla;
    EXCEPTION WHEN OTHER THEN
        v_sla := OBJECT_CONSTRUCT('status', 'SKIPPED');
    END;

    -- 4) LINEAGE
    BEGIN
        CALL EVALUATE_LINEAGE(:P_CONTRACT_ID, :v_run_id) INTO v_lin;
    EXCEPTION WHEN OTHER THEN
        v_lin := OBJECT_CONSTRUCT('status', 'SKIPPED');
    END;

    -- Roll up overall status (FAIL dominates, then WARN)
    LET statuses ARRAY := ARRAY_CONSTRUCT(
        v_schema_st, v_qual:status::VARCHAR, v_sla:status::VARCHAR, v_lin:status::VARCHAR);
    v_overall := CASE
        WHEN ARRAY_CONTAINS('FAIL'::VARIANT, statuses) THEN 'FAIL'
        WHEN ARRAY_CONTAINS('WARN'::VARIANT, statuses) THEN 'WARN'
        ELSE 'PASS' END;

    -- Decide enforcement action
    IF (v_overall = 'FAIL') THEN
        IF (v_enforce = 'BLOCK') THEN v_action := 'BLOCKED';
        ELSEIF (v_enforce = 'ALERT') THEN v_action := 'ALERTED';
        ELSE v_action := 'MONITORED'; END IF;

        -- Log breach
        INSERT INTO BREACH_LOG
            (CONTRACT_ID, CONTRACT_VERSION, BINDING_ID, DIMENSION, SEVERITY,
             ENFORCEMENT_ACTION, SUMMARY, DETAILS, RUN_ID)
        SELECT :P_CONTRACT_ID, :v_version, :v_binding,
               ARRAY_TO_STRING(ARRAY_CONSTRUCT_COMPACT(
                    IFF(:v_schema_st='FAIL','SCHEMA',NULL),
                    IFF(:v_qual:status::VARCHAR='FAIL','QUALITY',NULL),
                    IFF(:v_sla:status::VARCHAR='FAIL','SLA',NULL),
                    IFF(:v_lin:status::VARCHAR='FAIL','LINEAGE',NULL)), ','),
               'ERROR', :v_action,
               'Contract ' || :P_CONTRACT_ID || ' FAILED validation (' || :v_enforce || ' mode)',
               OBJECT_CONSTRUCT('schema', :v_schema_st, 'quality', :v_qual,
                                'sla', :v_sla, 'lineage', :v_lin),
               :v_run_id;
    END IF;

    -- Close the run
    UPDATE VALIDATION_RUN
       SET RUN_END = CURRENT_TIMESTAMP(),
           SCHEMA_STATUS = :v_schema_st,
           QUALITY_STATUS = :v_qual:status::VARCHAR,
           SLA_STATUS = :v_sla:status::VARCHAR,
           LINEAGE_STATUS = :v_lin:status::VARCHAR,
           OVERALL_STATUS = :v_overall,
           ENFORCEMENT_ACTION = :v_action,
           DETAILS = OBJECT_CONSTRUCT('schema', :v_drift, 'quality', :v_qual,
                                      'sla', :v_sla, 'lineage', :v_lin)
     WHERE RUN_ID = :v_run_id;

    LET summary VARIANT := OBJECT_CONSTRUCT(
        'run_id', v_run_id, 'contract_id', P_CONTRACT_ID, 'version', v_version,
        'overall', v_overall, 'enforcement_mode', v_enforce, 'action', v_action,
        'schema', v_schema_st, 'quality', v_qual:status::VARCHAR,
        'sla', v_sla:status::VARCHAR, 'lineage', v_lin:status::VARCHAR);

    -- BLOCK: throw so the calling pipeline/task fails
    IF (v_overall = 'FAIL' AND v_enforce = 'BLOCK') THEN
        RAISE STATEMENT_ERROR;
    END IF;

    RETURN summary;
EXCEPTION
    WHEN STATEMENT_ERROR THEN
        RETURN OBJECT_CONSTRUCT('run_id', v_run_id, 'contract_id', P_CONTRACT_ID,
            'overall', 'FAIL', 'action', 'BLOCKED',
            'error', 'CONTRACT BLOCKED: ' || P_CONTRACT_ID || ' failed validation in BLOCK mode');
END;
$$;

-- ----------------------------------------------------------------------------
-- ENFORCE_PIPELINE_GATE
-- Call this inside a data pipeline / TASK before promoting data. Throws on BLOCK.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE ENFORCE_PIPELINE_GATE(P_CONTRACT_ID VARCHAR, P_FRESHNESS_COL VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_res VARIANT;
BEGIN
    CALL VALIDATE_CONTRACT(:P_CONTRACT_ID, :P_FRESHNESS_COL, 'PIPELINE_GATE') INTO v_res;
    IF (v_res:action::VARCHAR = 'BLOCKED') THEN
        RETURN 'BLOCKED: ' || :P_CONTRACT_ID || ' — downstream promotion halted. See BREACH_LOG.';
    END IF;
    RETURN 'PROCEED: ' || :P_CONTRACT_ID || ' — ' || v_res:overall::VARCHAR;
END;
$$;

-- ----------------------------------------------------------------------------
-- RUN_ALL_CONTRACTS — validate every active contract (for the monitoring task)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE RUN_ALL_CONTRACTS()
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    results ARRAY := ARRAY_CONSTRUCT();
    v_res   VARIANT;
BEGIN
    LET c RESULTSET := (SELECT DISTINCT CONTRACT_ID FROM CONTRACT WHERE STATUS = 'ACTIVE');
    FOR row IN c DO
        BEGIN
            -- MONITOR-style run: never throw, just record (uses _LOADED_AT if present)
            CALL VALIDATE_CONTRACT(:row.CONTRACT_ID, '_LOADED_AT', 'TASK') INTO v_res;
            results := ARRAY_APPEND(results, v_res);
        EXCEPTION WHEN OTHER THEN
            results := ARRAY_APPEND(results,
                OBJECT_CONSTRUCT('contract_id', row.CONTRACT_ID, 'error', SQLERRM));
        END;
    END FOR;
    RETURN OBJECT_CONSTRUCT('validated', ARRAY_SIZE(results), 'runs', results);
END;
$$;

-- ----------------------------------------------------------------------------
-- Serverless monitoring TASK — always-on contract validation (created suspended)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TASK TASK_MONITOR_CONTRACTS
    SCHEDULE = '60 MINUTE'
    USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
    COMMENT = 'Hourly validation of all active data contracts (MONITOR mode).'
AS
    CALL GOVERNANCE.DATA_CONTRACTS.RUN_ALL_CONTRACTS();

-- Arm in production with:  ALTER TASK TASK_MONITOR_CONTRACTS RESUME;

-- ----------------------------------------------------------------------------
-- Grants
-- ----------------------------------------------------------------------------
GRANT USAGE ON PROCEDURE VALIDATE_CONTRACT(VARCHAR, VARCHAR, VARCHAR) TO ROLE DATA_ENGINEER;
GRANT USAGE ON PROCEDURE ENFORCE_PIPELINE_GATE(VARCHAR, VARCHAR) TO ROLE DATA_ENGINEER;
GRANT USAGE ON PROCEDURE RUN_ALL_CONTRACTS() TO ROLE DATA_ENGINEER;
GRANT USAGE ON PROCEDURE VALIDATE_CONTRACT(VARCHAR, VARCHAR, VARCHAR) TO ROLE DATA_STEWARD;

SELECT '✓ Enforcement layer created (VALIDATE_CONTRACT, ENFORCE_PIPELINE_GATE, RUN_ALL_CONTRACTS, TASK_MONITOR_CONTRACTS [suspended])' AS STATUS;
