-- ============================================================================
-- SNOWFLAKE HORIZON CONTEXT — SELECT STAR INTEGRATION DEMO
-- ============================================================================
-- 
-- Simulates the "Horizon Context" product capability that Snowflake gained
-- through the Select Star acquisition (completed Dec 2025, PrPr Summit 2026).
--
-- What this builds:
--   • CURATED_DEV.HORIZON_CONTEXT schema — Snowflake-managed metadata store
--   • 5 core tables mirroring the HorizonStar architecture (GS-persisted
--     connector state, Select Star-crawled objects, cross-platform lineage,
--     usage intelligence, AI governance recommendations)
--   • Simulated connectors: PostgreSQL, SQL Server, Tableau, Power BI, dbt
--   • 70+ catalog objects spanning the full enterprise data stack
--   • 30 cross-platform lineage edges (external source → Snowflake → BI)
--   • Stored procedures for crawl simulation and Cortex AI enrichment
--   • Views for Universal Catalog, lineage, usage intelligence, governance gaps
--
-- Architecture reference (from HorizonStar design docs):
--   Customer (Snowsight connector setup)
--     → GS persists connector state/credentials
--       → Select Star crawls external metadata
--         → Copy service ingests into Snowflake-controlled store (this schema)
--           → Snowscope / Universal Search surfaces results
--
-- PrPr scope (Summit 2026): connectors for PostgreSQL, SQL Server, Tableau,
--   Power BI, dbt. Looker + Databricks targeted for PuPr (fall 2026).
-- ============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE CURATED_DEV;

-- ============================================================================
-- SCHEMA
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS CURATED_DEV.HORIZON_CONTEXT
    COMMENT = 'Horizon Context metadata store — Snowflake-managed external catalog objects, 
               cross-platform lineage, usage intelligence, and AI governance enrichments 
               harvested by the Select Star-powered metadata connector service.
               Mirrors the FDB-backed serving layer in the HorizonStar architecture.';

USE SCHEMA CURATED_DEV.HORIZON_CONTEXT;

-- ============================================================================
-- TABLE: EXT_CONNECTORS
-- Persisted in GS (simulated here). Connector credentials stored in DPO-backed
-- GS storage; only metadata/status lives in this table.
-- ============================================================================

CREATE OR REPLACE TABLE EXT_CONNECTORS (
    CONNECTOR_ID         VARCHAR(50)   NOT NULL,
    SOURCE_SYSTEM        VARCHAR(100)  NOT NULL  COMMENT 'Human-readable platform name',
    SOURCE_TYPE          VARCHAR(50)   NOT NULL  COMMENT 'DATABASE | BI_TOOL | PIPELINE | CLOUD_WAREHOUSE',
    CONNECTION_NAME      VARCHAR(200)  NOT NULL  COMMENT 'User-defined display name from connector setup wizard',
    HOST_MASKED          VARCHAR(300)            COMMENT 'Host/URL with credentials stripped',
    STATUS               VARCHAR(20)   NOT NULL DEFAULT 'ACTIVE'
                                                COMMENT 'ACTIVE | CRAWLING | ERROR | PAUSED | PENDING',
    CRAWL_FREQUENCY      VARCHAR(20)   DEFAULT 'DAILY'
                                                COMMENT 'HOURLY | DAILY | WEEKLY',
    LAST_CRAWL_AT        TIMESTAMP_NTZ           COMMENT 'Last successful crawl completion',
    NEXT_CRAWL_AT        TIMESTAMP_NTZ           COMMENT 'Scheduled next crawl (managed by GS in PuPr)',
    OBJECTS_TOTAL        INTEGER       DEFAULT 0 COMMENT 'Total metadata objects in catalog',
    TABLES_DISCOVERED    INTEGER       DEFAULT 0,
    COLUMNS_DISCOVERED   INTEGER       DEFAULT 0,
    DASHBOARDS_DISCOVERED INTEGER      DEFAULT 0,
    MODELS_DISCOVERED    INTEGER       DEFAULT 0,
    ERROR_MESSAGE        VARCHAR(1000)           COMMENT 'Last error if STATUS = ERROR',
    CONNECTOR_ICON       VARCHAR(10)             COMMENT 'Emoji for UI display',
    CONNECTOR_COLOR      VARCHAR(7)              COMMENT 'Hex color for UI display',
    CONNECTOR_VERSION    VARCHAR(20)   DEFAULT '1.0.0',
    RBAC_CONNECTOR_ROLE  VARCHAR(200)            COMMENT 'Snowflake role governing access to this connector',
    IS_PRPR_AVAILABLE    BOOLEAN       DEFAULT TRUE COMMENT 'Available in PrPr or deferred to PuPr/GA',
    ROADMAP_NOTE         VARCHAR(500)            COMMENT 'Field-facing roadmap context',
    CREATED_AT           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_EXT_CONNECTORS PRIMARY KEY (CONNECTOR_ID)
)
COMMENT = 'Registered Horizon Context external metadata connectors. State persisted by GS; 
           credentials stored in DPO-backed GS storage (not in this table).';

-- ============================================================================
-- TABLE: EXT_CATALOG_OBJECTS
-- Metadata objects harvested from external systems and Snowflake-native objects
-- enrolled in the unified catalog. Backed by FDB in production; here in tables.
-- ============================================================================

CREATE OR REPLACE TABLE EXT_CATALOG_OBJECTS (
    OBJECT_ID            VARCHAR(50)   NOT NULL,
    CONNECTOR_ID         VARCHAR(50)   NOT NULL,
    OBJECT_TYPE          VARCHAR(50)   NOT NULL
                                       COMMENT 'DATABASE | SCHEMA | TABLE | VIEW | COLUMN | DASHBOARD | REPORT | MODEL | PIPELINE',
    QUALIFIED_NAME       VARCHAR(1000) NOT NULL  COMMENT 'Full object path in source system',
    SOURCE_SYSTEM        VARCHAR(100)  NOT NULL,
    SOURCE_LAYER         VARCHAR(30)             COMMENT 'EXTERNAL | RAW | CURATED | SEMANTIC | BI',
    DATABASE_NAME        VARCHAR(200),
    SCHEMA_NAME          VARCHAR(200),
    TABLE_NAME           VARCHAR(200),
    COLUMN_NAME          VARCHAR(200)            COMMENT 'Only set when OBJECT_TYPE = COLUMN',
    DATA_TYPE            VARCHAR(100)            COMMENT 'Column data type if applicable',
    DESCRIPTION          VARCHAR(4000)           COMMENT 'Business description',
    DESCRIPTION_SOURCE   VARCHAR(50)             COMMENT 'MANUAL | AI_GENERATED | SOURCE_DOCS | DBT_YAML | EMPTY',
    SENSITIVITY_CLASS    VARCHAR(20)             COMMENT 'PUBLIC | INTERNAL | CONFIDENTIAL | RESTRICTED',
    IS_PII               BOOLEAN       DEFAULT FALSE,
    PII_TYPE             VARCHAR(200)            COMMENT 'Comma-separated PII types: NAME,EMAIL,SSN,PHONE,DOB,SALARY,HEALTH',
    POPULARITY_SCORE     FLOAT                   COMMENT '0-100 score; combines query_count, user_count, BI_downstream',
    QUERY_COUNT_30D      INTEGER       DEFAULT 0,
    USER_COUNT_30D       INTEGER       DEFAULT 0,
    DOWNSTREAM_BI_COUNT  INTEGER       DEFAULT 0 COMMENT 'Number of BI reports/dashboards consuming this object',
    UPSTREAM_SOURCE_COUNT INTEGER      DEFAULT 0 COMMENT 'Number of upstream objects feeding into this one',
    OWNER_EMAIL          VARCHAR(200),
    OWNER_TEAM           VARCHAR(100),
    SNOWFLAKE_OBJECT_REF VARCHAR(500)            COMMENT 'Mapped Snowflake object if cross-system lineage established',
    HAS_GOVERNANCE_GAP   BOOLEAN       DEFAULT FALSE COMMENT 'Missing owner, description, or sensitivity tag',
    IS_ORPHANED          BOOLEAN       DEFAULT FALSE COMMENT 'Zero downstream consumers in 90 days',
    LAST_CRAWLED_AT      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_EXT_CATALOG_OBJECTS PRIMARY KEY (OBJECT_ID)
)
COMMENT = 'Unified catalog objects — external platforms + Snowflake-native — indexed for 
           Universal Search and Browse in Horizon Context.';

-- ============================================================================
-- TABLE: EXT_COLUMN_LINEAGE
-- Cross-platform lineage graph. Spans external source → Snowflake → BI tool.
-- Snowflake-internal edges come from OBJECT_DEPENDENCIES; external edges from 
-- Select Star connector analysis.
-- ============================================================================

CREATE OR REPLACE TABLE EXT_COLUMN_LINEAGE (
    LINEAGE_ID           VARCHAR(50)   NOT NULL,
    SOURCE_OBJECT_ID     VARCHAR(50)   NOT NULL,
    TARGET_OBJECT_ID     VARCHAR(50)   NOT NULL,
    SOURCE_SYSTEM        VARCHAR(100),
    TARGET_SYSTEM        VARCHAR(100),
    SOURCE_LAYER         VARCHAR(30)   COMMENT 'EXTERNAL | RAW | CURATED | SEMANTIC | BI',
    TARGET_LAYER         VARCHAR(30),
    LINEAGE_TYPE         VARCHAR(50)   NOT NULL
                                       COMMENT 'INGESTED | TRANSFORMED | PUBLISHED | CONSUMED | CERTIFIED',
    TRANSFORMATION_DESC  VARCHAR(2000) COMMENT 'Human-readable transformation description',
    CONFIDENCE_SCORE     FLOAT         DEFAULT 1.0 COMMENT '0-1; inferred lineage scored lower',
    IS_COLUMN_LEVEL      BOOLEAN       DEFAULT FALSE COMMENT 'True = column-to-column; False = table-level',
    HOP_NUMBER           INTEGER       DEFAULT 1    COMMENT 'Position in multi-hop lineage path',
    LINEAGE_PATH_ID      VARCHAR(50)                COMMENT 'Groups hops into named end-to-end paths',
    CREATED_AT           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_EXT_COLUMN_LINEAGE PRIMARY KEY (LINEAGE_ID)
)
COMMENT = 'Cross-platform lineage graph edges. Extends Snowflake native OBJECT_DEPENDENCIES 
           upstream to external sources and downstream to BI consumption.';

-- ============================================================================
-- TABLE: EXT_USAGE_STATS
-- Daily usage snapshots for each catalog object. Populated from Snowflake 
-- QUERY_HISTORY (for Snowflake objects) and BI tool usage APIs (for dashboards).
-- ============================================================================

