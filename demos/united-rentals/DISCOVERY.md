# United Rentals — Discovery & Current State

> Synthesized from: Technical Discovery Kickoff (Dec 2025), Strategic Discovery Framework, Architecture Suggestions Assessment

## Executive Summary

United Rentals' Snowflake environment was inherited from a Teradata "lift and shift" migration. The platform now spans three physically separate accounts with no established SDLC pattern to move work between them. The Discovery account (AI/experimental) and Production account (business-critical EDW) operate with different authentication models, different naming conventions, and different governance approaches — creating significant manual overhead ("heroics") whenever work needs to cross account boundaries.

The primary objective is to **harmonize Discovery and Production** into a unified federated platform that enables a seamless path from experimental AI/ML work to production-grade data products.

## Current State Architecture

### Three-Account Topology

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          CURRENT STATE                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ACCOUNT 1: EDW PRODUCTION              ACCOUNT 2: EDW DEVELOPMENT      │
│  ┌─────────────────────────────┐        ┌───────────────────────────┐   │
│  │  EDW Database (core)        │        │  Mirror of Production     │   │
│  │  Manning Database           │        │  (Development/Testing)    │   │
│  │  Sales Ops Database         │        │                           │   │
│  │                             │        └───────────────────────────┘   │
│  │  Auth: Local + Service Accts│                                        │
│  │  ELT:  Wherescape Red       │                                        │
│  │ Ingest: Precisely → Fivetran│        ACCOUNT 3: DISCOVERY            │
│  │  Users: Admin/System only   │        ┌───────────────────────────┐   │
│  └──────────────┬──────────────┘        │  Skunkworks / AI / ML     │   │
│                 │                       │  Cortex AI experiments    │   │
│                 │  Data Share           │                           │   │
│                 └───────────────────────│  Auth: SSO + OAuth        │   │
│                                         │  Security: Row-Level (RLS)│   │
│                                         │  Users: Branch employees  │   │
│                                         └───────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

### Account Details

| Account | Current Name | Proposed Name | Purpose | Auth Model | Key Tools |
|---------|-------------|---------------|---------|------------|-----------|
| 1 | EDW Production | Snowflake Production | Business-critical reporting, operational metrics | Local auth, service accounts | Wherescape Red, Fivetran |
| 2 | EDW Development | Snowflake Development | Dev mirror of Production | Mirrors Prod | Wherescape Red |
| 3 | Discovery | Discovery | Experimental analytics, AI/ML (Cortex), branch-level access | SSO/OAuth, RLS | Cortex AI, notebooks |

### Data Flow

```
ERP / Source Systems
        │
        │  Fivetran (replacing Precisely)
        ▼
┌──────────────────┐     Data Share      ┌──────────────────┐
│  EDW PRODUCTION  │ ──────────────────► │    DISCOVERY     │
│  (Source of Truth)│                    │  (Read-only copy)│
└──────────────────┘                     └──────────────────┘
        │
        │  Manual replication
        ▼
┌──────────────────┐
│  EDW DEVELOPMENT │
│  (Dev/Test mirror)│
└──────────────────┘
```

## Key Challenges — "The Heroics"

### 1. The Path-to-Production Gap

**Problem**: There is no established SDLC pattern to move successful experiments from the Discovery account to Production. Objects and naming conventions differ significantly between the two environments, making migration manual and painful.

**Impact**: Successful AI MVPs built with Cortex in Discovery are stranded — they cannot be operationalized into Production without significant rework.

**DCA Solution**: CI/CD pipeline with Git integration, promotion roles, and automated testing gates. See [SDLC_ARCHITECTURE.md](../../docs/SDLC_ARCHITECTURE.md).

### 2. Governance vs. Autonomy

**Problem**: Non-DBA teams (Manning, Sales Ops) are managing their own environments within the Production account. UR needs a strategy to give these teams dev/prod capabilities without losing platform governance or allowing uncontrolled data duplication.

**Impact**: Teams either wait in ticket queues for DBA support or create shadow databases without governance oversight.

**DCA Solution**: Container-by-DB (Database-as-a-Container) model where each domain gets RAW/CURATED/SEMANTIC databases with autonomous management but federated governance. See [ARCHITECTURE.md](../../docs/ARCHITECTURE.md).

### 3. Inconsistent Security Models (RBAC)

**Problem**: Discovery uses SSO/OAuth with row-level security and individual employee accounts. EDW Production uses local authentication with primarily admin/service account access. Role hierarchies differ completely.

**Impact**: Users cannot move between environments without context-switching auth methods. Role harmonization is manual and error-prone.

**DCA Solution**: Unified Identity Plane with SSO across all accounts, harmonized RBAC/ABAC hierarchy. See [GOVERNANCE.md](../../docs/GOVERNANCE.md).

### 4. Lineage Visibility Loss

**Problem**: When data is shared across accounts, lineage is lost. UR cannot trace data from a report in Discovery back to the DDL in Production/Wherescape Red.

**Impact**: Compliance risk, debugging difficulty, and inability to perform impact analysis across the full data lifecycle.

**DCA Solution**: Snowflake Horizon catalog with ACCESS_HISTORY, data contracts that encode lineage expectations. See [ARCHITECTURE.md](../../docs/ARCHITECTURE.md).

### 5. Legacy ELT Dependency

**Problem**: Wherescape Red handles all transformation logic and code promotion between environments. This is a legacy tool from the Teradata era that creates vendor lock-in and limits modern CI/CD practices.

**Impact**: Transformation logic is trapped in a proprietary tool, making it difficult to adopt cloud-native patterns.

