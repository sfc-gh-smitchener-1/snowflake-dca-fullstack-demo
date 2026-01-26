-- ============================================================================
-- CURATED LAYER - Dynamic Tables for Business-Ready Data
-- ============================================================================
-- 
-- This script creates Dynamic Tables that:
--   1. Transform raw data into dimensional model (dims and facts)
--   2. Automatically refresh based on upstream changes
--   3. Apply business rules and derived attributes
--   4. Create pseudonymized columns for AI-safe consumption
--   5. Enforce data quality through transformation
--
-- Dynamic Tables use TARGET_LAG to define freshness SLAs:
--   - Reference data: 24 hours
--   - Dimension tables: 1-4 hours
--   - Fact tables: 15-60 minutes
--   - Aggregates: 1-4 hours
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE CURATED_DEV;
USE WAREHOUSE TRANSFORM_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- DIMENSION: Date (Static Table - Not Dynamic)
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Date dimension is static and pre-generated.
-- Covers 2015-2030 for historical and future analysis.
--
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA CURATED_DEV.DIMENSIONS;

CREATE OR REPLACE TABLE DIM_DATE AS
WITH date_spine AS (
    SELECT DATEADD(DAY, SEQ4(), '2015-01-01')::DATE AS DATE_KEY
    FROM TABLE(GENERATOR(ROWCOUNT => 5844))  -- ~16 years
)
SELECT
    -- Primary Key
    DATE_KEY,
    DATE_KEY AS FULL_DATE,
    
    -- Year attributes
    YEAR(DATE_KEY) AS YEAR,
    QUARTER(DATE_KEY) AS QUARTER,
    MONTH(DATE_KEY) AS MONTH,
    MONTHNAME(DATE_KEY) AS MONTH_NAME,
    WEEK(DATE_KEY) AS WEEK_OF_YEAR,
    DAYOFWEEK(DATE_KEY) AS DAY_OF_WEEK,
    DAYNAME(DATE_KEY) AS DAY_NAME,
    DAYOFMONTH(DATE_KEY) AS DAY_OF_MONTH,
    DAYOFYEAR(DATE_KEY) AS DAY_OF_YEAR,
    
    -- Fiscal Year (July start)
    CASE WHEN MONTH(DATE_KEY) >= 7 THEN YEAR(DATE_KEY) ELSE YEAR(DATE_KEY) - 1 END AS FISCAL_YEAR,
    CASE 
        WHEN MONTH(DATE_KEY) >= 7 THEN MONTH(DATE_KEY) - 6 
        ELSE MONTH(DATE_KEY) + 6 
    END AS FISCAL_MONTH,
    CEIL(CASE WHEN MONTH(DATE_KEY) >= 7 THEN MONTH(DATE_KEY) - 6 ELSE MONTH(DATE_KEY) + 6 END / 3.0) AS FISCAL_QUARTER,
    
    -- Week flags
    CASE WHEN DAYOFWEEK(DATE_KEY) IN (0, 6) THEN TRUE ELSE FALSE END AS IS_WEEKEND,
    CASE WHEN DAYOFWEEK(DATE_KEY) IN (0, 6) THEN FALSE ELSE TRUE END AS IS_WEEKDAY,
    
    -- Common holidays (US - simplified)
    CASE 
        WHEN MONTH(DATE_KEY) = 1 AND DAYOFMONTH(DATE_KEY) = 1 THEN TRUE  -- New Year
        WHEN MONTH(DATE_KEY) = 7 AND DAYOFMONTH(DATE_KEY) = 4 THEN TRUE  -- July 4
        WHEN MONTH(DATE_KEY) = 12 AND DAYOFMONTH(DATE_KEY) = 25 THEN TRUE  -- Christmas
        WHEN MONTH(DATE_KEY) = 11 AND DAYOFWEEK(DATE_KEY) = 4 
             AND DAYOFMONTH(DATE_KEY) BETWEEN 22 AND 28 THEN TRUE  -- Thanksgiving
        ELSE FALSE
    END AS IS_HOLIDAY,
    
    -- Period keys for grouping
    TO_CHAR(DATE_KEY, 'YYYYMM')::INT AS YEAR_MONTH_KEY,
    TO_CHAR(DATE_KEY, 'YYYYQ')::VARCHAR AS YEAR_QUARTER_KEY,
    YEAR(DATE_KEY) * 100 + WEEK(DATE_KEY) AS YEAR_WEEK_KEY,
    
    -- Relative date flags
    CASE WHEN DATE_KEY = CURRENT_DATE() THEN TRUE ELSE FALSE END AS IS_TODAY,
    CASE WHEN DATE_KEY = DATEADD(DAY, -1, CURRENT_DATE()) THEN TRUE ELSE FALSE END AS IS_YESTERDAY,
    CASE WHEN DATE_KEY >= DATE_TRUNC('WEEK', CURRENT_DATE()) 
         AND DATE_KEY < DATEADD(WEEK, 1, DATE_TRUNC('WEEK', CURRENT_DATE())) THEN TRUE ELSE FALSE END AS IS_CURRENT_WEEK,
    CASE WHEN DATE_KEY >= DATE_TRUNC('MONTH', CURRENT_DATE()) 
         AND DATE_KEY < DATEADD(MONTH, 1, DATE_TRUNC('MONTH', CURRENT_DATE())) THEN TRUE ELSE FALSE END AS IS_CURRENT_MONTH
    
