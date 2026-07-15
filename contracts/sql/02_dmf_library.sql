-- ============================================================================
-- DATA CONTRACTS ON SNOWFLAKE HORIZON — 02 DMF LIBRARY
-- ============================================================================
--
-- The QUALITY enforcement layer. Data Metric Functions (DMFs) are the Horizon
-- primitive that evaluates data-quality metrics on a schedule and writes results
-- to SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS.
--
-- This script provides:
--   A. A catalog of SYSTEM DMFs used by contracts (reference only — they already exist)
--   B. CUSTOM DMFs implementing Rappi/enterprise-specific business rules
--   C. Helper procedures to ATTACH a DMF to a contracted object + set schedule
--
-- Prerequisites (run once as ACCOUNTADMIN — see 00_setup.sql):
--   GRANT EXECUTE DATA METRIC FUNCTION ON ACCOUNT TO ROLE DATA_ADMIN;
--   GRANT DATABASE ROLE SNOWFLAKE.DATA_METRIC_USER TO ROLE DATA_ADMIN;
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE WAREHOUSE TRANSFORM_WH;
USE SCHEMA GOVERNANCE.DATA_CONTRACTS;

-- ============================================================================
-- A. SYSTEM DMF CATALOG (reference)
-- ----------------------------------------------------------------------------
-- These ship with Snowflake and are used directly in QUALITY_RULE.DMF_NAME:
--   SNOWFLAKE.CORE.NULL_COUNT(col)        — count of NULLs
--   SNOWFLAKE.CORE.NULL_PERCENT(col)      — % NULL
--   SNOWFLAKE.CORE.DUPLICATE_COUNT(col)   — count of duplicate values
--   SNOWFLAKE.CORE.UNIQUE_COUNT(col)      — distinct values
--   SNOWFLAKE.CORE.ROW_COUNT()            — table row count (volume SLA)
--   SNOWFLAKE.CORE.FRESHNESS(ts_col)      — seconds since max(ts_col) (freshness SLA)
--   SNOWFLAKE.CORE.BLANK_COUNT(col)       — count of blank strings
--   SNOWFLAKE.CORE.AVG / MIN / MAX / STDDEV(col)
--   SNOWFLAKE.CORE.ACCEPTED_VALUES(...)   — set membership
-- ============================================================================

-- ============================================================================
-- B. CUSTOM DMFs — enterprise business rules
-- ----------------------------------------------------------------------------
-- A DMF takes a TABLE argument with typed columns and returns a NUMBER metric.
-- The scheduler passes the bound table/columns automatically.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- DMF_NEGATIVE_AMOUNT_COUNT — count of rows where a monetary amount is negative
-- Use on: transaction / revenue / invoice amounts that must be >= 0
-- ----------------------------------------------------------------------------
CREATE OR REPLACE DATA METRIC FUNCTION DMF_NEGATIVE_AMOUNT_COUNT(
    ARG_T TABLE(ARG_C NUMBER)
)
RETURNS NUMBER
COMMENT = 'Contract quality DMF: number of rows where the monitored amount column is negative.'
AS
$$
    SELECT COUNT_IF(ARG_C < 0) FROM ARG_T
$$;

-- ----------------------------------------------------------------------------
-- DMF_FUTURE_DATE_COUNT — count of rows with a timestamp in the future
-- Use on: created_at / order_date columns that must not be future-dated
-- ----------------------------------------------------------------------------
CREATE OR REPLACE DATA METRIC FUNCTION DMF_FUTURE_DATE_COUNT(
    ARG_T TABLE(ARG_C TIMESTAMP_NTZ)
)
RETURNS NUMBER
COMMENT = 'Contract quality DMF: number of rows whose monitored timestamp is in the future.'
AS
$$
    SELECT COUNT_IF(ARG_C > CURRENT_TIMESTAMP()) FROM ARG_T
$$;

-- ----------------------------------------------------------------------------
-- DMF_INVALID_EMAIL_COUNT — count of syntactically invalid emails
-- Use on: customer/contact email columns
-- ----------------------------------------------------------------------------
CREATE OR REPLACE DATA METRIC FUNCTION DMF_INVALID_EMAIL_COUNT(
    ARG_T TABLE(ARG_C VARCHAR)
)
RETURNS NUMBER
COMMENT = 'Contract quality DMF: number of non-null email values failing a basic RFC-ish pattern.'
AS
$$
    SELECT COUNT_IF(
        ARG_C IS NOT NULL
        AND NOT RLIKE(ARG_C, '^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}$')
    )
    FROM ARG_T
$$;

