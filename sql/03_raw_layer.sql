-- ============================================================================
-- RAW LAYER - SCD Type 2 Tables for Source Systems
-- ============================================================================
-- 
-- This script creates RAW layer tables with:
--   1. SCD Type 2 history tracking columns
--   2. Full governance tagging
--   3. Support for multiple source systems (CRM, ERP, HR, Operations)
--   4. Staging tables for data loading
--
-- The RAW layer is domain-agnostic - the same patterns apply whether
-- the source is Salesforce, SAP, Oracle, or any other system.
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE RAW_DEV;
USE WAREHOUSE TRANSFORM_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- SCD TYPE 2 SYSTEM COLUMNS
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Every RAW table includes these columns for history tracking:
-- 
-- | Column          | Type           | Description                           |
-- |-----------------|----------------|---------------------------------------|
-- | _LOADED_AT      | TIMESTAMP_NTZ  | When record was loaded                |
-- | _SOURCE_SYSTEM  | VARCHAR        | Origin system (SALESFORCE, SAP, etc.) |
-- | _SOURCE_TABLE   | VARCHAR        | Source table name                     |
-- | _ROW_HASH       | VARCHAR        | SHA2 hash for change detection        |
-- | _IS_CURRENT     | BOOLEAN        | TRUE for current version              |
-- | _VALID_FROM     | TIMESTAMP_NTZ  | When this version became effective    |
-- | _VALID_TO       | TIMESTAMP_NTZ  | When superseded (9999-12-31=current)  |
--
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- CRM SCHEMA - Customer and Sales Data
-- ─────────────────────────────────────────────────────────────────────────────

USE SCHEMA RAW_DEV.CRM;

-- =============================================================================
-- CUSTOMER_RAW: Core customer/account data
-- =============================================================================

CREATE TABLE IF NOT EXISTS CUSTOMER_RAW (
    -- Business Keys
    CUSTOMER_ID             VARCHAR(50)         NOT NULL,
    
    -- Core Attributes (PII)
    FIRST_NAME              VARCHAR(100),
    LAST_NAME               VARCHAR(100),
    EMAIL                   VARCHAR(255),
    PHONE                   VARCHAR(50),
    MOBILE_PHONE            VARCHAR(50),
    
    -- Address (PII)
    ADDRESS_LINE1           VARCHAR(255),
    ADDRESS_LINE2           VARCHAR(255),
    CITY                    VARCHAR(100),
    STATE_PROVINCE          VARCHAR(100),
    POSTAL_CODE             VARCHAR(20),
    COUNTRY                 VARCHAR(100),
    
    -- Business Attributes
    COMPANY_NAME            VARCHAR(255),
    INDUSTRY                VARCHAR(100),
    COMPANY_SIZE            VARCHAR(50),
    CUSTOMER_TYPE           VARCHAR(50),
    CUSTOMER_STATUS         VARCHAR(50),
    CUSTOMER_SEGMENT        VARCHAR(50),
    
    -- Financial
    LIFETIME_VALUE          NUMBER(18,2),
    CREDIT_LIMIT            NUMBER(18,2),
    PAYMENT_TERMS           VARCHAR(50),
    CURRENCY_CODE           VARCHAR(10),
    
    -- Dates
    CREATED_DATE            DATE,
    FIRST_PURCHASE_DATE     DATE,
    LAST_PURCHASE_DATE      DATE,
    CHURN_DATE              DATE,
    
    -- Relationships
    ACCOUNT_OWNER_ID        VARCHAR(50),
    PARENT_CUSTOMER_ID      VARCHAR(50),
    
    -- Region/Territory
    REGION                  VARCHAR(100),
    TERRITORY               VARCHAR(100),
    
    -- Consent/Compliance
    MARKETING_CONSENT       BOOLEAN,
    DATA_PROCESSING_CONSENT BOOLEAN,
    CONSENT_DATE            DATE,
    GDPR_DELETE_REQUESTED   BOOLEAN,
    
    -- SCD Type 2 System Columns
    _LOADED_AT              TIMESTAMP_NTZ       DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_SYSTEM          VARCHAR(100)        DEFAULT 'CRM',
    _SOURCE_TABLE           VARCHAR(100)        DEFAULT 'CUSTOMER',
    _ROW_HASH               VARCHAR(64),
    _IS_CURRENT             BOOLEAN             DEFAULT TRUE,
    _VALID_FROM             TIMESTAMP_NTZ       DEFAULT CURRENT_TIMESTAMP(),
    _VALID_TO               TIMESTAMP_NTZ       DEFAULT '9999-12-31'::TIMESTAMP_NTZ,
    
    -- Constraints
    CONSTRAINT pk_customer_raw PRIMARY KEY (CUSTOMER_ID, _VALID_FROM)
)
COMMENT = 'Raw customer/account data from CRM system with SCD Type 2 history.';

