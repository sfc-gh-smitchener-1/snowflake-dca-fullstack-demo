-- ============================================================================
-- FINTECH KNOWLEDGE GRAPH — FINANCIAL CRIME RAI INFERENCE
-- ============================================================================
-- Financial crime detection procedures using graph analysis:
--   1. Fraud ring detection (connected components)
--   2. AML risk scoring (network position + behavior)
--   3. Sanctions screening (graph traversal)
--   4. Corridor risk scoring
--   5. Agent compliance scoring
--   6. Orchestrator (run all)
--
-- Prerequisites: 01_fintech_graph_populate.sql and 02_fintech_compliance_gaps.sql
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE DCA_DEMO;
USE SCHEMA GOVERNANCE;
USE WAREHOUSE COMPUTE_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 1: SP_FINTECH_FRAUD_RINGS
-- ═══════════════════════════════════════════════════════════════════════════
-- Connected component analysis: finds groups of CUSTOMER nodes connected
-- by SHARES_BENEFICIARY, SHARES_ADDRESS, or SHARES_DEVICE edges.
-- Rings with > 2 members generate HIGH severity recommendations.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_FINTECH_FRAUD_RINGS()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_clusters_found INTEGER DEFAULT 0;
    v_recommendations INTEGER DEFAULT 0;
BEGIN
    -- Find connected components via iterative label propagation
    -- Each customer starts with its own label (node_id), then propagates
    -- the minimum label across fraud-indicator edges.

    -- Step 1: Initialize cluster assignments (each node = own cluster)
    CREATE OR REPLACE TEMPORARY TABLE DCA_DEMO.GOVERNANCE.TMP_FRAUD_CLUSTERS AS
    SELECT
        node_id,
        node_id AS cluster_label,
        1 AS iteration
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
    WHERE node_type = 'CUSTOMER'
      AND layer = 'BUSINESS';

    -- Step 2: Propagate minimum label through fraud-indicator edges (3 iterations)
    -- Iteration 1
    MERGE INTO DCA_DEMO.GOVERNANCE.TMP_FRAUD_CLUSTERS AS tgt
    USING (
        SELECT c.node_id, MIN(LEAST(c.cluster_label, c2.cluster_label)) AS new_label
        FROM DCA_DEMO.GOVERNANCE.TMP_FRAUD_CLUSTERS c
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
            ON (c.node_id = e.source_node_id OR c.node_id = e.target_node_id)
        JOIN DCA_DEMO.GOVERNANCE.TMP_FRAUD_CLUSTERS c2
            ON (c2.node_id = CASE WHEN c.node_id = e.source_node_id THEN e.target_node_id ELSE e.source_node_id END)
        WHERE e.edge_type IN ('SHARES_BENEFICIARY', 'SHARES_ADDRESS', 'SHARES_DEVICE')
        GROUP BY c.node_id
    ) AS src
    ON tgt.node_id = src.node_id
    WHEN MATCHED AND src.new_label < tgt.cluster_label THEN
        UPDATE SET tgt.cluster_label = src.new_label, tgt.iteration = 2;

    -- Iteration 2
    MERGE INTO DCA_DEMO.GOVERNANCE.TMP_FRAUD_CLUSTERS AS tgt
    USING (
        SELECT c.node_id, MIN(LEAST(c.cluster_label, c2.cluster_label)) AS new_label
        FROM DCA_DEMO.GOVERNANCE.TMP_FRAUD_CLUSTERS c
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
            ON (c.node_id = e.source_node_id OR c.node_id = e.target_node_id)
        JOIN DCA_DEMO.GOVERNANCE.TMP_FRAUD_CLUSTERS c2
            ON (c2.node_id = CASE WHEN c.node_id = e.source_node_id THEN e.target_node_id ELSE e.source_node_id END)
        WHERE e.edge_type IN ('SHARES_BENEFICIARY', 'SHARES_ADDRESS', 'SHARES_DEVICE')
        GROUP BY c.node_id
    ) AS src
    ON tgt.node_id = src.node_id
    WHEN MATCHED AND src.new_label < tgt.cluster_label THEN
        UPDATE SET tgt.cluster_label = src.new_label, tgt.iteration = 3;

    -- Iteration 3
    MERGE INTO DCA_DEMO.GOVERNANCE.TMP_FRAUD_CLUSTERS AS tgt
    USING (
        SELECT c.node_id, MIN(LEAST(c.cluster_label, c2.cluster_label)) AS new_label
        FROM DCA_DEMO.GOVERNANCE.TMP_FRAUD_CLUSTERS c
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
            ON (c.node_id = e.source_node_id OR c.node_id = e.target_node_id)
        JOIN DCA_DEMO.GOVERNANCE.TMP_FRAUD_CLUSTERS c2
            ON (c2.node_id = CASE WHEN c.node_id = e.source_node_id THEN e.target_node_id ELSE e.source_node_id END)
        WHERE e.edge_type IN ('SHARES_BENEFICIARY', 'SHARES_ADDRESS', 'SHARES_DEVICE')
        GROUP BY c.node_id
    ) AS src
    ON tgt.node_id = src.node_id
    WHEN MATCHED AND src.new_label < tgt.cluster_label THEN
        UPDATE SET tgt.cluster_label = src.new_label, tgt.iteration = 4;

    -- Step 3: Insert clusters with > 2 members into entity clusters table
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_ENTITY_CLUSTERS AS tgt
    USING (
        SELECT
            DENSE_RANK() OVER (ORDER BY c.cluster_label) AS cluster_id,
            c.node_id,
            'FRAUD_RING_' || DENSE_RANK() OVER (ORDER BY c.cluster_label) AS cluster_label,
            0.85 AS confidence
        FROM DCA_DEMO.GOVERNANCE.TMP_FRAUD_CLUSTERS c
        WHERE c.cluster_label IN (
            SELECT cluster_label
            FROM DCA_DEMO.GOVERNANCE.TMP_FRAUD_CLUSTERS
            GROUP BY cluster_label
            HAVING COUNT(*) > 2
        )
    ) AS src
    ON tgt.node_id = src.node_id AND tgt.cluster_label = src.cluster_label
    WHEN MATCHED THEN UPDATE SET
        tgt.cluster_id = src.cluster_id,
        tgt.confidence = src.confidence
    WHEN NOT MATCHED THEN INSERT (cluster_id, node_id, cluster_label, confidence)
        VALUES (src.cluster_id, src.node_id, src.cluster_label, src.confidence);

    SELECT COUNT(DISTINCT cluster_label) INTO :v_clusters_found
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_ENTITY_CLUSTERS
    WHERE cluster_label LIKE 'FRAUD_RING_%';

    -- Step 4: Generate recommendations for detected fraud rings
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS AS tgt
    USING (
        SELECT
            'FIN_FRAUD_RING_' || cluster_label AS recommendation_id,
            'FRAUD_RING' AS recommendation_type,
            'HIGH' AS severity,
            MIN(node_id) AS source_node_id,
            NULL AS target_node_id,
            'Fraud ring detected: ' || COUNT(*) || ' customers connected via shared beneficiaries/addresses/devices. Cluster: ' || cluster_label AS description,
            'Investigate all members of ' || cluster_label || '. File SAR if structuring confirmed. Consider transaction holds pending review.' AS suggested_action,
            'OPEN' AS status
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_ENTITY_CLUSTERS
        WHERE cluster_label LIKE 'FRAUD_RING_%'
        GROUP BY cluster_label
    ) AS src
    ON tgt.recommendation_id = src.recommendation_id
    WHEN MATCHED THEN UPDATE SET
        tgt.description = src.description,
        tgt.suggested_action = src.suggested_action
    WHEN NOT MATCHED THEN INSERT (recommendation_id, recommendation_type, severity, source_node_id, target_node_id, description, suggested_action, status)
        VALUES (src.recommendation_id, src.recommendation_type, src.severity, src.source_node_id, src.target_node_id, src.description, src.suggested_action, src.status);

    SELECT COUNT(*) INTO :v_recommendations
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS
    WHERE recommendation_id LIKE 'FIN_FRAUD_RING_%';

    DROP TABLE IF EXISTS DCA_DEMO.GOVERNANCE.TMP_FRAUD_CLUSTERS;

    RETURN 'Fraud ring detection complete. Rings found: ' || :v_clusters_found ||
           ', Recommendations generated: ' || :v_recommendations;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 2: SP_FINTECH_AML_SCORING