CREATE OR REPLACE TABLE EXT_USAGE_STATS (
    STAT_ID              VARCHAR(50)   NOT NULL,
    OBJECT_ID            VARCHAR(50)   NOT NULL,
    STAT_DATE            DATE          NOT NULL,
    QUERY_COUNT          INTEGER       DEFAULT 0,
    DISTINCT_USERS       INTEGER       DEFAULT 0,
    BI_VIEWS             INTEGER       DEFAULT 0   COMMENT 'Dashboard/report views from BI tool APIs',
    DATA_FRESHNESS_HOURS FLOAT                     COMMENT 'Hours since last data write',
    AVG_QUERY_DURATION_MS INTEGER                  COMMENT 'P50 query duration',
    BYTES_SCANNED        BIGINT        DEFAULT 0,
    CREATED_AT           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_EXT_USAGE_STATS PRIMARY KEY (STAT_ID)
)
COMMENT = 'Daily usage statistics powering popularity scores and orphan detection.';

-- ============================================================================
-- TABLE: EXT_GOVERNANCE_RECOMMENDATIONS
-- AI-generated governance recommendations from Select Star metadata analysis.
-- In production: driven by Cortex COMPLETE on metadata graph.
-- ============================================================================

CREATE OR REPLACE TABLE EXT_GOVERNANCE_RECOMMENDATIONS (
    REC_ID               VARCHAR(50)   NOT NULL,
    OBJECT_ID            VARCHAR(50)   NOT NULL,
    RECOMMENDATION_TYPE  VARCHAR(50)   NOT NULL
                                       COMMENT 'ADD_TAG | ADD_DESCRIPTION | ASSIGN_OWNER | APPLY_MASK | DEPRECATE | REVIEW_PII | CERTIFY',
    PRIORITY             VARCHAR(10)   DEFAULT 'MEDIUM' COMMENT 'CRITICAL | HIGH | MEDIUM | LOW',
    REASON               VARCHAR(2000) NOT NULL,
    SUGGESTED_VALUE      VARCHAR(1000)             COMMENT 'Suggested tag value, description snippet, or owner email',
    AI_CONFIDENCE        FLOAT                     COMMENT '0-1 confidence in the recommendation',
    STATUS               VARCHAR(20)   DEFAULT 'OPEN'
                                       COMMENT 'OPEN | ACCEPTED | AUTO_APPLIED | DISMISSED',
    CREATED_AT           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    RESOLVED_AT          TIMESTAMP_NTZ,
    RESOLVED_BY          VARCHAR(100),
    CONSTRAINT PK_EXT_GOVERNANCE_RECOMMENDATIONS PRIMARY KEY (REC_ID)
)
COMMENT = 'AI governance recommendations surfaced by Horizon Context from cross-system metadata analysis.';

-- ============================================================================
-- SEED DATA: CONNECTORS
-- ============================================================================

INSERT INTO EXT_CONNECTORS VALUES
-- Snowflake (native) — always enrolled; represents the internal data estate
('conn-sf', 'Snowflake', 'CLOUD_WAREHOUSE', 'snowflake-internal-estate',
 'account.snowflakecomputing.com', 'ACTIVE', 'CONTINUOUS',
 DATEADD(minute, -5, CURRENT_TIMESTAMP()), DATEADD(minute, 55, CURRENT_TIMESTAMP()),
 1847, 312, 4821, 0, 0, NULL, '❄️', '#29B5E8', '2.0.0',
 'HORIZON_CONTEXT_ADMIN', TRUE,
 'Native Snowflake objects auto-enrolled in Horizon Context. Lineage sourced from OBJECT_DEPENDENCIES.',
 DATEADD(day, -120, CURRENT_TIMESTAMP()), CURRENT_TIMESTAMP()),

-- PostgreSQL operational database
('conn-pg', 'PostgreSQL', 'DATABASE', 'prod-postgres-operational',
 '***-prod.rds.amazonaws.com:5432', 'ACTIVE', 'DAILY',
 DATEADD(hour, -3, CURRENT_TIMESTAMP()), DATEADD(hour, 21, CURRENT_TIMESTAMP()),
 487, 38, 412, 0, 0, NULL, '🐘', '#336791', '1.2.1',
 'HORIZON_CONTEXT_ADMIN', TRUE, NULL,
 DATEADD(day, -90, CURRENT_TIMESTAMP()), CURRENT_TIMESTAMP()),

-- Microsoft SQL Server ERP
('conn-sql', 'Microsoft SQL Server', 'DATABASE', 'erp-sqlserver-prod',
 '10.***.***.**:1433', 'ACTIVE', 'DAILY',
 DATEADD(hour, -6, CURRENT_TIMESTAMP()), DATEADD(hour, 18, CURRENT_TIMESTAMP()),
 312, 24, 287, 0, 0, NULL, '🪟', '#CC2927', '1.1.0',
 'HORIZON_CONTEXT_ADMIN', TRUE, NULL,
 DATEADD(day, -60, CURRENT_TIMESTAMP()), CURRENT_TIMESTAMP()),

-- Tableau Cloud
('conn-tab', 'Tableau', 'BI_TOOL', 'tableau-cloud-production',
 'https://10ay.online.tableau.com', 'ACTIVE', 'HOURLY',
 DATEADD(minute, -45, CURRENT_TIMESTAMP()), DATEADD(minute, 15, CURRENT_TIMESTAMP()),
 89, 0, 0, 89, 0, NULL, '📊', '#E97627', '1.3.0',
 'HORIZON_CONTEXT_ADMIN', TRUE, NULL,
 DATEADD(day, -45, CURRENT_TIMESTAMP()), CURRENT_TIMESTAMP()),

-- Power BI
('conn-pbi', 'Power BI', 'BI_TOOL', 'powerbi-premium-workspace',
 'https://app.powerbi.com/groups/***', 'ACTIVE', 'HOURLY',
 DATEADD(minute, -20, CURRENT_TIMESTAMP()), DATEADD(minute, 40, CURRENT_TIMESTAMP()),
 67, 0, 0, 67, 0, NULL, '📈', '#F2C811', '1.0.3',
 'HORIZON_CONTEXT_ADMIN', TRUE, NULL,
 DATEADD(day, -30, CURRENT_TIMESTAMP()), CURRENT_TIMESTAMP()),

-- dbt Cloud
('conn-dbt', 'dbt Cloud', 'PIPELINE', 'dbt-analytics-engineering',
 'https://cloud.getdbt.com/accounts/***', 'ACTIVE', 'DAILY',
 DATEADD(hour, -1, CURRENT_TIMESTAMP()), DATEADD(hour, 23, CURRENT_TIMESTAMP()),
 156, 62, 891, 0, 62, NULL, '🔧', '#FF694A', '1.1.2',
 'HORIZON_CONTEXT_ADMIN', TRUE, NULL,
 DATEADD(day, -75, CURRENT_TIMESTAMP()), CURRENT_TIMESTAMP()),

-- Looker (PuPr — paused per PrPr scope decisions)
('conn-look', 'Looker', 'BI_TOOL', 'looker-enterprise',
 'https://***.looker.com', 'PAUSED', 'DAILY',
 NULL, NULL,
 0, 0, 0, 0, 0,
 'Connector development in progress — targeted for Public Preview (fall 2026)',
 '🔍', '#4285F4', '0.9.0', NULL, FALSE,
 'Looker connector is in PuPr engineering backlog. BigQuery/Looker connectors targeted for summer/fall 2026 wave per field guidance.',
 DATEADD(day, -10, CURRENT_TIMESTAMP()), CURRENT_TIMESTAMP()),

-- Databricks (PuPr — explicitly deferred per PrPr scope)
('conn-dbx', 'Databricks', 'CLOUD_WAREHOUSE', 'databricks-ml-workspace',
 'https://***.azuredatabricks.net', 'PAUSED', 'DAILY',
 NULL, NULL,
 0, 0, 0, 0, 0,
 'BigQuery and Databricks not part of May 2026 PrPr — targeted for summer 2026',
 '🧱', '#FF3621', '0.8.0', NULL, FALSE,
 'Per May 2026 field guidance: Databricks/BigQuery customers told these are not day-one PrPr items. Expected summer/fall 2026.',
 DATEADD(day, -5, CURRENT_TIMESTAMP()), CURRENT_TIMESTAMP());

-- ============================================================================
-- SEED DATA: CATALOG OBJECTS — External Sources
-- ============================================================================

INSERT INTO EXT_CATALOG_OBJECTS
(OBJECT_ID, CONNECTOR_ID, OBJECT_TYPE, QUALIFIED_NAME, SOURCE_SYSTEM, SOURCE_LAYER,
 DATABASE_NAME, SCHEMA_NAME, TABLE_NAME, COLUMN_NAME, DATA_TYPE,
 DESCRIPTION, DESCRIPTION_SOURCE, SENSITIVITY_CLASS, IS_PII, PII_TYPE,
 POPULARITY_SCORE, QUERY_COUNT_30D, USER_COUNT_30D, DOWNSTREAM_BI_COUNT, UPSTREAM_SOURCE_COUNT,
 OWNER_EMAIL, OWNER_TEAM, SNOWFLAKE_OBJECT_REF, HAS_GOVERNANCE_GAP, IS_ORPHANED)
VALUES

-- ── PostgreSQL: public schema ──────────────────────────────────────────────

('pg-customers', 'conn-pg', 'TABLE', 'postgres.public.customers',
 'PostgreSQL', 'EXTERNAL', 'postgres', 'public', 'customers', NULL, NULL,
 'Master customer records for all active and historical accounts. Source of truth for CRM identity resolution.',
 'MANUAL', 'CONFIDENTIAL', FALSE, NULL,
 78.4, 1240, 34, 4, 0,
 'data-eng@company.com', 'Data Engineering',
 'RAW_DEV.SALESFORCE.ACCOUNT', FALSE, FALSE),

('pg-customers-email', 'conn-pg', 'COLUMN', 'postgres.public.customers.email',
 'PostgreSQL', 'EXTERNAL', 'postgres', 'public', 'customers', 'email', 'VARCHAR(255)',
 'Primary contact email address for the customer account.',
 'MANUAL', 'CONFIDENTIAL', TRUE, 'EMAIL',
 68.2, 980, 28, 3, 0,
 'data-eng@company.com', 'Data Engineering',
 NULL, FALSE, FALSE),

('pg-customers-name', 'conn-pg', 'COLUMN', 'postgres.public.customers.full_name',
 'PostgreSQL', 'EXTERNAL', 'postgres', 'public', 'customers', 'full_name', 'VARCHAR(200)',
 'Full legal name of the customer, used for identity verification and CRM records.',
 'AI_GENERATED', 'CONFIDENTIAL', TRUE, 'NAME',
 65.1, 1100, 31, 4, 0,
 'data-eng@company.com', 'Data Engineering',
 NULL, FALSE, FALSE),

('pg-customers-phone', 'conn-pg', 'COLUMN', 'postgres.public.customers.phone',
 'PostgreSQL', 'EXTERNAL', 'postgres', 'public', 'customers', 'phone', 'VARCHAR(20)',
 NULL,
 'EMPTY', 'CONFIDENTIAL', TRUE, 'PHONE',
 42.0, 320, 12, 1, 0,
 NULL, 'Data Engineering',
 NULL, TRUE, FALSE),

