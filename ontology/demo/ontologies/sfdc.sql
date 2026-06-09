-- ============================================================================
-- SALESFORCE ontology (TBox) — generated from mappings/salesforce.py
-- ============================================================================
-- Do not edit by hand. Regenerate with: python tools/generate_tbox.py
-- Mirrors ontologies/salesforce.ttl. Loads namespace/class/property/
-- shape/constraint into the shared SILVER TBox. The matching ABox comes from:
--     python tools/generate_ontology_data.py --system salesforce
--     snow sql -D "SYSTEM=salesforce" -f 02b_load_source_ontology.sql
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
       FROM VALUES ('http://example.com/ont/sfdc/', 'sfdc', 'SALESFORCE source-system ontology')) s
ON t.namespace_iri = s.namespace_iri
WHEN NOT MATCHED THEN INSERT VALUES (s.namespace_iri, s.prefix, s.description);

-- 1. Classes
MERGE INTO class AS t
USING (SELECT column1 AS class_iri, column2 AS namespace_iri, column3 AS label,
              column4 AS definition, column5 AS sub_class_of
       FROM VALUES
         ('sfdc:Account', 'http://example.com/ont/sfdc/', 'Account', 'SALESFORCE Account', 'schema:Organization'),
         ('sfdc:Contact', 'http://example.com/ont/sfdc/', 'Contact', 'SALESFORCE Contact', 'schema:Person'),
         ('sfdc:Opportunity', 'http://example.com/ont/sfdc/', 'Opportunity', 'SALESFORCE Opportunity', 'schema:Thing'),
         ('sfdc:Case', 'http://example.com/ont/sfdc/', 'Case', 'SALESFORCE Case', 'schema:Thing'),
         ('sfdc:Lead', 'http://example.com/ont/sfdc/', 'Lead', 'SALESFORCE Lead', 'schema:Organization'),
         ('sfdc:Product', 'http://example.com/ont/sfdc/', 'Product', 'SALESFORCE Product2', 'schema:Thing'),
         ('sfdc:Campaign', 'http://example.com/ont/sfdc/', 'Campaign', 'SALESFORCE Campaign', 'schema:Organization'),
         ('sfdc:Task', 'http://example.com/ont/sfdc/', 'Task', 'SALESFORCE Task', 'schema:Thing')
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
         ('sfdc:industry', 'http://example.com/ont/sfdc/', 'industry', 'datatype', 'sfdc:Account', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sfdc:accountType', 'http://example.com/ont/sfdc/', 'account Type', 'datatype', 'sfdc:Account', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sfdc:rating', 'http://example.com/ont/sfdc/', 'rating', 'datatype', 'sfdc:Account', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sfdc:annualRevenue', 'http://example.com/ont/sfdc/', 'annual Revenue', 'datatype', 'sfdc:Account', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('sfdc:numberOfEmployees', 'http://example.com/ont/sfdc/', 'number Of Employees', 'datatype', 'sfdc:Account', NULL, 'xsd:integer', NULL, 0, 1, NULL),
         ('sfdc:customerSegment', 'http://example.com/ont/sfdc/', 'customer Segment', 'datatype', 'sfdc:Account', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sfdc:firstName', 'http://example.com/ont/sfdc/', 'first Name', 'datatype', 'sfdc:Contact', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sfdc:lastName', 'http://example.com/ont/sfdc/', 'last Name', 'datatype', 'sfdc:Contact', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sfdc:title', 'http://example.com/ont/sfdc/', 'title', 'datatype', 'sfdc:Contact', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sfdc:department', 'http://example.com/ont/sfdc/', 'department', 'datatype', 'sfdc:Contact', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sfdc:leadSource', 'http://example.com/ont/sfdc/', 'lead Source', 'datatype', 'sfdc:Contact', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sfdc:belongsToAccount', 'http://example.com/ont/sfdc/', 'belongs To Account', 'object', 'sfdc:Contact', 'sfdc:Account', NULL, NULL, 0, 1, NULL),
         ('sfdc:amount', 'http://example.com/ont/sfdc/', 'amount', 'datatype', 'sfdc:Opportunity', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('sfdc:stageName', 'http://example.com/ont/sfdc/', 'stage Name', 'datatype', 'sfdc:Opportunity', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sfdc:probability', 'http://example.com/ont/sfdc/', 'probability', 'datatype', 'sfdc:Opportunity', NULL, 'xsd:integer', NULL, 0, 1, NULL),
         ('sfdc:closeDate', 'http://example.com/ont/sfdc/', 'close Date', 'datatype', 'sfdc:Opportunity', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sfdc:opportunityType', 'http://example.com/ont/sfdc/', 'opportunity Type', 'datatype', 'sfdc:Opportunity', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sfdc:forecastCategory', 'http://example.com/ont/sfdc/', 'forecast Category', 'datatype', 'sfdc:Opportunity', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sfdc:relatedAccount', 'http://example.com/ont/sfdc/', 'related Account', 'object', 'sfdc:Opportunity', 'sfdc:Account', NULL, NULL, 0, 1, NULL),
         ('sfdc:caseNumber', 'http://example.com/ont/sfdc/', 'case Number', 'datatype', 'sfdc:Case', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sfdc:status', 'http://example.com/ont/sfdc/', 'status', 'datatype', 'sfdc:Case', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sfdc:priority', 'http://example.com/ont/sfdc/', 'priority', 'datatype', 'sfdc:Case', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sfdc:caseType', 'http://example.com/ont/sfdc/', 'case Type', 'datatype', 'sfdc:Case', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sfdc:origin', 'http://example.com/ont/sfdc/', 'origin', 'datatype', 'sfdc:Case', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sfdc:relatedContact', 'http://example.com/ont/sfdc/', 'related Contact', 'object', 'sfdc:Case', 'sfdc:Contact', NULL, NULL, 0, 1, NULL),
         ('sfdc:productCode', 'http://example.com/ont/sfdc/', 'product Code', 'datatype', 'sfdc:Product', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sfdc:family', 'http://example.com/ont/sfdc/', 'family', 'datatype', 'sfdc:Product', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sfdc:sku', 'http://example.com/ont/sfdc/', 'sku', 'datatype', 'sfdc:Product', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sfdc:unitOfMeasure', 'http://example.com/ont/sfdc/', 'unit Of Measure', 'datatype', 'sfdc:Product', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sfdc:campaignType', 'http://example.com/ont/sfdc/', 'campaign Type', 'datatype', 'sfdc:Campaign', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sfdc:budgetedCost', 'http://example.com/ont/sfdc/', 'budgeted Cost', 'datatype', 'sfdc:Campaign', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('sfdc:expectedRevenue', 'http://example.com/ont/sfdc/', 'expected Revenue', 'datatype', 'sfdc:Campaign', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('sfdc:activityDate', 'http://example.com/ont/sfdc/', 'activity Date', 'datatype', 'sfdc:Task', NULL, 'xsd:string', NULL, 0, 1, NULL)
       ) s ON t.property_iri = s.property_iri
WHEN NOT MATCHED THEN INSERT VALUES
    (s.property_iri, s.namespace_iri, s.label, s.kind, s.domain_class_iri,
     s.range_class_iri, s.range_datatype, s.range_domain_iri,
     s.min_count::INTEGER, s.max_count::INTEGER, s.sub_property_of);

-- 3. Shapes
MERGE INTO shape AS t
USING (SELECT column1 AS shape_iri, column2 AS target_class_iri, column3 AS label
       FROM VALUES
         ('sfdc:AccountShape', 'sfdc:Account', 'Account data-quality contract'),
         ('sfdc:ContactShape', 'sfdc:Contact', 'Contact data-quality contract'),
         ('sfdc:OpportunityShape', 'sfdc:Opportunity', 'Opportunity data-quality contract'),
         ('sfdc:CaseShape', 'sfdc:Case', 'Case data-quality contract'),
         ('sfdc:LeadShape', 'sfdc:Lead', 'Lead data-quality contract'),
         ('sfdc:ProductShape', 'sfdc:Product', 'Product data-quality contract'),
         ('sfdc:CampaignShape', 'sfdc:Campaign', 'Campaign data-quality contract'),
         ('sfdc:TaskShape', 'sfdc:Task', 'Task data-quality contract')
       ) s ON t.shape_iri = s.shape_iri
WHEN NOT MATCHED THEN INSERT VALUES (s.shape_iri, s.target_class_iri, s.label);

-- 4. Constraints
MERGE INTO constraint AS t
USING (SELECT column1 AS constraint_id, column2 AS shape_iri, column3 AS kind,
              column4 AS property_iri, column5 AS body
       FROM VALUES
         ('salesforce-c01', 'sfdc:AccountShape', 'minCount', 'schema:name', '1'),
         ('salesforce-c02', 'sfdc:OpportunityShape', 'minCount', 'schema:name', '1'),
         ('salesforce-c03', 'sfdc:CaseShape', 'minCount', 'schema:name', '1'),
         ('salesforce-c04', 'sfdc:LeadShape', 'minCount', 'schema:name', '1'),
         ('salesforce-c05', 'sfdc:ProductShape', 'minCount', 'schema:name', '1'),
         ('salesforce-c06', 'sfdc:CampaignShape', 'minCount', 'schema:name', '1'),
         ('salesforce-c07', 'sfdc:TaskShape', 'minCount', 'schema:name', '1')
       ) s ON t.constraint_id = s.constraint_id
WHEN NOT MATCHED THEN INSERT VALUES
    (s.constraint_id, s.shape_iri, s.kind, s.property_iri, s.body);

SELECT 'SALESFORCE ontology (TBox) loaded' AS status,
       (SELECT COUNT(*) FROM class WHERE namespace_iri = 'http://example.com/ont/sfdc/')    AS classes,
       (SELECT COUNT(*) FROM property WHERE namespace_iri = 'http://example.com/ont/sfdc/') AS properties;
