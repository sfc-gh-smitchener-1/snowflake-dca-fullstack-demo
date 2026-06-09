# Object Ontology — Snowflake Data Cloud

> "Dependencies are mechanical rather than philosophical. Each architectural layer
> inherits the stability or instability of the layer that precedes it."
> — Enterprise Architecture Guide for the Snowflake Data Cloud, v7

---

## Taxonomy Overview

Snowflake objects are not all the same *kind* of thing. Treating them as if they are
leads to architectural mistakes in governance, lineage, and ownership design.

This document establishes a formal taxonomy using three axes:

1. **Continuant vs. Occurrent** — does it persist, or does it happen?
2. **Independent vs. Dependent** — does it exist on its own, or only in relation to something else?
3. **Physical vs. Institutional** — does it exist as bytes/compute, or by collective agreement?

---

## The Object Hierarchy

```
SNOWFLAKE OBJECT UNIVERSE
│
├── ORGANIZATION                          [Independent Continuant — Institutional]
│   │   Exists by Snowflake agreement. Contains accounts.
│   │   Identity: org name + Snowflake-assigned UUID
│   │
│   └── ACCOUNT                           [Independent Continuant — Institutional]
│       │   The primary unit of isolation. Has its own users, roles, objects.
│       │   Identity: account locator (immutable); account name (mutable)
│       │   Note: Name is a role description; locator is an identity condition.
│       │
│       ├── WAREHOUSE                     [Independent Continuant — Physical]
│       │       Compute resource. Can exist with no objects attached.
│       │       Identity: name within account
│       │       Lifecycle: created → running/suspended → dropped
│       │       Ontological note: An Interactive Warehouse has stronger
│       │       dependence on its associated tables than a standard warehouse.
│       │
│       ├── DATABASE                      [Independent Continuant — Institutional]
│       │   │   Namespace container. Exists to organize, not compute.
│       │   │   Identity: name within account
│       │   │
│       │   └── SCHEMA                    [Dependent Continuant — Institutional]
│       │       │   Depends on its database for existence.
│       │       │   Identity: database.schema name pair
│       │       │
│       │       ├── TABLE                 [Dependent Continuant — Physical/Institutional]
│       │       │       Depends on schema. Stores data physically.
│       │       │       Identity: fully qualified name (DB.SCHEMA.TABLE)
│       │       │       Persistence: survives data changes; identity is
│       │       │       NOT tied to its rows
│       │       │       Schema change: RENAME preserves identity;
│       │       │       DROP + recreate creates a new object
│       │       │
│       │       ├── DYNAMIC TABLE         [Dependent Continuant — Causal]
│       │       │       Depends on source tables for both existence AND content.
│       │       │       Identity: name, but content is causally derived
│       │       │       Ontological type: a table whose state is
│       │       │       continuously caused by its source query
│       │       │       Critical: if source is dropped, dynamic table breaks —
│       │       │       existential dependence on source
│       │       │
│       │       ├── INTERACTIVE TABLE     [Dependent Continuant — Physical/Causal]
│       │       │       Static: depends on warehouse for serving, schema for existence
│       │       │       Dynamic: additionally causally depends on source (TARGET_LAG)
│       │       │       Strong coupling to Interactive Warehouse
│       │       │
│       │       ├── VIEW                  [Dependent Continuant — Purely Institutional]
│       │       │       No physical storage. Exists only as a query definition.
│       │       │       Identity: name + definition
│       │       │       Existentially depends on all tables in its SELECT
│       │       │       Secure View adds an institutional layer:
│       │       │       access to definition is restricted by collective agreement
│       │       │
│       │       ├── STREAM                [Dependent Continuant — Relational/Temporal]
│       │       │       Tracks changes on a source object.
│       │       │       Identity: name + source object reference
│       │       │       Unique ontological character: it is a continuant whose
│       │       │       content is constituted by occurrents (change events)
│       │       │       Offset (consumer position) is part of its identity state
│       │       │
│       │       ├── TASK                  [Dependent Occurrent / Process Bearer]
│       │       │       A scheduled or triggered process definition.
│       │       │       The task definition is a continuant.
│       │       │       Task executions are occurrents — they happen.
│       │       │       Ontological note: Task depends on warehouse and SQL;
│       │       │       its executions are causally triggered events
│       │       │
│       │       ├── FUNCTION / PROCEDURE  [Dependent Continuant — Institutional]
│       │       │       Exists as definition (continuant).
│       │       │       Invocations are occurrents.
│       │       │
│       │       ├── STAGE                 [Dependent Continuant — Physical]
│       │       │       Points to cloud storage. Internal stage is owned by Snowflake.
│       │       │       External stage is a reference — depends on external existence.
│       │       │
│       │       └── POLICY OBJECTS        [Dependent Continuant — Normative/Institutional]
│               │   Masking, Row Access, Aggregation, Projection Policies
│               │   These are normative institutional objects:
│               │   they encode what OUGHT to happen, not just what IS
│               │   They depend on the role/account context to evaluate
│               │
├── ROLES                                 [Dependent Continuant — Institutional]
│       Exist within an account. Assigned to users or other roles.
│       Identity: name within account
│       Ontological character: Roles are STATUS FUNCTIONS (Searle)
│       "This user counts as SYSADMIN in this account"
│       The role has no physical existence — only institutional force
│
├── SHARES                                [Dependent Continuant — Relational/Institutional]
│       Exists at account level. References objects in source account.
│       Identity: name within provider account
│       Ontological note: A Share is a RELATION, not an object —
│       it is the institutional bridge between provider and consumer
│       Its force depends on: (a) Snowflake infrastructure and
│       (b) collective agreement (account whitelist, grants)
│
└── QUERIES / EXECUTIONS                  [Occurrents — Physical/Computational]
        Happen. Have start/end. Produce results.
        Not continuants — once complete, the query-event is in the past.
        Query results may persist as tables (continuants) or be ephemeral.
```