('pg-transactions', 'conn-pg', 'TABLE', 'postgres.public.transactions',
 'PostgreSQL', 'EXTERNAL', 'postgres', 'public', 'transactions', NULL, NULL,
 'All financial transactions between customers and the company. Includes order amounts, currencies, and status.',
 'MANUAL', 'CONFIDENTIAL', FALSE, NULL,
 91.2, 4420, 47, 6, 0,
 'data-eng@company.com', 'Data Engineering',
 'RAW_DEV.SAP.VBAK', FALSE, FALSE),

('pg-products', 'conn-pg', 'TABLE', 'postgres.public.products',
 'PostgreSQL', 'EXTERNAL', 'postgres', 'public', 'products', NULL, NULL,
 'Product catalog with pricing, SKU codes, and supplier relationships.',
 'MANUAL', 'INTERNAL', FALSE, NULL,
 55.7, 870, 22, 3, 0,
 'catalog-team@company.com', 'Product Catalog',
 'RAW_DEV.SAP.MARA', FALSE, FALSE),

('pg-employees', 'conn-pg', 'TABLE', 'postgres.public.employees',
 'PostgreSQL', 'EXTERNAL', 'postgres', 'public', 'employees', NULL, NULL,
 NULL,
 'EMPTY', 'RESTRICTED', TRUE, 'NAME,EMAIL,SALARY',
 44.3, 310, 8, 2, 0,
 NULL, NULL,
 'RAW_DEV.WORKDAY.WORKERS', TRUE, FALSE),

('pg-employees-salary', 'conn-pg', 'COLUMN', 'postgres.public.employees.salary',
 'PostgreSQL', 'EXTERNAL', 'postgres', 'public', 'employees', 'salary', 'DECIMAL(12,2)',
 NULL,
 'EMPTY', 'RESTRICTED', TRUE, 'SALARY',
 28.0, 95, 4, 1, 0,
 NULL, NULL,
 NULL, TRUE, FALSE),

('pg-orders', 'conn-pg', 'TABLE', 'postgres.public.orders',
 'PostgreSQL', 'EXTERNAL', 'postgres', 'public', 'orders', NULL, NULL,
 'Customer purchase orders linking customers, products, and assigned account managers.',
 'MANUAL', 'INTERNAL', FALSE, NULL,
 82.1, 3100, 41, 5, 2,
 'data-eng@company.com', 'Data Engineering',
 NULL, FALSE, FALSE),

('pg-customer-ltv', 'conn-pg', 'TABLE', 'postgres.analytics.customer_ltv',
 'PostgreSQL', 'EXTERNAL', 'postgres', 'analytics', 'customer_ltv', NULL, NULL,
 'Pre-computed lifetime value scores for customer segmentation and churn modeling.',
 'SOURCE_DOCS', 'INTERNAL', FALSE, NULL,
 61.8, 720, 19, 2, 1,
 'analytics@company.com', 'Analytics Engineering',
 NULL, FALSE, FALSE),

('pg-monthly-revenue', 'conn-pg', 'TABLE', 'postgres.analytics.monthly_revenue',
 'PostgreSQL', 'EXTERNAL', 'postgres', 'analytics', 'monthly_revenue', NULL, NULL,
 NULL,
 'EMPTY', 'INTERNAL', FALSE, NULL,
 14.2, 88, 5, 0, 1,
 NULL, NULL,
 NULL, TRUE, TRUE),

-- ── SQL Server: dbo schema ─────────────────────────────────────────────────

('sql-coa', 'conn-sql', 'TABLE', 'erp.dbo.chart_of_accounts',
 'Microsoft SQL Server', 'EXTERNAL', 'erp', 'dbo', 'chart_of_accounts', NULL, NULL,
 'Master chart of accounts for general ledger reporting. Defines account hierarchies used in all financial consolidations.',
 'MANUAL', 'INTERNAL', FALSE, NULL,
 52.4, 640, 18, 3, 0,
 'finance-ops@company.com', 'Finance Operations',
 'RAW_DEV.ORACLE.GL_JE_HEADERS', FALSE, FALSE),

('sql-journals', 'conn-sql', 'TABLE', 'erp.dbo.journal_entries',
 'Microsoft SQL Server', 'EXTERNAL', 'erp', 'dbo', 'journal_entries', NULL, NULL,
 'All accounting journal entries across all business units. Used for monthly close reporting and audit trails.',
 'MANUAL', 'CONFIDENTIAL', FALSE, NULL,
 74.9, 1820, 29, 4, 1,
 'finance-ops@company.com', 'Finance Operations',
 'RAW_DEV.ORACLE.GL_JE_HEADERS', FALSE, FALSE),

('sql-vendors', 'conn-sql', 'TABLE', 'erp.dbo.vendor_master',
 'Microsoft SQL Server', 'EXTERNAL', 'erp', 'dbo', 'vendor_master', NULL, NULL,
 NULL,
 'EMPTY', 'CONFIDENTIAL', FALSE, NULL,
 38.6, 420, 14, 2, 0,
 'procurement@company.com', 'Procurement',
 'RAW_DEV.SAP.LFA1', TRUE, FALSE),

('sql-po', 'conn-sql', 'TABLE', 'erp.dbo.purchase_orders',
 'Microsoft SQL Server', 'EXTERNAL', 'erp', 'dbo', 'purchase_orders', NULL, NULL,
 'Purchase orders raised against approved vendors. Linked to AP invoices for three-way matching.',
 'SOURCE_DOCS', 'INTERNAL', FALSE, NULL,
 61.2, 890, 22, 2, 1,
 'procurement@company.com', 'Procurement',
 'RAW_DEV.SAP.EKKO', FALSE, FALSE),

('sql-ap', 'conn-sql', 'TABLE', 'erp.dbo.ap_invoices',
 'Microsoft SQL Server', 'EXTERNAL', 'erp', 'dbo', 'ap_invoices', NULL, NULL,
 'Accounts payable invoices from vendors. Sensitive — contains payment terms and banking references.',
 'MANUAL', 'CONFIDENTIAL', FALSE, NULL,
 56.3, 740, 16, 3, 1,
 'finance-ops@company.com', 'Finance Operations',
 'RAW_DEV.ORACLE.AP_INVOICES', FALSE, FALSE),

('sql-ar', 'conn-sql', 'TABLE', 'erp.dbo.ar_invoices',
 'Microsoft SQL Server', 'EXTERNAL', 'erp', 'dbo', 'ar_invoices', NULL, NULL,
 'Accounts receivable invoices issued to customers. Drives revenue recognition and DSO calculations.',
 'MANUAL', 'CONFIDENTIAL', FALSE, NULL,
 68.7, 1120, 24, 3, 1,
 'finance-ops@company.com', 'Finance Operations',
 'RAW_DEV.ORACLE.AR_INVOICES', FALSE, FALSE),

('sql-headcount', 'conn-sql', 'TABLE', 'erp.hr.headcount',
 'Microsoft SQL Server', 'EXTERNAL', 'erp', 'hr', 'headcount', NULL, NULL,
 'Headcount snapshots by department and cost center. Used for workforce planning and budget variance.',
 'SOURCE_DOCS', 'INTERNAL', FALSE, NULL,
 47.1, 580, 15, 2, 0,
 'hr-analytics@company.com', 'HR Analytics',
 'RAW_DEV.WORKDAY.WORKERS', FALSE, FALSE),

('sql-payroll', 'conn-sql', 'TABLE', 'erp.hr.payroll',
 'Microsoft SQL Server', 'EXTERNAL', 'erp', 'hr', 'payroll', NULL, NULL,
 NULL,
 'EMPTY', 'RESTRICTED', TRUE, 'SALARY',
 22.8, 140, 5, 1, 0,
 NULL, NULL,
 NULL, TRUE, FALSE),

-- ── Tableau Cloud ──────────────────────────────────────────────────────────

('tab-rev-dash', 'conn-tab', 'DASHBOARD', 'tableau://Executive Suite/Executive Revenue Dashboard',
 'Tableau', 'BI', NULL, 'Executive Suite', 'Executive Revenue Dashboard', NULL, NULL,
 'Executive-level revenue dashboard showing YTD performance, quarterly trends, and regional breakdowns. Updates daily from Snowflake semantic views.',
 'MANUAL', 'CONFIDENTIAL', FALSE, NULL,
 94.7, 0, 0, 0, 3,
 'bi-team@company.com', 'Business Intelligence',
 'SEM_DEV.SAP.REVENUE_SUMMARY', FALSE, FALSE),

('tab-cust360', 'conn-tab', 'DASHBOARD', 'tableau://Executive Suite/Customer 360 View',
 'Tableau', 'BI', NULL, 'Executive Suite', 'Customer 360 View', NULL, NULL,
 'Unified customer view combining CRM, transaction history, and support interactions. Primary tool for account management teams.',
 'MANUAL', 'CONFIDENTIAL', FALSE, NULL,
 89.2, 0, 0, 0, 2,
 'bi-team@company.com', 'Business Intelligence',
 'SEM_DEV.SALESFORCE.CUSTOMER_HEALTH_SCORE', FALSE, FALSE),

('tab-board', 'conn-tab', 'DASHBOARD', 'tableau://Executive Suite/Board Summary KPIs',
 'Tableau', 'BI', NULL, 'Executive Suite', 'Board Summary KPIs', NULL, NULL,
 'Monthly board-level KPI summary. Restricted to C-suite and board members.',
 'MANUAL', 'RESTRICTED', FALSE, NULL,
 72.5, 0, 0, 0, 4,
 'cfo@company.com', 'Finance Leadership',
 NULL, FALSE, FALSE),

('tab-supply', 'conn-tab', 'DASHBOARD', 'tableau://Operations/Supply Chain Performance',
 'Tableau', 'BI', NULL, 'Operations', 'Supply Chain Performance', NULL, NULL,
 'End-to-end supply chain visibility covering procurement, inventory turns, and delivery SLA tracking.',
 'MANUAL', 'INTERNAL', FALSE, NULL,
 65.4, 0, 0, 0, 3,
 'bi-team@company.com', 'Business Intelligence',
 NULL, FALSE, FALSE),

('tab-hr', 'conn-tab', 'DASHBOARD', 'tableau://HR & Finance/HR Analytics',
 'Tableau', 'BI', NULL, 'HR & Finance', 'HR Analytics', NULL, NULL,
 'Headcount, attrition, tenure, and compensation band analytics. Feeds quarterly workforce review.',
 'MANUAL', 'RESTRICTED', FALSE, NULL,
 58.1, 0, 0, 0, 2,
 'hr-analytics@company.com', 'HR Analytics',
 'SEM_DEV.WORKDAY.WORKFORCE_SUMMARY', FALSE, FALSE),