FROM date_spine
WHERE DATE_KEY <= '2030-12-31';

-- Apply tags
ALTER TABLE DIM_DATE SET TAG 
    GOVERNANCE.TAGS.DATA_CLASSIFICATION = 'PUBLIC',
    GOVERNANCE.TAGS.DATA_QUALITY_TIER = 'GOLD';

-- ═══════════════════════════════════════════════════════════════════════════
-- DIMENSION: Customer
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Customer dimension with:
--   - Pseudonymized keys for AI workloads
--   - Derived attributes (segment, tenure, etc.)
--   - Display name for privacy-safe reporting
--   - Current record only (_IS_CURRENT = TRUE)
--
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.DIMENSIONS.DIM_CUSTOMER
    TARGET_LAG = '1 hour'
    WAREHOUSE = TRANSFORM_WH
    COMMENT = 'Customer dimension with derived attributes and pseudonymization for AI safety.'
AS
SELECT
    -- Surrogate Key
    c.CUSTOMER_ID AS CUSTOMER_KEY,
    c.CUSTOMER_ID,
    
    -- Pseudonymized Keys (for AI workloads)
    SHA2(c.CUSTOMER_ID, 256) AS CUSTOMER_ID_HASH,
    SHA2(COALESCE(c.EMAIL, c.CUSTOMER_ID), 256) AS EMAIL_HASH,
    SHA2(CONCAT(COALESCE(c.FIRST_NAME,''), ' ', COALESCE(c.LAST_NAME,'')), 256) AS NAME_HASH,
    
    -- PII Fields (will be masked downstream)
    c.FIRST_NAME,
    c.LAST_NAME,
    c.EMAIL,
    c.PHONE,
    c.MOBILE_PHONE,
    c.ADDRESS_LINE1,
    c.ADDRESS_LINE2,
    c.CITY,
    c.STATE_PROVINCE,
    c.POSTAL_CODE,
    c.COUNTRY,
    
    -- Derived: Display Name (privacy-safe)
    COALESCE(c.FIRST_NAME, 'Customer') || ' ' || LEFT(COALESCE(c.LAST_NAME, 'X'), 1) || '.' AS DISPLAY_NAME,
    
    -- Business Attributes
    c.COMPANY_NAME,
    c.INDUSTRY,
    c.COMPANY_SIZE,
    c.CUSTOMER_TYPE,
    c.CUSTOMER_STATUS,
    c.CUSTOMER_SEGMENT,
    
    -- Derived: Segment Tier
    CASE 
        WHEN c.LIFETIME_VALUE >= 100000 THEN 'ENTERPRISE'
        WHEN c.LIFETIME_VALUE >= 25000 THEN 'MID-MARKET'
        WHEN c.LIFETIME_VALUE >= 5000 THEN 'SMB'
        ELSE 'STARTER'
    END AS CUSTOMER_TIER,
    
    -- Financial
    c.LIFETIME_VALUE,
    c.CREDIT_LIMIT,
    c.PAYMENT_TERMS,
    c.CURRENCY_CODE,
    
    -- Dates
    c.CREATED_DATE,
    c.FIRST_PURCHASE_DATE,
    c.LAST_PURCHASE_DATE,
    c.CHURN_DATE,
    
    -- Derived: Tenure Days
    DATEDIFF('day', c.CREATED_DATE, CURRENT_DATE()) AS TENURE_DAYS,
    
    -- Derived: Tenure Bucket
    CASE 
        WHEN DATEDIFF('day', c.CREATED_DATE, CURRENT_DATE()) >= 1095 THEN '3+ Years'
        WHEN DATEDIFF('day', c.CREATED_DATE, CURRENT_DATE()) >= 730 THEN '2-3 Years'
        WHEN DATEDIFF('day', c.CREATED_DATE, CURRENT_DATE()) >= 365 THEN '1-2 Years'
        WHEN DATEDIFF('day', c.CREATED_DATE, CURRENT_DATE()) >= 90 THEN '3-12 Months'
        ELSE '<3 Months'
    END AS TENURE_BUCKET,
    
    -- Derived: Days Since Last Purchase
    DATEDIFF('day', c.LAST_PURCHASE_DATE, CURRENT_DATE()) AS DAYS_SINCE_LAST_PURCHASE,
    
    -- Derived: Customer Health
    CASE 
        WHEN c.CHURN_DATE IS NOT NULL THEN 'CHURNED'
        WHEN DATEDIFF('day', c.LAST_PURCHASE_DATE, CURRENT_DATE()) > 180 THEN 'AT_RISK'
        WHEN DATEDIFF('day', c.LAST_PURCHASE_DATE, CURRENT_DATE()) > 90 THEN 'DORMANT'
        ELSE 'ACTIVE'
    END AS CUSTOMER_HEALTH,
    
    -- Derived: Is Active
    CASE WHEN c.CUSTOMER_STATUS = 'ACTIVE' AND c.CHURN_DATE IS NULL THEN TRUE ELSE FALSE END AS IS_ACTIVE,
    
    -- Relationships
    c.ACCOUNT_OWNER_ID,
    c.PARENT_CUSTOMER_ID,
    
    -- Region/Territory
    c.REGION,
    c.TERRITORY,
    
    -- Consent
    c.MARKETING_CONSENT,
    c.DATA_PROCESSING_CONSENT,
    c.CONSENT_DATE,
    c.GDPR_DELETE_REQUESTED,
    
    -- Metadata
    c._LOADED_AT AS _SOURCE_LOADED_AT,
    c._SOURCE_SYSTEM,
    c._ROW_HASH AS _SOURCE_HASH,
    c._IS_CURRENT
    
