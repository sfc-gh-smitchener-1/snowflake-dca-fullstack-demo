-- ============================================================================
-- SNOWFLAKE DATA CLOUD ARCHITECTURE DEMO - INITIAL SETUP
-- ============================================================================
-- 
-- This is the FIRST script to run. It creates ALL foundational objects:
--   1. Roles and role hierarchy (enterprise-grade)
--   2. Warehouses for different workloads
--   3. Databases and schemas (RAW, CURATED, SEMANTIC, GOVERNANCE)
--   4. Governance tags (compliance-aware)
--   5. Future grants for access control
--
-- OWNERSHIP: DATA_ADMIN owns all objects
-- RUN AS: ACCOUNTADMIN (only this script requires ACCOUNTADMIN)
--
-- Deployment Order (after this script):
--   2. 03_raw_layer.sql  - RAW tables with SCD Type 2
--   3. 04_load_data.sql  - Load synthetic data (or generate)
--   4. 05_curated_layer.sql - Dynamic Tables
--   5. 06_semantic_layer.sql - Semantic Views
--   6. 07_governance.sql - Masking and row access policies
--   7. 08_contracts.sql  - Data contracts
--   8. 09_streamlit.sql  - Streamlit deployment
--   9. 10_marketplace.sql - Data products
--
-- Compliance Frameworks Supported:
--   - GDPR (EU Data Protection)
--   - HIPAA (US Healthcare)
--   - FERPA (US Education)
--   - CCPA (California Privacy)
--   - SOC2 (Security Controls)
--   - PCI-DSS (Payment Card Industry)
--
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- PRE-FLIGHT CHECK
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;

SELECT 
    '=== SNOWFLAKE DCA FULL STACK DEMO ===' AS DEPLOYMENT_START,
    CURRENT_TIMESTAMP() AS TIMESTAMP,
    CURRENT_ACCOUNT() AS ACCOUNT,
    CURRENT_REGION() AS REGION,
    CURRENT_USER() AS DEPLOYING_USER;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 1: ROLE HIERARCHY
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Enterprise role hierarchy supporting:
--   - Separation of duties
--   - Least privilege access
--   - Compliance requirements
--   - AI/ML workload isolation
--
-- ─────────────────────────────────────────────────────────────────────────────
-- ROLE HIERARCHY DIAGRAM
-- ─────────────────────────────────────────────────────────────────────────────
-- 
--                            ACCOUNTADMIN
--                                  │
--                             SYSADMIN
--                                  │
--                             DATA_ADMIN ◄── Owns all demo objects
--                                  │
--          ┌───────────────────────┼───────────────────────┐
--          │                       │                       │
--     DATA_ENGINEER           DATA_STEWARD            PII_VIEWER
--          │                       │                       │
--          │          ┌────────────┼────────────┐          │
--          │          │            │            │          │
--          │      ANALYST      MANAGER      AUDITOR        │
--          │          │            │            │          │
--          │          └──────┬─────┴──────┬─────┘          │
--          │                 │            │                │
--          └─────────►   VIEWER     EXTERNAL_PARTNER  ◄────┘
--                            │
--                        AI_AGENT
--
-- ─────────────────────────────────────────────────────────────────────────────

-- =============================================================================
-- Administrative Roles
-- =============================================================================

CREATE ROLE IF NOT EXISTS DATA_ADMIN
    COMMENT = 'Full administrative access to all data layers and governance. Owns all demo objects.';

CREATE ROLE IF NOT EXISTS DATA_ENGINEER
    COMMENT = 'Manages data pipelines, RAW and CURATED layers. No PII access.';

CREATE ROLE IF NOT EXISTS DATA_STEWARD
    COMMENT = 'Manages governance tags, quality rules, and compliance. Monitors data quality.';

CREATE ROLE IF NOT EXISTS PII_VIEWER
    COMMENT = 'Privileged role for viewing unmasked PII. Requires special authorization and audit.';

-- =============================================================================
-- Business Roles
-- =============================================================================

