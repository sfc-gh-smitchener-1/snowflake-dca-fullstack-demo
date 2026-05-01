-- ============================================================
-- DCA Demo | Module 2: Schemas and Synthetic Data
-- ============================================================
-- Run as: SYSADMIN (after Module 1)
-- Purpose: Creates DCA_DEMO database with four data layers:
--
--   RAW              — uninterpreted brute facts (raw ingestion)
--   CURATED          — institutional facts in formation (cleaned, conformed)
--   SEMANTIC_FINANCE — full institutional facts (Finance data products)
--   SEMANTIC_SALES   — full institutional facts (Sales data products)
--   GOVERNANCE       — governance catalog and metadata
-- ============================================================

USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;

-- ── 1. Database and schemas ──────────────────────────────────

CREATE DATABASE IF NOT EXISTS DCA_DEMO
  COMMENT = 'Data Contracts Architecture demo database';

CREATE SCHEMA IF NOT EXISTS DCA_DEMO.RAW
  COMMENT = 'Raw ingestion layer. Data as received from source systems — uninterpreted brute facts. No guarantees on quality, completeness, or schema stability.';

CREATE SCHEMA IF NOT EXISTS DCA_DEMO.CURATED
  COMMENT = 'Curated layer. Cleaned, conformed, and deduplicated — institutional facts in formation. Surrogate keys applied. PII tagged and masked.';

CREATE SCHEMA IF NOT EXISTS DCA_DEMO.SEMANTIC_FINANCE
  COMMENT = 'Semantic Finance layer. Analytics-ready Finance data products governed by data contracts — full institutional facts with declared meaning, assigned ownership, and monitored quality.';

CREATE SCHEMA IF NOT EXISTS DCA_DEMO.SEMANTIC_SALES
  COMMENT = 'Semantic Sales layer. Analytics-ready Sales data products governed by data contracts.';

CREATE SCHEMA IF NOT EXISTS DCA_DEMO.GOVERNANCE
  COMMENT = 'Governance metadata schema. Stores data product catalog, contract registry, and quality monitoring logs.';

USE DATABASE DCA_DEMO;

-- ── 2. Database and schema grants ────────────────────────────

GRANT USAGE ON DATABASE DCA_DEMO TO ROLE dca_platform_admin;
GRANT USAGE ON DATABASE DCA_DEMO TO ROLE finance_data_owner;
GRANT USAGE ON DATABASE DCA_DEMO TO ROLE finance_data_consumer;
GRANT USAGE ON DATABASE DCA_DEMO TO ROLE sales_data_owner;
GRANT USAGE ON DATABASE DCA_DEMO TO ROLE sales_data_consumer;
GRANT USAGE ON DATABASE DCA_DEMO TO ROLE dca_raw_loader;

-- RAW: loader inserts, platform admin owns DDL
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA DCA_DEMO.RAW   TO ROLE dca_platform_admin;
GRANT USAGE ON SCHEMA DCA_DEMO.RAW                               TO ROLE dca_raw_loader;
GRANT INSERT ON ALL TABLES IN SCHEMA DCA_DEMO.RAW                TO ROLE dca_raw_loader;
GRANT INSERT ON FUTURE TABLES IN SCHEMA DCA_DEMO.RAW             TO ROLE dca_raw_loader;

-- CURATED: domain owners can read, platform admin owns DDL
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA DCA_DEMO.CURATED TO ROLE dca_platform_admin;
GRANT USAGE, SELECT ON ALL TABLES IN SCHEMA DCA_DEMO.CURATED       TO ROLE finance_data_owner;
GRANT USAGE, SELECT ON ALL TABLES IN SCHEMA DCA_DEMO.CURATED       TO ROLE sales_data_owner;
GRANT USAGE ON SCHEMA DCA_DEMO.CURATED                             TO ROLE finance_data_owner;
GRANT USAGE ON SCHEMA DCA_DEMO.CURATED                             TO ROLE sales_data_owner;

