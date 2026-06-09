-- ============================================================================
-- SERVICENOW ontology (TBox) — generated from mappings/servicenow.py
-- ============================================================================
-- Do not edit by hand. Regenerate with: python tools/generate_tbox.py
-- Mirrors ontologies/servicenow.ttl. Loads namespace/class/property/
-- shape/constraint into the shared SILVER TBox. The matching ABox comes from:
--     python tools/generate_ontology_data.py --system servicenow
--     snow sql -D "SYSTEM=servicenow" -f 02b_load_source_ontology.sql
-- Prereqs: 01_setup_database.sql, 02_load_synthetic_data.sql, 00_shared_tbox.sql
-- Idempotent (MERGE).
-- ============================================================================

USE ROLE      ONT_DEMO_BUILDER_ROLE;
USE DATABASE  ONT_DEMO;
USE SCHEMA    SILVER;
USE WAREHOUSE ONT_DEMO_INGEST_WH;

-- 0. Namespace
MERGE INTO namespace AS t
USING (SELECT column1 AS namespace_iri, column2 AS prefix, column3 AS description
       FROM VALUES ('http://example.com/ont/snow/', 'snow', 'SERVICENOW source-system ontology')) s
ON t.namespace_iri = s.namespace_iri
WHEN NOT MATCHED THEN INSERT VALUES (s.namespace_iri, s.prefix, s.description);

-- 1. Classes
MERGE INTO class AS t
USING (SELECT column1 AS class_iri, column2 AS namespace_iri, column3 AS label,
              column4 AS definition, column5 AS sub_class_of
       FROM VALUES
         ('snow:User', 'http://example.com/ont/snow/', 'User', 'SERVICENOW sys_user', 'schema:Person'),
         ('snow:Incident', 'http://example.com/ont/snow/', 'Incident', 'SERVICENOW incident', 'schema:Thing'),
         ('snow:ChangeRequest', 'http://example.com/ont/snow/', 'Change Request', 'SERVICENOW change_request', 'schema:Thing'),
         ('snow:Problem', 'http://example.com/ont/snow/', 'Problem', 'SERVICENOW problem', 'schema:Thing'),
         ('snow:ConfigurationItem', 'http://example.com/ont/snow/', 'Configuration Item', 'SERVICENOW cmdb_ci', 'schema:Thing'),
         ('snow:CatalogRequest', 'http://example.com/ont/snow/', 'Catalog Request', 'SERVICENOW sc_request', 'schema:Thing'),
         ('snow:KnowledgeArticle', 'http://example.com/ont/snow/', 'Knowledge Article', 'SERVICENOW kb_knowledge', 'schema:Thing')
       ) s ON t.class_iri = s.class_iri
WHEN NOT MATCHED THEN INSERT VALUES
    (s.class_iri, s.namespace_iri, s.label, s.definition, s.sub_class_of);