CREATE ROLE IF NOT EXISTS ANALYST
    COMMENT = 'Business analyst with access to SEMANTIC layer. PII masked.';

CREATE ROLE IF NOT EXISTS MANAGER
    COMMENT = 'Manager with broader access than analyst. Partial PII for direct reports.';

CREATE ROLE IF NOT EXISTS AUDITOR
    COMMENT = 'Compliance auditor with read access to governance metadata and audit logs.';

CREATE ROLE IF NOT EXISTS VIEWER
    COMMENT = 'Read-only access to aggregated data. No individual records.';

-- =============================================================================
-- External/Partner Roles
-- =============================================================================

CREATE ROLE IF NOT EXISTS EXTERNAL_PARTNER
    COMMENT = 'External partner access via data sharing. Highly restricted.';

-- =============================================================================
-- AI/ML Roles
-- =============================================================================

CREATE ROLE IF NOT EXISTS AI_AGENT
    COMMENT = 'AI/ML workloads. Only pseudonymized and aggregated data. No direct PII.';

CREATE ROLE IF NOT EXISTS ML_ENGINEER
    COMMENT = 'Machine learning engineer. Access to training data (masked/pseudonymized).';

-- =============================================================================
-- Role Hierarchy Grants
-- =============================================================================

-- Top of hierarchy
GRANT ROLE DATA_ADMIN TO ROLE SYSADMIN;

-- Administrative roles under DATA_ADMIN
GRANT ROLE DATA_ENGINEER TO ROLE DATA_ADMIN;
GRANT ROLE DATA_STEWARD TO ROLE DATA_ADMIN;
GRANT ROLE PII_VIEWER TO ROLE DATA_ADMIN;

-- Business roles under DATA_STEWARD
GRANT ROLE ANALYST TO ROLE DATA_STEWARD;
GRANT ROLE MANAGER TO ROLE DATA_STEWARD;
GRANT ROLE AUDITOR TO ROLE DATA_STEWARD;

-- Viewer under multiple parents
GRANT ROLE VIEWER TO ROLE ANALYST;
GRANT ROLE VIEWER TO ROLE MANAGER;

-- AI/ML roles
GRANT ROLE AI_AGENT TO ROLE DATA_STEWARD;
GRANT ROLE ML_ENGINEER TO ROLE DATA_ENGINEER;

-- External partner (restricted)
GRANT ROLE EXTERNAL_PARTNER TO ROLE DATA_STEWARD;

-- =============================================================================
-- Demo Access: Grant all roles to DATA_ADMIN and ACCOUNTADMIN for role switching
-- =============================================================================

GRANT ROLE ANALYST TO ROLE DATA_ADMIN;
GRANT ROLE MANAGER TO ROLE DATA_ADMIN;
GRANT ROLE AUDITOR TO ROLE DATA_ADMIN;
GRANT ROLE VIEWER TO ROLE DATA_ADMIN;
GRANT ROLE EXTERNAL_PARTNER TO ROLE DATA_ADMIN;
GRANT ROLE AI_AGENT TO ROLE DATA_ADMIN;
GRANT ROLE ML_ENGINEER TO ROLE DATA_ADMIN;

-- Grant to ACCOUNTADMIN for demo purposes
GRANT ROLE DATA_ADMIN TO ROLE ACCOUNTADMIN;
GRANT ROLE DATA_ENGINEER TO ROLE ACCOUNTADMIN;
GRANT ROLE DATA_STEWARD TO ROLE ACCOUNTADMIN;
GRANT ROLE PII_VIEWER TO ROLE ACCOUNTADMIN;
GRANT ROLE ANALYST TO ROLE ACCOUNTADMIN;
GRANT ROLE MANAGER TO ROLE ACCOUNTADMIN;
GRANT ROLE AUDITOR TO ROLE ACCOUNTADMIN;
GRANT ROLE VIEWER TO ROLE ACCOUNTADMIN;
GRANT ROLE AI_AGENT TO ROLE ACCOUNTADMIN;

