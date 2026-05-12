-- ============================================================================
-- DCIM KNOWLEDGE GRAPH — SIEMENS ACQUIRED PORTFOLIO GRAPH POPULATION
-- ============================================================================
-- Extends the DCIM Knowledge Graph with nodes from the acquired Siemens
-- Desigo CC / MindSphere portfolio (2,000 data centers). Also creates
-- SAME_AS edges for entity resolution between Siemens racks and ServiceNow racks.
--
-- The Acquisition Story: A hyperscaler acquired a competitor running Siemens DCIM.
-- 2,000 data centers now need to be integrated into the unified governance platform.
-- Entity resolution identifies "same physical rack, different system ID" matches.
--
-- Prerequisites: 04_dcim_graph_populate.sql deployed, Siemens data loaded
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE DCA_DEMO;
USE SCHEMA GOVERNANCE;
USE WAREHOUSE COMPUTE_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE: SP_DCIM_POPULATE_SIEMENS_GRAPH
-- ═══════════════════════════════════════════════════════════════════════════
-- Populates FACILITY, ZONE, POWER_DISTRIBUTION, COOLING_LOOP, RACK, and
-- MAINTENANCE_ORDER nodes along with containment hierarchy edges and
-- cross-system entity resolution (SAME_AS / CANDIDATE_SAME_AS) edges.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_DCIM_POPULATE_SIEMENS_GRAPH()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_facility_nodes INTEGER DEFAULT 0;
    v_zone_nodes INTEGER DEFAULT 0;
    v_pdu_nodes INTEGER DEFAULT 0;
    v_cooling_nodes INTEGER DEFAULT 0;
    v_rack_nodes INTEGER DEFAULT 0;
    v_mo_nodes INTEGER DEFAULT 0;
    v_hierarchy_edges INTEGER DEFAULT 0;
    v_mo_edges INTEGER DEFAULT 0;
    v_same_as_edges INTEGER DEFAULT 0;
    v_candidate_edges INTEGER DEFAULT 0;
    v_table_exists INTEGER DEFAULT 0;