('tab-finance', 'conn-tab', 'DASHBOARD', 'tableau://HR & Finance/Finance Monthly Close',
 'Tableau', 'BI', NULL, 'HR & Finance', 'Finance Monthly Close', NULL, NULL,
 'Month-end close package with P&L, balance sheet, and variance to budget. Generated on business day 3.',
 'MANUAL', 'CONFIDENTIAL', FALSE, NULL,
 66.9, 0, 0, 0, 3,
 'finance-ops@company.com', 'Finance Operations',
 NULL, FALSE, FALSE),

('tab-acquisition', 'conn-tab', 'DASHBOARD', 'tableau://Operations/Customer Acquisition Funnel',
 'Tableau', 'BI', NULL, 'Operations', 'Customer Acquisition Funnel', NULL, NULL,
 NULL,
 'EMPTY', 'INTERNAL', FALSE, NULL,
 31.2, 0, 0, 0, 1,
 NULL, NULL,
 NULL, TRUE, FALSE),

-- ── Power BI ───────────────────────────────────────────────────────────────

('pbi-sales', 'conn-pbi', 'REPORT', 'powerbi://Premium/Sales & Revenue Analytics',
 'Power BI', 'BI', NULL, 'Premium Workspace', 'Sales & Revenue Analytics', NULL, NULL,
 'Sales performance tracking with pipeline, closed-won, and revenue attainment against quarterly targets.',
 'SOURCE_DOCS', 'CONFIDENTIAL', FALSE, NULL,
 76.3, 0, 0, 0, 2,
 'bi-team@company.com', 'Business Intelligence',
 NULL, FALSE, FALSE),

('pbi-finance', 'conn-pbi', 'REPORT', 'powerbi://Premium/Finance Monthly Reporting',
 'Power BI', 'BI', NULL, 'Premium Workspace', 'Finance Monthly Reporting', NULL, NULL,
 'Official finance monthly reporting pack distributed to leadership. Sourced from Snowflake curated and semantic layers.',
 'MANUAL', 'CONFIDENTIAL', FALSE, NULL,
 81.7, 0, 0, 0, 3,
 'finance-ops@company.com', 'Finance Operations',
 NULL, FALSE, FALSE),

('pbi-hr', 'conn-pbi', 'REPORT', 'powerbi://Premium/HR Headcount Dashboard',
 'Power BI', 'BI', NULL, 'Premium Workspace', 'HR Headcount Dashboard', NULL, NULL,
 NULL,
 'EMPTY', 'RESTRICTED', FALSE, NULL,
 42.4, 0, 0, 0, 1,
 NULL, 'HR Analytics',
 NULL, TRUE, FALSE),

('pbi-customer', 'conn-pbi', 'REPORT', 'powerbi://Premium/Customer Acquisition Report',
 'Power BI', 'BI', NULL, 'Premium Workspace', 'Customer Acquisition Report', NULL, NULL,
 'New customer acquisition funnel analysis by channel, geography, and segment.',
 'AI_GENERATED', 'INTERNAL', FALSE, NULL,
 53.8, 0, 0, 0, 2,
 'marketing@company.com', 'Marketing Analytics',
 NULL, FALSE, FALSE),

-- ── dbt Cloud ──────────────────────────────────────────────────────────────

('dbt-stg-cust', 'conn-dbt', 'MODEL', 'dbt://analytics/staging/stg_customers',
 'dbt Cloud', 'PIPELINE', 'analytics', 'staging', 'stg_customers', NULL, NULL,
 'Staging model that standardizes and deduplicates customer records from the PostgreSQL operational database. Applies column naming conventions and data type casting.',
 'DBT_YAML', 'INTERNAL', FALSE, NULL,
 72.1, 480, 12, 3, 1,
 'analytics-eng@company.com', 'Analytics Engineering',
 'RAW_DEV.SALESFORCE.ACCOUNT', FALSE, FALSE),

('dbt-stg-txn', 'conn-dbt', 'MODEL', 'dbt://analytics/staging/stg_transactions',
 'dbt Cloud', 'PIPELINE', 'analytics', 'staging', 'stg_transactions', NULL, NULL,
 'Staging model for raw transaction data. Applies currency normalization and filters out test/void transactions.',
 'DBT_YAML', 'INTERNAL', FALSE, NULL,
 85.6, 1240, 18, 4, 1,
 'analytics-eng@company.com', 'Analytics Engineering',
 'RAW_DEV.SAP.VBAK', FALSE, FALSE),

('dbt-stg-emp', 'conn-dbt', 'MODEL', 'dbt://analytics/staging/stg_employees',
 'dbt Cloud', 'PIPELINE', 'analytics', 'staging', 'stg_employees', NULL, NULL,
 NULL,
 'EMPTY', 'RESTRICTED', TRUE, 'NAME,EMAIL,SALARY',
 38.4, 210, 7, 2, 1,
 NULL, 'Analytics Engineering',
 NULL, TRUE, FALSE),

('dbt-stg-vendor', 'conn-dbt', 'MODEL', 'dbt://analytics/staging/stg_vendors',
 'dbt Cloud', 'PIPELINE', 'analytics', 'staging', 'stg_vendors', NULL, NULL,
 'Staging model for vendor master data from SQL Server ERP. Enriches with DUNS numbers and risk classifications.',
 'DBT_YAML', 'INTERNAL', FALSE, NULL,
 41.2, 290, 9, 2, 1,
 'analytics-eng@company.com', 'Analytics Engineering',
 NULL, FALSE, FALSE),

('dbt-dim-cust', 'conn-dbt', 'MODEL', 'dbt://analytics/marts/dim_customer',
 'dbt Cloud', 'PIPELINE', 'analytics', 'marts', 'dim_customer', NULL, NULL,
 'Customer dimension with SCD Type 2 history tracking. Enriched with LTV scores, segment assignments, and churn risk bands.',
 'DBT_YAML', 'INTERNAL', FALSE, NULL,
 88.4, 2100, 31, 4, 2,
 'analytics-eng@company.com', 'Analytics Engineering',
 'CURATED_DEV.SALESFORCE.DIM_CUSTOMER', FALSE, FALSE),

('dbt-fct-rev', 'conn-dbt', 'MODEL', 'dbt://analytics/marts/fct_revenue',
 'dbt Cloud', 'PIPELINE', 'analytics', 'marts', 'fct_revenue', NULL, NULL,
 'Revenue fact table joining orders, line items, and product dimensions. Grain: one row per order line per day.',
 'DBT_YAML', 'INTERNAL', FALSE, NULL,
 92.1, 3400, 44, 6, 3,
 'analytics-eng@company.com', 'Analytics Engineering',
 'CURATED_DEV.SAP.FACT_REVENUE', FALSE, FALSE),

('dbt-dim-acct', 'conn-dbt', 'MODEL', 'dbt://analytics/marts/dim_account',
 'dbt Cloud', 'PIPELINE', 'analytics', 'marts', 'dim_account', NULL, NULL,
 'Chart of accounts dimension with GL account hierarchy and reporting segment mappings.',
 'DBT_YAML', 'INTERNAL', FALSE, NULL,
 49.3, 380, 11, 2, 1,
 'analytics-eng@company.com', 'Analytics Engineering',
 'CURATED_DEV.ORACLE.DIM_ACCOUNT', FALSE, FALSE),

('dbt-dim-emp', 'conn-dbt', 'MODEL', 'dbt://analytics/marts/dim_employee',
 'dbt Cloud', 'PIPELINE', 'analytics', 'marts', 'dim_employee', NULL, NULL,
 NULL,
 'EMPTY', 'RESTRICTED', TRUE, 'NAME,EMAIL,SALARY',
 33.7, 180, 6, 2, 2,
 NULL, NULL,
 'CURATED_DEV.WORKDAY.DIM_EMPLOYEE', TRUE, FALSE),

-- ── Snowflake Native Objects (enrolled in unified catalog) ─────────────────

('sf-raw-account', 'conn-sf', 'TABLE', 'RAW_DEV.SALESFORCE.ACCOUNT',
 'Snowflake', 'RAW', 'RAW_DEV', 'SALESFORCE', 'ACCOUNT', NULL, NULL,
 'Salesforce Account records ingested via Snowpipe. SCD Type 2 with _VALID_FROM/_VALID_TO tracking.',
 'MANUAL', 'CONFIDENTIAL', FALSE, NULL,
 83.2, 2800, 38, 5, 2,
 'data-eng@company.com', 'Data Engineering',
 NULL, FALSE, FALSE),

('sf-curated-dim-cust', 'conn-sf', 'TABLE', 'CURATED_DEV.SALESFORCE.DIM_CUSTOMER',
 'Snowflake', 'CURATED', 'CURATED_DEV', 'SALESFORCE', 'DIM_CUSTOMER', NULL, NULL,
 'Customer dimension (Dynamic Table, lag=1h). Enriched with LTV tier, segment, and account health score. Source: SALESFORCE.ACCOUNT + dbt dim_customer.',
 'MANUAL', 'CONFIDENTIAL', FALSE, NULL,
 91.8, 4200, 52, 5, 3,
 'data-eng@company.com', 'Data Engineering',
 NULL, FALSE, FALSE),

('sf-raw-vbak', 'conn-sf', 'TABLE', 'RAW_DEV.SAP.VBAK',
 'Snowflake', 'RAW', 'RAW_DEV', 'SAP', 'VBAK', NULL, NULL,
 'SAP Sales Order Header table. Contains order-level data including sold-to party, order type, and creation date.',
 'SOURCE_DOCS', 'INTERNAL', FALSE, NULL,
 78.6, 2400, 33, 4, 1,
 'data-eng@company.com', 'Data Engineering',
 NULL, FALSE, FALSE),

('sf-curated-fact-rev', 'conn-sf', 'TABLE', 'CURATED_DEV.SAP.FACT_REVENUE',
 'Snowflake', 'CURATED', 'CURATED_DEV', 'SAP', 'FACT_REVENUE', NULL, NULL,
 'Revenue fact table (Dynamic Table, lag=1h). Grain: order line. Joins VBAK, VBAP, KNA1, MARA. Primary source for all revenue reporting.',
 'MANUAL', 'CONFIDENTIAL', FALSE, NULL,
 95.4, 6100, 67, 7, 4,
 'data-eng@company.com', 'Data Engineering',
 NULL, FALSE, FALSE),

('sf-sem-revenue', 'conn-sf', 'VIEW', 'SEM_DEV.SAP.REVENUE_SUMMARY',
 'Snowflake', 'SEMANTIC', 'SEM_DEV', 'SAP', 'REVENUE_SUMMARY', NULL, NULL,
 'Native Semantic View providing certified revenue metrics: gross_revenue, net_revenue, discount_amount, refund_amount. Cortex Analyst-ready.',
 'MANUAL', 'INTERNAL', FALSE, NULL,
 97.2, 8400, 89, 8, 2,
 'bi-team@company.com', 'Business Intelligence',
 NULL, FALSE, FALSE),

