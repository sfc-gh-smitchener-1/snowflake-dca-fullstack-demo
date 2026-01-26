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

-- File formats
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
-- DYNAMIC TABLE CREATION PROCEDURE
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- This procedure:
--   1. Scans the stage for files matching a source system pattern
--   2. Uses INFER_SCHEMA to detect columns
--   3. Creates tables dynamically with proper data types
--   4. Loads the data
--
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE RAW_DEV.STAGING.INFER_AND_CREATE_TABLE(
    p_source_system VARCHAR,      -- SAP, SALESFORCE, ORACLE, FHIR, WORKDAY, SERVICENOW
    p_table_name VARCHAR,         -- Table/object name (e.g., KNA1, Account, Patient)
    p_file_format VARCHAR,        -- CSV, JSON, or PARQUET
    p_stage_path VARCHAR          -- Path in stage (e.g., 'sap_s4hana/KNA1.csv')
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_schema_name VARCHAR;
    v_full_table_name VARCHAR;
    v_file_format_name VARCHAR;
    v_column_defs VARCHAR;
    v_create_sql VARCHAR;
    v_copy_sql VARCHAR;
    v_result VARCHAR;
BEGIN
    -- Map source system to schema
    v_schema_name := 'RAW_DEV.' || UPPER(p_source_system);
    v_full_table_name := v_schema_name || '.' || UPPER(p_table_name);
    v_file_format_name := 'RAW_DEV.STAGING.' || UPPER(p_file_format) || '_FORMAT';
    
    -- Generate column definitions from INFER_SCHEMA
    SELECT LISTAGG(
        '"' || COLUMN_NAME || '" ' || TYPE,
        ', '
    ) WITHIN GROUP (ORDER BY ORDER_ID)
    INTO v_column_defs
    FROM TABLE(
        INFER_SCHEMA(
            LOCATION => '@RAW_DEV.STAGING.DATA_STAGE/' || p_stage_path,
            FILE_FORMAT => v_file_format_name,
            MAX_RECORDS_PER_FILE => 1000
        )
    );
    
    -- If no columns inferred, return error
    IF (v_column_defs IS NULL OR v_column_defs = '') THEN
        RETURN 'ERROR: Could not infer schema from ' || p_stage_path;
    END IF;
    
    -- Create table using inferred schema
    v_create_sql := 'CREATE OR REPLACE TABLE ' || v_full_table_name || ' (' || v_column_defs || ')';
    v_create_sql := v_create_sql || ' COMMENT = ''Auto-generated from ' || p_stage_path || '''';
    
    EXECUTE IMMEDIATE v_create_sql;
    
    -- Load data based on file format
    IF (UPPER(p_file_format) = 'CSV') THEN
        v_copy_sql := 'COPY INTO ' || v_full_table_name || 
                      ' FROM @RAW_DEV.STAGING.DATA_STAGE/' || p_stage_path ||
                      ' FILE_FORMAT = ' || v_file_format_name ||
                      ' MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE' ||
                      ' ON_ERROR = CONTINUE';
    ELSEIF (UPPER(p_file_format) = 'JSON') THEN
        -- For JSON, we need to handle it differently - load into VARIANT first
        v_copy_sql := 'COPY INTO ' || v_full_table_name || 
                      ' FROM @RAW_DEV.STAGING.DATA_STAGE/' || p_stage_path ||
                      ' FILE_FORMAT = ' || v_file_format_name ||
                      ' MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE' ||
                      ' ON_ERROR = CONTINUE';
    ELSE
        v_copy_sql := 'COPY INTO ' || v_full_table_name || 
                      ' FROM @RAW_DEV.STAGING.DATA_STAGE/' || p_stage_path ||
                      ' FILE_FORMAT = ' || v_file_format_name ||
                      ' MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE' ||
                      ' ON_ERROR = CONTINUE';
    END IF;
    
    EXECUTE IMMEDIATE v_copy_sql;
    
    -- Get row count
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || v_full_table_name INTO v_result;
    
    RETURN 'SUCCESS: Created ' || v_full_table_name || ' with ' || v_result || ' rows';
    
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR: ' || SQLERRM;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- BULK LOAD PROCEDURE FOR SOURCE SYSTEM
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Loads ALL tables for a given source system by scanning the stage
--
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE RAW_DEV.STAGING.LOAD_SOURCE_SYSTEM(
    p_source_system VARCHAR,   -- SAP, SALESFORCE, ORACLE, FHIR, WORKDAY, SERVICENOW
    p_file_format VARCHAR      -- CSV or JSON
)
RETURNS TABLE (table_name VARCHAR, status VARCHAR, row_count NUMBER)
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_stage_folder VARCHAR;
    v_file_pattern VARCHAR;
    v_result_table RESULTSET;
BEGIN
    -- Map source system to stage folder
    CASE UPPER(p_source_system)
        WHEN 'SAP' THEN v_stage_folder := 'sap_s4hana';
        WHEN 'SALESFORCE' THEN v_stage_folder := 'salesforce';
        WHEN 'ORACLE' THEN v_stage_folder := 'oracle_ebs';
        WHEN 'FHIR' THEN v_stage_folder := 'fhir_r4';
        WHEN 'WORKDAY' THEN v_stage_folder := 'workday';
        WHEN 'SERVICENOW' THEN v_stage_folder := 'servicenow';
        ELSE v_stage_folder := LOWER(p_source_system);
    END CASE;
    
    -- Create temp table for results
    CREATE OR REPLACE TEMPORARY TABLE _load_results (
        table_name VARCHAR,
        status VARCHAR,
        row_count NUMBER
    );
    
    -- Get list of files in stage folder
    v_file_pattern := '@RAW_DEV.STAGING.DATA_STAGE/' || v_stage_folder || '/';
    
    -- List files and process each
    FOR file_rec IN (
        SELECT 
            REGEXP_REPLACE("name", '.*/', '') AS file_name,
            REGEXP_REPLACE(REGEXP_REPLACE("name", '.*/', ''), '\\.(csv|json|parquet)$', '') AS table_name
        FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
        WHERE "name" LIKE '%.' || LOWER(p_file_format)
    )
    DO
        DECLARE
            v_result VARCHAR;
            v_row_count NUMBER DEFAULT 0;
        BEGIN
            -- Call the infer and create procedure
            CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE(
                p_source_system,
                file_rec.table_name,
                p_file_format,
                v_stage_folder || '/' || file_rec.file_name
            ) INTO v_result;
            
            -- Get row count if successful
            IF (v_result LIKE 'SUCCESS%') THEN
                EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM RAW_DEV.' || UPPER(p_source_system) || '.' || UPPER(file_rec.table_name) INTO v_row_count;
            END IF;
            
            INSERT INTO _load_results VALUES (file_rec.table_name, v_result, v_row_count);
        END;
    END FOR;
    
    -- Return results
    v_result_table := (SELECT * FROM _load_results);
    RETURN TABLE(v_result_table);
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPER: LIST AVAILABLE SOURCE SYSTEM FILES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE RAW_DEV.STAGING.LIST_SOURCE_FILES(
    p_source_system VARCHAR
)
RETURNS TABLE (file_name VARCHAR, file_size NUMBER, last_modified TIMESTAMP_NTZ)
LANGUAGE SQL
AS
$$
DECLARE
    v_stage_folder VARCHAR;
BEGIN
    CASE UPPER(p_source_system)
        WHEN 'SAP' THEN v_stage_folder := 'sap_s4hana';
        WHEN 'SALESFORCE' THEN v_stage_folder := 'salesforce';
        WHEN 'ORACLE' THEN v_stage_folder := 'oracle_ebs';
        WHEN 'FHIR' THEN v_stage_folder := 'fhir_r4';
        WHEN 'WORKDAY' THEN v_stage_folder := 'workday';
        WHEN 'SERVICENOW' THEN v_stage_folder := 'servicenow';
        ELSE v_stage_folder := LOWER(p_source_system);
    END CASE;
    
    RETURN TABLE(
        SELECT 
            "name" AS file_name,
            "size" AS file_size,
            "last_modified" AS last_modified
        FROM DIRECTORY(@RAW_DEV.STAGING.DATA_STAGE)
        WHERE "name" LIKE v_stage_folder || '/%'
        ORDER BY "name"
    );
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- QUICK LOAD COMMANDS
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- After uploading files to the stage, use these commands:
--
-- 1. Upload files to stage:
--    PUT file:///path/to/data/sap_s4hana/*.csv @RAW_DEV.STAGING.DATA_STAGE/sap_s4hana/ AUTO_COMPRESS=TRUE;
--
-- 2. Load individual table:
--    CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SAP', 'KNA1', 'CSV', 'sap_s4hana/KNA1.csv');
--
-- 3. Load all tables for a source system:
--    CALL RAW_DEV.STAGING.LOAD_SOURCE_SYSTEM('SAP', 'CSV');
--
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- EXAMPLE: MANUAL TABLE CREATION (When schema is known)
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- For known source systems, you can also create tables explicitly.
-- These serve as reference implementations.
--
-- ═══════════════════════════════════════════════════════════════════════════

-- SAP KNA1 (Customer Master) - Reference Implementation
CREATE TABLE IF NOT EXISTS RAW_DEV.SAP.KNA1_TEMPLATE (
    -- SAP Key Fields
    MANDT VARCHAR(3),                          -- Client
    KUNNR VARCHAR(10),                         -- Customer Number
    
    -- General Data
    NAME1 VARCHAR(35),                         -- Name 1
    NAME2 VARCHAR(35),                         -- Name 2
    SORTL VARCHAR(10),                         -- Sort field
    STRAS VARCHAR(35),                         -- Street Address
    ORT01 VARCHAR(35),                         -- City
    PSTLZ VARCHAR(10),                         -- Postal Code
    LAND1 VARCHAR(3),                          -- Country Key
    REGIO VARCHAR(3),                          -- Region
    SPRAS VARCHAR(2),                          -- Language
    
    -- Communication
    TELF1 VARCHAR(16),                         -- Telephone 1
    TELFX VARCHAR(16),                         -- Fax
    SMTP_ADDR VARCHAR(241),                    -- Email
    
    -- Control Data
    KTOKD VARCHAR(4),                          -- Account Group
    ERDAT VARCHAR(8),                          -- Created Date (YYYYMMDD)
    ERNAM VARCHAR(12),                         -- Created By
    LOEVM VARCHAR(1),                          -- Deletion Flag
    SPERR VARCHAR(1),                          -- Central Block
    
    -- Classification
    BRSCH VARCHAR(4),                          -- Industry
    KUKLA VARCHAR(2),                          -- Customer Classification
    STCEG VARCHAR(20),                         -- VAT Number
    
    -- SCD Type 2 Columns (from data generator)
    "_LOADED_AT" TIMESTAMP_NTZ,
    "_SOURCE_SYSTEM" VARCHAR(100),
    "_SOURCE_TABLE" VARCHAR(100),
    "_ROW_HASH" VARCHAR(64),
    "_IS_CURRENT" BOOLEAN,
    "_VALID_FROM" TIMESTAMP_NTZ,
    "_VALID_TO" VARCHAR(50)
)
COMMENT = 'SAP KNA1 Customer Master template - use INFER_AND_CREATE_TABLE for dynamic creation';

-- Salesforce Account - Reference Implementation
CREATE TABLE IF NOT EXISTS RAW_DEV.SALESFORCE.ACCOUNT_TEMPLATE (
    -- System Fields
    "Id" VARCHAR(18),
    "IsDeleted" BOOLEAN,
    "CreatedDate" VARCHAR(50),
    "CreatedById" VARCHAR(18),
    "LastModifiedDate" VARCHAR(50),
    "LastModifiedById" VARCHAR(18),
    "SystemModstamp" VARCHAR(50),
    
    -- Account Fields
    "Name" VARCHAR(255),
    "Type" VARCHAR(255),
    "Industry" VARCHAR(255),
    "AnnualRevenue" NUMBER(18,2),
    "NumberOfEmployees" NUMBER,
    "Rating" VARCHAR(50),
    
    -- Address
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
    
    -- Contact
    "Phone" VARCHAR(50),
    "Fax" VARCHAR(50),
    "Website" VARCHAR(255),
    
    -- Ownership
    "OwnerId" VARCHAR(18),
    
    -- Custom Fields
    "Customer_Segment__c" VARCHAR(255),
    "Lifecycle_Stage__c" VARCHAR(255),
    
    -- SCD Type 2
    "_LOADED_AT" TIMESTAMP_NTZ,
    "_SOURCE_SYSTEM" VARCHAR(100),
    "_SOURCE_TABLE" VARCHAR(100),
    "_ROW_HASH" VARCHAR(64),
    "_IS_CURRENT" BOOLEAN,
    "_VALID_FROM" TIMESTAMP_NTZ,
    "_VALID_TO" VARCHAR(50)
)
COMMENT = 'Salesforce Account template - use INFER_AND_CREATE_TABLE for dynamic creation';

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
    
    -- SCD Type 2
    "_LOADED_AT" TIMESTAMP_NTZ,
    "_SOURCE_SYSTEM" VARCHAR(100),
    "_SOURCE_TABLE" VARCHAR(100),
    "_ROW_HASH" VARCHAR(64),
    "_IS_CURRENT" BOOLEAN,
    "_VALID_FROM" TIMESTAMP_NTZ,
    "_VALID_TO" VARCHAR(50)
)
COMMENT = 'FHIR Patient template - use INFER_AND_CREATE_TABLE for dynamic creation';

-- ═══════════════════════════════════════════════════════════════════════════
-- GOVERNANCE TAG APPLICATION (Applied after table creation)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE RAW_DEV.STAGING.APPLY_SOURCE_SYSTEM_TAGS(
    p_source_system VARCHAR,
    p_table_name VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_full_table_name VARCHAR;
    v_data_domain VARCHAR;
    v_classification VARCHAR;
BEGIN
    v_full_table_name := 'RAW_DEV.' || UPPER(p_source_system) || '.' || UPPER(p_table_name);
    
    -- Set defaults based on source system
    CASE UPPER(p_source_system)
        WHEN 'SAP' THEN 
            v_data_domain := 'ERP';
            v_classification := 'CONFIDENTIAL';
        WHEN 'SALESFORCE' THEN 
            v_data_domain := 'CRM';
            v_classification := 'CONFIDENTIAL';
        WHEN 'ORACLE' THEN 
            v_data_domain := 'ERP';
            v_classification := 'CONFIDENTIAL';
        WHEN 'FHIR' THEN 
            v_data_domain := 'HEALTHCARE';
            v_classification := 'RESTRICTED';
        WHEN 'WORKDAY' THEN 
            v_data_domain := 'HCM';
            v_classification := 'RESTRICTED';
        WHEN 'SERVICENOW' THEN 
            v_data_domain := 'ITSM';
            v_classification := 'INTERNAL';
        ELSE
            v_data_domain := 'OTHER';
            v_classification := 'INTERNAL';
    END CASE;
    
    -- Apply table-level tags
    EXECUTE IMMEDIATE 'ALTER TABLE ' || v_full_table_name || ' SET TAG ' ||
        'GOVERNANCE.TAGS.DATA_CLASSIFICATION = ''' || v_classification || ''', ' ||
        'GOVERNANCE.TAGS.DATA_DOMAIN = ''' || v_data_domain || ''', ' ||
        'GOVERNANCE.TAGS.DATA_QUALITY_TIER = ''BRONZE'', ' ||
        'GOVERNANCE.TAGS.SOURCE_SYSTEM = ''' || UPPER(p_source_system) || '''';
    
    RETURN 'SUCCESS: Applied tags to ' || v_full_table_name;
    
EXCEPTION
    WHEN OTHER THEN
        RETURN 'WARNING: Could not apply tags - ' || SQLERRM;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANT ACCESS
-- ═══════════════════════════════════════════════════════════════════════════

-- Staging access
GRANT USAGE ON SCHEMA RAW_DEV.STAGING TO ROLE DATA_ENGINEER;
GRANT READ, WRITE ON STAGE RAW_DEV.STAGING.DATA_STAGE TO ROLE DATA_ENGINEER;
GRANT USAGE ON PROCEDURE RAW_DEV.STAGING.INFER_AND_CREATE_TABLE(VARCHAR, VARCHAR, VARCHAR, VARCHAR) TO ROLE DATA_ENGINEER;
GRANT USAGE ON PROCEDURE RAW_DEV.STAGING.LOAD_SOURCE_SYSTEM(VARCHAR, VARCHAR) TO ROLE DATA_ENGINEER;
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
-- STEP 4: Create tables and load data (choose one method)
-- ───────────────────────────────────────────────────────────────────────────
-- Method A: Load single table
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SAP', 'KNA1', 'CSV', 'sap_s4hana/KNA1.csv');
--
-- Method B: Load all tables for a source system
-- CALL RAW_DEV.STAGING.LOAD_SOURCE_SYSTEM('SAP', 'CSV');
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

SELECT '✓ RAW Layer Dynamic Schema Infrastructure Created' AS STATUS;
SELECT '  Source System Schemas: SAP, SALESFORCE, ORACLE, FHIR, WORKDAY, SERVICENOW' AS INFO;
SELECT '  Use INFER_AND_CREATE_TABLE() or LOAD_SOURCE_SYSTEM() to create tables' AS INFO;
