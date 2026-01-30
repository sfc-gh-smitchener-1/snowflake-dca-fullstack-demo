-- ============================================================================
-- DATA MARKETPLACE - Domain-Specific Data Products with RBAC
-- ============================================================================
-- 
-- This script creates a comprehensive internal data marketplace with:
--   1. Domain-specific consumer roles for access control
--   2. Rich data product listings with descriptions and sample queries
--   3. Secure views ensuring no PII exposure
--   4. Self-service discovery via catalog
--
-- Domain Roles:
--   - ERP_CONSUMER: SAP and Oracle ERP data access
--   - CRM_CONSUMER: Salesforce CRM data access
--   - HEALTHCARE_CONSUMER: FHIR healthcare data access
--   - WORKFORCE_CONSUMER: Workday HR data access
--   - ITSM_CONSUMER: ServiceNow IT data access
--   - MARKETPLACE_CONSUMER: General access to all non-sensitive products
--
-- RUN AS: ACCOUNTADMIN (for role creation), then DATA_ADMIN
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 1: CREATE DOMAIN-SPECIFIC CONSUMER ROLES
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;

-- -----------------------------------------------------------------------------
-- ERP Consumer Role - SAP and Oracle Enterprise Resource Planning
-- -----------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS ERP_CONSUMER
    COMMENT = 'Enterprise Resource Planning data consumer. Access to SAP and Oracle ERP data products including sales orders, purchase orders, inventory, and financial transactions. Ideal for supply chain analysts, procurement teams, and finance operations.';

-- -----------------------------------------------------------------------------
-- CRM Consumer Role - Salesforce Customer Relationship Management
-- -----------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS CRM_CONSUMER
    COMMENT = 'Customer Relationship Management data consumer. Access to Salesforce data products including opportunities, leads, accounts, contacts, and service cases. Ideal for sales operations, marketing analytics, and customer success teams.';

-- -----------------------------------------------------------------------------
-- Healthcare Consumer Role - FHIR Clinical Data
-- -----------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS HEALTHCARE_CONSUMER
    COMMENT = 'Healthcare analytics data consumer. Access to FHIR-based clinical data products including patient demographics (de-identified), encounters, conditions, and procedures. HIPAA-compliant aggregated views only. Ideal for population health analysts, clinical operations, and quality improvement teams.';

-- -----------------------------------------------------------------------------
-- Workforce Consumer Role - Workday Human Capital Management
-- -----------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS WORKFORCE_CONSUMER
    COMMENT = 'Workforce analytics data consumer. Access to Workday HR data products including headcount, tenure, compensation bands (aggregated), and organizational structure. No individual employee PII. Ideal for HR business partners, workforce planning, and organizational development.';

-- -----------------------------------------------------------------------------
-- ITSM Consumer Role - ServiceNow IT Service Management
-- -----------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS ITSM_CONSUMER
    COMMENT = 'IT Service Management data consumer. Access to ServiceNow data products including incident metrics, change management, problem trends, and SLA performance. Ideal for IT operations, service desk managers, and IT leadership.';

-- -----------------------------------------------------------------------------
-- General Marketplace Consumer Role - Cross-Domain Access
-- -----------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS MARKETPLACE_CONSUMER
    COMMENT = 'General marketplace consumer with access to curated, non-sensitive data products across all domains. Provides a unified view of organizational metrics for executives, data scientists, and cross-functional teams.';

-- -----------------------------------------------------------------------------
-- Role Hierarchy and Grants
-- -----------------------------------------------------------------------------

-- All domain roles report to DATA_STEWARD
GRANT ROLE ERP_CONSUMER TO ROLE DATA_STEWARD;
GRANT ROLE CRM_CONSUMER TO ROLE DATA_STEWARD;
GRANT ROLE HEALTHCARE_CONSUMER TO ROLE DATA_STEWARD;
GRANT ROLE WORKFORCE_CONSUMER TO ROLE DATA_STEWARD;
GRANT ROLE ITSM_CONSUMER TO ROLE DATA_STEWARD;
GRANT ROLE MARKETPLACE_CONSUMER TO ROLE DATA_STEWARD;

-- DATA_ADMIN has access to all marketplace roles
GRANT ROLE ERP_CONSUMER TO ROLE DATA_ADMIN;
GRANT ROLE CRM_CONSUMER TO ROLE DATA_ADMIN;
GRANT ROLE HEALTHCARE_CONSUMER TO ROLE DATA_ADMIN;
GRANT ROLE WORKFORCE_CONSUMER TO ROLE DATA_ADMIN;
GRANT ROLE ITSM_CONSUMER TO ROLE DATA_ADMIN;
GRANT ROLE MARKETPLACE_CONSUMER TO ROLE DATA_ADMIN;

-- Grant all marketplace roles to steve for demo purposes
GRANT ROLE ERP_CONSUMER TO USER STEVE;
GRANT ROLE CRM_CONSUMER TO USER STEVE;
GRANT ROLE HEALTHCARE_CONSUMER TO USER STEVE;
GRANT ROLE WORKFORCE_CONSUMER TO USER STEVE;
GRANT ROLE ITSM_CONSUMER TO USER STEVE;
GRANT ROLE MARKETPLACE_CONSUMER TO USER STEVE;

-- Grant warehouse access to all consumer roles
GRANT USAGE ON WAREHOUSE ANALYTICS_WH TO ROLE ERP_CONSUMER;
GRANT USAGE ON WAREHOUSE ANALYTICS_WH TO ROLE CRM_CONSUMER;
GRANT USAGE ON WAREHOUSE ANALYTICS_WH TO ROLE HEALTHCARE_CONSUMER;
GRANT USAGE ON WAREHOUSE ANALYTICS_WH TO ROLE WORKFORCE_CONSUMER;
GRANT USAGE ON WAREHOUSE ANALYTICS_WH TO ROLE ITSM_CONSUMER;
GRANT USAGE ON WAREHOUSE ANALYTICS_WH TO ROLE MARKETPLACE_CONSUMER;

-- Grant database access
GRANT USAGE ON DATABASE SEM_DEV TO ROLE ERP_CONSUMER;
GRANT USAGE ON DATABASE SEM_DEV TO ROLE CRM_CONSUMER;
GRANT USAGE ON DATABASE SEM_DEV TO ROLE HEALTHCARE_CONSUMER;
GRANT USAGE ON DATABASE SEM_DEV TO ROLE WORKFORCE_CONSUMER;
GRANT USAGE ON DATABASE SEM_DEV TO ROLE ITSM_CONSUMER;
GRANT USAGE ON DATABASE SEM_DEV TO ROLE MARKETPLACE_CONSUMER;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 2: SET UP MARKETPLACE SCHEMA AND CATALOG
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE DATA_ADMIN;
USE WAREHOUSE ANALYTICS_WH;
USE DATABASE SEM_DEV;

-- Create marketplace schema if not exists
CREATE SCHEMA IF NOT EXISTS SEM_DEV.MARKETPLACE
    COMMENT = 'Internal data marketplace with domain-specific data products';

-- Grant schema access to all consumer roles
GRANT USAGE ON SCHEMA SEM_DEV.MARKETPLACE TO ROLE ERP_CONSUMER;
GRANT USAGE ON SCHEMA SEM_DEV.MARKETPLACE TO ROLE CRM_CONSUMER;
GRANT USAGE ON SCHEMA SEM_DEV.MARKETPLACE TO ROLE HEALTHCARE_CONSUMER;
GRANT USAGE ON SCHEMA SEM_DEV.MARKETPLACE TO ROLE WORKFORCE_CONSUMER;
GRANT USAGE ON SCHEMA SEM_DEV.MARKETPLACE TO ROLE ITSM_CONSUMER;
GRANT USAGE ON SCHEMA SEM_DEV.MARKETPLACE TO ROLE MARKETPLACE_CONSUMER;

USE SCHEMA SEM_DEV.MARKETPLACE;

-- ═══════════════════════════════════════════════════════════════════════════
-- DATA PRODUCT CATALOG - Enhanced with Sample Queries
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA GOVERNANCE.OBSERVABILITY;

