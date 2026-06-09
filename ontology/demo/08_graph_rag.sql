-- ============================================================================
-- Snowflake Ontology Reference — 08_graph_rag.sql
-- ============================================================================
-- Graph RAG layer on top of the ontology substrate.
--
-- What it adds
--   1. silver.node_embedding         — Cortex-embedded representation of every
--                                      individual (Snowflake-Arctic 768-dim).
--                                      Refreshed as a Dynamic Table so new
--                                      individuals get embedded automatically.
--   2. silver.f_retrieve_subgraph    — Table UDF: question → seeds (vector
--                                      search) → 1–2-hop expansion (recursive
--                                      CTE on edge) → typed subgraph rows.
--   3. silver.p_graph_rag            — Stored procedure: orchestrates retrieve
--                                      + synthesize. Returns VARIANT with
--                                      {answer, subgraph, citations, model,
--                                       latency_ms}.
--   4. gold.v_blast_radius           — One-shot view that powers the "if entity X
--                                      is affected, what is exposed?" impact demo
--                                      (source-generic over all object edges).
--
-- Design choices the demo is built to defend
--   • Small models win when retrieval is typed. Default model is llama3.1-8b;
--     you can swap to mistral-large2 or claude-3-5-sonnet by passing a
--     different `model` argument. Same code path.
--   • Nothing leaves the account. Embed, search, retrieve, generate, log —
--     every step is a SQL call billed to Snowflake virtual compute.
--   • The graph is the guardrail. The synthesis prompt is built only from
--     rows returned by f_retrieve_subgraph, which is in turn constrained by
--     the property graph + row access policies (see 09_governance_policies.sql).
--
-- Run AFTER 03_query_patterns.sql (node/edge DTs) and 06_gold_views.sql.
-- Idempotent — safe to re-run.
-- ============================================================================

USE ROLE      ONT_DEMO_BUILDER_ROLE;
USE DATABASE  ONT_DEMO;
USE SCHEMA    SILVER;
USE WAREHOUSE ONT_DEMO_INGEST_WH;

-- ---------------------------------------------------------------------------
-- 1. silver.node_embedding — vector index over every individual
-- ---------------------------------------------------------------------------
-- Embedded text is "label · class · key literals" so a single vector captures
-- both the entity and its salient attributes. Dynamic Table keeps it warm.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE DYNAMIC TABLE node_embedding
    TARGET_LAG = '5 minutes'
    WAREHOUSE  = ONT_DEMO_SEARCH_WH
    CLUSTER BY (class_iri)
AS
SELECT
    i.individual_uid                                                 AS node_uid,
    i.class_iri,
    COALESCE(NULLIF(i.label, ''), i.individual_uid)                  AS label,
    -- Compact "card" we embed.
    (
        COALESCE(NULLIF(i.label, ''), i.individual_uid)
        || ' | class=' || REPLACE(i.class_iri, 'http://', '')
        -- Source-agnostic: embed every literal attribute the entity carries
        -- (the join below already restricts to non-null literals). Works for
        -- any source system's predicates without a hard-coded whitelist.
        || COALESCE(' | ' || LISTAGG(
               DISTINCT REPLACE(s.predicate_iri, 'http://', '') || '=' || s.object_literal,
               ' · '
           ), '')
    )                                                                AS embed_text,
    SNOWFLAKE.CORTEX.EMBED_TEXT_768(
        'snowflake-arctic-embed-m-v1.5',
        COALESCE(NULLIF(i.label, ''), i.individual_uid)
        || ' | class=' || REPLACE(i.class_iri, 'http://', '')
    )                                                                AS embedding
FROM individual i
LEFT JOIN statement s
       ON s.subject_uid = i.individual_uid
      AND s.valid_to IS NULL
      AND s.object_literal IS NOT NULL
WHERE i.valid_to IS NULL
GROUP BY i.individual_uid, i.class_iri, i.label;

