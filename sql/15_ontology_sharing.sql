-- ============================================================================
-- ONTOLOGY KNOWLEDGE GRAPH - SHARING CONFIGURATION
-- ============================================================================
--
-- Configures data sharing for the Ontology Knowledge Graph:
--   1. Secure views over graph tables (required for sharing)
--   2. Snowflake Share with grants
--   3. SPCS service endpoint access for consumers
--   4. Data product catalog registration
--
-- PREREQUISITES:
--   - 14_rai_graph_sync.sql must have been executed
--   - ONTOLOGY_CONSUMER role must exist
--   - ONTOLOGY_GRAPH_SERVICE deployed via ontology/spcs/service-spec.yaml
--
-- RUN AS: ACCOUNTADMIN
-- ============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE DCA_DEMO;
USE SCHEMA GOVERNANCE;
USE WAREHOUSE COMPUTE_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 1: SECURE VIEWS
-- ═══════════════════════════════════════════════════════════════════════════
-- Secure views are required for sharing — base tables cannot be shared
-- directly. Each view exposes the full table with row-level security via
-- the SECURE keyword.

CREATE OR REPLACE SECURE VIEW DCA_DEMO.GOVERNANCE.V_ONTOLOGY_NODES AS
SELECT
    node_id,
    node_type,
    layer,
    source_system,
    fqn,
    display_name,
    properties,
    created_at
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES;

CREATE OR REPLACE SECURE VIEW DCA_DEMO.GOVERNANCE.V_ONTOLOGY_EDGES AS
SELECT
    edge_id,
    source_node_id,
    target_node_id,
    edge_type,
    layer,
    weight,
    properties,
    created_at
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES;

CREATE OR REPLACE SECURE VIEW DCA_DEMO.GOVERNANCE.V_ONTOLOGY_SCORES AS
SELECT
    node_id,
    overall_score,
    tag_coverage,
    contract_coverage,
    ownership_score,
    quality_score,
    scored_at
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES;

CREATE OR REPLACE SECURE VIEW DCA_DEMO.GOVERNANCE.V_ONTOLOGY_RECOMMENDATIONS AS
SELECT
    recommendation_id,
    recommendation_type,
    severity,
    source_node_id,
    target_node_id,
    description,
    suggested_action,
    status,
    created_at,
    resolved_at
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS
WHERE status != 'DISMISSED';

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 2: SNOWFLAKE SHARE
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE SHARE ONTOLOGY_GRAPH_DATA_SHARE
    COMMENT = 'Ontology Knowledge Graph — node/edge model with governance scores and RAI recommendations';

GRANT USAGE ON DATABASE DCA_DEMO TO SHARE ONTOLOGY_GRAPH_DATA_SHARE;
GRANT USAGE ON SCHEMA DCA_DEMO.GOVERNANCE TO SHARE ONTOLOGY_GRAPH_DATA_SHARE;
GRANT SELECT ON VIEW DCA_DEMO.GOVERNANCE.V_ONTOLOGY_NODES TO SHARE ONTOLOGY_GRAPH_DATA_SHARE;
GRANT SELECT ON VIEW DCA_DEMO.GOVERNANCE.V_ONTOLOGY_EDGES TO SHARE ONTOLOGY_GRAPH_DATA_SHARE;
GRANT SELECT ON VIEW DCA_DEMO.GOVERNANCE.V_ONTOLOGY_SCORES TO SHARE ONTOLOGY_GRAPH_DATA_SHARE;
GRANT SELECT ON VIEW DCA_DEMO.GOVERNANCE.V_ONTOLOGY_RECOMMENDATIONS TO SHARE ONTOLOGY_GRAPH_DATA_SHARE;

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 3: SPCS SERVICE ENDPOINT ACCESS
-- ═══════════════════════════════════════════════════════════════════════════
-- Grant the ONTOLOGY_CONSUMER role access to the SPCS-hosted FastAPI service
-- so consumers can query the graph API endpoint.

GRANT USAGE ON SERVICE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SERVICE TO ROLE ONTOLOGY_CONSUMER;

-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 4: DATA PRODUCT CATALOG REGISTRATION
-- ═══════════════════════════════════════════════════════════════════════════

INSERT INTO DCA_DEMO.GOVERNANCE.DATA_PRODUCT_CATALOG (
    product_id,
    schema_name,
    table_name,
    product_name,
    description,
    domain,
    data_contract_version,
    contract_status,
    owner_role,
    sample_query,
    tags
)
SELECT
    'ontology_graph',
    'GOVERNANCE',
    'ONTOLOGY_GRAPH_NODES',
    'Ontology Knowledge Graph',
    'Cross-system knowledge graph linking metadata and business entities with RAI-powered governance scoring',
    'GOVERNANCE',
    '1.0.0',
    'ACTIVE',
    'ONTOLOGY_ADMIN',
    'SELECT n.display_name, n.node_type, n.source_system FROM DCA_DEMO.GOVERNANCE.V_ONTOLOGY_NODES n WHERE n.layer = ''METADATA'' LIMIT 20;',
    PARSE_JSON('["ontology","knowledge-graph","rai","governance"]')
WHERE NOT EXISTS (
    SELECT 1 FROM DCA_DEMO.GOVERNANCE.DATA_PRODUCT_CATALOG
    WHERE product_id = 'ontology_graph'
);

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

-- Confirm share was created
SHOW SHARES LIKE 'ONTOLOGY_GRAPH%';

-- Confirm secure views exist
SELECT table_name, table_type, is_secure
FROM DCA_DEMO.INFORMATION_SCHEMA.VIEWS
WHERE table_schema = 'GOVERNANCE'
  AND table_name LIKE 'V_ONTOLOGY%'
ORDER BY table_name;

-- Confirm catalog registration
SELECT product_id, product_name, contract_status
FROM DCA_DEMO.GOVERNANCE.DATA_PRODUCT_CATALOG
WHERE product_id = 'ontology_graph';
