# Snowflake Horizon & Select Star: A Detailed Guide

## Overview

Snowflake Horizon is Snowflake's built-in governance layer — a unified set of compliance, security, privacy, and observability capabilities baked natively into the Snowflake platform. In December 2025, Snowflake acquired Select Star and is integrating its capabilities directly into Horizon as **Horizon Context** — extending Horizon's reach beyond Snowflake-native assets into a cross-platform catalog spanning external databases, BI tools, and pipelines. Together they address the full spectrum of data governance from raw policy enforcement inside Snowflake to cross-platform discovery and usage intelligence.

---

## Part 0: The Select Star Acquisition — What Field Teams Need to Know

### The Acquisition (Dec 2025)

Snowflake publicly announced and onboarded the Select Star team in late Nov–early Dec 2025. Internally, the acquisition was framed as the way to move Horizon beyond Snowflake-native assets into a cross-platform catalog spanning external databases, BI tools, and lineage. The strategic goal: improve AI context, governance, discoverability, and trust across the broader enterprise data estate.

Key leadership:
- **Shinji Kim** (Select Star CEO/founder) → Product Management, reporting to Prasanna Krishnan
- **Przemek Kuczynski** (Select Star Head of Engineering) → Engineering, reporting to Shekhar Iyer

### Why Snowflake Acquired Select Star

The acquisition rationale was specific and capability-driven:
- Expand Horizon Catalog's view of enterprise data **beyond Snowflake-native objects**
- Bring in proven integrations across databases, BI tools, and pipelines (PostgreSQL, SQL Server, Tableau, Power BI, dbt — all day-one PrPr)
- Add automated metadata context, column-level lineage, popularity, and richer business-facing catalog UX
- Strengthen Snowflake Intelligence / Cortex by giving AI better context about what data means, which assets are trusted, and how data flows across systems

**What Snowflake is NOT doing:** keeping Select Star as a separate product. The destination is full absorption into Horizon Catalog / Horizon Context. Standalone Select Star accounts were discontinued; existing customers are being migrated with export support.

### Internal Project Name: HorizonStar / Broadening Star

The end-state vision: a Horizon Catalog that can ingest external metadata from databases and BI tools, make it searchable/browsable/lineage-aware inside Snowflake, and feed richer governed context into AI, semantic views, and Cortex experiences.

Field messaging positioned this as "**Horizon Context**": a governed context layer combining Select Star integration, semantic modeling, search, lineage, popularity, and AI-assisted metadata enrichment.

---

### Timeline (Field-Ready Summary)

| Milestone | Date | Status |
|-----------|------|--------|
| Acquisition announced | Nov–Dec 2025 | ✅ Complete |
| PrPr launch | Summit 2026 (May/Jun) | ✅ 20 customers, 24 internal accounts |
| PuPr target | Fall 2026 (est. Sept) | 🔄 Active in PLT |
| GA | FY27 (est. Nov/Dec 2026) | 📅 Directional |

### PrPr Connector Scope (what's available now)

| Connector | PrPr Available | Notes |
|-----------|---------------|-------|
| PostgreSQL | ✅ | Day-one PrPr |
| Microsoft SQL Server | ✅ | Day-one PrPr |
| Tableau Cloud | ✅ | Day-one PrPr |
| Power BI Premium | ✅ | Day-one PrPr |
| dbt Cloud | ✅ | Day-one PrPr |
| Looker | ❌ | PuPr backlog (fall 2026) |
| Databricks / BigQuery | ❌ | Summer/fall 2026 wave |
| Sigma, Metabase | ❌ | PuPr backlog |

### PrPr Known Limitations (important for field conversations)

- No customer-facing SQL DDL for connectors yet — UI-only setup
- Metadata is **read-only** in PrPr — no writeback to tags/descriptions
- No granular RBAC below connector level in PrPr (connector-level access only)
- No org-level connectors — account-level only
- Search indexing lag: 3–5 hours depending on export/indexing cycles
- No Business Glossary integration in PrPr
- No semantic views directly created from metadata connectors in PrPr

### PuPr / GA Additions

PuPr (fall 2026) adds:
- Metadata and lineage persisted in FDB as serving layer (more Snowflake-native)
- Granular RBAC to database level
- Metadata writeback (descriptions, tags, custom attributes)
- Snowflake-native SQL DDL for connector create/alter/drop
- Tags, contacts, account usage views for external metadata
- 5+ additional connectors
- Stricter network policy enforcement (SSRF hardening)

