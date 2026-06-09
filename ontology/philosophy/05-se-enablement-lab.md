# SE Enablement Lab — Data Cloud Architecture: Full-Stack Walkthrough

> **Audience:** Snowflake SEs and Solution Architects
> **Purpose:** Hands-on internalization of the DCA framework — its ontological foundations,
> architectural patterns, and the human dynamics that make or break deployments.
> **Format:** Read the context, run the SQL, discuss the questions.

---

## Before You Start

This lab is not primarily about SQL syntax. It is about developing the habit of asking
**ontological questions first** — about identity, ownership, meaning, and trust — before
reaching for a technical answer.

The SQL is the easy part. The hard part is knowing *what* you are building and *why*.

### Prerequisites
- Snowflake account with SYSADMIN or ACCOUNTADMIN (trial account is fine)
- Familiarity with basic Snowflake DDL
- Have read [01 — Philosophical Foundations](01-philosophical-foundations.md) (at minimum the Key Claim section)

### Lab Structure
| Module | Focus | Ontological Theme |
|--------|-------|------------------|
| 1 | Account + Role Architecture | Ownership as institutional fact |
| 2 | Medallion Schema Setup | Object identity across layers |
| 3 | Data Contracts in Code | Constitutive rules |
| 4 | Governance Interfaces | Human agreement → platform enforcement |
| 5 | Sharing with Enforcement | Cross-account institutional facts |
| 6 | Diagnostic Exercises | Field readiness |
| 7 | Knowledge Graph Exploration | Ontology made operational |

---

## Module 1 — Account and Role Architecture

### Context

Roles in Snowflake are **status functions** (Searle). They have no physical existence.
A role called `FINANCE_DATA_OWNER` only has meaning if the organisation collectively
agrees that the Finance Data Team owns the objects granted to that role — and holds
them accountable for it.

In most customer environments, SYSADMIN owns everything. This is the equivalent of
having no institutional fact about ownership at all — everything is owned by the
platform, which means nothing is owned by a human team.

### Setup: Three-Owner Architecture

```sql
-- ============================================================
-- MODULE 1: ROLE ARCHITECTURE AS INSTITUTIONAL OWNERSHIP
-- ============================================================

-- Platform-level roles (map to RDO responsibilities)
CREATE ROLE IF NOT EXISTS rdo_platform_admin
  COMMENT = 'RDO: platform operations, account management, SDLC execution';

CREATE ROLE IF NOT EXISTS rdo_ingestion_engineer
  COMMENT = 'RDO: bronze ingestion, pipeline operations, source connectivity';

-- Governance roles (map to CDO responsibilities)
CREATE ROLE IF NOT EXISTS cdo_governance_admin
  COMMENT = 'CDO: governance policy authoring, classification, standards enforcement';

CREATE ROLE IF NOT EXISTS cdo_data_steward
  COMMENT = 'CDO: data quality monitoring, contract review, semantic standards';

-- Domain roles (map to Data Team responsibilities)
CREATE ROLE IF NOT EXISTS finance_data_owner
  COMMENT = 'Finance Data Team: owns gold/domain finance assets and contracts';

CREATE ROLE IF NOT EXISTS finance_data_consumer
  COMMENT = 'Finance consumers: read access to finance gold products';

CREATE ROLE IF NOT EXISTS sales_data_owner
  COMMENT = 'Sales Data Team: owns gold/domain sales assets and contracts';

-- Role hierarchy
GRANT ROLE rdo_ingestion_engineer TO ROLE rdo_platform_admin;
GRANT ROLE cdo_data_steward TO ROLE cdo_governance_admin;
GRANT ROLE finance_data_consumer TO ROLE finance_data_owner;

-- Grant to SYSADMIN for lab purposes
GRANT ROLE rdo_platform_admin TO ROLE SYSADMIN;
GRANT ROLE cdo_governance_admin TO ROLE SYSADMIN;
GRANT ROLE finance_data_owner TO ROLE SYSADMIN;
```

### Discussion Questions — Module 1

> **Q1.1:** In this role design, who is accountable when a Finance Gold table has wrong data?
> Map the accountability to a role, then ask: is there a *person* behind that role in a real org?

> **Q1.2:** A customer shows you a Snowflake account where ACCOUNTADMIN has been used
> to create all databases, schemas, and tables. What does this tell you about
> the state of their human ownership model? What is the first conversation to have?

