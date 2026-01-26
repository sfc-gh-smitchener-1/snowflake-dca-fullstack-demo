-- ============================================================================
-- SEMANTIC LAYER - Dynamic Native Semantic Views for Cortex Analyst
-- ============================================================================
-- 
-- This script creates dynamic semantic views that:
--   1. Support multiple source systems (SAP, Salesforce, Oracle, FHIR, etc.)
--   2. Provide pre-defined dimensions and metrics for Cortex Analyst
--   3. Enable natural language query capabilities
--   4. Map source system fields to business-friendly names
--
-- Semantic Views are the Gold layer - optimized for consumption by:
--   - Cortex Analyst (natural language to SQL)
--   - Business analysts (self-service)
--   - AI/ML workloads (with pseudonymized data)
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE SEM_DEV;
USE WAREHOUSE ANALYTICS_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- SEMANTIC VIEW CREATION PROCEDURE
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Creates semantic views dynamically based on curated layer tables.
-- Maps source system curated tables to semantic views.
--
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE SEM_DEV.SEM_SALES.CREATE_SEMANTIC_VIEW_FOR_SOURCE(
    p_source_system VARCHAR,
    p_semantic_domain VARCHAR  -- SALES, CUSTOMER, HR, OPERATIONS, HEALTHCARE
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_create_sql VARCHAR;
    v_view_name VARCHAR;
BEGIN
    CASE UPPER(p_source_system)
        -- ═══════════════════════════════════════════════════════════════════════
        -- SAP Semantic Views
        -- ═══════════════════════════════════════════════════════════════════════
        WHEN 'SAP' THEN
            CASE UPPER(p_semantic_domain)
                WHEN 'SALES' THEN
                    v_view_name := 'SAP_SALES_ANALYTICS';
                    v_create_sql := '
                    CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.SEM_SALES.' || v_view_name || '
                      TABLES (
                        orders AS CURATED_DEV.FACTS.FACT_SALES_ORDERS_SAP PRIMARY KEY (ORDER_KEY),
                        customers AS CURATED_DEV.DIMENSIONS.DIM_CUSTOMER_SAP PRIMARY KEY (CUSTOMER_KEY),
                        products AS CURATED_DEV.DIMENSIONS.DIM_PRODUCT_SAP PRIMARY KEY (PRODUCT_KEY),
                        dates AS CURATED_DEV.DIMENSIONS.DIM_DATE PRIMARY KEY (DATE_KEY)
                      )
                      RELATIONSHIPS (
                        orders(CUSTOMER_KEY) REFERENCES customers(CUSTOMER_KEY),
                        orders(ORDER_DATE) REFERENCES dates(DATE_KEY)
                      )
                      DIMENSIONS (
                        dates.YEAR AS year COMMENT ''Calendar year'',
                        dates.QUARTER AS quarter COMMENT ''Quarter (1-4)'',
                        dates.MONTH_NAME AS month COMMENT ''Month name'',
                        dates.FISCAL_YEAR AS fiscal_year COMMENT ''Fiscal year'',
                        
                        customers.CUSTOMER_ID AS customer_id COMMENT ''SAP Customer Number (KUNNR)'',
                        customers.CUSTOMER_NAME AS customer_name COMMENT ''Customer name (NAME1)'',
                        customers.CITY AS city COMMENT ''City (ORT01)'',
                        customers.COUNTRY AS country COMMENT ''Country (LAND1)'',
                        customers.INDUSTRY_CODE AS industry COMMENT ''Industry sector (BRSCH)'',
                        customers.IS_ACTIVE AS is_active_customer,
                        
                        orders.ORDER_NUMBER AS order_number COMMENT ''Sales document number (VBELN)'',
                        orders.SALES_ORG AS sales_organization COMMENT ''Sales organization (VKORG)'',
                        orders.DISTRIBUTION_CHANNEL AS channel COMMENT ''Distribution channel (VTWEG)'',
                        orders.ORDER_TYPE AS order_type COMMENT ''Sales document type (AUART)'',
                        orders.ORDER_STATUS AS status COMMENT ''Overall status (GBSTK)'',
                        orders.IS_COMPLETED AS is_completed
                      )
                      METRICS (
                        orders.total_revenue AS SUM(orders.NET_VALUE) COMMENT ''Total net value (NETWR)'',
                        orders.avg_order_value AS AVG(orders.NET_VALUE) COMMENT ''Average order value'',
                        orders.order_count AS COUNT(orders.ORDER_KEY) COMMENT ''Number of orders'',
                        orders.completed_orders AS SUM(CASE WHEN orders.IS_COMPLETED THEN 1 ELSE 0 END) COMMENT ''Completed orders'',
                        customers.customer_count AS COUNT(DISTINCT customers.CUSTOMER_KEY) COMMENT ''Unique customers''
                      )
                      COMMENT = ''SAP S/4HANA Sales Analytics - Orders (VBAK), Customers (KNA1), Materials (MARA)''';
                      
                WHEN 'PROCUREMENT' THEN
                    v_view_name := 'SAP_PROCUREMENT_ANALYTICS';
                    v_create_sql := '
                    CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.SEM_OPERATIONS.' || v_view_name || '
                      TABLES (
                        purchase_orders AS CURATED_DEV.FACTS.FACT_PURCHASE_ORDERS_SAP PRIMARY KEY (PO_KEY),
                        vendors AS CURATED_DEV.DIMENSIONS.DIM_VENDOR_SAP PRIMARY KEY (VENDOR_KEY),
                        dates AS CURATED_DEV.DIMENSIONS.DIM_DATE PRIMARY KEY (DATE_KEY)
                      )
                      RELATIONSHIPS (
                        purchase_orders(VENDOR_KEY) REFERENCES vendors(VENDOR_KEY),
                        purchase_orders(PO_DATE) REFERENCES dates(DATE_KEY)
                      )
                      DIMENSIONS (
                        dates.YEAR AS year,
                        dates.QUARTER AS quarter,
                        dates.MONTH_NAME AS month,
                        
                        vendors.VENDOR_ID AS vendor_id COMMENT ''Vendor number (LIFNR)'',
                        vendors.VENDOR_NAME AS vendor_name COMMENT ''Vendor name (NAME1)'',
                        vendors.COUNTRY AS vendor_country,
                        vendors.IS_ACTIVE AS is_active_vendor,
                        
                        purchase_orders.PO_NUMBER AS po_number COMMENT ''Purchase order (EBELN)'',
                        purchase_orders.PURCHASING_ORG AS purchasing_org COMMENT ''Purchasing org (EKORG)'',
                        purchase_orders.PO_TYPE AS po_type COMMENT ''Document type (BSART)''
                      )
                      METRICS (
                        purchase_orders.po_count AS COUNT(purchase_orders.PO_KEY) COMMENT ''Number of POs'',
                        vendors.vendor_count AS COUNT(DISTINCT vendors.VENDOR_KEY) COMMENT ''Unique vendors''
                      )
                      COMMENT = ''SAP S/4HANA Procurement Analytics - Purchase Orders (EKKO), Vendors (LFA1)''';
                ELSE
                    RETURN 'ERROR: Unsupported SAP domain: ' || p_semantic_domain;
            END CASE;
            
        -- ═══════════════════════════════════════════════════════════════════════
        -- Salesforce Semantic Views
        -- ═══════════════════════════════════════════════════════════════════════
        WHEN 'SALESFORCE' THEN
            CASE UPPER(p_semantic_domain)
                WHEN 'SALES' THEN
                    v_view_name := 'SF_SALES_ANALYTICS';
                    v_create_sql := '
                    CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.SEM_SALES.' || v_view_name || '
                      TABLES (
                        opportunities AS CURATED_DEV.FACTS.FACT_OPPORTUNITIES_SF PRIMARY KEY (OPPORTUNITY_KEY),
                        accounts AS CURATED_DEV.DIMENSIONS.DIM_CUSTOMER_SF PRIMARY KEY (CUSTOMER_KEY),
                        dates AS CURATED_DEV.DIMENSIONS.DIM_DATE PRIMARY KEY (DATE_KEY)
                      )
                      RELATIONSHIPS (
                        opportunities(CUSTOMER_KEY) REFERENCES accounts(CUSTOMER_KEY),
                        opportunities(CLOSE_DATE) REFERENCES dates(DATE_KEY)
                      )
                      DIMENSIONS (
                        dates.YEAR AS year COMMENT ''Close date year'',
                        dates.QUARTER AS quarter COMMENT ''Close date quarter'',
                        dates.MONTH_NAME AS month COMMENT ''Close date month'',
                        dates.FISCAL_YEAR AS fiscal_year,
                        
                        accounts.CUSTOMER_ID AS account_id COMMENT ''Salesforce Account ID'',
                        accounts.CUSTOMER_NAME AS account_name COMMENT ''Account Name'',
                        accounts.CUSTOMER_TYPE AS account_type COMMENT ''Account Type'',
                        accounts.INDUSTRY AS industry COMMENT ''Industry'',
                        accounts.CUSTOMER_TIER AS customer_tier COMMENT ''Customer value tier'',
                        accounts.BILLING_STATE AS state,
                        accounts.BILLING_COUNTRY AS country,
                        
                        opportunities.OPPORTUNITY_ID AS opportunity_id,
                        opportunities.OPPORTUNITY_NAME AS opportunity_name,
                        opportunities.STAGE_NAME AS stage COMMENT ''Pipeline Stage (StageName)'',
                        opportunities.OPPORTUNITY_TYPE AS type COMMENT ''Opportunity Type'',
                        opportunities.LEAD_SOURCE AS lead_source COMMENT ''Lead Source'',
                        opportunities.FORECAST_CATEGORY AS forecast_category,
                        opportunities.IS_CLOSED AS is_closed,
                        opportunities.IS_WON AS is_won
                      )
                      METRICS (
                        opportunities.total_pipeline AS SUM(opportunities.AMOUNT) COMMENT ''Total pipeline value'',
                        opportunities.avg_deal_size AS AVG(opportunities.AMOUNT) COMMENT ''Average deal size'',
                        opportunities.opportunity_count AS COUNT(opportunities.OPPORTUNITY_KEY) COMMENT ''Number of opportunities'',
                        opportunities.won_deals AS SUM(CASE WHEN opportunities.IS_WON THEN 1 ELSE 0 END) COMMENT ''Won deals'',
                        opportunities.closed_deals AS SUM(CASE WHEN opportunities.IS_CLOSED THEN 1 ELSE 0 END),
                        opportunities.win_rate AS opportunities.won_deals / NULLIF(opportunities.closed_deals, 0) * 100 COMMENT ''Win rate percentage'',
                        accounts.account_count AS COUNT(DISTINCT accounts.CUSTOMER_KEY) COMMENT ''Unique accounts''
                      )
                      COMMENT = ''Salesforce Sales Analytics - Pipeline, Opportunities, Accounts''';
                      
                WHEN 'SERVICE' THEN
                    v_view_name := 'SF_SERVICE_ANALYTICS';
                    v_create_sql := '
                    CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.SEM_OPERATIONS.' || v_view_name || '
                      TABLES (
                        cases AS CURATED_DEV.FACTS.FACT_CASES_SF PRIMARY KEY (CASE_KEY),
                        accounts AS CURATED_DEV.DIMENSIONS.DIM_CUSTOMER_SF PRIMARY KEY (CUSTOMER_KEY),
                        contacts AS CURATED_DEV.DIMENSIONS.DIM_CONTACT_SF PRIMARY KEY (CONTACT_KEY)
                      )
                      RELATIONSHIPS (
                        cases(CUSTOMER_KEY) REFERENCES accounts(CUSTOMER_KEY),
                        cases(CONTACT_KEY) REFERENCES contacts(CONTACT_KEY)
                      )
                      DIMENSIONS (
                        accounts.CUSTOMER_NAME AS account_name,
                        accounts.CUSTOMER_TIER AS customer_tier,
                        
                        contacts.DISPLAY_NAME AS contact_name,
                        
                        cases.CASE_NUMBER AS case_number,
                        cases.STATUS AS status COMMENT ''Case Status'',
                        cases.PRIORITY AS priority COMMENT ''Case Priority'',
                        cases.ORIGIN AS origin COMMENT ''Case Origin'',
                        cases.CASE_TYPE AS case_type,
                        cases.IS_CLOSED AS is_closed
                      )
                      METRICS (
                        cases.case_count AS COUNT(cases.CASE_KEY) COMMENT ''Total cases'',
                        cases.open_cases AS SUM(CASE WHEN NOT cases.IS_CLOSED THEN 1 ELSE 0 END) COMMENT ''Open cases'',
                        cases.closed_cases AS SUM(CASE WHEN cases.IS_CLOSED THEN 1 ELSE 0 END) COMMENT ''Closed cases''
                      )
                      COMMENT = ''Salesforce Service Analytics - Cases, Accounts, Contacts''';
                ELSE
                    RETURN 'ERROR: Unsupported Salesforce domain: ' || p_semantic_domain;
            END CASE;
            
        -- ═══════════════════════════════════════════════════════════════════════
        -- FHIR Semantic Views
        -- ═══════════════════════════════════════════════════════════════════════
        WHEN 'FHIR' THEN
            CASE UPPER(p_semantic_domain)
                WHEN 'CLINICAL' THEN
                    v_view_name := 'FHIR_CLINICAL_ANALYTICS';
                    v_create_sql := '
                    CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.SEM_HEALTHCARE.' || v_view_name || '
                      TABLES (
                        encounters AS CURATED_DEV.FACTS.FACT_ENCOUNTERS_FHIR PRIMARY KEY (ENCOUNTER_KEY),
                        conditions AS CURATED_DEV.FACTS.FACT_CONDITIONS_FHIR PRIMARY KEY (CONDITION_KEY),
                        patients AS CURATED_DEV.DIMENSIONS.DIM_PATIENT_FHIR PRIMARY KEY (PATIENT_KEY)
                      )
                      RELATIONSHIPS (
                        encounters(PATIENT_KEY) REFERENCES patients(PATIENT_KEY),
                        conditions(PATIENT_KEY) REFERENCES patients(PATIENT_KEY),
                        conditions(ENCOUNTER_KEY) REFERENCES encounters(ENCOUNTER_KEY)
                      )
                      DIMENSIONS (
                        patients.PATIENT_ID AS patient_id COMMENT ''FHIR Patient ID'',
                        patients.GENDER AS gender COMMENT ''Patient gender'',
                        patients.CITY AS city,
                        patients.STATE AS state,
                        patients.IS_ACTIVE AS is_active_patient,
                        
                        encounters.ENCOUNTER_ID AS encounter_id,
                        encounters.ENCOUNTER_CLASS AS encounter_class COMMENT ''Class (ambulatory, inpatient, emergency)'',
                        encounters.ENCOUNTER_TYPE AS encounter_type,
                        encounters.STATUS AS encounter_status,
                        
                        conditions.DIAGNOSIS_CODE AS diagnosis_code COMMENT ''ICD-10/SNOMED code'',
                        conditions.DIAGNOSIS_DESCRIPTION AS diagnosis,
                        conditions.CODE_SYSTEM AS code_system,
                        conditions.CLINICAL_STATUS AS clinical_status
                      )
                      METRICS (
                        encounters.encounter_count AS COUNT(encounters.ENCOUNTER_KEY) COMMENT ''Total encounters'',
                        encounters.avg_duration_minutes AS AVG(encounters.DURATION_MINUTES) COMMENT ''Average encounter duration'',
                        conditions.condition_count AS COUNT(conditions.CONDITION_KEY) COMMENT ''Total conditions'',
                        patients.patient_count AS COUNT(DISTINCT patients.PATIENT_KEY) COMMENT ''Unique patients''
                      )
                      COMMENT = ''FHIR R4 Clinical Analytics - Encounters, Conditions, Patients''';
                ELSE
                    RETURN 'ERROR: Unsupported FHIR domain: ' || p_semantic_domain;
            END CASE;
            
        -- ═══════════════════════════════════════════════════════════════════════
        -- Workday Semantic Views
        -- ═══════════════════════════════════════════════════════════════════════
        WHEN 'WORKDAY' THEN
            CASE UPPER(p_semantic_domain)
                WHEN 'HR' THEN
                    v_view_name := 'WD_WORKFORCE_ANALYTICS';
                    v_create_sql := '
                    CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.SEM_HR.' || v_view_name || '
                      TABLES (
                        employees AS CURATED_DEV.DIMENSIONS.DIM_EMPLOYEE_WD PRIMARY KEY (EMPLOYEE_KEY)
                      )
                      DIMENSIONS (
                        employees.EMPLOYEE_ID AS employee_id COMMENT ''Workday Worker ID'',
                        employees.PREFERRED_NAME AS employee_name COMMENT ''Preferred name'',
                        employees.EMPLOYMENT_TYPE AS employment_type,
                        employees.JOB_TITLE AS job_title COMMENT ''Business Title'',
                        employees.JOB_LEVEL AS job_level,
                        employees.DEPARTMENT AS department COMMENT ''Supervisory Organization'',
                        employees.WORK_LOCATION AS location,
                        employees.IS_ACTIVE AS is_active
                      )
                      METRICS (
                        employees.headcount AS COUNT(employees.EMPLOYEE_KEY) COMMENT ''Total headcount'',
                        employees.active_headcount AS COUNT(CASE WHEN employees.IS_ACTIVE THEN employees.EMPLOYEE_KEY END) COMMENT ''Active employees'',
                        employees.avg_tenure AS AVG(employees.TENURE_YEARS) COMMENT ''Average tenure in years''
                      )
                      COMMENT = ''Workday HCM Workforce Analytics - Workers, Organizations''';
                ELSE
                    RETURN 'ERROR: Unsupported Workday domain: ' || p_semantic_domain;
            END CASE;
            
        -- ═══════════════════════════════════════════════════════════════════════
        -- ServiceNow Semantic Views
        -- ═══════════════════════════════════════════════════════════════════════
        WHEN 'SERVICENOW' THEN
            CASE UPPER(p_semantic_domain)
                WHEN 'ITSM' THEN
                    v_view_name := 'SN_ITSM_ANALYTICS';
                    v_create_sql := '
                    CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.SEM_OPERATIONS.' || v_view_name || '
                      TABLES (
                        incidents AS CURATED_DEV.FACTS.FACT_INCIDENTS_SN PRIMARY KEY (INCIDENT_KEY),
                        users AS CURATED_DEV.DIMENSIONS.DIM_USER_SN PRIMARY KEY (USER_KEY)
                      )
                      RELATIONSHIPS (
                        incidents(CALLER_KEY) REFERENCES users(USER_KEY)
                      )
                      DIMENSIONS (
                        users.USERNAME AS username,
                        users.JOB_TITLE AS job_title,
                        users.DEPARTMENT AS department,
                        users.LOCATION AS location,
                        
                        incidents.INCIDENT_NUMBER AS incident_number,
                        incidents.PRIORITY AS priority COMMENT ''Incident priority (1-5)'',
                        incidents.URGENCY AS urgency,
                        incidents.IMPACT AS impact,
                        incidents.STATE AS state,
                        incidents.CATEGORY AS category,
                        incidents.SUBCATEGORY AS subcategory,
                        incidents.ASSIGNMENT_GROUP AS assignment_group
                      )
                      METRICS (
                        incidents.incident_count AS COUNT(incidents.INCIDENT_KEY) COMMENT ''Total incidents'',
                        incidents.avg_resolution_time AS AVG(incidents.TIME_TO_RESOLVE_MINUTES) COMMENT ''Avg resolution time (minutes)'',
                        incidents.p1_incidents AS SUM(CASE WHEN incidents.PRIORITY = ''1'' THEN 1 ELSE 0 END) COMMENT ''Priority 1 incidents'',
                        users.user_count AS COUNT(DISTINCT users.USER_KEY) COMMENT ''Unique users''
                      )
                      COMMENT = ''ServiceNow ITSM Analytics - Incidents, Users''';
                ELSE
                    RETURN 'ERROR: Unsupported ServiceNow domain: ' || p_semantic_domain;
            END CASE;
        ELSE
            RETURN 'ERROR: Unsupported source system: ' || p_source_system;
    END CASE;
    
    EXECUTE IMMEDIATE v_create_sql;
    RETURN 'SUCCESS: Created semantic view ' || v_view_name;
    
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR: ' || SQLERRM;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- BUILD ALL SEMANTIC VIEWS FOR A SOURCE SYSTEM
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE SEM_DEV.SEM_SALES.BUILD_SEMANTIC_LAYER(
    p_source_system VARCHAR
)
RETURNS TABLE (semantic_view VARCHAR, status VARCHAR)
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    result RESULTSET;
BEGIN
    CREATE OR REPLACE TEMPORARY TABLE _sem_results (
        semantic_view VARCHAR,
        status VARCHAR
    );
    
    CASE UPPER(p_source_system)
        WHEN 'SAP' THEN
            CALL SEM_DEV.SEM_SALES.CREATE_SEMANTIC_VIEW_FOR_SOURCE('SAP', 'SALES');
            INSERT INTO _sem_results VALUES ('SAP_SALES_ANALYTICS', 'Created');
            
            CALL SEM_DEV.SEM_SALES.CREATE_SEMANTIC_VIEW_FOR_SOURCE('SAP', 'PROCUREMENT');
            INSERT INTO _sem_results VALUES ('SAP_PROCUREMENT_ANALYTICS', 'Created');
            
        WHEN 'SALESFORCE' THEN
            CALL SEM_DEV.SEM_SALES.CREATE_SEMANTIC_VIEW_FOR_SOURCE('SALESFORCE', 'SALES');
            INSERT INTO _sem_results VALUES ('SF_SALES_ANALYTICS', 'Created');
            
            CALL SEM_DEV.SEM_SALES.CREATE_SEMANTIC_VIEW_FOR_SOURCE('SALESFORCE', 'SERVICE');
            INSERT INTO _sem_results VALUES ('SF_SERVICE_ANALYTICS', 'Created');
            
        WHEN 'FHIR' THEN
            CALL SEM_DEV.SEM_SALES.CREATE_SEMANTIC_VIEW_FOR_SOURCE('FHIR', 'CLINICAL');
            INSERT INTO _sem_results VALUES ('FHIR_CLINICAL_ANALYTICS', 'Created');
            
        WHEN 'WORKDAY' THEN
            CALL SEM_DEV.SEM_SALES.CREATE_SEMANTIC_VIEW_FOR_SOURCE('WORKDAY', 'HR');
            INSERT INTO _sem_results VALUES ('WD_WORKFORCE_ANALYTICS', 'Created');
            
        WHEN 'SERVICENOW' THEN
            CALL SEM_DEV.SEM_SALES.CREATE_SEMANTIC_VIEW_FOR_SOURCE('SERVICENOW', 'ITSM');
            INSERT INTO _sem_results VALUES ('SN_ITSM_ANALYTICS', 'Created');
    END CASE;
    
    result := (SELECT * FROM _sem_results);
    RETURN TABLE(result);
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- ADDITIONAL SCHEMAS FOR DOMAIN-SPECIFIC SEMANTIC VIEWS
-- ═══════════════════════════════════════════════════════════════════════════

CREATE SCHEMA IF NOT EXISTS SEM_DEV.SEM_HEALTHCARE
    COMMENT = 'Healthcare domain semantic views (FHIR, EHR systems)';

-- ═══════════════════════════════════════════════════════════════════════════
-- MARKETPLACE SECURE VIEWS (No PII)
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA SEM_DEV.MARKETPLACE;

-- Generic secure view for sales summaries (works with any source)
CREATE OR REPLACE SECURE VIEW VW_SALES_SUMMARY AS
SELECT
    d.YEAR,
    d.QUARTER,
    d.MONTH_NAME AS MONTH,
    'Multi-Source' AS DATA_SOURCE,
    COUNT(*) AS ORDER_COUNT,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIMESTAMP
FROM CURATED_DEV.DIMENSIONS.DIM_DATE d
WHERE d.YEAR >= YEAR(CURRENT_DATE()) - 2
GROUP BY d.YEAR, d.QUARTER, d.MONTH_NAME
ORDER BY d.YEAR DESC, d.QUARTER DESC;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

GRANT USAGE ON SCHEMA SEM_DEV.SEM_SALES TO ROLE ANALYST;
GRANT USAGE ON SCHEMA SEM_DEV.SEM_CUSTOMER TO ROLE ANALYST;
GRANT USAGE ON SCHEMA SEM_DEV.SEM_HR TO ROLE MANAGER;
GRANT USAGE ON SCHEMA SEM_DEV.SEM_OPERATIONS TO ROLE ANALYST;
GRANT USAGE ON SCHEMA SEM_DEV.SEM_HEALTHCARE TO ROLE ANALYST;
GRANT USAGE ON SCHEMA SEM_DEV.MARKETPLACE TO ROLE VIEWER;

GRANT SELECT ON ALL VIEWS IN SCHEMA SEM_DEV.MARKETPLACE TO ROLE VIEWER;
GRANT SELECT ON ALL VIEWS IN SCHEMA SEM_DEV.MARKETPLACE TO ROLE EXTERNAL_PARTNER;

GRANT USAGE ON PROCEDURE SEM_DEV.SEM_SALES.CREATE_SEMANTIC_VIEW_FOR_SOURCE(VARCHAR, VARCHAR) TO ROLE DATA_ENGINEER;
GRANT USAGE ON PROCEDURE SEM_DEV.SEM_SALES.BUILD_SEMANTIC_LAYER(VARCHAR) TO ROLE DATA_ENGINEER;

-- ═══════════════════════════════════════════════════════════════════════════
-- USAGE INSTRUCTIONS
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- OPTION 1: Build all semantic views for a source system
--   CALL SEM_DEV.SEM_SALES.BUILD_SEMANTIC_LAYER('SAP');
--   CALL SEM_DEV.SEM_SALES.BUILD_SEMANTIC_LAYER('SALESFORCE');
--   CALL SEM_DEV.SEM_SALES.BUILD_SEMANTIC_LAYER('FHIR');
--
-- OPTION 2: Create specific semantic view
--   CALL SEM_DEV.SEM_SALES.CREATE_SEMANTIC_VIEW_FOR_SOURCE('SAP', 'SALES');
--   CALL SEM_DEV.SEM_SALES.CREATE_SEMANTIC_VIEW_FOR_SOURCE('SALESFORCE', 'SERVICE');
--
-- VERIFY:
--   SHOW SEMANTIC VIEWS IN DATABASE SEM_DEV;
--
-- USE WITH CORTEX ANALYST:
--   SELECT SNOWFLAKE.CORTEX.COMPLETE('claude-3-5-sonnet', 
--     'Using semantic view SAP_SALES_ANALYTICS, what were total sales by region last quarter?');
--
-- ═══════════════════════════════════════════════════════════════════════════

SELECT '✓ Semantic Layer Dynamic Infrastructure Created' AS STATUS;
SELECT '  Use BUILD_SEMANTIC_LAYER(''SAP'') to create semantic views for a source system' AS INFO;
