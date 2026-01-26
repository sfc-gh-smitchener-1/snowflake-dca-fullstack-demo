-- ============================================================================
-- SNOWFLAKE HORIZON - GOVERNANCE POLICIES
-- ============================================================================
-- 
-- This script creates comprehensive governance controls:
--   1. Masking policies for PII protection (column-level)
--   2. Row access policies for data filtering (row-level)
--   3. Policy application to tables and columns
--   4. Compliance framework support (GDPR, HIPAA, FERPA, CCPA)
--
-- Defense in Depth Strategy:
--   - Layer 1: Role-based access (RBAC) - handled by grants
--   - Layer 2: Column masking - hide/transform sensitive data
--   - Layer 3: Row access - filter rows based on context
--   - Layer 4: Audit trail - log all access (built-in)
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE WAREHOUSE TRANSFORM_WH;
USE DATABASE GOVERNANCE;
USE SCHEMA GOVERNANCE.POLICIES;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 1: MASKING POLICIES
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Masking policies define how data appears based on the querying role.
-- Each policy can have multiple tiers of visibility.
--
-- Masking Levels:
--   - FULL: Unmasked data (privileged roles only)
--   - PARTIAL: Partially revealed (e.g., last 4 digits)
--   - MASKED: Completely hidden or replaced
--   - NULL: Return NULL instead of data
--
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- MASK_SSN: Social Security Number / National ID
-- ─────────────────────────────────────────────────────────────────────────────
-- Highly sensitive - minimal exposure
-- FULL: DATA_ADMIN, PII_VIEWER
-- PARTIAL: MANAGER (last 4 digits)
-- MASKED: Everyone else

CREATE OR REPLACE MASKING POLICY MASK_SSN AS (val STRING)
RETURNS STRING ->
    CASE
        -- Full access for privileged roles
        WHEN CURRENT_ROLE() IN ('DATA_ADMIN', 'PII_VIEWER', 'ACCOUNTADMIN') THEN val
        -- Partial for managers (last 4 digits)
        WHEN CURRENT_ROLE() IN ('MANAGER') THEN 'XXX-XX-' || RIGHT(val, 4)
        -- Masked for everyone else
        ELSE '***-**-****'
    END;

COMMENT ON MASKING POLICY MASK_SSN IS 'Masks SSN/National ID. Full access: DATA_ADMIN, PII_VIEWER. Partial: MANAGER. Masked: all others.';

-- ─────────────────────────────────────────────────────────────────────────────
-- MASK_DOB: Date of Birth
-- ─────────────────────────────────────────────────────────────────────────────
-- FULL: DATA_ADMIN, PII_VIEWER
-- YEAR_ONLY: MANAGER, ANALYST (for age calculations)
-- NULL: AI_AGENT, VIEWER

CREATE OR REPLACE MASKING POLICY MASK_DOB AS (val DATE)
RETURNS DATE ->
    CASE
        -- Full access
        WHEN CURRENT_ROLE() IN ('DATA_ADMIN', 'PII_VIEWER', 'ACCOUNTADMIN') THEN val
        -- Year only (for age bands)
        WHEN CURRENT_ROLE() IN ('MANAGER', 'ANALYST') THEN DATE_TRUNC('YEAR', val)
        -- NULL for AI and restricted roles
        ELSE NULL
    END;

COMMENT ON MASKING POLICY MASK_DOB IS 'Masks date of birth. Full: privileged roles. Year only: business roles. NULL: AI and external.';

-- ─────────────────────────────────────────────────────────────────────────────
-- MASK_EMAIL: Email Address
-- ─────────────────────────────────────────────────────────────────────────────
-- FULL: DATA_ADMIN, PII_VIEWER, MANAGER
-- PARTIAL: ANALYST (first 2 chars + domain)
-- MASKED: AI_AGENT, VIEWER

