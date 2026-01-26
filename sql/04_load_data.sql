-- ============================================================================
-- DATA LOADING - Load Source System Data into RAW Layer
-- ============================================================================
-- 
-- This script provides multiple methods to load data:
--
--   METHOD 1: Load from generated source system files (recommended)
--             Uses INFER_SCHEMA to dynamically create tables
--
--   METHOD 2: Generate simple demo data in-Snowflake
--             Quick setup for demonstrations
--
-- SUPPORTED SOURCE SYSTEMS:
--   - SAP S/4HANA:  KNA1, MARA, VBAK, VBAP, PA0001, PA0002, LFA1, EKKO, BKPF
--   - Salesforce:   Account, Contact, Opportunity, Case, Lead, Product2
--   - Oracle EBS:   HZ_PARTIES, OE_ORDER_*, AP_*, RA_*, GL_JE_LINES, HR_*
--   - FHIR R4:      Patient, Practitioner, Encounter, Condition, Observation
--   - Workday:      Workers, Organizations, Compensation, Time_Off
--   - ServiceNow:   incident, change_request, problem, cmdb_ci
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE WAREHOUSE INGEST_WH;
USE DATABASE RAW_DEV;

-- ═══════════════════════════════════════════════════════════════════════════
-- METHOD 1: LOAD FROM GENERATED SOURCE SYSTEM FILES
-- ═══════════════════════════════════════════════════════════════════════════
--
-- STEP 1: Generate data locally
-- ─────────────────────────────────────────────────────────────────────────────
--   cd tools
--   python data_generator.py --system sap --domain all --output ../data
--   python data_generator.py --system salesforce --domain all --output ../data
--   python data_generator.py --system fhir --domain all --format json --output ../data
--
-- STEP 2: Upload files to Snowflake stage
-- ─────────────────────────────────────────────────────────────────────────────
--   -- Using SnowSQL
--   PUT file:///path/to/data/sap_s4hana/*.csv @RAW_DEV.STAGING.DATA_STAGE/sap_s4hana/ AUTO_COMPRESS=TRUE;
--   PUT file:///path/to/data/salesforce/*.csv @RAW_DEV.STAGING.DATA_STAGE/salesforce/ AUTO_COMPRESS=TRUE;
--   PUT file:///path/to/data/fhir_r4/*.json @RAW_DEV.STAGING.DATA_STAGE/fhir_r4/ AUTO_COMPRESS=TRUE;
--
--   -- Or using Snowsight: Data > Databases > RAW_DEV > Stages > DATA_STAGE > Upload
--
-- STEP 3: List files to verify
-- ─────────────────────────────────────────────────────────────────────────────

LIST @RAW_DEV.STAGING.DATA_STAGE;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 4: Load individual tables (Method A)
-- ─────────────────────────────────────────────────────────────────────────────

-- SAP Tables
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SAP', 'KNA1', 'CSV', 'sap_s4hana/KNA1.csv');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SAP', 'MARA', 'CSV', 'sap_s4hana/MARA.csv');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SAP', 'VBAK', 'CSV', 'sap_s4hana/VBAK.csv');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SAP', 'VBAP', 'CSV', 'sap_s4hana/VBAP.csv');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SAP', 'PA0001', 'CSV', 'sap_s4hana/PA0001.csv');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SAP', 'PA0002', 'CSV', 'sap_s4hana/PA0002.csv');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SAP', 'LFA1', 'CSV', 'sap_s4hana/LFA1.csv');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SAP', 'EKKO', 'CSV', 'sap_s4hana/EKKO.csv');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SAP', 'BKPF', 'CSV', 'sap_s4hana/BKPF.csv');

-- Salesforce Objects
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SALESFORCE', 'ACCOUNT', 'CSV', 'salesforce/Account.csv');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SALESFORCE', 'CONTACT', 'CSV', 'salesforce/Contact.csv');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SALESFORCE', 'OPPORTUNITY', 'CSV', 'salesforce/Opportunity.csv');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SALESFORCE', 'CASE', 'CSV', 'salesforce/Case.csv');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SALESFORCE', 'LEAD', 'CSV', 'salesforce/Lead.csv');

