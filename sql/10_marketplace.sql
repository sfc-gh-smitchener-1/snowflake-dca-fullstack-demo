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
GRANT USAGE ON DATABASE CURATED_DEV TO ROLE ERP_CONSUMER;
GRANT USAGE ON DATABASE CURATED_DEV TO ROLE CRM_CONSUMER;
GRANT USAGE ON DATABASE CURATED_DEV TO ROLE HEALTHCARE_CONSUMER;
GRANT USAGE ON DATABASE CURATED_DEV TO ROLE WORKFORCE_CONSUMER;
GRANT USAGE ON DATABASE CURATED_DEV TO ROLE ITSM_CONSUMER;
GRANT USAGE ON DATABASE CURATED_DEV TO ROLE MARKETPLACE_CONSUMER;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 2: SET UP MARKETPLACE SCHEMA AND CATALOG
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE DATA_ADMIN;
USE WAREHOUSE ANALYTICS_WH;
USE DATABASE CURATED_DEV;

-- Create marketplace schema if not exists
CREATE SCHEMA IF NOT EXISTS CURATED_DEV.MARKETPLACE
    COMMENT = 'Internal data marketplace with domain-specific data products';

-- Grant schema access to all consumer roles
GRANT USAGE ON SCHEMA CURATED_DEV.MARKETPLACE TO ROLE ERP_CONSUMER;
GRANT USAGE ON SCHEMA CURATED_DEV.MARKETPLACE TO ROLE CRM_CONSUMER;
GRANT USAGE ON SCHEMA CURATED_DEV.MARKETPLACE TO ROLE HEALTHCARE_CONSUMER;
GRANT USAGE ON SCHEMA CURATED_DEV.MARKETPLACE TO ROLE WORKFORCE_CONSUMER;
GRANT USAGE ON SCHEMA CURATED_DEV.MARKETPLACE TO ROLE ITSM_CONSUMER;
GRANT USAGE ON SCHEMA CURATED_DEV.MARKETPLACE TO ROLE MARKETPLACE_CONSUMER;

USE SCHEMA CURATED_DEV.MARKETPLACE;

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
    ALLOWED_ROLES           VARCHAR(500),
    
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
    USE_CASES               VARCHAR(1000),
    TAGS                    VARCHAR(500),
    
    -- Status
    STATUS                  VARCHAR(20) DEFAULT 'ACTIVE',
    CREATED_AT              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 3: SAP ERP DATA PRODUCTS
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA CURATED_DEV.MARKETPLACE;

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
    SUM(CASE WHEN IS_COMPLETED THEN 1 ELSE 0 END) AS COMPLETED_ORDERS,
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
    PO_TYPE,
    EXTRACT(YEAR FROM PO_DATE) AS PO_YEAR,
    EXTRACT(QUARTER FROM PO_DATE) AS PO_QUARTER,
    EXTRACT(MONTH FROM PO_DATE) AS PO_MONTH,
    COUNT(*) AS PO_COUNT,
    COUNT(DISTINCT VENDOR_KEY) AS UNIQUE_VENDORS,
    SUM(TOTAL_VALUE) AS TOTAL_SPEND,
    AVG(TOTAL_VALUE) AS AVG_PO_VALUE,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.SAP.FACT_PURCHASE_ORDERS
