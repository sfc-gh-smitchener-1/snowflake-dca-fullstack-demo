-- ============================================================================
-- CURATED LAYER - Dynamic Tables by Source System
-- ============================================================================
-- 
-- Schema Structure (one schema per source system):
--   CURATED_DEV.SHARED      - Shared dimensions (DIM_DATE)
--   CURATED_DEV.SAP         - SAP dimensions and facts
--   CURATED_DEV.SALESFORCE  - Salesforce dimensions and facts
--   CURATED_DEV.FHIR        - FHIR dimensions and facts
--   CURATED_DEV.WORKDAY     - Workday dimensions and facts
--   CURATED_DEV.SERVICENOW  - ServiceNow dimensions and facts
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE CURATED_DEV;
USE WAREHOUSE TRANSFORM_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- CREATE SOURCE SYSTEM SCHEMAS
-- ═══════════════════════════════════════════════════════════════════════════

CREATE SCHEMA IF NOT EXISTS CURATED_DEV.SHARED
    COMMENT = 'Shared reference dimensions (Date, Geography, etc.)';

CREATE SCHEMA IF NOT EXISTS CURATED_DEV.SAP
    COMMENT = 'SAP S/4HANA curated dimensions and facts';

CREATE SCHEMA IF NOT EXISTS CURATED_DEV.SALESFORCE
    COMMENT = 'Salesforce CRM curated dimensions and facts';

CREATE SCHEMA IF NOT EXISTS CURATED_DEV.FHIR
    COMMENT = 'FHIR R4 healthcare curated dimensions and facts';

CREATE SCHEMA IF NOT EXISTS CURATED_DEV.WORKDAY
    COMMENT = 'Workday HCM curated dimensions and facts';

CREATE SCHEMA IF NOT EXISTS CURATED_DEV.SERVICENOW
    COMMENT = 'ServiceNow ITSM curated dimensions and facts';

-- ═══════════════════════════════════════════════════════════════════════════
-- SHARED: DIM_DATE (Static Reference Table)
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA CURATED_DEV.SHARED;

CREATE OR REPLACE TABLE DIM_DATE AS
WITH date_spine AS (
    SELECT DATEADD(DAY, SEQ4(), '2015-01-01')::DATE AS DATE_KEY
    FROM TABLE(GENERATOR(ROWCOUNT => 5844))
)
SELECT
    DATE_KEY,
    YEAR(DATE_KEY) AS YEAR,
    QUARTER(DATE_KEY) AS QUARTER,
    MONTH(DATE_KEY) AS MONTH,
    MONTHNAME(DATE_KEY) AS MONTH_NAME,
    WEEK(DATE_KEY) AS WEEK_OF_YEAR,
    DAYOFWEEK(DATE_KEY) AS DAY_OF_WEEK,
    DAYNAME(DATE_KEY) AS DAY_NAME,
    DAYOFMONTH(DATE_KEY) AS DAY_OF_MONTH,
    CASE WHEN MONTH(DATE_KEY) >= 7 THEN YEAR(DATE_KEY) ELSE YEAR(DATE_KEY) - 1 END AS FISCAL_YEAR,
    CEIL(CASE WHEN MONTH(DATE_KEY) >= 7 THEN MONTH(DATE_KEY) - 6 ELSE MONTH(DATE_KEY) + 6 END / 3.0) AS FISCAL_QUARTER,
    CASE WHEN DAYOFWEEK(DATE_KEY) IN (0, 6) THEN TRUE ELSE FALSE END AS IS_WEEKEND
FROM date_spine
WHERE DATE_KEY <= '2030-12-31';