FROM RAW_DEV.CRM.CUSTOMER_RAW c
WHERE c._IS_CURRENT = TRUE;

-- Apply tags
ALTER DYNAMIC TABLE DIM_CUSTOMER SET TAG 
    GOVERNANCE.TAGS.DATA_CLASSIFICATION = 'CONFIDENTIAL',
    GOVERNANCE.TAGS.DATA_DOMAIN = 'CUSTOMER',
    GOVERNANCE.TAGS.DATA_QUALITY_TIER = 'SILVER';

-- ═══════════════════════════════════════════════════════════════════════════
-- DIMENSION: Product
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.DIMENSIONS.DIM_PRODUCT
    TARGET_LAG = '24 hours'
    WAREHOUSE = TRANSFORM_WH
    COMMENT = 'Product dimension with categorization and pricing attributes.'
AS
SELECT
    -- Keys
    p.PRODUCT_ID AS PRODUCT_KEY,
    p.PRODUCT_ID,
    p.PRODUCT_CODE,
    
    -- Pseudonymized
    SHA2(p.PRODUCT_ID, 256) AS PRODUCT_ID_HASH,
    
    -- Product Details
    p.PRODUCT_NAME,
    p.PRODUCT_DESCRIPTION,
    
    -- Classification
    p.PRODUCT_CATEGORY,
    p.PRODUCT_SUBCATEGORY,
    p.PRODUCT_LINE,
    p.BRAND,
    
    -- Pricing
    p.LIST_PRICE,
    p.COST_PRICE,
    p.CURRENCY_CODE,
    
    -- Derived: Margin
    p.LIST_PRICE - COALESCE(p.COST_PRICE, 0) AS MARGIN_AMOUNT,
    CASE 
        WHEN p.LIST_PRICE > 0 THEN ROUND(100.0 * (p.LIST_PRICE - COALESCE(p.COST_PRICE, 0)) / p.LIST_PRICE, 2)
        ELSE 0 
    END AS MARGIN_PERCENT,
    
    -- Derived: Price Tier
    CASE 
        WHEN p.LIST_PRICE >= 1000 THEN 'PREMIUM'
        WHEN p.LIST_PRICE >= 100 THEN 'STANDARD'
        ELSE 'ECONOMY'
    END AS PRICE_TIER,
    
    -- Status
    p.PRODUCT_STATUS,
    p.IS_ACTIVE,
    p.LAUNCH_DATE,
    p.DISCONTINUE_DATE,
    
    -- Derived: Product Age (days)
    DATEDIFF('day', p.LAUNCH_DATE, CURRENT_DATE()) AS PRODUCT_AGE_DAYS,
    
    -- Derived: Is New (launched in last 90 days)
    CASE WHEN DATEDIFF('day', p.LAUNCH_DATE, CURRENT_DATE()) <= 90 THEN TRUE ELSE FALSE END AS IS_NEW_PRODUCT,
    
    -- Inventory
    p.REORDER_POINT,
    p.SAFETY_STOCK,
    p.LEAD_TIME_DAYS,
    
    -- Attributes
    p.WEIGHT,
    p.WEIGHT_UNIT,
    p.SIZE_DIMENSIONS,
    p.COLOR,
    
    -- Metadata
    p._LOADED_AT AS _SOURCE_LOADED_AT,
    p._IS_CURRENT
    
