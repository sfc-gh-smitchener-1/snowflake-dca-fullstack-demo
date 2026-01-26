-- ============================================================================
-- RAW LAYER - Dynamic Schema Inference from Source Systems
-- ============================================================================
-- 
-- This script creates RAW layer tables DYNAMICALLY based on the source system
-- data files generated. It uses Snowflake's INFER_SCHEMA to automatically
-- detect columns from CSV/JSON/Parquet files.
--
-- SUPPORTED SOURCE SYSTEMS:
--   - SAP S/4HANA:  KNA1, MARA, VBAK, VBAP, PA0001, PA0002, LFA1, EKKO, BKPF
--   - Salesforce:   Account, Contact, Opportunity, Case, Lead, Product2, Campaign, Task
--   - Oracle EBS:   HZ_PARTIES, OE_ORDER_*, AP_*, RA_*, GL_JE_LINES, HR_*, MTL_*
--   - FHIR R4:      Patient, Practitioner, Encounter, Condition, Observation, etc.
--   - Workday:      Workers, Organizations, Compensation, Time_Off, Benefits
--   - ServiceNow:   incident, change_request, problem, cmdb_ci, sc_request
--
-- The data generator automatically includes SCD Type 2 columns:
--   _LOADED_AT, _SOURCE_SYSTEM, _SOURCE_TABLE, _ROW_HASH, _IS_CURRENT, 
--   _VALID_FROM, _VALID_TO
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE RAW_DEV;
USE WAREHOUSE TRANSFORM_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- STAGING AREA FOR DATA FILES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE SCHEMA IF NOT EXISTS RAW_DEV.STAGING
    COMMENT = 'Staging area for source system data files';

USE SCHEMA RAW_DEV.STAGING;

-- Internal stage for data files
CREATE STAGE IF NOT EXISTS DATA_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Stage for source system data files (CSV, JSON, Parquet)';

-- File formats for INFER_SCHEMA (needs to see headers)
CREATE FILE FORMAT IF NOT EXISTS CSV_INFER_FORMAT
    TYPE = 'CSV'
    PARSE_HEADER = TRUE
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('', 'NULL', 'null', 'None')
    EMPTY_FIELD_AS_NULL = TRUE
    COMPRESSION = AUTO;

-- File format for COPY INTO (skip header, load by position)
CREATE FILE FORMAT IF NOT EXISTS CSV_FORMAT
    TYPE = 'CSV'
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('', 'NULL', 'null', 'None')
    EMPTY_FIELD_AS_NULL = TRUE
    COMPRESSION = AUTO;

CREATE FILE FORMAT IF NOT EXISTS JSON_FORMAT
    TYPE = 'JSON'
    COMPRESSION = AUTO
    STRIP_OUTER_ARRAY = TRUE;

CREATE FILE FORMAT IF NOT EXISTS PARQUET_FORMAT
    TYPE = 'PARQUET'
    COMPRESSION = AUTO;

-- ═══════════════════════════════════════════════════════════════════════════
-- SOURCE SYSTEM SCHEMAS
-- ═══════════════════════════════════════════════════════════════════════════

-- SAP S/4HANA
CREATE SCHEMA IF NOT EXISTS RAW_DEV.SAP
    COMMENT = 'SAP ECC/S4HANA source data (KNA1, MARA, VBAK, etc.)';

-- Salesforce
CREATE SCHEMA IF NOT EXISTS RAW_DEV.SALESFORCE
    COMMENT = 'Salesforce CRM source data (Account, Opportunity, etc.)';

-- Oracle EBS
CREATE SCHEMA IF NOT EXISTS RAW_DEV.ORACLE
    COMMENT = 'Oracle E-Business Suite source data (HZ_PARTIES, OE_ORDER_*, etc.)';

-- FHIR R4
CREATE SCHEMA IF NOT EXISTS RAW_DEV.FHIR
    COMMENT = 'HL7 FHIR R4 healthcare resources (Patient, Encounter, etc.)';

-- Workday
CREATE SCHEMA IF NOT EXISTS RAW_DEV.WORKDAY
    COMMENT = 'Workday HCM source data (Workers, Compensation, etc.)';

-- ServiceNow
CREATE SCHEMA IF NOT EXISTS RAW_DEV.SERVICENOW
    COMMENT = 'ServiceNow ITSM source data (incident, change_request, etc.)';

