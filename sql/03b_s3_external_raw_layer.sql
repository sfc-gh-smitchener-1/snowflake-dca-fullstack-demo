-- ============================================================================
-- RAW LAYER (S3) - External Tables over Non-Iceberg S3 Files
-- ============================================================================
--
-- This script creates the S3-backed external table raw layer alongside the
-- existing internal-stage approach (03_raw_layer.sql).  Every curated Dynamic
-- Table and Semantic View that references RAW_DEV.* automatically inherits
-- lineage to the S3 files once the external tables replace the internal copies.
--
-- S3 LAYOUT (bucket populated by tools/upload_to_s3.py)
-- ──────────────────────────────────────────────────────
--   <bucket>/sap_s4hana/          ← Parquet  (SAP S/4HANA)
--   <bucket>/salesforce/          ← CSV      (Salesforce CRM)
--   <bucket>/oracle_ebs/          ← CSV      (Oracle EBS)
--   <bucket>/fhir_r4/             ← XML      (HL7 FHIR R4)
--   <bucket>/workday/             ← JSON     (Workday HCM)
--   <bucket>/servicenow/          ← CSV      (ServiceNow ITSM)
--   <bucket>/dcim/servicenow/     ← CSV      (DCIM ServiceNow CMDB)
--   <bucket>/dcim/siemens_dcim/   ← XML      (Siemens Desigo CC BMS)
--   <bucket>/dcim/telemetry/      ← Parquet  (DC network telemetry)
--   <bucket>/dcim/workday_dcim/   ← JSON     (DCIM Workday workforce)
--
-- DEPLOYMENT ORDER
-- ──────────────────────────────────────────────────────
--   1. terraform apply             ← create S3 bucket + IAM role (placeholder values)
--   2. Generate data + upload_to_s3.py
--   3. Run this script up to the STORAGE INTEGRATION section
--   4. DESCRIBE INTEGRATION S3_RAW_INTEGRATION; ← get IAM principal + external ID
--   5. Update terraform/variables.tf + terraform apply  ← lock trust policy
--   6. Re-run CREATE STORAGE INTEGRATION with real ARN
--   7. Call CALL RAW_DEV.STAGING.CREATE_ALL_S3_EXTERNAL_TABLES();
--   8. Verify with lineage queries at the bottom of this script
--
-- SUPPORTED SOURCE SYSTEMS (~68 tables, 4 formats):
--   SAP:        KNA1, MARA, VBAK, VBAP, LFA1, EKKO, BKPF, PA0001, PA0002
--   Salesforce: Account, Contact, Opportunity, Case, Lead, Product2, Campaign, Task
--   Oracle EBS: HZ_PARTIES, MTL_SYSTEM_ITEMS_B, OE_ORDER_HEADERS_ALL,
--               OE_ORDER_LINES_ALL, AP_INVOICES_ALL, RA_CUSTOMER_TRX_ALL,
--               GL_JE_LINES, HR_ALL_PEOPLE_F
--   FHIR R4:    Patient, Practitioner, Organization, Encounter, Condition,
--               Observation, MedicationRequest, Procedure, Claim
--   Workday:    Workers, Organizations, Job_Profiles, Compensation,
--               Time_Off, Benefit_Elections
--   ServiceNow: sys_user, incident, change_request, problem, cmdb_ci,
--               sc_request, kb_knowledge
--   DCIM SN:    data_centers, halls, racks, switches, ports, incidents,
--               change_requests
--   DCIM Siemens: facilities, zones, power_distribution_units, cooling_loops,
--                 rack_inventory, bms_sensors, maintenance_orders
--   DCIM Telemetry: port_metrics, switch_health, environmental_sensors, alerts
--   DCIM Workday: teams, technicians, certifications, shifts, skill_assignments,
--                 time_off, training_completions
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE RAW_DEV;
USE WAREHOUSE TRANSFORM_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 1: STORAGE INTEGRATION
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Replace <IAM_ROLE_ARN>   with the value from:   terraform output iam_role_arn
-- Replace <S3_BUCKET_URI>  with the value from:   terraform output s3_bucket_uri
--
-- After creation, run:
--   DESCRIBE INTEGRATION S3_RAW_INTEGRATION;
-- Copy STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID into
-- terraform/variables.tf, then re-run terraform apply to lock the trust policy.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE STORAGE INTEGRATION IF NOT EXISTS S3_RAW_INTEGRATION
    TYPE                      = EXTERNAL_STAGE
    STORAGE_PROVIDER          = 'S3'
    ENABLED                   = TRUE
    STORAGE_AWS_ROLE_ARN      = '<IAM_ROLE_ARN>'
    STORAGE_ALLOWED_LOCATIONS = ('<S3_BUCKET_URI>')
    COMMENT = 'Snowflake storage integration for DCA raw layer S3 bucket';

-- After updating terraform trust policy, re-run the ALTER to refresh the ARN:
-- ALTER STORAGE INTEGRATION S3_RAW_INTEGRATION
--     SET STORAGE_AWS_ROLE_ARN = '<IAM_ROLE_ARN>';

GRANT USAGE ON INTEGRATION S3_RAW_INTEGRATION TO ROLE DATA_ENGINEER;

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 2: EXTERNAL STAGE
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA RAW_DEV.STAGING;

CREATE EXTERNAL STAGE IF NOT EXISTS RAW_DEV.STAGING.S3_RAW_STAGE
    URL                 = '<S3_BUCKET_URI>'
    STORAGE_INTEGRATION = S3_RAW_INTEGRATION
    DIRECTORY           = (ENABLE = TRUE AUTO_REFRESH = FALSE)
    COMMENT             = 'External stage for DCA raw layer S3 files (all formats)';

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 3: FILE FORMATS FOR EXTERNAL TABLES
-- ═══════════════════════════════════════════════════════════════════════════
--
-- CSV_EXTERNAL_FORMAT uses PARSE_HEADER = TRUE so column-name references
-- ($1:column_name) work in external table definitions — same ergonomics as
-- Parquet and JSON without hardcoded column positions.
-- ═══════════════════════════════════════════════════════════════════════════

-- CSV with header parsing (for external tables, use column-name path notation)
CREATE FILE FORMAT IF NOT EXISTS RAW_DEV.STAGING.CSV_EXTERNAL_FORMAT
    TYPE                        = 'CSV'
    PARSE_HEADER                = TRUE
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF                     = ('', 'NULL', 'null', 'None')
    EMPTY_FIELD_AS_NULL         = TRUE
    SKIP_BLANK_LINES            = TRUE
    COMPRESSION                 = AUTO
    COMMENT                     = 'CSV format with header parsing for external tables';

-- Parquet (reuses existing but redeclared here for clarity)
CREATE FILE FORMAT IF NOT EXISTS RAW_DEV.STAGING.PARQUET_EXT_FORMAT
    TYPE        = 'PARQUET'
    COMPRESSION = AUTO
    COMMENT     = 'Parquet format for external tables';

