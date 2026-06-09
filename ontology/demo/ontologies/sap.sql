-- ============================================================================
-- SAP ontology (TBox) — generated from mappings/sap.py
-- ============================================================================
-- Do not edit by hand. Regenerate with: python tools/generate_tbox.py
-- Mirrors ontologies/sap.ttl. Loads namespace/class/property/
-- shape/constraint into the shared SILVER TBox. The matching ABox comes from:
--     python tools/generate_ontology_data.py --system sap
--     snow sql -D "SYSTEM=sap" -f 02b_load_source_ontology.sql
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
       FROM VALUES ('http://example.com/ont/sap/', 'sap', 'SAP source-system ontology')) s
ON t.namespace_iri = s.namespace_iri
WHEN NOT MATCHED THEN INSERT VALUES (s.namespace_iri, s.prefix, s.description);

-- 1. Classes
MERGE INTO class AS t
USING (SELECT column1 AS class_iri, column2 AS namespace_iri, column3 AS label,
              column4 AS definition, column5 AS sub_class_of
       FROM VALUES
         ('sap:Customer', 'http://example.com/ont/sap/', 'Customer', 'SAP KNA1', 'schema:Organization'),
         ('sap:Material', 'http://example.com/ont/sap/', 'Material', 'SAP MARA', 'schema:Thing'),
         ('sap:SalesOrder', 'http://example.com/ont/sap/', 'Sales Order', 'SAP VBAK', 'schema:Thing'),
         ('sap:SalesOrderItem', 'http://example.com/ont/sap/', 'Sales Order Item', 'SAP VBAP', 'schema:Thing'),
         ('sap:Vendor', 'http://example.com/ont/sap/', 'Vendor', 'SAP LFA1', 'schema:Organization'),
         ('sap:PurchaseOrder', 'http://example.com/ont/sap/', 'Purchase Order', 'SAP EKKO', 'schema:Thing'),
         ('sap:AccountingDocument', 'http://example.com/ont/sap/', 'Accounting Document', 'SAP BKPF', 'schema:Thing'),
         ('sap:Employee', 'http://example.com/ont/sap/', 'Employee', 'SAP PA0001', 'schema:Person')
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
         ('sap:country', 'http://example.com/ont/sap/', 'country', 'datatype', 'sap:Customer', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sap:accountGroup', 'http://example.com/ont/sap/', 'account Group', 'datatype', 'sap:Customer', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sap:industryKey', 'http://example.com/ont/sap/', 'industry Key', 'datatype', 'sap:Customer', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sap:vatNumber', 'http://example.com/ont/sap/', 'vat Number', 'datatype', 'sap:Customer', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sap:materialType', 'http://example.com/ont/sap/', 'material Type', 'datatype', 'sap:Material', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sap:materialGroup', 'http://example.com/ont/sap/', 'material Group', 'datatype', 'sap:Material', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sap:baseUnit', 'http://example.com/ont/sap/', 'base Unit', 'datatype', 'sap:Material', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sap:grossWeight', 'http://example.com/ont/sap/', 'gross Weight', 'datatype', 'sap:Material', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('sap:netWeight', 'http://example.com/ont/sap/', 'net Weight', 'datatype', 'sap:Material', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('sap:orderType', 'http://example.com/ont/sap/', 'order Type', 'datatype', 'sap:SalesOrder', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sap:documentDate', 'http://example.com/ont/sap/', 'document Date', 'datatype', 'sap:SalesOrder', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sap:netValue', 'http://example.com/ont/sap/', 'net Value', 'datatype', 'sap:SalesOrder', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('sap:currency', 'http://example.com/ont/sap/', 'currency', 'datatype', 'sap:SalesOrder', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sap:overallStatus', 'http://example.com/ont/sap/', 'overall Status', 'datatype', 'sap:SalesOrder', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sap:soldToParty', 'http://example.com/ont/sap/', 'sold To Party', 'object', 'sap:SalesOrder', 'sap:Customer', NULL, NULL, 0, 1, NULL),
         ('sap:quantity', 'http://example.com/ont/sap/', 'quantity', 'datatype', 'sap:SalesOrderItem', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('sap:netPrice', 'http://example.com/ont/sap/', 'net Price', 'datatype', 'sap:SalesOrderItem', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('sap:partOfOrder', 'http://example.com/ont/sap/', 'part Of Order', 'object', 'sap:SalesOrderItem', 'sap:SalesOrder', NULL, NULL, 0, 1, NULL),
         ('sap:refersToMaterial', 'http://example.com/ont/sap/', 'refers To Material', 'object', 'sap:SalesOrderItem', 'sap:Material', NULL, NULL, 0, 1, NULL),
         ('sap:documentType', 'http://example.com/ont/sap/', 'document Type', 'datatype', 'sap:PurchaseOrder', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sap:totalValue', 'http://example.com/ont/sap/', 'total Value', 'datatype', 'sap:PurchaseOrder', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('sap:vendorParty', 'http://example.com/ont/sap/', 'vendor Party', 'object', 'sap:PurchaseOrder', 'sap:Vendor', NULL, NULL, 0, 1, NULL),
         ('sap:postingDate', 'http://example.com/ont/sap/', 'posting Date', 'datatype', 'sap:AccountingDocument', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sap:fiscalYear', 'http://example.com/ont/sap/', 'fiscal Year', 'datatype', 'sap:AccountingDocument', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sap:companyCode', 'http://example.com/ont/sap/', 'company Code', 'datatype', 'sap:Employee', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sap:plant', 'http://example.com/ont/sap/', 'plant', 'datatype', 'sap:Employee', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sap:costCenter', 'http://example.com/ont/sap/', 'cost Center', 'datatype', 'sap:Employee', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sap:orgUnit', 'http://example.com/ont/sap/', 'org Unit', 'datatype', 'sap:Employee', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sap:firstName', 'http://example.com/ont/sap/', 'first Name', 'datatype', 'sap:Employee', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sap:lastName', 'http://example.com/ont/sap/', 'last Name', 'datatype', 'sap:Employee', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sap:birthDate', 'http://example.com/ont/sap/', 'birth Date', 'datatype', 'sap:Employee', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('sap:nationality', 'http://example.com/ont/sap/', 'nationality', 'datatype', 'sap:Employee', NULL, 'xsd:string', NULL, 0, 1, NULL)
       ) s ON t.property_iri = s.property_iri
WHEN NOT MATCHED THEN INSERT VALUES
    (s.property_iri, s.namespace_iri, s.label, s.kind, s.domain_class_iri,
     s.range_class_iri, s.range_datatype, s.range_domain_iri,
     s.min_count::INTEGER, s.max_count::INTEGER, s.sub_property_of);

-- 3. Shapes
MERGE INTO shape AS t
USING (SELECT column1 AS shape_iri, column2 AS target_class_iri, column3 AS label
       FROM VALUES
         ('sap:CustomerShape', 'sap:Customer', 'Customer data-quality contract'),
         ('sap:MaterialShape', 'sap:Material', 'Material data-quality contract'),
         ('sap:SalesOrderShape', 'sap:SalesOrder', 'Sales Order data-quality contract'),
         ('sap:SalesOrderItemShape', 'sap:SalesOrderItem', 'Sales Order Item data-quality contract'),
         ('sap:VendorShape', 'sap:Vendor', 'Vendor data-quality contract'),
         ('sap:PurchaseOrderShape', 'sap:PurchaseOrder', 'Purchase Order data-quality contract'),
         ('sap:AccountingDocumentShape', 'sap:AccountingDocument', 'Accounting Document data-quality contract'),
         ('sap:EmployeeShape', 'sap:Employee', 'Employee data-quality contract')
       ) s ON t.shape_iri = s.shape_iri
WHEN NOT MATCHED THEN INSERT VALUES (s.shape_iri, s.target_class_iri, s.label);

-- 4. Constraints
MERGE INTO constraint AS t
USING (SELECT column1 AS constraint_id, column2 AS shape_iri, column3 AS kind,
              column4 AS property_iri, column5 AS body
       FROM VALUES
         ('sap-c01', 'sap:CustomerShape', 'minCount', 'schema:name', '1'),
         ('sap-c02', 'sap:MaterialShape', 'minCount', 'schema:name', '1'),
         ('sap-c03', 'sap:SalesOrderItemShape', 'minCount', 'schema:name', '1'),
         ('sap-c04', 'sap:VendorShape', 'minCount', 'schema:name', '1'),
         ('sap-c05', 'sap:AccountingDocumentShape', 'minCount', 'schema:name', '1')
       ) s ON t.constraint_id = s.constraint_id
WHEN NOT MATCHED THEN INSERT VALUES
    (s.constraint_id, s.shape_iri, s.kind, s.property_iri, s.body);

SELECT 'SAP ontology (TBox) loaded' AS status,
       (SELECT COUNT(*) FROM class WHERE namespace_iri = 'http://example.com/ont/sap/')    AS classes,
       (SELECT COUNT(*) FROM property WHERE namespace_iri = 'http://example.com/ont/sap/') AS properties;
