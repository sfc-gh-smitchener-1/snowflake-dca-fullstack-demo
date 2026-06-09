-- ============================================================================
-- Snowflake Ontology Reference — 02_load_synthetic_data.sql
-- ============================================================================
-- Defines the SILVER triple-store substrate and seeds it with a tiny enterprise
-- ontology (Customer, Account, Product, Order, Address) plus a handful of
-- individuals + statements you can query immediately.
-- ============================================================================

USE ROLE ONT_DEMO_BUILDER_ROLE;
USE DATABASE ONT_DEMO;
USE SCHEMA   SILVER;
USE WAREHOUSE ONT_DEMO_INGEST_WH;

-- ---------------------------------------------------------------------------
-- TBox: namespace + class + property + value_domain + shape + constraint
-- ---------------------------------------------------------------------------

CREATE OR REPLACE TABLE namespace (
    namespace_iri  STRING       PRIMARY KEY,
    prefix         STRING       NOT NULL,
    description    STRING
);

CREATE OR REPLACE TABLE class (
    class_iri      STRING       PRIMARY KEY,
    namespace_iri  STRING       NOT NULL REFERENCES namespace(namespace_iri),
    label          STRING       NOT NULL,
    definition     STRING,
    sub_class_of   STRING       REFERENCES class(class_iri)
);

CREATE OR REPLACE TABLE value_domain (
    value_domain_iri STRING     PRIMARY KEY,
    kind             STRING     NOT NULL,    -- 'enumeration' | 'unit' | 'regex' | 'range'
    unit_code        STRING,                 -- UCUM code (for kind='unit')
    pattern          STRING,                 -- regex (for kind='regex')
    min_value        FLOAT,                  -- for kind='range'
    max_value        FLOAT,
    enumeration      ARRAY                   -- for kind='enumeration'
);

CREATE OR REPLACE TABLE property (
    property_iri      STRING     PRIMARY KEY,
    namespace_iri     STRING     NOT NULL REFERENCES namespace(namespace_iri),
    label             STRING     NOT NULL,
    kind              STRING     NOT NULL,   -- 'object' | 'datatype'
    domain_class_iri  STRING     REFERENCES class(class_iri),
    range_class_iri   STRING     REFERENCES class(class_iri),    -- when kind='object'
    range_datatype    STRING,                                     -- when kind='datatype' (xsd:string, xsd:decimal, …)
    range_domain_iri  STRING     REFERENCES value_domain(value_domain_iri),
    min_count         INTEGER,
    max_count         INTEGER,
    sub_property_of   STRING     REFERENCES property(property_iri)
);

CREATE OR REPLACE TABLE shape (
    shape_iri          STRING    PRIMARY KEY,
    target_class_iri   STRING    NOT NULL REFERENCES class(class_iri),
    label              STRING
);

CREATE OR REPLACE TABLE constraint (
    constraint_id      STRING    PRIMARY KEY,
    shape_iri          STRING    NOT NULL REFERENCES shape(shape_iri),
    kind               STRING    NOT NULL,    -- 'minCount' | 'maxCount' | 'datatype' | 'pattern' | 'in' | 'sql'
    property_iri       STRING    REFERENCES property(property_iri),
    body               STRING                 -- numeric for counts, regex for pattern, SQL fragment for kind='sql'
);

-- ---------------------------------------------------------------------------
-- ABox: individual + statement (the triple store)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE TABLE individual (
    individual_uid   STRING       PRIMARY KEY,
    canonical_iri    STRING       UNIQUE,
    class_iri        STRING       NOT NULL REFERENCES class(class_iri),
    label            STRING,
    valid_from       TIMESTAMP_TZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    valid_to         TIMESTAMP_TZ
)
CLUSTER BY (class_iri, valid_to);

CREATE OR REPLACE TABLE statement (
    statement_id     STRING       PRIMARY KEY,
    subject_uid      STRING       NOT NULL REFERENCES individual(individual_uid),
    predicate_iri   STRING       NOT NULL REFERENCES property(property_iri),
    object_uid       STRING       REFERENCES individual(individual_uid),    -- for object properties
    object_literal   STRING,                                                 -- for datatype properties
    object_datatype  STRING,                                                 -- xsd:string, xsd:decimal, …
    source_system    STRING,
    confidence       FLOAT        DEFAULT 1.0,
    valid_from       TIMESTAMP_TZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    valid_to         TIMESTAMP_TZ
)
CLUSTER BY (predicate_iri, subject_uid);

-- ---------------------------------------------------------------------------
-- Seed: namespaces
-- ---------------------------------------------------------------------------
INSERT INTO namespace VALUES
    ('http://schema.org/',                'schema',  'Schema.org web vocabulary'),
    ('http://www.w3.org/2001/XMLSchema#', 'xsd',     'XSD datatypes'),
    ('http://example.com/ont/',           'ex',      'Demo organization-specific ontology');