GA adds:
- Full connector CRUD via SQL
- Business Glossary + semantic view integration
- Auto-generated popularity scores and AI documentation at scale
- Org-level catalog (deferred from PrPr/PuPr — primitives not ready)

---

### Core Architecture (HorizonStar Design)

The foundational architectural approach: keep much of the Select Star backend running in Snowflake-managed apps-cluster infrastructure (Kubernetes) while progressively pulling customer-facing control, RBAC, SQL access, and serving surfaces into Snowflake/GS/Snowsight.

```
Customer (Snowsight connector setup wizard)
  └─→ GS (persists connector state/credentials via DPO-backed storage)
        └─→ Select Star service (crawls external metadata on Snowflake K8s apps cluster)
              └─→ Copy/ingestion service (moves metadata to Snowflake-controlled FDB store)
                    └─→ Snowscope / Universal Search (serves catalog, lineage, popularity)
```

Platform choices:
- **No new public services** — GS/service-to-service calls over internal addressing
- **SnowIdentity + mTLS + ZNS** for internal service auth/discovery
- **FUSE** for app secrets
- **DPO-backed GS storage** for customer connector credentials
- **Proxy BDE model** — splits lightweight RBAC-bearing entities from heavier metadata storage

This demo simulates the Snowflake-controlled metadata store (the FDB layer) using `CURATED_DEV.HORIZON_CONTEXT` tables.

---

---

## Part 1: Snowflake Horizon

### What Is Horizon?

Announced at Snowflake Summit 2023, Horizon is not a separate product — it is the **governance layer of Snowflake itself**, consolidating capabilities that were previously scattered across the platform into a coherent governance posture. Horizon operates across four pillars:

| Pillar | Purpose |
|---|---|
| **Discover** | Find and understand data across the estate |
| **Protect** | Enforce access, privacy, and security controls |
| **Monitor** | Track who did what, when, and to what data |
| **Comply** | Meet regulatory and policy obligations |

---

### Pillar 1: Discover

#### Universal Search
Snowflake's Universal Search allows users to search across databases, schemas, tables, views, columns, data products, and Marketplace listings from a single interface. It indexes object names, descriptions, comments, and tags. It surfaces both internal assets and external Marketplace content in one query.

#### Object Tagging
Tags in Snowflake are schema-level objects that can be applied to databases, schemas, tables, columns, warehouses, and more. Tags are first-class citizens: they survive object renames, propagate via tag policies, and integrate directly with masking and row access policies.

```sql
-- Create a tag
CREATE TAG governance.tags.pii_category
  ALLOWED_VALUES 'NAME', 'EMAIL', 'SSN', 'DOB', 'PHONE';

-- Apply to a column
ALTER TABLE raw.patients
  MODIFY COLUMN patient_email
  SET TAG governance.tags.pii_category = 'EMAIL';
```

Tags can also be applied automatically via **Auto Tag Policies** (Cortex-powered classification).

#### Data Classification
Snowflake's built-in classifier (`SNOWFLAKE.DATA_PRIVACY.CLASSIFY_TABLE`) automatically scans table columns and assigns semantic categories (e.g., `NAME`, `EMAIL`, `US_SSN`, `DATE_OF_BIRTH`) and privacy categories (`IDENTIFIER`, `QUASI_IDENTIFIER`, `SENSITIVE`). This seeds the tag graph without manual effort.

```sql
-- Classify a table and store results
CALL snowflake.data_privacy.classify_table(
  'RAW_LAYER.PATIENTS.PATIENT_DEMOGRAPHICS',
  {'auto_tag': true}
);
```

#### Business Glossary
A governance glossary stored in Snowflake allows data stewards to define business terms (e.g., "Active Patient", "Covered Entity", "Net Revenue") and link them to physical columns. This bridges business language and physical schema. Glossary terms appear in Universal Search and can drive policy decisions.

#### Data Products
Horizon introduces the concept of a **Data Product** — a curated, governed, and shareable data asset. Data products are defined with metadata (owner, description, SLA, classification) and published for internal or external consumers through the Marketplace or Snowflake Shares.

---

### Pillar 2: Protect

#### Dynamic Data Masking
Masking policies are SQL functions attached to columns that transform data at query time based on the querying role. Unmasked data never leaves the Snowflake engine for unauthorized users.