-- SEMANTIC_FINANCE: finance domain owns DDL, consumers read
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA DCA_DEMO.SEMANTIC_FINANCE TO ROLE finance_data_owner;
GRANT USAGE ON SCHEMA DCA_DEMO.SEMANTIC_FINANCE                             TO ROLE finance_data_consumer;
GRANT SELECT ON ALL TABLES IN SCHEMA DCA_DEMO.SEMANTIC_FINANCE              TO ROLE finance_data_consumer;
GRANT SELECT ON FUTURE TABLES IN SCHEMA DCA_DEMO.SEMANTIC_FINANCE           TO ROLE finance_data_consumer;

-- SEMANTIC_SALES: sales domain owns DDL, consumers read
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA DCA_DEMO.SEMANTIC_SALES TO ROLE sales_data_owner;
GRANT USAGE ON SCHEMA DCA_DEMO.SEMANTIC_SALES                              TO ROLE sales_data_consumer;
GRANT SELECT ON ALL TABLES IN SCHEMA DCA_DEMO.SEMANTIC_SALES               TO ROLE sales_data_consumer;
GRANT SELECT ON FUTURE TABLES IN SCHEMA DCA_DEMO.SEMANTIC_SALES            TO ROLE sales_data_consumer;

-- GOVERNANCE: governance admin and platform admin own DDL, domain owners read
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA DCA_DEMO.GOVERNANCE TO ROLE dca_governance_admin;
GRANT USAGE ON SCHEMA DCA_DEMO.GOVERNANCE                             TO ROLE dca_platform_admin;
GRANT USAGE ON SCHEMA DCA_DEMO.GOVERNANCE                             TO ROLE finance_data_owner;
GRANT USAGE ON SCHEMA DCA_DEMO.GOVERNANCE                             TO ROLE sales_data_owner;
GRANT USAGE ON SCHEMA DCA_DEMO.GOVERNANCE                             TO ROLE finance_data_consumer;
GRANT USAGE ON SCHEMA DCA_DEMO.GOVERNANCE                             TO ROLE sales_data_consumer;

-- ── 3. RAW layer tables ───────────────────────────────────────

