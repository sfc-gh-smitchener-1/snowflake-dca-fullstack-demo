-- ============================================================================
-- Snowflake Ontology Reference — 11_blog_enrichments.sql
-- ============================================================================
-- Bolts the two interventions from Snowflake's
-- "Ontology-grounded Reasoning with Cortex Agents" (May 25, 2026) blog onto
-- our Graph RAG layer.
--
-- The blog's strongest two findings:
--   (1) "Fix the data layer first." — Pre-compute the descendant attributes
--       of every concept and bake them into its profile/embedding.
--       In their benchmark this single intervention captured ~80% of the
--       lift over a Semantic-View-only agent.
--   (2) Targeted, hand-curated terminology mappings close the last
--       ~8 percentage points (composite terms the hierarchy can't resolve).
--
-- What this file adds
--   1. silver.class_profile               — Dynamic Table; one row per class
--                                            with descendant-aggregated
--                                            attributes baked into the
--                                            embedded text. (Intervention 1)
--   2. silver.search_corpus               — view that unions individual-level
--                                            (silver.node_embedding) and
--                                            class-level (silver.class_profile)
--                                            rows so the retriever sees both.
--   3. silver.synonym                     — per-source composite-term mappings
--                                            (Intervention 2), tagged by
--                                            source_system. Schema is permissive
--                                            so any deployment can load its own
--                                            glossary without changing code.
--   4. silver.f_resolve_synonyms          — table function: question text →
--                                            matching synonym rows.
--   5. silver.f_retrieve_subgraph         — REPLACED to query search_corpus
--                                            and walk edges only from
--                                            individual seeds (class seeds
--                                            already carry their descendants
--                                            in the profile).
--   6. silver.p_graph_rag                 — REPLACED to render class profiles
--                                            and synonym definitions into
--                                            the prompt as distinct sections.
--
-- Idempotent. Run AFTER 08_graph_rag.sql (and 09 / 10 if you want them in
-- the loop).
-- ============================================================================

USE ROLE      ONT_DEMO_BUILDER_ROLE;
USE DATABASE  ONT_DEMO;
USE SCHEMA    SILVER;
USE WAREHOUSE ONT_DEMO_INGEST_WH;

-- ---------------------------------------------------------------------------
-- 1. silver.class_profile  (Intervention 1 — descendant rollup)
-- ---------------------------------------------------------------------------
-- One row per ontology class, with the labels + key literals of every
-- individual instance in the class OR any subclass folded into the
-- embedded text. This is what the blog calls a "neighborhood profile."
-- ---------------------------------------------------------------------------

CREATE OR REPLACE DYNAMIC TABLE class_profile
    TARGET_LAG = '10 minutes'
    WAREHOUSE  = ONT_DEMO_SEARCH_WH
    CLUSTER BY (class_iri)
AS
WITH RECURSIVE class_descendants AS (
    -- Anchor: every class is its own descendant at depth 0
    SELECT class_iri AS root_iri, class_iri AS desc_iri, 0 AS depth
    FROM   class
    UNION ALL
    SELECT cd.root_iri, c.class_iri, cd.depth + 1
    FROM   class_descendants cd
    JOIN   class c ON c.sub_class_of = cd.desc_iri
    WHERE  cd.depth < 8
),
descendant_attrs AS (
    SELECT
        cd.root_iri              AS class_iri,
        i.individual_uid,
        i.label                  AS individual_label,
        s.predicate_iri,
        s.object_literal
    FROM   class_descendants cd
    JOIN   individual i
           ON i.class_iri = cd.desc_iri
          AND i.valid_to IS NULL
    LEFT JOIN statement s
           ON s.subject_uid = i.individual_uid
          AND s.valid_to IS NULL
          AND s.object_literal IS NOT NULL
),
class_descendant_labels AS (
    SELECT
        class_iri,
        LISTAGG(individual_label, ', ')
            WITHIN GROUP (ORDER BY individual_label) AS sample_labels,
        COUNT(DISTINCT individual_uid)               AS descendant_count
    FROM (
        SELECT
            class_iri,
            individual_uid,
            individual_label,
            ROW_NUMBER() OVER (
                PARTITION BY class_iri
                ORDER BY     individual_label
            ) AS rn
        FROM (
            SELECT DISTINCT class_iri, individual_uid, individual_label
            FROM   descendant_attrs
            WHERE  individual_label IS NOT NULL
        )
    )
    WHERE rn <= 25
    GROUP BY class_iri
),
class_descendant_attrs AS (
    SELECT
        class_iri,
        LISTAGG(
            REPLACE(predicate_iri, 'http://', '') || '=' || object_literal,
            '; '
        ) WITHIN GROUP (ORDER BY predicate_iri) AS sample_attrs
    FROM (
        SELECT
            class_iri, predicate_iri, object_literal,
            ROW_NUMBER() OVER (
                PARTITION BY class_iri
                ORDER BY     predicate_iri
            ) AS rn
        FROM (
            SELECT DISTINCT class_iri, predicate_iri, object_literal
            FROM   descendant_attrs
            WHERE  object_literal IS NOT NULL
        )
    )
    WHERE rn <= 100
    GROUP BY class_iri
)
SELECT
    'CLASS::' || c.class_iri                                        AS node_uid,
    c.class_iri,
    c.label,
    c.definition,
    cdl.descendant_count,
    -- The "neighborhood profile" — everything a small model needs about
    -- this class without ever walking the graph at query time.
    (
        c.label
        || ' ('   || REPLACE(c.class_iri, 'http://', '') || ')'
        || COALESCE(' — ' || c.definition, '')
        || COALESCE(' · descendant_count=' || cdl.descendant_count::STRING, '')
        || COALESCE(' · descendants: ' || cdl.sample_labels, '')
        || COALESCE(' · attrs: '       || cda.sample_attrs,  '')
    )                                                               AS embed_text,
    SNOWFLAKE.CORTEX.EMBED_TEXT_768(
        'snowflake-arctic-embed-m-v1.5',
        c.label
        || ' ' || COALESCE(c.definition, '')
        || COALESCE(' descendants ' || cdl.sample_labels, '')
        || COALESCE(' attrs '       || cda.sample_attrs,  '')
    )                                                               AS embedding
FROM class c
LEFT JOIN class_descendant_labels cdl USING (class_iri)
LEFT JOIN class_descendant_attrs  cda USING (class_iri);

-- ---------------------------------------------------------------------------
-- 2. silver.search_corpus  (unified retrieval surface)
-- ---------------------------------------------------------------------------
-- Hands the retriever a single shape regardless of whether the row is an
-- ABox individual or a TBox class profile.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW search_corpus AS
SELECT 'individual' AS kind, node_uid, class_iri, label, embed_text, embedding
FROM   node_embedding
UNION ALL
SELECT 'class'      AS kind, node_uid, class_iri, label, embed_text, embedding
FROM   class_profile;

-- ---------------------------------------------------------------------------
-- 3. silver.synonym  (Intervention 2 — curated composite-term mappings)
-- ---------------------------------------------------------------------------
-- Free-form, hand-curated mappings the blog used to close the last
-- ~8 percentage points. Seeds are organized PER SOURCE SYSTEM (source_system
-- column) so each vertical contributes its own business jargon → IRI mappings.
-- A real deployment would load each system's glossary (SAP T-codes, Salesforce
-- record types, FHIR value sets, ServiceNow categories, …) into this one table.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS synonym (
    synonym_id      STRING       PRIMARY KEY,
    surface_form    STRING       NOT NULL,                -- what the user types
    canonical_iri   STRING,                               -- IRI it maps to
    sql_predicate   STRING,                               -- optional SQL fragment
    notes           STRING,
    source_system   STRING,                               -- owning source system
    valid_from      TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
    valid_to        TIMESTAMP_TZ
);

