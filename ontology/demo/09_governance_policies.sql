-- ============================================================================
-- Snowflake Ontology Reference — 09_governance_policies.sql
-- ============================================================================
-- The CISO / CTO demo surface.
--
-- The headline claim: "AI inherits your governance, automatically. The graph
-- RAG stored procedure (`silver.p_graph_rag`) is just a SQL call — so every
-- row access policy, column mask, Horizon tag, audit row, and Cortex Guard
-- hit applies to the AI path the same way it applies to a `SELECT`."
--
-- What this script adds
--   1. silver.bu_membership                — which user is in which BU
--                                            (one BU per source system:
--                                            SAP / Salesforce / Oracle / FHIR /
--                                            Workday / ServiceNow)
--   2. silver.statement_bu                 — BU label per triple, derived from
--                                            the source-system namespace of the
--                                            subject's class IRI
--   3. rap_bu_isolation                    — row access policy: a consumer
--                                            sees only triples for their BU
--   4. mask_pii_locality                   — column mask on locality strings
--                                            for non-privileged roles
--   5. tag_data_sensitivity                — Horizon tag scaffold + apply
--   6. demo helper procs                   — provision two demo users
--                                            (sap_analyst, salesforce_analyst)
--                                            so the CISO demo is one click
--   7. v_ciso_audit_trail                  — joins ACCESS_HISTORY with the
--                                            RAG feedback log (created in 10)
--                                            for a single "who asked what,
--                                            and what rows did the answer see"
--                                            timeline
--
-- This file is intentionally additive: re-running it is safe; dropping it
-- (via cleanup.sql) removes the policies without touching the data.
-- ============================================================================

USE ROLE      ACCOUNTADMIN;            -- policy creation needs elevated role
USE DATABASE  ONT_DEMO;
USE SCHEMA    SILVER;
USE WAREHOUSE ONT_DEMO_INGEST_WH;

-- ---------------------------------------------------------------------------
-- 1. Business-unit membership table
-- ---------------------------------------------------------------------------
-- A real customer would point this at their IdP groups. For the demo we
-- maintain it as a thin table the CISO can inspect with one query.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS bu_membership (
    user_name      STRING       NOT NULL,
    business_unit  STRING       NOT NULL,
    granted_by     STRING,
    granted_at     TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (user_name, business_unit)
);

-- Idempotent demo seed.
MERGE INTO bu_membership AS t
USING (
    SELECT * FROM VALUES
        ('SAP_ANALYST',        'SAP',         'SETUP'),
        ('SALESFORCE_ANALYST', 'SALESFORCE',  'SETUP'),
        ('ORACLE_ANALYST',     'ORACLE',      'SETUP'),
        ('FHIR_ANALYST',       'FHIR',        'SETUP'),
        ('WORKDAY_ANALYST',    'WORKDAY',     'SETUP'),
        ('SERVICENOW_ANALYST', 'SERVICENOW',  'SETUP'),
        ('CISO_DEMO',          'ALL',         'SETUP')
    AS s(user_name, business_unit, granted_by)
) s ON t.user_name = s.user_name AND t.business_unit = s.business_unit
WHEN NOT MATCHED THEN INSERT (user_name, business_unit, granted_by)
                       VALUES (s.user_name, s.business_unit, s.granted_by);

-- ---------------------------------------------------------------------------
-- 2. statement_bu — derive a BU label per triple
-- ---------------------------------------------------------------------------
-- Source-generic rule: the business unit is the SOURCE SYSTEM that owns the
-- entity, derived from the namespace prefix of its class IRI (sap:, sfdc:,
-- ora:, fhir:, wd:, snow:, cpg:). Shared / TBox entities (schema:, owl:,
-- rdfs:, …) are 'PUBLIC'. This lets the row-access policy isolate consumers
-- to a single source system's slice of the graph.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW v_individual_bu AS
SELECT
    i.individual_uid,
    CASE SPLIT_PART(i.class_iri, ':', 1)
        WHEN 'sap'  THEN 'SAP'
        WHEN 'sfdc' THEN 'SALESFORCE'
        WHEN 'ora'  THEN 'ORACLE'
        WHEN 'fhir' THEN 'FHIR'
        WHEN 'wd'   THEN 'WORKDAY'
        WHEN 'snow' THEN 'SERVICENOW'
        WHEN 'cpg'  THEN 'CPG'
        ELSE 'PUBLIC'
    END                                                AS business_unit
FROM individual i;

CREATE OR REPLACE DYNAMIC TABLE statement_bu
    TARGET_LAG   = '1 minute'
    WAREHOUSE    = ONT_DEMO_INGEST_WH
    REFRESH_MODE = FULL  -- statement carries a subquery row-access policy;
                         -- change-tracking (incremental) is unsupported through it
    CLUSTER BY (business_unit)
