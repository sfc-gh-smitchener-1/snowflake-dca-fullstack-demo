# United Rentals — Workshop Facilitation Guide

> **On-Site Architecture Whiteboarding Session** — "From Manual Heroics to the UR Federated Data Product Factory"

## Session Details

| Field | Detail |
|-------|--------|
| **Date** | 23 MAR 2026 |
| **Time** | 9:00 AM - 1:00 PM (4 hours, working lunch 12:00-1:00) |
| **Location** | Stanford HQ |
| **Format** | Whiteboard-led workshop with slide anchors, live architecture sketching, interactive handouts |
| **Remote Access** | WebEx for remote participants |

## Attendees

**Snowflake**: Enterprise Data Architect (Lead), Account Team

**United Rentals**: Data Engineering, Analytics Leadership, Platform/Ops, Business Domain Owners (Fleet, Telematics)

## Pre-Work (Distribute 5 Business Days Before)

| Item | Owner | Purpose |
|------|-------|---------|
| Current-state account inventory (accounts, regions, key databases) | UR | Informs Segment 2 whiteboard |
| Top 3-5 "Heroic" processes (pain points in Discovery-to-Production promotion) | UR | Seeds the Friction Map in Segment 1 |
| Enterprise Architecture Guide v7 — Chapters 4 & 7 (excerpt) | Snowflake | Context on RAW, CURATED, SEMANTIC and Federated Execution |
| Architecture Comparison Scorecard (printed handout) | Snowflake | One per attendee |
| UR Data Contract Template v1.0 (printed handout) | Snowflake | One per attendee |
| List of current "heroic" data processes requiring most manual intervention | UR | Inform architecture planning |

## Agenda at a Glance

| Time | Segment | Duration |
|------|---------|----------|
| 9:00 AM | **Segment 1** — The Problem: Mapping the "Heroics" | 45 min |
| 9:45 AM | **Segment 2** — The Pattern: Container-by-DB and Federated Marketplace | 60 min |
| 10:45 AM | BREAK | 15 min |
| 11:00 AM | **Segment 3** — The Proof: Cortex-Powered Modeling and Data Contracts | 45 min |
| 11:45 AM | **Segment 4** — The Path: 30/60/90 Execution Roadmap | 45 min |
| 12:30 PM | **Segment 5** — Working Lunch: Pilot Selection and Commitments | 30 min |
| 1:00 PM | CLOSE | — |

---

## Segment 1 — The Problem: Mapping the "Heroics"

**Time**: 9:00 AM - 9:45 AM (45 minutes)

**Objective**: Shared understanding that "Heroics" are an architectural symptom, not a people problem.

### 9:00-9:10 | Opening and Introductions (10 min)

**Setup**: Stand at the whiteboard. Do not use slides.

**Talk Track**:
> "We're here today because we know your 'Discovery' and 'Production' environments are disconnected, and moving data or AI models between them is painful. But before we look at architecture diagrams, I want to map the actual operational cost of this setup. In the data world, we call this 'Heroics.' When the business asks a critical question — like 'What assets can I rent right now within 50 miles?' — how much manual glue, phone calls, or overnight batch-waiting is required to answer it?"

**Align on workshop outcomes**: Leave with a consensus architecture pattern, a signed-off contract template, and a named pilot workload.

### 9:10-9:30 | Current-State Friction Map (20 min)

**Action**: Ask the room to call out the top 3-4 data processes or business questions that require the most "heroics." Write them on the whiteboard under the heading **"Current Heroics"**.

**Whiteboard Layout** — Three lanes:
```
┌─────────────────────────────────────────────────────────┐
│                    CURRENT HEROICS                      │
├──────────────────┬──────────────────┬───────────────────┤
│    MIGRATION     │    OPERATIONS    │     SECURITY      │
│                  │                  │                   │
│  Who owns it?    │  Who owns it?    │  Who owns it?     │
│  How often?      │  How often?      │  How often?       │
│  Effort/occur?   │  Effort/occur?   │  Effort/occur?    │
│                  │                  │                   │
│  ____________    │  ____________    │  ____________     │
│  ____________    │  ____________    │  ____________     │
│  ____________    │  ____________    │  ____________     │
└──────────────────┴──────────────────┴───────────────────┘
```

**Prompts if the room is slow to start**:
- **Migration Heroics**: How many hours are spent manually rewriting code in Wherescape to move a model from Discovery to Production?
- **Ops Heroics**: Reconciling fleet rental status vs. CMMS maintenance downtime
- **Security Heroics**: Managing the mismatch between Production's local auth and Discovery's SSO/Row-Level Security

