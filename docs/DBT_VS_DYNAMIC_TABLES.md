# dbt vs Dynamic Tables: Transformation Strategies in the Data Cloud Architecture

> **When to use which, why both can coexist, and how this demo proves it.**

---

## Overview

The DCA Full Stack Demo now includes **two transformation engines** working side by side:

| Engine | Manages | Pattern |
|--------|---------|---------|
| **Dynamic Tables** | SAP, Salesforce, Oracle EBS, FHIR, Workday | Snowflake-native, config-driven, zero-orchestration |
| **dbt** | ServiceNow ITSM | Code-first, Git-native, test-driven |

This is intentional. Real enterprises don't pick one tool for everything. Teams that already invested in dbt should keep using it. Teams that want zero-ops simplicity should use Dynamic Tables. The architecture supports both — and this document explains the tradeoffs.

---

## Head-to-Head Comparison

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                   dbt vs DYNAMIC TABLES — AT A GLANCE                          │
├──────────────────────┬──────────────────────────┬──────────────────────────────┤
│  Capability          │  dbt                     │  Dynamic Tables              │
├──────────────────────┼──────────────────────────┼──────────────────────────────┤
│  Orchestration       │  External (CI/CD, cron,  │  Built-in (Snowflake-managed │
│                      │  Airflow, dbt Cloud)     │  refresh via TARGET_LAG)     │
├──────────────────────┼──────────────────────────┼──────────────────────────────┤
│  Refresh Model       │  Push (dbt run triggers  │  Pull (Snowflake detects     │
│                      │  materialization)        │  upstream changes)           │
├──────────────────────┼──────────────────────────┼──────────────────────────────┤
│  Freshness SLA       │  Manual (dbt source      │  Declarative (TARGET_LAG     │
│                      │  freshness checks)       │  = '1 hour')                 │
├──────────────────────┼──────────────────────────┼──────────────────────────────┤
│  Testing             │  Built-in (not_null,     │  None built-in (requires     │
│                      │  unique, relationships,  │  external quality checks     │
│                      │  custom SQL tests)       │  or DMFs)                    │
├──────────────────────┼──────────────────────────┼──────────────────────────────┤
│  Documentation       │  Auto-generated (dbt     │  Table comments only         │
│                      │  docs serve + catalog)   │                              │
├──────────────────────┼──────────────────────────┼──────────────────────────────┤
│  Lineage             │  Full DAG visualization  │  Snowflake ACCESS_HISTORY    │
│                      │  (ref() tracking)        │  and OBJECT_DEPENDENCIES     │
├──────────────────────┼──────────────────────────┼──────────────────────────────┤
│  Version Control     │  Native (SQL files in    │  Possible via Git            │
│                      │  Git, PR workflows)      │  integration, but DDL-based  │
├──────────────────────┼──────────────────────────┼──────────────────────────────┤
│  CI/CD Integration   │  Native (dbt build in    │  Requires SQL execution      │
│                      │  GitHub Actions, etc.)   │  in pipeline                 │
├──────────────────────┼──────────────────────────┼──────────────────────────────┤
│  Incremental Logic   │  Explicit (developer     │  Automatic (Snowflake        │
│                      │  writes incremental      │  manages incremental vs      │
│                      │  strategy)               │  full refresh)               │
├──────────────────────┼──────────────────────────┼──────────────────────────────┤
│  Learning Curve      │  Moderate (Jinja, ref,   │  Low (just SQL + TARGET_LAG) │
│                      │  YAML configs, profiles) │                              │
├──────────────────────┼──────────────────────────┼──────────────────────────────┤
│  Operational Overhead│  Medium (scheduler,      │  Minimal (Snowflake manages  │
│                      │  compute, monitoring)    │  everything)                 │
├──────────────────────┼──────────────────────────┼──────────────────────────────┤
│  Portability         │  High (adapters for      │  Snowflake-only              │
│                      │  Snowflake, BigQuery,    │                              │
│                      │  Redshift, Databricks)   │                              │
├──────────────────────┼──────────────────────────┼──────────────────────────────┤
│  Cost Model          │  Warehouse credits when  │  Warehouse credits on        │
│                      │  dbt run executes        │  refresh (auto-managed)      │
├──────────────────────┼──────────────────────────┼──────────────────────────────┤
│  Ecosystem           │  dbt packages (dbt-utils,│  Snowflake-native only       │
│                      │  dbt-expectations, etc.) │                              │
└──────────────────────┴──────────────────────────┴──────────────────────────────┘
```

---

## What dbt Brings

### 1. Built-In Testing

dbt's testing framework is its strongest differentiator for data quality. Every model can have schema tests (YAML) and custom SQL tests:

```yaml
# Schema tests — declared in YAML, run via `dbt test`
columns:
  - name: incident_key
    tests:
      - not_null
      - unique
  - name: caller_key
    tests:
      - relationships:
          to: ref('dim_user')
          field: user_key