```sql
CREATE MASKING POLICY governance.policies.mask_email
  AS (val STRING) RETURNS STRING ->
    CASE
      WHEN CURRENT_ROLE() IN ('DATA_STEWARD', 'ANALYST_FULL') THEN val
      ELSE REGEXP_REPLACE(val, '.+@', '****@')
    END;

ALTER TABLE raw.patients
  MODIFY COLUMN patient_email
  SET MASKING POLICY governance.policies.mask_email;
```

**Conditional masking** allows one column's value to determine masking behavior on another column. **Tag-based masking policies** apply masks to all columns bearing a given tag, so you write one policy and it covers every `pii_category = 'EMAIL'` column in the account.

#### Row Access Policies
Row access policies filter rows returned by any query against a table, based on the querying role or session context. Useful for multi-tenant data, regional data residency, or role-scoped data access.

```sql
CREATE ROW ACCESS POLICY governance.policies.patient_facility_rls
  AS (facility_id VARCHAR) RETURNS BOOLEAN ->
    EXISTS (
      SELECT 1 FROM security.facility_role_map
      WHERE role_name = CURRENT_ROLE()
        AND facility = facility_id
    );
```

#### Aggregation Policies
Restrict query results to ensure aggregate outputs only (minimum group size). Useful for preventing re-identification attacks on quasi-identifiers even through aggregate queries.

#### Projection Policies
Prevent columns from being returned in `SELECT *` or direct column projections unless the user holds a specific privilege. A complement to masking that blocks column visibility entirely.

#### Network Policies & Private Connectivity
Network policies restrict Snowflake access by IP range. Private connectivity options (AWS PrivateLink, Azure Private Link, GCP Private Service Connect) keep traffic off the public internet. These are enforced at the account, user, or integration level.

#### Authentication Policies
Authentication policies enforce MFA requirements, allowed authentication methods (password, SSO, key-pair), and session timeouts at the user or account level.

#### Tri-Secret Secure / BYOK
With Tri-Secret Secure, customer-managed keys (via AWS KMS, Azure Key Vault, or GCP KMS) are combined with Snowflake-managed keys to create a composite encryption key. Data cannot be decrypted by Snowflake without the customer's key.

---

### Pillar 3: Monitor

#### Access History
The `SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY` view records every query that touched a base table column, including columns read via views. This provides column-level audit detail — not just "who ran what query" but "who read which columns".

```sql
SELECT
  query_start_time,
  user_name,
  base_objects_accessed,
  objects_modified
FROM snowflake.account_usage.access_history
WHERE array_contains('RAW_LAYER.PATIENTS.PATIENT_DEMOGRAPHICS'::VARIANT,
                      base_objects_accessed)
ORDER BY query_start_time DESC;
```

#### Column-Level Lineage
Snowflake tracks column-level lineage natively — how columns in one table derive from columns in upstream tables, through `CREATE TABLE AS SELECT`, Dynamic Tables, views, and stored procedures. This is queryable via `SNOWFLAKE.ACCOUNT_USAGE.OBJECT_DEPENDENCIES`.

```sql
SELECT *
FROM snowflake.account_usage.object_dependencies
WHERE referenced_object_name = 'PATIENT_DEMOGRAPHICS';
```

This graph powers the **lineage visualization** in Snowsight.

#### Object Dependencies
Beyond column lineage, `OBJECT_DEPENDENCIES` tracks all referencing/referenced relationships — views referencing tables, tasks calling stored procedures, Dynamic Tables chained to other Dynamic Tables. Critical for safe refactoring and deprecation.

#### Query History & Performance
`QUERY_HISTORY` and `WAREHOUSE_METERING_HISTORY` provide detailed execution metadata: credits consumed, bytes scanned, partition pruning rates, spillage, queue time. Horizon surfaces this into governance-relevant lenses like "who is scanning unmasked data" or "which policies are adding query latency".

#### Data Quality Monitoring
Snowflake's Data Metric Functions (DMFs) allow you to define custom data quality checks that run on a schedule against tables. Built-in system metrics include `NULL_COUNT`, `DUPLICATE_COUNT`, `FRESHNESS`, `ROW_COUNT`. Custom DMFs can encode business rules.

```sql
-- System DMF example
ALTER TABLE curated.patient_vitals
  ADD DATA METRIC FUNCTION snowflake.core.null_count
    ON (patient_id);

-- Check results
SELECT *
FROM TABLE(snowflake.core.get_dmf_results('curated.patient_vitals'));
```