-- =============================================================================
-- Cortex Analyst Access
-- =============================================================================

-- Enable Cortex cross-region if needed
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';

-- Grant Cortex access to relevant roles
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE DATA_ADMIN;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE DATA_ENGINEER;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE DATA_STEWARD;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE ANALYST;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE MANAGER;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE AI_AGENT;

-- Grant creation privileges
GRANT CREATE DATABASE ON ACCOUNT TO ROLE DATA_ADMIN;
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE DATA_ADMIN;
GRANT CREATE SHARE ON ACCOUNT TO ROLE DATA_ADMIN;
GRANT CREATE DATA EXCHANGE LISTING ON ACCOUNT TO ROLE DATA_ADMIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 2: WAREHOUSES
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Separate warehouses for:
--   - INGEST_WH: Data loading (burstable)
--   - TRANSFORM_WH: Dynamic Tables and transformations
--   - ANALYTICS_WH: User queries and Cortex Analyst
--   - AI_WH: ML workloads (isolated)
--
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE DATA_ADMIN;

-- Ingestion warehouse (burstable for batch loads)
CREATE WAREHOUSE IF NOT EXISTS INGEST_WH
    WAREHOUSE_SIZE = 'SMALL'
    WAREHOUSE_TYPE = 'STANDARD'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 2
    SCALING_POLICY = 'ECONOMY'
    COMMENT = 'Warehouse for data ingestion workloads. Auto-scales for batch loads.';

-- Transformation warehouse (for Dynamic Tables)
CREATE WAREHOUSE IF NOT EXISTS TRANSFORM_WH
    WAREHOUSE_SIZE = 'SMALL'
    WAREHOUSE_TYPE = 'STANDARD'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    COMMENT = 'Warehouse for transformation and Dynamic Tables.';

-- Analytics warehouse (for queries and Cortex)
CREATE WAREHOUSE IF NOT EXISTS ANALYTICS_WH
    WAREHOUSE_SIZE = 'SMALL'
    WAREHOUSE_TYPE = 'STANDARD'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    COMMENT = 'Warehouse for analytics queries and Cortex Analyst.';

-- AI/ML warehouse (isolated for ML workloads)
CREATE WAREHOUSE IF NOT EXISTS AI_WH
    WAREHOUSE_SIZE = 'SMALL'
    WAREHOUSE_TYPE = 'STANDARD'
    AUTO_SUSPEND = 120
    AUTO_RESUME = TRUE
    COMMENT = 'Warehouse for AI/ML workloads. Isolated for resource management.';

-- =============================================================================
-- Warehouse Access Grants
-- =============================================================================

-- DATA_ENGINEER: Ingestion and transformation
GRANT USAGE ON WAREHOUSE INGEST_WH TO ROLE DATA_ENGINEER;
GRANT USAGE ON WAREHOUSE TRANSFORM_WH TO ROLE DATA_ENGINEER;
GRANT USAGE ON WAREHOUSE ANALYTICS_WH TO ROLE DATA_ENGINEER;

-- DATA_STEWARD: Analytics only
GRANT USAGE ON WAREHOUSE ANALYTICS_WH TO ROLE DATA_STEWARD;

-- PII_VIEWER: Analytics only
GRANT USAGE ON WAREHOUSE ANALYTICS_WH TO ROLE PII_VIEWER;

-- Business roles: Analytics
GRANT USAGE ON WAREHOUSE ANALYTICS_WH TO ROLE ANALYST;
GRANT USAGE ON WAREHOUSE ANALYTICS_WH TO ROLE MANAGER;
GRANT USAGE ON WAREHOUSE ANALYTICS_WH TO ROLE AUDITOR;
GRANT USAGE ON WAREHOUSE ANALYTICS_WH TO ROLE VIEWER;