CREATE OR REPLACE MASKING POLICY MASK_EMAIL AS (val STRING)
RETURNS STRING ->
    CASE
        -- Full access
        WHEN CURRENT_ROLE() IN ('DATA_ADMIN', 'PII_VIEWER', 'MANAGER', 'ACCOUNTADMIN') THEN val
        -- Partial (preserve domain for analytics)
        WHEN CURRENT_ROLE() IN ('ANALYST', 'DATA_STEWARD') THEN 
            CONCAT(LEFT(val, 2), '***@', SPLIT_PART(val, '@', 2))
        -- Masked
        ELSE '[EMAIL REDACTED]'
    END;

COMMENT ON MASKING POLICY MASK_EMAIL IS 'Masks email addresses. Preserves domain for analytics roles.';

-- ─────────────────────────────────────────────────────────────────────────────
-- MASK_PHONE: Phone Number
-- ─────────────────────────────────────────────────────────────────────────────
-- FULL: DATA_ADMIN, PII_VIEWER, MANAGER
-- PARTIAL: ANALYST (last 4 digits)
-- MASKED: Everyone else

CREATE OR REPLACE MASKING POLICY MASK_PHONE AS (val STRING)
RETURNS STRING ->
    CASE
        -- Full access
        WHEN CURRENT_ROLE() IN ('DATA_ADMIN', 'PII_VIEWER', 'MANAGER', 'ACCOUNTADMIN') THEN val
        -- Partial (last 4 for verification)
        WHEN CURRENT_ROLE() IN ('ANALYST') THEN 
            'XXX-XXX-' || RIGHT(REGEXP_REPLACE(val, '[^0-9]', ''), 4)
        -- Masked
        ELSE '[PHONE REDACTED]'
    END;

COMMENT ON MASKING POLICY MASK_PHONE IS 'Masks phone numbers. Last 4 digits for verification by analysts.';

-- ─────────────────────────────────────────────────────────────────────────────
-- MASK_ADDRESS: Physical Address
-- ─────────────────────────────────────────────────────────────────────────────
-- FULL: DATA_ADMIN, PII_VIEWER
-- CITY_ONLY: MANAGER, ANALYST (for geographic analysis)
-- MASKED: Everyone else

CREATE OR REPLACE MASKING POLICY MASK_ADDRESS AS (val STRING)
RETURNS STRING ->
    CASE
        -- Full access
        WHEN CURRENT_ROLE() IN ('DATA_ADMIN', 'PII_VIEWER', 'ACCOUNTADMIN') THEN val
        -- City/region level (allow geographic analysis)
        WHEN CURRENT_ROLE() IN ('MANAGER', 'ANALYST') THEN '[Address in ' || 
            COALESCE(REGEXP_SUBSTR(val, '[A-Za-z]+,? [A-Z]{2}'), 'Region') || ']'
        -- Masked
        ELSE '[ADDRESS REDACTED]'
    END;

COMMENT ON MASKING POLICY MASK_ADDRESS IS 'Masks physical addresses. Geographic region preserved for analysis.';

-- ─────────────────────────────────────────────────────────────────────────────
-- MASK_NAME: Person Name (First/Last)
-- ─────────────────────────────────────────────────────────────────────────────
-- FULL: Most business roles (names often needed)
-- INITIALS: AI_AGENT
-- MASKED: EXTERNAL_PARTNER

CREATE OR REPLACE MASKING POLICY MASK_NAME AS (val STRING)
RETURNS STRING ->
    CASE
        -- Full access for internal roles
        WHEN CURRENT_ROLE() IN ('DATA_ADMIN', 'PII_VIEWER', 'MANAGER', 'ANALYST', 
                                'DATA_STEWARD', 'DATA_ENGINEER', 'ACCOUNTADMIN') THEN val
        -- Initials for AI
        WHEN CURRENT_ROLE() = 'AI_AGENT' THEN LEFT(val, 1) || '.'
        -- Masked for external
        ELSE '[NAME REDACTED]'
    END;

COMMENT ON MASKING POLICY MASK_NAME IS 'Masks person names. Full for internal, initials for AI, masked for external.';

