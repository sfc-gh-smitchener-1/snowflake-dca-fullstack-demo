-- ============================================================================
-- FINTECH DEMO — INTENTIONAL BSA/AML COMPLIANCE GAPS
-- ============================================================================
-- Creates demonstration objects that exhibit financial crime compliance
-- failures the Knowledge Graph should detect via RAI inference.
--
-- Gaps introduced:
--   1. High-velocity customer with stale KYC (no refresh in 3 years)
--   2. Structuring ring — 5 customers sharing same beneficiary, all < $3K
--   3. Agent with 10x volume spike and no SAR filed
--   4. Transaction to sanctioned-country corridor without screening edge
--   5. Beneficial ownership chain obscuring PEP connection
--
-- Prerequisites: scripts 11-15 deployed, 01_fintech_graph_populate.sql run
-- RUN AS: SYSADMIN
-- ============================================================================

USE ROLE SYSADMIN;
USE DATABASE DCA_DEMO;
USE SCHEMA GOVERNANCE;
USE WAREHOUSE COMPUTE_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- GAP 1: High-Velocity Customer with Stale KYC
-- ═══════════════════════════════════════════════════════════════════════════
-- A customer who has 100+ recent transactions but whose KYC verification
-- was last performed 3 years ago. No KYC_REFRESH edge exists.
-- BSA requires Enhanced Due Diligence (EDD) for high-risk customers.
-- ═══════════════════════════════════════════════════════════════════════════

-- Insert high-velocity customer
MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
USING (
    SELECT
        'FIN_GAP_CUST_STALE_KYC' AS node_id,
        'CUSTOMER' AS node_type,
        'BUSINESS' AS layer,
        'SYNTHETIC' AS source_system,
        'GAP1_HIGH_VELOCITY_STALE_KYC' AS fqn,
        'Maria Hernandez (Stale KYC)' AS display_name,
        OBJECT_CONSTRUCT(
            'customer_id', 'CUST-GAP-001',
            'last_kyc_date', '2022-01-15',
            'kyc_status', 'EXPIRED',
            'transaction_count_30d', 127,
            'total_amount_30d', 385000,
            'primary_corridor', 'US→MX',
            'risk_flag', 'HIGH_VELOCITY_STALE_KYC',
            'gap_description', 'Customer has 127 transactions in last 30 days totaling $385K but KYC was last verified 3+ years ago. No EDD triggered.'
        ) AS properties
) AS src
ON tgt.node_id = src.node_id
WHEN MATCHED THEN UPDATE SET tgt.properties = src.properties, tgt.display_name = src.display_name
WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
    VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

-- Insert stale KYC_VERIFIED edge (dated 3 years ago — no refresh)
MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
USING (
    SELECT
        'FIN_GAP_EDGE_STALE_KYC' AS edge_id,
        'FIN_GAP_CUST_STALE_KYC' AS source_node_id,
        'FIN_COR_' || MD5('US→MX') AS target_node_id,
        'KYC_VERIFIED' AS edge_type,
        'BUSINESS' AS layer,
        0.3 AS weight,
        OBJECT_CONSTRUCT('verification_date', '2022-01-15', 'method', 'ID_SCAN', 'status', 'EXPIRED') AS properties
) AS src
ON tgt.edge_id = src.edge_id
WHEN MATCHED THEN UPDATE SET tgt.properties = src.properties
WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight, properties)
    VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight, src.properties);

-- INTENTIONAL OMISSION: No KYC_REFRESH edge. No EDD_COMPLETED edge.
-- SP_FINTECH_AML_SCORING() should flag this customer as HIGH risk due to
-- stale KYC + high velocity.

-- ═══════════════════════════════════════════════════════════════════════════
-- GAP 2: Structuring Ring — 5 Customers, Same Beneficiary, All < $3K
-- ═══════════════════════════════════════════════════════════════════════════
-- Classic smurfing/structuring pattern: multiple customers send to the same
-- beneficiary, each just under the $3,000 reporting threshold.
-- Individually innocent. Collectively: textbook BSA violation.
-- ═══════════════════════════════════════════════════════════════════════════

