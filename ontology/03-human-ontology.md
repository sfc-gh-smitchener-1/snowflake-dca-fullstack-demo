# Human Ontology — Roles, Trust, and Collective Intentionality in the DCA

> "AI cannot fix unclear semantics. Governance cannot repair missing ownership.
> Automation cannot correct undefined constraints."
> — Enterprise Architecture Guide for the Snowflake Data Cloud, v7

---

## The Central Claim

Data systems are social systems first, and technical systems second.

Every table has an owner. Every policy has an author. Every data contract has parties. Every governance decision was made by a person in a context, under pressure, with incomplete information, shaped by their relationships with other people.

The technical platform executes what has been made explicit. But what gets made explicit — and *how clearly* — is entirely determined by the humans operating the system and the quality of their relationships with each other.

This document maps those humans and those relationships using the same ontological precision applied to Snowflake objects in [02 — Object Ontology](02-object-ontology.md).

---

## Human Actors as Role-Bearers

Following Searle: roles are **status functions** — `X counts as Y in context C`.

A person does not *become* a CDO in any biological or psychological sense. They *count as* CDO within the institutional context of an organization that has collectively assigned that status. The moment the organization withdraws collective recognition, the status evaporates — even if the person's skills and knowledge remain.

This is why:
- A CDO without organizational authority is a technical expert, not a CDO
- A governance policy without executive backing is a document, not a policy
- A data contract without both parties' acceptance is a proposal, not a contract

```
┌─────────────────────────────────────────────────────────────────────┐
│                    THE THREE ROLE DOMAINS                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   CDO (Chief Data Officer)                                          │
│   ─────────────────────────────────────────────────────────────     │
│   Status function: "counts as the authority over data meaning,      │
│   standards, and enterprise governance"                             │
│                                                                     │
│   Institutional backing required:                                   │
│   • C-suite mandate to set and enforce data standards               │
│   • Budget authority over governance tooling                        │
│   • Cross-functional jurisdiction (not just IT)                     │
│   • Recognised as arbiter of semantic disputes                      │
│                                                                     │
│   When backing is weak: CDO becomes advisory-only.                  │
│   Governance becomes suggestion. Semantic drift accelerates.        │
│                                                                     │
│   RDO (Regional Data Office / Platform Operations)                  │
│   ─────────────────────────────────────────────────────────────     │
│   Status function: "counts as responsible for data availability,    │
│   infrastructure, ingestion, and SDLC execution"                    │
│                                                                     │
│   Institutional backing required:                                   │
│   • Operational authority over production accounts                  │
│   • SLA accountability with clear escalation paths                  │
│   • Engineering capacity to execute platform changes                │
│   • Trust relationship with CDO (not subordination — partnership)   │
│                                                                     │
│   When backing is weak: RDO becomes a ticket queue.                 │
│   Platform becomes reactive. Data freshness and reliability fail.   │
│                                                                     │
│   DATA TEAMS (Domain Owners)                                        │
│   ─────────────────────────────────────────────────────────────     │
│   Status function: "counts as accountable for the meaning and       │
│   quality of their domain's data products"                          │
│                                                                     │
│   Institutional backing required:                                   │
│   • Clear domain ownership (not shared responsibility)              │
│   • Authority to define and enforce domain contracts                │
│   • Consumer-facing accountability (SLAs, documentation)            │
│   • Escalation path to CDO for cross-domain semantic disputes       │
│                                                                     │
│   When backing is weak: Data Teams become pipeline maintainers.     │
│   Domain data products become undocumented internal tables.         │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## The Relationship Map

Human relationships in the DCA are not org-chart relationships. They are **ontological relationships** — each carries specific dependencies, trust requirements, and failure modes.

```
┌─────────────────────────────────────────────────────────────────────┐
│                    DCA HUMAN RELATIONSHIP MAP                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│                         CDO                                         │
│                          │                                          │
│              ┌───────────┼───────────┐                              │
│              │           │           │                              │
│         STANDARDS    GOVERNANCE   CONTRACTS                         │
│         (defines)    (mandates)    (ratifies)                       │
│              │           │           │                              │
│              └───────────┼───────────┘                              │
│                          │                                          │
│              ┌───────────┴───────────┐                              │
│              │                       │                              │
│             RDO                 DATA TEAMS                          │
│              │                       │                              │
│         EXECUTES                  OWNS                              │
│         (infrastructure,          (domain products,                 │
│          SDLC, ops)               quality, definitions)             │
│              │                       │                              │
│              └───────────┬───────────┘                              │
│                          │                                          │
│                      CONSUMERS                                      │
│                   (internal teams,                                  │
│                    external partners,                               │
│                    AI/ML systems)                                   │
│                                                                     │
│   RELATIONSHIP TYPES:                                               │
│                                                                     │
│   CDO ←──── TRUST ────→ RDO                                         │
│   (semantic authority vs operational authority — must be mutual)    │
│                                                                     │
│   CDO ←── MANDATE ───→ DATA TEAMS                                   │
│   (CDO sets standards; Teams accept and implement)                  │
│                                                                     │
│   RDO ←── SERVICE ───→ DATA TEAMS                                   │
│   (RDO provides platform; Teams are the primary beneficiaries)      │
│                                                                     │
│   DATA TEAMS ←── CONTRACT ──→ CONSUMERS                             │
│   (formal agreement on schema, quality, SLA, purpose)               │
│                                                                     │
│   CDO ←── ARBITRATION ──→ DATA TEAMS                                │
│   (CDO resolves semantic disputes between domains)                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Trust as an Ontological Primitive