CREATE OR REPLACE TABLE RAW.RAW_TRANSACTIONS (
    transaction_id    VARCHAR(36)                 COMMENT 'UUID assigned at ingestion',
    source_txn_ref    VARCHAR(20)                 COMMENT 'Source system reference — format varies by system',
    event_timestamp   TIMESTAMP_NTZ               COMMENT 'Raw event timestamp from source — timezone not normalised',
    customer_name_raw VARCHAR(300)                COMMENT 'Customer name as received — may contain aliases or abbreviations',
    product_raw       VARCHAR(300)                COMMENT 'Product description from source — not mapped to product catalogue',
    amount_raw        NUMBER(14, 2)               COMMENT 'Transaction amount in source currency',
    currency          VARCHAR(3)                  COMMENT 'ISO 4217 currency code',
    stage             VARCHAR(30)                 COMMENT 'Deal stage from CRM',
    sales_rep         VARCHAR(200)                COMMENT 'Sales rep name — free text from CRM',
    region            VARCHAR(20)                 COMMENT 'Sales region — may be NULL if not captured by source',
    load_status       VARCHAR(20) DEFAULT 'ORIGINAL' COMMENT 'ORIGINAL or DUPLICATE — set by ingestion pipeline',
    ingested_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Raw CRM transaction feed. Do not use for reporting — use SEMANTIC_FINANCE.MONTHLY_REVENUE.';

CREATE OR REPLACE TABLE RAW.RAW_CUSTOMERS (
    customer_id_raw   VARCHAR(50)                 COMMENT 'Source system customer identifier',
    full_name         VARCHAR(200)                COMMENT 'Contact full name — PII',
    email             VARCHAR(200)                COMMENT 'Contact email — PII',
    phone             VARCHAR(30)                 COMMENT 'Contact phone — PII, format varies by region',
    company           VARCHAR(200)                COMMENT 'Company / account name',
    industry          VARCHAR(100)                COMMENT 'Industry vertical',
    created_at_raw    TIMESTAMP_NTZ               COMMENT 'Account creation timestamp from source',
    source_system     VARCHAR(50)                 COMMENT 'Origin system (CRM, BILLING, MARKETING)',
    load_status       VARCHAR(20) DEFAULT 'ORIGINAL',
    ingested_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Raw customer feed from CRM. Contains PII — access restricted to data owners.';

CREATE OR REPLACE TABLE RAW.RAW_PRODUCTS (
    product_id_raw    VARCHAR(50)                 COMMENT 'Source system product identifier',
    product_name      VARCHAR(200)                COMMENT 'Product name',
    category          VARCHAR(50)                 COMMENT 'LICENSE / SUPPORT / ADD_ON / SERVICES / TRAINING',
    list_price_usd    NUMBER(12, 2)               COMMENT 'List price in USD',
    sku               VARCHAR(50)                 COMMENT 'Stock keeping unit',
    is_active         BOOLEAN     DEFAULT TRUE,
    load_status       VARCHAR(20) DEFAULT 'ORIGINAL',
    ingested_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Raw product catalogue from billing system.';

-- ── 4. Seed RAW data ──────────────────────────────────────────

-- 4a. Products (20 rows)
INSERT INTO RAW.RAW_PRODUCTS (product_id_raw, product_name, category, list_price_usd, sku) VALUES
    ('PRD-001', 'Enterprise Platform License',            'LICENSE',  95000.00, 'EPL-ENT-001'),
    ('PRD-002', 'Professional Services - Implementation', 'SERVICES', 18000.00, 'PS-IMPL-001'),
    ('PRD-003', 'Annual Support & Success',               'SUPPORT',  12000.00, 'SUP-ANN-001'),
    ('PRD-004', 'Analytics Add-on Module',                'ADD_ON',    8500.00, 'ADD-ANA-001'),
    ('PRD-005', 'Training & Certification Package',       'TRAINING',  4500.00, 'TRN-CERT-001'),
    ('PRD-006', 'Data Connector Bundle',                  'ADD_ON',    6200.00, 'ADD-DCB-001'),
    ('PRD-007', 'Security & Compliance Add-on',           'ADD_ON',    7800.00, 'ADD-SEC-001'),
    ('PRD-008', 'API Access Tier - Premium',              'ADD_ON',    5000.00, 'ADD-API-001'),
    ('PRD-009', 'Enterprise Platform License - Scale',    'LICENSE',  145000.00,'EPL-SCL-001'),
    ('PRD-010', 'Managed Services - Standard',            'SERVICES', 24000.00, 'MS-STD-001'),
    ('PRD-011', 'Managed Services - Premium',             'SERVICES', 48000.00, 'MS-PRM-001'),
    ('PRD-012', 'Annual Support & Success - Enterprise',  'SUPPORT',  22000.00, 'SUP-ENT-001'),
    ('PRD-013', 'Data Governance Module',                 'ADD_ON',   11000.00, 'ADD-DGM-001'),
    ('PRD-014', 'Advanced Analytics Pack',                'ADD_ON',    9200.00, 'ADD-AAP-001'),
    ('PRD-015', 'Custom Connector Development',           'SERVICES', 15000.00, 'PS-CCD-001'),
    ('PRD-016', 'Platform Health Assessment',             'SERVICES',  6500.00, 'PS-PHA-001'),
    ('PRD-017', 'Certification Bundle - Team',            'TRAINING',  8000.00, 'TRN-TEAM-001'),
    ('PRD-018', 'Renewal - Standard',                     'SUPPORT',  12000.00, 'REN-STD-001'),
    ('PRD-019', 'Renewal - Enterprise',                   'SUPPORT',  22000.00, 'REN-ENT-001'),
    ('PRD-020', 'Expansion Seat Pack',                    'ADD_ON',    3500.00, 'ADD-ESP-001');

-- 4b. Customers (50 rows — 10 companies × 5 contacts)
INSERT INTO RAW.RAW_CUSTOMERS
    (customer_id_raw, full_name, email, phone, company, industry, created_at_raw, source_system)
WITH companies(company_id, company_name, domain, industry) AS (
    SELECT * FROM VALUES
        ('C001','Meridian Capital Group',      'meridiangroup.com',      'Financial Services'),
        ('C002','Apex Technology Partners',    'apextech.io',            'Technology'),
        ('C003','Horizon Retail Group',        'horizonretail.com',      'Retail'),
        ('C004','GlobalTech Solutions',        'globaltech.com',         'Technology'),
        ('C005','Pinnacle Financial Services', 'pinnacle-fs.com',        'Financial Services'),
        ('C006','NorthStar Analytics',         'northstar-analytics.ai', 'Analytics'),
        ('C007','Cascade Healthcare',          'cascadehealth.org',      'Healthcare'),
        ('C008','Vortex Manufacturing',        'vortexmfg.com',          'Manufacturing'),
        ('C009','Summit Energy Corp',          'summitenergy.com',       'Energy'),
        ('C010','Bluewater Logistics',         'bluewaterlog.com',       'Logistics')
),
contacts(cn, first_name, last_name) AS (
    SELECT * FROM VALUES
        (1,'James','Harrison'),
        (2,'Sarah','Mitchell'),
        (3,'Michael','Torres'),
        (4,'Rebecca','Nguyen'),
        (5,'Thomas','Bradley')
)
SELECT
    c.company_id || '-CON-' || LPAD(co.cn::VARCHAR, 2, '0')                         AS customer_id_raw,
    co.first_name || ' ' || co.last_name                                             AS full_name,
    LOWER(co.first_name) || '.' || LOWER(co.last_name) || '@' || c.domain           AS email,
    '+1-' || LPAD(SUBSTR(c.company_id, 2)::INTEGER::VARCHAR, 3, '0')
      || '-555-' || LPAD(co.cn::VARCHAR, 4, '0')                                    AS phone,
    c.company_name,
    c.industry,
    DATEADD('day', -(co.cn * 73 + SUBSTR(c.company_id, 2)::INTEGER * 11),
            CURRENT_DATE())::TIMESTAMP_NTZ                                           AS created_at_raw,
    IFF(co.cn <= 3, 'CRM', 'BILLING')                                                AS source_system
FROM companies c CROSS JOIN contacts co;

-- 4c. Transactions (200 rows — includes ~10 duplicates for demo purposes)
INSERT INTO RAW.RAW_TRANSACTIONS
    (transaction_id, source_txn_ref, event_timestamp, customer_name_raw,
     product_raw, amount_raw, currency, stage, sales_rep, region, load_status)
WITH gen AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS rn
    FROM TABLE(GENERATOR(ROWCOUNT => 200))
),
company_list(idx, cname) AS (
    SELECT * FROM VALUES
        (0,'Meridian Capital Group'),(1,'Apex Technology Partners'),(2,'Horizon Retail Group'),
        (3,'GlobalTech Solutions'),(4,'Pinnacle Financial Services'),(5,'NorthStar Analytics'),
        (6,'Cascade Healthcare'),(7,'Vortex Manufacturing'),(8,'Summit Energy Corp'),
        (9,'Bluewater Logistics')
),
product_list(idx, pname, base_price) AS (
    SELECT * FROM VALUES
        (0,'Enterprise Platform License',95000.00),(1,'Professional Services - Implementation',18000.00),
        (2,'Annual Support & Success',12000.00),(3,'Analytics Add-on Module',8500.00),
        (4,'Training & Certification Package',4500.00),(5,'Data Connector Bundle',6200.00),
        (6,'Security & Compliance Add-on',7800.00),(7,'API Access Tier - Premium',5000.00),
        (8,'Enterprise Platform License - Scale',145000.00),(9,'Managed Services - Premium',48000.00),
        (10,'Data Governance Module',11000.00),(11,'Renewal - Enterprise',22000.00),
        (12,'Renewal - Standard',12000.00),(13,'Advanced Analytics Pack',9200.00),
        (14,'Managed Services - Standard',24000.00)
),
rep_list(idx, rname, rregion) AS (
    SELECT * FROM VALUES
        (0,'Alice Johnson','AMER'),(1,'Bob Martinez','AMER'),(2,'Carol Chen','APAC'),
        (3,'David Okonkwo','EMEA'),(4,'Emma Richardson','EMEA'),
        (5,'Frank Kowalski','AMER'),(6,'Grace Tanaka','APAC')
)
SELECT
    UUID_STRING()                                                                     AS transaction_id,
    'TXN-' || LPAD(g.rn::VARCHAR, 6, '0')                                            AS source_txn_ref,
    DATEADD('day', -(MOD(g.rn * 53, 548)), CURRENT_DATE())::TIMESTAMP_NTZ            AS event_timestamp,
    cl.cname                                                                          AS customer_name_raw,
    pl.pname                                                                          AS product_raw,
    ROUND(pl.base_price * (0.75 + MOD(g.rn * 17, 50) / 100.0), 2)                   AS amount_raw,
    CASE MOD(g.rn * 7, 7)
        WHEN 0 THEN 'USD' WHEN 1 THEN 'USD' WHEN 2 THEN 'USD'
        WHEN 3 THEN 'EUR' WHEN 4 THEN 'GBP' WHEN 5 THEN 'USD' ELSE 'CAD' END        AS currency,
    CASE MOD(g.rn * 11, 7)
        WHEN 0 THEN 'CLOSED_WON'  WHEN 1 THEN 'CLOSED_WON'  WHEN 2 THEN 'CLOSED_WON'
        WHEN 3 THEN 'CLOSED_LOST' WHEN 4 THEN 'PIPELINE'
        WHEN 5 THEN 'NEGOTIATION' ELSE 'CLOSED_WON' END                              AS stage,
    rl.rname                                                                          AS sales_rep,
    rl.rregion                                                                        AS region,
    IFF(MOD(g.rn, 20) = 0, 'DUPLICATE', 'ORIGINAL')                                  AS load_status
FROM gen g
JOIN company_list cl ON cl.idx = MOD(g.rn * 3, 10)
JOIN product_list  pl ON pl.idx = MOD(g.rn * 7, 15)
JOIN rep_list      rl ON rl.idx = MOD(g.rn * 5, 7);

-- ── 5. CURATED layer (built from RAW) ────────────────────────

CREATE OR REPLACE TABLE CURATED.PRODUCTS
COMMENT = 'Curated product reference data. Deduplicated from RAW.RAW_PRODUCTS. Source for product_sk joins.'
AS
SELECT
    ROW_NUMBER() OVER (ORDER BY product_name)  AS product_sk,
    product_id_raw                             AS product_id,
    TRIM(product_name)                         AS product_name,
    category,
    list_price_usd                             AS unit_price_usd,
    CURRENT_TIMESTAMP()                        AS dw_load_ts
FROM RAW.RAW_PRODUCTS
WHERE load_status = 'ORIGINAL'
  AND is_active   = TRUE;

CREATE OR REPLACE TABLE CURATED.CUSTOMERS
COMMENT = 'Curated customer data. Deduplicated by email. PII columns masked via GOVERNANCE masking policies (Module 3).'
AS
SELECT
    ROW_NUMBER() OVER (ORDER BY company, customer_id_raw)  AS customer_sk,
    customer_id_raw                                        AS customer_id,
    TRIM(full_name)                                        AS full_name,
    LOWER(TRIM(email))                                     AS email,
    REGEXP_REPLACE(phone, '[^0-9+\\-]', '')                AS phone,
    TRIM(company)                                          AS company,
    industry,
    created_at_raw::DATE                                   AS customer_since,
    CURRENT_TIMESTAMP()                                    AS dw_load_ts
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY email ORDER BY ingested_at) AS rn
    FROM RAW.RAW_CUSTOMERS
) deduped
WHERE rn = 1;

