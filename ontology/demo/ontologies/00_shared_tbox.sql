-- ============================================================================
-- Shared TBox additions for the multi-source ontology demo
-- ============================================================================
-- The base substrate (02_load_synthetic_data.sql) seeds schema:, xsd:, ex:
-- namespaces plus schema:name / schema:email / schema:addressRegion. The
-- per-source loaders (ontologies/<system>.sql) reuse those shared schema.org
-- properties for labels, emails, and region so the generic Cortex Search
-- service and Gold views work uniformly across every source system.
--
-- This script adds the handful of additional schema.org properties the source
-- mappings reference. Run it once, after 02, before any ontologies/<system>.sql.
-- It is idempotent (MERGE).
-- ============================================================================

USE ROLE      ONT_DEMO_BUILDER_ROLE;
USE DATABASE  ONT_DEMO;
USE SCHEMA    SILVER;
USE WAREHOUSE ONT_DEMO_INGEST_WH;

MERGE INTO property AS t
USING (
    SELECT column1::STRING AS property_iri, column2::STRING AS namespace_iri, column3::STRING AS label,
           column4::STRING AS kind, column5::STRING AS domain_class_iri, column6::STRING AS range_class_iri,
           column7::STRING AS range_datatype, column8::STRING AS range_domain_iri,
           column9::INTEGER AS min_count, column10::INTEGER AS max_count, NULL::STRING AS sub_property_of
    FROM VALUES
      ('schema:addressLocality', 'http://schema.org/', 'addressLocality', 'datatype', 'schema:Thing', NULL, 'xsd:string', NULL, 0, 1),
      ('schema:telephone',       'http://schema.org/', 'telephone',       'datatype', 'schema:Thing', NULL, 'xsd:string', NULL, 0, 1),
      ('schema:url',             'http://schema.org/', 'url',             'datatype', 'schema:Thing', NULL, 'xsd:string', NULL, 0, 1)
) s ON t.property_iri = s.property_iri
WHEN NOT MATCHED THEN INSERT VALUES
    (s.property_iri, s.namespace_iri, s.label, s.kind, s.domain_class_iri,
     s.range_class_iri, s.range_datatype, s.range_domain_iri, s.min_count, s.max_count, s.sub_property_of);

SELECT 'shared schema.org properties merged' AS status;