-- JSON array (Workday REST API payloads)
CREATE FILE FORMAT IF NOT EXISTS RAW_DEV.STAGING.JSON_EXT_FORMAT
    TYPE              = 'JSON'
    COMPRESSION       = AUTO
    STRIP_OUTER_ARRAY = TRUE
    COMMENT           = 'JSON format for external tables';

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 4: NEW DCIM SCHEMAS IN RAW_DEV
-- ═══════════════════════════════════════════════════════════════════════════

CREATE SCHEMA IF NOT EXISTS RAW_DEV.DCIM_SERVICENOW
    COMMENT = 'DCIM ServiceNow CMDB: data centers, halls, racks, switches, ports';

CREATE SCHEMA IF NOT EXISTS RAW_DEV.DCIM_SIEMENS
    COMMENT = 'Siemens Desigo CC BMS: facilities, zones, PDUs, cooling, sensors (XML)';

CREATE SCHEMA IF NOT EXISTS RAW_DEV.DCIM_TELEMETRY
    COMMENT = 'DC network telemetry: port metrics, switch health, env sensors (Parquet)';

CREATE SCHEMA IF NOT EXISTS RAW_DEV.DCIM_WORKDAY
    COMMENT = 'DCIM Workday workforce: technicians, certifications, shifts (JSON)';

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 5: REFERENCE DDL — EXPLICIT EXTERNAL TABLE EXAMPLES
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Three representative tables (one per non-XML format) show the column
-- expression pattern.  All remaining tables are created by the
-- CREATE_ALL_S3_EXTERNAL_TABLES() procedure in Section 6.
-- ═══════════════════════════════════════════════════════════════════════════

-- ---------------------------------------------------------------------------
-- 5a. SAP KNA1 — Parquet format (column-name path notation)
-- ---------------------------------------------------------------------------
CREATE EXTERNAL TABLE IF NOT EXISTS RAW_DEV.SAP.KNA1 (
    -- Business key and core master fields
    MANDT              VARCHAR(3)     AS ($1:MANDT::VARCHAR),
    KUNNR              VARCHAR(10)    AS ($1:KUNNR::VARCHAR),
    NAME1              VARCHAR(35)    AS ($1:NAME1::VARCHAR),
    NAME2              VARCHAR(35)    AS ($1:NAME2::VARCHAR),
    SORTL              VARCHAR(10)    AS ($1:SORTL::VARCHAR),
    STRAS              VARCHAR(35)    AS ($1:STRAS::VARCHAR),
    ORT01              VARCHAR(35)    AS ($1:ORT01::VARCHAR),
    PSTLZ              VARCHAR(10)    AS ($1:PSTLZ::VARCHAR),
    LAND1              VARCHAR(3)     AS ($1:LAND1::VARCHAR),
    REGIO              VARCHAR(3)     AS ($1:REGIO::VARCHAR),
    SPRAS              VARCHAR(2)     AS ($1:SPRAS::VARCHAR),
    TELF1              VARCHAR(16)    AS ($1:TELF1::VARCHAR),
    TELFX              VARCHAR(16)    AS ($1:TELFX::VARCHAR),
    SMTP_ADDR          VARCHAR(241)   AS ($1:SMTP_ADDR::VARCHAR),
    KTOKD              VARCHAR(4)     AS ($1:KTOKD::VARCHAR),
    ERDAT              VARCHAR(8)     AS ($1:ERDAT::VARCHAR),
    ERNAM              VARCHAR(12)    AS ($1:ERNAM::VARCHAR),
    LOEVM              VARCHAR(1)     AS ($1:LOEVM::VARCHAR),
    SPERR              VARCHAR(1)     AS ($1:SPERR::VARCHAR),
    BRSCH              VARCHAR(4)     AS ($1:BRSCH::VARCHAR),
    KUKLA              VARCHAR(2)     AS ($1:KUKLA::VARCHAR),
    STCEG              VARCHAR(20)    AS ($1:STCEG::VARCHAR),
    -- SCD Type 2 metadata
    _LOADED_AT         TIMESTAMP_NTZ  AS ($1:_LOADED_AT::TIMESTAMP_NTZ),
    _SOURCE_SYSTEM     VARCHAR(100)   AS ($1:_SOURCE_SYSTEM::VARCHAR),
    _SOURCE_TABLE      VARCHAR(100)   AS ($1:_SOURCE_TABLE::VARCHAR),
    _ROW_HASH          VARCHAR(64)    AS ($1:_ROW_HASH::VARCHAR),
    _IS_CURRENT        BOOLEAN        AS ($1:_IS_CURRENT::BOOLEAN),
    _VALID_FROM        TIMESTAMP_NTZ  AS ($1:_VALID_FROM::TIMESTAMP_NTZ),
    _VALID_TO          VARCHAR(50)    AS ($1:_VALID_TO::VARCHAR),
    -- S3 file-level lineage columns (always present in all external tables)
    _S3_FILE_PATH      VARCHAR        AS (METADATA$FILENAME::VARCHAR),
    _FILE_LAST_MODIFIED TIMESTAMP_NTZ AS (METADATA$FILE_LAST_MODIFIED::TIMESTAMP_NTZ)
)
WITH LOCATION = @RAW_DEV.STAGING.S3_RAW_STAGE/sap_s4hana/
FILE_FORMAT = RAW_DEV.STAGING.PARQUET_EXT_FORMAT
COMMENT = 'SAP KNA1 Customer Master — Parquet on S3 (external table)';

