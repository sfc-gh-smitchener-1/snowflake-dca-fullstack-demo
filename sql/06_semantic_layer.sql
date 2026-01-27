-- ============================================================================
-- SEMANTIC LAYER - Native Semantic Views by Source System
-- ============================================================================
-- 
-- Schema Structure (one schema per source system):
--   SEM_DEV.SAP         - SAP semantic views
--   SEM_DEV.SALESFORCE  - Salesforce semantic views
--   SEM_DEV.FHIR        - FHIR semantic views
--   SEM_DEV.WORKDAY     - Workday semantic views
--   SEM_DEV.SERVICENOW  - ServiceNow semantic views
--   SEM_DEV.MARKETPLACE - Cross-system aggregated views for sharing
--
-- Semantic Views are the Gold layer - optimized for Cortex Analyst
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE SEM_DEV;
USE WAREHOUSE ANALYTICS_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- CREATE SOURCE SYSTEM SCHEMAS
-- ═══════════════════════════════════════════════════════════════════════════

CREATE SCHEMA IF NOT EXISTS SEM_DEV.SAP
    COMMENT = 'SAP S/4HANA semantic views for Cortex Analyst';

CREATE SCHEMA IF NOT EXISTS SEM_DEV.SALESFORCE
    COMMENT = 'Salesforce CRM semantic views for Cortex Analyst';

CREATE SCHEMA IF NOT EXISTS SEM_DEV.FHIR
    COMMENT = 'FHIR R4 healthcare semantic views for Cortex Analyst';

CREATE SCHEMA IF NOT EXISTS SEM_DEV.WORKDAY
    COMMENT = 'Workday HCM semantic views for Cortex Analyst';

CREATE SCHEMA IF NOT EXISTS SEM_DEV.SERVICENOW
    COMMENT = 'ServiceNow ITSM semantic views for Cortex Analyst';

CREATE SCHEMA IF NOT EXISTS SEM_DEV.MARKETPLACE
    COMMENT = 'Cross-system aggregated views for data sharing';

