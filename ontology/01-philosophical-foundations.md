# Philosophical Foundations of the Data Cloud Architecture

> "The platform can only execute what has been made explicit."
> — Enterprise Architecture Guide for the Snowflake Data Cloud, v7

---

## What Is Ontology, and Why Does It Matter Here?

Ontology, in its philosophical sense, is the study of **what exists** — the categories of being, how things relate to one another, what makes something the thing it is, and how objects depend on each other for their existence.

Applied to enterprise data architecture, ontology asks:

- What kinds of things does a data platform contain — and are they the same *kind* of thing?
- What makes a table the *same* table after a schema change?
- Does a governance policy exist independently of the people who agreed to it?
- When a CDO defines a data standard, what kind of object have they created?
- How does intent — originating in a human mind — become enforceable system behaviour?

These are not abstract questions. Every architectural decision you make encodes answers to them, whether you are conscious of that or not. Ontology makes those answers explicit. And as the v7 guide asserts: **the platform can only execute what has been made explicit**.

---

## The Three Branches This Work Draws On

### 1. Barry Smith & Basic Formal Ontology (BFO)

BFO is a top-level ontology used in biomedical and engineering domains to create interoperable knowledge representations. Its core distinction:

```
CONTINUANTS                        OCCURRENTS
────────────────────────────       ────────────────────────────
Entities that persist through      Entities that unfold through
time while maintaining identity    time — they happen

Examples in Snowflake:             Examples in Snowflake:
- Tables                           - Queries
- Roles                            - Stream change records
- Policies                         - Task executions
- Accounts                         - Data pipeline runs
- Schemas                          - Refresh cycles
```

**Why it matters:** A table and a query are fundamentally different kinds of thing. A table persists — it has identity conditions across time. A query happens and is gone. A stream sits between: it is a continuant (it persists) whose content is constituted by occurrents (the change events that flow through it). Treating them as the same kind of object leads to architectural confusion.

---

### 2. Nicola Guarino — Formal Ontology and Identity

Guarino's work establishes that every object needs **identity conditions** — rules that tell us when two descriptions refer to the same object, and when a persisting object is still "the same" after change.

```
RIGID IDENTITY                     NON-RIGID / ROLE IDENTITY
────────────────────────────       ────────────────────────────
Object is necessarily what         Object plays a role that could
it is — no context changes it      in principle be played by another

Examples in Snowflake:             Examples in Snowflake:
- An Account (UUID-identified)     - "The Production Database"
- A Table's creation timestamp     - "The Data Owner" (a role,
- A Share's unique name              not a fixed person)
                                   - "The Master Data" table
                                     (could be replaced)
```

**Key insight for DCA:** When engineers say "the production database" they are using a *role description* not an *identity condition*. The database that plays the role of "production" can change. This matters enormously for governance, SDLC, and handoffs. The v7 concept of ownership boundaries only works if the objects being owned have stable, agreed identity conditions.

---

### 3. John Searle — Social Ontology and Institutional Facts

This is the most important framework for data architecture, and the least understood.

Searle distinguishes two kinds of facts:

```
BRUTE FACTS                        INSTITUTIONAL FACTS
────────────────────────────       ────────────────────────────
Exist independently of human       Exist only because humans
agreement or representation        collectively agree they do

"This table has 10M rows"          "This table is governed by
"This query ran in 300ms"           the Finance Data Contract"
"This account is in AWS            "This person is the CDO"
 us-east-1"                        "This data is PII"
                                   "This share is approved
                                    for external distribution"
```

**The formula for institutional facts:** `X counts as Y in context C`

- A cluster of rows *counts as* a customer record *in the context of* the CRM domain contract
- A person *counts as* the CDO *in the context of* the organizational authority structure
- A Snowflake ROLE *counts as* SYSADMIN *in the context of* a given account

**Why this is architecturally critical:**

Institutional facts require **collective intentionality** — shared "we-intentions" — to remain in force. The moment the collective stops maintaining the agreement, the institutional fact collapses.

```
DATA GOVERNANCE FAILURE ROOT CAUSE
───────────────────────────────────
When a data contract is defined but
teams do not collectively accept it,
the contract is a brute fact document
(bytes on disk) but NOT an
institutional fact (no governing force).

This is why governance programs fail
despite having policies, tools, and
frameworks in place.

The platform enforces what is explicit.
But what is "explicit" in a social
system requires collective agreement,
not just written documentation.
```

---

## The Dependency Chain as Ontological Architecture

The v7 guide's core framework — `People → Data → Governance → Automation` — is not just a sequencing model. It is an **ontological dependency chain**.

