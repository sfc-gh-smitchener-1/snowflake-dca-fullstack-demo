-- ============================================================================
-- DATA MARKETPLACE - Secure Data Products for Internal Sharing
-- ============================================================================
-- 
-- This script creates:
--   1. Secure shares for internal data products
--   2. Marketplace listings for self-service discovery
--   3. Access-controlled views for data products
--   4. Usage monitoring for data products
--
-- Data Products follow these principles:
--   - No raw PII exposed (aggregated or pseudonymized)
--   - Clear documentation and use cases
--   - Access controls aligned with governance
--   - Usage tracking for chargeback/monitoring
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE WAREHOUSE ANALYTICS_WH;
USE DATABASE SEM_DEV;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 1: SECURE VIEWS FOR DATA PRODUCTS
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Create SECURE views that encapsulate data products.
-- Secure views prevent consumers from seeing the underlying query logic.
--
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA SEM_DEV.MARKETPLACE;

-- ─────────────────────────────────────────────────────────────────────────────
-- DATA PRODUCT: Sales Performance Metrics
-- ─────────────────────────────────────────────────────────────────────────────
-- Aggregated sales metrics for executive reporting.
-- No individual transaction or customer PII.

CREATE OR REPLACE SECURE VIEW DP_SALES_PERFORMANCE AS
SELECT
    -- Time dimensions
    d.YEAR,
    d.QUARTER,
    d.MONTH_NAME AS MONTH,
    d.FISCAL_YEAR,
    d.FISCAL_QUARTER,
    
    -- Geographic dimensions
    a.REGION,
    
    -- Channel dimensions
    a.SALES_CHANNEL,
    
    -- Metrics
    SUM(a.ORDER_COUNT) AS TOTAL_ORDERS,
    SUM(a.TOTAL_REVENUE) AS TOTAL_REVENUE,
    ROUND(SUM(a.TOTAL_REVENUE) / NULLIF(SUM(a.ORDER_COUNT), 0), 2) AS AVG_ORDER_VALUE,
    SUM(a.CUSTOMER_COUNT) AS UNIQUE_CUSTOMERS,
    
    -- Performance metrics
    SUM(a.COMPLETED_ORDERS) AS COMPLETED_ORDERS,
    SUM(a.CANCELLED_ORDERS) AS CANCELLED_ORDERS,
    ROUND(100.0 * SUM(a.COMPLETED_ORDERS) / NULLIF(SUM(a.ORDER_COUNT), 0), 2) AS COMPLETION_RATE,
    
    -- Discount metrics
    SUM(a.TOTAL_DISCOUNTS) AS TOTAL_DISCOUNTS,
    ROUND(100.0 * SUM(a.TOTAL_DISCOUNTS) / NULLIF(SUM(a.TOTAL_REVENUE), 0), 2) AS DISCOUNT_RATE,
    
    -- Fulfillment metrics
    ROUND(AVG(a.AVG_DAYS_TO_SHIP), 1) AS AVG_DAYS_TO_SHIP,
    
    -- Metadata
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIMESTAMP,
    'v1.0' AS PRODUCT_VERSION

FROM CURATED_DEV.AGGREGATES.AGG_DAILY_SALES a
JOIN CURATED_DEV.DIMENSIONS.DIM_DATE d ON a.DATE_KEY = d.DATE_KEY
WHERE d.YEAR >= YEAR(CURRENT_DATE()) - 3  -- Last 3 years
GROUP BY 
    d.YEAR, d.QUARTER, d.MONTH_NAME, d.FISCAL_YEAR, d.FISCAL_QUARTER,
    a.REGION, a.SALES_CHANNEL
ORDER BY d.YEAR DESC, d.QUARTER DESC, a.REGION;

COMMENT ON VIEW DP_SALES_PERFORMANCE IS 
    'Sales Performance Data Product: Aggregated monthly/quarterly sales metrics by region and channel. No PII. Updated hourly.';