-- 2. Properties
MERGE INTO property AS t
USING (SELECT column1 AS property_iri, column2 AS namespace_iri, column3 AS label,
              column4 AS kind, column5 AS domain_class_iri, column6 AS range_class_iri,
              column7 AS range_datatype, column8 AS range_domain_iri,
              column9 AS min_count, column10 AS max_count, column11 AS sub_property_of
       FROM VALUES
         ('snow:userName', 'http://example.com/ont/snow/', 'user Name', 'datatype', 'snow:User', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('snow:title', 'http://example.com/ont/snow/', 'title', 'datatype', 'snow:User', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('snow:active', 'http://example.com/ont/snow/', 'active', 'datatype', 'snow:User', NULL, 'xsd:boolean', NULL, 0, 1, NULL),
         ('snow:vip', 'http://example.com/ont/snow/', 'vip', 'datatype', 'snow:User', NULL, 'xsd:boolean', NULL, 0, 1, NULL),
         ('snow:number', 'http://example.com/ont/snow/', 'number', 'datatype', 'snow:Incident', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('snow:state', 'http://example.com/ont/snow/', 'state', 'datatype', 'snow:Incident', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('snow:priority', 'http://example.com/ont/snow/', 'priority', 'datatype', 'snow:Incident', NULL, 'xsd:integer', NULL, 0, 1, NULL),
         ('snow:impact', 'http://example.com/ont/snow/', 'impact', 'datatype', 'snow:Incident', NULL, 'xsd:integer', NULL, 0, 1, NULL),
         ('snow:urgency', 'http://example.com/ont/snow/', 'urgency', 'datatype', 'snow:Incident', NULL, 'xsd:integer', NULL, 0, 1, NULL),
         ('snow:category', 'http://example.com/ont/snow/', 'category', 'datatype', 'snow:Incident', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('snow:openedAt', 'http://example.com/ont/snow/', 'opened At', 'datatype', 'snow:Incident', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('snow:caller', 'http://example.com/ont/snow/', 'caller', 'object', 'snow:Incident', 'snow:User', NULL, NULL, 0, 1, NULL),
         ('snow:assignedTo', 'http://example.com/ont/snow/', 'assigned To', 'object', 'snow:Incident', 'snow:User', NULL, NULL, 0, 1, NULL),
         ('snow:changeType', 'http://example.com/ont/snow/', 'change Type', 'datatype', 'snow:ChangeRequest', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('snow:risk', 'http://example.com/ont/snow/', 'risk', 'datatype', 'snow:ChangeRequest', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('snow:startDate', 'http://example.com/ont/snow/', 'start Date', 'datatype', 'snow:ChangeRequest', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('snow:requestedBy', 'http://example.com/ont/snow/', 'requested By', 'object', 'snow:ChangeRequest', 'snow:User', NULL, NULL, 0, 1, NULL),
         ('snow:knownError', 'http://example.com/ont/snow/', 'known Error', 'datatype', 'snow:Problem', NULL, 'xsd:boolean', NULL, 0, 1, NULL),
         ('snow:ciClass', 'http://example.com/ont/snow/', 'ci Class', 'datatype', 'snow:ConfigurationItem', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('snow:assetTag', 'http://example.com/ont/snow/', 'asset Tag', 'datatype', 'snow:ConfigurationItem', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('snow:serialNumber', 'http://example.com/ont/snow/', 'serial Number', 'datatype', 'snow:ConfigurationItem', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('snow:ipAddress', 'http://example.com/ont/snow/', 'ip Address', 'datatype', 'snow:ConfigurationItem', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('snow:installStatus', 'http://example.com/ont/snow/', 'install Status', 'datatype', 'snow:ConfigurationItem', NULL, 'xsd:integer', NULL, 0, 1, NULL),
         ('snow:cost', 'http://example.com/ont/snow/', 'cost', 'datatype', 'snow:ConfigurationItem', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('snow:stage', 'http://example.com/ont/snow/', 'stage', 'datatype', 'snow:CatalogRequest', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('snow:price', 'http://example.com/ont/snow/', 'price', 'datatype', 'snow:CatalogRequest', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('snow:requestedFor', 'http://example.com/ont/snow/', 'requested For', 'object', 'snow:CatalogRequest', 'snow:User', NULL, NULL, 0, 1, NULL),
         ('snow:workflowState', 'http://example.com/ont/snow/', 'workflow State', 'datatype', 'snow:KnowledgeArticle', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('snow:viewCount', 'http://example.com/ont/snow/', 'view Count', 'datatype', 'snow:KnowledgeArticle', NULL, 'xsd:integer', NULL, 0, 1, NULL),
         ('snow:rating', 'http://example.com/ont/snow/', 'rating', 'datatype', 'snow:KnowledgeArticle', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('snow:author', 'http://example.com/ont/snow/', 'author', 'object', 'snow:KnowledgeArticle', 'snow:User', NULL, NULL, 0, 1, NULL)
       ) s ON t.property_iri = s.property_iri
WHEN NOT MATCHED THEN INSERT VALUES
    (s.property_iri, s.namespace_iri, s.label, s.kind, s.domain_class_iri,
     s.range_class_iri, s.range_datatype, s.range_domain_iri,
     s.min_count::INTEGER, s.max_count::INTEGER, s.sub_property_of);

-- 3. Shapes
MERGE INTO shape AS t
USING (SELECT column1 AS shape_iri, column2 AS target_class_iri, column3 AS label
       FROM VALUES
         ('snow:UserShape', 'snow:User', 'User data-quality contract'),
         ('snow:IncidentShape', 'snow:Incident', 'Incident data-quality contract'),
         ('snow:ChangeRequestShape', 'snow:ChangeRequest', 'Change Request data-quality contract'),
         ('snow:ProblemShape', 'snow:Problem', 'Problem data-quality contract'),
         ('snow:ConfigurationItemShape', 'snow:ConfigurationItem', 'Configuration Item data-quality contract'),
         ('snow:CatalogRequestShape', 'snow:CatalogRequest', 'Catalog Request data-quality contract'),
         ('snow:KnowledgeArticleShape', 'snow:KnowledgeArticle', 'Knowledge Article data-quality contract')
       ) s ON t.shape_iri = s.shape_iri
WHEN NOT MATCHED THEN INSERT VALUES (s.shape_iri, s.target_class_iri, s.label);

-- 4. Constraints
MERGE INTO constraint AS t
USING (SELECT column1 AS constraint_id, column2 AS shape_iri, column3 AS kind,
              column4 AS property_iri, column5 AS body
       FROM VALUES
         ('servicenow-c01', 'snow:UserShape', 'minCount', 'schema:name', '1'),
         ('servicenow-c02', 'snow:IncidentShape', 'minCount', 'schema:name', '1'),
         ('servicenow-c03', 'snow:ChangeRequestShape', 'minCount', 'schema:name', '1'),
         ('servicenow-c04', 'snow:ProblemShape', 'minCount', 'schema:name', '1'),
         ('servicenow-c05', 'snow:ConfigurationItemShape', 'minCount', 'schema:name', '1'),
         ('servicenow-c06', 'snow:CatalogRequestShape', 'minCount', 'schema:name', '1'),
         ('servicenow-c07', 'snow:KnowledgeArticleShape', 'minCount', 'schema:name', '1')
       ) s ON t.constraint_id = s.constraint_id
WHEN NOT MATCHED THEN INSERT VALUES
    (s.constraint_id, s.shape_iri, s.kind, s.property_iri, s.body);

SELECT 'SERVICENOW ontology (TBox) loaded' AS status,
       (SELECT COUNT(*) FROM class WHERE namespace_iri = 'http://example.com/ont/snow/')    AS classes,
       (SELECT COUNT(*) FROM property WHERE namespace_iri = 'http://example.com/ont/snow/') AS properties;