-- AI roles: Dedicated AI warehouse
GRANT USAGE ON WAREHOUSE AI_WH TO ROLE AI_AGENT;
GRANT USAGE ON WAREHOUSE AI_WH TO ROLE ML_ENGINEER;
GRANT USAGE ON WAREHOUSE ANALYTICS_WH TO ROLE AI_AGENT;

-- External partner: Limited analytics
GRANT USAGE ON WAREHOUSE ANALYTICS_WH TO ROLE EXTERNAL_PARTNER;

USE WAREHOUSE TRANSFORM_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 3: DATABASES
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Database structure:
--   - GOVERNANCE: Tags, policies, observability
--   - RAW_DEV: Bronze layer (raw data with SCD2)
--   - CURATED_DEV: Silver layer (Dynamic Tables)
--   - SEM_DEV: Gold layer (Semantic Views)
--
-- ═══════════════════════════════════════════════════════════════════════════

-- Governance database (tags, policies, monitoring)
CREATE DATABASE IF NOT EXISTS GOVERNANCE
    COMMENT = 'Data governance: tags, policies, quality rules, and observability.';

-- RAW layer (Bronze)
CREATE DATABASE IF NOT EXISTS RAW_DEV
    COMMENT = 'Raw data layer - ingestion from source systems with SCD Type 2 history.';

-- CURATED layer (Silver)
CREATE DATABASE IF NOT EXISTS CURATED_DEV
    COMMENT = 'Curated layer - transformed data using Dynamic Tables.';

-- SEMANTIC layer (Gold)
CREATE DATABASE IF NOT EXISTS SEM_DEV
    COMMENT = 'Semantic layer - consumer-facing views with governance policies.';

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 4: SCHEMAS
-- ═══════════════════════════════════════════════════════════════════════════

-- =============================================================================
-- GOVERNANCE Schemas
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS GOVERNANCE.TAGS
    COMMENT = 'Governance tag definitions.';

CREATE SCHEMA IF NOT EXISTS GOVERNANCE.POLICIES
    COMMENT = 'Masking and row access policy definitions.';

CREATE SCHEMA IF NOT EXISTS GOVERNANCE.OBSERVABILITY
    COMMENT = 'Monitoring views and dashboards.';

CREATE SCHEMA IF NOT EXISTS GOVERNANCE.QUALITY
    COMMENT = 'Data quality rules and results.';

CREATE SCHEMA IF NOT EXISTS GOVERNANCE.LINEAGE
    COMMENT = 'Data lineage and dependency tracking.';

-- =============================================================================
-- RAW Layer Schemas (by source system)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS RAW_DEV.STAGING
    COMMENT = 'Staging area for data loading.';

CREATE SCHEMA IF NOT EXISTS RAW_DEV.CRM
    COMMENT = 'CRM/Salesforce source data.';

CREATE SCHEMA IF NOT EXISTS RAW_DEV.ERP
    COMMENT = 'ERP/SAP source data.';

CREATE SCHEMA IF NOT EXISTS RAW_DEV.HR
    COMMENT = 'HR/Workday source data.';

CREATE SCHEMA IF NOT EXISTS RAW_DEV.OPERATIONS
    COMMENT = 'Operations/ServiceNow source data.';

-- =============================================================================
-- CURATED Layer Schemas (dimensional model)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS CURATED_DEV.DIMENSIONS
    COMMENT = 'Curated dimension tables (DIM_*).';

CREATE SCHEMA IF NOT EXISTS CURATED_DEV.FACTS
    COMMENT = 'Curated fact tables (FACT_*).';

CREATE SCHEMA IF NOT EXISTS CURATED_DEV.AGGREGATES
    COMMENT = 'Pre-computed aggregates (AGG_*).';

CREATE SCHEMA IF NOT EXISTS CURATED_DEV.REFERENCE
    COMMENT = 'Reference and lookup tables.';

-- =============================================================================
-- SEMANTIC Layer Schemas (by business domain)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS SEM_DEV.SEM_SALES
    COMMENT = 'Sales and revenue analytics.';

