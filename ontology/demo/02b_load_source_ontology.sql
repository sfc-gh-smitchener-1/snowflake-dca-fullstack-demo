-- ============================================================================
-- Snowflake Ontology Reference — 02b_load_source_ontology.sql
-- ============================================================================
-- Generic, source-parameterized BRONZE -> SILVER triple loader. Loads the
-- ontology ABox (individuals + object/literal statements) produced by the
-- adapter for ONE source system into the shared SILVER substrate that
-- 02_load_synthetic_data.sql created. Replaces the CPG-only
-- 02b_load_cpg_synthetic.sql.
--
-- The source system is supplied as a Snowflake CLI template variable so the
-- same script serves all six systems:
--
--     cd demo
--     python tools/generate_ontology_data.py --system sap     # writes data/sap/*.csv
--     snow sql -D "SYSTEM=sap" -f ontologies/sap.sql           # load the TBox
--     snow sql -D "SYSTEM=sap" -f 02b_load_source_ontology.sql # load the ABox
--
-- Prerequisites
--   1. 01_setup_database.sql
--   2. 02_load_synthetic_data.sql  (TBox tables + tiny core ABox)
--   3. 00_shared_tbox.sql          (shared schema.org properties)
--   4. ontologies/<SYSTEM>.sql     (the source's classes/properties/shapes)
--   5. data/<SYSTEM>/{individuals,statements_object,statements_literal}.csv
-- ============================================================================

USE ROLE      ONT_DEMO_BUILDER_ROLE;
USE DATABASE  ONT_DEMO;
USE SCHEMA    SILVER;
USE WAREHOUSE ONT_DEMO_INGEST_WH;

-- ---------------------------------------------------------------------------
-- 1. Reusable, source-agnostic file format + landing stage
-- ---------------------------------------------------------------------------
CREATE FILE FORMAT IF NOT EXISTS BRONZE.SOURCE_CSV
    TYPE = CSV
    PARSE_HEADER = TRUE
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('', 'NULL')
    EMPTY_FIELD_AS_NULL = TRUE
    REPLACE_INVALID_CHARACTERS = TRUE;

CREATE STAGE IF NOT EXISTS BRONZE.SOURCE_LANDING
    FILE_FORMAT = BRONZE.SOURCE_CSV
    DIRECTORY   = ( ENABLE = TRUE )
    COMMENT     = 'Landing stage for the source-system ontology adapter output';

-- ---------------------------------------------------------------------------
-- 2. Bronze landing tables (recreated per source load)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE BRONZE.SRC_INDIVIDUALS (
    INDIVIDUAL_UID  STRING,
    CANONICAL_IRI   STRING,
    CLASS_IRI       STRING,
    LABEL           STRING
);

CREATE OR REPLACE TABLE BRONZE.SRC_STATEMENTS_OBJECT (
    STATEMENT_ID    STRING,
    SUBJECT_UID     STRING,
    PREDICATE_IRI   STRING,
    OBJECT_UID      STRING
);

CREATE OR REPLACE TABLE BRONZE.SRC_STATEMENTS_LITERAL (
    STATEMENT_ID    STRING,
    SUBJECT_UID     STRING,
    PREDICATE_IRI   STRING,
    OBJECT_LITERAL  STRING,
    OBJECT_DATATYPE STRING
);

-- ---------------------------------------------------------------------------
-- 3. Upload + COPY INTO (paths namespaced by source so loads don't collide)
--    `snow sql` resolves the relative file:// path against the script's dir.
-- ---------------------------------------------------------------------------
PUT file://data/<% SYSTEM %>/individuals.csv
    @BRONZE.SOURCE_LANDING/<% SYSTEM %>/individuals/
    OVERWRITE = TRUE AUTO_COMPRESS = TRUE;

PUT file://data/<% SYSTEM %>/statements_object.csv
    @BRONZE.SOURCE_LANDING/<% SYSTEM %>/statements_object/
    OVERWRITE = TRUE AUTO_COMPRESS = TRUE;

PUT file://data/<% SYSTEM %>/statements_literal.csv
    @BRONZE.SOURCE_LANDING/<% SYSTEM %>/statements_literal/
    OVERWRITE = TRUE AUTO_COMPRESS = TRUE;

COPY INTO BRONZE.SRC_INDIVIDUALS
    FROM @BRONZE.SOURCE_LANDING/<% SYSTEM %>/individuals/
    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
    FILE_FORMAT = ( FORMAT_NAME = BRONZE.SOURCE_CSV );

COPY INTO BRONZE.SRC_STATEMENTS_OBJECT
    FROM @BRONZE.SOURCE_LANDING/<% SYSTEM %>/statements_object/
    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
    FILE_FORMAT = ( FORMAT_NAME = BRONZE.SOURCE_CSV );

COPY INTO BRONZE.SRC_STATEMENTS_LITERAL
    FROM @BRONZE.SOURCE_LANDING/<% SYSTEM %>/statements_literal/
    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
    FILE_FORMAT = ( FORMAT_NAME = BRONZE.SOURCE_CSV );

-- ---------------------------------------------------------------------------
-- 4. Promote Bronze -> Silver (the canonical ABox), tagged source_system
--    Individuals are de-duplicated by UID (a few source tables enrich the same
--    entity, e.g. SAP PA0001 + PA0002 both describe one Employee).
-- ---------------------------------------------------------------------------
INSERT INTO SILVER.individual (individual_uid, canonical_iri, class_iri, label, valid_from, valid_to)
SELECT individual_uid, canonical_iri, class_iri, label, CURRENT_TIMESTAMP(), NULL
FROM   BRONZE.SRC_INDIVIDUALS
QUALIFY ROW_NUMBER() OVER (PARTITION BY individual_uid ORDER BY label DESC NULLS LAST) = 1
AND    individual_uid NOT IN (SELECT individual_uid FROM SILVER.individual);

INSERT INTO SILVER.statement
    (statement_id, subject_uid, predicate_iri, object_uid, object_literal, object_datatype, source_system, confidence, valid_from, valid_to)
SELECT statement_id, subject_uid, predicate_iri, object_uid, NULL, NULL, UPPER('<% SYSTEM %>'), 1.0, CURRENT_TIMESTAMP(), NULL
FROM   BRONZE.SRC_STATEMENTS_OBJECT
WHERE  statement_id NOT IN (SELECT statement_id FROM SILVER.statement);

INSERT INTO SILVER.statement
    (statement_id, subject_uid, predicate_iri, object_uid, object_literal, object_datatype, source_system, confidence, valid_from, valid_to)
SELECT statement_id, subject_uid, predicate_iri, NULL, object_literal, object_datatype, UPPER('<% SYSTEM %>'), 1.0, CURRENT_TIMESTAMP(), NULL
FROM   BRONZE.SRC_STATEMENTS_LITERAL
WHERE  statement_id NOT IN (SELECT statement_id FROM SILVER.statement);

-- ---------------------------------------------------------------------------
-- 5. Volume report for this source
-- ---------------------------------------------------------------------------
SELECT UPPER('<% SYSTEM %>') AS source_system, i.class_iri, COUNT(*) AS individuals
FROM   SILVER.individual i
JOIN   SILVER.class c ON c.class_iri = i.class_iri
WHERE  c.namespace_iri = 'http://example.com/ont/<% SYSTEM %>/'
GROUP BY i.class_iri
ORDER BY individuals DESC;
