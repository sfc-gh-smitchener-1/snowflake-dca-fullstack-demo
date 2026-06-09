-- ============================================================================
-- ORACLE ontology (TBox) — generated from mappings/oracle.py
-- ============================================================================
-- Do not edit by hand. Regenerate with: python tools/generate_tbox.py
-- Mirrors ontologies/oracle.ttl. Loads namespace/class/property/
-- shape/constraint into the shared SILVER TBox. The matching ABox comes from:
--     python tools/generate_ontology_data.py --system oracle
--     snow sql -D "SYSTEM=oracle" -f 02b_load_source_ontology.sql
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
       FROM VALUES ('http://example.com/ont/ora/', 'ora', 'ORACLE source-system ontology')) s
ON t.namespace_iri = s.namespace_iri
WHEN NOT MATCHED THEN INSERT VALUES (s.namespace_iri, s.prefix, s.description);

-- 1. Classes
MERGE INTO class AS t
USING (SELECT column1 AS class_iri, column2 AS namespace_iri, column3 AS label,
              column4 AS definition, column5 AS sub_class_of
       FROM VALUES
         ('ora:Party', 'http://example.com/ont/ora/', 'Party', 'ORACLE HZ_PARTIES', 'schema:Organization'),
         ('ora:Supplier', 'http://example.com/ont/ora/', 'Supplier', 'ORACLE AP_SUPPLIERS', 'schema:Organization'),
         ('ora:InventoryItem', 'http://example.com/ont/ora/', 'Inventory Item', 'ORACLE MTL_SYSTEM_ITEMS_B', 'schema:Thing'),
         ('ora:SalesOrder', 'http://example.com/ont/ora/', 'Sales Order', 'ORACLE OE_ORDER_HEADERS_ALL', 'schema:Thing'),
         ('ora:SalesOrderLine', 'http://example.com/ont/ora/', 'Sales Order Line', 'ORACLE OE_ORDER_LINES_ALL', 'schema:Thing'),
         ('ora:PayablesInvoice', 'http://example.com/ont/ora/', 'Payables Invoice', 'ORACLE AP_INVOICES_ALL', 'schema:Thing'),
         ('ora:ReceivablesInvoice', 'http://example.com/ont/ora/', 'Receivables Invoice', 'ORACLE RA_CUSTOMER_TRX_ALL', 'schema:Thing'),
         ('ora:JournalLine', 'http://example.com/ont/ora/', 'Journal Line', 'ORACLE GL_JE_LINES', 'schema:Thing')
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
         ('ora:partyType', 'http://example.com/ont/ora/', 'party Type', 'datatype', 'ora:Party', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('ora:status', 'http://example.com/ont/ora/', 'status', 'datatype', 'ora:Party', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('ora:categoryCode', 'http://example.com/ont/ora/', 'category Code', 'datatype', 'ora:Party', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('ora:dunsNumber', 'http://example.com/ont/ora/', 'duns Number', 'datatype', 'ora:Party', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('ora:vendorNumber', 'http://example.com/ont/ora/', 'vendor Number', 'datatype', 'ora:Supplier', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('ora:vendorType', 'http://example.com/ont/ora/', 'vendor Type', 'datatype', 'ora:Supplier', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('ora:enabledFlag', 'http://example.com/ont/ora/', 'enabled Flag', 'datatype', 'ora:Supplier', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('ora:paymentMethod', 'http://example.com/ont/ora/', 'payment Method', 'datatype', 'ora:Supplier', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('ora:itemNumber', 'http://example.com/ont/ora/', 'item Number', 'datatype', 'ora:InventoryItem', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('ora:itemType', 'http://example.com/ont/ora/', 'item Type', 'datatype', 'ora:InventoryItem', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('ora:primaryUom', 'http://example.com/ont/ora/', 'primary Uom', 'datatype', 'ora:InventoryItem', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('ora:listPrice', 'http://example.com/ont/ora/', 'list Price', 'datatype', 'ora:InventoryItem', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('ora:unitWeight', 'http://example.com/ont/ora/', 'unit Weight', 'datatype', 'ora:InventoryItem', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('ora:orderNumber', 'http://example.com/ont/ora/', 'order Number', 'datatype', 'ora:SalesOrder', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('ora:orderedDate', 'http://example.com/ont/ora/', 'ordered Date', 'datatype', 'ora:SalesOrder', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('ora:flowStatus', 'http://example.com/ont/ora/', 'flow Status', 'datatype', 'ora:SalesOrder', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('ora:currency', 'http://example.com/ont/ora/', 'currency', 'datatype', 'ora:SalesOrder', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('ora:bookedFlag', 'http://example.com/ont/ora/', 'booked Flag', 'datatype', 'ora:SalesOrder', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('ora:soldToParty', 'http://example.com/ont/ora/', 'sold To Party', 'object', 'ora:SalesOrder', 'ora:Party', NULL, NULL, 0, 1, NULL),
         ('ora:orderedQuantity', 'http://example.com/ont/ora/', 'ordered Quantity', 'datatype', 'ora:SalesOrderLine', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('ora:uom', 'http://example.com/ont/ora/', 'uom', 'datatype', 'ora:SalesOrderLine', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('ora:unitSellingPrice', 'http://example.com/ont/ora/', 'unit Selling Price', 'datatype', 'ora:SalesOrderLine', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('ora:partOfOrder', 'http://example.com/ont/ora/', 'part Of Order', 'object', 'ora:SalesOrderLine', 'ora:SalesOrder', NULL, NULL, 0, 1, NULL),
         ('ora:invoiceNumber', 'http://example.com/ont/ora/', 'invoice Number', 'datatype', 'ora:PayablesInvoice', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('ora:invoiceDate', 'http://example.com/ont/ora/', 'invoice Date', 'datatype', 'ora:PayablesInvoice', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('ora:invoiceAmount', 'http://example.com/ont/ora/', 'invoice Amount', 'datatype', 'ora:PayablesInvoice', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('ora:approvalStatus', 'http://example.com/ont/ora/', 'approval Status', 'datatype', 'ora:PayablesInvoice', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('ora:billedBySupplier', 'http://example.com/ont/ora/', 'billed By Supplier', 'object', 'ora:PayablesInvoice', 'ora:Supplier', NULL, NULL, 0, 1, NULL),
         ('ora:billedToParty', 'http://example.com/ont/ora/', 'billed To Party', 'object', 'ora:ReceivablesInvoice', 'ora:Party', NULL, NULL, 0, 1, NULL),
         ('ora:periodName', 'http://example.com/ont/ora/', 'period Name', 'datatype', 'ora:JournalLine', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('ora:effectiveDate', 'http://example.com/ont/ora/', 'effective Date', 'datatype', 'ora:JournalLine', NULL, 'xsd:string', NULL, 0, 1, NULL),
         ('ora:enteredDr', 'http://example.com/ont/ora/', 'entered Dr', 'datatype', 'ora:JournalLine', NULL, 'xsd:decimal', NULL, 0, 1, NULL),
         ('ora:enteredCr', 'http://example.com/ont/ora/', 'entered Cr', 'datatype', 'ora:JournalLine', NULL, 'xsd:decimal', NULL, 0, 1, NULL)
       ) s ON t.property_iri = s.property_iri
WHEN NOT MATCHED THEN INSERT VALUES
    (s.property_iri, s.namespace_iri, s.label, s.kind, s.domain_class_iri,
     s.range_class_iri, s.range_datatype, s.range_domain_iri,
     s.min_count::INTEGER, s.max_count::INTEGER, s.sub_property_of);

-- 3. Shapes
MERGE INTO shape AS t
USING (SELECT column1 AS shape_iri, column2 AS target_class_iri, column3 AS label
       FROM VALUES
         ('ora:PartyShape', 'ora:Party', 'Party data-quality contract'),
         ('ora:SupplierShape', 'ora:Supplier', 'Supplier data-quality contract'),
         ('ora:InventoryItemShape', 'ora:InventoryItem', 'Inventory Item data-quality contract'),
         ('ora:SalesOrderShape', 'ora:SalesOrder', 'Sales Order data-quality contract'),
         ('ora:SalesOrderLineShape', 'ora:SalesOrderLine', 'Sales Order Line data-quality contract'),
         ('ora:PayablesInvoiceShape', 'ora:PayablesInvoice', 'Payables Invoice data-quality contract'),
         ('ora:ReceivablesInvoiceShape', 'ora:ReceivablesInvoice', 'Receivables Invoice data-quality contract'),
         ('ora:JournalLineShape', 'ora:JournalLine', 'Journal Line data-quality contract')
       ) s ON t.shape_iri = s.shape_iri
WHEN NOT MATCHED THEN INSERT VALUES (s.shape_iri, s.target_class_iri, s.label);

-- 4. Constraints
MERGE INTO constraint AS t
USING (SELECT column1 AS constraint_id, column2 AS shape_iri, column3 AS kind,
              column4 AS property_iri, column5 AS body
       FROM VALUES
         ('oracle-c01', 'ora:PartyShape', 'minCount', 'schema:name', '1'),
         ('oracle-c02', 'ora:SupplierShape', 'minCount', 'schema:name', '1'),
         ('oracle-c03', 'ora:InventoryItemShape', 'minCount', 'schema:name', '1'),
         ('oracle-c04', 'ora:SalesOrderLineShape', 'minCount', 'schema:name', '1'),
         ('oracle-c05', 'ora:JournalLineShape', 'minCount', 'schema:name', '1')
       ) s ON t.constraint_id = s.constraint_id
WHEN NOT MATCHED THEN INSERT VALUES
    (s.constraint_id, s.shape_iri, s.kind, s.property_iri, s.body);

SELECT 'ORACLE ontology (TBox) loaded' AS status,
       (SELECT COUNT(*) FROM class WHERE namespace_iri = 'http://example.com/ont/ora/')    AS classes,
       (SELECT COUNT(*) FROM property WHERE namespace_iri = 'http://example.com/ont/ora/') AS properties;