-- ═══════════════════════════════════════════════════════════════════════════
-- BUILD PROCEDURE: Creates all semantic views for a source system
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE SEM_DEV.MARKETPLACE.BUILD_SEMANTIC_LAYER(
    P_SOURCE_SYSTEM VARCHAR
)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var results = [];
    var sourceSystem = P_SOURCE_SYSTEM.toUpperCase();
    var semSchema = 'SEM_DEV.' + sourceSystem;
    var curSchema = 'CURATED_DEV.' + sourceSystem;
    
    function createSemanticView(viewName, createSql) {
        try {
            snowflake.createStatement({sqlText: createSql}).execute();
            results.push({view: viewName, status: 'SUCCESS'});
        } catch (err) {
            results.push({view: viewName, status: 'ERROR', message: err.message});
        }
    }
    
    try {
        switch (sourceSystem) {
            // ═══════════════════════════════════════════════════════════════
            // SAP S/4HANA Semantic Views
            // ═══════════════════════════════════════════════════════════════
            case 'SAP':
                // Sales Analytics
                createSemanticView('SALES_ANALYTICS', `
                    CREATE OR REPLACE SEMANTIC VIEW ${semSchema}.SALES_ANALYTICS
                      TABLES (
                        orders AS ${curSchema}.FACT_SALES_ORDERS PRIMARY KEY (ORDER_KEY),
                        customers AS ${curSchema}.DIM_CUSTOMER PRIMARY KEY (CUSTOMER_KEY),
                        products AS ${curSchema}.DIM_PRODUCT PRIMARY KEY (PRODUCT_KEY),
                        dates AS CURATED_DEV.SHARED.DIM_DATE PRIMARY KEY (DATE_KEY)
                      )
                      RELATIONSHIPS (
                        orders(CUSTOMER_KEY) REFERENCES customers(CUSTOMER_KEY),
                        orders(ORDER_DATE) REFERENCES dates(DATE_KEY)
                      )
                      DIMENSIONS (
                        dates.YEAR AS year COMMENT 'Calendar year',
                        dates.QUARTER AS quarter COMMENT 'Quarter (1-4)',
                        dates.MONTH_NAME AS month COMMENT 'Month name',
                        dates.FISCAL_YEAR AS fiscal_year COMMENT 'Fiscal year',
                        
                        customers.CUSTOMER_ID AS customer_id COMMENT 'SAP Customer Number (KUNNR)',
                        customers.CUSTOMER_NAME AS customer_name COMMENT 'Customer name',
                        customers.CITY AS city,
                        customers.COUNTRY AS country,
                        customers.INDUSTRY_CODE AS industry COMMENT 'Industry sector',
                        customers.IS_ACTIVE AS is_active_customer,
                        
                        orders.ORDER_NUMBER AS order_number COMMENT 'Sales document (VBELN)',
                        orders.SALES_ORG AS sales_organization,
                        orders.DISTRIBUTION_CHANNEL AS channel,
                        orders.ORDER_TYPE AS order_type,
                        orders.ORDER_STATUS AS status,
                        orders.IS_COMPLETED AS is_completed
                      )
                      METRICS (
                        orders.total_revenue AS SUM(orders.NET_VALUE) COMMENT 'Total net value',
                        orders.avg_order_value AS AVG(orders.NET_VALUE) COMMENT 'Average order value',
                        orders.order_count AS COUNT(orders.ORDER_KEY) COMMENT 'Number of orders',
                        orders.completed_orders AS SUM(CASE WHEN orders.IS_COMPLETED THEN 1 ELSE 0 END),
                        customers.customer_count AS COUNT(DISTINCT customers.CUSTOMER_KEY)
                      )
                      COMMENT = 'SAP Sales Analytics - Orders, Customers, Products'
                `);
                
                // Procurement Analytics
                createSemanticView('PROCUREMENT_ANALYTICS', `
                    CREATE OR REPLACE SEMANTIC VIEW ${semSchema}.PROCUREMENT_ANALYTICS
                      TABLES (
                        purchase_orders AS ${curSchema}.FACT_PURCHASE_ORDERS PRIMARY KEY (PO_KEY),
                        vendors AS ${curSchema}.DIM_VENDOR PRIMARY KEY (VENDOR_KEY),
                        dates AS CURATED_DEV.SHARED.DIM_DATE PRIMARY KEY (DATE_KEY)
                      )
                      RELATIONSHIPS (
                        purchase_orders(VENDOR_KEY) REFERENCES vendors(VENDOR_KEY),
                        purchase_orders(PO_DATE) REFERENCES dates(DATE_KEY)
                      )
                      DIMENSIONS (
                        dates.YEAR AS year,
                        dates.QUARTER AS quarter,
                        dates.MONTH_NAME AS month,
                        
                        vendors.VENDOR_ID AS vendor_id COMMENT 'Vendor number (LIFNR)',
                        vendors.VENDOR_NAME AS vendor_name,
                        vendors.COUNTRY AS vendor_country,
                        vendors.IS_ACTIVE AS is_active_vendor,
                        
                        purchase_orders.PO_NUMBER AS po_number COMMENT 'Purchase order (EBELN)',
                        purchase_orders.PURCHASING_ORG AS purchasing_org,
                        purchase_orders.PO_TYPE AS po_type
                      )
                      METRICS (
                        purchase_orders.po_count AS COUNT(purchase_orders.PO_KEY) COMMENT 'Number of POs',
                        vendors.vendor_count AS COUNT(DISTINCT vendors.VENDOR_KEY) COMMENT 'Unique vendors'
                      )
                      COMMENT = 'SAP Procurement Analytics - Purchase Orders, Vendors'
                `);
                break;
                
            // ═══════════════════════════════════════════════════════════════
            // SALESFORCE Semantic Views
            // ═══════════════════════════════════════════════════════════════
            case 'SALESFORCE':
                // Pipeline Analytics
                createSemanticView('PIPELINE_ANALYTICS', `
                    CREATE OR REPLACE SEMANTIC VIEW ${semSchema}.PIPELINE_ANALYTICS
                      TABLES (
                        opportunities AS ${curSchema}.FACT_OPPORTUNITIES PRIMARY KEY (OPPORTUNITY_KEY),
                        accounts AS ${curSchema}.DIM_ACCOUNT PRIMARY KEY (ACCOUNT_KEY),
                        dates AS CURATED_DEV.SHARED.DIM_DATE PRIMARY KEY (DATE_KEY)
                      )
                      RELATIONSHIPS (
                        opportunities(ACCOUNT_KEY) REFERENCES accounts(ACCOUNT_KEY),
                        opportunities(CLOSE_DATE) REFERENCES dates(DATE_KEY)
                      )
                      DIMENSIONS (
                        dates.YEAR AS year COMMENT 'Close date year',
                        dates.QUARTER AS quarter COMMENT 'Close date quarter',
                        dates.MONTH_NAME AS month,
                        dates.FISCAL_YEAR AS fiscal_year,
                        
                        accounts.ACCOUNT_ID AS account_id,
                        accounts.ACCOUNT_NAME AS account_name,
                        accounts.ACCOUNT_TYPE AS account_type,
                        accounts.INDUSTRY AS industry,
                        accounts.ACCOUNT_TIER AS account_tier COMMENT 'Customer value tier',
                        accounts.BILLING_STATE AS state,
                        accounts.BILLING_COUNTRY AS country,
                        
                        opportunities.OPPORTUNITY_ID AS opportunity_id,
                        opportunities.OPPORTUNITY_NAME AS opportunity_name,
                        opportunities.STAGE_NAME AS stage COMMENT 'Pipeline Stage',
                        opportunities.OPPORTUNITY_TYPE AS type,
                        opportunities.LEAD_SOURCE AS lead_source,
                        opportunities.FORECAST_CATEGORY AS forecast_category,
                        opportunities.IS_CLOSED AS is_closed,
                        opportunities.IS_WON AS is_won
                      )
                      METRICS (
                        opportunities.total_pipeline AS SUM(opportunities.AMOUNT) COMMENT 'Total pipeline value',
                        opportunities.avg_deal_size AS AVG(opportunities.AMOUNT) COMMENT 'Average deal size',
                        opportunities.opportunity_count AS COUNT(opportunities.OPPORTUNITY_KEY),
                        opportunities.won_deals AS SUM(CASE WHEN opportunities.IS_WON THEN 1 ELSE 0 END),
                        opportunities.closed_deals AS SUM(CASE WHEN opportunities.IS_CLOSED THEN 1 ELSE 0 END),
                        opportunities.win_rate AS opportunities.won_deals / NULLIF(opportunities.closed_deals, 0) * 100 COMMENT 'Win rate %',
                        accounts.account_count AS COUNT(DISTINCT accounts.ACCOUNT_KEY)
                      )
                      COMMENT = 'Salesforce Pipeline Analytics - Opportunities, Accounts'
                `);
                break;
                
            // ═══════════════════════════════════════════════════════════════
            // FHIR Semantic Views
            // ═══════════════════════════════════════════════════════════════
            case 'FHIR':
                // Clinical Analytics
                createSemanticView('CLINICAL_ANALYTICS', `
                    CREATE OR REPLACE SEMANTIC VIEW ${semSchema}.CLINICAL_ANALYTICS
                      TABLES (
                        encounters AS ${curSchema}.FACT_ENCOUNTERS PRIMARY KEY (ENCOUNTER_KEY),
                        patients AS ${curSchema}.DIM_PATIENT PRIMARY KEY (PATIENT_KEY)
                      )
                      RELATIONSHIPS (
                        encounters(PATIENT_KEY) REFERENCES patients(PATIENT_KEY)
                      )
                      DIMENSIONS (
                        patients.PATIENT_ID AS patient_id COMMENT 'FHIR Patient ID',
                        patients.GENDER AS gender,
                        patients.CITY AS city,
                        patients.STATE AS state,
                        patients.IS_ACTIVE AS is_active_patient,
                        
                        encounters.ENCOUNTER_ID AS encounter_id,
                        encounters.ENCOUNTER_CLASS AS encounter_class COMMENT 'ambulatory, inpatient, emergency',
                        encounters.ENCOUNTER_TYPE AS encounter_type,
                        encounters.STATUS AS encounter_status
                      )
                      METRICS (
                        encounters.encounter_count AS COUNT(encounters.ENCOUNTER_KEY) COMMENT 'Total encounters',
                        encounters.avg_duration_minutes AS AVG(encounters.DURATION_MINUTES) COMMENT 'Avg duration (min)',
                        patients.patient_count AS COUNT(DISTINCT patients.PATIENT_KEY) COMMENT 'Unique patients'
                      )
                      COMMENT = 'FHIR Clinical Analytics - Encounters, Patients'
                `);
                break;
                
            // ═══════════════════════════════════════════════════════════════
            // WORKDAY Semantic Views
            // ═══════════════════════════════════════════════════════════════
            case 'WORKDAY':
                // Workforce Analytics
                createSemanticView('WORKFORCE_ANALYTICS', `
                    CREATE OR REPLACE SEMANTIC VIEW ${semSchema}.WORKFORCE_ANALYTICS
                      TABLES (
                        employees AS ${curSchema}.DIM_EMPLOYEE PRIMARY KEY (EMPLOYEE_KEY)
                      )
                      DIMENSIONS (
                        employees.EMPLOYEE_ID AS employee_id COMMENT 'Workday Worker ID',
                        employees.PREFERRED_NAME AS employee_name,
                        employees.EMPLOYMENT_TYPE AS employment_type,
                        employees.JOB_TITLE AS job_title,
                        employees.JOB_LEVEL AS job_level,
                        employees.DEPARTMENT AS department,
                        employees.WORK_LOCATION AS location,
                        employees.IS_ACTIVE AS is_active
                      )
                      METRICS (
                        employees.headcount AS COUNT(employees.EMPLOYEE_KEY) COMMENT 'Total headcount',
                        employees.active_headcount AS COUNT(CASE WHEN employees.IS_ACTIVE THEN employees.EMPLOYEE_KEY END),
                        employees.avg_tenure AS AVG(employees.TENURE_YEARS) COMMENT 'Avg tenure (years)'
                      )
                      COMMENT = 'Workday Workforce Analytics - Employees'
                `);
                break;
                
            // ═══════════════════════════════════════════════════════════════
            // SERVICENOW Semantic Views
            // ═══════════════════════════════════════════════════════════════
            case 'SERVICENOW':
                // ITSM Analytics
                createSemanticView('ITSM_ANALYTICS', `
                    CREATE OR REPLACE SEMANTIC VIEW ${semSchema}.ITSM_ANALYTICS
                      TABLES (
                        incidents AS ${curSchema}.FACT_INCIDENTS PRIMARY KEY (INCIDENT_KEY),
                        users AS ${curSchema}.DIM_USER PRIMARY KEY (USER_KEY)
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
                        incidents.PRIORITY AS priority COMMENT 'Priority (1-5)',
                        incidents.URGENCY AS urgency,
                        incidents.IMPACT AS impact,
                        incidents.STATE AS state,
                        incidents.CATEGORY AS category,
                        incidents.SUBCATEGORY AS subcategory,
                        incidents.ASSIGNMENT_GROUP AS assignment_group
                      )
                      METRICS (
                        incidents.incident_count AS COUNT(incidents.INCIDENT_KEY) COMMENT 'Total incidents',
                        incidents.avg_resolution_time AS AVG(incidents.TIME_TO_RESOLVE_MINUTES) COMMENT 'Avg resolution (min)',
                        incidents.p1_incidents AS SUM(CASE WHEN incidents.PRIORITY = '1' THEN 1 ELSE 0 END),
                        users.user_count AS COUNT(DISTINCT users.USER_KEY)
                      )
                      COMMENT = 'ServiceNow ITSM Analytics - Incidents, Users'
                `);
                break;
                
            default:
                return {status: 'ERROR', message: 'Unsupported source system: ' + sourceSystem};
        }
        
        var successCount = results.filter(function(r) { return r.status === 'SUCCESS'; }).length;
        var errorCount = results.filter(function(r) { return r.status === 'ERROR'; }).length;
        
        return {
            status: errorCount === 0 ? 'SUCCESS' : 'PARTIAL',
            source_system: sourceSystem,
            target_schema: semSchema,
            views_created: successCount,
            views_failed: errorCount,
            details: results
        };
        
    } catch (err) {
        return {status: 'ERROR', message: err.message};
    }
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- MARKETPLACE: Aggregated views for data sharing (no PII)
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA SEM_DEV.MARKETPLACE;

