# DCA Ontological Synthesis — Where Technology Meets Human Agreement

> "Scale amplifies fragility rather than value when dependencies remain ambiguous."
> — Enterprise Architecture Guide for the Snowflake Data Cloud, v7

---

## The Synthesis Problem

The previous three documents established:

1. **[01 — Philosophical Foundations](01-philosophical-foundations.md):** The ontological frameworks needed to reason clearly about data systems — BFO, Guarino's identity conditions, Searle's social ontology.

2. **[02 — Object Ontology](02-object-ontology.md):** A formal taxonomy of Snowflake objects — their types, identity conditions, dependence relationships, and what the medallion layers represent ontologically.

3. **[03 — Human Ontology](03-human-ontology.md):** The roles, relationships, trust structures, and collective intentionality that determine whether a data platform functions or fails.

The synthesis question is: **how do these two systems — the technical and the human — interface with each other?**

The answer is both simple and profound: **every Snowflake object that carries institutional meaning is a materialised human agreement**. The platform's durability is the durability of those agreements.

---

## The Full DCA Ontological Map

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        DCA FULL ONTOLOGICAL MAP                                 │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   HUMAN LAYER                              TECHNICAL LAYER                      │
│   (Social Ontology)                        (Object Ontology)                    │
│   ─────────────────────────────────────────────────────────                     │
│                                                                                 │
│   PEOPLE ──────────────────────────────────────────────────────────────────     │
│   CDO, RDO, Data Teams, Consumers                                               │
│   (Agentive subjects with status functions and intent)                          │
│                │                                                                │
│                │  encode intent as                                              │
│                ▼                                                                │
│   MEANING ─────────────────────────────────────────────────────────────────     │
│   Domain definitions, business concepts, metrics                                │
│   (Institutional facts: exist by collective agreement)                          │
│                │                                  Snowflake objects:            │
│                │  represented in                  Semantic Views                │
│                ▼                                  Data Contracts                │
│   SEMANTICS ───────────────────────────────────────────────────────────────     │
│   Agreed names, types, relationships, canonical keys                            │
│   (Identity conditions made explicit)                                           │
│                │                                  Snowflake objects:            │
│                │  governed by                     Tags, Classifications         │
│                ▼                                  Masking Policies              │
│   GOVERNANCE ──────────────────────────────────────────────────────────────     │
│   Policies, contracts, access rules, classification                             │
│   (Normative institutional objects — encode what OUGHT to be)                   │
│                │                                  Snowflake objects:            │
│                │  executed as                     Row Access Policies           │
│                ▼                                  RBAC / Shares                 │
│   DATA ────────────────────────────────────────────────────────────────────     │
│   Bronze / Silver / Gold tables, streams, dynamic tables                        │
│   (Dependent continuants — physical existence + institutional meaning)          │
│                │                                  Snowflake objects:            │
│                │  processed by                    Tables, Views                 │
│                ▼                                  Dynamic Tables                │
│   AUTOMATION ──────────────────────────────────────────────────────────────     │
│   Pipelines, tasks, models, dashboards, APIs                                    │
│   (Occurrents — happen, produce effects, inherit upstream meaning)              │
│                                                   Snowflake objects:            │
│                                                   Tasks, Snowpipe               │
│                                                   Dynamic Tables                │
│                                                   Cortex AI                     │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Interfaces: Where Human Agreements Become Technical Objects