FROM RAW_DEV.CRM.PRODUCT_RAW p
WHERE p._IS_CURRENT = TRUE;

-- Apply tags
ALTER DYNAMIC TABLE DIM_PRODUCT SET TAG 
    GOVERNANCE.TAGS.DATA_CLASSIFICATION = 'INTERNAL',
    GOVERNANCE.TAGS.DATA_DOMAIN = 'PRODUCT',
    GOVERNANCE.TAGS.DATA_QUALITY_TIER = 'SILVER';

-- ═══════════════════════════════════════════════════════════════════════════
-- DIMENSION: Employee
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.DIMENSIONS.DIM_EMPLOYEE
    TARGET_LAG = '1 hour'
    WAREHOUSE = TRANSFORM_WH
    COMMENT = 'Employee dimension with HR attributes. Contains sensitive PII.'
AS
SELECT
    -- Keys
    e.EMPLOYEE_ID AS EMPLOYEE_KEY,
    e.EMPLOYEE_ID,
    e.EMPLOYEE_NUMBER,
    
    -- Pseudonymized
    SHA2(e.EMPLOYEE_ID, 256) AS EMPLOYEE_ID_HASH,
    SHA2(CONCAT(COALESCE(e.FIRST_NAME,''), ' ', COALESCE(e.LAST_NAME,'')), 256) AS NAME_HASH,
    SHA2(COALESCE(e.EMAIL, e.EMPLOYEE_ID), 256) AS EMAIL_HASH,
    
    -- PII (will be masked)
    e.FIRST_NAME,
    e.MIDDLE_NAME,
    e.LAST_NAME,
    e.PREFERRED_NAME,
    e.EMAIL,
    e.PHONE_WORK,
    e.PHONE_MOBILE,
    e.SSN,
    e.DATE_OF_BIRTH,
    
    -- Derived: Display Name
    COALESCE(e.PREFERRED_NAME, e.FIRST_NAME) || ' ' || e.LAST_NAME AS DISPLAY_NAME,
    
    -- Derived: Age
    DATEDIFF('year', e.DATE_OF_BIRTH, CURRENT_DATE()) AS AGE,
    
    -- Derived: Age Band
    CASE 
        WHEN DATEDIFF('year', e.DATE_OF_BIRTH, CURRENT_DATE()) < 25 THEN 'Under 25'
        WHEN DATEDIFF('year', e.DATE_OF_BIRTH, CURRENT_DATE()) < 35 THEN '25-34'
        WHEN DATEDIFF('year', e.DATE_OF_BIRTH, CURRENT_DATE()) < 45 THEN '35-44'
        WHEN DATEDIFF('year', e.DATE_OF_BIRTH, CURRENT_DATE()) < 55 THEN '45-54'
        WHEN DATEDIFF('year', e.DATE_OF_BIRTH, CURRENT_DATE()) < 65 THEN '55-64'
        ELSE '65+'
    END AS AGE_BAND,
    
    -- Demographics
    e.GENDER,
    e.NATIONALITY,
    
    -- Address
    e.HOME_ADDRESS_LINE1,
    e.HOME_CITY,
    e.HOME_STATE,
    e.HOME_POSTAL_CODE,
    e.HOME_COUNTRY,
    
    -- Employment
    e.HIRE_DATE,
    e.TERMINATION_DATE,
    e.EMPLOYMENT_STATUS,
    e.EMPLOYMENT_TYPE,
    
    -- Derived: Tenure
    ROUND(DATEDIFF('day', e.HIRE_DATE, COALESCE(e.TERMINATION_DATE, CURRENT_DATE())) / 365.25, 1) AS TENURE_YEARS,
    
    -- Derived: Tenure Bucket
    CASE 
        WHEN DATEDIFF('year', e.HIRE_DATE, CURRENT_DATE()) >= 10 THEN '10+ Years'
        WHEN DATEDIFF('year', e.HIRE_DATE, CURRENT_DATE()) >= 5 THEN '5-10 Years'
        WHEN DATEDIFF('year', e.HIRE_DATE, CURRENT_DATE()) >= 2 THEN '2-5 Years'
        WHEN DATEDIFF('year', e.HIRE_DATE, CURRENT_DATE()) >= 1 THEN '1-2 Years'
        ELSE '<1 Year'
    END AS TENURE_BUCKET,
    
    -- Derived: Is Active
    CASE WHEN e.EMPLOYMENT_STATUS = 'Active' AND e.TERMINATION_DATE IS NULL THEN TRUE ELSE FALSE END AS IS_ACTIVE,
    
    -- Position
    e.JOB_TITLE,
    e.JOB_LEVEL,
    e.DEPARTMENT_ID,
    e.DEPARTMENT_NAME,
    e.DIVISION,
    e.COST_CENTER,
    
    -- Manager
    e.MANAGER_ID,
    e.MANAGER_NAME,
    
    -- Location
    e.WORK_LOCATION,
    e.WORK_CITY,
    e.WORK_STATE,
    e.WORK_COUNTRY,
    e.REMOTE_WORKER,
    
    -- Compensation (sensitive)
    e.BASE_SALARY,
    e.SALARY_CURRENCY,
    e.PAY_FREQUENCY,
    e.BONUS_TARGET_PERCENT,
    
    -- Derived: Salary Band
    CASE 
        WHEN e.BASE_SALARY >= 200000 THEN 'Executive'
        WHEN e.BASE_SALARY >= 150000 THEN 'Senior'
        WHEN e.BASE_SALARY >= 100000 THEN 'Mid-Senior'
        WHEN e.BASE_SALARY >= 75000 THEN 'Mid'
        WHEN e.BASE_SALARY >= 50000 THEN 'Junior'
        ELSE 'Entry'
    END AS SALARY_BAND,
    
    -- Metadata
    e._LOADED_AT AS _SOURCE_LOADED_AT,
    e._IS_CURRENT
    
