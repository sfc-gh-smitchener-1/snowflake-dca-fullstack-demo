-- ============================================================================
-- Snowflake Ontology Reference — 04_dbt_tests_and_dmfs.sql
-- ============================================================================
-- Maps a handful of SHACL shapes (from `silver.shape` + `silver.constraint`)
-- onto DATA_METRIC_FUNCTIONs. Each DMF returns the count of *violations* so a
-- value of 0 = healthy; non-zero shows up in Horizon Catalog and any external
-- monitor that polls SNOWFLAKE.ACCOUNT_USAGE.DATA_METRIC_FUNCTION_REFERENCES.
--
-- These are the "enforcement half" of L4 ontology. The "documentation half"
-- is `ontologies/demo.ttl`.
-- ============================================================================

USE ROLE ONT_DEMO_BUILDER_ROLE;
USE DATABASE ONT_DEMO;
USE SCHEMA SILVER;
USE WAREHOUSE ONT_DEMO_INGEST_WH;

-- ---------------------------------------------------------------------------
-- DMF 1 — minCount: every Customer has at least one schema:name
--   SHACL:  :CustomerShape sh:property [ sh:path schema:name ; sh:minCount 1 ]
-- ---------------------------------------------------------------------------
CREATE OR REPLACE DATA METRIC FUNCTION dmf_customer_missing_name (
    ARG_T TABLE(individual_uid STRING, class_iri STRING)
)
RETURNS NUMBER
AS
$$
    SELECT COUNT(*)
    FROM ARG_T i
    LEFT JOIN ONT_DEMO.SILVER.statement s
           ON s.subject_uid    = i.individual_uid
          AND s.predicate_iri = 'schema:name'
          AND s.valid_to IS NULL
    WHERE i.class_iri = 'ex:Customer'
      AND s.statement_id IS NULL
$$;

-- ---------------------------------------------------------------------------
-- DMF 2 — minCount: every Customer holds at least one Account
--   SHACL:  :CustomerShape sh:property [ sh:path ex:holdsAccount ; sh:minCount 1 ]
-- ---------------------------------------------------------------------------
CREATE OR REPLACE DATA METRIC FUNCTION dmf_customer_missing_account (
    ARG_T TABLE(individual_uid STRING, class_iri STRING)
)
RETURNS NUMBER
AS
$$
    SELECT COUNT(*)
    FROM ARG_T i
    LEFT JOIN ONT_DEMO.SILVER.statement s
           ON s.subject_uid    = i.individual_uid
          AND s.predicate_iri = 'ex:holdsAccount'
          AND s.valid_to IS NULL
    WHERE i.class_iri = 'ex:Customer'
      AND s.statement_id IS NULL
$$;

-- ---------------------------------------------------------------------------
-- DMF 3 — sh:in: ex:accountStatus must be in (ACTIVE, SUSPENDED, CLOSED)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE DATA METRIC FUNCTION dmf_account_status_invalid (
    ARG_T TABLE(statement_id STRING, predicate_iri STRING, object_literal STRING)
)
RETURNS NUMBER
AS
$$
    SELECT COUNT(*)
    FROM ARG_T s
    WHERE s.predicate_iri = 'ex:accountStatus'
      AND s.object_literal NOT IN ('ACTIVE','SUSPENDED','CLOSED')
$$;

-- ---------------------------------------------------------------------------
-- DMF 4 — sh:pattern: schema:addressRegion must match ^[A-Z]{2}$ (US state)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE DATA METRIC FUNCTION dmf_address_region_pattern (
    ARG_T TABLE(statement_id STRING, predicate_iri STRING, object_literal STRING)
)
RETURNS NUMBER
AS
$$
    SELECT COUNT(*)
    FROM ARG_T s
    WHERE s.predicate_iri = 'schema:addressRegion'
      AND NOT REGEXP_LIKE(s.object_literal, '^[A-Z]{2}$')
$$;

-- ---------------------------------------------------------------------------
-- DMF 5 — sh:datatype + sh:minInclusive: ex:priceUSD is decimal ≥ 0
-- ---------------------------------------------------------------------------
CREATE OR REPLACE DATA METRIC FUNCTION dmf_product_price_invalid (
    ARG_T TABLE(statement_id STRING, predicate_iri STRING, object_literal STRING)
)
RETURNS NUMBER
AS
$$
    SELECT COUNT(*)
    FROM ARG_T s
    WHERE s.predicate_iri = 'ex:priceUSD'
      AND (TRY_CAST(s.object_literal AS NUMBER(18,2)) IS NULL
           OR TRY_CAST(s.object_literal AS NUMBER(18,2)) < 0)
$$;

-- ---------------------------------------------------------------------------
-- DMF 6 — sh:class (referential integrity on object properties):
-- every ex:holdsAccount object_uid must point to an individual of class ex:Account
-- ---------------------------------------------------------------------------
CREATE OR REPLACE DATA METRIC FUNCTION dmf_holdsaccount_wrong_class (
    ARG_T TABLE(statement_id STRING, predicate_iri STRING, object_uid STRING)
)
RETURNS NUMBER
AS
$$
    SELECT COUNT(*)
    FROM ARG_T s
    LEFT JOIN ONT_DEMO.SILVER.individual i
           ON i.individual_uid = s.object_uid
    WHERE s.predicate_iri = 'ex:holdsAccount'
      AND (i.individual_uid IS NULL OR i.class_iri <> 'ex:Account')
$$;

-- ---------------------------------------------------------------------------
-- Wire the DMFs to the tables they observe (Horizon will pick them up)
-- Schedule: every 30 minutes; DMFs can also be triggered on insert/update.
-- ---------------------------------------------------------------------------
ALTER TABLE individual SET DATA_METRIC_SCHEDULE = '30 MINUTE';
ALTER TABLE individual ADD DATA METRIC FUNCTION dmf_customer_missing_name ON (individual_uid, class_iri);
ALTER TABLE individual ADD DATA METRIC FUNCTION dmf_customer_missing_account ON (individual_uid, class_iri);

ALTER TABLE statement  SET DATA_METRIC_SCHEDULE = '30 MINUTE';
ALTER TABLE statement  ADD DATA METRIC FUNCTION dmf_account_status_invalid ON (statement_id, predicate_iri, object_literal);
ALTER TABLE statement  ADD DATA METRIC FUNCTION dmf_address_region_pattern ON (statement_id, predicate_iri, object_literal);
ALTER TABLE statement  ADD DATA METRIC FUNCTION dmf_product_price_invalid  ON (statement_id, predicate_iri, object_literal);
ALTER TABLE statement  ADD DATA METRIC FUNCTION dmf_holdsaccount_wrong_class ON (statement_id, predicate_iri, object_uid);

-- ---------------------------------------------------------------------------
-- Quick health roll-up view (what your Streamlit dashboard polls)
-- ---------------------------------------------------------------------------
USE SCHEMA GOLD;

CREATE OR REPLACE VIEW v_ontology_health AS
SELECT
    metric_name,
    table_name,
    measurement_time,
    value AS violation_count
FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS
WHERE table_database = 'ONT_DEMO'
  AND metric_name LIKE 'DMF\\_%' ESCAPE '\\'
ORDER BY measurement_time DESC, metric_name;

SELECT 'DMFs created and attached. Wait one schedule tick, then SELECT * FROM GOLD.v_ontology_health;' AS status;
