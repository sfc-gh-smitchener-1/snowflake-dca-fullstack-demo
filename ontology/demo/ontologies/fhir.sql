-- ============================================================================
-- FHIR ontology (TBox) — generated from mappings/fhir.py
-- ============================================================================
-- Do not edit by hand. Regenerate with: python tools/generate_tbox.py
-- Mirrors ontologies/fhir.ttl. Loads namespace/class/property/
-- shape/constraint into the shared SILVER TBox. The matching ABox comes from:
--     python tools/generate_ontology_data.py --system fhir
--     snow sql -D "SYSTEM=fhir" -f 02b_load_source_ontology.sql
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
       FROM VALUES ('http://example.com/ont/fhir/', 'fhir', 'FHIR source-system ontology')) s
ON t.namespace_iri = s.namespace_iri
WHEN NOT MATCHED THEN INSERT VALUES (s.namespace_iri, s.prefix, s.description);

-- 1. Classes
MERGE INTO class AS t
USING (SELECT column1 AS class_iri, column2 AS namespace_iri, column3 AS label,
              column4 AS definition, column5 AS sub_class_of
       FROM VALUES
         ('fhir:Patient', 'http://example.com/ont/fhir/', 'Patient', 'FHIR Patient', 'schema:Person'),
         ('fhir:Practitioner', 'http://example.com/ont/fhir/', 'Practitioner', 'FHIR Practitioner', 'schema:Person'),
         ('fhir:Organization', 'http://example.com/ont/fhir/', 'Organization', 'FHIR Organization', 'schema:Organization'),
         ('fhir:Encounter', 'http://example.com/ont/fhir/', 'Encounter', 'FHIR Encounter', 'schema:Thing'),
         ('fhir:Condition', 'http://example.com/ont/fhir/', 'Condition', 'FHIR Condition', 'schema:Thing'),
         ('fhir:Observation', 'http://example.com/ont/fhir/', 'Observation', 'FHIR Observation', 'schema:Thing'),
         ('fhir:MedicationRequest', 'http://example.com/ont/fhir/', 'Medication Request', 'FHIR MedicationRequest', 'schema:Thing'),
         ('fhir:Procedure', 'http://example.com/ont/fhir/', 'Procedure', 'FHIR Procedure', 'schema:Thing'),
         ('fhir:Claim', 'http://example.com/ont/fhir/', 'Claim', 'FHIR Claim', 'schema:Thing')
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
         ('fhir:mrn', 'http://example.com/ont/fhir/', 'mrn', 'datatype', 'fhir:Patient', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('fhir:gender', 'http://example.com/ont/fhir/', 'gender', 'datatype', 'fhir:Patient', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('fhir:birthDate', 'http://example.com/ont/fhir/', 'birth Date', 'datatype', 'fhir:Patient', NULL, 'xsd:date', NULL, 0, 1, NULL),
         ('fhir:npi', 'http://example.com/ont/fhir/', 'npi', 'datatype', 'fhir:Practitioner', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('fhir:specialty', 'http://example.com/ont/fhir/', 'specialty', 'datatype', 'fhir:Practitioner', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('fhir:organizationType', 'http://example.com/ont/fhir/', 'organization Type', 'datatype', 'fhir:Organization', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('fhir:status', 'http://example.com/ont/fhir/', 'status', 'datatype', 'fhir:Encounter', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('fhir:encounterClass', 'http://example.com/ont/fhir/', 'encounter Class', 'datatype', 'fhir:Encounter', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('fhir:subject', 'http://example.com/ont/fhir/', 'subject', 'object', 'fhir:Encounter', 'fhir:Patient', NULL, NULL, 0, 1, NULL),
         ('fhir:icd10Code', 'http://example.com/ont/fhir/', 'icd10 Code', 'datatype', 'fhir:Condition', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('fhir:clinicalStatus', 'http://example.com/ont/fhir/', 'clinical Status', 'datatype', 'fhir:Condition', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('fhir:severity', 'http://example.com/ont/fhir/', 'severity', 'datatype', 'fhir:Condition', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('fhir:onsetDate', 'http://example.com/ont/fhir/', 'onset Date', 'datatype', 'fhir:Condition', NULL, 'xsd:date', NULL, 0, 1, NULL),
         ('fhir:partOfEncounter', 'http://example.com/ont/fhir/', 'part Of Encounter', 'object', 'fhir:Condition', 'fhir:Encounter', NULL, NULL, 0, 1, NULL),
         ('fhir:loincCode', 'http://example.com/ont/fhir/', 'loinc Code', 'datatype', 'fhir:Observation', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('fhir:value', 'http://example.com/ont/fhir/', 'value', 'datatype', 'fhir:Observation', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('fhir:unit', 'http://example.com/ont/fhir/', 'unit', 'datatype', 'fhir:Observation', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('fhir:rxNormCode', 'http://example.com/ont/fhir/', 'rx Norm Code', 'datatype', 'fhir:MedicationRequest', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('fhir:intent', 'http://example.com/ont/fhir/', 'intent', 'datatype', 'fhir:MedicationRequest', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('fhir:requester', 'http://example.com/ont/fhir/', 'requester', 'object', 'fhir:MedicationRequest', 'fhir:Practitioner', NULL, NULL, 0, 1, NULL),
         ('fhir:snomedCode', 'http://example.com/ont/fhir/', 'snomed Code', 'datatype', 'fhir:Procedure', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('fhir:performedDate', 'http://example.com/ont/fhir/', 'performed Date', 'datatype', 'fhir:Procedure', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('fhir:claimType', 'http://example.com/ont/fhir/', 'claim Type', 'datatype', 'fhir:Claim', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('fhir:use', 'http://example.com/ont/fhir/', 'use', 'datatype', 'fhir:Claim', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('fhir:totalValue', 'http://example.com/ont/fhir/', 'total Value', 'datatype', 'fhir:Claim', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('fhir:createdDate', 'http://example.com/ont/fhir/', 'created Date', 'datatype', 'fhir:Claim', NULL, 'xsd:date', NULL, 0, 1, NULL),
         ('fhir:provider', 'http://example.com/ont/fhir/', 'provider', 'object', 'fhir:Claim', 'fhir:Organization', NULL, NULL, 0, 1, NULL)
       ) s ON t.property_iri = s.property_iri
WHEN NOT MATCHED THEN INSERT VALUES
    (s.property_iri, s.namespace_iri, s.label, s.kind, s.domain_class_iri,
     s.range_class_iri, s.range_datatype, s.range_domain_iri,
     s.min_count::INTEGER, s.max_count::INTEGER, s.sub_property_of);

-- 3. Shapes
MERGE INTO shape AS t
USING (SELECT column1 AS shape_iri, column2 AS target_class_iri, column3 AS label
       FROM VALUES
         ('fhir:PatientShape', 'fhir:Patient', 'Patient data-quality contract'),
         ('fhir:PractitionerShape', 'fhir:Practitioner', 'Practitioner data-quality contract'),
         ('fhir:OrganizationShape', 'fhir:Organization', 'Organization data-quality contract'),
         ('fhir:EncounterShape', 'fhir:Encounter', 'Encounter data-quality contract'),
         ('fhir:ConditionShape', 'fhir:Condition', 'Condition data-quality contract'),
         ('fhir:ObservationShape', 'fhir:Observation', 'Observation data-quality contract'),
         ('fhir:MedicationRequestShape', 'fhir:MedicationRequest', 'Medication Request data-quality contract'),
         ('fhir:ProcedureShape', 'fhir:Procedure', 'Procedure data-quality contract'),
         ('fhir:ClaimShape', 'fhir:Claim', 'Claim data-quality contract')
       ) s ON t.shape_iri = s.shape_iri
WHEN NOT MATCHED THEN INSERT VALUES (s.shape_iri, s.target_class_iri, s.label);

-- 4. Constraints
MERGE INTO constraint AS t
USING (SELECT column1 AS constraint_id, column2 AS shape_iri, column3 AS kind,
              column4 AS property_iri, column5 AS body
       FROM VALUES
         ('fhir-c01', 'fhir:PatientShape', 'minCount', 'schema:name', '1'),
         ('fhir-c02', 'fhir:PractitionerShape', 'minCount', 'schema:name', '1'),
         ('fhir-c03', 'fhir:OrganizationShape', 'minCount', 'schema:name', '1'),
         ('fhir-c04', 'fhir:EncounterShape', 'minCount', 'schema:name', '1'),
         ('fhir-c05', 'fhir:ConditionShape', 'minCount', 'schema:name', '1'),
         ('fhir-c06', 'fhir:ObservationShape', 'minCount', 'schema:name', '1'),
         ('fhir-c07', 'fhir:MedicationRequestShape', 'minCount', 'schema:name', '1'),
         ('fhir-c08', 'fhir:ProcedureShape', 'minCount', 'schema:name', '1')
       ) s ON t.constraint_id = s.constraint_id
WHEN NOT MATCHED THEN INSERT VALUES
    (s.constraint_id, s.shape_iri, s.kind, s.property_iri, s.body);

SELECT 'FHIR ontology (TBox) loaded' AS status,
       (SELECT COUNT(*) FROM class WHERE namespace_iri = 'http://example.com/ont/fhir/')    AS classes,
       (SELECT COUNT(*) FROM property WHERE namespace_iri = 'http://example.com/ont/fhir/') AS properties;