FROM RAW_DEV.HR.EMPLOYEE_RAW e
WHERE e._IS_CURRENT = TRUE;

-- Apply tags
ALTER DYNAMIC TABLE DIM_EMPLOYEE SET TAG 
    GOVERNANCE.TAGS.DATA_CLASSIFICATION = 'RESTRICTED',
    GOVERNANCE.TAGS.DATA_DOMAIN = 'EMPLOYEE',
    GOVERNANCE.TAGS.DATA_QUALITY_TIER = 'SILVER';

-- ═══════════════════════════════════════════════════════════════════════════
-- FACT: Orders
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA CURATED_DEV.FACTS;

CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.FACTS.FACT_ORDERS
    TARGET_LAG = '1 hour'
    WAREHOUSE = TRANSFORM_WH
    COMMENT = 'Order fact table with dimensional keys and calculated metrics.'
AS
SELECT
    -- Keys
    o.ORDER_ID AS ORDER_KEY,
    o.ORDER_ID,
    o.ORDER_NUMBER,
    o.CUSTOMER_ID AS CUSTOMER_KEY,
    o.SALES_REP_ID AS SALES_REP_KEY,
    o.ORDER_DATE AS DATE_KEY,
    
    -- Order Attributes
    o.ORDER_DATE,
    o.ORDER_STATUS,
    o.ORDER_TYPE,
    o.ORDER_PRIORITY,
    
    -- Financial
    o.SUBTOTAL,
    o.DISCOUNT_AMOUNT,
    o.TAX_AMOUNT,
    o.SHIPPING_AMOUNT,
    o.ORDER_TOTAL,
    o.CURRENCY_CODE,
    
    -- Derived: Net Revenue
    o.ORDER_TOTAL - COALESCE(o.TAX_AMOUNT, 0) - COALESCE(o.SHIPPING_AMOUNT, 0) AS NET_REVENUE,
    
    -- Derived: Discount Percent
    CASE WHEN o.SUBTOTAL > 0 THEN ROUND(100.0 * o.DISCOUNT_AMOUNT / o.SUBTOTAL, 2) ELSE 0 END AS DISCOUNT_PERCENT,
    
    -- Shipping
    o.SHIP_DATE,
    o.DELIVERY_DATE,
    o.SHIPPING_METHOD,
    
    -- Derived: Ship Days
    DATEDIFF('day', o.ORDER_DATE, o.SHIP_DATE) AS DAYS_TO_SHIP,
    DATEDIFF('day', o.SHIP_DATE, o.DELIVERY_DATE) AS DAYS_IN_TRANSIT,
    DATEDIFF('day', o.ORDER_DATE, o.DELIVERY_DATE) AS TOTAL_FULFILLMENT_DAYS,
    
    -- Channel
    o.SALES_CHANNEL,
    o.SOURCE_CAMPAIGN,
    
    -- Region
    o.REGION,
    
    -- Line item count (would be joined in production)
    1 AS ORDER_LINE_COUNT,
    
    -- Derived: Is Completed
    CASE WHEN o.ORDER_STATUS IN ('Delivered', 'Completed', 'Closed') THEN TRUE ELSE FALSE END AS IS_COMPLETED,
    
    -- Derived: Is Cancelled
    CASE WHEN o.ORDER_STATUS IN ('Cancelled', 'Returned') THEN TRUE ELSE FALSE END AS IS_CANCELLED,
    
    -- Metadata
    o._LOADED_AT AS _SOURCE_LOADED_AT,
    o._IS_CURRENT
    