-- Cross-system date summary
CREATE OR REPLACE SECURE VIEW VW_DATE_SUMMARY AS
SELECT
    YEAR,
    QUARTER,
    MONTH_NAME AS MONTH,
    COUNT(*) AS DAYS_IN_PERIOD,
    SUM(CASE WHEN IS_WEEKEND THEN 1 ELSE 0 END) AS WEEKEND_DAYS,
    SUM(CASE WHEN NOT IS_WEEKEND THEN 1 ELSE 0 END) AS BUSINESS_DAYS
FROM CURATED_DEV.SHARED.DIM_DATE
WHERE YEAR >= YEAR(CURRENT_DATE()) - 2
GROUP BY YEAR, QUARTER, MONTH_NAME
ORDER BY YEAR DESC, QUARTER DESC;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

-- Grant schema usage
GRANT USAGE ON SCHEMA SEM_DEV.SAP TO ROLE ANALYST;
GRANT USAGE ON SCHEMA SEM_DEV.SALESFORCE TO ROLE ANALYST;
GRANT USAGE ON SCHEMA SEM_DEV.FHIR TO ROLE ANALYST;
GRANT USAGE ON SCHEMA SEM_DEV.WORKDAY TO ROLE MANAGER;
GRANT USAGE ON SCHEMA SEM_DEV.SERVICENOW TO ROLE ANALYST;
GRANT USAGE ON SCHEMA SEM_DEV.MARKETPLACE TO ROLE VIEWER;