CREATE SCHEMA IF NOT EXISTS SEM_DEV.SEM_CUSTOMER
    COMMENT = 'Customer analytics and 360 views.';

CREATE SCHEMA IF NOT EXISTS SEM_DEV.SEM_OPERATIONS
    COMMENT = 'Operations and fulfillment analytics.';

CREATE SCHEMA IF NOT EXISTS SEM_DEV.SEM_HR
    COMMENT = 'Workforce and HR analytics.';

CREATE SCHEMA IF NOT EXISTS SEM_DEV.SEM_GOVERNANCE
    COMMENT = 'Governance and compliance analytics.';

CREATE SCHEMA IF NOT EXISTS SEM_DEV.MARKETPLACE
    COMMENT = 'Data products for internal marketplace.';

CREATE SCHEMA IF NOT EXISTS SEM_DEV.STREAMLIT
    COMMENT = 'Streamlit application deployment.';

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 5: GOVERNANCE TAGS
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Comprehensive tag library supporting:
--   - Data classification (sensitivity)
--   - PII identification
--   - AI/ML eligibility
--   - Compliance frameworks (GDPR, HIPAA, FERPA, CCPA)
--   - Data residency/sovereignty
--   - Retention policies
--
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA GOVERNANCE.TAGS;

-- =============================================================================
-- Data Classification Tag
-- =============================================================================
CREATE TAG IF NOT EXISTS DATA_CLASSIFICATION
    ALLOWED_VALUES 'PUBLIC', 'INTERNAL', 'CONFIDENTIAL', 'RESTRICTED'
    COMMENT = 'Data classification level for sensitivity. PUBLIC=unrestricted, INTERNAL=employees, CONFIDENTIAL=need-to-know, RESTRICTED=highly protected.';

-- =============================================================================
-- PII Type Tag
-- =============================================================================
CREATE TAG IF NOT EXISTS PII_TYPE
    ALLOWED_VALUES 'NONE', 'INDIRECT', 'DIRECT', 'SENSITIVE'
    COMMENT = 'Personal information level. NONE=no PII, INDIRECT=quasi-identifiers, DIRECT=name/email/phone, SENSITIVE=SSN/health/financial.';

-- =============================================================================
-- AI Eligibility Tag
-- =============================================================================
CREATE TAG IF NOT EXISTS AI_ALLOWED
    ALLOWED_VALUES 'TRUE', 'FALSE', 'PSEUDONYMIZED', 'AGGREGATED'
    COMMENT = 'AI/ML workload eligibility. TRUE=safe for AI, FALSE=never expose, PSEUDONYMIZED=hash first, AGGREGATED=only in aggregate.';

-- =============================================================================
-- Compliance Framework Tags
-- =============================================================================
CREATE TAG IF NOT EXISTS COMPLIANCE_FRAMEWORK
    ALLOWED_VALUES 'NONE', 'GDPR', 'HIPAA', 'FERPA', 'CCPA', 'PCI', 'SOC2'
    COMMENT = 'Applicable compliance framework for this data.';

CREATE TAG IF NOT EXISTS GDPR_CATEGORY
    ALLOWED_VALUES 'NOT_APPLICABLE', 'PERSONAL_DATA', 'SPECIAL_CATEGORY', 'CRIMINAL_DATA'
    COMMENT = 'GDPR data category. PERSONAL_DATA=Art.4, SPECIAL_CATEGORY=Art.9, CRIMINAL_DATA=Art.10.';

CREATE TAG IF NOT EXISTS HIPAA_CATEGORY
    ALLOWED_VALUES 'NOT_APPLICABLE', 'PHI', 'DE_IDENTIFIED', 'LIMITED_DATA_SET'
    COMMENT = 'HIPAA data category. PHI=Protected Health Information, DE_IDENTIFIED=Safe Harbor method applied.';