> **Q1.3:** What is the difference between granting OWNERSHIP to `finance_data_owner`
> vs. granting SELECT? Why does the distinction matter ontologically?

---

## Module 2 — Medallion Schema as Ontological Zones

### Context

Each medallion layer is ontologically distinct:
- **Bronze:** brute facts — the world as recorded, owned by RDO
- **Silver:** institutional facts in formation — governed, conformed, owned by CDO
- **Gold:** full institutional facts — domain products with contracts, owned by Data Teams

The schema structure should enforce these boundaries, not merely suggest them.

### Setup

```sql
-- ============================================================
-- MODULE 2: MEDALLION SCHEMA AS ONTOLOGICAL ZONES
-- ============================================================

-- Create the DCA demo database
CREATE DATABASE IF NOT EXISTS dca_lab
  COMMENT = 'DCA Ontology Lab — three-layer medallion with ownership boundaries';

-- Bronze: RDO-owned, immutable ingestion zone
CREATE SCHEMA IF NOT EXISTS dca_lab.bronze
  COMMENT = 'OWNER: RDO. Brute facts. Immutable raw ingestion. No institutional transformation.';

GRANT OWNERSHIP ON SCHEMA dca_lab.bronze TO ROLE rdo_ingestion_engineer REVOKE CURRENT GRANTS;

-- Silver: CDO-owned, governed conformance zone
CREATE SCHEMA IF NOT EXISTS dca_lab.silver
  COMMENT = 'OWNER: CDO. Institutional facts in formation. Enterprise standards applied.';

GRANT OWNERSHIP ON SCHEMA dca_lab.silver TO ROLE cdo_governance_admin REVOKE CURRENT GRANTS;

-- Gold: Data Team-owned, domain product zone
CREATE SCHEMA IF NOT EXISTS dca_lab.gold_finance
  COMMENT = 'OWNER: Finance Data Team. Full institutional facts. Governed data products.';

GRANT OWNERSHIP ON SCHEMA dca_lab.gold_finance TO ROLE finance_data_owner REVOKE CURRENT GRANTS;

CREATE SCHEMA IF NOT EXISTS dca_lab.gold_sales
  COMMENT = 'OWNER: Sales Data Team. Full institutional facts. Governed data products.';

GRANT OWNERSHIP ON SCHEMA dca_lab.gold_sales TO ROLE sales_data_owner REVOKE CURRENT GRANTS;

-- Confirm ownership
SHOW SCHEMAS IN DATABASE dca_lab;
-- Each schema should show its owner role — these are the institutional ownership facts
```

### The Bronze Table: Brute Facts

```sql
-- Bronze: raw ingestion — minimal transformation, source fidelity preserved
USE ROLE rdo_ingestion_engineer;
USE WAREHOUSE COMPUTE_WH; -- use your available warehouse

CREATE TABLE IF NOT EXISTS dca_lab.bronze.raw_transactions (
  -- Source system fields — preserved exactly as received
  src_txn_id        VARCHAR       NOT NULL  COMMENT 'Source system transaction ID — immutable',
  src_customer_id   VARCHAR                 COMMENT 'Source system customer identifier',
  src_amount        VARCHAR                 COMMENT 'Raw amount — string, as received from source',
  src_currency      VARCHAR                 COMMENT 'ISO 4217 currency code from source',
  src_txn_date      VARCHAR                 COMMENT 'Raw date string from source — not parsed',
  src_status        VARCHAR                 COMMENT 'Source status code — not yet conformed',
  src_payload       VARIANT                 COMMENT 'Full source payload for audit/reprocessing',

  -- Ingestion metadata — added by RDO pipeline, not source data
  _ingested_at      TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP()
                    COMMENT 'When this record was ingested by the RDO pipeline',
  _source_system    VARCHAR       NOT NULL  COMMENT 'Source system identifier',
  _pipeline_version VARCHAR                 COMMENT 'Version of ingestion pipeline that created this'
)
COMMENT = 'BRONZE: Raw transaction events. Immutable. Source fidelity preserved. Owner: RDO.'
;

-- Note: no UPDATE or DELETE expected on Bronze
-- The brute fact must remain what it was when recorded
```

### The Silver Table: Institutional Facts in Formation