### 9:30-9:45 | Root-Cause Analysis (15 min)

**Action**: Synthesize the whiteboard into root causes. Drive toward the thesis: most friction originates from physical account boundaries creating artificial data movement and governance fragmentation.

**Key DCA Anchor**: "Complex systems do not scale outcomes until they stabilize dependencies. The friction UR experiences is the predictable result of unstable boundaries: People define intent, but the multi-account topology breaks the chain before Governance and Automation can execute it."

**Leave the "Current Heroics" list on the whiteboard for the entire meeting.**

---

## Segment 2 — The Pattern: Container-by-DB and Federated Marketplace

**Time**: 9:45 AM - 10:45 AM (60 minutes)

**Objective**: Align on the evolution from fragmented to federated.

### 9:45-10:05 | Single vs. Multi-Account Architecture (20 min)

**Action**: Present two patterns side-by-side. Walk through the Architecture Comparison Scorecard row by row. Whiteboard UR's current topology against the target Container-by-DB model.

**Use the printed handout**: Architecture Comparison Scorecard (see [ARCHITECTURE_STRATEGY.md](ARCHITECTURE_STRATEGY.md) for the full table).

**Key discussion points**:
- UR's current fragmented state vs. unified (Container-by-DB) vs. federated (marketplace)
- Pros/cons of each for UR's specific team structure
- Reference: [Account Architecture Patterns](../../docs/snowflake_account_architecture_patterns.md)

### 10:05-10:20 | RAW, CURATED, SEMANTIC within Container-by-DB (15 min)

**Action**: Map UR's Discovery, Development, and Production domains onto the three-layer progression (RAW → CURATED → SEMANTIC). Show how each database becomes a logical container whose boundaries are **contract boundaries**, not physical account walls.

**Whiteboard the Container-by-DB layout** showing EDW, Manning, Sales Ops, and Fleet as separate domains within the hub.

**Key talk track for CURATED layer**:
> "This is where Dynamic Tables or dbt replace Wherescape Red. Each domain team chooses their transformation engine — the architecture doesn't care which tool you use, only that the data contract is satisfied."

### 10:20-10:35 | Internal Marketplace — Hub-and-Spoke (15 min)

**Action**: Sketch the Hub-and-Spoke model where Fleet, Telematics, and Ops act as Data Providers in a Private Exchange, and Discovery/Analytics act as Consumers.

**Whiteboard the marketplace**:
```
         ┌──────────────┐
         │  UR PRIVATE  │
         │DATA EXCHANGE │
         └──────┬───────┘
    ┌───────────┼───────────┐
    ▼           ▼           ▼
┌────────┐ ┌────────┐ ┌────────┐
│ Fleet  │ │Telemat.│ │  Ops   │
│Provider│ │Provider│ │Provider│
└────────┘ └────────┘ └────────┘
```

**External marketplace integration**: Show how UR can ingest 3rd-party data (weather, economic, OEM telematics) directly without ETL.

### 10:35-10:45 | Snowflake Horizon: Governance That Follows the Data (10 min)

**Action**: Demonstrate how Snowflake Horizon policies (tags, masking, row-level security) are enforced at the source and travel with the data product across the marketplace.

**Reference**: [GOVERNANCE.md](../../docs/GOVERNANCE.md) — show the tag taxonomy and policy examples from the core DCA demo.

---

## BREAK (10:45 AM - 11:00 AM)

---

## Segment 3 — The Proof: Cortex, Data Contracts, and Live Demo

**Time**: 11:00 AM - 11:45 AM (45 minutes)

**Objective**: Show working proof of the patterns discussed in Segment 2.

### 11:00-11:15 | Cross-Account Intelligence with Cortex (15 min)

**Action**: Demonstrate how Snowflake Cortex can provide insights across a federated structure without moving underlying data.

**Live Demo — DCA Framework**:
1. Show the Semantic Views in the core demo (`06_semantic_layer`)
2. Demonstrate Cortex Analyst answering natural language questions
3. Show how Row Access Policies filter results by role

**Talk track**: Point back to the whiteboard "Ops Heroics" — show how a branch manager asking "What assets can I rent within 50 miles?" gets an instant, governed answer through Cortex Analyst.

### 11:15-11:30 | Data Contracts in Action (15 min)

**Action**: Walk through the Data Contract framework from the core DCA demo.

**Live Demo**:
1. Show the contract registry (`08_contracts`)
2. Demonstrate schema contract validation
3. Show quality gates that prevent bad data from reaching production
4. Show SLA monitoring

**Talk track**: Point back to the "Migration Heroics" — show how Git integration + data contracts create the automated promotion path from Discovery to Production.

