-- ============================================================================
-- CPG industry ontology (TBox) — optional vertical
-- ============================================================================
-- The demo's canonical data now comes from the six enterprise source systems
-- (see ontologies/<system>.sql + tools/generate_ontology_data.py). The CPG
-- vertical is retained as an OPTIONAL example ontology (mirrors
-- ontologies/cpg.ttl): it shows how to layer a rich industry taxonomy on top of
-- the same substrate. Only the TBox is loaded here — the rudimentary CPG data
-- generator has been removed in favour of the multi-source adapter.
--
-- Prereqs: 01_setup_database.sql, 02_load_synthetic_data.sql. Idempotent.
-- ============================================================================

USE ROLE      ONT_DEMO_BUILDER_ROLE;
USE DATABASE  ONT_DEMO;
USE SCHEMA    SILVER;
USE WAREHOUSE ONT_DEMO_INGEST_WH;

MERGE INTO namespace AS t
USING (
    SELECT * FROM VALUES
        ('http://example.com/ont/cpg/', 'cpg', 'Generic CPG industry ontology'),
        ('http://gs1.org/voc/',          'gs1', 'GS1 Web Vocabulary (referenced; not loaded)')
    AS s(namespace_iri, prefix, description)
) AS s ON t.namespace_iri = s.namespace_iri
WHEN NOT MATCHED THEN INSERT VALUES (s.namespace_iri, s.prefix, s.description);

MERGE INTO class AS t
USING (
    SELECT * FROM VALUES
      ('cpg:Manufacturer',        'http://example.com/ont/cpg/', 'Manufacturer',        'Org that makes products',           'schema:Organization'),
      ('cpg:Retailer',            'http://example.com/ont/cpg/', 'Retailer',            'Org that sells to consumers',       'schema:Organization'),
      ('cpg:Wholesaler',          'http://example.com/ont/cpg/', 'Wholesaler',          'Org that sells to retailers',       'schema:Organization'),
      ('cpg:Brand',               'http://example.com/ont/cpg/', 'Brand',               'Consumer-facing brand identity',    'schema:Thing'),
      ('cpg:Product',             'http://example.com/ont/cpg/', 'CPG Product',         'A consumable / household SKU',      'ex:Product'),
      ('cpg:Beverage',            'http://example.com/ont/cpg/', 'Beverage',            NULL,                                 'cpg:Product'),
      ('cpg:Snack',               'http://example.com/ont/cpg/', 'Snack',               NULL,                                 'cpg:Product'),
      ('cpg:DairyItem',           'http://example.com/ont/cpg/', 'Dairy item',          NULL,                                 'cpg:Product'),
      ('cpg:Condiment',           'http://example.com/ont/cpg/', 'Condiment',           NULL,                                 'cpg:Product'),
      ('cpg:FrozenItem',          'http://example.com/ont/cpg/', 'Frozen item',         NULL,                                 'cpg:Product'),
      ('cpg:PantryItem',          'http://example.com/ont/cpg/', 'Pantry item',         NULL,                                 'cpg:Product'),
      ('cpg:PersonalCare',        'http://example.com/ont/cpg/', 'Personal care item',  NULL,                                 'cpg:Product'),
      ('cpg:HouseholdItem',       'http://example.com/ont/cpg/', 'Household item',      NULL,                                 'cpg:Product'),
      ('cpg:CategoryNode',        'http://example.com/ont/cpg/', 'Category node',       'A node in any product taxonomy',    'schema:Thing'),
      ('cpg:GpcSegment',          'http://example.com/ont/cpg/', 'GPC segment',         NULL,                                 'cpg:CategoryNode'),
      ('cpg:GpcFamily',           'http://example.com/ont/cpg/', 'GPC family',          NULL,                                 'cpg:CategoryNode'),
      ('cpg:GpcBrick',            'http://example.com/ont/cpg/', 'GPC brick',           NULL,                                 'cpg:CategoryNode'),
      ('cpg:Location',            'http://example.com/ont/cpg/', 'Location',            'A physical place',                   'schema:Thing'),
      ('cpg:RetailStore',         'http://example.com/ont/cpg/', 'Retail store',        NULL,                                 'cpg:Location'),
      ('cpg:DistributionCenter',  'http://example.com/ont/cpg/', 'Distribution center', NULL,                                 'cpg:Location'),
      ('cpg:ManufacturingPlant',  'http://example.com/ont/cpg/', 'Manufacturing plant', NULL,                                 'cpg:Location'),
      ('cpg:WholesaleWarehouse',  'http://example.com/ont/cpg/', 'Wholesale warehouse', NULL,                                 'cpg:Location'),
      ('cpg:Allergen',            'http://example.com/ont/cpg/', 'Allergen',            'FALCPA major allergen code',         'schema:Thing'),
      ('cpg:Claim',               'http://example.com/ont/cpg/', 'Claim',               'Regulated or marketing claim',       'schema:Thing')
    AS v(class_iri, namespace_iri, label, definition, sub_class_of)
) s ON t.class_iri = s.class_iri
WHEN NOT MATCHED THEN INSERT VALUES (s.class_iri, s.namespace_iri, s.label, s.definition, s.sub_class_of);

