-- ============================================================================
-- Snowflake Ontology Reference — 03_query_patterns.sql
-- ============================================================================
-- Builds the property-graph projections (node + edge) as Dynamic Tables,
-- adds search_optimization, creates a Cortex Search service, and demonstrates
-- the four canonical query patterns:
--
--   Q1 — single-entity lookup
--   Q2 — hierarchy walk (class subClassOf)
--   Q3 — multi-hop traversal (Customer → Order → Product)
--   Q4 — semantic discovery (Cortex Search + EMBED_TEXT cosine)
-- ============================================================================

USE ROLE ONT_DEMO_BUILDER_ROLE;
USE DATABASE ONT_DEMO;
USE SCHEMA SILVER;
USE WAREHOUSE ONT_DEMO_INGEST_WH;

-- ---------------------------------------------------------------------------
-- Dynamic Tables: node + edge projections of the triple store
-- ---------------------------------------------------------------------------

CREATE OR REPLACE DYNAMIC TABLE node
    TARGET_LAG = '1 minute'
    WAREHOUSE  = ONT_DEMO_INGEST_WH
    CLUSTER BY (class_iri)
AS
SELECT
    i.individual_uid       AS node_uid,
    i.canonical_iri        AS node_iri,
    i.class_iri,
    i.label,
    -- Pivot the most common datatype properties into typed columns for hot reads.
    MAX(CASE WHEN s.predicate_iri = 'schema:name'        THEN s.object_literal END) AS name,
    MAX(CASE WHEN s.predicate_iri = 'schema:email'       THEN s.object_literal END) AS email,
    MAX(CASE WHEN s.predicate_iri = 'ex:accountStatus'   THEN s.object_literal END) AS account_status,
    MAX(CASE WHEN s.predicate_iri = 'ex:orderStatus'     THEN s.object_literal END) AS order_status,
    MAX(CASE WHEN s.predicate_iri = 'ex:priceUSD'        THEN TRY_CAST(s.object_literal AS NUMBER(18,2)) END) AS price_usd,
    MAX(CASE WHEN s.predicate_iri = 'schema:addressRegion' THEN s.object_literal END) AS address_region,
    i.valid_from,
    i.valid_to
FROM individual i
LEFT JOIN statement s
       ON s.subject_uid = i.individual_uid
      AND s.valid_to IS NULL
WHERE i.valid_to IS NULL
GROUP BY ALL;

CREATE OR REPLACE DYNAMIC TABLE edge
    TARGET_LAG = '1 minute'
    WAREHOUSE  = ONT_DEMO_INGEST_WH
    CLUSTER BY (predicate_iri, src_uid)
AS
SELECT
    s.statement_id,
    s.subject_uid    AS src_uid,
    s.predicate_iri,
    s.object_uid     AS dst_uid,
    s.source_system,
    s.confidence,
    s.valid_from,
    s.valid_to
FROM statement s
WHERE s.object_uid IS NOT NULL          -- object-properties only; datatype values live on node
  AND s.valid_to IS NULL;

-- ---------------------------------------------------------------------------
-- Search optimization for fast triple lookups in both directions
-- ---------------------------------------------------------------------------
ALTER TABLE statement
    ADD SEARCH OPTIMIZATION ON EQUALITY (subject_uid, object_uid, predicate_iri);

-- ---------------------------------------------------------------------------
-- GOLD: friendly views the Cortex Analyst semantic model points at
-- ---------------------------------------------------------------------------
USE SCHEMA GOLD;

CREATE OR REPLACE VIEW v_customer AS
SELECT
    n.node_uid       AS customer_uid,
    n.node_iri       AS customer_iri,
    n.name           AS customer_name,
    n.address_region,
    n.valid_from,
    n.valid_to
FROM SILVER.node n
WHERE n.class_iri = 'ex:Customer';

CREATE OR REPLACE VIEW v_account AS
SELECT
    n.node_uid       AS account_uid,
    n.label          AS account_label,
    n.account_status,
    e.src_uid        AS customer_uid
FROM SILVER.node n
LEFT JOIN SILVER.edge e
       ON e.dst_uid = n.node_uid
      AND e.predicate_iri = 'ex:holdsAccount'
WHERE n.class_iri = 'ex:Account';

CREATE OR REPLACE VIEW v_product AS
SELECT
    n.node_uid       AS product_uid,
    n.name           AS product_name,
    n.class_iri,             -- 'ex:Product' or 'ex:Beverage'
    n.price_usd
FROM SILVER.node n
WHERE n.class_iri IN ('ex:Product','ex:Beverage');

CREATE OR REPLACE VIEW v_order AS
SELECT
    n.node_uid       AS order_uid,
    n.label          AS order_label,
    n.order_status,
    cust.src_uid     AS customer_uid