CREATE OR REPLACE TABLE CURATED.SALES_REPS
COMMENT = 'Sales rep reference table with quota targets. Static reference — updated manually each fiscal year.'
AS
SELECT col1 AS rep_sk, col2 AS rep_name, col3 AS region, col4 AS quota_usd,
       CURRENT_TIMESTAMP() AS dw_load_ts
FROM VALUES
    (1, 'Alice Johnson',   'AMER', 750000.00),
    (2, 'Bob Martinez',    'AMER', 650000.00),
    (3, 'Carol Chen',      'APAC', 600000.00),
    (4, 'David Okonkwo',   'EMEA', 700000.00),
    (5, 'Emma Richardson', 'EMEA', 680000.00),
    (6, 'Frank Kowalski',  'AMER', 720000.00),
    (7, 'Grace Tanaka',    'APAC', 580000.00);

CREATE OR REPLACE TABLE CURATED.TRANSACTIONS
COMMENT = 'Curated transactions. Deduplicated, currency-normalised to USD, surrogate keys applied.'
AS
SELECT
    ROW_NUMBER() OVER (ORDER BY t.event_timestamp, t.transaction_id)  AS transaction_sk,
    t.transaction_id,
    t.event_timestamp::DATE                                            AS transaction_date,
    c.customer_sk,
    p.product_sk,
    ROUND(t.amount_raw * CASE t.currency
        WHEN 'USD' THEN 1.0000
        WHEN 'EUR' THEN 1.0850
        WHEN 'GBP' THEN 1.2700
        WHEN 'CAD' THEN 0.7400
        ELSE 1.0000 END, 2)                                           AS amount_usd,
    t.currency                                                         AS currency_orig,
    t.amount_raw                                                       AS amount_orig,
    t.stage,
    t.sales_rep,
    COALESCE(t.region, 'UNKNOWN')                                      AS region,
    (t.stage = 'CLOSED_WON')                                           AS is_won,
    p.category                                                         AS product_category,
    CURRENT_TIMESTAMP()                                                AS dw_load_ts
