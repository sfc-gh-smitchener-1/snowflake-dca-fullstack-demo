-- ============================================================================
-- HCLS KNOWLEDGE GRAPH — COMORBIDITY INDEXING & PAYER RESPONSE ANALYTICS
-- ============================================================================
-- Computes Charlson Comorbidity Index per patient, identifies co-occurring
-- conditions, analyzes payer adjudication patterns by comorbidity tier,
-- and populates the Knowledge Graph with payer domain edges.
--
-- Prerequisites: scripts 01 + 04 deployed, FHIR + Payer data loaded
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE DCA_DEMO;
USE SCHEMA GOVERNANCE;
USE WAREHOUSE COMPUTE_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 1: SP_HCLS_COMORBIDITY_INDEX
-- ═══════════════════════════════════════════════════════════════════════════
-- Computes the Charlson Comorbidity Index (CCI) for each patient using
-- ICD-10 code matching against the standardized Charlson category map.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_COMORBIDITY_INDEX()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_row_count INTEGER DEFAULT 0;
    v_cond_exists INTEGER DEFAULT 0;
BEGIN

    SELECT COUNT(*) INTO :v_cond_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'FHIR' AND table_name = 'FACT_CONDITIONS';

    IF (:v_cond_exists = 0) THEN
        RETURN 'Comorbidity index skipped — FACT_CONDITIONS not found.';
    END IF;

    CREATE OR REPLACE TABLE DCA_DEMO.GOVERNANCE.HCLS_PATIENT_COMORBIDITY AS
    WITH charlson_map AS (
        -- Weight 1 categories
        SELECT 'MI' AS category, 1 AS weight, code_prefix
        FROM (VALUES ('I21'), ('I22'), ('I252')) AS t(code_prefix)
        UNION ALL
        SELECT 'CHF', 1, code_prefix
        FROM (VALUES ('I50'), ('I110'), ('I130'), ('I132')) AS t(code_prefix)
        UNION ALL
        SELECT 'PVD', 1, code_prefix
        FROM (VALUES ('I70'), ('I71'), ('I73'), ('I771')) AS t(code_prefix)
        UNION ALL
        SELECT 'CVD', 1, code_prefix
        FROM (VALUES ('I6'), ('G45'), ('G46')) AS t(code_prefix)
        UNION ALL
        SELECT 'DEMENTIA', 1, code_prefix
        FROM (VALUES ('F00'), ('F01'), ('F02'), ('F03'), ('G30'), ('G311')) AS t(code_prefix)
        UNION ALL
        SELECT 'COPD', 1, code_prefix
        FROM (VALUES ('J40'), ('J41'), ('J42'), ('J43'), ('J44'), ('J45'), ('J46'), ('J47'),
                     ('J60'), ('J61'), ('J62'), ('J63'), ('J64'), ('J65'), ('J66'), ('J67')) AS t(code_prefix)
        UNION ALL
        SELECT 'RHEUMATIC', 1, code_prefix
        FROM (VALUES ('M05'), ('M06'), ('M32'), ('M33'), ('M34')) AS t(code_prefix)
        UNION ALL
        SELECT 'PEPTIC_ULCER', 1, code_prefix
        FROM (VALUES ('K25'), ('K26'), ('K27'), ('K28')) AS t(code_prefix)
        UNION ALL
        SELECT 'MILD_LIVER', 1, code_prefix
        FROM (VALUES ('B18'), ('K700'), ('K701'), ('K702'), ('K703'), ('K73'), ('K74'), ('K760')) AS t(code_prefix)
        UNION ALL
        SELECT 'DIABETES_UNCOMPLICATED', 1, code_prefix
        FROM (VALUES ('E100'), ('E101'), ('E109'), ('E110'), ('E111'), ('E119')) AS t(code_prefix)
        UNION ALL
        -- Weight 2 categories
        SELECT 'DIABETES_COMPLICATED', 2, code_prefix
        FROM (VALUES ('E102'), ('E103'), ('E104'), ('E105'), ('E106'), ('E107'), ('E108'),
                     ('E112'), ('E113'), ('E114'), ('E115'), ('E116'), ('E117'), ('E118')) AS t(code_prefix)
        UNION ALL
        SELECT 'HEMIPLEGIA', 2, code_prefix
        FROM (VALUES ('G041'), ('G114'), ('G80'), ('G81'), ('G82')) AS t(code_prefix)
        UNION ALL
        SELECT 'RENAL', 2, code_prefix
        FROM (VALUES ('N18'), ('N19'), ('N05'), ('I120'), ('I131')) AS t(code_prefix)
        UNION ALL
        SELECT 'MALIGNANCY', 2, code_prefix
        FROM (VALUES ('C0'), ('C1'), ('C2'), ('C30'), ('C31'), ('C32'), ('C33'), ('C34'),
                     ('C37'), ('C38'), ('C39'), ('C40'), ('C41'), ('C43'), ('C45'), ('C46'),
                     ('C47'), ('C48'), ('C49'), ('C5'), ('C60'), ('C61'), ('C62'), ('C63'),
                     ('C64'), ('C65'), ('C66'), ('C67'), ('C68'), ('C69'), ('C70'), ('C71'),
                     ('C72'), ('C73'), ('C74'), ('C75'), ('C76'),
                     ('C81'), ('C82'), ('C83'), ('C84'), ('C85'), ('C88'),
                     ('C90'), ('C91'), ('C92'), ('C93'), ('C94'), ('C95'), ('C96'), ('C97')) AS t(code_prefix)
        UNION ALL
        -- Weight 3 categories
        SELECT 'MODERATE_SEVERE_LIVER', 3, code_prefix
        FROM (VALUES ('K704'), ('K711'), ('K72'), ('K765'), ('K766'), ('K767'), ('I85')) AS t(code_prefix)
        UNION ALL
        -- Weight 6 categories
        SELECT 'METASTATIC', 6, code_prefix
        FROM (VALUES ('C77'), ('C78'), ('C79'), ('C80')) AS t(code_prefix)
        UNION ALL
        SELECT 'AIDS', 6, code_prefix
        FROM (VALUES ('B20'), ('B21'), ('B22'), ('B24')) AS t(code_prefix)
    ),
    patient_categories AS (
        SELECT DISTINCT
            c.PATIENT_ID,
            cm.category,
            cm.weight
        FROM CURATED_DEV.FHIR.FACT_CONDITIONS c
        JOIN charlson_map cm
            ON c.CODE LIKE cm.code_prefix || '%'
        WHERE c.PATIENT_ID IS NOT NULL
          AND c.CODE IS NOT NULL
    ),
    patient_cci AS (
        SELECT
            PATIENT_ID,
            SUM(weight) AS cci_score,
            COUNT(DISTINCT category) AS condition_count,
            ARRAY_AGG(DISTINCT category) AS top_conditions_array
        FROM patient_categories
        GROUP BY PATIENT_ID
    )
    SELECT
        PATIENT_ID AS patient_id,
        cci_score,
        CASE
            WHEN cci_score <= 1 THEN 'LOW'
            WHEN cci_score <= 3 THEN 'MODERATE'
            WHEN cci_score <= 6 THEN 'HIGH'
            ELSE 'SEVERE'
        END AS cci_tier,
        condition_count,
        TO_VARCHAR(top_conditions_array) AS top_conditions_json,
        CURRENT_TIMESTAMP() AS calculation_date
    FROM patient_cci;

    SELECT COUNT(*) INTO :v_row_count
    FROM DCA_DEMO.GOVERNANCE.HCLS_PATIENT_COMORBIDITY;

    RETURN 'Comorbidity index computed. Patients scored: ' || :v_row_count;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 2: SP_HCLS_COMORBIDITY_CLUSTERS