-- ─────────────────────────────────────────────────────────────────────────────
-- DATA PRODUCT: Customer Segments Summary
-- ─────────────────────────────────────────────────────────────────────────────
-- Customer distribution and value by segment.
-- No individual customer PII - only aggregates.

CREATE OR REPLACE SECURE VIEW DP_CUSTOMER_SEGMENTS AS
SELECT
    -- Segment dimensions
    c.CUSTOMER_TIER,
    c.CUSTOMER_SEGMENT,
    c.INDUSTRY,
    c.REGION,
    c.TENURE_BUCKET,
    
    -- Health distribution
    c.CUSTOMER_HEALTH,
    
    -- Metrics
    COUNT(*) AS CUSTOMER_COUNT,
    SUM(CASE WHEN c.IS_ACTIVE THEN 1 ELSE 0 END) AS ACTIVE_CUSTOMERS,
    SUM(CASE WHEN NOT c.IS_ACTIVE THEN 1 ELSE 0 END) AS INACTIVE_CUSTOMERS,
    
    -- Value metrics
    ROUND(AVG(c.LIFETIME_VALUE), 2) AS AVG_LIFETIME_VALUE,
    ROUND(SUM(c.LIFETIME_VALUE), 2) AS TOTAL_LIFETIME_VALUE,
    ROUND(MEDIAN(c.LIFETIME_VALUE), 2) AS MEDIAN_LIFETIME_VALUE,
    
    -- Tenure metrics
    ROUND(AVG(c.TENURE_DAYS), 0) AS AVG_TENURE_DAYS,
    
    -- Engagement metrics
    ROUND(AVG(c.DAYS_SINCE_LAST_PURCHASE), 0) AS AVG_DAYS_SINCE_PURCHASE,
    
    -- Metadata
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIMESTAMP

FROM CURATED_DEV.DIMENSIONS.DIM_CUSTOMER c
WHERE c._IS_CURRENT = TRUE
GROUP BY 
    c.CUSTOMER_TIER, c.CUSTOMER_SEGMENT, c.INDUSTRY, 
    c.REGION, c.TENURE_BUCKET, c.CUSTOMER_HEALTH
ORDER BY CUSTOMER_COUNT DESC;

COMMENT ON VIEW DP_CUSTOMER_SEGMENTS IS 
    'Customer Segments Data Product: Aggregated customer metrics by segment, tier, and region. No individual PII.';

-- ─────────────────────────────────────────────────────────────────────────────
-- DATA PRODUCT: Regional Business Summary
-- ─────────────────────────────────────────────────────────────────────────────
-- Regional rollup for geographic analysis.
-- Combines customers and sales data.