-- ═══════════════════════════════════════════════════════════════════════════
-- DYNAMIC TABLE CREATION PROCEDURE (JavaScript)
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- This procedure:
--   1. Uses INFER_SCHEMA to detect columns from staged files
--   2. Creates tables dynamically with proper data types
--   3. Loads the data using COPY INTO
--
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE RAW_DEV.STAGING.INFER_AND_CREATE_TABLE(
    P_SOURCE_SYSTEM VARCHAR,
    P_TABLE_NAME VARCHAR,
    P_FILE_FORMAT VARCHAR,
    P_STAGE_PATH VARCHAR
)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var schemaName = 'RAW_DEV.' + P_SOURCE_SYSTEM.toUpperCase();
    var fullTableName = schemaName + '.' + P_TABLE_NAME.toUpperCase();
    var fileFormatName = 'RAW_DEV.STAGING.' + P_FILE_FORMAT.toUpperCase() + '_FORMAT';
    
    try {
        // Step 1: Infer schema from the staged file
        var inferSql = `
            SELECT LISTAGG('"' || COLUMN_NAME || '" ' || TYPE, ', ') 
                   WITHIN GROUP (ORDER BY ORDER_ID) AS COL_DEFS
            FROM TABLE(
                INFER_SCHEMA(
                    LOCATION => '@RAW_DEV.STAGING.DATA_STAGE/${P_STAGE_PATH}',
                    FILE_FORMAT => '${fileFormatName}',
                    MAX_RECORDS_PER_FILE => 1000
                )
            )
        `;
        
        var inferStmt = snowflake.createStatement({sqlText: inferSql});
        var inferResult = inferStmt.execute();
        
        if (!inferResult.next()) {
            return 'ERROR: Could not infer schema from ' + P_STAGE_PATH;
        }
        
        var columnDefs = inferResult.getColumnValue(1);
        
        if (!columnDefs || columnDefs.trim() === '') {
            return 'ERROR: No columns inferred from ' + P_STAGE_PATH;
        }
        
        // Step 2: Create the table
        var createSql = `CREATE OR REPLACE TABLE ${fullTableName} (${columnDefs}) 
                         COMMENT = 'Auto-generated from ${P_STAGE_PATH}'`;
        
        var createStmt = snowflake.createStatement({sqlText: createSql});
        createStmt.execute();
        
        // Step 3: Load data (columns already in correct order from INFER_SCHEMA)
        var copySql = `COPY INTO ${fullTableName} 
                       FROM @RAW_DEV.STAGING.DATA_STAGE/${P_STAGE_PATH}
                       FILE_FORMAT = ${fileFormatName}
                       ON_ERROR = CONTINUE`;
        
        var copyStmt = snowflake.createStatement({sqlText: copySql});
        copyStmt.execute();
        
        // Step 4: Get row count
        var countSql = `SELECT COUNT(*) FROM ${fullTableName}`;
        var countStmt = snowflake.createStatement({sqlText: countSql});
        var countResult = countStmt.execute();
        countResult.next();
        var rowCount = countResult.getColumnValue(1);
        
        return 'SUCCESS: Created ' + fullTableName + ' with ' + rowCount + ' rows';
        
    } catch (err) {
        return 'ERROR: ' + err.message;
    }
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPER: LIST AVAILABLE SOURCE SYSTEM FILES (JavaScript)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE RAW_DEV.STAGING.LIST_SOURCE_FILES(
    P_SOURCE_SYSTEM VARCHAR
)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
AS
$$
    var folderMap = {
        'SAP': 'sap_s4hana',
        'SALESFORCE': 'salesforce',
        'ORACLE': 'oracle_ebs',
        'FHIR': 'fhir_r4',
        'WORKDAY': 'workday',
        'SERVICENOW': 'servicenow'
    };
    
    var folder = folderMap[P_SOURCE_SYSTEM.toUpperCase()] || P_SOURCE_SYSTEM.toLowerCase();
    
    try {
        var listSql = `LIST @RAW_DEV.STAGING.DATA_STAGE/${folder}/`;
        var stmt = snowflake.createStatement({sqlText: listSql});
        var result = stmt.execute();
        
        var files = [];
        while (result.next()) {
            files.push(result.getColumnValue(1));
        }
        
        if (files.length === 0) {
            return 'No files found in ' + folder + '/';
        }
        
        return 'Files in ' + folder + '/:\n' + files.join('\n');
        
    } catch (err) {
        return 'ERROR: ' + err.message;
    }
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- GOVERNANCE TAG APPLICATION (JavaScript)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE RAW_DEV.STAGING.APPLY_SOURCE_SYSTEM_TAGS(
    P_SOURCE_SYSTEM VARCHAR,
    P_TABLE_NAME VARCHAR
)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var fullTableName = 'RAW_DEV.' + P_SOURCE_SYSTEM.toUpperCase() + '.' + P_TABLE_NAME.toUpperCase();
    
    var domainMap = {
        'SAP': {domain: 'ERP', classification: 'CONFIDENTIAL'},
        'SALESFORCE': {domain: 'CRM', classification: 'CONFIDENTIAL'},
        'ORACLE': {domain: 'ERP', classification: 'CONFIDENTIAL'},
        'FHIR': {domain: 'HEALTHCARE', classification: 'RESTRICTED'},
        'WORKDAY': {domain: 'HCM', classification: 'RESTRICTED'},
        'SERVICENOW': {domain: 'ITSM', classification: 'INTERNAL'}
    };
    
    var config = domainMap[P_SOURCE_SYSTEM.toUpperCase()] || {domain: 'OTHER', classification: 'INTERNAL'};
    
    try {
        var tagSql = `ALTER TABLE ${fullTableName} SET TAG 
            GOVERNANCE.TAGS.DATA_CLASSIFICATION = '${config.classification}',
            GOVERNANCE.TAGS.DATA_DOMAIN = '${config.domain}',
            GOVERNANCE.TAGS.DATA_QUALITY_TIER = 'BRONZE',
            GOVERNANCE.TAGS.SOURCE_SYSTEM = '${P_SOURCE_SYSTEM.toUpperCase()}'`;
        
        var stmt = snowflake.createStatement({sqlText: tagSql});
        stmt.execute();
        
        return 'SUCCESS: Applied tags to ' + fullTableName;
        
    } catch (err) {
        return 'WARNING: Could not apply tags - ' + err.message;
    }
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANT ACCESS
-- ═══════════════════════════════════════════════════════════════════════════