-- ---------------------------------------------------------------------------
-- 5b. Salesforce Account — CSV format (PARSE_HEADER column-name notation)
-- ---------------------------------------------------------------------------
CREATE EXTERNAL TABLE IF NOT EXISTS RAW_DEV.SALESFORCE.ACCOUNT (
    ID                     VARCHAR(18)  AS ($1:Id::VARCHAR),
    ISDELETED              BOOLEAN      AS ($1:IsDeleted::BOOLEAN),
    NAME                   VARCHAR(255) AS ($1:Name::VARCHAR),
    TYPE                   VARCHAR(255) AS ($1:Type::VARCHAR),
    INDUSTRY               VARCHAR(255) AS ($1:Industry::VARCHAR),
    ANNUALREVENUE          NUMBER(18,2) AS ($1:AnnualRevenue::NUMBER),
    NUMBEROFEMPLOYEES      NUMBER       AS ($1:NumberOfEmployees::NUMBER),
    RATING                 VARCHAR(50)  AS ($1:Rating::VARCHAR),
    BILLINGSTREET          VARCHAR(255) AS ($1:BillingStreet::VARCHAR),
    BILLINGCITY            VARCHAR(255) AS ($1:BillingCity::VARCHAR),
    BILLINGSTATE           VARCHAR(255) AS ($1:BillingState::VARCHAR),
    BILLINGPOSTALCODE      VARCHAR(50)  AS ($1:BillingPostalCode::VARCHAR),
    BILLINGCOUNTRY         VARCHAR(255) AS ($1:BillingCountry::VARCHAR),
    PHONE                  VARCHAR(50)  AS ($1:Phone::VARCHAR),
    WEBSITE                VARCHAR(255) AS ($1:Website::VARCHAR),
    OWNERID                VARCHAR(18)  AS ($1:OwnerId::VARCHAR),
    CUSTOMER_SEGMENT__C    VARCHAR(255) AS ($1:Customer_Segment__c::VARCHAR),
    LIFECYCLE_STAGE__C     VARCHAR(255) AS ($1:Lifecycle_Stage__c::VARCHAR),
    -- SCD Type 2 metadata
    _LOADED_AT             TIMESTAMP_NTZ AS ($1:_LOADED_AT::TIMESTAMP_NTZ),
    _SOURCE_SYSTEM         VARCHAR(100)  AS ($1:_SOURCE_SYSTEM::VARCHAR),
    _SOURCE_TABLE          VARCHAR(100)  AS ($1:_SOURCE_TABLE::VARCHAR),
    _ROW_HASH              VARCHAR(64)   AS ($1:_ROW_HASH::VARCHAR),
    _IS_CURRENT            BOOLEAN       AS ($1:_IS_CURRENT::BOOLEAN),
    _VALID_FROM            TIMESTAMP_NTZ AS ($1:_VALID_FROM::TIMESTAMP_NTZ),
    _VALID_TO              VARCHAR(50)   AS ($1:_VALID_TO::VARCHAR),
    _S3_FILE_PATH          VARCHAR       AS (METADATA$FILENAME::VARCHAR),
    _FILE_LAST_MODIFIED    TIMESTAMP_NTZ AS (METADATA$FILE_LAST_MODIFIED::TIMESTAMP_NTZ)
)
WITH LOCATION = @RAW_DEV.STAGING.S3_RAW_STAGE/salesforce/
PATTERN = '.*Account.*[.]csv'
FILE_FORMAT = RAW_DEV.STAGING.CSV_EXTERNAL_FORMAT
COMMENT = 'Salesforce Account — CSV on S3 (external table)';

-- ---------------------------------------------------------------------------
-- 5c. Workday Workers — JSON format (field-name path notation)
-- ---------------------------------------------------------------------------
CREATE EXTERNAL TABLE IF NOT EXISTS RAW_DEV.WORKDAY.WORKERS (
    WORKER_ID              VARCHAR(50)   AS ($1:worker_id::VARCHAR),
    EMPLOYEE_ID            VARCHAR(20)   AS ($1:employee_id::VARCHAR),
    FIRST_NAME             VARCHAR(100)  AS ($1:first_name::VARCHAR),
    LAST_NAME              VARCHAR(100)  AS ($1:last_name::VARCHAR),
    EMAIL                  VARCHAR(255)  AS ($1:email::VARCHAR),
    HIRE_DATE              DATE          AS ($1:hire_date::DATE),
    TERMINATION_DATE       DATE          AS ($1:termination_date::DATE),
    EMPLOYMENT_STATUS      VARCHAR(50)   AS ($1:employment_status::VARCHAR),
    WORKER_TYPE            VARCHAR(50)   AS ($1:worker_type::VARCHAR),
    POSITION_ID            VARCHAR(50)   AS ($1:position_id::VARCHAR),
    SUPERVISOR_ID          VARCHAR(50)   AS ($1:supervisor_id::VARCHAR),
    COST_CENTER            VARCHAR(50)   AS ($1:cost_center::VARCHAR),
    LOCATION               VARCHAR(100)  AS ($1:location::VARCHAR),
    COUNTRY                VARCHAR(50)   AS ($1:country::VARCHAR),
    -- SCD Type 2 metadata
    _LOADED_AT             TIMESTAMP_NTZ AS ($1:_LOADED_AT::TIMESTAMP_NTZ),
    _SOURCE_SYSTEM         VARCHAR(100)  AS ($1:_SOURCE_SYSTEM::VARCHAR),
    _SOURCE_TABLE          VARCHAR(100)  AS ($1:_SOURCE_TABLE::VARCHAR),
    _ROW_HASH              VARCHAR(64)   AS ($1:_ROW_HASH::VARCHAR),
    _IS_CURRENT            BOOLEAN       AS ($1:_IS_CURRENT::BOOLEAN),
    _VALID_FROM            TIMESTAMP_NTZ AS ($1:_VALID_FROM::TIMESTAMP_NTZ),
    _VALID_TO              VARCHAR(50)   AS ($1:_VALID_TO::VARCHAR),
    _S3_FILE_PATH          VARCHAR       AS (METADATA$FILENAME::VARCHAR),
    _FILE_LAST_MODIFIED    TIMESTAMP_NTZ AS (METADATA$FILE_LAST_MODIFIED::TIMESTAMP_NTZ)
)
WITH LOCATION = @RAW_DEV.STAGING.S3_RAW_STAGE/workday/
PATTERN = '.*Workers.*[.]json'
FILE_FORMAT = RAW_DEV.STAGING.JSON_EXT_FORMAT
COMMENT = 'Workday Workers — JSON on S3 (external table)';

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 6: XML PATTERN — FHIR R4 Patient (two-object approach)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Snowflake does not support TYPE = XML in CREATE EXTERNAL TABLE FILE_FORMAT.
-- Pattern: raw external table reads each XML file as a single VARIANT row via
-- $1 (treated as plain text), then PARSE_XML() normalises it.  A view on top
-- provides the column-level interface consumed by the curated layer.
--
-- This preserves the authentic HL7 FHIR XML in S3 — no transformation on
-- ingestion.  Lineage in Access History shows:
--   SEM_DEV.FHIR.CLINICAL_ANALYTICS
--     → CURATED_DEV.FHIR.DIM_PATIENT  (Dynamic Table)
--       → RAW_DEV.FHIR.PATIENT        (View on raw XML external table)
--         → RAW_DEV.FHIR.PATIENT_XML_RAW (External Table → S3 XML)
-- ═══════════════════════════════════════════════════════════════════════════

-- 6a. Raw XML external table (one VARIANT row per file)
CREATE EXTERNAL TABLE IF NOT EXISTS RAW_DEV.FHIR.PATIENT_XML_RAW (
    RAW_XML           VARIANT  AS (TO_VARIANT($1::VARCHAR)),
    _S3_FILE_PATH     VARCHAR  AS (METADATA$FILENAME::VARCHAR),
    _FILE_LAST_MODIFIED TIMESTAMP_NTZ AS (METADATA$FILE_LAST_MODIFIED::TIMESTAMP_NTZ)
)
WITH LOCATION = @RAW_DEV.STAGING.S3_RAW_STAGE/fhir_r4/
PATTERN = '.*Patient.*[.]xml'
FILE_FORMAT = (
    TYPE = CSV
    RECORD_DELIMITER = NONE
    FIELD_DELIMITER  = NONE
)
COMMENT = 'FHIR Patient XML — raw per-file VARIANT (backing table for Patient view)';