#### Trust Center
The Trust Center provides a security posture dashboard — scanning the account for misconfigurations, policy gaps, and compliance risks. It surfaces findings like "X users have no MFA", "Y tables have PII columns with no masking policy", and "Z service accounts use password auth". Findings are risk-scored and actionable.

---

### Pillar 4: Comply

#### Compliance Center
Built on top of the Trust Center, the Compliance Center maps Snowflake's controls to regulatory frameworks (HIPAA, PCI-DSS, SOC 2, GDPR). It provides a control inventory showing which framework requirements are met by which Snowflake features, and which controls have gaps.

#### Privacy Policies & Consent Management
Projection and aggregation policies can be combined with tag-based masking to enforce privacy-by-design. For regulated industries (healthcare, finance), Horizon provides the technical controls that map to:
- HIPAA Safeguards (access controls, audit logging, encryption)
- GDPR Article 25 (data minimisation, privacy by default)
- CCPA (right to access, right to delete — via data product governance)

#### Governance Hierarchies
Snowflake supports a complete RBAC hierarchy with functional roles (what you can do) and access roles (what data you can see). Combined with object tags and policy inheritance, governance rules propagate automatically as data moves from raw to curated to semantic layers.

---

## Part 2: Select Star

### What Is Select Star?

Select Star is a **data intelligence platform** — a modern data catalog focused on automated discovery, usage analytics, and cross-system lineage. It is available as a **Snowflake Native App** (data stays in your Snowflake account) and also as a SaaS deployment with Snowflake integration.

Select Star positions itself as the layer that makes Horizon's governance investments *discoverable and actionable* for data consumers — not just data engineers and stewards.

### Core Select Star Capabilities

#### 1. Automated Metadata Harvesting
Select Star continuously ingests metadata from connected systems:
- Snowflake (tables, views, columns, schemas, query history)
- dbt (model descriptions, tests, lineage DAG, documentation)
- BI tools (Looker, Tableau, Power BI, Metabase, Mode — which dashboards use which columns)
- Orchestrators (Airflow, Prefect, Dagster — pipeline-level lineage)
- Reverse ETL (Census, Hightouch)

This creates a **cross-system metadata graph** that Snowflake Horizon alone cannot build — Horizon is authoritative inside Snowflake but blind to what happens upstream in dbt or downstream in Tableau.

#### 2. Usage-Based Popularity Scoring
Select Star mines Snowflake's query history to score every table and column by real usage:
- How many users queried this table in the last 30/90 days?
- Which columns are actually read vs. never touched?
- Which tables have zero downstream consumers?
- Which dashboards pull from this table?

This transforms the catalog from a static inventory into a **living usage map** — teams can see that `PATIENT_DEMOGRAPHICS.EMAIL` is accessed by 14 analysts daily and feeds 6 Looker dashboards, before making any governance decisions about it.

#### 3. End-to-End Lineage (Column-Level, Cross-System)
Where Snowflake Horizon tracks lineage *within* Snowflake, Select Star extends it across the stack:

```
Airflow DAG → Snowpipe → Raw Table → dbt model → Dynamic Table → Semantic View → Looker Explore → Dashboard
```

Every node in that chain is navigable in Select Star's lineage graph. Column-level lineage flows through dbt transformations into Snowflake columns and out to specific BI report fields.

#### 4. AI-Powered Descriptions
Select Star uses LLMs to auto-generate column and table descriptions by:
- Analyzing column names and sample values
- Reading dbt model logic and tests
- Incorporating query patterns (what WHERE clauses use this column)
- Reading existing documentation from dbt YAML files

These descriptions can be pushed back into Snowflake object comments and Business Glossary entries, enriching Horizon's Universal Search index.

#### 5. Column-Level Sensitive Data Detection
Select Star scans column names and inferred data patterns to flag likely sensitive columns — complementing Snowflake's built-in classifier. Where Snowflake's classifier requires explicit invocation per table, Select Star provides a continuously updated sensitivity surface across the whole estate, including BI-layer columns.

#### 6. Slack/Teams Integration & Contextual Search
Select Star embeds catalog search into collaboration tools. An analyst can ask "what's the freshest patient census table?" directly in Slack and get a ranked result with popularity score, last refresh time, and owner contact — without leaving their workflow.

#### 7. Ownership & Stewardship Workflows
Select Star surfaces column and table owners (pulled from Snowflake RBAC, dbt ownership metadata, and usage patterns) and supports assignment workflows. Stewards are notified when their assets go stale, lose downstream consumers, or accumulate unresolved description gaps.