-- FHIR Resources (JSON format)
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('FHIR', 'PATIENT', 'JSON', 'fhir_r4/Patient.json');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('FHIR', 'ENCOUNTER', 'JSON', 'fhir_r4/Encounter.json');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('FHIR', 'CONDITION', 'JSON', 'fhir_r4/Condition.json');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('FHIR', 'OBSERVATION', 'JSON', 'fhir_r4/Observation.json');

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 4 Alternative: Bulk load all tables for a source system (Method B)
-- ─────────────────────────────────────────────────────────────────────────────

-- Load all SAP tables at once
-- CALL RAW_DEV.STAGING.LOAD_SOURCE_SYSTEM('SAP', 'CSV');

-- Load all Salesforce objects
-- CALL RAW_DEV.STAGING.LOAD_SOURCE_SYSTEM('SALESFORCE', 'CSV');

-- Load all Oracle EBS tables
-- CALL RAW_DEV.STAGING.LOAD_SOURCE_SYSTEM('ORACLE', 'CSV');

-- Load all FHIR resources
-- CALL RAW_DEV.STAGING.LOAD_SOURCE_SYSTEM('FHIR', 'JSON');

-- Load all Workday reports
-- CALL RAW_DEV.STAGING.LOAD_SOURCE_SYSTEM('WORKDAY', 'CSV');

-- Load all ServiceNow tables
-- CALL RAW_DEV.STAGING.LOAD_SOURCE_SYSTEM('SERVICENOW', 'CSV');

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 5: Apply governance tags to loaded tables
-- ─────────────────────────────────────────────────────────────────────────────

-- CALL RAW_DEV.STAGING.APPLY_SOURCE_SYSTEM_TAGS('SAP', 'KNA1');
-- CALL RAW_DEV.STAGING.APPLY_SOURCE_SYSTEM_TAGS('SAP', 'MARA');
-- CALL RAW_DEV.STAGING.APPLY_SOURCE_SYSTEM_TAGS('SALESFORCE', 'ACCOUNT');
-- CALL RAW_DEV.STAGING.APPLY_SOURCE_SYSTEM_TAGS('FHIR', 'PATIENT');