('sf-raw-workers', 'conn-sf', 'TABLE', 'RAW_DEV.WORKDAY.WORKERS',
 'Snowflake', 'RAW', 'RAW_DEV', 'WORKDAY', 'WORKERS', NULL, NULL,
 'Workday HCM worker records. Contains employee demographics, position, compensation, and organizational hierarchy.',
 'MANUAL', 'RESTRICTED', TRUE, 'NAME,EMAIL,SALARY',
 61.3, 840, 14, 3, 2,
 'hr-analytics@company.com', 'HR Analytics',
 NULL, FALSE, FALSE),

('sf-curated-dim-emp', 'conn-sf', 'TABLE', 'CURATED_DEV.WORKDAY.DIM_EMPLOYEE',
 'Snowflake', 'CURATED', 'CURATED_DEV', 'WORKDAY', 'DIM_EMPLOYEE', NULL, NULL,
 'Employee dimension (Dynamic Table, lag=4h). Active employees with anonymized compensation bands, department hierarchy, and tenure cohorts.',
 'MANUAL', 'RESTRICTED', FALSE, NULL,
 73.8, 1100, 19, 3, 2,
 'hr-analytics@company.com', 'HR Analytics',
 NULL, FALSE, FALSE),

('sf-raw-gl', 'conn-sf', 'TABLE', 'RAW_DEV.ORACLE.GL_JE_HEADERS',
 'Snowflake', 'RAW', 'RAW_DEV', 'ORACLE', 'GL_JE_HEADERS', NULL, NULL,
 'Oracle EBS General Ledger journal entry headers. Linked to GL_JE_LINES for full entry detail.',
 'SOURCE_DOCS', 'CONFIDENTIAL', FALSE, NULL,
 64.7, 920, 16, 3, 1,
 'finance-ops@company.com', 'Finance Operations',
 NULL, FALSE, FALSE),

('sf-curated-fact-je', 'conn-sf', 'TABLE', 'CURATED_DEV.ORACLE.FACT_JOURNAL_ENTRIES',
 'Snowflake', 'CURATED', 'CURATED_DEV', 'ORACLE', 'FACT_JOURNAL_ENTRIES', NULL, NULL,
 'Journal entries fact table (Dynamic Table, lag=24h). Joins GL_JE_HEADERS and GL_JE_LINES with chart of accounts dimension.',
 'MANUAL', 'CONFIDENTIAL', FALSE, NULL,
 71.4, 1280, 21, 3, 2,
 'finance-ops@company.com', 'Finance Operations',
 NULL, FALSE, FALSE),

('sf-sem-workforce', 'conn-sf', 'VIEW', 'SEM_DEV.WORKDAY.WORKFORCE_SUMMARY',
 'Snowflake', 'SEMANTIC', 'SEM_DEV', 'WORKDAY', 'WORKFORCE_SUMMARY', NULL, NULL,
 'Certified workforce metrics semantic view. Provides headcount, attrition_rate, avg_tenure_years with RBAC ensuring anonymization below 5-person cohorts.',
 'MANUAL', 'RESTRICTED', FALSE, NULL,
 69.2, 620, 11, 2, 1,
 'hr-analytics@company.com', 'HR Analytics',
 NULL, FALSE, FALSE);

-- ============================================================================
-- SEED DATA: CROSS-PLATFORM LINEAGE
-- Paths represent end-to-end data journeys from external sources to BI
-- ============================================================================

INSERT INTO EXT_COLUMN_LINEAGE
(LINEAGE_ID, SOURCE_OBJECT_ID, TARGET_OBJECT_ID,
 SOURCE_SYSTEM, TARGET_SYSTEM, SOURCE_LAYER, TARGET_LAYER,
 LINEAGE_TYPE, TRANSFORMATION_DESC, CONFIDENCE_SCORE, IS_COLUMN_LEVEL, HOP_NUMBER, LINEAGE_PATH_ID)
VALUES

-- PATH A: Customer 360 (PostgreSQL → dbt → Snowflake RAW → CURATED → Tableau + Power BI)
('lin-a1', 'pg-customers', 'dbt-stg-cust',
 'PostgreSQL', 'dbt Cloud', 'EXTERNAL', 'PIPELINE',
 'INGESTED', 'dbt stg_customers reads from PostgreSQL public.customers via Snowflake external connection. Applies deduplication on customer_id and standardizes column names.', 0.98, FALSE, 1, 'path-cust-360'),

('lin-a2', 'dbt-stg-cust', 'sf-raw-account',
 'dbt Cloud', 'Snowflake', 'PIPELINE', 'RAW',
 'TRANSFORMED', 'dbt model output materialized into RAW_DEV.SALESFORCE.ACCOUNT. Merges with Salesforce API data where available; PostgreSQL is authoritative for CRM identity.', 0.95, FALSE, 2, 'path-cust-360'),

('lin-a3', 'sf-raw-account', 'sf-curated-dim-cust',
 'Snowflake', 'Snowflake', 'RAW', 'CURATED',
 'TRANSFORMED', 'Dynamic Table CURATED_DEV.SALESFORCE.DIM_CUSTOMER joins RAW ACCOUNT with LTV scores and segment models. Lag: 1 hour. SCD Type 2 applied.', 1.0, FALSE, 3, 'path-cust-360'),

('lin-a4', 'sf-curated-dim-cust', 'tab-cust360',
 'Snowflake', 'Tableau', 'CURATED', 'BI',
 'CONSUMED', 'Tableau Customer 360 View uses DIM_CUSTOMER as its primary data source. Joins with SEM_DEV semantic views for enriched metrics.', 0.97, FALSE, 4, 'path-cust-360'),

('lin-a5', 'sf-curated-dim-cust', 'pbi-customer',
 'Snowflake', 'Power BI', 'CURATED', 'BI',
 'CONSUMED', 'Power BI Customer Acquisition Report connects via DirectQuery to CURATED_DEV.SALESFORCE.DIM_CUSTOMER.', 0.94, FALSE, 4, 'path-cust-360'),

('lin-a6', 'dbt-dim-cust', 'sf-curated-dim-cust',
 'dbt Cloud', 'Snowflake', 'PIPELINE', 'CURATED',
 'TRANSFORMED', 'dbt marts/dim_customer enriches staging data with LTV tier calculations before final materialization in Snowflake CURATED layer.', 0.92, FALSE, 3, 'path-cust-360'),

-- PATH B: Revenue (PostgreSQL transactions → dbt → Snowflake → Semantic → Tableau + Power BI)
('lin-b1', 'pg-transactions', 'dbt-stg-txn',
 'PostgreSQL', 'dbt Cloud', 'EXTERNAL', 'PIPELINE',
 'INGESTED', 'dbt stg_transactions reads from PostgreSQL public.transactions. Applies currency normalization (all amounts converted to USD), filters void/test transactions.', 0.98, FALSE, 1, 'path-revenue'),

('lin-b2', 'dbt-stg-txn', 'sf-raw-vbak',
 'dbt Cloud', 'Snowflake', 'PIPELINE', 'RAW',
 'TRANSFORMED', 'Transaction data materialized into SAP VBAK format in RAW_DEV. Merged with SAP direct export where available; PostgreSQL transactions are authoritative for e-commerce channel.', 0.93, FALSE, 2, 'path-revenue'),

('lin-b3', 'sf-raw-vbak', 'sf-curated-fact-rev',
 'Snowflake', 'Snowflake', 'RAW', 'CURATED',
 'TRANSFORMED', 'FACT_REVENUE Dynamic Table joins VBAK (header) + VBAP (line items) + KNA1 (customer) + MARA (material). Lag: 1 hour. Revenue recognition rules applied.', 1.0, FALSE, 3, 'path-revenue'),

('lin-b4', 'dbt-fct-rev', 'sf-curated-fact-rev',
 'dbt Cloud', 'Snowflake', 'PIPELINE', 'CURATED',
 'TRANSFORMED', 'dbt fct_revenue adds marketing attribution, discount tier logic, and segment enrichment before feeding CURATED FACT_REVENUE.', 0.91, FALSE, 3, 'path-revenue'),

('lin-b5', 'sf-curated-fact-rev', 'sf-sem-revenue',
 'Snowflake', 'Snowflake', 'CURATED', 'SEMANTIC',
 'PUBLISHED', 'REVENUE_SUMMARY Semantic View exposes certified gross_revenue, net_revenue, and discount_amount metrics. RBAC: ANALYST+ roles.', 1.0, FALSE, 4, 'path-revenue'),

('lin-b6', 'sf-sem-revenue', 'tab-rev-dash',
 'Snowflake', 'Tableau', 'SEMANTIC', 'BI',
 'CONSUMED', 'Tableau Executive Revenue Dashboard queries SEM_DEV.SAP.REVENUE_SUMMARY via Snowflake connector. Certified semantic layer ensures consistent metric definitions across all consumers.', 0.99, FALSE, 5, 'path-revenue'),

('lin-b7', 'sf-sem-revenue', 'tab-board',
 'Snowflake', 'Tableau', 'SEMANTIC', 'BI',
 'CONSUMED', 'Board Summary KPIs dashboard pulls revenue KPIs directly from the certified semantic view. Restricted to C-suite roles.', 0.97, FALSE, 5, 'path-revenue'),

('lin-b8', 'sf-curated-fact-rev', 'pbi-finance',
 'Snowflake', 'Power BI', 'CURATED', 'BI',
 'CONSUMED', 'Finance Monthly Reporting in Power BI uses FACT_REVENUE via Import mode for offline distribution to finance leadership.', 0.95, FALSE, 4, 'path-revenue'),

('lin-b9', 'sf-curated-fact-rev', 'pbi-sales',
 'Snowflake', 'Power BI', 'CURATED', 'BI',
 'CONSUMED', 'Power BI Sales & Revenue Analytics DirectQuery connection to FACT_REVENUE for real-time pipeline tracking.', 0.96, FALSE, 4, 'path-revenue'),

-- PATH C: Finance / GL (SQL Server → Snowflake → Curated → Power BI + Tableau)
('lin-c1', 'sql-journals', 'sf-raw-gl',
 'Microsoft SQL Server', 'Snowflake', 'EXTERNAL', 'RAW',
 'INGESTED', 'Journal entries loaded from SQL Server ERP into Snowflake RAW via scheduled batch connector (daily). Schema mapped from SQL Server dbo layout to Oracle EBS column naming.', 0.96, FALSE, 1, 'path-finance'),

('lin-c2', 'sf-raw-gl', 'sf-curated-fact-je',
 'Snowflake', 'Snowflake', 'RAW', 'CURATED',
 'TRANSFORMED', 'FACT_JOURNAL_ENTRIES Dynamic Table joins GL headers with line items and dim_account hierarchy. Applies cost center rollup rules for management reporting.', 1.0, FALSE, 2, 'path-finance'),

('lin-c3', 'sf-curated-fact-je', 'pbi-finance',
 'Snowflake', 'Power BI', 'CURATED', 'BI',
 'CONSUMED', 'Finance Monthly Reporting merges FACT_JOURNAL_ENTRIES with FACT_REVENUE for full P&L pack generation.', 0.94, FALSE, 3, 'path-finance'),