---

## Part 3: How Select Star Fits Into Snowflake Horizon

### The Gap Select Star Fills

Snowflake Horizon is the **enforcement and audit layer** — authoritative, policy-driven, deeply integrated with query execution. But governance has two sides:

| Dimension | Snowflake Horizon | Select Star |
|---|---|---|
| Policy enforcement | Native, in-engine | Not applicable |
| Cross-system lineage | Snowflake-only | Full stack (dbt, BI, pipelines) |
| Usage analytics | Query history (raw) | Curated popularity scores |
| AI-generated descriptions | Limited | Full coverage |
| BI tool visibility | None | Looker, Tableau, Power BI, etc. |
| Catalog UX | Snowsight | Purpose-built catalog interface |
| Slack/Teams integration | None | Native |
| Governance workflow | RBAC + policies | Ownership assignment, notifications |
| Data product publishing | Horizon Data Products | Select Star catalog as discovery layer |

Select Star is **not a replacement** for Horizon — it is the intelligence and discovery layer that makes Horizon's governed assets *findable and understandable* across the organization.

### Integration Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                     SNOWFLAKE ACCOUNT                          │
│                                                                │
│  ┌─────────────────────┐    ┌──────────────────────────────┐   │
│  │   DATA ESTATE       │    │   SNOWFLAKE HORIZON          │   │
│  │                     │    │                              │   │
│  │  Raw Layer          │    │  • Tags & Classification     │   │
│  │  Curated Layer      │◄───┤  • Masking Policies          │   │
│  │  Semantic Layer     │    │  • Row Access Policies       │   │
│  │  Data Products      │    │  • Access History            │   │
│  └──────────┬──────────┘    │  • Column-Level Lineage      │   │
│             │               │  • Trust Center              │   │
│             │               │  • Business Glossary         │   │
│             │               └──────────────────────────────┘   │
│             │                                                  │
│  ┌──────────▼────────────────────────────────────────────── ┐  │
│  │            SELECT STAR (Native App)                      │  │
│  │                                                          │  │
│  │  Reads: query_history, object_dependencies,              │  │
│  │         information_schema, access_history               │  │
│  │                                                          │  │
│  │  Builds: cross-system lineage graph, popularity scores,  │  │
│  │          AI descriptions, ownership maps                 │  │
│  │                                                          │  │
│  │  Writes back: object comments, glossary enrichment       │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
        ▲                    ▲                    ▲
        │                    │                    │
    dbt Cloud            Tableau/Looker        Dagster/Prefect
    (model lineage,      (dashboard→column    (pipeline→table
     descriptions,        lineage)             lineage)
     tests)