-- ═══════════════════════════════════════════════════════════════════════════
-- METHOD 2: GENERATE DEMO DATA IN-SNOWFLAKE
-- ═══════════════════════════════════════════════════════════════════════════
--
-- For quick demos without file upload, generate simplified data directly.
-- This creates sample data matching common source system patterns.
--
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- SAP KNA1 (Customer Master) - Quick Demo Data
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS RAW_DEV.SAP.KNA1 AS
SELECT
    '100' AS MANDT,
    LPAD(SEQ4()::STRING, 10, '0') AS KUNNR,
    ARRAY_CONSTRUCT('ACME Corp', 'Global Industries', 'Tech Solutions', 'Prime Manufacturing', 'Metro Services')[UNIFORM(0, 4, RANDOM())] || ' ' || SEQ4() AS NAME1,
    ARRAY_CONSTRUCT('LLC', 'Inc', 'GmbH', 'Ltd', 'AG')[UNIFORM(0, 4, RANDOM())] AS NAME2,
    LEFT(NAME1, 10) AS SORTL,
    UNIFORM(100, 9999, RANDOM()) || ' ' || ARRAY_CONSTRUCT('Main', 'Oak', 'Industrial', 'Commerce', 'Business')[UNIFORM(0, 4, RANDOM())] || ' Street' AS STRAS,
    ARRAY_CONSTRUCT('New York', 'Los Angeles', 'Chicago', 'Houston', 'Munich', 'London')[UNIFORM(0, 5, RANDOM())] AS ORT01,
    LPAD(UNIFORM(10000, 99999, RANDOM())::STRING, 5, '0') AS PSTLZ,
    ARRAY_CONSTRUCT('US', 'US', 'US', 'DE', 'GB')[UNIFORM(0, 4, RANDOM())] AS LAND1,
    CASE WHEN LAND1 = 'US' THEN ARRAY_CONSTRUCT('NY', 'CA', 'IL', 'TX')[UNIFORM(0, 3, RANDOM())] ELSE '' END AS REGIO,
    CASE WHEN LAND1 = 'DE' THEN 'D' ELSE 'E' END AS SPRAS,
    '+1-' || UNIFORM(200, 999, RANDOM()) || '-' || UNIFORM(200, 999, RANDOM()) || '-' || UNIFORM(1000, 9999, RANDOM()) AS TELF1,
    '+1-' || UNIFORM(200, 999, RANDOM()) || '-' || UNIFORM(200, 999, RANDOM()) || '-' || UNIFORM(1000, 9999, RANDOM()) AS TELFX,
    LOWER(REPLACE(LEFT(NAME1, 20), ' ', '.')) || '@example.com' AS SMTP_ADDR,
    ARRAY_CONSTRUCT('0001', '0002', 'CPDA')[UNIFORM(0, 2, RANDOM())] AS KTOKD,
    TO_CHAR(DATEADD(DAY, -UNIFORM(1, 1825, RANDOM()), CURRENT_DATE()), 'YYYYMMDD') AS ERDAT,
    'USER' || LPAD(UNIFORM(1, 100, RANDOM())::STRING, 3, '0') AS ERNAM,
    '' AS LOEVM,
    '' AS SPERR,
    ARRAY_CONSTRUCT('0001', '0002', '0003', '0004', '0005')[UNIFORM(0, 4, RANDOM())] AS BRSCH,
    ARRAY_CONSTRUCT('01', '02', '03')[UNIFORM(0, 2, RANDOM())] AS KUKLA,
    CASE WHEN UNIFORM(0, 100, RANDOM()) > 30 THEN LAND1 || UNIFORM(100000000, 999999999, RANDOM())::STRING ELSE '' END AS STCEG,
    -- SCD Type 2 columns
    CURRENT_TIMESTAMP() AS "_LOADED_AT",
    'SAP_S4HANA' AS "_SOURCE_SYSTEM",
    'KNA1' AS "_SOURCE_TABLE",
    SHA2(SEQ4()::STRING, 256) AS "_ROW_HASH",
    TRUE AS "_IS_CURRENT",
    CURRENT_TIMESTAMP() AS "_VALID_FROM",
    '9999-12-31' AS "_VALID_TO"
FROM TABLE(GENERATOR(ROWCOUNT => 1000));

-- ─────────────────────────────────────────────────────────────────────────────
-- SAP MARA (Material Master) - Quick Demo Data
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS RAW_DEV.SAP.MARA AS
SELECT
    '100' AS MANDT,
    'MAT' || LPAD(SEQ4()::STRING, 15, '0') AS MATNR,
    ARRAY_CONSTRUCT('FERT', 'HALB', 'ROH', 'HAWA', 'DIEN')[UNIFORM(0, 4, RANDOM())] AS MTART,
    ARRAY_CONSTRUCT('001', '002', '003', '004', '005', '006')[UNIFORM(0, 5, RANDOM())] AS MATKL,
    ARRAY_CONSTRUCT('M', 'C', 'P')[UNIFORM(0, 2, RANDOM())] AS MBRSH,
    ARRAY_CONSTRUCT('EA', 'KG', 'L', 'M', 'PC', 'ST')[UNIFORM(0, 5, RANDOM())] AS MEINS,
    MEINS AS BSTME,
    ARRAY_CONSTRUCT('Premium', 'Standard', 'Basic', 'Elite', 'Pro')[UNIFORM(0, 4, RANDOM())] || ' ' || 
    ARRAY_CONSTRUCT('Widget', 'Component', 'Module', 'Unit', 'Part')[UNIFORM(0, 4, RANDOM())] AS MAKTX,
    ROUND(UNIFORM(0.1, 100, RANDOM())::FLOAT, 3) AS BRGEW,
    ROUND(BRGEW * 0.9, 3) AS NTGEW,
    'KG' AS GEWEI,
    ROUND(UNIFORM(0.001, 10, RANDOM())::FLOAT, 3) AS VOLUM,
    'M3' AS VOLEH,
    '' AS LVORM,
    TO_CHAR(DATEADD(DAY, -UNIFORM(1, 1095, RANDOM()), CURRENT_DATE()), 'YYYYMMDD') AS ERSDA,
    'USER' || LPAD(UNIFORM(1, 100, RANDOM())::STRING, 3, '0') AS ERNAM,
    UNIFORM(1, 9, RANDOM())::STRING || UNIFORM(0, 9, RANDOM())::STRING || UNIFORM(0, 9, RANDOM())::STRING || '00000' AS PRDHA,
    -- SCD Type 2 columns
    CURRENT_TIMESTAMP() AS "_LOADED_AT",
    'SAP_S4HANA' AS "_SOURCE_SYSTEM",
    'MARA' AS "_SOURCE_TABLE",
    SHA2(SEQ4()::STRING, 256) AS "_ROW_HASH",
    TRUE AS "_IS_CURRENT",
    CURRENT_TIMESTAMP() AS "_VALID_FROM",
    '9999-12-31' AS "_VALID_TO"