-- Staging access
GRANT USAGE ON SCHEMA RAW_DEV.STAGING TO ROLE DATA_ENGINEER;
GRANT READ, WRITE ON STAGE RAW_DEV.STAGING.DATA_STAGE TO ROLE DATA_ENGINEER;
GRANT USAGE ON PROCEDURE RAW_DEV.STAGING.INFER_AND_CREATE_TABLE(VARCHAR, VARCHAR, VARCHAR, VARCHAR) TO ROLE DATA_ENGINEER;
GRANT USAGE ON PROCEDURE RAW_DEV.STAGING.LIST_SOURCE_FILES(VARCHAR) TO ROLE DATA_ENGINEER;

-- Source system schema access for DATA_ENGINEER
GRANT ALL ON SCHEMA RAW_DEV.SAP TO ROLE DATA_ENGINEER;
GRANT ALL ON SCHEMA RAW_DEV.SALESFORCE TO ROLE DATA_ENGINEER;
GRANT ALL ON SCHEMA RAW_DEV.ORACLE TO ROLE DATA_ENGINEER;
GRANT ALL ON SCHEMA RAW_DEV.FHIR TO ROLE DATA_ENGINEER;
GRANT ALL ON SCHEMA RAW_DEV.WORKDAY TO ROLE DATA_ENGINEER;
GRANT ALL ON SCHEMA RAW_DEV.SERVICENOW TO ROLE DATA_ENGINEER;

-- Read access for DATA_STEWARD
GRANT USAGE ON SCHEMA RAW_DEV.SAP TO ROLE DATA_STEWARD;
GRANT USAGE ON SCHEMA RAW_DEV.SALESFORCE TO ROLE DATA_STEWARD;
GRANT USAGE ON SCHEMA RAW_DEV.ORACLE TO ROLE DATA_STEWARD;
GRANT USAGE ON SCHEMA RAW_DEV.FHIR TO ROLE DATA_STEWARD;
GRANT USAGE ON SCHEMA RAW_DEV.WORKDAY TO ROLE DATA_STEWARD;
GRANT USAGE ON SCHEMA RAW_DEV.SERVICENOW TO ROLE DATA_STEWARD;