```sql
-- Silver: CDO governs conformance — enterprise canonical keys, types, standards applied
USE ROLE cdo_governance_admin;

CREATE TABLE IF NOT EXISTS dca_lab.silver.transactions (
  -- Enterprise canonical keys (identity conditions now explicit)
  txn_id            VARCHAR       NOT NULL  COMMENT 'Enterprise canonical transaction ID',
  customer_id       VARCHAR       NOT NULL  COMMENT 'Enterprise canonical customer ID (CRM golden record)',

  -- Conformed and typed
  amount_usd        NUMBER(18,4)  NOT NULL  COMMENT 'Amount in USD, converted and validated',
  original_amount   NUMBER(18,4)            COMMENT 'Original amount before FX conversion',
  original_currency VARCHAR(3)              COMMENT 'ISO 4217 original currency',
  txn_date          DATE          NOT NULL  COMMENT 'Parsed, validated transaction date',
  txn_status        VARCHAR       NOT NULL  COMMENT 'Conformed status: COMPLETED|PENDING|FAILED|REVERSED',
  txn_channel       VARCHAR                 COMMENT 'Conformed channel: ONLINE|POS|ATM|API',

  -- Classification metadata (CDO-assigned)
  data_sensitivity  VARCHAR DEFAULT 'INTERNAL'
                    COMMENT 'CDO classification: PUBLIC|INTERNAL|CONFIDENTIAL|RESTRICTED',

  -- Lineage
  _source_txn_id    VARCHAR       NOT NULL  COMMENT 'FK to bronze.raw_transactions.src_txn_id',
  _conformed_at     TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP()
                    COMMENT 'When CDO pipeline conformed this record',
  _conform_version  VARCHAR                 COMMENT 'Version of conformance rules applied'
)
COMMENT = 'SILVER: Conformed transactions. Enterprise canonical keys and types. Owner: CDO.'
;
```

### The Gold Table: Full Institutional Fact

```sql
-- Gold: Finance Data Team creates a domain data product with full institutional backing
USE ROLE finance_data_owner;

CREATE TABLE IF NOT EXISTS dca_lab.gold_finance.monthly_revenue (
  -- Business-level identity
  revenue_period    DATE          NOT NULL  COMMENT 'First day of revenue month (YYYY-MM-01)',
  region            VARCHAR       NOT NULL  COMMENT 'Sales region: EMEA|APAC|AMER|GLOBAL',
  product_line      VARCHAR       NOT NULL  COMMENT 'Conformed product line from catalogue',

  -- The institutional fact: revenue (agreed definition)
  gross_revenue_usd NUMBER(18,2)  NOT NULL
                    COMMENT 'Gross invoiced revenue in USD. Definition: sum of COMPLETED txns, net of system reversals. Excludes manual adjustments. See Finance Data Contract v2.1.',
  net_revenue_usd   NUMBER(18,2)  NOT NULL
                    COMMENT 'Net revenue after returns and credits. See Finance Data Contract v2.1.',
  txn_count         INTEGER       NOT NULL  COMMENT 'Count of transactions contributing to revenue',

  -- Contract metadata
  data_contract_version VARCHAR   COMMENT 'Version of Finance Data Contract governing this table',
  _produced_at      TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),

  -- Primary key — identity condition for this data product
  CONSTRAINT pk_monthly_revenue PRIMARY KEY (revenue_period, region, product_line)
)
COMMENT = 'GOLD: Monthly revenue by region and product. Owner: Finance Data Team. Governed by Finance Data Contract v2.1. Consumer SLA: 99.9% freshness within 2 hours of month-end close.'
;
```

### Discussion Questions — Module 2

> **Q2.1:** Look at the column definitions in Bronze vs Silver vs Gold.
> At which layer does a "transaction" become an enterprise concept rather than a source record?
> What is the ontological significance of the `txn_id` change from `src_txn_id`?

> **Q2.2:** The Gold comment says "See Finance Data Contract v2.1."
> If that document lives in Confluence and the table owner leaves the company,
> what happens to the institutional fact about what "revenue" means?
> How would you fix this architecturally?

> **Q2.3:** A customer wants to put their transformation logic directly into Bronze.
> What ontological problem does this create? How do you explain the risk to a non-technical exec?

---

## Module 3 — Data Contracts as Constitutive Rules

### Context

A data contract is not a regulative rule ("you should use data this way").
It is a constitutive rule — it creates the data product. Without it, the table is just bytes.