FROM RAW.RAW_TRANSACTIONS t
LEFT JOIN CURATED.CUSTOMERS c ON TRIM(t.customer_name_raw) = TRIM(c.company)
LEFT JOIN CURATED.PRODUCTS  p ON TRIM(t.product_raw)       = TRIM(p.product_name)
WHERE t.load_status = 'ORIGINAL';

-- ── 6. SEMANTIC_FINANCE layer ─────────────────────────────────

CREATE OR REPLACE TABLE SEMANTIC_FINANCE.MONTHLY_REVENUE
COMMENT = 'Finance data product: monthly closed-won revenue exclusive of tax. Contract v1.2 — owner: finance_data_owner. SLA: refresh within 24 hours.'
AS
SELECT
    DATE_TRUNC('month', transaction_date)               AS month_date,
    SUM(amount_usd)                                     AS total_revenue_usd,
    SUM(IFF(product_category = 'LICENSE',  amount_usd, 0)) AS new_business_usd,
    SUM(IFF(product_category = 'SUPPORT',  amount_usd, 0)) AS renewal_usd,
    SUM(IFF(product_category = 'ADD_ON',   amount_usd, 0)) AS expansion_usd,
    SUM(IFF(product_category = 'SERVICES', amount_usd, 0)) AS services_usd,
    COUNT(*)                                            AS deal_count,
    CURRENT_TIMESTAMP()                                 AS as_of_ts
