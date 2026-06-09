-- ============================================================================
-- 07_dmfs.sql — metadata-driven data-quality from silver.constraint
-- ----------------------------------------------------------------------------
-- Replaces the CPG-specific dmf_cpg_* functions. Three GENERIC Data Metric
-- Functions evaluate every SHACL-style constraint stored in silver.constraint
-- (authored per source in ontologies/<system>.sql), so the Health tab works
-- for all six source systems with no per-source code.
--
--   dmf_mincount_violations  — minCount constraints  (missing required props)
--   dmf_pattern_violations   — pattern constraints   (regex on literals)
--   dmf_enum_violations      — 'in' constraints      (allowed value list)
--
-- A companion GOLD.v_ontology_health view evaluates the same constraints live
-- (no DMF schedule wait) and is what streamlit_app.py's Health tab reads.
-- ============================================================================

USE ROLE      ONT_DEMO_BUILDER_ROLE;
USE DATABASE  ONT_DEMO;
USE SCHEMA    SILVER;
USE WAREHOUSE ONT_DEMO_INGEST_WH;

-- ---------------------------------------------------------------------------
-- 1. Generic DMFs (constraint-driven)
-- ---------------------------------------------------------------------------

-- minCount: count (individual, required-property) pairs that fall short.
CREATE OR REPLACE DATA METRIC FUNCTION dmf_mincount_violations (
    ARG_T TABLE(individual_uid STRING, class_iri STRING)
) RETURNS NUMBER AS
$$
    SELECT COUNT(*) FROM (
        SELECT i.individual_uid, con.property_iri
        FROM ARG_T i
        JOIN ONT_DEMO.SILVER.shape sh      ON sh.target_class_iri = i.class_iri
        JOIN ONT_DEMO.SILVER.constraint con ON con.shape_iri = sh.shape_iri
                                           AND con.kind = 'minCount'
        LEFT JOIN ONT_DEMO.SILVER.statement s
               ON s.subject_uid = i.individual_uid
              AND s.predicate_iri = con.property_iri
              AND s.valid_to IS NULL
        GROUP BY i.individual_uid, con.property_iri, con.body
        HAVING COUNT(s.statement_id) < TRY_CAST(con.body AS INTEGER)
    )
$$;

-- pattern: count literals that violate a regex constraint on their predicate.
CREATE OR REPLACE DATA METRIC FUNCTION dmf_pattern_violations (
    ARG_T TABLE(statement_id STRING, predicate_iri STRING, object_literal STRING)
) RETURNS NUMBER AS
$$
    SELECT COUNT(*)
    FROM ARG_T s
    JOIN ONT_DEMO.SILVER.constraint con
      ON con.kind = 'pattern' AND con.property_iri = s.predicate_iri
    WHERE s.object_literal IS NOT NULL
      AND NOT REGEXP_LIKE(s.object_literal, con.body)
$$;

-- in: count literals outside the allowed comma-separated value list.
CREATE OR REPLACE DATA METRIC FUNCTION dmf_enum_violations (
    ARG_T TABLE(statement_id STRING, predicate_iri STRING, object_literal STRING)
) RETURNS NUMBER AS
$$
    SELECT COUNT(*)
    FROM ARG_T s
    JOIN ONT_DEMO.SILVER.constraint con
      ON con.kind = 'in' AND con.property_iri = s.predicate_iri
    WHERE s.object_literal IS NOT NULL
      AND NOT ARRAY_CONTAINS(s.object_literal::VARIANT, SPLIT(con.body, ','))
$$;

-- ---------------------------------------------------------------------------
-- 2. Attach the DMFs (schedule is set by 04_dbt_tests_and_dmfs.sql)
-- ---------------------------------------------------------------------------
ALTER TABLE individual ADD DATA METRIC FUNCTION dmf_mincount_violations ON (individual_uid, class_iri);
ALTER TABLE statement  ADD DATA METRIC FUNCTION dmf_pattern_violations  ON (statement_id, predicate_iri, object_literal);
ALTER TABLE statement  ADD DATA METRIC FUNCTION dmf_enum_violations     ON (statement_id, predicate_iri, object_literal);

-- ---------------------------------------------------------------------------
-- 3. Live, source-aware health roll-up (no DMF schedule wait)
--    One row per constraint with violation + evaluated counts, tagged by the
--    source system (derived from the target class's namespace prefix).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW GOLD.v_ontology_health AS
-- minCount: evaluated = #individuals of the class; violations = #short
WITH per_individual AS (
    SELECT con.constraint_id, con.shape_iri, con.kind, con.property_iri,
           sh.target_class_iri AS class_iri, cl.namespace_iri,
           i.individual_uid,
           COUNT(s.statement_id) AS have,
           TRY_CAST(con.body AS INTEGER) AS need
    FROM SILVER.constraint con
    JOIN SILVER.shape sh ON sh.shape_iri = con.shape_iri
    JOIN SILVER.class cl ON cl.class_iri = sh.target_class_iri
    JOIN SILVER.individual i ON i.class_iri = sh.target_class_iri AND i.valid_to IS NULL
    LEFT JOIN SILVER.statement s
           ON s.subject_uid = i.individual_uid
          AND s.predicate_iri = con.property_iri
          AND s.valid_to IS NULL
    WHERE con.kind = 'minCount'
    GROUP BY 1,2,3,4,5,6,7,9
),
mincount AS (
    SELECT UPPER(ns.prefix) AS source_system, p.constraint_id, p.shape_iri, p.class_iri,
           p.kind, p.property_iri,
           COUNT(*) AS evaluated,
           SUM(IFF(p.have < p.need, 1, 0)) AS violations
    FROM per_individual p
    JOIN SILVER.namespace ns ON ns.namespace_iri = p.namespace_iri
    GROUP BY 1,2,3,4,5,6
),
literal_checks AS (
    SELECT UPPER(ns.prefix) AS source_system, con.constraint_id, con.shape_iri,
           sh.target_class_iri AS class_iri, con.kind, con.property_iri,
           COUNT(s.statement_id) AS evaluated,
           SUM(
               CASE
                   WHEN con.kind = 'pattern'
                        AND NOT REGEXP_LIKE(s.object_literal, con.body) THEN 1
                   WHEN con.kind = 'in'
                        AND NOT ARRAY_CONTAINS(s.object_literal::VARIANT, SPLIT(con.body, ',')) THEN 1
                   ELSE 0
               END
           ) AS violations
    FROM SILVER.constraint con
    JOIN SILVER.shape sh ON sh.shape_iri = con.shape_iri
    JOIN SILVER.class cl ON cl.class_iri = sh.target_class_iri
    JOIN SILVER.namespace ns ON ns.namespace_iri = cl.namespace_iri
    JOIN SILVER.statement s
      ON s.predicate_iri = con.property_iri
     AND s.object_literal IS NOT NULL
     AND s.valid_to IS NULL
    WHERE con.kind IN ('pattern', 'in')
    GROUP BY 1,2,3,4,5,6
)
SELECT * FROM mincount
UNION ALL
SELECT * FROM literal_checks;

SELECT 'Generic DMFs created + attached; GOLD.v_ontology_health ready.' AS status;