-- 6b. Normalised view — column-level interface matching SCD Type 2 contract
CREATE OR REPLACE VIEW RAW_DEV.FHIR.PATIENT
COMMENT = 'FHIR R4 Patient — normalised view over raw XML; exposes SCD Type 2 columns'
AS
WITH parsed AS (
    SELECT
        PARSE_XML(RAW_XML::VARCHAR) AS xml,
        _S3_FILE_PATH,
        _FILE_LAST_MODIFIED
    FROM RAW_DEV.FHIR.PATIENT_XML_RAW
)
SELECT
    XMLGET(xml, 'id'):   "$"::VARCHAR         AS ID,
    XMLGET(xml, 'active'):"$"::BOOLEAN        AS ACTIVE,
    XMLGET(xml, 'gender'):"$"::VARCHAR        AS GENDER,
    XMLGET(xml, 'birthDate'):"$"::VARCHAR     AS BIRTH_DATE,
    XMLGET(XMLGET(xml, 'name'), 'family'):"$"::VARCHAR AS FAMILY_NAME,
    XMLGET(XMLGET(xml, 'name'), 'given'):"$"::VARCHAR  AS GIVEN_NAME,
    XMLGET(XMLGET(xml, 'address'), 'city'):"$"::VARCHAR    AS CITY,
    XMLGET(XMLGET(xml, 'address'), 'state'):"$"::VARCHAR   AS STATE,
    XMLGET(XMLGET(xml, 'address'), 'country'):"$"::VARCHAR AS COUNTRY,
    XMLGET(xml, '_LOADED_AT'):"$"::TIMESTAMP_NTZ     AS _LOADED_AT,
    XMLGET(xml, '_SOURCE_SYSTEM'):"$"::VARCHAR        AS _SOURCE_SYSTEM,
    XMLGET(xml, '_SOURCE_TABLE'):"$"::VARCHAR         AS _SOURCE_TABLE,
    XMLGET(xml, '_ROW_HASH'):"$"::VARCHAR             AS _ROW_HASH,
    XMLGET(xml, '_IS_CURRENT'):"$"::BOOLEAN           AS _IS_CURRENT,
    XMLGET(xml, '_VALID_FROM'):"$"::TIMESTAMP_NTZ     AS _VALID_FROM,
    XMLGET(xml, '_VALID_TO'):"$"::VARCHAR             AS _VALID_TO,
    _S3_FILE_PATH,
    _FILE_LAST_MODIFIED
FROM parsed;

-- Siemens BMS XML — same two-object pattern (raw table + view)
CREATE EXTERNAL TABLE IF NOT EXISTS RAW_DEV.DCIM_SIEMENS.FACILITIES_XML_RAW (
    RAW_XML             VARIANT  AS (TO_VARIANT($1::VARCHAR)),
    _S3_FILE_PATH       VARCHAR  AS (METADATA$FILENAME::VARCHAR),
    _FILE_LAST_MODIFIED TIMESTAMP_NTZ AS (METADATA$FILE_LAST_MODIFIED::TIMESTAMP_NTZ)
)
WITH LOCATION = @RAW_DEV.STAGING.S3_RAW_STAGE/dcim/siemens_dcim/
PATTERN = '.*facilities.*[.]xml'
FILE_FORMAT = (
    TYPE = CSV
    RECORD_DELIMITER = NONE
    FIELD_DELIMITER  = NONE
)
COMMENT = 'Siemens Desigo CC facilities XML — raw backing table';

CREATE OR REPLACE VIEW RAW_DEV.DCIM_SIEMENS.FACILITIES
COMMENT = 'Siemens Desigo CC Facilities — normalised view over raw XML'
AS
WITH parsed AS (
    SELECT
        PARSE_XML(RAW_XML::VARCHAR) AS xml,
        _S3_FILE_PATH,
        _FILE_LAST_MODIFIED
    FROM RAW_DEV.DCIM_SIEMENS.FACILITIES_XML_RAW
)
SELECT
    XMLGET(xml, 'facility_id'):"$"::VARCHAR           AS FACILITY_ID,
    XMLGET(xml, 'standort_name'):"$"::VARCHAR         AS STANDORT_NAME,
    XMLGET(xml, 'gebaeude_typ'):"$"::VARCHAR          AS GEBAEUDE_TYP,
    XMLGET(xml, 'region'):"$"::VARCHAR                AS REGION,
    XMLGET(xml, 'country'):"$"::VARCHAR               AS COUNTRY,
    XMLGET(xml, 'city'):"$"::VARCHAR                  AS CITY,
    XMLGET(xml, 'tier_level'):"$"::NUMBER             AS TIER_LEVEL,
    XMLGET(xml, 'total_power_mw'):"$"::FLOAT          AS TOTAL_POWER_MW,
    XMLGET(xml, 'total_cooling_mw'):"$"::FLOAT        AS TOTAL_COOLING_MW,
    XMLGET(xml, 'rack_capacity'):"$"::NUMBER          AS RACK_CAPACITY,
    XMLGET(xml, 'commissioning_date'):"$"::DATE       AS COMMISSIONING_DATE,
    XMLGET(xml, 'acquisition_date'):"$"::DATE         AS ACQUISITION_DATE,
    XMLGET(xml, 'current_standort_name'):"$"::VARCHAR AS CURRENT_STANDORT_NAME,
    XMLGET(xml, 'historical_standort_name'):"$"::VARCHAR AS HISTORICAL_STANDORT_NAME,
    XMLGET(xml, 'original_standort_name'):"$"::VARCHAR   AS ORIGINAL_STANDORT_NAME,
    XMLGET(xml, '_LOADED_AT'):"$"::TIMESTAMP_NTZ      AS _LOADED_AT,
    XMLGET(xml, '_SOURCE_SYSTEM'):"$"::VARCHAR        AS _SOURCE_SYSTEM,
    XMLGET(xml, '_SOURCE_TABLE'):"$"::VARCHAR         AS _SOURCE_TABLE,
    XMLGET(xml, '_ROW_HASH'):"$"::VARCHAR             AS _ROW_HASH,
    XMLGET(xml, '_IS_CURRENT'):"$"::BOOLEAN           AS _IS_CURRENT,
    XMLGET(xml, '_VALID_FROM'):"$"::TIMESTAMP_NTZ     AS _VALID_FROM,
    XMLGET(xml, '_VALID_TO'):"$"::VARCHAR             AS _VALID_TO,
    _S3_FILE_PATH,
    _FILE_LAST_MODIFIED