-- Insert 5 structuring customers
MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
USING (
    SELECT * FROM (
        SELECT 'FIN_GAP_STRUCT_1' AS node_id, 'CUSTOMER' AS node_type, 'BUSINESS' AS layer, 'SYNTHETIC' AS source_system, 'GAP2_STRUCT_1' AS fqn, 'Juan Perez (Structuring Ring)' AS display_name, OBJECT_CONSTRUCT('customer_id', 'STRUCT-001', 'avg_transaction', 2850, 'frequency', 'weekly', 'ring_id', 'RING_ALPHA') AS properties
        UNION ALL SELECT 'FIN_GAP_STRUCT_2', 'CUSTOMER', 'BUSINESS', 'SYNTHETIC', 'GAP2_STRUCT_2', 'Carlos Mendoza (Structuring Ring)', OBJECT_CONSTRUCT('customer_id', 'STRUCT-002', 'avg_transaction', 2920, 'frequency', 'weekly', 'ring_id', 'RING_ALPHA')
        UNION ALL SELECT 'FIN_GAP_STRUCT_3', 'CUSTOMER', 'BUSINESS', 'SYNTHETIC', 'GAP2_STRUCT_3', 'Roberto Silva (Structuring Ring)', OBJECT_CONSTRUCT('customer_id', 'STRUCT-003', 'avg_transaction', 2780, 'frequency', 'weekly', 'ring_id', 'RING_ALPHA')
        UNION ALL SELECT 'FIN_GAP_STRUCT_4', 'CUSTOMER', 'BUSINESS', 'SYNTHETIC', 'GAP2_STRUCT_4', 'Miguel Torres (Structuring Ring)', OBJECT_CONSTRUCT('customer_id', 'STRUCT-004', 'avg_transaction', 2990, 'frequency', 'weekly', 'ring_id', 'RING_ALPHA')
        UNION ALL SELECT 'FIN_GAP_STRUCT_5', 'CUSTOMER', 'BUSINESS', 'SYNTHETIC', 'GAP2_STRUCT_5', 'Diego Ramirez (Structuring Ring)', OBJECT_CONSTRUCT('customer_id', 'STRUCT-005', 'avg_transaction', 2870, 'frequency', 'weekly', 'ring_id', 'RING_ALPHA')
    )
) AS src
ON tgt.node_id = src.node_id
WHEN MATCHED THEN UPDATE SET tgt.properties = src.properties, tgt.display_name = src.display_name
WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
    VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

-- Shared beneficiary for the ring
MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
USING (
    SELECT
        'FIN_GAP_BEN_RING_TARGET' AS node_id,
        'BENEFICIARY' AS node_type,
        'BUSINESS' AS layer,
        'SYNTHETIC' AS source_system,
        'GAP2_RING_BENEFICIARY' AS fqn,
        'Casa de Cambio Monterrey #47' AS display_name,
        OBJECT_CONSTRUCT(
            'beneficiary_id', 'BEN-RING-001',
            'country', 'MX',
            'city', 'Monterrey',
            'total_received_30d', 72050,
            'unique_senders', 5,
            'all_under_threshold', TRUE
        ) AS properties
) AS src
ON tgt.node_id = src.node_id
WHEN MATCHED THEN UPDATE SET tgt.properties = src.properties, tgt.display_name = src.display_name
WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
    VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