-- ═══════════════════════════════════════════════════════════════════════════
-- BUILD PROCEDURE: Creates all curated objects for a source system
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE CURATED_DEV.SHARED.BUILD_CURATED_LAYER(
    P_SOURCE_SYSTEM VARCHAR
)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var results = [];
    var sourceSystem = P_SOURCE_SYSTEM.toUpperCase();
    var targetSchema = 'CURATED_DEV.' + sourceSystem;
    var rawSchema = 'RAW_DEV.' + sourceSystem;
    
    function createDynamicTable(tableName, selectSql, targetLag, comment) {
        var createSql = `
            CREATE OR REPLACE DYNAMIC TABLE ${targetSchema}.${tableName}
                TARGET_LAG = '${targetLag}'
                WAREHOUSE = TRANSFORM_WH
                COMMENT = '${comment}'
            AS ${selectSql}
        `;
        try {
            snowflake.createStatement({sqlText: createSql}).execute();
            results.push({object: tableName, status: 'SUCCESS', type: 'DYNAMIC TABLE'});
        } catch (err) {
            results.push({object: tableName, status: 'ERROR', message: err.message});
        }
    }
    
    try {
        switch (sourceSystem) {
            // ═══════════════════════════════════════════════════════════════
            // SAP S/4HANA
            // ═══════════════════════════════════════════════════════════════
            case 'SAP':
                // DIM_CUSTOMER from KNA1
                createDynamicTable('DIM_CUSTOMER', `
                    SELECT
                        KUNNR AS CUSTOMER_KEY,
                        KUNNR AS CUSTOMER_ID,
                        SHA2(KUNNR, 256) AS CUSTOMER_ID_HASH,
                        NAME1 AS CUSTOMER_NAME,
                        NAME2 AS CUSTOMER_NAME2,
                        STRAS AS ADDRESS,
                        ORT01 AS CITY,
                        PSTLZ AS POSTAL_CODE,
                        REGIO AS STATE,
                        LAND1 AS COUNTRY,
                        TELF1 AS PHONE,
                        SMTP_ADDR AS EMAIL,
                        BRSCH AS INDUSTRY_CODE,
                        KUKLA AS CUSTOMER_CLASS,
                        KTOKD AS ACCOUNT_GROUP,
                        CASE WHEN LOEVM = 'X' THEN FALSE ELSE TRUE END AS IS_ACTIVE,
                        TRY_TO_DATE(ERDAT::VARCHAR, 'YYYYMMDD') AS CREATED_DATE,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ${rawSchema}.KNA1
                    WHERE "_IS_CURRENT" = TRUE
                `, '1 hour', 'SAP Customer Master from KNA1');
                
                // DIM_PRODUCT from MARA
                createDynamicTable('DIM_PRODUCT', `
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
                        CASE WHEN LVORM = 'X' THEN FALSE ELSE TRUE END AS IS_ACTIVE,
                        TRY_TO_DATE(ERSDA::VARCHAR, 'YYYYMMDD') AS CREATED_DATE,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ${rawSchema}.MARA
                    WHERE "_IS_CURRENT" = TRUE
                `, '24 hours', 'SAP Material Master from MARA');
                
                // DIM_VENDOR from LFA1
                createDynamicTable('DIM_VENDOR', `
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
                        CASE WHEN LOEVM = 'X' THEN FALSE ELSE TRUE END AS IS_ACTIVE,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ${rawSchema}.LFA1
                    WHERE "_IS_CURRENT" = TRUE
                `, '24 hours', 'SAP Vendor Master from LFA1');
                
                // FACT_SALES_ORDERS from VBAK
                createDynamicTable('FACT_SALES_ORDERS', `
                    SELECT
                        VBELN AS ORDER_KEY,
                        VBELN AS ORDER_NUMBER,
                        KUNNR AS CUSTOMER_KEY,
                        TRY_TO_DATE(AUDAT::VARCHAR, 'YYYYMMDD') AS ORDER_DATE,
                        TRY_TO_DATE(ERDAT::VARCHAR, 'YYYYMMDD') AS CREATED_DATE,
                        VKORG AS SALES_ORG,
                        VTWEG AS DISTRIBUTION_CHANNEL,
                        SPART AS DIVISION,
                        AUART AS ORDER_TYPE,
                        NETWR AS NET_VALUE,
                        WAERK AS CURRENCY,
                        GBSTK AS ORDER_STATUS,
                        CASE WHEN GBSTK = 'C' THEN TRUE ELSE FALSE END AS IS_COMPLETED,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ${rawSchema}.VBAK
                    WHERE "_IS_CURRENT" = TRUE
                `, '1 hour', 'SAP Sales Orders from VBAK');
                
                // FACT_PURCHASE_ORDERS from EKKO
                createDynamicTable('FACT_PURCHASE_ORDERS', `
                    SELECT
                        EBELN AS PO_KEY,
                        EBELN AS PO_NUMBER,
                        LIFNR AS VENDOR_KEY,
                        TRY_TO_DATE(BEDAT::VARCHAR, 'YYYYMMDD') AS PO_DATE,
                        TRY_TO_DATE(ERDAT::VARCHAR, 'YYYYMMDD') AS CREATED_DATE,
                        EKORG AS PURCHASING_ORG,
                        EKGRP AS PURCHASING_GROUP,
                        BSART AS PO_TYPE,
                        WAERS AS CURRENCY,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ${rawSchema}.EKKO
                    WHERE "_IS_CURRENT" = TRUE
                `, '1 hour', 'SAP Purchase Orders from EKKO');
                break;
                
            // ═══════════════════════════════════════════════════════════════
            // SALESFORCE
            // ═══════════════════════════════════════════════════════════════
            case 'SALESFORCE':
                // DIM_ACCOUNT from Account
                createDynamicTable('DIM_ACCOUNT', `
                    SELECT
                        "Id" AS ACCOUNT_KEY,
                        "Id" AS ACCOUNT_ID,
                        SHA2("Id", 256) AS ACCOUNT_ID_HASH,
                        "Name" AS ACCOUNT_NAME,
                        "Type" AS ACCOUNT_TYPE,
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
                        "OwnerId" AS OWNER_ID,
                        CASE 
                            WHEN "AnnualRevenue" >= 100000000 THEN 'ENTERPRISE'
                            WHEN "AnnualRevenue" >= 10000000 THEN 'MID-MARKET'
                            WHEN "AnnualRevenue" >= 1000000 THEN 'SMB'
                            ELSE 'STARTUP'
                        END AS ACCOUNT_TIER,
                        NOT COALESCE("IsDeleted", FALSE) AS IS_ACTIVE,
                        TRY_TO_TIMESTAMP("CreatedDate") AS CREATED_DATE,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ${rawSchema}.ACCOUNT
                    WHERE "_IS_CURRENT" = TRUE
                `, '1 hour', 'Salesforce Account dimension');
                
                // FACT_OPPORTUNITIES from Opportunity
                createDynamicTable('FACT_OPPORTUNITIES', `
                    SELECT
                        "Id" AS OPPORTUNITY_KEY,
                        "Id" AS OPPORTUNITY_ID,
                        "AccountId" AS ACCOUNT_KEY,
                        "OwnerId" AS OWNER_KEY,
                        "Name" AS OPPORTUNITY_NAME,
                        "Amount" AS AMOUNT,
                        TRY_TO_DATE("CloseDate") AS CLOSE_DATE,
                        "StageName" AS STAGE_NAME,
                        "Probability" AS PROBABILITY,
                        "Type" AS OPPORTUNITY_TYPE,
                        "LeadSource" AS LEAD_SOURCE,
                        "ForecastCategory" AS FORECAST_CATEGORY,
                        COALESCE("IsClosed", FALSE) AS IS_CLOSED,
                        COALESCE("IsWon", FALSE) AS IS_WON,
                        TRY_TO_TIMESTAMP("CreatedDate") AS CREATED_DATE,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ${rawSchema}.OPPORTUNITY
                    WHERE "_IS_CURRENT" = TRUE
                `, '1 hour', 'Salesforce Opportunity fact');
                break;
                
            // ═══════════════════════════════════════════════════════════════
            // FHIR R4
            // ═══════════════════════════════════════════════════════════════
            case 'FHIR':
                // DIM_PATIENT from Patient
                createDynamicTable('DIM_PATIENT', `
                    SELECT
                        "id" AS PATIENT_KEY,
                        "id" AS PATIENT_ID,
                        SHA2("id", 256) AS PATIENT_ID_HASH,
                        "name"[0]:given[0]::VARCHAR AS FIRST_NAME,
                        "name"[0]:family::VARCHAR AS LAST_NAME,
                        "gender" AS GENDER,
                        TRY_TO_DATE("birthDate") AS BIRTH_DATE,
                        "address"[0]:city::VARCHAR AS CITY,
                        "address"[0]:state::VARCHAR AS STATE,
                        "address"[0]:postalCode::VARCHAR AS POSTAL_CODE,
                        "address"[0]:country::VARCHAR AS COUNTRY,
                        COALESCE("active", TRUE) AS IS_ACTIVE,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ${rawSchema}.PATIENT
                    WHERE "_IS_CURRENT" = TRUE
                `, '1 hour', 'FHIR Patient dimension');
                
                // FACT_ENCOUNTERS from Encounter
                createDynamicTable('FACT_ENCOUNTERS', `
                    SELECT
                        "id" AS ENCOUNTER_KEY,
                        "id" AS ENCOUNTER_ID,
                        REPLACE("subject":reference::VARCHAR, 'Patient/', '') AS PATIENT_KEY,
                        "class":code::VARCHAR AS ENCOUNTER_CLASS,
                        "type"[0]:coding[0]:code::VARCHAR AS ENCOUNTER_TYPE_CODE,
                        "type"[0]:coding[0]:display::VARCHAR AS ENCOUNTER_TYPE,
                        "status" AS STATUS,
                        TRY_TO_TIMESTAMP("period":start::VARCHAR) AS START_TIME,
                        TRY_TO_TIMESTAMP("period":end::VARCHAR) AS END_TIME,
                        DATEDIFF('minute', TRY_TO_TIMESTAMP("period":start::VARCHAR), TRY_TO_TIMESTAMP("period":end::VARCHAR)) AS DURATION_MINUTES,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ${rawSchema}.ENCOUNTER
                    WHERE "_IS_CURRENT" = TRUE
                `, '1 hour', 'FHIR Encounter fact');
                break;
                
            // ═══════════════════════════════════════════════════════════════
            // WORKDAY
            // ═══════════════════════════════════════════════════════════════
            case 'WORKDAY':
                // DIM_EMPLOYEE from Workers
                createDynamicTable('DIM_EMPLOYEE', `
                    SELECT
                        "Worker_ID" AS EMPLOYEE_KEY,
                        "Worker_ID" AS EMPLOYEE_ID,
                        SHA2("Worker_ID", 256) AS EMPLOYEE_ID_HASH,
                        "Legal_First_Name" AS FIRST_NAME,
                        "Legal_Last_Name" AS LAST_NAME,
                        "Preferred_First_Name" AS PREFERRED_NAME,
                        "Primary_Work_Email" AS EMAIL,
                        "Employee_Type" AS EMPLOYMENT_TYPE,
                        "Business_Title" AS JOB_TITLE,
                        "Job_Level" AS JOB_LEVEL,
                        "Supervisory_Organization_Name" AS DEPARTMENT,
                        "Manager_Name" AS MANAGER_NAME,
                        "Location_Name" AS WORK_LOCATION,
                        TRY_TO_DATE("Hire_Date") AS HIRE_DATE,
                        TRY_TO_DATE("Termination_Date") AS TERMINATION_DATE,
                        "Worker_Status" = 'Active' AS IS_ACTIVE,
                        ROUND(DATEDIFF('day', TRY_TO_DATE("Hire_Date"), COALESCE(TRY_TO_DATE("Termination_Date"), CURRENT_DATE())) / 365.25, 1) AS TENURE_YEARS,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ${rawSchema}.WORKERS
                    WHERE "_IS_CURRENT" = TRUE
                `, '4 hours', 'Workday Employee dimension');
                break;
                
            // ═══════════════════════════════════════════════════════════════
            // SERVICENOW
            // ═══════════════════════════════════════════════════════════════
            case 'SERVICENOW':
                // DIM_USER from sys_user
                createDynamicTable('DIM_USER', `
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
                        "active" AS IS_ACTIVE,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ${rawSchema}.SYS_USER
                    WHERE "_IS_CURRENT" = TRUE
                `, '24 hours', 'ServiceNow User dimension');
                
                // FACT_INCIDENTS from incident
                createDynamicTable('FACT_INCIDENTS', `
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
                        TRY_TO_TIMESTAMP("opened_at") AS OPENED_AT,
                        TRY_TO_TIMESTAMP("resolved_at") AS RESOLVED_AT,
                        TRY_TO_TIMESTAMP("closed_at") AS CLOSED_AT,
                        DATEDIFF('minute', TRY_TO_TIMESTAMP("opened_at"), COALESCE(TRY_TO_TIMESTAMP("resolved_at"), CURRENT_TIMESTAMP())) AS TIME_TO_RESOLVE_MINUTES,
                        "_LOADED_AT" AS _SOURCE_LOADED_AT,
                        "_SOURCE_SYSTEM",
                        "_IS_CURRENT"
                    FROM ${rawSchema}.INCIDENT
                    WHERE "_IS_CURRENT" = TRUE
                `, '15 minutes', 'ServiceNow Incident fact');
                break;
                
            default:
                return {status: 'ERROR', message: 'Unsupported source system: ' + sourceSystem};
        }
        
        var successCount = results.filter(function(r) { return r.status === 'SUCCESS'; }).length;
        var errorCount = results.filter(function(r) { return r.status === 'ERROR'; }).length;
        
        return {
            status: errorCount === 0 ? 'SUCCESS' : 'PARTIAL',
            source_system: sourceSystem,
            target_schema: targetSchema,
            objects_created: successCount,
            objects_failed: errorCount,
            details: results
        };
        
    } catch (err) {
        return {status: 'ERROR', message: err.message};
    }
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

