-- ============================================================================
-- ONTOLOGY KNOWLEDGE GRAPH - RAI INFRASTRUCTURE SETUP
-- ============================================================================
--
-- This script sets up the foundational infrastructure for the Ontology
-- Knowledge Graph module, which uses RelationalAI (RAI) on SPCS to provide
-- graph-based governance analysis.
--
-- Prerequisites:
--   1. Scripts 01-10 have been executed successfully
--   2. RAI Native App installed from Snowflake Marketplace
--      (Search for "RelationalAI" in Marketplace and install)
--
-- Creates:
--   1. Compute pool for SPCS services
--   2. Image repository for container images
--   3. RAI engine for graph computation
--   4. Schema for materialized graph tables
--   5. Roles for graph administration and consumption
--
-- RUN AS: ACCOUNTADMIN (for role/compute pool creation), then DATA_ADMIN
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 1: COMPUTE POOL FOR SPCS
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;
USE DATABASE DCA_DEMO;
USE WAREHOUSE COMPUTE_WH;

-- Compute pool for the Ontology Graph SPCS service
CREATE COMPUTE POOL IF NOT EXISTS RAI_COMPUTE_POOL
    MIN_NODES = 1
    MAX_NODES = 1
    INSTANCE_FAMILY = CPU_X64_S
    COMMENT = 'Compute pool for Ontology Knowledge Graph SPCS service';

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 2: IMAGE REPOSITORY
-- ═══════════════════════════════════════════════════════════════════════════

-- Repository for storing container images (Ontology Graph API)
CREATE IMAGE REPOSITORY IF NOT EXISTS DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_REPO
    COMMENT = 'Container image repository for Ontology Knowledge Graph services';

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 3: RAI ENGINE
-- ═══════════════════════════════════════════════════════════════════════════

-- NOTE: The RAI Native App must be installed from the Snowflake Marketplace
-- before this step. The app provides the RAI.API schema with engine management.

-- Create a dedicated RAI engine for ontology graph computation
CALL RAI.API.CREATE_ENGINE('ONTOLOGY_ENGINE', 'HIGHMEM_X64_S');

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 4: SCHEMA FOR GRAPH TABLES
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE DATA_ADMIN;

-- Schema to hold materialized node/edge tables and RAI results
CREATE SCHEMA IF NOT EXISTS DCA_DEMO.GOVERNANCE
    COMMENT = 'Governance schema (already exists from 01_setup.sql)';

-- Note: GOVERNANCE schema already exists from 01_setup.sql
-- The graph tables (created in 12_ontology_graph_tables.sql) will live
-- directly in the GOVERNANCE schema with prefix ONTOLOGY_GRAPH_

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 5: ROLES AND PRIVILEGES
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;

-- Role for administering the ontology graph (run inference, manage data)
CREATE ROLE IF NOT EXISTS ONTOLOGY_ADMIN
    COMMENT = 'Administers the Ontology Knowledge Graph - manages graph data, runs RAI inference';

-- Role for consuming/querying the ontology graph (read-only access)
CREATE ROLE IF NOT EXISTS ONTOLOGY_CONSUMER
    COMMENT = 'Consumes the Ontology Knowledge Graph - queries graph data and API endpoints';

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 6: ROLE HIERARCHY GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

-- ONTOLOGY_ADMIN inherits from DATA_ADMIN
GRANT ROLE ONTOLOGY_ADMIN TO ROLE DATA_ADMIN;

-- ONTOLOGY_CONSUMER granted to downstream consumers
GRANT ROLE ONTOLOGY_CONSUMER TO ROLE DATA_STEWARD;
GRANT ROLE ONTOLOGY_CONSUMER TO ROLE MARKETPLACE_CONSUMER;

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 7: RESOURCE GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

-- Warehouse access
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE ONTOLOGY_CONSUMER;

-- Database access
GRANT USAGE ON DATABASE DCA_DEMO TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON DATABASE DCA_DEMO TO ROLE ONTOLOGY_CONSUMER;

-- Schema access
GRANT USAGE ON SCHEMA DCA_DEMO.GOVERNANCE TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON SCHEMA DCA_DEMO.GOVERNANCE TO ROLE ONTOLOGY_CONSUMER;
GRANT CREATE TABLE ON SCHEMA DCA_DEMO.GOVERNANCE TO ROLE ONTOLOGY_ADMIN;
GRANT CREATE VIEW ON SCHEMA DCA_DEMO.GOVERNANCE TO ROLE ONTOLOGY_ADMIN;
GRANT CREATE PROCEDURE ON SCHEMA DCA_DEMO.GOVERNANCE TO ROLE ONTOLOGY_ADMIN;

-- Compute pool access for ONTOLOGY_ADMIN (needed for SPCS deployments)
GRANT USAGE ON COMPUTE POOL RAI_COMPUTE_POOL TO ROLE ONTOLOGY_ADMIN;

-- Image repository access
GRANT READ, WRITE ON IMAGE REPOSITORY DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_REPO TO ROLE ONTOLOGY_ADMIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

-- Verify setup
SELECT 'RAI Infrastructure Setup Complete' AS status;
SHOW COMPUTE POOLS LIKE 'RAI_COMPUTE_POOL';
SHOW ROLES LIKE 'ONTOLOGY%';