-- =============================================================================
-- ORDER_RAW: Sales transactions/orders
-- =============================================================================

CREATE TABLE IF NOT EXISTS ORDER_RAW (
    -- Business Keys
    ORDER_ID                VARCHAR(50)         NOT NULL,
    ORDER_NUMBER            VARCHAR(50),
    
    -- Relationships
    CUSTOMER_ID             VARCHAR(50)         NOT NULL,
    ACCOUNT_ID              VARCHAR(50),
    SALES_REP_ID            VARCHAR(50),
    
    -- Order Details
    ORDER_DATE              DATE                NOT NULL,
    ORDER_STATUS            VARCHAR(50),
    ORDER_TYPE              VARCHAR(50),
    ORDER_PRIORITY          VARCHAR(20),
    
    -- Financial
    SUBTOTAL                NUMBER(18,2),
    DISCOUNT_AMOUNT         NUMBER(18,2),
    TAX_AMOUNT              NUMBER(18,2),
    SHIPPING_AMOUNT         NUMBER(18,2),
    ORDER_TOTAL             NUMBER(18,2),
    CURRENCY_CODE           VARCHAR(10),
    
    -- Shipping
    SHIP_DATE               DATE,
    DELIVERY_DATE           DATE,
    SHIPPING_METHOD         VARCHAR(100),
    TRACKING_NUMBER         VARCHAR(100),
    
    -- Shipping Address
    SHIP_ADDRESS_LINE1      VARCHAR(255),
    SHIP_ADDRESS_LINE2      VARCHAR(255),
    SHIP_CITY               VARCHAR(100),
    SHIP_STATE              VARCHAR(100),
    SHIP_POSTAL_CODE        VARCHAR(20),
    SHIP_COUNTRY            VARCHAR(100),
    
    -- Channel/Source
    SALES_CHANNEL           VARCHAR(50),
    SOURCE_CAMPAIGN         VARCHAR(100),
    
    -- Region
    REGION                  VARCHAR(100),
    
    -- SCD Type 2 System Columns
    _LOADED_AT              TIMESTAMP_NTZ       DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_SYSTEM          VARCHAR(100)        DEFAULT 'CRM',
    _SOURCE_TABLE           VARCHAR(100)        DEFAULT 'ORDER',
    _ROW_HASH               VARCHAR(64),
    _IS_CURRENT             BOOLEAN             DEFAULT TRUE,
    _VALID_FROM             TIMESTAMP_NTZ       DEFAULT CURRENT_TIMESTAMP(),
    _VALID_TO               TIMESTAMP_NTZ       DEFAULT '9999-12-31'::TIMESTAMP_NTZ,
    
    CONSTRAINT pk_order_raw PRIMARY KEY (ORDER_ID, _VALID_FROM)
)
COMMENT = 'Raw order/transaction data from CRM system with SCD Type 2 history.';

-- =============================================================================
-- ORDER_LINE_RAW: Order line items
-- =============================================================================

