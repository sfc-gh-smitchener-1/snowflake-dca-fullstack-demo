-- ============================================================
-- DCA Demo | Module 3: Governance Layer
-- ============================================================
-- Run as: SYSADMIN (after Module 2)
-- Purpose: Tags, masking policies, data contracts,
--          and the DATA_PRODUCT_CATALOG registry.
--
-- NOTE: Data Metric Functions (DMFs) require Enterprise edition
--       or higher. The DMF block is wrapped in a comment block
--       for Standard edition accounts — see Section 5.
-- ============================================================

USE ROLE SYSADMIN;
USE DATABASE DCA_DEMO;
USE WAREHOUSE COMPUTE_WH;

-- ── 1. Custom tags ────────────────────────────────────────────

CREATE OR REPLACE TAG GOVERNANCE.pii_category
  ALLOWED_VALUES 'EMAIL', 'PHONE', 'NAME', 'ADDRESS', 'SSN', 'DOB'
  COMMENT = 'PII classification category. Applied to columns containing personal data. Triggers automated masking policy attachment.';

CREATE OR REPLACE TAG GOVERNANCE.data_contract_version
  COMMENT = 'Semantic versioning of the data contract governing this object. Format: MAJOR.MINOR (e.g. 1.0, 1.2, 2.0). Major version change = breaking schema change.';

CREATE OR REPLACE TAG GOVERNANCE.data_contract_owner
  COMMENT = 'Snowflake role accountable for the data contract on this object. This role is the institutional owner — they sign off on schema changes and SLA breaches.';

CREATE OR REPLACE TAG GOVERNANCE.data_purpose
  ALLOWED_VALUES 'REPORTING', 'ANALYTICS', 'OPERATIONAL', 'REGULATORY', 'INTERNAL'
  COMMENT = 'Declared purpose of this data product. Consumers must not use data beyond the declared purpose without a contract amendment.';

CREATE OR REPLACE TAG GOVERNANCE.sla_freshness_hours
  COMMENT = 'Maximum acceptable age of data in hours before the SLA is considered breached. Monitored by the freshness_hours DMF.';

-- ── 2. Masking policies ───────────────────────────────────────

CREATE OR REPLACE MASKING POLICY GOVERNANCE.email_mask
AS (val STRING) RETURNS STRING ->
  CASE
    WHEN CURRENT_ROLE() IN (
        'FINANCE_DATA_OWNER', 'SALES_DATA_OWNER',
        'DCA_PLATFORM_ADMIN', 'DCA_GOVERNANCE_ADMIN',
        'SYSADMIN', 'ACCOUNTADMIN'
    ) THEN val
    ELSE REGEXP_REPLACE(val, '^[^@]+', '****')  -- consumers see ****@domain.com
  END
COMMENT = 'Email masking: full address visible to data owners and above; masked to consumers.';

CREATE OR REPLACE MASKING POLICY GOVERNANCE.phone_mask
AS (val STRING) RETURNS STRING ->
  CASE
    WHEN CURRENT_ROLE() IN (
        'FINANCE_DATA_OWNER', 'SALES_DATA_OWNER',
        'DCA_PLATFORM_ADMIN', 'DCA_GOVERNANCE_ADMIN',
        'SYSADMIN', 'ACCOUNTADMIN'
    ) THEN val
    ELSE '***-***-' || RIGHT(REGEXP_REPLACE(val, '[^0-9]', ''), 4)
  END
COMMENT = 'Phone masking: full number visible to data owners and above; last 4 digits to consumers.';

GRANT APPLY MASKING POLICY ON ACCOUNT TO ROLE dca_governance_admin;
GRANT APPLY TAG ON ACCOUNT TO ROLE dca_governance_admin;
GRANT CREATE MASKING POLICY ON SCHEMA DCA_DEMO.GOVERNANCE TO ROLE dca_governance_admin;

-- ── 3. Apply masking policies to CURATED PII columns ─────────

ALTER TABLE CURATED.CUSTOMERS
  MODIFY COLUMN email SET MASKING POLICY GOVERNANCE.email_mask;

ALTER TABLE CURATED.CUSTOMERS
  MODIFY COLUMN phone SET MASKING POLICY GOVERNANCE.phone_mask;

-- ── 4. Apply PII classification tags ─────────────────────────
-- CURATED layer — primary PII surface with masking enforced

ALTER TABLE CURATED.CUSTOMERS MODIFY COLUMN email
  SET TAG GOVERNANCE.pii_category = 'EMAIL';
ALTER TABLE CURATED.CUSTOMERS MODIFY COLUMN phone
  SET TAG GOVERNANCE.pii_category = 'PHONE';
ALTER TABLE CURATED.CUSTOMERS MODIFY COLUMN full_name
  SET TAG GOVERNANCE.pii_category = 'NAME';

-- RAW layer — PII tagged to flag sensitivity even without masking
ALTER TABLE RAW.RAW_CUSTOMERS MODIFY COLUMN email
  SET TAG GOVERNANCE.pii_category = 'EMAIL';
ALTER TABLE RAW.RAW_CUSTOMERS MODIFY COLUMN phone
  SET TAG GOVERNANCE.pii_category = 'PHONE';