This module encodes a data contract as first-class metadata in Snowflake.

```sql
-- ============================================================
-- MODULE 3: DATA CONTRACTS AS PLATFORM OBJECTS
-- ============================================================

-- Step 1: Create the contract tag — makes contract version queryable
USE ROLE cdo_governance_admin;

CREATE TAG IF NOT EXISTS dca_lab.silver.data_contract_version
  ALLOWED_VALUES ('v1.0', 'v1.1', 'v2.0', 'v2.1', 'DRAFT', 'DEPRECATED')
  COMMENT = 'Version of the data contract governing this object';

CREATE TAG IF NOT EXISTS dca_lab.silver.data_contract_owner
  COMMENT = 'Team accountable for this data contract';

CREATE TAG IF NOT EXISTS dca_lab.silver.data_contract_consumers
  COMMENT = 'Comma-separated list of approved consumer teams';

CREATE TAG IF NOT EXISTS dca_lab.silver.data_purpose
  ALLOWED_VALUES ('ANALYTICS', 'REPORTING', 'AI_TRAINING', 'OPERATIONS', 'SHARING', 'AUDIT')
  COMMENT = 'Approved purpose for consumption of this object';

-- Step 2: Apply contract metadata to the Gold table
USE ROLE finance_data_owner;

ALTER TABLE dca_lab.gold_finance.monthly_revenue
  SET TAG dca_lab.silver.data_contract_version = 'v2.1';

ALTER TABLE dca_lab.gold_finance.monthly_revenue
  SET TAG dca_lab.silver.data_contract_owner = 'finance-data-team@company.com';

ALTER TABLE dca_lab.gold_finance.monthly_revenue
  SET TAG dca_lab.silver.data_contract_consumers = 'FP&A,Executive Dashboard,Sales Analytics';

ALTER TABLE dca_lab.gold_finance.monthly_revenue
  SET TAG dca_lab.silver.data_purpose = 'ANALYTICS';

-- Step 3: Query the contract registry — who owns what
USE ROLE cdo_governance_admin;

SELECT
  object_name,
  object_database,
  object_schema,
  tag_name,
  tag_value
FROM TABLE(
  dca_lab.information_schema.tag_references_all_columns(
    'dca_lab.gold_finance.monthly_revenue',
    'table'
  )
)
ORDER BY tag_name;
```

### Data Quality Enforcement (Contract SLA in Code)

```sql
-- Step 4: Encode the freshness SLA as a monitored metric
USE ROLE cdo_governance_admin;

-- Create a custom data metric function for freshness monitoring
CREATE OR REPLACE DATA METRIC FUNCTION dca_lab.silver.freshness_hours(
  ARG_T TABLE(produced_at TIMESTAMP_LTZ)
)
RETURNS NUMBER
COMMENT = 'Returns hours since the most recent record was produced. Alert if > 2 for Gold tables.'
AS
$$
  SELECT DATEDIFF('hour', MAX(produced_at), CURRENT_TIMESTAMP())
  FROM ARG_T
$$;

-- Attach to the Gold table
ALTER TABLE dca_lab.gold_finance.monthly_revenue
  ADD DATA METRIC FUNCTION dca_lab.silver.freshness_hours
  ON (_produced_at)
  SCHEDULE = 'TRIGGER_ON_CHANGES';

-- Now check metric results
SELECT *
FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS
WHERE metric_name ILIKE '%freshness%'
  AND table_name = 'MONTHLY_REVENUE'
ORDER BY measurement_time DESC
LIMIT 10;
```

### Discussion Questions — Module 3

> **Q3.1:** In the tag setup, `data_purpose` has allowed values.
> A developer asks why you're restricting to a fixed list.
> How do you explain this in terms of institutional facts and collective intentionality?

> **Q3.2:** The freshness DMF alerts the platform. Who should the alert go to?
> Design the escalation path: DMF breach → alert → who → what action → resolution.
> Map each step to a human role in the DCA.

> **Q3.3:** A customer says "we already have data contracts in our API spec docs."
> What is the ontological gap between a contract in a document and a contract
> encoded as platform metadata + enforced DMF? Use concrete examples.

---

## Module 4 — Governance Interfaces: Human Agreement → Platform Enforcement

### Context

This module implements the six critical interfaces from
[04 — DCA Ontological Synthesis](04-dca-ontological-synthesis.md).