FROM CURATED.TRANSACTIONS
WHERE is_won = TRUE
GROUP BY 1
ORDER BY 1;

CREATE OR REPLACE TABLE SEMANTIC_FINANCE.REVENUE_BY_PRODUCT
COMMENT = 'Finance data product: lifetime closed-won revenue by product. Contract v1.1 — owner: finance_data_owner.'
AS
SELECT
    p.product_name,
    p.category,
    SUM(t.amount_usd)           AS total_revenue_usd,
    COUNT(*)                    AS deal_count,
    ROUND(AVG(t.amount_usd), 2) AS avg_deal_size_usd,
    CURRENT_TIMESTAMP()         AS as_of_ts
FROM CURATED.TRANSACTIONS t
JOIN CURATED.PRODUCTS p ON t.product_sk = p.product_sk
WHERE t.is_won = TRUE
GROUP BY 1, 2
ORDER BY 3 DESC;

CREATE OR REPLACE TABLE SEMANTIC_FINANCE.CUSTOMER_LIFETIME_VALUE
COMMENT = 'Finance data product: customer-level LTV with segmentation. Contract v2.0 — owner: finance_data_owner.'
AS
WITH clv AS (
    SELECT
        c.customer_sk,
        c.company,
        SUM(t.amount_usd)       AS total_revenue_usd,
        COUNT(*)                AS deal_count,
        MIN(t.transaction_date) AS first_deal_date,
        MAX(t.transaction_date) AS last_deal_date
    FROM CURATED.TRANSACTIONS t
    JOIN CURATED.CUSTOMERS    c ON t.customer_sk = c.customer_sk
    WHERE t.is_won = TRUE
    GROUP BY 1, 2
)
SELECT
    customer_sk,
    company,
    total_revenue_usd,
    deal_count,
    first_deal_date,
    last_deal_date,
    CASE
        WHEN total_revenue_usd >= 400000 THEN 'PLATINUM'
        WHEN total_revenue_usd >= 200000 THEN 'GOLD'
        WHEN total_revenue_usd >=  80000 THEN 'SILVER'
        ELSE 'STANDARD'
    END                         AS clv_segment,
    CURRENT_TIMESTAMP()         AS as_of_ts