-- ---------------------------------------------------------------------------
-- Seed: classes (a minimal enterprise core)
-- ---------------------------------------------------------------------------
INSERT INTO class (class_iri, namespace_iri, label, definition, sub_class_of) VALUES
    ('schema:Thing',           'http://schema.org/',          'Thing',         'Root of the hierarchy',                   NULL),
    ('schema:Person',          'http://schema.org/',          'Person',        'A natural person',                         'schema:Thing'),
    ('schema:Organization',    'http://schema.org/',          'Organization', 'A company / nonprofit / agency',           'schema:Thing'),
    ('ex:Customer',            'http://example.com/ont/',     'Customer',      'A party that has at least one Account',    'schema:Organization'),
    ('ex:Account',             'http://example.com/ont/',     'Account',       'A contracted relationship',                'schema:Thing'),
    ('ex:Product',             'http://example.com/ont/',     'Product',       'A sellable good',                          'schema:Thing'),
    ('ex:Beverage',            'http://example.com/ont/',     'Beverage',      'A drinkable product',                      'ex:Product'),
    ('ex:Order',               'http://example.com/ont/',     'Order',         'A transaction record',                     'schema:Thing'),
    ('schema:PostalAddress',   'http://schema.org/',          'PostalAddress','A postal mailing address',                  'schema:Thing');

-- ---------------------------------------------------------------------------
-- Seed: value domains
-- ---------------------------------------------------------------------------
INSERT INTO value_domain
    (value_domain_iri, kind, unit_code, pattern, min_value, max_value, enumeration)
SELECT 'ex:USStateCode',  'regex',       NULL,  '^[A-Z]{2}$', NULL, NULL,   NULL
UNION ALL
SELECT 'ex:OrderStatus',  'enumeration', NULL,  NULL,         NULL, NULL,   ARRAY_CONSTRUCT('PLACED','PAID','SHIPPED','DELIVERED','CANCELED')
UNION ALL
SELECT 'ex:AccountStatus','enumeration', NULL,  NULL,         NULL, NULL,   ARRAY_CONSTRUCT('ACTIVE','SUSPENDED','CLOSED')
UNION ALL
SELECT 'ex:PriceUSD',     'range',       'USD', NULL,         0,    100000, NULL;

-- ---------------------------------------------------------------------------
-- Seed: properties
-- ---------------------------------------------------------------------------
INSERT INTO property
    (property_iri,             namespace_iri,                label,             kind,       domain_class_iri,   range_class_iri,         range_datatype, range_domain_iri,    min_count, max_count, sub_property_of)
VALUES
    ('schema:name',            'http://schema.org/',          'name',            'datatype', 'schema:Thing',     NULL,                    'xsd:string',   NULL,                1,         1,         NULL),
    ('schema:email',           'http://schema.org/',          'email',           'datatype', 'schema:Person',    NULL,                    'xsd:string',   NULL,                0,         NULL,      NULL),
    ('schema:addressRegion',   'http://schema.org/',          'addressRegion',   'datatype', 'schema:PostalAddress', NULL,                'xsd:string',   'ex:USStateCode',    0,         1,         NULL),
    ('schema:address',         'http://schema.org/',          'address',         'object',   'schema:Thing',     'schema:PostalAddress',  NULL,           NULL,                0,         NULL,      NULL),
    ('ex:holdsAccount',        'http://example.com/ont/',     'holdsAccount',    'object',   'ex:Customer',      'ex:Account',            NULL,           NULL,                1,         NULL,      NULL),
    ('ex:accountStatus',       'http://example.com/ont/',     'accountStatus',   'datatype', 'ex:Account',       NULL,                    'xsd:string',   'ex:AccountStatus',  1,         1,         NULL),
    ('ex:placedOrder',         'http://example.com/ont/',     'placedOrder',     'object',   'ex:Customer',      'ex:Order',              NULL,           NULL,                0,         NULL,      NULL),
    ('ex:orderStatus',         'http://example.com/ont/',     'orderStatus',     'datatype', 'ex:Order',         NULL,                    'xsd:string',   'ex:OrderStatus',    1,         1,         NULL),
    ('ex:orderedProduct',      'http://example.com/ont/',     'orderedProduct',  'object',   'ex:Order',         'ex:Product',            NULL,           NULL,                1,         NULL,      NULL),
    ('ex:priceUSD',            'http://example.com/ont/',     'priceUSD',        'datatype', 'ex:Product',       NULL,                    'xsd:decimal',  'ex:PriceUSD',       1,         1,         NULL);