GRANT SELECT ON ALL TABLES IN SCHEMA RAW_DEV.SAP TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL TABLES IN SCHEMA RAW_DEV.SALESFORCE TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL TABLES IN SCHEMA RAW_DEV.ORACLE TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL TABLES IN SCHEMA RAW_DEV.FHIR TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL TABLES IN SCHEMA RAW_DEV.WORKDAY TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL TABLES IN SCHEMA RAW_DEV.SERVICENOW TO ROLE DATA_STEWARD;

-- Future grants
GRANT SELECT ON FUTURE TABLES IN SCHEMA RAW_DEV.SAP TO ROLE DATA_STEWARD;
GRANT SELECT ON FUTURE TABLES IN SCHEMA RAW_DEV.SALESFORCE TO ROLE DATA_STEWARD;
GRANT SELECT ON FUTURE TABLES IN SCHEMA RAW_DEV.ORACLE TO ROLE DATA_STEWARD;
GRANT SELECT ON FUTURE TABLES IN SCHEMA RAW_DEV.FHIR TO ROLE DATA_STEWARD;
GRANT SELECT ON FUTURE TABLES IN SCHEMA RAW_DEV.WORKDAY TO ROLE DATA_STEWARD;
GRANT SELECT ON FUTURE TABLES IN SCHEMA RAW_DEV.SERVICENOW TO ROLE DATA_STEWARD;

-- ═══════════════════════════════════════════════════════════════════════════
-- EXAMPLE: MANUAL TABLE CREATION (When schema is known)
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- For known source systems, you can also create tables explicitly.
-- These serve as reference implementations.
-- Commented out - use INFER_AND_CREATE_TABLE for dynamic creation.
--
-- ═══════════════════════════════════════════════════════════════════════════

/*
-- SAP KNA1 (Customer Master) - Reference Implementation
CREATE TABLE IF NOT EXISTS RAW_DEV.SAP.KNA1_TEMPLATE (
    MANDT VARCHAR(3),
    KUNNR VARCHAR(10),
    NAME1 VARCHAR(35),
    NAME2 VARCHAR(35),
    SORTL VARCHAR(10),
    STRAS VARCHAR(35),
    ORT01 VARCHAR(35),
    PSTLZ VARCHAR(10),
    LAND1 VARCHAR(3),
    REGIO VARCHAR(3),
    SPRAS VARCHAR(2),
    TELF1 VARCHAR(16),
    TELFX VARCHAR(16),
    SMTP_ADDR VARCHAR(241),
    KTOKD VARCHAR(4),
    ERDAT VARCHAR(8),
    ERNAM VARCHAR(12),
    LOEVM VARCHAR(1),
    SPERR VARCHAR(1),
    BRSCH VARCHAR(4),
    KUKLA VARCHAR(2),
    STCEG VARCHAR(20),
    "_LOADED_AT" TIMESTAMP_NTZ,
    "_SOURCE_SYSTEM" VARCHAR(100),
    "_SOURCE_TABLE" VARCHAR(100),
    "_ROW_HASH" VARCHAR(64),
    "_IS_CURRENT" BOOLEAN,
    "_VALID_FROM" TIMESTAMP_NTZ,
    "_VALID_TO" VARCHAR(50)
)
COMMENT = 'SAP KNA1 Customer Master template';

-- Salesforce Account - Reference Implementation
CREATE TABLE IF NOT EXISTS RAW_DEV.SALESFORCE.ACCOUNT_TEMPLATE (
    "Id" VARCHAR(18),
    "IsDeleted" BOOLEAN,
    "CreatedDate" VARCHAR(50),
    "CreatedById" VARCHAR(18),
    "LastModifiedDate" VARCHAR(50),
    "LastModifiedById" VARCHAR(18),
    "SystemModstamp" VARCHAR(50),
    "Name" VARCHAR(255),
    "Type" VARCHAR(255),
    "Industry" VARCHAR(255),
    "AnnualRevenue" NUMBER(18,2),
    "NumberOfEmployees" NUMBER,
    "Rating" VARCHAR(50),
    "BillingStreet" VARCHAR(255),
    "BillingCity" VARCHAR(255),
    "BillingState" VARCHAR(255),
    "BillingPostalCode" VARCHAR(50),
    "BillingCountry" VARCHAR(255),
    "ShippingStreet" VARCHAR(255),
    "ShippingCity" VARCHAR(255),
    "ShippingState" VARCHAR(255),
    "ShippingPostalCode" VARCHAR(50),
    "ShippingCountry" VARCHAR(255),
    "Phone" VARCHAR(50),
    "Fax" VARCHAR(50),
    "Website" VARCHAR(255),
    "OwnerId" VARCHAR(18),
    "Customer_Segment__c" VARCHAR(255),
    "Lifecycle_Stage__c" VARCHAR(255),
    "_LOADED_AT" TIMESTAMP_NTZ,
    "_SOURCE_SYSTEM" VARCHAR(100),
    "_SOURCE_TABLE" VARCHAR(100),
    "_ROW_HASH" VARCHAR(64),
    "_IS_CURRENT" BOOLEAN,
    "_VALID_FROM" TIMESTAMP_NTZ,
    "_VALID_TO" VARCHAR(50)
)
COMMENT = 'Salesforce Account template';

-- FHIR Patient - Reference Implementation
CREATE TABLE IF NOT EXISTS RAW_DEV.FHIR.PATIENT_TEMPLATE (
    "resourceType" VARCHAR(50),
    "id" VARCHAR(50),
    "identifier" VARIANT,
    "active" BOOLEAN,
    "name" VARIANT,
    "telecom" VARIANT,
    "gender" VARCHAR(20),
    "birthDate" VARCHAR(20),
    "address" VARIANT,
    "maritalStatus" VARIANT,
    "communication" VARIANT,
    "_LOADED_AT" TIMESTAMP_NTZ,
    "_SOURCE_SYSTEM" VARCHAR(100),
    "_SOURCE_TABLE" VARCHAR(100),
    "_ROW_HASH" VARCHAR(64),
    "_IS_CURRENT" BOOLEAN,
    "_VALID_FROM" TIMESTAMP_NTZ,
    "_VALID_TO" VARCHAR(50)
)
COMMENT = 'FHIR Patient template';
*/

