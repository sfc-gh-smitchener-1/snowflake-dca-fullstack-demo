-- ============================================================================
-- ONTOLOGY KNOWLEDGE GRAPH - POPULATE GRAPH TABLES
-- ============================================================================
--
-- Creates stored procedures to populate the Ontology Knowledge Graph with
-- nodes and edges from Snowflake metadata and curated business data:
--   1. SP_POPULATE_METADATA_NODES - Tables, columns, roles from INFORMATION_SCHEMA
--   2. SP_POPULATE_METADATA_EDGES - Ownership, tagging, and grant relationships
--   3. SP_POPULATE_BUSINESS_NODES - Business entities from curated source systems
--   4. SP_POPULATE_BUSINESS_EDGES - Business relationships (purchases, encounters)
--   5. SP_POPULATE_CROSS_EDGES - Links business entities to their metadata tables
--   6. SP_REFRESH_GRAPH - Orchestrator that runs all procedures and snapshots
--
-- SOURCE SYSTEMS:
--   SAP, Oracle, Salesforce, FHIR, Workday, ServiceNow
--   (tables in CURATED_DEV.<source>.*)
--
-- PREREQUISITES:
--   - 12_ontology_graph_tables.sql must have been executed
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE DCA_DEMO;
USE SCHEMA GOVERNANCE;
USE WAREHOUSE COMPUTE_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 1: POPULATE METADATA NODES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_POPULATE_METADATA_NODES()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_node_count INTEGER DEFAULT 0;
BEGIN
    -- Insert TABLE nodes from INFORMATION_SCHEMA
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
    USING (
        SELECT
            'META_' || MD5(table_catalog || '.' || table_schema || '.' || table_name) AS node_id,
            'TABLE' AS node_type,
            'METADATA' AS layer,
            'SNOWFLAKE' AS source_system,
            table_catalog || '.' || table_schema || '.' || table_name AS fqn,
            table_name AS display_name,
            OBJECT_CONSTRUCT(
                'catalog', table_catalog,
                'schema', table_schema,
                'table_type', table_type,
                'row_count', row_count,
                'bytes', bytes
            ) AS properties
        FROM DCA_DEMO.INFORMATION_SCHEMA.TABLES
        WHERE table_schema NOT IN ('INFORMATION_SCHEMA')
          AND table_type IN ('BASE TABLE', 'VIEW')
    ) AS src
    ON tgt.node_id = src.node_id
    WHEN MATCHED THEN UPDATE SET
        tgt.properties = src.properties
    WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
        VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

    -- Insert COLUMN nodes from INFORMATION_SCHEMA
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
    USING (
        SELECT
            'META_' || MD5(table_catalog || '.' || table_schema || '.' || table_name || '.' || column_name) AS node_id,
            'COLUMN' AS node_type,
            'METADATA' AS layer,
            'SNOWFLAKE' AS source_system,
            table_catalog || '.' || table_schema || '.' || table_name || '.' || column_name AS fqn,
            column_name AS display_name,
            OBJECT_CONSTRUCT(
                'table_fqn', table_catalog || '.' || table_schema || '.' || table_name,
                'data_type', data_type,
                'is_nullable', is_nullable,
                'ordinal_position', ordinal_position
            ) AS properties
        FROM DCA_DEMO.INFORMATION_SCHEMA.COLUMNS
        WHERE table_schema NOT IN ('INFORMATION_SCHEMA')
    ) AS src
    ON tgt.node_id = src.node_id
    WHEN MATCHED THEN UPDATE SET
        tgt.properties = src.properties
    WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
        VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

    -- Count inserted nodes
    SELECT COUNT(*) INTO :v_node_count
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
    WHERE layer = 'METADATA';

    RETURN 'Metadata nodes populated: ' || :v_node_count || ' total metadata nodes';
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 2: POPULATE METADATA EDGES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_POPULATE_METADATA_EDGES()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_edge_count INTEGER DEFAULT 0;
BEGIN
    -- TABLE → COLUMN edges (HAS_COLUMN)
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT
            'EDGE_' || MD5(
                'META_' || MD5(table_catalog || '.' || table_schema || '.' || table_name) ||
                'META_' || MD5(table_catalog || '.' || table_schema || '.' || table_name || '.' || column_name) ||
                'HAS_COLUMN'
            ) AS edge_id,
            'META_' || MD5(table_catalog || '.' || table_schema || '.' || table_name) AS source_node_id,
            'META_' || MD5(table_catalog || '.' || table_schema || '.' || table_name || '.' || column_name) AS target_node_id,
            'HAS_COLUMN' AS edge_type,
            'METADATA' AS layer,
            1.0 AS weight
        FROM DCA_DEMO.INFORMATION_SCHEMA.COLUMNS
        WHERE table_schema NOT IN ('INFORMATION_SCHEMA')
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    -- ROLE → TABLE edges (GRANTED_TO) from table privileges
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT DISTINCT
            'EDGE_' || MD5(
                'META_' || MD5(grantee) ||
                'META_' || MD5(table_catalog || '.' || table_schema || '.' || table_name) ||
                'GRANTED_TO'
            ) AS edge_id,
            'META_' || MD5(grantee) AS source_node_id,
            'META_' || MD5(table_catalog || '.' || table_schema || '.' || table_name) AS target_node_id,
            'GRANTED_TO' AS edge_type,
            'METADATA' AS layer,
            1.0 AS weight
        FROM DCA_DEMO.INFORMATION_SCHEMA.TABLE_PRIVILEGES
        WHERE privilege_type = 'SELECT'
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    -- TAG → TABLE/COLUMN edges (TAGGED_WITH) using TAG_REFERENCES
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT
            'EDGE_' || MD5(
                'META_' || MD5(object_database || '.' || object_schema || '.' || object_name ||
                    CASE WHEN column_name IS NOT NULL THEN '.' || column_name ELSE '' END) ||
                'META_' || MD5(tag_database || '.' || tag_schema || '.' || tag_name) ||
                'TAGGED_WITH'
            ) AS edge_id,
            'META_' || MD5(object_database || '.' || object_schema || '.' || object_name ||
                CASE WHEN column_name IS NOT NULL THEN '.' || column_name ELSE '' END) AS source_node_id,
            'META_' || MD5(tag_database || '.' || tag_schema || '.' || tag_name) AS target_node_id,
            'TAGGED_WITH' AS edge_type,
            'METADATA' AS layer,
            1.0 AS weight
        FROM TABLE(DCA_DEMO.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('DCA_DEMO', 'GOVERNANCE'))
        WHERE tag_name IS NOT NULL
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    -- Count edges
    SELECT COUNT(*) INTO :v_edge_count
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
    WHERE layer = 'METADATA';

    RETURN 'Metadata edges populated: ' || :v_edge_count || ' total metadata edges';
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 3: POPULATE BUSINESS NODES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_POPULATE_BUSINESS_NODES()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_node_count INTEGER DEFAULT 0;
BEGIN
    -- CUSTOMER nodes from Salesforce DIM_ACCOUNT
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
    USING (
        SELECT
            'BIZ_CUST_' || MD5(ACCOUNT_ID) AS node_id,
            'CUSTOMER' AS node_type,
            'BUSINESS' AS layer,
            'SALESFORCE' AS source_system,
            ACCOUNT_ID AS fqn,
            ACCOUNT_NAME AS display_name,
            OBJECT_CONSTRUCT('source_table', 'CURATED_DEV.SALESFORCE.DIM_ACCOUNT', 'account_id', ACCOUNT_ID) AS properties
        FROM CURATED_DEV.SALESFORCE.DIM_ACCOUNT
    ) AS src
    ON tgt.node_id = src.node_id
    WHEN MATCHED THEN UPDATE SET tgt.display_name = src.display_name, tgt.properties = src.properties
    WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
        VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

    -- PATIENT nodes from FHIR DIM_PATIENT
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
    USING (
        SELECT
            'BIZ_PAT_' || MD5(PATIENT_ID) AS node_id,
            'PATIENT' AS node_type,
            'BUSINESS' AS layer,
            'FHIR' AS source_system,
            PATIENT_ID AS fqn,
            COALESCE(FIRST_NAME || ' ' || LAST_NAME, PATIENT_ID) AS display_name,
            OBJECT_CONSTRUCT('source_table', 'CURATED_DEV.FHIR.DIM_PATIENT', 'patient_id', PATIENT_ID) AS properties
        FROM CURATED_DEV.FHIR.DIM_PATIENT
    ) AS src
    ON tgt.node_id = src.node_id
    WHEN MATCHED THEN UPDATE SET tgt.display_name = src.display_name, tgt.properties = src.properties
    WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
        VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

    -- EMPLOYEE nodes from Workday DIM_WORKER
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
    USING (
        SELECT
            'BIZ_EMP_' || MD5(WORKER_ID) AS node_id,
            'EMPLOYEE' AS node_type,
            'BUSINESS' AS layer,
            'WORKDAY' AS source_system,
            WORKER_ID AS fqn,
            COALESCE(FIRST_NAME || ' ' || LAST_NAME, WORKER_ID) AS display_name,
            OBJECT_CONSTRUCT('source_table', 'CURATED_DEV.WORKDAY.DIM_WORKER', 'worker_id', WORKER_ID) AS properties
        FROM CURATED_DEV.WORKDAY.DIM_WORKER
    ) AS src
    ON tgt.node_id = src.node_id
    WHEN MATCHED THEN UPDATE SET tgt.display_name = src.display_name, tgt.properties = src.properties
    WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
        VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

    -- PRODUCT nodes from SAP DIM_MATERIAL
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
    USING (
        SELECT
            'BIZ_PROD_' || MD5(MATERIAL_ID) AS node_id,
            'PRODUCT' AS node_type,
            'BUSINESS' AS layer,
            'SAP' AS source_system,
            MATERIAL_ID AS fqn,
            MATERIAL_NAME AS display_name,
            OBJECT_CONSTRUCT('source_table', 'CURATED_DEV.SAP.DIM_MATERIAL', 'material_id', MATERIAL_ID) AS properties
        FROM CURATED_DEV.SAP.DIM_MATERIAL
    ) AS src
    ON tgt.node_id = src.node_id
    WHEN MATCHED THEN UPDATE SET tgt.display_name = src.display_name, tgt.properties = src.properties
    WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
        VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

    -- INCIDENT nodes from ServiceNow DIM_INCIDENT
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
    USING (
        SELECT
            'BIZ_INC_' || MD5(INCIDENT_ID) AS node_id,
            'INCIDENT' AS node_type,
            'BUSINESS' AS layer,
            'SERVICENOW' AS source_system,
            INCIDENT_ID AS fqn,
            SHORT_DESCRIPTION AS display_name,
            OBJECT_CONSTRUCT('source_table', 'CURATED_DEV.SERVICENOW.DIM_INCIDENT', 'incident_id', INCIDENT_ID) AS properties
        FROM CURATED_DEV.SERVICENOW.DIM_INCIDENT
    ) AS src
    ON tgt.node_id = src.node_id
    WHEN MATCHED THEN UPDATE SET tgt.display_name = src.display_name, tgt.properties = src.properties
    WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
        VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

    -- Count business nodes
    SELECT COUNT(*) INTO :v_node_count
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
    WHERE layer = 'BUSINESS';

    RETURN 'Business nodes populated: ' || :v_node_count || ' total business nodes';
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 4: POPULATE BUSINESS EDGES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_POPULATE_BUSINESS_EDGES()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_edge_count INTEGER DEFAULT 0;
BEGIN
    -- CUSTOMER → ORDER edges (PURCHASES) from SAP FACT_SALES_ORDER
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT DISTINCT
            'EDGE_' || MD5(
                'BIZ_CUST_' || MD5(CUSTOMER_ID) ||
                'BIZ_ORD_' || MD5(ORDER_ID) ||
                'PURCHASES'
            ) AS edge_id,
            'BIZ_CUST_' || MD5(CUSTOMER_ID) AS source_node_id,
            'BIZ_ORD_' || MD5(ORDER_ID) AS target_node_id,
            'PURCHASES' AS edge_type,
            'BUSINESS' AS layer,
            1.0 AS weight
        FROM CURATED_DEV.SAP.FACT_SALES_ORDER
        WHERE CUSTOMER_ID IS NOT NULL
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    -- PATIENT → ENCOUNTER edges (HAS_ENCOUNTER) from FHIR FACT_ENCOUNTER
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT DISTINCT
            'EDGE_' || MD5(
                'BIZ_PAT_' || MD5(PATIENT_ID) ||
                'BIZ_ENC_' || MD5(ENCOUNTER_ID) ||
                'HAS_ENCOUNTER'
            ) AS edge_id,
            'BIZ_PAT_' || MD5(PATIENT_ID) AS source_node_id,
            'BIZ_ENC_' || MD5(ENCOUNTER_ID) AS target_node_id,
            'HAS_ENCOUNTER' AS edge_type,
            'BUSINESS' AS layer,
            1.0 AS weight
        FROM CURATED_DEV.FHIR.FACT_ENCOUNTER
        WHERE PATIENT_ID IS NOT NULL
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    -- EMPLOYEE → ORG edges (WORKS_FOR) from Workday DIM_WORKER
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT DISTINCT
            'EDGE_' || MD5(
                'BIZ_EMP_' || MD5(WORKER_ID) ||
                'BIZ_ORG_' || MD5(DEPARTMENT) ||
                'WORKS_FOR'
            ) AS edge_id,
            'BIZ_EMP_' || MD5(WORKER_ID) AS source_node_id,
            'BIZ_ORG_' || MD5(DEPARTMENT) AS target_node_id,
            'WORKS_FOR' AS edge_type,
            'BUSINESS' AS layer,
            1.0 AS weight
        FROM CURATED_DEV.WORKDAY.DIM_WORKER
        WHERE DEPARTMENT IS NOT NULL
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    -- Count business edges
    SELECT COUNT(*) INTO :v_edge_count
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
    WHERE layer = 'BUSINESS';

    RETURN 'Business edges populated: ' || :v_edge_count || ' total business edges';
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 5: POPULATE CROSS-LAYER EDGES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_POPULATE_CROSS_EDGES()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_edge_count INTEGER DEFAULT 0;
BEGIN
    -- CUSTOMER node ↔ DIM_ACCOUNT table node
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT
            'EDGE_' || MD5(
                'BIZ_CUST_' || MD5(ACCOUNT_ID) ||
                'META_' || MD5('DCA_DEMO.SALESFORCE.DIM_ACCOUNT') ||
                'SOURCED_FROM'
            ) AS edge_id,
            'BIZ_CUST_' || MD5(ACCOUNT_ID) AS source_node_id,
            'META_' || MD5('DCA_DEMO.SALESFORCE.DIM_ACCOUNT') AS target_node_id,
            'SOURCED_FROM' AS edge_type,
            'CROSS' AS layer,
            1.0 AS weight
        FROM CURATED_DEV.SALESFORCE.DIM_ACCOUNT
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    -- PATIENT node ↔ DIM_PATIENT table node
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT
            'EDGE_' || MD5(
                'BIZ_PAT_' || MD5(PATIENT_ID) ||
                'META_' || MD5('DCA_DEMO.FHIR.DIM_PATIENT') ||
                'SOURCED_FROM'
            ) AS edge_id,
            'BIZ_PAT_' || MD5(PATIENT_ID) AS source_node_id,
            'META_' || MD5('DCA_DEMO.FHIR.DIM_PATIENT') AS target_node_id,
            'SOURCED_FROM' AS edge_type,
            'CROSS' AS layer,
            1.0 AS weight
        FROM CURATED_DEV.FHIR.DIM_PATIENT
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    -- EMPLOYEE node ↔ DIM_WORKER table node
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT
            'EDGE_' || MD5(
                'BIZ_EMP_' || MD5(WORKER_ID) ||
                'META_' || MD5('DCA_DEMO.WORKDAY.DIM_WORKER') ||
                'SOURCED_FROM'
            ) AS edge_id,
            'BIZ_EMP_' || MD5(WORKER_ID) AS source_node_id,
            'META_' || MD5('DCA_DEMO.WORKDAY.DIM_WORKER') AS target_node_id,
            'SOURCED_FROM' AS edge_type,
            'CROSS' AS layer,
            1.0 AS weight
        FROM CURATED_DEV.WORKDAY.DIM_WORKER
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    -- Count cross edges
    SELECT COUNT(*) INTO :v_edge_count
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
    WHERE layer = 'CROSS';

    RETURN 'Cross-layer edges populated: ' || :v_edge_count || ' total cross edges';
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 6: REFRESH GRAPH (ORCHESTRATOR)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_REFRESH_GRAPH()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_result_metadata_nodes VARCHAR;
    v_result_metadata_edges VARCHAR;
    v_result_business_nodes VARCHAR;
    v_result_business_edges VARCHAR;
    v_result_cross_edges VARCHAR;
    v_total_nodes INTEGER;
    v_total_edges INTEGER;