-- ---------------------------------------------------------------------------
-- Seed: SHACL-equivalent shapes + constraints
-- ---------------------------------------------------------------------------
INSERT INTO shape VALUES
    ('ex:CustomerShape', 'ex:Customer', 'Constraints every Customer must satisfy'),
    ('ex:AccountShape',  'ex:Account',  'Constraints every Account must satisfy'),
    ('ex:OrderShape',    'ex:Order',    'Constraints every Order must satisfy'),
    ('ex:ProductShape',  'ex:Product',  'Constraints every Product must satisfy');

INSERT INTO constraint VALUES
    ('c1', 'ex:CustomerShape', 'minCount', 'schema:name',          '1'),
    ('c2', 'ex:CustomerShape', 'minCount', 'ex:holdsAccount',      '1'),
    ('c3', 'ex:AccountShape',  'minCount', 'ex:accountStatus',     '1'),
    ('c4', 'ex:AccountShape',  'in',       'ex:accountStatus',     'ACTIVE,SUSPENDED,CLOSED'),
    ('c5', 'ex:OrderShape',    'in',       'ex:orderStatus',       'PLACED,PAID,SHIPPED,DELIVERED,CANCELED'),
    ('c6', 'ex:OrderShape',    'minCount', 'ex:orderedProduct',    '1'),
    ('c7', 'ex:ProductShape',  'minCount', 'ex:priceUSD',          '1');

-- ---------------------------------------------------------------------------
-- Seed: individuals (a handful per class)
-- ---------------------------------------------------------------------------
INSERT INTO individual (individual_uid, canonical_iri, class_iri, label) VALUES
    -- Customers
    ('CUST-1001', 'ex:Customer/1001', 'ex:Customer',         'Acme Inc.'),
    ('CUST-1002', 'ex:Customer/1002', 'ex:Customer',         'Beta Corp'),
    ('CUST-1003', 'ex:Customer/1003', 'ex:Customer',         'Cedar LLC'),
    -- Accounts
    ('ACCT-2001', 'ex:Account/2001',  'ex:Account',          'Acme primary'),
    ('ACCT-2002', 'ex:Account/2002',  'ex:Account',          'Acme reseller'),
    ('ACCT-2003', 'ex:Account/2003',  'ex:Account',          'Beta primary'),
    ('ACCT-2004', 'ex:Account/2004',  'ex:Account',          'Cedar primary'),
    -- Products
    ('PROD-3001', 'ex:Product/3001',  'ex:Product',          'WidgetPro 2026'),
    ('PROD-3002', 'ex:Product/3002',  'ex:Product',          'WidgetPro Mini'),
    ('PROD-3003', 'ex:Product/3003',  'ex:Beverage',         'CoolerCola 12oz'),
    ('PROD-3004', 'ex:Product/3004',  'ex:Beverage',         'SparkleWater 1L'),
    -- Orders
    ('ORD-4001',  'ex:Order/4001',    'ex:Order',            'Order 4001'),
    ('ORD-4002',  'ex:Order/4002',    'ex:Order',            'Order 4002'),
    ('ORD-4003',  'ex:Order/4003',    'ex:Order',            'Order 4003'),
    -- Addresses
    ('ADDR-5001', 'ex:Address/5001',  'schema:PostalAddress','Acme HQ — Palo Alto, CA'),
    ('ADDR-5002', 'ex:Address/5002',  'schema:PostalAddress','Beta HQ — Boston, MA'),
    ('ADDR-5003', 'ex:Address/5003',  'schema:PostalAddress','Cedar HQ — Austin, TX');

-- ---------------------------------------------------------------------------
-- Seed: statements (the actual triples)
-- ---------------------------------------------------------------------------
-- Naming convention: stmt-<seq>; predicates use property IRIs
INSERT INTO statement
    (statement_id, subject_uid, predicate_iri,        object_uid, object_literal,           object_datatype, source_system, confidence)
