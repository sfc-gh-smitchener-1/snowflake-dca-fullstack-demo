-- ============================================================================
-- SEMANTIC LAYER - Native Snowflake Semantic Views for Cortex Analyst
-- ============================================================================
-- 
-- This script creates native Snowflake Semantic Views that provide:
--   1. Logical table definitions with relationships
--   2. Pre-defined dimensions and metrics for Cortex Analyst
--   3. Business-friendly names and descriptions
--   4. Natural language query capabilities via Cortex
--
-- Semantic Views are the Gold layer - optimized for consumption by:
--   - Cortex Analyst (natural language to SQL)
--   - Business analysts (self-service)
--   - Dashboards and BI tools
--   - AI/ML workloads (with pseudonymized data)
--
-- Reference: https://docs.snowflake.com/en/sql-reference/sql/create-semantic-view
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE SEM_DEV;
USE WAREHOUSE ANALYTICS_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- SEMANTIC VIEW: Sales Analytics
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Primary semantic view for sales and revenue analysis.
-- Combines orders, customers, products, and dates.
-- Used by: Sales leadership, Finance, Revenue ops
--
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA SEM_DEV.SEM_SALES;

CREATE OR REPLACE SEMANTIC VIEW SALES_ANALYTICS
  TABLES (
    -- Define the tables and their primary keys
    orders AS CURATED_DEV.FACTS.FACT_ORDERS PRIMARY KEY (ORDER_KEY),
    customers AS CURATED_DEV.DIMENSIONS.DIM_CUSTOMER PRIMARY KEY (CUSTOMER_KEY),
    products AS CURATED_DEV.DIMENSIONS.DIM_PRODUCT PRIMARY KEY (PRODUCT_KEY),
    dates AS CURATED_DEV.DIMENSIONS.DIM_DATE PRIMARY KEY (DATE_KEY)
  )
  RELATIONSHIPS (
    -- Define how tables join together
    orders(CUSTOMER_KEY) REFERENCES customers(CUSTOMER_KEY),
    orders(DATE_KEY) REFERENCES dates(DATE_KEY)
    -- Note: Product key would be on order_line in full model
  )
  DIMENSIONS (
    -- ═══════════════════════════════════════════════════════════════════════
    -- TIME DIMENSIONS
    -- ═══════════════════════════════════════════════════════════════════════
    dates.YEAR AS year COMMENT 'Calendar year (e.g., 2024)',
    dates.QUARTER AS quarter COMMENT 'Calendar quarter (1-4)',
    dates.MONTH AS month COMMENT 'Calendar month (1-12)',
    dates.MONTH_NAME AS month_name COMMENT 'Month name (e.g., January)',
    dates.WEEK_OF_YEAR AS week COMMENT 'Week of year (1-52)',
    dates.DAY_NAME AS day_name COMMENT 'Day of week name (e.g., Monday)',
    dates.FISCAL_YEAR AS fiscal_year COMMENT 'Fiscal year (July start)',
    dates.FISCAL_QUARTER AS fiscal_quarter COMMENT 'Fiscal quarter (1-4)',
    dates.IS_WEEKEND AS is_weekend COMMENT 'True if Saturday or Sunday',
    dates.IS_HOLIDAY AS is_holiday COMMENT 'True if common US holiday',
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- CUSTOMER DIMENSIONS
    -- ═══════════════════════════════════════════════════════════════════════
    customers.CUSTOMER_ID AS customer_id COMMENT 'Unique customer identifier',
    customers.DISPLAY_NAME AS customer_name COMMENT 'Privacy-safe customer display name',
    customers.COMPANY_NAME AS company_name COMMENT 'Company/organization name',
    customers.CUSTOMER_TYPE AS customer_type COMMENT 'Customer type (e.g., Business, Consumer)',
    customers.CUSTOMER_SEGMENT AS customer_segment COMMENT 'Marketing segment',
    customers.CUSTOMER_TIER AS customer_tier COMMENT 'Value tier (Enterprise, Mid-Market, SMB, Starter)',
    customers.CUSTOMER_HEALTH AS customer_health COMMENT 'Health status (Active, Dormant, At Risk, Churned)',
    customers.INDUSTRY AS industry COMMENT 'Industry vertical',
    customers.REGION AS customer_region COMMENT 'Customer geographic region',
    customers.COUNTRY AS customer_country COMMENT 'Customer country',
    customers.TENURE_BUCKET AS customer_tenure COMMENT 'Customer tenure bucket',
    customers.IS_ACTIVE AS is_active_customer COMMENT 'True if customer is currently active',
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- ORDER DIMENSIONS
    -- ═══════════════════════════════════════════════════════════════════════
    orders.ORDER_ID AS order_id COMMENT 'Unique order identifier',
    orders.ORDER_NUMBER AS order_number COMMENT 'Human-readable order number',
    orders.ORDER_STATUS AS order_status COMMENT 'Current order status',
    orders.ORDER_TYPE AS order_type COMMENT 'Order type (New, Renewal, Upsell)',
    orders.ORDER_PRIORITY AS order_priority COMMENT 'Order priority level',
    orders.SALES_CHANNEL AS sales_channel COMMENT 'Sales channel (Online, Field, Partner)',
    orders.REGION AS order_region COMMENT 'Order geographic region',
    orders.IS_COMPLETED AS is_completed COMMENT 'True if order is completed',
    orders.IS_CANCELLED AS is_cancelled COMMENT 'True if order was cancelled'
  )
  METRICS (
    -- ═══════════════════════════════════════════════════════════════════════
    -- REVENUE METRICS
    -- ═══════════════════════════════════════════════════════════════════════
    orders.total_revenue AS SUM(orders.ORDER_TOTAL) 
      COMMENT 'Total revenue from all orders',
    orders.net_revenue AS SUM(orders.NET_REVENUE) 
      COMMENT 'Net revenue (excluding tax and shipping)',
    orders.avg_order_value AS AVG(orders.ORDER_TOTAL) 
      COMMENT 'Average order value (AOV)',
    orders.total_discounts AS SUM(orders.DISCOUNT_AMOUNT) 
      COMMENT 'Total discount amount given',
    orders.total_tax AS SUM(orders.TAX_AMOUNT) 
      COMMENT 'Total tax collected',
    orders.total_shipping AS SUM(orders.SHIPPING_AMOUNT) 
      COMMENT 'Total shipping revenue',
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- ORDER METRICS
    -- ═══════════════════════════════════════════════════════════════════════
    orders.order_count AS COUNT(orders.ORDER_KEY) 
      COMMENT 'Total number of orders',
    orders.completed_orders AS SUM(CASE WHEN orders.IS_COMPLETED THEN 1 ELSE 0 END) 
      COMMENT 'Number of completed orders',
    orders.cancelled_orders AS SUM(CASE WHEN orders.IS_CANCELLED THEN 1 ELSE 0 END) 
      COMMENT 'Number of cancelled orders',
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- CUSTOMER METRICS
    -- ═══════════════════════════════════════════════════════════════════════
    customers.customer_count AS COUNT(DISTINCT customers.CUSTOMER_KEY) 
      COMMENT 'Unique customer count',
    customers.active_customers AS COUNT(DISTINCT CASE WHEN customers.IS_ACTIVE THEN customers.CUSTOMER_KEY END) 
      COMMENT 'Active customer count',
    customers.avg_lifetime_value AS AVG(customers.LIFETIME_VALUE) 
      COMMENT 'Average customer lifetime value',
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- FULFILLMENT METRICS
    -- ═══════════════════════════════════════════════════════════════════════
    orders.avg_days_to_ship AS AVG(orders.DAYS_TO_SHIP) 
      COMMENT 'Average days from order to shipment',
    orders.avg_fulfillment_days AS AVG(orders.TOTAL_FULFILLMENT_DAYS) 
      COMMENT 'Average total fulfillment time in days',
    
    -- ═══════════════════════════════════════════════════════════════════════
    -- DERIVED METRICS
    -- ═══════════════════════════════════════════════════════════════════════
    revenue_per_customer AS orders.total_revenue / NULLIF(customers.customer_count, 0) 
      COMMENT 'Revenue per unique customer',
    completion_rate AS orders.completed_orders / NULLIF(orders.order_count, 0) * 100 
      COMMENT 'Order completion rate percentage',
    cancellation_rate AS orders.cancelled_orders / NULLIF(orders.order_count, 0) * 100 
      COMMENT 'Order cancellation rate percentage',
    discount_rate AS orders.total_discounts / NULLIF(orders.total_revenue, 0) * 100 
      COMMENT 'Discount rate as percentage of revenue'
  )
  COMMENT = 'Sales analytics semantic view for revenue, order, and customer analysis. Use for sales reporting, forecasting, and performance tracking.';