### 11:30-11:45 | Transformation Engines — Dynamic Tables + dbt (15 min)

**Action**: Show both transformation approaches from the core DCA demo.

**Live Demo**:
1. Show Dynamic Tables with TARGET_LAG SLA (`05_curated_layer`)
2. Show the dbt pipeline for ServiceNow (`dbt_servicenow/`)
3. Show how both produce CURATED layer outputs that satisfy the same data contracts

**Talk track**: "Your teams don't need to agree on one tool. The architecture is engine-agnostic — it cares about the contract, not the transformation method."

---

## Segment 4 — The Path: 30/60/90 Execution Roadmap

**Time**: 11:45 AM - 12:30 PM (45 minutes)

**Objective**: Transition from architecture vision to concrete execution plan.

### 11:45-12:00 | Phase Breakdown (15 min)

**Whiteboard the three phases** (see [ROADMAP.md](ROADMAP.md) for full detail):

```
PHASE 1 (30 Days)          PHASE 2 (60 Days)         PHASE 3 (90 Days)
─────────────────          ─────────────────         ─────────────────
Identity Plane             Internal Marketplace      Federated Governance
Container-by-DB            First Provider (Telemat.) External Marketplace
SSO Harmonization          CI/CD Pipeline            Production Cortex AI
```

### 12:00-12:15 | Risk and Dependencies (15 min)

**Facilitated discussion**: For each phase, identify:
- What could block us?
- Who needs to be involved that isn't in the room?
- What existing processes need to change?

### 12:15-12:30 | Success Criteria (15 min)

Define measurable success criteria for each phase. Write these on the whiteboard alongside the phases.

---

## Segment 5 — Working Lunch: Pilot Selection and Commitments

**Time**: 12:30 PM - 1:00 PM (30 minutes)

**Objective**: Leave with a named pilot workload and mutual accountability.

### The 4-Week Contract Exercise

**Setup**: Walk back to the "Current Heroics" list on the whiteboard.

**Talk Track**:
> "We've shown how Federated Data Domains, Git integration, and Data Contracts work. Now, let's make it real for UR. If we could wave a magic wand and solve just ONE of these friction points on the board over the next 4 weeks — one that would make the most noise with UR leadership — which one are we tackling?"

### Force the Choice (10 min)

Get agreement on one pilot. Potential candidates:
- Operationalize the Cortex AI MVP for Fleet Availability
- Automate the Discovery → Production promotion for one domain
- Unify SSO across Production and Discovery

### Draft the Execution Plan (15 min)

**Action**: Erase the rest of the board. Write the chosen pilot in the center. Break it down:

| Step | Question | Owner |
|------|----------|-------|
| **1. The Domain** | Who owns the raw data for this? | _______________ |
| **2. The Contract** | What are the exact schema and SLA rules before this hits Production? | _______________ |
| **3. The Governance** | What Horizon tags must be applied? (PII_TYPE, DATA_CLASSIFICATION) | _______________ |
| **4. The AI Access** | Point Cortex Analyst at the semantic view | _______________ |
| **5. The SSO** | Who provisions the SSO integration? | _______________ |
| **6. The Git Repo** | Who manages the Git connection? | _______________ |
| **7. The Snowflake Support** | Who from Snowflake supports the UR team? | _______________ |

### The Close (5 min)

**Action**: Take a picture of the whiteboard. This is the mutual action plan built by the customer, for the customer.

**Talk Track**:
> "We didn't run a workshop. We facilitated an architectural design sprint that directly solves your biggest operational pain. See you in 4 weeks for the results."

---

## Post-Workshop Deliverables

| Deliverable | Owner | Timeline |
|-------------|-------|----------|
| Whiteboard photos (Friction Map, Architecture, Pilot Plan) | Snowflake | Same day |
| Architecture Comparison Scorecard (final, annotated) | Snowflake | 3 business days |
| Federated Governance Proposal (Horizon policy mapping) | Snowflake | 5 business days |
| Marketplace Blueprint (technical design) | Snowflake + UR | 10 business days |
| Finalized 30/60/90 Roadmap | Joint | 5 business days |
| Pilot kick-off meeting | Joint | Within 1 week |

## Materials Checklist

- [ ] Whiteboard markers (multiple colors)
- [ ] Printed Architecture Comparison Scorecards (one per attendee)
- [ ] Printed Data Contract Template v1.0 (one per attendee)
- [ ] Laptop with core DCA demo ready to run (Cortex Analyst, Dynamic Tables, dbt, Governance)
- [ ] WebEx link for remote participants
- [ ] Camera/phone for whiteboard captures