MERGE INTO property AS t
USING (
    SELECT column1::STRING AS property_iri, column2::STRING AS namespace_iri, column3::STRING AS label,
           column4::STRING AS kind,         column5::STRING AS domain_class_iri, column6::STRING AS range_class_iri,
           column7::STRING AS range_datatype, column8::STRING AS range_domain_iri,
           column9::INTEGER AS min_count,    column10::INTEGER AS max_count, NULL::STRING AS sub_property_of
    FROM VALUES
      ('cpg:gtin13',              'http://example.com/ont/cpg/', 'GTIN-13',              'datatype', 'cpg:Product',     NULL,                  'xsd:string', NULL, 1, 1),
      ('cpg:netContentG',         'http://example.com/ont/cpg/', 'Net content (g)',      'datatype', 'cpg:Product',     NULL,                  'xsd:decimal',NULL, 0, 1),
      ('cpg:countryOfOrigin',     'http://example.com/ont/cpg/', 'Country of origin',    'datatype', 'cpg:Product',     NULL,                  'xsd:string', NULL, 0, 1),
      ('cpg:gpcBrickCode',        'http://example.com/ont/cpg/', 'GPC brick code',       'datatype', 'cpg:GpcBrick',    NULL,                  'xsd:string', NULL, 1, 1),
      ('cpg:madeBy',              'http://example.com/ont/cpg/', 'made by',              'object',   'cpg:Product',     'cpg:Manufacturer',    NULL,         NULL, 1, 1),
      ('cpg:operatedByOrg',       'http://example.com/ont/cpg/', 'operated by',          'object',   'cpg:Brand',       'cpg:Manufacturer',    NULL,         NULL, 1, 1),
      ('cpg:belongsToBrand',      'http://example.com/ont/cpg/', 'belongs to brand',     'object',   'cpg:Product',     'cpg:Brand',           NULL,         NULL, 1, 1),
      ('cpg:belongsToCategory',   'http://example.com/ont/cpg/', 'belongs to category',  'object',   'cpg:Product',     'cpg:CategoryNode',    NULL,         NULL, 1, NULL),
      ('cpg:declaresAllergen',    'http://example.com/ont/cpg/', 'declares allergen',    'object',   'cpg:Product',     'cpg:Allergen',        NULL,         NULL, 0, NULL),
      ('cpg:hasClaim',            'http://example.com/ont/cpg/', 'has claim',            'object',   'cpg:Product',     'cpg:Claim',           NULL,         NULL, 0, NULL),
      ('cpg:soldAt',              'http://example.com/ont/cpg/', 'sold at retailer',     'object',   'cpg:Product',     'cpg:Retailer',        NULL,         NULL, 0, NULL),
      ('cpg:operatedByRetailer',  'http://example.com/ont/cpg/', 'operated by retailer', 'object',   'cpg:Location',    'cpg:Retailer',        NULL,         NULL, 0, 1),
      ('cpg:operatedByMfr',       'http://example.com/ont/cpg/', 'operated by mfr',      'object',   'cpg:Location',    'cpg:Manufacturer',    NULL,         NULL, 0, 1),
      ('cpg:operatedByWholesaler','http://example.com/ont/cpg/', 'operated by wholesaler','object',  'cpg:Location',    'cpg:Wholesaler',      NULL,         NULL, 0, 1),
      ('cpg:locatedAt',           'http://example.com/ont/cpg/', 'located at',           'object',   'cpg:Location',    'schema:PostalAddress',NULL,         NULL, 1, 1),
      ('cpg:parentCategory',      'http://example.com/ont/cpg/', 'parent category',      'object',   'cpg:CategoryNode','cpg:CategoryNode',    NULL,         NULL, 0, 1),
      ('schema:streetAddress',    'http://schema.org/',          'streetAddress',        'datatype', 'schema:PostalAddress', NULL,             'xsd:string', NULL, 0, 1),
      ('schema:postalCode',       'http://schema.org/',          'postalCode',           'datatype', 'schema:PostalAddress', NULL,             'xsd:string', NULL, 0, 1),
      ('schema:addressCountry',   'http://schema.org/',          'addressCountry',       'datatype', 'schema:PostalAddress', NULL,             'xsd:string', NULL, 0, 1)
) s ON t.property_iri = s.property_iri
WHEN NOT MATCHED THEN INSERT VALUES
    (s.property_iri, s.namespace_iri, s.label, s.kind, s.domain_class_iri,
     s.range_class_iri, s.range_datatype, s.range_domain_iri,
     s.min_count, s.max_count, s.sub_property_of);