('lin-c4', 'sf-curated-fact-je', 'tab-finance',
 'Snowflake', 'Tableau', 'CURATED', 'BI',
 'CONSUMED', 'Tableau Finance Monthly Close workbook pulls journal entry data for variance analysis and actuals vs budget views.', 0.93, FALSE, 3, 'path-finance'),

('lin-c5', 'sql-coa', 'sf-raw-gl',
 'Microsoft SQL Server', 'Snowflake', 'EXTERNAL', 'RAW',
 'INGESTED', 'Chart of accounts dimension loaded alongside journal entries. Provides account hierarchy for GL rollup reporting.', 0.95, FALSE, 1, 'path-finance'),

-- PATH D: Workforce (SQL Server HR + PostgreSQL → Snowflake → Curated → Tableau + Power BI)
('lin-d1', 'sql-headcount', 'sf-raw-workers',
 'Microsoft SQL Server', 'Snowflake', 'EXTERNAL', 'RAW',
 'INGESTED', 'HR headcount snapshots from SQL Server loaded into Snowflake WORKDAY.WORKERS format (unified HR schema). Batch daily load.', 0.92, FALSE, 1, 'path-workforce'),

('lin-d2', 'pg-employees', 'sf-raw-workers',
 'PostgreSQL', 'Snowflake', 'EXTERNAL', 'RAW',
 'INGESTED', 'PostgreSQL operational employee records merged with SQL Server HR data. PostgreSQL is authoritative for contractor and temp worker records.', 0.88, FALSE, 1, 'path-workforce'),

('lin-d3', 'sf-raw-workers', 'sf-curated-dim-emp',
 'Snowflake', 'Snowflake', 'RAW', 'CURATED',
 'TRANSFORMED', 'DIM_EMPLOYEE Dynamic Table enriches raw worker records with anonymized compensation bands, tenure cohorts, and org hierarchy. Salary columns masked at CURATED layer.', 1.0, FALSE, 2, 'path-workforce'),

('lin-d4', 'dbt-dim-emp', 'sf-curated-dim-emp',
 'dbt Cloud', 'Snowflake', 'PIPELINE', 'CURATED',
 'TRANSFORMED', 'dbt dim_employee adds attrition risk scores and flight risk flags before final load to CURATED layer.', 0.89, FALSE, 2, 'path-workforce'),

('lin-d5', 'sf-curated-dim-emp', 'sf-sem-workforce',
 'Snowflake', 'Snowflake', 'CURATED', 'SEMANTIC',
 'PUBLISHED', 'WORKFORCE_SUMMARY Semantic View aggregates employee metrics with minimum cohort size of 5 (aggregation policy enforced).', 1.0, FALSE, 3, 'path-workforce'),

('lin-d6', 'sf-sem-workforce', 'tab-hr',
 'Snowflake', 'Tableau', 'SEMANTIC', 'BI',
 'CONSUMED', 'Tableau HR Analytics dashboard queries certified workforce semantic view. Aggregation policy prevents re-identification at sub-5-person granularity.', 0.97, FALSE, 4, 'path-workforce'),

('lin-d7', 'sf-curated-dim-emp', 'pbi-hr',
 'Snowflake', 'Power BI', 'CURATED', 'BI',
 'CONSUMED', 'Power BI HR Headcount Dashboard connects to CURATED DIM_EMPLOYEE for manager-level headcount reporting. Row access policy limits each manager to their org subtree.', 0.93, FALSE, 3, 'path-workforce');

-- ============================================================================
-- SEED DATA: USAGE STATS (14 days rolling window for key objects)
-- ============================================================================

INSERT INTO EXT_USAGE_STATS
(STAT_ID, OBJECT_ID, STAT_DATE,
 QUERY_COUNT, DISTINCT_USERS, BI_VIEWS, DATA_FRESHNESS_HOURS, AVG_QUERY_DURATION_MS, BYTES_SCANNED)
SELECT
    'stat-' || OBJECT_ID || '-' || TO_VARCHAR(stat_date, 'YYYYMMDD'),
    OBJECT_ID,
    stat_date,
    QUERY_COUNT,
    DISTINCT_USERS,
    BI_VIEWS,
    DATA_FRESHNESS_HOURS,
    AVG_QUERY_DURATION_MS,
    BYTES_SCANNED
FROM (
    SELECT
        obj.OBJECT_ID,
        DATEADD(day, -seq.n, CURRENT_DATE()) AS stat_date,
        -- Revenue semantic view: highest traffic
        CASE obj.OBJECT_ID
            WHEN 'sf-sem-revenue'       THEN ROUND(UNIFORM(240, 420, RANDOM()) * (1 + 0.1 * SIN(seq.n)))
            WHEN 'sf-curated-fact-rev'  THEN ROUND(UNIFORM(180, 320, RANDOM()))
            WHEN 'sf-curated-dim-cust'  THEN ROUND(UNIFORM(120, 200, RANDOM()))
            WHEN 'pg-transactions'      THEN ROUND(UNIFORM(80, 180, RANDOM()))
            WHEN 'dbt-fct-rev'          THEN ROUND(UNIFORM(60, 140, RANDOM()))
            ELSE 0
        END AS QUERY_COUNT,
        CASE obj.OBJECT_ID
            WHEN 'sf-sem-revenue'       THEN ROUND(UNIFORM(12, 28, RANDOM()))
            WHEN 'sf-curated-fact-rev'  THEN ROUND(UNIFORM(8, 22, RANDOM()))
            WHEN 'sf-curated-dim-cust'  THEN ROUND(UNIFORM(6, 18, RANDOM()))
            WHEN 'pg-transactions'      THEN ROUND(UNIFORM(4, 14, RANDOM()))
            WHEN 'dbt-fct-rev'          THEN ROUND(UNIFORM(3, 12, RANDOM()))
            ELSE 0
        END AS DISTINCT_USERS,
        CASE obj.OBJECT_ID
            WHEN 'tab-rev-dash'   THEN ROUND(UNIFORM(40, 120, RANDOM()))
            WHEN 'tab-cust360'    THEN ROUND(UNIFORM(30, 90, RANDOM()))
            WHEN 'pbi-finance'    THEN ROUND(UNIFORM(25, 80, RANDOM()))
            WHEN 'pbi-sales'      THEN ROUND(UNIFORM(20, 60, RANDOM()))
            WHEN 'tab-board'      THEN ROUND(UNIFORM(5, 25, RANDOM()))
            ELSE 0
        END AS BI_VIEWS,
        CASE obj.OBJECT_ID
            WHEN 'sf-sem-revenue'  THEN ROUND(UNIFORM(0.5, 2.0, RANDOM()), 1)
            WHEN 'sf-curated-fact-rev' THEN ROUND(UNIFORM(0.8, 2.5, RANDOM()), 1)
            ELSE ROUND(UNIFORM(2, 24, RANDOM()), 1)
        END AS DATA_FRESHNESS_HOURS,
        ROUND(UNIFORM(450, 8500, RANDOM())) AS AVG_QUERY_DURATION_MS,
        ROUND(UNIFORM(100000000, 50000000000, RANDOM())) AS BYTES_SCANNED
    FROM EXT_CATALOG_OBJECTS obj
    CROSS JOIN (
        SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS n
        FROM TABLE(GENERATOR(ROWCOUNT => 14))
    ) seq
    WHERE obj.OBJECT_ID IN (
        'sf-sem-revenue', 'sf-curated-fact-rev', 'sf-curated-dim-cust',
        'pg-transactions', 'dbt-fct-rev',
        'tab-rev-dash', 'tab-cust360', 'pbi-finance', 'pbi-sales', 'tab-board'
    )
);

-- ============================================================================
-- SEED DATA: GOVERNANCE RECOMMENDATIONS
-- ============================================================================

INSERT INTO EXT_GOVERNANCE_RECOMMENDATIONS
(REC_ID, OBJECT_ID, RECOMMENDATION_TYPE, PRIORITY, REASON, SUGGESTED_VALUE, AI_CONFIDENCE, STATUS)
VALUES

('rec-01', 'pg-employees', 'APPLY_MASK', 'CRITICAL',
 'Table postgres.public.employees contains SALARY column (PII type: SALARY) with no Snowflake masking policy. Table has 310 queries/month across 8 users and feeds 2 BI reports. High breach risk for compensation data.',
 'Apply MASKING POLICY salary_mask on mapped column RAW_DEV.WORKDAY.WORKERS.COMPENSATION to restrict to RESTRICTED_DATA_STEWARD role only.',
 0.96, 'OPEN'),

('rec-02', 'pg-employees-salary', 'ADD_TAG', 'CRITICAL',
 'Column postgres.public.employees.salary is a SALARY-type PII field with no Snowflake Horizon sensitivity tag applied to its mapped column. Tag-based masking policy cannot trigger without the tag.',
 'Apply TAG sensitivity_class = ''RESTRICTED'' and TAG pii_category = ''SALARY'' to RAW_DEV.WORKDAY.WORKERS.SALARY_AMOUNT.',
 0.97, 'OPEN'),

('rec-03', 'sql-payroll', 'ASSIGN_OWNER', 'HIGH',
 'Table erp.hr.payroll contains RESTRICTED-class data (salary information) but has no assigned data owner. Unowned restricted data is a compliance risk — no one accountable for access reviews or breach notification.',
 'Assign owner: hr-analytics@company.com (HR Analytics team owns all compensation data in the estate).',
 0.88, 'OPEN'),

('rec-04', 'pg-employees', 'ADD_DESCRIPTION', 'HIGH',
 'Table postgres.public.employees has no business description despite being a high-risk PII asset with 310 monthly queries. Missing descriptions in Universal Search reduce data trust and governance discoverability.',
 'Suggested description: "Operational employee master records for all active and terminated staff. Contains personally identifiable information including name, email, and compensation. Access is restricted to HR Analytics and authorized data stewards. Mapped to Snowflake RAW_DEV.WORKDAY.WORKERS."',
 0.91, 'OPEN'),

('rec-05', 'dbt-stg-emp', 'APPLY_MASK', 'HIGH',
 'dbt model stg_employees exposes NAME, EMAIL, and SALARY fields from source employee data. No masking policy exists on the Snowflake output table. 7 users queried this asset in the last 30 days including non-HR roles.',
 'Apply column-level masking on output table name, email, and salary columns. Use existing MASK_NAME and MASK_EMAIL policies from governance schema.',
 0.89, 'OPEN'),

('rec-06', 'pg-monthly-revenue', 'DEPRECATE', 'MEDIUM',
 'Table postgres.analytics.monthly_revenue has zero downstream BI consumers and only 88 queries from 5 users in the last 30 days. The same data is available with better lineage and governance through SEM_DEV.SAP.REVENUE_SUMMARY. Candidate for deprecation to reduce governance surface area.',
 'Notify owner of zero-consumer status. Propose deprecation in 30 days. Redirect consumers to certified semantic view SEM_DEV.SAP.REVENUE_SUMMARY.',
 0.84, 'OPEN'),