---

## Dependence Map

The following shows which objects existentially depend on which others.
If a depended-upon object is dropped, dependent objects break or disappear.

```
┌─────────────────────────────────────────────────────────────────────┐
│                    EXISTENTIAL DEPENDENCE CHAIN                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   ORGANIZATION                                                      │
│       └──depends──> ACCOUNT                                         │
│                         └──depends──> DATABASE                      │
│                                           └──depends──> SCHEMA      │
│                                                             │        │
│                                    ┌────────────────────────┘        │
│                                    │                                │
│                               TABLE ◄──────────────── STREAM       │
│                                    │         (tracks changes on)    │
│                                    │                                │
│                               TABLE ◄──────────────── DYNAMIC TABLE│
│                                    │    (causally derived from)     │
│                                    │                                │
│                               TABLE ◄──────────────── VIEW         │
│                                    │    (queries against)           │
│                                    │                                │
│                            WAREHOUSE ◄─────────────── TASK         │
│                                         (executes on)               │
│                                                                     │
│   ROLES ──(grant to)──> USERS / OTHER ROLES                        │
│   ROLES ──(grant on)──> OBJECTS (privilege relationship)           │
│                                                                     │
│   SHARES ──(references)──> OBJECTS in provider account             │
│   SHARES ──(consumed by)──> consumer ACCOUNT                       │
│                                                                     │
│   POLICIES ──(attached to)──> TABLE COLUMNS / TABLES               │
│   POLICIES ──(evaluated against)──> ROLE context at query time     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Identity Conditions for Core Objects

A critical question for governance, SDLC, and lineage: **when is an object still the same object?**

| Object | Identity Condition | Change That Preserves Identity | Change That Breaks Identity |
|--------|-------------------|-------------------------------|----------------------------|
| Account | Account locator (UUID-like) | Name change, region alias | Cannot be "the same" account after drop/recreate |
| Database | Name within account | Objects inside change | DROP + CREATE with same name = new object |
| Table | Fully qualified name | Column renames, data changes, row additions | DROP + CREATE = new object; RENAME = same object |
| Dynamic Table | Name + source query | TARGET_LAG change | Changing source query = semantically new object |
| View | Name + definition | Underlying data changes | Changing SELECT = new semantic object |
| Stream | Name + source ref + offset | Data flowing through | Source dropped = stream broken |
| Role | Name within account | Privilege changes | DROP + recreate = new role (grants lost) |
| Share | Name within provider account | Objects added/removed | DROP + recreate = consumers lose access |
| Policy | Name + definition | Re-attached elsewhere | Changed definition = changed enforcement |

---

## The Medallion Layers as Ontological Zones

The Bronze/Silver/Gold architecture maps onto distinct ontological territories:

```
┌─────────────────────────────────────────────────────────────────────┐
│                    MEDALLION AS ONTOLOGICAL ZONES                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  BRONZE (Raw)                                                       │
│  ─────────────────────────────────────────────────────────────────  │
│  Ontological type: BRUTE FACTS                                      │
│  Objects here represent the world as it was recorded.               │
│  Minimal institutional overlay. Closest to physical reality.        │
│  Identity: source system + timestamp (immutable record)             │
│  Governed by: RDO — who controls ingestion fidelity                 │
│  Key property: IMMUTABILITY — the past should not be rewritten      │
│                                                                     │
│         ↓  (transformation adds institutional meaning)              │
│                                                                     │
│  SILVER (Governed)                                                  │
│  ─────────────────────────────────────────────────────────────────  │
│  Ontological type: INSTITUTIONAL FACTS in formation                 │
│  Objects here are brute facts given institutional meaning:          │
│  cleansed, conformed, classified, named by enterprise standards.    │
│  Identity: enterprise canonical key (golden record)                 │
│  Governed by: CDO — who controls what things mean enterprise-wide   │
│  Key property: CONFORMANCE — objects here answer to shared          │
│  semantics, not source-system semantics                             │
│                                                                     │
│         ↓  (domain logic adds business-level institutional facts)   │
│                                                                     │
│  GOLD (Domain Products)                                             │
│  ─────────────────────────────────────────────────────────────────  │
│  Ontological type: FULL INSTITUTIONAL FACTS                         │
│  Objects here exist to serve specific institutional purposes:       │
│  the Finance revenue view, the Sales pipeline model, etc.           │
│  Identity: business concept (e.g. "Q3 Revenue by Region")           │
│  Governed by: Data Teams — who define domain meaning and SLAs       │
│  Key property: INTENTIONALITY — these objects were created to       │
│  represent specific business concepts for specific consumers        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Ontological Implications for Architecture Decisions