CREATE OR REPLACE SECURE VIEW DP_REGIONAL_SUMMARY AS
WITH customer_metrics AS (
    SELECT
        REGION,
        COUNT(*) AS CUSTOMER_COUNT,
        SUM(CASE WHEN IS_ACTIVE THEN 1 ELSE 0 END) AS ACTIVE_CUSTOMERS,
        SUM(LIFETIME_VALUE) AS TOTAL_LTV,
        AVG(TENURE_DAYS) AS AVG_TENURE
    FROM CURATED_DEV.DIMENSIONS.DIM_CUSTOMER
    WHERE _IS_CURRENT = TRUE
    GROUP BY REGION
),
sales_metrics AS (
    SELECT
        REGION,
        SUM(ORDER_COUNT) AS TOTAL_ORDERS,
        SUM(TOTAL_REVENUE) AS TOTAL_REVENUE,
        SUM(CUSTOMER_COUNT) AS ORDERING_CUSTOMERS
    FROM CURATED_DEV.AGGREGATES.AGG_DAILY_SALES
    WHERE DATE_KEY >= DATEADD('year', -1, CURRENT_DATE())  -- Last 12 months
    GROUP BY REGION
)
SELECT
    COALESCE(c.REGION, s.REGION) AS REGION,
    
    -- Customer metrics
    COALESCE(c.CUSTOMER_COUNT, 0) AS TOTAL_CUSTOMERS,
    COALESCE(c.ACTIVE_CUSTOMERS, 0) AS ACTIVE_CUSTOMERS,
    ROUND(COALESCE(c.TOTAL_LTV, 0), 2) AS TOTAL_LIFETIME_VALUE,
    ROUND(COALESCE(c.AVG_TENURE, 0), 0) AS AVG_TENURE_DAYS,
    
    -- Sales metrics (last 12 months)
    COALESCE(s.TOTAL_ORDERS, 0) AS ORDERS_L12M,
    ROUND(COALESCE(s.TOTAL_REVENUE, 0), 2) AS REVENUE_L12M,
    
    -- Derived metrics
    ROUND(COALESCE(s.TOTAL_REVENUE, 0) / NULLIF(c.ACTIVE_CUSTOMERS, 0), 2) AS REVENUE_PER_ACTIVE_CUSTOMER,
    ROUND(100.0 * COALESCE(c.ACTIVE_CUSTOMERS, 0) / NULLIF(c.CUSTOMER_COUNT, 0), 2) AS ACTIVE_RATE,
    
    -- Metadata
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIMESTAMP

FROM customer_metrics c
FULL OUTER JOIN sales_metrics s ON c.REGION = s.REGION
ORDER BY REVENUE_L12M DESC NULLS LAST;

COMMENT ON VIEW DP_REGIONAL_SUMMARY IS 
    'Regional Business Summary: Combined customer and sales metrics by region. Rolling 12-month sales data.';

-- ─────────────────────────────────────────────────────────────────────────────
-- DATA PRODUCT: Product Performance (placeholder)
-- ─────────────────────────────────────────────────────────────────────────────
-- Product-level metrics for merchandising.

CREATE OR REPLACE SECURE VIEW DP_PRODUCT_PERFORMANCE AS
SELECT
    p.PRODUCT_CATEGORY,
    p.PRODUCT_SUBCATEGORY,
    p.PRODUCT_LINE,
    p.BRAND,
    p.PRICE_TIER,
    
    -- Product counts
    COUNT(*) AS PRODUCT_COUNT,
    SUM(CASE WHEN p.IS_ACTIVE THEN 1 ELSE 0 END) AS ACTIVE_PRODUCTS,
    SUM(CASE WHEN p.IS_NEW_PRODUCT THEN 1 ELSE 0 END) AS NEW_PRODUCTS,
    
    -- Pricing
    ROUND(AVG(p.LIST_PRICE), 2) AS AVG_LIST_PRICE,
    ROUND(AVG(p.MARGIN_PERCENT), 2) AS AVG_MARGIN_PERCENT,
    
    -- Metadata
    CURRENT_TIMESTAMP() AS SNAPSHOT_TIMESTAMP

FROM CURATED_DEV.DIMENSIONS.DIM_PRODUCT p
WHERE p._IS_CURRENT = TRUE
GROUP BY 
    p.PRODUCT_CATEGORY, p.PRODUCT_SUBCATEGORY, 
    p.PRODUCT_LINE, p.BRAND, p.PRICE_TIER
ORDER BY PRODUCT_COUNT DESC;

COMMENT ON VIEW DP_PRODUCT_PERFORMANCE IS 
    'Product Performance Data Product: Product metrics by category, line, and brand.';

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 2: CREATE SHARES FOR DATA PRODUCTS
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Shares allow secure data exchange within and across Snowflake accounts.
-- For internal marketplace, we create shares that can be consumed by 
-- other databases/roles within the same account.
--
-- ═══════════════════════════════════════════════════════════════════════════