Focus: the interface between a human classification decision and
a runtime-enforced masking policy.

```sql
-- ============================================================
-- MODULE 4: GOVERNANCE INTERFACES
-- ============================================================

-- INTERFACE 3: Sensitivity → Classification + Policy

-- Step 1: Classify (CDO decision encoded as tag)
USE ROLE cdo_governance_admin;

CREATE TAG IF NOT EXISTS dca_lab.silver.pii_category
  ALLOWED_VALUES ('NAME', 'EMAIL', 'PHONE', 'FINANCIAL', 'LOCATION', 'IDENTIFIER', 'NONE')
  COMMENT = 'PII category under GDPR Article 4. Assigned by CDO classification process.';

-- Step 2: Create the masking policy (CDO governance)
CREATE OR REPLACE MASKING POLICY dca_lab.silver.mask_financial_data
  AS (val NUMBER) RETURNS NUMBER ->
  CASE
    WHEN CURRENT_ROLE() IN ('finance_data_owner', 'cdo_governance_admin', 'rdo_platform_admin')
      THEN val                         -- owners and governance see real values
    WHEN CURRENT_ROLE() = 'finance_data_consumer'
      THEN ROUND(val, -2)              -- consumers see values rounded to nearest 100
    ELSE NULL                          -- everyone else sees NULL
  END
COMMENT = 'Financial data masking. Owner: CDO. Applied per Finance Data Contract v2.1.';

-- Step 3: Attach policy (the interface — human decision becomes runtime enforcement)
ALTER TABLE dca_lab.gold_finance.monthly_revenue
  MODIFY COLUMN gross_revenue_usd
  SET MASKING POLICY dca_lab.silver.mask_financial_data;

ALTER TABLE dca_lab.gold_finance.monthly_revenue
  MODIFY COLUMN net_revenue_usd
  SET MASKING POLICY dca_lab.silver.mask_financial_data;

-- Step 4: Verify — test as different roles
USE ROLE finance_data_owner;
-- Should see exact values
SELECT gross_revenue_usd, net_revenue_usd
FROM dca_lab.gold_finance.monthly_revenue
LIMIT 3;

USE ROLE finance_data_consumer;
-- Should see rounded values (nearest 100)
SELECT gross_revenue_usd, net_revenue_usd
FROM dca_lab.gold_finance.monthly_revenue
LIMIT 3;

-- INTERFACE 2: Ownership → RBAC
USE ROLE cdo_governance_admin;

-- Grant read access to approved consumers
GRANT USAGE ON DATABASE dca_lab TO ROLE finance_data_consumer;
GRANT USAGE ON SCHEMA dca_lab.gold_finance TO ROLE finance_data_consumer;
GRANT SELECT ON TABLE dca_lab.gold_finance.monthly_revenue TO ROLE finance_data_consumer;
-- Note: no INSERT, UPDATE, DELETE — the data product is read-only for consumers
```

### Discussion Questions — Module 4

> **Q4.1:** The masking policy returns `NULL` for unknown roles. A junior developer
> who only has PUBLIC role tries to query the table and sees NULL for revenue.
> They think the data is missing. What is the UX problem and how do you address it
> while maintaining security? Is this a technical or a human problem?

> **Q4.2:** Walk through Interface 1 (Intent → Schema) using the Bronze table DDL.
> What evidence is there that the schema was designed with domain input?
> What would a schema look like that was NOT designed with domain input?

> **Q4.3:** A customer's security team wants masking policies reviewed quarterly.
> Design the review process: what Snowflake objects do you query to audit
> which policies are applied where? Show the SQL.

---

## Module 5 — Sharing with Cross-Account Enforcement

### Context

Shares create institutional relationships across account boundaries.
The enforcement patterns from [cross-account RBAC](../snowflake-cross-account-rbac.md)
apply here with the ontological framing.