-- Backfill the column for pre-existing deployments.
ALTER TABLE synonym ADD COLUMN IF NOT EXISTS source_system STRING;

-- Seed per-source synonyms (idempotent).
MERGE INTO synonym AS t
USING (
    SELECT * FROM VALUES
      -- SAP S/4HANA -----------------------------------------------------------
      ('sap-001', 'sold-to party',   'sap:Customer',     $$class_iri = 'sap:Customer'$$,       'SAP KNA1 sold-to / customer master.',          'SAP'),
      ('sap-002', 'sales order',      'sap:SalesOrder',   $$class_iri = 'sap:SalesOrder'$$,     'SAP VBAK sales document header.',              'SAP'),
      ('sap-003', 'material master',  'sap:Material',     $$class_iri = 'sap:Material'$$,       'SAP MARA material master record.',             'SAP'),
      -- Salesforce ------------------------------------------------------------
      ('sfdc-001', 'deal',            'sfdc:Opportunity', $$class_iri = 'sfdc:Opportunity'$$,   'Salesforce Opportunity / pipeline deal.',      'SALESFORCE'),
      ('sfdc-002', 'customer account','sfdc:Account',     $$class_iri = 'sfdc:Account'$$,       'Salesforce Account.',                          'SALESFORCE'),
      ('sfdc-003', 'support ticket',  'sfdc:Case',        $$class_iri = 'sfdc:Case'$$,          'Salesforce Case.',                             'SALESFORCE'),
      -- Oracle EBS ------------------------------------------------------------
      ('ora-001', 'supplier',         'ora:Supplier',     $$class_iri = 'ora:Supplier'$$,       'Oracle EBS AP supplier.',                      'ORACLE'),
      ('ora-002', 'ap invoice',       'ora:PayablesInvoice', $$class_iri = 'ora:PayablesInvoice'$$, 'Oracle AP_INVOICES payables invoice.',     'ORACLE'),
      ('ora-003', 'customer party',   'ora:Party',        $$class_iri = 'ora:Party'$$,          'Oracle TCA HZ_PARTIES party.',                 'ORACLE'),
      -- HL7 FHIR --------------------------------------------------------------
      ('fhir-001', 'patient',         'fhir:Patient',     $$class_iri = 'fhir:Patient'$$,       'FHIR Patient resource.',                       'FHIR'),
      ('fhir-002', 'diagnosis',       'fhir:Condition',   $$class_iri = 'fhir:Condition'$$,     'FHIR Condition / problem-list entry.',         'FHIR'),
      ('fhir-003', 'lab result',      'fhir:Observation', $$class_iri = 'fhir:Observation'$$,   'FHIR Observation.',                            'FHIR'),
      -- Workday HCM -----------------------------------------------------------
      ('wd-001', 'employee',          'wd:Worker',        $$class_iri = 'wd:Worker'$$,          'Workday Worker.',                              'WORKDAY'),
      ('wd-002', 'pay',               'wd:Compensation',  $$class_iri = 'wd:Compensation'$$,    'Workday Compensation record.',                 'WORKDAY'),
      ('wd-003', 'pto',               'wd:TimeOff',       $$class_iri = 'wd:TimeOff'$$,         'Workday Time Off / leave.',                    'WORKDAY'),
      -- ServiceNow ------------------------------------------------------------
      ('snow-001', 'ticket',          'snow:Incident',    $$class_iri = 'snow:Incident'$$,      'ServiceNow Incident.',                         'SERVICENOW'),
      ('snow-002', 'config item',     'snow:ConfigurationItem', $$class_iri = 'snow:ConfigurationItem'$$, 'ServiceNow CMDB configuration item.', 'SERVICENOW'),
      ('snow-003', 'change',          'snow:ChangeRequest', $$class_iri = 'snow:ChangeRequest'$$, 'ServiceNow Change Request.',                 'SERVICENOW')
    AS s(synonym_id, surface_form, canonical_iri, sql_predicate, notes, source_system)
) s ON t.synonym_id = s.synonym_id
WHEN NOT MATCHED THEN INSERT (synonym_id, surface_form, canonical_iri, sql_predicate, notes, source_system)
                       VALUES (s.synonym_id, s.surface_form, s.canonical_iri, s.sql_predicate, s.notes, s.source_system);