FROM RAW_DEV.CRM.ORDER_RAW o
WHERE o._IS_CURRENT = TRUE;

-- Apply tags
ALTER DYNAMIC TABLE FACT_ORDERS SET TAG 
    GOVERNANCE.TAGS.DATA_CLASSIFICATION = 'CONFIDENTIAL',
    GOVERNANCE.TAGS.DATA_DOMAIN = 'ORDER',
    GOVERNANCE.TAGS.DATA_QUALITY_TIER = 'SILVER';

-- ═══════════════════════════════════════════════════════════════════════════
-- AGGREGATE: Daily Sales Summary
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA CURATED_DEV.AGGREGATES;

CREATE OR REPLACE DYNAMIC TABLE CURATED_DEV.AGGREGATES.AGG_DAILY_SALES
    TARGET_LAG = '1 hour'
    WAREHOUSE = TRANSFORM_WH
    COMMENT = 'Daily sales aggregates by region and channel. No PII.'
AS
SELECT
    -- Keys
    o.ORDER_DATE AS DATE_KEY,
    o.REGION,
    o.SALES_CHANNEL,
    
    -- Measures
    COUNT(DISTINCT o.ORDER_ID) AS ORDER_COUNT,
    COUNT(DISTINCT o.CUSTOMER_ID) AS CUSTOMER_COUNT,
    
    -- Revenue
    SUM(o.ORDER_TOTAL) AS TOTAL_REVENUE,
    SUM(o.SUBTOTAL) AS SUBTOTAL,
    SUM(o.DISCOUNT_AMOUNT) AS TOTAL_DISCOUNTS,
    SUM(o.TAX_AMOUNT) AS TOTAL_TAX,
    SUM(o.SHIPPING_AMOUNT) AS TOTAL_SHIPPING,
    
    -- Derived
    AVG(o.ORDER_TOTAL) AS AVG_ORDER_VALUE,
    SUM(o.ORDER_TOTAL) / NULLIF(COUNT(DISTINCT o.CUSTOMER_ID), 0) AS REVENUE_PER_CUSTOMER,
    
    -- Status breakdown
    COUNT(CASE WHEN o.ORDER_STATUS IN ('Delivered', 'Completed', 'Closed') THEN 1 END) AS COMPLETED_ORDERS,
    COUNT(CASE WHEN o.ORDER_STATUS IN ('Cancelled', 'Returned') THEN 1 END) AS CANCELLED_ORDERS,
    
    -- Fulfillment
    AVG(DATEDIFF('day', o.ORDER_DATE, o.SHIP_DATE)) AS AVG_DAYS_TO_SHIP
    