CREATE TAG IF NOT EXISTS FERPA_CATEGORY
    ALLOWED_VALUES 'NOT_APPLICABLE', 'DIRECTORY', 'EDUCATIONAL_RECORD', 'SENSITIVE'
    COMMENT = 'FERPA category. DIRECTORY=opt-out public info, EDUCATIONAL_RECORD=protected, SENSITIVE=highly protected.';

-- =============================================================================
-- Data Residency/Sovereignty Tag
-- =============================================================================
CREATE TAG IF NOT EXISTS RESIDENCY_REGION
    ALLOWED_VALUES 'GLOBAL', 'US_ONLY', 'EU_ONLY', 'UK_ONLY', 'APAC_ONLY', 'ORIGIN'
    COMMENT = 'Data residency requirement. ORIGIN=must stay in originating region.';

-- =============================================================================
-- Retention Policy Tag
-- =============================================================================
CREATE TAG IF NOT EXISTS RETENTION_DAYS
    ALLOWED_VALUES '30', '90', '365', '730', '2555', 'INDEFINITE'
    COMMENT = 'Data retention period in days. 2555=7 years (regulatory common). INDEFINITE=no deletion.';

-- =============================================================================
-- Data Domain Tag
-- =============================================================================
CREATE TAG IF NOT EXISTS DATA_DOMAIN
    ALLOWED_VALUES 'CUSTOMER', 'EMPLOYEE', 'PRODUCT', 'ORDER', 'FINANCE', 'OPERATIONS', 'MARKETING', 'HR'
    COMMENT = 'Business domain for data stewardship and ownership.';

-- =============================================================================
-- Data Quality Tag
-- =============================================================================
CREATE TAG IF NOT EXISTS DATA_QUALITY_TIER
    ALLOWED_VALUES 'BRONZE', 'SILVER', 'GOLD', 'PLATINUM'
    COMMENT = 'Data quality tier. BRONZE=raw, SILVER=cleaned, GOLD=validated, PLATINUM=certified.';

-- =============================================================================
-- Source System Tag
-- =============================================================================
CREATE TAG IF NOT EXISTS SOURCE_SYSTEM
    COMMENT = 'Originating source system (e.g., SALESFORCE, SAP, WORKDAY).';

-- =============================================================================
-- Contract/Owner Tag
-- =============================================================================
CREATE TAG IF NOT EXISTS DATA_OWNER
    COMMENT = 'Team or individual responsible for data stewardship.';

CREATE TAG IF NOT EXISTS DATA_CONTRACT_ID
    COMMENT = 'Associated data contract identifier.';

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 6: DATABASE-LEVEL GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

-- DATA_ENGINEER: Full access to RAW and CURATED
GRANT USAGE ON DATABASE GOVERNANCE TO ROLE DATA_ENGINEER;
GRANT USAGE ON DATABASE RAW_DEV TO ROLE DATA_ENGINEER;
GRANT USAGE ON DATABASE CURATED_DEV TO ROLE DATA_ENGINEER;
GRANT USAGE ON DATABASE SEM_DEV TO ROLE DATA_ENGINEER;

-- DATA_STEWARD: Governance and read access to all layers
GRANT USAGE ON DATABASE GOVERNANCE TO ROLE DATA_STEWARD;
GRANT USAGE ON DATABASE RAW_DEV TO ROLE DATA_STEWARD;
GRANT USAGE ON DATABASE CURATED_DEV TO ROLE DATA_STEWARD;
GRANT USAGE ON DATABASE SEM_DEV TO ROLE DATA_STEWARD;

-- PII_VIEWER: Semantic layer only
GRANT USAGE ON DATABASE SEM_DEV TO ROLE PII_VIEWER;

-- Business roles: Semantic layer only
GRANT USAGE ON DATABASE SEM_DEV TO ROLE ANALYST;
GRANT USAGE ON DATABASE SEM_DEV TO ROLE MANAGER;
GRANT USAGE ON DATABASE SEM_DEV TO ROLE VIEWER;