```sql
-- ============================================================
-- MODULE 5: CROSS-ACCOUNT SHARING AS INSTITUTIONAL BRIDGE
-- ============================================================

-- Step 1: Create a secure view for sharing
-- The secure view IS the institutional boundary between provider and consumer
USE ROLE finance_data_owner;

CREATE OR REPLACE SECURE VIEW dca_lab.gold_finance.monthly_revenue_shared
COMMENT = 'External-facing data product. Enforcement: account-level access control + purpose-bound masking.'
AS
SELECT
  revenue_period,
  region,
  product_line,

  -- INTERFACE 6: Access Purpose → Consumption Control
  -- Enforcement based on which account is consuming
  CASE
    WHEN CURRENT_ACCOUNT() = 'TRUSTED_PARTNER_ACCOUNT'
      AND INVOKER_ROLE() = 'ANALYST'
    THEN gross_revenue_usd          -- trusted partner analysts see actuals
    ELSE ROUND(gross_revenue_usd, -3)  -- all others see rounded to nearest 1000
  END AS gross_revenue_usd,

  -- Never expose net revenue outside — purpose limitation enforced here
  txn_count,
  data_contract_version

FROM dca_lab.gold_finance.monthly_revenue

-- Row-level: only share COMPLETED months (no in-progress data)
WHERE revenue_period < DATE_TRUNC('month', CURRENT_DATE());

-- Step 2: Create the share
CREATE SHARE IF NOT EXISTS dca_finance_external
  COMMENT = 'Finance monthly revenue — external partner share. Governed by Finance External Data Contract v1.0.';

GRANT USAGE ON DATABASE dca_lab TO SHARE dca_finance_external;
GRANT USAGE ON SCHEMA dca_lab.gold_finance TO SHARE dca_finance_external;
GRANT SELECT ON VIEW dca_lab.gold_finance.monthly_revenue_shared TO SHARE dca_finance_external;

-- Step 3: Whitelist only approved accounts
-- ALTER SHARE dca_finance_external ADD ACCOUNTS = (PARTNER_ACCOUNT_LOCATOR);
-- (Commented out — requires real account locators)

-- Step 4: Verify the share definition
SHOW GRANTS TO SHARE dca_finance_external;
```

### Discussion Questions — Module 5

> **Q5.1:** The secure view filters to completed months only. What ontological principle
> does this enforce? (Hint: think about what it means for a fact to be "settled"
> vs. "in formation".)

> **Q5.2:** A partner's analyst role is named `DATA_SCIENTIST` not `ANALYST`.
> The `INVOKER_ROLE()` check fails and they see rounded data.
> This is a trust design problem. How do you solve it without
> giving the partner admin access to your governance logic?

> **Q5.3:** Design the "external data contract" that would govern this share.
> Using the six contract components from the synthesis document,
> what specific commitments would the Finance team be making?
> What would the partner be committing to in return?

---

## Module 6 — Diagnostic Exercises: Field Readiness

These exercises simulate what you will find in real customer environments.
For each, identify: (a) the ontological failure, (b) the human relationship issue,
(c) the architectural fix, and (d) the discovery question you would ask.

### Scenario A: The Orphaned Table

```sql
-- You run this query in a customer's account:
SELECT
  table_catalog,
  table_schema,
  table_name,
  table_owner,
  comment,
  row_count,
  created
FROM information_schema.tables
WHERE table_schema = 'GOLD'
  AND comment IS NULL
  AND table_owner = 'SYSADMIN'
ORDER BY created;

-- You get 47 tables back.
```

**Questions:**
- What ontological failure does this represent?
- What human relationship has broken down?
- What is the business risk?
- What is your opening question to the CDO?

---

### Scenario B: The Semantic War

A customer tells you: "We have three revenue figures. Finance says $42M.
Sales says $38M. The CEO dashboard shows $45M. We have a board meeting next week."

**Questions:**
- Name the ontological failure (use precise terminology from the framework).
- Which of the six critical interfaces has not been implemented?
- Map this to a failure in collective intentionality.
- What is the one Snowflake object, if it existed and was trusted by all three teams,
  that would resolve this? How would you build it?

---

### Scenario C: The Governance Ghost

A customer shows you their Snowflake account. They have:
- 847 masking policies defined
- Classification tags on 3,200 columns
- A dedicated data governance team of 6 people
- A governance dashboard showing 94% compliance

They also tell you: "Our data scientists say they can't get the data they need.
Consumers complain that everything is masked. Business teams maintain their own
copies of governed tables because the governed versions are unusable."

**Questions:**
- What has gone wrong despite apparent governance health?
- What is the human ontology failure here?
- What is the architectural manifestation?
- How do you diagnose whether governance is real or performative?
- Design a 30-minute discovery conversation that would reveal the truth.

---

### Scenario D: The Trust Cliff