MERGE INTO shape AS t
USING (
    SELECT * FROM VALUES
      ('cpg:ProductShape',      'cpg:Product',      'CPG product data-quality contract'),
      ('cpg:BrandShape',        'cpg:Brand',        'CPG brand contract'),
      ('cpg:RetailerShape',     'cpg:Retailer',     'Retailer contract'),
      ('cpg:WholesalerShape',   'cpg:Wholesaler',   'Wholesaler contract'),
      ('cpg:LocationShape',     'cpg:Location',     'Location contract'),
      ('cpg:ManufacturerShape', 'cpg:Manufacturer', 'Manufacturer contract'),
      ('cpg:GpcBrickShape',     'cpg:GpcBrick',     'GPC brick code contract')
    AS v(shape_iri, target_class_iri, label)
) s ON t.shape_iri = s.shape_iri
WHEN NOT MATCHED THEN INSERT VALUES (s.shape_iri, s.target_class_iri, s.label);

MERGE INTO constraint AS t
USING (
    SELECT * FROM VALUES
      ('cpg-c01', 'cpg:ProductShape',      'minCount', 'schema:name',         '1'),
      ('cpg-c02', 'cpg:ProductShape',      'minCount', 'cpg:gtin13',          '1'),
      ('cpg-c03', 'cpg:ProductShape',      'pattern',  'cpg:gtin13',          '^[0-9]{13}$'),
      ('cpg-c04', 'cpg:ProductShape',      'minCount', 'cpg:madeBy',          '1'),
      ('cpg-c05', 'cpg:ProductShape',      'minCount', 'cpg:belongsToBrand',  '1'),
      ('cpg-c06', 'cpg:ProductShape',      'minCount', 'cpg:belongsToCategory','1'),
      ('cpg-c07', 'cpg:ProductShape',      'minCount', 'ex:priceUSD',         '1'),
      ('cpg-c08', 'cpg:ProductShape',      'pattern',  'cpg:countryOfOrigin', '^[A-Z]{2}$'),
      ('cpg-c09', 'cpg:BrandShape',        'minCount', 'cpg:operatedByOrg',   '1'),
      ('cpg-c10', 'cpg:BrandShape',        'minCount', 'schema:name',         '1'),
      ('cpg-c11', 'cpg:RetailerShape',     'minCount', 'schema:name',         '1'),
      ('cpg-c12', 'cpg:WholesalerShape',   'minCount', 'schema:name',         '1'),
      ('cpg-c13', 'cpg:LocationShape',     'minCount', 'schema:name',         '1'),
      ('cpg-c14', 'cpg:LocationShape',     'minCount', 'cpg:locatedAt',       '1'),
      ('cpg-c15', 'cpg:ManufacturerShape', 'minCount', 'schema:name',         '1'),
      ('cpg-c16', 'cpg:GpcBrickShape',     'pattern',  'cpg:gpcBrickCode',    '^[0-9]{8}$')
    AS v(constraint_id, shape_iri, kind, property_iri, body)
) s ON t.constraint_id = s.constraint_id
WHEN NOT MATCHED THEN INSERT VALUES (s.constraint_id, s.shape_iri, s.kind, s.property_iri, s.body);

SELECT 'CPG vertical ontology (TBox) loaded — optional' AS status;