-- Create share for Sales Analytics products
CREATE OR REPLACE SHARE SALES_ANALYTICS_SHARE
    COMMENT = 'Sales Analytics Data Products - Aggregated sales, customer segments, and regional metrics.';

-- Grant necessary privileges to share
GRANT USAGE ON DATABASE SEM_DEV TO SHARE SALES_ANALYTICS_SHARE;
GRANT USAGE ON SCHEMA SEM_DEV.MARKETPLACE TO SHARE SALES_ANALYTICS_SHARE;

-- Add data products to share
GRANT SELECT ON VIEW SEM_DEV.MARKETPLACE.DP_SALES_PERFORMANCE TO SHARE SALES_ANALYTICS_SHARE;
GRANT SELECT ON VIEW SEM_DEV.MARKETPLACE.DP_CUSTOMER_SEGMENTS TO SHARE SALES_ANALYTICS_SHARE;
GRANT SELECT ON VIEW SEM_DEV.MARKETPLACE.DP_REGIONAL_SUMMARY TO SHARE SALES_ANALYTICS_SHARE;
GRANT SELECT ON VIEW SEM_DEV.MARKETPLACE.DP_PRODUCT_PERFORMANCE TO SHARE SALES_ANALYTICS_SHARE;

-- Create share for Operations products
CREATE OR REPLACE SHARE OPERATIONS_ANALYTICS_SHARE
    COMMENT = 'Operations Analytics Data Products - Fulfillment and operational metrics.';

GRANT USAGE ON DATABASE SEM_DEV TO SHARE OPERATIONS_ANALYTICS_SHARE;
GRANT USAGE ON SCHEMA SEM_DEV.MARKETPLACE TO SHARE OPERATIONS_ANALYTICS_SHARE;
GRANT SELECT ON VIEW SEM_DEV.MARKETPLACE.VW_SALES_SUMMARY TO SHARE OPERATIONS_ANALYTICS_SHARE;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 3: GRANT ACCESS TO INTERNAL ROLES
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- For internal marketplace, grant access to appropriate roles.
-- These views can be queried directly or through shares.
--
-- ═══════════════════════════════════════════════════════════════════════════

-- Sales Performance - broad access (no PII)
GRANT SELECT ON VIEW DP_SALES_PERFORMANCE TO ROLE ANALYST;
GRANT SELECT ON VIEW DP_SALES_PERFORMANCE TO ROLE MANAGER;
GRANT SELECT ON VIEW DP_SALES_PERFORMANCE TO ROLE VIEWER;
GRANT SELECT ON VIEW DP_SALES_PERFORMANCE TO ROLE AI_AGENT;
GRANT SELECT ON VIEW DP_SALES_PERFORMANCE TO ROLE EXTERNAL_PARTNER;

-- Customer Segments - internal only
GRANT SELECT ON VIEW DP_CUSTOMER_SEGMENTS TO ROLE ANALYST;
GRANT SELECT ON VIEW DP_CUSTOMER_SEGMENTS TO ROLE MANAGER;
GRANT SELECT ON VIEW DP_CUSTOMER_SEGMENTS TO ROLE AI_AGENT;
-- Note: EXTERNAL_PARTNER excluded from customer data

-- Regional Summary - broad access
GRANT SELECT ON VIEW DP_REGIONAL_SUMMARY TO ROLE ANALYST;
GRANT SELECT ON VIEW DP_REGIONAL_SUMMARY TO ROLE MANAGER;
GRANT SELECT ON VIEW DP_REGIONAL_SUMMARY TO ROLE VIEWER;
GRANT SELECT ON VIEW DP_REGIONAL_SUMMARY TO ROLE AI_AGENT;