CREATE TABLE IF NOT EXISTS ORDER_LINE_RAW (
    -- Business Keys
    ORDER_LINE_ID           VARCHAR(50)         NOT NULL,
    ORDER_ID                VARCHAR(50)         NOT NULL,
    
    -- Product Reference
    PRODUCT_ID              VARCHAR(50)         NOT NULL,
    PRODUCT_CODE            VARCHAR(50),
    PRODUCT_NAME            VARCHAR(255),
    
    -- Quantities
    QUANTITY                NUMBER(18,4),
    UNIT_OF_MEASURE         VARCHAR(20),
    
    -- Pricing
    UNIT_PRICE              NUMBER(18,4),
    DISCOUNT_PERCENT        NUMBER(5,2),
    DISCOUNT_AMOUNT         NUMBER(18,2),
    LINE_TOTAL              NUMBER(18,2),
    COST_AMOUNT             NUMBER(18,2),
    
    -- Fulfillment
    FULFILLED_QUANTITY      NUMBER(18,4),
    RETURNED_QUANTITY       NUMBER(18,4),
    LINE_STATUS             VARCHAR(50),
    
    -- SCD Type 2 System Columns
    _LOADED_AT              TIMESTAMP_NTZ       DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_SYSTEM          VARCHAR(100)        DEFAULT 'CRM',
    _SOURCE_TABLE           VARCHAR(100)        DEFAULT 'ORDER_LINE',
    _ROW_HASH               VARCHAR(64),
    _IS_CURRENT             BOOLEAN             DEFAULT TRUE,
    _VALID_FROM             TIMESTAMP_NTZ       DEFAULT CURRENT_TIMESTAMP(),
    _VALID_TO               TIMESTAMP_NTZ       DEFAULT '9999-12-31'::TIMESTAMP_NTZ,
    
    CONSTRAINT pk_order_line_raw PRIMARY KEY (ORDER_LINE_ID, _VALID_FROM)
)
COMMENT = 'Raw order line item data with SCD Type 2 history.';

-- =============================================================================
-- PRODUCT_RAW: Product catalog
-- =============================================================================

CREATE TABLE IF NOT EXISTS PRODUCT_RAW (
    -- Business Keys
    PRODUCT_ID              VARCHAR(50)         NOT NULL,
    PRODUCT_CODE            VARCHAR(50)         NOT NULL,
    
    -- Product Details
    PRODUCT_NAME            VARCHAR(255)        NOT NULL,
    PRODUCT_DESCRIPTION     VARCHAR(4000),
    
    -- Classification
    PRODUCT_CATEGORY        VARCHAR(100),
    PRODUCT_SUBCATEGORY     VARCHAR(100),
    PRODUCT_LINE            VARCHAR(100),
    BRAND                   VARCHAR(100),
    
    -- Pricing
    LIST_PRICE              NUMBER(18,4),
    COST_PRICE              NUMBER(18,4),
    CURRENCY_CODE           VARCHAR(10),
    
    -- Status
    PRODUCT_STATUS          VARCHAR(50),
    IS_ACTIVE               BOOLEAN,
    LAUNCH_DATE             DATE,
    DISCONTINUE_DATE        DATE,
    
    -- Inventory
    REORDER_POINT           NUMBER(18,4),
    SAFETY_STOCK            NUMBER(18,4),
    LEAD_TIME_DAYS          NUMBER(10),
    
    -- Attributes
    WEIGHT                  NUMBER(18,4),
    WEIGHT_UNIT             VARCHAR(20),
    SIZE_DIMENSIONS         VARCHAR(100),
    COLOR                   VARCHAR(50),
    
    -- SCD Type 2 System Columns
    _LOADED_AT              TIMESTAMP_NTZ       DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_SYSTEM          VARCHAR(100)        DEFAULT 'ERP',
    _SOURCE_TABLE           VARCHAR(100)        DEFAULT 'PRODUCT',
    _ROW_HASH               VARCHAR(64),
    _IS_CURRENT             BOOLEAN             DEFAULT TRUE,
    _VALID_FROM             TIMESTAMP_NTZ       DEFAULT CURRENT_TIMESTAMP(),
    _VALID_TO               TIMESTAMP_NTZ       DEFAULT '9999-12-31'::TIMESTAMP_NTZ,
    
    CONSTRAINT pk_product_raw PRIMARY KEY (PRODUCT_ID, _VALID_FROM)
)
COMMENT = 'Raw product catalog data with SCD Type 2 history.';

-- ─────────────────────────────────────────────────────────────────────────────
-- HR SCHEMA - Employee/Workforce Data
-- ─────────────────────────────────────────────────────────────────────────────

USE SCHEMA RAW_DEV.HR;

-- =============================================================================
-- EMPLOYEE_RAW: Employee master data
-- =============================================================================