FROM clv;

-- ── 7. SEMANTIC_SALES layer ───────────────────────────────────

CREATE OR REPLACE TABLE SEMANTIC_SALES.PIPELINE_SUMMARY
COMMENT = 'Sales data product: current deal pipeline by stage with weighted value. Contract v1.0 — owner: sales_data_owner. SLA: refresh within 4 hours.'
AS
SELECT
    stage,
    COUNT(*)           AS deal_count,
    SUM(amount_usd)    AS total_value_usd,
    ROUND(SUM(amount_usd) * CASE stage
        WHEN 'CLOSED_WON'  THEN 1.00
        WHEN 'NEGOTIATION' THEN 0.60
        WHEN 'PIPELINE'    THEN 0.20
        ELSE 0.00 END, 2) AS weighted_value_usd,
    CURRENT_TIMESTAMP() AS as_of_ts
FROM CURATED.TRANSACTIONS
GROUP BY 1
ORDER BY CASE stage
    WHEN 'CLOSED_WON' THEN 1 WHEN 'NEGOTIATION' THEN 2
    WHEN 'PIPELINE'   THEN 3 ELSE 4 END;

CREATE OR REPLACE TABLE SEMANTIC_SALES.REP_PERFORMANCE
COMMENT = 'Sales data product: rep-level quota attainment and deal metrics. Contract v1.3 — owner: sales_data_owner.'
AS
SELECT
    r.rep_name,
    r.region,
    r.quota_usd,
    COALESCE(SUM(t.amount_usd), 0)                                   AS closed_won_usd,
    ROUND(COALESCE(SUM(t.amount_usd), 0) / r.quota_usd * 100, 1)    AS quota_attainment_pct,
    COUNT(t.transaction_sk)                                          AS deal_count,
    ROUND(AVG(t.amount_usd), 2)                                      AS avg_deal_size_usd,
    CURRENT_TIMESTAMP()                                              AS as_of_ts
