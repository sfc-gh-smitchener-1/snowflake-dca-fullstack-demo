-- ============================================================================
-- ONTOLOGY KNOWLEDGE GRAPH - ROLES & GRANTS SETUP
-- ============================================================================
--
-- Sets up the roles and grants for the Snowflake-native Ontology Knowledge
-- Graph module (see docs/KNOWLEDGE_GRAPH.md). The graph is queried entirely
-- in-database with recursive CTEs and SQL stored procedures — no sidecar,
-- no container service.
--
-- Prerequisites:
--   1. Scripts 01-10 have been executed successfully
--
-- Creates:
--   1. Roles for graph administration and consumption
--   2. Role hierarchy + resource grants
--
-- RUN AS: ACCOUNTADMIN (for role creation), then DATA_ADMIN
-- ============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE DCA_DEMO;
USE WAREHOUSE COMPUTE_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 1: ROLES AND PRIVILEGES
-- ═══════════════════════════════════════════════════════════════════════════

-- Role for administering the ontology graph (run inference, manage data)
CREATE ROLE IF NOT EXISTS ONTOLOGY_ADMIN
    COMMENT = 'Administers the Ontology Knowledge Graph - manages graph data, runs inference';

-- Role for consuming/querying the ontology graph (read-only access)
CREATE ROLE IF NOT EXISTS ONTOLOGY_CONSUMER
    COMMENT = 'Consumes the Ontology Knowledge Graph - queries graph data';

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 2: ROLE HIERARCHY GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

-- ONTOLOGY_ADMIN inherits from DATA_ADMIN
GRANT ROLE ONTOLOGY_ADMIN TO ROLE DATA_ADMIN;

-- ONTOLOGY_CONSUMER granted to downstream consumers
GRANT ROLE ONTOLOGY_CONSUMER TO ROLE DATA_STEWARD;

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 3: RESOURCE GRANTS
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

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'Ontology Knowledge Graph roles & grants setup complete (Snowflake-native)' AS status;
SHOW ROLES LIKE 'ONTOLOGY%';