```

```sql
-- Custom SQL test — assert_no_orphaned_incidents.sql
-- Returns rows that violate the rule (0 rows = pass)
select incident_key, caller_key
from {{ ref('fact_incidents') }} f
left join {{ ref('dim_user') }} u on f.caller_key = u.user_key
where f.caller_key is not null and u.user_key is null
```

**Dynamic Tables have no equivalent.** Quality checks require external tooling, Data Metric Functions (DMFs), or the contract validation pattern used in this demo's `08_contracts.sql`.

### 2. DAG-Based Lineage

dbt's `ref()` function creates an explicit dependency graph:

```
stg_servicenow__users ──► dim_user ──┬──► fact_incidents
                                     ├──► fact_changes
stg_servicenow__incidents ───────────┘    fact_problems
                                          fact_requests
stg_servicenow__cmdb_ci ──► dim_cmdb_ci
```

This DAG is:
- **Visible** via `dbt docs generate && dbt docs serve`
- **Executable** — `dbt build` runs models in dependency order
- **Selectable** — `dbt run --select fact_incidents+` runs a model and everything downstream

### 3. Documentation Generation

`dbt docs` produces a browsable catalog with:
- Model descriptions and column-level documentation
- Lineage graph (interactive)
- Source freshness status
- Test results
- Governance metadata (via `meta` config)

### 4. CI/CD-Native Workflow

```
Developer writes model → Git push → PR triggers dbt build --target ci
→ Tests pass → Reviewer approves → Merge → dbt build --target prod
```

This fits naturally into existing engineering workflows. Every model change is reviewed, tested, and deployed through the same Git pipeline as application code.

### 5. Jinja Macros for Reusable Logic

```sql
{% macro sla_breach_check(priority_column, minutes_column) %}
    case
        when {{ priority_column }} in ('1', '1 - Critical')
            and {{ minutes_column }} > 240 then true
        ...
    end
{% endmacro %}
```

Macros allow business logic (like SLA thresholds) to be defined once and reused across models. Dynamic Tables require copy-pasting SQL or using stored procedures.

### 6. Cross-Warehouse Portability

dbt runs on Snowflake, BigQuery, Redshift, Databricks, and more. Organizations with multi-cloud or multi-warehouse strategies can use the same transformation layer everywhere. Dynamic Tables are Snowflake-exclusive.

---

## What Dynamic Tables Bring

### 1. Zero-Orchestration

No scheduler. No CI/CD pipeline for refresh. No monitoring of job queues. You write:

```sql
CREATE DYNAMIC TABLE dim_customer
    TARGET_LAG = '1 hour'
    WAREHOUSE = TRANSFORM_WH
AS SELECT ... FROM raw.customers;
```

Snowflake handles when and how to refresh. This is a fundamentally different operational model — there's nothing to break, nothing to schedule, nothing to monitor (beyond the table itself).

### 2. Declarative Freshness SLAs

`TARGET_LAG` is a first-class SLA primitive:

| Table | TARGET_LAG | Meaning |
|-------|-----------|---------|
| FACT_INCIDENTS | 15 minutes | Near-real-time incident tracking |
| DIM_CUSTOMER | 1 hour | Hourly customer refresh |
| DIM_PRODUCT | 24 hours | Daily product updates |

dbt requires external scheduling (cron, Airflow, dbt Cloud) to achieve similar SLAs, and freshness is checked after-the-fact rather than guaranteed.

### 3. Automatic Incremental Processing

Dynamic Tables automatically determine whether to do a full refresh or incremental update. No developer intervention. dbt requires explicit incremental model configuration:

```sql
-- dbt incremental model (developer must write this logic)
{{ config(materialized='incremental', unique_key='id') }}
select * from {{ source('raw', 'events') }}
{% if is_incremental() %}
    where updated_at > (select max(updated_at) from {{ this }})
{% endif %}
```

### 4. Simpler Operational Footprint

| Concern | Dynamic Tables | dbt |
|---------|---------------|-----|
| Scheduler | None needed | Airflow / dbt Cloud / cron |
| Compute | Auto-managed | Must size warehouses for dbt runs |
| Monitoring | `DYNAMIC_TABLE_REFRESH_HISTORY()` | dbt Cloud / custom dashboards |
| Failure recovery | Automatic retry | Manual re-run or alerting |

### 5. Deep Snowflake Integration

Dynamic Tables natively integrate with Snowflake's:
- Micro-partitioning and query optimization
- Time Travel and Fail-safe
- Object-level governance tags
- ACCESS_HISTORY lineage

---

## When to Use Which

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                         DECISION FRAMEWORK                                     │
├────────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│  USE dbt WHEN:                          USE DYNAMIC TABLES WHEN:               │
│  ─────────────                          ────────────────────────               │
│                                                                                │
│  • Team already has dbt expertise       • Team wants minimal operational       │
│    and existing dbt projects              overhead                             │
│                                                                                │
│  • Heavy testing requirements           • Near-real-time freshness SLAs        │
│    (regulatory, contractual)              (TARGET_LAG < 1 hour)                │
│                                                                                │
│  • Multi-warehouse strategy             • Simple pass-through or light         │
│    (Snowflake + BigQuery, etc.)           transformations                      │
│                                                                                │
│  • Complex business logic that          • Team is Snowflake-native and         │
│    benefits from version-controlled       prefers fewer tools                  │
│    Jinja macros                                                                │
│                                                                                │
│  • CI/CD-driven deployment is           • No existing scheduler                │
│    already established                    infrastructure                       │
│                                                                                │
│  • Auto-generated documentation         • Rapid prototyping (just write SQL)   │
│    and lineage are high priority                                               │
│                                                                                │
│  • Source freshness checks and          • Dozens of similar tables that         │
│    data quality gates in pipeline         can be config-driven                 │
│                                                                                │
└────────────────────────────────────────────────────────────────────────────────┘
```