-- ═══════════════════════════════════════════════════════════════════════════
-- Customer risk scoring based on:
--   - Transaction velocity (25%)
--   - Network risk / watchlist proximity (30%)
--   - KYC freshness (20%)
--   - Corridor risk (15%)
--   - Structuring indicator (10%)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_FINTECH_AML_SCORING()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_scored_customers INTEGER DEFAULT 0;
    v_high_risk INTEGER DEFAULT 0;
BEGIN
    -- Score each CUSTOMER node on AML risk dimensions
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES AS tgt
    USING (
        SELECT
            n.node_id,
            -- Dimension 1: Transaction velocity (outgoing edge count as proxy)
            LEAST(1.0, COALESCE(txn.edge_count, 0) / 50.0) AS velocity_score,
            -- Dimension 2: Network risk (proximity to watchlist entities)
            CASE
                WHEN EXISTS (
                    SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e1
                    JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES wl ON e1.target_node_id = wl.node_id
                    WHERE e1.source_node_id = n.node_id
                      AND wl.node_type = 'WATCHLIST_ENTITY'
                ) THEN 1.0  -- Direct match (1 hop)
                WHEN EXISTS (
                    SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e1
                    JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e2 ON e1.target_node_id = e2.source_node_id
                    JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES wl ON e2.target_node_id = wl.node_id
                    WHERE e1.source_node_id = n.node_id
                      AND wl.node_type = 'WATCHLIST_ENTITY'
                ) THEN 0.7  -- 2 hops
                WHEN EXISTS (
                    SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e1
                    JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e2 ON e1.target_node_id = e2.source_node_id
                    JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e3 ON e2.target_node_id = e3.source_node_id
                    JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES wl ON e3.target_node_id = wl.node_id
                    WHERE e1.source_node_id = n.node_id
                      AND wl.node_type = 'WATCHLIST_ENTITY'
                ) THEN 0.4  -- 3 hops
                ELSE 0.0
            END AS network_risk_score,
            -- Dimension 3: KYC freshness (stale = high risk)
            CASE
                WHEN n.properties:"last_kyc_date" IS NOT NULL THEN
                    LEAST(1.0, DATEDIFF('day', TRY_TO_DATE(n.properties:"last_kyc_date"::VARCHAR), CURRENT_DATE()) / 1095.0)
                WHEN EXISTS (
                    SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
                    WHERE e.source_node_id = n.node_id AND e.edge_type = 'KYC_VERIFIED'
                ) THEN 0.3
                ELSE 0.8  -- No KYC evidence at all
            END AS kyc_staleness_score,
            -- Dimension 4: Corridor risk (based on connected corridors)
            COALESCE(cor.max_risk, 0.2) AS corridor_risk_score,
            -- Dimension 5: Structuring indicator (from properties or edge patterns)
            CASE
                WHEN n.properties:"avg_transaction" IS NOT NULL
                     AND n.properties:"avg_transaction"::FLOAT BETWEEN 2800 AND 2999
                THEN 0.9
                WHEN shares.share_count > 2 THEN 0.7
                ELSE 0.1
            END AS structuring_score,
            -- Weighted composite: velocity(25%) + network(30%) + kyc(20%) + corridor(15%) + structuring(10%)
            ROUND(
                0.25 * LEAST(1.0, COALESCE(txn.edge_count, 0) / 50.0) +
                0.30 * CASE
                    WHEN EXISTS (SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e1 JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES wl ON e1.target_node_id = wl.node_id WHERE e1.source_node_id = n.node_id AND wl.node_type = 'WATCHLIST_ENTITY') THEN 1.0
                    WHEN EXISTS (SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e1 JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e2 ON e1.target_node_id = e2.source_node_id JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES wl ON e2.target_node_id = wl.node_id WHERE e1.source_node_id = n.node_id AND wl.node_type = 'WATCHLIST_ENTITY') THEN 0.7
                    WHEN EXISTS (SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e1 JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e2 ON e1.target_node_id = e2.source_node_id JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e3 ON e2.target_node_id = e3.source_node_id JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES wl ON e3.target_node_id = wl.node_id WHERE e1.source_node_id = n.node_id AND wl.node_type = 'WATCHLIST_ENTITY') THEN 0.4
                    ELSE 0.0 END +
                0.20 * CASE
                    WHEN n.properties:"last_kyc_date" IS NOT NULL THEN LEAST(1.0, DATEDIFF('day', TRY_TO_DATE(n.properties:"last_kyc_date"::VARCHAR), CURRENT_DATE()) / 1095.0)
                    WHEN EXISTS (SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e WHERE e.source_node_id = n.node_id AND e.edge_type = 'KYC_VERIFIED') THEN 0.3
                    ELSE 0.8 END +
                0.15 * COALESCE(cor.max_risk, 0.2) +
                0.10 * CASE
                    WHEN n.properties:"avg_transaction" IS NOT NULL AND n.properties:"avg_transaction"::FLOAT BETWEEN 2800 AND 2999 THEN 0.9
                    WHEN shares.share_count > 2 THEN 0.7
                    ELSE 0.1 END
            , 3) AS overall_score
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
        -- Transaction velocity: count outgoing edges
        LEFT JOIN (
            SELECT source_node_id, COUNT(*) AS edge_count
            FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
            WHERE edge_type IN ('SENDS_TO', 'TRANSACTS_VIA')
            GROUP BY source_node_id
        ) txn ON n.node_id = txn.source_node_id
        -- Corridor risk: max risk level of connected corridors
        LEFT JOIN (
            SELECT e.source_node_id,
                   MAX(CASE
                       WHEN cor_n.properties:"risk_level"::VARCHAR = 'HIGH' THEN 0.8
                       WHEN cor_n.properties:"risk_level"::VARCHAR = 'PROHIBITED' THEN 1.0
                       WHEN cor_n.properties:"risk_level"::VARCHAR = 'MEDIUM' THEN 0.5
                       ELSE 0.2
                   END) AS max_risk
            FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
            JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES cor_n ON e.target_node_id = cor_n.node_id
            WHERE e.edge_type = 'ROUTED_THROUGH' AND cor_n.node_type = 'CORRIDOR'
            GROUP BY e.source_node_id
        ) cor ON n.node_id = cor.source_node_id
        -- Structuring: shared beneficiary count
        LEFT JOIN (
            SELECT source_node_id, COUNT(*) AS share_count
            FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
            WHERE edge_type = 'SHARES_BENEFICIARY'
            GROUP BY source_node_id
        ) shares ON n.node_id = shares.source_node_id
        WHERE n.node_type = 'CUSTOMER'
          AND n.layer = 'BUSINESS'
    ) AS src
    ON tgt.node_id = src.node_id
    WHEN MATCHED THEN UPDATE SET
        tgt.overall_score = src.overall_score,
        tgt.tag_coverage = src.kyc_staleness_score,
        tgt.contract_coverage = src.velocity_score,
        tgt.ownership_score = src.network_risk_score,
        tgt.quality_score = src.structuring_score,
        tgt.scored_at = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN INSERT (node_id, overall_score, tag_coverage, contract_coverage, ownership_score, quality_score, scored_at)
        VALUES (src.node_id, src.overall_score, src.kyc_staleness_score, src.velocity_score, src.network_risk_score, src.structuring_score, CURRENT_TIMESTAMP());

    SELECT COUNT(*) INTO :v_scored_customers
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES s
    JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n ON s.node_id = n.node_id
    WHERE n.node_type = 'CUSTOMER';

    -- Generate recommendations for high-risk customers (score > 0.7)
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS AS tgt
    USING (
        SELECT
            'FIN_AML_' || MD5(s.node_id) AS recommendation_id,
            'AML_HIGH_RISK' AS recommendation_type,
            CASE WHEN s.overall_score > 0.85 THEN 'HIGH' ELSE 'MEDIUM' END AS severity,
            s.node_id AS source_node_id,
            NULL AS target_node_id,
            'Customer ' || n.display_name || ' scored ' || ROUND(s.overall_score, 2) ||
            ' on AML risk (threshold: 0.7). Key factors: network_risk=' || ROUND(s.ownership_score, 2) ||
            ', kyc_staleness=' || ROUND(s.tag_coverage, 2) ||
            ', structuring=' || ROUND(s.quality_score, 2) AS description,
            'Initiate Enhanced Due Diligence (EDD). Review transaction patterns and network connections. Consider SAR filing if structuring confirmed.' AS suggested_action,
            'OPEN' AS status
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES s
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n ON s.node_id = n.node_id
        WHERE n.node_type = 'CUSTOMER' AND s.overall_score > 0.7
    ) AS src
    ON tgt.recommendation_id = src.recommendation_id
    WHEN MATCHED THEN UPDATE SET
        tgt.severity = src.severity,
        tgt.description = src.description
    WHEN NOT MATCHED THEN INSERT (recommendation_id, recommendation_type, severity, source_node_id, target_node_id, description, suggested_action, status)
        VALUES (src.recommendation_id, src.recommendation_type, src.severity, src.source_node_id, src.target_node_id, src.description, src.suggested_action, src.status);

    SELECT COUNT(*) INTO :v_high_risk
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS
    WHERE recommendation_id LIKE 'FIN_AML_%';

    RETURN 'AML scoring complete. Customers scored: ' || :v_scored_customers ||
           ', High-risk flagged: ' || :v_high_risk;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 3: SP_FINTECH_SANCTIONS_SCREENING