-- Grant access to relevant roles
GRANT SELECT, REFERENCES ON SEMANTIC VIEW SALES_ANALYTICS TO ROLE ANALYST;
GRANT SELECT, REFERENCES ON SEMANTIC VIEW SALES_ANALYTICS TO ROLE MANAGER;
GRANT SELECT, REFERENCES ON SEMANTIC VIEW SALES_ANALYTICS TO ROLE AI_AGENT;
GRANT SELECT, REFERENCES ON SEMANTIC VIEW SALES_ANALYTICS TO ROLE DATA_STEWARD;

-- ═══════════════════════════════════════════════════════════════════════════
-- SEMANTIC VIEW: Customer Analytics
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Customer-centric view for Customer 360 analysis.
-- Focus on customer attributes, health, and value.
-- Used by: Customer Success, Marketing, Sales
--
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA SEM_DEV.SEM_CUSTOMER;

CREATE OR REPLACE SEMANTIC VIEW CUSTOMER_ANALYTICS
  TABLES (
    customers AS CURATED_DEV.DIMENSIONS.DIM_CUSTOMER PRIMARY KEY (CUSTOMER_KEY),
    orders AS CURATED_DEV.FACTS.FACT_ORDERS PRIMARY KEY (ORDER_KEY)
  )
  RELATIONSHIPS (
    orders(CUSTOMER_KEY) REFERENCES customers(CUSTOMER_KEY)
  )
  DIMENSIONS (
    -- Customer Identity (privacy-safe)
    customers.CUSTOMER_ID AS customer_id,
    customers.DISPLAY_NAME AS customer_name,
    customers.COMPANY_NAME AS company_name,
    
    -- Classification
    customers.CUSTOMER_TYPE AS customer_type,
    customers.CUSTOMER_SEGMENT AS customer_segment,
    customers.CUSTOMER_TIER AS customer_tier,
    customers.INDUSTRY AS industry,
    
    -- Status
    customers.CUSTOMER_STATUS AS customer_status,
    customers.CUSTOMER_HEALTH AS customer_health,
    customers.IS_ACTIVE AS is_active,
    
    -- Geography
    customers.REGION AS region,
    customers.COUNTRY AS country,
    customers.CITY AS city,
    
    -- Tenure
    customers.TENURE_BUCKET AS tenure_bucket,
    customers.CREATED_DATE AS created_date,
    
    -- Consent
    customers.MARKETING_CONSENT AS marketing_consent,
    customers.DATA_PROCESSING_CONSENT AS data_consent,
    customers.GDPR_DELETE_REQUESTED AS gdpr_delete_requested
  )
  METRICS (
    -- Customer Counts
    customers.customer_count AS COUNT(customers.CUSTOMER_KEY),
    customers.active_customers AS COUNT(CASE WHEN customers.IS_ACTIVE THEN customers.CUSTOMER_KEY END),
    customers.churned_customers AS COUNT(CASE WHEN customers.CUSTOMER_HEALTH = 'CHURNED' THEN customers.CUSTOMER_KEY END),
    customers.at_risk_customers AS COUNT(CASE WHEN customers.CUSTOMER_HEALTH = 'AT_RISK' THEN customers.CUSTOMER_KEY END),
    
    -- Value Metrics
    customers.total_lifetime_value AS SUM(customers.LIFETIME_VALUE),
    customers.avg_lifetime_value AS AVG(customers.LIFETIME_VALUE),
    customers.max_lifetime_value AS MAX(customers.LIFETIME_VALUE),
    
    -- Tenure Metrics
    customers.avg_tenure_days AS AVG(customers.TENURE_DAYS),
    customers.avg_days_since_purchase AS AVG(customers.DAYS_SINCE_LAST_PURCHASE),
    
    -- Order Metrics (from joined orders)
    orders.total_orders AS COUNT(orders.ORDER_KEY),
    orders.total_revenue AS SUM(orders.ORDER_TOTAL),
    orders.avg_order_value AS AVG(orders.ORDER_TOTAL),
    
    -- Derived
    orders_per_customer AS orders.total_orders / NULLIF(customers.customer_count, 0),
    churn_rate AS customers.churned_customers / NULLIF(customers.customer_count, 0) * 100,
    at_risk_rate AS customers.at_risk_customers / NULLIF(customers.customer_count, 0) * 100
  )
  COMMENT = 'Customer analytics semantic view for customer 360 analysis, health monitoring, and lifecycle management.';