---

## The Hybrid Architecture (This Demo)

This demo proves that dbt and Dynamic Tables coexist cleanly. Here's how:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                      HYBRID TRANSFORMATION ARCHITECTURE                          │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐     │
│  │                         RAW LAYER (Bronze)                              │     │
│  │  RAW_DEV.SAP │ RAW_DEV.SALESFORCE │ RAW_DEV.ORACLE │ RAW_DEV.FHIR     │     │
│  │  RAW_DEV.WORKDAY │ RAW_DEV.SERVICENOW                                  │     │
│  │                                                                         │     │
│  │  All source systems land here via INFER_SCHEMA + SCD Type 2             │     │
│  └────────────────────────┬────────────────────────┬───────────────────────┘     │
│                           │                        │                             │
│              ┌────────────┴──────────┐    ┌────────┴────────────┐                │
│              │                       │    │                     │                │
│              ▼                       │    ▼                     │                │
│  ┌───────────────────────┐           │  ┌───────────────────────┐                │
│  │   DYNAMIC TABLES      │           │  │   dbt PROJECT         │                │
│  │   (5 source systems)  │           │  │   (ServiceNow)        │                │
│  │                       │           │  │                       │                │
│  │  • SAP S/4HANA        │           │  │  staging/             │                │
│  │  • Salesforce         │           │  │   stg_servicenow__*   │                │
│  │  • Oracle EBS         │           │  │                       │                │
│  │  • FHIR R4            │           │  │  marts/dimensions/    │                │
│  │  • Workday            │           │  │   dim_user             │                │
│  │                       │           │  │   dim_cmdb_ci          │                │
│  │  Config-driven via    │           │  │                       │                │
│  │  CURATED_CONFIG table │           │  │  marts/facts/         │                │
│  │  TARGET_LAG SLAs      │           │  │   fact_incidents       │                │
│  │  ~30 dim/fact tables  │           │  │   fact_changes         │                │
│  │                       │           │  │   fact_problems        │                │
│  │  Refresh: Automatic   │           │  │   fact_requests        │                │
│  │  Tests: None built-in │           │  │                       │                │
│  │  Docs: Table comments │           │  │  Refresh: dbt run     │                │
│  │                       │           │  │  Tests: dbt test       │                │
│  └───────────┬───────────┘           │  │  Docs: dbt docs        │                │
│              │                       │  │  Lineage: ref() DAG    │                │
│              │                       │  └───────────┬───────────┘                │
│              │                       │              │                             │
│              └───────────────────────┴──────────────┘                             │
│                                      │                                           │
│                                      ▼                                           │
│  ┌─────────────────────────────────────────────────────────────────────────┐     │
│  │                     CURATED LAYER (Silver)                              │     │
│  │  CURATED_DEV.SAP │ CURATED_DEV.SALESFORCE │ CURATED_DEV.ORACLE         │     │
│  │  CURATED_DEV.FHIR │ CURATED_DEV.WORKDAY │ CURATED_DEV.DBT_SERVICENOW  │     │
│  │                                                                         │     │
│  │  All tables look the same to consumers — regardless of engine           │     │
│  └────────────────────────────────┬────────────────────────────────────────┘     │
│                                   │                                              │
│                                   ▼                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐     │
│  │                     SEMANTIC LAYER (Gold)                               │     │
│  │  Semantic Views │ Cortex Analyst │ Marketplace Data Products            │     │
│  │                                                                         │     │
│  │  Consumers don't know (or care) which engine produced the data          │     │
│  └─────────────────────────────────────────────────────────────────────────┘     │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Key Design Principle