-- SHARES_BENEFICIARY edges connecting all 5 to the same beneficiary
MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
USING (
    SELECT * FROM (
        SELECT 'FIN_GAP_EDGE_STRUCT_1' AS edge_id, 'FIN_GAP_STRUCT_1' AS source_node_id, 'FIN_GAP_BEN_RING_TARGET' AS target_node_id, 'SENDS_TO' AS edge_type, 'BUSINESS' AS layer, 1.0 AS weight
        UNION ALL SELECT 'FIN_GAP_EDGE_STRUCT_2', 'FIN_GAP_STRUCT_2', 'FIN_GAP_BEN_RING_TARGET', 'SENDS_TO', 'BUSINESS', 1.0
        UNION ALL SELECT 'FIN_GAP_EDGE_STRUCT_3', 'FIN_GAP_STRUCT_3', 'FIN_GAP_BEN_RING_TARGET', 'SENDS_TO', 'BUSINESS', 1.0
        UNION ALL SELECT 'FIN_GAP_EDGE_STRUCT_4', 'FIN_GAP_STRUCT_4', 'FIN_GAP_BEN_RING_TARGET', 'SENDS_TO', 'BUSINESS', 1.0
        UNION ALL SELECT 'FIN_GAP_EDGE_STRUCT_5', 'FIN_GAP_STRUCT_5', 'FIN_GAP_BEN_RING_TARGET', 'SENDS_TO', 'BUSINESS', 1.0
    )
) AS src
ON tgt.edge_id = src.edge_id
WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
    VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

-- SHARES_BENEFICIARY edges between the structuring customers (pairwise)
MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
USING (
    SELECT * FROM (
        SELECT 'FIN_GAP_EDGE_SB_12' AS edge_id, 'FIN_GAP_STRUCT_1' AS source_node_id, 'FIN_GAP_STRUCT_2' AS target_node_id, 'SHARES_BENEFICIARY' AS edge_type, 'BUSINESS' AS layer, 1.0 AS weight
        UNION ALL SELECT 'FIN_GAP_EDGE_SB_13', 'FIN_GAP_STRUCT_1', 'FIN_GAP_STRUCT_3', 'SHARES_BENEFICIARY', 'BUSINESS', 1.0
        UNION ALL SELECT 'FIN_GAP_EDGE_SB_14', 'FIN_GAP_STRUCT_1', 'FIN_GAP_STRUCT_4', 'SHARES_BENEFICIARY', 'BUSINESS', 1.0
        UNION ALL SELECT 'FIN_GAP_EDGE_SB_15', 'FIN_GAP_STRUCT_1', 'FIN_GAP_STRUCT_5', 'SHARES_BENEFICIARY', 'BUSINESS', 1.0
        UNION ALL SELECT 'FIN_GAP_EDGE_SB_23', 'FIN_GAP_STRUCT_2', 'FIN_GAP_STRUCT_3', 'SHARES_BENEFICIARY', 'BUSINESS', 1.0
        UNION ALL SELECT 'FIN_GAP_EDGE_SB_24', 'FIN_GAP_STRUCT_2', 'FIN_GAP_STRUCT_4', 'SHARES_BENEFICIARY', 'BUSINESS', 1.0
        UNION ALL SELECT 'FIN_GAP_EDGE_SB_25', 'FIN_GAP_STRUCT_2', 'FIN_GAP_STRUCT_5', 'SHARES_BENEFICIARY', 'BUSINESS', 1.0
        UNION ALL SELECT 'FIN_GAP_EDGE_SB_34', 'FIN_GAP_STRUCT_3', 'FIN_GAP_STRUCT_4', 'SHARES_BENEFICIARY', 'BUSINESS', 1.0
        UNION ALL SELECT 'FIN_GAP_EDGE_SB_35', 'FIN_GAP_STRUCT_3', 'FIN_GAP_STRUCT_5', 'SHARES_BENEFICIARY', 'BUSINESS', 1.0
        UNION ALL SELECT 'FIN_GAP_EDGE_SB_45', 'FIN_GAP_STRUCT_4', 'FIN_GAP_STRUCT_5', 'SHARES_BENEFICIARY', 'BUSINESS', 1.0
    )
) AS src
ON tgt.edge_id = src.edge_id
WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
    VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

