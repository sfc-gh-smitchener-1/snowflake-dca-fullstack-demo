-- ============================================================================
-- UNITED RENTALS DEMO - Governance: Masking, Row Access, Tags
-- ============================================================================
--
-- Demonstrates Snowflake Horizon governance capabilities:
--   1. MASKING POLICIES: Customer PII + rental pricing graduated by role
--   2. ROW ACCESS POLICIES: Region/branch-scoped data per role
--   3. TAG APPLICATION: Data classification on sensitive columns
--
-- Role-based access matrix:
--   ┌─────────────────────────┬──────────┬─────────┬────────┬──────┬────────┐
--   │ Data Element            │ Fleet Mgr│ Reg Dir │ Br Mgr │ Corp │ Extern │
--   ├─────────────────────────┼──────────┼─────────┼────────┼──────┼────────┤
--   │ Customer Name           │ Full     │ Full    │ Full   │ Mask │ Mask   │
--   │ Customer Email          │ Full     │ Full    │ Full   │ Mask │ Mask   │
--   │ Customer Phone          │ Full     │ Full    │ Full   │ Mask │ Mask   │
--   │ Rental Rates            │ Full     │ Full    │ Full   │ Full │ Hidden │
--   │ Regions Visible         │ All      │ Assign  │ Assign │ All  │ Assign │
--   │ Branches Visible        │ All      │ Region  │ 1 Only │ All  │ Region │
--   └─────────────────────────┴──────────┴─────────┴────────┴──────┴────────┘
--
-- Prerequisites: 01_ur_setup.sql, 03_ur_curated_layer.sql
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE CURATED_DEV;
USE SCHEMA CURATED_DEV.UNITED_RENTALS;
USE WAREHOUSE ANALYTICS_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- MASKING POLICIES
-- ═══════════════════════════════════════════════════════════════════════════

-- Customer Name: Masked for Corporate Analyst and External Partner
CREATE OR REPLACE MASKING POLICY CURATED_DEV.UNITED_RENTALS.MASK_UR_CUSTOMER_NAME
    AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('DATA_ADMIN', 'UR_FLEET_MANAGER', 'UR_REGIONAL_DIRECTOR', 'UR_BRANCH_MANAGER')
            THEN val
        WHEN CURRENT_ROLE() = 'UR_CORPORATE_ANALYST'
            THEN CONCAT(LEFT(val, 3), '***')
        ELSE '*** RESTRICTED ***'
    END
    COMMENT = 'Masks customer company name based on UR role hierarchy';

-- Customer Email: Masked for analysts, hidden for external
CREATE OR REPLACE MASKING POLICY CURATED_DEV.UNITED_RENTALS.MASK_UR_EMAIL
    AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('DATA_ADMIN', 'UR_FLEET_MANAGER', 'UR_REGIONAL_DIRECTOR', 'UR_BRANCH_MANAGER')
            THEN val
        WHEN CURRENT_ROLE() = 'UR_CORPORATE_ANALYST'
            THEN CONCAT('***@', SPLIT_PART(val, '@', 2))
        ELSE '***@***.***'
    END
    COMMENT = 'Masks customer email - partial for analysts, full for external';

-- Customer Phone: Masked for analysts, hidden for external
CREATE OR REPLACE MASKING POLICY CURATED_DEV.UNITED_RENTALS.MASK_UR_PHONE
    AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('DATA_ADMIN', 'UR_FLEET_MANAGER', 'UR_REGIONAL_DIRECTOR', 'UR_BRANCH_MANAGER')
            THEN val
        WHEN CURRENT_ROLE() = 'UR_CORPORATE_ANALYST'
            THEN CONCAT('***-***-', RIGHT(val, 4))
        ELSE '***-***-****'
    END
    COMMENT = 'Masks customer phone - last 4 digits for analysts, full mask for external';

-- Rental Rate: Hidden for external partners
CREATE OR REPLACE MASKING POLICY CURATED_DEV.UNITED_RENTALS.MASK_UR_RATE
    AS (val FLOAT) RETURNS FLOAT ->
    CASE
        WHEN CURRENT_ROLE() IN ('DATA_ADMIN', 'UR_FLEET_MANAGER', 'UR_REGIONAL_DIRECTOR',
                                 'UR_BRANCH_MANAGER', 'UR_CORPORATE_ANALYST')
            THEN val
        ELSE NULL
    END
    COMMENT = 'Hides rental pricing from external partners';