A customer is 18 months into a data mesh transformation. They have:
- Clear CDO/RDO split
- Data domain teams with named owners
- Data contracts in a git repo
- Dynamic Tables for all Silver transformations
- A Snowflake Horizon governance score of 87%

But adoption is at 23%. Most consumers still query Bronze directly.

**Questions:**
- Why would consumers bypass Silver and Gold to query Bronze directly?
- What does Bronze querying tell you about the state of consumer trust?
- Which of the three trust relationships (CDO/RDO, CDO/Teams, Teams/Consumers)
  has failed most severely?
- What is the one question you would ask to locate the root cause?

---

## Module 7 — Knowledge Graph Exploration

### Context

The philosophical frameworks from Modules 1-6 are now operational. The Ontology Knowledge
Graph materializes the DCA ontological map as a computable node/edge model. Every
institutional fact — ownership, classification, lineage, access — becomes a queryable
graph relation.

This module uses the graph to answer the Five Discovery Questions automatically.

### Prerequisites
- Scripts 11-15 deployed (`sql/11_rai_setup.sql` through `sql/15_ontology_sharing.sql`)
- Graph populated: `CALL DCA_DEMO.GOVERNANCE.SP_REFRESH_GRAPH();`
- RAI inference run: `CALL DCA_DEMO.GOVERNANCE.SP_RUN_INFERENCE();`

### Exercise 7A: Explore the Graph

```sql
-- ============================================================
-- MODULE 7A: GRAPH STRUCTURE EXPLORATION
-- ============================================================

USE ROLE ONTOLOGY_ADMIN;
USE DATABASE DCA_DEMO;
USE WAREHOUSE COMPUTE_WH;

-- How many nodes and edges?
SELECT 
    (SELECT COUNT(*) FROM GOVERNANCE.ONTOLOGY_GRAPH_NODES) AS total_nodes,
    (SELECT COUNT(*) FROM GOVERNANCE.ONTOLOGY_GRAPH_EDGES) AS total_edges;

-- Node distribution by layer and type
SELECT layer, node_type, COUNT(*) AS cnt
FROM GOVERNANCE.ONTOLOGY_GRAPH_NODES
GROUP BY layer, node_type
ORDER BY layer, cnt DESC;

-- Edge distribution by type
SELECT edge_type, layer, COUNT(*) AS cnt
FROM GOVERNANCE.ONTOLOGY_GRAPH_EDGES
GROUP BY edge_type, layer
ORDER BY cnt DESC;

-- Cross-layer edges (the ontological bridges)
SELECT source_node_id, target_node_id, edge_type
FROM GOVERNANCE.ONTOLOGY_GRAPH_EDGES
WHERE layer = 'CROSS'
LIMIT 20;
```

**Discussion:**
- What does the ratio of METADATA to BUSINESS nodes tell you about this platform?
- Why are CROSS edges the most ontologically interesting?
- Which edge type has the highest count? What does that imply about the architecture?

### Exercise 7B: Governance Scoring

```sql
-- ============================================================
-- MODULE 7B: GOVERNANCE HEALTH VIA GRAPH SCORING
-- ============================================================

-- Worst-governed objects
SELECT n.display_name, n.node_type, n.source_system,
       s.overall_score, s.tag_coverage, s.contract_coverage, s.ownership_score
FROM GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES s
JOIN GOVERNANCE.ONTOLOGY_GRAPH_NODES n ON s.node_id = n.node_id
WHERE s.overall_score < 0.4
ORDER BY s.overall_score ASC;

-- Score distribution
SELECT 
    CASE 
        WHEN overall_score >= 0.7 THEN 'GREEN (well-governed)'
        WHEN overall_score >= 0.4 THEN 'YELLOW (gaps exist)'
        ELSE 'RED (under-governed)'
    END AS governance_band,
    COUNT(*) AS node_count
FROM GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES
GROUP BY governance_band
ORDER BY governance_band;
```

**Discussion:**
- Do the red-scored objects correspond to the intentional gaps from Module 4 (`04_governance_gaps.sql`)?
- If a customer showed you this score distribution, what would you recommend?
- What is the relationship between governance score and consumer trust?

### Exercise 7C: RAI Recommendations