-- INTENTIONAL OMISSION: No SAR_FILED edge. No INVESTIGATION_OPENED edge.
-- SP_FINTECH_FRAUD_RINGS() should detect this as a connected component cluster.

-- ═══════════════════════════════════════════════════════════════════════════
-- GAP 3: Agent Volume Spike — 10x Increase, No SAR Filed
-- ═══════════════════════════════════════════════════════════════════════════
-- An agent location that experienced a 10x volume spike (typical indicator
-- of agent-facilitated money laundering) with no corresponding SAR filing.
-- DOJ/FinCEN specifically cite agent monitoring failures in consent orders.
-- ═══════════════════════════════════════════════════════════════════════════

MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
USING (
    SELECT
        'FIN_GAP_AGT_SPIKE' AS node_id,
        'AGENT' AS node_type,
        'BUSINESS' AS layer,
        'SYNTHETIC' AS source_system,
        'GAP3_AGENT_VOLUME_SPIKE' AS fqn,
        'QuickSend Agent #7742 (Volume Spike)' AS display_name,
        OBJECT_CONSTRUCT(
            'agent_id', 'AGT-GAP-001',
            'location', 'Los Angeles, CA',
            'avg_monthly_volume', 45000,
            'current_month_volume', 487000,
            'volume_multiplier', 10.8,
            'sar_filed_count', 0,
            'suspicious_patterns', 15,
            'kyc_completion_rate', 0.62,
            'gap_description', 'Agent volume increased 10.8x over 90-day average. 15 structuring patterns detected. Zero SARs filed. 62% KYC completion rate.'
        ) AS properties
) AS src
ON tgt.node_id = src.node_id
WHEN MATCHED THEN UPDATE SET tgt.properties = src.properties, tgt.display_name = src.display_name
WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
    VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

-- Connect agent to high-risk corridor
MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
USING (
    SELECT
        'FIN_GAP_EDGE_AGT_CORRIDOR' AS edge_id,
        'FIN_GAP_AGT_SPIKE' AS source_node_id,
        'FIN_COR_' || MD5('US→CO') AS target_node_id,
        'OPERATES_IN' AS edge_type,
        'BUSINESS' AS layer,
        1.0 AS weight
) AS src
ON tgt.edge_id = src.edge_id
WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
    VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

-- INTENTIONAL OMISSION: No SAR_FILED edge from any customer at this agent.
-- SP_FINTECH_AGENT_COMPLIANCE() should flag this agent as HIGH risk.

-- ═══════════════════════════════════════════════════════════════════════════
-- GAP 4: Sanctioned Corridor Transaction Without Screening
-- ═══════════════════════════════════════════════════════════════════════════
-- A transaction routed through a corridor whose destination country is
-- subject to comprehensive OFAC sanctions. No SCREENING_COMPLETED edge
-- exists — meaning the transaction was processed without sanctions check.
-- ═══════════════════════════════════════════════════════════════════════════

-- High-risk corridor to sanctioned destination
MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
USING (
    SELECT
        'FIN_GAP_COR_SANCTIONED' AS node_id,
        'CORRIDOR' AS node_type,
        'BUSINESS' AS layer,
        'SYNTHETIC' AS source_system,
        'GAP4_SANCTIONED_CORRIDOR' AS fqn,
        'AE → DPRK (Sanctioned Corridor)' AS display_name,
        OBJECT_CONSTRUCT(
            'origin_country', 'AE',
            'destination_country', 'DPRK',
            'risk_level', 'PROHIBITED',
            'sanctions_program', 'DPRK_COMPREHENSIVE',
            'should_be_blocked', TRUE,
            'gap_description', 'Corridor to comprehensively sanctioned jurisdiction. Any transaction should be blocked.'
        ) AS properties
) AS src
ON tgt.node_id = src.node_id
WHEN MATCHED THEN UPDATE SET tgt.properties = src.properties, tgt.display_name = src.display_name
WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
    VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

