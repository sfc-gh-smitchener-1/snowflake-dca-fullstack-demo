-- ============================================================================
-- DATA CONTRACTS ON SNOWFLAKE HORIZON — 01 REGISTRY
-- ============================================================================
--
-- The intent/agreement layer. These tables store WHAT was promised and by whom.
-- Horizon primitives (created in later scripts) provide the enforcement.
--
-- Tables:
--   CONTRACT               — one row per contract version (producer↔consumer promise)
--   CONTRACT_BINDING       — maps a contract to a physical object + enforcement mode
--   SCHEMA_FINGERPRINT     — captured column-level shape per contract version
--   QUALITY_RULE           — declared quality rules → DMFs (bound in 04)
--   SLA_RULE               — declared freshness / volume SLAs (bound in 05)
--   LINEAGE_ASSERTION      — declared upstream/downstream lineage expectations
--   VALIDATION_RUN         — one row per contract validation execution (evidence)
--   VALIDATION_RESULT      — per-dimension result rows for each validation run
--   BREACH_LOG             — recorded breaches with enforcement action taken
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE WAREHOUSE TRANSFORM_WH;
USE SCHEMA GOVERNANCE.DATA_CONTRACTS;

-- ----------------------------------------------------------------------------
-- CONTRACT — the versioned producer↔consumer agreement
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS CONTRACT (
    CONTRACT_ID          VARCHAR(150)  NOT NULL,
    CONTRACT_VERSION     VARCHAR(20)   NOT NULL DEFAULT '1.0.0',
    CONTRACT_NAME        VARCHAR(255)  NOT NULL,
    STATUS               VARCHAR(20)   NOT NULL DEFAULT 'ACTIVE'
                                       COMMENT 'DRAFT | ACTIVE | DEPRECATED | RETIRED',
    -- Producer side
    PRODUCER_TEAM        VARCHAR(255),
    PRODUCER_EMAIL       VARCHAR(255),
    -- Consumer side
    CONSUMER_TEAMS       ARRAY,
    CONSUMER_CRITICALITY VARCHAR(20)   DEFAULT 'MEDIUM'
                                       COMMENT 'CRITICAL | HIGH | MEDIUM | LOW — drives default enforcement mode',
    -- Data classification / governance clause
    DATA_CLASSIFICATION  VARCHAR(20)   COMMENT 'PUBLIC | INTERNAL | CONFIDENTIAL | RESTRICTED',
    COMPLIANCE_FRAMEWORKS ARRAY        COMMENT 'e.g. [HIPAA, GDPR, SOX, PCI]',
    -- Default enforcement + change policy
    DEFAULT_ENFORCEMENT  VARCHAR(20)   DEFAULT 'ALERT'
                                       COMMENT 'BLOCK | ALERT | MONITOR',
    SCHEMA_STABILITY     VARCHAR(20)   DEFAULT 'STABLE'
                                       COMMENT 'STABLE | EVOLVING | DEPRECATED',
    BREAKING_CHANGE_POLICY VARCHAR(50) DEFAULT 'VERSION_BUMP_REQUIRED'
                                       COMMENT 'VERSION_BUMP_REQUIRED | NOTIFY_CONSUMERS | BLOCK',
    -- Freeform definitions kept for auditability / export to OpenDataContract-style YAML
    DESCRIPTION          VARCHAR(4000),
    CONTRACT_SPEC        VARIANT       COMMENT 'Full machine-readable contract spec (schema+quality+sla+lineage)',
    -- Lifecycle
    EFFECTIVE_FROM       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    EFFECTIVE_TO         TIMESTAMP_NTZ DEFAULT '9999-12-31'::TIMESTAMP_NTZ,
    CREATED_AT           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CREATED_BY           VARCHAR(255)  DEFAULT CURRENT_USER(),
    UPDATED_AT           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_CONTRACT PRIMARY KEY (CONTRACT_ID, CONTRACT_VERSION)
)
COMMENT = 'Versioned data contract — the producer/consumer promise. Intent layer.';