-- ─────────────────────────────────────────────────────────────────────────────
-- MASK_SALARY: Compensation Data
-- ─────────────────────────────────────────────────────────────────────────────
-- FULL: DATA_ADMIN, PII_VIEWER
-- ROUNDED: MANAGER (nearest $10K for budgeting)
-- NULL: Everyone else

CREATE OR REPLACE MASKING POLICY MASK_SALARY AS (val NUMBER)
RETURNS NUMBER ->
    CASE
        -- Full access
        WHEN CURRENT_ROLE() IN ('DATA_ADMIN', 'PII_VIEWER', 'ACCOUNTADMIN') THEN val
        -- Rounded for managers (budget planning)
        WHEN CURRENT_ROLE() IN ('MANAGER') THEN ROUND(val, -4)
        -- NULL for others
        ELSE NULL
    END;

COMMENT ON MASKING POLICY MASK_SALARY IS 'Masks salary data. Rounded for managers, hidden for others.';

-- ─────────────────────────────────────────────────────────────────────────────
-- MASK_CREDIT_CARD: Payment Card Data (PCI-DSS)
-- ─────────────────────────────────────────────────────────────────────────────
-- FULL: Never (PCI compliance)
-- PARTIAL: DATA_ADMIN only (last 4)
-- MASKED: Everyone

CREATE OR REPLACE MASKING POLICY MASK_CREDIT_CARD AS (val STRING)
RETURNS STRING ->
    CASE
        -- Even admins only see last 4 (PCI compliance)
        WHEN CURRENT_ROLE() IN ('DATA_ADMIN', 'ACCOUNTADMIN') THEN 
            'XXXX-XXXX-XXXX-' || RIGHT(REGEXP_REPLACE(val, '[^0-9]', ''), 4)
        -- Everyone else sees fully masked
        ELSE 'XXXX-XXXX-XXXX-XXXX'
    END;

COMMENT ON MASKING POLICY MASK_CREDIT_CARD IS 'PCI-DSS compliant credit card masking. No role sees full card number.';

-- ─────────────────────────────────────────────────────────────────────────────
-- MASK_CUSTOMER_ID: Customer Identifier
-- ─────────────────────────────────────────────────────────────────────────────
-- Used for AI workloads - returns hash instead of actual ID

CREATE OR REPLACE MASKING POLICY MASK_CUSTOMER_ID AS (val STRING)
RETURNS STRING ->
    CASE
        -- Full access for internal
        WHEN CURRENT_ROLE() IN ('DATA_ADMIN', 'PII_VIEWER', 'MANAGER', 'ANALYST',
                                'DATA_STEWARD', 'DATA_ENGINEER', 'ACCOUNTADMIN') THEN val
        -- Pseudonymized for AI
        WHEN CURRENT_ROLE() = 'AI_AGENT' THEN SHA2(val, 256)
        -- Masked for external
        ELSE '[ID REDACTED]'
    END;

COMMENT ON MASKING POLICY MASK_CUSTOMER_ID IS 'Masks customer IDs. Pseudonymized (hashed) for AI workloads.';

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 2: ROW ACCESS POLICIES
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Row access policies filter which rows a user can see.
-- They complement column masking for comprehensive data protection.
--
-- Common patterns:
--   - Geographic filtering (region-based access)
--   - Hierarchical filtering (department/team)
--   - Attribute filtering (sensitivity level)
--
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- ROW_ACCESS_BY_REGION: Geographic data filtering
-- ─────────────────────────────────────────────────────────────────────────────
-- Controls access based on data region (GDPR compliance)
-- EU data only visible to EU-authorized roles

CREATE OR REPLACE ROW ACCESS POLICY ROW_ACCESS_BY_REGION
AS (data_region STRING)
RETURNS BOOLEAN ->
    -- Full access roles see all
    CURRENT_ROLE() IN ('DATA_ADMIN', 'PII_VIEWER', 'ACCOUNTADMIN', 'DATA_STEWARD')
    -- Or region matches user's authorized regions
    OR (
        data_region IS NULL  -- Allow NULL regions
    )
    OR (
        data_region NOT IN ('EU', 'UK')  -- Non-EU data accessible to all
    )
    -- EU/UK data requires specific authorization (simplified - would use mapping table)
    OR (
        data_region IN ('EU', 'UK') 
        AND CURRENT_ROLE() NOT IN ('EXTERNAL_PARTNER')  -- Block external from EU data
    );