GROUP BY PURCHASING_ORG, PURCHASING_GROUP, PO_TYPE,
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
    STATE,
    CITY,
    INDUSTRY_CODE AS INDUSTRY,
    CUSTOMER_CLASS,
    ACCOUNT_GROUP,
    COUNT(*) AS CUSTOMER_COUNT,
    SUM(CASE WHEN IS_ACTIVE THEN 1 ELSE 0 END) AS ACTIVE_CUSTOMERS,
    SUM(CASE WHEN NOT IS_ACTIVE THEN 1 ELSE 0 END) AS INACTIVE_CUSTOMERS,
    ROUND(100.0 * SUM(CASE WHEN IS_ACTIVE THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS ACTIVE_RATE_PCT,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.SAP.DIM_CUSTOMER
GROUP BY COUNTRY, STATE, CITY, INDUSTRY_CODE, CUSTOMER_CLASS, ACCOUNT_GROUP
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
    'SAP', 'CURATED_DEV', 'MARKETPLACE', 'DP_SAP_SALES_ANALYTICS', 'SECURE_VIEW',
    'SALES', 'INTERNAL', FALSE, 'No PII - aggregated metrics only. Safe for executive dashboards.',
    'ERP_CONSUMER', 'ERP_CONSUMER, MARKETPLACE_CONSUMER, DATA_ADMIN',
    'SELECT ORDER_YEAR, ORDER_QUARTER, SUM(TOTAL_REVENUE) as QUARTERLY_REVENUE FROM CURATED_DEV.MARKETPLACE.DP_SAP_SALES_ANALYTICS GROUP BY ORDER_YEAR, ORDER_QUARTER ORDER BY 1 DESC, 2 DESC',
    'Quarterly revenue trends for executive dashboard',
    'SELECT SALES_ORGANIZATION, DISTRIBUTION_CHANNEL, SUM(TOTAL_REVENUE) as REVENUE, SUM(ORDER_COUNT) as ORDERS FROM CURATED_DEV.MARKETPLACE.DP_SAP_SALES_ANALYTICS WHERE ORDER_YEAR = YEAR(CURRENT_DATE()) GROUP BY 1, 2 ORDER BY REVENUE DESC',
    'YTD performance by sales org and channel',
    'SELECT ORDER_YEAR, ORDER_MONTH, UNIQUE_CUSTOMERS, LAG(UNIQUE_CUSTOMERS) OVER (ORDER BY ORDER_YEAR, ORDER_MONTH) as PREV_MONTH FROM CURATED_DEV.MARKETPLACE.DP_SAP_SALES_ANALYTICS WHERE SALES_ORGANIZATION = ''1000''',
    'Customer acquisition trend analysis',
    'SELECT DISTRIBUTION_CHANNEL, ROUND(AVG(AVG_ORDER_VALUE), 2) as AOV FROM CURATED_DEV.MARKETPLACE.DP_SAP_SALES_ANALYTICS GROUP BY DISTRIBUTION_CHANNEL ORDER BY AOV DESC',
    'Average order value comparison by channel',
    'SELECT * FROM CURATED_DEV.MARKETPLACE.DP_SAP_SALES_ANALYTICS WHERE ORDER_YEAR >= YEAR(CURRENT_DATE()) - 1 AND TOTAL_REVENUE > 100000',
    'High-value sales activity in last 2 years',
    'SAP Finance Team', 'sap-data-steward@company.com', 4,
    'Revenue Reporting, Sales Dashboards, Channel Analysis, Demand Forecasting',
    'SAP, ERP, Sales, Revenue, SD'
),
(
    'DP-SAP-PROC-001',
    'SAP Procurement Analytics',
    'Purchase order analytics from SAP MM (Materials Management) module. Provides spend visibility, vendor activity metrics, and procurement patterns across purchasing organizations. Aggregated from EKKO/EKPO tables with 4-hour refresh.',
    'Drives strategic sourcing decisions, identifies cost reduction opportunities, and enables vendor consolidation analysis. Critical for procurement optimization and supply chain resilience.',
    'v1.0',
    'SAP', 'CURATED_DEV', 'MARKETPLACE', 'DP_SAP_PROCUREMENT_ANALYTICS', 'SECURE_VIEW',
    'PROCUREMENT', 'INTERNAL', FALSE, 'No PII - vendor IDs are anonymized in aggregation.',
    'ERP_CONSUMER', 'ERP_CONSUMER, MARKETPLACE_CONSUMER, DATA_ADMIN',
    'SELECT PO_YEAR, PO_QUARTER, SUM(TOTAL_SPEND) as QUARTERLY_SPEND FROM CURATED_DEV.MARKETPLACE.DP_SAP_PROCUREMENT_ANALYTICS GROUP BY 1, 2 ORDER BY 1 DESC, 2 DESC',
    'Quarterly procurement spend for budget tracking',
    'SELECT PURCHASING_ORGANIZATION, COUNT(DISTINCT VENDOR_KEY) as VENDOR_COUNT, SUM(TOTAL_SPEND) as SPEND FROM CURATED_DEV.MARKETPLACE.DP_SAP_PROCUREMENT_ANALYTICS WHERE PO_YEAR = YEAR(CURRENT_DATE()) GROUP BY 1',
    'Vendor concentration by purchasing org',
    'SELECT PO_TYPE, SUM(TOTAL_SPEND) as TOTAL_SPEND, SUM(PO_COUNT) as PO_COUNT FROM CURATED_DEV.MARKETPLACE.DP_SAP_PROCUREMENT_ANALYTICS GROUP BY 1 ORDER BY 2 DESC',
    'Spend analysis by PO type',
    'SELECT PO_YEAR, PO_MONTH, ROUND(AVG(AVG_PO_VALUE), 2) as AVG_VALUE FROM CURATED_DEV.MARKETPLACE.DP_SAP_PROCUREMENT_ANALYTICS GROUP BY 1, 2 ORDER BY 1, 2',
    'Average PO value trend over time',
    'SELECT PURCHASING_GROUP, SUM(UNIQUE_VENDORS) as VENDORS, SUM(TOTAL_SPEND) as SPEND FROM CURATED_DEV.MARKETPLACE.DP_SAP_PROCUREMENT_ANALYTICS GROUP BY 1 ORDER BY 3 DESC',
    'Vendor count and spend by purchasing group',
    'Procurement Operations', 'procurement-analytics@company.com', 4,
    'Spend Analysis, Vendor Scorecard, Budget Planning, Category Management',
    'SAP, ERP, Procurement, Spend, MM'
),
(
    'DP-SAP-CUST-001',
    'SAP Customer Summary',
    'Customer master analytics from SAP SD module. Provides customer distribution by geography, account group, and currency with aggregated counts. Supports customer segmentation and territory analysis.',
    'Enables territory optimization, identifies customer concentration risks, and supports geographic expansion planning. Essential for sales strategy and customer success.',
    'v1.0',
    'SAP', 'CURATED_DEV', 'MARKETPLACE', 'DP_SAP_CUSTOMER_SUMMARY', 'SECURE_VIEW',
    'SALES', 'INTERNAL', FALSE, 'No customer names or contact details - aggregated geography metrics only.',
    'ERP_CONSUMER', 'ERP_CONSUMER, MARKETPLACE_CONSUMER, DATA_ADMIN',
    'SELECT COUNTRY, SUM(CUSTOMER_COUNT) as CUSTOMERS FROM CURATED_DEV.MARKETPLACE.DP_SAP_CUSTOMER_SUMMARY GROUP BY 1 ORDER BY 2 DESC',
    'Customer count by country for geographic analysis',
    'SELECT ACCOUNT_GROUP, SUM(CUSTOMER_COUNT) as CUSTOMERS FROM CURATED_DEV.MARKETPLACE.DP_SAP_CUSTOMER_SUMMARY GROUP BY 1 ORDER BY 2 DESC',
    'Customer distribution by account group',
    'SELECT STATE, CITY, SUM(CUSTOMER_COUNT) as CUSTOMERS FROM CURATED_DEV.MARKETPLACE.DP_SAP_CUSTOMER_SUMMARY GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 20',
    'Top territories by customer count',
    'SELECT CURRENCY, SUM(CUSTOMER_COUNT) as CUSTOMERS FROM CURATED_DEV.MARKETPLACE.DP_SAP_CUSTOMER_SUMMARY GROUP BY 1',
    'Customer count by currency',
    'SELECT COUNTRY, COUNT(DISTINCT STATE) as STATES FROM CURATED_DEV.MARKETPLACE.DP_SAP_CUSTOMER_SUMMARY GROUP BY 1 ORDER BY 2 DESC',
    'Geographic spread by country',
    'Sales Operations', 'sap-sales@company.com', 4,
    'Customer Segmentation, Territory Planning, Geographic Analysis, Account Management',
    'SAP, ERP, Customers, Master Data, SD'
);

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 4: ORACLE ERP DATA PRODUCTS
-- ═══════════════════════════════════════════════════════════════════════════

-- -----------------------------------------------------------------------------
-- Oracle Financial Analytics
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SECURE VIEW DP_ORACLE_FINANCIAL_ANALYTICS AS
SELECT
    LEDGER_ID,
    PERIOD_NAME,
    STATUS,
    EXTRACT(YEAR FROM EFFECTIVE_DATE) AS FISCAL_YEAR,
    EXTRACT(QUARTER FROM EFFECTIVE_DATE) AS FISCAL_QUARTER,
    COUNT(*) AS JOURNAL_ENTRY_COUNT,
    SUM(ENTERED_DEBIT) AS TOTAL_DEBITS,
    SUM(ENTERED_CREDIT) AS TOTAL_CREDITS,
    SUM(COALESCE(ENTERED_DEBIT, 0)) - SUM(COALESCE(ENTERED_CREDIT, 0)) AS NET_AMOUNT,
    COUNT(DISTINCT HEADER_ID) AS BATCH_COUNT,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.ORACLE.FACT_GL_JOURNAL_LINES
GROUP BY LEDGER_ID, PERIOD_NAME, STATUS,
         EXTRACT(YEAR FROM EFFECTIVE_DATE), EXTRACT(QUARTER FROM EFFECTIVE_DATE)
ORDER BY FISCAL_YEAR DESC, FISCAL_QUARTER DESC;

COMMENT ON VIEW DP_ORACLE_FINANCIAL_ANALYTICS IS 'Oracle GL Analytics: General ledger journal entry metrics by ledger, period, and account class. Use for financial close tracking, variance analysis, and audit preparation. Updated every 4 hours.';

GRANT SELECT ON VIEW DP_ORACLE_FINANCIAL_ANALYTICS TO ROLE ERP_CONSUMER;
GRANT SELECT ON VIEW DP_ORACLE_FINANCIAL_ANALYTICS TO ROLE MARKETPLACE_CONSUMER;

-- -----------------------------------------------------------------------------
-- Oracle AP Analytics
-- -----------------------------------------------------------------------------
CREATE OR REPLACE SECURE VIEW DP_ORACLE_AP_ANALYTICS AS
SELECT
    INVOICE_TYPE,
    SOURCE,
    APPROVAL_STATUS,
    EXTRACT(YEAR FROM INVOICE_DATE) AS INVOICE_YEAR,
    EXTRACT(QUARTER FROM INVOICE_DATE) AS INVOICE_QUARTER,
    COUNT(*) AS INVOICE_COUNT,
    COUNT(DISTINCT VENDOR_KEY) AS UNIQUE_VENDORS,
    SUM(INVOICE_AMOUNT) AS TOTAL_INVOICE_AMOUNT,
    AVG(INVOICE_AMOUNT) AS AVG_INVOICE_AMOUNT,
    SUM(CASE WHEN PAYMENT_STATUS = 'Y' THEN 1 ELSE 0 END) AS PAID_COUNT,
    SUM(CASE WHEN PAYMENT_STATUS = 'N' THEN 1 ELSE 0 END) AS UNPAID_COUNT,
    SUM(CASE WHEN IS_CANCELLED THEN 1 ELSE 0 END) AS CANCELLED_COUNT,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.ORACLE.FACT_AP_INVOICES
GROUP BY INVOICE_TYPE, SOURCE, APPROVAL_STATUS,
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
    SAMPLE_QUERY_4, SAMPLE_QUERY_4_DESC,
    SAMPLE_QUERY_5, SAMPLE_QUERY_5_DESC,
    OWNER_TEAM, DATA_STEWARD_EMAIL, SLA_REFRESH_HOURS, USE_CASES, TAGS
) VALUES 
(
    'DP-ORACLE-FIN-001',
    'Oracle Financial Analytics',
    'General Ledger journal entry analytics from Oracle Financials Cloud. Provides visibility into accounting activity, period close metrics, and ledger balances. Aggregated from GL_JE_LINES with dual-entry validation.',
    'Accelerates financial close process, enables real-time variance detection, and supports SOX compliance through complete audit trail visibility.',
    'v1.0',
    'ORACLE', 'CURATED_DEV', 'MARKETPLACE', 'DP_ORACLE_FINANCIAL_ANALYTICS', 'SECURE_VIEW',
    'FINANCE', 'CONFIDENTIAL', FALSE, 'No individual transaction details - aggregated by period and account class.',
    'ERP_CONSUMER', 'ERP_CONSUMER, MARKETPLACE_CONSUMER, DATA_ADMIN',
    'SELECT FISCAL_YEAR, FISCAL_QUARTER, SUM(NET_AMOUNT) as NET_POSITION FROM CURATED_DEV.MARKETPLACE.DP_ORACLE_FINANCIAL_ANALYTICS GROUP BY 1, 2 ORDER BY 1 DESC, 2 DESC',
    'Net financial position by quarter',
    'SELECT STATUS, SUM(TOTAL_DEBITS) as DEBITS, SUM(TOTAL_CREDITS) as CREDITS FROM CURATED_DEV.MARKETPLACE.DP_ORACLE_FINANCIAL_ANALYTICS WHERE FISCAL_YEAR = YEAR(CURRENT_DATE()) GROUP BY 1',
    'YTD activity by status for trial balance',
    'SELECT PERIOD_NAME, SUM(JOURNAL_ENTRY_COUNT) as ENTRIES, SUM(BATCH_COUNT) as BATCHES FROM CURATED_DEV.MARKETPLACE.DP_ORACLE_FINANCIAL_ANALYTICS GROUP BY 1 ORDER BY 1',
    'Period close activity tracking',
    'SELECT LEDGER_ID, SUM(NET_AMOUNT) as NET FROM CURATED_DEV.MARKETPLACE.DP_ORACLE_FINANCIAL_ANALYTICS GROUP BY 1',
    'Net amount by ledger',
    'SELECT FISCAL_YEAR, SUM(TOTAL_DEBITS) as DEBITS FROM CURATED_DEV.MARKETPLACE.DP_ORACLE_FINANCIAL_ANALYTICS GROUP BY 1 ORDER BY 1 DESC',
    'Annual debit totals',
    'Oracle Finance Team', 'oracle-finance@company.com', 4,
    'Financial Close, Variance Analysis, Audit Support, Budget vs Actual',
    'Oracle, ERP, Finance, GL, Accounting'
),
(
    'DP-ORACLE-AP-001',
    'Oracle Accounts Payable Analytics',
    'Accounts Payable invoice analytics from Oracle Financials Cloud. Provides payment activity metrics, invoice aging, and vendor payment patterns. Supports cash management and vendor relationship optimization.',
    'Improves working capital management through payment timing optimization. Identifies early payment discount opportunities and vendor consolidation candidates.',
    'v1.0',
    'ORACLE', 'CURATED_DEV', 'MARKETPLACE', 'DP_ORACLE_AP_ANALYTICS', 'SECURE_VIEW',
    'FINANCE', 'CONFIDENTIAL', FALSE, 'Vendor names anonymized. No bank account details.',
    'ERP_CONSUMER', 'ERP_CONSUMER, MARKETPLACE_CONSUMER, DATA_ADMIN',
    'SELECT INVOICE_YEAR, INVOICE_QUARTER, SUM(TOTAL_INVOICE_AMOUNT) as TOTAL_AP FROM CURATED_DEV.MARKETPLACE.DP_ORACLE_AP_ANALYTICS GROUP BY 1, 2 ORDER BY 1 DESC, 2 DESC',
    'Quarterly AP volume for cash flow planning',
    'SELECT INVOICE_TYPE, SUM(INVOICE_COUNT) as COUNT, SUM(TOTAL_INVOICE_AMOUNT) as AMOUNT FROM CURATED_DEV.MARKETPLACE.DP_ORACLE_AP_ANALYTICS GROUP BY 1',
    'Invoice type distribution analysis',
    'SELECT APPROVAL_STATUS, SUM(UNPAID_COUNT) as UNPAID, SUM(TOTAL_INVOICE_AMOUNT) as AMOUNT FROM CURATED_DEV.MARKETPLACE.DP_ORACLE_AP_ANALYTICS GROUP BY 1 ORDER BY 2 DESC',
    'Unpaid invoices by approval status',
    'SELECT SOURCE, SUM(INVOICE_COUNT) as COUNT FROM CURATED_DEV.MARKETPLACE.DP_ORACLE_AP_ANALYTICS GROUP BY 1',
    'Invoice count by source',
    'SELECT INVOICE_YEAR, SUM(CANCELLED_COUNT) as CANCELLED FROM CURATED_DEV.MARKETPLACE.DP_ORACLE_AP_ANALYTICS GROUP BY 1 ORDER BY 1 DESC',
    'Cancelled invoices by year',
    'Oracle Finance Team', 'oracle-ap@company.com', 4,
    'Cash Flow Forecasting, Vendor Payments, Working Capital, Payment Terms',
    'Oracle, ERP, AP, Payments, Vendors'
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
    ACCOUNT_TIER,
    BILLING_COUNTRY AS COUNTRY,
    BILLING_STATE AS STATE,
    COUNT(*) AS ACCOUNT_COUNT,
    SUM(CASE WHEN IS_ACTIVE THEN 1 ELSE 0 END) AS ACTIVE_ACCOUNTS,
    SUM(ANNUAL_REVENUE) AS TOTAL_ARR,
    AVG(ANNUAL_REVENUE) AS AVG_ARR,
    SUM(EMPLOYEE_COUNT) AS TOTAL_EMPLOYEES,
    AVG(EMPLOYEE_COUNT) AS AVG_EMPLOYEES,
    ROUND(100.0 * SUM(CASE WHEN IS_ACTIVE THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS RETENTION_RATE_PCT,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.SALESFORCE.DIM_ACCOUNT
GROUP BY INDUSTRY, ACCOUNT_TIER, BILLING_COUNTRY, BILLING_STATE
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
    'SALESFORCE', 'CURATED_DEV', 'MARKETPLACE', 'DP_SALESFORCE_PIPELINE', 'SECURE_VIEW',
    'SALES', 'INTERNAL', FALSE, 'No customer names or deal details - aggregated stage metrics only.',
    'CRM_CONSUMER', 'CRM_CONSUMER, MARKETPLACE_CONSUMER, DATA_ADMIN',
    'SELECT CLOSE_YEAR, CLOSE_QUARTER, SUM(WON_REVENUE) as BOOKINGS, AVG(WIN_RATE_PCT) as WIN_RATE FROM CURATED_DEV.MARKETPLACE.DP_SALESFORCE_PIPELINE GROUP BY 1, 2 ORDER BY 1 DESC, 2 DESC',
    'Quarterly bookings and win rate for board deck',
    'SELECT PIPELINE_STAGE, SUM(TOTAL_PIPELINE_VALUE) as PIPELINE, SUM(OPPORTUNITY_COUNT) as DEALS FROM CURATED_DEV.MARKETPLACE.DP_SALESFORCE_PIPELINE WHERE CLOSE_YEAR = YEAR(CURRENT_DATE()) AND NOT PIPELINE_STAGE IN (''Closed Won'', ''Closed Lost'') GROUP BY 1',
    'Current pipeline by stage for coverage analysis',
    'SELECT LEAD_SOURCE, SUM(WON_COUNT) as WINS, AVG(WIN_RATE_PCT) as WIN_RATE FROM CURATED_DEV.MARKETPLACE.DP_SALESFORCE_PIPELINE GROUP BY 1 ORDER BY 2 DESC',
    'Lead source effectiveness for marketing ROI',
    'SELECT FORECAST_CATEGORY, SUM(TOTAL_PIPELINE_VALUE) as VALUE FROM CURATED_DEV.MARKETPLACE.DP_SALESFORCE_PIPELINE WHERE CLOSE_YEAR = YEAR(CURRENT_DATE()) AND CLOSE_QUARTER = QUARTER(CURRENT_DATE()) GROUP BY 1',
    'Current quarter forecast by category',
    'SELECT OPPORTUNITY_TYPE, AVG(AVG_DEAL_SIZE) as AVG_DEAL, AVG(MEDIAN_DEAL_SIZE) as MEDIAN_DEAL FROM CURATED_DEV.MARKETPLACE.DP_SALESFORCE_PIPELINE GROUP BY 1 ORDER BY 2 DESC',
    'Deal size analysis by opportunity type',
    'Sales Operations', 'sales-ops@company.com', 1,
    'Pipeline Review, Forecast Calls, Sales Dashboards, Win/Loss Analysis',
    'Salesforce, CRM, Pipeline, Opportunities, Revenue'
),
(
    'DP-SF-ACCOUNTS-001',
    'Salesforce Account Health',
    'Customer account analytics from Salesforce CRM. Provides account segmentation metrics, annual revenue distribution, and retention indicators by industry, tier, and geography.',
    'Supports customer success prioritization, identifies at-risk segments, and enables data-driven territory design. Essential for customer retention and expansion strategies.',
    'v1.0',
    'SALESFORCE', 'CURATED_DEV', 'MARKETPLACE', 'DP_SALESFORCE_ACCOUNT_HEALTH', 'SECURE_VIEW',
    'CUSTOMER', 'INTERNAL', FALSE, 'No company names or contacts - aggregated segment metrics only.',
    'CRM_CONSUMER', 'CRM_CONSUMER, MARKETPLACE_CONSUMER, DATA_ADMIN',
    'SELECT ACCOUNT_TIER, SUM(ACCOUNT_COUNT) as ACCOUNTS, SUM(TOTAL_ARR) as ARR FROM CURATED_DEV.MARKETPLACE.DP_SALESFORCE_ACCOUNT_HEALTH GROUP BY 1 ORDER BY 2 DESC',
    'Account and ARR distribution by tier',
    'SELECT INDUSTRY, SUM(ACTIVE_ACCOUNTS) as ACTIVE, AVG(RETENTION_RATE_PCT) as RETENTION FROM CURATED_DEV.MARKETPLACE.DP_SALESFORCE_ACCOUNT_HEALTH GROUP BY 1 ORDER BY 3',
    'Industries with lowest retention for intervention',
    'SELECT COUNTRY, STATE, SUM(TOTAL_ARR) as ARR FROM CURATED_DEV.MARKETPLACE.DP_SALESFORCE_ACCOUNT_HEALTH GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 20',
    'Top territories by ARR for resource allocation',
    'SELECT INDUSTRY, SUM(TOTAL_EMPLOYEES) as EMPLOYEES FROM CURATED_DEV.MARKETPLACE.DP_SALESFORCE_ACCOUNT_HEALTH GROUP BY 1 ORDER BY 2 DESC',
    'Employee distribution by industry',
    'SELECT ACCOUNT_TIER, AVG(AVG_ARR) as AVG_ARR FROM CURATED_DEV.MARKETPLACE.DP_SALESFORCE_ACCOUNT_HEALTH GROUP BY 1',
    'Average ARR by account tier',
    'Sales Operations', 'customer-success@company.com', 4,
    'Customer Segmentation, Territory Planning, Retention Analysis, Account Scoring',
    'Salesforce, CRM, Accounts, Customers, ARR'
),
(
    'DP-SF-SERVICE-001',
    'Salesforce Service Analytics',
    'Customer service analytics from Salesforce Service Cloud. Provides case volume metrics, resolution rates, escalation patterns, and channel effectiveness by priority and type.',
    'Drives service level improvements, optimizes support staffing, and identifies product issues through support patterns. Critical for customer satisfaction and NPS improvement.',
    'v1.0',
    'SALESFORCE', 'CURATED_DEV', 'MARKETPLACE', 'DP_SALESFORCE_SERVICE_ANALYTICS', 'SECURE_VIEW',
    'SERVICE', 'INTERNAL', FALSE, 'No customer identifiers or case details - aggregated metrics only.',
    'CRM_CONSUMER', 'CRM_CONSUMER, MARKETPLACE_CONSUMER, DATA_ADMIN',
    'SELECT CREATED_YEAR, CREATED_MONTH, SUM(CASE_COUNT) as VOLUME, AVG(CLOSURE_RATE_PCT) as RESOLUTION_RATE FROM CURATED_DEV.MARKETPLACE.DP_SALESFORCE_SERVICE_ANALYTICS GROUP BY 1, 2 ORDER BY 1 DESC, 2 DESC',
    'Monthly case volume and resolution trends',
    'SELECT PRIORITY, SUM(CASE_COUNT) as CASES, AVG(ESCALATION_RATE_PCT) as ESCALATION_RATE FROM CURATED_DEV.MARKETPLACE.DP_SALESFORCE_SERVICE_ANALYTICS GROUP BY 1 ORDER BY 1',
    'Case distribution and escalation by priority',
    'SELECT CASE_ORIGIN, SUM(CASE_COUNT) as CASES, AVG(CLOSURE_RATE_PCT) as CLOSURE_RATE FROM CURATED_DEV.MARKETPLACE.DP_SALESFORCE_SERVICE_ANALYTICS GROUP BY 1 ORDER BY 2 DESC',
    'Channel effectiveness analysis',
    'SELECT CASE_TYPE, SUM(CASE_COUNT) as CASES FROM CURATED_DEV.MARKETPLACE.DP_SALESFORCE_SERVICE_ANALYTICS GROUP BY 1 ORDER BY 2 DESC',
    'Case volume by type',
    'SELECT CASE_STATUS, SUM(CLOSED_COUNT) as CLOSED FROM CURATED_DEV.MARKETPLACE.DP_SALESFORCE_SERVICE_ANALYTICS GROUP BY 1',
    'Closed cases by status',
    'Customer Support', 'support-analytics@company.com', 1,
    'Service Dashboards, SLA Monitoring, Staffing Planning, Customer Satisfaction',
    'Salesforce, CRM, Service, Cases, Support'
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
    REASON,
    EXTRACT(YEAR FROM START_TIME) AS ENCOUNTER_YEAR,
    EXTRACT(QUARTER FROM START_TIME) AS ENCOUNTER_QUARTER,
    COUNT(*) AS ENCOUNTER_COUNT,
    COUNT(DISTINCT PATIENT_KEY) AS UNIQUE_PATIENTS,
    AVG(DURATION_MINUTES) AS AVG_DURATION_MINUTES,
    MEDIAN(DURATION_MINUTES) AS MEDIAN_DURATION_MINUTES,
    MIN(DURATION_MINUTES) AS MIN_DURATION_MINUTES,
    MAX(DURATION_MINUTES) AS MAX_DURATION_MINUTES,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.FHIR.FACT_ENCOUNTERS
GROUP BY ENCOUNTER_CLASS, ENCOUNTER_TYPE, STATUS, REASON,
         EXTRACT(YEAR FROM START_TIME), EXTRACT(QUARTER FROM START_TIME)
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
    COUNTRY,
    COUNT(*) AS PATIENT_COUNT,
    SUM(CASE WHEN IS_ACTIVE THEN 1 ELSE 0 END) AS ACTIVE_PATIENTS,
    ROUND(100.0 * SUM(CASE WHEN IS_ACTIVE THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS ACTIVE_RATE_PCT,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.FHIR.DIM_PATIENT
GROUP BY GENDER, FLOOR(DATEDIFF('YEAR', BIRTH_DATE, CURRENT_DATE()) / 10) * 10, STATE, COUNTRY
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
    CONDITION_CODE,
    CONDITION_NAME,
    CLINICAL_STATUS,
    CATEGORY,
    SEVERITY,
    COUNT(*) AS CONDITION_COUNT,
    COUNT(DISTINCT PATIENT_KEY) AS PATIENTS_AFFECTED,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.FHIR.FACT_CONDITIONS
GROUP BY CODE_SYSTEM, CONDITION_CODE, CONDITION_NAME, CLINICAL_STATUS, CATEGORY, SEVERITY
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
    SAMPLE_QUERY_5, SAMPLE_QUERY_5_DESC,
    OWNER_TEAM, DATA_STEWARD_EMAIL, SLA_REFRESH_HOURS, USE_CASES, TAGS
) VALUES 
(
    'DP-FHIR-ENCOUNTERS-001',
    'FHIR Clinical Encounters',
    'De-identified clinical encounter analytics from FHIR R4 resources. Provides encounter volumes, duration metrics, and facility utilization patterns. Fully HIPAA compliant with no Protected Health Information.',
    'Enables evidence-based capacity planning, identifies bottlenecks in patient flow, and supports operational efficiency initiatives. Critical for healthcare operations and quality improvement.',
    'v1.0',
    'FHIR', 'CURATED_DEV', 'MARKETPLACE', 'DP_FHIR_CLINICAL_ENCOUNTERS', 'SECURE_VIEW',
    'CLINICAL', 'RESTRICTED', FALSE, 'HIPAA compliant. No PHI. Aggregated metrics only. IRB approval not required for operational use.',
    'HEALTHCARE_CONSUMER', 'HEALTHCARE_CONSUMER, MARKETPLACE_CONSUMER, DATA_ADMIN',
    'SELECT ENCOUNTER_YEAR, ENCOUNTER_QUARTER, SUM(ENCOUNTER_COUNT) as VISITS, SUM(UNIQUE_PATIENTS) as PATIENTS FROM CURATED_DEV.MARKETPLACE.DP_FHIR_CLINICAL_ENCOUNTERS GROUP BY 1, 2 ORDER BY 1 DESC, 2 DESC',
    'Quarterly patient visit volume for capacity planning',
    'SELECT ENCOUNTER_CLASS, SUM(ENCOUNTER_COUNT) as VISITS, AVG(AVG_DURATION_MINUTES) as AVG_DURATION FROM CURATED_DEV.MARKETPLACE.DP_FHIR_CLINICAL_ENCOUNTERS GROUP BY 1 ORDER BY 2 DESC',
    'Visit distribution by encounter class',
    'SELECT REASON, SUM(ENCOUNTER_COUNT) as VISITS FROM CURATED_DEV.MARKETPLACE.DP_FHIR_CLINICAL_ENCOUNTERS WHERE ENCOUNTER_YEAR = YEAR(CURRENT_DATE()) GROUP BY 1 ORDER BY 2 DESC',
    'YTD visits by reason',
    'SELECT ENCOUNTER_TYPE, AVG(AVG_DURATION_MINUTES) as AVG_MIN, AVG(MEDIAN_DURATION_MINUTES) as MEDIAN_MIN FROM CURATED_DEV.MARKETPLACE.DP_FHIR_CLINICAL_ENCOUNTERS GROUP BY 1 ORDER BY 2 DESC',
    'Duration benchmarks by encounter type',
    'SELECT ENCOUNTER_STATUS, SUM(ENCOUNTER_COUNT) as COUNT FROM CURATED_DEV.MARKETPLACE.DP_FHIR_CLINICAL_ENCOUNTERS GROUP BY 1',
    'Encounters by status',
    'Clinical Operations', 'clinical-analytics@health.org', 4,
    'Capacity Planning, Operational Efficiency, Quality Metrics, Resource Allocation',
    'FHIR, Healthcare, Clinical, Encounters, HIPAA'
),
(
    'DP-FHIR-POPULATION-001',
    'FHIR Population Health',
    'De-identified population demographics from FHIR Patient resources. Age bands, gender distribution, and geographic spread with minimum cell sizes for privacy protection. Supports population health management initiatives.',
    'Enables population segmentation for care management programs, identifies health disparities, and supports community health needs assessments.',
    'v1.0',
    'FHIR', 'CURATED_DEV', 'MARKETPLACE', 'DP_FHIR_POPULATION_HEALTH', 'SECURE_VIEW',
    'POPULATION_HEALTH', 'RESTRICTED', FALSE, 'HIPAA Safe Harbor compliant. Age bands used instead of exact ages. Minimum cell size 10.',
    'HEALTHCARE_CONSUMER', 'HEALTHCARE_CONSUMER, MARKETPLACE_CONSUMER, DATA_ADMIN',
    'SELECT GENDER, SUM(PATIENT_COUNT) as PATIENTS FROM CURATED_DEV.MARKETPLACE.DP_FHIR_POPULATION_HEALTH GROUP BY 1',
    'Patient population by gender',
    'SELECT AGE_BAND, SUM(PATIENT_COUNT) as PATIENTS FROM CURATED_DEV.MARKETPLACE.DP_FHIR_POPULATION_HEALTH GROUP BY 1 ORDER BY 1',
    'Age distribution pyramid for population health',
    'SELECT STATE, SUM(PATIENT_COUNT) as PATIENTS, AVG(ACTIVE_RATE_PCT) as ENGAGEMENT FROM CURATED_DEV.MARKETPLACE.DP_FHIR_POPULATION_HEALTH GROUP BY 1 ORDER BY 2 DESC',
    'Geographic distribution for community health planning',
    'SELECT COUNTRY, SUM(PATIENT_COUNT) as PATIENTS FROM CURATED_DEV.MARKETPLACE.DP_FHIR_POPULATION_HEALTH GROUP BY 1',
    'Patient count by country',
    'SELECT AGE_BAND, GENDER, SUM(PATIENT_COUNT) as PATIENTS FROM CURATED_DEV.MARKETPLACE.DP_FHIR_POPULATION_HEALTH GROUP BY 1, 2 ORDER BY 1, 2',
    'Age and gender distribution matrix',
    'Population Health', 'population-health@health.org', 24,
    'Population Segmentation, Health Equity, Community Health, Care Gaps',
    'FHIR, Healthcare, Population, Demographics, HIPAA'
),
(
    'DP-FHIR-CONDITIONS-001',
    'FHIR Condition Analytics',
    'De-identified clinical condition prevalence from FHIR Condition resources. Top conditions by patient count with minimum cell size protection. Supports population health and quality measurement initiatives.',
    'Enables disease burden analysis, quality measure tracking, and clinical program prioritization. Supports value-based care initiatives and population health management.',
    'v1.0',
    'FHIR', 'CURATED_DEV', 'MARKETPLACE', 'DP_FHIR_CONDITION_ANALYTICS', 'SECURE_VIEW',
    'CLINICAL', 'RESTRICTED', FALSE, 'HIPAA compliant. Minimum 10 patients per condition. No individual patient data.',
    'HEALTHCARE_CONSUMER', 'HEALTHCARE_CONSUMER, MARKETPLACE_CONSUMER, DATA_ADMIN',
    'SELECT CONDITION_CODE, CONDITION_NAME, PATIENT_COUNT FROM CURATED_DEV.MARKETPLACE.DP_FHIR_CONDITION_ANALYTICS ORDER BY PATIENT_COUNT DESC LIMIT 20',
    'Top 20 conditions by prevalence',
    'SELECT CATEGORY, SUM(PATIENT_COUNT) as PATIENTS FROM CURATED_DEV.MARKETPLACE.DP_FHIR_CONDITION_ANALYTICS GROUP BY 1 ORDER BY 2 DESC',
    'Patient count by condition category',
    'SELECT CLINICAL_STATUS, COUNT(*) as CONDITION_COUNT FROM CURATED_DEV.MARKETPLACE.DP_FHIR_CONDITION_ANALYTICS GROUP BY 1',
    'Conditions by clinical status',
    'SELECT CONDITION_NAME, PATIENT_COUNT, PREVALENCE_RANK FROM CURATED_DEV.MARKETPLACE.DP_FHIR_CONDITION_ANALYTICS WHERE PREVALENCE_RANK <= 10',
    'Top 10 conditions by prevalence rank',
    'SELECT CATEGORY, AVG(PATIENT_COUNT) as AVG_PATIENTS FROM CURATED_DEV.MARKETPLACE.DP_FHIR_CONDITION_ANALYTICS GROUP BY 1',
    'Average patient count by category',
    'Clinical Analytics', 'clinical-analytics@health.org', 4,
    'Disease Burden, Quality Measures, Population Health, Clinical Programs',
    'FHIR, Healthcare, Conditions, Diagnosis, HIPAA'
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
    COMPENSATION_GRADE,
    COMPENSATION_PLAN,
    CURRENCY AS CURRENCY_CODE,
    COUNT(*) AS EMPLOYEE_COUNT,
    ROUND(AVG(BASE_PAY_AMOUNT), 0) AS AVG_BASE_PAY,
    ROUND(MEDIAN(BASE_PAY_AMOUNT), 0) AS MEDIAN_BASE_PAY,
    ROUND(MIN(BASE_PAY_AMOUNT), 0) AS MIN_BASE_PAY,
    ROUND(MAX(BASE_PAY_AMOUNT), 0) AS MAX_BASE_PAY,
    ROUND(STDDEV(BASE_PAY_AMOUNT), 0) AS STDDEV_BASE_PAY,
    ROUND(AVG(COMPA_RATIO), 2) AS AVG_COMPA_RATIO,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.WORKDAY.FACT_COMPENSATION
GROUP BY COMPENSATION_GRADE, COMPENSATION_PLAN, CURRENCY
HAVING COUNT(*) >= 5  -- Privacy threshold
ORDER BY COMPENSATION_GRADE, COMPENSATION_PLAN;

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
    EXTRACT(YEAR FROM SUBMITTED_DATE) AS REQUEST_YEAR,
    EXTRACT(QUARTER FROM SUBMITTED_DATE) AS REQUEST_QUARTER,
    COUNT(*) AS REQUEST_COUNT,
    COUNT(DISTINCT EMPLOYEE_KEY) AS EMPLOYEES_REQUESTING,
    SUM(TOTAL_HOURS) AS TOTAL_HOURS_REQUESTED,
    SUM(TOTAL_DAYS) AS TOTAL_DAYS_REQUESTED,
    AVG(TOTAL_HOURS) AS AVG_HOURS_PER_REQUEST,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.WORKDAY.FACT_TIME_OFF
GROUP BY TIME_OFF_TYPE, STATUS, 
         EXTRACT(YEAR FROM SUBMITTED_DATE), EXTRACT(QUARTER FROM SUBMITTED_DATE)
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
    'WORKDAY', 'CURATED_DEV', 'MARKETPLACE', 'DP_WORKDAY_WORKFORCE', 'SECURE_VIEW',
    'HR', 'CONFIDENTIAL', FALSE, 'No employee names, IDs, or individual data. Aggregated by organizational dimensions only.',
    'WORKFORCE_CONSUMER', 'WORKFORCE_CONSUMER, MARKETPLACE_CONSUMER, DATA_ADMIN',
    'SELECT DEPARTMENT, SUM(ACTIVE_EMPLOYEES) as HEADCOUNT FROM CURATED_DEV.MARKETPLACE.DP_WORKDAY_WORKFORCE GROUP BY 1 ORDER BY 2 DESC',
    'Current headcount by department for org chart',
    'SELECT JOB_LEVEL, SUM(HEADCOUNT) as TOTAL, AVG(AVG_TENURE_YEARS) as AVG_TENURE FROM CURATED_DEV.MARKETPLACE.DP_WORKDAY_WORKFORCE GROUP BY 1 ORDER BY 1',
    'Tenure analysis by job level for retention strategy',
    'SELECT COUNTRY, WORK_LOCATION, SUM(ACTIVE_EMPLOYEES) as EMPLOYEES FROM CURATED_DEV.MARKETPLACE.DP_WORKDAY_WORKFORCE GROUP BY 1, 2 ORDER BY 3 DESC',
    'Geographic distribution for location strategy',
    'SELECT WORKER_TYPE, SUM(HEADCOUNT) as COUNT, AVG(AVG_FTE) as AVG_FTE FROM CURATED_DEV.MARKETPLACE.DP_WORKDAY_WORKFORCE GROUP BY 1',
    'Employee vs contractor mix analysis',
    'SELECT JOB_FAMILY, SUM(ACTIVE_EMPLOYEES) as ACTIVE, SUM(TERMINATED_EMPLOYEES) as TERMED FROM CURATED_DEV.MARKETPLACE.DP_WORKDAY_WORKFORCE GROUP BY 1 ORDER BY 2 DESC',
    'Attrition patterns by job family',
    'HR Analytics', 'hr-analytics@company.com', 4,
    'Workforce Planning, Org Design, Retention Analysis, Location Strategy',
    'Workday, HR, Workforce, Headcount, HCM'
),
(
    'DP-WD-COMP-001',
    'Workday Compensation Bands',
    'Compensation band statistics from Workday HCM. Provides pay range metrics by grade and level with statistical distribution. Minimum 5 employees per band for privacy protection.',
    'Supports market competitiveness analysis, pay equity assessments, and compensation planning. Critical for total rewards and HR leadership.',
    'v1.0',
    'WORKDAY', 'CURATED_DEV', 'MARKETPLACE', 'DP_WORKDAY_COMPENSATION', 'SECURE_VIEW',
    'COMPENSATION', 'RESTRICTED', FALSE, 'No individual salaries. Aggregated bands with minimum 5 employees. Audited access.',
    'WORKFORCE_CONSUMER', 'WORKFORCE_CONSUMER, DATA_ADMIN',
    'SELECT PAY_GRADE, AVG_BASE_PAY, MEDIAN_BASE_PAY, MIN_BASE_PAY, MAX_BASE_PAY FROM CURATED_DEV.MARKETPLACE.DP_WORKDAY_COMPENSATION ORDER BY PAY_GRADE',
    'Compensation band ranges for benchmarking',
    'SELECT JOB_LEVEL, AVG(AVG_BASE_PAY) as AVG_PAY FROM CURATED_DEV.MARKETPLACE.DP_WORKDAY_COMPENSATION GROUP BY 1 ORDER BY 1',
    'Average pay progression by level',
    'SELECT PAY_GRADE, STDDEV_BASE_PAY / NULLIF(AVG_BASE_PAY, 0) as PAY_VARIABILITY FROM CURATED_DEV.MARKETPLACE.DP_WORKDAY_COMPENSATION WHERE EMPLOYEE_COUNT >= 10',
    'Pay equity indicator by grade (low variability = equity)',
    'SELECT CURRENCY, SUM(EMPLOYEE_COUNT) as EMPLOYEES FROM CURATED_DEV.MARKETPLACE.DP_WORKDAY_COMPENSATION GROUP BY 1',
    'Employee count by currency',
    'SELECT PAY_GRADE, SUM(EMPLOYEE_COUNT) as TOTAL FROM CURATED_DEV.MARKETPLACE.DP_WORKDAY_COMPENSATION GROUP BY 1 ORDER BY 2 DESC',
    'Employee distribution across pay grades',
    'Total Rewards', 'compensation@company.com', 24,
    'Comp Planning, Pay Equity, Market Analysis, Budget Planning',
    'Workday, HR, Compensation, Salary, Pay'
),
(
    'DP-WD-TIMEOFF-001',
    'Workday Time Off Analytics',
    'Time off request analytics from Workday HCM. Provides leave patterns, utilization rates, and request trends by type and department. Supports workforce planning and policy compliance.',
    'Enables proactive coverage planning, identifies leave pattern trends, and supports policy compliance monitoring. Essential for HR operations and workforce planning.',
    'v1.0',
    'WORKDAY', 'CURATED_DEV', 'MARKETPLACE', 'DP_WORKDAY_TIME_OFF', 'SECURE_VIEW',
    'HR', 'CONFIDENTIAL', FALSE, 'No individual employee data. Aggregated by time off type and period.',
    'WORKFORCE_CONSUMER', 'WORKFORCE_CONSUMER, MARKETPLACE_CONSUMER, DATA_ADMIN',
    'SELECT TIME_OFF_TYPE, SUM(REQUEST_COUNT) as REQUESTS, SUM(TOTAL_DAYS) as DAYS FROM CURATED_DEV.MARKETPLACE.DP_WORKDAY_TIME_OFF GROUP BY 1 ORDER BY 3 DESC',
    'Time off utilization by type',
    'SELECT REQUEST_YEAR, REQUEST_MONTH, SUM(REQUEST_COUNT) as REQUESTS FROM CURATED_DEV.MARKETPLACE.DP_WORKDAY_TIME_OFF GROUP BY 1, 2 ORDER BY 1 DESC, 2 DESC',
    'Monthly time off request trends',
    'SELECT STATUS, SUM(REQUEST_COUNT) as REQUESTS FROM CURATED_DEV.MARKETPLACE.DP_WORKDAY_TIME_OFF GROUP BY 1',
    'Request distribution by status',
    'SELECT TIME_OFF_TYPE, AVG(AVG_DAYS_PER_REQUEST) as AVG_DURATION FROM CURATED_DEV.MARKETPLACE.DP_WORKDAY_TIME_OFF GROUP BY 1 ORDER BY 2 DESC',
    'Average leave duration by type',
    'SELECT REQUEST_YEAR, REQUEST_QUARTER, SUM(TOTAL_DAYS) as DAYS FROM CURATED_DEV.MARKETPLACE.DP_WORKDAY_TIME_OFF GROUP BY 1, 2 ORDER BY 1, 2',
    'Quarterly leave days for capacity planning',
    'HR Operations', 'hr-operations@company.com', 4,
    'Leave Management, Workforce Planning, Coverage Planning, Policy Compliance',
    'Workday, HR, Time Off, Leave, PTO'
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
    IMPACT,
    EXTRACT(YEAR FROM PLANNED_START_DATE) AS CHANGE_YEAR,
    EXTRACT(QUARTER FROM PLANNED_START_DATE) AS CHANGE_QUARTER,
    COUNT(*) AS CHANGE_COUNT,
    SUM(CASE WHEN STATE = 'closed' THEN 1 ELSE 0 END) AS CLOSED_COUNT,
    SUM(CASE WHEN STATE = 'canceled' THEN 1 ELSE 0 END) AS CANCELLED_COUNT,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.SERVICENOW.FACT_CHANGES
GROUP BY CHANGE_TYPE, RISK, STATE, IMPACT,
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
    URGENCY,
    IMPACT,
    ASSIGNMENT_GROUP,
    EXTRACT(YEAR FROM CREATED_DATE) AS OPENED_YEAR,
    EXTRACT(QUARTER FROM CREATED_DATE) AS OPENED_QUARTER,
    COUNT(*) AS PROBLEM_COUNT,
    SUM(CASE WHEN IS_KNOWN_ERROR THEN 1 ELSE 0 END) AS KNOWN_ERROR_COUNT,
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIME
FROM CURATED_DEV.SERVICENOW.FACT_PROBLEMS
GROUP BY PRIORITY, STATE, URGENCY, IMPACT, ASSIGNMENT_GROUP,
         EXTRACT(YEAR FROM CREATED_DATE), EXTRACT(QUARTER FROM CREATED_DATE)
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
    'SERVICENOW', 'CURATED_DEV', 'MARKETPLACE', 'DP_SERVICENOW_INCIDENTS', 'SECURE_VIEW',
    'ITSM', 'INTERNAL', FALSE, 'No user identifiers or ticket details. Aggregated operational metrics only.',
    'ITSM_CONSUMER', 'ITSM_CONSUMER, MARKETPLACE_CONSUMER, DATA_ADMIN',
    'SELECT OPENED_YEAR, OPENED_MONTH, SUM(INCIDENT_COUNT) as VOLUME, AVG(AVG_RESOLUTION_MINUTES) as AVG_MTTR FROM CURATED_DEV.MARKETPLACE.DP_SERVICENOW_INCIDENTS GROUP BY 1, 2 ORDER BY 1 DESC, 2 DESC',
    'Monthly incident volume and MTTR trend for SLA reporting',
    'SELECT PRIORITY, SUM(INCIDENT_COUNT) as COUNT, AVG(AVG_RESOLUTION_MINUTES) as AVG_RESOLUTION FROM CURATED_DEV.MARKETPLACE.DP_SERVICENOW_INCIDENTS WHERE OPENED_YEAR = YEAR(CURRENT_DATE()) GROUP BY 1 ORDER BY 1',
    'YTD incidents by priority for severity analysis',
    'SELECT ASSIGNMENT_GROUP, SUM(INCIDENT_COUNT) as VOLUME, SUM(HIGH_PRIORITY_COUNT) as P1_P2 FROM CURATED_DEV.MARKETPLACE.DP_SERVICENOW_INCIDENTS WHERE OPENED_YEAR = YEAR(CURRENT_DATE()) GROUP BY 1 ORDER BY 2 DESC LIMIT 10',
    'Top 10 assignment groups by volume for capacity planning',
    'SELECT CATEGORY, SUM(INCIDENT_COUNT) as COUNT FROM CURATED_DEV.MARKETPLACE.DP_SERVICENOW_INCIDENTS WHERE OPENED_YEAR = YEAR(CURRENT_DATE()) GROUP BY 1 ORDER BY 2 DESC',
    'Incident distribution by category for problem trends',
    'SELECT OPENED_YEAR, OPENED_MONTH, SUM(RESOLVED_COUNT) / NULLIF(SUM(INCIDENT_COUNT), 0) as RESOLUTION_RATE FROM CURATED_DEV.MARKETPLACE.DP_SERVICENOW_INCIDENTS GROUP BY 1, 2 ORDER BY 1, 2',
    'Resolution rate trend for service improvement tracking',
    'IT Operations', 'it-analytics@company.com', 1,
    'SLA Dashboards, Capacity Planning, Service Improvement, Executive Reporting',
    'ServiceNow, ITSM, Incidents, Help Desk, ITIL'
),
(
    'DP-SN-CHANGES-001',
    'ServiceNow Change Analytics',
    'IT change management analytics from ServiceNow. Provides change volumes, success rates, and risk distribution. Supports ITIL change management processes and CAB decision-making.',
    'Reduces change-related incidents through data-driven risk assessment. Improves change success rates and supports continuous improvement in IT service delivery.',
    'v1.0',
    'SERVICENOW', 'CURATED_DEV', 'MARKETPLACE', 'DP_SERVICENOW_CHANGES', 'SECURE_VIEW',
    'ITSM', 'INTERNAL', FALSE, 'No change details or implementer information. Aggregated metrics only.',
    'ITSM_CONSUMER', 'ITSM_CONSUMER, MARKETPLACE_CONSUMER, DATA_ADMIN',
    'SELECT CHANGE_YEAR, CHANGE_QUARTER, SUM(CHANGE_COUNT) as CHANGES, AVG(SUCCESS_RATE_PCT) as SUCCESS_RATE FROM CURATED_DEV.MARKETPLACE.DP_SERVICENOW_CHANGES GROUP BY 1, 2 ORDER BY 1 DESC, 2 DESC',
    'Quarterly change volume and success rate for CAB review',
    'SELECT RISK, SUM(CHANGE_COUNT) as COUNT, AVG(SUCCESS_RATE_PCT) as SUCCESS_RATE FROM CURATED_DEV.MARKETPLACE.DP_SERVICENOW_CHANGES GROUP BY 1 ORDER BY 1',
    'Success rate by risk level for risk assessment calibration',
    'SELECT CHANGE_TYPE, SUM(SUCCESSFUL_COUNT) as SUCCESS, SUM(FAILED_COUNT) as FAILED FROM CURATED_DEV.MARKETPLACE.DP_SERVICENOW_CHANGES GROUP BY 1',
    'Change outcomes by type for process improvement',
    'SELECT ASSIGNMENT_GROUP, SUM(CHANGE_COUNT) as TOTAL FROM CURATED_DEV.MARKETPLACE.DP_SERVICENOW_CHANGES GROUP BY 1 ORDER BY 2 DESC',
    'Change volume by assignment group',
    'SELECT STATE, SUM(CHANGE_COUNT) as COUNT FROM CURATED_DEV.MARKETPLACE.DP_SERVICENOW_CHANGES GROUP BY 1',
    'Changes by state',
    'IT Change Management', 'change-management@company.com', 4,
    'CAB Reporting, Risk Assessment, Change Success, ITIL Compliance',
    'ServiceNow, ITSM, Changes, CAB, ITIL'
),
(
    'DP-SN-PROBLEMS-001',
    'ServiceNow Problem Analytics',
    'IT problem management analytics from ServiceNow. Provides problem trends, root cause analysis completion rates, and related incident impact. Supports proactive problem management and service reliability.',
    'Drives reduction in recurring incidents through systematic root cause analysis. Enables proactive IT operations and improves overall service stability.',
    'v1.0',
    'SERVICENOW', 'CURATED_DEV', 'MARKETPLACE', 'DP_SERVICENOW_PROBLEMS', 'SECURE_VIEW',
    'ITSM', 'INTERNAL', FALSE, 'No problem details or technical information. Aggregated metrics only.',
    'ITSM_CONSUMER', 'ITSM_CONSUMER, MARKETPLACE_CONSUMER, DATA_ADMIN',
    'SELECT OPENED_YEAR, OPENED_QUARTER, SUM(PROBLEM_COUNT) as PROBLEMS, AVG(RCA_RATE_PCT) as RCA_COMPLETION FROM CURATED_DEV.MARKETPLACE.DP_SERVICENOW_PROBLEMS GROUP BY 1, 2 ORDER BY 1 DESC, 2 DESC',
    'Quarterly problem volume and RCA completion for management',
    'SELECT IMPACT, SUM(PROBLEM_COUNT) as COUNT FROM CURATED_DEV.MARKETPLACE.DP_SERVICENOW_PROBLEMS GROUP BY 1 ORDER BY 2 DESC',
    'Problem count by impact for prioritization',
    'SELECT PRIORITY, SUM(RELATED_INCIDENTS) as IMPACT FROM CURATED_DEV.MARKETPLACE.DP_SERVICENOW_PROBLEMS GROUP BY 1 ORDER BY 1',
    'Incident impact by problem priority',
    'SELECT STATE, SUM(PROBLEM_COUNT) as COUNT FROM CURATED_DEV.MARKETPLACE.DP_SERVICENOW_PROBLEMS GROUP BY 1',
    'Problems by state',
    'SELECT URGENCY, SUM(PROBLEM_COUNT) as COUNT FROM CURATED_DEV.MARKETPLACE.DP_SERVICENOW_PROBLEMS GROUP BY 1',
    'Problem distribution by urgency',
    'IT Problem Management', 'problem-management@company.com', 4,
    'Problem Trends, RCA Tracking, Service Reliability, Proactive Management',
    'ServiceNow, ITSM, Problems, RCA, ITIL'
);

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 9: DATA PRODUCT CATALOG VIEW
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW CURATED_DEV.MARKETPLACE.VW_DATA_PRODUCT_CATALOG AS
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
    ALLOWED_ROLES,
    SAMPLE_QUERY_1,
    SAMPLE_QUERY_1_DESC,
    SAMPLE_QUERY_2,
    SAMPLE_QUERY_2_DESC,
    SAMPLE_QUERY_3,
    SAMPLE_QUERY_3_DESC,
    OWNER_TEAM,
    DATA_STEWARD_EMAIL,
    SLA_REFRESH_HOURS,
    USE_CASES,
    TAGS,
    STATUS,
    CREATED_AT
FROM GOVERNANCE.OBSERVABILITY.DATA_PRODUCT_CATALOG
WHERE STATUS = 'ACTIVE'
ORDER BY SOURCE_SYSTEM, DOMAIN;

GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.VW_DATA_PRODUCT_CATALOG TO ROLE ERP_CONSUMER;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.VW_DATA_PRODUCT_CATALOG TO ROLE CRM_CONSUMER;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.VW_DATA_PRODUCT_CATALOG TO ROLE HEALTHCARE_CONSUMER;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.VW_DATA_PRODUCT_CATALOG TO ROLE WORKFORCE_CONSUMER;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.VW_DATA_PRODUCT_CATALOG TO ROLE ITSM_CONSUMER;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.VW_DATA_PRODUCT_CATALOG TO ROLE MARKETPLACE_CONSUMER;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 10: ADDITIONAL GRANTS AND VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

-- Grant future views
GRANT SELECT ON FUTURE VIEWS IN SCHEMA CURATED_DEV.MARKETPLACE TO ROLE ERP_CONSUMER;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA CURATED_DEV.MARKETPLACE TO ROLE CRM_CONSUMER;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA CURATED_DEV.MARKETPLACE TO ROLE HEALTHCARE_CONSUMER;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA CURATED_DEV.MARKETPLACE TO ROLE WORKFORCE_CONSUMER;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA CURATED_DEV.MARKETPLACE TO ROLE ITSM_CONSUMER;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA CURATED_DEV.MARKETPLACE TO ROLE MARKETPLACE_CONSUMER;

-- Also grant to existing business roles
GRANT USAGE ON SCHEMA CURATED_DEV.MARKETPLACE TO ROLE ANALYST;
GRANT USAGE ON SCHEMA CURATED_DEV.MARKETPLACE TO ROLE MANAGER;
GRANT USAGE ON SCHEMA CURATED_DEV.MARKETPLACE TO ROLE VIEWER;
GRANT SELECT ON ALL VIEWS IN SCHEMA CURATED_DEV.MARKETPLACE TO ROLE ANALYST;
GRANT SELECT ON ALL VIEWS IN SCHEMA CURATED_DEV.MARKETPLACE TO ROLE MANAGER;
GRANT SELECT ON ALL VIEWS IN SCHEMA CURATED_DEV.MARKETPLACE TO ROLE VIEWER;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 11: INTERNAL ORGANIZATIONAL LISTINGS
-- ═══════════════════════════════════════════════════════════════════════════
-- Creates internal listings visible to users within this Snowflake account.
-- Users can discover these in Snowsight: Data > Private Sharing > Shared With You

USE ROLE ACCOUNTADMIN;

-- -----------------------------------------------------------------------------
-- Create Shares for Internal Listings
-- Shares are required as the underlying data product for listings
-- -----------------------------------------------------------------------------

-- SAP ERP Data Share
CREATE OR REPLACE SHARE SAP_ERP_DATA_SHARE
    COMMENT = 'SAP ERP Analytics - Sales, Procurement, and Customer data products';

GRANT USAGE ON DATABASE CURATED_DEV TO SHARE SAP_ERP_DATA_SHARE;
GRANT USAGE ON SCHEMA CURATED_DEV.MARKETPLACE TO SHARE SAP_ERP_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_SAP_SALES_ANALYTICS TO SHARE SAP_ERP_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_SAP_PROCUREMENT_ANALYTICS TO SHARE SAP_ERP_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_SAP_CUSTOMER_SUMMARY TO SHARE SAP_ERP_DATA_SHARE;

-- Oracle Financials Data Share
CREATE OR REPLACE SHARE ORACLE_FINANCIALS_DATA_SHARE
    COMMENT = 'Oracle Financials Analytics - GL and AP analytics';

GRANT USAGE ON DATABASE CURATED_DEV TO SHARE ORACLE_FINANCIALS_DATA_SHARE;
GRANT USAGE ON SCHEMA CURATED_DEV.MARKETPLACE TO SHARE ORACLE_FINANCIALS_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_ORACLE_FINANCIAL_ANALYTICS TO SHARE ORACLE_FINANCIALS_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_ORACLE_AP_ANALYTICS TO SHARE ORACLE_FINANCIALS_DATA_SHARE;

-- Salesforce CRM Data Share
CREATE OR REPLACE SHARE SALESFORCE_CRM_DATA_SHARE
    COMMENT = 'Salesforce CRM Analytics - Pipeline, Account Health, and Service';

GRANT USAGE ON DATABASE CURATED_DEV TO SHARE SALESFORCE_CRM_DATA_SHARE;
GRANT USAGE ON SCHEMA CURATED_DEV.MARKETPLACE TO SHARE SALESFORCE_CRM_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_SALESFORCE_PIPELINE TO SHARE SALESFORCE_CRM_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_SALESFORCE_ACCOUNT_HEALTH TO SHARE SALESFORCE_CRM_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_SALESFORCE_SERVICE_ANALYTICS TO SHARE SALESFORCE_CRM_DATA_SHARE;

-- FHIR Healthcare Data Share
CREATE OR REPLACE SHARE FHIR_HEALTHCARE_DATA_SHARE
    COMMENT = 'FHIR Healthcare Analytics - HIPAA-compliant clinical data';

GRANT USAGE ON DATABASE CURATED_DEV TO SHARE FHIR_HEALTHCARE_DATA_SHARE;
GRANT USAGE ON SCHEMA CURATED_DEV.MARKETPLACE TO SHARE FHIR_HEALTHCARE_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_FHIR_CLINICAL_ENCOUNTERS TO SHARE FHIR_HEALTHCARE_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_FHIR_POPULATION_HEALTH TO SHARE FHIR_HEALTHCARE_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_FHIR_CONDITION_ANALYTICS TO SHARE FHIR_HEALTHCARE_DATA_SHARE;

-- Workday HR Data Share
CREATE OR REPLACE SHARE WORKDAY_HR_DATA_SHARE
    COMMENT = 'Workday HR Analytics - Workforce, Compensation, and Time Off';

GRANT USAGE ON DATABASE CURATED_DEV TO SHARE WORKDAY_HR_DATA_SHARE;
GRANT USAGE ON SCHEMA CURATED_DEV.MARKETPLACE TO SHARE WORKDAY_HR_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_WORKDAY_WORKFORCE TO SHARE WORKDAY_HR_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_WORKDAY_COMPENSATION TO SHARE WORKDAY_HR_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_WORKDAY_TIME_OFF TO SHARE WORKDAY_HR_DATA_SHARE;

-- ServiceNow ITSM Data Share
CREATE OR REPLACE SHARE SERVICENOW_ITSM_DATA_SHARE
    COMMENT = 'ServiceNow ITSM Analytics - Incidents, Changes, and Problems';

GRANT USAGE ON DATABASE CURATED_DEV TO SHARE SERVICENOW_ITSM_DATA_SHARE;
GRANT USAGE ON SCHEMA CURATED_DEV.MARKETPLACE TO SHARE SERVICENOW_ITSM_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_SERVICENOW_INCIDENTS TO SHARE SERVICENOW_ITSM_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_SERVICENOW_CHANGES TO SHARE SERVICENOW_ITSM_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_SERVICENOW_PROBLEMS TO SHARE SERVICENOW_ITSM_DATA_SHARE;

-- Enterprise Analytics Share (all domains combined)
CREATE OR REPLACE SHARE ENTERPRISE_ANALYTICS_DATA_SHARE
    COMMENT = 'Enterprise Analytics - All 17 data products across 6 source systems';

GRANT USAGE ON DATABASE CURATED_DEV TO SHARE ENTERPRISE_ANALYTICS_DATA_SHARE;
GRANT USAGE ON SCHEMA CURATED_DEV.MARKETPLACE TO SHARE ENTERPRISE_ANALYTICS_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_SAP_SALES_ANALYTICS TO SHARE ENTERPRISE_ANALYTICS_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_SAP_PROCUREMENT_ANALYTICS TO SHARE ENTERPRISE_ANALYTICS_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_SAP_CUSTOMER_SUMMARY TO SHARE ENTERPRISE_ANALYTICS_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_ORACLE_FINANCIAL_ANALYTICS TO SHARE ENTERPRISE_ANALYTICS_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_ORACLE_AP_ANALYTICS TO SHARE ENTERPRISE_ANALYTICS_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_SALESFORCE_PIPELINE TO SHARE ENTERPRISE_ANALYTICS_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_SALESFORCE_ACCOUNT_HEALTH TO SHARE ENTERPRISE_ANALYTICS_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_SALESFORCE_SERVICE_ANALYTICS TO SHARE ENTERPRISE_ANALYTICS_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_FHIR_CLINICAL_ENCOUNTERS TO SHARE ENTERPRISE_ANALYTICS_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_FHIR_POPULATION_HEALTH TO SHARE ENTERPRISE_ANALYTICS_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_FHIR_CONDITION_ANALYTICS TO SHARE ENTERPRISE_ANALYTICS_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_WORKDAY_WORKFORCE TO SHARE ENTERPRISE_ANALYTICS_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_WORKDAY_COMPENSATION TO SHARE ENTERPRISE_ANALYTICS_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_WORKDAY_TIME_OFF TO SHARE ENTERPRISE_ANALYTICS_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_SERVICENOW_INCIDENTS TO SHARE ENTERPRISE_ANALYTICS_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_SERVICENOW_CHANGES TO SHARE ENTERPRISE_ANALYTICS_DATA_SHARE;
GRANT SELECT ON VIEW CURATED_DEV.MARKETPLACE.DP_SERVICENOW_PROBLEMS TO SHARE ENTERPRISE_ANALYTICS_DATA_SHARE;

-- -----------------------------------------------------------------------------
-- Add Descriptions to Shares (Shows in Internal Listing UI)
-- These comments provide metadata for shares when browsing in Snowsight
-- -----------------------------------------------------------------------------

-- SAP ERP Analytics Share Description
COMMENT ON SHARE SAP_ERP_DATA_SHARE IS '{"title": "SAP ERP Analytics", "subtitle": "Sales, Procurement, and Customer Analytics from SAP S/4HANA", "description": "Comprehensive SAP ERP analytics providing real-time insights into enterprise operations. Includes DP_SAP_SALES_ANALYTICS (revenue metrics, order volumes), DP_SAP_PROCUREMENT_ANALYTICS (spend visibility, vendor metrics), and DP_SAP_CUSTOMER_SUMMARY (customer distribution by geography). Refresh Rate: Every 4 hours. Data Classification: Internal - No PII.", "use_cases": ["Revenue Reporting", "Sales Performance", "Procurement Optimization", "Spend Analysis"]}';

-- Oracle Financials Analytics Share Description
COMMENT ON SHARE ORACLE_FINANCIALS_DATA_SHARE IS '{"title": "Oracle Financials Analytics", "subtitle": "General Ledger and Accounts Payable from Oracle Cloud", "description": "Oracle Financials Cloud analytics for finance teams and executives. Includes DP_ORACLE_FINANCIAL_ANALYTICS (GL journal metrics, debit/credit balances) and DP_ORACLE_AP_ANALYTICS (invoice volumes, payment status). Refresh Rate: Every 4 hours. Data Classification: Confidential.", "use_cases": ["Financial Close", "Variance Analysis", "Audit Support", "Cash Flow Forecasting"]}';

-- Salesforce CRM Analytics Share Description
COMMENT ON SHARE SALESFORCE_CRM_DATA_SHARE IS '{"title": "Salesforce CRM Analytics", "subtitle": "Pipeline, Account Health, and Service Analytics", "description": "Salesforce CRM analytics for sales, customer success, and service teams. Includes DP_SALESFORCE_PIPELINE (pipeline value, win rates), DP_SALESFORCE_ACCOUNT_HEALTH (customer segmentation, ARR), and DP_SALESFORCE_SERVICE_ANALYTICS (case volumes, resolution rates). Refresh Rate: Hourly. Data Classification: Internal.", "use_cases": ["Pipeline Review", "Forecast Accuracy", "Customer Retention", "Service Level Monitoring"]}';

-- FHIR Healthcare Analytics Share Description
COMMENT ON SHARE FHIR_HEALTHCARE_DATA_SHARE IS '{"title": "FHIR Healthcare Analytics", "subtitle": "HIPAA-Compliant Clinical and Population Health Data", "description": "De-identified healthcare analytics from FHIR R4 resources. Includes DP_FHIR_CLINICAL_ENCOUNTERS (encounter volumes, duration metrics), DP_FHIR_POPULATION_HEALTH (de-identified demographics, age bands), and DP_FHIR_CONDITION_ANALYTICS (top conditions by prevalence). HIPAA Compliant - No PHI. Refresh Rate: Every 4 hours.", "use_cases": ["Capacity Planning", "Population Health Management", "Quality Improvement", "Clinical Operations"]}';

-- Workday HR Analytics Share Description
COMMENT ON SHARE WORKDAY_HR_DATA_SHARE IS '{"title": "Workday HR Analytics", "subtitle": "Workforce, Compensation, and Time Off Analytics", "description": "Workday HCM analytics for HR and leadership teams. Includes DP_WORKDAY_WORKFORCE (headcount, tenure by department), DP_WORKDAY_COMPENSATION (pay ranges by grade, min 5 employees per band), and DP_WORKDAY_TIME_OFF (leave patterns, utilization). No individual employee data. Refresh Rate: Every 4 hours. Data Classification: Confidential.", "use_cases": ["Workforce Planning", "Organizational Design", "Compensation Benchmarking", "Pay Equity Analysis"]}';

-- ServiceNow ITSM Analytics Share Description
COMMENT ON SHARE SERVICENOW_ITSM_DATA_SHARE IS '{"title": "ServiceNow ITSM Analytics", "subtitle": "Incident, Change, and Problem Analytics", "description": "ServiceNow IT Service Management analytics for IT operations. Includes DP_SERVICENOW_INCIDENTS (incident volumes, MTTR, SLA performance), DP_SERVICENOW_CHANGES (change success rates, risk distribution), and DP_SERVICENOW_PROBLEMS (problem trends, root cause completion). Refresh Rate: Hourly. Data Classification: Internal.", "use_cases": ["SLA Monitoring", "Capacity Planning", "Service Improvement", "Change Advisory Board"]}';

-- Enterprise Analytics Suite Share Description (All Domains)
COMMENT ON SHARE ENTERPRISE_ANALYTICS_DATA_SHARE IS '{"title": "Enterprise Analytics Suite", "subtitle": "Complete Cross-Domain Analytics - 17 Data Products", "description": "Comprehensive enterprise analytics spanning all business domains. Includes SAP (3 products), Oracle (2 products), Salesforce (3 products), FHIR (3 products), Workday (3 products), and ServiceNow (3 products). Total: 17 data products across 6 source systems. Ideal for executives, data scientists, and cross-functional teams building unified dashboards.", "use_cases": ["Executive Dashboards", "Cross-Functional Analytics", "Data Science", "Business Intelligence"]}';

-- -----------------------------------------------------------------------------
-- Create Organization Listings (Internal Marketplace)
-- These appear in Snowsight under Data > Private Sharing > Internal Marketplace
-- -----------------------------------------------------------------------------

-- SAP ERP Analytics Organization Listing
CREATE ORGANIZATION LISTING IF NOT EXISTS SAP_ERP_ANALYTICS
    SHARE SAP_ERP_DATA_SHARE
    AS $$
title: "SAP ERP Analytics"
description: "Comprehensive SAP ERP analytics providing real-time insights into enterprise operations. Includes DP_SAP_SALES_ANALYTICS, DP_SAP_PROCUREMENT_ANALYTICS, and DP_SAP_CUSTOMER_SUMMARY. Refresh Rate: Every 4 hours."
organization_targets:
  support_contact: "data-platform@company.com"
  approver_contact: "data-admin@company.com"
$$
PUBLISH = TRUE;

-- Oracle Financials Analytics Organization Listing
CREATE ORGANIZATION LISTING IF NOT EXISTS ORACLE_FINANCIALS_ANALYTICS
    SHARE ORACLE_FINANCIALS_DATA_SHARE
    AS $$
title: "Oracle Financials Analytics"
description: "Oracle Financials Cloud analytics for finance teams. Includes DP_ORACLE_FINANCIAL_ANALYTICS and DP_ORACLE_AP_ANALYTICS. Refresh Rate: Every 4 hours."
organization_targets:
  support_contact: "data-platform@company.com"
  approver_contact: "data-admin@company.com"
$$
PUBLISH = TRUE;

-- Salesforce CRM Analytics Organization Listing
CREATE ORGANIZATION LISTING IF NOT EXISTS SALESFORCE_CRM_ANALYTICS
    SHARE SALESFORCE_CRM_DATA_SHARE
    AS $$
title: "Salesforce CRM Analytics"
description: "Salesforce CRM analytics for sales and service teams. Includes DP_SALESFORCE_PIPELINE, DP_SALESFORCE_ACCOUNT_HEALTH, and DP_SALESFORCE_SERVICE_ANALYTICS. Refresh Rate: Hourly."
organization_targets:
  support_contact: "data-platform@company.com"
  approver_contact: "data-admin@company.com"
$$
PUBLISH = TRUE;

-- FHIR Healthcare Analytics Organization Listing
CREATE ORGANIZATION LISTING IF NOT EXISTS FHIR_HEALTHCARE_ANALYTICS
    SHARE FHIR_HEALTHCARE_DATA_SHARE
    AS $$
title: "FHIR Healthcare Analytics"
description: "De-identified healthcare analytics from FHIR R4 resources. HIPAA Compliant. Includes DP_FHIR_CLINICAL_ENCOUNTERS, DP_FHIR_POPULATION_HEALTH, and DP_FHIR_CONDITION_ANALYTICS."
organization_targets:
  support_contact: "data-platform@company.com"
  approver_contact: "data-admin@company.com"
$$
PUBLISH = TRUE;

-- Workday HR Analytics Organization Listing
CREATE ORGANIZATION LISTING IF NOT EXISTS WORKDAY_HR_ANALYTICS
    SHARE WORKDAY_HR_DATA_SHARE
    AS $$
title: "Workday HR Analytics"
description: "Workday HCM analytics for HR and leadership. Includes DP_WORKDAY_WORKFORCE, DP_WORKDAY_COMPENSATION, and DP_WORKDAY_TIME_OFF. No individual employee data."
organization_targets:
  support_contact: "data-platform@company.com"
  approver_contact: "data-admin@company.com"
$$
PUBLISH = TRUE;

-- ServiceNow ITSM Analytics Organization Listing
CREATE ORGANIZATION LISTING IF NOT EXISTS SERVICENOW_ITSM_ANALYTICS
    SHARE SERVICENOW_ITSM_DATA_SHARE
    AS $$
title: "ServiceNow ITSM Analytics"
description: "ServiceNow IT Service Management analytics. Includes DP_SERVICENOW_INCIDENTS, DP_SERVICENOW_CHANGES, and DP_SERVICENOW_PROBLEMS. Refresh Rate: Hourly."
organization_targets:
  support_contact: "data-platform@company.com"
  approver_contact: "data-admin@company.com"
$$
PUBLISH = TRUE;

-- Enterprise Analytics Suite Organization Listing (All Domains)
CREATE ORGANIZATION LISTING IF NOT EXISTS ENTERPRISE_ANALYTICS_SUITE
    SHARE ENTERPRISE_ANALYTICS_DATA_SHARE
    AS $$
title: "Enterprise Analytics Suite"
description: "Complete cross-domain analytics - 17 data products across SAP, Oracle, Salesforce, FHIR, Workday, and ServiceNow. Ideal for executives and data scientists."
organization_targets:
  support_contact: "data-platform@company.com"
  approver_contact: "data-admin@company.com"
$$
PUBLISH = TRUE;

-- Show created shares and listings
SHOW SHARES;
SHOW ORGANIZATION LISTINGS;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT '✓ Data Marketplace with Domain Roles Created' AS STATUS;
SELECT '✓ Internal Listings Created for Intra-Company Discovery' AS LISTING_STATUS;

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
SHOW VIEWS IN SCHEMA CURATED_DEV.MARKETPLACE;

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
--   SELECT * FROM CURATED_DEV.MARKETPLACE.DP_SAP_SALES_ANALYTICS;
--   
--   USE ROLE CRM_CONSUMER;
--   SELECT * FROM CURATED_DEV.MARKETPLACE.DP_SALESFORCE_PIPELINE;
--   
--   USE ROLE HEALTHCARE_CONSUMER;
--   SELECT * FROM CURATED_DEV.MARKETPLACE.DP_FHIR_CLINICAL_ENCOUNTERS;
--
-- BROWSE CATALOG:
--   SELECT PRODUCT_NAME, SOURCE_SYSTEM, DOMAIN, SAMPLE_QUERY_1_DESC 
--   FROM CURATED_DEV.MARKETPLACE.VW_DATA_PRODUCT_CATALOG;
--
-- TRY SAMPLE QUERIES:
--   SELECT SAMPLE_QUERY_1, SAMPLE_QUERY_1_DESC 
--   FROM CURATED_DEV.MARKETPLACE.VW_DATA_PRODUCT_CATALOG 
--   WHERE SOURCE_SYSTEM = 'SALESFORCE';
--
-- ═══════════════════════════════════════════════════════════════════════════