-- ----------------------------------------------------------------------------
-- CONTRACT_BINDING — attach a contract to a physical object
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS CONTRACT_BINDING (
    BINDING_ID           VARCHAR(150)  NOT NULL,
    CONTRACT_ID          VARCHAR(150)  NOT NULL,
    CONTRACT_VERSION     VARCHAR(20)   NOT NULL,
    -- Fully-qualified physical object under contract
    OBJECT_DATABASE      VARCHAR(255)  NOT NULL,
    OBJECT_SCHEMA        VARCHAR(255)  NOT NULL,
    OBJECT_NAME          VARCHAR(255)  NOT NULL,
    OBJECT_TYPE          VARCHAR(50)   DEFAULT 'TABLE'
                                       COMMENT 'TABLE | VIEW | DYNAMIC TABLE | EXTERNAL TABLE | SEMANTIC VIEW',
    FULL_OBJECT_PATH     VARCHAR(800)  AS (OBJECT_DATABASE || '.' || OBJECT_SCHEMA || '.' || OBJECT_NAME),
    -- Enforcement mode override (else inherit CONTRACT.DEFAULT_ENFORCEMENT)
    ENFORCEMENT_MODE     VARCHAR(20)   COMMENT 'BLOCK | ALERT | MONITOR (NULL = inherit contract default)',
    -- Layer this object sits in (used for lineage assertions)
    DATA_LAYER           VARCHAR(30)   COMMENT 'RAW | CURATED | SEMANTIC',
    IS_ACTIVE            BOOLEAN       DEFAULT TRUE,
    BOUND_AT             TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_CONTRACT_BINDING PRIMARY KEY (BINDING_ID)
)
COMMENT = 'Binds a contract version to a physical Snowflake object. One contract may bind many objects.';

-- ----------------------------------------------------------------------------
-- SCHEMA_FINGERPRINT — the contracted column-level shape
-- Captured at contract creation; drift detection (03) diffs live schema vs this.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS SCHEMA_FINGERPRINT (
    FINGERPRINT_ID       VARCHAR(150)  NOT NULL,
    CONTRACT_ID          VARCHAR(150)  NOT NULL,
    CONTRACT_VERSION     VARCHAR(20)   NOT NULL,
    BINDING_ID           VARCHAR(150)  NOT NULL,
    COLUMN_NAME          VARCHAR(255)  NOT NULL,
    ORDINAL_POSITION     INTEGER,
    DATA_TYPE            VARCHAR(100)  NOT NULL,
    IS_NULLABLE          BOOLEAN       DEFAULT TRUE,
    NUMERIC_PRECISION    INTEGER,
    NUMERIC_SCALE        INTEGER,
    CHARACTER_MAX_LENGTH INTEGER,
    IS_REQUIRED_BY_CONTRACT BOOLEAN    DEFAULT TRUE
                                       COMMENT 'If TRUE, dropping/renaming this column is a breaking change',
    CAPTURED_AT          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_SCHEMA_FINGERPRINT PRIMARY KEY (FINGERPRINT_ID)
)
COMMENT = 'Column-level contracted schema shape. Source of truth for schema drift detection.';

-- ----------------------------------------------------------------------------
-- QUALITY_RULE — declared quality expectations (bound to DMFs in 04)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS QUALITY_RULE (
    RULE_ID              VARCHAR(150)  NOT NULL,
    CONTRACT_ID          VARCHAR(150)  NOT NULL,
    CONTRACT_VERSION     VARCHAR(20)   NOT NULL,
    BINDING_ID           VARCHAR(150),
    RULE_NAME            VARCHAR(255)  NOT NULL,
    RULE_DESCRIPTION     VARCHAR(1000),
    -- The Horizon DMF that implements this rule
    DMF_NAME             VARCHAR(255)  COMMENT 'Fully-qualified DMF, e.g. SNOWFLAKE.CORE.NULL_COUNT or GOVERNANCE.DATA_CONTRACTS.DMF_*',
    TARGET_COLUMN        VARCHAR(255)  COMMENT 'Column the DMF is evaluated on (NULL for table-level DMFs)',
    -- Pass/fail thresholding applied to the DMF result
    COMPARATOR           VARCHAR(10)   DEFAULT '<=' COMMENT '<= | >= | = | < | > | !=',
    THRESHOLD_VALUE      FLOAT         COMMENT 'Threshold the DMF result is compared against',
    WARNING_THRESHOLD    FLOAT         COMMENT 'Optional soft threshold for WARN status',
    SEVERITY             VARCHAR(20)   DEFAULT 'ERROR' COMMENT 'ERROR | WARN | INFO',
    IS_ACTIVE            BOOLEAN       DEFAULT TRUE,
    CREATED_AT           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_QUALITY_RULE PRIMARY KEY (RULE_ID)
)
COMMENT = 'Declared quality rules. Each maps to a Data Metric Function whose result is thresholded.';

