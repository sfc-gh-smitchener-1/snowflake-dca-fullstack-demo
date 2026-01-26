-- ============================================================================
-- CURATED LAYER - Dynamic Tables for Business-Ready Data
-- ============================================================================
-- 
-- This script creates Dynamic Tables that:
--   1. Transform raw source system data into dimensional model
--   2. Automatically refresh based on upstream changes
--   3. Apply business rules and derived attributes
--   4. Create pseudonymized columns for AI-safe consumption
--   5. Support multiple source systems (SAP, Salesforce, Oracle, FHIR, etc.)
--
-- Dynamic Tables use TARGET_LAG to define freshness SLAs:
--   - Reference data: 24 hours
--   - Dimension tables: 1-4 hours
--   - Fact tables: 15-60 minutes
--   - Aggregates: 1-4 hours
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE CURATED_DEV;
USE WAREHOUSE TRANSFORM_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- DIMENSION: Date (Static Table)
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA CURATED_DEV.DIMENSIONS;

CREATE OR REPLACE TABLE DIM_DATE AS
WITH date_spine AS (
    SELECT DATEADD(DAY, SEQ4(), '2015-01-01')::DATE AS DATE_KEY
    FROM TABLE(GENERATOR(ROWCOUNT => 5844))  -- ~16 years
)
SELECT
    DATE_KEY,
    DATE_KEY AS FULL_DATE,
    YEAR(DATE_KEY) AS YEAR,
    QUARTER(DATE_KEY) AS QUARTER,
    MONTH(DATE_KEY) AS MONTH,
    MONTHNAME(DATE_KEY) AS MONTH_NAME,
    WEEK(DATE_KEY) AS WEEK_OF_YEAR,
    DAYOFWEEK(DATE_KEY) AS DAY_OF_WEEK,
    DAYNAME(DATE_KEY) AS DAY_NAME,
    DAYOFMONTH(DATE_KEY) AS DAY_OF_MONTH,
    DAYOFYEAR(DATE_KEY) AS DAY_OF_YEAR,
    CASE WHEN MONTH(DATE_KEY) >= 7 THEN YEAR(DATE_KEY) ELSE YEAR(DATE_KEY) - 1 END AS FISCAL_YEAR,
    CASE WHEN MONTH(DATE_KEY) >= 7 THEN MONTH(DATE_KEY) - 6 ELSE MONTH(DATE_KEY) + 6 END AS FISCAL_MONTH,
    CEIL(CASE WHEN MONTH(DATE_KEY) >= 7 THEN MONTH(DATE_KEY) - 6 ELSE MONTH(DATE_KEY) + 6 END / 3.0) AS FISCAL_QUARTER,
    CASE WHEN DAYOFWEEK(DATE_KEY) IN (0, 6) THEN TRUE ELSE FALSE END AS IS_WEEKEND,
    CASE WHEN DAYOFWEEK(DATE_KEY) IN (0, 6) THEN FALSE ELSE TRUE END AS IS_WEEKDAY,
    CASE 
        WHEN MONTH(DATE_KEY) = 1 AND DAYOFMONTH(DATE_KEY) = 1 THEN TRUE
        WHEN MONTH(DATE_KEY) = 7 AND DAYOFMONTH(DATE_KEY) = 4 THEN TRUE
        WHEN MONTH(DATE_KEY) = 12 AND DAYOFMONTH(DATE_KEY) = 25 THEN TRUE
        ELSE FALSE
    END AS IS_HOLIDAY,
    TO_CHAR(DATE_KEY, 'YYYYMM')::INT AS YEAR_MONTH_KEY,
    TO_CHAR(DATE_KEY, 'YYYYQ')::VARCHAR AS YEAR_QUARTER_KEY
FROM date_spine
WHERE DATE_KEY <= '2030-12-31';

