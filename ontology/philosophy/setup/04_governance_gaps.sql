-- ============================================================
-- DCA Demo | Module 4: Intentional Governance Gaps
-- ============================================================
-- Run as: SYSADMIN (after Modules 1–3)
-- Purpose: Creates the "before" state — objects that exhibit
--          the governance failures the Diagnostic Tool surfaces.
--
-- Gaps introduced:
--   1. Conflicting "revenue" definitions across domains
--   2. PII column with no masking policy
--   3. Orphaned data product — no owner, no contract
--   4. Raw layer bypass — consumer granted direct RAW access
-- ============================================================

USE ROLE SYSADMIN;
USE DATABASE DCA_DEMO;
USE WAREHOUSE COMPUTE_WH;

-- ── Gap 1: Conflicting revenue definition ────────────────────
-- SEMANTIC_SALES.REVENUE_SUMMARY defines revenue inclusive of
-- tax (gross-up applied). SEMANTIC_FINANCE.MONTHLY_REVENUE
-- defines it exclusive of tax. Both objects are named "revenue".
-- Neither has a tag or comment that makes the difference explicit
-- to downstream consumers.

CREATE OR REPLACE TABLE SEMANTIC_SALES.REVENUE_SUMMARY (
    month_date          DATE          COMMENT 'Calendar month',
    total_revenue_usd   NUMBER(14, 2) COMMENT 'Total billed amount — INCLUDES applicable tax gross-up (8.5%). Do not compare directly to Finance MONTHLY_REVENUE.',
    deal_count          INTEGER,
    as_of_ts            TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Sales view of monthly revenue. NOTE: includes tax gross-up at 8.5%. This is intentionally different from Finance MONTHLY_REVENUE — see GAP 1 in governance documentation.';

INSERT INTO SEMANTIC_SALES.REVENUE_SUMMARY (month_date, total_revenue_usd, deal_count)
SELECT
    DATE_TRUNC('month', t.transaction_date)      AS month_date,
    ROUND(SUM(t.amount_usd) * 1.085, 2)          AS total_revenue_usd,  -- 8.5% tax gross-up
    COUNT(*)                                     AS deal_count
FROM CURATED.TRANSACTIONS t
WHERE t.is_won = TRUE
GROUP BY 1
ORDER BY 1;

-- INTENTIONAL OMISSION: No data_contract_version tag applied.
-- No data_contract_owner. No data_purpose.
-- This table will appear as ungoverned on the health dashboard.

GRANT SELECT ON TABLE SEMANTIC_SALES.REVENUE_SUMMARY TO ROLE sales_data_consumer;

-- ── Gap 2: Unmasked PII extract ──────────────────────────────
-- Created for a one-off segmentation project. Never decommissioned.
-- Contains raw PII with no masking policy applied.
-- Accessible to both finance and sales consumers.

CREATE OR REPLACE TABLE CURATED.CUSTOMER_PII_EXTRACT (
    customer_sk   INTEGER,
    full_name     VARCHAR(200)  COMMENT 'PII — no masking policy on this table',
    email         VARCHAR(200)  COMMENT 'PII — no masking policy on this table',
    phone         VARCHAR(30)   COMMENT 'PII — no masking policy on this table',
    company       VARCHAR(200),
    industry      VARCHAR(100),
    extracted_by  VARCHAR(100) DEFAULT 'ad_hoc_analysis',
    extracted_at  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Ad-hoc PII extract for Q3 segmentation project. STATUS: pending decommission review. Contains unmasked PII — not compliant with governance policy.';

INSERT INTO CURATED.CUSTOMER_PII_EXTRACT
    (customer_sk, full_name, email, phone, company, industry)
SELECT customer_sk, full_name, email, phone, company, industry
FROM CURATED.CUSTOMERS;
-- NOTE: email and phone are read here using the SYSADMIN role,
-- bypassing the masking policies. In production, this insert
-- would expose unmasked PII to the target table permanently.

-- INTENTIONAL OMISSION: No masking policy applied.
-- No pii_category tag. Consumers get raw PII.
GRANT SELECT ON TABLE CURATED.CUSTOMER_PII_EXTRACT TO ROLE finance_data_consumer;
GRANT SELECT ON TABLE CURATED.CUSTOMER_PII_EXTRACT TO ROLE sales_data_consumer;

-- ── Gap 3: Orphaned data product ─────────────────────────────
-- Built by an external contractor. Project ended.
-- No role was assigned as owner. No contract. No tags.
-- Model is unvalidated — marked as beta but deployed to Semantic.

CREATE OR REPLACE TABLE SEMANTIC_FINANCE.CHURN_RISK_SCORE (
    customer_sk         INTEGER,
    company             VARCHAR(200),
    churn_risk_score    FLOAT        COMMENT 'Score 0–1; higher = greater churn risk',
    churn_risk_segment  VARCHAR(20)  COMMENT 'LOW / MEDIUM / HIGH',
    model_version       VARCHAR(20)  DEFAULT 'v0.9-beta',
    scored_at           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'ML churn risk scores. Model v0.9-beta — not validated for production use. Owner: UNKNOWN. No data contract.';

INSERT INTO SEMANTIC_FINANCE.CHURN_RISK_SCORE
    (customer_sk, company, churn_risk_score, churn_risk_segment)
WITH scored AS (
    SELECT
        customer_sk,
        company,
        ABS(MOD(HASH(customer_sk::VARCHAR || 'seed42'), 1000)) / 1000.0 AS raw_score
    FROM CURATED.CUSTOMERS
)
SELECT
    customer_sk,
    company,
    ROUND(raw_score, 3)                          AS churn_risk_score,
    CASE
        WHEN raw_score < 0.33 THEN 'LOW'
        WHEN raw_score < 0.66 THEN 'MEDIUM'
        ELSE 'HIGH'
    END                                          AS churn_risk_segment
FROM scored;

-- INTENTIONAL OMISSIONS: no data_contract_version, no data_contract_owner,
-- no data_purpose, no sla_freshness_hours, no consumer access policy.
-- Table owner defaults to SYSADMIN — no accountable role.

-- ── Gap 4: Raw layer bypass ───────────────────────────────────
-- A consumer was granted direct SELECT on RAW.RAW_TRANSACTIONS,
-- bypassing the CURATED cleansing and governance layers entirely.
-- This should never happen — but there is no policy preventing it.

GRANT SELECT ON TABLE RAW.RAW_TRANSACTIONS TO ROLE finance_data_consumer;
-- ^ Demonstrates absence of layer access controls.
--   In a governed DCA, consumers should only reach SEMANTIC tables.
--   This gap will surface on the Governance Health dashboard.

SELECT 'Module 4 complete: governance gaps created' AS status;

-- ── Gap summary (for demo reference) ─────────────────────────
SELECT gap_id, gap_type, object_name, gap_description FROM VALUES
    (1, 'Conflicting definition',
     'SEMANTIC_SALES.REVENUE_SUMMARY vs SEMANTIC_FINANCE.MONTHLY_REVENUE',
     'Both define "monthly revenue" but use different calculations (incl. vs excl. tax). No contract tag distinguishes them.'),
    (2, 'Unmasked PII',
     'CURATED.CUSTOMER_PII_EXTRACT',
     'Contains email and phone with no masking policy. Accessible to consumers who should only see masked data.'),
    (3, 'No ownership or contract',
     'SEMANTIC_FINANCE.CHURN_RISK_SCORE',
     'No data_contract_owner, no version, no purpose. Unvalidated ML model deployed to the Semantic layer.'),
    (4, 'Layer access bypass',
     'RAW.RAW_TRANSACTIONS → finance_data_consumer',
     'Consumer role has direct SELECT on RAW table, bypassing CURATED governance and SEMANTIC contracts.')
    AS t(gap_id, gap_type, object_name, gap_description)
ORDER BY gap_id;