FROM RAW_DEV.CRM.ORDER_RAW o
WHERE o._IS_CURRENT = TRUE
GROUP BY o.ORDER_DATE, o.REGION, o.SALES_CHANNEL;

-- Apply tags (no PII in aggregates)
ALTER DYNAMIC TABLE AGG_DAILY_SALES SET TAG 
    GOVERNANCE.TAGS.DATA_CLASSIFICATION = 'INTERNAL',
    GOVERNANCE.TAGS.DATA_DOMAIN = 'ORDER',
    GOVERNANCE.TAGS.DATA_QUALITY_TIER = 'GOLD',
    GOVERNANCE.TAGS.AI_ALLOWED = 'TRUE';

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS FOR CURATED LAYER
-- ═══════════════════════════════════════════════════════════════════════════

-- DATA_ENGINEER: Full read access
GRANT USAGE ON SCHEMA CURATED_DEV.DIMENSIONS TO ROLE DATA_ENGINEER;
GRANT USAGE ON SCHEMA CURATED_DEV.FACTS TO ROLE DATA_ENGINEER;
GRANT USAGE ON SCHEMA CURATED_DEV.AGGREGATES TO ROLE DATA_ENGINEER;

GRANT SELECT ON ALL TABLES IN SCHEMA CURATED_DEV.DIMENSIONS TO ROLE DATA_ENGINEER;
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA CURATED_DEV.DIMENSIONS TO ROLE DATA_ENGINEER;
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA CURATED_DEV.FACTS TO ROLE DATA_ENGINEER;
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA CURATED_DEV.AGGREGATES TO ROLE DATA_ENGINEER;

-- DATA_STEWARD: Read access for governance
GRANT USAGE ON SCHEMA CURATED_DEV.DIMENSIONS TO ROLE DATA_STEWARD;
GRANT USAGE ON SCHEMA CURATED_DEV.FACTS TO ROLE DATA_STEWARD;
GRANT USAGE ON SCHEMA CURATED_DEV.AGGREGATES TO ROLE DATA_STEWARD;

GRANT SELECT ON ALL TABLES IN SCHEMA CURATED_DEV.DIMENSIONS TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA CURATED_DEV.DIMENSIONS TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA CURATED_DEV.FACTS TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA CURATED_DEV.AGGREGATES TO ROLE DATA_STEWARD;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT '✓ Curated Layer Dynamic Tables Created' AS STATUS;

SHOW DYNAMIC TABLES IN DATABASE CURATED_DEV;
SHOW TABLES IN SCHEMA CURATED_DEV.DIMENSIONS;