BEGIN
    -- Truncate all tables for a clean refresh
    TRUNCATE TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES;
    TRUNCATE TABLE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES;

    -- Populate in order
    CALL DCA_DEMO.GOVERNANCE.SP_POPULATE_METADATA_NODES() INTO :v_result_metadata_nodes;
    CALL DCA_DEMO.GOVERNANCE.SP_POPULATE_METADATA_EDGES() INTO :v_result_metadata_edges;
    CALL DCA_DEMO.GOVERNANCE.SP_POPULATE_BUSINESS_NODES() INTO :v_result_business_nodes;
    CALL DCA_DEMO.GOVERNANCE.SP_POPULATE_BUSINESS_EDGES() INTO :v_result_business_edges;
    CALL DCA_DEMO.GOVERNANCE.SP_POPULATE_CROSS_EDGES() INTO :v_result_cross_edges;

    -- Get totals
    SELECT COUNT(*) INTO :v_total_nodes FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES;
    SELECT COUNT(*) INTO :v_total_edges FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES;

    -- Insert snapshot record
    INSERT INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SNAPSHOTS (node_count, edge_count, metadata)
    VALUES (
        :v_total_nodes,
        :v_total_edges,
        OBJECT_CONSTRUCT(
            'metadata_nodes', :v_result_metadata_nodes,
            'metadata_edges', :v_result_metadata_edges,
            'business_nodes', :v_result_business_nodes,
            'business_edges', :v_result_business_edges,
            'cross_edges', :v_result_cross_edges
        )
    );

    RETURN 'Graph refresh complete. Nodes: ' || :v_total_nodes || ', Edges: ' || :v_total_edges;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_POPULATE_METADATA_NODES() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_POPULATE_METADATA_EDGES() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_POPULATE_BUSINESS_NODES() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_POPULATE_BUSINESS_EDGES() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_POPULATE_CROSS_EDGES() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_REFRESH_GRAPH() TO ROLE ONTOLOGY_ADMIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'Graph population procedures created successfully' AS status;

SHOW PROCEDURES IN SCHEMA DCA_DEMO.GOVERNANCE
    LIKE 'SP_POPULATE%';

SHOW PROCEDURES IN SCHEMA DCA_DEMO.GOVERNANCE
    LIKE 'SP_REFRESH%';