-- Grant select on marketplace views
GRANT SELECT ON ALL VIEWS IN SCHEMA SEM_DEV.MARKETPLACE TO ROLE VIEWER;
GRANT SELECT ON ALL VIEWS IN SCHEMA SEM_DEV.MARKETPLACE TO ROLE EXTERNAL_PARTNER;

-- Grant procedure usage
GRANT USAGE ON PROCEDURE SEM_DEV.MARKETPLACE.BUILD_SEMANTIC_LAYER(VARCHAR) TO ROLE DATA_ENGINEER;

-- Future grants
GRANT SELECT ON FUTURE VIEWS IN SCHEMA SEM_DEV.MARKETPLACE TO ROLE VIEWER;

-- ═══════════════════════════════════════════════════════════════════════════
-- USAGE INSTRUCTIONS
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Build semantic layer for a source system:
--   CALL SEM_DEV.MARKETPLACE.BUILD_SEMANTIC_LAYER('SAP');
--   CALL SEM_DEV.MARKETPLACE.BUILD_SEMANTIC_LAYER('SALESFORCE');
--   CALL SEM_DEV.MARKETPLACE.BUILD_SEMANTIC_LAYER('FHIR');
--   CALL SEM_DEV.MARKETPLACE.BUILD_SEMANTIC_LAYER('WORKDAY');
--   CALL SEM_DEV.MARKETPLACE.BUILD_SEMANTIC_LAYER('SERVICENOW');
--
-- Verify:
--   SHOW SEMANTIC VIEWS IN SCHEMA SEM_DEV.SAP;
--
-- Use with Cortex Analyst:
--   SELECT SNOWFLAKE.CORTEX.COMPLETE('claude-3-5-sonnet', 
--     'Using SEM_DEV.SAP.SALES_ANALYTICS, what were total sales by region?');
--
-- ═══════════════════════════════════════════════════════════════════════════

SELECT '06_semantic_layer.sql completed successfully' AS STATUS;