```sql
-- ============================================================
-- MODULE 7C: AUTOMATED GOVERNANCE RECOMMENDATIONS
-- ============================================================

-- All open recommendations
SELECT recommendation_type, severity, description, suggested_action
FROM GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS
WHERE status = 'OPEN'
ORDER BY 
    CASE severity WHEN 'HIGH' THEN 1 WHEN 'MEDIUM' THEN 2 ELSE 3 END;

-- Recommendations by type
SELECT recommendation_type, COUNT(*) AS cnt,
       SUM(CASE WHEN severity = 'HIGH' THEN 1 ELSE 0 END) AS high_sev
FROM GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS
WHERE status = 'OPEN'
GROUP BY recommendation_type;
```

**Discussion:**
- Map each recommendation back to one of the Four Governance Gaps. Did RAI find all four?
- Which recommendation type is most dangerous to ignore? Why?
- In a customer conversation, how would you present these recommendations without
  making governance feel like punishment?

### Exercise 7D: The Five Questions, Answered by the Graph

```sql
-- ============================================================
-- MODULE 7D: DISCOVERY QUESTIONS VIA GRAPH ANALYSIS
-- ============================================================

-- Q1: "Do we have conflicting definitions?"
-- Look for entity clusters with the same display_name but different sources
SELECT cluster_id, node_id, cluster_label, confidence
FROM GOVERNANCE.ONTOLOGY_GRAPH_RAI_ENTITY_CLUSTERS
WHERE confidence > 0.7
ORDER BY cluster_id, confidence DESC;

-- Q2: "Who is accountable?"
-- Find tables with no ownership edge (no non-SYSADMIN GRANTED_TO)
SELECT n.display_name, n.fqn
FROM GOVERNANCE.ONTOLOGY_GRAPH_NODES n
WHERE n.node_type = 'TABLE' AND n.layer = 'METADATA'
  AND NOT EXISTS (
      SELECT 1 FROM GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
      WHERE e.target_node_id = n.node_id
        AND e.edge_type = 'GRANTED_TO'
        AND e.source_node_id NOT IN (
            SELECT node_id FROM GOVERNANCE.ONTOLOGY_GRAPH_NODES
            WHERE display_name IN ('SYSADMIN', 'ACCOUNTADMIN')
        )
  );

-- Q4: "Are consumers bypassing the governed path?"
SELECT r.description, r.suggested_action
FROM GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS r
WHERE r.recommendation_type = 'LAYER_BYPASS';
```

**Discussion:**
- For each of the Five Discovery Questions, can the graph provide a definitive answer
  or only a signal? Where does human judgment still matter?
- What additional edges would make the graph more powerful?
- How would you use this in a customer workshop to move from "we think governance is fine"
  to "here's proof of where it's not"?

---

## Lab Completion Checklist

By the end of this lab, you should be able to:

```
□  Explain the difference between a brute fact and an institutional fact
   using a real Snowflake object as an example

□  Identify the six critical interfaces in a customer's architecture
   and assess the health of each

□  Diagnose human ontology failures from their data system signatures

□  Design a role architecture that maps to real human accountability,
   not just technical access control

□  Explain why a data contract in Confluence is not the same as a
   data contract encoded as platform metadata + DMF + tags

□  Walk a CDO or data leader through the dependency chain
   (People → Data → Governance → Automation) without using jargon

□  Ask the five discovery questions that reveal whether a customer
   has governance or the appearance of governance

□  Query the Knowledge Graph to identify governance gaps that
   traditional point-in-time checks would miss

□  Explain how RAI inference rules map to the Five Discovery Questions

□  Use governance scores to prioritize remediation in a customer conversation
```

---

## The Five Discovery Questions

Take these into any customer conversation:

| # | Question | What It Diagnoses |
|---|----------|------------------|
| 1 | "If I ask five different people what 'revenue' means, will I get five different answers?" | Semantic health / collective intentionality |
| 2 | "Who is personally accountable when the Orders table has wrong data?" | Ownership health |
| 3 | "How do consumers find out when a schema has changed?" | Contract trust |
| 4 | "Does your CDO have the authority to mandate a definition that Engineering must implement?" | Institutional authority |
| 5 | "Do your data scientists use the governed tables, or do they keep their own copies?" | Consumer trust — the ultimate test |

If the answers to all five are strong: you have a customer ready for advanced platform
capabilities. If any are weak: the human ontological work must happen before the
platform can deliver its promise.

---

*Return to: [04 — DCA Ontological Synthesis](04-dca-ontological-synthesis.md)*
*Start from: [00 — README](00-README.md)*