CREATE TABLE IF NOT EXISTS EMPLOYEE_RAW (
    -- Business Keys
    EMPLOYEE_ID             VARCHAR(50)         NOT NULL,
    EMPLOYEE_NUMBER         VARCHAR(50),
    
    -- PII - Personal Information
    FIRST_NAME              VARCHAR(100),
    MIDDLE_NAME             VARCHAR(100),
    LAST_NAME               VARCHAR(100),
    PREFERRED_NAME          VARCHAR(100),
    EMAIL                   VARCHAR(255),
    PERSONAL_EMAIL          VARCHAR(255),
    PHONE_WORK              VARCHAR(50),
    PHONE_MOBILE            VARCHAR(50),
    
    -- Highly Sensitive PII
    SSN                     VARCHAR(20),
    DATE_OF_BIRTH           DATE,
    GENDER                  VARCHAR(20),
    NATIONALITY             VARCHAR(100),
    
    -- Address
    HOME_ADDRESS_LINE1      VARCHAR(255),
    HOME_ADDRESS_LINE2      VARCHAR(255),
    HOME_CITY               VARCHAR(100),
    HOME_STATE              VARCHAR(100),
    HOME_POSTAL_CODE        VARCHAR(20),
    HOME_COUNTRY            VARCHAR(100),
    
    -- Employment Details
    HIRE_DATE               DATE,
    TERMINATION_DATE        DATE,
    EMPLOYMENT_STATUS       VARCHAR(50),
    EMPLOYMENT_TYPE         VARCHAR(50),
    
    -- Position
    JOB_TITLE               VARCHAR(255),
    JOB_LEVEL               VARCHAR(50),
    DEPARTMENT_ID           VARCHAR(50),
    DEPARTMENT_NAME         VARCHAR(255),
    DIVISION                VARCHAR(100),
    COST_CENTER             VARCHAR(50),
    
    -- Manager
    MANAGER_ID              VARCHAR(50),
    MANAGER_NAME            VARCHAR(255),
    
    -- Location
    WORK_LOCATION           VARCHAR(255),
    WORK_CITY               VARCHAR(100),
    WORK_STATE              VARCHAR(100),
    WORK_COUNTRY            VARCHAR(100),
    REMOTE_WORKER           BOOLEAN,
    
    -- Compensation (Sensitive)
    BASE_SALARY             NUMBER(18,2),
    SALARY_CURRENCY         VARCHAR(10),
    PAY_FREQUENCY           VARCHAR(20),
    BONUS_TARGET_PERCENT    NUMBER(5,2),
    STOCK_OPTIONS           NUMBER(18,4),
    
    -- SCD Type 2 System Columns
    _LOADED_AT              TIMESTAMP_NTZ       DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_SYSTEM          VARCHAR(100)        DEFAULT 'HR',
    _SOURCE_TABLE           VARCHAR(100)        DEFAULT 'EMPLOYEE',
    _ROW_HASH               VARCHAR(64),
    _IS_CURRENT             BOOLEAN             DEFAULT TRUE,
    _VALID_FROM             TIMESTAMP_NTZ       DEFAULT CURRENT_TIMESTAMP(),
    _VALID_TO               TIMESTAMP_NTZ       DEFAULT '9999-12-31'::TIMESTAMP_NTZ,
    
    CONSTRAINT pk_employee_raw PRIMARY KEY (EMPLOYEE_ID, _VALID_FROM)
)
COMMENT = 'Raw employee data from HR system with SCD Type 2 history. Contains PII.';

-- =============================================================================
-- DEPARTMENT_RAW: Organizational structure
-- =============================================================================

