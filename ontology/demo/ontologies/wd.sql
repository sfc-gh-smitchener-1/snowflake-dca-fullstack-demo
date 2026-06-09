-- ============================================================================
-- WORKDAY ontology (TBox) — generated from mappings/workday.py
-- ============================================================================
-- Do not edit by hand. Regenerate with: python tools/generate_tbox.py
-- Mirrors ontologies/workday.ttl. Loads namespace/class/property/
-- shape/constraint into the shared SILVER TBox. The matching ABox comes from:
--     python tools/generate_ontology_data.py --system workday
--     snow sql -D "SYSTEM=workday" -f 02b_load_source_ontology.sql
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
       FROM VALUES ('http://example.com/ont/wd/', 'wd', 'WORKDAY source-system ontology')) s
ON t.namespace_iri = s.namespace_iri
WHEN NOT MATCHED THEN INSERT VALUES (s.namespace_iri, s.prefix, s.description);

-- 1. Classes
MERGE INTO class AS t
USING (SELECT column1 AS class_iri, column2 AS namespace_iri, column3 AS label,
              column4 AS definition, column5 AS sub_class_of
       FROM VALUES
         ('wd:Worker', 'http://example.com/ont/wd/', 'Worker', 'WORKDAY Workers', 'schema:Person'),
         ('wd:Organization', 'http://example.com/ont/wd/', 'Organization', 'WORKDAY Organizations', 'schema:Organization'),
         ('wd:JobProfile', 'http://example.com/ont/wd/', 'Job Profile', 'WORKDAY Job_Profiles', 'schema:Thing'),
         ('wd:Compensation', 'http://example.com/ont/wd/', 'Compensation', 'WORKDAY Compensation', 'schema:Thing'),
         ('wd:TimeOff', 'http://example.com/ont/wd/', 'Time Off', 'WORKDAY Time_Off', 'schema:Thing'),
         ('wd:BenefitElection', 'http://example.com/ont/wd/', 'Benefit Election', 'WORKDAY Benefit_Elections', 'schema:Thing')
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
         ('wd:firstName', 'http://example.com/ont/wd/', 'first Name', 'datatype', 'wd:Worker', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('wd:lastName', 'http://example.com/ont/wd/', 'last Name', 'datatype', 'wd:Worker', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('wd:employeeId', 'http://example.com/ont/wd/', 'employee Id', 'datatype', 'wd:Worker', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('wd:gender', 'http://example.com/ont/wd/', 'gender', 'datatype', 'wd:Worker', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('wd:jobFamily', 'http://example.com/ont/wd/', 'job Family', 'datatype', 'wd:Worker', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('wd:jobLevel', 'http://example.com/ont/wd/', 'job Level', 'datatype', 'wd:Worker', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('wd:workerType', 'http://example.com/ont/wd/', 'worker Type', 'datatype', 'wd:Worker', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('wd:activeStatus', 'http://example.com/ont/wd/', 'active Status', 'datatype', 'wd:Worker', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('wd:hireDate', 'http://example.com/ont/wd/', 'hire Date', 'datatype', 'wd:Worker', NULL, 'xsd:date', NULL, 0, 1, NULL),
         ('wd:annualSalary', 'http://example.com/ont/wd/', 'annual Salary', 'datatype', 'wd:Worker', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('wd:costCenter', 'http://example.com/ont/wd/', 'cost Center', 'datatype', 'wd:Worker', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('wd:organizationCode', 'http://example.com/ont/wd/', 'organization Code', 'datatype', 'wd:Organization', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('wd:organizationType', 'http://example.com/ont/wd/', 'organization Type', 'datatype', 'wd:Organization', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('wd:organizationSubtype', 'http://example.com/ont/wd/', 'organization Subtype', 'datatype', 'wd:Organization', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('wd:jobCode', 'http://example.com/ont/wd/', 'job Code', 'datatype', 'wd:JobProfile', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('wd:managementLevel', 'http://example.com/ont/wd/', 'management Level', 'datatype', 'wd:JobProfile', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('wd:basePayAmount', 'http://example.com/ont/wd/', 'base Pay Amount', 'datatype', 'wd:Compensation', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('wd:totalCompensation', 'http://example.com/ont/wd/', 'total Compensation', 'datatype', 'wd:Compensation', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('wd:compensationGrade', 'http://example.com/ont/wd/', 'compensation Grade', 'datatype', 'wd:Compensation', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('wd:compaRatio', 'http://example.com/ont/wd/', 'compa Ratio', 'datatype', 'wd:Compensation', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('wd:effectiveDate', 'http://example.com/ont/wd/', 'effective Date', 'datatype', 'wd:Compensation', NULL, 'xsd:date', NULL, 0, 1, NULL),
         ('wd:forWorker', 'http://example.com/ont/wd/', 'for Worker', 'object', 'wd:Compensation', 'wd:Worker', NULL, NULL, 0, 1, NULL),
         ('wd:startDate', 'http://example.com/ont/wd/', 'start Date', 'datatype', 'wd:TimeOff', NULL, 'xsd:date', NULL, 0, 1, NULL),
         ('wd:endDate', 'http://example.com/ont/wd/', 'end Date', 'datatype', 'wd:TimeOff', NULL, 'xsd:date', NULL, 0, 1, NULL),
         ('wd:totalDays', 'http://example.com/ont/wd/', 'total Days', 'datatype', 'wd:TimeOff', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('wd:status', 'http://example.com/ont/wd/', 'status', 'datatype', 'wd:TimeOff', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('wd:benefitPlanType', 'http://example.com/ont/wd/', 'benefit Plan Type', 'datatype', 'wd:BenefitElection', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('wd:coverageLevel', 'http://example.com/ont/wd/', 'coverage Level', 'datatype', 'wd:BenefitElection', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('wd:employeeCost', 'http://example.com/ont/wd/', 'employee Cost', 'datatype', 'wd:BenefitElection', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('wd:employerCost', 'http://example.com/ont/wd/', 'employer Cost', 'datatype', 'wd:BenefitElection', NULL, 'xsd:decimal', NULL, 0, 1, NULL)
       ) s ON t.property_iri = s.property_iri
WHEN NOT MATCHED THEN INSERT VALUES
    (s.property_iri, s.namespace_iri, s.label, s.kind, s.domain_class_iri,
     s.range_class_iri, s.range_datatype, s.range_domain_iri,
     s.min_count::INTEGER, s.max_count::INTEGER, s.sub_property_of);

-- 3. Shapes
MERGE INTO shape AS t
USING (SELECT column1 AS shape_iri, column2 AS target_class_iri, column3 AS label
       FROM VALUES
         ('wd:WorkerShape', 'wd:Worker', 'Worker data-quality contract'),
         ('wd:OrganizationShape', 'wd:Organization', 'Organization data-quality contract'),
         ('wd:JobProfileShape', 'wd:JobProfile', 'Job Profile data-quality contract'),
         ('wd:CompensationShape', 'wd:Compensation', 'Compensation data-quality contract'),
         ('wd:TimeOffShape', 'wd:TimeOff', 'Time Off data-quality contract'),
         ('wd:BenefitElectionShape', 'wd:BenefitElection', 'Benefit Election data-quality contract')
       ) s ON t.shape_iri = s.shape_iri
WHEN NOT MATCHED THEN INSERT VALUES (s.shape_iri, s.target_class_iri, s.label);

-- 4. Constraints
MERGE INTO constraint AS t
USING (SELECT column1 AS constraint_id, column2 AS shape_iri, column3 AS kind,
              column4 AS property_iri, column5 AS body
       FROM VALUES
         ('workday-c01', 'wd:WorkerShape', 'minCount', 'schema:name', '1'),
         ('workday-c02', 'wd:OrganizationShape', 'minCount', 'schema:name', '1'),
         ('workday-c03', 'wd:JobProfileShape', 'minCount', 'schema:name', '1'),
         ('workday-c04', 'wd:CompensationShape', 'minCount', 'schema:name', '1'),
         ('workday-c05', 'wd:TimeOffShape', 'minCount', 'schema:name', '1'),
         ('workday-c06', 'wd:BenefitElectionShape', 'minCount', 'schema:name', '1')
       ) s ON t.constraint_id = s.constraint_id
WHEN NOT MATCHED THEN INSERT VALUES
    (s.constraint_id, s.shape_iri, s.kind, s.property_iri, s.body);

SELECT 'WORKDAY ontology (TBox) loaded' AS status,
       (SELECT COUNT(*) FROM class WHERE namespace_iri = 'http://example.com/ont/wd/')    AS classes,
       (SELECT COUNT(*) FROM property WHERE namespace_iri = 'http://example.com/ont/wd/') AS properties;