-- ═══════════════════════════════════════════════════════════════════════════
-- Graph traversal for sanctions detection:
--   - Direct: CUSTOMER/BENEFICIARY → MATCHED_WATCHLIST → WATCHLIST_ENTITY
--   - Indirect: CUSTOMER → SENDS_TO → BENEFICIARY → MATCHED_WATCHLIST
--   - Ownership: CUSTOMER → OWNS → ENTITY → CONTROLS → ENTITY → MATCHED_WATCHLIST
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_FINTECH_SANCTIONS_SCREENING()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_direct_matches INTEGER DEFAULT 0;
    v_indirect_matches INTEGER DEFAULT 0;
    v_ownership_matches INTEGER DEFAULT 0;
BEGIN
    -- Direct sanctions matches (1 hop: node → MATCHED_WATCHLIST → watchlist)
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS AS tgt
    USING (
        SELECT
            'FIN_SANC_DIRECT_' || MD5(n.node_id || wl.node_id) AS recommendation_id,
            'SANCTIONS_MATCH' AS recommendation_type,
            'HIGH' AS severity,
            n.node_id AS source_node_id,
            wl.node_id AS target_node_id,
            'DIRECT sanctions match: ' || n.display_name || ' (' || n.node_type || ') matched to watchlist entity "' ||
            wl.display_name || '" (list: ' || COALESCE(wl.properties:"list_type"::VARCHAR, 'UNKNOWN') || ').' AS description,
            'IMMEDIATE ACTION: Block all transactions. Notify BSA Officer. File SAR within 24 hours. Report to OFAC if SDN match.' AS suggested_action,
            'OPEN' AS status
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n ON e.source_node_id = n.node_id
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES wl ON e.target_node_id = wl.node_id
        WHERE e.edge_type = 'MATCHED_WATCHLIST'
          AND wl.node_type = 'WATCHLIST_ENTITY'
          AND n.node_type IN ('CUSTOMER', 'BENEFICIARY', 'ENTITY')
    ) AS src
    ON tgt.recommendation_id = src.recommendation_id
    WHEN MATCHED THEN UPDATE SET
        tgt.description = src.description,
        tgt.severity = src.severity
    WHEN NOT MATCHED THEN INSERT (recommendation_id, recommendation_type, severity, source_node_id, target_node_id, description, suggested_action, status)
        VALUES (src.recommendation_id, src.recommendation_type, src.severity, src.source_node_id, src.target_node_id, src.description, src.suggested_action, src.status);

    SELECT COUNT(*) INTO :v_direct_matches
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS
    WHERE recommendation_id LIKE 'FIN_SANC_DIRECT_%';

    -- Indirect sanctions (2 hops: CUSTOMER → SENDS_TO → BENEFICIARY → MATCHED_WATCHLIST → WATCHLIST)
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS AS tgt
    USING (
        SELECT
            'FIN_SANC_INDIRECT_' || MD5(cust.node_id || wl.node_id) AS recommendation_id,
            'SANCTIONS_MATCH' AS recommendation_type,
            'MEDIUM' AS severity,
            cust.node_id AS source_node_id,
            wl.node_id AS target_node_id,
            'INDIRECT sanctions proximity: Customer "' || cust.display_name ||
            '" sends money to beneficiary "' || ben.display_name ||
            '" who is matched to watchlist entity "' || wl.display_name ||
            '" (2 hops). List: ' || COALESCE(wl.properties:"list_type"::VARCHAR, 'UNKNOWN') || '.' AS description,
            'Enhanced Due Diligence required. Review all transactions to this beneficiary. Consider relationship termination.' AS suggested_action,
            'OPEN' AS status
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e1
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES cust ON e1.source_node_id = cust.node_id
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES ben ON e1.target_node_id = ben.node_id
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e2 ON ben.node_id = e2.source_node_id
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES wl ON e2.target_node_id = wl.node_id
        WHERE e1.edge_type = 'SENDS_TO'
          AND e2.edge_type = 'MATCHED_WATCHLIST'
          AND cust.node_type = 'CUSTOMER'
          AND wl.node_type = 'WATCHLIST_ENTITY'
    ) AS src
    ON tgt.recommendation_id = src.recommendation_id
    WHEN MATCHED THEN UPDATE SET
        tgt.description = src.description,
        tgt.severity = src.severity
    WHEN NOT MATCHED THEN INSERT (recommendation_id, recommendation_type, severity, source_node_id, target_node_id, description, suggested_action, status)
        VALUES (src.recommendation_id, src.recommendation_type, src.severity, src.source_node_id, src.target_node_id, src.description, src.suggested_action, src.status);

    SELECT COUNT(*) INTO :v_indirect_matches
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS
    WHERE recommendation_id LIKE 'FIN_SANC_INDIRECT_%';

    -- Ownership chain traversal (3 hops: CUSTOMER → OWNS → ENTITY → CONTROLS → ENTITY → MATCHED_WATCHLIST)
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS AS tgt
    USING (
        SELECT
            'FIN_SANC_OWNERSHIP_' || MD5(cust.node_id || wl.node_id) AS recommendation_id,
            'SANCTIONS_MATCH' AS recommendation_type,
            'HIGH' AS severity,
            cust.node_id AS source_node_id,
            wl.node_id AS target_node_id,
            'OWNERSHIP CHAIN sanctions exposure: Customer "' || cust.display_name ||
            '" → OWNS → "' || ent1.display_name ||
            '" → CONTROLS → "' || ent2.display_name ||
            '" → MATCHED_WATCHLIST → "' || wl.display_name ||
            '" (3 hops via beneficial ownership). Name-matching would NOT detect this.' AS description,
            'CRITICAL: Beneficial ownership chain connects customer to sanctioned/PEP entity. Full CDD review. Consider blocking. File SAR.' AS suggested_action,
            'OPEN' AS status
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e1
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES cust ON e1.source_node_id = cust.node_id
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES ent1 ON e1.target_node_id = ent1.node_id
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e2 ON ent1.node_id = e2.source_node_id
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES ent2 ON e2.target_node_id = ent2.node_id
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e3 ON ent2.node_id = e3.source_node_id
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES wl ON e3.target_node_id = wl.node_id
        WHERE e1.edge_type = 'OWNS'
          AND e2.edge_type = 'CONTROLS'
          AND e3.edge_type = 'MATCHED_WATCHLIST'
          AND cust.node_type = 'CUSTOMER'
          AND wl.node_type = 'WATCHLIST_ENTITY'
    ) AS src
    ON tgt.recommendation_id = src.recommendation_id
    WHEN MATCHED THEN UPDATE SET
        tgt.description = src.description,
        tgt.severity = src.severity
    WHEN NOT MATCHED THEN INSERT (recommendation_id, recommendation_type, severity, source_node_id, target_node_id, description, suggested_action, status)
        VALUES (src.recommendation_id, src.recommendation_type, src.severity, src.source_node_id, src.target_node_id, src.description, src.suggested_action, src.status);

    SELECT COUNT(*) INTO :v_ownership_matches
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS
    WHERE recommendation_id LIKE 'FIN_SANC_OWNERSHIP_%';

    RETURN 'Sanctions screening complete. Direct matches: ' || :v_direct_matches ||
           ', Indirect (2-hop): ' || :v_indirect_matches ||
           ', Ownership chain (3-hop): ' || :v_ownership_matches;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 4: SP_FINTECH_CORRIDOR_RISK
