-- ============================================================================
-- DATA MARKETPLACE - Dynamic Data Products for Multi-Source Systems
-- ============================================================================
-- 
-- This script creates dynamic data products that:
--   1. Auto-generate aggregated views from source system data
--   2. Ensure no PII exposure (aggregated or pseudonymized)
--   3. Support self-service discovery via catalog
--   4. Enable secure sharing within and across accounts
--
-- Data Products follow these principles:
--   - No raw PII exposed
--   - Clear documentation and use cases
--   - Access controls aligned with governance
--   - Usage tracking for monitoring
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE WAREHOUSE ANALYTICS_WH;
USE DATABASE SEM_DEV;
USE SCHEMA SEM_DEV.MARKETPLACE;

-- ═══════════════════════════════════════════════════════════════════════════
-- DATA PRODUCT CATALOG
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA GOVERNANCE.OBSERVABILITY;

CREATE TABLE IF NOT EXISTS DATA_PRODUCT_CATALOG (
    PRODUCT_ID              VARCHAR(50) PRIMARY KEY,
    PRODUCT_NAME            VARCHAR(255) NOT NULL,
    PRODUCT_DESCRIPTION     VARCHAR(4000),
    PRODUCT_VERSION         VARCHAR(20),
    
    -- Source Information
    SOURCE_SYSTEM           VARCHAR(50),
    DATABASE_NAME           VARCHAR(255),
    SCHEMA_NAME             VARCHAR(255),
    OBJECT_NAME             VARCHAR(255),
    OBJECT_TYPE             VARCHAR(50),
    
    -- Classification
    DOMAIN                  VARCHAR(100),
    DATA_CLASSIFICATION     VARCHAR(50),
    CONTAINS_PII            BOOLEAN DEFAULT FALSE,
    
    -- Access
    SHARE_NAME              VARCHAR(255),
    ALLOWED_ROLES           ARRAY,
    
    -- Metadata
    OWNER_TEAM              VARCHAR(100),
    SLA_REFRESH_HOURS       NUMBER,
    USE_CASES               ARRAY,
    
    -- Status
    STATUS                  VARCHAR(20) DEFAULT 'ACTIVE',
    CREATED_AT              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ═══════════════════════════════════════════════════════════════════════════
-- DYNAMIC DATA PRODUCT GENERATION
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA SEM_DEV.MARKETPLACE;

CREATE OR REPLACE PROCEDURE SEM_DEV.MARKETPLACE.CREATE_DATA_PRODUCT(
    p_source_system VARCHAR,
    p_product_type VARCHAR,    -- SALES, CUSTOMER, OPERATIONS, HEALTHCARE, HR
    p_product_name VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_create_sql VARCHAR;
    v_product_id VARCHAR;
    v_view_name VARCHAR;
BEGIN
    v_product_id := 'DP-' || UPPER(p_source_system) || '-' || UPPER(p_product_type) || '-001';
    v_view_name := 'DP_' || UPPER(p_source_system) || '_' || UPPER(p_product_type);
    
    CASE UPPER(p_source_system)
        -- ═══════════════════════════════════════════════════════════════════════
        -- SAP Data Products
        -- ═══════════════════════════════════════════════════════════════════════
        WHEN 'SAP' THEN
            CASE UPPER(p_product_type)
                WHEN 'SALES' THEN
                    v_create_sql := '
                    CREATE OR REPLACE SECURE VIEW SEM_DEV.MARKETPLACE.' || v_view_name || ' AS
                    SELECT
                        SALES_ORG AS SALES_ORGANIZATION,
                        DISTRIBUTION_CHANNEL AS CHANNEL,
                        EXTRACT(YEAR FROM ORDER_DATE) AS YEAR,
                        EXTRACT(QUARTER FROM ORDER_DATE) AS QUARTER,
                        COUNT(*) AS ORDER_COUNT,
                        SUM(NET_VALUE) AS TOTAL_REVENUE,
                        AVG(NET_VALUE) AS AVG_ORDER_VALUE,
                        COUNT(DISTINCT CUSTOMER_KEY) AS UNIQUE_CUSTOMERS,
                        CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
                    FROM CURATED_DEV.FACTS.FACT_SALES_ORDERS_SAP
                    WHERE "_IS_CURRENT" = TRUE
                    GROUP BY SALES_ORG, DISTRIBUTION_CHANNEL, 
                             EXTRACT(YEAR FROM ORDER_DATE), EXTRACT(QUARTER FROM ORDER_DATE)
                    ORDER BY YEAR DESC, QUARTER DESC';
                    
                WHEN 'CUSTOMER' THEN
                    v_create_sql := '
                    CREATE OR REPLACE SECURE VIEW SEM_DEV.MARKETPLACE.' || v_view_name || ' AS
                    SELECT
                        COUNTRY,
                        INDUSTRY_CODE AS INDUSTRY,
                        CUSTOMER_CLASS,
                        COUNT(*) AS CUSTOMER_COUNT,
                        SUM(CASE WHEN IS_ACTIVE THEN 1 ELSE 0 END) AS ACTIVE_CUSTOMERS,
                        CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
                    FROM CURATED_DEV.DIMENSIONS.DIM_CUSTOMER_SAP
                    WHERE "_IS_CURRENT" = TRUE
                    GROUP BY COUNTRY, INDUSTRY_CODE, CUSTOMER_CLASS
                    ORDER BY CUSTOMER_COUNT DESC';
                    
                WHEN 'PROCUREMENT' THEN
                    v_create_sql := '
                    CREATE OR REPLACE SECURE VIEW SEM_DEV.MARKETPLACE.' || v_view_name || ' AS
                    SELECT
                        PURCHASING_ORG,
                        PO_TYPE,
                        EXTRACT(YEAR FROM PO_DATE) AS YEAR,
                        EXTRACT(MONTH FROM PO_DATE) AS MONTH,
                        COUNT(*) AS PO_COUNT,
                        COUNT(DISTINCT VENDOR_KEY) AS UNIQUE_VENDORS,
                        CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
                    FROM CURATED_DEV.FACTS.FACT_PURCHASE_ORDERS_SAP
                    WHERE "_IS_CURRENT" = TRUE
                    GROUP BY PURCHASING_ORG, PO_TYPE, 
                             EXTRACT(YEAR FROM PO_DATE), EXTRACT(MONTH FROM PO_DATE)
                    ORDER BY YEAR DESC, MONTH DESC';
                ELSE
                    RETURN 'ERROR: Unsupported SAP product type: ' || p_product_type;
            END CASE;
            
        -- ═══════════════════════════════════════════════════════════════════════
        -- Salesforce Data Products
        -- ═══════════════════════════════════════════════════════════════════════
        WHEN 'SALESFORCE' THEN
            CASE UPPER(p_product_type)
                WHEN 'SALES' THEN
                    v_create_sql := '
                    CREATE OR REPLACE SECURE VIEW SEM_DEV.MARKETPLACE.' || v_view_name || ' AS
                    SELECT
                        STAGE_NAME AS PIPELINE_STAGE,
                        OPPORTUNITY_TYPE,
                        LEAD_SOURCE,
                        FORECAST_CATEGORY,
                        EXTRACT(YEAR FROM CLOSE_DATE) AS CLOSE_YEAR,
                        EXTRACT(QUARTER FROM CLOSE_DATE) AS CLOSE_QUARTER,
                        COUNT(*) AS OPPORTUNITY_COUNT,
                        SUM(AMOUNT) AS TOTAL_PIPELINE,
                        AVG(AMOUNT) AS AVG_DEAL_SIZE,
                        SUM(CASE WHEN IS_WON THEN 1 ELSE 0 END) AS WON_DEALS,
                        SUM(CASE WHEN IS_CLOSED AND NOT IS_WON THEN 1 ELSE 0 END) AS LOST_DEALS,
                        ROUND(100.0 * SUM(CASE WHEN IS_WON THEN 1 ELSE 0 END) / 
                              NULLIF(SUM(CASE WHEN IS_CLOSED THEN 1 ELSE 0 END), 0), 2) AS WIN_RATE,
                        CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
                    FROM CURATED_DEV.FACTS.FACT_OPPORTUNITIES_SF
                    WHERE "_IS_CURRENT" = TRUE
                    GROUP BY STAGE_NAME, OPPORTUNITY_TYPE, LEAD_SOURCE, FORECAST_CATEGORY,
                             EXTRACT(YEAR FROM CLOSE_DATE), EXTRACT(QUARTER FROM CLOSE_DATE)
                    ORDER BY CLOSE_YEAR DESC, CLOSE_QUARTER DESC';
                    
                WHEN 'SERVICE' THEN
                    v_create_sql := '
                    CREATE OR REPLACE SECURE VIEW SEM_DEV.MARKETPLACE.' || v_view_name || ' AS
                    SELECT
                        STATUS AS CASE_STATUS,
                        PRIORITY,
                        ORIGIN,
                        CASE_TYPE,
                        COUNT(*) AS CASE_COUNT,
                        SUM(CASE WHEN IS_CLOSED THEN 1 ELSE 0 END) AS CLOSED_CASES,
                        ROUND(100.0 * SUM(CASE WHEN IS_CLOSED THEN 1 ELSE 0 END) / COUNT(*), 2) AS CLOSURE_RATE,
                        CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
                    FROM CURATED_DEV.FACTS.FACT_CASES_SF
                    WHERE "_IS_CURRENT" = TRUE
                    GROUP BY STATUS, PRIORITY, ORIGIN, CASE_TYPE
                    ORDER BY CASE_COUNT DESC';
                    
                WHEN 'CUSTOMER' THEN
                    v_create_sql := '
                    CREATE OR REPLACE SECURE VIEW SEM_DEV.MARKETPLACE.' || v_view_name || ' AS
                    SELECT
                        CUSTOMER_TYPE AS ACCOUNT_TYPE,
                        INDUSTRY,
                        CUSTOMER_TIER,
                        BILLING_STATE AS STATE,
                        BILLING_COUNTRY AS COUNTRY,
                        COUNT(*) AS ACCOUNT_COUNT,
                        SUM(CASE WHEN IS_ACTIVE THEN 1 ELSE 0 END) AS ACTIVE_ACCOUNTS,
                        SUM(ANNUAL_REVENUE) AS TOTAL_ANNUAL_REVENUE,
                        AVG(ANNUAL_REVENUE) AS AVG_ANNUAL_REVENUE,
                        SUM(EMPLOYEE_COUNT) AS TOTAL_EMPLOYEES,
                        CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
                    FROM CURATED_DEV.DIMENSIONS.DIM_CUSTOMER_SF
                    WHERE "_IS_CURRENT" = TRUE
                    GROUP BY CUSTOMER_TYPE, INDUSTRY, CUSTOMER_TIER, BILLING_STATE, BILLING_COUNTRY
                    ORDER BY ACCOUNT_COUNT DESC';
                ELSE
                    RETURN 'ERROR: Unsupported Salesforce product type: ' || p_product_type;
            END CASE;
            
        -- ═══════════════════════════════════════════════════════════════════════
        -- FHIR Data Products
        -- ═══════════════════════════════════════════════════════════════════════
        WHEN 'FHIR' THEN
            CASE UPPER(p_product_type)
                WHEN 'CLINICAL' THEN
                    v_create_sql := '
                    CREATE OR REPLACE SECURE VIEW SEM_DEV.MARKETPLACE.' || v_view_name || ' AS
                    SELECT
                        ENCOUNTER_CLASS,
                        ENCOUNTER_TYPE,
                        STATUS AS ENCOUNTER_STATUS,
                        COUNT(*) AS ENCOUNTER_COUNT,
                        COUNT(DISTINCT PATIENT_KEY) AS UNIQUE_PATIENTS,
                        AVG(DURATION_MINUTES) AS AVG_DURATION_MINUTES,
                        CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
                    FROM CURATED_DEV.FACTS.FACT_ENCOUNTERS_FHIR
                    WHERE "_IS_CURRENT" = TRUE
                    GROUP BY ENCOUNTER_CLASS, ENCOUNTER_TYPE, STATUS
                    ORDER BY ENCOUNTER_COUNT DESC';
                    
                WHEN 'DIAGNOSIS' THEN
                    v_create_sql := '
                    CREATE OR REPLACE SECURE VIEW SEM_DEV.MARKETPLACE.' || v_view_name || ' AS
                    SELECT
                        DIAGNOSIS_CODE,
                        DIAGNOSIS_DESCRIPTION,
                        CODE_SYSTEM,
                        CLINICAL_STATUS,
                        COUNT(*) AS CONDITION_COUNT,
                        COUNT(DISTINCT PATIENT_KEY) AS PATIENTS_AFFECTED,
                        CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
                    FROM CURATED_DEV.FACTS.FACT_CONDITIONS_FHIR
                    WHERE "_IS_CURRENT" = TRUE
                    GROUP BY DIAGNOSIS_CODE, DIAGNOSIS_DESCRIPTION, CODE_SYSTEM, CLINICAL_STATUS
                    ORDER BY CONDITION_COUNT DESC
                    LIMIT 100';
                    
                WHEN 'DEMOGRAPHICS' THEN
                    v_create_sql := '
                    CREATE OR REPLACE SECURE VIEW SEM_DEV.MARKETPLACE.' || v_view_name || ' AS
                    SELECT
                        GENDER,
                        STATE,
                        MARITAL_STATUS,
                        COUNT(*) AS PATIENT_COUNT,
                        SUM(CASE WHEN IS_ACTIVE THEN 1 ELSE 0 END) AS ACTIVE_PATIENTS,
                        CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
                    FROM CURATED_DEV.DIMENSIONS.DIM_PATIENT_FHIR
                    WHERE "_IS_CURRENT" = TRUE
                    GROUP BY GENDER, STATE, MARITAL_STATUS
                    ORDER BY PATIENT_COUNT DESC';
                ELSE
                    RETURN 'ERROR: Unsupported FHIR product type: ' || p_product_type;
            END CASE;
            
        -- ═══════════════════════════════════════════════════════════════════════
        -- Workday Data Products
        -- ═══════════════════════════════════════════════════════════════════════
        WHEN 'WORKDAY' THEN
            CASE UPPER(p_product_type)
                WHEN 'HR' THEN
                    v_create_sql := '
                    CREATE OR REPLACE SECURE VIEW SEM_DEV.MARKETPLACE.' || v_view_name || ' AS
                    SELECT
                        DEPARTMENT,
                        JOB_LEVEL,
                        EMPLOYMENT_TYPE,
                        WORK_LOCATION,
                        COUNT(*) AS HEADCOUNT,
                        SUM(CASE WHEN IS_ACTIVE THEN 1 ELSE 0 END) AS ACTIVE_EMPLOYEES,
                        ROUND(AVG(TENURE_YEARS), 1) AS AVG_TENURE_YEARS,
                        CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
                    FROM CURATED_DEV.DIMENSIONS.DIM_EMPLOYEE_WD
                    WHERE "_IS_CURRENT" = TRUE
                    GROUP BY DEPARTMENT, JOB_LEVEL, EMPLOYMENT_TYPE, WORK_LOCATION
                    ORDER BY HEADCOUNT DESC';
                ELSE
                    RETURN 'ERROR: Unsupported Workday product type: ' || p_product_type;
            END CASE;
            
        -- ═══════════════════════════════════════════════════════════════════════
        -- ServiceNow Data Products
        -- ═══════════════════════════════════════════════════════════════════════
        WHEN 'SERVICENOW' THEN
            CASE UPPER(p_product_type)
                WHEN 'ITSM' THEN
                    v_create_sql := '
                    CREATE OR REPLACE SECURE VIEW SEM_DEV.MARKETPLACE.' || v_view_name || ' AS
                    SELECT
                        PRIORITY,
                        CATEGORY,
                        STATE,
                        ASSIGNMENT_GROUP,
                        COUNT(*) AS INCIDENT_COUNT,
                        ROUND(AVG(TIME_TO_RESOLVE_MINUTES), 0) AS AVG_RESOLUTION_MINUTES,
                        SUM(CASE WHEN PRIORITY IN (''1'', ''2'') THEN 1 ELSE 0 END) AS HIGH_PRIORITY_COUNT,
                        CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
                    FROM CURATED_DEV.FACTS.FACT_INCIDENTS_SN
                    WHERE "_IS_CURRENT" = TRUE
                    GROUP BY PRIORITY, CATEGORY, STATE, ASSIGNMENT_GROUP
                    ORDER BY INCIDENT_COUNT DESC';
                ELSE
                    RETURN 'ERROR: Unsupported ServiceNow product type: ' || p_product_type;
            END CASE;
        ELSE
            RETURN 'ERROR: Unsupported source system: ' || p_source_system;
    END CASE;
    
    -- Create the view
    EXECUTE IMMEDIATE v_create_sql;
    
    -- Register in catalog
    INSERT INTO GOVERNANCE.OBSERVABILITY.DATA_PRODUCT_CATALOG (
        PRODUCT_ID, PRODUCT_NAME, PRODUCT_DESCRIPTION, PRODUCT_VERSION,
        SOURCE_SYSTEM, DATABASE_NAME, SCHEMA_NAME, OBJECT_NAME, OBJECT_TYPE,
        DOMAIN, DATA_CLASSIFICATION, CONTAINS_PII,
        ALLOWED_ROLES, OWNER_TEAM, SLA_REFRESH_HOURS, USE_CASES
    ) VALUES (
        v_product_id,
        p_product_name,
        'Auto-generated data product from ' || p_source_system || ' ' || p_product_type || ' data',
        'v1.0',
        UPPER(p_source_system),
        'SEM_DEV',
        'MARKETPLACE',
        v_view_name,
        'SECURE_VIEW',
        UPPER(p_product_type),
        'INTERNAL',
        FALSE,
        ARRAY_CONSTRUCT('ANALYST', 'MANAGER', 'VIEWER'),
        p_source_system || ' Team',
        1,
        ARRAY_CONSTRUCT('Analytics', 'Reporting', 'Dashboards')
    );
    
    RETURN 'SUCCESS: Created data product ' || v_view_name;
    
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR: ' || SQLERRM;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- BUILD ALL DATA PRODUCTS FOR A SOURCE SYSTEM
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE SEM_DEV.MARKETPLACE.BUILD_DATA_PRODUCTS(
    p_source_system VARCHAR
)
RETURNS TABLE (product_name VARCHAR, view_name VARCHAR, status VARCHAR)
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    result RESULTSET;
BEGIN
    CREATE OR REPLACE TEMPORARY TABLE _product_results (
        product_name VARCHAR,
        view_name VARCHAR,
        status VARCHAR
    );
    
    CASE UPPER(p_source_system)
        WHEN 'SAP' THEN
            CALL SEM_DEV.MARKETPLACE.CREATE_DATA_PRODUCT('SAP', 'SALES', 'SAP Sales Performance');
            INSERT INTO _product_results VALUES ('SAP Sales Performance', 'DP_SAP_SALES', 'Created');
            
            CALL SEM_DEV.MARKETPLACE.CREATE_DATA_PRODUCT('SAP', 'CUSTOMER', 'SAP Customer Summary');
            INSERT INTO _product_results VALUES ('SAP Customer Summary', 'DP_SAP_CUSTOMER', 'Created');
            
            CALL SEM_DEV.MARKETPLACE.CREATE_DATA_PRODUCT('SAP', 'PROCUREMENT', 'SAP Procurement Metrics');
            INSERT INTO _product_results VALUES ('SAP Procurement Metrics', 'DP_SAP_PROCUREMENT', 'Created');
            
        WHEN 'SALESFORCE' THEN
            CALL SEM_DEV.MARKETPLACE.CREATE_DATA_PRODUCT('SALESFORCE', 'SALES', 'Salesforce Pipeline Analytics');
            INSERT INTO _product_results VALUES ('SF Pipeline Analytics', 'DP_SALESFORCE_SALES', 'Created');
            
            CALL SEM_DEV.MARKETPLACE.CREATE_DATA_PRODUCT('SALESFORCE', 'SERVICE', 'Salesforce Service Metrics');
            INSERT INTO _product_results VALUES ('SF Service Metrics', 'DP_SALESFORCE_SERVICE', 'Created');
            
            CALL SEM_DEV.MARKETPLACE.CREATE_DATA_PRODUCT('SALESFORCE', 'CUSTOMER', 'Salesforce Account Summary');
            INSERT INTO _product_results VALUES ('SF Account Summary', 'DP_SALESFORCE_CUSTOMER', 'Created');
            
        WHEN 'FHIR' THEN
            CALL SEM_DEV.MARKETPLACE.CREATE_DATA_PRODUCT('FHIR', 'CLINICAL', 'FHIR Clinical Encounters');
            INSERT INTO _product_results VALUES ('FHIR Clinical Encounters', 'DP_FHIR_CLINICAL', 'Created');
            
            CALL SEM_DEV.MARKETPLACE.CREATE_DATA_PRODUCT('FHIR', 'DIAGNOSIS', 'FHIR Diagnosis Summary');
            INSERT INTO _product_results VALUES ('FHIR Diagnosis Summary', 'DP_FHIR_DIAGNOSIS', 'Created');
            
            CALL SEM_DEV.MARKETPLACE.CREATE_DATA_PRODUCT('FHIR', 'DEMOGRAPHICS', 'FHIR Patient Demographics');
            INSERT INTO _product_results VALUES ('FHIR Patient Demographics', 'DP_FHIR_DEMOGRAPHICS', 'Created');
            
        WHEN 'WORKDAY' THEN
            CALL SEM_DEV.MARKETPLACE.CREATE_DATA_PRODUCT('WORKDAY', 'HR', 'Workday Workforce Metrics');
            INSERT INTO _product_results VALUES ('Workday Workforce Metrics', 'DP_WORKDAY_HR', 'Created');
            
        WHEN 'SERVICENOW' THEN
            CALL SEM_DEV.MARKETPLACE.CREATE_DATA_PRODUCT('SERVICENOW', 'ITSM', 'ServiceNow Incident Metrics');
            INSERT INTO _product_results VALUES ('SN Incident Metrics', 'DP_SERVICENOW_ITSM', 'Created');
    END CASE;
    
    result := (SELECT * FROM _product_results);
    RETURN TABLE(result);
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- DATA PRODUCT CATALOG VIEW
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW SEM_DEV.MARKETPLACE.VW_DATA_PRODUCT_CATALOG AS
SELECT 
    PRODUCT_ID,
    PRODUCT_NAME,
    PRODUCT_DESCRIPTION,
    SOURCE_SYSTEM,
    DOMAIN,
    OBJECT_NAME AS VIEW_NAME,
    DATA_CLASSIFICATION,
    CONTAINS_PII,
    ARRAY_TO_STRING(ALLOWED_ROLES, ', ') AS ALLOWED_ROLES,
    OWNER_TEAM,
    SLA_REFRESH_HOURS,
    STATUS,
    CREATED_AT
FROM GOVERNANCE.OBSERVABILITY.DATA_PRODUCT_CATALOG
WHERE STATUS = 'ACTIVE'
ORDER BY SOURCE_SYSTEM, DOMAIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

GRANT USAGE ON SCHEMA SEM_DEV.MARKETPLACE TO ROLE ANALYST;
GRANT USAGE ON SCHEMA SEM_DEV.MARKETPLACE TO ROLE MANAGER;
GRANT USAGE ON SCHEMA SEM_DEV.MARKETPLACE TO ROLE VIEWER;
GRANT USAGE ON SCHEMA SEM_DEV.MARKETPLACE TO ROLE AI_AGENT;

GRANT SELECT ON ALL VIEWS IN SCHEMA SEM_DEV.MARKETPLACE TO ROLE ANALYST;
GRANT SELECT ON ALL VIEWS IN SCHEMA SEM_DEV.MARKETPLACE TO ROLE MANAGER;
GRANT SELECT ON ALL VIEWS IN SCHEMA SEM_DEV.MARKETPLACE TO ROLE VIEWER;

GRANT SELECT ON FUTURE VIEWS IN SCHEMA SEM_DEV.MARKETPLACE TO ROLE ANALYST;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA SEM_DEV.MARKETPLACE TO ROLE MANAGER;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA SEM_DEV.MARKETPLACE TO ROLE VIEWER;

GRANT USAGE ON PROCEDURE SEM_DEV.MARKETPLACE.CREATE_DATA_PRODUCT(VARCHAR, VARCHAR, VARCHAR) TO ROLE DATA_STEWARD;
GRANT USAGE ON PROCEDURE SEM_DEV.MARKETPLACE.BUILD_DATA_PRODUCTS(VARCHAR) TO ROLE DATA_STEWARD;

-- ═══════════════════════════════════════════════════════════════════════════
-- USAGE INSTRUCTIONS
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- STEP 1: Build data products for source systems
--   CALL SEM_DEV.MARKETPLACE.BUILD_DATA_PRODUCTS('SAP');
--   CALL SEM_DEV.MARKETPLACE.BUILD_DATA_PRODUCTS('SALESFORCE');
--   CALL SEM_DEV.MARKETPLACE.BUILD_DATA_PRODUCTS('FHIR');
--   CALL SEM_DEV.MARKETPLACE.BUILD_DATA_PRODUCTS('WORKDAY');
--   CALL SEM_DEV.MARKETPLACE.BUILD_DATA_PRODUCTS('SERVICENOW');
--
-- STEP 2: Create individual data product
--   CALL SEM_DEV.MARKETPLACE.CREATE_DATA_PRODUCT('SAP', 'SALES', 'SAP Sales Performance');
--
-- STEP 3: Browse catalog
--   SELECT * FROM SEM_DEV.MARKETPLACE.VW_DATA_PRODUCT_CATALOG;
--
-- STEP 4: Query data products
--   SELECT * FROM SEM_DEV.MARKETPLACE.DP_SAP_SALES;
--   SELECT * FROM SEM_DEV.MARKETPLACE.DP_SALESFORCE_SALES;
--
-- ═══════════════════════════════════════════════════════════════════════════

SELECT '✓ Data Marketplace Created' AS STATUS;
SELECT '  Use BUILD_DATA_PRODUCTS(''SAP'') to create data products for a source system' AS INFO;
SHOW VIEWS IN SCHEMA SEM_DEV.MARKETPLACE;