-- ---------------------------------------------------------------------------
-- 2. silver.f_retrieve_subgraph — hybrid vector + graph retriever
-- ---------------------------------------------------------------------------
-- SQL Table UDFs do not support recursive CTEs or LIMIT <parameter>.
-- We use QUALIFY ROW_NUMBER() for top-K seeding and explicit hop CTEs
-- (hop1, hop2, hop3) instead of a recursive walk. Max supported hops = 3,
-- which covers every meaningful demo scenario.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION f_retrieve_subgraph(
    QUESTION   STRING,
    TOP_K      INTEGER,
    MAX_HOPS   INTEGER
)
RETURNS TABLE (
    kind          STRING,      -- 'node' | 'edge'
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
    -- Embed the question once
    q_vec AS (
        SELECT SNOWFLAKE.CORTEX.EMBED_TEXT_768(
                   'snowflake-arctic-embed-m-v1.5', QUESTION
               ) AS v
    ),
    -- Top-K seeds via cosine similarity (QUALIFY replaces LIMIT <param>)
    seeds AS (
        SELECT
            n.node_uid,
            n.class_iri,
            n.label,
            n.embed_text                                               AS snippet,
            VECTOR_COSINE_SIMILARITY(n.embedding, q.v)                 AS score
        FROM node_embedding n
        CROSS JOIN q_vec q
        QUALIFY ROW_NUMBER() OVER (
            ORDER BY VECTOR_COSINE_SIMILARITY(n.embedding, q.v) DESC
        ) <= TOP_K
    ),
    -- Hop 1: edges leaving seed nodes
    hop1 AS (
        SELECT e.src_uid, e.predicate_iri, e.dst_uid,
               1          AS depth,
               s.score * 0.7 AS score
        FROM seeds s
        JOIN edge e ON e.src_uid = s.node_uid AND e.valid_to IS NULL
        WHERE MAX_HOPS >= 1
    ),
    -- Hop 2: edges leaving hop-1 destinations
    hop2 AS (
        SELECT e.src_uid, e.predicate_iri, e.dst_uid,
               2          AS depth,
               h.score * 0.7 AS score
        FROM hop1 h
        JOIN edge e ON e.src_uid = h.dst_uid AND e.valid_to IS NULL
        WHERE MAX_HOPS >= 2
    ),
    -- Hop 3: edges leaving hop-2 destinations
    hop3 AS (
        SELECT e.src_uid, e.predicate_iri, e.dst_uid,
               3          AS depth,
               h.score * 0.7 AS score
        FROM hop2 h
        JOIN edge e ON e.src_uid = h.dst_uid AND e.valid_to IS NULL
        WHERE MAX_HOPS >= 3
    ),
    -- All node UIDs reached (deduplicate, keep shallowest depth + highest score)
    all_node_uids AS (
        SELECT node_uid, 0 AS depth, score FROM seeds
        UNION
        SELECT dst_uid, 1, MAX(score) FROM hop1 GROUP BY dst_uid
        UNION
        SELECT dst_uid, 2, MAX(score) FROM hop2 GROUP BY dst_uid
        UNION
        SELECT dst_uid, 3, MAX(score) FROM hop3 GROUP BY dst_uid
    ),
    -- All edges across all hops
    all_edges AS (
        SELECT * FROM hop1
        UNION ALL SELECT * FROM hop2
        UNION ALL SELECT * FROM hop3
    )
    -- Node rows
    SELECT
        'node'               AS kind,
        an.depth,
        an.score,
        CAST(NULL AS STRING) AS src_uid,
        CAST(NULL AS STRING) AS predicate_iri,
        CAST(NULL AS STRING) AS dst_uid,
        ne.node_uid,
        ne.class_iri,
        ne.label,
        ne.embed_text        AS snippet
    FROM all_node_uids an
    JOIN node_embedding ne USING (node_uid)
    UNION ALL
    -- Edge rows
    SELECT
        'edge'               AS kind,
        ae.depth,
        ae.score,
        ae.src_uid,
        ae.predicate_iri,
        ae.dst_uid,
        CAST(NULL AS STRING) AS node_uid,
        CAST(NULL AS STRING) AS class_iri,
        CAST(NULL AS STRING) AS label,
        CAST(NULL AS STRING) AS snippet
    FROM all_edges ae
$$;

-- ---------------------------------------------------------------------------
-- 3. silver.p_graph_rag — retrieve + synthesize
-- ---------------------------------------------------------------------------
-- Returns a VARIANT shaped like:
--   {
--     "answer":     "<LLM completion>",
--     "model":      "<model used>",
--     "subgraph":   { "nodes": [...], "edges": [...] },
--     "citations":  [ "<node_uid>", ... ],
--     "prompt":     "<the prompt actually sent>",
--     "latency_ms": <int>
--   }
--
-- Default model is intentionally a *small* one (llama3.1-8b) to make the
-- "graph carries the load, small model finishes the sentence" point.
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
    subgraph        VARIANT;
    nodes_json      VARIANT;
    edges_json      VARIANT;
    citations       VARIANT;
    prompt          STRING;
    answer          STRING;
    out             VARIANT;
BEGIN
    -- Materialize the retrieval once and reuse.
    CREATE OR REPLACE TEMPORARY TABLE _rag_sub AS
    SELECT * FROM TABLE(f_retrieve_subgraph(:QUESTION, :TOP_K, :MAX_HOPS));

    -- Assign aggregates using := (subquery) — avoids multi-line SELECT INTO
    -- parsing issues in Snowflake SQL Scripting.
    nodes_json := (
        SELECT ARRAY_AGG(OBJECT_CONSTRUCT(
                   'node_uid',  node_uid,  'class_iri', class_iri,
                   'label',     label,     'snippet',   snippet,
                   'depth',     depth,     'score',     score))
        FROM _rag_sub WHERE kind = 'node'
    );

    edges_json := (
        SELECT ARRAY_AGG(OBJECT_CONSTRUCT(
                   'src_uid',       src_uid,
                   'predicate_iri', predicate_iri,
                   'dst_uid',       dst_uid,
                   'depth',         depth))
        FROM _rag_sub WHERE kind = 'edge'
    );

    citations := (
        SELECT ARRAY_AGG(node_uid)
        FROM (SELECT DISTINCT node_uid FROM _rag_sub WHERE kind = 'node' AND depth = 0)
    );

    subgraph := OBJECT_CONSTRUCT('nodes', :nodes_json, 'edges', :edges_json);

    -- Build the prompt as a single expression assigned via :=
    prompt := (
        SELECT
            '# QUESTION' || CHR(10) || :QUESTION || CHR(10) || CHR(10) ||
            '# GRAPH CONTEXT (the only allowed source of facts)' || CHR(10) ||
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
            '- Answer using ONLY the nodes and edges above.' || CHR(10) ||
            '- Cite each fact inline with [node_uid].' || CHR(10) ||
            '- If the graph does not contain the answer, say so explicitly.' || CHR(10) ||
            '- Be terse. Bullet points preferred.'
    );

    answer := SNOWFLAKE.CORTEX.COMPLETE(:MODEL, :prompt);

    out := OBJECT_CONSTRUCT(
        'answer',     :answer,
        'model',      :MODEL,
        'subgraph',   :subgraph,
        'citations',  :citations,
        'prompt',     :prompt,
        'latency_ms', DATEDIFF('millisecond', :t_start, CURRENT_TIMESTAMP())
    );

    RETURN out;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. gold.v_blast_radius — source-generic "impact radius" walk
-- ---------------------------------------------------------------------------
-- "If entity :uid is affected (recalled product, breached account, terminated
-- worker, retired CI, …), what is reachable from it?" One recursive walk over
-- ALL object edges (up to depth 3), for ANY root in ANY source. The Streamlit
-- Recall tab filters this by the root_uid the user selects.
-- ---------------------------------------------------------------------------

