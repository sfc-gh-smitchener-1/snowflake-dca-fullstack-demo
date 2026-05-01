-- ============================================================
-- DCA Demo | Module 1: Role Architecture
-- ============================================================
-- Run as: ACCOUNTADMIN
-- Purpose: Creates the three-tier role hierarchy that models
--          the CDO → RDO → Consumer ownership chain.
--
--   ACCOUNTADMIN
--     └─ SYSADMIN
--           └─ dca_governance_admin     ← CDO layer
--                 └─ dca_platform_admin ← Platform RDO
--                       ├─ finance_data_owner
--                       │     └─ finance_data_consumer
--                       └─ sales_data_owner
--                             └─ sales_data_consumer
--
--   dca_raw_loader                      ← Ingestion service (no hierarchy)
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;  -- edit if your warehouse has a different name

-- ── 1. Functional roles ──────────────────────────────────────

CREATE ROLE IF NOT EXISTS dca_governance_admin
  COMMENT = 'CDO layer — owns governance objects: tags, masking policies, data contracts. Institutional authority over the meaning of data.';

CREATE ROLE IF NOT EXISTS dca_platform_admin
  COMMENT = 'Platform RDO — owns database and schema DDL, grants domain roles to object owners. Maintains the ontological infrastructure.';

CREATE ROLE IF NOT EXISTS finance_data_owner
  COMMENT = 'Finance RDO — accountable owner of all GOLD_FINANCE data products. Issues data contracts on behalf of the Finance domain.';

CREATE ROLE IF NOT EXISTS finance_data_consumer
  COMMENT = 'Finance consumer — read-only access to GOLD_FINANCE data products. Operates under the terms of the data contract.';

CREATE ROLE IF NOT EXISTS sales_data_owner
  COMMENT = 'Sales RDO — accountable owner of all GOLD_SALES data products. Issues data contracts on behalf of the Sales domain.';

CREATE ROLE IF NOT EXISTS sales_data_consumer
  COMMENT = 'Sales consumer — read-only access to GOLD_SALES data products. Operates under the terms of the data contract.';

CREATE ROLE IF NOT EXISTS dca_raw_loader
  COMMENT = 'Ingestion service account — INSERT-only access to RAW schema. Has no awareness of downstream governance obligations.';

-- ── 2. Role hierarchy ────────────────────────────────────────

GRANT ROLE dca_platform_admin    TO ROLE dca_governance_admin;
GRANT ROLE finance_data_owner    TO ROLE dca_platform_admin;
GRANT ROLE sales_data_owner      TO ROLE dca_platform_admin;
GRANT ROLE finance_data_consumer TO ROLE finance_data_owner;
GRANT ROLE sales_data_consumer   TO ROLE sales_data_owner;

-- Allow a single SYSADMIN user to switch between all roles in a trial account
GRANT ROLE dca_governance_admin  TO ROLE SYSADMIN;
GRANT ROLE dca_platform_admin    TO ROLE SYSADMIN;
GRANT ROLE finance_data_owner    TO ROLE SYSADMIN;
GRANT ROLE finance_data_consumer TO ROLE SYSADMIN;
GRANT ROLE sales_data_owner      TO ROLE SYSADMIN;
GRANT ROLE sales_data_consumer   TO ROLE SYSADMIN;
GRANT ROLE dca_raw_loader        TO ROLE SYSADMIN;

-- ── 3. Warehouse grants ──────────────────────────────────────

GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE dca_governance_admin;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE dca_platform_admin;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE finance_data_owner;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE finance_data_consumer;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE sales_data_owner;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE sales_data_consumer;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE dca_raw_loader;

SELECT 'Module 1 complete: role architecture created successfully' AS status;