('rec-07', 'sql-vendors', 'ADD_DESCRIPTION', 'MEDIUM',
 'Table erp.dbo.vendor_master has CONFIDENTIAL classification but no description. 14 users query this asset monthly across procurement and finance teams.',
 'Suggested description: "Vendor master records from the ERP system including supplier contact information, payment terms, and risk classification. Confidential — contains banking reference data. Mapped to Snowflake RAW_DEV.SAP.LFA1."',
 0.87, 'OPEN'),

('rec-08', 'tab-acquisition', 'ASSIGN_OWNER', 'MEDIUM',
 'Tableau dashboard Customer Acquisition Funnel has no assigned owner. Dashboard has 31 monthly views but no one to maintain it, update data sources, or respond to consumer requests.',
 'Assign owner: marketing@company.com based on usage patterns (85% of consumers are in Marketing domain).',
 0.82, 'OPEN'),

('rec-09', 'pbi-hr', 'ADD_DESCRIPTION', 'MEDIUM',
 'Power BI report HR Headcount Dashboard has no business description and is RESTRICTED classification. Without a description, users cannot determine if this is the appropriate report for their use case.',
 'Suggested description: "Manager-level headcount reporting by department, cost center, and hiring status. Row access policy restricts each manager to their direct org subtree. Data updated daily from Snowflake CURATED_DEV.WORKDAY.DIM_EMPLOYEE."',
 0.85, 'OPEN'),

('rec-10', 'dbt-dim-emp', 'ASSIGN_OWNER', 'HIGH',
 'dbt model dim_employee handles RESTRICTED employee data (NAME, EMAIL, SALARY) but has no assigned owner in the catalog. Without an owner, access review and change management processes cannot function.',
 'Assign owner: hr-analytics@company.com. This model should require HR Analytics approval for any schema changes.',
 0.91, 'OPEN'),

('rec-11', 'pg-customers-phone', 'ADD_DESCRIPTION', 'LOW',
 'Column postgres.public.customers.phone is classified as PII (PHONE) but has no description. Low-priority as email and name columns are well-documented, but complete column documentation improves Universal Search ranking.',
 'Suggested description: "Primary phone number for customer contact. May be mobile or landline. Used for order confirmation notifications and account recovery workflows."',
 0.79, 'OPEN'),

('rec-12', 'sf-curated-fact-rev', 'CERTIFY', 'HIGH',
 'CURATED_DEV.SAP.FACT_REVENUE is the highest-queried table in the estate (6,100 queries/month, 67 users, 7 BI consumers) but has not been formally certified as a Data Product. Certification would improve trust, add SLA guarantees, and increase discoverability in Universal Search.',
 'Create Horizon Data Product for FACT_REVENUE with SLA: 99.5% freshness within 2 hours. Owner: data-eng@company.com.',
 0.93, 'OPEN'),

('rec-13', 'sf-sem-revenue', 'CERTIFY', 'HIGH',
 'SEM_DEV.SAP.REVENUE_SUMMARY serves 8 BI dashboards and 89 monthly users but is not published as a certified Data Product. Semantic views are the ideal Data Product layer — certifying this view would clarify it as the single source of truth for all revenue metrics.',
 'Publish as Horizon Data Product: "Certified Revenue Metrics". Add business glossary links for gross_revenue, net_revenue, discount_amount.',
 0.95, 'OPEN'),

('rec-14', 'sql-payroll', 'REVIEW_PII', 'CRITICAL',
 'SQL Server erp.hr.payroll has no description, no owner, and RESTRICTED classification with no corresponding masking policy on its mapped Snowflake column. This is the highest-risk unmitigated PII gap in the external estate.',
 'Immediate action: assign owner, add description, apply salary masking policy. Schedule access review within 7 days.',
 0.98, 'OPEN'),

('rec-15', 'dbt-stg-emp', 'ADD_DESCRIPTION', 'MEDIUM',
 'dbt staging model stg_employees has no description despite handling sensitive employee data from two source systems (PostgreSQL + SQL Server). dbt model descriptions are also shown in Select Star lineage view.',
 'Suggested description: "Staging model that standardizes employee records from PostgreSQL operational database and SQL Server ERP. Applies PII masking, deduplication by employee_id, and schema normalization. Output feeds dim_employee mart."',
 0.86, 'OPEN');

-- ============================================================================
-- VIEWS
-- ============================================================================

-- Unified Catalog — one row per object, enriched with governance context
CREATE OR REPLACE VIEW V_UNIFIED_CATALOG AS
SELECT
    o.OBJECT_ID,
    o.CONNECTOR_ID,
    o.OBJECT_TYPE,
    o.QUALIFIED_NAME,
    o.SOURCE_SYSTEM,
    o.SOURCE_LAYER,
    o.DATABASE_NAME,
    o.SCHEMA_NAME,
    o.TABLE_NAME,
    o.COLUMN_NAME,
    o.DATA_TYPE,
    o.DESCRIPTION,
    o.DESCRIPTION_SOURCE,
    o.SENSITIVITY_CLASS,
    o.IS_PII,
    o.PII_TYPE,
    o.POPULARITY_SCORE,
    o.QUERY_COUNT_30D,
    o.USER_COUNT_30D,
    o.DOWNSTREAM_BI_COUNT,
    o.OWNER_EMAIL,
    o.OWNER_TEAM,
    o.HAS_GOVERNANCE_GAP,
    o.IS_ORPHANED,
    o.LAST_CRAWLED_AT,
    -- Connector details
    c.STATUS              AS CONNECTOR_STATUS,
    c.CONNECTOR_ICON,
    c.CONNECTOR_COLOR,
    c.LAST_CRAWL_AT       AS CONNECTOR_LAST_CRAWL,
    -- Governance gap score (0-5 gaps)
    (CASE WHEN o.DESCRIPTION IS NULL OR o.DESCRIPTION = '' THEN 1 ELSE 0 END
   + CASE WHEN o.OWNER_EMAIL IS NULL THEN 1 ELSE 0 END
   + CASE WHEN o.SENSITIVITY_CLASS IS NULL THEN 1 ELSE 0 END
   + CASE WHEN o.IS_PII AND o.PII_TYPE IS NULL THEN 1 ELSE 0 END
   + CASE WHEN o.POPULARITY_SCORE > 50 AND o.DESCRIPTION IS NULL THEN 1 ELSE 0 END)
                          AS GOVERNANCE_GAP_SCORE,
    -- Downstream lineage count (out-edges)
    COALESCE(dl.DOWNSTREAM_COUNT, 0) AS TOTAL_DOWNSTREAM_EDGES,
    -- Upstream lineage count (in-edges)
    COALESCE(ul.UPSTREAM_COUNT, 0)   AS TOTAL_UPSTREAM_EDGES
FROM EXT_CATALOG_OBJECTS o
JOIN EXT_CONNECTORS c ON o.CONNECTOR_ID = c.CONNECTOR_ID
LEFT JOIN (
    SELECT SOURCE_OBJECT_ID, COUNT(*) AS DOWNSTREAM_COUNT
    FROM EXT_COLUMN_LINEAGE
    GROUP BY SOURCE_OBJECT_ID
) dl ON o.OBJECT_ID = dl.SOURCE_OBJECT_ID
LEFT JOIN (
    SELECT TARGET_OBJECT_ID, COUNT(*) AS UPSTREAM_COUNT
    FROM EXT_COLUMN_LINEAGE
    GROUP BY TARGET_OBJECT_ID
) ul ON o.OBJECT_ID = ul.TARGET_OBJECT_ID
COMMENT = 'Unified view of all catalog objects (Snowflake-native + external platforms) with governance scoring and lineage edge counts.';

-- Cross-Platform Lineage — enriched with source/target object details
CREATE OR REPLACE VIEW V_CROSS_PLATFORM_LINEAGE AS
SELECT
    l.LINEAGE_ID,
    l.LINEAGE_PATH_ID,
    l.HOP_NUMBER,
    l.LINEAGE_TYPE,
    l.CONFIDENCE_SCORE,
    -- Source node
    l.SOURCE_OBJECT_ID,
    src.OBJECT_TYPE        AS SOURCE_OBJECT_TYPE,
    src.QUALIFIED_NAME     AS SOURCE_QUALIFIED_NAME,
    src.SOURCE_SYSTEM      AS SOURCE_PLATFORM,
    src.SOURCE_LAYER       AS SOURCE_LAYER,
    src.TABLE_NAME         AS SOURCE_TABLE,
    src.CONNECTOR_ICON     AS SOURCE_ICON,
    src.CONNECTOR_COLOR    AS SOURCE_COLOR,
    src.POPULARITY_SCORE   AS SOURCE_POPULARITY,
    -- Target node
    l.TARGET_OBJECT_ID,
    tgt.OBJECT_TYPE        AS TARGET_OBJECT_TYPE,
    tgt.QUALIFIED_NAME     AS TARGET_QUALIFIED_NAME,
    tgt.SOURCE_SYSTEM      AS TARGET_PLATFORM,
    tgt.SOURCE_LAYER       AS TARGET_LAYER,
    tgt.TABLE_NAME         AS TARGET_TABLE,
    tgt.CONNECTOR_ICON     AS TARGET_ICON,
    tgt.CONNECTOR_COLOR    AS TARGET_COLOR,
    tgt.POPULARITY_SCORE   AS TARGET_POPULARITY,
    -- Edge details
    l.TRANSFORMATION_DESC,
    l.IS_COLUMN_LEVEL,
    l.CREATED_AT
FROM EXT_COLUMN_LINEAGE l
JOIN V_UNIFIED_CATALOG src ON l.SOURCE_OBJECT_ID = src.OBJECT_ID
JOIN V_UNIFIED_CATALOG tgt ON l.TARGET_OBJECT_ID = tgt.OBJECT_ID
COMMENT = 'Cross-platform lineage graph with enriched source/target metadata. Powers the Horizon Context lineage explorer.';

-- Usage Intelligence — aggregated usage metrics per object
CREATE OR REPLACE VIEW V_USAGE_INTELLIGENCE AS
SELECT
    o.OBJECT_ID,
    o.QUALIFIED_NAME,
    o.SOURCE_SYSTEM,
    o.SOURCE_LAYER,
    o.OBJECT_TYPE,
    o.POPULARITY_SCORE,
    o.QUERY_COUNT_30D,
    o.USER_COUNT_30D,
    o.DOWNSTREAM_BI_COUNT,
    o.IS_ORPHANED,
    o.OWNER_EMAIL,
    o.OWNER_TEAM,
    c.CONNECTOR_ICON,
    c.CONNECTOR_COLOR,
    -- 14-day aggregates from usage stats
    COALESCE(us.TOTAL_QUERIES_14D, 0)   AS TOTAL_QUERIES_14D,
    COALESCE(us.PEAK_DAILY_QUERIES, 0)  AS PEAK_DAILY_QUERIES,
    COALESCE(us.AVG_DAILY_QUERIES, 0)   AS AVG_DAILY_QUERIES,
    COALESCE(us.TOTAL_BI_VIEWS, 0)      AS TOTAL_BI_VIEWS_14D,
    COALESCE(us.AVG_FRESHNESS_HRS, 24)  AS AVG_FRESHNESS_HOURS,
    -- Tier classification
    CASE
        WHEN o.POPULARITY_SCORE >= 80 THEN 'PLATINUM'
        WHEN o.POPULARITY_SCORE >= 60 THEN 'GOLD'
        WHEN o.POPULARITY_SCORE >= 40 THEN 'SILVER'
        WHEN o.POPULARITY_SCORE >= 20 THEN 'BRONZE'
        ELSE 'UNCATEGORIZED'
    END AS POPULARITY_TIER