CREATE TABLE IF NOT EXISTS DEPARTMENT_RAW (
    -- Business Keys
    DEPARTMENT_ID           VARCHAR(50)         NOT NULL,
    DEPARTMENT_CODE         VARCHAR(50),
    
    -- Department Details
    DEPARTMENT_NAME         VARCHAR(255)        NOT NULL,
    DEPARTMENT_DESCRIPTION  VARCHAR(1000),
    
    -- Hierarchy
    PARENT_DEPARTMENT_ID    VARCHAR(50),
    DIVISION                VARCHAR(100),
    BUSINESS_UNIT           VARCHAR(100),
    
    -- Leadership
    DEPARTMENT_HEAD_ID      VARCHAR(50),
    DEPARTMENT_HEAD_NAME    VARCHAR(255),
    
    -- Budgeting
    COST_CENTER             VARCHAR(50),
    BUDGET_AMOUNT           NUMBER(18,2),
    HEADCOUNT_BUDGET        NUMBER(10),
    
    -- Status
    IS_ACTIVE               BOOLEAN,
    EFFECTIVE_DATE          DATE,
    END_DATE                DATE,
    
    -- Location
    PRIMARY_LOCATION        VARCHAR(255),
    
    -- SCD Type 2 System Columns
    _LOADED_AT              TIMESTAMP_NTZ       DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_SYSTEM          VARCHAR(100)        DEFAULT 'HR',
    _SOURCE_TABLE           VARCHAR(100)        DEFAULT 'DEPARTMENT',
    _ROW_HASH               VARCHAR(64),
    _IS_CURRENT             BOOLEAN             DEFAULT TRUE,
    _VALID_FROM             TIMESTAMP_NTZ       DEFAULT CURRENT_TIMESTAMP(),
    _VALID_TO               TIMESTAMP_NTZ       DEFAULT '9999-12-31'::TIMESTAMP_NTZ,
    
    CONSTRAINT pk_department_raw PRIMARY KEY (DEPARTMENT_ID, _VALID_FROM)
)
COMMENT = 'Raw department/org structure data with SCD Type 2 history.';

-- ─────────────────────────────────────────────────────────────────────────────
-- OPERATIONS SCHEMA - Operational Data
-- ─────────────────────────────────────────────────────────────────────────────

USE SCHEMA RAW_DEV.OPERATIONS;

-- =============================================================================
-- LOCATION_RAW: Facilities/locations
-- =============================================================================

CREATE TABLE IF NOT EXISTS LOCATION_RAW (
    -- Business Keys
    LOCATION_ID             VARCHAR(50)         NOT NULL,
    LOCATION_CODE           VARCHAR(50),
    
    -- Location Details
    LOCATION_NAME           VARCHAR(255)        NOT NULL,
    LOCATION_TYPE           VARCHAR(50),
    
    -- Address
    ADDRESS_LINE1           VARCHAR(255),
    ADDRESS_LINE2           VARCHAR(255),
    CITY                    VARCHAR(100),
    STATE_PROVINCE          VARCHAR(100),
    POSTAL_CODE             VARCHAR(20),
    COUNTRY                 VARCHAR(100),
    REGION                  VARCHAR(100),
    
    -- Geo
    LATITUDE                NUMBER(10,7),
    LONGITUDE               NUMBER(10,7),
    TIMEZONE                VARCHAR(50),
    
    -- Capacity
    CAPACITY                NUMBER(18,4),
    SQUARE_FOOTAGE          NUMBER(18,2),
    EMPLOYEE_COUNT          NUMBER(10),
    
    -- Status
    IS_ACTIVE               BOOLEAN,
    OPEN_DATE               DATE,
    CLOSE_DATE              DATE,
    
    -- Contact
    PHONE                   VARCHAR(50),
    EMAIL                   VARCHAR(255),
    MANAGER_ID              VARCHAR(50),
    
    -- SCD Type 2 System Columns
    _LOADED_AT              TIMESTAMP_NTZ       DEFAULT CURRENT_TIMESTAMP(),
    _SOURCE_SYSTEM          VARCHAR(100)        DEFAULT 'OPERATIONS',
    _SOURCE_TABLE           VARCHAR(100)        DEFAULT 'LOCATION',
    _ROW_HASH               VARCHAR(64),
    _IS_CURRENT             BOOLEAN             DEFAULT TRUE,
    _VALID_FROM             TIMESTAMP_NTZ       DEFAULT CURRENT_TIMESTAMP(),
    _VALID_TO               TIMESTAMP_NTZ       DEFAULT '9999-12-31'::TIMESTAMP_NTZ,
    
    CONSTRAINT pk_location_raw PRIMARY KEY (LOCATION_ID, _VALID_FROM)
)
COMMENT = 'Raw location/facility data with SCD Type 2 history.';

-- ═══════════════════════════════════════════════════════════════════════════
-- GOVERNANCE TAG APPLICATION
-- ═══════════════════════════════════════════════════════════════════════════