FROM TABLE(GENERATOR(ROWCOUNT => 500));

-- ─────────────────────────────────────────────────────────────────────────────
-- SAP VBAK (Sales Order Header) - Quick Demo Data
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS RAW_DEV.SAP.VBAK AS
SELECT
    '100' AS MANDT,
    LPAD(SEQ4()::STRING, 10, '0') AS VBELN,
    ARRAY_CONSTRUCT('1000', '1100', '2000', '3000')[UNIFORM(0, 3, RANDOM())] AS VKORG,
    ARRAY_CONSTRUCT('10', '20', '30')[UNIFORM(0, 2, RANDOM())] AS VTWEG,
    ARRAY_CONSTRUCT('00', '10', '20')[UNIFORM(0, 2, RANDOM())] AS SPART,
    LEFT(VKORG, 2) || '01' AS VKBUR,
    LPAD(UNIFORM(1, 20, RANDOM())::STRING, 3, '0') AS VKGRP,
    ARRAY_CONSTRUCT('TA', 'OR', 'SO', 'RE')[UNIFORM(0, 3, RANDOM())] AS AUART,
    TO_CHAR(DATEADD(DAY, -UNIFORM(1, 730, RANDOM()), CURRENT_DATE()), 'YYYYMMDD') AS AUDAT,
    AUDAT AS ERDAT,
    LPAD(UNIFORM(0, 23, RANDOM())::STRING, 2, '0') || LPAD(UNIFORM(0, 59, RANDOM())::STRING, 2, '0') || LPAD(UNIFORM(0, 59, RANDOM())::STRING, 2, '0') AS ERZET,
    'USER' || LPAD(UNIFORM(1, 100, RANDOM())::STRING, 3, '0') AS ERNAM,
    LPAD(UNIFORM(1, 1000, RANDOM())::STRING, 10, '0') AS KUNNR,
    ARRAY_CONSTRUCT('A', 'B', 'C')[UNIFORM(0, 2, RANDOM())] AS GBSTK,
    ROUND(UNIFORM(100, 50000, RANDOM())::FLOAT, 2) AS NETWR,
    ARRAY_CONSTRUCT('USD', 'EUR', 'GBP', 'JPY', 'CNY')[UNIFORM(0, 4, RANDOM())] AS WAERK,
    TO_CHAR(DATEADD(DAY, UNIFORM(1, 30, RANDOM()), TO_DATE(AUDAT, 'YYYYMMDD')), 'YYYYMMDD') AS VDATU,
    'PO-' || UNIFORM(100000, 999999, RANDOM())::STRING AS BSTNK,
    -- SCD Type 2 columns
    CURRENT_TIMESTAMP() AS "_LOADED_AT",
    'SAP_S4HANA' AS "_SOURCE_SYSTEM",
    'VBAK' AS "_SOURCE_TABLE",
    SHA2(SEQ4()::STRING, 256) AS "_ROW_HASH",
    TRUE AS "_IS_CURRENT",
    CURRENT_TIMESTAMP() AS "_VALID_FROM",
    '9999-12-31' AS "_VALID_TO"
FROM TABLE(GENERATOR(ROWCOUNT => 5000));

