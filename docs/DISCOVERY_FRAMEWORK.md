# Enterprise Architect Discovery Framework

> **Audience:** Enterprise Architects & Solution Architects running customer intro / discovery sessions.
> **Purpose:** A reusable, industry-agnostic set of discovery questions that you can (a) derive from
> documentation a prospect sends you (reference architectures, L1 project plans from partners) and
> (b) tailor to the specific customer and their vertical.
> **Grounding:** Organized on the DCA spine (`PEOPLE → CONTRACTS → DATA → GOVERNANCE → CONSUMPTION → AI`),
> the ontology reference architecture, and the runnable industry demos (HCLS, Fintech, DCIM).

---

## How to Use This Framework

**Assume the customer has none of this in place.** Most prospects will *not* have data contracts, a
knowledge graph, a governed semantic layer, or named data ownership — and that's the point. Discovery is not
an audit of their DCA maturity; it is a diagnostic that surfaces where meaning, ownership, and trust have
broken down, and then **correlates each finding to the class of capability a DCA-type solution provides.**

So every question does two things:

1. **Reads current state** in the customer's own terms (no DCA vocabulary required to answer).
2. **Correlates to a DCA-type capability** — the *category* of solution their answer points toward, described
   generically (e.g., "automated schema-change detection"), not as a specific product object.

Run discovery in three passes:

1. **Pre-read (async).** Before the call, mine the customer's documents — reference architecture, L1 project
   plan, current-state diagrams, RFP. Use [Part 2](#part-2--document-driven-discovery) to turn those artifacts
   into targeted questions. You walk in already knowing 60% of their landscape.
2. **Base pass (any industry).** Use the [Part 1](#part-1--the-base-question-set-any-industry) question bank,
   organized along the DCA spine. These apply to every customer regardless of vertical or platform.
3. **Tailor pass (their industry).** Layer in the [Part 3](#part-3--industry-tailoring) vertical bank (HCLS,
   Fintech, DCIM) or generate one for a new vertical.

Score what you hear against the [maturity rubric](#part-4--maturity-rubric--red-flags), then correlate the
gaps to a solution path ([Part 5](#part-5--from-answers-to-a-dca-type-solution)).

**The golden rule:** *Ask the ontological question before the technical one.* "What does 'customer' mean to
you?" precedes "What is your CDC strategy for the customer table?"

**On the "Correlates to" column:** it names the *capability category* the finding points toward — vendor- and
implementation-neutral. It is where a DCA-type solution creates value, not a claim the customer has it today.

---

## The DCA Spine (mental model for the whole conversation)

```
PEOPLE  →  CONTRACTS  →  DATA  →  GOVERNANCE  →  CONSUMPTION  →  AI
  │           │           │          │              │            │
who owns   what is    where does   who is        who reads   what does
& is       promised   it live &    protected     it & how    the model
accountable to whom    how does it  at each                   run on
           (schema,    flow         boundary                  (governed
            quality,   (medallion)                             data?)
            SLA,
            lineage)
```

Every layer is a hard prerequisite for the next. AI at the end doesn't make the earlier layers optional —
it makes them **load-bearing**. Weakness in any layer surfaces as a broken promise in the layers to its right.
Discovery walks the spine and finds *which* promises are unbacked today.

---

## The Five Anchor Questions

If you have only five minutes, ask these. They are the fastest read on organizational data health, work in
any industry on any platform, and each maps to a DCA layer. Everything in Part 1 elaborates on these.

| # | Question | What It Diagnoses | Correlates to (DCA-type capability) |
|---|----------|-------------------|--------------------------------------|
| 1 | "If I ask five different people what *revenue* (or your core metric) means, will I get five different answers?" | Semantic health / shared meaning | Governed semantic layer / shared definitions |
| 2 | "Who is *personally* accountable when your core operational table has wrong data?" | Ownership health | Data ownership model & accountability |
| 3 | "How do consumers find out when a schema has changed — before or after it breaks their dashboard?" | Contract trust | Data contracts + change detection |
| 4 | "Does your data office have the authority to mandate a definition that Engineering *must* implement?" | Institutional authority | Governance authority & enforcement |
| 5 | "Do your data scientists use the governed tables, or do they keep their own copies?" | Consumer trust — the ultimate test | Trusted, adopted data products |

If all five are strong, the customer is ready for advanced platform + AI capabilities. If any is weak, the
human/architectural work must happen before AI can deliver on its promise — and *that gap is your value
proposition*.

---

# Part 1 — The Base Question Set (Any Industry)

Organized by the DCA spine plus two cross-cutting sections (Architecture & Topology, Ontology & Semantics).
Each row: **Q** = what to ask (in the customer's terms), **Diagnoses** = what it reveals, **Correlates to** =
the generic DCA-type capability category the answer points toward.

---

## 1.0 Architecture & Topology (the map)

Establish the physical and organizational shape of the estate first. This frames every later answer, whatever
platform they run on.

| Q | Diagnoses | Correlates to (DCA-type capability) |
|---|-----------|--------------------------------------|
| How many data platforms / accounts do you run, and along what lines are they split — region, business unit, environment, acquisition? | Topology & isolation drivers | Account/tenancy strategy (isolation vs. sharing) |
| Walk me through your data layers. Where does raw land, where is it conformed, and where do business products live? | Layer discipline; where transformation happens | Medallion architecture (raw → curated → semantic) |
| Which teams own which layers? Is the ingestion team the same as the team producing business metrics? | Ownership boundaries | Layered ownership (platform / governance / domain) |
| What does data movement actually run on — a modern transform tool, hand-written jobs, or a legacy ELT platform? | Transformation strategy; modernization surface | Declarative, version-controlled pipelines |
| How do you separate dev / test / prod, and how expensive is it to spin up a copy for a team? | SDLC maturity | Cheap environment/branch isolation (e.g., clones) |
| When you acquire a company or onboard a new source, what's the integration path and how long until its data is trustworthy? | Extensibility; entity-resolution need | Repeatable onboarding + entity resolution |

---

## 1.1 PEOPLE — Ownership & Accountability

The foundational layer. Ownership only means something if the organization collectively agrees a team owns
something **and holds them accountable**. Most customers have technical access control but no real ownership.

| Q | Diagnoses | Correlates to (DCA-type capability) |
|---|-----------|--------------------------------------|
| Who is *personally* accountable when your core table has wrong data — a named person, or a queue? | Real vs. nominal ownership | Named data-product ownership |
| Look at your most important tables — who owns them technically? A super-admin role, or a domain team? | "Platform owns everything = nobody owns anything" | Ownership assigned to domain roles |
| Does your data office have authority to mandate a definition Engineering must implement, or only to recommend? | Institutional authority vs. advisory | Governance with enforcement authority |
| When a data-product owner leaves, what happens to the knowledge of what it means and why it exists? | Bus-factor; tribal vs. institutional knowledge | Durable, embedded product metadata |
| Is there a clear split between platform operations and governance policy, or is it one overloaded team? | Operating-model separation | Distinct platform vs. governance functions |
| Who signs off before a new data product is declared "production"? | Promotion gate ownership | Owned promotion / release gate |

**Field signal:** many Gold-level tables owned by a shared admin account with blank descriptions = ownership
was never established. Opening question: *"Who do you call when one of these is wrong?"*

---

## 1.2 CONTRACTS — Producer ↔ Consumer Agreements

A data contract makes the producer/consumer relationship explicit and enforceable. Most customers rely on
informal, undocumented expectations. Probe all four dimensions: **schema, quality, SLA, lineage.**

| Q | Diagnoses | Correlates to (DCA-type capability) |
|---|-----------|--------------------------------------|
| Do producers and consumers have an explicit, versioned agreement about a table's shape, quality, and freshness — or is it "whatever the table happens to contain today"? | Contract existence | Versioned data contracts |
| **(Schema)** How do consumers find out a column was dropped or retyped — a changelog, or a broken dashboard on Monday? | Schema-change awareness | Automated schema-drift detection |
| **(Quality)** What rules define "good" data on your critical tables (no negatives, no future dates, no orphan keys)? Are they enforced or just documented? | Quality-rule enforcement | Automated data-quality checks (metrics/tests) |
| **(SLA)** What's the freshness promise on your most important table, and who gets paged when it's late? | SLA + escalation | Freshness/volume SLAs with alerting |
| **(Lineage)** Can you prove what feeds a given report, back to source — including hops into BI tools or external systems? | Lineage traceability | End-to-end (incl. cross-platform) lineage |
| When an expectation is breached, what happens — pipeline halts, someone's alerted, or bad data flows to prod? | Enforcement posture | Enforcement modes (block / alert / monitor) |
| Roughly what share of your business-critical tables have any explicit contract today? | Contract coverage | Contract coverage & scorecarding |
| If your contracts live in a wiki or API spec, what actually enforces them at runtime? | Document vs. enforced gap | Contracts as enforced metadata, not prose |

---

## 1.3 DATA — Flow, Modeling & Fidelity

| Q | Diagnoses | Correlates to (DCA-type capability) |
|---|-----------|--------------------------------------|
| Do you preserve raw source fidelity, or transform on ingest and discard the original? | Reprocessing capability; audit | Immutable raw layer (replay/audit) |
| How do you handle history — keep versions, or overwrite? Can you reconstruct a record as of a past date? | History & audit strategy | Change tracking (SCD) + time travel |
| The same real-world entity (customer, patient, part, asset) is in several systems under different IDs. Can you link them programmatically today? | Entity-resolution maturity | Entity resolution / master identity |
| How is schema handled on ingest — fixed and brittle, or does it evolve as sources change? | Ingestion flexibility | Schema-flexible ingestion |
| Where does transformation logic live, and is it version-controlled and reviewable? | Git-native vs. click-ops | Version-controlled transformations |
| How large are your biggest tables and what's the freshness need — batch, micro-batch, streaming? | Latency & scale sizing | Tiered freshness / incremental processing |

---

## 1.4 GOVERNANCE — Protection at Every Boundary

Governance is where a **human classification decision** becomes a **runtime-enforced policy**. Many customers
have classification *labels* without enforcement, or enforcement without proof of coverage.

| Q | Diagnoses | Correlates to (DCA-type capability) |
|---|-----------|--------------------------------------|
| Can you prove that *every* column with sensitive data is classified and protected — everywhere it exists, including copies? | Classification completeness | Classification + coverage assurance |
| Which compliance frameworks apply, and to which data domains? (GDPR, HIPAA, PCI-DSS, SOX, CCPA, FERPA, SOC2) | Regulatory surface per domain | Framework-aligned tagging/policies |
| How is column masking and row-level security applied — per role, per region, per purpose? | Masking / RLS maturity | Column masking + row-access policies |
| At your last audit, how did you demonstrate minimum-necessary access — manual log review or automatically? | Audit-trail automation | Automated access analysis / audit |
| Do you have a governance dashboard? Does it measure real protection, or just how many things are tagged? | Performative vs. real governance | Coverage/quality scoring, not tag counts |
| Are there data residency / sovereignty rules dictating where data physically sits? | Residency constraints | Residency-aware placement |
| How do you govern data leaving the platform — shares, extracts, external access? | Egress governance | Governed sharing (secure views/shares) |

**Governance-ghost test:** a customer with many masking policies, thousands of tagged columns, a dedicated
team, and a "high-compliance" dashboard — whose analysts still keep private copies because governed tables are
unusable — has *performative* governance. Diagnose the gap between the dashboard and actual behavior.

---

## 1.5 CONSUMPTION — Access, Semantics & Trust

| Q | Diagnoses | Correlates to (DCA-type capability) |
|---|-----------|--------------------------------------|
| If I ask five people what your core metric means, do I get five answers? | Semantic health | Governed semantic layer / single definition |
| Do consumers query governed products, or build private copies "because the official one is wrong/slow/masked"? | Consumer trust (ultimate test) | Trusted products + bypass detection |
| How do business users get answers today — SQL, a BI tool, self-service, or a ticket to the data team? | Consumption friction | Self-service / natural-language analytics |
| How do you distribute governed data products internally and to partners? | Distribution model | Data marketplace / internal listings |
| When someone finds the "right" table, do they trust its freshness and correctness without asking a human? | Trust at point of consumption | Contract health surfaced to consumers |
| Are your BI dashboards traceable back to governed sources? | Cross-platform lineage | BI-to-source lineage |

---

## 1.6 AI — Does the Model Run on Governed Data?

AI sits at the end of the spine; its trustworthiness is entirely a function of the layers before it. Many
customers are piloting AI on ungoverned extracts — the single highest-leverage gap to surface.

| Q | Diagnoses | Correlates to (DCA-type capability) |
|---|-----------|--------------------------------------|
| Is your AI / LLM consuming governed, defined data, or raw tables and ad-hoc extracts? | AI data foundation | AI on governed semantic layer |
| Who is accountable when the AI gives a wrong answer derived from bad data? | AI accountability chain | Traceability to owned, contracted source |
| Do your AI agents have a knowledge graph / shared model for context, or are they reasoning over a data swamp? | Context substrate | Knowledge graph / ontology for grounding |
| Are AI training/RAG datasets governed — classified, contracted, purpose-tagged — or copied out with no controls? | AI data-supply-chain governance | Purpose tagging + ownership on AI inputs |
| Do you control which columns/data are even eligible for AI use? | AI eligibility controls | AI-use policy / eligibility tagging |
| How do you prevent the model from surfacing sensitive data it shouldn't? | AI output governance | Policy enforcement under AI + output guards |

---

## 1.7 Ontology & Semantics (cross-cutting)

The flexibility engine, and usually the biggest missing piece. The question is whether the customer has any
shared model of their business entities and relationships — most don't; each system defines its own.

| Q | Diagnoses | Correlates to (DCA-type capability) |
|---|-----------|--------------------------------------|
| Do you have a shared definition of your core entities (Customer, Product, Employee, Asset) across systems, or does each system define its own? | Conceptual model existence | Shared ontology / canonical model |
| Are your business relationships (who-owns-what, what-connects-to-what) queryable, or locked inside app logic? | Relationship discoverability | Knowledge graph (nodes/edges) |
| When you need to answer a question spanning systems ("which customers in region X bought product Y and filed a case"), how hard is that today? | Cross-system traversal | Graph traversal across sources |
| Are industry-standard vocabularies in play (FHIR for health, FIBO for finance, GS1 for retail)? | Standards adoption | Standards-aligned semantic layer |
| Could you add a new source system's concepts without re-architecting everything? | Extensibility | Declarative source-to-ontology mapping |

---

## Target-State Architecture Pillars (1.8 – 1.12)

The sections above diagnose the *foundations*. The next five diagnose where the market is heading and where a
DCA-type solution differentiates: an **open, interoperable lakehouse** with **multimodal ingestion**, a
**single open catalog/governance plane**, **semantic data products**, and **agentic activation**. Each pillar
lists both discovery questions and **signals to listen for** — phrases or facts that tell you the pillar is
live in the deal — plus, where relevant, the competitive wedge.

---

## 1.8 Open & Interoperable Lakehouse Architecture

The customer wants openness (no lock-in, multi-engine access, open table formats) *and* the ergonomics of a
managed platform. The question is whether "open" means "governed and interoperable" or "a pile of files in a
bucket that four engines fight over."

| Q | Diagnoses | Correlates to (DCA-type capability) |
|---|-----------|--------------------------------------|
| Are you standardizing on an open table format (Apache Iceberg, Delta), and is that a strategic mandate or a pilot? | Open-format commitment | Iceberg-native tables + external catalog interop |
| Do multiple engines (Snowflake, Spark, Trino, Flink, a BI engine) need to read/write the *same* tables? Who writes vs. who only reads? | Multi-engine interop; write-conflict risk | Single open storage, many engines, one catalog |
| Is storage decoupled from compute, and do you control your own cloud storage (bring-your-own-bucket)? | Storage/compute separation; data sovereignty | Open storage with managed compute |
| What's your explicit position on vendor lock-in, and how do you plan to keep data portable? | Lock-in sensitivity (often exec-driven) | Open formats + open catalog = portability |
| Where does interoperability break today — a format conversion, a copy between engines, a nightly export? | Interop friction / hidden copies | Zero-copy interop across engines |

**Signals to listen for:** "Iceberg mandate," "we don't want to be locked in," "our data scientists live in
Spark/Databricks but analysts are in [BI/warehouse]," "we keep two copies," "bring-your-own-storage,"
open-format line items in the reference architecture.

---

## 1.9 Connectivity & Multimodal Ingestion (clinical / multimodal emphasis)

Modern estates ingest far more than rows and columns. In clinical (and other regulated/asset-heavy) settings,
"the data" is structured records **plus** documents, images, waveforms, streams, and free text. Probe both the
*connectivity pattern* (how it lands) and the *modality coverage* (what lands).

| Q | Diagnoses | Correlates to (DCA-type capability) |
|---|-----------|--------------------------------------|
| What ingestion patterns are in play — batch, micro-batch, streaming, CDC from operational systems? | Latency & pattern spread | Unified batch + streaming + CDC ingestion |
| Beyond structured data, what modalities do you handle — clinical documents/notes, imaging (DICOM), HL7v2/FHIR messages, waveforms/device telemetry, genomics, PDFs, audio? | Multimodal coverage & gaps | Structured + semi-structured + unstructured ingestion |
| How do you land and govern *unstructured* data (images, notes) alongside its structured metadata? | Unstructured governance | Unstructured file support + metadata linkage |
| How many bespoke connectors/integrations do you maintain, and who owns them when they break? | Connector sprawl & fragility | Managed connectors + declarative pipelines |
| For clinical interoperability specifically — are you parsing FHIR/HL7 into queryable models, or storing raw messages you can't analyze? | Standards-based ingestion maturity | FHIR/HL7-aware ingestion → semantic model |
| How real-time do downstream consumers actually need each source to be? | Freshness-tiering discipline | Tiered `TARGET_LAG` / incremental refresh |

**Signals to listen for:** "we can't analyze our imaging/notes," "everything is raw HL7 blobs," "we have 200
point-to-point integrations," "genomics/waveform data sits in a separate silo," "real-time" used loosely for
everything.

---

## 1.10 Unified Open Catalog & Governance  *(competitive: unified catalog + Horizon vs. Glue-alone)*

This is the pillar most likely to decide the deal. Openness fragments governance: the moment data lives in an
open format read by many engines, a **single catalog + governance plane** becomes the differentiator. The
common competitor is a stitched-together open stack (e.g., Glue Data Catalog + Lake Formation + per-engine
controls) that governs *some* tables in *some* engines but can't prove policy consistency across all of them.

| Q | Diagnoses | Correlates to (DCA-type capability) |
|---|-----------|--------------------------------------|
| Do you have one catalog across all engines and formats, or a different catalog per engine/tool? | Catalog fragmentation | Single open catalog (Iceberg REST catalog) |
| When you set a masking or access policy, does it hold no matter which engine reads the table — or only inside one engine? | Policy portability across engines | Governance that travels with the data |
| Can you prove, in one place, who can access what across your open + managed data? | Unified auditability | One governance plane over open + native |
| Who can *write* to your open tables, and how do you prevent an external engine from bypassing your controls? | Write-path governance gap | Catalog-enforced write credentials |
| If you adopt [open format] broadly, what governs it — the same controls as your managed data, or a separate, weaker stack? | Governance consistency risk | Consistent policy over open + managed |
| How much effort goes into keeping catalogs/permissions in sync across tools today? | Sync tax / drift | Interoperable catalog, no manual sync |

**Signals to listen for (compete-and-win triggers):** "Glue catalog," "Lake Formation," "we govern per
engine," "policies don't carry over to Spark/Trino," "we sync permissions with a script," "our open tables
aren't really governed," multiple catalogs in the reference architecture. **Competitive wedge:** a unified open
catalog + governance plane (e.g., Polaris/Open Catalog + Horizon) governs the *same* open tables consistently
across engines — vs. Glue-alone, which catalogs but does not deliver a single, portable, provable governance
plane.

---

## 1.11 Semantic Data Products & Context

Beyond a semantic *layer* (1.5) and an ontology (1.7): are analytics packaged as **products** — owned,
contracted, discoverable, versioned, and enriched with business context an AI or human can reason over? This
is where semantics, contracts, and ownership converge into something consumable.

| Q | Diagnoses | Correlates to (DCA-type capability) |
|---|-----------|--------------------------------------|
| Do you think of your outputs as "tables" or as "products" with an owner, a consumer, an SLA, and a definition? | Product thinking vs. table sprawl | Semantic data products (contract + owner + SLA) |
| When a consumer (or an AI agent) finds a dataset, is the business meaning and context attached, or do they have to ask a human? | Context portability | Semantic model + ontology context |
| How discoverable are trusted products — a catalog/marketplace, or tribal knowledge? | Discoverability | Internal marketplace / product catalog |
| Are metric definitions centralized and reusable, or re-implemented in every dashboard and model? | Metric reuse | Shared semantic/metric layer |
| Can an AI system consume a product *with* its definitions and relationships, not just raw columns? | AI-ready semantics | Semantic layer + knowledge graph as context |

**Signals to listen for:** "every dashboard redefines the metric," "no one knows which table is the real one,"
"our LLM doesn't understand our business terms," "we want a data-products / data-mesh operating model."

---

## 1.12 Agentic & Application Activation

The consumption endgame: governed semantics and context feeding **agents** and **operational applications** —
not just dashboards. Value is realized when insight is *activated* back into a workflow, app, or autonomous
agent, all still under governance.

| Q | Diagnoses | Correlates to (DCA-type capability) |
|---|-----------|--------------------------------------|
| Are you building (or piloting) AI agents that take actions, or only chat/Q&A over data? | Agentic maturity | Governed agents over semantic + graph context |
| Where does an AI answer or model output *go* — a human reads it, or it triggers an action in an app/workflow? | Activation vs. dead-end insight | Activation into apps / operational workflows |
| Do agents operate under the same governance and access controls as human users, or do they run with broad service-account access? | Agent governance gap | Agents bound by row/column policy + purpose |
| How do you build and serve data apps today — bespoke web apps, notebooks, or a native app platform? | App delivery friction | Native data apps close to the data |
| Do insights flow back into operational systems (reverse ETL / activation), and is that path governed? | Operational activation loop | Governed activation back to source systems |
| When an agent acts on stale or wrong data, how would you even know? | Agent trust / observability | Contracts + lineage under agentic use |

**Signals to listen for:** "we're building agents/copilots," "we want to embed analytics in the product,"
"insights don't reach the front line," "our agent has admin access to everything," "we push data back into
Salesforce/ServiceNow," notebooks/scripts as the only serving layer.

---

# Part 2 — Document-Driven Discovery

Prospects and partners send artifacts *before* the intro: **reference architectures, L1 project plans,
current-state diagrams, RFPs, data catalogs.** Mine them to walk in prepared. For each artifact, extract the
listed facts and convert them into the targeted questions below. Remember these docs usually describe *target*
state or an idealized partner template — the gap between the document and reality is the discovery goldmine.

## 2.1 Reading a Reference Architecture

**Extract:** platform(s), account/region topology, layers/zones, source systems, integration/ELT tooling,
**table formats (Iceberg/Delta), storage layer, query engines, catalog(s)**, BI/consumption tools, governance
tooling, AI/ML + **agent/app** components, data-flow arrows.

Then ask:

- "Your architecture shows [N accounts / these zones]. What drove that split — region, BU, compliance, or history?"
- "I see [source systems A, B, C]. Which team owns each, and which are systems of record vs. copies?"
- "The diagram shows data flowing from [X] to [Y]. What runs that movement, and what validates it in between?"
- "I don't see contracts / a semantic layer / lineage on this diagram. Is that missing from the picture, or from the platform?"
- "You've got [open format] read by [engines A, B]. What single catalog and policy governs all of them?"
- "I see [Glue / Lake Formation / multiple catalogs] — do access and masking policies hold across every engine, or per engine?"
- "Which modalities land here — just structured, or documents/imaging/HL7/streams too — and how is the unstructured side governed?"
- "Where do outputs go — dashboards only, or agents and operational apps? Are those paths governed?"
- "Where on this diagram does a business definition of [core metric] get set? Where does AI consume from?"
- "Which boxes are aspirational (target state) vs. actually running today?"

## 2.2 Reading an L1 Project Plan (from a partner / SI)

**Extract:** workstreams, phases/milestones, in-scope sources, migration source (legacy platform), named
roles/RACI, go-live dates, success criteria, dependencies.

Then ask:

- "The plan has [workstreams]. Which one owns *data definitions and ownership* — or is that assumed to already exist?"
- "I see a migration from [legacy platform]. Are you lifting-and-shifting the model, or re-modeling on the way?"
- "The RACI names [roles]. Who is Accountable (not just Responsible) for data quality after go-live?"
- "Milestone [M] is 'data available in prod.' What's the gate — how do you decide it's trustworthy enough to promote?"
- "Success criteria mention [X]. How will you *prove* it — what metric, measured how?"
- "The plan assumes [dependency]. What happens to the timeline if the definitions/contracts aren't ready?"
- "Where in this plan does governance/security get implemented — day one, or 'phase 2'?" *(Phase-2 governance is a red flag.)*

## 2.3 Mapping Any Document to the DCA Spine

For any artifact, tag what you find onto the spine and note the **gaps** — silence is a signal. The right-hand
column is the DCA-type capability that gap correlates to.

| Spine layer | Look for in the doc | If absent, ask | Correlates to |
|-------------|--------------------|-----------------|---------------|
| People | RACI, ownership, org chart, "data owner" roles | "Who owns each data product? Is that written down?" | Ownership model |
| Contracts | SLAs, quality rules, schema governance, change mgmt | "How are producer/consumer expectations agreed and enforced?" | Data contracts |
| Data | Source list, layers, ELT tooling, CDC/history | "How does data flow and how is history preserved?" | Medallion + change tracking |
| Governance | Security, compliance, masking, classification, residency | "How is sensitive data protected at each boundary?" | Policy enforcement + audit |
| Consumption | BI tools, semantic layer, self-service, marketplace | "How do people find and trust the data they consume?" | Semantic layer + products |
| AI | ML platform, LLM, feature store, GenAI use cases | "What does AI run on, and is that data governed?" | Governed AI inputs |
| Ontology | Canonical model, MDM, entity resolution, standards | "Do you have a shared model of your core entities?" | Ontology / knowledge graph |
| Lakehouse | Iceberg/Delta, S3/ADLS storage, Spark/Trino engines | "Is this open format governed the same as everything else?" | Open interoperable lakehouse |
| Open catalog | Glue, Lake Formation, Unity, Polaris, multiple catalogs | "Does one catalog + policy span all engines and formats?" | Unified open catalog + governance |
| Ingestion | Connectors, HL7/FHIR, DICOM, streaming, unstructured stores | "How do multimodal and unstructured sources land and get governed?" | Multimodal ingestion |
| Activation | Agents, copilots, embedded apps, reverse ETL | "Where do insights and agent actions go, and are they governed?" | Agentic & app activation |

---

# Part 3 — Industry Tailoring

The base set works everywhere; tailoring makes it land. Pull the vocabulary, entities, and pain points from
the matching vertical and swap them into the base questions ("revenue" → "claims denial rate" for a payer;
"customer" → "patient" for a provider). Each vertical maps to a runnable demo you can show *if* the correlation
is strong.

## 3.1 Healthcare & Life Sciences (HCLS)

**Demo:** `industry-demos/hcls/` · **Entities:** Patient, Encounter, Condition, Medication, Procedure,
Practitioner, Claim, Worker, Department, Plan · **Standards:** FHIR R4, HL7 · **Regs:** HIPAA, HITRUST,
21st Century Cures Act · **Stakeholders:** CMIO, CNO, CPO, VP Data & Analytics, VP Revenue Cycle.

| Q | Diagnoses | Correlates to |
|---|-----------|---------------|
| Can you prove every column containing PHI is classified and masked, everywhere it exists? | PHI governance completeness | Classification + coverage assurance |
| If the same patient is in your EHR and claims system, can you link them programmatically? | Patient entity resolution | Entity resolution |
| At your last HIPAA audit, how did you demonstrate minimum-necessary access? | Access governance | Automated access audit |
| Are your ML training datasets derived from PHI under an IRB-approved protocol? | Research compliance | Purpose-tagged AI inputs |
| Can you trace a patient's full care pathway across systems, admission to follow-up? | Clinical data integration | Knowledge graph traversal |
| Can you correlate staffing levels with patient outcomes? | Cross-domain analytics | Cross-domain graph + semantics |

## 3.2 Financial Services / Fintech / Payments

**Demo:** `industry-demos/fintech/` · **Entities:** Customer, Beneficiary, Transaction, Agent, Corridor,
Watchlist Entity, Device, SAR · **Standards:** FIBO · **Regs:** BSA/AML, OFAC/sanctions, KYC, PCI-DSS ·
**Stakeholders:** CCO, VP Financial Intelligence Unit, Head of Fraud Ops, Director Agent Compliance.

| Q | Diagnoses | Correlates to |
|---|-----------|---------------|
| What's your AML false-positive rate, and what does it cost in analyst hours? | Detection precision | Graph-based detection |
| Can you detect a structuring ring or shared-device cluster, or only single-transaction rules? | Pattern detection | Knowledge graph relationships |
| How fast is sanctions/watchlist screening, and can you prove a transaction was screened? | Screening + auditability | Automated audit trail |
| How do you find customers with stale KYC before a regulator does? | KYC lifecycle | Data-quality/SLA monitoring |
| Can you trace funds across corridors and agents to file a defensible SAR? | Financial-crime traversal | Graph traversal + lineage |
| When you acquire an agent network, how do you resolve overlapping identities? | Entity resolution | Entity resolution |

## 3.3 Data Center / Infrastructure / Asset-Heavy Operations (DCIM)

**Demo:** `industry-demos/dcim/` · **Entities:** Data Center, Hall, Rack, Switch, Port, Technician,
Certification, Team, Incident, Change Request, Alert · **Sources:** ServiceNow CMDB, Workday, network
telemetry, BMS · **Stakeholders:** VP Infrastructure, NOC Director, Facilities Manager, EA.

| Q | Diagnoses | Correlates to |
|---|-----------|---------------|
| Can you correlate equipment risk with technician certification gaps? | Cross-domain analytics | Cross-domain graph |
| When an incident hits a switch, can you find the nearest certified, available technician? | Graph pathfinding | Knowledge graph traversal |
| After an acquisition, how do you reconcile thousands of new sites against your existing estate? | Entity resolution at scale | Entity resolution |
| Can you reconstruct a rack's exact state as of an audit date months ago? | Audit / history | Change tracking + time travel |
| How do you tier freshness — real-time telemetry vs. daily asset snapshots? | Freshness strategy | Tiered incremental processing |

## 3.4 Adding a New Vertical (Retail, Manufacturing, Insurance, Public Sector, …)

The framework flexes to *any* industry. To tailor for a new vertical:

1. **Identify the systems of record** (e.g., retail: POS, e-commerce, ERP, loyalty).
2. **Pick the industry standard vocabulary** (GS1 for retail, FIBO for finance, FHIR for health, ISA-95 for
   manufacturing, ACORD for insurance) to layer over a general vocabulary like Schema.org.
3. **Map source tables → entities and relationships** using a declarative source-to-ontology mapping.
4. **Derive the vertical question bank** by substituting the vertical's core entity for "customer/revenue" in
   the Part 1 base questions, then adding its specific regulatory + operational pains.

Seed question for any vertical: *"What are the 3–5 nouns your business runs on, and which 3–5 systems own
them?"* — that answer seeds both the ontology and the tailored questions.

---

# Part 4 — Maturity Rubric & Red Flags

Score each spine layer as you hear answers. Expect most customers to sit in Red/Yellow — that is normal and is
where the opportunity lives. Green is the state a DCA-type solution moves them toward.

| Layer | 🔴 Red (do this first) | 🟡 Yellow (gaps) | 🟢 Green (DCA-type target state) |
|-------|------------------------|------------------|----------------------------------|
| People | Shared admin owns everything; no named owners | Roles exist, accountability fuzzy | Named owners, clear operating model, real authority |
| Contracts | "Whatever's in the table"; expectations in a wiki | Some SLAs, no enforcement | Versioned contracts with automated enforcement |
| Data | Overwrite, no history, no entity resolution | Some history, manual matching | Immutable raw, change tracking, entity resolution |
| Governance | Labels = theater; manual audits | Masking on some data, dashboard exists | Classified everywhere, coverage-scored, automated audit |
| Consumption | Private copies everywhere; many definitions | Semantic layer exists, low trust | Governed products consumers actually use |
| AI | Model on raw extracts; nobody accountable | Governed inputs, no context graph | Governed semantics + knowledge graph + purpose controls |

**High-signal red flags:**

- **The Orphaned Table** — many important tables, admin-owned, blank descriptions. *Ownership never existed.*
- **The Semantic War** — three different numbers for the same metric before a board meeting. *No shared meaning.*
- **The Governance Ghost** — high compliance dashboard, but consumers keep private copies. *Performative governance.*
- **The Trust Cliff** — mature-looking platform, but low adoption; consumers bypass the governed path. *Consumer trust collapsed.*
- **Phase-2 Governance** — the L1 plan defers security/governance to a later phase. *It rarely happens.*
- **The Diagram Fiction** — the reference architecture shows contracts/lineage/semantic layer that don't actually run.

---

# Part 5 — From Answers to a DCA-Type Solution

Correlate the gap you heard to the capability category to demonstrate. Show a specific demo only when the
correlation is strong and the customer has felt the pain.

| What you heard (current state) | Correlates to (capability) | Where DCA illustrates it |
|--------------------------------|----------------------------|--------------------------|
| "We have five definitions of revenue" | Governed semantic layer | Semantic views + natural-language analytics |
| "We find out about schema changes when dashboards break" | Schema-drift detection + contracts | Contract fingerprint → drift → gate |
| "Bad data reaches production" | Quality enforcement at pipeline boundary | Quality rules + enforced pipeline gate |
| "We can't prove sensitive data is protected everywhere" | Classification coverage + propagation | Tagging + graph PII-propagation inference |
| "The same entity is in five systems" | Entity resolution | Knowledge-graph entity resolution |
| "Our AI can't be trusted / hallucinates" | Governed AI inputs + grounding | Graph RAG on governed semantic layer |
| "We just acquired a company" | Onboarding + entity resolution at scale | Acquisition/entity-resolution pattern |
| "Iceberg mandate / we can't be locked in" | Open, interoperable lakehouse | Iceberg-native tables + external engine interop |
| "We can't analyze our imaging / notes / HL7" | Multimodal ingestion | Structured + unstructured ingestion → semantics |
| "Glue/Lake Formation; policies don't carry across engines" | Unified open catalog + governance | Single open catalog + governance plane (Polaris/Open Catalog + Horizon) |
| "Every dashboard redefines the metric" | Semantic data products | Owned, contracted semantic products |
| "We're building agents / embedding analytics" | Agentic & app activation | Governed agents + native app activation |
| Vertical-specific pain | Matching vertical capability | Industry demo (HCLS / Fintech / DCIM) |

**Illustrative 5-minute enforcement sequence:** show coverage → a healthy contract → break quality → break
schema → re-validate (blocked) → the pipeline gate stops promotion → cross-platform lineage into the BI tool.

---

## Appendix — One-Page Discovery Checklist

```
ARCHITECTURE   □ accounts/regions & why  □ data layers & owners       □ ELT tooling  □ dev/test/prod
PEOPLE         □ named accountability     □ admin-owns-everything?     □ gov authority □ operating model
CONTRACTS      □ contracts exist?         □ schema-change awareness    □ quality rules □ SLA + alerting
               □ lineage provable         □ enforcement posture        □ coverage %
DATA           □ raw fidelity/history     □ entity resolution          □ schema evolution □ latency/scale
GOVERNANCE     □ classification coverage  □ compliance frameworks      □ masking/RLS   □ audit automation
               □ residency                □ real vs performative
CONSUMPTION    □ semantic consistency     □ private copies?            □ consumption UX □ BI lineage
AI             □ governed inputs?         □ accountability             □ context graph  □ purpose controls
ONTOLOGY       □ shared entity model      □ relationships queryable    □ standards      □ extensibility
LAKEHOUSE      □ open format mandate      □ multi-engine access        □ storage/compute split □ lock-in stance
INGESTION      □ batch/stream/CDC mix     □ multimodal coverage        □ unstructured gov □ connector sprawl
OPEN CATALOG   □ one catalog or many?     □ policy portable across engines □ write-path gov □ competitor (Glue?)
DATA PRODUCTS  □ product vs table         □ context attached           □ discoverable    □ metric reuse
AGENTIC        □ agents vs Q&A            □ activation path             □ agent governance □ app delivery
TAILORING      □ vertical                 □ core nouns (3-5)           □ systems (3-5)  □ regs
```

---

*Grounding docs: `README.md` (DCA spine), `ontology/philosophy/05-se-enablement-lab.md` (anchor questions),*
*`contracts/README.md` (contracts as capability), `industry-demos/{hcls,fintech,dcim}/DISCOVERY.md` (verticals),*
*`docs/ONTOLOGY.md` & `ontology/README.md` (flexibility mechanism).*