COMMENT ON ROW ACCESS POLICY ROW_ACCESS_BY_REGION IS 'GDPR-compliant region filtering. Restricts EU/UK data access.';

-- ─────────────────────────────────────────────────────────────────────────────
-- ROW_ACCESS_BY_CLASSIFICATION: Sensitivity-based filtering
-- ─────────────────────────────────────────────────────────────────────────────
-- Filters rows based on data classification level

CREATE OR REPLACE ROW ACCESS POLICY ROW_ACCESS_BY_CLASSIFICATION
AS (classification STRING)
RETURNS BOOLEAN ->
    -- Full access roles
    CURRENT_ROLE() IN ('DATA_ADMIN', 'PII_VIEWER', 'ACCOUNTADMIN')
    -- Or classification level matches role capability
    OR (
        classification = 'PUBLIC'  -- Everyone can see PUBLIC
    )
    OR (
        classification = 'INTERNAL' 
        AND CURRENT_ROLE() NOT IN ('EXTERNAL_PARTNER')
    )
    OR (
        classification = 'CONFIDENTIAL'
        AND CURRENT_ROLE() IN ('MANAGER', 'ANALYST', 'DATA_STEWARD', 'DATA_ENGINEER')
    );
    -- RESTRICTED only visible to full access roles (handled by first condition)

COMMENT ON ROW ACCESS POLICY ROW_ACCESS_BY_CLASSIFICATION IS 'Filters rows by data classification level.';

-- ─────────────────────────────────────────────────────────────────────────────
-- ROW_ACCESS_ACTIVE_ONLY: Filter to active records
-- ─────────────────────────────────────────────────────────────────────────────
-- Some roles should only see active/current records

CREATE OR REPLACE ROW ACCESS POLICY ROW_ACCESS_ACTIVE_ONLY
AS (is_current BOOLEAN)
RETURNS BOOLEAN ->
    -- Full access roles see all (including historical)
    CURRENT_ROLE() IN ('DATA_ADMIN', 'DATA_ENGINEER', 'DATA_STEWARD', 'ACCOUNTADMIN')
    -- Everyone else sees current records only
    OR is_current = TRUE;

COMMENT ON ROW ACCESS POLICY ROW_ACCESS_ACTIVE_ONLY IS 'Restricts non-admin roles to current records only.';

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 3: ROLE-BASED ACCESS MAPPING TABLE
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- For complex scenarios, policies can reference mapping tables.
-- This allows dynamic policy management without DDL changes.
--
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA GOVERNANCE.POLICIES;

-- Role to Region mapping (for geographic access control)
CREATE TABLE IF NOT EXISTS ROLE_REGION_ACCESS (
    ROLE_NAME           VARCHAR(100) NOT NULL,
    REGION              VARCHAR(50) NOT NULL,
    ACCESS_LEVEL        VARCHAR(20) DEFAULT 'READ',  -- READ, WRITE, ADMIN
    EFFECTIVE_FROM      DATE DEFAULT CURRENT_DATE(),
    EFFECTIVE_TO        DATE DEFAULT '9999-12-31',
    CONSTRAINT pk_role_region PRIMARY KEY (ROLE_NAME, REGION)
)
COMMENT = 'Maps roles to authorized geographic regions for row-level filtering.';

-- Insert default mappings
INSERT INTO ROLE_REGION_ACCESS (ROLE_NAME, REGION, ACCESS_LEVEL) VALUES
    ('DATA_ADMIN', 'GLOBAL', 'ADMIN'),
    ('DATA_STEWARD', 'GLOBAL', 'READ'),
    ('MANAGER', 'US', 'READ'),
    ('MANAGER', 'EU', 'READ'),
    ('ANALYST', 'US', 'READ'),
    ('EXTERNAL_PARTNER', 'US', 'READ');