USE SCHEMA GOLD;

CREATE OR REPLACE VIEW v_blast_radius AS
WITH RECURSIVE radius AS (
    SELECT
        n.node_uid                                                          AS root_uid,
        n.class_iri                                                         AS root_class,
        n.node_uid                                                          AS reached_uid,
        CAST(NULL AS STRING)                                                AS via_predicate,
        CAST(NULL AS STRING)                                                AS via_uid,
        0                                                                   AS depth
    FROM SILVER.node n
    UNION ALL
    SELECT
        r.root_uid,
        r.root_class,
        e.dst_uid                                                           AS reached_uid,
        e.predicate_iri                                                     AS via_predicate,
        r.reached_uid                                                       AS via_uid,
        r.depth + 1                                                         AS depth
    FROM radius r
    JOIN SILVER.edge e
      ON e.src_uid = r.reached_uid
     AND e.valid_to IS NULL
    WHERE r.depth < 3
)
SELECT
    r.root_uid,
    r.root_class,
    root.label                                  AS root_label,
    r.depth,
    r.via_predicate,
    r.reached_uid,
    n.class_iri                                 AS reached_class,
    n.label                                     AS reached_label,
    n.name                                      AS reached_name
FROM radius r
LEFT JOIN SILVER.node n    ON n.node_uid = r.reached_uid
LEFT JOIN SILVER.node root ON root.node_uid = r.root_uid
WHERE r.depth > 0;

-- ---------------------------------------------------------------------------
-- 5. Smoke test
-- ---------------------------------------------------------------------------
-- Run after the embedding DT has refreshed (1st run takes ~30s for the small
-- demo, a few minutes for the CPG-scale data set).

SELECT 'Run after node_embedding DT has refreshed:' AS hint;

-- Pure retrieval (no LLM yet) — verifies vector + graph plumbing.
SELECT * FROM TABLE(SILVER.f_retrieve_subgraph(
    'customer with the largest sales order', 5, 2
)) ORDER BY kind, depth, score DESC;

-- Full RAG round-trip with the small model.
-- CALL SILVER.p_graph_rag('Which sales orders are missing a sold-to party?', 8, 1, 'llama3.1-8b');

-- The blast-radius demo — run with whichever entity UID Streamlit picks.
-- SELECT * FROM GOLD.v_blast_radius WHERE root_uid = 'SAP-CUST-0000000001' ORDER BY depth;