-- ═══════════════════════════════════════════════════════════════════════════
-- Identifies co-occurring condition pairs and creates COMORBID_WITH edges
-- in the Knowledge Graph between CONDITION nodes.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_COMORBIDITY_CLUSTERS()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_pair_count INTEGER DEFAULT 0;
    v_edge_count INTEGER DEFAULT 0;
    v_cond_exists INTEGER DEFAULT 0;
BEGIN

    SELECT COUNT(*) INTO :v_cond_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'FHIR' AND table_name = 'FACT_CONDITIONS';

    IF (:v_cond_exists = 0) THEN
        RETURN 'Comorbidity clusters skipped — FACT_CONDITIONS not found.';
    END IF;

    -- Build co-occurrence pairs
    CREATE OR REPLACE TABLE DCA_DEMO.GOVERNANCE.HCLS_COMORBIDITY_PAIRS AS
    WITH patient_conditions AS (
        SELECT DISTINCT
            PATIENT_ID,
            CODE AS icd10_code,
            COALESCE(CODE_DISPLAY, CODE) AS code_desc
        FROM CURATED_DEV.FHIR.FACT_CONDITIONS
        WHERE PATIENT_ID IS NOT NULL
          AND CODE IS NOT NULL
    ),
    condition_counts AS (
        SELECT icd10_code, COUNT(DISTINCT PATIENT_ID) AS patient_count
        FROM patient_conditions
        GROUP BY icd10_code
        HAVING patient_count >= 10
    ),
    pairs AS (
        SELECT
            a.icd10_code AS condition_a_code,
            a.code_desc AS condition_a_desc,
            b.icd10_code AS condition_b_code,
            b.code_desc AS condition_b_desc,
            COUNT(DISTINCT a.PATIENT_ID) AS shared_patient_count
        FROM patient_conditions a
        JOIN patient_conditions b
            ON a.PATIENT_ID = b.PATIENT_ID
            AND a.icd10_code < b.icd10_code
        WHERE a.icd10_code IN (SELECT icd10_code FROM condition_counts)
          AND b.icd10_code IN (SELECT icd10_code FROM condition_counts)
        GROUP BY 1, 2, 3, 4
    )
    SELECT
        p.condition_a_code,
        p.condition_a_desc,
        p.condition_b_code,
        p.condition_b_desc,
        p.shared_patient_count,
        ROUND(p.shared_patient_count::FLOAT / NULLIF(ca.patient_count, 0), 4) AS co_occurrence_rate
    FROM pairs p
    JOIN condition_counts ca ON p.condition_a_code = ca.icd10_code
    WHERE p.shared_patient_count::FLOAT / NULLIF(ca.patient_count, 0) > 0.05;

    SELECT COUNT(*) INTO :v_pair_count
    FROM DCA_DEMO.GOVERNANCE.HCLS_COMORBIDITY_PAIRS;

    -- Create COMORBID_WITH edges in Knowledge Graph
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT
            'PYR_COMRB_' || MD5(condition_a_code || condition_b_code) AS edge_id,
            'HCLS_DX_' || MD5(condition_a_code) AS source_node_id,
            'HCLS_DX_' || MD5(condition_b_code) AS target_node_id,
            'COMORBID_WITH' AS edge_type,
            'BUSINESS' AS layer,
            co_occurrence_rate AS weight,
            OBJECT_CONSTRUCT(
                'shared_patients', shared_patient_count,
                'co_occurrence_rate', co_occurrence_rate,
                'condition_a', condition_a_desc,
                'condition_b', condition_b_desc
            ) AS properties
        FROM DCA_DEMO.GOVERNANCE.HCLS_COMORBIDITY_PAIRS
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN MATCHED THEN UPDATE SET
        tgt.weight = src.weight,
        tgt.properties = src.properties
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight, properties)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight, src.properties);

    SELECT COUNT(*) INTO :v_edge_count
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
    WHERE edge_type = 'COMORBID_WITH' AND edge_id LIKE 'PYR_COMRB_%';

    RETURN 'Comorbidity clusters computed. Pairs: ' || :v_pair_count || ', COMORBID_WITH edges: ' || :v_edge_count;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 3: SP_HCLS_PAYER_RESPONSE