ALTER TABLE RAW.RAW_CUSTOMERS MODIFY COLUMN full_name
  SET TAG GOVERNANCE.pii_category = 'NAME';

-- ── 5. Data contract tags on Semantic layer ───────────────────

ALTER TABLE SEMANTIC_FINANCE.MONTHLY_REVENUE SET TAG
  GOVERNANCE.data_contract_version = '1.2',
  GOVERNANCE.data_contract_owner   = 'finance_data_owner',
  GOVERNANCE.data_purpose          = 'REPORTING',
  GOVERNANCE.sla_freshness_hours   = '24';

ALTER TABLE SEMANTIC_FINANCE.REVENUE_BY_PRODUCT SET TAG
  GOVERNANCE.data_contract_version = '1.1',
  GOVERNANCE.data_contract_owner   = 'finance_data_owner',
  GOVERNANCE.data_purpose          = 'ANALYTICS',
  GOVERNANCE.sla_freshness_hours   = '24';

ALTER TABLE SEMANTIC_FINANCE.CUSTOMER_LIFETIME_VALUE SET TAG
  GOVERNANCE.data_contract_version = '2.0',
  GOVERNANCE.data_contract_owner   = 'finance_data_owner',
  GOVERNANCE.data_purpose          = 'ANALYTICS',
  GOVERNANCE.sla_freshness_hours   = '168';

ALTER TABLE SEMANTIC_SALES.PIPELINE_SUMMARY SET TAG
  GOVERNANCE.data_contract_version = '1.0',
  GOVERNANCE.data_contract_owner   = 'sales_data_owner',
  GOVERNANCE.data_purpose          = 'OPERATIONAL',
  GOVERNANCE.sla_freshness_hours   = '4';

ALTER TABLE SEMANTIC_SALES.REP_PERFORMANCE SET TAG
  GOVERNANCE.data_contract_version = '1.3',
  GOVERNANCE.data_contract_owner   = 'sales_data_owner',
  GOVERNANCE.data_purpose          = 'REPORTING',
  GOVERNANCE.sla_freshness_hours   = '24';

ALTER TABLE SEMANTIC_SALES.WIN_RATE_BY_REGION SET TAG
  GOVERNANCE.data_contract_version = '1.0',
  GOVERNANCE.data_contract_owner   = 'sales_data_owner',
  GOVERNANCE.data_purpose          = 'ANALYTICS',
  GOVERNANCE.sla_freshness_hours   = '48';

-- ── 6. Data Metric Function  [Enterprise / BC edition only] ───
-- Comment out this block if running on Standard edition.

CREATE DATA METRIC FUNCTION IF NOT EXISTS GOVERNANCE.freshness_hours(
    arg_t TABLE(as_of_ts TIMESTAMP_NTZ)
)
RETURNS NUMBER
AS $$
    SELECT ROUND(DATEDIFF('minute', MAX(as_of_ts), CURRENT_TIMESTAMP()) / 60.0, 1)
    FROM arg_t
$$
COMMENT = 'Returns hours elapsed since the most recent as_of_ts value. Attach to Semantic tables to monitor freshness against SLA.';

-- Attach to Semantic tables that have an as_of_ts column
ALTER TABLE SEMANTIC_FINANCE.MONTHLY_REVENUE
  ADD DATA METRIC FUNCTION GOVERNANCE.freshness_hours ON (as_of_ts)
  DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES';

ALTER TABLE SEMANTIC_FINANCE.REVENUE_BY_PRODUCT
  ADD DATA METRIC FUNCTION GOVERNANCE.freshness_hours ON (as_of_ts)
  DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES';

ALTER TABLE SEMANTIC_SALES.PIPELINE_SUMMARY
  ADD DATA METRIC FUNCTION GOVERNANCE.freshness_hours ON (as_of_ts)
  DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES';

ALTER TABLE SEMANTIC_SALES.REP_PERFORMANCE
  ADD DATA METRIC FUNCTION GOVERNANCE.freshness_hours ON (as_of_ts)
  DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES';

-- ── 7. Data Product Catalog ───────────────────────────────────

CREATE OR REPLACE TABLE GOVERNANCE.DATA_PRODUCT_CATALOG (
    catalog_id             INTEGER AUTOINCREMENT PRIMARY KEY,
    schema_name            VARCHAR(50)    NOT NULL,
    table_name             VARCHAR(200)   NOT NULL,
    full_table_name        VARCHAR(400)   NOT NULL,
    display_name           VARCHAR(200),
    description            VARCHAR(2000),
    data_contract_version  VARCHAR(20),
    contract_owner_role    VARCHAR(100),
    data_purpose           VARCHAR(50),
    sla_freshness_hours    INTEGER,
    consumer_roles         VARIANT        COMMENT 'JSON array of roles permitted to consume this product',
    is_pii_in_scope        BOOLEAN        DEFAULT FALSE,
    contract_status        VARCHAR(20)    DEFAULT 'ACTIVE'
                           COMMENT 'ACTIVE / DRAFT / DEPRECATED',
    registered_at          TIMESTAMP_NTZ  DEFAULT CURRENT_TIMESTAMP(),
    last_reviewed_at       TIMESTAMP_NTZ  DEFAULT CURRENT_TIMESTAMP(),
    notes                  VARCHAR(2000)
)
COMMENT = 'Central registry of governed data products in DCA_DEMO. Maintained by dca_governance_admin. Queried by the Streamlit Contract Registry page.';

