# Snowflake Data Cloud Architecture — Full Stack Demo

> **People-First, Contract-Driven Data Architecture** — A complete enterprise data platform where teams have autonomy to manage their data, contracts encode intent and agreements, and only validated data flows to production.

## Philosophy

This architecture is built on a fundamental principle: **data serves people, and people must retain control over their data**.

```
┌────────────────────────────────────────────────────────────────────────────┐
│                        THE DATA CLOUD PHILOSOPHY                           │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│   PEOPLE define intent  →  CONTRACTS encode agreements  →  DATA flows      │
│                                                                            │
│   • Teams own their data domains with full autonomy                        │
│   • Contracts establish mutual expectations (quality, schema, SLA)         │
│   • Quality gates enforce standards before production                      │
│   • Governance protects at every boundary                                  │
│   • Cross-account sharing enables true federation                          │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

Whether you operate in a **single Snowflake account** or across **multiple accounts spanning regions and clouds**, this architecture provides the patterns for federated data management with centralized trust.

## Deployment Patterns

This demo supports two reference architectures. See [SDLC_ARCHITECTURE.md](docs/SDLC_ARCHITECTURE.md) for detailed documentation.

### Multi-Account Architecture

For organizations requiring strong isolation between business units, regions, or environments:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  SALES_PROD     │    │   HR_PROD       │    │ FINANCE_PROD    │
│  (US Region)    │    │  (EU Region)    │    │  (US Region)    │
└────────┬────────┘    └────────┬────────┘    └────────┬────────┘
         │    Secure Shares     │                      │
         └──────────────────────┼──────────────────────┘
                                ▼
┌───────────────────────────────────────────────────────────────┐
│              CORPORATE DATA HUB (Consumer Account)            │
└───────────────────────────────────────────────────────────────┘
```

### Single-Account Architecture