-- Auditor: Governance and Semantic
GRANT USAGE ON DATABASE GOVERNANCE TO ROLE AUDITOR;
GRANT USAGE ON DATABASE SEM_DEV TO ROLE AUDITOR;

-- AI roles: Semantic layer only
GRANT USAGE ON DATABASE SEM_DEV TO ROLE AI_AGENT;
GRANT USAGE ON DATABASE CURATED_DEV TO ROLE ML_ENGINEER;
GRANT USAGE ON DATABASE SEM_DEV TO ROLE ML_ENGINEER;

-- External partner: Semantic marketplace only
GRANT USAGE ON DATABASE SEM_DEV TO ROLE EXTERNAL_PARTNER;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 7: SCHEMA-LEVEL GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

-- DATA_ENGINEER: All schemas in RAW and CURATED
GRANT USAGE ON ALL SCHEMAS IN DATABASE RAW_DEV TO ROLE DATA_ENGINEER;
GRANT USAGE ON ALL SCHEMAS IN DATABASE CURATED_DEV TO ROLE DATA_ENGINEER;
GRANT USAGE ON ALL SCHEMAS IN DATABASE SEM_DEV TO ROLE DATA_ENGINEER;
GRANT CREATE TABLE ON ALL SCHEMAS IN DATABASE RAW_DEV TO ROLE DATA_ENGINEER;
GRANT CREATE DYNAMIC TABLE ON ALL SCHEMAS IN DATABASE CURATED_DEV TO ROLE DATA_ENGINEER;
GRANT CREATE VIEW ON ALL SCHEMAS IN DATABASE SEM_DEV TO ROLE DATA_ENGINEER;

-- DATA_STEWARD: All schemas (read)
GRANT USAGE ON ALL SCHEMAS IN DATABASE GOVERNANCE TO ROLE DATA_STEWARD;
GRANT USAGE ON ALL SCHEMAS IN DATABASE RAW_DEV TO ROLE DATA_STEWARD;
GRANT USAGE ON ALL SCHEMAS IN DATABASE CURATED_DEV TO ROLE DATA_STEWARD;
GRANT USAGE ON ALL SCHEMAS IN DATABASE SEM_DEV TO ROLE DATA_STEWARD;

-- Business roles: Semantic schemas
GRANT USAGE ON SCHEMA SEM_DEV.SEM_SALES TO ROLE ANALYST;
GRANT USAGE ON SCHEMA SEM_DEV.SEM_CUSTOMER TO ROLE ANALYST;
GRANT USAGE ON SCHEMA SEM_DEV.SEM_OPERATIONS TO ROLE ANALYST;
GRANT USAGE ON SCHEMA SEM_DEV.SEM_SALES TO ROLE MANAGER;
GRANT USAGE ON SCHEMA SEM_DEV.SEM_CUSTOMER TO ROLE MANAGER;
GRANT USAGE ON SCHEMA SEM_DEV.SEM_HR TO ROLE MANAGER;

-- AI roles: Semantic layer
GRANT USAGE ON SCHEMA SEM_DEV.SEM_SALES TO ROLE AI_AGENT;
GRANT USAGE ON SCHEMA SEM_DEV.SEM_CUSTOMER TO ROLE AI_AGENT;
GRANT USAGE ON SCHEMA SEM_DEV.SEM_OPERATIONS TO ROLE AI_AGENT;

-- External: Marketplace only
GRANT USAGE ON SCHEMA SEM_DEV.MARKETPLACE TO ROLE EXTERNAL_PARTNER;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 8: FUTURE GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

-- DATA_ENGINEER: Future tables in RAW
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES IN DATABASE RAW_DEV TO ROLE DATA_ENGINEER;
GRANT SELECT ON FUTURE TABLES IN DATABASE CURATED_DEV TO ROLE DATA_ENGINEER;
GRANT SELECT ON FUTURE DYNAMIC TABLES IN DATABASE CURATED_DEV TO ROLE DATA_ENGINEER;
GRANT SELECT ON FUTURE VIEWS IN DATABASE SEM_DEV TO ROLE DATA_ENGINEER;