### 1. Never treat a View as equivalent to a Table
A view has no independent physical existence. It is constituted by its source tables at query time. When you govern a view, you are governing a *derived institutional fact* — the governance only holds if the underlying tables remain stable.

### 2. Stream offset is part of the stream's state — it is not just metadata
The consumer position in a stream is an identity-relevant property. Two streams on the same table at different offsets are in different *states* — they do not represent the same information. Resetting a stream offset is an ontologically significant act.

### 3. Roles are status functions, not physical objects — treat them as such
When you DROP and recreate a role with the same name, you have created a new status function with the same label. All privileges granted to the old role are gone. This matters in SDLC: role cloning is not role preservation.

### 4. Data contracts are institutional facts — they require collective backing
A contract defined in YAML and stored in a repo is a *document* (brute fact). It becomes an institutional fact only when the relevant parties (CDO, RDO, Data Team, consumers) collectively accept it as binding. The Snowflake platform can enforce policies. It cannot manufacture collective intentionality.

### 5. The Bronze layer must be treated as brute fact territory
Applying heavy institutional transformation at Bronze violates its ontological function. Bronze is where the world was recorded. Silver is where it gets interpreted. Conflating them is where semantic debt originates.

---

*Next: [03 — Human Ontology](03-human-ontology.md) — the CDO, RDO, Data Teams, and how human relationships constitute and break data systems.*