-- Grant access
GRANT SELECT, REFERENCES ON SEMANTIC VIEW CUSTOMER_ANALYTICS TO ROLE ANALYST;
GRANT SELECT, REFERENCES ON SEMANTIC VIEW CUSTOMER_ANALYTICS TO ROLE MANAGER;
GRANT SELECT, REFERENCES ON SEMANTIC VIEW CUSTOMER_ANALYTICS TO ROLE AI_AGENT;

-- ═══════════════════════════════════════════════════════════════════════════
-- SEMANTIC VIEW: Workforce Analytics
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- HR analytics for workforce planning and management.
-- Contains sensitive employee data - restricted access.
-- Used by: HR, Executives
--
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA SEM_DEV.SEM_HR;

CREATE OR REPLACE SEMANTIC VIEW WORKFORCE_ANALYTICS
  TABLES (
    employees AS CURATED_DEV.DIMENSIONS.DIM_EMPLOYEE PRIMARY KEY (EMPLOYEE_KEY)
  )
  DIMENSIONS (
    -- Identity (privacy-safe)
    employees.EMPLOYEE_ID AS employee_id,
    employees.DISPLAY_NAME AS employee_name,
    
    -- Position
    employees.JOB_TITLE AS job_title,
    employees.JOB_LEVEL AS job_level,
    employees.DEPARTMENT_NAME AS department,
    employees.DIVISION AS division,
    
    -- Status
    employees.EMPLOYMENT_STATUS AS employment_status,
    employees.EMPLOYMENT_TYPE AS employment_type,
    employees.IS_ACTIVE AS is_active,
    
    -- Location
    employees.WORK_CITY AS work_city,
    employees.WORK_STATE AS work_state,
    employees.WORK_COUNTRY AS work_country,
    employees.REMOTE_WORKER AS is_remote,
    
    -- Demographics (aggregates only)
    employees.GENDER AS gender,
    employees.AGE_BAND AS age_band,
    employees.TENURE_BUCKET AS tenure_bucket,
    
    -- Compensation
    employees.SALARY_BAND AS salary_band,
    
    -- Dates
    employees.HIRE_DATE AS hire_date
  )
  METRICS (
    -- Headcount
    employees.headcount AS COUNT(employees.EMPLOYEE_KEY),
    employees.active_headcount AS COUNT(CASE WHEN employees.IS_ACTIVE THEN employees.EMPLOYEE_KEY END),
    employees.terminated_count AS COUNT(CASE WHEN NOT employees.IS_ACTIVE THEN employees.EMPLOYEE_KEY END),
    
    -- Tenure
    employees.avg_tenure_years AS AVG(employees.TENURE_YEARS),
    employees.new_hires AS COUNT(CASE WHEN employees.TENURE_YEARS < 1 THEN employees.EMPLOYEE_KEY END),
    
    -- Age
    employees.avg_age AS AVG(employees.AGE),
    
    -- Remote
    employees.remote_count AS COUNT(CASE WHEN employees.REMOTE_WORKER THEN employees.EMPLOYEE_KEY END),
    
    -- Derived
    turnover_rate AS employees.terminated_count / NULLIF(employees.headcount, 0) * 100,
    remote_percentage AS employees.remote_count / NULLIF(employees.active_headcount, 0) * 100
  )
  COMMENT = 'Workforce analytics semantic view for HR reporting, headcount planning, and organizational analysis. Contains sensitive employee data.';