**The consumer doesn't care which engine produced the data.** Semantic Views, Cortex Analyst, and Marketplace data products work identically whether the underlying table is a Dynamic Table or a dbt-materialized table. The transformation engine is a producer concern, not a consumer concern.

---

## The dbt ServiceNow Pipeline in This Demo

### Project Structure

```
dbt_servicenow/
├── dbt_project.yml              # Project config (materialization, schemas)
├── profiles.yml.example         # Snowflake connection template
├── models/
│   ├── staging/                 # Thin views — rename, filter, type-cast
│   │   ├── _sources.yml         # Source definitions + freshness checks
│   │   ├── _stg_servicenow.yml  # Staging model tests + docs
│   │   ├── stg_servicenow__users.sql
│   │   ├── stg_servicenow__incidents.sql
│   │   ├── stg_servicenow__changes.sql
│   │   ├── stg_servicenow__problems.sql
│   │   ├── stg_servicenow__cmdb_ci.sql
│   │   └── stg_servicenow__requests.sql
│   └── marts/                   # Business-ready tables — joins, metrics
│       ├── _marts_servicenow.yml  # Mart model tests + docs
│       ├── dimensions/
│       │   ├── dim_user.sql
│       │   └── dim_cmdb_ci.sql
│       └── facts/
│           ├── fact_incidents.sql   # SLA breach detection
│           ├── fact_changes.sql
│           ├── fact_problems.sql
│           └── fact_requests.sql
├── tests/
│   └── assert_no_orphaned_incidents.sql  # Custom referential integrity test
└── macros/
    └── generate_sla_thresholds.sql       # Reusable SLA logic
```

### Running the Pipeline

```bash
cd dbt_servicenow

# Install dependencies (if using packages)
dbt deps

# Run all models (staging views + mart tables)
dbt run

# Run tests (schema + custom)
dbt test

# Build = run + test in dependency order
dbt build

# Generate and serve documentation
dbt docs generate
dbt docs serve

# Check source freshness against SLA targets
dbt source freshness

# Run just the incident pipeline and its upstream
dbt build --select +fact_incidents
```

### DAG Visualization

When you run `dbt docs serve`, you see the full lineage graph:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  ServiceNow dbt DAG                                                          │
│                                                                              │
│  SOURCES (RAW_DEV.SERVICENOW)                                                │
│  ═══════════════════════════                                                 │
│  SYS_USER ─────────────► stg_servicenow__users ──────► dim_user ──┐          │
│  INCIDENT ─────────────► stg_servicenow__incidents ───────────────┼► fact_*  │
│  CHANGE_REQUEST ───────► stg_servicenow__changes ─────────────────┘          │
│  PROBLEM ──────────────► stg_servicenow__problems                            │
│  CMDB_CI ──────────────► stg_servicenow__cmdb_ci ────► dim_cmdb_ci           │
│  SC_REQUEST ───────────► stg_servicenow__requests                            │
│                                                                              │
│  6 sources → 6 staging views → 2 dimensions + 4 facts = 12 models           │
│  23 schema tests + 1 custom test + 7 source freshness checks                │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## For Teams Already Using dbt

If your organization already has dbt in production, the DCA architecture welcomes it:

1. **Keep your existing dbt projects.** They become domain-specific transformation pipelines within the DCA, writing to the CURATED layer just like Dynamic Tables do.

2. **dbt tests replace (or complement) data contracts.** The `schema.yml` tests in dbt serve the same purpose as the contract validation in `08_contracts.sql`. Teams can choose which enforcement mechanism fits their workflow.

3. **dbt source freshness maps to SLA contracts.** The `freshness` config in `_sources.yml` is functionally equivalent to the SLA monitoring views in the governance layer.

4. **dbt docs integrate with the data marketplace.** The auto-generated catalog provides discovery and documentation that complements the Snowflake-native marketplace listings.

5. **No migration required.** You don't need to convert Dynamic Tables to dbt or vice versa. Each source system can use whichever engine its owning team prefers.

---

## Summary

| Question | Answer |
|----------|--------|
| Can dbt and Dynamic Tables coexist? | Yes — this demo proves it |
| Should I migrate from Dynamic Tables to dbt? | Only if you need dbt's testing, docs, or portability |
| Should I migrate from dbt to Dynamic Tables? | Only if you want zero-ops and Snowflake-native SLAs |
| What does the consumer see? | Identical tables in the CURATED layer — engine-agnostic |
| What should new teams pick? | Depends on existing skills, tooling, and operational preferences |
