# Demo Script - 15 Minute Walkthrough

## Overview

This guide provides a structured 15-minute demonstration of the Snowflake Data Cloud Architecture demo, showcasing Horizon governance, Dynamic Tables, dbt, Cortex Analyst, and the Internal Data Marketplace.

## Prerequisites

Before the demo:
1. Deploy all SQL scripts (01-10)
2. Generate and load source system data:
   ```bash
   cd tools
   python data_generator.py --system sap --domain all --output ../data
   # Or: --system salesforce, oracle, fhir, workday, servicenow
   ```
3. Run the dbt pipeline for ServiceNow:
   ```bash
   cd dbt_servicenow
   dbt build
   ```
4. Ensure Streamlit app is deployed
5. Have Snowsight open and logged in

## Demo Flow

### Opening (1 minute)

**Talk Track:**
> "Today I'll show you a complete enterprise data platform built on Snowflake's Data Cloud. We'll see how data flows from source systems through three layers - raw, curated, and semantic - with comprehensive governance at every step. Then we'll interact with the data using natural language through Cortex Analyst."

### Part 1: Architecture Overview (3 minutes)

#### Show the README Diagram

Open README.md and highlight the architecture:

> "Our architecture follows the medallion pattern:
> - **RAW Layer**: Captures data from any source system with full history
> - **CURATED Layer**: Transforms data using Dynamic Tables (SAP, Salesforce, Oracle, FHIR, Workday) and dbt (ServiceNow) — teams choose their engine
> - **SEMANTIC Layer**: Provides business-friendly views optimized for Cortex Analyst"

#### Show the Role Hierarchy

```sql
-- Run in Snowsight
SHOW ROLES LIKE 'DATA_%';
SHOW ROLES LIKE 'ANALYST';
SHOW ROLES LIKE 'AI_%';
```

> "We have a comprehensive role hierarchy that enforces least-privilege access. DATA_ADMIN owns everything, while business users like ANALYST only see what they need."

### Part 2: Dynamic Tables (3 minutes)

#### Show Dynamic Table Status

```sql
USE ROLE DATA_ADMIN;
USE WAREHOUSE TRANSFORM_WH;

-- Show Dynamic Tables
SHOW DYNAMIC TABLES IN DATABASE CURATED_DEV;

-- Check refresh history
SELECT 
    name,
    state,
    last_completed_time,
    target_lag,
    state_message
FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY())
WHERE name LIKE '%DIM%' OR name LIKE '%FACT%'
ORDER BY last_completed_time DESC
LIMIT 10;
```

> "Dynamic Tables automatically transform data based on the TARGET_LAG we specify. Customer dimensions refresh every hour, while reference data refreshes every 24 hours. No scheduling, no maintenance - Snowflake handles it all."

#### Show a Dynamic Table Definition

```sql
-- Show the transformation logic
SELECT GET_DDL('DYNAMIC TABLE', 'CURATED_DEV.DIMENSIONS.DIM_CUSTOMER');
```

> "Notice the derived attributes - customer tier, tenure bucket, health score. These business rules are encoded once and refresh automatically."

### Part 2b: dbt Pipeline — ServiceNow (2 minutes)

#### Show the dbt DAG

```bash
# In terminal (or show pre-generated docs)
cd dbt_servicenow
dbt docs generate
dbt docs serve
```

> "For teams that already use dbt, the DCA supports code-first transformation alongside Dynamic Tables. Here ServiceNow ITSM is managed by dbt — same RAW layer, same CURATED output, different engine."

#### Show dbt Tests and Lineage

```bash
# Run models and tests
dbt build

# Check source freshness
dbt source freshness
```

> "dbt brings built-in testing — not_null, unique, accepted_values, relationship tests — all defined in YAML alongside the model code. Every run validates data quality automatically."

#### Show the dbt Output in Snowflake

```sql
-- dbt-managed curated tables sit alongside Dynamic Table schemas
USE ROLE DATA_ADMIN;
SHOW SCHEMAS IN DATABASE CURATED_DEV LIKE '%SERVICENOW%';

-- Query a dbt fact table
SELECT priority, COUNT(*) as incident_count, 
       SUM(CASE WHEN is_sla_breached THEN 1 ELSE 0 END) as sla_breaches
FROM CURATED_DEV.DBT_SERVICENOW.FACT_INCIDENTS
GROUP BY priority ORDER BY priority;
```

> "Consumers don't know or care whether a table was built by Dynamic Tables or dbt — they see the same curated, contract-validated, governance-tagged output."

### Part 3: Semantic Views for Cortex (3 minutes)

#### Show Semantic View Structure

```sql
-- List semantic views
SHOW SEMANTIC VIEWS IN DATABASE SEM_DEV;

-- Show sales analytics definition
SELECT GET_DDL('SEMANTIC VIEW', 'SEM_DEV.SEM_SALES.SALES_ANALYTICS');
```

> "Semantic Views are native Snowflake objects that define tables, relationships, dimensions, and metrics. Cortex Analyst understands these and can write accurate SQL from natural language."

### Part 4: Governance Demo (3 minutes)

#### Show Masking in Action

```sql
-- As DATA_ADMIN - full access
USE ROLE DATA_ADMIN;
SELECT CUSTOMER_ID, FIRST_NAME, LAST_NAME, EMAIL, PHONE
FROM CURATED_DEV.DIMENSIONS.DIM_CUSTOMER
LIMIT 5;

-- As ANALYST - masked
USE ROLE ANALYST;
SELECT CUSTOMER_ID, FIRST_NAME, LAST_NAME, EMAIL, PHONE
FROM CURATED_DEV.DIMENSIONS.DIM_CUSTOMER
LIMIT 5;

-- As AI_AGENT - pseudonymized
USE ROLE AI_AGENT;
SELECT CUSTOMER_ID_HASH, DISPLAY_NAME, CUSTOMER_TIER
FROM CURATED_DEV.DIMENSIONS.DIM_CUSTOMER
LIMIT 5;
```