Trust is not a soft concept. In social ontology, trust is a **load-bearing structure** — it is the condition under which institutional facts remain in force when no one is actively monitoring them.

Data governance works at scale only through trust, because no policy can be individually audited at query time for every transaction. The platform enforces what is explicit. Trust is what keeps people maintaining the explicitness.

### The Three Trust Relationships in the DCA

```
1. CDO ↔ RDO: HORIZONTAL TRUST (between equals)
───────────────────────────────────────────────────────
Nature: Neither owns the other. CDO owns meaning. RDO owns operations.
        Without mutual trust, each will encroach on the other's domain
        or withhold cooperation.

Failure mode (CDO dominates):
  CDO mandates platform changes without RDO operational input.
  RDO executes reluctantly. Platform becomes unstable.
  "Governance is imposed, not co-created."

Failure mode (RDO dominates):
  RDO optimises for uptime and throughput. Governance is treated as overhead.
  Data standards erode. Technical debt accumulates.
  "Infrastructure works but nothing means anything."

Health indicator:
  CDO and RDO co-sign data contracts.
  Architectural decisions require both to approve.


2. CDO / RDO ↔ DATA TEAMS: VERTICAL TRUST (authority and acceptance)
───────────────────────────────────────────────────────────────────────
Nature: CDO has authority; Data Teams have local knowledge.
        Neither can succeed without the other.
        Trust flows in both directions.

Failure mode (authority without trust):
  Standards are mandated but not explained. Teams comply superficially.
  Classification is checkbox-driven. Semantic drift continues beneath
  the surface of apparent compliance.

Failure mode (local autonomy without standards):
  Each domain defines its own semantics. No interoperability.
  The org has data. It does not have a data platform.

Health indicator:
  Data Teams participate in contract definition, not just sign-off.
  CDO decisions incorporate domain feedback.
  Disputes have a clear, respected resolution path.


3. DATA TEAMS ↔ CONSUMERS: CONTRACT TRUST (producer to consumer)
───────────────────────────────────────────────────────────────────────
Nature: Consumer depends on producer for data that is accurate,
        fresh, and semantically stable. Producer depends on consumer
        to use data within agreed purpose.

Failure mode (producer unaccountable):
  Schema changes break consumers without notice.
  SLAs are aspirational, not binding.
  Consumers stop trusting the data. Shadow copies proliferate.

Failure mode (consumer out of scope):
  Consumer uses data for purposes outside the contract
  (e.g., re-exporting PII, training models on restricted data).
  Provider bears liability. Trust collapses.

Health indicator:
  Schema changes are versioned and communicated in advance.
  Consumers have clear, documented SLAs.
  Purpose limitations are encoded in governance policies, not just text.
```