BEGIN

    -- ── 1. FACILITY nodes ───────────────────────────────────────────────
    SELECT COUNT(*) INTO :v_table_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'SIEMENS_DCIM' AND table_name = 'DIM_FACILITY';

    IF (:v_table_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT
                'SM_FAC_' || MD5(FACILITY_ID) AS node_id,
                'FACILITY' AS node_type,
                'BUSINESS' AS layer,
                'SIEMENS_DCIM' AS source_system,
                FACILITY_ID AS fqn,
                COALESCE(FACILITY_NAME, 'Unknown') || ' (' || COALESCE(COUNTRY, 'Unknown') || ')' AS display_name,
                OBJECT_CONSTRUCT(
                    'facility_id', FACILITY_ID,
                    'building_type', BUILDING_TYPE,
                    'tier_level', TIER_LEVEL,
                    'total_power_mw', TOTAL_POWER_MW,
                    'acquisition_date', ACQUISITION_DATE,
                    'source_table', 'CURATED_DEV.SIEMENS_DCIM.DIM_FACILITY'
                ) AS properties
            FROM CURATED_DEV.SIEMENS_DCIM.DIM_FACILITY
            WHERE FACILITY_ID IS NOT NULL
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        SELECT COUNT(*) INTO :v_facility_nodes
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        WHERE node_type = 'FACILITY' AND node_id LIKE 'SM_FAC_%';
    END IF;

    -- ── 2. ZONE nodes ───────────────────────────────────────────────────
    LET v_zone_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_zone_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'SIEMENS_DCIM' AND table_name = 'DIM_ZONE';

    IF (:v_zone_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT
                'SM_ZONE_' || MD5(ZONE_ID) AS node_id,
                'ZONE' AS node_type,
                'BUSINESS' AS layer,
                'SIEMENS_DCIM' AS source_system,
                ZONE_ID AS fqn,
                COALESCE(ZONE_NAME, ZONE_ID) || ' [' || COALESCE(ZONE_TYPE, 'Unknown') || ']' AS display_name,
                OBJECT_CONSTRUCT(
                    'zone_type', ZONE_TYPE,
                    'cooling_type', COOLING_TYPE,
                    'target_temp', TARGET_TEMP_CELSIUS,
                    'area_sqm', AREA_SQM,
                    'source_table', 'CURATED_DEV.SIEMENS_DCIM.DIM_ZONE'
                ) AS properties
            FROM CURATED_DEV.SIEMENS_DCIM.DIM_ZONE
            WHERE ZONE_ID IS NOT NULL
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        SELECT COUNT(*) INTO :v_zone_nodes
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        WHERE node_type = 'ZONE' AND node_id LIKE 'SM_ZONE_%';
    END IF;

    -- ── 3. PDU nodes ────────────────────────────────────────────────────
    LET v_pdu_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_pdu_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'SIEMENS_DCIM' AND table_name = 'DIM_POWER_DISTRIBUTION_UNIT';

    IF (:v_pdu_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT
                'SM_PDU_' || MD5(PDU_ID) AS node_id,
                'POWER_DISTRIBUTION' AS node_type,
                'BUSINESS' AS layer,
                'SIEMENS_DCIM' AS source_system,
                PDU_ID AS fqn,
                COALESCE(EQUIPMENT_TYPE, 'PDU') || ' - ' || COALESCE(MODEL, 'Unknown') AS display_name,
                OBJECT_CONSTRUCT(
                    'capacity_kva', CAPACITY_KVA,
                    'current_load_pct', CURRENT_LOAD_PCT,
                    'redundancy', REDUNDANCY,
                    'source_table', 'CURATED_DEV.SIEMENS_DCIM.DIM_POWER_DISTRIBUTION_UNIT'
                ) AS properties
            FROM CURATED_DEV.SIEMENS_DCIM.DIM_POWER_DISTRIBUTION_UNIT
            WHERE PDU_ID IS NOT NULL
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        SELECT COUNT(*) INTO :v_pdu_nodes
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        WHERE node_type = 'POWER_DISTRIBUTION' AND node_id LIKE 'SM_PDU_%';
    END IF;

    -- ── 4. COOLING_LOOP nodes ───────────────────────────────────────────
    LET v_cool_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_cool_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'SIEMENS_DCIM' AND table_name = 'DIM_COOLING_LOOP';

    IF (:v_cool_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT
                'SM_COOL_' || MD5(LOOP_ID) AS node_id,
                'COOLING_LOOP' AS node_type,
                'BUSINESS' AS layer,
                'SIEMENS_DCIM' AS source_system,
                LOOP_ID AS fqn,
                COALESCE(LOOP_TYPE, 'Unknown') || ' (' || COALESCE(CAST(CAPACITY_KW AS VARCHAR), '?') || 'kW)' AS display_name,
                OBJECT_CONSTRUCT(
                    'efficiency_cop', EFFICIENCY_COP,
                    'supply_temp', SUPPLY_TEMP_CELSIUS,
                    'return_temp', RETURN_TEMP_CELSIUS,
                    'refrigerant_type', REFRIGERANT_TYPE,
                    'source_table', 'CURATED_DEV.SIEMENS_DCIM.DIM_COOLING_LOOP'
                ) AS properties
            FROM CURATED_DEV.SIEMENS_DCIM.DIM_COOLING_LOOP
            WHERE LOOP_ID IS NOT NULL
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        SELECT COUNT(*) INTO :v_cooling_nodes
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        WHERE node_type = 'COOLING_LOOP' AND node_id LIKE 'SM_COOL_%';
    END IF;

    -- ── 5. RACK_INVENTORY nodes ─────────────────────────────────────────
    LET v_rack_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_rack_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'SIEMENS_DCIM' AND table_name = 'DIM_RACK_INVENTORY';

    IF (:v_rack_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT
                'SM_RACK_' || MD5(SIEMENS_RACK_ID) AS node_id,
                'RACK' AS node_type,
                'BUSINESS' AS layer,
                'SIEMENS_DCIM' AS source_system,
                SIEMENS_RACK_ID AS fqn,
                'Rack R' || COALESCE(ROW_NUMBER, '?') || '-' || COALESCE(CAST(POSITION_IN_ROW AS VARCHAR), '?') AS display_name,
                OBJECT_CONSTRUCT(
                    'u_capacity', U_CAPACITY,
                    'u_used', U_USED,
                    'power_allocation_kw', POWER_ALLOCATION_KW,
                    'customer_name', CUSTOMER_NAME,
                    'servicenow_correlation_id', SERVICENOW_CORRELATION_ID,
                    'source_table', 'CURATED_DEV.SIEMENS_DCIM.DIM_RACK_INVENTORY'
                ) AS properties
            FROM CURATED_DEV.SIEMENS_DCIM.DIM_RACK_INVENTORY
            WHERE SIEMENS_RACK_ID IS NOT NULL
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        SELECT COUNT(*) INTO :v_rack_nodes
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        WHERE node_type = 'RACK' AND node_id LIKE 'SM_RACK_%';
    END IF;

    -- ── 6. MAINTENANCE_ORDER nodes ──────────────────────────────────────
    LET v_mo_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_mo_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'SIEMENS_DCIM' AND table_name = 'FACT_MAINTENANCE_ORDER';

    IF (:v_mo_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT
                'SM_MO_' || MD5(ORDER_ID) AS node_id,
                'MAINTENANCE_ORDER' AS node_type,
                'BUSINESS' AS layer,
                'SIEMENS_DCIM' AS source_system,
                ORDER_ID AS fqn,
                COALESCE(ORDER_TYPE, 'Unknown') || ' - P' || COALESCE(CAST(PRIORITY AS VARCHAR), '?') AS display_name,
                OBJECT_CONSTRUCT(
                    'equipment_type', EQUIPMENT_TYPE,
                    'status', STATUS,
                    'priority', PRIORITY,
                    'resolution_hours', RESOLUTION_HOURS,
                    'source_table', 'CURATED_DEV.SIEMENS_DCIM.FACT_MAINTENANCE_ORDER'
                ) AS properties
            FROM CURATED_DEV.SIEMENS_DCIM.FACT_MAINTENANCE_ORDER
            WHERE ORDER_ID IS NOT NULL
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        SELECT COUNT(*) INTO :v_mo_nodes
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        WHERE node_type = 'MAINTENANCE_ORDER' AND node_id LIKE 'SM_MO_%';
    END IF;

    -- ── 7. HIERARCHY EDGES ──────────────────────────────────────────────

    -- ZONE_IN_FACILITY: zone → facility
    IF (:v_zone_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT
                'SM_ZIF_' || MD5(ZONE_ID) AS edge_id,
                'SM_ZONE_' || MD5(ZONE_ID) AS source_node_id,
                'SM_FAC_' || MD5(FACILITY_ID) AS target_node_id,
                'ZONE_IN_FACILITY' AS edge_type,
                'BUSINESS' AS layer,
                1.0 AS weight
            FROM CURATED_DEV.SIEMENS_DCIM.DIM_ZONE
            WHERE ZONE_ID IS NOT NULL AND FACILITY_ID IS NOT NULL
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);
    END IF;

    -- PDU_IN_ZONE: pdu → zone
    IF (:v_pdu_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT
                'SM_PIZ_' || MD5(PDU_ID) AS edge_id,
                'SM_PDU_' || MD5(PDU_ID) AS source_node_id,
                'SM_ZONE_' || MD5(ZONE_ID) AS target_node_id,
                'PDU_IN_ZONE' AS edge_type,
                'BUSINESS' AS layer,
                1.0 AS weight
            FROM CURATED_DEV.SIEMENS_DCIM.DIM_POWER_DISTRIBUTION_UNIT
            WHERE PDU_ID IS NOT NULL AND ZONE_ID IS NOT NULL
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);
    END IF;

    -- COOLING_SERVES_ZONE: cooling_loop → zone
    IF (:v_cool_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT
                'SM_CSZ_' || MD5(LOOP_ID) AS edge_id,
                'SM_COOL_' || MD5(LOOP_ID) AS source_node_id,
                'SM_ZONE_' || MD5(ZONE_ID) AS target_node_id,
                'COOLING_SERVES_ZONE' AS edge_type,
                'BUSINESS' AS layer,
                1.0 AS weight
            FROM CURATED_DEV.SIEMENS_DCIM.DIM_COOLING_LOOP
            WHERE LOOP_ID IS NOT NULL AND ZONE_ID IS NOT NULL
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);
    END IF;

    -- RACK_IN_ZONE: rack → zone
    IF (:v_rack_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT
                'SM_RIZ_' || MD5(SIEMENS_RACK_ID) AS edge_id,
                'SM_RACK_' || MD5(SIEMENS_RACK_ID) AS source_node_id,
                'SM_ZONE_' || MD5(ZONE_ID) AS target_node_id,
                'RACK_IN_ZONE' AS edge_type,
                'BUSINESS' AS layer,
                1.0 AS weight
            FROM CURATED_DEV.SIEMENS_DCIM.DIM_RACK_INVENTORY
            WHERE SIEMENS_RACK_ID IS NOT NULL AND ZONE_ID IS NOT NULL
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);
    END IF;

    -- MO_AFFECTS_EQUIPMENT: maintenance_order → zone (linked via zone_id on the order)
    IF (:v_mo_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT
                'SM_MAE_' || MD5(ORDER_ID) AS edge_id,
                'SM_MO_' || MD5(ORDER_ID) AS source_node_id,
                'SM_ZONE_' || MD5(ZONE_ID) AS target_node_id,
                'MO_AFFECTS_EQUIPMENT' AS edge_type,
                'BUSINESS' AS layer,
                CASE PRIORITY
                    WHEN 1 THEN 1.0
                    WHEN 2 THEN 0.75
                    WHEN 3 THEN 0.5
                    ELSE 0.25
                END AS weight,
                OBJECT_CONSTRUCT(
                    'equipment_type', EQUIPMENT_TYPE,
                    'order_type', ORDER_TYPE,
                    'priority', PRIORITY
                ) AS properties
            FROM CURATED_DEV.SIEMENS_DCIM.FACT_MAINTENANCE_ORDER
            WHERE ORDER_ID IS NOT NULL AND ZONE_ID IS NOT NULL
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN MATCHED THEN UPDATE SET
            tgt.weight = src.weight,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight, properties)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight, src.properties);

        SELECT COUNT(*) INTO :v_mo_edges
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
        WHERE edge_type = 'MO_AFFECTS_EQUIPMENT' AND edge_id LIKE 'SM_MAE_%';
    END IF;

    SELECT COUNT(*) INTO :v_hierarchy_edges
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
    WHERE edge_id LIKE 'SM_ZIF_%'
       OR edge_id LIKE 'SM_PIZ_%'
       OR edge_id LIKE 'SM_CSZ_%'
       OR edge_id LIKE 'SM_RIZ_%';

    -- ── 8. CROSS-SYSTEM ENTITY RESOLUTION ───────────────────────────────

    -- SAME_AS: Siemens racks with a known ServiceNow correlation ID
    IF (:v_rack_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT
                'SM_SA_' || MD5(SIEMENS_RACK_ID) AS edge_id,
                'SM_RACK_' || MD5(SIEMENS_RACK_ID) AS source_node_id,
                'DC_RACK_' || MD5(SERVICENOW_CORRELATION_ID) AS target_node_id,
                'SAME_AS' AS edge_type,
                'CROSS' AS layer,
                1.0 AS weight,
                OBJECT_CONSTRUCT(
                    'match_method', 'MANUAL_CORRELATION',
                    'confidence', 1.0,
                    'siemens_rack_id', SIEMENS_RACK_ID,
                    'servicenow_rack_id', SERVICENOW_CORRELATION_ID
                ) AS properties
            FROM CURATED_DEV.SIEMENS_DCIM.DIM_RACK_INVENTORY
            WHERE SIEMENS_RACK_ID IS NOT NULL
              AND SERVICENOW_CORRELATION_ID IS NOT NULL
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN MATCHED THEN UPDATE SET
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight, properties)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight, src.properties);

        SELECT COUNT(*) INTO :v_same_as_edges
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
        WHERE edge_type = 'SAME_AS' AND edge_id LIKE 'SM_SA_%';

        -- CANDIDATE_SAME_AS: Fuzzy matching by u_capacity + power_allocation within same region
        -- For Siemens racks WITHOUT a servicenow_correlation_id, find ServiceNow racks
        -- with matching u_capacity (±2) and power_allocation_kw (±3) in overlapping regions.
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT
                'SM_CSA_' || MD5(sr.SIEMENS_RACK_ID || '_' || sn.RACK_ID) AS edge_id,
                'SM_RACK_' || MD5(sr.SIEMENS_RACK_ID) AS source_node_id,
                'DC_RACK_' || MD5(sn.RACK_ID) AS target_node_id,
                'CANDIDATE_SAME_AS' AS edge_type,
                'CROSS' AS layer,
                0.7 AS weight,
                OBJECT_CONSTRUCT(
                    'match_method', 'ATTRIBUTE_SIMILARITY',
                    'confidence', 0.7,
                    'siemens_rack_id', sr.SIEMENS_RACK_ID,
                    'servicenow_rack_id', sn.RACK_ID,
                    'siemens_u_capacity', sr.U_CAPACITY,
                    'servicenow_rack_units', sn.RACK_UNITS,
                    'siemens_power_kw', sr.POWER_ALLOCATION_KW,
                    'servicenow_power_kw', sn.POWER_ALLOCATION_KW
                ) AS properties
            FROM CURATED_DEV.SIEMENS_DCIM.DIM_RACK_INVENTORY sr
            INNER JOIN CURATED_DEV.SERVICENOW.DIM_RACK sn
                ON ABS(sr.U_CAPACITY - sn.RACK_UNITS) <= 2
               AND ABS(sr.POWER_ALLOCATION_KW - sn.POWER_ALLOCATION_KW) <= 3.0
            WHERE sr.SERVICENOW_CORRELATION_ID IS NULL
              AND sr.SIEMENS_RACK_ID IS NOT NULL
              AND sn.RACK_ID IS NOT NULL
            -- Limit to best candidate per Siemens rack (closest power match)
            QUALIFY ROW_NUMBER() OVER (
                PARTITION BY sr.SIEMENS_RACK_ID
                ORDER BY ABS(sr.POWER_ALLOCATION_KW - sn.POWER_ALLOCATION_KW)
            ) = 1
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN MATCHED THEN UPDATE SET
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight, properties)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight, src.properties);

        SELECT COUNT(*) INTO :v_candidate_edges
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
        WHERE edge_type = 'CANDIDATE_SAME_AS' AND edge_id LIKE 'SM_CSA_%';
    END IF;

    -- ── Final summary ──────────────────────────────────────────────────
    RETURN 'Siemens DCIM Graph populated. Nodes — Facilities: ' || :v_facility_nodes ||
           ', Zones: ' || :v_zone_nodes ||
           ', PDUs: ' || :v_pdu_nodes ||
           ', Cooling Loops: ' || :v_cooling_nodes ||
           ', Racks: ' || :v_rack_nodes ||
           ', Maintenance Orders: ' || :v_mo_nodes ||
           '. Edges — Hierarchy: ' || :v_hierarchy_edges ||
           ', Maintenance: ' || :v_mo_edges ||
           '. Entity Resolution — SAME_AS: ' || :v_same_as_edges ||
           ', CANDIDATE_SAME_AS: ' || :v_candidate_edges;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'DCIM Siemens graph population procedure created' AS status;

SELECT node_type, COUNT(*) AS node_count
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
WHERE node_id LIKE 'SM_%'
  AND source_system = 'SIEMENS_DCIM'
GROUP BY node_type
ORDER BY node_type;

SELECT edge_type, layer, COUNT(*) AS edge_count
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
WHERE edge_id LIKE 'SM_%'
GROUP BY edge_type, layer
ORDER BY layer, edge_type;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_DCIM_POPULATE_SIEMENS_GRAPH() TO ROLE ONTOLOGY_ADMIN;