-- Grant access (restricted)
GRANT SELECT, REFERENCES ON SEMANTIC VIEW WORKFORCE_ANALYTICS TO ROLE MANAGER;
GRANT SELECT, REFERENCES ON SEMANTIC VIEW WORKFORCE_ANALYTICS TO ROLE DATA_STEWARD;
-- Note: ANALYST does not have access due to sensitive HR data

-- ═══════════════════════════════════════════════════════════════════════════
-- SEMANTIC VIEW: Operations Analytics
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Operational metrics for fulfillment and efficiency.
-- No PII - safe for broad access.
-- Used by: Operations, Supply Chain, Executives
--
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA SEM_DEV.SEM_OPERATIONS;

CREATE OR REPLACE SEMANTIC VIEW OPERATIONS_METRICS
  TABLES (
    daily_sales AS CURATED_DEV.AGGREGATES.AGG_DAILY_SALES PRIMARY KEY (DATE_KEY, REGION, SALES_CHANNEL),
    dates AS CURATED_DEV.DIMENSIONS.DIM_DATE PRIMARY KEY (DATE_KEY)
  )
  RELATIONSHIPS (
    daily_sales(DATE_KEY) REFERENCES dates(DATE_KEY)
  )
  DIMENSIONS (
    -- Time
    dates.YEAR AS year,
    dates.QUARTER AS quarter,
    dates.MONTH AS month,
    dates.MONTH_NAME AS month_name,
    dates.WEEK_OF_YEAR AS week,
    dates.DAY_NAME AS day_name,
    dates.FISCAL_YEAR AS fiscal_year,
    dates.IS_WEEKEND AS is_weekend,
    
    -- Geography
    daily_sales.REGION AS region,
    
    -- Channel
    daily_sales.SALES_CHANNEL AS sales_channel
  )
  METRICS (
    -- Volume
    daily_sales.total_orders AS SUM(daily_sales.ORDER_COUNT),
    daily_sales.total_customers AS SUM(daily_sales.CUSTOMER_COUNT),
    
    -- Revenue
    daily_sales.total_revenue AS SUM(daily_sales.TOTAL_REVENUE),
    daily_sales.avg_daily_revenue AS AVG(daily_sales.TOTAL_REVENUE),
    daily_sales.total_discounts AS SUM(daily_sales.TOTAL_DISCOUNTS),
    
    -- Fulfillment
    daily_sales.completed_orders AS SUM(daily_sales.COMPLETED_ORDERS),
    daily_sales.cancelled_orders AS SUM(daily_sales.CANCELLED_ORDERS),
    daily_sales.avg_days_to_ship AS AVG(daily_sales.AVG_DAYS_TO_SHIP),
    
    -- Derived
    daily_sales.avg_order_value AS SUM(daily_sales.TOTAL_REVENUE) / NULLIF(SUM(daily_sales.ORDER_COUNT), 0),
    completion_rate AS SUM(daily_sales.COMPLETED_ORDERS) / NULLIF(SUM(daily_sales.ORDER_COUNT), 0) * 100
  )
  COMMENT = 'Operations metrics semantic view for fulfillment tracking, channel performance, and daily operational analysis. No PII included.';

