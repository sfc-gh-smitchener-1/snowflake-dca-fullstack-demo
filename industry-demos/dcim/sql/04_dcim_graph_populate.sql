-- ============================================================================
-- DCIM KNOWLEDGE GRAPH — INFRASTRUCTURE GRAPH POPULATION
-- ============================================================================
-- Extends the base Ontology Knowledge Graph with DCIM infrastructure nodes
-- and relationship edges for data center topology analysis.
--
-- Prerequisites: scripts 11-15 deployed, DCIM data loaded and curated
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE DCA_DEMO;
USE SCHEMA GOVERNANCE;
USE WAREHOUSE COMPUTE_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE: SP_DCIM_POPULATE_INFRASTRUCTURE_GRAPH
-- ═══════════════════════════════════════════════════════════════════════════
-- Populates DATA_CENTER, HALL, RACK, SWITCH, PORT, and INCIDENT nodes
-- along with containment hierarchy and incident relationship edges.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_DCIM_POPULATE_INFRASTRUCTURE_GRAPH()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_dc_nodes INTEGER DEFAULT 0;
    v_hall_nodes INTEGER DEFAULT 0;
    v_rack_nodes INTEGER DEFAULT 0;
    v_switch_nodes INTEGER DEFAULT 0;
    v_port_nodes INTEGER DEFAULT 0;
    v_incident_nodes INTEGER DEFAULT 0;
    v_hierarchy_edges INTEGER DEFAULT 0;
    v_incident_edges INTEGER DEFAULT 0;
    v_cross_edges INTEGER DEFAULT 0;
    v_table_exists INTEGER DEFAULT 0;