-- ─────────────────────────────────────────────────────────────────────────────
-- Salesforce Account - Quick Demo Data
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS RAW_DEV.SALESFORCE.ACCOUNT AS
SELECT
    '001' || SUBSTRING(UUID_STRING(), 1, 12) || 'AAA' AS "Id",
    FALSE AS "IsDeleted",
    TO_CHAR(DATEADD(DAY, -UNIFORM(1, 1825, RANDOM()), CURRENT_TIMESTAMP()), 'YYYY-MM-DD"T"HH24:MI:SS.000Z') AS "CreatedDate",
    '005' || SUBSTRING(UUID_STRING(), 1, 12) || 'BBB' AS "CreatedById",
    TO_CHAR(DATEADD(DAY, -UNIFORM(1, 365, RANDOM()), CURRENT_TIMESTAMP()), 'YYYY-MM-DD"T"HH24:MI:SS.000Z') AS "LastModifiedDate",
    '005' || SUBSTRING(UUID_STRING(), 1, 12) || 'CCC' AS "LastModifiedById",
    TO_CHAR(CURRENT_TIMESTAMP(), 'YYYY-MM-DD"T"HH24:MI:SS.000Z') AS "SystemModstamp",
    ARRAY_CONSTRUCT('Acme Corp', 'Global Industries', 'Tech Solutions', 'Prime Manufacturing')[UNIFORM(0, 3, RANDOM())] || ' ' || SEQ4() AS "Name",
    ARRAY_CONSTRUCT('Prospect', 'Customer - Direct', 'Customer - Channel', 'Partner')[UNIFORM(0, 3, RANDOM())] AS "Type",
    ARRAY_CONSTRUCT('Technology', 'Healthcare', 'Finance', 'Retail', 'Manufacturing')[UNIFORM(0, 4, RANDOM())] AS "Industry",
    ROUND(UNIFORM(100000, 100000000, RANDOM())::FLOAT, 2) AS "AnnualRevenue",
    UNIFORM(10, 10000, RANDOM()) AS "NumberOfEmployees",
    ARRAY_CONSTRUCT('Hot', 'Warm', 'Cold')[UNIFORM(0, 2, RANDOM())] AS "Rating",
    UNIFORM(100, 9999, RANDOM()) || ' ' || ARRAY_CONSTRUCT('Main', 'Oak', 'Commerce')[UNIFORM(0, 2, RANDOM())] || ' Street' AS "BillingStreet",
    ARRAY_CONSTRUCT('New York', 'Los Angeles', 'Chicago', 'Houston', 'Phoenix')[UNIFORM(0, 4, RANDOM())] AS "BillingCity",
    ARRAY_CONSTRUCT('NY', 'CA', 'IL', 'TX', 'AZ')[UNIFORM(0, 4, RANDOM())] AS "BillingState",
    LPAD(UNIFORM(10000, 99999, RANDOM())::STRING, 5, '0') AS "BillingPostalCode",
    'United States' AS "BillingCountry",
    "BillingStreet" AS "ShippingStreet",
    "BillingCity" AS "ShippingCity",
    "BillingState" AS "ShippingState",
    "BillingPostalCode" AS "ShippingPostalCode",
    "BillingCountry" AS "ShippingCountry",
    '+1-' || UNIFORM(200, 999, RANDOM()) || '-' || UNIFORM(200, 999, RANDOM()) || '-' || UNIFORM(1000, 9999, RANDOM()) AS "Phone",
    NULL AS "Fax",
    'https://www.' || LOWER(REPLACE("Name", ' ', '')) || '.com' AS "Website",
    '005' || SUBSTRING(UUID_STRING(), 1, 12) || 'DDD' AS "OwnerId",
    ARRAY_CONSTRUCT('Enterprise', 'Mid-Market', 'SMB', 'Startup')[UNIFORM(0, 3, RANDOM())] AS "Customer_Segment__c",
    ARRAY_CONSTRUCT('Lead', 'Prospect', 'Customer', 'Churned')[UNIFORM(0, 3, RANDOM())] AS "Lifecycle_Stage__c",
    -- SCD Type 2 columns
    CURRENT_TIMESTAMP() AS "_LOADED_AT",
    'SALESFORCE' AS "_SOURCE_SYSTEM",
    'Account' AS "_SOURCE_TABLE",
    SHA2(SEQ4()::STRING, 256) AS "_ROW_HASH",
    TRUE AS "_IS_CURRENT",
    CURRENT_TIMESTAMP() AS "_VALID_FROM",
    '9999-12-31' AS "_VALID_TO"