-- ═══════════════════════════════════════════════════════════════════════════
-- Corridor-level scoring:
--   - Sanctioned-country adjacency (30%)
--   - Volume deviation (25%)
--   - Concentration HHI (20%)
--   - SAR density (15%)
--   - Regulatory designation (10%)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_FINTECH_CORRIDOR_RISK()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_scored_corridors INTEGER DEFAULT 0;
    v_high_risk_corridors INTEGER DEFAULT 0;
BEGIN
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES AS tgt
    USING (
        SELECT
            n.node_id,
            -- Sanctioned-country adjacency (30%)
            CASE
                WHEN n.properties:"destination_country"::VARCHAR IN ('DPRK', 'IR', 'SY', 'CU', 'VE') THEN 1.0
                WHEN n.properties:"risk_level"::VARCHAR = 'PROHIBITED' THEN 1.0
                WHEN n.properties:"risk_level"::VARCHAR = 'HIGH' THEN 0.7
                WHEN n.properties:"risk_level"::VARCHAR = 'MEDIUM' THEN 0.4
                ELSE 0.1
            END AS sanctions_adjacency,
            -- Volume deviation (25%) — proxy from properties
            CASE
                WHEN n.properties:"avg_monthly_volume"::FLOAT > 10000000 THEN 0.6
                WHEN n.properties:"avg_monthly_volume"::FLOAT > 5000000 THEN 0.4
                ELSE 0.2
            END AS volume_deviation,
            -- Concentration HHI (20%) — based on transaction count through corridor
            LEAST(1.0, COALESCE(txn_count.cnt, 0) / 100.0) AS concentration_hhi,
            -- SAR density (15%) — SARs per transaction on this corridor
            CASE
                WHEN n.properties:"risk_level"::VARCHAR = 'HIGH' THEN 0.6
                WHEN n.properties:"risk_level"::VARCHAR = 'PROHIBITED' THEN 0.9
                ELSE 0.2
            END AS sar_density,
            -- Regulatory designation (10%)
            CASE
                WHEN n.properties:"risk_level"::VARCHAR = 'PROHIBITED' THEN 1.0
                WHEN n.properties:"risk_level"::VARCHAR = 'HIGH' THEN 0.7
                ELSE 0.1
            END AS regulatory_designation,
            -- Weighted composite
            ROUND(
                0.30 * CASE
                    WHEN n.properties:"destination_country"::VARCHAR IN ('DPRK', 'IR', 'SY', 'CU', 'VE') THEN 1.0
                    WHEN n.properties:"risk_level"::VARCHAR = 'PROHIBITED' THEN 1.0
                    WHEN n.properties:"risk_level"::VARCHAR = 'HIGH' THEN 0.7
                    WHEN n.properties:"risk_level"::VARCHAR = 'MEDIUM' THEN 0.4
                    ELSE 0.1 END +
                0.25 * CASE
                    WHEN n.properties:"avg_monthly_volume"::FLOAT > 10000000 THEN 0.6
                    WHEN n.properties:"avg_monthly_volume"::FLOAT > 5000000 THEN 0.4
                    ELSE 0.2 END +
                0.20 * LEAST(1.0, COALESCE(txn_count.cnt, 0) / 100.0) +
                0.15 * CASE
                    WHEN n.properties:"risk_level"::VARCHAR = 'HIGH' THEN 0.6
                    WHEN n.properties:"risk_level"::VARCHAR = 'PROHIBITED' THEN 0.9
                    ELSE 0.2 END +
                0.10 * CASE
                    WHEN n.properties:"risk_level"::VARCHAR = 'PROHIBITED' THEN 1.0
                    WHEN n.properties:"risk_level"::VARCHAR = 'HIGH' THEN 0.7
                    ELSE 0.1 END
            , 3) AS overall_score
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
        LEFT JOIN (
            SELECT target_node_id, COUNT(*) AS cnt
            FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
            WHERE edge_type = 'ROUTED_THROUGH'
            GROUP BY target_node_id
        ) txn_count ON n.node_id = txn_count.target_node_id
        WHERE n.node_type = 'CORRIDOR'
    ) AS src
    ON tgt.node_id = src.node_id
    WHEN MATCHED THEN UPDATE SET
        tgt.overall_score = src.overall_score,
        tgt.tag_coverage = src.sanctions_adjacency,
        tgt.contract_coverage = src.volume_deviation,
        tgt.ownership_score = src.concentration_hhi,
        tgt.quality_score = src.sar_density,
        tgt.scored_at = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN INSERT (node_id, overall_score, tag_coverage, contract_coverage, ownership_score, quality_score, scored_at)
        VALUES (src.node_id, src.overall_score, src.sanctions_adjacency, src.volume_deviation, src.concentration_hhi, src.sar_density, CURRENT_TIMESTAMP());

    SELECT COUNT(*) INTO :v_scored_corridors
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES s
    JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n ON s.node_id = n.node_id
    WHERE n.node_type = 'CORRIDOR';

    -- Generate recommendations for high-risk corridors
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS AS tgt
    USING (
        SELECT
            'FIN_CORRIDOR_' || MD5(s.node_id) AS recommendation_id,
            'CORRIDOR_HIGH_RISK' AS recommendation_type,
            CASE WHEN s.overall_score > 0.7 THEN 'HIGH' ELSE 'MEDIUM' END AS severity,
            s.node_id AS source_node_id,
            NULL AS target_node_id,
            'Corridor "' || n.display_name || '" scored ' || ROUND(s.overall_score, 2) ||
            ' on risk assessment. Sanctions adjacency: ' || ROUND(s.tag_coverage, 2) ||
            ', Volume factor: ' || ROUND(s.contract_coverage, 2) || '.' AS description,
            'Review corridor controls. Consider enhanced monitoring, transaction limits, or corridor suspension if sanctioned-country adjacent.' AS suggested_action,
            'OPEN' AS status
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES s
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n ON s.node_id = n.node_id
        WHERE n.node_type = 'CORRIDOR' AND s.overall_score > 0.5
    ) AS src
    ON tgt.recommendation_id = src.recommendation_id
    WHEN MATCHED THEN UPDATE SET
        tgt.description = src.description,
        tgt.severity = src.severity
    WHEN NOT MATCHED THEN INSERT (recommendation_id, recommendation_type, severity, source_node_id, target_node_id, description, suggested_action, status)
        VALUES (src.recommendation_id, src.recommendation_type, src.severity, src.source_node_id, src.target_node_id, src.description, src.suggested_action, src.status);

    SELECT COUNT(*) INTO :v_high_risk_corridors
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS
    WHERE recommendation_id LIKE 'FIN_CORRIDOR_%';

    RETURN 'Corridor risk scoring complete. Corridors scored: ' || :v_scored_corridors ||
           ', High-risk flagged: ' || :v_high_risk_corridors;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 5: SP_FINTECH_AGENT_COMPLIANCE