BEGIN

    -- ── 1. DATA_CENTER nodes ───────────────────────────────────────────────
    SELECT COUNT(*) INTO :v_table_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'SERVICENOW' AND table_name = 'DIM_DATA_CENTERS';

    IF (:v_table_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT
                'DC_DC_' || MD5(DATA_CENTER_ID) AS node_id,
                'DATA_CENTER' AS node_type,
                'BUSINESS' AS layer,
                'SERVICENOW' AS source_system,
                DATA_CENTER_ID AS fqn,
                COALESCE(DC_NAME, 'Unknown') || ' (' || COALESCE(REGION, 'Unknown') || ')' AS display_name,
                OBJECT_CONSTRUCT(
                    'data_center_id', DATA_CENTER_ID,
                    'dc_name', DC_NAME,
                    'region', REGION,
                    'tier', TIER,
                    'power_capacity_mw', POWER_CAPACITY_MW,
                    'sla_tier', SLA_TIER,
                    'source_table', 'CURATED_DEV.SERVICENOW.DIM_DATA_CENTERS'
                ) AS properties
            FROM CURATED_DEV.SERVICENOW.DIM_DATA_CENTERS
            WHERE DATA_CENTER_ID IS NOT NULL
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        SELECT COUNT(*) INTO :v_dc_nodes
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        WHERE node_type = 'DATA_CENTER' AND node_id LIKE 'DC_DC_%';
    END IF;

    -- ── 2. HALL nodes ──────────────────────────────────────────────────────
    LET v_hall_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_hall_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'SERVICENOW' AND table_name = 'DIM_HALLS';

    IF (:v_hall_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT
                'DC_HALL_' || MD5(HALL_ID) AS node_id,
                'HALL' AS node_type,
                'BUSINESS' AS layer,
                'SERVICENOW' AS source_system,
                HALL_ID AS fqn,
                COALESCE(HALL_NAME, HALL_ID) AS display_name,
                OBJECT_CONSTRUCT(
                    'hall_id', HALL_ID,
                    'hall_name', HALL_NAME,
                    'data_center_id', DATA_CENTER_ID,
                    'floor_area_sqft', FLOOR_AREA_SQFT,
                    'cooling_capacity_kw', COOLING_CAPACITY_KW,
                    'source_table', 'CURATED_DEV.SERVICENOW.DIM_HALLS'
                ) AS properties
            FROM CURATED_DEV.SERVICENOW.DIM_HALLS
            WHERE HALL_ID IS NOT NULL
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        SELECT COUNT(*) INTO :v_hall_nodes
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        WHERE node_type = 'HALL' AND node_id LIKE 'DC_HALL_%';
    END IF;

    -- ── 3. RACK nodes ──────────────────────────────────────────────────────
    LET v_rack_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_rack_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'SERVICENOW' AND table_name = 'DIM_RACKS';

    IF (:v_rack_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT
                'DC_RACK_' || MD5(RACK_ID) AS node_id,
                'RACK' AS node_type,
                'BUSINESS' AS layer,
                'SERVICENOW' AS source_system,
                RACK_ID AS fqn,
                COALESCE(RACK_NAME, RACK_ID) AS display_name,
                OBJECT_CONSTRUCT(
                    'rack_id', RACK_ID,
                    'rack_name', RACK_NAME,
                    'hall_id', HALL_ID,
                    'power_allocation_kw', POWER_ALLOCATION_KW,
                    'current_load_kw', CURRENT_LOAD_KW,
                    'rack_units', RACK_UNITS,
                    'source_table', 'CURATED_DEV.SERVICENOW.DIM_RACKS'
                ) AS properties
            FROM CURATED_DEV.SERVICENOW.DIM_RACKS
            WHERE RACK_ID IS NOT NULL
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        SELECT COUNT(*) INTO :v_rack_nodes
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        WHERE node_type = 'RACK' AND node_id LIKE 'DC_RACK_%';
    END IF;

    -- ── 4. SWITCH nodes ────────────────────────────────────────────────────
    LET v_switch_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_switch_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'SERVICENOW' AND table_name = 'DIM_SWITCHES';

    IF (:v_switch_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT
                'DC_SW_' || MD5(SWITCH_ID) AS node_id,
                'SWITCH' AS node_type,
                'BUSINESS' AS layer,
                'SERVICENOW' AS source_system,
                SWITCH_ID AS fqn,
                COALESCE(MODEL, 'Unknown') || ' [' || COALESCE(SWITCH_ROLE, 'Unknown') || ']' AS display_name,
                OBJECT_CONSTRUCT(
                    'switch_id', SWITCH_ID,
                    'model', MODEL,
                    'switch_role', SWITCH_ROLE,
                    'firmware_version', FIRMWARE_VERSION,
                    'rack_id', RACK_ID,
                    'install_date', INSTALL_DATE,
                    'source_table', 'CURATED_DEV.SERVICENOW.DIM_SWITCHES'
                ) AS properties
            FROM CURATED_DEV.SERVICENOW.DIM_SWITCHES
            WHERE SWITCH_ID IS NOT NULL
              AND _IS_CURRENT = TRUE
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        SELECT COUNT(*) INTO :v_switch_nodes
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        WHERE node_type = 'SWITCH' AND node_id LIKE 'DC_SW_%';
    END IF;

    -- ── 5. PORT nodes ──────────────────────────────────────────────────────
    LET v_port_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_port_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'SERVICENOW' AND table_name = 'FACT_PORTS';

    IF (:v_port_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT
                'DC_PORT_' || MD5(PORT_ID) AS node_id,
                'PORT' AS node_type,
                'BUSINESS' AS layer,
                'SERVICENOW' AS source_system,
                PORT_ID AS fqn,
                COALESCE(PORT_NAME, PORT_ID) || ' (' || COALESCE(SPEED, 'Unknown') || ')' AS display_name,
                OBJECT_CONSTRUCT(
                    'port_id', PORT_ID,
                    'port_name', PORT_NAME,
                    'switch_id', SWITCH_ID,
                    'speed', SPEED,
                    'connected_device_type', CONNECTED_DEVICE_TYPE,
                    'source_table', 'CURATED_DEV.SERVICENOW.FACT_PORTS'
                ) AS properties
            FROM CURATED_DEV.SERVICENOW.FACT_PORTS
            WHERE PORT_ID IS NOT NULL
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        SELECT COUNT(*) INTO :v_port_nodes
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        WHERE node_type = 'PORT' AND node_id LIKE 'DC_PORT_%';
    END IF;

    -- ── 6. INCIDENT nodes ──────────────────────────────────────────────────
    LET v_inc_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_inc_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'SERVICENOW' AND table_name = 'FACT_INCIDENTS';

    IF (:v_inc_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT
                'DC_INC_' || MD5(INCIDENT_ID) AS node_id,
                'INCIDENT' AS node_type,
                'BUSINESS' AS layer,
                'SERVICENOW' AS source_system,
                INCIDENT_ID AS fqn,
                COALESCE(INCIDENT_NUMBER, INCIDENT_ID) || ' [' || COALESCE(PRIORITY, 'P4') || ']' AS display_name,
                OBJECT_CONSTRUCT(
                    'incident_id', INCIDENT_ID,
                    'incident_number', INCIDENT_NUMBER,
                    'priority', PRIORITY,
                    'category', CATEGORY,
                    'status', STATUS,
                    'resolution_time_hours', RESOLUTION_TIME_HOURS,
                    'assigned_technician_id', ASSIGNED_TECHNICIAN_ID,
                    'switch_id', SWITCH_ID,
                    'source_table', 'CURATED_DEV.SERVICENOW.FACT_INCIDENTS'
                ) AS properties
            FROM CURATED_DEV.SERVICENOW.FACT_INCIDENTS
            WHERE INCIDENT_ID IS NOT NULL
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        SELECT COUNT(*) INTO :v_incident_nodes
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        WHERE node_type = 'INCIDENT' AND node_id LIKE 'DC_INC_%';
    END IF;

    -- ── 7. HIERARCHY EDGES ─────────────────────────────────────────────────

    -- HALL_IN_DC: hall → data_center
    IF (:v_hall_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT
                'DC_HIDC_' || MD5(HALL_ID) AS edge_id,
                'DC_HALL_' || MD5(HALL_ID) AS source_node_id,
                'DC_DC_' || MD5(DATA_CENTER_ID) AS target_node_id,
                'HALL_IN_DC' AS edge_type,
                'BUSINESS' AS layer,
                1.0 AS weight
            FROM CURATED_DEV.SERVICENOW.DIM_HALLS
            WHERE HALL_ID IS NOT NULL AND DATA_CENTER_ID IS NOT NULL
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);
    END IF;

    -- RACK_IN_HALL: rack → hall
    IF (:v_rack_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT
                'DC_RIH_' || MD5(RACK_ID) AS edge_id,
                'DC_RACK_' || MD5(RACK_ID) AS source_node_id,
                'DC_HALL_' || MD5(HALL_ID) AS target_node_id,
                'RACK_IN_HALL' AS edge_type,
                'BUSINESS' AS layer,
                1.0 AS weight
            FROM CURATED_DEV.SERVICENOW.DIM_RACKS
            WHERE RACK_ID IS NOT NULL AND HALL_ID IS NOT NULL
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);
    END IF;

    -- SWITCH_IN_RACK: switch → rack
    IF (:v_switch_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT
                'DC_SIR_' || MD5(SWITCH_ID) AS edge_id,
                'DC_SW_' || MD5(SWITCH_ID) AS source_node_id,
                'DC_RACK_' || MD5(RACK_ID) AS target_node_id,
                'SWITCH_IN_RACK' AS edge_type,
                'BUSINESS' AS layer,
                1.0 AS weight
            FROM CURATED_DEV.SERVICENOW.DIM_SWITCHES
            WHERE SWITCH_ID IS NOT NULL AND RACK_ID IS NOT NULL
              AND _IS_CURRENT = TRUE
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);
    END IF;

    -- PORT_ON_SWITCH: port → switch
    IF (:v_port_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT
                'DC_POS_' || MD5(PORT_ID) AS edge_id,
                'DC_PORT_' || MD5(PORT_ID) AS source_node_id,
                'DC_SW_' || MD5(SWITCH_ID) AS target_node_id,
                'PORT_ON_SWITCH' AS edge_type,
                'BUSINESS' AS layer,
                1.0 AS weight
            FROM CURATED_DEV.SERVICENOW.FACT_PORTS
            WHERE PORT_ID IS NOT NULL AND SWITCH_ID IS NOT NULL
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);
    END IF;

    SELECT COUNT(*) INTO :v_hierarchy_edges
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
    WHERE edge_id LIKE 'DC_HIDC_%'
       OR edge_id LIKE 'DC_RIH_%'
       OR edge_id LIKE 'DC_SIR_%'
       OR edge_id LIKE 'DC_POS_%';

    -- ── 8. INCIDENT_AFFECTS_SWITCH: incident → switch ──────────────────────
    IF (:v_inc_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT
                'DC_IAS_' || MD5(INCIDENT_ID) AS edge_id,
                'DC_INC_' || MD5(INCIDENT_ID) AS source_node_id,
                'DC_SW_' || MD5(SWITCH_ID) AS target_node_id,
                'INCIDENT_AFFECTS_SWITCH' AS edge_type,
                'BUSINESS' AS layer,
                CASE PRIORITY
                    WHEN 'P1' THEN 1.0
                    WHEN 'P2' THEN 0.75
                    WHEN 'P3' THEN 0.5
                    ELSE 0.25
                END AS weight,
                OBJECT_CONSTRUCT(
                    'priority', PRIORITY,
                    'category', CATEGORY
                ) AS properties
            FROM CURATED_DEV.SERVICENOW.FACT_INCIDENTS
            WHERE INCIDENT_ID IS NOT NULL AND SWITCH_ID IS NOT NULL
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN MATCHED THEN UPDATE SET
            tgt.weight = src.weight,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight, properties)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight, src.properties);

        SELECT COUNT(*) INTO :v_incident_edges
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
        WHERE edge_type = 'INCIDENT_AFFECTS_SWITCH' AND edge_id LIKE 'DC_IAS_%';
    END IF;

    -- ── 9. CROSS-LAYER STORED_IN Edges ─────────────────────────────────────

    -- SWITCH nodes → DIM_SWITCHES table metadata node
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT DISTINCT
            'DC_EDGE_' || MD5(
                n.node_id ||
                'META_' || MD5('CURATED_DEV.SERVICENOW.DIM_SWITCHES') ||
                'STORED_IN'
            ) AS edge_id,
            n.node_id AS source_node_id,
            'META_' || MD5('CURATED_DEV.SERVICENOW.DIM_SWITCHES') AS target_node_id,
            'STORED_IN' AS edge_type,
            'CROSS' AS layer,
            1.0 AS weight
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
        WHERE n.node_id LIKE 'DC_SW_%'
          AND n.node_type = 'SWITCH'
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    -- INCIDENT nodes → FACT_INCIDENTS table metadata node
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT DISTINCT
            'DC_EDGE_' || MD5(
                n.node_id ||
                'META_' || MD5('CURATED_DEV.SERVICENOW.FACT_INCIDENTS') ||
                'STORED_IN'
            ) AS edge_id,
            n.node_id AS source_node_id,
            'META_' || MD5('CURATED_DEV.SERVICENOW.FACT_INCIDENTS') AS target_node_id,
            'STORED_IN' AS edge_type,
            'CROSS' AS layer,
            1.0 AS weight
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
        WHERE n.node_id LIKE 'DC_INC_%'
          AND n.node_type = 'INCIDENT'
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    SELECT COUNT(*) INTO :v_cross_edges
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
    WHERE edge_id LIKE 'DC_EDGE_%' AND layer = 'CROSS';

    -- ── Final summary ─────────────────────────────────────────────────────
    RETURN 'DCIM Infrastructure Graph populated. Nodes — DCs: ' || :v_dc_nodes ||
           ', Halls: ' || :v_hall_nodes ||
           ', Racks: ' || :v_rack_nodes ||
           ', Switches: ' || :v_switch_nodes ||
           ', Ports: ' || :v_port_nodes ||
           ', Incidents: ' || :v_incident_nodes ||
           '. Edges — Hierarchy: ' || :v_hierarchy_edges ||
           ', Incidents: ' || :v_incident_edges ||
           ', Cross-layer: ' || :v_cross_edges;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'DCIM infrastructure graph population procedure created' AS status;

SELECT node_type, COUNT(*) AS node_count
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
WHERE node_id LIKE 'DC_%'
  AND source_system = 'SERVICENOW'
GROUP BY node_type
ORDER BY node_type;

SELECT edge_type, layer, COUNT(*) AS edge_count
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
WHERE edge_id LIKE 'DC_%'
GROUP BY edge_type, layer
ORDER BY layer, edge_type;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_DCIM_POPULATE_INFRASTRUCTURE_GRAPH() TO ROLE ONTOLOGY_ADMIN;