For organizations preferring centralized management with logical separation via RBAC/ABAC:

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                           SNOWFLAKE ACCOUNT                                   │
│                                                                               │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │                      PRODUCTION DATABASES                               │  │
│  │  RAW_PROD │ CURATED_PROD │ SEMANTIC_PROD │ GOVERNANCE                   │  │
│  └──────────────────────────────┬──────────────────────────────────────────┘  │
│                                 │ Zero-Copy Clones                            │
│                   ┌─────────────┼─────────────┐                               │
│                   ▼             ▼             ▼                               │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │                    TEAM DEVELOPMENT DATABASES                           │  │
│  │                                                                         │  │
│  │  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐            │  │
│  │  │ TEAM_SALES_DEV  │ │  TEAM_HR_DEV    │ │TEAM_FINANCE_DEV │            │  │
│  │  │                 │ │                 │ │                 │            │  │
│  │  │ Team autonomy:  │ │ Team autonomy:  │ │ Team autonomy:  │            │  │
│  │  │ • Own schemas   │ │ • Own schemas   │ │ • Own schemas   │            │  │
│  │  │ • Own contracts │ │ • Own contracts │ │ • Own contracts │            │  │
│  │  │ • Own measures  │ │ • Own measures  │ │ • Own measures  │            │  │
│  │  └─────────────────┘ └─────────────────┘ └─────────────────┘            │  │
│  │                                                                         │  │
│  │  SDLC: Clone → Develop → Validate → PR Review → Promote to Prod         │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
└───────────────────────────────────────────────────────────────────────────────┘
```

**Key Features:**
- **Zero-copy clones** from production for instant, cost-effective development environments
- **Team autonomy** to create schemas, contracts, and semantic measures
- **RBAC/ABAC/CGAC** for fine-grained access control without account proliferation
- **CI/CD promotion gates** with contract validation before production deployment

## Key Capabilities

| Capability | Description |
|------------|-------------|
| **Data Contracts** | Schema, quality, SLA, and governance agreements between producers and consumers |
| **Multi-Account Support** | Cross-region, cross-cloud data sharing with contract validation |
| **Team Autonomy** | Each team manages their data their way, publishing to production via contracts |
| **Medallion Architecture** | RAW → CURATED → SEMANTIC with SCD Type 2 history |
| **Dynamic Tables** | Automated transformation with TARGET_LAG SLAs |
| **Semantic Views** | Native Snowflake Semantic Views for Cortex Analyst |
| **Cortex Analyst** | Natural language to SQL via semantic models |
| **Snowflake Horizon** | Tag-based governance, masking, row-level security |
| **Compliance Framework** | GDPR, HIPAA, FERPA, CCPA, SOC2, PCI-DSS patterns |
| **Data Marketplace** | Secure data products for internal/external consumption |
| **Streamlit in Snowflake** | Interactive demo with role-switching |

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                  SNOWFLAKE DATA CLOUD ARCHITECTURE                          │
│                     People-First, Contract-Driven                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                           PEOPLE LAYER                              │    │
│  │  Data Producers (Teams) │ Data Stewards │ Analysts │ AI Agents      │    │
│  │                                                                     │    │
│  │  Each team has AUTONOMY to manage their data domain                 │    │
│  └──────────────────────────────────┬──────────────────────────────────┘    │
│                                     │                                       │
│                                     ▼                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                        CONTRACT LAYER                               │    │
│  │                                                                     │    │
│  │   ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐   │    │
│  │   │   Schema    │ │   Quality   │ │     SLA     │ │ Governance  │   │    │
│  │   │  Contract   │ │  Contract   │ │  Contract   │ │  Contract   │   │    │
│  │   └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘   │    │
│  │                                                                     │    │
│  │   Contracts are the TRUST BOUNDARY between producers and consumers  │    │
│  └──────────────────────────────────┬──────────────────────────────────┘    │
│                                     │                                       │
│                                     ▼                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                          DATA LAYER                                 │    │
│  │                                                                     │    │
│  │   RAW (Bronze)    →    CURATED (Silver)    →    SEMANTIC (Gold)     │    │
│  │   SCD Type 2           Dynamic Tables           Semantic Views      │    │
│  │   Team-owned           Contract-validated       Consumer-ready      │    │
│  │                                                                     │    │
│  │   Data flows ONLY when contracts are satisfied                      │    │
│  └──────────────────────────────────┬──────────────────────────────────┘    │
│                                     │                                       │
│                                     ▼                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                       GOVERNANCE LAYER                              │    │
│  │                                                                     │    │
│  │   Tags │ Masking │ Row Access │ Compliance │ Audit                  │    │
│  │                                                                     │    │
│  │   Governance protects at EVERY boundary, including contracts        │    │
│  └──────────────────────────────────┬──────────────────────────────────┘    │
│                                     │                                       │
│                                     ▼                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                       CONSUMPTION LAYER                             │    │
│  │                                                                     │    │
│  │   ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────────┐   │    │
│  │   │  CORTEX ANALYST │ │   MARKETPLACE   │ │  CROSS-ACCOUNT     │    │    │
│  │   │  Natural Lang.  │ │  Data Products  │ │   SHARING          │    │    │
│  │   └─────────────────┘ └─────────────────┘ └─────────────────────┘   │    │
│  │                                                                     │    │
│  │   Consumers trust data because contracts guarantee quality          │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Multi-Account Topology

For organizations with multiple Snowflake accounts (regional, business unit, or partner):

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  SALES ACCOUNT  │    │   HR ACCOUNT    │    │ FINANCE ACCOUNT │
│  (US Region)    │    │  (EU Region)    │    │  (US Region)    │
│                 │    │                 │    │                 │
│  Team owns data │    │  Team owns data │    │  Team owns data │
│  Publishes via  │    │  Publishes via  │    │  Publishes via  │
│  contracts      │    │  contracts      │    │  contracts      │
└────────┬────────┘    └────────┬────────┘    └────────┬────────┘
         │                      │                      │
         └──────────────────────┼──────────────────────┘
                                │
                                ▼
┌───────────────────────────────────────────────────────────────────────┐
│                    CORPORATE DATA ACCOUNT (Consumer)                  │
│                                                                       │
│   Inbound Shares → Contract Validation → Curated → Semantic → Apps    │
│                                                                       │
│   Only contract-compliant data is accepted and integrated             │
└───────────────────────────────────────────────────────────────────────┘
```

## Data Contracts

Contracts are explicit agreements between data producers and consumers:

| Contract Type | What It Defines | Example |
|---------------|-----------------|---------|
| **Schema** | Column names, types, keys | `CUSTOMER_ID VARCHAR NOT NULL PRIMARY KEY` |
| **Quality** | Rules with pass thresholds | `email_valid: 99% of emails match regex` |
| **SLA** | Freshness, availability | `Data no older than 4 hours, 99.9% uptime` |
| **Governance** | Classification, compliance | `CONFIDENTIAL, GDPR, US_ONLY residency` |

### Contract Validation Flow