-- ═══════════════════════════════════════════════════════════════════════════
-- USAGE INSTRUCTIONS
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- STEP 1: Generate source system data (local machine)
-- ───────────────────────────────────────────────────────────────────────────
-- cd tools
-- python data_generator.py --system sap --domain all --output ../data
-- python data_generator.py --system salesforce --domain all --output ../data
-- python data_generator.py --system fhir --domain all --format json --output ../data
--
-- STEP 2: Upload to Snowflake stage (SnowSQL or Snowsight)
-- ───────────────────────────────────────────────────────────────────────────
-- PUT file:///path/to/data/sap_s4hana/*.csv @RAW_DEV.STAGING.DATA_STAGE/sap_s4hana/ AUTO_COMPRESS=TRUE;
-- PUT file:///path/to/data/salesforce/*.csv @RAW_DEV.STAGING.DATA_STAGE/salesforce/ AUTO_COMPRESS=TRUE;
-- PUT file:///path/to/data/fhir_r4/*.json @RAW_DEV.STAGING.DATA_STAGE/fhir_r4/ AUTO_COMPRESS=TRUE;
--
-- STEP 3: List files to verify upload
-- ───────────────────────────────────────────────────────────────────────────
-- LIST @RAW_DEV.STAGING.DATA_STAGE/sap_s4hana/;
-- CALL RAW_DEV.STAGING.LIST_SOURCE_FILES('SAP');
--
-- STEP 4: Create tables and load data
-- ───────────────────────────────────────────────────────────────────────────
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SAP', 'KNA1', 'CSV', 'sap_s4hana/KNA1.csv');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SALESFORCE', 'ACCOUNT', 'CSV', 'salesforce/Account.csv');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('FHIR', 'PATIENT', 'JSON', 'fhir_r4/Patient.json');
--
-- STEP 5: Apply governance tags
-- ───────────────────────────────────────────────────────────────────────────
-- CALL RAW_DEV.STAGING.APPLY_SOURCE_SYSTEM_TAGS('SAP', 'KNA1');
--
-- STEP 6: Verify
-- ───────────────────────────────────────────────────────────────────────────
-- SHOW TABLES IN SCHEMA RAW_DEV.SAP;
-- SELECT COUNT(*) FROM RAW_DEV.SAP.KNA1;
-- SELECT * FROM RAW_DEV.SAP.KNA1 LIMIT 5;
--
-- ═══════════════════════════════════════════════════════════════════════════

SELECT '03_raw_layer.sql completed successfully' AS STATUS;
