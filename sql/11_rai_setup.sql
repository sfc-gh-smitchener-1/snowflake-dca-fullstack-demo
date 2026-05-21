-- ============================================================================
-- ONTOLOGY KNOWLEDGE GRAPH - SPCS INFRASTRUCTURE SETUP
-- ============================================================================
--
-- Sets up the foundational infrastructure for the Ontology Knowledge Graph
-- module. The graph can be queried two ways (see docs/GRAPH_BACKENDS.md):
--   1. Snowflake-native (default) — recursive CTEs, no SPCS required
--   2. Neo4j sidecar on SPCS — for Cypher / GDS-class algorithms
--
-- This script provisions the SPCS infrastructure needed for backend #2.
-- The Snowflake-native backend works without any of this.
--
-- Prerequisites:
--   1. Scripts 01-10 have been executed successfully
--
-- Creates:
--   1. Compute pool for SPCS services (Neo4j + API)
--   2. Image repository for container images
--   3. Roles for graph administration and consumption
--   4. Resource grants
--
-- RUN AS: ACCOUNTADMIN (for role/compute pool creation), then DATA_ADMIN
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 1: COMPUTE POOL FOR SPCS
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;
USE DATABASE DCA_DEMO;
USE WAREHOUSE COMPUTE_WH;

-- Compute pool for the Ontology Graph SPCS service.
--
-- CPU_X64_M sized to accommodate the Neo4j sidecar's heap + pagecache.
-- If you deploy with service-spec.snowflake-only.yaml (no Neo4j sidecar),
-- you can downsize this pool to CPU_X64_S to cut cost.
CREATE COMPUTE POOL IF NOT EXISTS RAI_COMPUTE_POOL
    MIN_NODES = 1
    MAX_NODES = 1
    INSTANCE_FAMILY = CPU_X64_M
    COMMENT = 'Compute pool for Ontology Knowledge Graph SPCS service (FastAPI + optional Neo4j sidecar)';

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 2: IMAGE REPOSITORY
-- ═══════════════════════════════════════════════════════════════════════════

-- Repository for storing container images (Ontology Graph API + Neo4j)
CREATE IMAGE REPOSITORY IF NOT EXISTS DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_REPO
    COMMENT = 'Container image repository for Ontology Knowledge Graph services (API + Neo4j)';

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 3: ROLES AND PRIVILEGES
-- ═══════════════════════════════════════════════════════════════════════════

-- Role for administering the ontology graph (run inference, manage data)
CREATE ROLE IF NOT EXISTS ONTOLOGY_ADMIN
    COMMENT = 'Administers the Ontology Knowledge Graph - manages graph data, runs inference';

-- Role for consuming/querying the ontology graph (read-only access)
CREATE ROLE IF NOT EXISTS ONTOLOGY_CONSUMER
    COMMENT = 'Consumes the Ontology Knowledge Graph - queries graph data and API endpoints';

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 4: ROLE HIERARCHY GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

-- ONTOLOGY_ADMIN inherits from DATA_ADMIN
GRANT ROLE ONTOLOGY_ADMIN TO ROLE DATA_ADMIN;

-- ONTOLOGY_CONSUMER granted to downstream consumers
GRANT ROLE ONTOLOGY_CONSUMER TO ROLE DATA_STEWARD;

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 5: RESOURCE GRANTS
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
GRANT CREATE SERVICE ON SCHEMA DCA_DEMO.GOVERNANCE TO ROLE ONTOLOGY_ADMIN;

-- Compute pool access for ONTOLOGY_ADMIN (needed for SPCS deployments)
GRANT USAGE ON COMPUTE POOL RAI_COMPUTE_POOL TO ROLE ONTOLOGY_ADMIN;
GRANT MONITOR ON COMPUTE POOL RAI_COMPUTE_POOL TO ROLE ONTOLOGY_ADMIN;

-- Image repository access
GRANT READ, WRITE ON IMAGE REPOSITORY DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_REPO TO ROLE ONTOLOGY_ADMIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 6: EXTERNAL ACCESS (for Neo4j container egress if needed)
-- ═══════════════════════════════════════════════════════════════════════════

-- Neo4j runs as a sidecar, no external egress needed.
-- If future plugins require downloads, create an external access integration here.

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'SPCS Infrastructure Setup Complete (Neo4j + API)' AS status;
SHOW COMPUTE POOLS LIKE 'RAI_COMPUTE_POOL';
SHOW ROLES LIKE 'ONTOLOGY%';