-- ═══════════════════════════════════════════════════════════════════════════
-- Analyzes payer adjudication patterns stratified by comorbidity tier,
-- computing denial rates, adjudication timing, and prior auth metrics.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_PAYER_RESPONSE()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_row_count INTEGER DEFAULT 0;
    v_cci_exists INTEGER DEFAULT 0;
    v_claims_exists INTEGER DEFAULT 0;
BEGIN

    SELECT COUNT(*) INTO :v_cci_exists
    FROM DCA_DEMO.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'GOVERNANCE' AND table_name = 'HCLS_PATIENT_COMORBIDITY';

    SELECT COUNT(*) INTO :v_claims_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'PAYER' AND table_name = 'FACT_CLAIMS_DETAIL';

    IF (:v_cci_exists = 0 OR :v_claims_exists = 0) THEN
        RETURN 'Payer response skipped — required tables not found (CCI: ' || :v_cci_exists || ', Claims: ' || :v_claims_exists || ').';
    END IF;

    CREATE OR REPLACE TABLE DCA_DEMO.GOVERNANCE.HCLS_PAYER_METRICS AS
    WITH claims_with_cci AS (
        SELECT
            cd.CLAIM_ID,
            cd.PATIENT_ID,
            cd.ENCOUNTER_ID,
            cd.PAYER_NAME,
            cd.PLAN_TYPE,
            cd.CLAIM_STATUS,
            cd.ADJUDICATION_STATUS,
            cd.PAID_AMOUNT,
            cd.PATIENT_RESPONSIBILITY,
            cd.SERVICE_DATE,
            cd.ADJUDICATION_DATE,
            DATEDIFF('day', cd.SERVICE_DATE, cd.ADJUDICATION_DATE) AS days_to_adjudicate,
            pc.cci_score,
            pc.cci_tier
        FROM CURATED_DEV.PAYER.FACT_CLAIMS_DETAIL cd
        JOIN DCA_DEMO.GOVERNANCE.HCLS_PATIENT_COMORBIDITY pc
            ON cd.PATIENT_ID = pc.patient_id
        WHERE cd.SERVICE_DATE IS NOT NULL
    ),
    prior_auth_stats AS (
        SELECT
            pa.PATIENT_ID,
            pa.ENCOUNTER_ID,
            COUNT(*) AS auth_count,
            SUM(CASE WHEN pa.AUTH_STATUS = 'APPROVED' THEN 1 ELSE 0 END) AS approved_count
        FROM CURATED_DEV.PAYER.FACT_PRIOR_AUTHORIZATIONS pa
        GROUP BY 1, 2
    )
    SELECT
        c.cci_tier,
        c.PAYER_NAME AS payer_name,
        c.PLAN_TYPE AS plan_type,
        ROUND(SUM(CASE WHEN c.ADJUDICATION_STATUS = 'DENIED' THEN 1 ELSE 0 END)::FLOAT
              / NULLIF(COUNT(*), 0), 4) AS denial_rate,
        ROUND(AVG(c.days_to_adjudicate), 1) AS avg_adjudication_days,
        ROUND(AVG(c.PAID_AMOUNT), 2) AS avg_paid,
        ROUND(SUM(CASE WHEN pa.auth_count > 0 THEN 1 ELSE 0 END)::FLOAT
              / NULLIF(COUNT(*), 0), 4) AS prior_auth_rate,
        ROUND(SUM(COALESCE(pa.approved_count, 0))::FLOAT
              / NULLIF(SUM(COALESCE(pa.auth_count, 0)), 0), 4) AS auth_approval_rate,
        ROUND(AVG(c.PATIENT_RESPONSIBILITY), 2) AS avg_patient_resp,
        COUNT(*) AS total_claims,
        DATE_TRUNC('month', MIN(c.SERVICE_DATE)) || ' to ' || DATE_TRUNC('month', MAX(c.SERVICE_DATE)) AS measurement_period
    FROM claims_with_cci c
    LEFT JOIN prior_auth_stats pa
        ON c.PATIENT_ID = pa.PATIENT_ID
        AND c.ENCOUNTER_ID = pa.ENCOUNTER_ID
    GROUP BY 1, 2, 3;

    SELECT COUNT(*) INTO :v_row_count
    FROM DCA_DEMO.GOVERNANCE.HCLS_PAYER_METRICS;

    RETURN 'Payer response metrics computed. Rows: ' || :v_row_count;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 4: SP_HCLS_PLAN_OF_CARE_GAPS