-- ═══════════════════════════════════════════════════════════════════════════
-- Agent compliance scoring:
--   - Volume anomaly (25%)
--   - SAR filing rate (25%)
--   - KYC completion (20%)
--   - Structuring at agent (20%)
--   - Regulatory history (10%)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_FINTECH_AGENT_COMPLIANCE()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_scored_agents INTEGER DEFAULT 0;
    v_high_risk_agents INTEGER DEFAULT 0;
BEGIN
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES AS tgt
    USING (
        SELECT
            n.node_id,
            -- Volume anomaly (25%): current vs average
            CASE
                WHEN n.properties:"volume_multiplier" IS NOT NULL THEN
                    LEAST(1.0, n.properties:"volume_multiplier"::FLOAT / 10.0)
                WHEN n.properties:"current_month_volume" IS NOT NULL AND n.properties:"avg_monthly_volume" IS NOT NULL
                     AND n.properties:"avg_monthly_volume"::FLOAT > 0 THEN
                    LEAST(1.0, (n.properties:"current_month_volume"::FLOAT / n.properties:"avg_monthly_volume"::FLOAT) / 10.0)
                ELSE 0.2
            END AS volume_anomaly,
            -- SAR filing rate (25%): should file when suspicious patterns detected
            CASE
                WHEN n.properties:"suspicious_patterns" IS NOT NULL
                     AND n.properties:"suspicious_patterns"::INTEGER > 0
                     AND COALESCE(n.properties:"sar_filed_count"::INTEGER, 0) = 0
                THEN 1.0  -- Suspicious patterns but no SARs = highest risk
                WHEN n.properties:"sar_filed_count" IS NOT NULL
                     AND n.properties:"sar_filed_count"::INTEGER > 0
                THEN 0.2  -- Filing SARs = lower risk
                ELSE 0.4  -- Unknown
            END AS sar_filing_risk,
            -- KYC completion (20%): % of customers with current KYC
            CASE
                WHEN n.properties:"kyc_completion_rate" IS NOT NULL THEN
                    1.0 - n.properties:"kyc_completion_rate"::FLOAT  -- Lower completion = higher risk
                ELSE 0.5
            END AS kyc_incompletion,
            -- Structuring at agent (20%): sub-threshold transaction patterns
            LEAST(1.0, COALESCE(struct_edges.cnt, 0) / 5.0) AS structuring_score,
            -- Regulatory history (10%)
            CASE
                WHEN n.properties:"prior_violations" IS NOT NULL
                     AND n.properties:"prior_violations"::INTEGER > 0
                THEN 0.8
                ELSE 0.1
            END AS regulatory_history,
            -- Weighted composite
            ROUND(
                0.25 * CASE
                    WHEN n.properties:"volume_multiplier" IS NOT NULL THEN LEAST(1.0, n.properties:"volume_multiplier"::FLOAT / 10.0)
                    WHEN n.properties:"current_month_volume" IS NOT NULL AND n.properties:"avg_monthly_volume" IS NOT NULL AND n.properties:"avg_monthly_volume"::FLOAT > 0
                        THEN LEAST(1.0, (n.properties:"current_month_volume"::FLOAT / n.properties:"avg_monthly_volume"::FLOAT) / 10.0)
                    ELSE 0.2 END +
                0.25 * CASE
                    WHEN n.properties:"suspicious_patterns" IS NOT NULL AND n.properties:"suspicious_patterns"::INTEGER > 0 AND COALESCE(n.properties:"sar_filed_count"::INTEGER, 0) = 0 THEN 1.0
                    WHEN n.properties:"sar_filed_count" IS NOT NULL AND n.properties:"sar_filed_count"::INTEGER > 0 THEN 0.2
                    ELSE 0.4 END +
                0.20 * CASE
                    WHEN n.properties:"kyc_completion_rate" IS NOT NULL THEN 1.0 - n.properties:"kyc_completion_rate"::FLOAT
                    ELSE 0.5 END +
                0.20 * LEAST(1.0, COALESCE(struct_edges.cnt, 0) / 5.0) +
                0.10 * CASE
                    WHEN n.properties:"prior_violations" IS NOT NULL AND n.properties:"prior_violations"::INTEGER > 0 THEN 0.8
                    ELSE 0.1 END
            , 3) AS overall_score
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
        -- Count structuring-indicator edges at this agent
        LEFT JOIN (
            SELECT e_via.target_node_id AS agent_node_id, COUNT(*) AS cnt
            FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e_via
            JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e_share
                ON e_via.source_node_id = e_share.source_node_id
            WHERE e_via.edge_type = 'TRANSACTS_VIA'
              AND e_share.edge_type IN ('SHARES_BENEFICIARY', 'SHARES_ADDRESS', 'SHARES_DEVICE')
            GROUP BY e_via.target_node_id
        ) struct_edges ON n.node_id = struct_edges.agent_node_id
        WHERE n.node_type = 'AGENT'
    ) AS src
    ON tgt.node_id = src.node_id
    WHEN MATCHED THEN UPDATE SET
        tgt.overall_score = src.overall_score,
        tgt.tag_coverage = src.volume_anomaly,
        tgt.contract_coverage = src.sar_filing_risk,
        tgt.ownership_score = src.kyc_incompletion,
        tgt.quality_score = src.structuring_score,
        tgt.scored_at = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN INSERT (node_id, overall_score, tag_coverage, contract_coverage, ownership_score, quality_score, scored_at)
        VALUES (src.node_id, src.overall_score, src.volume_anomaly, src.sar_filing_risk, src.kyc_incompletion, src.structuring_score, CURRENT_TIMESTAMP());

    SELECT COUNT(*) INTO :v_scored_agents
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES s
    JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n ON s.node_id = n.node_id
    WHERE n.node_type = 'AGENT';

    -- Generate recommendations for high-risk agents
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS AS tgt
    USING (
        SELECT
            'FIN_AGENT_' || MD5(s.node_id) AS recommendation_id,
            'AGENT_COMPLIANCE' AS recommendation_type,
            CASE WHEN s.overall_score > 0.7 THEN 'HIGH' ELSE 'MEDIUM' END AS severity,
            s.node_id AS source_node_id,
            NULL AS target_node_id,
            'Agent "' || n.display_name || '" scored ' || ROUND(s.overall_score, 2) ||
            ' on compliance risk. Volume anomaly: ' || ROUND(s.tag_coverage, 2) ||
            ', SAR filing gap: ' || ROUND(s.contract_coverage, 2) ||
            ', KYC incomplete: ' || ROUND(s.ownership_score, 2) || '.' AS description,
            'Immediate compliance review. If volume anomaly > 5x with no SARs filed, consider agent suspension pending investigation.' AS suggested_action,
            'OPEN' AS status
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES s
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n ON s.node_id = n.node_id
        WHERE n.node_type = 'AGENT' AND s.overall_score > 0.5
    ) AS src
    ON tgt.recommendation_id = src.recommendation_id
    WHEN MATCHED THEN UPDATE SET
        tgt.description = src.description,
        tgt.severity = src.severity
    WHEN NOT MATCHED THEN INSERT (recommendation_id, recommendation_type, severity, source_node_id, target_node_id, description, suggested_action, status)
        VALUES (src.recommendation_id, src.recommendation_type, src.severity, src.source_node_id, src.target_node_id, src.description, src.suggested_action, src.status);

    SELECT COUNT(*) INTO :v_high_risk_agents
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS
    WHERE recommendation_id LIKE 'FIN_AGENT_%';

    RETURN 'Agent compliance scoring complete. Agents scored: ' || :v_scored_agents ||
           ', High-risk flagged: ' || :v_high_risk_agents;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 6: SP_FINTECH_RUN_ALL