-- Credit Limit: Only visible to fleet manager and admin
CREATE OR REPLACE MASKING POLICY CURATED_DEV.UNITED_RENTALS.MASK_UR_CREDIT
    AS (val FLOAT) RETURNS FLOAT ->
    CASE
        WHEN CURRENT_ROLE() IN ('DATA_ADMIN', 'UR_FLEET_MANAGER')
            THEN val
        ELSE NULL
    END
    COMMENT = 'Credit limit visible only to fleet manager and admin';

-- ═══════════════════════════════════════════════════════════════════════════
-- ROW ACCESS POLICY (region/branch scoping)
-- ═══════════════════════════════════════════════════════════════════════════

-- Row access based on region mapping table
CREATE OR REPLACE ROW ACCESS POLICY CURATED_DEV.UNITED_RENTALS.RAP_UR_REGION
    AS (region_val VARCHAR) RETURNS BOOLEAN ->
    CASE
        -- Admin always sees everything
        WHEN CURRENT_ROLE() = 'DATA_ADMIN' THEN TRUE
        -- Check role-region mapping
        WHEN EXISTS (
            SELECT 1 FROM CURATED_DEV.UNITED_RENTALS.ROLE_REGION_MAPPING
            WHERE ROLE_NAME = CURRENT_ROLE()
              AND REGION = region_val
        ) THEN TRUE
        ELSE FALSE
    END
    COMMENT = 'Restricts row visibility by region based on role-region mapping table';

-- ═══════════════════════════════════════════════════════════════════════════
-- APPLY MASKING POLICIES TO CURATED TABLES
-- ═══════════════════════════════════════════════════════════════════════════

-- DIM_CUSTOMER masking
ALTER TABLE CURATED_DEV.UNITED_RENTALS.DIM_CUSTOMER MODIFY COLUMN
    COMPANY_NAME SET MASKING POLICY CURATED_DEV.UNITED_RENTALS.MASK_UR_CUSTOMER_NAME;

ALTER TABLE CURATED_DEV.UNITED_RENTALS.DIM_CUSTOMER MODIFY COLUMN
    EMAIL SET MASKING POLICY CURATED_DEV.UNITED_RENTALS.MASK_UR_EMAIL;

ALTER TABLE CURATED_DEV.UNITED_RENTALS.DIM_CUSTOMER MODIFY COLUMN
    PHONE SET MASKING POLICY CURATED_DEV.UNITED_RENTALS.MASK_UR_PHONE;

ALTER TABLE CURATED_DEV.UNITED_RENTALS.DIM_CUSTOMER MODIFY COLUMN
    CREDIT_LIMIT SET MASKING POLICY CURATED_DEV.UNITED_RENTALS.MASK_UR_CREDIT;

-- DIM_EQUIPMENT rate masking
ALTER TABLE CURATED_DEV.UNITED_RENTALS.DIM_EQUIPMENT MODIFY COLUMN
    DAILY_RATE SET MASKING POLICY CURATED_DEV.UNITED_RENTALS.MASK_UR_RATE;

ALTER TABLE CURATED_DEV.UNITED_RENTALS.DIM_EQUIPMENT MODIFY COLUMN
    WEEKLY_RATE SET MASKING POLICY CURATED_DEV.UNITED_RENTALS.MASK_UR_RATE;

ALTER TABLE CURATED_DEV.UNITED_RENTALS.DIM_EQUIPMENT MODIFY COLUMN
    MONTHLY_RATE SET MASKING POLICY CURATED_DEV.UNITED_RENTALS.MASK_UR_RATE;

-- FACT_RENTALS rate and customer masking
ALTER TABLE CURATED_DEV.UNITED_RENTALS.FACT_RENTALS MODIFY COLUMN
    DAILY_RATE SET MASKING POLICY CURATED_DEV.UNITED_RENTALS.MASK_UR_RATE;