-- -----------------------------------------------------------------------------
-- CUSTOMER_RAW Tags
-- -----------------------------------------------------------------------------

USE SCHEMA RAW_DEV.CRM;

-- Table-level tags
ALTER TABLE CUSTOMER_RAW SET TAG 
    GOVERNANCE.TAGS.DATA_CLASSIFICATION = 'CONFIDENTIAL',
    GOVERNANCE.TAGS.DATA_DOMAIN = 'CUSTOMER',
    GOVERNANCE.TAGS.DATA_QUALITY_TIER = 'BRONZE',
    GOVERNANCE.TAGS.SOURCE_SYSTEM = 'CRM';

-- PII Column tags
ALTER TABLE CUSTOMER_RAW MODIFY COLUMN FIRST_NAME SET TAG
    GOVERNANCE.TAGS.PII_TYPE = 'DIRECT',
    GOVERNANCE.TAGS.AI_ALLOWED = 'PSEUDONYMIZED',
    GOVERNANCE.TAGS.GDPR_CATEGORY = 'PERSONAL_DATA';

ALTER TABLE CUSTOMER_RAW MODIFY COLUMN LAST_NAME SET TAG
    GOVERNANCE.TAGS.PII_TYPE = 'DIRECT',
    GOVERNANCE.TAGS.AI_ALLOWED = 'PSEUDONYMIZED',
    GOVERNANCE.TAGS.GDPR_CATEGORY = 'PERSONAL_DATA';

ALTER TABLE CUSTOMER_RAW MODIFY COLUMN EMAIL SET TAG
    GOVERNANCE.TAGS.PII_TYPE = 'DIRECT',
    GOVERNANCE.TAGS.AI_ALLOWED = 'PSEUDONYMIZED',
    GOVERNANCE.TAGS.GDPR_CATEGORY = 'PERSONAL_DATA';

ALTER TABLE CUSTOMER_RAW MODIFY COLUMN PHONE SET TAG
    GOVERNANCE.TAGS.PII_TYPE = 'DIRECT',
    GOVERNANCE.TAGS.AI_ALLOWED = 'FALSE',
    GOVERNANCE.TAGS.GDPR_CATEGORY = 'PERSONAL_DATA';

ALTER TABLE CUSTOMER_RAW MODIFY COLUMN ADDRESS_LINE1 SET TAG
    GOVERNANCE.TAGS.PII_TYPE = 'DIRECT',
    GOVERNANCE.TAGS.AI_ALLOWED = 'FALSE',
    GOVERNANCE.TAGS.GDPR_CATEGORY = 'PERSONAL_DATA';

-- Non-PII tags
ALTER TABLE CUSTOMER_RAW MODIFY COLUMN CUSTOMER_SEGMENT SET TAG
    GOVERNANCE.TAGS.PII_TYPE = 'NONE',
    GOVERNANCE.TAGS.AI_ALLOWED = 'TRUE';

ALTER TABLE CUSTOMER_RAW MODIFY COLUMN REGION SET TAG
    GOVERNANCE.TAGS.PII_TYPE = 'NONE',
    GOVERNANCE.TAGS.AI_ALLOWED = 'TRUE';

-- -----------------------------------------------------------------------------
-- EMPLOYEE_RAW Tags (Highly Sensitive)
-- -----------------------------------------------------------------------------

USE SCHEMA RAW_DEV.HR;

-- Table-level tags
ALTER TABLE EMPLOYEE_RAW SET TAG 
    GOVERNANCE.TAGS.DATA_CLASSIFICATION = 'RESTRICTED',
    GOVERNANCE.TAGS.DATA_DOMAIN = 'EMPLOYEE',
    GOVERNANCE.TAGS.DATA_QUALITY_TIER = 'BRONZE',
    GOVERNANCE.TAGS.SOURCE_SYSTEM = 'HR';

-- SSN - Most sensitive
ALTER TABLE EMPLOYEE_RAW MODIFY COLUMN SSN SET TAG
    GOVERNANCE.TAGS.PII_TYPE = 'SENSITIVE',
    GOVERNANCE.TAGS.AI_ALLOWED = 'FALSE',
    GOVERNANCE.TAGS.GDPR_CATEGORY = 'PERSONAL_DATA',
    GOVERNANCE.TAGS.DATA_CLASSIFICATION = 'RESTRICTED',
    GOVERNANCE.TAGS.RESIDENCY_REGION = 'US_ONLY';