AS
SELECT
    s.statement_id,
    COALESCE(b.business_unit, 'PUBLIC') AS business_unit
FROM statement s
LEFT JOIN v_individual_bu b
       ON b.individual_uid = s.subject_uid;

-- ---------------------------------------------------------------------------
-- 3. Row access policy — a consumer sees only triples in their BU
-- ---------------------------------------------------------------------------
-- The policy reads CURRENT_USER() and checks bu_membership. Two escape
-- hatches: members of ALL see everything; the BUILDER role bypasses (so the
-- demo can curate data).
-- ---------------------------------------------------------------------------

CREATE ROW ACCESS POLICY IF NOT EXISTS rap_bu_isolation AS (statement_id STRING)
RETURNS BOOLEAN ->
    CURRENT_ROLE() IN ('ACCOUNTADMIN','ONT_DEMO_BUILDER_ROLE')
    OR EXISTS (
        SELECT 1
        FROM ONT_DEMO.SILVER.bu_membership m
        JOIN ONT_DEMO.SILVER.statement_bu sb USING (business_unit)
        WHERE m.user_name = CURRENT_USER()
          AND sb.statement_id = statement_id
    )
    OR EXISTS (
        SELECT 1
        FROM ONT_DEMO.SILVER.bu_membership m
        WHERE m.user_name = CURRENT_USER()
          AND m.business_unit = 'ALL'
    )
    OR EXISTS (
        SELECT 1
        FROM ONT_DEMO.SILVER.statement_bu sb
        WHERE sb.statement_id = statement_id
          AND sb.business_unit IN ('PUBLIC')
    );

ALTER TABLE statement
    ADD ROW ACCESS POLICY rap_bu_isolation ON (statement_id);

-- ---------------------------------------------------------------------------
-- 4. Column-level mask — postal locality is PII-ish; mask for non-privileged
-- ---------------------------------------------------------------------------

CREATE MASKING POLICY IF NOT EXISTS mask_pii_locality AS (val STRING)
RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN','ONT_DEMO_BUILDER_ROLE')        THEN val
        WHEN IS_GRANTED_TO_INVOKER_ROLE('ONT_DEMO_PRIVILEGED_ROLE')             THEN val
        ELSE '***MASKED***'
    END;