---

## Collective Intentionality: When Governance Becomes Real

Searle's concept of **collective intentionality** — "we intend" rather than "I intend" — is the mechanism that converts individual policy documents into functioning institutional facts.

```
INDIVIDUAL INTENTIONALITY          COLLECTIVE INTENTIONALITY
─────────────────────────────      ──────────────────────────────────
"I agree to follow this            "We — as CDO, RDO, and Data Teams —
 data standard"                     agree to maintain this standard
                                    and hold each other accountable"

Result: Compliance while           Result: Self-enforcing governance.
monitored; drift otherwise.        Violations surface because teams
                                   police their own domain boundaries.
```

### The Three Conditions for Collective Intentionality in Data Governance

| Condition | What It Looks Like in Practice | Failure Signal |
|-----------|-------------------------------|----------------|
| **Shared understanding** | All parties interpret a standard the same way | Semantic disputes that recur |
| **Mutual commitment** | All parties accept the standard as binding on themselves | "That standard applies to other teams" |
| **Reciprocal accountability** | Violations are raised, not ignored | Silent non-compliance; no feedback loops |

---

## Power, Authority, and the Ghost of Informal Influence

Formal authority structures (the org chart) are not the only force shaping data systems. **Informal influence** — the trusted engineer whose opinion carries more weight than their title suggests, the senior analyst who decides what "revenue" really means in practice — is equally real and often more durable.

```
FORMAL AUTHORITY RISKS                 INFORMAL INFLUENCE RISKS
──────────────────────────────         ─────────────────────────────────
• Decisions made without               • Shadow standards develop outside
  domain knowledge                       formal governance channels
• Compliance without buy-in            • Critical definitions exist only
• Bottlenecks at approval gates          in one person's head
• Policy designed for auditors,        • Key person dependency on
  not practitioners                      semantic arbiters
• Accountability without empowerment   • Informal veto power blocks
                                         architectural progress
```

**Architectural implication:** The DCA must be designed to capture informal knowledge and make it explicit. Semantic views, data contracts, and ownership metadata are the mechanisms for converting informal institutional knowledge into first-class platform objects that survive personnel changes.

---

## Human Failure Modes and Their Architectural Signatures

These are the most common human-origin failures and the data system signatures they produce:

```
HUMAN FAILURE                  SYSTEM SIGNATURE
─────────────────────────────  ──────────────────────────────────────────
CDO/RDO relationship breaks    Governance policies exist but are not
                               applied to Bronze ingestion.
                               Schema changes bypass review.
                               Production incidents attributed to
                               "platform issues" not ownership gaps.

Data Team ownership is vague   Tables with no documented owner.
                               Multiple tables claiming to be the
                               "canonical" version of a concept.
                               Quality alerts with no assigned
                               resolution owner.

Contract trust is absent       Shadow datasets maintained by consumers.
                               Consumers use Bronze data directly,
                               bypassing Silver governance.
                               "We don't trust the shared tables."

Collective intentionality      Policies applied inconsistently across
is absent                      domains. Classification tags that
                               mean different things in different schemas.
                               Governance dashboards green while
                               semantic quality degrades.

Informal knowledge not         Business-critical logic embedded in
captured                       unowned stored procedures.
                               Metric definitions that exist only in
                               a senior analyst's Confluence page.
                               Model results that cannot be explained
                               because feature definitions were never
                               formalised.
```

---

## The Human Condition the DCA is Designed to Solve

The architecture does not assume perfect humans. It assumes:

- People will disagree about meaning — so it provides contracts and arbitration paths
- People will leave — so it encodes knowledge as first-class metadata
- People will make mistakes — so it provides lineage, audit history, and rollback
- People will act in local self-interest — so it provides governance with teeth
- People will not read documentation — so it encodes constraints in the platform itself

The DCA is not a governance programme. It is a **system for making human agreements durable** in the face of the natural entropy that affects every human organisation at scale.

---

*Next: [04 — DCA Ontological Synthesis](04-dca-ontological-synthesis.md) — where the object ontology and the human ontology converge into a single coherent framework.*