-- ----------------------------------------------------------------------------
-- DMF_ORPHAN_KEY_COUNT — count of NULL/blank business keys
-- Use on: primary/business key columns that must always be populated
-- ----------------------------------------------------------------------------
CREATE OR REPLACE DATA METRIC FUNCTION DMF_ORPHAN_KEY_COUNT(
    ARG_T TABLE(ARG_C VARCHAR)
)
RETURNS NUMBER
COMMENT = 'Contract quality DMF: number of rows with a NULL or blank business key.'
AS
$$
    SELECT COUNT_IF(ARG_C IS NULL OR TRIM(ARG_C) = '') FROM ARG_T
$$;

-- ----------------------------------------------------------------------------
-- DMF_STALE_SCD_COUNT — SCD Type 2 rows marked current but with an end date
-- Use on: RAW SCD2 tables using _IS_CURRENT / _VALID_TO convention
-- Two-column DMF (flag + end-timestamp)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE DATA METRIC FUNCTION DMF_SCD2_INTEGRITY_COUNT(
    ARG_T TABLE(ARG_IS_CURRENT BOOLEAN, ARG_VALID_TO TIMESTAMP_NTZ)
)
RETURNS NUMBER
COMMENT = 'Contract quality DMF: SCD2 integrity — rows flagged current but already end-dated (or vice versa).'
AS
$$
    SELECT COUNT_IF(
        (ARG_IS_CURRENT = TRUE  AND ARG_VALID_TO < CURRENT_TIMESTAMP())
     OR (ARG_IS_CURRENT = FALSE AND ARG_VALID_TO >= CURRENT_TIMESTAMP())
    )
    FROM ARG_T
$$;

-- ============================================================================
-- C. HELPER PROCEDURE — attach a DMF to a contracted object with a schedule
-- ----------------------------------------------------------------------------
-- Wraps the two Horizon DDL statements needed to make a DMF run on a schedule:
--   1) ALTER TABLE ... SET DATA_METRIC_SCHEDULE = ...
--   2) ALTER TABLE ... ADD DATA METRIC FUNCTION ... ON (col)
-- Idempotent-ish: drops the DMF association first if present.
-- ============================================================================
CREATE OR REPLACE PROCEDURE ATTACH_DMF(
    P_FULL_TABLE   VARCHAR,   -- e.g. RAW_DEV.SALESFORCE.ACCOUNT
    P_DMF_NAME     VARCHAR,   -- e.g. SNOWFLAKE.CORE.NULL_COUNT
    P_ON_COLUMNS   VARCHAR,   -- e.g. "EMAIL" or "IS_CURRENT, VALID_TO" (SQL column list)
    P_SCHEDULE     VARCHAR    -- e.g. '5 MINUTE' | 'USING CRON 0 * * * * UTC' | 'TRIGGER_ON_CHANGES'
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    sched_clause VARCHAR;
BEGIN
    -- Set the evaluation schedule on the table (safe to re-run)
    IF (UPPER(P_SCHEDULE) = 'TRIGGER_ON_CHANGES') THEN
        sched_clause := 'TRIGGER_ON_CHANGES';
    ELSEIF (UPPER(P_SCHEDULE) LIKE 'USING CRON%') THEN
        sched_clause := '''' || P_SCHEDULE || '''';
    ELSE
        sched_clause := '''' || P_SCHEDULE || '''';
    END IF;

    EXECUTE IMMEDIATE
        'ALTER TABLE ' || P_FULL_TABLE ||
        ' SET DATA_METRIC_SCHEDULE = ' || sched_clause;

    -- Attach the DMF. If it already exists this will error; swallow and continue.
    BEGIN
        EXECUTE IMMEDIATE
            'ALTER TABLE ' || P_FULL_TABLE ||
            ' ADD DATA METRIC FUNCTION ' || P_DMF_NAME ||
            ' ON (' || P_ON_COLUMNS || ')';
    EXCEPTION
        WHEN OTHER THEN
            RETURN 'Schedule set; DMF ' || P_DMF_NAME || ' already attached to ' || P_FULL_TABLE
                || ' (or attach failed: ' || SQLERRM || ')';
    END;

    RETURN 'Attached ' || P_DMF_NAME || ' ON (' || P_ON_COLUMNS || ') to '
        || P_FULL_TABLE || ' @ schedule ' || P_SCHEDULE;
END;
$$;

-- ----------------------------------------------------------------------------
-- Grants
-- ----------------------------------------------------------------------------
GRANT USAGE ON PROCEDURE ATTACH_DMF(VARCHAR, VARCHAR, VARCHAR, VARCHAR) TO ROLE DATA_ENGINEER;

-- DMFs must be grantable to roles that own the monitored tables.
GRANT USAGE ON ALL DATA METRIC FUNCTIONS IN SCHEMA GOVERNANCE.DATA_CONTRACTS TO ROLE DATA_ENGINEER;
GRANT USAGE ON ALL DATA METRIC FUNCTIONS IN SCHEMA GOVERNANCE.DATA_CONTRACTS TO ROLE DATA_STEWARD;

SELECT '✓ DMF library created (5 custom DMFs + ATTACH_DMF helper)' AS STATUS;