FROM SILVER.node n
LEFT JOIN SILVER.edge cust
       ON cust.dst_uid = n.node_uid
      AND cust.predicate_iri = 'ex:placedOrder'
WHERE n.class_iri = 'ex:Order';

CREATE OR REPLACE VIEW v_order_line AS
SELECT
    e.src_uid        AS order_uid,
    e.dst_uid        AS product_uid
FROM SILVER.edge e
WHERE e.predicate_iri = 'ex:orderedProduct';

-- ============================================================================
-- Q1 — Single-entity lookup (point read)
-- ============================================================================
-- Get one customer + its accounts. With a Hybrid Table on individual + node,
-- this is a single-digit-millisecond response in production.
-- ----------------------------------------------------------------------------
SELECT 'Q1 — Acme + its accounts' AS demo;

SELECT c.customer_name, a.account_uid, a.account_status
FROM   GOLD.v_customer c
JOIN   GOLD.v_account  a USING (customer_uid)
WHERE  c.customer_uid = 'CUST-1001';

-- ============================================================================
-- Q2 — Hierarchy walk (class hierarchy via subClassOf)
-- ============================================================================
-- All classes that are (transitively) a subclass of ex:Product.
-- ----------------------------------------------------------------------------
SELECT 'Q2 — descendant classes of ex:Product' AS demo;

WITH RECURSIVE class_tree AS (
    SELECT class_iri, sub_class_of, 0 AS depth, label
      FROM SILVER.class
     WHERE class_iri = 'ex:Product'
    UNION ALL
    SELECT c.class_iri, c.sub_class_of, t.depth + 1, c.label
      FROM SILVER.class c
      JOIN class_tree t ON c.sub_class_of = t.class_iri
)
SELECT class_iri, label, depth FROM class_tree ORDER BY depth, class_iri;

-- ============================================================================
-- Q3 — Multi-hop traversal (Customer → Order → Product)
-- ============================================================================
-- "All products ever ordered by Acme." Predicate-clustered edge table walks
-- fast even at billion-edge scale.
-- ----------------------------------------------------------------------------
SELECT 'Q3 — Products ordered by Acme' AS demo;

SELECT DISTINCT p.product_name, p.class_iri, p.price_usd
FROM   GOLD.v_customer  c
JOIN   GOLD.v_order     o   USING (customer_uid)
JOIN   GOLD.v_order_line ol ON o.order_uid = ol.order_uid
JOIN   GOLD.v_product   p   USING (product_uid)
WHERE  c.customer_name = 'Acme Inc.';

-- ============================================================================
-- Generic n-hop variant — recursive walk from any starting node along a set of
-- predicates, capped at max_depth.
-- ----------------------------------------------------------------------------
SELECT 'Q3 — recursive n-hop from CUST-1001 along {ex:placedOrder, ex:orderedProduct}' AS demo;

WITH RECURSIVE walk AS (
    SELECT src_uid, predicate_iri, dst_uid, 1 AS depth, ARRAY_CONSTRUCT(src_uid, dst_uid) AS path
      FROM SILVER.edge
     WHERE src_uid = 'CUST-1001'
       AND predicate_iri IN ('ex:placedOrder','ex:orderedProduct')
    UNION ALL
    SELECT e.src_uid, e.predicate_iri, e.dst_uid, w.depth + 1,
           ARRAY_APPEND(w.path, e.dst_uid)
      FROM SILVER.edge e
      JOIN walk w ON e.src_uid = w.dst_uid
     WHERE e.predicate_iri IN ('ex:placedOrder','ex:orderedProduct')
       AND w.depth < 5
       AND NOT ARRAY_CONTAINS(e.dst_uid::variant, w.path)   -- cycle guard
)
SELECT depth, src_uid, predicate_iri, dst_uid FROM walk ORDER BY depth, src_uid;

-- ============================================================================
-- Q4 — Semantic discovery (Cortex Search service)
-- ============================================================================
-- A hybrid (lexical + semantic) search service over individual labels + the
-- name / address_region literals on each node.
-- ----------------------------------------------------------------------------

USE SCHEMA SILVER;

CREATE OR REPLACE CORTEX SEARCH SERVICE node_search_svc
    ON search_text
    ATTRIBUTES class_iri, node_uid
    WAREHOUSE = ONT_DEMO_SEARCH_WH
    TARGET_LAG = '5 minutes'
    AS (
        SELECT
            node_uid,
            class_iri,
            COALESCE(name, label) || ' ' || COALESCE(address_region, '') AS search_text
        FROM SILVER.node
    );

-- Once the service is built, query it from SQL via SEARCH_PREVIEW (the
-- service!QUERY() table form exists only in the REST / Python APIs):
--   SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
--       'ONT_DEMO.SILVER.NODE_SEARCH_SVC',
--       '{"query":"cola drink","columns":["node_uid","class_iri","search_text"],"limit":5}'
--   );
-- ============================================================================