-- DATA_STEWARD: Future governance objects
GRANT SELECT ON FUTURE TABLES IN DATABASE GOVERNANCE TO ROLE DATA_STEWARD;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES IN SCHEMA GOVERNANCE.QUALITY TO ROLE DATA_STEWARD;
GRANT SELECT ON FUTURE VIEWS IN DATABASE GOVERNANCE TO ROLE DATA_STEWARD;

-- Business roles: Future semantic views
GRANT SELECT ON FUTURE VIEWS IN SCHEMA SEM_DEV.SEM_SALES TO ROLE ANALYST;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA SEM_DEV.SEM_CUSTOMER TO ROLE ANALYST;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA SEM_DEV.SEM_SALES TO ROLE MANAGER;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA SEM_DEV.SEM_CUSTOMER TO ROLE MANAGER;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA SEM_DEV.SEM_HR TO ROLE MANAGER;

-- AI roles: Future views
GRANT SELECT ON FUTURE VIEWS IN SCHEMA SEM_DEV.SEM_SALES TO ROLE AI_AGENT;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA SEM_DEV.SEM_CUSTOMER TO ROLE AI_AGENT;

-- External: Future marketplace objects
GRANT SELECT ON FUTURE VIEWS IN SCHEMA SEM_DEV.MARKETPLACE TO ROLE EXTERNAL_PARTNER;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 9: STAGING AREA
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA RAW_DEV.STAGING;

-- Create internal stage for data loading
CREATE STAGE IF NOT EXISTS DATA_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Internal stage for loading synthetic or source data.';

-- Create file format for CSV
CREATE FILE FORMAT IF NOT EXISTS CSV_FORMAT
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('', 'NULL', 'null')
    TRIM_SPACE = TRUE
    ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
    COMMENT = 'Standard CSV format for data loading.';

-- Create file format for JSON
CREATE FILE FORMAT IF NOT EXISTS JSON_FORMAT
    TYPE = 'JSON'
    STRIP_OUTER_ARRAY = TRUE
    COMMENT = 'Standard JSON format for data loading.';

-- Create file format for Parquet
CREATE FILE FORMAT IF NOT EXISTS PARQUET_FORMAT
    TYPE = 'PARQUET'
    COMMENT = 'Standard Parquet format for data loading.';

-- Grant stage access
GRANT READ, WRITE ON STAGE DATA_STAGE TO ROLE DATA_ENGINEER;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE DATA_ADMIN;

SELECT '✓ Snowflake Data Cloud Architecture Setup Complete' AS STATUS;
SELECT '  All objects owned by DATA_ADMIN' AS NOTE_1;
SELECT '  Enterprise role hierarchy configured' AS NOTE_2;
SELECT '  Compliance-aware tags created' AS NOTE_3;
SELECT '  Ready for data loading and transformation' AS NOTE_4;

-- Show what was created
SHOW ROLES LIKE 'DATA_%';
SHOW ROLES LIKE 'ANALYST';
SHOW ROLES LIKE 'MANAGER';
SHOW ROLES LIKE 'AI_%';
SHOW WAREHOUSES;
SHOW DATABASES LIKE '%DEV';
SHOW DATABASES LIKE 'GOVERNANCE';
SHOW TAGS IN SCHEMA GOVERNANCE.TAGS;

-- ═══════════════════════════════════════════════════════════════════════════
-- NEXT STEPS
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 
    'Next Steps:' AS INFO,
    '1. Run 03_raw_layer.sql to create raw tables' AS STEP_1,
    '2. Generate data: python tools/data_generator.py --system all --domain all --output data' AS STEP_2,
    '3. Upload data: PUT file://data/*.csv @RAW_DEV.STAGING.DATA_STAGE AUTO_COMPRESS=FALSE' AS STEP_3,
    '4. Run 04_load_data.sql to load data' AS STEP_4,
    '5. Run remaining scripts in order (05-10)' AS STEP_5;