-- ═══════════════════════════════════════════════════════════════════════════
-- DYNAMIC DIMENSION CREATION PROCEDURE
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Creates curated dimension tables from RAW source system data.
-- Maps source system fields to standardized dimension attributes.
--
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE CURATED_DEV.DIMENSIONS.CREATE_DIMENSION_FROM_SOURCE(
    p_source_system VARCHAR,      -- SAP, SALESFORCE, ORACLE, FHIR, WORKDAY, SERVICENOW
    p_source_table VARCHAR,       -- Source table name
    p_dimension_name VARCHAR,     -- Target dimension name (e.g., DIM_CUSTOMER)
    p_target_lag VARCHAR          -- TARGET_LAG for refresh (e.g., '1 hour')
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_source_path VARCHAR;
    v_create_sql VARCHAR;
    v_result VARCHAR;
BEGIN
    v_source_path := 'RAW_DEV.' || UPPER(p_source_system) || '.' || UPPER(p_source_table);
    
    -- Build dynamic table based on source system
    CASE UPPER(p_source_system)
        -- ═══════════════════════════════════════════════════════════════════════
        -- SAP S/4HANA Source Mappings
        -- ═══════════════════════════════════════════════════════════════════════
        WHEN 'SAP' THEN
            CASE UPPER(p_source_table)
                WHEN 'KNA1' THEN
                    v_create_sql := '
                    CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.DIMENSIONS.' || p_dimension_name || '
                        TARGET_LAG = ''' || p_target_lag || '''
                        WAREHOUSE = TRANSFORM_WH
                        COMMENT = ''Customer dimension from SAP KNA1''
                    AS
                    SELECT
                        KUNNR AS CUSTOMER_KEY,
                        KUNNR AS CUSTOMER_ID,
                        SHA2(KUNNR, 256) AS CUSTOMER_ID_HASH,
                        NAME1 AS CUSTOMER_NAME,
                        NAME2 AS CUSTOMER_NAME2,
                        STRAS AS ADDRESS,
                        ORT01 AS CITY,
                        PSTLZ AS POSTAL_CODE,
                        REGIO AS STATE_PROVINCE,
                        LAND1 AS COUNTRY,
                        TELF1 AS PHONE,
                        SMTP_ADDR AS EMAIL,
                        BRSCH AS INDUSTRY_CODE,
                        KUKLA AS CUSTOMER_CLASS,
                        KTOKD AS ACCOUNT_GROUP,
                        CASE WHEN LOEVM = ''X'' THEN FALSE ELSE TRUE END AS IS_ACTIVE,
                        TO_DATE(ERDAT, ''YYYYMMDD'') AS CREATED_DATE,
                        MANDT AS CLIENT,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_SOURCE_TABLE",
                        "_ROW_HASH" AS _SOURCE_HASH,
                        "_IS_CURRENT"
                    FROM ' || v_source_path || '
                    WHERE "_IS_CURRENT" = TRUE';
                    
                WHEN 'MARA' THEN
                    v_create_sql := '
                    CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.DIMENSIONS.' || p_dimension_name || '
                        TARGET_LAG = ''' || p_target_lag || '''
                        WAREHOUSE = TRANSFORM_WH
                        COMMENT = ''Product/Material dimension from SAP MARA''
                    AS
                    SELECT
                        MATNR AS PRODUCT_KEY,
                        MATNR AS MATERIAL_NUMBER,
                        SHA2(MATNR, 256) AS PRODUCT_ID_HASH,
                        MAKTX AS PRODUCT_NAME,
                        MTART AS MATERIAL_TYPE,
                        MATKL AS MATERIAL_GROUP,
                        MBRSH AS INDUSTRY_SECTOR,
                        MEINS AS BASE_UOM,
                        BRGEW AS GROSS_WEIGHT,
                        NTGEW AS NET_WEIGHT,
                        GEWEI AS WEIGHT_UNIT,
                        CASE WHEN LVORM = ''X'' THEN FALSE ELSE TRUE END AS IS_ACTIVE,
                        TO_DATE(ERSDA, ''YYYYMMDD'') AS CREATED_DATE,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ' || v_source_path || '
                    WHERE "_IS_CURRENT" = TRUE';
                    
                WHEN 'LFA1' THEN
                    v_create_sql := '
                    CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.DIMENSIONS.' || p_dimension_name || '
                        TARGET_LAG = ''' || p_target_lag || '''
                        WAREHOUSE = TRANSFORM_WH
                        COMMENT = ''Vendor dimension from SAP LFA1''
                    AS
                    SELECT
                        LIFNR AS VENDOR_KEY,
                        LIFNR AS VENDOR_ID,
                        SHA2(LIFNR, 256) AS VENDOR_ID_HASH,
                        NAME1 AS VENDOR_NAME,
                        NAME2 AS VENDOR_NAME2,
                        STRAS AS ADDRESS,
                        ORT01 AS CITY,
                        PSTLZ AS POSTAL_CODE,
                        LAND1 AS COUNTRY,
                        TELF1 AS PHONE,
                        SMTP_ADDR AS EMAIL,
                        CASE WHEN LOEVM = ''X'' THEN FALSE ELSE TRUE END AS IS_ACTIVE,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ' || v_source_path || '
                    WHERE "_IS_CURRENT" = TRUE';
                ELSE
                    RETURN 'ERROR: Unsupported SAP table: ' || p_source_table;
            END CASE;
            
        -- ═══════════════════════════════════════════════════════════════════════
        -- Salesforce Source Mappings
        -- ═══════════════════════════════════════════════════════════════════════
        WHEN 'SALESFORCE' THEN
            CASE UPPER(p_source_table)
                WHEN 'ACCOUNT' THEN
                    v_create_sql := '
                    CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.DIMENSIONS.' || p_dimension_name || '
                        TARGET_LAG = ''' || p_target_lag || '''
                        WAREHOUSE = TRANSFORM_WH
                        COMMENT = ''Customer/Account dimension from Salesforce''
                    AS
                    SELECT
                        "Id" AS CUSTOMER_KEY,
                        "Id" AS CUSTOMER_ID,
                        SHA2("Id", 256) AS CUSTOMER_ID_HASH,
                        "Name" AS CUSTOMER_NAME,
                        "Type" AS CUSTOMER_TYPE,
                        "Industry" AS INDUSTRY,
                        "AnnualRevenue" AS ANNUAL_REVENUE,
                        "NumberOfEmployees" AS EMPLOYEE_COUNT,
                        "Rating" AS RATING,
                        "BillingStreet" AS BILLING_ADDRESS,
                        "BillingCity" AS BILLING_CITY,
                        "BillingState" AS BILLING_STATE,
                        "BillingPostalCode" AS BILLING_POSTAL_CODE,
                        "BillingCountry" AS BILLING_COUNTRY,
                        "Phone" AS PHONE,
                        "Website" AS WEBSITE,
                        "OwnerId" AS ACCOUNT_OWNER_ID,
                        CASE 
                            WHEN "AnnualRevenue" >= 100000000 THEN ''ENTERPRISE''
                            WHEN "AnnualRevenue" >= 10000000 THEN ''MID-MARKET''
                            WHEN "AnnualRevenue" >= 1000000 THEN ''SMB''
                            ELSE ''STARTUP''
                        END AS CUSTOMER_TIER,
                        NOT COALESCE("IsDeleted", FALSE) AS IS_ACTIVE,
                        TO_TIMESTAMP("CreatedDate") AS CREATED_DATE,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ' || v_source_path || '
                    WHERE "_IS_CURRENT" = TRUE';
                    
                WHEN 'CONTACT' THEN
                    v_create_sql := '
                    CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.DIMENSIONS.' || p_dimension_name || '
                        TARGET_LAG = ''' || p_target_lag || '''
                        WAREHOUSE = TRANSFORM_WH
                        COMMENT = ''Contact dimension from Salesforce''
                    AS
                    SELECT
                        "Id" AS CONTACT_KEY,
                        "Id" AS CONTACT_ID,
                        SHA2("Id", 256) AS CONTACT_ID_HASH,
                        "FirstName" AS FIRST_NAME,
                        "LastName" AS LAST_NAME,
                        "Email" AS EMAIL,
                        SHA2(COALESCE("Email", "Id"), 256) AS EMAIL_HASH,
                        "Phone" AS PHONE,
                        "Title" AS JOB_TITLE,
                        "AccountId" AS ACCOUNT_ID,
                        "MailingCity" AS CITY,
                        "MailingState" AS STATE,
                        "MailingCountry" AS COUNTRY,
                        COALESCE("FirstName", '''') || '' '' || LEFT(COALESCE("LastName", ''X''), 1) || ''.'' AS DISPLAY_NAME,
                        NOT COALESCE("IsDeleted", FALSE) AS IS_ACTIVE,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ' || v_source_path || '
                    WHERE "_IS_CURRENT" = TRUE';
                    
                WHEN 'PRODUCT2' THEN
                    v_create_sql := '
                    CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.DIMENSIONS.' || p_dimension_name || '
                        TARGET_LAG = ''' || p_target_lag || '''
                        WAREHOUSE = TRANSFORM_WH
                        COMMENT = ''Product dimension from Salesforce''
                    AS
                    SELECT
                        "Id" AS PRODUCT_KEY,
                        "Id" AS PRODUCT_ID,
                        "ProductCode" AS PRODUCT_CODE,
                        SHA2("Id", 256) AS PRODUCT_ID_HASH,
                        "Name" AS PRODUCT_NAME,
                        "Description" AS PRODUCT_DESCRIPTION,
                        "Family" AS PRODUCT_FAMILY,
                        COALESCE("IsActive", TRUE) AS IS_ACTIVE,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ' || v_source_path || '
                    WHERE "_IS_CURRENT" = TRUE';
                ELSE
                    RETURN 'ERROR: Unsupported Salesforce object: ' || p_source_table;
            END CASE;
            
        -- ═══════════════════════════════════════════════════════════════════════
        -- FHIR R4 Source Mappings
        -- ═══════════════════════════════════════════════════════════════════════
        WHEN 'FHIR' THEN
            CASE UPPER(p_source_table)
                WHEN 'PATIENT' THEN
                    v_create_sql := '
                    CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.DIMENSIONS.' || p_dimension_name || '
                        TARGET_LAG = ''' || p_target_lag || '''
                        WAREHOUSE = TRANSFORM_WH
                        COMMENT = ''Patient dimension from FHIR R4''
                    AS
                    SELECT
                        "id" AS PATIENT_KEY,
                        "id" AS PATIENT_ID,
                        SHA2("id", 256) AS PATIENT_ID_HASH,
                        "name"[0]:given[0]::VARCHAR AS FIRST_NAME,
                        "name"[0]:family::VARCHAR AS LAST_NAME,
                        SHA2("name"[0]:given[0]::VARCHAR || '' '' || "name"[0]:family::VARCHAR, 256) AS NAME_HASH,
                        "gender" AS GENDER,
                        "birthDate"::DATE AS BIRTH_DATE,
                        "address"[0]:city::VARCHAR AS CITY,
                        "address"[0]:state::VARCHAR AS STATE,
                        "address"[0]:postalCode::VARCHAR AS POSTAL_CODE,
                        "address"[0]:country::VARCHAR AS COUNTRY,
                        "telecom" AS TELECOM,
                        "maritalStatus":coding[0]:code::VARCHAR AS MARITAL_STATUS,
                        COALESCE("active", TRUE) AS IS_ACTIVE,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ' || v_source_path || '
                    WHERE "_IS_CURRENT" = TRUE';
                    
                WHEN 'PRACTITIONER' THEN
                    v_create_sql := '
                    CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.DIMENSIONS.' || p_dimension_name || '
                        TARGET_LAG = ''' || p_target_lag || '''
                        WAREHOUSE = TRANSFORM_WH
                        COMMENT = ''Practitioner dimension from FHIR R4''
                    AS
                    SELECT
                        "id" AS PRACTITIONER_KEY,
                        "id" AS PRACTITIONER_ID,
                        SHA2("id", 256) AS PRACTITIONER_ID_HASH,
                        "name"[0]:given[0]::VARCHAR AS FIRST_NAME,
                        "name"[0]:family::VARCHAR AS LAST_NAME,
                        "gender" AS GENDER,
                        "qualification" AS QUALIFICATIONS,
                        COALESCE("active", TRUE) AS IS_ACTIVE,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ' || v_source_path || '
                    WHERE "_IS_CURRENT" = TRUE';
                ELSE
                    RETURN 'ERROR: Unsupported FHIR resource: ' || p_source_table;
            END CASE;
            
        -- ═══════════════════════════════════════════════════════════════════════
        -- Workday Source Mappings
        -- ═══════════════════════════════════════════════════════════════════════
        WHEN 'WORKDAY' THEN
            CASE UPPER(p_source_table)
                WHEN 'WORKERS' THEN
                    v_create_sql := '
                    CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.DIMENSIONS.' || p_dimension_name || '
                        TARGET_LAG = ''' || p_target_lag || '''
                        WAREHOUSE = TRANSFORM_WH
                        COMMENT = ''Employee dimension from Workday''
                    AS
                    SELECT
                        "Worker_ID" AS EMPLOYEE_KEY,
                        "Worker_ID" AS EMPLOYEE_ID,
                        SHA2("Worker_ID", 256) AS EMPLOYEE_ID_HASH,
                        "Legal_First_Name" AS FIRST_NAME,
                        "Legal_Last_Name" AS LAST_NAME,
                        SHA2("Legal_First_Name" || '' '' || "Legal_Last_Name", 256) AS NAME_HASH,
                        "Preferred_First_Name" AS PREFERRED_NAME,
                        "Primary_Work_Email" AS EMAIL,
                        "Employee_Type" AS EMPLOYMENT_TYPE,
                        "Business_Title" AS JOB_TITLE,
                        "Job_Level" AS JOB_LEVEL,
                        "Supervisory_Organization_Name" AS DEPARTMENT,
                        "Manager_Name" AS MANAGER_NAME,
                        "Location_Name" AS WORK_LOCATION,
                        "Hire_Date"::DATE AS HIRE_DATE,
                        "Termination_Date"::DATE AS TERMINATION_DATE,
                        "Worker_Status" = ''Active'' AS IS_ACTIVE,
                        ROUND(DATEDIFF(''day'', "Hire_Date"::DATE, COALESCE("Termination_Date"::DATE, CURRENT_DATE())) / 365.25, 1) AS TENURE_YEARS,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ' || v_source_path || '
                    WHERE "_IS_CURRENT" = TRUE';
                ELSE
                    RETURN 'ERROR: Unsupported Workday report: ' || p_source_table;
            END CASE;
            
        -- ═══════════════════════════════════════════════════════════════════════
        -- ServiceNow Source Mappings
        -- ═══════════════════════════════════════════════════════════════════════
        WHEN 'SERVICENOW' THEN
            CASE UPPER(p_source_table)
                WHEN 'SYS_USER' THEN
                    v_create_sql := '
                    CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.DIMENSIONS.' || p_dimension_name || '
                        TARGET_LAG = ''' || p_target_lag || '''
                        WAREHOUSE = TRANSFORM_WH
                        COMMENT = ''User dimension from ServiceNow''
                    AS
                    SELECT
                        "sys_id" AS USER_KEY,
                        "sys_id" AS USER_ID,
                        SHA2("sys_id", 256) AS USER_ID_HASH,
                        "user_name" AS USERNAME,
                        "first_name" AS FIRST_NAME,
                        "last_name" AS LAST_NAME,
                        "email" AS EMAIL,
                        "title" AS JOB_TITLE,
                        "department" AS DEPARTMENT,
                        "location" AS LOCATION,
                        "manager" AS MANAGER_ID,
                        "active" AS IS_ACTIVE,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ' || v_source_path || '
                    WHERE "_IS_CURRENT" = TRUE';
                ELSE
                    RETURN 'ERROR: Unsupported ServiceNow table: ' || p_source_table;
            END CASE;
        ELSE
            RETURN 'ERROR: Unsupported source system: ' || p_source_system;
    END CASE;
    
    -- Execute the create statement
    EXECUTE IMMEDIATE v_create_sql;
    
    RETURN 'SUCCESS: Created dimension ' || p_dimension_name || ' from ' || v_source_path;
    
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR: ' || SQLERRM;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- DYNAMIC FACT TABLE CREATION PROCEDURE
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE CURATED_DEV.FACTS.CREATE_FACT_FROM_SOURCE(
    p_source_system VARCHAR,
    p_source_table VARCHAR,
    p_fact_name VARCHAR,
    p_target_lag VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_source_path VARCHAR;
    v_create_sql VARCHAR;
BEGIN
    v_source_path := 'RAW_DEV.' || UPPER(p_source_system) || '.' || UPPER(p_source_table);
    
    CASE UPPER(p_source_system)
        WHEN 'SAP' THEN
            CASE UPPER(p_source_table)
                WHEN 'VBAK' THEN
                    v_create_sql := '
                    CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.FACTS.' || p_fact_name || '
                        TARGET_LAG = ''' || p_target_lag || '''
                        WAREHOUSE = TRANSFORM_WH
                        COMMENT = ''Sales Order fact from SAP VBAK''
                    AS
                    SELECT
                        VBELN AS ORDER_KEY,
                        VBELN AS ORDER_NUMBER,
                        KUNNR AS CUSTOMER_KEY,
                        TO_DATE(AUDAT, ''YYYYMMDD'') AS ORDER_DATE,
                        TO_DATE(ERDAT, ''YYYYMMDD'') AS CREATED_DATE,
                        VKORG AS SALES_ORG,
                        VTWEG AS DISTRIBUTION_CHANNEL,
                        SPART AS DIVISION,
                        AUART AS ORDER_TYPE,
                        NETWR AS NET_VALUE,
                        WAERK AS CURRENCY,
                        GBSTK AS ORDER_STATUS,
                        CASE 
                            WHEN GBSTK = ''C'' THEN TRUE 
                            ELSE FALSE 
                        END AS IS_COMPLETED,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ' || v_source_path || '
                    WHERE "_IS_CURRENT" = TRUE';
                    
                WHEN 'EKKO' THEN
                    v_create_sql := '
                    CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.FACTS.' || p_fact_name || '
                        TARGET_LAG = ''' || p_target_lag || '''
                        WAREHOUSE = TRANSFORM_WH
                        COMMENT = ''Purchase Order fact from SAP EKKO''
                    AS
                    SELECT
                        EBELN AS PO_KEY,
                        EBELN AS PO_NUMBER,
                        LIFNR AS VENDOR_KEY,
                        TO_DATE(BEDAT, ''YYYYMMDD'') AS PO_DATE,
                        EKORG AS PURCHASING_ORG,
                        EKGRP AS PURCHASING_GROUP,
                        BSART AS PO_TYPE,
                        WAERS AS CURRENCY,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ' || v_source_path || '
                    WHERE "_IS_CURRENT" = TRUE';
                ELSE
                    RETURN 'ERROR: Unsupported SAP fact table: ' || p_source_table;
            END CASE;
            
        WHEN 'SALESFORCE' THEN
            CASE UPPER(p_source_table)
                WHEN 'OPPORTUNITY' THEN
                    v_create_sql := '
                    CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.FACTS.' || p_fact_name || '
                        TARGET_LAG = ''' || p_target_lag || '''
                        WAREHOUSE = TRANSFORM_WH
                        COMMENT = ''Opportunity fact from Salesforce''
                    AS
                    SELECT
                        "Id" AS OPPORTUNITY_KEY,
                        "Id" AS OPPORTUNITY_ID,
                        "AccountId" AS CUSTOMER_KEY,
                        "OwnerId" AS SALES_REP_KEY,
                        "Name" AS OPPORTUNITY_NAME,
                        "Amount" AS AMOUNT,
                        "CloseDate"::DATE AS CLOSE_DATE,
                        "StageName" AS STAGE_NAME,
                        "Probability" AS PROBABILITY,
                        "Type" AS OPPORTUNITY_TYPE,
                        "LeadSource" AS LEAD_SOURCE,
                        "ForecastCategory" AS FORECAST_CATEGORY,
                        COALESCE("IsClosed", FALSE) AS IS_CLOSED,
                        COALESCE("IsWon", FALSE) AS IS_WON,
                        TO_TIMESTAMP("CreatedDate") AS CREATED_DATE,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ' || v_source_path || '
                    WHERE "_IS_CURRENT" = TRUE';
                    
                WHEN 'CASE' THEN
                    v_create_sql := '
                    CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.FACTS.' || p_fact_name || '
                        TARGET_LAG = ''' || p_target_lag || '''
                        WAREHOUSE = TRANSFORM_WH
                        COMMENT = ''Case fact from Salesforce''
                    AS
                    SELECT
                        "Id" AS CASE_KEY,
                        "CaseNumber" AS CASE_NUMBER,
                        "AccountId" AS CUSTOMER_KEY,
                        "ContactId" AS CONTACT_KEY,
                        "OwnerId" AS OWNER_KEY,
                        "Subject" AS SUBJECT,
                        "Status" AS STATUS,
                        "Priority" AS PRIORITY,
                        "Origin" AS ORIGIN,
                        "Type" AS CASE_TYPE,
                        COALESCE("IsClosed", FALSE) AS IS_CLOSED,
                        TO_TIMESTAMP("CreatedDate") AS CREATED_DATE,
                        TO_TIMESTAMP("ClosedDate") AS CLOSED_DATE,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ' || v_source_path || '
                    WHERE "_IS_CURRENT" = TRUE';
                ELSE
                    RETURN 'ERROR: Unsupported Salesforce fact object: ' || p_source_table;
            END CASE;
            
        WHEN 'FHIR' THEN
            CASE UPPER(p_source_table)
                WHEN 'ENCOUNTER' THEN
                    v_create_sql := '
                    CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.FACTS.' || p_fact_name || '
                        TARGET_LAG = ''' || p_target_lag || '''
                        WAREHOUSE = TRANSFORM_WH
                        COMMENT = ''Encounter fact from FHIR R4''
                    AS
                    SELECT
                        "id" AS ENCOUNTER_KEY,
                        "id" AS ENCOUNTER_ID,
                        REPLACE("subject":reference::VARCHAR, ''Patient/'', '''') AS PATIENT_KEY,
                        "class":code::VARCHAR AS ENCOUNTER_CLASS,
                        "type"[0]:coding[0]:code::VARCHAR AS ENCOUNTER_TYPE_CODE,
                        "type"[0]:coding[0]:display::VARCHAR AS ENCOUNTER_TYPE,
                        "status" AS STATUS,
                        "period":start::TIMESTAMP AS START_TIME,
                        "period":end::TIMESTAMP AS END_TIME,
                        DATEDIFF(''minute'', "period":start::TIMESTAMP, "period":end::TIMESTAMP) AS DURATION_MINUTES,
                        "serviceProvider":reference::VARCHAR AS SERVICE_PROVIDER,
                        "reasonCode"[0]:coding[0]:code::VARCHAR AS REASON_CODE,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ' || v_source_path || '
                    WHERE "_IS_CURRENT" = TRUE';
                    
                WHEN 'CONDITION' THEN
                    v_create_sql := '
                    CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.FACTS.' || p_fact_name || '
                        TARGET_LAG = ''' || p_target_lag || '''
                        WAREHOUSE = TRANSFORM_WH
                        COMMENT = ''Condition/Diagnosis fact from FHIR R4''
                    AS
                    SELECT
                        "id" AS CONDITION_KEY,
                        "id" AS CONDITION_ID,
                        REPLACE("subject":reference::VARCHAR, ''Patient/'', '''') AS PATIENT_KEY,
                        REPLACE("encounter":reference::VARCHAR, ''Encounter/'', '''') AS ENCOUNTER_KEY,
                        "code":coding[0]:code::VARCHAR AS DIAGNOSIS_CODE,
                        "code":coding[0]:display::VARCHAR AS DIAGNOSIS_DESCRIPTION,
                        "code":coding[0]:system::VARCHAR AS CODE_SYSTEM,
                        "clinicalStatus":coding[0]:code::VARCHAR AS CLINICAL_STATUS,
                        "verificationStatus":coding[0]:code::VARCHAR AS VERIFICATION_STATUS,
                        "onsetDateTime"::DATE AS ONSET_DATE,
                        "abatementDateTime"::DATE AS ABATEMENT_DATE,
                        "recordedDate"::DATE AS RECORDED_DATE,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ' || v_source_path || '
                    WHERE "_IS_CURRENT" = TRUE';
                ELSE
                    RETURN 'ERROR: Unsupported FHIR fact resource: ' || p_source_table;
            END CASE;
            
        WHEN 'SERVICENOW' THEN
            CASE UPPER(p_source_table)
                WHEN 'INCIDENT' THEN
                    v_create_sql := '
                    CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.FACTS.' || p_fact_name || '
                        TARGET_LAG = ''' || p_target_lag || '''
                        WAREHOUSE = TRANSFORM_WH
                        COMMENT = ''Incident fact from ServiceNow''
                    AS
                    SELECT
                        "sys_id" AS INCIDENT_KEY,
                        "number" AS INCIDENT_NUMBER,
                        "caller_id" AS CALLER_KEY,
                        "assigned_to" AS ASSIGNED_TO_KEY,
                        "assignment_group" AS ASSIGNMENT_GROUP,
                        "short_description" AS SHORT_DESCRIPTION,
                        "priority" AS PRIORITY,
                        "urgency" AS URGENCY,
                        "impact" AS IMPACT,
                        "state" AS STATE,
                        "category" AS CATEGORY,
                        "subcategory" AS SUBCATEGORY,
                        "cmdb_ci" AS CI_KEY,
                        "opened_at"::TIMESTAMP AS OPENED_AT,
                        "resolved_at"::TIMESTAMP AS RESOLVED_AT,
                        "closed_at"::TIMESTAMP AS CLOSED_AT,
                        DATEDIFF(''minute'', "opened_at"::TIMESTAMP, COALESCE("resolved_at"::TIMESTAMP, CURRENT_TIMESTAMP())) AS TIME_TO_RESOLVE_MINUTES,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ' || v_source_path || '
                    WHERE "_IS_CURRENT" = TRUE';
                ELSE
                    RETURN 'ERROR: Unsupported ServiceNow fact table: ' || p_source_table;
            END CASE;
        ELSE
            RETURN 'ERROR: Unsupported source system: ' || p_source_system;
    END CASE;
    
    EXECUTE IMMEDIATE v_create_sql;
    RETURN 'SUCCESS: Created fact ' || p_fact_name || ' from ' || v_source_path;
    
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR: ' || SQLERRM;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- QUICK CREATE: Build Curated Layer for a Source System
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE CURATED_DEV.DIMENSIONS.BUILD_CURATED_LAYER(
    p_source_system VARCHAR
)
RETURNS TABLE (object_type VARCHAR, object_name VARCHAR, status VARCHAR)
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    result RESULTSET;
BEGIN
    CREATE OR REPLACE TEMPORARY TABLE _build_results (
        object_type VARCHAR,
        object_name VARCHAR,
        status VARCHAR
    );
    
    CASE UPPER(p_source_system)
        WHEN 'SAP' THEN
            -- SAP Dimensions
            CALL CURATED_DEV.DIMENSIONS.CREATE_DIMENSION_FROM_SOURCE('SAP', 'KNA1', 'DIM_CUSTOMER_SAP', '1 hour');
            INSERT INTO _build_results VALUES ('DIMENSION', 'DIM_CUSTOMER_SAP', 'Created');
            
            CALL CURATED_DEV.DIMENSIONS.CREATE_DIMENSION_FROM_SOURCE('SAP', 'MARA', 'DIM_PRODUCT_SAP', '24 hours');
            INSERT INTO _build_results VALUES ('DIMENSION', 'DIM_PRODUCT_SAP', 'Created');
            
            CALL CURATED_DEV.DIMENSIONS.CREATE_DIMENSION_FROM_SOURCE('SAP', 'LFA1', 'DIM_VENDOR_SAP', '24 hours');
            INSERT INTO _build_results VALUES ('DIMENSION', 'DIM_VENDOR_SAP', 'Created');
            
            -- SAP Facts
            CALL CURATED_DEV.FACTS.CREATE_FACT_FROM_SOURCE('SAP', 'VBAK', 'FACT_SALES_ORDERS_SAP', '1 hour');
            INSERT INTO _build_results VALUES ('FACT', 'FACT_SALES_ORDERS_SAP', 'Created');
            
            CALL CURATED_DEV.FACTS.CREATE_FACT_FROM_SOURCE('SAP', 'EKKO', 'FACT_PURCHASE_ORDERS_SAP', '1 hour');
            INSERT INTO _build_results VALUES ('FACT', 'FACT_PURCHASE_ORDERS_SAP', 'Created');
            
        WHEN 'SALESFORCE' THEN
            -- Salesforce Dimensions
            CALL CURATED_DEV.DIMENSIONS.CREATE_DIMENSION_FROM_SOURCE('SALESFORCE', 'ACCOUNT', 'DIM_CUSTOMER_SF', '1 hour');
            INSERT INTO _build_results VALUES ('DIMENSION', 'DIM_CUSTOMER_SF', 'Created');
            
            CALL CURATED_DEV.DIMENSIONS.CREATE_DIMENSION_FROM_SOURCE('SALESFORCE', 'CONTACT', 'DIM_CONTACT_SF', '1 hour');
            INSERT INTO _build_results VALUES ('DIMENSION', 'DIM_CONTACT_SF', 'Created');
            
            CALL CURATED_DEV.DIMENSIONS.CREATE_DIMENSION_FROM_SOURCE('SALESFORCE', 'PRODUCT2', 'DIM_PRODUCT_SF', '24 hours');
            INSERT INTO _build_results VALUES ('DIMENSION', 'DIM_PRODUCT_SF', 'Created');
            
            -- Salesforce Facts
            CALL CURATED_DEV.FACTS.CREATE_FACT_FROM_SOURCE('SALESFORCE', 'OPPORTUNITY', 'FACT_OPPORTUNITIES_SF', '1 hour');
            INSERT INTO _build_results VALUES ('FACT', 'FACT_OPPORTUNITIES_SF', 'Created');
            
            CALL CURATED_DEV.FACTS.CREATE_FACT_FROM_SOURCE('SALESFORCE', 'CASE', 'FACT_CASES_SF', '1 hour');
            INSERT INTO _build_results VALUES ('FACT', 'FACT_CASES_SF', 'Created');
            
        WHEN 'FHIR' THEN
            -- FHIR Dimensions
            CALL CURATED_DEV.DIMENSIONS.CREATE_DIMENSION_FROM_SOURCE('FHIR', 'PATIENT', 'DIM_PATIENT_FHIR', '1 hour');
            INSERT INTO _build_results VALUES ('DIMENSION', 'DIM_PATIENT_FHIR', 'Created');
            
            CALL CURATED_DEV.DIMENSIONS.CREATE_DIMENSION_FROM_SOURCE('FHIR', 'PRACTITIONER', 'DIM_PRACTITIONER_FHIR', '24 hours');
            INSERT INTO _build_results VALUES ('DIMENSION', 'DIM_PRACTITIONER_FHIR', 'Created');
            
            -- FHIR Facts
            CALL CURATED_DEV.FACTS.CREATE_FACT_FROM_SOURCE('FHIR', 'ENCOUNTER', 'FACT_ENCOUNTERS_FHIR', '1 hour');
            INSERT INTO _build_results VALUES ('FACT', 'FACT_ENCOUNTERS_FHIR', 'Created');
            
            CALL CURATED_DEV.FACTS.CREATE_FACT_FROM_SOURCE('FHIR', 'CONDITION', 'FACT_CONDITIONS_FHIR', '1 hour');
            INSERT INTO _build_results VALUES ('FACT', 'FACT_CONDITIONS_FHIR', 'Created');
            
        WHEN 'WORKDAY' THEN
            CALL CURATED_DEV.DIMENSIONS.CREATE_DIMENSION_FROM_SOURCE('WORKDAY', 'WORKERS', 'DIM_EMPLOYEE_WD', '1 hour');
            INSERT INTO _build_results VALUES ('DIMENSION', 'DIM_EMPLOYEE_WD', 'Created');
            
        WHEN 'SERVICENOW' THEN
            CALL CURATED_DEV.DIMENSIONS.CREATE_DIMENSION_FROM_SOURCE('SERVICENOW', 'SYS_USER', 'DIM_USER_SN', '24 hours');
            INSERT INTO _build_results VALUES ('DIMENSION', 'DIM_USER_SN', 'Created');
            
            CALL CURATED_DEV.FACTS.CREATE_FACT_FROM_SOURCE('SERVICENOW', 'INCIDENT', 'FACT_INCIDENTS_SN', '15 minutes');
            INSERT INTO _build_results VALUES ('FACT', 'FACT_INCIDENTS_SN', 'Created');
    END CASE;
    
    result := (SELECT * FROM _build_results);
    RETURN TABLE(result);
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

GRANT USAGE ON SCHEMA CURATED_DEV.DIMENSIONS TO ROLE DATA_ENGINEER;
GRANT USAGE ON SCHEMA CURATED_DEV.FACTS TO ROLE DATA_ENGINEER;
GRANT USAGE ON SCHEMA CURATED_DEV.AGGREGATES TO ROLE DATA_ENGINEER;

GRANT SELECT ON ALL TABLES IN SCHEMA CURATED_DEV.DIMENSIONS TO ROLE DATA_ENGINEER;
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA CURATED_DEV.DIMENSIONS TO ROLE DATA_ENGINEER;
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA CURATED_DEV.FACTS TO ROLE DATA_ENGINEER;

GRANT USAGE ON PROCEDURE CURATED_DEV.DIMENSIONS.CREATE_DIMENSION_FROM_SOURCE(VARCHAR, VARCHAR, VARCHAR, VARCHAR) TO ROLE DATA_ENGINEER;
GRANT USAGE ON PROCEDURE CURATED_DEV.FACTS.CREATE_FACT_FROM_SOURCE(VARCHAR, VARCHAR, VARCHAR, VARCHAR) TO ROLE DATA_ENGINEER;
GRANT USAGE ON PROCEDURE CURATED_DEV.DIMENSIONS.BUILD_CURATED_LAYER(VARCHAR) TO ROLE DATA_ENGINEER;

-- ═══════════════════════════════════════════════════════════════════════════
-- USAGE INSTRUCTIONS
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- OPTION 1: Build entire curated layer for a source system
--   CALL CURATED_DEV.DIMENSIONS.BUILD_CURATED_LAYER('SAP');
--   CALL CURATED_DEV.DIMENSIONS.BUILD_CURATED_LAYER('SALESFORCE');
--   CALL CURATED_DEV.DIMENSIONS.BUILD_CURATED_LAYER('FHIR');
--
-- OPTION 2: Create individual dimensions/facts
--   CALL CURATED_DEV.DIMENSIONS.CREATE_DIMENSION_FROM_SOURCE('SAP', 'KNA1', 'DIM_CUSTOMER', '1 hour');
--   CALL CURATED_DEV.FACTS.CREATE_FACT_FROM_SOURCE('SALESFORCE', 'OPPORTUNITY', 'FACT_PIPELINE', '1 hour');
--
-- VERIFY:
--   SHOW DYNAMIC TABLES IN DATABASE CURATED_DEV;
--
-- ═══════════════════════════════════════════════════════════════════════════

SELECT '✓ Curated Layer Dynamic Infrastructure Created' AS STATUS;
SELECT '  Use BUILD_CURATED_LAYER(''SAP'') to create dimensions/facts for a source system' AS INFO;