CREATE OR REPLACE TABLE DATA_PRODUCT_CATALOG (
    PRODUCT_ID              VARCHAR(50) PRIMARY KEY,
    PRODUCT_NAME            VARCHAR(255) NOT NULL,
    PRODUCT_DESCRIPTION     VARCHAR(4000),
    BUSINESS_VALUE          VARCHAR(2000),
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
    COMPLIANCE_NOTES        VARCHAR(1000),
    
    -- Access Control
    CONSUMER_ROLE           VARCHAR(100),
    ALLOWED_ROLES           ARRAY,
    
    -- Sample Queries (for discoverability)
    SAMPLE_QUERY_1          VARCHAR(2000),
    SAMPLE_QUERY_1_DESC     VARCHAR(500),
    SAMPLE_QUERY_2          VARCHAR(2000),
    SAMPLE_QUERY_2_DESC     VARCHAR(500),
    SAMPLE_QUERY_3          VARCHAR(2000),
    SAMPLE_QUERY_3_DESC     VARCHAR(500),
    SAMPLE_QUERY_4          VARCHAR(2000),
    SAMPLE_QUERY_4_DESC     VARCHAR(500),
    SAMPLE_QUERY_5          VARCHAR(2000),
    SAMPLE_QUERY_5_DESC     VARCHAR(500),
    
    -- Metadata
    OWNER_TEAM              VARCHAR(100),
    DATA_STEWARD_EMAIL      VARCHAR(255),
    SLA_REFRESH_HOURS       NUMBER,
    USE_CASES               ARRAY,
    TAGS                    ARRAY,
    
    -- Status
    STATUS                  VARCHAR(20) DEFAULT 'ACTIVE',
    CREATED_AT              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 3: SAP ERP DATA PRODUCTS
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA SEM_DEV.MARKETPLACE;

-- -----------------------------------------------------------------------------
-- SAP Sales Analytics
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SECURE VIEW DP_SAP_SALES_ANALYTICS AS
SELECT
    SALES_ORG AS SALES_ORGANIZATION,
    DISTRIBUTION_CHANNEL,
    DIVISION,
    EXTRACT(YEAR FROM ORDER_DATE) AS ORDER_YEAR,
    EXTRACT(QUARTER FROM ORDER_DATE) AS ORDER_QUARTER,
    EXTRACT(MONTH FROM ORDER_DATE) AS ORDER_MONTH,
    COUNT(*) AS ORDER_COUNT,
    COUNT(DISTINCT CUSTOMER_KEY) AS UNIQUE_CUSTOMERS,
    SUM(NET_VALUE) AS TOTAL_REVENUE,
    AVG(NET_VALUE) AS AVG_ORDER_VALUE,
    MIN(NET_VALUE) AS MIN_ORDER_VALUE,
    MAX(NET_VALUE) AS MAX_ORDER_VALUE,
    SUM(QUANTITY) AS TOTAL_UNITS_SOLD,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.SAP.FACT_SALES_ORDERS
GROUP BY SALES_ORG, DISTRIBUTION_CHANNEL, DIVISION,
         EXTRACT(YEAR FROM ORDER_DATE), EXTRACT(QUARTER FROM ORDER_DATE), EXTRACT(MONTH FROM ORDER_DATE)
ORDER BY ORDER_YEAR DESC, ORDER_QUARTER DESC, ORDER_MONTH DESC;

COMMENT ON VIEW DP_SAP_SALES_ANALYTICS IS 'SAP Sales Analytics: Aggregated sales order metrics by organization, channel, and time period. Use for revenue analysis, sales performance tracking, and demand forecasting. Updated every 4 hours.';

-- Grant to ERP consumers only
GRANT SELECT ON VIEW DP_SAP_SALES_ANALYTICS TO ROLE ERP_CONSUMER;
GRANT SELECT ON VIEW DP_SAP_SALES_ANALYTICS TO ROLE MARKETPLACE_CONSUMER;

-- -----------------------------------------------------------------------------
-- SAP Procurement Analytics
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SECURE VIEW DP_SAP_PROCUREMENT_ANALYTICS AS
SELECT
    PURCHASING_ORG AS PURCHASING_ORGANIZATION,
    PURCHASING_GROUP,
    VENDOR_KEY,
    EXTRACT(YEAR FROM PO_DATE) AS PO_YEAR,
    EXTRACT(QUARTER FROM PO_DATE) AS PO_QUARTER,
    EXTRACT(MONTH FROM PO_DATE) AS PO_MONTH,
    COUNT(*) AS PO_COUNT,
    COUNT(DISTINCT MATERIAL_KEY) AS UNIQUE_MATERIALS,
    SUM(NET_PRICE * QUANTITY) AS TOTAL_SPEND,
    AVG(NET_PRICE) AS AVG_UNIT_PRICE,
    SUM(QUANTITY) AS TOTAL_UNITS_ORDERED,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.SAP.FACT_PURCHASE_ORDERS
GROUP BY PURCHASING_ORG, PURCHASING_GROUP, VENDOR_KEY,
         EXTRACT(YEAR FROM PO_DATE), EXTRACT(QUARTER FROM PO_DATE), EXTRACT(MONTH FROM PO_DATE)
ORDER BY PO_YEAR DESC, PO_QUARTER DESC, PO_MONTH DESC;

COMMENT ON VIEW DP_SAP_PROCUREMENT_ANALYTICS IS 'SAP Procurement Analytics: Purchase order metrics by organization, group, and vendor. Use for spend analysis, vendor performance, and procurement optimization. Updated every 4 hours.';

GRANT SELECT ON VIEW DP_SAP_PROCUREMENT_ANALYTICS TO ROLE ERP_CONSUMER;
GRANT SELECT ON VIEW DP_SAP_PROCUREMENT_ANALYTICS TO ROLE MARKETPLACE_CONSUMER;

-- -----------------------------------------------------------------------------
-- SAP Customer Summary
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SECURE VIEW DP_SAP_CUSTOMER_SUMMARY AS
SELECT
    COUNTRY,
    REGION,
    INDUSTRY_CODE AS INDUSTRY,
    CUSTOMER_CLASS,
    ACCOUNT_GROUP,
    COUNT(*) AS CUSTOMER_COUNT,
    SUM(CASE WHEN IS_ACTIVE THEN 1 ELSE 0 END) AS ACTIVE_CUSTOMERS,
    SUM(CASE WHEN NOT IS_ACTIVE THEN 1 ELSE 0 END) AS INACTIVE_CUSTOMERS,
    ROUND(100.0 * SUM(CASE WHEN IS_ACTIVE THEN 1 ELSE 0 END) / COUNT(*), 2) AS ACTIVE_RATE_PCT,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.SAP.DIM_CUSTOMER
GROUP BY COUNTRY, REGION, INDUSTRY_CODE, CUSTOMER_CLASS, ACCOUNT_GROUP
ORDER BY CUSTOMER_COUNT DESC;

COMMENT ON VIEW DP_SAP_CUSTOMER_SUMMARY IS 'SAP Customer Summary: Customer counts by geography, industry, and classification. Use for market segmentation, territory planning, and customer base analysis. Updated every 24 hours.';

GRANT SELECT ON VIEW DP_SAP_CUSTOMER_SUMMARY TO ROLE ERP_CONSUMER;
GRANT SELECT ON VIEW DP_SAP_CUSTOMER_SUMMARY TO ROLE MARKETPLACE_CONSUMER;

-- Register SAP products in catalog
INSERT INTO GOVERNANCE.OBSERVABILITY.DATA_PRODUCT_CATALOG (
    PRODUCT_ID, PRODUCT_NAME, PRODUCT_DESCRIPTION, BUSINESS_VALUE, PRODUCT_VERSION,
    SOURCE_SYSTEM, DATABASE_NAME, SCHEMA_NAME, OBJECT_NAME, OBJECT_TYPE,
    DOMAIN, DATA_CLASSIFICATION, CONTAINS_PII, COMPLIANCE_NOTES,
    CONSUMER_ROLE, ALLOWED_ROLES,
    SAMPLE_QUERY_1, SAMPLE_QUERY_1_DESC,
    SAMPLE_QUERY_2, SAMPLE_QUERY_2_DESC,
    SAMPLE_QUERY_3, SAMPLE_QUERY_3_DESC,
    SAMPLE_QUERY_4, SAMPLE_QUERY_4_DESC,
    SAMPLE_QUERY_5, SAMPLE_QUERY_5_DESC,
    OWNER_TEAM, DATA_STEWARD_EMAIL, SLA_REFRESH_HOURS, USE_CASES, TAGS
) VALUES 
(
    'DP-SAP-SALES-001',
    'SAP Sales Analytics',
    'Comprehensive sales order analytics derived from SAP SD (Sales & Distribution) module. Provides aggregated revenue metrics, order volumes, and customer activity across sales organizations and distribution channels. Data is refreshed every 4 hours from the SAP VBAK/VBAP tables via Dynamic Tables.',
    'Enables data-driven sales performance management, revenue forecasting, and channel optimization. Reduces time-to-insight from days to minutes for sales leadership decisions.',
    'v1.0',
    'SAP', 'SEM_DEV', 'MARKETPLACE', 'DP_SAP_SALES_ANALYTICS', 'SECURE_VIEW',
    'SALES', 'INTERNAL', FALSE, 'No PII - aggregated metrics only. Safe for executive dashboards.',
    'ERP_CONSUMER', ARRAY_CONSTRUCT('ERP_CONSUMER', 'MARKETPLACE_CONSUMER', 'DATA_ADMIN'),
    'SELECT ORDER_YEAR, ORDER_QUARTER, SUM(TOTAL_REVENUE) as QUARTERLY_REVENUE FROM SEM_DEV.MARKETPLACE.DP_SAP_SALES_ANALYTICS GROUP BY ORDER_YEAR, ORDER_QUARTER ORDER BY 1 DESC, 2 DESC',
    'Quarterly revenue trends for executive dashboard',
    'SELECT SALES_ORGANIZATION, DISTRIBUTION_CHANNEL, SUM(TOTAL_REVENUE) as REVENUE, SUM(ORDER_COUNT) as ORDERS FROM SEM_DEV.MARKETPLACE.DP_SAP_SALES_ANALYTICS WHERE ORDER_YEAR = YEAR(CURRENT_DATE()) GROUP BY 1, 2 ORDER BY REVENUE DESC',
    'YTD performance by sales org and channel',
    'SELECT ORDER_YEAR, ORDER_MONTH, UNIQUE_CUSTOMERS, LAG(UNIQUE_CUSTOMERS) OVER (ORDER BY ORDER_YEAR, ORDER_MONTH) as PREV_MONTH FROM SEM_DEV.MARKETPLACE.DP_SAP_SALES_ANALYTICS WHERE SALES_ORGANIZATION = ''1000''',
    'Customer acquisition trend analysis',
    'SELECT DISTRIBUTION_CHANNEL, ROUND(AVG(AVG_ORDER_VALUE), 2) as AOV FROM SEM_DEV.MARKETPLACE.DP_SAP_SALES_ANALYTICS GROUP BY DISTRIBUTION_CHANNEL ORDER BY AOV DESC',
    'Average order value comparison by channel',
    'SELECT * FROM SEM_DEV.MARKETPLACE.DP_SAP_SALES_ANALYTICS WHERE ORDER_YEAR >= YEAR(CURRENT_DATE()) - 1 AND TOTAL_REVENUE > 100000',
    'High-value sales activity in last 2 years',
    'SAP Finance Team', 'sap-data-steward@company.com', 4,
    ARRAY_CONSTRUCT('Revenue Reporting', 'Sales Dashboards', 'Channel Analysis', 'Demand Forecasting'),
    ARRAY_CONSTRUCT('SAP', 'ERP', 'Sales', 'Revenue', 'SD')
),
(
    'DP-SAP-PROC-001',
    'SAP Procurement Analytics',
    'Purchase order analytics from SAP MM (Materials Management) module. Provides spend visibility, vendor activity metrics, and procurement patterns across purchasing organizations. Aggregated from EKKO/EKPO tables with 4-hour refresh.',
    'Drives strategic sourcing decisions, identifies cost reduction opportunities, and enables vendor consolidation analysis. Critical for procurement optimization and supply chain resilience.',
    'v1.0',
    'SAP', 'SEM_DEV', 'MARKETPLACE', 'DP_SAP_PROCUREMENT_ANALYTICS', 'SECURE_VIEW',
    'PROCUREMENT', 'INTERNAL', FALSE, 'No PII - vendor IDs are anonymized in aggregation.',
    'ERP_CONSUMER', ARRAY_CONSTRUCT('ERP_CONSUMER', 'MARKETPLACE_CONSUMER', 'DATA_ADMIN'),
    'SELECT PO_YEAR, PO_QUARTER, SUM(TOTAL_SPEND) as QUARTERLY_SPEND FROM SEM_DEV.MARKETPLACE.DP_SAP_PROCUREMENT_ANALYTICS GROUP BY 1, 2 ORDER BY 1 DESC, 2 DESC',
    'Quarterly procurement spend for budget tracking',
    'SELECT PURCHASING_ORGANIZATION, COUNT(DISTINCT VENDOR_KEY) as VENDOR_COUNT, SUM(TOTAL_SPEND) as SPEND FROM SEM_DEV.MARKETPLACE.DP_SAP_PROCUREMENT_ANALYTICS WHERE PO_YEAR = YEAR(CURRENT_DATE()) GROUP BY 1',
    'Vendor concentration by purchasing org',
    'SELECT VENDOR_KEY, SUM(TOTAL_SPEND) as TOTAL_SPEND, SUM(PO_COUNT) as PO_COUNT FROM SEM_DEV.MARKETPLACE.DP_SAP_PROCUREMENT_ANALYTICS GROUP BY 1 ORDER BY 2 DESC LIMIT 20',
    'Top 20 vendors by spend volume',
    'SELECT PO_YEAR, PO_MONTH, ROUND(AVG(AVG_UNIT_PRICE), 2) as AVG_PRICE FROM SEM_DEV.MARKETPLACE.DP_SAP_PROCUREMENT_ANALYTICS GROUP BY 1, 2 ORDER BY 1, 2',
    'Price trend analysis over time',
    'SELECT PURCHASING_GROUP, SUM(TOTAL_UNITS_ORDERED) as UNITS FROM SEM_DEV.MARKETPLACE.DP_SAP_PROCUREMENT_ANALYTICS GROUP BY 1 ORDER BY 2 DESC',
    'Order volume by purchasing group',
    'Procurement Operations', 'procurement-analytics@company.com', 4,
    ARRAY_CONSTRUCT('Spend Analysis', 'Vendor Scorecard', 'Budget Planning', 'Category Management'),
    ARRAY_CONSTRUCT('SAP', 'ERP', 'Procurement', 'Spend', 'MM')
);

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 4: ORACLE ERP DATA PRODUCTS
-- ═══════════════════════════════════════════════════════════════════════════

-- -----------------------------------------------------------------------------
-- Oracle Financial Analytics
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SECURE VIEW DP_ORACLE_FINANCIAL_ANALYTICS AS
SELECT
    LEDGER_NAME,
    PERIOD_NAME,
    ACCOUNT_CLASS,
    EXTRACT(YEAR FROM ACCOUNTING_DATE) AS FISCAL_YEAR,
    EXTRACT(QUARTER FROM ACCOUNTING_DATE) AS FISCAL_QUARTER,
    COUNT(*) AS JOURNAL_ENTRY_COUNT,
    SUM(ENTERED_DEBIT) AS TOTAL_DEBITS,
    SUM(ENTERED_CREDIT) AS TOTAL_CREDITS,
    SUM(ENTERED_DEBIT) - SUM(ENTERED_CREDIT) AS NET_AMOUNT,
    COUNT(DISTINCT BATCH_NAME) AS BATCH_COUNT,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.ORACLE.FACT_GL_JOURNAL_LINES
GROUP BY LEDGER_NAME, PERIOD_NAME, ACCOUNT_CLASS,
         EXTRACT(YEAR FROM ACCOUNTING_DATE), EXTRACT(QUARTER FROM ACCOUNTING_DATE)
ORDER BY FISCAL_YEAR DESC, FISCAL_QUARTER DESC;

COMMENT ON VIEW DP_ORACLE_FINANCIAL_ANALYTICS IS 'Oracle GL Analytics: General ledger journal entry metrics by ledger, period, and account class. Use for financial close tracking, variance analysis, and audit preparation. Updated every 4 hours.';

GRANT SELECT ON VIEW DP_ORACLE_FINANCIAL_ANALYTICS TO ROLE ERP_CONSUMER;
GRANT SELECT ON VIEW DP_ORACLE_FINANCIAL_ANALYTICS TO ROLE MARKETPLACE_CONSUMER;

-- -----------------------------------------------------------------------------
-- Oracle AP Analytics
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SECURE VIEW DP_ORACLE_AP_ANALYTICS AS
SELECT
    VENDOR_SITE AS VENDOR_LOCATION,
    PAYMENT_METHOD,
    INVOICE_TYPE,
    EXTRACT(YEAR FROM INVOICE_DATE) AS INVOICE_YEAR,
    EXTRACT(QUARTER FROM INVOICE_DATE) AS INVOICE_QUARTER,
    COUNT(*) AS INVOICE_COUNT,
    SUM(INVOICE_AMOUNT) AS TOTAL_INVOICE_AMOUNT,
    AVG(INVOICE_AMOUNT) AS AVG_INVOICE_AMOUNT,
    SUM(CASE WHEN PAYMENT_STATUS = 'PAID' THEN 1 ELSE 0 END) AS PAID_COUNT,
    SUM(CASE WHEN PAYMENT_STATUS = 'PENDING' THEN 1 ELSE 0 END) AS PENDING_COUNT,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.ORACLE.FACT_AP_INVOICES
GROUP BY VENDOR_SITE, PAYMENT_METHOD, INVOICE_TYPE,
         EXTRACT(YEAR FROM INVOICE_DATE), EXTRACT(QUARTER FROM INVOICE_DATE)
ORDER BY INVOICE_YEAR DESC, INVOICE_QUARTER DESC;

COMMENT ON VIEW DP_ORACLE_AP_ANALYTICS IS 'Oracle Accounts Payable Analytics: Invoice metrics by vendor location, payment method, and type. Use for cash flow forecasting, payment optimization, and vendor payment analysis. Updated every 4 hours.';

GRANT SELECT ON VIEW DP_ORACLE_AP_ANALYTICS TO ROLE ERP_CONSUMER;
GRANT SELECT ON VIEW DP_ORACLE_AP_ANALYTICS TO ROLE MARKETPLACE_CONSUMER;

-- Register Oracle products in catalog
INSERT INTO GOVERNANCE.OBSERVABILITY.DATA_PRODUCT_CATALOG (
    PRODUCT_ID, PRODUCT_NAME, PRODUCT_DESCRIPTION, BUSINESS_VALUE, PRODUCT_VERSION,
    SOURCE_SYSTEM, DATABASE_NAME, SCHEMA_NAME, OBJECT_NAME, OBJECT_TYPE,
    DOMAIN, DATA_CLASSIFICATION, CONTAINS_PII, COMPLIANCE_NOTES,
    CONSUMER_ROLE, ALLOWED_ROLES,
    SAMPLE_QUERY_1, SAMPLE_QUERY_1_DESC,
    SAMPLE_QUERY_2, SAMPLE_QUERY_2_DESC,
    SAMPLE_QUERY_3, SAMPLE_QUERY_3_DESC,
    OWNER_TEAM, DATA_STEWARD_EMAIL, SLA_REFRESH_HOURS, USE_CASES, TAGS
) VALUES 
(
    'DP-ORACLE-FIN-001',
    'Oracle Financial Analytics',
    'General Ledger journal entry analytics from Oracle Financials Cloud. Provides visibility into accounting activity, period close metrics, and ledger balances. Aggregated from GL_JE_LINES with dual-entry validation.',
    'Accelerates financial close process, enables real-time variance detection, and supports SOX compliance through complete audit trail visibility.',
    'v1.0',
    'ORACLE', 'SEM_DEV', 'MARKETPLACE', 'DP_ORACLE_FINANCIAL_ANALYTICS', 'SECURE_VIEW',
    'FINANCE', 'CONFIDENTIAL', FALSE, 'No individual transaction details - aggregated by period and account class.',
    'ERP_CONSUMER', ARRAY_CONSTRUCT('ERP_CONSUMER', 'MARKETPLACE_CONSUMER', 'DATA_ADMIN'),
    'SELECT FISCAL_YEAR, FISCAL_QUARTER, SUM(NET_AMOUNT) as NET_POSITION FROM SEM_DEV.MARKETPLACE.DP_ORACLE_FINANCIAL_ANALYTICS GROUP BY 1, 2 ORDER BY 1 DESC, 2 DESC',
    'Net financial position by quarter',
    'SELECT ACCOUNT_CLASS, SUM(TOTAL_DEBITS) as DEBITS, SUM(TOTAL_CREDITS) as CREDITS FROM SEM_DEV.MARKETPLACE.DP_ORACLE_FINANCIAL_ANALYTICS WHERE FISCAL_YEAR = YEAR(CURRENT_DATE()) GROUP BY 1',
    'YTD activity by account class for trial balance',
    'SELECT PERIOD_NAME, JOURNAL_ENTRY_COUNT, BATCH_COUNT FROM SEM_DEV.MARKETPLACE.DP_ORACLE_FINANCIAL_ANALYTICS WHERE LEDGER_NAME = ''US_LEDGER'' ORDER BY FISCAL_YEAR DESC, FISCAL_QUARTER DESC',
    'Period close activity tracking',
    'Oracle Finance Team', 'oracle-finance@company.com', 4,
    ARRAY_CONSTRUCT('Financial Close', 'Variance Analysis', 'Audit Support', 'Budget vs Actual'),
    ARRAY_CONSTRUCT('Oracle', 'ERP', 'Finance', 'GL', 'Accounting')
),
(
    'DP-ORACLE-AP-001',
    'Oracle Accounts Payable Analytics',
    'Accounts Payable invoice analytics from Oracle Financials Cloud. Provides payment activity metrics, invoice aging, and vendor payment patterns. Supports cash management and vendor relationship optimization.',
    'Improves working capital management through payment timing optimization. Identifies early payment discount opportunities and vendor consolidation candidates.',
    'v1.0',
    'ORACLE', 'SEM_DEV', 'MARKETPLACE', 'DP_ORACLE_AP_ANALYTICS', 'SECURE_VIEW',
    'FINANCE', 'CONFIDENTIAL', FALSE, 'Vendor names anonymized. No bank account details.',
    'ERP_CONSUMER', ARRAY_CONSTRUCT('ERP_CONSUMER', 'MARKETPLACE_CONSUMER', 'DATA_ADMIN'),
    'SELECT INVOICE_YEAR, INVOICE_QUARTER, SUM(TOTAL_INVOICE_AMOUNT) as TOTAL_AP FROM SEM_DEV.MARKETPLACE.DP_ORACLE_AP_ANALYTICS GROUP BY 1, 2 ORDER BY 1 DESC, 2 DESC',
    'Quarterly AP volume for cash flow planning',
    'SELECT PAYMENT_METHOD, SUM(INVOICE_COUNT) as COUNT, SUM(TOTAL_INVOICE_AMOUNT) as AMOUNT FROM SEM_DEV.MARKETPLACE.DP_ORACLE_AP_ANALYTICS GROUP BY 1',
    'Payment method distribution analysis',
    'SELECT VENDOR_LOCATION, SUM(PENDING_COUNT) as PENDING, SUM(TOTAL_INVOICE_AMOUNT) as AMOUNT FROM SEM_DEV.MARKETPLACE.DP_ORACLE_AP_ANALYTICS WHERE PENDING_COUNT > 0 GROUP BY 1 ORDER BY 2 DESC',
    'Pending payments by vendor location',
    'Oracle Finance Team', 'oracle-ap@company.com', 4,
    ARRAY_CONSTRUCT('Cash Flow Forecasting', 'Vendor Payments', 'Working Capital', 'Payment Terms'),
    ARRAY_CONSTRUCT('Oracle', 'ERP', 'AP', 'Payments', 'Vendors')
);

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 5: SALESFORCE CRM DATA PRODUCTS
-- ═══════════════════════════════════════════════════════════════════════════

-- -----------------------------------------------------------------------------
-- Salesforce Pipeline Analytics
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SECURE VIEW DP_SALESFORCE_PIPELINE AS
SELECT
    STAGE_NAME AS PIPELINE_STAGE,
    OPPORTUNITY_TYPE,
    LEAD_SOURCE,
    FORECAST_CATEGORY,
    EXTRACT(YEAR FROM CLOSE_DATE) AS CLOSE_YEAR,
    EXTRACT(QUARTER FROM CLOSE_DATE) AS CLOSE_QUARTER,
    COUNT(*) AS OPPORTUNITY_COUNT,
    SUM(AMOUNT) AS TOTAL_PIPELINE_VALUE,
    AVG(AMOUNT) AS AVG_DEAL_SIZE,
    MEDIAN(AMOUNT) AS MEDIAN_DEAL_SIZE,
    SUM(CASE WHEN IS_WON THEN 1 ELSE 0 END) AS WON_COUNT,
    SUM(CASE WHEN IS_WON THEN AMOUNT ELSE 0 END) AS WON_REVENUE,
    SUM(CASE WHEN IS_CLOSED AND NOT IS_WON THEN 1 ELSE 0 END) AS LOST_COUNT,
    ROUND(100.0 * SUM(CASE WHEN IS_WON THEN 1 ELSE 0 END) / 
          NULLIF(SUM(CASE WHEN IS_CLOSED THEN 1 ELSE 0 END), 0), 2) AS WIN_RATE_PCT,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.SALESFORCE.FACT_OPPORTUNITIES
GROUP BY STAGE_NAME, OPPORTUNITY_TYPE, LEAD_SOURCE, FORECAST_CATEGORY,
         EXTRACT(YEAR FROM CLOSE_DATE), EXTRACT(QUARTER FROM CLOSE_DATE)
ORDER BY CLOSE_YEAR DESC, CLOSE_QUARTER DESC;

COMMENT ON VIEW DP_SALESFORCE_PIPELINE IS 'Salesforce Pipeline Analytics: Opportunity metrics by stage, type, source, and time period. Use for pipeline coverage, win rate analysis, and revenue forecasting. Updated hourly.';

GRANT SELECT ON VIEW DP_SALESFORCE_PIPELINE TO ROLE CRM_CONSUMER;
GRANT SELECT ON VIEW DP_SALESFORCE_PIPELINE TO ROLE MARKETPLACE_CONSUMER;

-- -----------------------------------------------------------------------------
-- Salesforce Account Health
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SECURE VIEW DP_SALESFORCE_ACCOUNT_HEALTH AS
SELECT
    INDUSTRY,
    CUSTOMER_TIER,
    BILLING_COUNTRY AS COUNTRY,
    BILLING_STATE AS STATE,
    COUNT(*) AS ACCOUNT_COUNT,
    SUM(CASE WHEN IS_ACTIVE THEN 1 ELSE 0 END) AS ACTIVE_ACCOUNTS,
    SUM(ANNUAL_REVENUE) AS TOTAL_ARR,
    AVG(ANNUAL_REVENUE) AS AVG_ARR,
    SUM(EMPLOYEE_COUNT) AS TOTAL_EMPLOYEES,
    AVG(EMPLOYEE_COUNT) AS AVG_EMPLOYEES,
    ROUND(100.0 * SUM(CASE WHEN IS_ACTIVE THEN 1 ELSE 0 END) / COUNT(*), 2) AS RETENTION_RATE_PCT,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.SALESFORCE.DIM_ACCOUNT
GROUP BY INDUSTRY, CUSTOMER_TIER, BILLING_COUNTRY, BILLING_STATE
ORDER BY TOTAL_ARR DESC;

COMMENT ON VIEW DP_SALESFORCE_ACCOUNT_HEALTH IS 'Salesforce Account Health: Account metrics by industry, tier, and geography. Use for customer segmentation, territory planning, and retention analysis. Updated every 4 hours.';

GRANT SELECT ON VIEW DP_SALESFORCE_ACCOUNT_HEALTH TO ROLE CRM_CONSUMER;
GRANT SELECT ON VIEW DP_SALESFORCE_ACCOUNT_HEALTH TO ROLE MARKETPLACE_CONSUMER;

-- -----------------------------------------------------------------------------
-- Salesforce Service Analytics
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SECURE VIEW DP_SALESFORCE_SERVICE_ANALYTICS AS
SELECT
    STATUS AS CASE_STATUS,
    PRIORITY,
    ORIGIN AS CASE_ORIGIN,
    CASE_TYPE,
    EXTRACT(YEAR FROM CREATED_DATE) AS CREATED_YEAR,
    EXTRACT(MONTH FROM CREATED_DATE) AS CREATED_MONTH,
    COUNT(*) AS CASE_COUNT,
    SUM(CASE WHEN IS_CLOSED THEN 1 ELSE 0 END) AS CLOSED_COUNT,
    SUM(CASE WHEN IS_ESCALATED THEN 1 ELSE 0 END) AS ESCALATED_COUNT,
    ROUND(100.0 * SUM(CASE WHEN IS_CLOSED THEN 1 ELSE 0 END) / COUNT(*), 2) AS CLOSURE_RATE_PCT,
    ROUND(100.0 * SUM(CASE WHEN IS_ESCALATED THEN 1 ELSE 0 END) / COUNT(*), 2) AS ESCALATION_RATE_PCT,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.SALESFORCE.FACT_CASES
GROUP BY STATUS, PRIORITY, ORIGIN, CASE_TYPE,
         EXTRACT(YEAR FROM CREATED_DATE), EXTRACT(MONTH FROM CREATED_DATE)
ORDER BY CREATED_YEAR DESC, CREATED_MONTH DESC;

COMMENT ON VIEW DP_SALESFORCE_SERVICE_ANALYTICS IS 'Salesforce Service Analytics: Support case metrics by status, priority, origin, and type. Use for service level monitoring, resource planning, and customer satisfaction analysis. Updated hourly.';

GRANT SELECT ON VIEW DP_SALESFORCE_SERVICE_ANALYTICS TO ROLE CRM_CONSUMER;
GRANT SELECT ON VIEW DP_SALESFORCE_SERVICE_ANALYTICS TO ROLE MARKETPLACE_CONSUMER;

-- Register Salesforce products in catalog
INSERT INTO GOVERNANCE.OBSERVABILITY.DATA_PRODUCT_CATALOG (
    PRODUCT_ID, PRODUCT_NAME, PRODUCT_DESCRIPTION, BUSINESS_VALUE, PRODUCT_VERSION,
    SOURCE_SYSTEM, DATABASE_NAME, SCHEMA_NAME, OBJECT_NAME, OBJECT_TYPE,
    DOMAIN, DATA_CLASSIFICATION, CONTAINS_PII, COMPLIANCE_NOTES,
    CONSUMER_ROLE, ALLOWED_ROLES,
    SAMPLE_QUERY_1, SAMPLE_QUERY_1_DESC,
    SAMPLE_QUERY_2, SAMPLE_QUERY_2_DESC,
    SAMPLE_QUERY_3, SAMPLE_QUERY_3_DESC,
    SAMPLE_QUERY_4, SAMPLE_QUERY_4_DESC,
    SAMPLE_QUERY_5, SAMPLE_QUERY_5_DESC,
    OWNER_TEAM, DATA_STEWARD_EMAIL, SLA_REFRESH_HOURS, USE_CASES, TAGS
) VALUES 
(
    'DP-SF-PIPELINE-001',
    'Salesforce Pipeline Analytics',
    'Sales pipeline analytics from Salesforce CRM. Provides comprehensive opportunity metrics including pipeline value, win rates, deal velocity, and forecast accuracy. Real-time visibility into sales performance across all stages.',
    'Enables accurate revenue forecasting, identifies pipeline gaps, and highlights coaching opportunities. Critical for sales leadership and board reporting.',
    'v1.0',
    'SALESFORCE', 'SEM_DEV', 'MARKETPLACE', 'DP_SALESFORCE_PIPELINE', 'SECURE_VIEW',
    'SALES', 'INTERNAL', FALSE, 'No customer names or deal details - aggregated stage metrics only.',
    'CRM_CONSUMER', ARRAY_CONSTRUCT('CRM_CONSUMER', 'MARKETPLACE_CONSUMER', 'DATA_ADMIN'),
    'SELECT CLOSE_YEAR, CLOSE_QUARTER, SUM(WON_REVENUE) as BOOKINGS, AVG(WIN_RATE_PCT) as WIN_RATE FROM SEM_DEV.MARKETPLACE.DP_SALESFORCE_PIPELINE GROUP BY 1, 2 ORDER BY 1 DESC, 2 DESC',
    'Quarterly bookings and win rate for board deck',
    'SELECT PIPELINE_STAGE, SUM(TOTAL_PIPELINE_VALUE) as PIPELINE, SUM(OPPORTUNITY_COUNT) as DEALS FROM SEM_DEV.MARKETPLACE.DP_SALESFORCE_PIPELINE WHERE CLOSE_YEAR = YEAR(CURRENT_DATE()) AND NOT PIPELINE_STAGE IN (''Closed Won'', ''Closed Lost'') GROUP BY 1',
    'Current pipeline by stage for coverage analysis',
    'SELECT LEAD_SOURCE, SUM(WON_COUNT) as WINS, AVG(WIN_RATE_PCT) as WIN_RATE FROM SEM_DEV.MARKETPLACE.DP_SALESFORCE_PIPELINE GROUP BY 1 ORDER BY 2 DESC',
    'Lead source effectiveness for marketing ROI',
    'SELECT FORECAST_CATEGORY, SUM(TOTAL_PIPELINE_VALUE) as VALUE FROM SEM_DEV.MARKETPLACE.DP_SALESFORCE_PIPELINE WHERE CLOSE_YEAR = YEAR(CURRENT_DATE()) AND CLOSE_QUARTER = QUARTER(CURRENT_DATE()) GROUP BY 1',
    'Current quarter forecast by category',
    'SELECT OPPORTUNITY_TYPE, AVG(AVG_DEAL_SIZE) as AVG_DEAL, AVG(MEDIAN_DEAL_SIZE) as MEDIAN_DEAL FROM SEM_DEV.MARKETPLACE.DP_SALESFORCE_PIPELINE GROUP BY 1 ORDER BY 2 DESC',
    'Deal size analysis by opportunity type',
    'Sales Operations', 'sales-ops@company.com', 1,
    ARRAY_CONSTRUCT('Pipeline Review', 'Forecast Calls', 'Sales Dashboards', 'Win/Loss Analysis'),
    ARRAY_CONSTRUCT('Salesforce', 'CRM', 'Pipeline', 'Opportunities', 'Revenue')
),
(
    'DP-SF-ACCOUNTS-001',
    'Salesforce Account Health',
    'Customer account analytics from Salesforce CRM. Provides account segmentation metrics, annual revenue distribution, and retention indicators by industry, tier, and geography.',
    'Supports customer success prioritization, identifies at-risk segments, and enables data-driven territory design. Essential for customer retention and expansion strategies.',
    'v1.0',
    'SALESFORCE', 'SEM_DEV', 'MARKETPLACE', 'DP_SALESFORCE_ACCOUNT_HEALTH', 'SECURE_VIEW',
    'CUSTOMER', 'INTERNAL', FALSE, 'No company names or contacts - aggregated segment metrics only.',
    'CRM_CONSUMER', ARRAY_CONSTRUCT('CRM_CONSUMER', 'MARKETPLACE_CONSUMER', 'DATA_ADMIN'),
    'SELECT CUSTOMER_TIER, SUM(ACCOUNT_COUNT) as ACCOUNTS, SUM(TOTAL_ARR) as ARR FROM SEM_DEV.MARKETPLACE.DP_SALESFORCE_ACCOUNT_HEALTH GROUP BY 1 ORDER BY 2 DESC',
    'Account and ARR distribution by tier',
    'SELECT INDUSTRY, ACTIVE_ACCOUNTS, RETENTION_RATE_PCT FROM SEM_DEV.MARKETPLACE.DP_SALESFORCE_ACCOUNT_HEALTH WHERE ACCOUNT_COUNT > 10 ORDER BY 3',
    'Industries with lowest retention for intervention',
    'SELECT COUNTRY, STATE, SUM(TOTAL_ARR) as ARR FROM SEM_DEV.MARKETPLACE.DP_SALESFORCE_ACCOUNT_HEALTH GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 20',
    'Top territories by ARR for resource allocation',
    'Sales Operations', 'customer-success@company.com', 4,
    ARRAY_CONSTRUCT('Customer Segmentation', 'Territory Planning', 'Retention Analysis', 'Account Scoring'),
    ARRAY_CONSTRUCT('Salesforce', 'CRM', 'Accounts', 'Customers', 'ARR')
),
(
    'DP-SF-SERVICE-001',
    'Salesforce Service Analytics',
    'Customer service analytics from Salesforce Service Cloud. Provides case volume metrics, resolution rates, escalation patterns, and channel effectiveness by priority and type.',
    'Drives service level improvements, optimizes support staffing, and identifies product issues through support patterns. Critical for customer satisfaction and NPS improvement.',
    'v1.0',
    'SALESFORCE', 'SEM_DEV', 'MARKETPLACE', 'DP_SALESFORCE_SERVICE_ANALYTICS', 'SECURE_VIEW',
    'SERVICE', 'INTERNAL', FALSE, 'No customer identifiers or case details - aggregated metrics only.',
    'CRM_CONSUMER', ARRAY_CONSTRUCT('CRM_CONSUMER', 'MARKETPLACE_CONSUMER', 'DATA_ADMIN'),
    'SELECT CREATED_YEAR, CREATED_MONTH, SUM(CASE_COUNT) as VOLUME, AVG(CLOSURE_RATE_PCT) as RESOLUTION_RATE FROM SEM_DEV.MARKETPLACE.DP_SALESFORCE_SERVICE_ANALYTICS GROUP BY 1, 2 ORDER BY 1 DESC, 2 DESC',
    'Monthly case volume and resolution trends',
    'SELECT PRIORITY, SUM(CASE_COUNT) as CASES, AVG(ESCALATION_RATE_PCT) as ESCALATION_RATE FROM SEM_DEV.MARKETPLACE.DP_SALESFORCE_SERVICE_ANALYTICS GROUP BY 1 ORDER BY 1',
    'Case distribution and escalation by priority',
    'SELECT CASE_ORIGIN, SUM(CASE_COUNT) as CASES, AVG(CLOSURE_RATE_PCT) as CLOSURE_RATE FROM SEM_DEV.MARKETPLACE.DP_SALESFORCE_SERVICE_ANALYTICS GROUP BY 1 ORDER BY 2 DESC',
    'Channel effectiveness analysis',
    'Customer Support', 'support-analytics@company.com', 1,
    ARRAY_CONSTRUCT('Service Dashboards', 'SLA Monitoring', 'Staffing Planning', 'Customer Satisfaction'),
    ARRAY_CONSTRUCT('Salesforce', 'CRM', 'Service', 'Cases', 'Support')
);

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 6: FHIR HEALTHCARE DATA PRODUCTS
-- ═══════════════════════════════════════════════════════════════════════════

-- -----------------------------------------------------------------------------
-- FHIR Clinical Encounters
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SECURE VIEW DP_FHIR_CLINICAL_ENCOUNTERS AS
SELECT
    ENCOUNTER_CLASS,
    ENCOUNTER_TYPE,
    STATUS AS ENCOUNTER_STATUS,
    FACILITY_NAME,
    EXTRACT(YEAR FROM PERIOD_START) AS ENCOUNTER_YEAR,
    EXTRACT(QUARTER FROM PERIOD_START) AS ENCOUNTER_QUARTER,
    COUNT(*) AS ENCOUNTER_COUNT,
    COUNT(DISTINCT PATIENT_KEY) AS UNIQUE_PATIENTS,
    AVG(DURATION_MINUTES) AS AVG_DURATION_MINUTES,
    MEDIAN(DURATION_MINUTES) AS MEDIAN_DURATION_MINUTES,
    MIN(DURATION_MINUTES) AS MIN_DURATION_MINUTES,
    MAX(DURATION_MINUTES) AS MAX_DURATION_MINUTES,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.FHIR.FACT_ENCOUNTERS
GROUP BY ENCOUNTER_CLASS, ENCOUNTER_TYPE, STATUS, FACILITY_NAME,
         EXTRACT(YEAR FROM PERIOD_START), EXTRACT(QUARTER FROM PERIOD_START)
ORDER BY ENCOUNTER_YEAR DESC, ENCOUNTER_QUARTER DESC;

COMMENT ON VIEW DP_FHIR_CLINICAL_ENCOUNTERS IS 'FHIR Clinical Encounters: De-identified encounter metrics by class, type, and facility. HIPAA compliant - no PHI. Use for capacity planning, resource utilization, and clinical operations analysis. Updated every 4 hours.';

GRANT SELECT ON VIEW DP_FHIR_CLINICAL_ENCOUNTERS TO ROLE HEALTHCARE_CONSUMER;
GRANT SELECT ON VIEW DP_FHIR_CLINICAL_ENCOUNTERS TO ROLE MARKETPLACE_CONSUMER;

-- -----------------------------------------------------------------------------
-- FHIR Population Health
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SECURE VIEW DP_FHIR_POPULATION_HEALTH AS
SELECT
    GENDER,
    FLOOR(DATEDIFF('YEAR', BIRTH_DATE, CURRENT_DATE()) / 10) * 10 AS AGE_BAND,
    STATE,
    MARITAL_STATUS,
    COUNT(*) AS PATIENT_COUNT,
    SUM(CASE WHEN IS_ACTIVE THEN 1 ELSE 0 END) AS ACTIVE_PATIENTS,
    ROUND(100.0 * SUM(CASE WHEN IS_ACTIVE THEN 1 ELSE 0 END) / COUNT(*), 2) AS ACTIVE_RATE_PCT,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.FHIR.DIM_PATIENT
GROUP BY GENDER, FLOOR(DATEDIFF('YEAR', BIRTH_DATE, CURRENT_DATE()) / 10) * 10, STATE, MARITAL_STATUS
ORDER BY PATIENT_COUNT DESC;

COMMENT ON VIEW DP_FHIR_POPULATION_HEALTH IS 'FHIR Population Health: De-identified patient demographics by age band, gender, and geography. HIPAA compliant - minimum cell size 10. Use for population health management and care gap analysis. Updated every 24 hours.';

GRANT SELECT ON VIEW DP_FHIR_POPULATION_HEALTH TO ROLE HEALTHCARE_CONSUMER;
GRANT SELECT ON VIEW DP_FHIR_POPULATION_HEALTH TO ROLE MARKETPLACE_CONSUMER;

-- -----------------------------------------------------------------------------
-- FHIR Condition Analytics
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SECURE VIEW DP_FHIR_CONDITION_ANALYTICS AS
SELECT
    CODE_SYSTEM,
    DIAGNOSIS_CODE,
    DIAGNOSIS_DESCRIPTION,
    CLINICAL_STATUS,
    SEVERITY,
    COUNT(*) AS CONDITION_COUNT,
    COUNT(DISTINCT PATIENT_KEY) AS PATIENTS_AFFECTED,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.FHIR.FACT_CONDITIONS
GROUP BY CODE_SYSTEM, DIAGNOSIS_CODE, DIAGNOSIS_DESCRIPTION, CLINICAL_STATUS, SEVERITY
HAVING COUNT(DISTINCT PATIENT_KEY) >= 10  -- HIPAA minimum cell size
ORDER BY CONDITION_COUNT DESC
LIMIT 100;

COMMENT ON VIEW DP_FHIR_CONDITION_ANALYTICS IS 'FHIR Condition Analytics: Top 100 conditions by prevalence with minimum 10 patients (HIPAA safe harbor). Use for disease burden analysis, quality measures, and clinical program planning. Updated every 4 hours.';

GRANT SELECT ON VIEW DP_FHIR_CONDITION_ANALYTICS TO ROLE HEALTHCARE_CONSUMER;
GRANT SELECT ON VIEW DP_FHIR_CONDITION_ANALYTICS TO ROLE MARKETPLACE_CONSUMER;

-- Register FHIR products in catalog
INSERT INTO GOVERNANCE.OBSERVABILITY.DATA_PRODUCT_CATALOG (
    PRODUCT_ID, PRODUCT_NAME, PRODUCT_DESCRIPTION, BUSINESS_VALUE, PRODUCT_VERSION,
    SOURCE_SYSTEM, DATABASE_NAME, SCHEMA_NAME, OBJECT_NAME, OBJECT_TYPE,
    DOMAIN, DATA_CLASSIFICATION, CONTAINS_PII, COMPLIANCE_NOTES,
    CONSUMER_ROLE, ALLOWED_ROLES,
    SAMPLE_QUERY_1, SAMPLE_QUERY_1_DESC,
    SAMPLE_QUERY_2, SAMPLE_QUERY_2_DESC,
    SAMPLE_QUERY_3, SAMPLE_QUERY_3_DESC,
    SAMPLE_QUERY_4, SAMPLE_QUERY_4_DESC,
    OWNER_TEAM, DATA_STEWARD_EMAIL, SLA_REFRESH_HOURS, USE_CASES, TAGS
) VALUES 
(
    'DP-FHIR-ENCOUNTERS-001',
    'FHIR Clinical Encounters',
    'De-identified clinical encounter analytics from FHIR R4 resources. Provides encounter volumes, duration metrics, and facility utilization patterns. Fully HIPAA compliant with no Protected Health Information.',
    'Enables evidence-based capacity planning, identifies bottlenecks in patient flow, and supports operational efficiency initiatives. Critical for healthcare operations and quality improvement.',
    'v1.0',
    'FHIR', 'SEM_DEV', 'MARKETPLACE', 'DP_FHIR_CLINICAL_ENCOUNTERS', 'SECURE_VIEW',
    'CLINICAL', 'RESTRICTED', FALSE, 'HIPAA compliant. No PHI. Aggregated metrics only. IRB approval not required for operational use.',
    'HEALTHCARE_CONSUMER', ARRAY_CONSTRUCT('HEALTHCARE_CONSUMER', 'MARKETPLACE_CONSUMER', 'DATA_ADMIN'),
    'SELECT ENCOUNTER_YEAR, ENCOUNTER_QUARTER, SUM(ENCOUNTER_COUNT) as VISITS, SUM(UNIQUE_PATIENTS) as PATIENTS FROM SEM_DEV.MARKETPLACE.DP_FHIR_CLINICAL_ENCOUNTERS GROUP BY 1, 2 ORDER BY 1 DESC, 2 DESC',
    'Quarterly patient visit volume for capacity planning',
    'SELECT ENCOUNTER_CLASS, SUM(ENCOUNTER_COUNT) as VISITS, AVG(AVG_DURATION_MINUTES) as AVG_DURATION FROM SEM_DEV.MARKETPLACE.DP_FHIR_CLINICAL_ENCOUNTERS GROUP BY 1 ORDER BY 2 DESC',
    'Visit distribution by encounter class',
    'SELECT FACILITY_NAME, SUM(ENCOUNTER_COUNT) as VISITS FROM SEM_DEV.MARKETPLACE.DP_FHIR_CLINICAL_ENCOUNTERS WHERE ENCOUNTER_YEAR = YEAR(CURRENT_DATE()) GROUP BY 1 ORDER BY 2 DESC',
    'YTD facility utilization comparison',
    'SELECT ENCOUNTER_TYPE, AVG(AVG_DURATION_MINUTES) as AVG_MIN, AVG(MEDIAN_DURATION_MINUTES) as MEDIAN_MIN FROM SEM_DEV.MARKETPLACE.DP_FHIR_CLINICAL_ENCOUNTERS GROUP BY 1 ORDER BY 2 DESC',
    'Duration benchmarks by encounter type',
    'Clinical Operations', 'clinical-analytics@health.org', 4,
    ARRAY_CONSTRUCT('Capacity Planning', 'Operational Efficiency', 'Quality Metrics', 'Resource Allocation'),
    ARRAY_CONSTRUCT('FHIR', 'Healthcare', 'Clinical', 'Encounters', 'HIPAA')
),
(
    'DP-FHIR-POPULATION-001',
    'FHIR Population Health',
    'De-identified population demographics from FHIR Patient resources. Age bands, gender distribution, and geographic spread with minimum cell sizes for privacy protection. Supports population health management initiatives.',
    'Enables population segmentation for care management programs, identifies health disparities, and supports community health needs assessments.',
    'v1.0',
    'FHIR', 'SEM_DEV', 'MARKETPLACE', 'DP_FHIR_POPULATION_HEALTH', 'SECURE_VIEW',
    'POPULATION_HEALTH', 'RESTRICTED', FALSE, 'HIPAA Safe Harbor compliant. Age bands used instead of exact ages. Minimum cell size 10.',
    'HEALTHCARE_CONSUMER', ARRAY_CONSTRUCT('HEALTHCARE_CONSUMER', 'MARKETPLACE_CONSUMER', 'DATA_ADMIN'),
    'SELECT GENDER, SUM(PATIENT_COUNT) as PATIENTS FROM SEM_DEV.MARKETPLACE.DP_FHIR_POPULATION_HEALTH GROUP BY 1',
    'Patient population by gender',
    'SELECT AGE_BAND, SUM(PATIENT_COUNT) as PATIENTS FROM SEM_DEV.MARKETPLACE.DP_FHIR_POPULATION_HEALTH GROUP BY 1 ORDER BY 1',
    'Age distribution pyramid for population health',
    'SELECT STATE, SUM(PATIENT_COUNT) as PATIENTS, AVG(ACTIVE_RATE_PCT) as ENGAGEMENT FROM SEM_DEV.MARKETPLACE.DP_FHIR_POPULATION_HEALTH GROUP BY 1 ORDER BY 2 DESC',
    'Geographic distribution for community health planning',
    'Population Health', 'population-health@health.org', 24,
    ARRAY_CONSTRUCT('Population Segmentation', 'Health Equity', 'Community Health', 'Care Gaps'),
    ARRAY_CONSTRUCT('FHIR', 'Healthcare', 'Population', 'Demographics', 'HIPAA')
);

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 7: WORKDAY HR DATA PRODUCTS
-- ═══════════════════════════════════════════════════════════════════════════

-- -----------------------------------------------------------------------------
-- Workday Workforce Analytics
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SECURE VIEW DP_WORKDAY_WORKFORCE AS
SELECT
    DEPARTMENT,
    JOB_FAMILY,
    JOB_LEVEL,
    WORKER_TYPE,
    WORK_LOCATION,
    COUNTRY,
    COUNT(*) AS HEADCOUNT,
    SUM(CASE WHEN IS_ACTIVE THEN 1 ELSE 0 END) AS ACTIVE_EMPLOYEES,
    SUM(CASE WHEN NOT IS_ACTIVE THEN 1 ELSE 0 END) AS TERMINATED_EMPLOYEES,
    ROUND(AVG(TENURE_YEARS), 1) AS AVG_TENURE_YEARS,
    ROUND(AVG(FTE), 2) AS AVG_FTE,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.WORKDAY.DIM_EMPLOYEE
GROUP BY DEPARTMENT, JOB_FAMILY, JOB_LEVEL, WORKER_TYPE, WORK_LOCATION, COUNTRY
ORDER BY HEADCOUNT DESC;

COMMENT ON VIEW DP_WORKDAY_WORKFORCE IS 'Workday Workforce Analytics: Headcount metrics by department, job family, level, and location. No individual employee data. Use for workforce planning, org design, and talent analytics. Updated every 4 hours.';

GRANT SELECT ON VIEW DP_WORKDAY_WORKFORCE TO ROLE WORKFORCE_CONSUMER;
GRANT SELECT ON VIEW DP_WORKDAY_WORKFORCE TO ROLE MARKETPLACE_CONSUMER;

-- -----------------------------------------------------------------------------
-- Workday Compensation Bands
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SECURE VIEW DP_WORKDAY_COMPENSATION AS
SELECT
    PAY_GRADE,
    JOB_LEVEL,
    CURRENCY_CODE,
    COUNT(*) AS EMPLOYEE_COUNT,
    ROUND(AVG(BASE_PAY), 0) AS AVG_BASE_PAY,
    ROUND(MEDIAN(BASE_PAY), 0) AS MEDIAN_BASE_PAY,
    ROUND(MIN(BASE_PAY), 0) AS MIN_BASE_PAY,
    ROUND(MAX(BASE_PAY), 0) AS MAX_BASE_PAY,
    ROUND(STDDEV(BASE_PAY), 0) AS STDDEV_BASE_PAY,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.WORKDAY.FACT_COMPENSATION
GROUP BY PAY_GRADE, JOB_LEVEL, CURRENCY_CODE
HAVING COUNT(*) >= 5  -- Privacy threshold
ORDER BY PAY_GRADE, JOB_LEVEL;

COMMENT ON VIEW DP_WORKDAY_COMPENSATION IS 'Workday Compensation Bands: Aggregated pay statistics by grade and level with minimum 5 employees for privacy. Use for compensation benchmarking, pay equity analysis, and budget planning. Updated every 24 hours.';

GRANT SELECT ON VIEW DP_WORKDAY_COMPENSATION TO ROLE WORKFORCE_CONSUMER;
-- Note: Compensation data NOT granted to general marketplace consumer

-- -----------------------------------------------------------------------------
-- Workday Time Off Analytics
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SECURE VIEW DP_WORKDAY_TIME_OFF AS
SELECT
    TIME_OFF_TYPE,
    STATUS AS REQUEST_STATUS,
    EXTRACT(YEAR FROM REQUEST_DATE) AS REQUEST_YEAR,
    EXTRACT(QUARTER FROM REQUEST_DATE) AS REQUEST_QUARTER,
    COUNT(*) AS REQUEST_COUNT,
    COUNT(DISTINCT EMPLOYEE_KEY) AS EMPLOYEES_REQUESTING,
    SUM(TOTAL_HOURS) AS TOTAL_HOURS_REQUESTED,
    AVG(TOTAL_HOURS) AS AVG_HOURS_PER_REQUEST,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.WORKDAY.FACT_TIME_OFF
GROUP BY TIME_OFF_TYPE, STATUS, 
         EXTRACT(YEAR FROM REQUEST_DATE), EXTRACT(QUARTER FROM REQUEST_DATE)
ORDER BY REQUEST_YEAR DESC, REQUEST_QUARTER DESC;

COMMENT ON VIEW DP_WORKDAY_TIME_OFF IS 'Workday Time Off Analytics: Leave request metrics by type and status. Use for absence trending, coverage planning, and policy effectiveness analysis. Updated every 4 hours.';

GRANT SELECT ON VIEW DP_WORKDAY_TIME_OFF TO ROLE WORKFORCE_CONSUMER;
GRANT SELECT ON VIEW DP_WORKDAY_TIME_OFF TO ROLE MARKETPLACE_CONSUMER;

-- Register Workday products in catalog
INSERT INTO GOVERNANCE.OBSERVABILITY.DATA_PRODUCT_CATALOG (
    PRODUCT_ID, PRODUCT_NAME, PRODUCT_DESCRIPTION, BUSINESS_VALUE, PRODUCT_VERSION,
    SOURCE_SYSTEM, DATABASE_NAME, SCHEMA_NAME, OBJECT_NAME, OBJECT_TYPE,
    DOMAIN, DATA_CLASSIFICATION, CONTAINS_PII, COMPLIANCE_NOTES,
    CONSUMER_ROLE, ALLOWED_ROLES,
    SAMPLE_QUERY_1, SAMPLE_QUERY_1_DESC,
    SAMPLE_QUERY_2, SAMPLE_QUERY_2_DESC,
    SAMPLE_QUERY_3, SAMPLE_QUERY_3_DESC,
    SAMPLE_QUERY_4, SAMPLE_QUERY_4_DESC,
    SAMPLE_QUERY_5, SAMPLE_QUERY_5_DESC,
    OWNER_TEAM, DATA_STEWARD_EMAIL, SLA_REFRESH_HOURS, USE_CASES, TAGS
) VALUES 
(
    'DP-WD-WORKFORCE-001',
    'Workday Workforce Analytics',
    'Workforce composition analytics from Workday HCM. Provides headcount, tenure, and organizational distribution metrics by department, job family, and location. No individual employee identifiers.',
    'Enables strategic workforce planning, identifies flight risks through tenure patterns, and supports organizational design decisions. Essential for HR business partners and leadership.',
    'v1.0',
    'WORKDAY', 'SEM_DEV', 'MARKETPLACE', 'DP_WORKDAY_WORKFORCE', 'SECURE_VIEW',
    'HR', 'CONFIDENTIAL', FALSE, 'No employee names, IDs, or individual data. Aggregated by organizational dimensions only.',
    'WORKFORCE_CONSUMER', ARRAY_CONSTRUCT('WORKFORCE_CONSUMER', 'MARKETPLACE_CONSUMER', 'DATA_ADMIN'),
    'SELECT DEPARTMENT, SUM(ACTIVE_EMPLOYEES) as HEADCOUNT FROM SEM_DEV.MARKETPLACE.DP_WORKDAY_WORKFORCE GROUP BY 1 ORDER BY 2 DESC',
    'Current headcount by department for org chart',
    'SELECT JOB_LEVEL, SUM(HEADCOUNT) as TOTAL, AVG(AVG_TENURE_YEARS) as AVG_TENURE FROM SEM_DEV.MARKETPLACE.DP_WORKDAY_WORKFORCE GROUP BY 1 ORDER BY 1',
    'Tenure analysis by job level for retention strategy',
    'SELECT COUNTRY, WORK_LOCATION, SUM(ACTIVE_EMPLOYEES) as EMPLOYEES FROM SEM_DEV.MARKETPLACE.DP_WORKDAY_WORKFORCE GROUP BY 1, 2 ORDER BY 3 DESC',
    'Geographic distribution for location strategy',
    'SELECT WORKER_TYPE, SUM(HEADCOUNT) as COUNT, AVG(AVG_FTE) as AVG_FTE FROM SEM_DEV.MARKETPLACE.DP_WORKDAY_WORKFORCE GROUP BY 1',
    'Employee vs contractor mix analysis',
    'SELECT JOB_FAMILY, SUM(ACTIVE_EMPLOYEES) as ACTIVE, SUM(TERMINATED_EMPLOYEES) as TERMED FROM SEM_DEV.MARKETPLACE.DP_WORKDAY_WORKFORCE GROUP BY 1 ORDER BY 2 DESC',
    'Attrition patterns by job family',
    'HR Analytics', 'hr-analytics@company.com', 4,
    ARRAY_CONSTRUCT('Workforce Planning', 'Org Design', 'Retention Analysis', 'Location Strategy'),
    ARRAY_CONSTRUCT('Workday', 'HR', 'Workforce', 'Headcount', 'HCM')
),
(
    'DP-WD-COMP-001',
    'Workday Compensation Bands',
    'Compensation band statistics from Workday HCM. Provides pay range metrics by grade and level with statistical distribution. Minimum 5 employees per band for privacy protection.',
    'Supports market competitiveness analysis, pay equity assessments, and compensation planning. Critical for total rewards and HR leadership.',
    'v1.0',
    'WORKDAY', 'SEM_DEV', 'MARKETPLACE', 'DP_WORKDAY_COMPENSATION', 'SECURE_VIEW',
    'COMPENSATION', 'RESTRICTED', FALSE, 'No individual salaries. Aggregated bands with minimum 5 employees. Audited access.',
    'WORKFORCE_CONSUMER', ARRAY_CONSTRUCT('WORKFORCE_CONSUMER', 'DATA_ADMIN'),
    'SELECT PAY_GRADE, AVG_BASE_PAY, MEDIAN_BASE_PAY, MIN_BASE_PAY, MAX_BASE_PAY FROM SEM_DEV.MARKETPLACE.DP_WORKDAY_COMPENSATION ORDER BY PAY_GRADE',
    'Compensation band ranges for benchmarking',
    'SELECT JOB_LEVEL, AVG(AVG_BASE_PAY) as AVG_PAY FROM SEM_DEV.MARKETPLACE.DP_WORKDAY_COMPENSATION GROUP BY 1 ORDER BY 1',
    'Average pay progression by level',
    'SELECT PAY_GRADE, STDDEV_BASE_PAY / NULLIF(AVG_BASE_PAY, 0) as PAY_VARIABILITY FROM SEM_DEV.MARKETPLACE.DP_WORKDAY_COMPENSATION WHERE EMPLOYEE_COUNT >= 10',
    'Pay equity indicator by grade (low variability = equity)',
    'Total Rewards', 'compensation@company.com', 24,
    ARRAY_CONSTRUCT('Comp Planning', 'Pay Equity', 'Market Analysis', 'Budget Planning'),
    ARRAY_CONSTRUCT('Workday', 'HR', 'Compensation', 'Salary', 'Pay')
);

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 8: SERVICENOW ITSM DATA PRODUCTS
-- ═══════════════════════════════════════════════════════════════════════════

-- -----------------------------------------------------------------------------
-- ServiceNow Incident Analytics
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SECURE VIEW DP_SERVICENOW_INCIDENTS AS
SELECT
    PRIORITY,
    CATEGORY,
    SUBCATEGORY,
    STATE,
    ASSIGNMENT_GROUP,
    EXTRACT(YEAR FROM OPENED_AT) AS OPENED_YEAR,
    EXTRACT(MONTH FROM OPENED_AT) AS OPENED_MONTH,
    COUNT(*) AS INCIDENT_COUNT,
    SUM(CASE WHEN STATE = 'Resolved' THEN 1 ELSE 0 END) AS RESOLVED_COUNT,
    SUM(CASE WHEN STATE = 'Closed' THEN 1 ELSE 0 END) AS CLOSED_COUNT,
    SUM(CASE WHEN PRIORITY IN ('1', '2', 'P1', 'P2', 'Critical', 'High') THEN 1 ELSE 0 END) AS HIGH_PRIORITY_COUNT,
    ROUND(AVG(TIME_TO_RESOLVE_MINUTES), 0) AS AVG_RESOLUTION_MINUTES,
    ROUND(MEDIAN(TIME_TO_RESOLVE_MINUTES), 0) AS MEDIAN_RESOLUTION_MINUTES,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.SERVICENOW.FACT_INCIDENTS
GROUP BY PRIORITY, CATEGORY, SUBCATEGORY, STATE, ASSIGNMENT_GROUP,
         EXTRACT(YEAR FROM OPENED_AT), EXTRACT(MONTH FROM OPENED_AT)
ORDER BY OPENED_YEAR DESC, OPENED_MONTH DESC;

COMMENT ON VIEW DP_SERVICENOW_INCIDENTS IS 'ServiceNow Incident Analytics: IT incident metrics by priority, category, and assignment group. Use for SLA monitoring, capacity planning, and service improvement. Updated hourly.';

GRANT SELECT ON VIEW DP_SERVICENOW_INCIDENTS TO ROLE ITSM_CONSUMER;
GRANT SELECT ON VIEW DP_SERVICENOW_INCIDENTS TO ROLE MARKETPLACE_CONSUMER;

-- -----------------------------------------------------------------------------
-- ServiceNow Change Analytics
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SECURE VIEW DP_SERVICENOW_CHANGES AS
SELECT
    CHANGE_TYPE,
    RISK,
    STATE,
    CATEGORY,
    ASSIGNMENT_GROUP,
    EXTRACT(YEAR FROM PLANNED_START_DATE) AS CHANGE_YEAR,
    EXTRACT(QUARTER FROM PLANNED_START_DATE) AS CHANGE_QUARTER,
    COUNT(*) AS CHANGE_COUNT,
    SUM(CASE WHEN STATE = 'Closed' AND CLOSE_CODE = 'Successful' THEN 1 ELSE 0 END) AS SUCCESSFUL_COUNT,
    SUM(CASE WHEN STATE = 'Closed' AND CLOSE_CODE != 'Successful' THEN 1 ELSE 0 END) AS FAILED_COUNT,
    ROUND(100.0 * SUM(CASE WHEN STATE = 'Closed' AND CLOSE_CODE = 'Successful' THEN 1 ELSE 0 END) / 
          NULLIF(SUM(CASE WHEN STATE = 'Closed' THEN 1 ELSE 0 END), 0), 2) AS SUCCESS_RATE_PCT,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.SERVICENOW.FACT_CHANGES
GROUP BY CHANGE_TYPE, RISK, STATE, CATEGORY, ASSIGNMENT_GROUP,
         EXTRACT(YEAR FROM PLANNED_START_DATE), EXTRACT(QUARTER FROM PLANNED_START_DATE)
ORDER BY CHANGE_YEAR DESC, CHANGE_QUARTER DESC;

COMMENT ON VIEW DP_SERVICENOW_CHANGES IS 'ServiceNow Change Analytics: IT change management metrics by type, risk, and outcome. Use for change success rate tracking, risk assessment, and ITIL compliance. Updated every 4 hours.';

GRANT SELECT ON VIEW DP_SERVICENOW_CHANGES TO ROLE ITSM_CONSUMER;
GRANT SELECT ON VIEW DP_SERVICENOW_CHANGES TO ROLE MARKETPLACE_CONSUMER;

-- -----------------------------------------------------------------------------
-- ServiceNow Problem Analytics
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SECURE VIEW DP_SERVICENOW_PROBLEMS AS
SELECT
    PRIORITY,
    STATE,
    CATEGORY,
    ROOT_CAUSE_CATEGORY,
    ASSIGNMENT_GROUP,
    EXTRACT(YEAR FROM OPENED_AT) AS OPENED_YEAR,
    EXTRACT(QUARTER FROM OPENED_AT) AS OPENED_QUARTER,
    COUNT(*) AS PROBLEM_COUNT,
    COUNT(DISTINCT RELATED_INCIDENT_COUNT) AS RELATED_INCIDENTS,
    SUM(CASE WHEN ROOT_CAUSE_IDENTIFIED THEN 1 ELSE 0 END) AS RCA_COMPLETE,
    ROUND(100.0 * SUM(CASE WHEN ROOT_CAUSE_IDENTIFIED THEN 1 ELSE 0 END) / COUNT(*), 2) AS RCA_RATE_PCT,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.SERVICENOW.FACT_PROBLEMS
GROUP BY PRIORITY, STATE, CATEGORY, ROOT_CAUSE_CATEGORY, ASSIGNMENT_GROUP,
         EXTRACT(YEAR FROM OPENED_AT), EXTRACT(QUARTER FROM OPENED_AT)
ORDER BY OPENED_YEAR DESC, OPENED_QUARTER DESC;

COMMENT ON VIEW DP_SERVICENOW_PROBLEMS IS 'ServiceNow Problem Analytics: Problem management metrics with root cause analysis rates. Use for trend identification, proactive problem management, and service reliability improvement. Updated every 4 hours.';

GRANT SELECT ON VIEW DP_SERVICENOW_PROBLEMS TO ROLE ITSM_CONSUMER;
GRANT SELECT ON VIEW DP_SERVICENOW_PROBLEMS TO ROLE MARKETPLACE_CONSUMER;

-- Register ServiceNow products in catalog
INSERT INTO GOVERNANCE.OBSERVABILITY.DATA_PRODUCT_CATALOG (
    PRODUCT_ID, PRODUCT_NAME, PRODUCT_DESCRIPTION, BUSINESS_VALUE, PRODUCT_VERSION,
    SOURCE_SYSTEM, DATABASE_NAME, SCHEMA_NAME, OBJECT_NAME, OBJECT_TYPE,
    DOMAIN, DATA_CLASSIFICATION, CONTAINS_PII, COMPLIANCE_NOTES,
    CONSUMER_ROLE, ALLOWED_ROLES,
    SAMPLE_QUERY_1, SAMPLE_QUERY_1_DESC,
    SAMPLE_QUERY_2, SAMPLE_QUERY_2_DESC,
    SAMPLE_QUERY_3, SAMPLE_QUERY_3_DESC,
    SAMPLE_QUERY_4, SAMPLE_QUERY_4_DESC,
    SAMPLE_QUERY_5, SAMPLE_QUERY_5_DESC,
    OWNER_TEAM, DATA_STEWARD_EMAIL, SLA_REFRESH_HOURS, USE_CASES, TAGS
) VALUES 
(
    'DP-SN-INCIDENTS-001',
    'ServiceNow Incident Analytics',
    'IT service incident analytics from ServiceNow ITSM. Provides incident volumes, resolution times, and SLA performance by priority, category, and assignment group. Real-time operational intelligence for IT leadership.',
    'Enables proactive service management, identifies chronic issues, and supports data-driven staffing decisions. Critical for IT operations and service desk management.',
    'v1.0',
    'SERVICENOW', 'SEM_DEV', 'MARKETPLACE', 'DP_SERVICENOW_INCIDENTS', 'SECURE_VIEW',
    'ITSM', 'INTERNAL', FALSE, 'No user identifiers or ticket details. Aggregated operational metrics only.',
    'ITSM_CONSUMER', ARRAY_CONSTRUCT('ITSM_CONSUMER', 'MARKETPLACE_CONSUMER', 'DATA_ADMIN'),
    'SELECT OPENED_YEAR, OPENED_MONTH, SUM(INCIDENT_COUNT) as VOLUME, AVG(AVG_RESOLUTION_MINUTES) as AVG_MTTR FROM SEM_DEV.MARKETPLACE.DP_SERVICENOW_INCIDENTS GROUP BY 1, 2 ORDER BY 1 DESC, 2 DESC',
    'Monthly incident volume and MTTR trend for SLA reporting',
    'SELECT PRIORITY, SUM(INCIDENT_COUNT) as COUNT, AVG(AVG_RESOLUTION_MINUTES) as AVG_RESOLUTION FROM SEM_DEV.MARKETPLACE.DP_SERVICENOW_INCIDENTS WHERE OPENED_YEAR = YEAR(CURRENT_DATE()) GROUP BY 1 ORDER BY 1',
    'YTD incidents by priority for severity analysis',
    'SELECT ASSIGNMENT_GROUP, SUM(INCIDENT_COUNT) as VOLUME, SUM(HIGH_PRIORITY_COUNT) as P1_P2 FROM SEM_DEV.MARKETPLACE.DP_SERVICENOW_INCIDENTS WHERE OPENED_YEAR = YEAR(CURRENT_DATE()) GROUP BY 1 ORDER BY 2 DESC LIMIT 10',
    'Top 10 assignment groups by volume for capacity planning',
    'SELECT CATEGORY, SUM(INCIDENT_COUNT) as COUNT FROM SEM_DEV.MARKETPLACE.DP_SERVICENOW_INCIDENTS WHERE OPENED_YEAR = YEAR(CURRENT_DATE()) GROUP BY 1 ORDER BY 2 DESC',
    'Incident distribution by category for problem trends',
    'SELECT OPENED_YEAR, OPENED_MONTH, SUM(RESOLVED_COUNT) / NULLIF(SUM(INCIDENT_COUNT), 0) as RESOLUTION_RATE FROM SEM_DEV.MARKETPLACE.DP_SERVICENOW_INCIDENTS GROUP BY 1, 2 ORDER BY 1, 2',
    'Resolution rate trend for service improvement tracking',
    'IT Operations', 'it-analytics@company.com', 1,
    ARRAY_CONSTRUCT('SLA Dashboards', 'Capacity Planning', 'Service Improvement', 'Executive Reporting'),
    ARRAY_CONSTRUCT('ServiceNow', 'ITSM', 'Incidents', 'Help Desk', 'ITIL')
),
(
    'DP-SN-CHANGES-001',
    'ServiceNow Change Analytics',
    'IT change management analytics from ServiceNow. Provides change volumes, success rates, and risk distribution. Supports ITIL change management processes and CAB decision-making.',
    'Reduces change-related incidents through data-driven risk assessment. Improves change success rates and supports continuous improvement in IT service delivery.',
    'v1.0',
    'SERVICENOW', 'SEM_DEV', 'MARKETPLACE', 'DP_SERVICENOW_CHANGES', 'SECURE_VIEW',
    'ITSM', 'INTERNAL', FALSE, 'No change details or implementer information. Aggregated metrics only.',
    'ITSM_CONSUMER', ARRAY_CONSTRUCT('ITSM_CONSUMER', 'MARKETPLACE_CONSUMER', 'DATA_ADMIN'),
    'SELECT CHANGE_YEAR, CHANGE_QUARTER, SUM(CHANGE_COUNT) as CHANGES, AVG(SUCCESS_RATE_PCT) as SUCCESS_RATE FROM SEM_DEV.MARKETPLACE.DP_SERVICENOW_CHANGES GROUP BY 1, 2 ORDER BY 1 DESC, 2 DESC',
    'Quarterly change volume and success rate for CAB review',
    'SELECT RISK, SUM(CHANGE_COUNT) as COUNT, AVG(SUCCESS_RATE_PCT) as SUCCESS_RATE FROM SEM_DEV.MARKETPLACE.DP_SERVICENOW_CHANGES GROUP BY 1 ORDER BY 1',
    'Success rate by risk level for risk assessment calibration',
    'SELECT CHANGE_TYPE, SUM(SUCCESSFUL_COUNT) as SUCCESS, SUM(FAILED_COUNT) as FAILED FROM SEM_DEV.MARKETPLACE.DP_SERVICENOW_CHANGES GROUP BY 1',
    'Change outcomes by type for process improvement',
    'IT Change Management', 'change-management@company.com', 4,
    ARRAY_CONSTRUCT('CAB Reporting', 'Risk Assessment', 'Change Success', 'ITIL Compliance'),
    ARRAY_CONSTRUCT('ServiceNow', 'ITSM', 'Changes', 'CAB', 'ITIL')
),
(
    'DP-SN-PROBLEMS-001',
    'ServiceNow Problem Analytics',
    'IT problem management analytics from ServiceNow. Provides problem trends, root cause analysis completion rates, and related incident impact. Supports proactive problem management and service reliability.',
    'Drives reduction in recurring incidents through systematic root cause analysis. Enables proactive IT operations and improves overall service stability.',
    'v1.0',
    'SERVICENOW', 'SEM_DEV', 'MARKETPLACE', 'DP_SERVICENOW_PROBLEMS', 'SECURE_VIEW',
    'ITSM', 'INTERNAL', FALSE, 'No problem details or technical information. Aggregated metrics only.',
    'ITSM_CONSUMER', ARRAY_CONSTRUCT('ITSM_CONSUMER', 'MARKETPLACE_CONSUMER', 'DATA_ADMIN'),
    'SELECT OPENED_YEAR, OPENED_QUARTER, SUM(PROBLEM_COUNT) as PROBLEMS, AVG(RCA_RATE_PCT) as RCA_COMPLETION FROM SEM_DEV.MARKETPLACE.DP_SERVICENOW_PROBLEMS GROUP BY 1, 2 ORDER BY 1 DESC, 2 DESC',
    'Quarterly problem volume and RCA completion for management',
    'SELECT ROOT_CAUSE_CATEGORY, SUM(PROBLEM_COUNT) as COUNT FROM SEM_DEV.MARKETPLACE.DP_SERVICENOW_PROBLEMS WHERE ROOT_CAUSE_CATEGORY IS NOT NULL GROUP BY 1 ORDER BY 2 DESC',
    'Root cause distribution for systemic improvement',
    'SELECT PRIORITY, SUM(RELATED_INCIDENTS) as IMPACT FROM SEM_DEV.MARKETPLACE.DP_SERVICENOW_PROBLEMS GROUP BY 1 ORDER BY 1',
    'Incident impact by problem priority for prioritization',
    'IT Problem Management', 'problem-management@company.com', 4,
    ARRAY_CONSTRUCT('Problem Trends', 'RCA Tracking', 'Service Reliability', 'Proactive Management'),
    ARRAY_CONSTRUCT('ServiceNow', 'ITSM', 'Problems', 'RCA', 'ITIL')
);

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 9: DATA PRODUCT CATALOG VIEW
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW SEM_DEV.MARKETPLACE.VW_DATA_PRODUCT_CATALOG AS
SELECT 
    PRODUCT_ID,
    PRODUCT_NAME,
    PRODUCT_DESCRIPTION,
    BUSINESS_VALUE,
    SOURCE_SYSTEM,
    DOMAIN,
    OBJECT_NAME AS VIEW_NAME,
    DATA_CLASSIFICATION,
    CONTAINS_PII,
    COMPLIANCE_NOTES,
    CONSUMER_ROLE,
    ARRAY_TO_STRING(ALLOWED_ROLES, ', ') AS ALLOWED_ROLES,
    SAMPLE_QUERY_1,
    SAMPLE_QUERY_1_DESC,
    SAMPLE_QUERY_2,
    SAMPLE_QUERY_2_DESC,
    SAMPLE_QUERY_3,
    SAMPLE_QUERY_3_DESC,
    OWNER_TEAM,
    DATA_STEWARD_EMAIL,
    SLA_REFRESH_HOURS,
    ARRAY_TO_STRING(USE_CASES, ', ') AS USE_CASES,
    ARRAY_TO_STRING(TAGS, ', ') AS TAGS,
    STATUS,
    CREATED_AT
FROM GOVERNANCE.OBSERVABILITY.DATA_PRODUCT_CATALOG
WHERE STATUS = 'ACTIVE'
ORDER BY SOURCE_SYSTEM, DOMAIN;

GRANT SELECT ON VIEW SEM_DEV.MARKETPLACE.VW_DATA_PRODUCT_CATALOG TO ROLE ERP_CONSUMER;
GRANT SELECT ON VIEW SEM_DEV.MARKETPLACE.VW_DATA_PRODUCT_CATALOG TO ROLE CRM_CONSUMER;
GRANT SELECT ON VIEW SEM_DEV.MARKETPLACE.VW_DATA_PRODUCT_CATALOG TO ROLE HEALTHCARE_CONSUMER;
GRANT SELECT ON VIEW SEM_DEV.MARKETPLACE.VW_DATA_PRODUCT_CATALOG TO ROLE WORKFORCE_CONSUMER;
GRANT SELECT ON VIEW SEM_DEV.MARKETPLACE.VW_DATA_PRODUCT_CATALOG TO ROLE ITSM_CONSUMER;
GRANT SELECT ON VIEW SEM_DEV.MARKETPLACE.VW_DATA_PRODUCT_CATALOG TO ROLE MARKETPLACE_CONSUMER;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 10: ADDITIONAL GRANTS AND VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

-- Grant future views
GRANT SELECT ON FUTURE VIEWS IN SCHEMA SEM_DEV.MARKETPLACE TO ROLE ERP_CONSUMER;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA SEM_DEV.MARKETPLACE TO ROLE CRM_CONSUMER;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA SEM_DEV.MARKETPLACE TO ROLE HEALTHCARE_CONSUMER;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA SEM_DEV.MARKETPLACE TO ROLE WORKFORCE_CONSUMER;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA SEM_DEV.MARKETPLACE TO ROLE ITSM_CONSUMER;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA SEM_DEV.MARKETPLACE TO ROLE MARKETPLACE_CONSUMER;

-- Also grant to existing business roles
GRANT USAGE ON SCHEMA SEM_DEV.MARKETPLACE TO ROLE ANALYST;
GRANT USAGE ON SCHEMA SEM_DEV.MARKETPLACE TO ROLE MANAGER;
GRANT USAGE ON SCHEMA SEM_DEV.MARKETPLACE TO ROLE VIEWER;
GRANT SELECT ON ALL VIEWS IN SCHEMA SEM_DEV.MARKETPLACE TO ROLE ANALYST;
GRANT SELECT ON ALL VIEWS IN SCHEMA SEM_DEV.MARKETPLACE TO ROLE MANAGER;
GRANT SELECT ON ALL VIEWS IN SCHEMA SEM_DEV.MARKETPLACE TO ROLE VIEWER;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT '✓ Data Marketplace with Domain Roles Created' AS STATUS;

SELECT 
    'Domain Consumer Roles Created:' AS INFO,
    'ERP_CONSUMER - SAP and Oracle ERP data' AS ROLE_1,
    'CRM_CONSUMER - Salesforce CRM data' AS ROLE_2,
    'HEALTHCARE_CONSUMER - FHIR clinical data (HIPAA compliant)' AS ROLE_3,
    'WORKFORCE_CONSUMER - Workday HR data' AS ROLE_4,
    'ITSM_CONSUMER - ServiceNow IT data' AS ROLE_5,
    'MARKETPLACE_CONSUMER - General access to all domains' AS ROLE_6;

SELECT 
    'All roles granted to STEVE for demo purposes' AS DEMO_NOTE;

-- Show what was created
SHOW ROLES LIKE '%CONSUMER';
SHOW VIEWS IN SCHEMA SEM_DEV.MARKETPLACE;

SELECT 
    SOURCE_SYSTEM,
    COUNT(*) AS PRODUCT_COUNT,
    LISTAGG(PRODUCT_NAME, ', ') WITHIN GROUP (ORDER BY PRODUCT_NAME) AS PRODUCTS
FROM GOVERNANCE.OBSERVABILITY.DATA_PRODUCT_CATALOG
WHERE STATUS = 'ACTIVE'
GROUP BY SOURCE_SYSTEM
ORDER BY SOURCE_SYSTEM;

-- ═══════════════════════════════════════════════════════════════════════════
-- USAGE INSTRUCTIONS
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- DEMO: Switch roles to see different data access
--   USE ROLE ERP_CONSUMER;
--   SELECT * FROM SEM_DEV.MARKETPLACE.DP_SAP_SALES_ANALYTICS;
--   
--   USE ROLE CRM_CONSUMER;
--   SELECT * FROM SEM_DEV.MARKETPLACE.DP_SALESFORCE_PIPELINE;
--   
--   USE ROLE HEALTHCARE_CONSUMER;
--   SELECT * FROM SEM_DEV.MARKETPLACE.DP_FHIR_CLINICAL_ENCOUNTERS;
--
-- BROWSE CATALOG:
--   SELECT PRODUCT_NAME, SOURCE_SYSTEM, DOMAIN, SAMPLE_QUERY_1_DESC 
--   FROM SEM_DEV.MARKETPLACE.VW_DATA_PRODUCT_CATALOG;
--
-- TRY SAMPLE QUERIES:
--   SELECT SAMPLE_QUERY_1, SAMPLE_QUERY_1_DESC 
--   FROM SEM_DEV.MARKETPLACE.VW_DATA_PRODUCT_CATALOG 
--   WHERE SOURCE_SYSTEM = 'SALESFORCE';
--
-- ═══════════════════════════════════════════════════════════════════════════
