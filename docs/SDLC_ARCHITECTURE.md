# SDLC & Reference Architectures

> **Deployment Patterns for Enterprise Snowflake** — Whether you operate in a single account or across multiple accounts, this guide provides reference architectures for Software Development Lifecycle (SDLC), team autonomy, and production promotion with appropriate governance.

---

## Table of Contents

1. [Overview](#overview)
2. [Multi-Account Architecture](#multi-account-architecture)
3. [Single-Account Architecture](#single-account-architecture)
4. [SDLC & CI/CD Patterns](#sdlc--cicd-patterns)
5. [Choosing Your Architecture](#choosing-your-architecture)

---

## Overview

Organizations deploying Snowflake face a fundamental architecture decision: **single account** vs **multiple accounts**. Both approaches are valid, and the choice depends on organizational structure, compliance requirements, and operational maturity.

| Aspect | Multi-Account | Single-Account |
|--------|---------------|----------------|
| **Isolation** | Complete account-level separation | Database/schema-level separation |
| **Governance** | Account-level policies | Role-based policies |
| **Cost Management** | Separate billing per account | Centralized with resource monitors |
| **Complexity** | Higher (shares, replication) | Lower (roles, grants) |
| **Best For** | Regulated industries, M&A, global orgs | Mid-size orgs, unified teams |

---

## Multi-Account Architecture

For organizations requiring **strong isolation** between business units, regions, or environments.

### Reference Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                      MULTI-ACCOUNT REFERENCE ARCHITECTURE                       │
│                         Environment & Team Separation                           │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │                        PRODUCTION ACCOUNTS                                │  │
│  │                                                                           │  │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐            │  │
│  │  │  SALES_PROD     │  │   HR_PROD       │  │ FINANCE_PROD    │            │  │
│  │  │  (US-WEST-2)    │  │  (EU-WEST-1)    │  │  (US-EAST-1)    │            │  │
│  │  │                 │  │                 │  │                 │            │  │
│  │  │  Team owns data │  │  GDPR compliant │  │  SOX compliant  │            │  │
│  │  │  Publishes via  │  │  EU residency   │  │  Audit trails   │            │  │
│  │  │  contracts      │  │  contracts      │  │  contracts      │            │  │
│  │  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘            │  │
│  │           │                    │                    │                     │  │
│  │           │   Secure Shares    │   Secure Shares    │                     │  │
│  │           └────────────────────┼────────────────────┘                     │  │
│  │                                │                                          │  │
│  │                                ▼                                          │  │
│  │  ┌───────────────────────────────────────────────────────────────────┐    │  │
│  │  │              CORPORATE DATA ACCOUNT (Consumer Hub)                │    │  │
│  │  │                                                                   │    │  │
│  │  │   Inbound Shares → Contract Validation → Curated → Semantic       │    │  │
│  │  │                                                                   │    │  │
│  │  │   • Enterprise-wide analytics                                     │    │  │
│  │  │   • Cross-domain joins                                            │    │  │
│  │  │   • Data marketplace                                              │    │  │
│  │  │   • Cortex Analyst                                                │    │  │
│  │  └───────────────────────────────────────────────────────────────────┘    │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │                      DEVELOPMENT ACCOUNTS (per team)                      │  │
│  │                                                                           │  │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐            │  │
│  │  │  SALES_DEV      │  │   HR_DEV        │  │ FINANCE_DEV     │            │  │
│  │  │                 │  │                 │  │                 │            │  │
│  │  │  Cloned from    │  │  Cloned from    │  │  Cloned from    │            │  │
│  │  │  SALES_PROD     │  │  HR_PROD        │  │  FINANCE_PROD   │            │  │
│  │  │                 │  │                 │  │                 │            │  │
│  │  │  • Feature dev  │  │  • Feature dev  │  │  • Feature dev  │            │  │
│  │  │  • Testing      │  │  • Testing      │  │  • Testing      │            │  │
│  │  │  • CI/CD        │  │  • CI/CD        │  │  • CI/CD        │            │  │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘            │  │
│  │                                                                           │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │                           SDLC FLOW                                       │  │
│  │                                                                           │  │
│  │   DEV Account ──► Git Branch ──► PR Review ──► QA/UAT ──► PROD Account    │  │
│  │                                                                           │  │
│  │   Cross-account replication for promotion                                 │  │
│  │   Contract validation at each gate                                        │  │
│  │                                                                           │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Multi-Account Benefits

1. **Complete Isolation** — Billing, security, and governance are entirely separate
2. **Regional Compliance** — Data residency requirements are naturally enforced
3. **Blast Radius** — Failures or security incidents are contained
4. **M&A Ready** — Acquired companies can operate independently

### Multi-Account Challenges

1. **Operational Complexity** — More accounts to manage, monitor, and secure
2. **Cross-Account Sharing** — Requires shares, listings, or replication
3. **Cost Visibility** — Harder to see unified spend without tooling
4. **Schema Drift** — Teams may diverge without strong governance

---

## Single-Account Architecture

For organizations that prefer **centralized management** with **logical separation** via RBAC, ABAC, and Column/Row-Level Security.

### Reference Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                     SINGLE-ACCOUNT REFERENCE ARCHITECTURE                       │
│                  Team Autonomy with Centralized Governance                      │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │                         SNOWFLAKE ACCOUNT                                 │  │
│  │                                                                           │  │
│  │  ┌─────────────────────────────────────────────────────────────────────┐  │  │
│  │  │                      PRODUCTION DATABASES                           │  │  │
│  │  │                                                                     │  │  │
│  │  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐   │  │  │
│  │  │  │ RAW_PROD    │ │ CURATED_PROD│ │SEMANTIC_PROD│ │ GOVERNANCE  │   │  │  │
│  │  │  │             │ │             │ │             │ │             │   │  │  │
│  │  │  │ Source data │ │ Dynamic     │ │ Semantic    │ │ Contracts   │   │  │  │
│  │  │  │ SCD Type 2  │ │ Tables      │ │ Views       │ │ Policies    │   │  │  │
│  │  │  │             │ │             │ │             │ │ Tags        │   │  │  │
│  │  │  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘   │  │  │
│  │  │                                                                     │  │  │
│  │  │  Owner: DATA_ADMIN    Modify: DATA_ENGINEER    Read: ANALYST       │  │  │
│  │  └──────────────────────────────────┬──────────────────────────────────┘  │  │
│  │                                     │                                     │  │
│  │                              ZERO-COPY CLONES                             │  │
│  │                                     │                                     │  │
│  │                   ┌─────────────────┼─────────────────┐                   │  │
│  │                   │                 │                 │                   │  │
│  │                   ▼                 ▼                 ▼                   │  │
│  │  ┌─────────────────────────────────────────────────────────────────────┐  │  │
│  │  │                   DEVELOPMENT DATABASES (per team)                  │  │  │
│  │  │                                                                     │  │  │
│  │  │  ┌───────────────────────────────────────────────────────────────┐  │  │  │
│  │  │  │              TEAM_SALES_DEV (Cloned from PROD)                │  │  │  │
│  │  │  │                                                               │  │  │  │
│  │  │  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐              │  │  │  │
│  │  │  │  │ RAW         │ │ CURATED     │ │ SANDBOX     │◄── Team's   │  │  │  │
│  │  │  │  │ (clone)     │ │ (clone)     │ │ (new work)  │    own work │  │  │  │
│  │  │  │  └─────────────┘ └─────────────┘ └─────────────┘              │  │  │  │
│  │  │  │                                                               │  │  │  │
│  │  │  │  Team can create: schemas, tables, views, procedures, UDFs    │  │  │  │
│  │  │  │  Team can define: contracts, measures, semantic models        │  │  │  │
│  │  │  │                                                               │  │  │  │
│  │  │  │  Owner: SALES_TEAM_ROLE                                       │  │  │  │
│  │  │  └───────────────────────────────────────────────────────────────┘  │  │  │
│  │  │                                                                     │  │  │
│  │  │  ┌───────────────────────────────────────────────────────────────┐  │  │  │
│  │  │  │              TEAM_HR_DEV (Cloned from PROD)                   │  │  │  │
│  │  │  │                                                               │  │  │  │
│  │  │  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐              │  │  │  │
│  │  │  │  │ RAW         │ │ CURATED     │ │ SANDBOX     │◄── Team's   │  │  │  │
│  │  │  │  │ (clone)     │ │ (clone)     │ │ (new work)  │    own work │  │  │  │
│  │  │  │  └─────────────┘ └─────────────┘ └─────────────┘              │  │  │  │
│  │  │  │                                                               │  │  │  │
│  │  │  │  Owner: HR_TEAM_ROLE                                          │  │  │  │
│  │  │  └───────────────────────────────────────────────────────────────┘  │  │  │
│  │  │                                                                     │  │  │
│  │  │  ┌───────────────────────────────────────────────────────────────┐  │  │  │
│  │  │  │              TEAM_FINANCE_DEV (Cloned from PROD)              │  │  │  │
│  │  │  │                                                               │  │  │  │
│  │  │  │  Similar structure...                                         │  │  │  │
│  │  │  │  Owner: FINANCE_TEAM_ROLE                                     │  │  │  │
│  │  │  └───────────────────────────────────────────────────────────────┘  │  │  │
│  │  │                                                                     │  │  │
│  │  └─────────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                           │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Access Control Model (RBAC/ABAC/CGAC)

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    SINGLE-ACCOUNT ACCESS CONTROL MODEL                          │
│                         RBAC + ABAC + Column/Row Security                       │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │                          ROLE HIERARCHY (RBAC)                            │  │
│  │                                                                           │  │
│  │                              ACCOUNTADMIN                                 │  │
│  │                                    │                                      │  │
│  │                              SYSADMIN                                     │  │
│  │                                    │                                      │  │
│  │                    ┌───────────────┼───────────────┐                      │  │
│  │                    │               │               │                      │  │
│  │              DATA_ADMIN      PLATFORM_ADMIN   SECURITY_ADMIN              │  │
│  │                    │               │               │                      │  │
│  │         ┌──────────┴─────────┬─────┴───────────────┴──────────┐           │  │
│  │         │                    │                                │           │  │
│  │   ┌─────┴─────┐      ┌──────┴──────┐                  ┌───────┴───────┐   │  │
│  │   │   TEAM    │      │    TEAM     │                  │     TEAM      │   │  │
│  │   │  ROLES    │      │   ROLES     │                  │    ROLES      │   │  │
│  │   │           │      │             │                  │               │   │  │
│  │   │SALES_ADMIN│      │  HR_ADMIN   │                  │FINANCE_ADMIN  │   │  │
│  │   │SALES_DEV  │      │  HR_DEV     │                  │FINANCE_DEV    │   │  │
│  │   │SALES_READ │      │  HR_READ    │                  │FINANCE_READ   │   │  │
│  │   └───────────┘      └─────────────┘                  └───────────────┘   │  │
│  │                                                                           │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │                   ATTRIBUTE-BASED ACCESS (ABAC)                           │  │
│  │                                                                           │  │
│  │   ┌─────────────────────────────────────────────────────────────────┐     │  │
│  │   │                    OBJECT TAGS                                  │     │  │
│  │   │                                                                 │     │  │
│  │   │  DATA_CLASSIFICATION: PUBLIC | INTERNAL | CONFIDENTIAL | RESTRICTED  │  │
│  │   │  PII_TYPE:            NONE | INDIRECT | DIRECT | SENSITIVE     │     │  │
│  │   │  DATA_DOMAIN:         SALES | HR | FINANCE | HEALTHCARE        │     │  │
│  │   │  ENVIRONMENT:         DEV | QA | UAT | PROD                    │     │  │
│  │   │  COST_CENTER:         Team-specific cost allocation            │     │  │
│  │   │                                                                 │     │  │
│  │   └─────────────────────────────────────────────────────────────────┘     │  │
│  │                                                                           │  │
│  │   ┌─────────────────────────────────────────────────────────────────┐     │  │
│  │   │                TAG-BASED MASKING POLICIES                       │     │  │
│  │   │                                                                 │     │  │
│  │   │  IF column.PII_TYPE = 'DIRECT' AND NOT current_role() IN       │     │  │
│  │   │     ('PII_VIEWER', 'DATA_ADMIN')                                │     │  │
│  │   │  THEN mask_value()                                              │     │  │
│  │   │                                                                 │     │  │
│  │   └─────────────────────────────────────────────────────────────────┘     │  │
│  │                                                                           │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │               COLUMN/ROW-LEVEL SECURITY (CGAC)                            │  │
│  │                                                                           │  │
│  │   ┌─────────────────────────────────────────────────────────────────┐     │  │
│  │   │                  ROW ACCESS POLICIES                            │     │  │
│  │   │                                                                 │     │  │
│  │   │  SALES team sees only their region's data                       │     │  │
│  │   │  HR team sees only their department's employees                 │     │  │
│  │   │  FINANCE sees aggregated data unless in FINANCE_DETAIL role     │     │  │
│  │   │                                                                 │     │  │
│  │   └─────────────────────────────────────────────────────────────────┘     │  │
│  │                                                                           │  │
│  │   ┌─────────────────────────────────────────────────────────────────┐     │  │
│  │   │                  COLUMN MASKING POLICIES                        │     │  │
│  │   │                                                                 │     │  │
│  │   │  SSN:    ****-**-1234     (last 4 visible)                      │     │  │
│  │   │  Email:  j***@company.com (partial mask)                        │     │  │
│  │   │  Salary: NULL or range    (redacted for non-HR)                 │     │  │
│  │   │                                                                 │     │  │
│  │   └─────────────────────────────────────────────────────────────────┘     │  │
│  │                                                                           │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Team Autonomy Model

Each team gets their own development database where they have full autonomy:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          TEAM AUTONOMY MODEL                                    │
│                   What Teams Own vs. What Platform Owns                         │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │                    TEAM OWNS (in their DEV database)                      │  │
│  │                                                                           │  │
│  │  ┌─────────────────────────────────────────────────────────────────────┐  │  │
│  │  │  SCHEMAS                                                            │  │  │
│  │  │  • SANDBOX          - Experimental work                             │  │  │
│  │  │  • STAGING          - Pre-production testing                        │  │  │
│  │  │  • FEATURE_*        - Feature branch schemas                        │  │  │
│  │  │  • ANALYTICS        - Team-specific analytics                       │  │  │
│  │  └─────────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                           │  │
│  │  ┌─────────────────────────────────────────────────────────────────────┐  │  │
│  │  │  DATA OBJECTS                                                       │  │  │
│  │  │  • Tables, Views, Materialized Views                                │  │  │
│  │  │  • Dynamic Tables (team-defined TARGET_LAG)                         │  │  │
│  │  │  • Streams, Tasks, Pipes                                            │  │  │
│  │  │  • Stored Procedures, UDFs, UDTFs                                   │  │  │
│  │  └─────────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                           │  │
│  │  ┌─────────────────────────────────────────────────────────────────────┐  │  │
│  │  │  CONTRACTS & SEMANTICS                                              │  │  │
│  │  │  • Data contracts (schema, quality, SLA)                            │  │  │
│  │  │  • Semantic models (measures, dimensions)                           │  │  │
│  │  │  • Business glossary terms                                          │  │  │
│  │  │  • Documentation                                                    │  │  │
│  │  └─────────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                           │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │                    PLATFORM OWNS (enforced centrally)                     │  │
│  │                                                                           │  │
│  │  ┌─────────────────────────────────────────────────────────────────────┐  │  │
│  │  │  GOVERNANCE                                                         │  │  │
│  │  │  • Tag definitions (DATA_CLASSIFICATION, PII_TYPE, etc.)            │  │  │
│  │  │  • Masking policies (applied via tags)                              │  │  │
│  │  │  • Row access policies                                              │  │  │
│  │  │  • Compliance frameworks (GDPR, HIPAA, etc.)                        │  │  │
│  │  └─────────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                           │  │
│  │  ┌─────────────────────────────────────────────────────────────────────┐  │  │
│  │  │  SECURITY                                                           │  │  │
│  │  │  • Role hierarchy and inheritance                                   │  │  │
│  │  │  • Network policies                                                 │  │  │
│  │  │  • Authentication (SSO, MFA)                                        │  │  │
│  │  │  • Audit logging configuration                                      │  │  │
│  │  └─────────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                           │  │
│  │  ┌─────────────────────────────────────────────────────────────────────┐  │  │
│  │  │  PRODUCTION PROMOTION                                               │  │  │
│  │  │  • Approval workflows                                               │  │  │
│  │  │  • Contract validation gates                                        │  │  │
│  │  │  • Deployment automation                                            │  │  │
│  │  │  • Rollback procedures                                              │  │  │
│  │  └─────────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                           │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## SDLC & CI/CD Patterns

### Single-Account SDLC Flow

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                     SINGLE-ACCOUNT SDLC WORKFLOW                                │
│                Clone-Based Development with Promotion Gates                     │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌────────────────────────────────────────────────────────────────────────┐     │
│  │ STEP 1: CLONE PRODUCTION TO DEVELOPMENT                                │     │
│  │                                                                        │     │
│  │  ┌──────────────────────────────────────────────────────────────────┐  │     │
│  │  │  -- Team requests development environment (automated)            │  │     │
│  │  │  CREATE DATABASE TEAM_SALES_DEV CLONE RAW_PROD;                  │  │     │
│  │  │  CREATE DATABASE TEAM_SALES_CURATED_DEV CLONE CURATED_PROD;      │  │     │
│  │  │                                                                  │  │     │
│  │  │  -- Zero-copy, instant, cost-effective                          │  │     │
│  │  │  -- Team has full read/write in their clone                      │  │     │
│  │  │  -- Production data is point-in-time snapshot                    │  │     │
│  │  └──────────────────────────────────────────────────────────────────┘  │     │
│  │                                                                        │     │
│  │  PROD ─────────────────► DEV (zero-copy clone)                         │     │
│  │   │                        │                                           │     │
│  │   │ Source of truth        │ Team's sandbox                            │     │
│  │   │ Protected              │ Full autonomy                             │     │
│  │                                                                        │     │
│  └────────────────────────────────────────────────────────────────────────┘     │
│                                                                                 │
│  ┌────────────────────────────────────────────────────────────────────────┐     │
│  │ STEP 2: DEVELOP & TEST                                                 │     │
│  │                                                                        │     │
│  │  ┌──────────────────┐                                                  │     │
│  │  │  Git Repository  │                                                  │     │
│  │  │                  │                                                  │     │
│  │  │  main (prod)     │◄───────────────────┐                             │     │
│  │  │       │          │                    │                             │     │
│  │  │       ├──develop │                    │ PR + Review                 │     │
│  │  │       │    │     │                    │                             │     │
│  │  │       │    ├──feature/new-metric      │                             │     │
│  │  │       │    │                          │                             │     │
│  │  └───────┼────┼──────┘                   │                             │     │
│  │          │    │                          │                             │     │
│  │          │    ▼                          │                             │     │
│  │  ┌───────┴────────────────┐    ┌─────────┴─────────┐                   │     │
│  │  │  TEAM_SALES_DEV DB     │    │  CI/CD Pipeline   │                   │     │
│  │  │                        │    │                   │                   │     │
│  │  │  • New tables          │───►│  • Lint SQL       │                   │     │
│  │  │  • Modified views      │    │  • Run tests      │                   │     │
│  │  │  • New measures        │    │  • Validate       │                   │     │
│  │  │  • Contract drafts     │    │    contracts      │                   │     │
│  │  │                        │    │  • Security scan  │                   │     │
│  │  └────────────────────────┘    └───────────────────┘                   │     │
│  │                                                                        │     │
│  └────────────────────────────────────────────────────────────────────────┘     │
│                                                                                 │
│  ┌────────────────────────────────────────────────────────────────────────┐     │
│  │ STEP 3: PROMOTION GATES (Checks & Balances)                            │     │
│  │                                                                        │     │
│  │  ┌──────────────────────────────────────────────────────────────────┐  │     │
│  │  │                    GATE 1: CONTRACT VALIDATION                   │  │     │
│  │  │                                                                  │  │     │
│  │  │   ✓ Schema matches contract definition                           │  │     │
│  │  │   ✓ All quality rules pass threshold                             │  │     │
│  │  │   ✓ No breaking changes to existing consumers                    │  │     │
│  │  │   ✓ SLA targets are achievable                                   │  │     │
│  │  └──────────────────────────────────────────────────────────────────┘  │     │
│  │                               │                                        │     │
│  │                               ▼                                        │     │
│  │  ┌──────────────────────────────────────────────────────────────────┐  │     │
│  │  │                    GATE 2: GOVERNANCE CHECK                      │  │     │
│  │  │                                                                  │  │     │
│  │  │   ✓ All PII columns are tagged                                   │  │     │
│  │  │   ✓ Masking policies are applied                                 │  │     │
│  │  │   ✓ Data classification is assigned                             │  │     │
│  │  │   ✓ No compliance violations                                     │  │     │
│  │  └──────────────────────────────────────────────────────────────────┘  │     │
│  │                               │                                        │     │
│  │                               ▼                                        │     │
│  │  ┌──────────────────────────────────────────────────────────────────┐  │     │
│  │  │                    GATE 3: PEER REVIEW                           │  │     │
│  │  │                                                                  │  │     │
│  │  │   ✓ Code review by team member                                   │  │     │
│  │  │   ✓ Data steward approval (if governance change)                 │  │     │
│  │  │   ✓ Platform team approval (if infra change)                     │  │     │
│  │  └──────────────────────────────────────────────────────────────────┘  │     │
│  │                               │                                        │     │
│  │                               ▼                                        │     │
│  │  ┌──────────────────────────────────────────────────────────────────┐  │     │
│  │  │                    GATE 4: UAT/STAGING                           │  │     │
│  │  │                                                                  │  │     │
│  │  │   ✓ Deploy to staging environment                                │  │     │
│  │  │   ✓ Run integration tests                                        │  │     │
│  │  │   ✓ Validate downstream impact                                   │  │     │
│  │  │   ✓ Performance benchmarks pass                                  │  │     │
│  │  └──────────────────────────────────────────────────────────────────┘  │     │
│  │                                                                        │     │
│  └────────────────────────────────────────────────────────────────────────┘     │
│                                                                                 │
│  ┌────────────────────────────────────────────────────────────────────────┐     │
│  │ STEP 4: DEPLOY TO PRODUCTION                                           │     │
│  │                                                                        │     │
│  │  ┌──────────────────────────────────────────────────────────────────┐  │     │
│  │  │  -- Automated deployment (after all gates pass)                  │  │     │
│  │  │                                                                  │  │     │
│  │  │  -- Option A: Execute DDL from Git                               │  │     │
│  │  │  EXECUTE IMMEDIATE FROM @git_repo/sql/curated/new_view.sql;      │  │     │
│  │  │                                                                  │  │     │
│  │  │  -- Option B: Clone validated objects                            │  │     │
│  │  │  CREATE OR REPLACE VIEW CURATED_PROD.SALES.NEW_VIEW              │  │     │
│  │  │    CLONE TEAM_SALES_DEV.STAGING.NEW_VIEW;                        │  │     │
│  │  │                                                                  │  │     │
│  │  │  -- Option C: Swap tables (for large changes)                    │  │     │
│  │  │  ALTER TABLE CURATED_PROD.SALES.FACT_SALES                       │  │     │
│  │  │    SWAP WITH TEAM_SALES_DEV.STAGING.FACT_SALES_V2;               │  │     │
│  │  └──────────────────────────────────────────────────────────────────┘  │     │
│  │                                                                        │     │
│  │  DEV ─────────────────► STAGING ─────────────────► PROD                │     │
│  │                                                                        │     │
│  │        All gates passed         Final validation                       │     │
│  │                                                                        │     │
│  └────────────────────────────────────────────────────────────────────────┘     │
│                                                                                 │
│  ┌────────────────────────────────────────────────────────────────────────┐     │
│  │ STEP 5: POST-DEPLOYMENT                                                │     │
│  │                                                                        │     │
│  │  • Update contract registry with new version                           │     │
│  │  • Notify downstream consumers                                         │     │
│  │  • Monitor for issues (automated alerting)                             │     │
│  │  • Drop stale development clones (cost management)                     │     │
│  │                                                                        │     │
│  └────────────────────────────────────────────────────────────────────────┘     │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### CI/CD Pipeline Configuration

```yaml
# .github/workflows/snowflake-deploy.yml
name: Snowflake SDLC Pipeline

on:
  pull_request:
    branches: [develop, main]
  push:
    branches: [main]

env:
  SNOWFLAKE_ACCOUNT: ${{ secrets.SNOWFLAKE_ACCOUNT }}
  SNOWFLAKE_USER: ${{ secrets.SNOWFLAKE_USER }}
  SNOWFLAKE_PRIVATE_KEY: ${{ secrets.SNOWFLAKE_PRIVATE_KEY }}

jobs:
  # Gate 1: Validate SQL and Contracts
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Lint SQL
        run: |
          pip install sqlfluff
          sqlfluff lint sql/ --dialect snowflake
      
      - name: Validate Contracts
        run: |
          python tools/validate_contracts.py \
            --contracts contracts/ \
            --sql sql/
      
      - name: Check for Breaking Changes
        run: |
          python tools/breaking_change_detector.py \
            --base origin/main \
            --head HEAD

  # Gate 2: Governance Check
  governance:
    runs-on: ubuntu-latest
    needs: validate
    steps:
      - uses: actions/checkout@v4
      
      - name: Verify PII Tags
        run: |
          python tools/governance_check.py \
            --check pii-tagging \
            --sql sql/
      
      - name: Verify Masking Policies
        run: |
          python tools/governance_check.py \
            --check masking-policies \
            --sql sql/
      
      - name: Compliance Scan
        run: |
          python tools/compliance_scanner.py \
            --frameworks GDPR,HIPAA,SOC2 \
            --sql sql/

  # Gate 3: Deploy to Staging
  staging:
    runs-on: ubuntu-latest
    needs: governance
    if: github.event_name == 'pull_request'
    environment: staging
    steps:
      - uses: actions/checkout@v4
      
      - name: Deploy to Staging
        run: |
          snowsql -c staging \
            -f sql/deploy_staging.sql \
            -D ENVIRONMENT=staging
      
      - name: Run Integration Tests
        run: |
          python tools/integration_tests.py \
            --environment staging

  # Gate 4: Deploy to Production
  production:
    runs-on: ubuntu-latest
    needs: [validate, governance]
    if: github.ref == 'refs/heads/main'
    environment: production
    steps:
      - uses: actions/checkout@v4
      
      - name: Deploy to Production
        run: |
          snowsql -c production \
            -f sql/deploy_production.sql \
            -D ENVIRONMENT=production
      
      - name: Update Contract Registry
        run: |
          python tools/update_contract_registry.py \
            --version ${{ github.sha }}
      
      - name: Notify Consumers
        run: |
          python tools/notify_consumers.py \
            --contracts contracts/
```

### Contract Validation Gate (Example)

```sql
-- GOVERNANCE.CONTRACTS.VALIDATE_FOR_PROMOTION
CREATE OR REPLACE PROCEDURE GOVERNANCE.CONTRACTS.VALIDATE_FOR_PROMOTION(
    p_source_schema VARCHAR,      -- e.g., 'TEAM_SALES_DEV.STAGING'
    p_target_schema VARCHAR,      -- e.g., 'CURATED_PROD.SALES'
    p_contract_id VARCHAR
)
RETURNS TABLE (
    check_name VARCHAR,
    passed BOOLEAN,
    message VARCHAR,
    severity VARCHAR
)
LANGUAGE SQL
AS
$$
DECLARE
    result RESULTSET;
BEGIN
    -- Collect all validation results
    result := (
        -- Schema validation
        SELECT 
            'SCHEMA_MATCH' AS check_name,
            CASE WHEN COUNT(*) = 0 THEN TRUE ELSE FALSE END AS passed,
            CASE WHEN COUNT(*) = 0 THEN 'Schema matches contract' 
                 ELSE 'Schema mismatch: ' || LISTAGG(column_name, ', ') END AS message,
            'ERROR' AS severity
        FROM (
            SELECT c.column_name
            FROM INFORMATION_SCHEMA.COLUMNS c
            WHERE c.table_schema = SPLIT_PART(:p_source_schema, '.', 2)
            EXCEPT
            SELECT column_name FROM GOVERNANCE.CONTRACTS.CONTRACT_SCHEMA
            WHERE contract_id = :p_contract_id
        )
        
        UNION ALL
        
        -- Quality rules validation
        SELECT 
            'QUALITY_RULES' AS check_name,
            CASE WHEN MIN(pass_rate) >= MIN(threshold) THEN TRUE ELSE FALSE END AS passed,
            CASE WHEN MIN(pass_rate) >= MIN(threshold) 
                 THEN 'All quality rules pass'
                 ELSE 'Quality threshold not met' END AS message,
            'ERROR' AS severity
        FROM GOVERNANCE.CONTRACTS.VALIDATE_QUALITY(:p_contract_id, :p_source_schema)
        
        UNION ALL
        
        -- Breaking change detection
        SELECT
            'NO_BREAKING_CHANGES' AS check_name,
            CASE WHEN COUNT(*) = 0 THEN TRUE ELSE FALSE END AS passed,
            CASE WHEN COUNT(*) = 0 THEN 'No breaking changes detected'
                 ELSE 'Breaking changes: ' || LISTAGG(change_description, '; ') END AS message,
            'ERROR' AS severity
        FROM GOVERNANCE.CONTRACTS.DETECT_BREAKING_CHANGES(:p_source_schema, :p_target_schema)
        
        UNION ALL
        
        -- Governance tagging check
        SELECT
            'GOVERNANCE_TAGS' AS check_name,
            CASE WHEN COUNT(*) = 0 THEN TRUE ELSE FALSE END AS passed,
            CASE WHEN COUNT(*) = 0 THEN 'All columns properly tagged'
                 ELSE 'Untagged PII columns: ' || LISTAGG(column_name, ', ') END AS message,
            'WARNING' AS severity
        FROM (
            SELECT column_name
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE table_schema = SPLIT_PART(:p_source_schema, '.', 2)
              AND column_name IN ('SSN', 'EMAIL', 'PHONE', 'DOB', 'SALARY', 'NATIONAL_ID')
              AND column_name NOT IN (
                  SELECT column_name 
                  FROM TABLE(INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(:p_source_schema || '.%', 'TABLE'))
                  WHERE tag_name = 'PII_TYPE'
              )
        )
    );
    
    RETURN TABLE(result);
END;
$$;
```

---

## Choosing Your Architecture

### Decision Matrix

| Factor | Choose Multi-Account | Choose Single-Account |
|--------|---------------------|----------------------|
| **Regulatory Requirements** | Strict data residency, SOX, HIPAA isolation | Standard compliance, shared policies |
| **Organizational Structure** | Separate BUs, M&A activity, partners | Unified teams, shared resources |
| **Team Maturity** | Independent ops teams per BU | Centralized data platform team |
| **Cost Model** | Separate budgets per BU | Unified cost management |
| **Data Sharing Needs** | Cross-org, external parties | Internal only |
| **Blast Radius Concerns** | High (finance, healthcare) | Moderate |
| **Operational Complexity Tolerance** | High | Lower |

### Hybrid Approach

Many organizations use a **hybrid approach**:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         HYBRID ARCHITECTURE                                     │
│               Multi-Account for Isolation + Single-Account SDLC                 │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │                    PRODUCTION ACCOUNTS (by region/BU)                     │  │
│  │                                                                           │  │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐            │  │
│  │  │  US_PROD        │  │   EU_PROD       │  │  APAC_PROD      │            │  │
│  │  │                 │  │                 │  │                 │            │  │
│  │  │  Uses single-   │  │  Uses single-   │  │  Uses single-   │            │  │
│  │  │  account SDLC   │  │  account SDLC   │  │  account SDLC   │            │  │
│  │  │  internally     │  │  internally     │  │  internally     │            │  │
│  │  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘            │  │
│  │           │                    │                    │                     │  │
│  │           └────────────────────┼────────────────────┘                     │  │
│  │                                │                                          │  │
│  │                         Secure Shares                                     │  │
│  │                                │                                          │  │
│  │                                ▼                                          │  │
│  │  ┌───────────────────────────────────────────────────────────────────┐    │  │
│  │  │                    GLOBAL DATA HUB ACCOUNT                        │    │  │
│  │  │                                                                   │    │  │
│  │  │   Aggregates from regional accounts                               │    │  │
│  │  │   Uses single-account SDLC for global analytics                   │    │  │
│  │  │   Publishes to global marketplace                                 │    │  │
│  │  └───────────────────────────────────────────────────────────────────┘    │  │
│  │                                                                           │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│                                                                                 │
│  Within each account: Clone-based dev, team autonomy, promotion gates          │
│  Across accounts: Secure sharing, contract validation, replication             │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Implementation Checklist

### Single-Account Setup

- [ ] Create role hierarchy (TEAM_*_ADMIN, TEAM_*_DEV, TEAM_*_READ)
- [ ] Create production databases (RAW_PROD, CURATED_PROD, SEMANTIC_PROD)
- [ ] Create GOVERNANCE database with contract registry
- [ ] Define tag taxonomy (DATA_CLASSIFICATION, PII_TYPE, etc.)
- [ ] Create masking policies attached to tags
- [ ] Set up Git integration for SQL versioning
- [ ] Create clone automation (stored procedure for team onboarding)
- [ ] Set up CI/CD pipeline with promotion gates
- [ ] Create monitoring for stale clones (cost management)
- [ ] Document team onboarding process

### Multi-Account Setup

- [ ] All single-account items above (per account)
- [ ] Configure Snowflake Organization
- [ ] Set up cross-account shares with contract metadata
- [ ] Configure replication for DR accounts
- [ ] Create centralized contract registry (shared or replicated)
- [ ] Set up cross-account monitoring
- [ ] Document cross-account data flow

---

## References

- [Snowflake Zero-Copy Cloning](https://docs.snowflake.com/en/user-guide/tables-storage-considerations#label-cloning-tables)
- [Snowflake Organizations](https://docs.snowflake.com/en/user-guide/organizations)
- [Role-Based Access Control](https://docs.snowflake.com/en/user-guide/security-access-control-overview)
- [Tag-Based Masking](https://docs.snowflake.com/en/user-guide/tag-based-masking-policies)
- [Git Integration](https://docs.snowflake.com/en/developer-guide/git/git-setting-up)
- [Data Sharing](https://docs.snowflake.com/en/user-guide/data-sharing-intro)
