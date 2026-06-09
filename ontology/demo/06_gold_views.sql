-- ============================================================================
-- 06_gold_views.sql — metadata-driven GOLD view generator
-- ----------------------------------------------------------------------------
-- Replaces the hand-written CPG-only V_CPG_* views + cpg_node DT. Instead of
-- one static view per business entity, a stored procedure inspects the ABox
-- and builds one wide GOLD view per class for a given source system, pivoting
-- whatever literal predicates and object edges each class actually uses. The
-- same procedure therefore serves all six source systems.
--
-- Generated view name: GOLD.V_<SYSTEM>_<CLASS>  (e.g. GOLD.V_SAP_CUSTOMER)
--   uid, label, name, <one column per literal predicate>, <one *_uid per edge>
--
-- Run AFTER the TBox + ABox for the source are loaded (ontologies/<sys>.sql,
-- 02b_load_source_ontology.sql), so the predicates are present to pivot.
-- ============================================================================

USE ROLE      ONT_DEMO_BUILDER_ROLE;
USE DATABASE  ONT_DEMO;
USE SCHEMA    GOLD;
USE WAREHOUSE ONT_DEMO_INGEST_WH;

CREATE OR REPLACE PROCEDURE GOLD.SP_BUILD_GOLD_VIEWS(SOURCE_PREFIX STRING)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    ns_iri      STRING DEFAULT 'http://example.com/ont/' || :SOURCE_PREFIX || '/';
    sys_upper   STRING DEFAULT UPPER(:SOURCE_PREFIX);
    made        INTEGER DEFAULT 0;
    class_iri   STRING;
    class_local STRING;
    view_name   STRING;
    lit_cols    STRING;
    obj_cols    STRING;
    ddl         STRING;
    -- A cursor query cannot take a bind variable through an implicit FOR loop,
    -- so the class list is materialized via a dynamically built RESULTSET.
    rs RESULTSET;
BEGIN
    rs := (EXECUTE IMMEDIATE
        'SELECT class_iri FROM ONT_DEMO.SILVER.class WHERE namespace_iri = '''
        || :ns_iri || '''');
    -- Declare the cursor AFTER the RESULTSET is assigned (else it binds null).
    LET c CURSOR FOR rs;
    FOR rec IN c DO
        class_iri   := rec.class_iri;
        class_local := SPLIT_PART(class_iri, ':', 2);
        view_name   := 'V_' || :sys_upper || '_' ||
                       UPPER(REGEXP_REPLACE(class_local, '[^A-Za-z0-9]', '_'));

        -- One literal column per datatype predicate this class actually uses
        -- (excluding schema:name, which is surfaced as a fixed `name` column).
        SELECT COALESCE(LISTAGG(
                 ', (SELECT MAX(object_literal) FROM ONT_DEMO.SILVER.statement s2'
                 || ' WHERE s2.subject_uid = i.individual_uid AND s2.valid_to IS NULL'
                 || ' AND s2.predicate_iri = ''' || predicate_iri || ''') AS '
                 || LOWER(REGEXP_REPLACE(SPLIT_PART(predicate_iri, ':', 2),
                                         '([a-z0-9])([A-Z])', '\\1_\\2'))
               , ''), '')
          INTO :lit_cols
          FROM (
              SELECT DISTINCT s.predicate_iri
              FROM ONT_DEMO.SILVER.statement s
              JOIN ONT_DEMO.SILVER.individual i ON i.individual_uid = s.subject_uid
              WHERE i.class_iri = :class_iri
                AND s.object_literal IS NOT NULL
                AND s.predicate_iri <> 'schema:name'
          );

        -- One <edge>_uid column per object predicate this class actually uses.
        SELECT COALESCE(LISTAGG(
                 ', (SELECT MAX(object_uid) FROM ONT_DEMO.SILVER.statement s3'
                 || ' WHERE s3.subject_uid = i.individual_uid AND s3.valid_to IS NULL'
                 || ' AND s3.predicate_iri = ''' || predicate_iri || ''') AS '
                 || LOWER(REGEXP_REPLACE(SPLIT_PART(predicate_iri, ':', 2),
                                         '([a-z0-9])([A-Z])', '\\1_\\2')) || '_uid'
               , ''), '')
          INTO :obj_cols
          FROM (
              SELECT DISTINCT s.predicate_iri
              FROM ONT_DEMO.SILVER.statement s
              JOIN ONT_DEMO.SILVER.individual i ON i.individual_uid = s.subject_uid
              WHERE i.class_iri = :class_iri
                AND s.object_uid IS NOT NULL
          );

        ddl := 'CREATE OR REPLACE VIEW GOLD.' || view_name || ' AS SELECT '
            || 'i.individual_uid AS uid, i.label, '
            || '(SELECT MAX(object_literal) FROM ONT_DEMO.SILVER.statement s1 '
            || 'WHERE s1.subject_uid = i.individual_uid AND s1.valid_to IS NULL '
            || 'AND s1.predicate_iri = ''schema:name'') AS name'
            || :lit_cols || :obj_cols
            || ' FROM ONT_DEMO.SILVER.individual i'
            || ' WHERE i.class_iri = ''' || class_iri || ''' AND i.valid_to IS NULL';

        EXECUTE IMMEDIATE :ddl;
        made := made + 1;
    END FOR;

    RETURN 'Built ' || made || ' GOLD views for source ' || :sys_upper;
END;
$$;

-- Build views for whichever sources you have loaded (safe to skip unused ones;
-- a source with no classes simply produces zero views).
CALL GOLD.SP_BUILD_GOLD_VIEWS('sap');
CALL GOLD.SP_BUILD_GOLD_VIEWS('sfdc');
CALL GOLD.SP_BUILD_GOLD_VIEWS('ora');
CALL GOLD.SP_BUILD_GOLD_VIEWS('fhir');
CALL GOLD.SP_BUILD_GOLD_VIEWS('wd');
CALL GOLD.SP_BUILD_GOLD_VIEWS('snow');
-- Optional CPG vertical (only if ontologies/cpg.sql + CPG data were loaded):
-- CALL GOLD.SP_BUILD_GOLD_VIEWS('cpg');

SELECT 'GOLD view generator installed and run for all loaded sources.' AS status;