The DCA has six critical interface points — places where a human agreement must be translated into a platform-enforceable object. These are the highest-risk points in the architecture.

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                       THE SIX CRITICAL INTERFACES                               │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  INTERFACE 1: Intent → Schema                                                   │
│  ──────────────────────────────────────────────────────────────────────────     │
│  Human side:  "We agree this entity has these attributes"                       │
│  Platform:    CREATE TABLE with column names, types, constraints                │
│  Risk:        Schema designed by engineers without domain input                 │
│               → column names that mean nothing to the business                  │
│  Health sign: Business stakeholders can read the DDL and recognise it           │
│                                                                                 │
│  INTERFACE 2: Ownership → RBAC                                                  │
│  ──────────────────────────────────────────────────────────────────────────     │
│  Human side:  "The Finance Data Team owns revenue data"                         │
│  Platform:    GRANT OWNERSHIP ON SCHEMA finance TO ROLE finance_data_owner      │
│  Risk:        Roles proliferate without mapping to actual human accountability  │
│               → ACCOUNTADMIN used for everything because ownership is unclear   │
│  Health sign: Every role maps to a named human team with documented purpose     │
│                                                                                 │
│  INTERFACE 3: Sensitivity → Classification + Policy                             │
│  ──────────────────────────────────────────────────────────────────────────     │
│  Human side:  "This column contains PII under GDPR"                             │
│  Platform:    TAG SENSITIVE_PII + MASKING POLICY applied to column              │
│  Risk:        Classification done once, never reviewed                          │
│               Masking policy logic not tested against real query patterns       │
│  Health sign: Classification reviewed on schema change; policies tested         │
│                                                                                 │
│  INTERFACE 4: Business Definition → Semantic View                               │
│  ──────────────────────────────────────────────────────────────────────────     │
│  Human side:  "Revenue means invoiced amount net of returns, in USD"            │
│  Platform:    SEMANTIC VIEW with metric definition + business name              │
│  Risk:        Metric definition agreed in a meeting, never encoded              │
│               → 4 different revenue columns across 4 Gold tables                │
│  Health sign: Cortex Analyst answers "what is revenue" by pointing              │
│               to a single semantic view definition                              │
│                                                                                 │
│  INTERFACE 5: Data Contract → Enforced Agreement                                │
│  ──────────────────────────────────────────────────────────────────────────     │
│  Human side:  "We commit to 99.9% freshness within 1 hour"                      │
│  Platform:    DATA METRIC FUNCTION monitoring freshness + ALERT on breach       │
│  Risk:        Contract exists in Confluence; no platform enforcement            │
│               → SLA breach discovered by consumer, not producer                 │
│  Health sign: Data contract violations surface as alerts to the owner,          │
│               not as surprised complaints from consumers                        │
│                                                                                 │
│  INTERFACE 6: Access Purpose → Consumption Control                              │
│  ──────────────────────────────────────────────────────────────────────────     │
│  Human side:  "This share is approved for analytics only, not AI training"      │
│  Platform:    SECURE VIEW + AGGREGATION POLICY + documented purpose tag         │
│  Risk:        Purpose limitation exists in email; consumer has raw access       │ 
│               → Data used outside agreed scope; provider liability              │
│  Health sign: Purpose limitations are enforced at query time, not assumed       │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## The Multi-Account Structure as Ontological Boundary Enforcement

The DCA's three-account topology (Innovation Studio, Pre-Prod, Production) is not primarily a security decision. It is an **ontological boundary** decision.

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    ACCOUNT BOUNDARIES AS ONTOLOGICAL ZONES                      │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   INNOVATION STUDIO (CDO)                                                       │
│   ────────────────────────────────────────────────────────────────────────      │
│   Ontological status: HYPOTHESIS SPACE                                          │
│   Objects here are CANDIDATES for institutional facthood.                       │
│   A model trained here is not yet a production model.                           │
│   A definition explored here is not yet a canonical definition.                 │
│   A data product prototyped here is not yet a data contract.                    │
│                                                                                 │
│   Key property: CONTROLLED INSTABILITY                                          │
│   Things here are allowed — expected — to change rapidly.                       │
│   Institutional facts are in formation, not in force.                           │
│                                                                                 │
│   Boundary function: Prevents hypothesis-space objects from                     │
│   acquiring the social force of production objects before                       │
│   they are ready. Protects consumers from dependency on                         │
│   objects whose identity conditions are still unstable.                         │
│                                                                                 │
│         ↓  (SDLC gate: identity stabilised, contract defined, reviewed)         │
│                                                                                 │
│   PRE-PROD (RDO)                                                                │
│   ────────────────────────────────────────────────────────────────────────      │
│   Ontological status: VALIDATION SPACE                                          │
│   Objects here are being tested for production-worthiness.                      │
│   They have stable identity conditions but have not yet been                    │
│   accepted as institutional facts by the production community.                  │
│                                                                                 │
│   Key property: CONTROLLED RESEMBLANCE                                          │
│   The environment resembles production closely enough to validate               │
│   that objects will behave as expected when they acquire                        │
│   full institutional force.                                                     │
│                                                                                 │
│   Boundary function: The test of whether an object is ready to be               │
│   treated as institutionally real. UAT is the collective acceptance             │
│   ceremony — teams agree "this is now production-worthy".                       │
│                                                                                 │
│         ↓  (SDLC gate: all parties sign off — UAT approved, governance clear)   │
│                                                                                 │
│   PRODUCTION (RDO)                                                              │
│   ────────────────────────────────────────────────────────────────────────      │
│   Ontological status: INSTITUTIONAL FACT SPACE                                  │
│   Objects here are fully institutionalised.                                     │
│   They carry the full force of data contracts, SLAs, and governance.            │
│   Changes here require the same collective acceptance process                   │
│   that created them in the first place.                                         │
│                                                                                 │
│   Key property: STABILITY UNDER PRESSURE                                        │
│   The defining feature of production is not performance.                        │
│   It is the social commitment of the organisation to maintain                   │
│   these objects as reliable institutional facts for their consumers.            │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## The Data Contract as Constitutive Rule