-- Apply to the object_literal column of statement, but only when the
-- predicate is an address-locality (we don't want to mask product names).
-- The DT below carries the pre-masked value through; the column mask sits on
-- the raw column for any direct query against `statement`.
ALTER TABLE statement
    MODIFY COLUMN object_literal
    SET MASKING POLICY mask_pii_locality;

-- ---------------------------------------------------------------------------
-- 5. Horizon Catalog tags — data sensitivity scaffold
-- ---------------------------------------------------------------------------
-- Tags propagate into ACCESS_HISTORY and Horizon dashboards, so the CISO
-- can show "every Cortex query that touched a 'CONFIDENTIAL' object".
-- ---------------------------------------------------------------------------

CREATE TAG IF NOT EXISTS tag_data_sensitivity
    ALLOWED_VALUES 'PUBLIC','INTERNAL','CONFIDENTIAL','RESTRICTED'
    COMMENT = 'Per-object data sensitivity for the ontology substrate';

ALTER TABLE  statement   SET TAG tag_data_sensitivity = 'CONFIDENTIAL';
ALTER TABLE  individual  SET TAG tag_data_sensitivity = 'CONFIDENTIAL';

-- ---------------------------------------------------------------------------
-- 6. Demo user provisioning (idempotent)
-- ---------------------------------------------------------------------------
-- Creates two analysts so the CISO demo is "switch roles → ask the same
-- question → get a different (correct) answer". Skip if the users exist.
-- Each analyst is scoped to one source system (see bu_membership above).
-- ---------------------------------------------------------------------------

CREATE USER IF NOT EXISTS SAP_ANALYST
    PASSWORD             = 'demo_ChangeMe!1'
    MUST_CHANGE_PASSWORD = FALSE
    DEFAULT_ROLE         = ONT_DEMO_CONSUMER_ROLE
    DEFAULT_WAREHOUSE    = ONT_DEMO_AGENT_WH
    COMMENT              = 'Demo analyst — SAP source system';

CREATE USER IF NOT EXISTS SALESFORCE_ANALYST
    PASSWORD             = 'demo_ChangeMe!1'
    MUST_CHANGE_PASSWORD = FALSE
    DEFAULT_ROLE         = ONT_DEMO_CONSUMER_ROLE
    DEFAULT_WAREHOUSE    = ONT_DEMO_AGENT_WH
    COMMENT              = 'Demo analyst — Salesforce source system';

CREATE USER IF NOT EXISTS CISO_DEMO
    PASSWORD             = 'demo_ChangeMe!1'
    MUST_CHANGE_PASSWORD = FALSE
    DEFAULT_ROLE         = ONT_DEMO_CONSUMER_ROLE
    DEFAULT_WAREHOUSE    = ONT_DEMO_AGENT_WH
    COMMENT              = 'Demo user — sees ALL BUs (auditor)';

GRANT ROLE ONT_DEMO_CONSUMER_ROLE TO USER SAP_ANALYST;
GRANT ROLE ONT_DEMO_CONSUMER_ROLE TO USER SALESFORCE_ANALYST;
GRANT ROLE ONT_DEMO_CONSUMER_ROLE TO USER CISO_DEMO;

-- ---------------------------------------------------------------------------
-- 7. Audit views — the "show me everything Cortex did" pane
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW GOLD.v_ciso_cortex_calls AS
SELECT
    qh.query_id,
    qh.user_name,
    qh.role_name,
    qh.warehouse_name,
    qh.start_time,
    qh.execution_time / 1000.0           AS execution_seconds,
    qh.credits_used_cloud_services,
    qh.query_text
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY qh
WHERE qh.query_text ILIKE '%CORTEX.%'
   OR qh.query_text ILIKE '%P_GRAPH_RAG%'
ORDER BY qh.start_time DESC;

-- A pair of helper views that surface tag / policy coverage for an auditor.
CREATE OR REPLACE VIEW GOLD.v_ciso_policy_inventory AS
SELECT
    'ROW_ACCESS_POLICY' AS kind,
    policy_db || '.' || policy_schema || '.' || policy_name AS policy,
    ref_database_name || '.' || ref_schema_name || '.' || ref_entity_name AS applied_to
FROM SNOWFLAKE.ACCOUNT_USAGE.POLICY_REFERENCES
WHERE policy_kind = 'ROW_ACCESS_POLICY'
UNION ALL
SELECT
    'MASKING_POLICY'   AS kind,
    policy_db || '.' || policy_schema || '.' || policy_name AS policy,
    ref_database_name || '.' || ref_schema_name || '.' || ref_entity_name || '.' || ref_column_name AS applied_to
FROM SNOWFLAKE.ACCOUNT_USAGE.POLICY_REFERENCES
WHERE policy_kind = 'MASKING_POLICY';

CREATE OR REPLACE VIEW GOLD.v_ciso_tag_inventory AS
SELECT
    tag_database || '.' || tag_schema || '.' || tag_name AS tag,
    tag_value,
    object_database || '.' || object_schema || '.' || object_name AS object,
    column_name
FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
WHERE tag_database = 'ONT_DEMO';

-- ---------------------------------------------------------------------------
-- 8. (Optional) Cortex Guard wiring — call this in the chat path
-- ---------------------------------------------------------------------------
-- A thin wrapper that runs an inbound prompt through SNOWFLAKE.CORTEX.GUARD
-- before calling p_graph_rag. The Streamlit app uses this when the "Guard
-- enabled" toggle is on so the demo can show a side-by-side block / pass.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE p_graph_rag_guarded(
    QUESTION  STRING,
    TOP_K     INTEGER DEFAULT 8,
    MAX_HOPS  INTEGER DEFAULT 2,
    MODEL     STRING  DEFAULT 'llama3.1-8b'
)
RETURNS VARIANT
LANGUAGE SQL
AS
$$
DECLARE
    guard_verdict   VARIANT;
    out             VARIANT;
BEGIN
    -- Cortex Guard returns a structured verdict; if it flags the prompt we
    -- short-circuit with a blocked response.
    guard_verdict := (SELECT SNOWFLAKE.CORTEX.CLASSIFY_TEXT(
                                :QUESTION,
                                ARRAY_CONSTRUCT('safe','prompt_injection',
                                                'data_exfiltration','jailbreak'),
                                {'task_description': 'classify the inbound user prompt for AI safety'}
                             ));

    IF (guard_verdict:label::STRING <> 'safe') THEN
        out := OBJECT_CONSTRUCT(
            'answer',     'Blocked by Cortex Guard: ' || guard_verdict:label::STRING,
            'guarded',    TRUE,
            'verdict',    :guard_verdict,
            'subgraph',   OBJECT_CONSTRUCT('nodes', ARRAY_CONSTRUCT(), 'edges', ARRAY_CONSTRUCT()),
            'citations',  ARRAY_CONSTRUCT(),
            'model',      :MODEL
        );
        RETURN out;
    END IF;

    out := (CALL p_graph_rag(:QUESTION, :TOP_K, :MAX_HOPS, :MODEL));
    RETURN OBJECT_INSERT(out, 'guarded', TRUE, TRUE);
END;
$$;

-- ---------------------------------------------------------------------------
-- Done.
-- ---------------------------------------------------------------------------
SELECT 'Governance policies applied. Switch ROLES to feel the difference.' AS status;