-- Grant schema usage
GRANT USAGE ON SCHEMA CURATED_DEV.SHARED TO ROLE DATA_ENGINEER;
GRANT USAGE ON SCHEMA CURATED_DEV.SAP TO ROLE DATA_ENGINEER;
GRANT USAGE ON SCHEMA CURATED_DEV.SALESFORCE TO ROLE DATA_ENGINEER;
GRANT USAGE ON SCHEMA CURATED_DEV.FHIR TO ROLE DATA_ENGINEER;
GRANT USAGE ON SCHEMA CURATED_DEV.WORKDAY TO ROLE DATA_ENGINEER;
GRANT USAGE ON SCHEMA CURATED_DEV.SERVICENOW TO ROLE DATA_ENGINEER;

-- Grant select on all objects
GRANT SELECT ON ALL TABLES IN SCHEMA CURATED_DEV.SHARED TO ROLE DATA_ENGINEER;
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA CURATED_DEV.SAP TO ROLE DATA_ENGINEER;
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA CURATED_DEV.SALESFORCE TO ROLE DATA_ENGINEER;
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA CURATED_DEV.FHIR TO ROLE DATA_ENGINEER;
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA CURATED_DEV.WORKDAY TO ROLE DATA_ENGINEER;
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA CURATED_DEV.SERVICENOW TO ROLE DATA_ENGINEER;