-- ═══════════════════════════════════════════════════════════════════════════
-- Orchestrator: runs graph population + all 5 inference procedures.
-- Records a snapshot and returns summary.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_FINTECH_RUN_ALL()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_result_graph VARCHAR;
    v_result_rings VARCHAR;
    v_result_aml VARCHAR;
    v_result_sanctions VARCHAR;
    v_result_corridor VARCHAR;
    v_result_agent VARCHAR;
    v_snapshot_id INTEGER;
BEGIN
    -- Step 1: Populate payment graph
    CALL DCA_DEMO.GOVERNANCE.SP_FINTECH_POPULATE_PAYMENT_GRAPH();
    SELECT * INTO :v_result_graph FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    -- Step 2: Fraud ring detection
    CALL DCA_DEMO.GOVERNANCE.SP_FINTECH_FRAUD_RINGS();
    SELECT * INTO :v_result_rings FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    -- Step 3: AML scoring
    CALL DCA_DEMO.GOVERNANCE.SP_FINTECH_AML_SCORING();
    SELECT * INTO :v_result_aml FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    -- Step 4: Sanctions screening
    CALL DCA_DEMO.GOVERNANCE.SP_FINTECH_SANCTIONS_SCREENING();
    SELECT * INTO :v_result_sanctions FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    -- Step 5: Corridor risk scoring
    CALL DCA_DEMO.GOVERNANCE.SP_FINTECH_CORRIDOR_RISK();
    SELECT * INTO :v_result_corridor FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    -- Step 6: Agent compliance scoring
    CALL DCA_DEMO.GOVERNANCE.SP_FINTECH_AGENT_COMPLIANCE();
    SELECT * INTO :v_result_agent FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    -- Step 7: Record snapshot
    INSERT INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SNAPSHOTS (node_count, edge_count, metadata)
    SELECT
        (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES WHERE node_id LIKE 'FIN_%' OR node_id LIKE 'FIN_GAP_%'),
        (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES WHERE edge_id LIKE 'FIN_%' OR edge_id LIKE 'FIN_GAP_%'),
        OBJECT_CONSTRUCT(
            'pipeline', 'FINTECH_RAI',
            'graph_result', :v_result_graph,
            'fraud_rings_result', :v_result_rings,
            'aml_result', :v_result_aml,
            'sanctions_result', :v_result_sanctions,
            'corridor_result', :v_result_corridor,
            'agent_result', :v_result_agent,
            'node_count', (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES WHERE node_id LIKE 'FIN_%'),
            'edge_count', (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES WHERE edge_id LIKE 'FIN_%'),
            'recommendations_count', (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS WHERE recommendation_id LIKE 'FIN_%')
        );

    RETURN 'Fintech RAI pipeline complete.' || CHR(10) ||
           '  Graph: ' || :v_result_graph || CHR(10) ||
           '  Fraud Rings: ' || :v_result_rings || CHR(10) ||
           '  AML Scoring: ' || :v_result_aml || CHR(10) ||
           '  Sanctions: ' || :v_result_sanctions || CHR(10) ||
           '  Corridor Risk: ' || :v_result_corridor || CHR(10) ||
           '  Agent Compliance: ' || :v_result_agent;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'Fintech Financial Crime RAI inference procedures created successfully' AS status;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_FINTECH_FRAUD_RINGS() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_FINTECH_AML_SCORING() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_FINTECH_SANCTIONS_SCREENING() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_FINTECH_CORRIDOR_RISK() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_FINTECH_AGENT_COMPLIANCE() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_FINTECH_RUN_ALL() TO ROLE ONTOLOGY_ADMIN;