-- ----------------------------------------------------------------------------
-- SLA_RULE — freshness / availability / volume expectations
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS SLA_RULE (
    SLA_ID               VARCHAR(150)  NOT NULL,
    CONTRACT_ID          VARCHAR(150)  NOT NULL,
    CONTRACT_VERSION     VARCHAR(20)   NOT NULL,
    BINDING_ID           VARCHAR(150),
    FRESHNESS_TARGET_MIN INTEGER       COMMENT 'Target max staleness in minutes',
    FRESHNESS_MAX_MIN    INTEGER       COMMENT 'Hard SLA ceiling in minutes (breach if exceeded)',
    MIN_ROW_COUNT        NUMBER(18),
    MAX_ROW_COUNT        NUMBER(18),
    ROW_COUNT_DRIFT_PCT  FLOAT         COMMENT 'Alert if daily row count changes by more than this %',
    AVAILABILITY_TARGET_PCT NUMBER(5,2) DEFAULT 99.9,
    ON_BREACH            VARCHAR(20)   DEFAULT 'ALERT' COMMENT 'BLOCK | ALERT | MONITOR',
    IS_ACTIVE            BOOLEAN       DEFAULT TRUE,
    CREATED_AT           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_SLA_RULE PRIMARY KEY (SLA_ID)
)
COMMENT = 'Declared SLA rules — freshness, volume, availability. Enforced via FRESHNESS/ROW_COUNT DMFs + Alerts.';

-- ----------------------------------------------------------------------------
-- LINEAGE_ASSERTION — expected provenance / downstream consumption
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS LINEAGE_ASSERTION (
    ASSERTION_ID         VARCHAR(150)  NOT NULL,
    CONTRACT_ID          VARCHAR(150)  NOT NULL,
    CONTRACT_VERSION     VARCHAR(20)   NOT NULL,
    BINDING_ID           VARCHAR(150),
    ASSERTION_TYPE       VARCHAR(30)   NOT NULL
                                       COMMENT 'UPSTREAM_REQUIRED | DOWNSTREAM_EXPECTED | NO_UNDECLARED_UPSTREAM | CROSS_PLATFORM',
    -- Related object (upstream source or downstream consumer)
    RELATED_OBJECT       VARCHAR(800)  NOT NULL
                                       COMMENT 'FQN of the expected upstream/downstream object, or Horizon Context object_id',
    RELATED_PLATFORM     VARCHAR(100)  DEFAULT 'Snowflake'
                                       COMMENT 'Snowflake | PostgreSQL | Tableau | Power BI | dbt Cloud | ...',
    IS_CRITICAL          BOOLEAN       DEFAULT FALSE
                                       COMMENT 'If TRUE, missing lineage is a contract breach',
    ON_BREACH            VARCHAR(20)   DEFAULT 'ALERT',
    IS_ACTIVE            BOOLEAN       DEFAULT TRUE,
    CREATED_AT           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_LINEAGE_ASSERTION PRIMARY KEY (ASSERTION_ID)
)
COMMENT = 'Declared lineage expectations. Verified against OBJECT_DEPENDENCIES, ACCESS_HISTORY, and Horizon Context.';