-- Future grants
GRANT SELECT ON FUTURE DYNAMIC TABLES IN SCHEMA CURATED_DEV.SAP TO ROLE DATA_ENGINEER;
GRANT SELECT ON FUTURE DYNAMIC TABLES IN SCHEMA CURATED_DEV.SALESFORCE TO ROLE DATA_ENGINEER;
GRANT SELECT ON FUTURE DYNAMIC TABLES IN SCHEMA CURATED_DEV.FHIR TO ROLE DATA_ENGINEER;
GRANT SELECT ON FUTURE DYNAMIC TABLES IN SCHEMA CURATED_DEV.WORKDAY TO ROLE DATA_ENGINEER;
GRANT SELECT ON FUTURE DYNAMIC TABLES IN SCHEMA CURATED_DEV.SERVICENOW TO ROLE DATA_ENGINEER;

GRANT USAGE ON PROCEDURE CURATED_DEV.SHARED.BUILD_CURATED_LAYER(VARCHAR) TO ROLE DATA_ENGINEER;

-- ═══════════════════════════════════════════════════════════════════════════
-- USAGE INSTRUCTIONS
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Build curated layer for a source system:
--   CALL CURATED_DEV.SHARED.BUILD_CURATED_LAYER('SAP');
--   CALL CURATED_DEV.SHARED.BUILD_CURATED_LAYER('SALESFORCE');
--   CALL CURATED_DEV.SHARED.BUILD_CURATED_LAYER('FHIR');
--   CALL CURATED_DEV.SHARED.BUILD_CURATED_LAYER('WORKDAY');
--   CALL CURATED_DEV.SHARED.BUILD_CURATED_LAYER('SERVICENOW');
--
-- Verify:
--   SHOW DYNAMIC TABLES IN SCHEMA CURATED_DEV.SAP;
--   SELECT * FROM CURATED_DEV.SAP.DIM_CUSTOMER LIMIT 10;
--   SELECT * FROM CURATED_DEV.SAP.FACT_SALES_ORDERS LIMIT 10;
--
-- ═══════════════════════════════════════════════════════════════════════════

SELECT '05_curated_layer.sql completed successfully' AS STATUS;