FROM EXT_CATALOG_OBJECTS o
JOIN EXT_CONNECTORS c ON o.CONNECTOR_ID = c.CONNECTOR_ID
LEFT JOIN (
    SELECT
        OBJECT_ID,
        SUM(QUERY_COUNT)                AS TOTAL_QUERIES_14D,
        MAX(QUERY_COUNT)                AS PEAK_DAILY_QUERIES,
        ROUND(AVG(QUERY_COUNT), 1)      AS AVG_DAILY_QUERIES,
        SUM(BI_VIEWS)                   AS TOTAL_BI_VIEWS,
        ROUND(AVG(DATA_FRESHNESS_HOURS), 1) AS AVG_FRESHNESS_HRS
    FROM EXT_USAGE_STATS
    WHERE STAT_DATE >= DATEADD(day, -14, CURRENT_DATE())
    GROUP BY OBJECT_ID
) us ON o.OBJECT_ID = us.OBJECT_ID
COMMENT = 'Usage intelligence view combining popularity scores with 14-day query telemetry and BI consumption data.';

-- Governance Gaps — objects needing attention
CREATE OR REPLACE VIEW V_GOVERNANCE_GAPS AS
SELECT
    o.OBJECT_ID,
    o.OBJECT_TYPE,
    o.QUALIFIED_NAME,
    o.SOURCE_SYSTEM,
    o.SOURCE_LAYER,
    o.SENSITIVITY_CLASS,
    o.IS_PII,
    o.PII_TYPE,
    o.POPULARITY_SCORE,
    o.QUERY_COUNT_30D,
    o.OWNER_EMAIL,
    o.IS_ORPHANED,
    c.CONNECTOR_ICON,
    CASE WHEN o.DESCRIPTION IS NULL OR o.DESCRIPTION = '' THEN TRUE ELSE FALSE END AS MISSING_DESCRIPTION,
    CASE WHEN o.OWNER_EMAIL IS NULL THEN TRUE ELSE FALSE END AS MISSING_OWNER,
    CASE WHEN o.SENSITIVITY_CLASS IS NULL THEN TRUE ELSE FALSE END AS MISSING_SENSITIVITY,
    CASE WHEN o.IS_PII AND o.PII_TYPE IS NULL THEN TRUE ELSE FALSE END AS UNDECLARED_PII,
    -- Risk score: PII * popularity * missing governance
    ROUND(
        (CASE WHEN o.IS_PII THEN 40 ELSE 0 END
       + CASE WHEN o.SENSITIVITY_CLASS IN ('RESTRICTED', 'CONFIDENTIAL') THEN 20 ELSE 0 END
       + CASE WHEN o.DESCRIPTION IS NULL OR o.DESCRIPTION = '' THEN 10 ELSE 0 END
       + CASE WHEN o.OWNER_EMAIL IS NULL THEN 20 ELSE 0 END
       + CASE WHEN o.QUERY_COUNT_30D > 500 THEN 10 ELSE 0 END)
    ) AS GOVERNANCE_RISK_SCORE,
    COUNT(r.REC_ID) AS OPEN_RECOMMENDATIONS
FROM EXT_CATALOG_OBJECTS o
JOIN EXT_CONNECTORS c ON o.CONNECTOR_ID = c.CONNECTOR_ID
LEFT JOIN EXT_GOVERNANCE_RECOMMENDATIONS r
    ON o.OBJECT_ID = r.OBJECT_ID AND r.STATUS = 'OPEN'
WHERE o.HAS_GOVERNANCE_GAP = TRUE
   OR o.IS_ORPHANED = TRUE
   OR o.IS_PII = TRUE
GROUP BY ALL
ORDER BY GOVERNANCE_RISK_SCORE DESC, o.POPULARITY_SCORE DESC
COMMENT = 'Governance gap analysis — all objects with missing metadata, unmitigated PII, or orphaned status. Risk-scored for prioritization.';

-- ============================================================================
-- STORED PROCEDURES
-- ============================================================================

-- Simulate a connector crawl (updates last_crawl_at, objects counts, status)
CREATE OR REPLACE PROCEDURE SP_SIMULATE_CONNECTOR_CRAWL(connector_id VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    conn_name VARCHAR;
    obj_count INTEGER;
    current_status VARCHAR;
    result_msg VARCHAR;
BEGIN
    -- Get current state
    SELECT CONNECTION_NAME, OBJECTS_TOTAL, STATUS
    INTO conn_name, obj_count, current_status
    FROM EXT_CONNECTORS
    WHERE CONNECTOR_ID = :connector_id;

    IF (current_status = 'PAUSED') THEN
        RETURN 'Connector ' || COALESCE(:conn_name, :connector_id) || ' is PAUSED — enable connector before crawling.';
    END IF;

    -- Simulate crawl: mark as CRAWLING
    UPDATE EXT_CONNECTORS
    SET STATUS = 'CRAWLING',
        UPDATED_AT = CURRENT_TIMESTAMP()
    WHERE CONNECTOR_ID = :connector_id;

    -- Simulate crawl completion with slightly updated counts
    UPDATE EXT_CONNECTORS
    SET STATUS = 'ACTIVE',
        LAST_CRAWL_AT = CURRENT_TIMESTAMP(),
        NEXT_CRAWL_AT = DATEADD(day, 1, CURRENT_TIMESTAMP()),
        OBJECTS_TOTAL = OBJECTS_TOTAL + FLOOR(UNIFORM(0, 12, RANDOM())),
        TABLES_DISCOVERED = TABLES_DISCOVERED + FLOOR(UNIFORM(0, 3, RANDOM())),
        COLUMNS_DISCOVERED = COLUMNS_DISCOVERED + FLOOR(UNIFORM(0, 25, RANDOM())),
        UPDATED_AT = CURRENT_TIMESTAMP()
    WHERE CONNECTOR_ID = :connector_id;

    SELECT CONNECTION_NAME || ': crawl completed. ' || OBJECTS_TOTAL || ' objects in catalog.'
    INTO result_msg
    FROM EXT_CONNECTORS
    WHERE CONNECTOR_ID = :connector_id;

    RETURN result_msg;
END;
$$
COMMENT = 'Simulates a Select Star metadata connector crawl. Updates connector status and object counts.';

-- Apply a governance recommendation (mark as ACCEPTED + apply simulated action)
CREATE OR REPLACE PROCEDURE SP_APPLY_RECOMMENDATION(rec_id VARCHAR, applied_by VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    rec_type VARCHAR;
    obj_name VARCHAR;
    suggested VARCHAR;
BEGIN
    SELECT r.RECOMMENDATION_TYPE, o.QUALIFIED_NAME, r.SUGGESTED_VALUE
    INTO rec_type, obj_name, suggested
    FROM EXT_GOVERNANCE_RECOMMENDATIONS r
    JOIN EXT_CATALOG_OBJECTS o ON r.OBJECT_ID = o.OBJECT_ID
    WHERE r.REC_ID = :rec_id;

    UPDATE EXT_GOVERNANCE_RECOMMENDATIONS
    SET STATUS = 'ACCEPTED',
        RESOLVED_AT = CURRENT_TIMESTAMP(),
        RESOLVED_BY = :applied_by
    WHERE REC_ID = :rec_id;

    -- Update the object's governance gap flag if description/owner was added
    IF (rec_type IN ('ADD_DESCRIPTION', 'ASSIGN_OWNER')) THEN
        UPDATE EXT_CATALOG_OBJECTS o
        SET HAS_GOVERNANCE_GAP = (
            SELECT CASE
                WHEN EXISTS (
                    SELECT 1 FROM EXT_GOVERNANCE_RECOMMENDATIONS r2
                    WHERE r2.OBJECT_ID = o.OBJECT_ID AND r2.STATUS = 'OPEN'
                ) THEN TRUE ELSE FALSE END
        )
        WHERE OBJECT_ID = (
            SELECT OBJECT_ID FROM EXT_GOVERNANCE_RECOMMENDATIONS WHERE REC_ID = :rec_id
        );
    END IF;

    RETURN 'Recommendation ' || :rec_id || ' (' || rec_type || ') applied to ' || COALESCE(obj_name, 'unknown') || ' by ' || :applied_by;
END;
$$
COMMENT = 'Marks a governance recommendation as accepted and updates the underlying catalog object.';

-- ============================================================================
-- GRANTS (adjust role to match your deployment)
-- ============================================================================

GRANT USAGE ON SCHEMA CURATED_DEV.HORIZON_CONTEXT TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL TABLES IN SCHEMA CURATED_DEV.HORIZON_CONTEXT TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL VIEWS IN SCHEMA CURATED_DEV.HORIZON_CONTEXT TO ROLE DATA_STEWARD;

GRANT USAGE ON SCHEMA CURATED_DEV.HORIZON_CONTEXT TO ROLE ANALYST;
GRANT SELECT ON ALL VIEWS IN SCHEMA CURATED_DEV.HORIZON_CONTEXT TO ROLE ANALYST;

GRANT ALL ON SCHEMA CURATED_DEV.HORIZON_CONTEXT TO ROLE DATA_ADMIN;
GRANT ALL ON ALL TABLES IN SCHEMA CURATED_DEV.HORIZON_CONTEXT TO ROLE DATA_ADMIN;
GRANT ALL ON ALL VIEWS IN SCHEMA CURATED_DEV.HORIZON_CONTEXT TO ROLE DATA_ADMIN;
GRANT ALL ON ALL PROCEDURES IN SCHEMA CURATED_DEV.HORIZON_CONTEXT TO ROLE DATA_ADMIN;

-- ============================================================================
-- SUMMARY
-- ============================================================================

SELECT
    'EXT_CONNECTORS'                AS OBJECT_NAME,
    COUNT(*)                        AS ROW_COUNT
FROM EXT_CONNECTORS
UNION ALL
SELECT 'EXT_CATALOG_OBJECTS', COUNT(*) FROM EXT_CATALOG_OBJECTS
UNION ALL
SELECT 'EXT_COLUMN_LINEAGE', COUNT(*) FROM EXT_COLUMN_LINEAGE
UNION ALL
SELECT 'EXT_USAGE_STATS', COUNT(*) FROM EXT_USAGE_STATS
UNION ALL
SELECT 'EXT_GOVERNANCE_RECOMMENDATIONS', COUNT(*) FROM EXT_GOVERNANCE_RECOMMENDATIONS
ORDER BY 1;