-- ----------------------------------------------------------------------------
-- VALIDATION_RUN — one execution of contract validation (evidence header)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS VALIDATION_RUN (
    RUN_ID               VARCHAR(64)   DEFAULT UUID_STRING() NOT NULL,
    CONTRACT_ID          VARCHAR(150)  NOT NULL,
    CONTRACT_VERSION     VARCHAR(20)   NOT NULL,
    BINDING_ID           VARCHAR(150),
    TRIGGERED_BY         VARCHAR(50)   DEFAULT 'MANUAL'
                                       COMMENT 'MANUAL | TASK | PIPELINE_GATE | ALERT',
    RUN_START            TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    RUN_END              TIMESTAMP_NTZ,
    -- Per-dimension outcomes
    SCHEMA_STATUS        VARCHAR(20)   COMMENT 'PASS | WARN | FAIL | SKIPPED',
    QUALITY_STATUS       VARCHAR(20),
    SLA_STATUS           VARCHAR(20),
    LINEAGE_STATUS       VARCHAR(20),
    OVERALL_STATUS       VARCHAR(20)   COMMENT 'PASS | WARN | FAIL',
    ENFORCEMENT_ACTION   VARCHAR(20)   COMMENT 'NONE | ALERTED | BLOCKED',
    ROW_COUNT            NUMBER(18),
    DETAILS              VARIANT,
    EXECUTED_BY          VARCHAR(255)  DEFAULT CURRENT_USER(),
    CONSTRAINT PK_VALIDATION_RUN PRIMARY KEY (RUN_ID)
)
COMMENT = 'Contract validation execution header. Evidence layer — one row per validation run.';

-- ----------------------------------------------------------------------------
-- VALIDATION_RESULT — per-rule detail for a validation run
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS VALIDATION_RESULT (
    RESULT_ID            VARCHAR(64)   DEFAULT UUID_STRING() NOT NULL,
    RUN_ID               VARCHAR(64)   NOT NULL,
    CONTRACT_ID          VARCHAR(150)  NOT NULL,
    DIMENSION            VARCHAR(20)   NOT NULL COMMENT 'SCHEMA | QUALITY | SLA | LINEAGE',
    RULE_REF             VARCHAR(255)  COMMENT 'RULE_ID / SLA_ID / ASSERTION_ID / column name',
    CHECK_NAME           VARCHAR(255),
    OBSERVED_VALUE       VARCHAR(1000),
    EXPECTED_VALUE       VARCHAR(1000),
    STATUS               VARCHAR(20)   COMMENT 'PASS | WARN | FAIL',
    SEVERITY             VARCHAR(20),
    MESSAGE              VARCHAR(2000),
    CREATED_AT           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_VALIDATION_RESULT PRIMARY KEY (RESULT_ID)
)
COMMENT = 'Per-rule validation detail rows. Drill-down evidence behind each VALIDATION_RUN.';

-- ----------------------------------------------------------------------------
-- BREACH_LOG — durable record of contract breaches + action taken
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS BREACH_LOG (
    BREACH_ID            VARCHAR(64)   DEFAULT UUID_STRING() NOT NULL,
    RUN_ID               VARCHAR(64),
    CONTRACT_ID          VARCHAR(150)  NOT NULL,
    CONTRACT_VERSION     VARCHAR(20),
    BINDING_ID           VARCHAR(150),
    DIMENSION            VARCHAR(20)   COMMENT 'SCHEMA | QUALITY | SLA | LINEAGE',
    SEVERITY             VARCHAR(20),
    ENFORCEMENT_ACTION   VARCHAR(20)   COMMENT 'ALERTED | BLOCKED | MONITORED',
    SUMMARY              VARCHAR(2000),
    DETAILS              VARIANT,
    DETECTED_AT          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    RESOLVED_AT          TIMESTAMP_NTZ,
    RESOLVED_BY          VARCHAR(255),
    RESOLUTION_NOTE      VARCHAR(2000),
    STATUS               VARCHAR(20)   DEFAULT 'OPEN' COMMENT 'OPEN | ACKNOWLEDGED | RESOLVED | WAIVED',
    CONSTRAINT PK_BREACH_LOG PRIMARY KEY (BREACH_ID)
)
COMMENT = 'Durable breach ledger with enforcement action and resolution workflow.';

-- ----------------------------------------------------------------------------
-- Grants
-- ----------------------------------------------------------------------------
GRANT SELECT ON ALL TABLES IN SCHEMA GOVERNANCE.DATA_CONTRACTS TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL TABLES IN SCHEMA GOVERNANCE.DATA_CONTRACTS TO ROLE DATA_ENGINEER;
GRANT SELECT ON ALL TABLES IN SCHEMA GOVERNANCE.DATA_CONTRACTS TO ROLE AUDITOR;

SELECT '✓ Contract registry tables created (9 tables)' AS STATUS;