FROM parsed;

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 7: AUTO-CREATE ALL REMAINING EXTERNAL TABLES
-- ═══════════════════════════════════════════════════════════════════════════
--
-- This procedure uses INFER_SCHEMA + USING TEMPLATE to create external tables
-- for every source file in S3, mirroring the internal-stage INFER_AND_CREATE_TABLE
-- pattern in 03_raw_layer.sql.  Run it AFTER uploading data with upload_to_s3.py.
--
-- Each table gets:
--   • All business columns inferred from the S3 file
--   • METADATA$FILENAME AS _S3_FILE_PATH
--   • METADATA$FILE_LAST_MODIFIED AS _FILE_LAST_MODIFIED
--   • Governance tags (DATA_CLASSIFICATION, DATA_DOMAIN, SOURCE_SYSTEM)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE RAW_DEV.STAGING.CREATE_S3_EXTERNAL_TABLE(
    P_SCHEMA_NAME   VARCHAR,   -- e.g. 'SAP', 'DCIM_TELEMETRY'
    P_TABLE_NAME    VARCHAR,   -- e.g. 'MARA'
    P_S3_PREFIX     VARCHAR,   -- e.g. 'sap_s4hana/'  (relative to stage root)
    P_FILE_PATTERN  VARCHAR,   -- e.g. '.*MARA.*[.]parquet'
    P_FILE_FORMAT   VARCHAR    -- 'PARQUET_EXT_FORMAT', 'CSV_EXTERNAL_FORMAT', 'JSON_EXT_FORMAT'
)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var schemaName    = 'RAW_DEV.' + P_SCHEMA_NAME.toUpperCase();
    var fullTableName = schemaName + '.' + P_TABLE_NAME.toUpperCase();
    var formatName    = 'RAW_DEV.STAGING.' + P_FILE_FORMAT.toUpperCase();
    var stagePath     = '@RAW_DEV.STAGING.S3_RAW_STAGE/' + P_S3_PREFIX;

    try {
        // ------------------------------------------------------------------
        // Step 1: Infer schema from the S3 files
        // ------------------------------------------------------------------
        var inferSql = `
            SELECT ARRAY_AGG(OBJECT_CONSTRUCT(
                'column_name', COLUMN_NAME,
                'type', TYPE,
                'nullable', NULLABLE
            )) AS schema_json
            FROM TABLE(
                INFER_SCHEMA(
                    LOCATION      => '${stagePath}',
                    FILE_FORMAT   => '${formatName}',
                    MAX_RECORDS_PER_FILE => 1000
                )
            )
        `;
        var inferStmt   = snowflake.createStatement({sqlText: inferSql});
        var inferResult = inferStmt.execute();

        if (!inferResult.next()) {
            return 'ERROR: INFER_SCHEMA returned no rows for ' + stagePath;
        }

        var schemaJson = inferResult.getColumnValue(1);
        if (!schemaJson || schemaJson === 'null') {
            return 'ERROR: No schema inferred from ' + stagePath;
        }

        var cols = JSON.parse(schemaJson);
        if (!cols || cols.length === 0) {
            return 'ERROR: Empty schema for ' + stagePath;
        }

        // ------------------------------------------------------------------
        // Step 2: Build column expression list
        //   For Parquet / JSON: $1:col_name::TYPE
        //   For CSV with PARSE_HEADER: $1:col_name::TYPE  (same!)
        // Append S3 metadata lineage columns at the end.
        // ------------------------------------------------------------------
        var colDefs = cols.map(function(c) {
            var safe = c.column_name.replace(/"/g, '');
            var nullable = (c.nullable !== false) ? '' : ' NOT NULL';
            return '"' + safe + '" ' + c.type + nullable +
                   ' AS ($1:"' + safe + '"::'  + c.type + ')';
        }).join(',\n    ');

        // Append S3 file-level lineage columns
        colDefs += ',\n    _S3_FILE_PATH VARCHAR AS (METADATA$FILENAME::VARCHAR)';
        colDefs += ',\n    _FILE_LAST_MODIFIED TIMESTAMP_NTZ AS (METADATA$FILE_LAST_MODIFIED::TIMESTAMP_NTZ)';

        // ------------------------------------------------------------------
        // Step 3: Create the external table
        // ------------------------------------------------------------------
        var patternClause = P_FILE_PATTERN && P_FILE_PATTERN !== ''
            ? "\nPATTERN = '" + P_FILE_PATTERN + "'"
            : '';

        var createSql = `
            CREATE EXTERNAL TABLE IF NOT EXISTS ${fullTableName} (
                ${colDefs}
            )
            WITH LOCATION = ${stagePath}
            ${patternClause}
            FILE_FORMAT = ${formatName}
            COMMENT = 'Auto-created from ${stagePath} (${P_FILE_FORMAT})'
        `;

        snowflake.createStatement({sqlText: createSql}).execute();

        // ------------------------------------------------------------------
        // Step 4: Apply governance tags (best-effort)
        // ------------------------------------------------------------------
        var tagSql = `
            CALL RAW_DEV.STAGING.APPLY_SOURCE_SYSTEM_TAGS(
                '${P_SCHEMA_NAME}', '${P_TABLE_NAME}'
            )
        `;
        try { snowflake.createStatement({sqlText: tagSql}).execute(); } catch(e) {}

        return 'SUCCESS: Created external table ' + fullTableName + ' from ' + stagePath;

    } catch (err) {
        return 'ERROR: ' + err.message + ' | SQL context: ' + P_TABLE_NAME;
    }
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- Orchestration procedure: creates ALL external tables for all source systems
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE RAW_DEV.STAGING.CREATE_ALL_S3_EXTERNAL_TABLES()
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    //
    // Table registry: [schema, table, s3_prefix, pattern, format]
    // Format tokens map to RAW_DEV.STAGING.<token>
    //
    var tables = [
        // ── SAP S/4HANA (Parquet) ──────────────────────────────────────
        ['SAP', 'KNA1',    'sap_s4hana/', '.*KNA1.*[.]parquet',    'PARQUET_EXT_FORMAT'],
        ['SAP', 'MARA',    'sap_s4hana/', '.*MARA.*[.]parquet',    'PARQUET_EXT_FORMAT'],
        ['SAP', 'VBAK',    'sap_s4hana/', '.*VBAK.*[.]parquet',    'PARQUET_EXT_FORMAT'],
        ['SAP', 'VBAP',    'sap_s4hana/', '.*VBAP.*[.]parquet',    'PARQUET_EXT_FORMAT'],
        ['SAP', 'LFA1',    'sap_s4hana/', '.*LFA1.*[.]parquet',    'PARQUET_EXT_FORMAT'],
        ['SAP', 'EKKO',    'sap_s4hana/', '.*EKKO.*[.]parquet',    'PARQUET_EXT_FORMAT'],
        ['SAP', 'BKPF',    'sap_s4hana/', '.*BKPF.*[.]parquet',    'PARQUET_EXT_FORMAT'],
        ['SAP', 'PA0001',  'sap_s4hana/', '.*PA0001.*[.]parquet',  'PARQUET_EXT_FORMAT'],
        ['SAP', 'PA0002',  'sap_s4hana/', '.*PA0002.*[.]parquet',  'PARQUET_EXT_FORMAT'],

        // ── Salesforce (CSV) ──────────────────────────────────────────
        ['SALESFORCE', 'ACCOUNT',     'salesforce/', '.*Account.*[.]csv',     'CSV_EXTERNAL_FORMAT'],
        ['SALESFORCE', 'CONTACT',     'salesforce/', '.*Contact.*[.]csv',     'CSV_EXTERNAL_FORMAT'],
        ['SALESFORCE', 'OPPORTUNITY', 'salesforce/', '.*Opportunity.*[.]csv', 'CSV_EXTERNAL_FORMAT'],
        ['SALESFORCE', 'CASE',        'salesforce/', '.*Case.*[.]csv',        'CSV_EXTERNAL_FORMAT'],
        ['SALESFORCE', 'LEAD',        'salesforce/', '.*Lead.*[.]csv',        'CSV_EXTERNAL_FORMAT'],
        ['SALESFORCE', 'PRODUCT2',    'salesforce/', '.*Product2.*[.]csv',    'CSV_EXTERNAL_FORMAT'],
        ['SALESFORCE', 'CAMPAIGN',    'salesforce/', '.*Campaign.*[.]csv',    'CSV_EXTERNAL_FORMAT'],
        ['SALESFORCE', 'TASK',        'salesforce/', '.*Task.*[.]csv',        'CSV_EXTERNAL_FORMAT'],

        // ── Oracle EBS (CSV) ─────────────────────────────────────────
        ['ORACLE', 'HZ_PARTIES',          'oracle_ebs/', '.*HZ_PARTIES.*[.]csv',          'CSV_EXTERNAL_FORMAT'],
        ['ORACLE', 'MTL_SYSTEM_ITEMS_B',  'oracle_ebs/', '.*MTL_SYSTEM_ITEMS_B.*[.]csv',  'CSV_EXTERNAL_FORMAT'],
        ['ORACLE', 'OE_ORDER_HEADERS_ALL','oracle_ebs/', '.*OE_ORDER_HEADERS_ALL.*[.]csv','CSV_EXTERNAL_FORMAT'],
        ['ORACLE', 'OE_ORDER_LINES_ALL',  'oracle_ebs/', '.*OE_ORDER_LINES_ALL.*[.]csv',  'CSV_EXTERNAL_FORMAT'],
        ['ORACLE', 'AP_INVOICES_ALL',     'oracle_ebs/', '.*AP_INVOICES_ALL.*[.]csv',     'CSV_EXTERNAL_FORMAT'],
        ['ORACLE', 'RA_CUSTOMER_TRX_ALL', 'oracle_ebs/', '.*RA_CUSTOMER_TRX_ALL.*[.]csv', 'CSV_EXTERNAL_FORMAT'],
        ['ORACLE', 'GL_JE_LINES',         'oracle_ebs/', '.*GL_JE_LINES.*[.]csv',         'CSV_EXTERNAL_FORMAT'],
        ['ORACLE', 'HR_ALL_PEOPLE_F',     'oracle_ebs/', '.*HR_ALL_PEOPLE_F.*[.]csv',     'CSV_EXTERNAL_FORMAT'],

        // ── Workday (JSON) ───────────────────────────────────────────
        ['WORKDAY', 'WORKERS',           'workday/', '.*Workers.*[.]json',           'JSON_EXT_FORMAT'],
        ['WORKDAY', 'ORGANIZATIONS',     'workday/', '.*Organizations.*[.]json',     'JSON_EXT_FORMAT'],
        ['WORKDAY', 'JOB_PROFILES',      'workday/', '.*Job_Profiles.*[.]json',      'JSON_EXT_FORMAT'],
        ['WORKDAY', 'COMPENSATION',      'workday/', '.*Compensation.*[.]json',      'JSON_EXT_FORMAT'],
        ['WORKDAY', 'TIME_OFF',          'workday/', '.*Time_Off.*[.]json',          'JSON_EXT_FORMAT'],
        ['WORKDAY', 'BENEFIT_ELECTIONS', 'workday/', '.*Benefit_Elections.*[.]json', 'JSON_EXT_FORMAT'],

        // ── ServiceNow Core (CSV) ────────────────────────────────────
        ['SERVICENOW', 'SYS_USER',        'servicenow/', '.*sys_user.*[.]csv',        'CSV_EXTERNAL_FORMAT'],
        ['SERVICENOW', 'INCIDENT',        'servicenow/', '.*incident.*[.]csv',        'CSV_EXTERNAL_FORMAT'],
        ['SERVICENOW', 'CHANGE_REQUEST',  'servicenow/', '.*change_request.*[.]csv',  'CSV_EXTERNAL_FORMAT'],
        ['SERVICENOW', 'PROBLEM',         'servicenow/', '.*problem.*[.]csv',         'CSV_EXTERNAL_FORMAT'],
        ['SERVICENOW', 'CMDB_CI',         'servicenow/', '.*cmdb_ci.*[.]csv',         'CSV_EXTERNAL_FORMAT'],
        ['SERVICENOW', 'SC_REQUEST',      'servicenow/', '.*sc_request.*[.]csv',      'CSV_EXTERNAL_FORMAT'],
        ['SERVICENOW', 'KB_KNOWLEDGE',    'servicenow/', '.*kb_knowledge.*[.]csv',    'CSV_EXTERNAL_FORMAT'],

        // ── DCIM ServiceNow (CSV) ─────────────────────────────────────
        ['DCIM_SERVICENOW', 'DATA_CENTERS',     'dcim/servicenow/', '.*data_centers.*[.]csv',     'CSV_EXTERNAL_FORMAT'],
        ['DCIM_SERVICENOW', 'HALLS',            'dcim/servicenow/', '.*halls.*[.]csv',            'CSV_EXTERNAL_FORMAT'],
        ['DCIM_SERVICENOW', 'RACKS',            'dcim/servicenow/', '.*racks.*[.]csv',            'CSV_EXTERNAL_FORMAT'],
        ['DCIM_SERVICENOW', 'SWITCHES',         'dcim/servicenow/', '.*switches.*[.]csv',         'CSV_EXTERNAL_FORMAT'],
        ['DCIM_SERVICENOW', 'PORTS',            'dcim/servicenow/', '.*ports.*[.]csv',            'CSV_EXTERNAL_FORMAT'],
        ['DCIM_SERVICENOW', 'INCIDENTS',        'dcim/servicenow/', '.*incidents.*[.]csv',        'CSV_EXTERNAL_FORMAT'],
        ['DCIM_SERVICENOW', 'CHANGE_REQUESTS',  'dcim/servicenow/', '.*change_requests.*[.]csv',  'CSV_EXTERNAL_FORMAT'],

        // ── DCIM Siemens XML tables are created via explicit DDL in Section 6
        // ── Additional XML tables (same pattern as FACILITIES above):
        ['DCIM_SIEMENS', 'ZONES_XML_RAW',               'dcim/siemens_dcim/', '.*zones.*[.]xml',               'CSV_EXTERNAL_FORMAT'],
        ['DCIM_SIEMENS', 'POWER_DISTRIBUTION_UNITS_XML_RAW', 'dcim/siemens_dcim/', '.*power_distribution_units.*[.]xml', 'CSV_EXTERNAL_FORMAT'],
        ['DCIM_SIEMENS', 'COOLING_LOOPS_XML_RAW',        'dcim/siemens_dcim/', '.*cooling_loops.*[.]xml',       'CSV_EXTERNAL_FORMAT'],
        ['DCIM_SIEMENS', 'RACK_INVENTORY_XML_RAW',       'dcim/siemens_dcim/', '.*rack_inventory.*[.]xml',      'CSV_EXTERNAL_FORMAT'],
        ['DCIM_SIEMENS', 'BMS_SENSORS_XML_RAW',          'dcim/siemens_dcim/', '.*bms_sensors.*[.]xml',         'CSV_EXTERNAL_FORMAT'],
        ['DCIM_SIEMENS', 'MAINTENANCE_ORDERS_XML_RAW',   'dcim/siemens_dcim/', '.*maintenance_orders.*[.]xml',  'CSV_EXTERNAL_FORMAT'],

        // ── DCIM Telemetry (Parquet) ──────────────────────────────────
        ['DCIM_TELEMETRY', 'PORT_METRICS',           'dcim/telemetry/', '.*port_metrics.*[.]parquet',           'PARQUET_EXT_FORMAT'],
        ['DCIM_TELEMETRY', 'SWITCH_HEALTH',          'dcim/telemetry/', '.*switch_health.*[.]parquet',          'PARQUET_EXT_FORMAT'],
        ['DCIM_TELEMETRY', 'ENVIRONMENTAL_SENSORS',  'dcim/telemetry/', '.*environmental_sensors.*[.]parquet',  'PARQUET_EXT_FORMAT'],
        ['DCIM_TELEMETRY', 'ALERTS',                 'dcim/telemetry/', '.*alerts.*[.]parquet',                 'PARQUET_EXT_FORMAT'],

        // ── DCIM Workday (JSON) ───────────────────────────────────────
        ['DCIM_WORKDAY', 'TEAMS',                'dcim/workday_dcim/', '.*teams.*[.]json',                'JSON_EXT_FORMAT'],
        ['DCIM_WORKDAY', 'TECHNICIANS',          'dcim/workday_dcim/', '.*technicians.*[.]json',          'JSON_EXT_FORMAT'],
        ['DCIM_WORKDAY', 'CERTIFICATIONS',       'dcim/workday_dcim/', '.*certifications.*[.]json',       'JSON_EXT_FORMAT'],
        ['DCIM_WORKDAY', 'SHIFTS',               'dcim/workday_dcim/', '.*shifts.*[.]json',               'JSON_EXT_FORMAT'],
        ['DCIM_WORKDAY', 'SKILL_ASSIGNMENTS',    'dcim/workday_dcim/', '.*skill_assignments.*[.]json',    'JSON_EXT_FORMAT'],
        ['DCIM_WORKDAY', 'TIME_OFF',             'dcim/workday_dcim/', '.*time_off.*[.]json',             'JSON_EXT_FORMAT'],
        ['DCIM_WORKDAY', 'TRAINING_COMPLETIONS', 'dcim/workday_dcim/', '.*training_completions.*[.]json', 'JSON_EXT_FORMAT']
    ];

    var results = [];
    var success = 0, failed = 0;

    for (var i = 0; i < tables.length; i++) {
        var t = tables[i];
        var callSql = `CALL RAW_DEV.STAGING.CREATE_S3_EXTERNAL_TABLE(
            '${t[0]}', '${t[1]}', '${t[2]}', '${t[3]}', '${t[4]}'
        )`;
        try {
            var stmt   = snowflake.createStatement({sqlText: callSql});
            var result = stmt.execute();
            result.next();
            var msg = result.getColumnValue(1);
            results.push({table: t[0] + '.' + t[1], status: msg});
            if (msg.startsWith('SUCCESS')) { success++; } else { failed++; }
        } catch(e) {
            results.push({table: t[0] + '.' + t[1], status: 'ERROR: ' + e.message});
            failed++;
        }
    }

    results.push({summary: 'Created: ' + success + ', Failed: ' + failed + ' of ' + tables.length});
    return results;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 8: REFRESH PROCEDURE
-- ═══════════════════════════════════════════════════════════════════════════
--
-- External table metadata must be refreshed when new S3 files are added.
-- Run after each upload_to_s3.py execution.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE RAW_DEV.STAGING.REFRESH_ALL_S3_EXTERNAL_TABLES()
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var schemas = ['SAP', 'SALESFORCE', 'ORACLE', 'WORKDAY', 'SERVICENOW',
                   'DCIM_SERVICENOW', 'DCIM_SIEMENS', 'DCIM_TELEMETRY', 'DCIM_WORKDAY'];
    // FHIR tables are views over raw XML tables; refresh the raw backing tables
    var fhirRaw = ['PATIENT_XML_RAW'];

    var results = [];
    var success = 0, failed = 0;

    // Refresh by schema
    for (var s = 0; s < schemas.length; s++) {
        var schema = schemas[s];
        try {
            var listSql = `
                SELECT TABLE_NAME
                FROM INFORMATION_SCHEMA.TABLES
                WHERE TABLE_SCHEMA = '${schema}'
                  AND TABLE_TYPE = 'EXTERNAL TABLE'
                  AND TABLE_CATALOG = 'RAW_DEV'
            `;
            var listStmt = snowflake.createStatement({sqlText: listSql});
            var listResult = listStmt.execute();

            while (listResult.next()) {
                var tbl = listResult.getColumnValue(1);
                try {
                    snowflake.createStatement({
                        sqlText: `ALTER EXTERNAL TABLE RAW_DEV.${schema}.${tbl} REFRESH`
                    }).execute();
                    results.push({table: schema + '.' + tbl, status: 'REFRESHED'});
                    success++;
                } catch(e) {
                    results.push({table: schema + '.' + tbl, status: 'ERROR: ' + e.message});
                    failed++;
                }
            }
        } catch(e) {
            results.push({schema: schema, status: 'ERROR listing tables: ' + e.message});
            failed++;
        }
    }

    // Refresh FHIR raw backing tables
    for (var f = 0; f < fhirRaw.length; f++) {
        var fhirTbl = 'FHIR.' + fhirRaw[f];
        try {
            snowflake.createStatement({
                sqlText: `ALTER EXTERNAL TABLE RAW_DEV.${fhirTbl} REFRESH`
            }).execute();
            results.push({table: fhirTbl, status: 'REFRESHED'});
            success++;
        } catch(e) {
            results.push({table: fhirTbl, status: 'ERROR: ' + e.message});
            failed++;
        }
    }

    results.push({summary: 'Refreshed: ' + success + ', Failed: ' + failed});
    return results;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 9: GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

GRANT USAGE ON INTEGRATION S3_RAW_INTEGRATION TO ROLE DATA_ENGINEER;
GRANT USAGE ON STAGE RAW_DEV.STAGING.S3_RAW_STAGE TO ROLE DATA_ENGINEER;

GRANT USAGE ON FILE FORMAT RAW_DEV.STAGING.CSV_EXTERNAL_FORMAT  TO ROLE DATA_ENGINEER;
GRANT USAGE ON FILE FORMAT RAW_DEV.STAGING.PARQUET_EXT_FORMAT   TO ROLE DATA_ENGINEER;
GRANT USAGE ON FILE FORMAT RAW_DEV.STAGING.JSON_EXT_FORMAT      TO ROLE DATA_ENGINEER;

GRANT USAGE ON PROCEDURE RAW_DEV.STAGING.CREATE_S3_EXTERNAL_TABLE(VARCHAR,VARCHAR,VARCHAR,VARCHAR,VARCHAR)
    TO ROLE DATA_ENGINEER;
GRANT USAGE ON PROCEDURE RAW_DEV.STAGING.CREATE_ALL_S3_EXTERNAL_TABLES()
    TO ROLE DATA_ENGINEER;
GRANT USAGE ON PROCEDURE RAW_DEV.STAGING.REFRESH_ALL_S3_EXTERNAL_TABLES()
    TO ROLE DATA_ENGINEER;

-- DCIM schema grants
GRANT ALL ON SCHEMA RAW_DEV.DCIM_SERVICENOW TO ROLE DATA_ENGINEER;
GRANT ALL ON SCHEMA RAW_DEV.DCIM_SIEMENS    TO ROLE DATA_ENGINEER;
GRANT ALL ON SCHEMA RAW_DEV.DCIM_TELEMETRY  TO ROLE DATA_ENGINEER;
GRANT ALL ON SCHEMA RAW_DEV.DCIM_WORKDAY    TO ROLE DATA_ENGINEER;

GRANT USAGE ON SCHEMA RAW_DEV.DCIM_SERVICENOW TO ROLE DATA_STEWARD;
GRANT USAGE ON SCHEMA RAW_DEV.DCIM_SIEMENS    TO ROLE DATA_STEWARD;
GRANT USAGE ON SCHEMA RAW_DEV.DCIM_TELEMETRY  TO ROLE DATA_STEWARD;
GRANT USAGE ON SCHEMA RAW_DEV.DCIM_WORKDAY    TO ROLE DATA_STEWARD;

GRANT SELECT ON ALL TABLES  IN SCHEMA RAW_DEV.DCIM_SERVICENOW TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL TABLES  IN SCHEMA RAW_DEV.DCIM_SIEMENS    TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL TABLES  IN SCHEMA RAW_DEV.DCIM_TELEMETRY  TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL TABLES  IN SCHEMA RAW_DEV.DCIM_WORKDAY    TO ROLE DATA_STEWARD;

GRANT SELECT ON ALL VIEWS   IN SCHEMA RAW_DEV.DCIM_SIEMENS    TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL VIEWS   IN SCHEMA RAW_DEV.FHIR             TO ROLE DATA_STEWARD;

GRANT SELECT ON FUTURE TABLES IN SCHEMA RAW_DEV.DCIM_SERVICENOW TO ROLE DATA_STEWARD;
GRANT SELECT ON FUTURE TABLES IN SCHEMA RAW_DEV.DCIM_SIEMENS    TO ROLE DATA_STEWARD;
GRANT SELECT ON FUTURE TABLES IN SCHEMA RAW_DEV.DCIM_TELEMETRY  TO ROLE DATA_STEWARD;
GRANT SELECT ON FUTURE TABLES IN SCHEMA RAW_DEV.DCIM_WORKDAY    TO ROLE DATA_STEWARD;

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 10: DEPLOYMENT EXECUTION
-- ═══════════════════════════════════════════════════════════════════════════
--
-- After storage integration trust policy is locked (terraform apply with real
-- IAM principal), upload data to S3, then execute the following:
-- ═══════════════════════════════════════════════════════════════════════════

-- Step A: Verify storage integration is connected
-- DESCRIBE INTEGRATION S3_RAW_INTEGRATION;

-- Step B: Refresh stage directory listing
-- ALTER STAGE RAW_DEV.STAGING.S3_RAW_STAGE REFRESH;

-- Step C: Create all external tables (runs INFER_SCHEMA per file)
-- CALL RAW_DEV.STAGING.CREATE_ALL_S3_EXTERNAL_TABLES();

-- Step D: Spot-check — query the three reference external tables directly
-- SELECT * FROM RAW_DEV.SAP.KNA1           LIMIT 5;   -- Parquet
-- SELECT * FROM RAW_DEV.SALESFORCE.ACCOUNT LIMIT 5;   -- CSV
-- SELECT * FROM RAW_DEV.WORKDAY.WORKERS    LIMIT 5;   -- JSON
-- SELECT * FROM RAW_DEV.FHIR.PATIENT       LIMIT 5;   -- XML (via view)

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 11: LINEAGE VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════
--
-- After executing a query that touches curated → raw → S3, run these to
-- confirm end-to-end lineage is visible in Snowflake Access History.
-- ═══════════════════════════════════════════════════════════════════════════

-- 11a. Trigger a lineage-generating query (refresh Dynamic Tables, then query Semantic View)
-- ALTER DYNAMIC TABLE CURATED_DEV.SAP.DIM_CUSTOMER REFRESH;
-- SELECT * FROM SEM_DEV.SAP.SALES_ANALYTICS LIMIT 10;

-- 11b. Verify base object lineage — S3 external tables appear as base objects
/*
SELECT
    query_start_time,
    query_text,
    f.value:objectName::VARCHAR  AS base_object,
    f.value:objectDomain::VARCHAR AS object_type
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY,
     LATERAL FLATTEN(input => BASE_OBJECTS_ACCESSED) f
WHERE f.value:objectDomain::VARCHAR = 'Table'
  AND f.value:objectName::VARCHAR ILIKE 'RAW_DEV.%'
  AND query_start_time >= DATEADD('hour', -1, CURRENT_TIMESTAMP())
ORDER BY query_start_time DESC
LIMIT 50;
*/

-- 11c. Show all external tables created by this script
/*
SELECT
    TABLE_CATALOG,
    TABLE_SCHEMA,
    TABLE_NAME,
    TABLE_TYPE,
    COMMENT,
    LAST_ALTERED
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'EXTERNAL TABLE'
  AND TABLE_CATALOG = 'RAW_DEV'
ORDER BY TABLE_SCHEMA, TABLE_NAME;
*/

-- 11d. Confirm _S3_FILE_PATH lineage column is populated for each format
/*
SELECT '_SAP_KNA1_PARQUET'        AS source, _S3_FILE_PATH FROM RAW_DEV.SAP.KNA1           LIMIT 1
UNION ALL
SELECT '_SALESFORCE_ACCOUNT_CSV'  AS source, _S3_FILE_PATH FROM RAW_DEV.SALESFORCE.ACCOUNT LIMIT 1
UNION ALL
SELECT '_WORKDAY_WORKERS_JSON'    AS source, _S3_FILE_PATH FROM RAW_DEV.WORKDAY.WORKERS    LIMIT 1
UNION ALL
SELECT '_FHIR_PATIENT_XML'        AS source, _S3_FILE_PATH FROM RAW_DEV.FHIR.PATIENT       LIMIT 1
UNION ALL
SELECT '_DCIM_TELEMETRY_PARQUET'  AS source, _S3_FILE_PATH FROM RAW_DEV.DCIM_TELEMETRY.PORT_METRICS LIMIT 1;
*/

SELECT '03b_s3_external_raw_layer.sql completed successfully' AS STATUS;