```
Producer Data  →  Schema Check  →  Quality Rules  →  SLA Check  →  Governance
                      ↓                 ↓               ↓             ↓
                   PASS/FAIL        PASS/FAIL       PASS/FAIL     PASS/FAIL
                      ↓                 ↓               ↓             ↓
                      └─────────────────┴───────────────┴─────────────┘
                                              │
                                   ┌──────────┴──────────┐
                                   │                     │
                              ALL PASS              ANY FAIL
                                   │                     │
                                   ▼                     ▼
                           Publish to Share      Quarantine + Alert
```

## Quick Start

### Prerequisites

- Snowflake account with ACCOUNTADMIN role
- Git repository access (GitHub, GitLab, etc.)
- Python 3.9+ (for local data generation)

### Deployment

```sql
-- Run each script in sequence
@sql/01_setup.sql              -- Roles, warehouses, databases, tags
@sql/02_git_integration.sql    -- Git repository connection
@sql/03_raw_layer.sql          -- Dynamic RAW layer infrastructure
@sql/04_load_data.sql          -- Load source system data (auto-infer schema)
@sql/05_curated_layer.sql      -- Dynamic Tables
@sql/06_semantic_layer.sql     -- Native Semantic Views
@sql/07_governance.sql         -- Horizon masking & row access
@sql/08_contracts.sql          -- Data contracts & validation
@sql/09_streamlit_app.sql      -- Deploy Streamlit app
@sql/10_marketplace.sql        -- Data products
```

### Load Source System Data

After generating data, upload to Snowflake and use dynamic schema inference:

```sql
-- Upload files to stage (SnowSQL)
PUT file:///path/to/data/sap_s4hana/*.csv @RAW_DEV.STAGING.DATA_STAGE/sap_s4hana/ AUTO_COMPRESS=TRUE;

-- Auto-create tables with inferred schema
CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SAP', 'KNA1', 'CSV', 'sap_s4hana/KNA1.csv');

-- Or load all tables for a source system at once
CALL RAW_DEV.STAGING.LOAD_SOURCE_SYSTEM('SAP', 'CSV');
```

### Generate Test Data

The data generator produces **source system-specific** synthetic data that mirrors real enterprise systems:

```bash
cd tools
pip install -r requirements.txt

# SAP S/4HANA (KNA1, MARA, VBAK, VBAP, PA0001, PA0002, LFA1, EKKO, BKPF)
python data_generator.py --system sap --domain all --output ../data

# Salesforce (Account, Contact, Opportunity, Case, Lead, Product2, Campaign, Task)
python data_generator.py --system salesforce --domain all --output ../data

# Oracle EBS (HZ_PARTIES, OE_ORDER_*, AP_*, RA_*, GL_JE_LINES, HR_*, MTL_*)
python data_generator.py --system oracle --domain all --output ../data

# FHIR R4 (Patient, Practitioner, Encounter, Condition, Observation, Claim)
python data_generator.py --system fhir --domain all --output ../data

# Workday HCM (Workers, Organizations, Compensation, Time_Off, Benefits)
python data_generator.py --system workday --domain hcm --output ../data

# ServiceNow (incident, change_request, problem, cmdb_ci, sc_request, kb_knowledge)
python data_generator.py --system servicenow --domain itsm --output ../data

# Quick test (1/10th size)
python data_generator.py --system sap --domain all --quick --output ../data
```

See [DATA_GENERATION.md](docs/DATA_GENERATION.md) for full documentation.

## Repository Structure

```
snowflake-dca-fullstack-demo/
│
├── README.md                              # This file
│
├── docs/                                  # Documentation
│   ├── ARCHITECTURE.md                    # People-first, contract-driven architecture
│   ├── SDLC_ARCHITECTURE.md               # Single/multi-account patterns, CI/CD, team autonomy
│   ├── GOVERNANCE.md                      # Compliance framework (GDPR, HIPAA, etc.)
│   ├── DEMO_SCRIPT.md                     # 15-minute demo walkthrough
│   └── SAMPLE_QUESTIONS.md                # Cortex Analyst examples
│
├── sql/                                   # Snowflake SQL Scripts
│   ├── 00_deploy_all.sql                  # Master deployment orchestrator
│   ├── 01_setup.sql                       # Roles, warehouses, databases, tags
│   ├── 02_git_integration.sql             # Git repository connection
│   ├── 03_raw_layer.sql                   # RAW tables with SCD Type 2
│   ├── 04_load_data.sql                   # Data loading procedures
│   ├── 05_curated_layer.sql               # Dynamic Tables
│   ├── 06_semantic_layer.sql              # Native Semantic Views
│   ├── 07_governance.sql                  # Horizon policies
│   ├── 08_contracts.sql                   # Data contracts & validation
│   ├── 09_streamlit_app.sql               # Streamlit deployment
│   ├── 10_marketplace.sql                 # Data product creation
│   └── 99_cleanup.sql                     # Complete teardown
│
├── streamlit/                             # Streamlit Application
│   └── app.py                             # Demo app with Cortex & governance
│
├── tools/                                 # Python Utilities
│   ├── data_generator.py                  # Source system-aware data generator
│   ├── requirements.txt                   # Python dependencies
│   └── __init__.py
│
├── data/                                  # Generated data (gitignored)
│   ├── sap_s4hana/                        # SAP ECC/S4HANA tables
│   ├── salesforce/                        # Salesforce objects
│   ├── oracle_ebs/                        # Oracle EBS tables
│   ├── fhir_r4/                           # HL7 FHIR resources
│   ├── workday/                           # Workday HCM reports
│   └── servicenow/                        # ServiceNow tables
│
└── docs/
    └── DATA_GENERATION.md                 # Source system documentation
```