-- DOB - Sensitive
ALTER TABLE EMPLOYEE_RAW MODIFY COLUMN DATE_OF_BIRTH SET TAG
    GOVERNANCE.TAGS.PII_TYPE = 'SENSITIVE',
    GOVERNANCE.TAGS.AI_ALLOWED = 'AGGREGATED',
    GOVERNANCE.TAGS.GDPR_CATEGORY = 'PERSONAL_DATA';

-- Salary - Sensitive
ALTER TABLE EMPLOYEE_RAW MODIFY COLUMN BASE_SALARY SET TAG
    GOVERNANCE.TAGS.PII_TYPE = 'SENSITIVE',
    GOVERNANCE.TAGS.AI_ALLOWED = 'AGGREGATED',
    GOVERNANCE.TAGS.DATA_CLASSIFICATION = 'RESTRICTED';

-- Name/Email - Direct PII
ALTER TABLE EMPLOYEE_RAW MODIFY COLUMN FIRST_NAME SET TAG
    GOVERNANCE.TAGS.PII_TYPE = 'DIRECT',
    GOVERNANCE.TAGS.AI_ALLOWED = 'PSEUDONYMIZED';

ALTER TABLE EMPLOYEE_RAW MODIFY COLUMN LAST_NAME SET TAG
    GOVERNANCE.TAGS.PII_TYPE = 'DIRECT',
    GOVERNANCE.TAGS.AI_ALLOWED = 'PSEUDONYMIZED';

ALTER TABLE EMPLOYEE_RAW MODIFY COLUMN EMAIL SET TAG
    GOVERNANCE.TAGS.PII_TYPE = 'DIRECT',
    GOVERNANCE.TAGS.AI_ALLOWED = 'PSEUDONYMIZED';

-- Non-PII
ALTER TABLE EMPLOYEE_RAW MODIFY COLUMN DEPARTMENT_NAME SET TAG
    GOVERNANCE.TAGS.PII_TYPE = 'NONE',
    GOVERNANCE.TAGS.AI_ALLOWED = 'TRUE';

ALTER TABLE EMPLOYEE_RAW MODIFY COLUMN JOB_TITLE SET TAG
    GOVERNANCE.TAGS.PII_TYPE = 'NONE',
    GOVERNANCE.TAGS.AI_ALLOWED = 'TRUE';

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANT ACCESS TO RAW LAYER
-- ═══════════════════════════════════════════════════════════════════════════

-- DATA_ENGINEER: Full access
GRANT USAGE ON SCHEMA RAW_DEV.CRM TO ROLE DATA_ENGINEER;
GRANT USAGE ON SCHEMA RAW_DEV.HR TO ROLE DATA_ENGINEER;
GRANT USAGE ON SCHEMA RAW_DEV.OPERATIONS TO ROLE DATA_ENGINEER;
GRANT USAGE ON SCHEMA RAW_DEV.ERP TO ROLE DATA_ENGINEER;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA RAW_DEV.CRM TO ROLE DATA_ENGINEER;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA RAW_DEV.HR TO ROLE DATA_ENGINEER;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA RAW_DEV.OPERATIONS TO ROLE DATA_ENGINEER;

-- DATA_STEWARD: Read access
GRANT SELECT ON ALL TABLES IN SCHEMA RAW_DEV.CRM TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL TABLES IN SCHEMA RAW_DEV.HR TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL TABLES IN SCHEMA RAW_DEV.OPERATIONS TO ROLE DATA_STEWARD;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT '✓ RAW Layer Tables Created' AS STATUS;

SHOW TABLES IN SCHEMA RAW_DEV.CRM;
SHOW TABLES IN SCHEMA RAW_DEV.HR;
SHOW TABLES IN SCHEMA RAW_DEV.OPERATIONS;

-- Check tags applied
SELECT * FROM TABLE(INFORMATION_SCHEMA.TAG_REFERENCES('RAW_DEV.CRM.CUSTOMER_RAW', 'TABLE'))
ORDER BY COLUMN_NAME, TAG_NAME;