**DCA Solution**: Replace with Dynamic Tables (declarative, zero-orchestration) and/or dbt (code-first, Git-native). See [DBT_VS_DYNAMIC_TABLES.md](../../docs/DBT_VS_DYNAMIC_TABLES.md).

## Architecture Gap Analysis

Identified gaps in the current architecture with recommended remediation:

| Gap | Current State | Snowflake Best Practice | Recommendation |
|-----|--------------|------------------------|----------------|
| **Identity Plane** | Prod uses local auth; Discovery uses SSO. Security mismatch across accounts. | Single Identity Provider (IdP) across all accounts. RBAC/ABAC harmonization is critical tech debt to address early. | Implement SSO layer wrapping both Production and Discovery. Design role hierarchy spanning Prod through Dev with isolation for compliance and SDLC. |
| **SDLC Bridge** | No visual or automated path to promote experiments from Discovery to Production. | Formal CI/CD pipeline using Git integration or Snowflake Native Apps. | Automated promotion pipeline (Git Actions/Terraform/Jenkins) from Discovery → Dev → Prod, governed by a "Promotion Role." |
| **Governance Metadata** | Lineage lost when data is shared across accounts. Unclear how Alation integration supports cross-system lineage. | Snowflake Horizon for single-pane-of-glass lineage and auditing within Snowflake. Partner tools (Alation) for cross-platform lineage. | Centralized Data Catalog powered by Snowflake Horizon leveraging ACCESS_HISTORY for automated end-to-end lineage from Fivetran ingestion to Cortex AI outputs. |
| **Tenant Isolation** | Manning and Sales Ops share Prod space but lack their own dev/prod cycles. | Database-as-a-Container with zero-copy cloning for instant, cost-effective logical isolation. | Dedicated databases for Manning and Sales Ops, each with local dev schemas. Code/Workspaces controlled in separate Git repos with Ops managing migrations. |
| **Cortex AI Pipeline** | All Discovery work and AI MVPs have no path from development to production. | Feature Store and model registry in Prod, accessible to Discovery. Map to SDLC pattern for migration. | Cortex AI Services block in Prod hosting models promoted from Discovery. Alternatively, publish to internal marketplace for consumer testing. |
| **Data Engineering** | Legacy Wherescape Red ELT. Fivetran replacing Precisely for ingestion but transformation tooling unchanged. | Fivetran for ingestion/connectors. Modern transformation via Snowflake-native or code-first tools. | Replace legacy lift-and-shift structures with Dynamic Tables and/or dbt for automated, declarative paths from raw to curated data. Establishes repeatable Path to Production for AI MVPs. |

## Discovery Question Framework

The following framework is tailored for major equipment rental companies. Use it to guide discovery conversations — business first, then operational reality, then architecture.

### 1. Business & Executive Context

- What are the top 3 outcomes the business is pushing for this year? (Utilization, margin, growth, customer experience, risk, cash flow, ESG?)
- Where do leaders feel they don't have confidence in the numbers today?
- How do decisions get made when data is late, incomplete, or conflicting?
- Where is the company moving faster than the data platform can support?

### 2. Rental Operations & Fleet Reality

- How do you currently track fleet availability, utilization by asset class, and idle vs. rentable vs. down-for-repair assets?
- How quickly can you answer: "What assets can I rent right now within 50 miles?"
- How do maintenance events, inspections, and downtime flow into analytics today?
- Where do operational teams still rely on spreadsheets or tribal knowledge?

### 3. Systems Landscape

- What are the systems of record? (ERP, Rental management, CMMS, Telematics/IoT, CRM, Billing)
- Which systems own the truth for: Asset master? Customer? Contract terms? Rates and discounts?
- Where do you see data duplication or reconciliation issues?
- Which systems are hardest to integrate or scale?

### 4. Current Data Architecture

- How would you describe your current architecture? (Central warehouse, data lake, hybrid, silos?)
- How long does it take to add a new data source, publish a new metric, or support a new use case?
- Where do pipelines break or lag most often?
- How do you manage historical vs. real-time data today?

### 5. Analytics, Reporting & Metrics

- Are utilization, revenue, and margin defined the same way across teams?
- How many versions of utilization, customer profitability, and fleet ROI exist?
- Where do analysts spend the most time — building insights or fixing data?
- How self-service is analytics for branch managers, regional ops, and finance?

### 6. Governance, Security & Compliance

- How do you control who can see what across regions, customers, and asset classes?
- How do you protect contract pricing, customer PII, and sensitive operational data?
- Are policies embedded in the data platform or enforced downstream in BI tools?
- How confident are you in auditability, lineage, and regulatory readiness?

### 7. AI, Optimization & Advanced Use Cases

- Where are you exploring AI today? (Demand forecasting, dynamic pricing, predictive maintenance, fleet optimization?)
- What limits these initiatives — data access, data quality, trust, or scale?
- How much time do data science teams spend preparing data vs. building models?
- How do models get operationalized back into the business?

### 8. Real-Time & Operational Intelligence

- How important is near-real-time visibility into fleet movement, utilization, and maintenance events?
- How do telematics and IoT data flow today?
- What happens when operations need answers during the rental transaction, not after?

### 9. Scale, Cost & Performance

- How fast is your data volume growing? (Telematics, sensor data, historical rentals?)
- Where do performance or cost concerns show up most?
- How do you isolate compute for finance, ops, and data science?

### 10. Future State Vision

- If this platform worked perfectly, what would be easy that isn't today?
- What would it mean if data was trusted by default, insights were available at the branch level, and AI models could be deployed safely and fast?
- What would leadership say one year from now if this initiative succeeded?
