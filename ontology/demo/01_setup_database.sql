-- ============================================================================
-- Snowflake Ontology Reference — 01_setup_database.sql
-- ============================================================================
-- Creates the database, schemas, virtual compute, and roles for the demo.
-- Run as ACCOUNTADMIN.
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- ---------------------------------------------------------------------------
-- Database & schemas
-- ---------------------------------------------------------------------------
CREATE OR REPLACE DATABASE ONT_DEMO
    COMMENT = 'Snowflake-native ontology reference architecture demo';

USE DATABASE ONT_DEMO;

CREATE OR REPLACE SCHEMA BRONZE
    COMMENT = 'Raw landings (synthetic source feeds)';

CREATE OR REPLACE SCHEMA SILVER
    COMMENT = 'Canonical ontology substrate: namespace, class, property, individual, statement';

CREATE OR REPLACE SCHEMA GOLD
    COMMENT = 'Business-facing semantic views for Cortex Analyst and BI';

CREATE OR REPLACE SCHEMA CONFIG
    COMMENT = 'Analytics (Cortex Analyst) model YAMLs and other config artifacts';

-- Analytics layer: Cortex Analyst model YAMLs (kept separate from the ontology
-- TBox artifacts). These are what show up in the Cortex Analyst model picker.
CREATE OR REPLACE STAGE CONFIG.CORTEX_ANALYST_MODELS
    DIRECTORY = ( ENABLE = TRUE )
    COMMENT = 'Stage holding Cortex Analyst (analytics) semantic model YAML files';

-- Streamlit-in-Snowflake app artifacts (deployed by `snow streamlit deploy`).
CREATE OR REPLACE STAGE CONFIG.STREAMLIT_STAGE
    DIRECTORY = ( ENABLE = TRUE )
    COMMENT = 'Stage holding the Ontology Console Streamlit app artifacts';

-- ---------------------------------------------------------------------------
-- Virtual compute (right-sized per workload, isolated from one another)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE WAREHOUSE ONT_DEMO_INGEST_WH
    WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Ingest + dbt + DMF refresh';

CREATE OR REPLACE WAREHOUSE ONT_DEMO_SEARCH_WH
    WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Cortex Search service compute';

CREATE OR REPLACE WAREHOUSE ONT_DEMO_AGENT_WH
    WAREHOUSE_SIZE = 'SMALL'  AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Cortex Agent / Analyst + Streamlit';

CREATE OR REPLACE WAREHOUSE ONT_DEMO_ANALYTICS_WH
    WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Ad-hoc analytics + recursive CTE traversals';

-- ---------------------------------------------------------------------------
-- Roles (demo personas)
-- ---------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS ONT_DEMO_BUILDER_ROLE
    COMMENT = 'Author the ontology: full read/write on SILVER + CONFIG';

CREATE ROLE IF NOT EXISTS ONT_DEMO_CONSUMER_ROLE
    COMMENT = 'Query the ontology: read-only on GOLD + run Cortex services';

GRANT USAGE ON DATABASE ONT_DEMO TO ROLE ONT_DEMO_BUILDER_ROLE;
GRANT USAGE ON SCHEMA  ONT_DEMO.BRONZE  TO ROLE ONT_DEMO_BUILDER_ROLE;
GRANT CREATE TABLE, CREATE VIEW, CREATE STAGE, CREATE FILE FORMAT
    ON SCHEMA ONT_DEMO.BRONZE TO ROLE ONT_DEMO_BUILDER_ROLE;
GRANT USAGE ON SCHEMA  ONT_DEMO.SILVER  TO ROLE ONT_DEMO_BUILDER_ROLE;
GRANT USAGE ON SCHEMA  ONT_DEMO.GOLD    TO ROLE ONT_DEMO_BUILDER_ROLE;
GRANT USAGE ON SCHEMA  ONT_DEMO.CONFIG  TO ROLE ONT_DEMO_BUILDER_ROLE;
GRANT CREATE TABLE, CREATE VIEW, CREATE DYNAMIC TABLE, CREATE STAGE,
    CREATE CORTEX SEARCH SERVICE, CREATE DATA METRIC FUNCTION,
    CREATE FUNCTION, CREATE PROCEDURE
    ON SCHEMA ONT_DEMO.SILVER TO ROLE ONT_DEMO_BUILDER_ROLE;
GRANT CREATE TABLE, CREATE VIEW, CREATE DYNAMIC TABLE,
    CREATE FUNCTION, CREATE PROCEDURE
    ON SCHEMA ONT_DEMO.GOLD   TO ROLE ONT_DEMO_BUILDER_ROLE;
GRANT READ, WRITE ON STAGE ONT_DEMO.CONFIG.CORTEX_ANALYST_MODELS TO ROLE ONT_DEMO_BUILDER_ROLE;
GRANT READ, WRITE ON STAGE ONT_DEMO.CONFIG.STREAMLIT_STAGE       TO ROLE ONT_DEMO_BUILDER_ROLE;
GRANT USAGE ON WAREHOUSE ONT_DEMO_INGEST_WH    TO ROLE ONT_DEMO_BUILDER_ROLE;
GRANT USAGE ON WAREHOUSE ONT_DEMO_ANALYTICS_WH TO ROLE ONT_DEMO_BUILDER_ROLE;
GRANT USAGE ON WAREHOUSE ONT_DEMO_SEARCH_WH    TO ROLE ONT_DEMO_BUILDER_ROLE;
GRANT USAGE ON WAREHOUSE ONT_DEMO_AGENT_WH     TO ROLE ONT_DEMO_BUILDER_ROLE;

GRANT USAGE ON DATABASE ONT_DEMO TO ROLE ONT_DEMO_CONSUMER_ROLE;
GRANT USAGE ON SCHEMA  ONT_DEMO.GOLD    TO ROLE ONT_DEMO_CONSUMER_ROLE;
GRANT USAGE ON SCHEMA  ONT_DEMO.CONFIG  TO ROLE ONT_DEMO_CONSUMER_ROLE;
GRANT READ ON STAGE ONT_DEMO.CONFIG.CORTEX_ANALYST_MODELS TO ROLE ONT_DEMO_CONSUMER_ROLE;
GRANT READ ON STAGE ONT_DEMO.CONFIG.STREAMLIT_STAGE       TO ROLE ONT_DEMO_CONSUMER_ROLE;
GRANT USAGE ON WAREHOUSE ONT_DEMO_AGENT_WH  TO ROLE ONT_DEMO_CONSUMER_ROLE;
GRANT USAGE ON WAREHOUSE ONT_DEMO_SEARCH_WH TO ROLE ONT_DEMO_CONSUMER_ROLE;

GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE ONT_DEMO_BUILDER_ROLE;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE ONT_DEMO_CONSUMER_ROLE;

GRANT ROLE ONT_DEMO_BUILDER_ROLE  TO ROLE SYSADMIN;
GRANT ROLE ONT_DEMO_CONSUMER_ROLE TO ROLE SYSADMIN;

SELECT 'ONT_DEMO database, schemas, virtual compute, and roles created.' AS status;