Searle distinguishes two types of rules:

- **Regulative rules:** govern pre-existing behaviour (e.g., "drive on the left")
- **Constitutive rules:** create the very behaviour they govern (e.g., "a checkmate move counts as winning chess")

Data contracts in the DCA are **constitutive rules**. They do not merely regulate the use of a dataset that exists independently. They *constitute* the dataset as a governed data product. Without the contract, the table is just bytes. With the contract, it is a data product with owners, consumers, SLAs, and purpose.

```
WITHOUT CONTRACT                   WITH CONTRACT
─────────────────────────────      ──────────────────────────────────
FINANCE.GOLD.REVENUE_MONTHLY       FINANCE.GOLD.REVENUE_MONTHLY
is a table.                        is a DATA PRODUCT.

It has rows and columns.           It has:
It may or may not be               • An owner (Finance Data Team)
accurate. Nobody knows.            • Consumers (known, agreed)
Nobody is accountable.             • A definition (invoiced, net, USD)
It might change at any time.       • A freshness SLA (< 1 hour lag)
Consumers use it at their          • A schema contract (versioned)
own risk.                          • A purpose limitation (analytics)
                                   • A quality guarantee (DMF-monitored)
                                   • An escalation path (when things fail)
```

---

## Synthesis: What an SA Needs to See in the Field

When working with a customer, the ontological framework translates directly into diagnostic questions and architectural recommendations.

### Diagnostic Questions (Human Layer)

| Question | What It Reveals |
|----------|----------------|
| "Who is the CDO and what is their mandate?" | Strength of semantic authority |
| "When the CDO and a VP of Engineering disagree, how is it resolved?" | Actual vs. nominal authority |
| "Can you name the owner of the Orders table?" | Ownership health |
| "Has the Finance team signed off on the revenue definition?" | Collective intentionality |
| "What happens when a consumer reports wrong data?" | Accountability and trust health |
| "How do teams find out about schema changes?" | Contract trust health |

### Diagnostic Questions (Object Layer)

| Question | What It Reveals |
|----------|----------------|
| "Do you have tables with no documented owner?" | Institutional orphans |
| "How many tables claim to be the canonical customer record?" | Identity condition failure |
| "Are your masking policies tested against real query patterns?" | Governance interface health |
| "Can Cortex Analyst answer 'what is revenue' consistently?" | Semantic view coverage |
| "Do data quality alerts go to the table owner or a shared mailbox?" | Accountability routing |
| "How do you know when a data contract has been breached?" | Contract enforcement health |

---

## The Architectural North Star

A fully ontologically healthy DCA has the following properties:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        ONTOLOGICAL HEALTH INDICATORS                            │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  IDENTITY HEALTH                                                                │
│  Every core business concept has exactly one canonical representation.          │
│  Consumers can ask "what is X?" and receive a consistent answer.                │
│                                                                                 │
│  OWNERSHIP HEALTH                                                               │
│  Every table, schema, and data product has a named, accountable owner.          │
│  Ownership is encoded in the platform (tags, RBAC), not just in documents.      │
│                                                                                 │
│  CONTRACT HEALTH                                                                │
│  Every consumer-facing data product has a signed, enforced contract.            │
│  Breaches surface to owners before consumers notice.                            │
│                                                                                 │
│  TRUST HEALTH                                                                   │
│  CDO and RDO co-create governance; neither imposes on the other.                │
│  Data Teams are domain owners, not just pipeline maintainers.                   │
│  Consumers trust shared data enough to use it over shadow copies.               │
│                                                                                 │
│  AUTOMATION HEALTH                                                              │
│  Pipelines produce results that the business can explain and defend.            │
│  AI outputs are traceable to the institutional facts that shaped them.          │
│  Schema changes propagate through the platform without silent breakage.         │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

*Next: [05 — SE Enablement Lab](05-se-enablement-lab.md) — hands-on walkthrough of the DCA for internal enablement, with talking points, SQL scripts, and architectural decision exercises.*