```

### Where They Complement Each Other

#### Discovery + Protection
Horizon's tag-based masking policies are only as effective as the tagging itself. Select Star's sensitivity detection and AI descriptions identify which columns *should* be tagged, feeding recommendations back to stewards who apply Horizon tags via governance workflows. Result: more complete policy coverage, faster.

#### Lineage (Inside + Outside)
Snowflake Horizon shows you that `SEMANTIC_LAYER.PATIENT_SUMMARY.RISK_SCORE` was derived from three upstream Dynamic Tables. Select Star shows you that `RISK_SCORE` flows into 4 Looker dashboards consumed by 23 executives, and that breaking this column would break those dashboards. Horizon gives you the provenance; Select Star gives you the impact.

#### Usage Intelligence for Governance Prioritization
Not all PII is equal. A column containing 10-year-old test data accessed by one dev needs less governance urgency than a column accessed 10,000 times per day by 50 users. Select Star's popularity scores let governance teams **prioritize Horizon policy deployment** on the highest-risk/highest-usage assets first.

#### Decommissioning & Data Quality
Select Star identifies tables with zero recent queries and no downstream BI consumers. Combined with Horizon's Data Metric Functions (freshness, null counts), this gives a complete picture of "stale AND poor quality" assets that should be deprecated — removing governance surface area and storage cost simultaneously.

#### Data Product Enrichment
Horizon Data Products require rich metadata to be useful in Universal Search and the Marketplace. Select Star's auto-generated descriptions, popularity scores, and usage context populate that metadata automatically. A Data Product published through Horizon becomes significantly more discoverable when Select Star has enriched its column descriptions and linked its upstream lineage.

---

## Part 4: Combined Governance Maturity Model

| Maturity Level | What It Looks Like | Horizon Capabilities | Select Star Role |
|---|---|---|---|
| **Level 1 – Reactive** | Manual tagging, no masking, audit after incident | Basic RBAC, object tagging | Catalog bootstrap, asset inventory |
| **Level 2 – Defined** | Auto-classification, masking on PII columns, lineage visible | Auto-tagging, masking policies, column lineage | Cross-system lineage, AI descriptions |
| **Level 3 – Managed** | Tag-based policies, Trust Center active, DMFs running | Tag-based masking, RLS, DMFs, Trust Center | Usage-driven governance prioritization, ownership workflows |
| **Level 4 – Optimized** | Automated policy deployment, compliance center mapped, data products published | Compliance Center, Horizon Data Products, Tri-Secret | Slack integration, full BI lineage, automatic staleness detection |
| **Level 5 – Predictive** | AI surfaces governance gaps before incidents | Cortex AI on access history, anomaly detection | Proactive sensitivity flagging, zero-touch description enrichment |

---

## Part 5: Practical Deployment Notes

### Native App vs. SaaS
Select Star is available as a **Snowflake Native App** — all metadata processing happens inside your Snowflake account. No raw data or query text leaves your security boundary. This is the recommended deployment for regulated industries (healthcare, finance, government) where data residency and HIPAA/SOC 2 compliance require processing to stay within the Snowflake perimeter.

### What Select Star Reads from Snowflake
Select Star's Native App reads the following Snowflake system views (all within your account):
- `SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY`
- `SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY`
- `SNOWFLAKE.ACCOUNT_USAGE.OBJECT_DEPENDENCIES`
- `INFORMATION_SCHEMA` (column metadata, data types)
- `SNOWFLAKE.ACCOUNT_USAGE.TABLES`, `.VIEWS`, `.COLUMNS`
- `SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES` (Horizon tag data)

### What Select Star Writes Back
- Object comments (descriptions on tables and columns)
- Business Glossary term links (where Snowflake API supports it)
- Snowflake object tags (where granted write access)

### Required Snowflake Roles
The Select Star Native App service account typically needs:
- `IMPORTED PRIVILEGES` on the `SNOWFLAKE` database (for account usage views)
- `USAGE` on all databases to be cataloged
- Optionally: `APPLY TAG` privilege for writeback enrichment

---

## Summary

Snowflake Horizon is the **governance engine** — it enforces policy, tracks lineage, classifies data, and maintains compliance posture entirely within the Snowflake platform. **Horizon Context** (powered by the Select Star acquisition) is the **cross-platform intelligence layer** — it extends lineage beyond Snowflake into external databases, BI tools, and pipelines; surfaces usage patterns and popularity scores; enriches metadata with Cortex AI; and makes the entire enterprise data estate discoverable in one unified catalog.

### Net Assessment (from acquisition design docs)

> *Snowflake bought Select Star to solve Horizon's weakest area: external metadata and cross-platform lineage.*
>
> **PrPr** was a pragmatic MVP that prioritized getting real external connectors, search, browse, lineage, and RBAC into customer hands by Summit 2026, even if the architecture still leaned heavily on the legacy Select Star backend.
>
> **PuPr** is where the product becomes meaningfully more Snowflake-native: better FDB persistence, richer governance, more connectors, metadata writeback, and more polished UX.
>
> **GA** is intended to finish the transition from "integrated legacy capability" to "first-class Horizon platform capability," but the exact GA month should be treated as directional rather than committed.

### Demo Implementation

This repository includes a full Horizon Context demo simulation:

| File | Purpose |
|------|---------|
| `sql/17_select_star_horizon_context.sql` | Schema, tables, seed data, views, stored procedures |
| `streamlit/app.py` → `render_horizon_context_page()` | 5-tab demo UI: Connector Hub, Universal Catalog, Cross-Platform Lineage, Usage Intelligence, AI Governance |

The demo simulates:
- 5 active connectors (PostgreSQL, SQL Server, Tableau, Power BI, dbt)
- 50+ external catalog objects
- 27 cross-platform lineage edges spanning 4 end-to-end paths
- AI governance recommendations (Cortex COMPLETE integration)
- Usage intelligence with popularity scoring and orphan detection

For enterprise Snowflake deployments — especially in regulated industries — Horizon + Horizon Context represents the current best practice for full-stack data governance: Horizon provides the enforcement backbone; Horizon Context provides the cross-platform intelligence layer.