-- ═══════════════════════════════════════════════════════════════════════════
-- Identifies gaps between payer-approved and actual care delivery,
-- correlating early discharge with 30-day readmission rates.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_PLAN_OF_CARE_GAPS()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_row_count INTEGER DEFAULT 0;
    v_cci_exists INTEGER DEFAULT 0;
    v_ur_exists INTEGER DEFAULT 0;
    v_enc_exists INTEGER DEFAULT 0;
BEGIN

    SELECT COUNT(*) INTO :v_cci_exists
    FROM DCA_DEMO.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'GOVERNANCE' AND table_name = 'HCLS_PATIENT_COMORBIDITY';

    SELECT COUNT(*) INTO :v_ur_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'PAYER' AND table_name = 'FACT_UTILIZATION_REVIEWS';

    SELECT COUNT(*) INTO :v_enc_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'FHIR' AND table_name = 'FACT_ENCOUNTERS';

    IF (:v_cci_exists = 0 OR :v_ur_exists = 0 OR :v_enc_exists = 0) THEN
        RETURN 'Care gaps skipped — required tables not found.';
    END IF;

    CREATE OR REPLACE TABLE DCA_DEMO.GOVERNANCE.HCLS_CARE_GAPS AS
    WITH encounter_los AS (
        SELECT
            e.ENCOUNTER_ID,
            e.PATIENT_ID,
            e.ORG_ID,
            e.ADMIT_DATE,
            e.DISCHARGE_DATE,
            DATEDIFF('day', e.ADMIT_DATE, COALESCE(e.DISCHARGE_DATE, CURRENT_DATE())) AS actual_days,
            -- Check for 30-day readmission
            CASE WHEN EXISTS (
                SELECT 1 FROM CURATED_DEV.FHIR.FACT_ENCOUNTERS e2
                WHERE e2.PATIENT_ID = e.PATIENT_ID
                  AND e2.ENCOUNTER_ID != e.ENCOUNTER_ID
                  AND e2.ADMIT_DATE BETWEEN e.DISCHARGE_DATE AND DATEADD('day', 30, e.DISCHARGE_DATE)
            ) THEN TRUE ELSE FALSE END AS readmitted_30day
        FROM CURATED_DEV.FHIR.FACT_ENCOUNTERS e
        WHERE e.ADMIT_DATE IS NOT NULL
          AND e.DISCHARGE_DATE IS NOT NULL
    ),
    review_approved AS (
        SELECT
            ur.ENCOUNTER_ID,
            ur.PATIENT_ID,
            ur.PAYER_NAME,
            ur.APPROVED_DAYS,
            ur.REVIEW_TYPE
        FROM CURATED_DEV.PAYER.FACT_UTILIZATION_REVIEWS ur
        WHERE ur.REVIEW_STATUS = 'APPROVED'
          AND ur.APPROVED_DAYS IS NOT NULL
    )
    SELECT
        el.ENCOUNTER_ID AS encounter_id,
        el.PATIENT_ID AS patient_id,
        COALESCE(pc.cci_tier, 'UNKNOWN') AS cci_tier,
        ra.APPROVED_DAYS AS approved_days,
        el.actual_days,
        el.actual_days - ra.APPROVED_DAYS AS variance_days,
        CASE
            WHEN el.actual_days - ra.APPROVED_DAYS > 2 THEN 'EXTENDED_STAY'
            WHEN ra.APPROVED_DAYS - el.actual_days > 0 THEN 'EARLY_DISCHARGE'
            ELSE 'WITHIN_PLAN'
        END AS gap_type,
        el.readmitted_30day,
        ra.PAYER_NAME AS payer_name
    FROM encounter_los el
    JOIN review_approved ra
        ON el.ENCOUNTER_ID = ra.ENCOUNTER_ID
    LEFT JOIN DCA_DEMO.GOVERNANCE.HCLS_PATIENT_COMORBIDITY pc
        ON el.PATIENT_ID = pc.patient_id;

    SELECT COUNT(*) INTO :v_row_count
    FROM DCA_DEMO.GOVERNANCE.HCLS_CARE_GAPS;

    RETURN 'Care gaps identified. Rows: ' || :v_row_count;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 5: SP_HCLS_POPULATE_PAYER_GRAPH