INSERT INTO GOVERNANCE.DATA_PRODUCT_CATALOG
    (schema_name, table_name, full_table_name, display_name, description,
     data_contract_version, contract_owner_role, data_purpose, sla_freshness_hours,
     consumer_roles, is_pii_in_scope, contract_status, notes)
SELECT col1, col2, col3, col4, col5, col6, col7, col8, col9,
       PARSE_JSON(col10), col11, col12, col13
FROM VALUES
    ('SEMANTIC_FINANCE', 'MONTHLY_REVENUE',
     'DCA_DEMO.SEMANTIC_FINANCE.MONTHLY_REVENUE',
     'Monthly Revenue',
     'Closed-won revenue by month, broken down by new business, renewal, expansion, and services. Exclusive of tax. Source of truth for Finance board reporting.',
     '1.2', 'finance_data_owner', 'REPORTING', 24,
     '["finance_data_consumer"]',
     FALSE, 'ACTIVE',
     'Refreshed nightly. Downstream: CFO dashboard, Board pack pipeline.'),

    ('SEMANTIC_FINANCE', 'REVENUE_BY_PRODUCT',
     'DCA_DEMO.SEMANTIC_FINANCE.REVENUE_BY_PRODUCT',
     'Revenue by Product',
     'Lifetime closed-won revenue and deal count by product name and category. Used for product mix analysis and pricing decisions.',
     '1.1', 'finance_data_owner', 'ANALYTICS', 24,
     '["finance_data_consumer"]',
     FALSE, 'ACTIVE',
     'Refreshed nightly. Downstream: Product analytics team.'),

    ('SEMANTIC_FINANCE', 'CUSTOMER_LIFETIME_VALUE',
     'DCA_DEMO.SEMANTIC_FINANCE.CUSTOMER_LIFETIME_VALUE',
     'Customer Lifetime Value',
     'Customer-level LTV with PLATINUM/GOLD/SILVER/STANDARD segmentation. Used for account prioritisation and renewal forecasting.',
     '2.0', 'finance_data_owner', 'ANALYTICS', 168,
     '["finance_data_consumer"]',
     FALSE, 'ACTIVE',
     'Weekly refresh acceptable. v2.0 introduced segmentation model change — breaking schema change from v1.x.'),

    ('SEMANTIC_SALES', 'PIPELINE_SUMMARY',
     'DCA_DEMO.SEMANTIC_SALES.PIPELINE_SUMMARY',
     'Pipeline Summary',
     'Current deal pipeline by stage with weighted values. Primary input to weekly sales forecast meetings.',
     '1.0', 'sales_data_owner', 'OPERATIONAL', 4,
     '["sales_data_consumer", "finance_data_consumer"]',
     FALSE, 'ACTIVE',
     '4-hour SLA — must be current before Monday morning pipeline reviews.'),

    ('SEMANTIC_SALES', 'REP_PERFORMANCE',
     'DCA_DEMO.SEMANTIC_SALES.REP_PERFORMANCE',
     'Rep Performance',
     'Quota, closed-won revenue, and attainment percentage by sales rep and region. Used for comp calculations and manager reviews.',
     '1.3', 'sales_data_owner', 'REPORTING', 24,
     '["sales_data_consumer"]',
     FALSE, 'ACTIVE',
     'v1.3 added avg_deal_size_usd. Downstream: Comp system, QBR dashboards.'),

    ('SEMANTIC_SALES', 'WIN_RATE_BY_REGION',
     'DCA_DEMO.SEMANTIC_SALES.WIN_RATE_BY_REGION',
     'Win Rate by Region',
     'Win rate, deal count, and average sales cycle by region. Used for regional go-to-market planning and headcount modelling.',
     '1.0', 'sales_data_owner', 'ANALYTICS', 48,
     '["sales_data_consumer", "finance_data_consumer"]',
     FALSE, 'ACTIVE',
     NULL);

-- Grant read to all domain roles
GRANT SELECT ON TABLE GOVERNANCE.DATA_PRODUCT_CATALOG TO ROLE finance_data_owner;
GRANT SELECT ON TABLE GOVERNANCE.DATA_PRODUCT_CATALOG TO ROLE sales_data_owner;
GRANT SELECT ON TABLE GOVERNANCE.DATA_PRODUCT_CATALOG TO ROLE finance_data_consumer;
GRANT SELECT ON TABLE GOVERNANCE.DATA_PRODUCT_CATALOG TO ROLE sales_data_consumer;

SELECT 'Module 3 complete: governance layer created successfully' AS status;

-- Verify
SELECT schema_name, display_name, data_contract_version, contract_status, sla_freshness_hours
FROM GOVERNANCE.DATA_PRODUCT_CATALOG
ORDER BY schema_name, table_name;