ALTER TABLE CURATED_DEV.UNITED_RENTALS.FACT_RENTALS MODIFY COLUMN
    TOTAL_AMOUNT SET MASKING POLICY CURATED_DEV.UNITED_RENTALS.MASK_UR_RATE;

ALTER TABLE CURATED_DEV.UNITED_RENTALS.FACT_RENTALS MODIFY COLUMN
    CUSTOMER_NAME SET MASKING POLICY CURATED_DEV.UNITED_RENTALS.MASK_UR_CUSTOMER_NAME;

-- ═══════════════════════════════════════════════════════════════════════════
-- APPLY ROW ACCESS POLICIES
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE CURATED_DEV.UNITED_RENTALS.DIM_BRANCH
    ADD ROW ACCESS POLICY CURATED_DEV.UNITED_RENTALS.RAP_UR_REGION ON (REGION);

ALTER TABLE CURATED_DEV.UNITED_RENTALS.DIM_EQUIPMENT
    ADD ROW ACCESS POLICY CURATED_DEV.UNITED_RENTALS.RAP_UR_REGION ON (
        (SELECT b.REGION FROM CURATED_DEV.UNITED_RENTALS.DIM_BRANCH b WHERE b.BRANCH_ID = BRANCH_ID)
    );

-- Note: Row access on equipment is handled via the FLEET_AVAILABILITY view
-- which joins to DIM_BRANCH (where the RAP is applied). The join naturally
-- filters equipment to only visible branches.

-- ═══════════════════════════════════════════════════════════════════════════
-- TAG APPLICATION (Snowflake Horizon data classification)
-- ═══════════════════════════════════════════════════════════════════════════

-- Tag the customer table with domain and sensitivity
ALTER TABLE CURATED_DEV.UNITED_RENTALS.DIM_CUSTOMER
    SET TAG GOVERNANCE.TAGS.UR_DATA_DOMAIN = 'CUSTOMER';

ALTER TABLE CURATED_DEV.UNITED_RENTALS.DIM_CUSTOMER MODIFY COLUMN
    COMPANY_NAME SET TAG GOVERNANCE.TAGS.UR_SENSITIVITY = 'INTERNAL';

ALTER TABLE CURATED_DEV.UNITED_RENTALS.DIM_CUSTOMER MODIFY COLUMN
    EMAIL SET TAG GOVERNANCE.TAGS.UR_SENSITIVITY = 'CONFIDENTIAL';

ALTER TABLE CURATED_DEV.UNITED_RENTALS.DIM_CUSTOMER MODIFY COLUMN
    PHONE SET TAG GOVERNANCE.TAGS.UR_SENSITIVITY = 'CONFIDENTIAL';

ALTER TABLE CURATED_DEV.UNITED_RENTALS.DIM_CUSTOMER MODIFY COLUMN
    CREDIT_LIMIT SET TAG GOVERNANCE.TAGS.UR_SENSITIVITY = 'RESTRICTED';

-- Tag equipment and rentals
ALTER TABLE CURATED_DEV.UNITED_RENTALS.DIM_EQUIPMENT
    SET TAG GOVERNANCE.TAGS.UR_DATA_DOMAIN = 'FLEET';

ALTER TABLE CURATED_DEV.UNITED_RENTALS.DIM_EQUIPMENT MODIFY COLUMN
    DAILY_RATE SET TAG GOVERNANCE.TAGS.UR_SENSITIVITY = 'INTERNAL';

ALTER TABLE CURATED_DEV.UNITED_RENTALS.FACT_RENTALS
    SET TAG GOVERNANCE.TAGS.UR_DATA_DOMAIN = 'RENTAL';

ALTER TABLE CURATED_DEV.UNITED_RENTALS.FACT_RENTALS MODIFY COLUMN
    TOTAL_AMOUNT SET TAG GOVERNANCE.TAGS.UR_SENSITIVITY = 'CONFIDENTIAL';

ALTER TABLE CURATED_DEV.UNITED_RENTALS.FACT_TELEMATICS_LATEST
    SET TAG GOVERNANCE.TAGS.UR_DATA_DOMAIN = 'TELEMATICS';

SELECT 'Governance complete: 5 masking policies, 1 row access policy, tags applied.' AS STATUS;
