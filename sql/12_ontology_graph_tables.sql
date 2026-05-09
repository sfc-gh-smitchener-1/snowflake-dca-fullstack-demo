-- ============================================================================
-- ONTOLOGY KNOWLEDGE GRAPH - TABLE DDL
-- ============================================================================
--
-- Creates the materialized node/edge tables for the Ontology Knowledge Graph:
--   1. ONTOLOGY_GRAPH_NODES - All graph nodes (metadata + business entities)
--   2. ONTOLOGY_GRAPH_EDGES - All relationships between nodes
--   3. ONTOLOGY_GRAPH_SNAPSHOTS - Point-in-time graph statistics
--   4. ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS - RAI-generated governance actions
--   5. ONTOLOGY_GRAPH_RAI_ENTITY_CLUSTERS - Cross-system entity resolution
--   6. ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES - Per-node governance health
--
-- PREREQUISITES:
--   - 11_rai_setup.sql must have been executed
--   - ONTOLOGY_ADMIN and ONTOLOGY_CONSUMER roles must exist
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE DCA_DEMO;
USE SCHEMA GOVERNANCE;
USE WAREHOUSE COMPUTE_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- TABLE 1: NODES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES (
    node_id         VARCHAR NOT NULL,
    node_type       VARCHAR NOT NULL,       -- TABLE, COLUMN, TAG, ROLE, POLICY, SHARE, CUSTOMER, PATIENT, PRODUCT, EMPLOYEE, ORG, INCIDENT, ORDER
    layer           VARCHAR NOT NULL,       -- METADATA | BUSINESS
    source_system   VARCHAR NOT NULL,       -- SNOWFLAKE | SAP | ORACLE | SALESFORCE | FHIR | WORKDAY | SERVICENOW
    fqn             VARCHAR,               -- Fully qualified name (metadata) or source ID (business)
    display_name    VARCHAR NOT NULL,
    properties      VARIANT,               -- JSON bag of type-specific attributes
    created_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_nodes PRIMARY KEY (node_id)
);

COMMENT ON TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES IS
    'All graph nodes representing metadata objects (tables, columns, roles, tags) and business entities (customers, patients, employees, products)';

-- ═══════════════════════════════════════════════════════════════════════════
-- TABLE 2: EDGES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES (
    edge_id         VARCHAR NOT NULL,
    source_node_id  VARCHAR NOT NULL,
    target_node_id  VARCHAR NOT NULL,
    edge_type       VARCHAR NOT NULL,       -- OWNS, TAGGED_WITH, MASKED_BY, LINEAGE_FROM, GRANTED_TO, PURCHASES, TREATED_BY, WORKS_FOR, etc.
    layer           VARCHAR NOT NULL,       -- METADATA | BUSINESS | CROSS
    weight          FLOAT DEFAULT 1.0,
    properties      VARIANT,
    created_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_edges PRIMARY KEY (edge_id)
);

COMMENT ON TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES IS
    'All relationships (edges) between graph nodes including metadata ownership, lineage, tagging, and business entity relationships';

-- ═══════════════════════════════════════════════════════════════════════════
-- TABLE 3: GRAPH SNAPSHOTS
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SNAPSHOTS (
    snapshot_id     INTEGER AUTOINCREMENT,
    snapshot_time   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    node_count      INTEGER,
    edge_count      INTEGER,
    metadata        VARIANT,
    CONSTRAINT pk_snapshots PRIMARY KEY (snapshot_id)
);

COMMENT ON TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SNAPSHOTS IS
    'Point-in-time snapshots of graph statistics captured after each refresh cycle';

-- ═══════════════════════════════════════════════════════════════════════════
-- TABLE 4: RAI RECOMMENDATIONS
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS (
    recommendation_id   INTEGER AUTOINCREMENT,
    recommendation_type VARCHAR NOT NULL,   -- PII_PROPAGATION, OWNERSHIP_GAP, ENTITY_MATCH, LAYER_BYPASS
    severity            VARCHAR NOT NULL,   -- HIGH, MEDIUM, LOW
    source_node_id      VARCHAR,
    target_node_id      VARCHAR,
    description         VARCHAR NOT NULL,
    suggested_action    VARCHAR,
    status              VARCHAR DEFAULT 'OPEN',  -- OPEN, APPROVED, DISMISSED
    created_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    resolved_at         TIMESTAMP_NTZ
);

COMMENT ON TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS IS
    'RAI-generated governance recommendations including PII propagation alerts, ownership gaps, entity matches, and layer bypass warnings';

-- ═══════════════════════════════════════════════════════════════════════════
-- TABLE 5: RAI ENTITY CLUSTERS
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_ENTITY_CLUSTERS (
    cluster_id      INTEGER,
    node_id         VARCHAR NOT NULL,
    cluster_label   VARCHAR,
    confidence      FLOAT,
    created_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

COMMENT ON TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_ENTITY_CLUSTERS IS
    'Cross-system entity resolution clusters produced by RAI graph algorithms — groups nodes representing the same real-world entity';

-- ═══════════════════════════════════════════════════════════════════════════
-- TABLE 6: RAI GOVERNANCE SCORES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES (
    node_id             VARCHAR NOT NULL,
    overall_score       FLOAT,
    tag_coverage        FLOAT,
    contract_coverage   FLOAT,
    ownership_score     FLOAT,
    quality_score       FLOAT,
    scored_at           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

COMMENT ON TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES IS
    'Per-node governance health scores computed by RAI inference — composite of tag coverage, contract presence, ownership, and quality monitoring';

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

-- ONTOLOGY_ADMIN: full access
GRANT ALL PRIVILEGES ON TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES TO ROLE ONTOLOGY_ADMIN;
GRANT ALL PRIVILEGES ON TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES TO ROLE ONTOLOGY_ADMIN;
GRANT ALL PRIVILEGES ON TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SNAPSHOTS TO ROLE ONTOLOGY_ADMIN;
GRANT ALL PRIVILEGES ON TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS TO ROLE ONTOLOGY_ADMIN;
GRANT ALL PRIVILEGES ON TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_ENTITY_CLUSTERS TO ROLE ONTOLOGY_ADMIN;
GRANT ALL PRIVILEGES ON TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES TO ROLE ONTOLOGY_ADMIN;

-- ONTOLOGY_CONSUMER: read-only access
GRANT SELECT ON TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES TO ROLE ONTOLOGY_CONSUMER;
GRANT SELECT ON TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES TO ROLE ONTOLOGY_CONSUMER;
GRANT SELECT ON TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SNAPSHOTS TO ROLE ONTOLOGY_CONSUMER;
GRANT SELECT ON TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS TO ROLE ONTOLOGY_CONSUMER;
GRANT SELECT ON TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_ENTITY_CLUSTERS TO ROLE ONTOLOGY_CONSUMER;
GRANT SELECT ON TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES TO ROLE ONTOLOGY_CONSUMER;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT table_name, table_type, comment
FROM DCA_DEMO.INFORMATION_SCHEMA.TABLES
WHERE table_schema = 'GOVERNANCE'
  AND table_name LIKE 'ONTOLOGY_GRAPH_%'
ORDER BY table_name;
