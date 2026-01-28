-- ============================================================================
-- SEMANTIC LAYER - Metadata-Driven Semantic Views for Cortex Analyst
-- ============================================================================
-- 
-- This script uses a metadata-driven approach to build semantic views:
--   1. SEMANTIC_CONFIG table stores all view definitions
--   2. BUILD_SEMANTIC_LAYER procedure reads config and creates views
--   3. Adding new views = inserting rows, not editing SQL
--
-- Schema Structure (one schema per source system):
--   SEM_DEV.SAP         - SAP semantic views
--   SEM_DEV.SALESFORCE  - Salesforce semantic views
--   SEM_DEV.ORACLE      - Oracle EBS semantic views
--   SEM_DEV.FHIR        - FHIR semantic views
--   SEM_DEV.WORKDAY     - Workday semantic views
--   SEM_DEV.SERVICENOW  - ServiceNow semantic views
--   SEM_DEV.MARKETPLACE - Cross-system aggregated views for sharing
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE SEM_DEV;
USE WAREHOUSE ANALYTICS_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- CREATE SCHEMAS
-- ═══════════════════════════════════════════════════════════════════════════

CREATE SCHEMA IF NOT EXISTS SEM_DEV.CONFIG
    COMMENT = 'Semantic layer configuration';

CREATE SCHEMA IF NOT EXISTS SEM_DEV.SAP
    COMMENT = 'SAP S/4HANA semantic views for Cortex Analyst';

CREATE SCHEMA IF NOT EXISTS SEM_DEV.SALESFORCE
    COMMENT = 'Salesforce CRM semantic views for Cortex Analyst';

CREATE SCHEMA IF NOT EXISTS SEM_DEV.ORACLE
    COMMENT = 'Oracle EBS semantic views for Cortex Analyst';

CREATE SCHEMA IF NOT EXISTS SEM_DEV.FHIR
    COMMENT = 'FHIR R4 healthcare semantic views for Cortex Analyst';

CREATE SCHEMA IF NOT EXISTS SEM_DEV.WORKDAY
    COMMENT = 'Workday HCM semantic views for Cortex Analyst';

CREATE SCHEMA IF NOT EXISTS SEM_DEV.SERVICENOW
    COMMENT = 'ServiceNow ITSM semantic views for Cortex Analyst';

CREATE SCHEMA IF NOT EXISTS SEM_DEV.MARKETPLACE
    COMMENT = 'Cross-system aggregated views for data sharing';

-- ═══════════════════════════════════════════════════════════════════════════
-- SEMANTIC CONFIGURATION TABLE
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA SEM_DEV.CONFIG;

DROP TABLE IF EXISTS SEM_DEV.CONFIG.SEMANTIC_CONFIG;

CREATE TABLE SEM_DEV.CONFIG.SEMANTIC_CONFIG (
    CONFIG_ID NUMBER AUTOINCREMENT PRIMARY KEY,
    SOURCE_SYSTEM VARCHAR(50) NOT NULL,
    VIEW_NAME VARCHAR(100) NOT NULL,
    VIEW_TYPE VARCHAR(30) DEFAULT 'SEMANTIC_VIEW',
    VIEW_SQL VARCHAR(32000) NOT NULL,
    VIEW_COMMENT VARCHAR(1000),
    IS_ACTIVE BOOLEAN DEFAULT TRUE,
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    
    CONSTRAINT UK_SEMANTIC_CONFIG UNIQUE (SOURCE_SYSTEM, VIEW_NAME)
);

-- ═══════════════════════════════════════════════════════════════════════════
-- SAP SEMANTIC VIEWS
-- ═══════════════════════════════════════════════════════════════════════════

INSERT INTO SEM_DEV.CONFIG.SEMANTIC_CONFIG 
    (SOURCE_SYSTEM, VIEW_NAME, VIEW_TYPE, VIEW_SQL, VIEW_COMMENT)