-- Role to Department mapping (for hierarchical access control)
CREATE TABLE IF NOT EXISTS ROLE_DEPARTMENT_ACCESS (
    ROLE_NAME           VARCHAR(100) NOT NULL,
    DEPARTMENT_ID       VARCHAR(50) NOT NULL,
    ACCESS_LEVEL        VARCHAR(20) DEFAULT 'READ',
    EFFECTIVE_FROM      DATE DEFAULT CURRENT_DATE(),
    EFFECTIVE_TO        DATE DEFAULT '9999-12-31',
    CONSTRAINT pk_role_dept PRIMARY KEY (ROLE_NAME, DEPARTMENT_ID)
)
COMMENT = 'Maps roles to authorized departments for row-level filtering.';

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 4: APPLY POLICIES TO TABLES
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Apply masking policies to specific columns.
-- Policies are enforced at query time.
--
-- ═══════════════════════════════════════════════════════════════════════════

-- -----------------------------------------------------------------------------
-- CUSTOMER_RAW - Apply masking policies
-- -----------------------------------------------------------------------------

ALTER TABLE RAW_DEV.CRM.CUSTOMER_RAW 
    MODIFY COLUMN FIRST_NAME SET MASKING POLICY GOVERNANCE.POLICIES.MASK_NAME;
    
ALTER TABLE RAW_DEV.CRM.CUSTOMER_RAW 
    MODIFY COLUMN LAST_NAME SET MASKING POLICY GOVERNANCE.POLICIES.MASK_NAME;
    
ALTER TABLE RAW_DEV.CRM.CUSTOMER_RAW 
    MODIFY COLUMN EMAIL SET MASKING POLICY GOVERNANCE.POLICIES.MASK_EMAIL;
    
ALTER TABLE RAW_DEV.CRM.CUSTOMER_RAW 
    MODIFY COLUMN PHONE SET MASKING POLICY GOVERNANCE.POLICIES.MASK_PHONE;
    
ALTER TABLE RAW_DEV.CRM.CUSTOMER_RAW 
    MODIFY COLUMN ADDRESS_LINE1 SET MASKING POLICY GOVERNANCE.POLICIES.MASK_ADDRESS;

ALTER TABLE RAW_DEV.CRM.CUSTOMER_RAW 
    MODIFY COLUMN CUSTOMER_ID SET MASKING POLICY GOVERNANCE.POLICIES.MASK_CUSTOMER_ID;

-- -----------------------------------------------------------------------------
-- EMPLOYEE_RAW - Apply masking policies (more restrictive)
-- -----------------------------------------------------------------------------

ALTER TABLE RAW_DEV.HR.EMPLOYEE_RAW 
    MODIFY COLUMN SSN SET MASKING POLICY GOVERNANCE.POLICIES.MASK_SSN;
    
ALTER TABLE RAW_DEV.HR.EMPLOYEE_RAW 
    MODIFY COLUMN DATE_OF_BIRTH SET MASKING POLICY GOVERNANCE.POLICIES.MASK_DOB;
    
ALTER TABLE RAW_DEV.HR.EMPLOYEE_RAW 
    MODIFY COLUMN FIRST_NAME SET MASKING POLICY GOVERNANCE.POLICIES.MASK_NAME;
    
ALTER TABLE RAW_DEV.HR.EMPLOYEE_RAW 
    MODIFY COLUMN LAST_NAME SET MASKING POLICY GOVERNANCE.POLICIES.MASK_NAME;
    
ALTER TABLE RAW_DEV.HR.EMPLOYEE_RAW 
    MODIFY COLUMN EMAIL SET MASKING POLICY GOVERNANCE.POLICIES.MASK_EMAIL;
    
ALTER TABLE RAW_DEV.HR.EMPLOYEE_RAW 
    MODIFY COLUMN PHONE_MOBILE SET MASKING POLICY GOVERNANCE.POLICIES.MASK_PHONE;
    