-- Transaction that went through the sanctioned corridor
MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
USING (
    SELECT
        'FIN_GAP_TXN_UNSCREENED' AS node_id,
        'TRANSACTION' AS node_type,
        'BUSINESS' AS layer,
        'SYNTHETIC' AS source_system,
        'GAP4_UNSCREENED_TXN' AS fqn,
        'TXN-UNSCREENED $25,000 (No Sanctions Check)' AS display_name,
        OBJECT_CONSTRUCT(
            'transaction_id', 'TXN-GAP-001',
            'amount', 25000,
            'currency', 'USD',
            'transaction_date', CURRENT_DATE() - 3,
            'screening_status', 'NOT_PERFORMED',
            'gap_description', '$25K transaction to DPRK corridor processed without sanctions screening.'
        ) AS properties
) AS src
ON tgt.node_id = src.node_id
WHEN MATCHED THEN UPDATE SET tgt.properties = src.properties, tgt.display_name = src.display_name
WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
    VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

-- Edge: Transaction routed through sanctioned corridor
MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
USING (
    SELECT
        'FIN_GAP_EDGE_TXN_SANC_COR' AS edge_id,
        'FIN_GAP_TXN_UNSCREENED' AS source_node_id,
        'FIN_GAP_COR_SANCTIONED' AS target_node_id,
        'ROUTED_THROUGH' AS edge_type,
        'BUSINESS' AS layer,
        1.0 AS weight
) AS src
ON tgt.edge_id = src.edge_id
WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
    VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

-- INTENTIONAL OMISSION: No SCREENING_COMPLETED edge on this transaction.
-- SP_FINTECH_SANCTIONS_SCREENING() should flag this as CRITICAL.

-- ═══════════════════════════════════════════════════════════════════════════
-- GAP 5: Beneficial Ownership Chain Obscuring PEP Connection
-- ═══════════════════════════════════════════════════════════════════════════
-- CUSTOMER_A → OWNS(51%) → SHELL_CORP_B → CONTROLS → ENTITY_C → MATCHED_WATCHLIST → PEP
-- Simple name-matching would never catch this 3-hop chain.
-- CDD Rule requires beneficial ownership identification for all customers.
-- ═══════════════════════════════════════════════════════════════════════════

-- The customer with hidden PEP exposure
MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
USING (
    SELECT
        'FIN_GAP_CUST_PEP_HIDDEN' AS node_id,
        'CUSTOMER' AS node_type,
        'BUSINESS' AS layer,
        'SYNTHETIC' AS source_system,
        'GAP5_PEP_HIDDEN_OWNERSHIP' AS fqn,
        'Alexander Volkov (Hidden PEP Link)' AS display_name,
        OBJECT_CONSTRUCT(
            'customer_id', 'CUST-GAP-005',
            'kyc_status', 'VERIFIED',
            'pep_screen_result', 'NO_MATCH',
            'beneficial_ownership_declared', FALSE,
            'gap_description', 'Customer passed name-based PEP screening but has indirect ownership chain to PEP entity via shell corporations.'
        ) AS properties
) AS src
ON tgt.node_id = src.node_id
WHEN MATCHED THEN UPDATE SET tgt.properties = src.properties, tgt.display_name = src.display_name
WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
    VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

-- Shell corporation B (intermediate)
MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
USING (
    SELECT
        'FIN_GAP_SHELL_CORP_B' AS node_id,
        'ENTITY' AS node_type,
        'BUSINESS' AS layer,
        'SYNTHETIC' AS source_system,
        'GAP5_SHELL_CORP_B' AS fqn,
        'Eurostar Trading GmbH (Shell)' AS display_name,
        OBJECT_CONSTRUCT(
            'entity_id', 'ENT-SHELL-001',
            'jurisdiction', 'Cyprus',
            'entity_type', 'SHELL_CORPORATION',
            'incorporation_date', '2019-08-22',
            'beneficial_owner', 'CUST-GAP-005'
        ) AS properties
) AS src
ON tgt.node_id = src.node_id
WHEN MATCHED THEN UPDATE SET tgt.properties = src.properties, tgt.display_name = src.display_name
WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
    VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