-- ═══════════════════════════════════════════════════════════════════════════
-- Populates the Knowledge Graph with payer domain nodes and edges:
-- CCI_TIER nodes, PLAN nodes, RISK_STRATIFIED edges, COVERED_BY edges,
-- DENIED_FOR edges, and COMORBID_WITH edges.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_POPULATE_PAYER_GRAPH()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_cci_nodes INTEGER DEFAULT 0;
    v_plan_nodes INTEGER DEFAULT 0;
    v_risk_edges INTEGER DEFAULT 0;
    v_covered_edges INTEGER DEFAULT 0;
    v_denied_edges INTEGER DEFAULT 0;
    v_cci_exists INTEGER DEFAULT 0;
BEGIN

    SELECT COUNT(*) INTO :v_cci_exists
    FROM DCA_DEMO.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'GOVERNANCE' AND table_name = 'HCLS_PATIENT_COMORBIDITY';

    IF (:v_cci_exists = 0) THEN
        RETURN 'Payer graph skipped — HCLS_PATIENT_COMORBIDITY not found.';
    END IF;

    -- ── 1. CCI_TIER nodes (one per patient) ────────────────────────────────
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
    USING (
        SELECT
            'PYR_CCI_' || MD5(patient_id || cci_tier) AS node_id,
            'CCI_TIER' AS node_type,
            'BUSINESS' AS layer,
            'PAYER' AS source_system,
            patient_id || '::' || cci_tier AS fqn,
            'CCI ' || cci_tier || ' (Score: ' || cci_score || ')' AS display_name,
            OBJECT_CONSTRUCT(
                'patient_id', patient_id,
                'cci_score', cci_score,
                'cci_tier', cci_tier,
                'condition_count', condition_count,
                'top_conditions', top_conditions_json,
                'calculation_date', calculation_date
            ) AS properties
        FROM DCA_DEMO.GOVERNANCE.HCLS_PATIENT_COMORBIDITY
    ) AS src
    ON tgt.node_id = src.node_id
    WHEN MATCHED THEN UPDATE SET
        tgt.display_name = src.display_name,
        tgt.properties = src.properties
    WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
        VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

    SELECT COUNT(*) INTO :v_cci_nodes
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
    WHERE node_type = 'CCI_TIER' AND node_id LIKE 'PYR_CCI_%';

    -- ── 2. PLAN nodes ──────────────────────────────────────────────────────
    LET v_plan_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_plan_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'PAYER' AND table_name = 'DIM_PLANS';

    IF (:v_plan_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT
                'PYR_PLAN_' || MD5(PLAN_ID) AS node_id,
                'PLAN' AS node_type,
                'BUSINESS' AS layer,
                'PAYER' AS source_system,
                PLAN_ID AS fqn,
                PLAN_NAME || ' (' || PLAN_TYPE || ')' AS display_name,
                OBJECT_CONSTRUCT(
                    'plan_id', PLAN_ID,
                    'plan_name', PLAN_NAME,
                    'plan_type', PLAN_TYPE,
                    'payer_name', PAYER_NAME,
                    'network_tier', NETWORK_TIER
                ) AS properties
            FROM CURATED_DEV.PAYER.DIM_PLANS
            WHERE PLAN_ID IS NOT NULL
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        SELECT COUNT(*) INTO :v_plan_nodes
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        WHERE node_type = 'PLAN' AND node_id LIKE 'PYR_PLAN_%';
    END IF;

    -- ── 3. RISK_STRATIFIED edges (Patient → CCI_TIER) ─────────────────────
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT
            'PYR_RISK_' || MD5(patient_id || cci_tier) AS edge_id,
            'BIZ_PAT_' || MD5(patient_id) AS source_node_id,
            'PYR_CCI_' || MD5(patient_id || cci_tier) AS target_node_id,
            'RISK_STRATIFIED' AS edge_type,
            'BUSINESS' AS layer,
            cci_score::FLOAT / 10.0 AS weight,
            OBJECT_CONSTRUCT(
                'cci_score', cci_score,
                'cci_tier', cci_tier,
                'condition_count', condition_count
            ) AS properties
        FROM DCA_DEMO.GOVERNANCE.HCLS_PATIENT_COMORBIDITY
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN MATCHED THEN UPDATE SET
        tgt.weight = src.weight,
        tgt.properties = src.properties
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight, properties)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight, src.properties);

    SELECT COUNT(*) INTO :v_risk_edges
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
    WHERE edge_type = 'RISK_STRATIFIED' AND edge_id LIKE 'PYR_RISK_%';

    -- ── 4. COVERED_BY edges (Patient → Plan) ──────────────────────────────
    LET v_coverage_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_coverage_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'PAYER' AND table_name = 'FACT_COVERAGE_PERIODS';

    IF (:v_coverage_exists > 0 AND :v_plan_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT DISTINCT
                'PYR_COV_' || MD5(cp.PATIENT_ID || cp.PLAN_ID) AS edge_id,
                'BIZ_PAT_' || MD5(cp.PATIENT_ID) AS source_node_id,
                'PYR_PLAN_' || MD5(cp.PLAN_ID) AS target_node_id,
                'COVERED_BY' AS edge_type,
                'BUSINESS' AS layer,
                1.0 AS weight,
                OBJECT_CONSTRUCT(
                    'start_date', cp.COVERAGE_START,
                    'end_date', cp.COVERAGE_END,
                    'coverage_status', cp.COVERAGE_STATUS
                ) AS properties
            FROM CURATED_DEV.PAYER.FACT_COVERAGE_PERIODS cp
            WHERE cp.PATIENT_ID IS NOT NULL
              AND cp.PLAN_ID IS NOT NULL
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN MATCHED THEN UPDATE SET
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight, properties)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight, src.properties);

        SELECT COUNT(*) INTO :v_covered_edges
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
        WHERE edge_type = 'COVERED_BY' AND edge_id LIKE 'PYR_COV_%';
    END IF;

    -- ── 5. DENIED_FOR edges (Claim → Denial Reason) ───────────────────────
    LET v_claims_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_claims_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'PAYER' AND table_name = 'FACT_CLAIMS_DETAIL';

    IF (:v_claims_exists > 0) THEN
        -- Create DENIAL_REASON nodes first
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT DISTINCT
                'PYR_DENY_' || MD5(DENIAL_REASON) AS node_id,
                'DENIAL_REASON' AS node_type,
                'BUSINESS' AS layer,
                'PAYER' AS source_system,
                DENIAL_REASON AS fqn,
                DENIAL_REASON AS display_name,
                OBJECT_CONSTRUCT(
                    'denial_reason', DENIAL_REASON,
                    'source_table', 'CURATED_DEV.PAYER.FACT_CLAIMS_DETAIL'
                ) AS properties
            FROM CURATED_DEV.PAYER.FACT_CLAIMS_DETAIL
            WHERE ADJUDICATION_STATUS = 'DENIED'
              AND DENIAL_REASON IS NOT NULL
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        -- DENIED_FOR edges from encounter to denial reason
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT
                'PYR_DENY_E_' || MD5(ENCOUNTER_ID || DENIAL_REASON) AS edge_id,
                'HCLS_ENC_' || MD5(ENCOUNTER_ID) AS source_node_id,
                'PYR_DENY_' || MD5(DENIAL_REASON) AS target_node_id,
                'DENIED_FOR' AS edge_type,
                'CROSS' AS layer,
                1.0 AS weight,
                OBJECT_CONSTRUCT(
                    'claim_id', CLAIM_ID,
                    'payer_name', PAYER_NAME,
                    'plan_type', PLAN_TYPE,
                    'denial_reason', DENIAL_REASON
                ) AS properties
            FROM CURATED_DEV.PAYER.FACT_CLAIMS_DETAIL
            WHERE ADJUDICATION_STATUS = 'DENIED'
              AND DENIAL_REASON IS NOT NULL
              AND ENCOUNTER_ID IS NOT NULL
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN MATCHED THEN UPDATE SET
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight, properties)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight, src.properties);

        SELECT COUNT(*) INTO :v_denied_edges
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
        WHERE edge_type = 'DENIED_FOR' AND edge_id LIKE 'PYR_DENY_E_%';
    END IF;

    -- ── 6. CROSS-LAYER STORED_IN Edges ─────────────────────────────────────
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT DISTINCT
            'PYR_EDGE_' || MD5(
                n.node_id ||
                'META_' || MD5('DCA_DEMO.GOVERNANCE.HCLS_PATIENT_COMORBIDITY') ||
                'STORED_IN'
            ) AS edge_id,
            n.node_id AS source_node_id,
            'META_' || MD5('DCA_DEMO.GOVERNANCE.HCLS_PATIENT_COMORBIDITY') AS target_node_id,
            'STORED_IN' AS edge_type,
            'CROSS' AS layer,
            1.0 AS weight
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
        WHERE n.node_id LIKE 'PYR_CCI_%'
          AND n.node_type = 'CCI_TIER'
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    -- ── Final summary ───────────────────────────────────────────────────────
    RETURN 'Payer graph populated. Nodes — CCI Tier: ' || :v_cci_nodes ||
           ', Plans: ' || :v_plan_nodes ||
           '. Edges — Risk Stratified: ' || :v_risk_edges ||
           ', Covered By: ' || :v_covered_edges ||
           ', Denied For: ' || :v_denied_edges;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 6: SP_HCLS_COMORBIDITY_PAYER_RUN_ALL (Orchestrator)