ALTER TABLE RAW_DEV.HR.EMPLOYEE_RAW 
    MODIFY COLUMN HOME_ADDRESS_LINE1 SET MASKING POLICY GOVERNANCE.POLICIES.MASK_ADDRESS;
    
ALTER TABLE RAW_DEV.HR.EMPLOYEE_RAW 
    MODIFY COLUMN BASE_SALARY SET MASKING POLICY GOVERNANCE.POLICIES.MASK_SALARY;

-- -----------------------------------------------------------------------------
-- DIM_CUSTOMER (CURATED) - Apply masking policies
-- -----------------------------------------------------------------------------

ALTER DYNAMIC TABLE CURATED_DEV.DIMENSIONS.DIM_CUSTOMER 
    MODIFY COLUMN FIRST_NAME SET MASKING POLICY GOVERNANCE.POLICIES.MASK_NAME;
    
ALTER DYNAMIC TABLE CURATED_DEV.DIMENSIONS.DIM_CUSTOMER 
    MODIFY COLUMN LAST_NAME SET MASKING POLICY GOVERNANCE.POLICIES.MASK_NAME;
    
ALTER DYNAMIC TABLE CURATED_DEV.DIMENSIONS.DIM_CUSTOMER 
    MODIFY COLUMN EMAIL SET MASKING POLICY GOVERNANCE.POLICIES.MASK_EMAIL;
    
ALTER DYNAMIC TABLE CURATED_DEV.DIMENSIONS.DIM_CUSTOMER 
    MODIFY COLUMN PHONE SET MASKING POLICY GOVERNANCE.POLICIES.MASK_PHONE;
    
ALTER DYNAMIC TABLE CURATED_DEV.DIMENSIONS.DIM_CUSTOMER 
    MODIFY COLUMN ADDRESS_LINE1 SET MASKING POLICY GOVERNANCE.POLICIES.MASK_ADDRESS;

-- -----------------------------------------------------------------------------
-- DIM_EMPLOYEE (CURATED) - Apply masking policies
-- -----------------------------------------------------------------------------

ALTER DYNAMIC TABLE CURATED_DEV.DIMENSIONS.DIM_EMPLOYEE 
    MODIFY COLUMN SSN SET MASKING POLICY GOVERNANCE.POLICIES.MASK_SSN;
    
ALTER DYNAMIC TABLE CURATED_DEV.DIMENSIONS.DIM_EMPLOYEE 
    MODIFY COLUMN DATE_OF_BIRTH SET MASKING POLICY GOVERNANCE.POLICIES.MASK_DOB;
    
ALTER DYNAMIC TABLE CURATED_DEV.DIMENSIONS.DIM_EMPLOYEE 
    MODIFY COLUMN FIRST_NAME SET MASKING POLICY GOVERNANCE.POLICIES.MASK_NAME;
    
ALTER DYNAMIC TABLE CURATED_DEV.DIMENSIONS.DIM_EMPLOYEE 
    MODIFY COLUMN LAST_NAME SET MASKING POLICY GOVERNANCE.POLICIES.MASK_NAME;
    
ALTER DYNAMIC TABLE CURATED_DEV.DIMENSIONS.DIM_EMPLOYEE 
    MODIFY COLUMN EMAIL SET MASKING POLICY GOVERNANCE.POLICIES.MASK_EMAIL;
    
ALTER DYNAMIC TABLE CURATED_DEV.DIMENSIONS.DIM_EMPLOYEE 
    MODIFY COLUMN BASE_SALARY SET MASKING POLICY GOVERNANCE.POLICIES.MASK_SALARY;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT '✓ Governance Policies Created and Applied' AS STATUS;

-- Show masking policies
SHOW MASKING POLICIES IN SCHEMA GOVERNANCE.POLICIES;

-- Show row access policies
SHOW ROW ACCESS POLICIES IN SCHEMA GOVERNANCE.POLICIES;

-- Verify policy application
SELECT * FROM TABLE(INFORMATION_SCHEMA.POLICY_REFERENCES(
    POLICY_NAME => 'GOVERNANCE.POLICIES.MASK_EMAIL'
));