-- Entity C (controlled by shell, linked to PEP)
MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
USING (
    SELECT
        'FIN_GAP_ENTITY_C' AS node_id,
        'ENTITY' AS node_type,
        'BUSINESS' AS layer,
        'SYNTHETIC' AS source_system,
        'GAP5_ENTITY_C' AS fqn,
        'Meridian Capital Partners Ltd' AS display_name,
        OBJECT_CONSTRUCT(
            'entity_id', 'ENT-MER-001',
            'jurisdiction', 'British Virgin Islands',
            'entity_type', 'HOLDING_COMPANY',
            'controlled_by', 'ENT-SHELL-001',
            'pep_connection', 'DUBIOUS_FINANCE_PEP'
        ) AS properties
) AS src
ON tgt.node_id = src.node_id
WHEN MATCHED THEN UPDATE SET tgt.properties = src.properties, tgt.display_name = src.display_name
WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
    VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

-- Ownership chain edges: CUSTOMER → OWNS → SHELL → CONTROLS → ENTITY → MATCHED_WATCHLIST → PEP
MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
USING (
    SELECT * FROM (
        -- Hop 1: Customer OWNS Shell Corp (51%)
        SELECT 'FIN_GAP_EDGE_OWNS_SHELL' AS edge_id, 'FIN_GAP_CUST_PEP_HIDDEN' AS source_node_id, 'FIN_GAP_SHELL_CORP_B' AS target_node_id, 'OWNS' AS edge_type, 'BUSINESS' AS layer, 0.51 AS weight, OBJECT_CONSTRUCT('ownership_pct', 51, 'relationship', 'BENEFICIAL_OWNER') AS properties
        -- Hop 2: Shell Corp CONTROLS Entity C
        UNION ALL SELECT 'FIN_GAP_EDGE_CONTROLS_ENT', 'FIN_GAP_SHELL_CORP_B', 'FIN_GAP_ENTITY_C', 'CONTROLS', 'BUSINESS', 1.0, OBJECT_CONSTRUCT('control_type', 'BOARD_MAJORITY', 'relationship', 'CORPORATE_CONTROL')
        -- Hop 3: Entity C MATCHED_WATCHLIST to PEP
        UNION ALL SELECT 'FIN_GAP_EDGE_PEP_MATCH', 'FIN_GAP_ENTITY_C', 'FIN_WL_' || MD5('DUBIOUS_FINANCE_PEP'), 'MATCHED_WATCHLIST', 'BUSINESS', 0.92, OBJECT_CONSTRUCT('match_type', 'BUSINESS_ASSOCIATE', 'match_score', 0.92, 'list_type', 'PEP')
    )
) AS src
ON tgt.edge_id = src.edge_id
WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight, properties)
    VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight, src.properties);

-- INTENTIONAL OMISSION: No PEP_SCREEN_POSITIVE on the customer.
-- Name-matching returned NO_MATCH because the customer's name is clean.
-- Only the graph traversal (3 hops) reveals the PEP connection.
-- SP_FINTECH_SANCTIONS_SCREENING() should detect this via ownership traversal.

-- ═══════════════════════════════════════════════════════════════════════════
-- GAP SUMMARY
-- ═══════════════════════════════════════════════════════════════════════════

SELECT
    'BSA/AML Compliance Gaps Created' AS status,
    (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES WHERE node_id LIKE 'FIN_GAP_%') AS gap_nodes,
    (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES WHERE edge_id LIKE 'FIN_GAP_%') AS gap_edges;

SELECT node_id, node_type, display_name,
       properties:"gap_description"::VARCHAR AS compliance_gap
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
WHERE node_id LIKE 'FIN_GAP_%'
  AND properties:"gap_description" IS NOT NULL
ORDER BY node_id;
