-- ============================================================================
-- FINTECH KNOWLEDGE GRAPH — PAYMENT NETWORK POPULATION
-- ============================================================================
-- Extends the base Ontology Knowledge Graph with cross-border payment nodes
-- and financial crime detection edge types.
--
-- Maps existing core demo data to fintech model:
--   SAP FACT_SALES_ORDERS → TRANSACTION nodes
--   SAP DIM_VENDOR → BENEFICIARY nodes
--   Salesforce DIM_ACCOUNT → AGENT nodes
--   Synthetic → WATCHLIST_ENTITY, CORRIDOR nodes
--
-- Prerequisites: scripts 11-15 deployed, SP_REFRESH_GRAPH() has run
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE DCA_DEMO;
USE SCHEMA GOVERNANCE;
USE WAREHOUSE COMPUTE_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE: SP_FINTECH_POPULATE_PAYMENT_GRAPH
-- ═══════════════════════════════════════════════════════════════════════════
-- Populates BENEFICIARY, TRANSACTION, AGENT, CORRIDOR, and WATCHLIST_ENTITY
-- nodes along with payment relationship edges for financial crime detection.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_FINTECH_POPULATE_PAYMENT_GRAPH()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_beneficiary_nodes INTEGER DEFAULT 0;
    v_transaction_nodes INTEGER DEFAULT 0;
    v_agent_nodes INTEGER DEFAULT 0;
    v_corridor_nodes INTEGER DEFAULT 0;
    v_watchlist_nodes INTEGER DEFAULT 0;
    v_payment_edges INTEGER DEFAULT 0;
    v_fraud_edges INTEGER DEFAULT 0;
    v_cross_edges INTEGER DEFAULT 0;
    v_table_exists INTEGER DEFAULT 0;