FROM TABLE(GENERATOR(ROWCOUNT => 1000));

-- ─────────────────────────────────────────────────────────────────────────────
-- Salesforce Opportunity - Quick Demo Data
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS RAW_DEV.SALESFORCE.OPPORTUNITY AS
SELECT
    '006' || SUBSTRING(UUID_STRING(), 1, 12) || 'AAA' AS "Id",
    FALSE AS "IsDeleted",
    TO_CHAR(DATEADD(DAY, -UNIFORM(1, 730, RANDOM()), CURRENT_TIMESTAMP()), 'YYYY-MM-DD"T"HH24:MI:SS.000Z') AS "CreatedDate",
    '005' || SUBSTRING(UUID_STRING(), 1, 12) || 'BBB' AS "CreatedById",
    '001' || SUBSTRING(UUID_STRING(), 1, 12) || 'CCC' AS "AccountId",
    '005' || SUBSTRING(UUID_STRING(), 1, 12) || 'DDD' AS "OwnerId",
    'Deal ' || SEQ4() || ' - ' || ARRAY_CONSTRUCT('Q1', 'Q2', 'Q3', 'Q4')[UNIFORM(0, 3, RANDOM())] AS "Name",
    ROUND(UNIFORM(5000, 500000, RANDOM())::FLOAT, 2) AS "Amount",
    DATEADD(DAY, UNIFORM(30, 180, RANDOM()), CURRENT_DATE())::DATE AS "CloseDate",
    ARRAY_CONSTRUCT('Prospecting', 'Qualification', 'Needs Analysis', 'Proposal', 'Negotiation', 'Closed Won', 'Closed Lost')[UNIFORM(0, 6, RANDOM())] AS "StageName",
    CASE "StageName"
        WHEN 'Prospecting' THEN 10
        WHEN 'Qualification' THEN 20
        WHEN 'Needs Analysis' THEN 30
        WHEN 'Proposal' THEN 70
        WHEN 'Negotiation' THEN 80
        WHEN 'Closed Won' THEN 100
        WHEN 'Closed Lost' THEN 0
        ELSE 50
    END AS "Probability",
    ARRAY_CONSTRUCT('New Customer', 'Existing Customer - Upgrade', 'Existing Customer - Replacement')[UNIFORM(0, 2, RANDOM())] AS "Type",
    ARRAY_CONSTRUCT('Web', 'Partner', 'Trade Show', 'Cold Call', 'Referral')[UNIFORM(0, 4, RANDOM())] AS "LeadSource",
    "StageName" IN ('Closed Won', 'Closed Lost') AS "IsClosed",
    "StageName" = 'Closed Won' AS "IsWon",
    CASE 
        WHEN "Probability" < 50 THEN 'Pipeline'
        WHEN "Probability" < 80 THEN 'Best Case'
        ELSE 'Commit'
    END AS "ForecastCategory",
    UNIFORM(1, 4, RANDOM()) AS "FiscalQuarter",
    YEAR(CURRENT_DATE()) AS "FiscalYear",
    -- SCD Type 2 columns
    CURRENT_TIMESTAMP() AS "_LOADED_AT",
    'SALESFORCE' AS "_SOURCE_SYSTEM",
    'Opportunity' AS "_SOURCE_TABLE",
    SHA2(SEQ4()::STRING, 256) AS "_ROW_HASH",
    TRUE AS "_IS_CURRENT",
    CURRENT_TIMESTAMP() AS "_VALID_FROM",
    '9999-12-31' AS "_VALID_TO"
FROM TABLE(GENERATOR(ROWCOUNT => 2000));

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT '✓ Data Loading Complete' AS STATUS;

-- Show loaded tables by source system
SELECT 
    TABLE_SCHEMA AS SCHEMA_NAME,
    TABLE_NAME,
    ROW_COUNT,
    CREATED AS CREATED_AT
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_CATALOG = 'RAW_DEV'
  AND TABLE_SCHEMA IN ('SAP', 'SALESFORCE', 'ORACLE', 'FHIR', 'WORKDAY', 'SERVICENOW')
  AND TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_SCHEMA, TABLE_NAME;