FROM CURATED.SALES_REPS r
LEFT JOIN CURATED.TRANSACTIONS t ON t.sales_rep = r.rep_name AND t.is_won = TRUE
GROUP BY 1, 2, 3
ORDER BY 5 DESC;

CREATE OR REPLACE TABLE SEMANTIC_SALES.WIN_RATE_BY_REGION
COMMENT = 'Sales data product: win rate and deal velocity by sales region. Contract v1.0 — owner: sales_data_owner.'
AS
SELECT
    region,
    COUNT(*)                                                          AS total_deals,
    SUM(IFF(is_won, 1, 0))                                           AS won_deals,
    ROUND(SUM(IFF(is_won, 1, 0)) / NULLIF(COUNT(*), 0) * 100, 1)    AS win_rate_pct,
    ROUND(AVG(CASE WHEN is_won
        THEN ABS(DATEDIFF('day',
            DATEADD('day', -MOD(transaction_sk * 17, 90), transaction_date),
            transaction_date))
        ELSE NULL END), 0)                                           AS avg_days_to_close,
    CURRENT_TIMESTAMP()                                              AS as_of_ts
FROM CURATED.TRANSACTIONS
GROUP BY 1
ORDER BY 4 DESC;

-- ── 8. Row count verification ─────────────────────────────────

SELECT table_name, row_count FROM VALUES
    ('RAW.RAW_TRANSACTIONS',                 (SELECT COUNT(*) FROM RAW.RAW_TRANSACTIONS)),
    ('RAW.RAW_CUSTOMERS',                    (SELECT COUNT(*) FROM RAW.RAW_CUSTOMERS)),
    ('RAW.RAW_PRODUCTS',                     (SELECT COUNT(*) FROM RAW.RAW_PRODUCTS)),
    ('CURATED.TRANSACTIONS',                 (SELECT COUNT(*) FROM CURATED.TRANSACTIONS)),
    ('CURATED.CUSTOMERS',                    (SELECT COUNT(*) FROM CURATED.CUSTOMERS)),
    ('CURATED.PRODUCTS',                     (SELECT COUNT(*) FROM CURATED.PRODUCTS)),
    ('CURATED.SALES_REPS',                   (SELECT COUNT(*) FROM CURATED.SALES_REPS)),
    ('SEMANTIC_FINANCE.MONTHLY_REVENUE',     (SELECT COUNT(*) FROM SEMANTIC_FINANCE.MONTHLY_REVENUE)),
    ('SEMANTIC_FINANCE.REVENUE_BY_PRODUCT',  (SELECT COUNT(*) FROM SEMANTIC_FINANCE.REVENUE_BY_PRODUCT)),
    ('SEMANTIC_FINANCE.CUSTOMER_LTV',        (SELECT COUNT(*) FROM SEMANTIC_FINANCE.CUSTOMER_LIFETIME_VALUE)),
    ('SEMANTIC_SALES.PIPELINE_SUMMARY',      (SELECT COUNT(*) FROM SEMANTIC_SALES.PIPELINE_SUMMARY)),
    ('SEMANTIC_SALES.REP_PERFORMANCE',       (SELECT COUNT(*) FROM SEMANTIC_SALES.REP_PERFORMANCE)),
    ('SEMANTIC_SALES.WIN_RATE_BY_REGION',    (SELECT COUNT(*) FROM SEMANTIC_SALES.WIN_RATE_BY_REGION))
    AS t(table_name, row_count)
ORDER BY 1;

SELECT 'Module 2 complete: schemas and data created successfully' AS status;