VALUES
    -- Customer names + addresses
    ('s001', 'CUST-1001', 'schema:name',          NULL,        'Acme Inc.',              'xsd:string', 'CRM', 1.0),
    ('s002', 'CUST-1002', 'schema:name',          NULL,        'Beta Corp',              'xsd:string', 'CRM', 1.0),
    ('s003', 'CUST-1003', 'schema:name',          NULL,        'Cedar LLC',              'xsd:string', 'CRM', 1.0),
    ('s004', 'CUST-1001', 'schema:address',       'ADDR-5001', NULL,                     NULL,         'CRM', 1.0),
    ('s005', 'CUST-1002', 'schema:address',       'ADDR-5002', NULL,                     NULL,         'CRM', 1.0),
    ('s006', 'CUST-1003', 'schema:address',       'ADDR-5003', NULL,                     NULL,         'CRM', 1.0),
    -- Addresses → region
    ('s007', 'ADDR-5001', 'schema:addressRegion', NULL,        'CA',                     'xsd:string', 'CRM', 1.0),
    ('s008', 'ADDR-5002', 'schema:addressRegion', NULL,        'MA',                     'xsd:string', 'CRM', 1.0),
    ('s009', 'ADDR-5003', 'schema:addressRegion', NULL,        'TX',                     'xsd:string', 'CRM', 1.0),
    -- Customer → Account
    ('s010', 'CUST-1001', 'ex:holdsAccount',      'ACCT-2001', NULL,                     NULL,         'ERP', 1.0),
    ('s011', 'CUST-1001', 'ex:holdsAccount',      'ACCT-2002', NULL,                     NULL,         'ERP', 1.0),
    ('s012', 'CUST-1002', 'ex:holdsAccount',      'ACCT-2003', NULL,                     NULL,         'ERP', 1.0),
    ('s013', 'CUST-1003', 'ex:holdsAccount',      'ACCT-2004', NULL,                     NULL,         'ERP', 1.0),
    -- Account → status
    ('s014', 'ACCT-2001', 'ex:accountStatus',     NULL,        'ACTIVE',                 'xsd:string', 'ERP', 1.0),
    ('s015', 'ACCT-2002', 'ex:accountStatus',     NULL,        'ACTIVE',                 'xsd:string', 'ERP', 1.0),
    ('s016', 'ACCT-2003', 'ex:accountStatus',     NULL,        'SUSPENDED',              'xsd:string', 'ERP', 1.0),
    ('s017', 'ACCT-2004', 'ex:accountStatus',     NULL,        'ACTIVE',                 'xsd:string', 'ERP', 1.0),
    -- Product names + prices
    ('s018', 'PROD-3001', 'schema:name',          NULL,        'WidgetPro 2026',         'xsd:string', 'PIM', 1.0),
    ('s019', 'PROD-3002', 'schema:name',          NULL,        'WidgetPro Mini',         'xsd:string', 'PIM', 1.0),
    ('s020', 'PROD-3003', 'schema:name',          NULL,        'CoolerCola 12oz',        'xsd:string', 'PIM', 1.0),
    ('s021', 'PROD-3004', 'schema:name',          NULL,        'SparkleWater 1L',        'xsd:string', 'PIM', 1.0),
    ('s022', 'PROD-3001', 'ex:priceUSD',          NULL,        '199.00',                 'xsd:decimal','PIM', 1.0),
    ('s023', 'PROD-3002', 'ex:priceUSD',          NULL,        '99.00',                  'xsd:decimal','PIM', 1.0),
    ('s024', 'PROD-3003', 'ex:priceUSD',          NULL,        '1.50',                   'xsd:decimal','PIM', 1.0),
    ('s025', 'PROD-3004', 'ex:priceUSD',          NULL,        '2.25',                   'xsd:decimal','PIM', 1.0),
    -- Orders
    ('s026', 'CUST-1001', 'ex:placedOrder',       'ORD-4001',  NULL,                     NULL,         'ERP', 1.0),
    ('s027', 'CUST-1001', 'ex:placedOrder',       'ORD-4002',  NULL,                     NULL,         'ERP', 1.0),
    ('s028', 'CUST-1003', 'ex:placedOrder',       'ORD-4003',  NULL,                     NULL,         'ERP', 1.0),
    ('s029', 'ORD-4001',  'ex:orderStatus',       NULL,        'DELIVERED',              'xsd:string', 'ERP', 1.0),
    ('s030', 'ORD-4002',  'ex:orderStatus',       NULL,        'PAID',                   'xsd:string', 'ERP', 1.0),
    ('s031', 'ORD-4003',  'ex:orderStatus',       NULL,        'PLACED',                 'xsd:string', 'ERP', 1.0),
    ('s032', 'ORD-4001',  'ex:orderedProduct',    'PROD-3001', NULL,                     NULL,         'ERP', 1.0),
    ('s033', 'ORD-4001',  'ex:orderedProduct',    'PROD-3003', NULL,                     NULL,         'ERP', 1.0),
    ('s034', 'ORD-4002',  'ex:orderedProduct',    'PROD-3002', NULL,                     NULL,         'ERP', 1.0),
    ('s035', 'ORD-4003',  'ex:orderedProduct',    'PROD-3004', NULL,                     NULL,         'ERP', 1.0);

SELECT
    (SELECT COUNT(*) FROM namespace)  AS namespaces,
    (SELECT COUNT(*) FROM class)      AS classes,
    (SELECT COUNT(*) FROM property)   AS properties,
    (SELECT COUNT(*) FROM individual) AS individuals,
    (SELECT COUNT(*) FROM statement)  AS statements,
    (SELECT COUNT(*) FROM shape)      AS shapes,
    (SELECT COUNT(*) FROM constraint) AS constraints;