## Compliance Framework

| Regulation | Region | Implementation |
|------------|--------|----------------|
| **GDPR** | EU | `RESIDENCY_REGION='EU_ONLY'`, consent tracking, right to erasure |
| **HIPAA** | US | `HIPAA_CATEGORY` tags, PHI masking, audit trails |
| **FERPA** | US | `FERPA_CATEGORY` tags, educational record protection |
| **CCPA** | California | Consent management, data deletion support |
| **PCI-DSS** | Global | Credit card masking (never full number visible) |
| **SOC2** | Global | Access controls, availability monitoring |

## Governance Tags

| Tag | Purpose | Values |
|-----|---------|--------|
| `DATA_CLASSIFICATION` | Sensitivity level | PUBLIC, INTERNAL, CONFIDENTIAL, RESTRICTED |
| `PII_TYPE` | Personal info type | NONE, INDIRECT, DIRECT, SENSITIVE |
| `AI_ALLOWED` | AI/ML eligibility | TRUE, FALSE, PSEUDONYMIZED, AGGREGATED |
| `RESIDENCY_REGION` | Data sovereignty | GLOBAL, US_ONLY, EU_ONLY, ORIGIN |
| `COMPLIANCE_FRAMEWORK` | Applicable regs | GDPR, HIPAA, FERPA, CCPA, PCI, SOC2 |

## Role Hierarchy

```
                            ACCOUNTADMIN
                                  │
                             DATA_ADMIN ◄── Owns all demo objects
                                  │
          ┌───────────────────────┼───────────────────────┐
          │                       │                       │
     DATA_ENGINEER           DATA_STEWARD            PII_VIEWER
          │                       │                       │
          │          ┌────────────┼────────────┐          │
          │          │            │            │          │
          │      ANALYST      MANAGER      AUDITOR        │
          │          │            │            │          │
          │          └──────┬─────┴──────┬─────┘          │
          │                 │            │                │
          └─────────►   VIEWER     EXTERNAL_PARTNER  ◄────┘
                            │
                        AI_AGENT
```

## Documentation

- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — People-first, contract-driven design
- [SDLC_ARCHITECTURE.md](docs/SDLC_ARCHITECTURE.md) — Single-account & multi-account deployment patterns, CI/CD, team autonomy
- [DATA_GENERATION.md](docs/DATA_GENERATION.md) — Source system data generation (SAP, Salesforce, Oracle, FHIR, Workday, ServiceNow)
- [GOVERNANCE.md](docs/GOVERNANCE.md) — Compliance framework details
- [DEMO_SCRIPT.md](docs/DEMO_SCRIPT.md) — 15-minute demo walkthrough
- [SAMPLE_QUESTIONS.md](docs/SAMPLE_QUESTIONS.md) — Cortex Analyst examples

## Resources

- [Snowflake Horizon](https://www.snowflake.com/en/data-cloud/horizon/)
- [Dynamic Tables](https://docs.snowflake.com/en/user-guide/dynamic-tables-intro)
- [Semantic Views](https://docs.snowflake.com/en/sql-reference/sql/create-semantic-view)
- [Cortex Analyst](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst)
- [Data Sharing](https://docs.snowflake.com/en/user-guide/data-sharing-intro)
- [Cross-Region Replication](https://docs.snowflake.com/en/user-guide/database-replication-intro)
- [Git Integration](https://docs.snowflake.com/en/developer-guide/git/git-setting-up)

## License

MIT License — See LICENSE file for details.
