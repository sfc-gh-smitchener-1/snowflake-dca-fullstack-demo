# TMR Working Session — Data Engineering Automation & Data Quality Acceleration

**Duration:** 2 hours (in-person, whiteboard-heavy)
**Audience:** Co-interim CDO replacements + technical leads
**Goal:** Demonstrate how Snowflake-native capabilities automate pipelines and quality remediation when data is visible to the platform — and how to accelerate consumption without sacrificing trust.

---

## Agenda

### Opening — Context & Desired Outcomes (10 min)

- Acknowledge leadership transition; reaffirm strategic direction
- Frame the session around three questions:
  1. How do we automate data engineering end-to-end using Snowflake-native tooling?
  2. How do we automate data quality remediation when reference/source/target schemas are all in Snowflake?
  3. How do we accelerate data usage without losing stakeholders to quality concerns?
- Whiteboard: Draw the "trust triangle" — Speed, Quality, Adoption — and how today's session resolves the tension

---

### Block 1 — Automating Data Engineering Pipelines (40 min)

**The premise:** If Snowflake can see the data (stages, tables, schemas), it can orchestrate the full pipeline without external ETL tooling.

#### 1A. The Building Blocks (15 min) — Whiteboard

Draw the end-to-end flow and map each stage to a Snowflake-native capability:

| Pipeline Stage | Snowflake Capability |
|---|---|
| Ingestion | Openflow connectors, Snowpipe Streaming, External Stages |
| Schema inference | INFER_SCHEMA, Dynamic Schema Detection |
| Transformation | Dynamic Tables (declarative, auto-refresh) |
| Orchestration | Tasks + DAGs (dependency-aware, event-driven) |
| Semantic layer | Native Semantic Views (for Cortex Analyst, apps) |
| CI/CD | DCM Projects (`snow dcm plan/deploy`), dbt Projects on Snowflake |
| AI-assisted authoring | Cortex Code — generates SQL, builds pipelines from prompts |

#### 1B. Live Demo — Account Usage Temporal Pipeline (15 min)

Walk through Steve's existing demo: temporal storage of Snowflake ACCOUNT_USAGE data showing all three layers in action:

- **RAW layer:** ACCOUNT_USAGE views ingested with SCD2 temporal pattern (`_VALID_FROM`, `_VALID_TO`, `_IS_CURRENT`) — full append-only history, nothing discarded
- **CURATED layer:** Dynamic Tables that auto-refresh — aggregating usage metrics, computing trends, joining across usage domains (warehouses, queries, storage, logins)
- **SEMANTIC layer:** Native Semantic View on top — enables Cortex Analyst to answer questions like "What's our warehouse cost trend this month?" in plain English

**On the whiteboard**, draw their current pipeline next to this pattern:
- **Their current state:** Source → SnapLogic/external tool → staging → manual transforms → reporting
- **This demo's pattern:** Source → Snowflake-native ingestion → Dynamic Tables (auto-chain) → Semantic View → Cortex Analyst

Key message: *No schedulers to manage. No DAG files to maintain. Dynamic Tables react to upstream changes automatically. This is the same pattern you'd apply to Workday, your SIS, or any other source.*

#### 1C. The "Correct Code" Question (10 min)

How Cortex Code + Projects + Prompts close the skills gap:
- Cortex Code generates pipeline SQL from natural language descriptions
- dbt Projects on Snowflake / DCM provide version control + CI/CD
- Semantic Views provide the "contract" — downstream consumers query meaning, not tables
- Demo concept: "Describe what you want in English → Cortex Code writes the Dynamic Table chain → DCM deploys it"

**Whiteboard artifact:** End-to-end pipeline diagram with capability labels

---

### Break (5 min)

---

### Block 2 — Automating Data Quality & Fidelity Remediation (35 min)

**The premise:** When reference data, source schemas, and target semantic definitions all live in Snowflake, the platform has everything it needs to detect, diagnose, and remediate quality issues autonomously.

#### 2A. The Quality Automation Stack (15 min) — Whiteboard

Draw the closed-loop quality system:

```
┌─────────────────────────────────────────────────────┐
│  SEMANTIC SCHEMA (target contract)                  │
│  "A student record MUST have enrollment_date,       │
│   GPA between 0.0–4.0, active program reference"    │
└──────────────────────┬──────────────────────────────┘
                       │ compare
┌──────────────────────▼──────────────────────────────┐
│  DATA QUALITY CHECKS (automated)                    │
│  • Schema drift detection (INFER_SCHEMA vs contract)│
│  • Referential integrity (FK validation via DTs)    │
│  • Statistical fidelity (distribution monitoring)   │
│  • Freshness SLAs (STREAM + TASK alerting)          │
└──────────────────────┬──────────────────────────────┘
                       │ violations
┌──────────────────────▼──────────────────────────────┐
│  REMEDIATION PIPELINES (automated)                  │
│  • Quarantine tables (bad records isolated)         │
│  • Auto-coercion rules (type fixes, null defaults)  │
│  • Cortex LLM classification (ambiguous values)     │
│  • Alert + escalate (Slack/email for human review)  │
└─────────────────────────────────────────────────────┘
```

#### 2B. What Makes This Possible in Snowflake (10 min)

- **Reference data as tables** → JOIN-based validation in Dynamic Tables
- **Source schemas discoverable** → `INFORMATION_SCHEMA` + tags + lineage
- **Target semantic definitions** → Native Semantic Views define the contract
- **Cortex AI functions** → `COMPLETE()`, `CLASSIFY()` for fuzzy remediation
- **Data Metric Functions (DMFs)** → Attach quality rules directly to tables, auto-evaluate on schedule
- **Alert + Notification integrations** → Push violations to teams without polling

#### 2C. Whiteboard Exercise (10 min)

Pick a known quality pain point (e.g., Workday data arriving with nulls, schema changes breaking downstream). Map it through the closed-loop system:
1. Define the contract (semantic schema says field X is required, references table Y)
2. Dynamic Table detects violation on refresh
3. Bad records route to quarantine
4. Good records flow to consumption
5. Alert fires to data steward with context

**Whiteboard artifact:** Closed-loop quality diagram with their actual data entities

---

### Block 3 — Accelerating Usage Without Losing Stakeholders (25 min)

**The premise:** Speed and trust aren't opposing forces if you build quality INTO the delivery path rather than bolting it on after.

#### 3A. The "Trust-by-Default" Architecture (10 min) — Whiteboard

Draw the layered approach:

```
STAKEHOLDER LAYER    →  Cortex Analyst / Streamlit / Notebooks
                         (they only see semantic layer — curated, validated, governed)
                              │
SEMANTIC LAYER       →  Native Semantic Views + Data Products
                         (quality-gated: only passes if DMF checks clear)
                              │
CURATED LAYER        →  Dynamic Tables with quality predicates
                         (WHERE _quality_score >= threshold)
                              │
RAW LAYER            →  Everything lands here, warts and all
                         (full history, SCD2, nothing hidden)
```

Key insight: **Stakeholders never touch raw data.** They interact with the semantic layer, which is quality-gated by design. This lets you ingest aggressively (speed) while never exposing unvalidated data (trust).

#### 3B. Accelerators That Build Confidence (10 min)

| Accelerator | What it does | Trust signal to stakeholders |
|---|---|---|
| Semantic Views | Natural language access to governed data | "I asked a question and got a certified answer" |
| Data Products (Marketplace/Listings) | Packaged, documented, SLA-backed datasets | "This dataset has an owner and a freshness guarantee" |
| Governance tags + masking | Automatic PII protection | "I can't accidentally see what I shouldn't" |
| Quality dashboards (Streamlit) | Live DMF results, lineage visualization | "I can see the quality score before I use the data" |
| Cortex Analyst | Ask questions in English, get SQL-validated answers | "I don't need to know SQL or trust my own joins" |

#### 3C. Discussion: Their Acceleration Priorities (5 min)

- Which stakeholder groups are they most worried about losing?
- What's the #1 quality issue that erodes trust today?
- What's the fastest "win" we can deliver to rebuild confidence?

---

### Wrap-Up — Next Steps & Commitments (5 min)

1. **Photograph the whiteboard** — we'll digitize into an architecture doc
2. **Identify one pilot pipeline** for end-to-end automation (Block 1)
3. **Identify one quality pain point** to build the closed-loop system around (Block 2)
4. **Identify one stakeholder group** to deliver an accelerated experience to (Block 3)
5. **Schedule follow-up:** 2-week check-in to review pilot progress

---

## Facilitation Notes

- **Whiteboard-first:** Every block starts at the whiteboard before any slides or demos
- **Their data, their problems:** Use real entity names, real pipeline names, real pain points — not generic examples
- **Leave artifacts:** Each block should produce a whiteboard diagram they can photograph and reference
- **Decision-forcing:** End each block with "what do we pick as the pilot?" — don't let it stay abstract
- **Read the room on CDO transition:** They may need reassurance that the technical direction survives the leadership change. The automation story helps here — less reliance on any one person's tribal knowledge