-- Product Performance - broad access
GRANT SELECT ON VIEW DP_PRODUCT_PERFORMANCE TO ROLE ANALYST;
GRANT SELECT ON VIEW DP_PRODUCT_PERFORMANCE TO ROLE MANAGER;
GRANT SELECT ON VIEW DP_PRODUCT_PERFORMANCE TO ROLE AI_AGENT;
GRANT SELECT ON VIEW DP_PRODUCT_PERFORMANCE TO ROLE EXTERNAL_PARTNER;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 4: DATA PRODUCT CATALOG
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Create a catalog table to document available data products.
-- This enables self-service discovery.
--
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA GOVERNANCE.OBSERVABILITY;

CREATE TABLE IF NOT EXISTS DATA_PRODUCT_CATALOG (
    PRODUCT_ID              VARCHAR(50) PRIMARY KEY,
    PRODUCT_NAME            VARCHAR(255) NOT NULL,
    PRODUCT_DESCRIPTION     VARCHAR(4000),
    PRODUCT_VERSION         VARCHAR(20),
    
    -- Location
    DATABASE_NAME           VARCHAR(255),
    SCHEMA_NAME             VARCHAR(255),
    OBJECT_NAME             VARCHAR(255),
    OBJECT_TYPE             VARCHAR(50),  -- VIEW, TABLE, SHARE
    
    -- Classification
    DOMAIN                  VARCHAR(100),
    DATA_CLASSIFICATION     VARCHAR(50),
    CONTAINS_PII            BOOLEAN DEFAULT FALSE,
    
    -- Access
    SHARE_NAME              VARCHAR(255),
    ALLOWED_ROLES           ARRAY,
    
    -- Metadata
    OWNER_TEAM              VARCHAR(100),
    OWNER_EMAIL             VARCHAR(255),
    SLA_REFRESH_HOURS       NUMBER,
    
    -- Documentation
    SAMPLE_QUERIES          VARCHAR(4000),
    USE_CASES               ARRAY,
    DATA_DICTIONARY_URL     VARCHAR(1000),
    
    -- Status
    STATUS                  VARCHAR(20) DEFAULT 'ACTIVE',
    CREATED_AT              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Catalog of available data products for self-service discovery.';

-- Insert data product entries
INSERT INTO DATA_PRODUCT_CATALOG 
(PRODUCT_ID, PRODUCT_NAME, PRODUCT_DESCRIPTION, PRODUCT_VERSION, 
 DATABASE_NAME, SCHEMA_NAME, OBJECT_NAME, OBJECT_TYPE,
 DOMAIN, DATA_CLASSIFICATION, CONTAINS_PII, 
 SHARE_NAME, ALLOWED_ROLES,
 OWNER_TEAM, SLA_REFRESH_HOURS, USE_CASES) 
VALUES
(
    'DP-SALES-001',
    'Sales Performance Metrics',
    'Aggregated monthly/quarterly sales metrics by region and channel. Includes revenue, orders, completion rates, and fulfillment metrics. Updated hourly from transactional data.',
    'v1.0',
    'SEM_DEV', 'MARKETPLACE', 'DP_SALES_PERFORMANCE', 'SECURE_VIEW',
    'SALES', 'INTERNAL', FALSE,
    'SALES_ANALYTICS_SHARE', ARRAY_CONSTRUCT('ANALYST', 'MANAGER', 'VIEWER', 'AI_AGENT', 'EXTERNAL_PARTNER'),
    'Revenue Operations', 1,
    ARRAY_CONSTRUCT('Executive dashboards', 'Quarterly business reviews', 'Sales forecasting', 'Channel performance analysis')
),
(
    'DP-CUST-001',
    'Customer Segments Summary',
    'Customer distribution and value metrics by segment, tier, industry, and region. No individual customer data exposed - only aggregate statistics.',
    'v1.0',
    'SEM_DEV', 'MARKETPLACE', 'DP_CUSTOMER_SEGMENTS', 'SECURE_VIEW',
    'CUSTOMER', 'CONFIDENTIAL', FALSE,
    'SALES_ANALYTICS_SHARE', ARRAY_CONSTRUCT('ANALYST', 'MANAGER', 'AI_AGENT'),
    'Customer Success', 1,
    ARRAY_CONSTRUCT('Customer segmentation', 'Churn analysis', 'LTV optimization', 'Marketing targeting')
),
(
    'DP-GEO-001',
    'Regional Business Summary',
    'Combined customer and sales metrics by geographic region. Rolling 12-month sales data with customer base statistics.',
    'v1.0',
    'SEM_DEV', 'MARKETPLACE', 'DP_REGIONAL_SUMMARY', 'SECURE_VIEW',
    'OPERATIONS', 'INTERNAL', FALSE,
    'SALES_ANALYTICS_SHARE', ARRAY_CONSTRUCT('ANALYST', 'MANAGER', 'VIEWER', 'AI_AGENT'),
    'Business Intelligence', 24,
    ARRAY_CONSTRUCT('Geographic expansion planning', 'Territory management', 'Regional performance comparison')
),
(
    'DP-PROD-001',
    'Product Performance Metrics',
    'Product catalog metrics by category, line, and brand. Includes pricing, margins, and product lifecycle status.',
    'v1.0',
    'SEM_DEV', 'MARKETPLACE', 'DP_PRODUCT_PERFORMANCE', 'SECURE_VIEW',
    'PRODUCT', 'INTERNAL', FALSE,
    'SALES_ANALYTICS_SHARE', ARRAY_CONSTRUCT('ANALYST', 'MANAGER', 'AI_AGENT', 'EXTERNAL_PARTNER'),
    'Product Management', 24,
    ARRAY_CONSTRUCT('Assortment planning', 'Pricing optimization', 'Category analysis')
);

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 5: USAGE MONITORING
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Create views to monitor data product usage for governance and chargeback.
--
-- ═══════════════════════════════════════════════════════════════════════════

-- View: Data Product Access History
CREATE OR REPLACE VIEW VW_DATA_PRODUCT_USAGE AS
SELECT
    ah.QUERY_START_TIME,
    ah.USER_NAME,
    ah.ROLE_NAME,
    -- Extract data product from query
    CASE 
        WHEN ah.DIRECT_OBJECTS_ACCESSED LIKE '%DP_SALES_PERFORMANCE%' THEN 'DP-SALES-001'
        WHEN ah.DIRECT_OBJECTS_ACCESSED LIKE '%DP_CUSTOMER_SEGMENTS%' THEN 'DP-CUST-001'
        WHEN ah.DIRECT_OBJECTS_ACCESSED LIKE '%DP_REGIONAL_SUMMARY%' THEN 'DP-GEO-001'
        WHEN ah.DIRECT_OBJECTS_ACCESSED LIKE '%DP_PRODUCT_PERFORMANCE%' THEN 'DP-PROD-001'
        ELSE 'OTHER'
    END AS PRODUCT_ID,
    ah.WAREHOUSE_NAME,
    ah.EXECUTION_STATUS,
    ah.TOTAL_ELAPSED_TIME / 1000 AS EXECUTION_SECONDS,
    ah.BYTES_SCANNED / 1024 / 1024 AS MB_SCANNED,
    ah.ROWS_PRODUCED
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY ah
WHERE ah.QUERY_START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
  AND (
    ah.DIRECT_OBJECTS_ACCESSED LIKE '%SEM_DEV.MARKETPLACE%'
    OR ah.BASE_OBJECTS_ACCESSED LIKE '%SEM_DEV.MARKETPLACE%'
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT '✓ Data Marketplace Created' AS STATUS;

-- Show data products
SHOW VIEWS IN SCHEMA SEM_DEV.MARKETPLACE;

-- Show shares
SHOW SHARES;

-- Show catalog
SELECT PRODUCT_ID, PRODUCT_NAME, DOMAIN, DATA_CLASSIFICATION, STATUS 
FROM GOVERNANCE.OBSERVABILITY.DATA_PRODUCT_CATALOG;