VALUES
-- SALES_ANALYTICS
('SAP', 'SALES_ANALYTICS', 'SEMANTIC_VIEW', '
CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.SAP.SALES_ANALYTICS
  TABLES (
    orders AS CURATED_DEV.SAP.FACT_SALES_ORDERS PRIMARY KEY (ORDER_KEY),
    customers AS CURATED_DEV.SAP.DIM_CUSTOMER PRIMARY KEY (CUSTOMER_KEY),
    dates AS CURATED_DEV.SHARED.DIM_DATE PRIMARY KEY (DATE_KEY)
  )
  RELATIONSHIPS (
    orders(CUSTOMER_KEY) REFERENCES customers(CUSTOMER_KEY),
    orders(ORDER_DATE) REFERENCES dates(DATE_KEY)
  )
  DIMENSIONS (
    dates.YEAR AS year,
    dates.QUARTER AS quarter,
    dates.MONTH_NAME AS month,
    dates.FISCAL_YEAR AS fiscal_year,
    customers.CUSTOMER_ID AS customer_id,
    customers.CUSTOMER_NAME AS customer_name,
    customers.CITY AS city,
    customers.COUNTRY AS country,
    customers.INDUSTRY_CODE AS industry_code,
    orders.ORDER_NUMBER AS order_number,
    orders.SALES_ORG AS sales_org,
    orders.ORDER_TYPE AS order_type,
    orders.ORDER_STATUS AS order_status
  )
  METRICS (
    orders.total_revenue AS SUM(orders.NET_VALUE),
    orders.order_count AS COUNT(orders.ORDER_KEY),
    customers.customer_count AS COUNT(DISTINCT customers.CUSTOMER_KEY)
  )
  COMMENT = ''SAP Sales Analytics - Orders and Customers''
', 'SAP Sales Orders with customers'),

-- PROCUREMENT_ANALYTICS
('SAP', 'PROCUREMENT_ANALYTICS', 'SEMANTIC_VIEW', '
CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.SAP.PROCUREMENT_ANALYTICS
  TABLES (
    purchase_orders AS CURATED_DEV.SAP.FACT_PURCHASE_ORDERS PRIMARY KEY (PO_KEY),
    vendors AS CURATED_DEV.SAP.DIM_VENDOR PRIMARY KEY (VENDOR_KEY),
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
    dates.FISCAL_YEAR AS fiscal_year,
    vendors.VENDOR_ID AS vendor_id,
    vendors.VENDOR_NAME AS vendor_name,
    vendors.COUNTRY AS country,
    purchase_orders.PO_NUMBER AS po_number,
    purchase_orders.PURCHASING_ORG AS purchasing_org,
    purchase_orders.PO_TYPE AS po_type,
    purchase_orders.STATUS AS status
  )
  METRICS (
    purchase_orders.po_count AS COUNT(purchase_orders.PO_KEY),
    purchase_orders.total_value AS SUM(purchase_orders.TOTAL_VALUE),
    vendors.vendor_count AS COUNT(DISTINCT vendors.VENDOR_KEY)
  )
  COMMENT = ''SAP Procurement Analytics - Purchase Orders and Vendors''
', 'SAP Purchase Orders with vendor dimension'),

-- FINANCE_ANALYTICS
('SAP', 'FINANCE_ANALYTICS', 'SEMANTIC_VIEW', '
CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.SAP.FINANCE_ANALYTICS
  TABLES (
    documents AS CURATED_DEV.SAP.FACT_ACCOUNTING_DOCUMENTS PRIMARY KEY (DOC_KEY),
    dates AS CURATED_DEV.SHARED.DIM_DATE PRIMARY KEY (DATE_KEY)
  )
  RELATIONSHIPS (
    documents(POSTING_DATE) REFERENCES dates(DATE_KEY)
  )
  DIMENSIONS (
    dates.YEAR AS year,
    dates.QUARTER AS quarter,
    dates.MONTH_NAME AS month,
    dates.FISCAL_YEAR AS fiscal_year,
    
    documents.COMPANY_CODE AS company_code,
    documents.DOCUMENT_NUMBER AS document_number,
    documents.DOCUMENT_TYPE AS document_type,
    documents.FISCAL_PERIOD AS fiscal_period,
    documents.CURRENCY AS currency,
    documents.DOCUMENT_STATUS AS document_status,
    documents.CREATED_BY AS created_by
  )
  METRICS (
    documents.document_count AS COUNT(documents.DOC_KEY)
  )
  COMMENT = ''SAP Finance Analytics - Accounting Documents''
', 'SAP Accounting Documents for financial analysis');

-- ═══════════════════════════════════════════════════════════════════════════
-- SALESFORCE SEMANTIC VIEWS
-- ═══════════════════════════════════════════════════════════════════════════

INSERT INTO SEM_DEV.CONFIG.SEMANTIC_CONFIG 
    (SOURCE_SYSTEM, VIEW_NAME, VIEW_TYPE, VIEW_SQL, VIEW_COMMENT)
VALUES
-- PIPELINE_ANALYTICS
('SALESFORCE', 'PIPELINE_ANALYTICS', 'SEMANTIC_VIEW', '
CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.SALESFORCE.PIPELINE_ANALYTICS
  TABLES (
    opportunities AS CURATED_DEV.SALESFORCE.FACT_OPPORTUNITIES PRIMARY KEY (OPPORTUNITY_KEY),
    accounts AS CURATED_DEV.SALESFORCE.DIM_ACCOUNT PRIMARY KEY (ACCOUNT_KEY),
    dates AS CURATED_DEV.SHARED.DIM_DATE PRIMARY KEY (DATE_KEY)
  )
  RELATIONSHIPS (
    opportunities(ACCOUNT_KEY) REFERENCES accounts(ACCOUNT_KEY),
    opportunities(CLOSE_DATE) REFERENCES dates(DATE_KEY)
  )
  DIMENSIONS (
    dates.YEAR AS year,
    dates.QUARTER AS quarter,
    dates.MONTH_NAME AS month,
    dates.FISCAL_YEAR AS fiscal_year,
    accounts.ACCOUNT_ID AS account_id,
    accounts.ACCOUNT_NAME AS account_name,
    accounts.ACCOUNT_TYPE AS account_type,
    accounts.INDUSTRY AS industry,
    accounts.ACCOUNT_TIER AS account_tier,
    accounts.BILLING_STATE AS billing_state,
    accounts.BILLING_COUNTRY AS billing_country,
    opportunities.OPPORTUNITY_ID AS opportunity_id,
    opportunities.OPPORTUNITY_NAME AS opportunity_name,
    opportunities.STAGE_NAME AS stage_name,
    opportunities.OPPORTUNITY_TYPE AS opportunity_type,
    opportunities.LEAD_SOURCE AS lead_source,
    opportunities.FORECAST_CATEGORY AS forecast_category
  )
  METRICS (
    opportunities.total_pipeline AS SUM(opportunities.AMOUNT),
    opportunities.avg_deal_size AS AVG(opportunities.AMOUNT),
    opportunities.opportunity_count AS COUNT(opportunities.OPPORTUNITY_KEY),
    accounts.account_count AS COUNT(DISTINCT accounts.ACCOUNT_KEY)
  )
  COMMENT = ''Salesforce Pipeline Analytics - Opportunities and Accounts''
', 'Salesforce Opportunity pipeline with accounts'),

-- CUSTOMER_360 (simplified)
('SALESFORCE', 'CUSTOMER_360', 'SEMANTIC_VIEW', '
CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.SALESFORCE.CUSTOMER_360
  TABLES (
    accounts AS CURATED_DEV.SALESFORCE.DIM_ACCOUNT PRIMARY KEY (ACCOUNT_KEY),
    contacts AS CURATED_DEV.SALESFORCE.DIM_CONTACT PRIMARY KEY (CONTACT_KEY),
    opportunities AS CURATED_DEV.SALESFORCE.FACT_OPPORTUNITIES PRIMARY KEY (OPPORTUNITY_KEY)
  )
  RELATIONSHIPS (
    contacts(ACCOUNT_KEY) REFERENCES accounts(ACCOUNT_KEY),
    opportunities(ACCOUNT_KEY) REFERENCES accounts(ACCOUNT_KEY)
  )
  DIMENSIONS (
    accounts.ACCOUNT_NAME AS account_name,
    accounts.ACCOUNT_TYPE AS account_type,
    accounts.INDUSTRY AS industry,
    accounts.ACCOUNT_TIER AS account_tier,
    accounts.ANNUAL_REVENUE AS annual_revenue,
    accounts.EMPLOYEE_COUNT AS employee_count,
    accounts.BILLING_CITY AS billing_city,
    accounts.BILLING_COUNTRY AS billing_country,
    contacts.FIRST_NAME AS first_name,
    contacts.LAST_NAME AS last_name,
    contacts.TITLE AS title
  )
  METRICS (
    accounts.total_accounts AS COUNT(DISTINCT accounts.ACCOUNT_KEY),
    contacts.contact_count AS COUNT(DISTINCT contacts.CONTACT_KEY),
    opportunities.total_opportunity_value AS SUM(opportunities.AMOUNT),
    opportunities.opportunity_count AS COUNT(DISTINCT opportunities.OPPORTUNITY_KEY)
  )
  COMMENT = ''Salesforce Customer 360 - Accounts, Contacts, Opportunities''
', 'Complete customer view across Salesforce objects'),

-- MARKETING_ANALYTICS (simplified - campaigns only)
('SALESFORCE', 'MARKETING_ANALYTICS', 'SEMANTIC_VIEW', '
CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.SALESFORCE.MARKETING_ANALYTICS
  TABLES (
    campaigns AS CURATED_DEV.SALESFORCE.DIM_CAMPAIGN PRIMARY KEY (CAMPAIGN_KEY)
  )
  DIMENSIONS (
    campaigns.CAMPAIGN_NAME AS campaign_name,
    campaigns.CAMPAIGN_TYPE AS campaign_type,
    campaigns.STATUS AS status
  )
  METRICS (
    campaigns.campaign_count AS COUNT(DISTINCT campaigns.CAMPAIGN_KEY),
    campaigns.total_budget AS SUM(campaigns.BUDGETED_COST),
    campaigns.total_actual_cost AS SUM(campaigns.ACTUAL_COST),
    campaigns.total_expected_revenue AS SUM(campaigns.EXPECTED_REVENUE)
  )
  COMMENT = ''Salesforce Marketing Analytics - Campaigns''
', 'Marketing campaign analytics');

-- ═══════════════════════════════════════════════════════════════════════════
-- ORACLE EBS SEMANTIC VIEWS
-- ═══════════════════════════════════════════════════════════════════════════

INSERT INTO SEM_DEV.CONFIG.SEMANTIC_CONFIG 
    (SOURCE_SYSTEM, VIEW_NAME, VIEW_TYPE, VIEW_SQL, VIEW_COMMENT)
VALUES
-- ORDER_ANALYTICS (simplified)
('ORACLE', 'ORDER_ANALYTICS', 'SEMANTIC_VIEW', '
CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.ORACLE.ORDER_ANALYTICS
  TABLES (
    orders AS CURATED_DEV.ORACLE.FACT_ORDER_HEADERS PRIMARY KEY (ORDER_KEY),
    parties AS CURATED_DEV.ORACLE.DIM_PARTY PRIMARY KEY (PARTY_KEY),
    dates AS CURATED_DEV.SHARED.DIM_DATE PRIMARY KEY (DATE_KEY)
  )
  RELATIONSHIPS (
    orders(CUSTOMER_KEY) REFERENCES parties(PARTY_KEY),
    orders(ORDER_DATE) REFERENCES dates(DATE_KEY)
  )
  DIMENSIONS (
    dates.YEAR AS year,
    dates.QUARTER AS quarter,
    dates.MONTH_NAME AS month,
    parties.PARTY_NAME AS party_name,
    parties.PARTY_TYPE AS party_type,
    parties.CITY AS city,
    parties.COUNTRY AS country,
    orders.ORDER_NUMBER AS order_number,
    orders.STATUS AS status,
    orders.SHIPPING_METHOD AS shipping_method
  )
  METRICS (
    orders.order_count AS COUNT(DISTINCT orders.ORDER_KEY),
    parties.customer_count AS COUNT(DISTINCT parties.PARTY_KEY)
  )
  COMMENT = ''Oracle EBS Order Analytics - Orders and Customers''
', 'Oracle order management analytics'),

-- AP_ANALYTICS (simplified)
('ORACLE', 'AP_ANALYTICS', 'SEMANTIC_VIEW', '
CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.ORACLE.AP_ANALYTICS
  TABLES (
    invoices AS CURATED_DEV.ORACLE.FACT_AP_INVOICES PRIMARY KEY (INVOICE_KEY),
    vendors AS CURATED_DEV.ORACLE.DIM_VENDOR PRIMARY KEY (VENDOR_KEY),
    dates AS CURATED_DEV.SHARED.DIM_DATE PRIMARY KEY (DATE_KEY)
  )
  RELATIONSHIPS (
    invoices(VENDOR_KEY) REFERENCES vendors(VENDOR_KEY),
    invoices(INVOICE_DATE) REFERENCES dates(DATE_KEY)
  )
  DIMENSIONS (
    dates.YEAR AS year,
    dates.QUARTER AS quarter,
    dates.MONTH_NAME AS month,
    vendors.VENDOR_NAME AS vendor_name,
    vendors.VENDOR_TYPE AS vendor_type,
    vendors.PAYMENT_METHOD AS payment_method,
    invoices.INVOICE_NUMBER AS invoice_number,
    invoices.INVOICE_TYPE AS invoice_type,
    invoices.CURRENCY AS currency,
    invoices.PAYMENT_STATUS AS payment_status,
    invoices.APPROVAL_STATUS AS approval_status
  )
  METRICS (
    invoices.invoice_count AS COUNT(invoices.INVOICE_KEY),
    invoices.total_invoice_amount AS SUM(invoices.INVOICE_AMOUNT),
    invoices.avg_invoice_amount AS AVG(invoices.INVOICE_AMOUNT),
    vendors.vendor_count AS COUNT(DISTINCT vendors.VENDOR_KEY)
  )
  COMMENT = ''Oracle AP Analytics - Payables Invoices and Vendors''
', 'Oracle Accounts Payable analytics'),

-- AR_ANALYTICS (simplified)
('ORACLE', 'AR_ANALYTICS', 'SEMANTIC_VIEW', '
CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.ORACLE.AR_ANALYTICS
  TABLES (
    invoices AS CURATED_DEV.ORACLE.FACT_AR_INVOICES PRIMARY KEY (INVOICE_KEY),
    parties AS CURATED_DEV.ORACLE.DIM_PARTY PRIMARY KEY (PARTY_KEY),
    dates AS CURATED_DEV.SHARED.DIM_DATE PRIMARY KEY (DATE_KEY)
  )
  RELATIONSHIPS (
    invoices(CUSTOMER_KEY) REFERENCES parties(PARTY_KEY),
    invoices(INVOICE_DATE) REFERENCES dates(DATE_KEY)
  )
  DIMENSIONS (
    dates.YEAR AS year,
    dates.QUARTER AS quarter,
    dates.MONTH_NAME AS month,
    parties.PARTY_NAME AS party_name,
    parties.PARTY_TYPE AS party_type,
    invoices.INVOICE_NUMBER AS invoice_number,
    invoices.CURRENCY AS currency,
    invoices.STATUS AS status
  )
  METRICS (
    invoices.invoice_count AS COUNT(invoices.INVOICE_KEY),
    parties.customer_count AS COUNT(DISTINCT parties.PARTY_KEY)
  )
  COMMENT = ''Oracle AR Analytics - Receivables Invoices and Customers''
', 'Oracle Accounts Receivable analytics'),

-- GL_ANALYTICS
('ORACLE', 'GL_ANALYTICS', 'SEMANTIC_VIEW', '
CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.ORACLE.GL_ANALYTICS
  TABLES (
    journal_lines AS CURATED_DEV.ORACLE.FACT_GL_JOURNAL_LINES PRIMARY KEY (LINE_KEY),
    dates AS CURATED_DEV.SHARED.DIM_DATE PRIMARY KEY (DATE_KEY)
  )
  RELATIONSHIPS (
    journal_lines(EFFECTIVE_DATE) REFERENCES dates(DATE_KEY)
  )
  DIMENSIONS (
    dates.YEAR AS year,
    dates.QUARTER AS quarter,
    dates.MONTH_NAME AS month,
    
    journal_lines.PERIOD_NAME AS period_name,
    journal_lines.LEDGER_ID AS ledger_id,
    journal_lines.DESCRIPTION AS description,
    journal_lines.STATUS AS status
  )
  METRICS (
    journal_lines.line_count AS COUNT(journal_lines.LINE_KEY),
    journal_lines.total_debits AS SUM(journal_lines.ENTERED_DEBIT),
    journal_lines.total_credits AS SUM(journal_lines.ENTERED_CREDIT),
    journal_lines.net_amount AS SUM(COALESCE(journal_lines.ENTERED_DEBIT, 0) - COALESCE(journal_lines.ENTERED_CREDIT, 0))
  )
  COMMENT = ''Oracle GL Analytics - General Ledger Journal Lines''
', 'Oracle General Ledger analytics');

-- ═══════════════════════════════════════════════════════════════════════════
-- FHIR SEMANTIC VIEWS
-- ═══════════════════════════════════════════════════════════════════════════

INSERT INTO SEM_DEV.CONFIG.SEMANTIC_CONFIG 
    (SOURCE_SYSTEM, VIEW_NAME, VIEW_TYPE, VIEW_SQL, VIEW_COMMENT)
VALUES
-- CLINICAL_ANALYTICS (simplified)
('FHIR', 'CLINICAL_ANALYTICS', 'SEMANTIC_VIEW', '
CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.FHIR.CLINICAL_ANALYTICS
  TABLES (
    encounters AS CURATED_DEV.FHIR.FACT_ENCOUNTERS PRIMARY KEY (ENCOUNTER_KEY),
    patients AS CURATED_DEV.FHIR.DIM_PATIENT PRIMARY KEY (PATIENT_KEY)
  )
  RELATIONSHIPS (
    encounters(PATIENT_KEY) REFERENCES patients(PATIENT_KEY)
  )
  DIMENSIONS (
    patients.PATIENT_ID AS patient_id,
    patients.GENDER AS gender,
    patients.CITY AS city,
    patients.STATE AS state,
    encounters.ENCOUNTER_ID AS encounter_id,
    encounters.ENCOUNTER_CLASS AS encounter_class,
    encounters.ENCOUNTER_TYPE AS encounter_type,
    encounters.STATUS AS status
  )
  METRICS (
    encounters.encounter_count AS COUNT(encounters.ENCOUNTER_KEY),
    patients.patient_count AS COUNT(DISTINCT patients.PATIENT_KEY)
  )
  COMMENT = ''FHIR Clinical Analytics - Encounters and Patients''
', 'FHIR clinical encounters'),

-- MEDICATION_ANALYTICS (simplified)
('FHIR', 'MEDICATION_ANALYTICS', 'SEMANTIC_VIEW', '
CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.FHIR.MEDICATION_ANALYTICS
  TABLES (
    medication_requests AS CURATED_DEV.FHIR.FACT_MEDICATION_REQUESTS PRIMARY KEY (MEDICATION_REQUEST_KEY),
    patients AS CURATED_DEV.FHIR.DIM_PATIENT PRIMARY KEY (PATIENT_KEY)
  )
  RELATIONSHIPS (
    medication_requests(PATIENT_KEY) REFERENCES patients(PATIENT_KEY)
  )
  DIMENSIONS (
    patients.PATIENT_ID AS patient_id,
    patients.GENDER AS gender,
    patients.STATE AS state,
    medication_requests.MEDICATION_CODE AS medication_code,
    medication_requests.MEDICATION_NAME AS medication_name,
    medication_requests.STATUS AS status,
    medication_requests.INTENT AS intent
  )
  METRICS (
    medication_requests.prescription_count AS COUNT(medication_requests.MEDICATION_REQUEST_KEY),
    patients.patient_count AS COUNT(DISTINCT patients.PATIENT_KEY)
  )
  COMMENT = ''FHIR Medication Analytics - Prescriptions and Patients''
', 'FHIR medication prescriptions'),

-- CLAIMS_ANALYTICS (simplified)
('FHIR', 'CLAIMS_ANALYTICS', 'SEMANTIC_VIEW', '
CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.FHIR.CLAIMS_ANALYTICS
  TABLES (
    claims AS CURATED_DEV.FHIR.FACT_CLAIMS PRIMARY KEY (CLAIM_KEY),
    patients AS CURATED_DEV.FHIR.DIM_PATIENT PRIMARY KEY (PATIENT_KEY)
  )
  RELATIONSHIPS (
    claims(PATIENT_KEY) REFERENCES patients(PATIENT_KEY)
  )
  DIMENSIONS (
    patients.PATIENT_ID AS patient_id,
    patients.GENDER AS gender,
    patients.STATE AS state,
    claims.CLAIM_TYPE AS claim_type,
    claims.STATUS AS status,
    claims.CLAIM_USE AS claim_use,
    claims.PRIORITY AS priority,
    claims.CURRENCY AS currency
  )
  METRICS (
    claims.claim_count AS COUNT(claims.CLAIM_KEY),
    claims.total_amount AS SUM(claims.TOTAL_AMOUNT),
    claims.avg_claim_amount AS AVG(claims.TOTAL_AMOUNT),
    patients.patient_count AS COUNT(DISTINCT patients.PATIENT_KEY)
  )
  COMMENT = ''FHIR Claims Analytics - Healthcare Claims and Patients''
', 'FHIR healthcare claims analytics');

-- ═══════════════════════════════════════════════════════════════════════════
-- WORKDAY SEMANTIC VIEWS
-- ═══════════════════════════════════════════════════════════════════════════

INSERT INTO SEM_DEV.CONFIG.SEMANTIC_CONFIG 
    (SOURCE_SYSTEM, VIEW_NAME, VIEW_TYPE, VIEW_SQL, VIEW_COMMENT)
VALUES
-- WORKFORCE_ANALYTICS (simplified)
('WORKDAY', 'WORKFORCE_ANALYTICS', 'SEMANTIC_VIEW', '
CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.WORKDAY.WORKFORCE_ANALYTICS
  TABLES (
    employees AS CURATED_DEV.WORKDAY.DIM_EMPLOYEE PRIMARY KEY (EMPLOYEE_KEY)
  )
  DIMENSIONS (
    employees.EMPLOYEE_ID AS employee_id,
    employees.FIRST_NAME AS first_name,
    employees.LAST_NAME AS last_name,
    employees.WORKER_TYPE AS worker_type,
    employees.JOB_TITLE AS job_title,
    employees.JOB_LEVEL AS job_level,
    employees.DEPARTMENT AS department,
    employees.WORK_LOCATION AS work_location,
    employees.CITY AS city,
    employees.STATE AS state,
    employees.COUNTRY AS country
  )
  METRICS (
    employees.headcount AS COUNT(employees.EMPLOYEE_KEY)
  )
  COMMENT = ''Workday Workforce Analytics - Employees''
', 'Workday workforce analytics'),

-- COMPENSATION_ANALYTICS (simplified)
('WORKDAY', 'COMPENSATION_ANALYTICS', 'SEMANTIC_VIEW', '
CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.WORKDAY.COMPENSATION_ANALYTICS
  TABLES (
    compensation AS CURATED_DEV.WORKDAY.FACT_COMPENSATION PRIMARY KEY (COMPENSATION_KEY),
    employees AS CURATED_DEV.WORKDAY.DIM_EMPLOYEE PRIMARY KEY (EMPLOYEE_KEY)
  )
  RELATIONSHIPS (
    compensation(EMPLOYEE_KEY) REFERENCES employees(EMPLOYEE_KEY)
  )
  DIMENSIONS (
    employees.EMPLOYEE_ID AS employee_id,
    employees.JOB_TITLE AS job_title,
    employees.JOB_LEVEL AS job_level,
    employees.DEPARTMENT AS department,
    compensation.PAY_FREQUENCY AS pay_frequency,
    compensation.CURRENCY AS currency
  )
  METRICS (
    compensation.total_base_pay AS SUM(compensation.BASE_PAY_AMOUNT),
    compensation.avg_base_pay AS AVG(compensation.BASE_PAY_AMOUNT),
    compensation.total_compensation AS SUM(compensation.TOTAL_COMPENSATION),
    compensation.avg_total_comp AS AVG(compensation.TOTAL_COMPENSATION),
    employees.employee_count AS COUNT(DISTINCT employees.EMPLOYEE_KEY)
  )
  COMMENT = ''Workday Compensation Analytics - Pay and Grade''
', 'Workday compensation analytics'),

-- TIME_OFF_ANALYTICS (simplified)
('WORKDAY', 'TIME_OFF_ANALYTICS', 'SEMANTIC_VIEW', '
CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.WORKDAY.TIME_OFF_ANALYTICS
  TABLES (
    time_off AS CURATED_DEV.WORKDAY.FACT_TIME_OFF PRIMARY KEY (TIME_OFF_KEY),
    employees AS CURATED_DEV.WORKDAY.DIM_EMPLOYEE PRIMARY KEY (EMPLOYEE_KEY)
  )
  RELATIONSHIPS (
    time_off(EMPLOYEE_KEY) REFERENCES employees(EMPLOYEE_KEY)
  )
  DIMENSIONS (
    employees.EMPLOYEE_ID AS employee_id,
    employees.DEPARTMENT AS department,
    time_off.TIME_OFF_TYPE AS time_off_type,
    time_off.STATUS AS status
  )
  METRICS (
    time_off.request_count AS COUNT(time_off.TIME_OFF_KEY),
    time_off.total_days AS SUM(time_off.TOTAL_DAYS),
    time_off.total_hours AS SUM(time_off.TOTAL_HOURS),
    employees.employee_count AS COUNT(DISTINCT employees.EMPLOYEE_KEY)
  )
  COMMENT = ''Workday Time Off Analytics - Leave Requests''
', 'Workday time off analytics'),

-- BENEFITS_ANALYTICS (simplified)
('WORKDAY', 'BENEFITS_ANALYTICS', 'SEMANTIC_VIEW', '
CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.WORKDAY.BENEFITS_ANALYTICS
  TABLES (
    benefits AS CURATED_DEV.WORKDAY.FACT_BENEFITS PRIMARY KEY (BENEFIT_KEY),
    employees AS CURATED_DEV.WORKDAY.DIM_EMPLOYEE PRIMARY KEY (EMPLOYEE_KEY)
  )
  RELATIONSHIPS (
    benefits(EMPLOYEE_KEY) REFERENCES employees(EMPLOYEE_KEY)
  )
  DIMENSIONS (
    employees.EMPLOYEE_ID AS employee_id,
    employees.DEPARTMENT AS department,
    benefits.BENEFIT_PLAN_TYPE AS plan_type,
    benefits.BENEFIT_PLAN_NAME AS plan_name,
    benefits.COVERAGE_LEVEL AS coverage_level
  )
  METRICS (
    benefits.enrollment_count AS COUNT(benefits.BENEFIT_KEY),
    benefits.total_employee_cost AS SUM(benefits.EMPLOYEE_COST),
    benefits.total_employer_cost AS SUM(benefits.EMPLOYER_COST),
    employees.employee_count AS COUNT(DISTINCT employees.EMPLOYEE_KEY)
  )
  COMMENT = ''Workday Benefits Analytics - Benefit Enrollments''
', 'Workday benefits analytics');

-- ═══════════════════════════════════════════════════════════════════════════
-- SERVICENOW SEMANTIC VIEWS
-- ═══════════════════════════════════════════════════════════════════════════

INSERT INTO SEM_DEV.CONFIG.SEMANTIC_CONFIG 
    (SOURCE_SYSTEM, VIEW_NAME, VIEW_TYPE, VIEW_SQL, VIEW_COMMENT)
VALUES
-- INCIDENT_ANALYTICS (simplified)
('SERVICENOW', 'INCIDENT_ANALYTICS', 'SEMANTIC_VIEW', '
CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.SERVICENOW.INCIDENT_ANALYTICS
  TABLES (
    incidents AS CURATED_DEV.SERVICENOW.FACT_INCIDENTS PRIMARY KEY (INCIDENT_KEY),
    users AS CURATED_DEV.SERVICENOW.DIM_USER PRIMARY KEY (USER_KEY)
  )
  RELATIONSHIPS (
    incidents(CALLER_KEY) REFERENCES users(USER_KEY)
  )
  DIMENSIONS (
    users.USERNAME AS username,
    users.FIRST_NAME AS first_name,
    users.LAST_NAME AS last_name,
    users.DEPARTMENT AS department,
    users.LOCATION AS location,
    incidents.INCIDENT_NUMBER AS incident_number,
    incidents.PRIORITY AS priority,
    incidents.URGENCY AS urgency,
    incidents.IMPACT AS impact,
    incidents.STATE AS state,
    incidents.CATEGORY AS category,
    incidents.SUBCATEGORY AS subcategory,
    incidents.ASSIGNMENT_GROUP AS assignment_group
  )
  METRICS (
    incidents.incident_count AS COUNT(incidents.INCIDENT_KEY),
    users.user_count AS COUNT(DISTINCT users.USER_KEY)
  )
  COMMENT = ''ServiceNow Incident Analytics - Incidents and Users''
', 'ServiceNow incident analytics'),

-- CHANGE_ANALYTICS (simplified)
('SERVICENOW', 'CHANGE_ANALYTICS', 'SEMANTIC_VIEW', '
CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.SERVICENOW.CHANGE_ANALYTICS
  TABLES (
    changes AS CURATED_DEV.SERVICENOW.FACT_CHANGES PRIMARY KEY (CHANGE_KEY),
    users AS CURATED_DEV.SERVICENOW.DIM_USER PRIMARY KEY (USER_KEY)
  )
  RELATIONSHIPS (
    changes(REQUESTED_BY_KEY) REFERENCES users(USER_KEY)
  )
  DIMENSIONS (
    users.USERNAME AS username,
    users.DEPARTMENT AS department,
    changes.CHANGE_NUMBER AS change_number,
    changes.CHANGE_TYPE AS change_type,
    changes.RISK AS risk,
    changes.IMPACT AS impact,
    changes.STATE AS state,
    changes.CATEGORY AS category,
    changes.ASSIGNMENT_GROUP AS assignment_group
  )
  METRICS (
    changes.change_count AS COUNT(changes.CHANGE_KEY),
    users.user_count AS COUNT(DISTINCT users.USER_KEY)
  )
  COMMENT = ''ServiceNow Change Analytics - Change Requests and Users''
', 'ServiceNow change analytics'),

-- PROBLEM_ANALYTICS (simplified)
('SERVICENOW', 'PROBLEM_ANALYTICS', 'SEMANTIC_VIEW', '
CREATE OR REPLACE SEMANTIC VIEW SEM_DEV.SERVICENOW.PROBLEM_ANALYTICS
  TABLES (
    problems AS CURATED_DEV.SERVICENOW.FACT_PROBLEMS PRIMARY KEY (PROBLEM_KEY),
    users AS CURATED_DEV.SERVICENOW.DIM_USER PRIMARY KEY (USER_KEY)
  )
  RELATIONSHIPS (
    problems(OPENED_BY_KEY) REFERENCES users(USER_KEY)
  )
  DIMENSIONS (
    users.USERNAME AS username,
    users.DEPARTMENT AS department,
    problems.PROBLEM_NUMBER AS problem_number,
    problems.PRIORITY AS priority,
    problems.URGENCY AS urgency,
    problems.IMPACT AS impact,
    problems.STATE AS state,
    problems.ASSIGNMENT_GROUP AS assignment_group
  )
  METRICS (
    problems.problem_count AS COUNT(problems.PROBLEM_KEY),
    users.user_count AS COUNT(DISTINCT users.USER_KEY)
  )
  COMMENT = ''ServiceNow Problem Analytics - Problems, Users, CIs''
', 'ServiceNow problem management analytics');

-- ═══════════════════════════════════════════════════════════════════════════
-- BUILD PROCEDURE
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE SEM_DEV.CONFIG.BUILD_SEMANTIC_LAYER(
    P_SOURCE_SYSTEM VARCHAR
)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var results = [];
    var sourceSystem = P_SOURCE_SYSTEM.toUpperCase();
    var targetSchema = 'SEM_DEV.' + sourceSystem;
    
    var configSql = `
        SELECT 
            VIEW_NAME,
            VIEW_TYPE,
            VIEW_SQL,
            VIEW_COMMENT
        FROM SEM_DEV.CONFIG.SEMANTIC_CONFIG
        WHERE SOURCE_SYSTEM = '${sourceSystem}'
          AND IS_ACTIVE = TRUE
        ORDER BY VIEW_NAME
    `;
    
    try {
        var configStmt = snowflake.createStatement({sqlText: configSql});
        var configResult = configStmt.execute();
        
        var viewCount = 0;
        
        while (configResult.next()) {
            var viewName = configResult.getColumnValue('VIEW_NAME');
            var viewSql = configResult.getColumnValue('VIEW_SQL');
            
            try {
                snowflake.createStatement({sqlText: viewSql}).execute();
                results.push({
                    view: viewName, 
                    status: 'SUCCESS'
                });
                viewCount++;
            } catch (err) {
                results.push({
                    view: viewName, 
                    status: 'ERROR',
                    message: err.message
                });
            }
        }
        
        if (viewCount === 0 && results.length === 0) {
            return {
                status: 'WARNING',
                message: 'No configurations found for source system: ' + sourceSystem,
                source_system: sourceSystem
            };
        }
        
        var successCount = results.filter(function(r) { return r.status === 'SUCCESS'; }).length;
        var errorCount = results.filter(function(r) { return r.status === 'ERROR'; }).length;
        
        return {
            status: errorCount === 0 ? 'SUCCESS' : (successCount > 0 ? 'PARTIAL' : 'FAILED'),
            source_system: sourceSystem,
            target_schema: targetSchema,
            views_created: successCount,
            views_failed: errorCount,
            details: results
        };
        
    } catch (err) {
        return {status: 'ERROR', message: err.message};
    }
$$;

-- Build all semantic layers
CREATE OR REPLACE PROCEDURE SEM_DEV.CONFIG.BUILD_ALL_SEMANTIC_LAYERS()
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var results = [];
    var sourceSystems = ['SAP', 'SALESFORCE', 'ORACLE', 'FHIR', 'WORKDAY', 'SERVICENOW'];
    
    for (var i = 0; i < sourceSystems.length; i++) {
        var system = sourceSystems[i];
        try {
            var callSql = "CALL SEM_DEV.CONFIG.BUILD_SEMANTIC_LAYER('" + system + "')";
            var stmt = snowflake.createStatement({sqlText: callSql});
            var result = stmt.execute();
            result.next();
            var buildResult = result.getColumnValue(1);
            results.push({
                source_system: system,
                result: buildResult
            });
        } catch (err) {
            results.push({
                source_system: system,
                result: {status: 'ERROR', message: err.message}
            });
        }
    }
    
    var totalSuccess = 0;
    var totalFailed = 0;
    
    for (var j = 0; j < results.length; j++) {
        if (results[j].result && results[j].result.views_created) {
            totalSuccess += results[j].result.views_created;
        }
        if (results[j].result && results[j].result.views_failed) {
            totalFailed += results[j].result.views_failed;
        }
    }
    
    return {
        status: totalFailed === 0 ? 'SUCCESS' : 'PARTIAL',
        total_views_created: totalSuccess,
        total_views_failed: totalFailed,
        systems: results
    };
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- MARKETPLACE VIEWS (Cross-system, no PII)
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

-- Configuration summary view
CREATE OR REPLACE VIEW SEM_DEV.CONFIG.V_SEMANTIC_CONFIG_SUMMARY AS
SELECT 
    SOURCE_SYSTEM,
    VIEW_TYPE,
    COUNT(*) AS VIEW_COUNT,
    SUM(CASE WHEN IS_ACTIVE THEN 1 ELSE 0 END) AS ACTIVE_COUNT
FROM SEM_DEV.CONFIG.SEMANTIC_CONFIG
GROUP BY SOURCE_SYSTEM, VIEW_TYPE
ORDER BY SOURCE_SYSTEM;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

-- Grant schema usage
GRANT USAGE ON SCHEMA SEM_DEV.CONFIG TO ROLE DATA_ENGINEER;
GRANT USAGE ON SCHEMA SEM_DEV.SAP TO ROLE ANALYST;
GRANT USAGE ON SCHEMA SEM_DEV.SALESFORCE TO ROLE ANALYST;
GRANT USAGE ON SCHEMA SEM_DEV.ORACLE TO ROLE ANALYST;
GRANT USAGE ON SCHEMA SEM_DEV.FHIR TO ROLE ANALYST;
GRANT USAGE ON SCHEMA SEM_DEV.WORKDAY TO ROLE MANAGER;
GRANT USAGE ON SCHEMA SEM_DEV.SERVICENOW TO ROLE ANALYST;
GRANT USAGE ON SCHEMA SEM_DEV.MARKETPLACE TO ROLE VIEWER;

-- Grant select on config
GRANT SELECT ON TABLE SEM_DEV.CONFIG.SEMANTIC_CONFIG TO ROLE DATA_ENGINEER;
GRANT SELECT ON VIEW SEM_DEV.CONFIG.V_SEMANTIC_CONFIG_SUMMARY TO ROLE DATA_ENGINEER;

-- Grant select on marketplace views
GRANT SELECT ON ALL VIEWS IN SCHEMA SEM_DEV.MARKETPLACE TO ROLE VIEWER;
GRANT SELECT ON ALL VIEWS IN SCHEMA SEM_DEV.MARKETPLACE TO ROLE EXTERNAL_PARTNER;

-- Grant procedure usage
GRANT USAGE ON PROCEDURE SEM_DEV.CONFIG.BUILD_SEMANTIC_LAYER(VARCHAR) TO ROLE DATA_ENGINEER;
GRANT USAGE ON PROCEDURE SEM_DEV.CONFIG.BUILD_ALL_SEMANTIC_LAYERS() TO ROLE DATA_ENGINEER;

-- Future grants
GRANT SELECT ON FUTURE VIEWS IN SCHEMA SEM_DEV.MARKETPLACE TO ROLE VIEWER;

-- ═══════════════════════════════════════════════════════════════════════════
-- USAGE INSTRUCTIONS
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- View configuration summary:
--   SELECT * FROM SEM_DEV.CONFIG.V_SEMANTIC_CONFIG_SUMMARY;
--
-- Build semantic layer for a single source system:
--   CALL SEM_DEV.CONFIG.BUILD_SEMANTIC_LAYER('SAP');
--   CALL SEM_DEV.CONFIG.BUILD_SEMANTIC_LAYER('SALESFORCE');
--   CALL SEM_DEV.CONFIG.BUILD_SEMANTIC_LAYER('ORACLE');
--   CALL SEM_DEV.CONFIG.BUILD_SEMANTIC_LAYER('FHIR');
--   CALL SEM_DEV.CONFIG.BUILD_SEMANTIC_LAYER('WORKDAY');
--   CALL SEM_DEV.CONFIG.BUILD_SEMANTIC_LAYER('SERVICENOW');
--
-- Build ALL semantic layers at once:
--   CALL SEM_DEV.CONFIG.BUILD_ALL_SEMANTIC_LAYERS();
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