> "Watch how the same query returns different data based on role. DATA_ADMIN sees everything. ANALYST sees masked emails and phones. AI_AGENT only gets pseudonymized hashes - safe for ML training."

#### Show Tags

```sql
USE ROLE DATA_ADMIN;

-- Show tags on a column
SELECT * FROM TABLE(INFORMATION_SCHEMA.TAG_REFERENCES(
    'CURATED_DEV.DIMENSIONS.DIM_CUSTOMER', 'TABLE'
));
```

> "Every column is tagged with classification level, PII type, and AI eligibility. Policies reference these tags for consistent enforcement."

### Part 5: Streamlit App (2 minutes)

#### Launch the App

Navigate to **Projects > Streamlit > DCA_DEMO_APP**

> "Let's see this in action through our Streamlit app..."

#### Dashboard Tab

> "The dashboard shows real-time KPIs from our Dynamic Tables. These refresh automatically with no manual intervention."

#### Cortex Analyst Tab

Ask:
- "What are total orders by region?"
- "Show me customer count by segment"
- "Which sales channel has the highest revenue?"

> "Cortex Analyst translates natural language into SQL using our semantic view definitions. Business users can self-serve without knowing SQL."

#### Governance Tab

Switch between roles in the sidebar:

> "Switch to ANALYST... notice the data is now masked. Switch to VIEWER... now we only see aggregates. Same app, same code - the data layer enforces security."

### Part 6: Data Marketplace (1 minute)

```sql
-- Show shares
SHOW SHARES LIKE '%ANALYTICS%';

-- Show data products
SELECT PRODUCT_ID, PRODUCT_NAME, DOMAIN, DATA_CLASSIFICATION
FROM GOVERNANCE.OBSERVABILITY.DATA_PRODUCT_CATALOG;
```

> "Data products are pre-packaged, governed datasets ready for consumption. Internal teams can discover and use them through our marketplace - no data engineering tickets required."

### Closing (1 minute)

> "To summarize what we've seen:
> 1. **Dynamic Tables** automate data transformation with SLA guarantees
> 2. **dbt** provides code-first, tested, documented pipelines for teams that prefer it
> 3. **Semantic Views** enable natural language analytics through Cortex
> 4. **Horizon Governance** enforces security at the data layer
> 5. **Data Marketplace** enables self-service data consumption
>
> Both transformation engines coexist in harmony — consumers see the same curated output regardless of which engine produced it. All of this runs entirely in Snowflake."

## Common Questions

**Q: How hard is it to add a new source system?**
> "Our data generator already supports SAP, Salesforce, Oracle EBS, FHIR, Workday, and ServiceNow out of the box. Just run:
> ```bash
> python data_generator.py --system sap --domain all --output ../data
> ```
> Each generates authentic tables matching real system schemas - SAP KNA1/VBAK, Salesforce Account/Opportunity, Oracle HZ_PARTIES, FHIR Patient/Encounter, etc."

**Q: What source systems does the demo support?**
> "Six enterprise systems:
> - **SAP S/4HANA**: KNA1, MARA, VBAK, VBAP, PA0001, PA0002, LFA1, EKKO, BKPF
> - **Salesforce**: Account, Contact, Opportunity, Case, Lead, Product2, Campaign, Task
> - **Oracle EBS**: HZ_PARTIES, OE_ORDER_*, AP_INVOICES, RA_CUSTOMER_TRX, GL_JE_LINES, HR_ALL_PEOPLE
> - **FHIR R4**: Patient, Practitioner, Encounter, Condition, Observation, MedicationRequest, Claim
> - **Workday**: Workers, Organizations, Compensation, Time_Off, Benefit_Elections
> - **ServiceNow**: incident, change_request, problem, cmdb_ci, sc_request, kb_knowledge"

**Q: What about performance at scale?**
> "Dynamic Tables use Snowflake's micro-partitioning and automatic optimization. Use `--scale 10` to generate 10x data for load testing."

**Q: How do we handle GDPR data residency?**
> "Each column can be tagged with RESIDENCY_REGION. Row access policies filter EU data from unauthorized roles."

**Q: Can we use this with our existing tools?**
> "Absolutely. Semantic views work with any BI tool. Tableau, Power BI, Looker - they all benefit from the pre-defined relationships."

**Q: Why use dbt alongside Dynamic Tables?**
> "They serve different needs. Dynamic Tables are zero-orchestration — ideal for teams that want Snowflake to manage everything. dbt is code-first — ideal for teams that already have dbt in their ecosystem and want Git-native transformations with built-in testing, macros, and docs. The DCA supports both in the same architecture."

**Q: Can a team migrate from Dynamic Tables to dbt (or vice versa)?**
> "Yes. Since both engines write to the same CURATED layer with the same contracts and governance, a team can swap engines without impacting downstream consumers. The curated output is the contract — the engine is an implementation detail."

**Q: How does dbt testing compare to data contracts?**
> "dbt tests (`not_null`, `unique`, `accepted_values`, `relationships`) are complementary to data contracts. dbt enforces quality at the transformation layer; contracts enforce quality at the publishing boundary. In a mature setup, both run — dbt tests catch issues early, contracts catch issues at the trust boundary."