-- ---------------------------------------------------------------------------
-- 4. silver.f_resolve_synonyms — question → matching curated mappings
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION f_resolve_synonyms(QUESTION STRING)
RETURNS TABLE (
    synonym_id    STRING,
    surface_form  STRING,
    canonical_iri STRING,
    sql_predicate STRING,
    notes         STRING
)
AS
$$
    SELECT s.synonym_id, s.surface_form, s.canonical_iri, s.sql_predicate, s.notes
    FROM   synonym s
    WHERE  s.valid_to IS NULL
      AND  CONTAINS(LOWER(QUESTION), LOWER(s.surface_form))
$$;

-- ---------------------------------------------------------------------------
-- 5. silver.f_retrieve_subgraph  (REPLACED — now reads search_corpus)
-- ---------------------------------------------------------------------------
-- Class seeds carry their own descendant context in `snippet`, so we don't
-- walk edges from them. Individual seeds still drive the recursive walk.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION f_retrieve_subgraph(
    QUESTION   STRING,
    TOP_K      INTEGER,
    MAX_HOPS   INTEGER
)
RETURNS TABLE (
    kind          STRING,      -- 'node' | 'edge' | 'class'
    depth         INTEGER,
    score         FLOAT,
    src_uid       STRING,
    predicate_iri STRING,
    dst_uid       STRING,
    node_uid      STRING,
    class_iri     STRING,
    label         STRING,
    snippet       STRING
)
AS
$$
    WITH
    q_vec AS (
        SELECT SNOWFLAKE.CORTEX.EMBED_TEXT_768(
                   'snowflake-arctic-embed-m-v1.5', QUESTION
               ) AS v
    ),
    -- Top-K from unified corpus; QUALIFY replaces LIMIT <param>
    seeds_all AS (
        SELECT
            sc.kind,
            sc.node_uid,
            sc.class_iri,
            sc.label,
            sc.embed_text                                              AS snippet,
            VECTOR_COSINE_SIMILARITY(sc.embedding, q.v)                AS score
        FROM   search_corpus sc
        CROSS JOIN q_vec q
        QUALIFY ROW_NUMBER() OVER (
            ORDER BY VECTOR_COSINE_SIMILARITY(sc.embedding, q.v) DESC
        ) <= TOP_K
    ),
    -- Only individual seeds drive the graph walk
    -- (class seeds carry descendant context in their snippet already)
    individual_seeds AS (
        SELECT * FROM seeds_all WHERE kind = 'individual'
    ),
    -- Explicit hops — recursive CTEs are not supported in SQL Table UDFs
    hop1 AS (
        SELECT e.src_uid, e.predicate_iri, e.dst_uid,
               1 AS depth, s.score * 0.7 AS score
        FROM individual_seeds s
        JOIN edge e ON e.src_uid = s.node_uid AND e.valid_to IS NULL
        WHERE MAX_HOPS >= 1
    ),
    hop2 AS (
        SELECT e.src_uid, e.predicate_iri, e.dst_uid,
               2 AS depth, h.score * 0.7 AS score
        FROM hop1 h
        JOIN edge e ON e.src_uid = h.dst_uid AND e.valid_to IS NULL
        WHERE MAX_HOPS >= 2
    ),
    hop3 AS (
        SELECT e.src_uid, e.predicate_iri, e.dst_uid,
               3 AS depth, h.score * 0.7 AS score
        FROM hop2 h
        JOIN edge e ON e.src_uid = h.dst_uid AND e.valid_to IS NULL
        WHERE MAX_HOPS >= 3
    ),
    all_node_uids AS (
        SELECT node_uid, 0 AS depth, score FROM individual_seeds
        UNION
        SELECT dst_uid, 1, MAX(score) FROM hop1 GROUP BY dst_uid
        UNION
        SELECT dst_uid, 2, MAX(score) FROM hop2 GROUP BY dst_uid
        UNION
        SELECT dst_uid, 3, MAX(score) FROM hop3 GROUP BY dst_uid
    ),
    all_edges AS (
        SELECT * FROM hop1
        UNION ALL SELECT * FROM hop2
        UNION ALL SELECT * FROM hop3
    )
    -- Class profile rows (no walk; descendant context is already inline)
    SELECT
        'class'              AS kind,
        0                    AS depth,
        s.score,
        CAST(NULL AS STRING) AS src_uid,
        CAST(NULL AS STRING) AS predicate_iri,
        CAST(NULL AS STRING) AS dst_uid,
        s.node_uid,
        s.class_iri,
        s.label,
        s.snippet
    FROM seeds_all s
    WHERE s.kind = 'class'
    UNION ALL
    -- Individual-level nodes touched by the walk
    SELECT
        'node'               AS kind,
        an.depth,
        an.score,
        CAST(NULL AS STRING),
        CAST(NULL AS STRING),
        CAST(NULL AS STRING),
        ne.node_uid,
        ne.class_iri,
        ne.label,
        ne.embed_text        AS snippet
    FROM all_node_uids an
    JOIN node_embedding ne USING (node_uid)
    UNION ALL
    -- Edges traversed
    SELECT
        'edge'               AS kind,
        ae.depth,
        ae.score,
        ae.src_uid,
        ae.predicate_iri,
        ae.dst_uid,
        CAST(NULL AS STRING),
        CAST(NULL AS STRING),
        CAST(NULL AS STRING),
        CAST(NULL AS STRING)
    FROM all_edges ae