-- Grant access (broad - no PII)
GRANT SELECT, REFERENCES ON SEMANTIC VIEW OPERATIONS_METRICS TO ROLE ANALYST;
GRANT SELECT, REFERENCES ON SEMANTIC VIEW OPERATIONS_METRICS TO ROLE MANAGER;
GRANT SELECT, REFERENCES ON SEMANTIC VIEW OPERATIONS_METRICS TO ROLE VIEWER;
GRANT SELECT, REFERENCES ON SEMANTIC VIEW OPERATIONS_METRICS TO ROLE AI_AGENT;
GRANT SELECT, REFERENCES ON SEMANTIC VIEW OPERATIONS_METRICS TO ROLE EXTERNAL_PARTNER;

-- ═══════════════════════════════════════════════════════════════════════════
-- SEMANTIC VIEW: Governance Analytics
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Data governance and quality metrics.
-- Used by: Data Stewards, Auditors
--
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA SEM_DEV.SEM_GOVERNANCE;

-- Note: This would query governance tables when they exist
-- Placeholder for governance semantic view

-- ═══════════════════════════════════════════════════════════════════════════
-- REGULAR VIEWS FOR MARKETPLACE
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Secure views for data products that will be shared via Marketplace.
-- These views aggregate data to remove PII while maintaining usefulness.
--
-- ═══════════════════════════════════════════════════════════════════════════