-- ═══════════════════════════════════════════════════════════════════════════
-- Runs all comorbidity and payer procedures in sequence and records a
-- snapshot to ONTOLOGY_GRAPH_SNAPSHOTS.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_COMORBIDITY_PAYER_RUN_ALL()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_result_cci VARCHAR;
    v_result_clusters VARCHAR;
    v_result_payer VARCHAR;
    v_result_gaps VARCHAR;
    v_result_graph VARCHAR;
    v_snapshot_id VARCHAR;
BEGIN
    -- Step 1: Compute CCI per patient
    CALL DCA_DEMO.GOVERNANCE.SP_HCLS_COMORBIDITY_INDEX();
    SELECT * INTO :v_result_cci FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    -- Step 2: Find comorbidity clusters
    CALL DCA_DEMO.GOVERNANCE.SP_HCLS_COMORBIDITY_CLUSTERS();
    SELECT * INTO :v_result_clusters FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    -- Step 3: Analyze payer response
    CALL DCA_DEMO.GOVERNANCE.SP_HCLS_PAYER_RESPONSE();
    SELECT * INTO :v_result_payer FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    -- Step 4: Identify care gaps
    CALL DCA_DEMO.GOVERNANCE.SP_HCLS_PLAN_OF_CARE_GAPS();
    SELECT * INTO :v_result_gaps FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    -- Step 5: Populate Knowledge Graph
    CALL DCA_DEMO.GOVERNANCE.SP_HCLS_POPULATE_PAYER_GRAPH();
    SELECT * INTO :v_result_graph FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    -- Record snapshot
    LET v_snapshot_id := 'HCLS_COMORBIDITY_' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS');

    INSERT INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SNAPSHOTS (snapshot_id, snapshot_type, created_at, metadata)
    SELECT
        :v_snapshot_id,
        'HCLS_COMORBIDITY_PAYER_RUN',
        CURRENT_TIMESTAMP(),
        OBJECT_CONSTRUCT(
            'cci_result', :v_result_cci,
            'clusters_result', :v_result_clusters,
            'payer_result', :v_result_payer,
            'gaps_result', :v_result_gaps,
            'graph_result', :v_result_graph,
            'cci_node_count', (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES WHERE node_id LIKE 'PYR_CCI_%'),
            'plan_node_count', (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES WHERE node_id LIKE 'PYR_PLAN_%'),
            'payer_edge_count', (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES WHERE edge_id LIKE 'PYR_%')
        );

    RETURN 'HCLS Comorbidity-Payer pipeline complete. Snapshot: ' || :v_snapshot_id || CHR(10) ||
           '  CCI: ' || :v_result_cci || CHR(10) ||
           '  Clusters: ' || :v_result_clusters || CHR(10) ||
           '  Payer: ' || :v_result_payer || CHR(10) ||
           '  Gaps: ' || :v_result_gaps || CHR(10) ||
           '  Graph: ' || :v_result_graph;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'HCLS comorbidity and payer procedures created successfully' AS status;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_COMORBIDITY_INDEX() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_COMORBIDITY_CLUSTERS() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_PAYER_RESPONSE() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_PLAN_OF_CARE_GAPS() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_POPULATE_PAYER_GRAPH() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_COMORBIDITY_PAYER_RUN_ALL() TO ROLE ONTOLOGY_ADMIN;