```
┌─────────────────────────────────────────────────────────────────────┐
│              ONTOLOGICAL DEPENDENCY CHAIN                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   PEOPLE                                                            │
│   ───────                                                           │
│   Source of intent, meaning, authority, and collective agreement.   │
│   Institutional facts originate here.                               │
│   Without this layer being stable, nothing downstream holds.        │
│                                                                     │
│   Ontological type: AGENTIVE SUBJECTS                               │
│   (capable of intention, authority, and social acts)                │
│                ↓  (encode intent as)                                │
│   DATA                                                              │
│   ────                                                              │
│   Representations of state, meaning, and events.                    │
│   Data objects inherit their meaning from the human agreements      │
│   that surround them — schemas, contracts, classifications.         │
│   Without stable semantics from the People layer,                   │
│   data encodes ambiguity at scale.                                  │
│                                                                     │
│   Ontological type: DEPENDENT CONTINUANTS                           │
│   (their meaning depends on the institutional context around them)  │
│                ↓  (constrain via)                                   │
│   GOVERNANCE                                                        │
│   ──────────                                                        │
│   The set of institutional facts made enforceable by the platform.  │
│   Policies, classifications, contracts, RBAC — these are            │
│   social objects given technical form.                              │
│   Without the People layer maintaining collective agreement,        │
│   governance is a brute fact (text) not an institutional fact.      │
│                                                                     │
│   Ontological type: NORMATIVE INSTITUTIONAL OBJECTS                 │
│   (ought-to-be enforced; exist in virtue of collective acceptance)  │
│                ↓  (execute as)                                      │
│   AUTOMATION                                                        │
│   ──────────                                                        │
│   Processes that act on data according to governance rules.         │
│   Automation has no semantics of its own — it executes what         │
│   the three upstream layers have made explicit.                     │
│   Instability upstream → amplified failure downstream.              │
│                                                                     │
│   Ontological type: OCCURRENTS / PROCESSES                          │
│   (they happen; they are caused; they produce effects)              │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Three Ontological Failure Modes

These map directly to the failure modes the v7 guide identifies:

### Failure Mode 1: Semantic Drift
**Ontological cause:** The identity conditions for a data object were never made explicit. Different teams hold different institutional facts about what the object *is*.

```
SYMPTOM                            ROOT CAUSE
──────────────────────────────     ─────────────────────────────────────
"Revenue" means different things   No agreed identity condition for the
in Finance, Sales, and Product.    concept "revenue". Multiple
Reports contradict each other.     incompatible institutional facts
                                   coexist without resolution.
```

### Failure Mode 2: Governance Without Force
**Ontological cause:** A governance policy was created as a document (brute fact) without the collective intentionality needed to make it an institutional fact.

```
SYMPTOM                            ROOT CAUSE
──────────────────────────────     ─────────────────────────────────────
Data classification policy         Policy exists as text. Teams do not
exists but teams ignore it.        collectively accept it as binding.
Masking policies are applied       No shared "we-intention" to enforce.
inconsistently.                    Searle: the institutional fact has
                                   no collective intentionality behind it.
```

### Failure Mode 3: Automation Amplifying Ambiguity
**Ontological cause:** Automation treats semantically unstable objects as if their identity were fixed, executing at scale before the upstream ontological instability is resolved.

```
SYMPTOM                            ROOT CAUSE
──────────────────────────────     ─────────────────────────────────────
Pipeline produces results that     Automation inherited ambiguous
no one trusts. Dashboards          semantics from an unstable data
diverge. AI models trained on      layer. Occurrents (processes)
contested data produce             executed what was explicit.
contested outputs.                 What was explicit was wrong.
```

---

## Ontological Prerequisites for the DCA

Before any technical architecture is evaluated, the following ontological conditions must be in place:

| Condition | Philosophical Term | DCA Translation |
|-----------|-------------------|-----------------|
| Agreed identity for core objects | Identity conditions | Canonical data definitions, golden records |
| Shared meaning for domain concepts | Collective intentionality | Data contracts with actual stakeholder sign-off |
| Clear authority structure | Deontic relations | CDO/RDO/Data Team ownership boundaries |
| Explicit dependency relationships | Ontological dependence | Documented lineage and object hierarchies |
| Normative rules with collective backing | Institutional facts | Governance policies that teams actually follow |

---

## The Key Claim

> Snowflake's architecture is valuable not because it is fast — that is table stakes.
> It is valuable because it is one of the few platforms designed to **carry intent as first-class metadata**,
> **evaluate that intent at runtime**, and **observe enforcement continuously**.
>
> But it can only do this for intent that has first been made explicit by the humans who operate it.
> The platform executes ontology. It cannot create ontology.

The job of the architect — and the SA — is to surface the ontological work that must happen before the platform can deliver its promise.

---

*Next: [02 — Object Ontology](02-object-ontology.md) — formal taxonomy of Snowflake objects and their relationships.*