$$;

-- ---------------------------------------------------------------------------
-- 6. silver.p_graph_rag  (REPLACED — class + synonym aware)
-- ---------------------------------------------------------------------------
-- Returns the same envelope shape as 08, but the `subgraph` payload now has
-- a `classes` array, and the prompt has dedicated CLASS PROFILES + SYNONYMS
-- sections.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE p_graph_rag(
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
    t_start         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP();
    nodes_json      VARIANT;
    edges_json      VARIANT;
    classes_json    VARIANT;
    synonyms_json   VARIANT;
    citations       VARIANT;
    prompt          STRING;
    answer          STRING;
    out             VARIANT;
BEGIN
    CREATE OR REPLACE TEMPORARY TABLE _rag_sub AS
    SELECT * FROM TABLE(f_retrieve_subgraph(:QUESTION, :TOP_K, :MAX_HOPS));

    CREATE OR REPLACE TEMPORARY TABLE _rag_syn AS
    SELECT * FROM TABLE(f_resolve_synonyms(:QUESTION));

    -- Use := (subquery) for all aggregates — avoids multi-line SELECT INTO issues
    nodes_json := (
        SELECT ARRAY_AGG(OBJECT_CONSTRUCT(
                   'node_uid', node_uid, 'class_iri', class_iri,
                   'label', label, 'snippet', snippet,
                   'depth', depth, 'score', score))
        FROM _rag_sub WHERE kind = 'node'
    );

    edges_json := (
        SELECT ARRAY_AGG(OBJECT_CONSTRUCT(
                   'src_uid', src_uid, 'predicate_iri', predicate_iri,
                   'dst_uid', dst_uid, 'depth', depth))
        FROM _rag_sub WHERE kind = 'edge'
    );

    classes_json := (
        SELECT ARRAY_AGG(OBJECT_CONSTRUCT(
                   'class_iri', class_iri, 'label', label,
                   'snippet', snippet, 'score', score))
        FROM _rag_sub WHERE kind = 'class'
    );

    synonyms_json := (
        SELECT ARRAY_AGG(OBJECT_CONSTRUCT(
                   'synonym_id', synonym_id, 'surface_form', surface_form,
                   'canonical_iri', canonical_iri, 'sql_predicate', sql_predicate,
                   'notes', notes))
        FROM _rag_syn
    );

    citations := (
        SELECT ARRAY_AGG(node_uid)
        FROM (SELECT DISTINCT node_uid FROM _rag_sub WHERE kind = 'node' AND depth = 0)
    );

    prompt := (
        SELECT
            '# QUESTION' || CHR(10) || :QUESTION || CHR(10) || CHR(10) ||
            '# CURATED TERMINOLOGY (overrides the hierarchy when applicable)' || CHR(10) ||
            COALESCE(
              (SELECT LISTAGG('- "' || value:surface_form::STRING || '" → '
                               || COALESCE('canonical=' || value:canonical_iri::STRING || ' ', '')
                               || COALESCE('sql=' || value:sql_predicate::STRING || ' ', '')
                               || COALESCE('— ' || value:notes::STRING, ''),
                              '|')
                       WITHIN GROUP (ORDER BY value:surface_form::STRING)
                 FROM TABLE(FLATTEN(input => :synonyms_json))),
              '(none matched)') ||
            CHR(10) || CHR(10) ||
            '# CLASS PROFILES (preaggregated descendant context — use these first)' || CHR(10) ||
            COALESCE(
              (SELECT LISTAGG('- ' || value:label::STRING
                               || ' [' || value:class_iri::STRING || ']: '
                               || value:snippet::STRING,
                              '|')
                       WITHIN GROUP (ORDER BY value:score::FLOAT DESC)
                 FROM TABLE(FLATTEN(input => :classes_json))),
              '(no class-level matches)') ||
            CHR(10) || CHR(10) ||
            '# GRAPH CONTEXT (instances + edges retrieved by the walker)' || CHR(10) ||
            '## Nodes' || CHR(10) ||
            COALESCE(
              (SELECT LISTAGG('- [' || value:node_uid::STRING || '] '
                               || value:label::STRING
                               || ' (' || value:class_iri::STRING || ') — '
                               || value:snippet::STRING,
                              '|')
                       WITHIN GROUP (ORDER BY value:score::FLOAT DESC)
                 FROM TABLE(FLATTEN(input => :nodes_json))),
              '(no nodes)') ||
            CHR(10) || CHR(10) ||
            '## Edges' || CHR(10) ||
            COALESCE(
              (SELECT LISTAGG('- ' || value:src_uid::STRING
                               || ' --[' || value:predicate_iri::STRING || ']--> '
                               || value:dst_uid::STRING,
                              '|')
                       WITHIN GROUP (ORDER BY value:depth::INTEGER)
                 FROM TABLE(FLATTEN(input => :edges_json))),
              '(no edges)') ||
            CHR(10) || CHR(10) ||
            '# INSTRUCTIONS' || CHR(10) ||
            '- Prefer CURATED TERMINOLOGY when it applies; it overrides hierarchy walks.' || CHR(10) ||
            '- Otherwise prefer CLASS PROFILES (already aggregated descendants).' || CHR(10) ||
            '- Use individual nodes / edges only when needed for specifics.' || CHR(10) ||
            '- Cite each fact inline with [node_uid] or [class_iri].' || CHR(10) ||
            '- If the context does not contain the answer, say so explicitly.' || CHR(10) ||
            '- Be terse. Bullet points preferred.'
    );

    answer := SNOWFLAKE.CORTEX.COMPLETE(:MODEL, :prompt);

    out := OBJECT_CONSTRUCT(
        'answer',     :answer,
        'model',      :MODEL,
        'subgraph',   OBJECT_CONSTRUCT(
                          'nodes',    :nodes_json,
                          'edges',    :edges_json,
                          'classes',  :classes_json,
                          'synonyms', :synonyms_json),
        'citations',  :citations,
        'prompt',     :prompt,
        'latency_ms', DATEDIFF('millisecond', :t_start, CURRENT_TIMESTAMP())
    );

    RETURN out;
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. Done.
-- ---------------------------------------------------------------------------

SELECT 'class_profile + synonym + enriched p_graph_rag deployed.' AS status;