BEGIN

    -- ── 1. BENEFICIARY nodes from SAP DIM_VENDOR ────────────────────────────
    SELECT COUNT(*) INTO :v_table_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'SAP' AND table_name = 'DIM_VENDOR';

    IF (:v_table_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT
                'FIN_BEN_' || MD5(VENDOR_ID) AS node_id,
                'BENEFICIARY' AS node_type,
                'BUSINESS' AS layer,
                'SAP' AS source_system,
                VENDOR_ID AS fqn,
                COALESCE(VENDOR_NAME, VENDOR_ID) AS display_name,
                OBJECT_CONSTRUCT(
                    'vendor_id', VENDOR_ID,
                    'country', COALESCE(COUNTRY, 'UNKNOWN'),
                    'city', COALESCE(CITY, 'UNKNOWN'),
                    'source_table', 'CURATED_DEV.SAP.DIM_VENDOR'
                ) AS properties
            FROM CURATED_DEV.SAP.DIM_VENDOR
            WHERE VENDOR_ID IS NOT NULL
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        SELECT COUNT(*) INTO :v_beneficiary_nodes
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        WHERE node_type = 'BENEFICIARY' AND node_id LIKE 'FIN_BEN_%';
    END IF;

    -- ── 2. TRANSACTION nodes from SAP FACT_SALES_ORDERS (limit 1000) ────────
    LET v_orders_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_orders_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'SAP' AND table_name = 'FACT_SALES_ORDERS';

    IF (:v_orders_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT
                'FIN_TXN_' || MD5(ORDER_ID) AS node_id,
                'TRANSACTION' AS node_type,
                'BUSINESS' AS layer,
                'SAP' AS source_system,
                ORDER_ID AS fqn,
                'TXN-' || ORDER_NUMBER || ' $' || ROUND(ORDER_AMOUNT, 2) AS display_name,
                OBJECT_CONSTRUCT(
                    'order_id', ORDER_ID,
                    'order_number', ORDER_NUMBER,
                    'amount', ORDER_AMOUNT,
                    'currency', COALESCE(CURRENCY_CODE, 'USD'),
                    'order_date', ORDER_DATE,
                    'corridor', COALESCE(SHIP_TO_COUNTRY, 'US') || '→' || COALESCE(BILL_TO_COUNTRY, 'US'),
                    'source_table', 'CURATED_DEV.SAP.FACT_SALES_ORDERS'
                ) AS properties
            FROM CURATED_DEV.SAP.FACT_SALES_ORDERS
            WHERE ORDER_ID IS NOT NULL
            LIMIT 1000
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        SELECT COUNT(*) INTO :v_transaction_nodes
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        WHERE node_type = 'TRANSACTION' AND node_id LIKE 'FIN_TXN_%';
    END IF;

    -- ── 3. AGENT nodes from Salesforce DIM_ACCOUNT ──────────────────────────
    LET v_account_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_account_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'SALESFORCE' AND table_name = 'DIM_ACCOUNT';

    IF (:v_account_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT
                'FIN_AGT_' || MD5(ACCOUNT_ID) AS node_id,
                'AGENT' AS node_type,
                'BUSINESS' AS layer,
                'SALESFORCE' AS source_system,
                ACCOUNT_ID AS fqn,
                COALESCE(ACCOUNT_NAME, ACCOUNT_ID) AS display_name,
                OBJECT_CONSTRUCT(
                    'account_id', ACCOUNT_ID,
                    'industry', COALESCE(INDUSTRY, 'Financial Services'),
                    'region', COALESCE(BILLING_STATE, 'UNKNOWN'),
                    'source_table', 'CURATED_DEV.SALESFORCE.DIM_ACCOUNT'
                ) AS properties
            FROM CURATED_DEV.SALESFORCE.DIM_ACCOUNT
            WHERE ACCOUNT_ID IS NOT NULL
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        SELECT COUNT(*) INTO :v_agent_nodes
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        WHERE node_type = 'AGENT' AND node_id LIKE 'FIN_AGT_%';
    END IF;

    -- ── 4. CORRIDOR nodes (synthetic — 10 major corridors) ──────────────────
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
    USING (
        SELECT * FROM (
            SELECT 'FIN_COR_' || MD5('US→MX') AS node_id, 'CORRIDOR' AS node_type, 'BUSINESS' AS layer, 'SYNTHETIC' AS source_system, 'US→MX' AS fqn, 'US → Mexico (High Volume)' AS display_name, OBJECT_CONSTRUCT('origin_country', 'US', 'destination_country', 'MX', 'risk_level', 'MEDIUM', 'avg_monthly_volume', 15000000) AS properties
            UNION ALL SELECT 'FIN_COR_' || MD5('US→PH'), 'CORRIDOR', 'BUSINESS', 'SYNTHETIC', 'US→PH', 'US → Philippines (High Volume)', OBJECT_CONSTRUCT('origin_country', 'US', 'destination_country', 'PH', 'risk_level', 'LOW', 'avg_monthly_volume', 8000000)
            UNION ALL SELECT 'FIN_COR_' || MD5('US→IN'), 'CORRIDOR', 'BUSINESS', 'SYNTHETIC', 'US→IN', 'US → India (High Volume)', OBJECT_CONSTRUCT('origin_country', 'US', 'destination_country', 'IN', 'risk_level', 'LOW', 'avg_monthly_volume', 12000000)
            UNION ALL SELECT 'FIN_COR_' || MD5('US→GT'), 'CORRIDOR', 'BUSINESS', 'SYNTHETIC', 'US→GT', 'US → Guatemala (Medium Volume)', OBJECT_CONSTRUCT('origin_country', 'US', 'destination_country', 'GT', 'risk_level', 'MEDIUM', 'avg_monthly_volume', 3000000)
            UNION ALL SELECT 'FIN_COR_' || MD5('US→CO'), 'CORRIDOR', 'BUSINESS', 'SYNTHETIC', 'US→CO', 'US → Colombia (Medium Risk)', OBJECT_CONSTRUCT('origin_country', 'US', 'destination_country', 'CO', 'risk_level', 'HIGH', 'avg_monthly_volume', 2500000)
            UNION ALL SELECT 'FIN_COR_' || MD5('UK→PK'), 'CORRIDOR', 'BUSINESS', 'SYNTHETIC', 'UK→PK', 'UK → Pakistan (Medium Volume)', OBJECT_CONSTRUCT('origin_country', 'UK', 'destination_country', 'PK', 'risk_level', 'MEDIUM', 'avg_monthly_volume', 5000000)
            UNION ALL SELECT 'FIN_COR_' || MD5('UK→NG'), 'CORRIDOR', 'BUSINESS', 'SYNTHETIC', 'UK→NG', 'UK → Nigeria (High Risk)', OBJECT_CONSTRUCT('origin_country', 'UK', 'destination_country', 'NG', 'risk_level', 'HIGH', 'avg_monthly_volume', 4000000)
            UNION ALL SELECT 'FIN_COR_' || MD5('DE→TR'), 'CORRIDOR', 'BUSINESS', 'SYNTHETIC', 'DE→TR', 'Germany → Turkey (Medium Volume)', OBJECT_CONSTRUCT('origin_country', 'DE', 'destination_country', 'TR', 'risk_level', 'MEDIUM', 'avg_monthly_volume', 6000000)
            UNION ALL SELECT 'FIN_COR_' || MD5('FR→MA'), 'CORRIDOR', 'BUSINESS', 'SYNTHETIC', 'FR→MA', 'France → Morocco (Medium Volume)', OBJECT_CONSTRUCT('origin_country', 'FR', 'destination_country', 'MA', 'risk_level', 'LOW', 'avg_monthly_volume', 3500000)
            UNION ALL SELECT 'FIN_COR_' || MD5('AE→PK'), 'CORRIDOR', 'BUSINESS', 'SYNTHETIC', 'AE→PK', 'UAE → Pakistan (High Volume)', OBJECT_CONSTRUCT('origin_country', 'AE', 'destination_country', 'PK', 'risk_level', 'HIGH', 'avg_monthly_volume', 7000000)
        )
    ) AS src
    ON tgt.node_id = src.node_id
    WHEN MATCHED THEN UPDATE SET
        tgt.display_name = src.display_name,
        tgt.properties = src.properties
    WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
        VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

    SELECT COUNT(*) INTO :v_corridor_nodes
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
    WHERE node_type = 'CORRIDOR' AND node_id LIKE 'FIN_COR_%';

    -- ── 5. WATCHLIST_ENTITY nodes (synthetic — 5 demo entities) ─────────────
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
    USING (
        SELECT * FROM (
            SELECT 'FIN_WL_' || MD5('ACME_SHELL_CORP') AS node_id, 'WATCHLIST_ENTITY' AS node_type, 'BUSINESS' AS layer, 'SYNTHETIC' AS source_system, 'ACME_SHELL_CORP' AS fqn, 'ACME Shell Corp' AS display_name, OBJECT_CONSTRUCT('list_type', 'SDN', 'designation_date', '2023-06-15', 'programs', ARRAY_CONSTRUCT('SDGT', 'IRAN'), 'entity_type', 'ORGANIZATION') AS properties
            UNION ALL SELECT 'FIN_WL_' || MD5('SHADOW_HOLDINGS_LTD'), 'WATCHLIST_ENTITY', 'BUSINESS', 'SYNTHETIC', 'SHADOW_HOLDINGS_LTD', 'Shadow Holdings Ltd', OBJECT_CONSTRUCT('list_type', 'SDN', 'designation_date', '2022-11-01', 'programs', ARRAY_CONSTRUCT('SYRIA', 'SDGT'), 'entity_type', 'ORGANIZATION')
            UNION ALL SELECT 'FIN_WL_' || MD5('PHANTOM_TRADE_LLC'), 'WATCHLIST_ENTITY', 'BUSINESS', 'SYNTHETIC', 'PHANTOM_TRADE_LLC', 'Phantom Trade LLC', OBJECT_CONSTRUCT('list_type', 'SDN', 'designation_date', '2024-01-20', 'programs', ARRAY_CONSTRUCT('DPRK', 'NONPROLIFERATION'), 'entity_type', 'ORGANIZATION')
            UNION ALL SELECT 'FIN_WL_' || MD5('DUBIOUS_FINANCE_PEP'), 'WATCHLIST_ENTITY', 'BUSINESS', 'SYNTHETIC', 'DUBIOUS_FINANCE_PEP', 'Viktor Dubious (PEP)', OBJECT_CONSTRUCT('list_type', 'PEP', 'designation_date', '2021-03-10', 'programs', ARRAY_CONSTRUCT('PEP_FOREIGN_OFFICIAL'), 'entity_type', 'INDIVIDUAL')
            UNION ALL SELECT 'FIN_WL_' || MD5('DARK_NEXUS_MEDIA'), 'WATCHLIST_ENTITY', 'BUSINESS', 'SYNTHETIC', 'DARK_NEXUS_MEDIA', 'Dark Nexus Media Group', OBJECT_CONSTRUCT('list_type', 'ADVERSE_MEDIA', 'designation_date', '2024-03-05', 'programs', ARRAY_CONSTRUCT('MONEY_LAUNDERING', 'FRAUD'), 'entity_type', 'ORGANIZATION')
        )
    ) AS src
    ON tgt.node_id = src.node_id
    WHEN MATCHED THEN UPDATE SET
        tgt.display_name = src.display_name,
        tgt.properties = src.properties
    WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
        VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

    SELECT COUNT(*) INTO :v_watchlist_nodes
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
    WHERE node_type = 'WATCHLIST_ENTITY' AND node_id LIKE 'FIN_WL_%';

    -- ── 6. PAYMENT EDGES ────────────────────────────────────────────────────

    -- CUSTOMER → BENEFICIARY (SENDS_TO) — from sales order customer→vendor
    IF (:v_orders_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT DISTINCT
                'FIN_EDGE_' || MD5(
                    'BIZ_CUST_' || MD5(CUSTOMER_ID) ||
                    'FIN_BEN_' || MD5(VENDOR_ID) ||
                    'SENDS_TO'
                ) AS edge_id,
                'BIZ_CUST_' || MD5(CUSTOMER_ID) AS source_node_id,
                'FIN_BEN_' || MD5(VENDOR_ID) AS target_node_id,
                'SENDS_TO' AS edge_type,
                'BUSINESS' AS layer,
                1.0 AS weight
            FROM CURATED_DEV.SAP.FACT_SALES_ORDERS
            WHERE CUSTOMER_ID IS NOT NULL AND VENDOR_ID IS NOT NULL
            LIMIT 1000
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);
    END IF;

    -- TRANSACTION → AGENT (TRANSACTS_VIA) — map orders to accounts
    IF (:v_orders_exists > 0 AND :v_account_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT
                'FIN_EDGE_' || MD5(
                    'FIN_TXN_' || MD5(o.ORDER_ID) ||
                    'FIN_AGT_' || MD5(a.ACCOUNT_ID) ||
                    'TRANSACTS_VIA'
                ) AS edge_id,
                'FIN_TXN_' || MD5(o.ORDER_ID) AS source_node_id,
                'FIN_AGT_' || MD5(a.ACCOUNT_ID) AS target_node_id,
                'TRANSACTS_VIA' AS edge_type,
                'BUSINESS' AS layer,
                1.0 AS weight
            FROM CURATED_DEV.SAP.FACT_SALES_ORDERS o
            JOIN CURATED_DEV.SALESFORCE.DIM_ACCOUNT a
                ON o.CUSTOMER_ID = a.ACCOUNT_ID
            WHERE o.ORDER_ID IS NOT NULL AND a.ACCOUNT_ID IS NOT NULL
            LIMIT 500
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);
    END IF;

    -- TRANSACTION → CORRIDOR (ROUTED_THROUGH) — assign corridors based on vendor country
    IF (:v_orders_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT
                'FIN_EDGE_' || MD5(
                    'FIN_TXN_' || MD5(o.ORDER_ID) ||
                    'FIN_COR_' || MD5('US→MX') ||
                    'ROUTED_THROUGH'
                ) AS edge_id,
                'FIN_TXN_' || MD5(o.ORDER_ID) AS source_node_id,
                'FIN_COR_' || MD5('US→MX') AS target_node_id,
                'ROUTED_THROUGH' AS edge_type,
                'BUSINESS' AS layer,
                1.0 AS weight
            FROM CURATED_DEV.SAP.FACT_SALES_ORDERS o
            WHERE o.ORDER_ID IS NOT NULL
            LIMIT 200
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);
    END IF;

    -- ── 7. FRAUD RING INDICATOR EDGES (synthetic) ───────────────────────────

    -- SHARES_BENEFICIARY — 3 groups of 5 customers sharing same beneficiary (structuring)
    -- Group 1: First 5 customers → first beneficiary
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT
            'FIN_EDGE_' || MD5(c.node_id || b.node_id || 'SHARES_BENEFICIARY') AS edge_id,
            c.node_id AS source_node_id,
            b.node_id AS target_node_id,
            'SHARES_BENEFICIARY' AS edge_type,
            'BUSINESS' AS layer,
            1.0 AS weight
        FROM (
            SELECT node_id, ROW_NUMBER() OVER (ORDER BY node_id) AS rn
            FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
            WHERE node_type = 'CUSTOMER' AND layer = 'BUSINESS'
            LIMIT 15
        ) c
        CROSS JOIN (
            SELECT node_id, ROW_NUMBER() OVER (ORDER BY node_id) AS rn
            FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
            WHERE node_type = 'BENEFICIARY' AND node_id LIKE 'FIN_BEN_%'
            LIMIT 3
        ) b
        WHERE CEIL(c.rn / 5.0) = b.rn
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    -- SHARES_DEVICE — synthetic: pairs of customers sharing same device fingerprint
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT
            'FIN_EDGE_' || MD5(c1.node_id || c2.node_id || 'SHARES_DEVICE') AS edge_id,
            c1.node_id AS source_node_id,
            c2.node_id AS target_node_id,
            'SHARES_DEVICE' AS edge_type,
            'BUSINESS' AS layer,
            0.9 AS weight
        FROM (
            SELECT node_id, ROW_NUMBER() OVER (ORDER BY node_id) AS rn
            FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
            WHERE node_type = 'CUSTOMER' AND layer = 'BUSINESS'
            LIMIT 10
        ) c1
        JOIN (
            SELECT node_id, ROW_NUMBER() OVER (ORDER BY node_id) AS rn
            FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
            WHERE node_type = 'CUSTOMER' AND layer = 'BUSINESS'
            LIMIT 10
        ) c2
            ON c1.rn = c2.rn - 1 AND MOD(c1.rn, 2) = 1
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    -- SHARES_ADDRESS — 2 groups of 4 customers sharing address
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT
            'FIN_EDGE_' || MD5(c1.node_id || c2.node_id || 'SHARES_ADDRESS') AS edge_id,
            c1.node_id AS source_node_id,
            c2.node_id AS target_node_id,
            'SHARES_ADDRESS' AS edge_type,
            'BUSINESS' AS layer,
            0.85 AS weight
        FROM (
            SELECT node_id, ROW_NUMBER() OVER (ORDER BY node_id) AS rn
            FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
            WHERE node_type = 'CUSTOMER' AND layer = 'BUSINESS'
            LIMIT 8 OFFSET 15
        ) c1
        JOIN (
            SELECT node_id, ROW_NUMBER() OVER (ORDER BY node_id) AS rn
            FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
            WHERE node_type = 'CUSTOMER' AND layer = 'BUSINESS'
            LIMIT 8 OFFSET 15
        ) c2
            ON c1.rn < c2.rn AND CEIL(c1.rn / 4.0) = CEIL(c2.rn / 4.0)
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    SELECT COUNT(*) INTO :v_fraud_edges
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
    WHERE edge_id LIKE 'FIN_EDGE_%'
      AND edge_type IN ('SHARES_BENEFICIARY', 'SHARES_DEVICE', 'SHARES_ADDRESS');

    -- ── 8. CROSS-LAYER EDGES ────────────────────────────────────────────────

    -- BENEFICIARY → DIM_VENDOR metadata node (STORED_IN)
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT DISTINCT
            'FIN_EDGE_' || MD5(
                n.node_id ||
                'META_' || MD5('CURATED_DEV.SAP.DIM_VENDOR') ||
                'STORED_IN'
            ) AS edge_id,
            n.node_id AS source_node_id,
            'META_' || MD5('CURATED_DEV.SAP.DIM_VENDOR') AS target_node_id,
            'STORED_IN' AS edge_type,
            'CROSS' AS layer,
            1.0 AS weight
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
        WHERE n.node_id LIKE 'FIN_BEN_%'
          AND n.node_type = 'BENEFICIARY'
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    -- AGENT → DIM_ACCOUNT metadata node (STORED_IN)
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT DISTINCT
            'FIN_EDGE_' || MD5(
                n.node_id ||
                'META_' || MD5('CURATED_DEV.SALESFORCE.DIM_ACCOUNT') ||
                'STORED_IN'
            ) AS edge_id,
            n.node_id AS source_node_id,
            'META_' || MD5('CURATED_DEV.SALESFORCE.DIM_ACCOUNT') AS target_node_id,
            'STORED_IN' AS edge_type,
            'CROSS' AS layer,
            1.0 AS weight
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
        WHERE n.node_id LIKE 'FIN_AGT_%'
          AND n.node_type = 'AGENT'
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    SELECT COUNT(*) INTO :v_cross_edges
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
    WHERE edge_id LIKE 'FIN_EDGE_%' AND layer = 'CROSS';

    SELECT COUNT(*) INTO :v_payment_edges
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
    WHERE edge_id LIKE 'FIN_EDGE_%';

    -- ── Final summary ───────────────────────────────────────────────────────
    RETURN 'Fintech Payment Graph populated.' || CHR(10) ||
           '  Nodes — Beneficiaries: ' || :v_beneficiary_nodes ||
           ', Transactions: ' || :v_transaction_nodes ||
           ', Agents: ' || :v_agent_nodes ||
           ', Corridors: ' || :v_corridor_nodes ||
           ', Watchlist: ' || :v_watchlist_nodes || CHR(10) ||
           '  Edges — Payment: ' || :v_payment_edges ||
           ', Fraud indicators: ' || :v_fraud_edges ||
           ', Cross-layer: ' || :v_cross_edges;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'Fintech payment graph population procedure created' AS status;

SELECT node_type, COUNT(*) AS node_count
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
WHERE node_id LIKE 'FIN_%'
GROUP BY node_type
ORDER BY node_type;

SELECT edge_type, layer, COUNT(*) AS edge_count
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
WHERE edge_id LIKE 'FIN_EDGE_%'
GROUP BY edge_type, layer
ORDER BY layer, edge_type;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_FINTECH_POPULATE_PAYMENT_GRAPH() TO ROLE ONTOLOGY_ADMIN;