USE SCHEMA SEM_DEV.MARKETPLACE;

-- Daily Sales Summary (no PII)
CREATE OR REPLACE SECURE VIEW VW_SALES_SUMMARY AS
SELECT
    d.YEAR,
    d.QUARTER,
    d.MONTH_NAME AS MONTH,
    a.REGION,
    a.SALES_CHANNEL,
    SUM(a.ORDER_COUNT) AS TOTAL_ORDERS,
    SUM(a.CUSTOMER_COUNT) AS UNIQUE_CUSTOMERS,
    SUM(a.TOTAL_REVENUE) AS TOTAL_REVENUE,
    ROUND(SUM(a.TOTAL_REVENUE) / NULLIF(SUM(a.ORDER_COUNT), 0), 2) AS AVG_ORDER_VALUE,
    SUM(a.COMPLETED_ORDERS) AS COMPLETED_ORDERS,
    SUM(a.CANCELLED_ORDERS) AS CANCELLED_ORDERS
FROM CURATED_DEV.AGGREGATES.AGG_DAILY_SALES a
JOIN CURATED_DEV.DIMENSIONS.DIM_DATE d ON a.DATE_KEY = d.DATE_KEY
GROUP BY d.YEAR, d.QUARTER, d.MONTH_NAME, a.REGION, a.SALES_CHANNEL
ORDER BY d.YEAR DESC, d.QUARTER DESC, a.REGION;

-- Customer Summary (aggregated, no individual PII)
CREATE OR REPLACE SECURE VIEW VW_CUSTOMER_SUMMARY AS
SELECT
    c.REGION,
    c.CUSTOMER_TIER,
    c.INDUSTRY,
    c.TENURE_BUCKET,
    COUNT(*) AS CUSTOMER_COUNT,
    SUM(CASE WHEN c.IS_ACTIVE THEN 1 ELSE 0 END) AS ACTIVE_CUSTOMERS,
    ROUND(AVG(c.LIFETIME_VALUE), 2) AS AVG_LIFETIME_VALUE,
    ROUND(AVG(c.TENURE_DAYS), 0) AS AVG_TENURE_DAYS
FROM CURATED_DEV.DIMENSIONS.DIM_CUSTOMER c
WHERE c._IS_CURRENT = TRUE
GROUP BY c.REGION, c.CUSTOMER_TIER, c.INDUSTRY, c.TENURE_BUCKET;

-- Grant marketplace views
GRANT SELECT ON VIEW VW_SALES_SUMMARY TO ROLE VIEWER;
GRANT SELECT ON VIEW VW_SALES_SUMMARY TO ROLE EXTERNAL_PARTNER;
GRANT SELECT ON VIEW VW_CUSTOMER_SUMMARY TO ROLE VIEWER;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT '✓ Semantic Layer Created' AS STATUS;

SHOW SEMANTIC VIEWS IN DATABASE SEM_DEV;
SHOW VIEWS IN SCHEMA SEM_DEV.MARKETPLACE;
