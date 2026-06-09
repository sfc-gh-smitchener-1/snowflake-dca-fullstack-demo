# Snowflake Data Cloud — Data Mesh Architecture (ASCII reference)

> **Purpose.** This file is the **plaintext wireframe** for the Data Cloud / data-mesh
> reference diagram. It is meant to be opened in a fixed-width editor (or pasted into
> Lucidchart, Excalidraw, FigJam, etc.) so you can rebuild the picture quickly without
> re-drafting every box from scratch.
>
> **How to use in Lucid.**
> 1. Drop a 5-column frame (the five swimlanes below).
> 2. Add the cross-cutting bands as four horizontal rectangles underneath.
> 3. Use the "Box contents" section to fill in each rectangle title + bullets.
> 4. Use the "Arrows / flows" section to connect lanes.
> 5. Use the "Snowflake objects" appendix to label each box with the actual primitives.
>
> Schema names in code stay `BRONZE` / `SILVER` / `GOLD`. In narrative we use
> **Raw / Curated / Semantic**.
>
> **Terminology rule.** Snowflake is a **data platform** (or *data cloud*, *data graph*),
> never a *warehouse*. The word *warehouse* is reserved for physical/manufacturing/
> distribution contexts (e.g. `cpg:WholesaleWarehouse`, "warehouse-club SKU"). When
> referring to the Snowflake compute primitive in narrative, use **virtual compute**,
> **compute service**, or **compute cluster**. The SQL keyword `WAREHOUSE` and Account
> Usage columns like `qh.warehouse_name` stay as-is in code only.

---

## 1. Top-level wireframe (5 swimlanes)

```
─────────────────────────────────────────────────────────────────────────────────────────────────────────────
                          S N O W F L A K E    D A T A    C L O U D    —    D A T A    M E S H
─────────────────────────────────────────────────────────────────────────────────────────────────────────────

┌──────────────┐    ┌────────────────────┐   ┌──────────────────────┐   ┌────────────────────┐   ┌──────────────────────┐
│   SOURCES    │    │   RAW   (BRONZE)   │   │  CURATED  (SILVER)   │   │  SEMANTIC  (GOLD)  │   │     ACTIVATION       │
│   per BU     │    │   land · preserve  │   │   integrate · model  │   │   contract · serve │   │   consume · share    │
└──────────────┘    └────────────────────┘   └──────────────────────┘   └────────────────────┘   └──────────────────────┘

┌──────────────┐    ┌────────────────────┐   ┌──────────────────────┐   ┌────────────────────┐   ┌──────────────────────┐
│  Domain 1    │──▶│  Ingest patterns   │──▶│  Identity & MDM      │──▶│  Business iface    │──▶│  Internal Democ.     │
└──────────────┘    └────────────────────┘   └──────────────────────┘   └────────────────────┘   └──────────────────────┘
┌──────────────┐    ┌────────────────────┐   ┌──────────────────────┐   ┌────────────────────┐   ┌──────────────────────┐
│  Domain 2    │──▶│  Object types      │──▶│  Models              │──▶│  Cortex Analyst    │──▶│  Cross-Business      │
└──────────────┘    └────────────────────┘   └──────────────────────┘   └────────────────────┘   │  Aggregation         │
┌──────────────┐    ┌────────────────────┐   ┌──────────────────────┐   ┌────────────────────┐   └──────────────────────┘
│  Domain 3    │──▶│  Conventions       │   │  Vocabulary &        │──▶│  Cortex Search     │   ┌──────────────────────┐
└──────────────┘    └────────────────────┘   │  Taxonomy            │   └────────────────────┘   │  External Democ.     │
                                             └──────────────────────┘   ┌────────────────────┐   └──────────────────────┘
                                             ┌──────────────────────┐   │  Graph RAG         │
                                             │  Quality             │──▶└────────────────────┘
                                             └──────────────────────┘   ┌────────────────────┐
                                             ┌──────────────────────┐   │  Data products     │
                                             │  Performance         │──▶└────────────────────┘
                                             └──────────────────────┘

╔═══════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║  CORTEX     ·  runtime AI services           (cross-layer)                                                 ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║  ONTOLOGY   ·  the contract layer            (RDF · OWL · SHACL · Turtle · JSON-LD)                        ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║  TAXONOMY   ·  parallel hierarchical classifications                                                       ║
╠═══════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║  HORIZON    ·  governance & observability plane                       (cross-cuts every layer)             ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════════════════╝

KEY PATTERN  ·  True data-mesh autonomy — each BU owns its entire Snowflake account, not just storage.
                Horizon governance unified across the org · per-account billing · one platform, not many engines.
```

---

## 2. Detailed box contents (per swimlane)

### 2.1 SOURCES — column 1

Three stacked source-domain cards. Each represents one business unit's system-of-record stack.

```
┌────────────────────────────────────┐   ┌────────────────────────────────────┐   ┌────────────────────────────────────┐
│  Domain 1   (e.g. Operations)      │   │  Domain 2   (e.g. Commercial)      │   │  Domain 3   (e.g. Enterprise)      │
│  ──────────────────────────────    │   │  ──────────────────────────────    │   │  ──────────────────────────────    │
│  • Oracle (DB / EBS / Fusion)      │   │  • SAP / ERP   (S/4HANA · ECC)     │   │  • CRM           (Salesforce · MS) │
│  • MES                             │   │  • MES                             │   │  • Project Mgt   (Jira · Asana)    │
│  • PLM      (Windchill · Teamcen.) │   │  • PLM                             │   │  • ServiceNow    (ITSM · HRSD)     │
│  • IoT / Sensors                   │   │  • IoT / Sensors                   │   │  • HR Systems    (Workday · UKG)   │
│  • Lab / quality systems           │   │  • POS / e-comm / loyalty          │   │  • Financial close · planning      │
│  • Files (CSV · XLSX · PDF)        │   │  • 3PL · logistics feeds           │   │  • SaaS APIs (Slack · Workday · …) │
└────────────────────────────────────┘   └────────────────────────────────────┘   └────────────────────────────────────┘
```

Arrow label leaving each Domain → Raw layer: **`Openflow / Snowpipe / ELT`**.

---

### 2.2 RAW (BRONZE) — column 2

Five cards. The Raw layer's job is to **land everything, lose nothing, and prove provenance**.

```
┌─────────────────────────────────────────────┐
│  Ingest patterns                            │
│  ─────────────────                          │
│  • Openflow              (managed CDC/ELT)  │
│  • Snowpipe              (auto-ingest)      │
│  • Snowpipe Streaming    (sub-sec rows)     │
│  • Kafka Connector / Apache Iceberg ingest  │
│  • External Tables on cloud storage         │
│  • COPY INTO  (one-shot · backfill)         │
│  • Database / account Replication · CDC     │
│  • Native Apps as data producers            │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Object types                               │
│  ────────────                               │
│  • External Stages (S3 / Azure / GCS)       │
│  • Internal Stages (named · table · user)   │
│  • Raw landing tables (1:1 with source)     │
│  • VARIANT columns for JSON / Avro / XML    │
│  • File Format objects                      │
│  • Streams over landing tables              │
│  • Tasks orchestrating Stream → next layer  │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Conventions                                │
│  ───────────                                │
│  • append-only · no destructive updates     │
│  • schema-on-read (VARIANT first)           │
│  • idempotent retries · ingest_id key       │
│  • backpressure-aware pipelines             │
│  • source_system · ingest_ts · file_name    │
│  • per-source retention + Time Travel       │
│  • zero-copy clones for replay              │
└─────────────────────────────────────────────┘
```

Arrow label leaving Raw → Curated: **`Stream + Task · Dynamic Table`**.

---

### 2.3 CURATED (SILVER) — column 3

Five cards. Curated is where **identity, vocabulary, models, quality, and physics** live.

```
┌─────────────────────────────────────────────┐
│  Identity & MDM                             │
│  ──────────────                             │
│  • canonical UID + dereferenceable IRI      │
│  • alt-key bridges (GTIN · SKU · ASIN …)    │
│  • bi-temporal (valid_from / valid_to,      │
│                 record_from / record_to)    │
│  • survivorship + golden-record rules       │
│  • match/merge audit trail                  │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Models                                     │
│  ──────                                     │
│  • Triple store    (statement · individual) │
│  • Property graph  (node + edge Dyn Tables) │
│  • Dimensional · SCD2 facts/dims            │
│  • Hybrid Tables   (Unistore · OLTP lookup) │
│  • Vector embeddings (per individual)       │
│  • Class profiles  (descendant rollup)      │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Vocabulary & Taxonomy                      │
│  ─────────────────────                      │
│  • Controlled vocabularies                  │
│  • UCUM units of measure                    │
│  • Code lists · enums · ISO sets            │
│  • Parallel taxonomies (GS1 · retailer …)   │
│  • Synonym table for composite terms        │
│  • Multi-locale labels                      │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Quality                                    │
│  ───────                                    │
│  • SHACL shapes → Data Metric Functions     │
│  • dbt / SQLMesh tests                      │
│  • Data contracts at producer boundary      │
│  • Horizon DQ scores · drift alerts         │
│  • Snapshot diff vs. last-known-good        │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Performance                                │
│  ───────────                                │
│  • Search Optimization Service              │
│  • Clustering keys                          │
│  • Dynamic Table cascades                   │
│  • Query Acceleration Service               │
│  • Materialized Views (selective)           │
│  • Result cache · metadata cache            │
└─────────────────────────────────────────────┘
```

Arrow label leaving Curated → Semantic: **`Views + Semantic Model + Cortex`**.

---

### 2.4 SEMANTIC (GOLD) — column 4

Five cards. Semantic is the **business contract** — everything beyond this point is consumption.

```
┌─────────────────────────────────────────────┐
│  Business interface                         │
│  ──────────────────                         │
│  • Semantic Views   (native Snowflake)      │
│  • Friendly v_* views per domain            │
│  • Materialized aggregates / KPIs           │
│  • Stable column names + descriptions       │
│  • Documented synonyms + sample questions   │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Cortex Analyst                             │
│  ──────────────                             │
│  • semantic_model.yaml                      │
│  • NL → governed SQL                        │
│  • Verified queries + dimensions/metrics    │
│  • Inherits RAP + masks (no leakage)        │
│  • Returns SQL + answer + confidence        │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Cortex Search                              │
│  ─────────────                              │
│  • Hybrid lexical + vector                  │
│  • Snowflake-Arctic-embed-m-v1.5 (768d)     │
│  • Node + class-profile embeddings          │
│  • Filterable on tag / BU / sensitivity     │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Graph RAG                                  │
│  ─────────                                  │
│  • class_profile rollup (blog pattern)      │
│  • synonym overrides                        │
│  • Cortex Guard on prompts                  │
│  • Recursive CTE subgraph traversal         │
│  • p_graph_rag  (2-tool flattened agent)    │
│  • inline citations + JSON envelope         │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Data products                              │
│  ─────────────                              │
│  • Enterprise KPIs                          │
│  • AI / ML features                         │
│  • Executive dashboards                     │
│  • Blast-radius walkers (recall · supply)   │
│  • Notebook-driven analyses                 │
└─────────────────────────────────────────────┘
```

Arrow label leaving Semantic → Activation: **`Marketplace · Share · App`**.

---

### 2.5 ACTIVATION — column 5

Three cards. The Activation column is **how value escapes Snowflake** — internally, across BUs, and externally.

```
┌─────────────────────────────────────────────┐
│  Internal Democratization                   │
│  ────────────────────────                   │
│  • Internal Marketplace listings            │
│  • Streamlit-in-Snowflake apps              │
│  • Snowflake Notebooks                      │
│  • Cortex Agents (Slack / Teams / web)      │
│  • Tableau · Power BI · Sigma · Hex         │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Cross-Business Aggregation                 │
│  ──────────────────────────                 │
│  • Unified program views (cross-BU)         │
│  • Enterprise supply chain                  │
│  • Combined financial metrics               │
│  • Workforce analytics                      │
│  • Cross-program benchmarks                 │
│  • Enterprise risk + compliance             │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  External Democratization                   │
│  ────────────────────────                   │
│  • Secure Data Shares                       │
│  • Snowflake Marketplace listings           │
│  • Data Clean Rooms                         │
│  • Partner / supplier data exchange         │
│  • Native Apps (monetized)                  │
└─────────────────────────────────────────────┘
```

---

## 3. Cross-cutting bands (below the swimlanes, full width)

### 3.1 CORTEX — runtime AI services

```
╔═════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║  CORTEX                                                                                                 ║
║  ────────────                                                                                           ║
║  • Analyst       — NL → governed SQL over semantic_model.yaml                                           ║
║  • Search        — hybrid lexical + vector retrieval                                                    ║
║  • Complete      — LLM serving (Arctic · Mistral-Large2 · Llama 3.1 · Claude 3.5 …)                     ║
║  • Embed Text    — Snowflake-Arctic-embed-m-v1.5 (768d)                                                 ║
║  • Guard         — prompt-injection / jailbreak / PII safety                                            ║
║  • Classify Text — zero-shot text classification                                                        ║
║  • Sentiment     — sentiment scoring                                                                    ║
║  • Fine-Tune     — adapter training inside the perimeter                                                ║
║  • Agents        — multi-tool reasoning + tool-call orchestration                                       ║
║  • Code          — agent optimization / evaluation IDE workflow                                         ║
╚═════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

### 3.2 ONTOLOGY — the contract layer

```
╔═════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║  ONTOLOGY                                                                                               ║
║  ──────────                                                                                             ║
║  Formats:    RDF · OWL · SHACL · Turtle (.ttl) · JSON-LD                                                ║
║  TBox:       class · property · shape · constraint · value_domain                                       ║
║  ABox:       individual · statement   (with source + confidence)                                        ║
║  Industry:   GS1  ·  FIBO  ·  FHIR  ·  SNOMED  ·  CIM  ·  CDISC  ·  …                                   ║
║  Loader:     SQL seed (TBox) → Stream + Task (ABox) → Dynamic Table projections                         ║
║  Identity:   canonical UID + IRI;  alt-keys mapped via bridges                                          ║
╚═════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

### 3.3 TAXONOMY — parallel hierarchical classifications

```
╔═════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║  TAXONOMY                                                                                               ║
║  ──────────                                                                                             ║
║  GS1 GPC          Segment → Family → Class → Brick                                                      ║
║  Retailer trees   Walmart · Kroger · Amazon · Target  (each with its own root + leaves)                 ║
║  Regulatory       FDA UNII · USDA · EFSA · NAICS · HS · GHS                                             ║
║  Internal         master hierarchy · marketing categories · finance segmentation                        ║
║  Implementation   recursive CTE traversal · synonym table for composite terms                           ║
║  Pattern          one individual can sit in many trees simultaneously                                   ║
╚═════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

### 3.4 HORIZON — governance & observability plane

```
╔═════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║  HORIZON                                                                                                ║
║  ─────────                                                                                              ║
║  Discovery       BigID  ·  Sensitive Data Classification  ·  PII / PHI / PCI                            ║
║  Compliance      FedRAMP · IL5 · CJIS · IRAP · HIPAA · SOC 2 · ISO 27001                                ║
║  Access          Row Access Policies · Dynamic Data Masking · Cortex Guard                              ║
║                  RBAC · Policy-Based Security · Aggregation / Projection Policies                       ║
║  Tagging / DQ    Object Tagging · Data Metric Functions · Data Quality Monitoring                       ║
║  Telemetry       Data Lineage · ACCESS_HISTORY · QUERY_HISTORY · Account Usage                          ║
║  Cost            Resource Monitors · per-compute cost attribution · Budgets                             ║
║  Catalog         Horizon Catalog · Open Catalog · Snowflake Open Catalog (Apache Polaris)               ║
╚═════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

---

## 4. Arrows / flows (label each connector in Lucid)

| From                              | To                                  | Label                                          |
| --------------------------------- | ----------------------------------- | ---------------------------------------------- |
| Domain 1 / 2 / 3                  | Raw · Ingest patterns               | `Openflow / Snowpipe / ELT`                    |
| Raw · Ingest patterns             | Raw · Object types                  | `produces`                                     |
| Raw · Object types                | Curated · Identity & MDM            | `Stream + Task`                                |
| Raw · Object types                | Curated · Models                    | `Dynamic Table`                                |
| Curated · Models                  | Curated · Vocabulary & Taxonomy     | `references`                                   |
| Curated · Vocabulary & Taxonomy   | Semantic · Cortex Analyst           | `verifies dimensions`                          |
| Curated · Quality                 | Semantic · Business interface       | `gates publish`                                |
| Curated · Performance             | Semantic · Cortex Search            | `accelerates`                                  |
| Semantic · Business interface     | Semantic · Cortex Analyst           | `semantic_model.yaml`                          |
| Semantic · Cortex Search          | Semantic · Graph RAG                | `vector hits`                                  |
| Semantic · Graph RAG              | Semantic · Data products            | `answers + citations`                          |
| Semantic · Data products          | Activation · Internal Democ.        | `apps · dashboards · agents`                   |
| Semantic · Data products          | Activation · Cross-Business Aggreg. | `combined views`                               |
| Semantic · Data products          | Activation · External Democ.        | `Shares · Marketplace · Clean Rooms`           |
| Horizon                           | every box                           | `governs · tags · audits` (dashed connectors)  |
| Cortex                            | every box from Curated → Activation | `serves AI` (dashed connectors)                |
| Ontology                          | Curated · Models                    | `contract`                                     |
| Ontology                          | Semantic · Business interface       | `contract`                                     |
| Taxonomy                          | Curated · Vocabulary & Taxonomy     | `parallel classifications`                     |
| Taxonomy                          | Semantic · Graph RAG                | `class_profile + synonym`                      |

---

## 5. Snowflake objects appendix (label each box)

| Layer / Box                                  | Snowflake primitives to label                                                          |
| -------------------------------------------- | -------------------------------------------------------------------------------------- |
| Raw · Ingest patterns                        | `PIPE`, `STAGE`, `EXTERNAL TABLE`, `STREAM`, `TASK`, `COPY INTO`, Openflow connectors  |
| Raw · Object types                           | `STAGE`, `TABLE` (landing), `FILE FORMAT`, `STREAM`, `VARIANT`                          |
| Raw · Conventions                            | Time Travel, Fail-Safe, zero-copy `CLONE`, replication policies                        |
| Curated · Identity & MDM                     | `TABLE` (individual, alt_key_bridge), bi-temporal columns, Hybrid Tables               |
| Curated · Models                             | `DYNAMIC TABLE` (node, edge, statement), `HYBRID TABLE`, SCD2 dims                     |
| Curated · Vocabulary & Taxonomy              | `TABLE` (class, property, code_list, synonym), recursive `WITH RECURSIVE`              |
| Curated · Quality                            | `DATA METRIC FUNCTION`, `ALERT`, dbt tests, Horizon DQ                                 |
| Curated · Performance                        | `SEARCH OPTIMIZATION`, `CLUSTER BY`, `QUERY_ACCELERATION_SERVICE`, `MATERIALIZED VIEW` |
| Semantic · Business interface                | `SEMANTIC VIEW`, `VIEW` (v_*), `MATERIALIZED VIEW`                                     |
| Semantic · Cortex Analyst                    | `SEMANTIC_MODEL` (yaml), Cortex Analyst REST + SQL                                     |
| Semantic · Cortex Search                     | `CORTEX SEARCH SERVICE`, `SNOWFLAKE.CORTEX.EMBED_TEXT_768`                             |
| Semantic · Graph RAG                         | `PROCEDURE p_graph_rag`, `FUNCTION f_retrieve_subgraph`, Cortex Guard                  |
| Semantic · Data products                     | `VIEW`, `MATERIALIZED VIEW`, Snowflake Notebooks                                       |
| Activation · Internal Democratization        | `STREAMLIT`, `NOTEBOOK`, `CORTEX AGENT`, internal `LISTING`                            |
| Activation · Cross-Business Aggregation      | cross-database `VIEW`, replication-backed reader accounts                              |
| Activation · External Democratization        | `SHARE`, `LISTING` (Marketplace), `CLEAN ROOM`, `NATIVE APP`                           |
| Horizon                                      | `ROW ACCESS POLICY`, `MASKING POLICY`, `TAG`, `DATA METRIC FUNCTION`, `ACCESS_HISTORY` |
| Cortex                                       | `SNOWFLAKE.CORTEX.*` family + Cortex Agents / Search / Analyst / Guard                 |

---

## 6. Lucid build order (recommended)

1. **Frame** — drop a 5-column container, label the headers (`Sources` · `Raw (Bronze)` · `Curated (Silver)` · `Semantic (Gold)` · `Activation`).
2. **Cards** — paste the section-2 contents into each column as stacked rectangles. Keep card width consistent per column.
3. **Bands** — below the columns, add four full-width rectangles for `Cortex`, `Ontology`, `Taxonomy`, `Horizon`. Use a muted background fill so they read as a "plane", not another column.
4. **Arrows** — wire up the connectors from section 4. Use solid lines for the primary flow (Sources → Raw → Curated → Semantic → Activation) and dashed for the cross-cutting bands (Horizon · Cortex · Ontology · Taxonomy).
5. **Labels** — pull the primitives from section 5 and add a small caption under each card title.
6. **Key pattern callout** — bottom-right corner, single line: *"True data-mesh autonomy — each BU owns its entire Snowflake account, not just storage."*

---

## 7. Activation — the "three concentric rings" story (industry-agnostic)

**Why rewrite this column.** As drawn today, Activation reads as a flat list of distribution
mechanisms (Streamlit, Marketplace, Clean Rooms, …). That makes the audience guess at the
narrative. The fix is to organise Activation by **who consumes the data and at what trust
boundary**, which works the same in CPG, Healthcare, FSI, Public Sector, Manufacturing, etc.

**The story (one line):**
> *"Activation is where the data graph **stays in platform** and creates value, instead of being
> sent to multiple tools. We do that in three concentric rings — for the BU that owns the data,
> for the enterprise that needs to see across BUs, and for the ecosystem we exchange data with.
> Same governance, same ontology, same platform — only the audience and the trust boundary change."*

### 7.1 Layout (three boxes, in this order, top to bottom)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│   ACTIVATION    ·    same ontology    ·    same governance    ·    3 audiences │
└──────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Ring 1 · INSIDE THE BU            CONSUME  │
│  ─────────────────────────────────────────  │
│  audience · the team that owns the data     │
│  trust    · inside one Snowflake account    │
│                                             │
│  • Streamlit-in-Snowflake apps              │
│  • Snowflake Notebooks                      │
│  • Cortex Agents (Slack · Teams · web)      │
│  • BI — Tableau · Power BI · Sigma · Hex    │
│  • Embedded apps via Snowflake REST + SQL   │
│  • Reverse-ETL into operational SaaS        │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Ring 2 · ACROSS THE ENTERPRISE      ALIGN  │
│  ─────────────────────────────────────────  │
│  audience · cross-BU teams + the C-suite    │
│  trust    · same org, multiple accounts     │
│                                             │
│  • Internal Marketplace (org-private)       │
│  • Cross-BU semantic views                  │
│  • Enterprise KPIs · combined finance       │
│  • Workforce + supply-chain analytics       │
│  • Cross-program benchmarks                 │
│  • Replicated reader accounts               │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Ring 3 · BEYOND THE ENTERPRISE   EXCHANGE  │
│  ─────────────────────────────────────────  │
│  audience · partners · customers · regs     │
│  trust    · cross-org, contractual          │
│                                             │
│  • Secure Data Shares                       │
│  • Snowflake Marketplace listings           │
│  • Data Clean Rooms (privacy-preserving)    │
│  • Native Apps  (free + paid · monetised)   │
│  • Partner / supplier data exchange         │
│  • Regulatory submissions + attestations    │
└─────────────────────────────────────────────┘
```

### 7.2 Why each ring exists (the verbs)

| Ring | Verb       | What changes vs. previous ring                              |
| ---- | ---------- | ----------------------------------------------------------- |
| 1    | **Consume**  | data stays inside the BU's account                          |
| 2    | **Align**    | data crosses BU boundaries via internal sharing primitives  |
| 3    | **Exchange** | data crosses the org boundary via contractual primitives    |

Each ring **inherits the governance and ontology of the previous one** — that's the punchline.
Horizon policies, RAP, masks, tags, lineage, and the ontology contract follow the data outward.

### 7.3 Talking points (use these per audience)

- **CTO / Platform** — "One graph, three reach levels. The same Dynamic Tables and policies
  power the BU app, the enterprise dashboard, and the partner clean room. There is no second
  pipeline for sharing."
- **CISO** — "The trust boundary is explicit at each ring. Ring 1 is RBAC + RAP inside one
  account. Ring 2 is replication + reader accounts under the same Horizon catalog. Ring 3 is
  Shares, Listings, and Clean Rooms — every external read is auditable in `ACCESS_HISTORY`."
- **Business / Domain owner** — "You publish once. Your team uses it as an app or agent. The
  enterprise sees it as part of the cross-BU view. Partners receive it through a share or a
  clean room — never an export."
- **Data engineer** — "There is no `_export` schema. Activation is just the same Gold views
  surfaced through Streamlit, Listings, or Shares. Add a row, and every ring sees it on the
  next refresh."

### 7.4 Replace the current Activation column with this

Today the diagram has: *Internal Democratization · Cross-Business Aggregation · External
Democratization · Cross-BU Semantic Layer*. Collapse those four into the three rings above
(Consume · Align · Exchange). The "Cross-BU Semantic Layer" content moves up into Semantic
where it actually belongs (it's a `SEMANTIC VIEW`, not an activation surface).

### 7.5 How the graph physically lives on the platform

The data graph is two tables. That's the punchline behind "stays in platform". No separate
graph database, no extra cluster to operate, no second governance model.

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│  ACTIVATION · the data graph stays in platform                                        │
│  Same governance · Same ontology · Same compute — no separate graph database needed   │
└──────────────────────────────────────────────────────────────────────────────────────┘

   ┌─────────────────────────────────┐                ┌─────────────────────────────────┐
   │  KG_NODE                        │                │  KG_EDGE                        │
   │  ─────────                      │                │  ─────────                      │
   │  • node_id          PK          │◀──── FK ───────│  • source_node_id   FK          │
   │  • node_type                    │                │  • target_node_id   FK ────────▶
   │      Asset · Plant · Product ·  │                │  • edge_type                    │
   │      SKU · Retailer · Drug ·    │                │      located_at · made_by ·     │
   │      Disease · Patient · …      │                │      sold_at · contains ·       │
   │  • properties       VARIANT     │                │      treats · targets · …       │
   │      flexible per-type schema   │                │  • confidence       0–1         │
   │  • valid_from / valid_to        │                │  • timestamp                    │
   │  • record_from / record_to      │                │  • metadata         VARIANT     │
   └─────────────────────────────────┘                └─────────────────────────────────┘

   Examples — same model, three industries

   Manufacturing                          CPG                                Medical
   ─────────────                          ───                                ───────
   KG_NODE                                KG_NODE                            KG_NODE
     id    : asset:pump-7H-204              id    : sku:CHEESE-12OZ            id    : drug:metformin
     type  : RotatingAsset                  type  : Product                    type  : Drug
     props : { mfg:"Sulzer",                props : { brand:"Philly",          props : { moa:"AMPK
               criticality:"A" }                      net_oz:12 }                        activator" }

   KG_EDGE                                KG_EDGE                            KG_EDGE
     src   : asset:pump-7H-204              src   : sku:CHEESE-12OZ            src   : drug:metformin
     tgt   : plant:richmond-line3           tgt   : retailer:kroger            tgt   : disease:t2-diabetes
     type  : located_at                     type  : sold_at                    type  : treats
     conf  : 1.00                           conf  : 0.98                       conf  : 0.92

   ┌──────────────────────────────────────────────────────────────────────────────────┐
   │  Snowflake does the rest — no graph DB to operate                                 │
   │  ────────────────────────────────────────────────                                 │
   │  • Distributed storage      micro-partitioning · automatic clustering             │
   │  • Elastic compute          per-query scale-out · zero idle cost                  │
   │  • Query optimization       cost-based · Search Optimization Service · QAS        │
   │  • Security                 RBAC · Row Access Policies · Dynamic Data Masking     │
   │  • Governance               Object Tagging · Data Lineage · ACCESS_HISTORY        │
   └──────────────────────────────────────────────────────────────────────────────────┘
```

**Compact card** (drop into the Activation column as a sub-box):

```
┌──────────────────────────────────────────────────────┐
│  Knowledge graph — in platform, two tables           │
│  ───────────────────────────────────────             │
│  KG_NODE    id · type · properties (VARIANT)         │
│             Asset · Product · Drug · Patient · …     │
│                                                      │
│  KG_EDGE    source · target · edge_type              │
│             confidence · timestamp · metadata        │
│             located_at · sold_at · treats · …        │
│                                                      │
│  Inherits   storage · scale · optimizer ·            │
│             security · governance — no graph DB      │
└──────────────────────────────────────────────────────┘
```

**Industry legend** (use in box captions):

| Industry      | Node example                  | Edge example                                                              |
| ------------- | ----------------------------- | ------------------------------------------------------------------------- |
| Manufacturing | `asset:pump-7H-204` (Asset)   | `pump-7H-204 ──located_at──▶ plant:richmond-line3`                        |
| CPG           | `sku:CHEESE-12OZ` (Product)   | `CHEESE-12OZ ──sold_at──▶ retailer:kroger`  ·  `──made_by──▶ brand:philly` |
| Medical       | `drug:metformin` (Drug)       | `metformin ──treats──▶ disease:t2-diabetes`  ·  `──targets──▶ gene:PRKAA1` |

Same `KG_NODE` + `KG_EDGE` schema across all three. Only the `node_type`, `edge_type`, and the
`properties` payload differ — which is the whole point.

> In our demo these tables exist as `silver.individual` (KG_NODE) and `silver.statement`
> (KG_EDGE), with property-graph projections in `silver.node` and `silver.edge` Dynamic Tables.
> Same shape, same story.

---

## 8. Icon map — what to put on every box

Use a **layered icon strategy**:

1. **Snowflake official** for any Snowflake product (Cortex, Marketplace, Native Apps, Hybrid
   Tables, Snowpipe, Streams, Tasks, Horizon, Polaris). These come from the Snowflake brand
   kit and are also available inside Lucid's *Snowflake* shape library.
2. **Vendor logos** for source systems and BI tools — pull from
   [Simple Icons](https://simpleicons.org) (CC0, ~3000 brand SVGs).
3. **Concept icons** for everything abstract (identity, graph, taxonomy, governance, share,
   …) — pull from [Lucide](https://lucide.dev) (MIT, ~1500 icons), [Tabler](https://tabler.io/icons)
   (MIT, ~5000 icons), or [Phosphor](https://phosphoricons.com).

In Lucid: **Shape Library → +Shapes → search "Snowflake"** to enable the official Snowflake
shape pack. For everything else, use *Insert → Image* with the SVG URL from Simple Icons / Lucide.

### 8.1 Sources column

| Box              | Icon concept                  | Where to get it                       |
| ---------------- | ----------------------------- | ------------------------------------- |
| Oracle           | Oracle wordmark / "O" droplet | Simple Icons → `oracle`               |
| SAP              | SAP wordmark                  | Simple Icons → `sap`                  |
| MES              | factory floor                 | Lucide `Factory` · Tabler `building-factory` |
| PLM              | engineering blueprint         | Lucide `FileSliders` · Tabler `blueprints`   |
| IoT / Sensors    | radio tower or chip           | Lucide `RadioTower` · `Cpu`           |
| Salesforce CRM   | cloud "f" mark                | Simple Icons → `salesforce`           |
| ServiceNow       | green chevron                 | Simple Icons → `servicenow`           |
| Workday          | yellow "W"                    | Simple Icons → `workday`              |
| Jira / Asana     | brand mark                    | Simple Icons → `jira` / `asana`       |
| HR Systems       | people group                  | Lucide `Users` · `UserSquare2`        |
| Domain header    | building / business unit      | Lucide `Building2` · `Building`       |

### 8.2 Raw (Bronze) column

| Box                 | Icon concept                  | Where to get it                                            |
| ------------------- | ----------------------------- | ---------------------------------------------------------- |
| Openflow            | flow / managed-pipe           | Snowflake brand · Lucide `Workflow`                        |
| Snowpipe            | Snowflake pipe icon           | Snowflake official "Snowpipe" mark                         |
| Snowpipe Streaming  | pipe + lightning              | Snowflake "Snowpipe Streaming" + Lucide `Zap`              |
| External Tables     | cloud + table                 | Lucide `Cloud` + `Table`                                   |
| Iceberg ingest      | iceberg / Apache Iceberg mark | Simple Icons → `apacheiceberg`                             |
| COPY INTO           | down-arrow into bin           | Lucide `ArrowDownToLine`                                   |
| Stages              | stage box                     | Snowflake official "Stage" icon · Lucide `Inbox`           |
| VARIANT JSON        | curly braces                  | Lucide `Braces` · `FileJson`                               |
| File Formats        | file with cog                 | Lucide `FileType` · `FileCog`                              |
| Streams             | flowing waves                 | Lucide `Waves` · Tabler `wave-saw-tool`                    |
| Tasks               | clock + arrow                 | Snowflake "Task" icon · Lucide `CalendarClock`             |
| Replication / CDC   | two databases linked          | Snowflake "Replication" icon · Lucide `DatabaseZap`        |
| Conventions header  | rule book                     | Lucide `BookCheck` · `Notebook`                            |

### 8.3 Curated (Silver) column

| Box                     | Icon concept                | Where to get it                                                   |
| ----------------------- | --------------------------- | ----------------------------------------------------------------- |
| Identity & MDM          | id card · fingerprint        | Lucide `IdCard` · `Fingerprint`                                  |
| Triple store            | three connected dots        | custom (3 circles + 2 edges) · Lucide `Triangle`                  |
| Property graph          | network / nodes-and-edges   | Lucide `Network` · Tabler `binary-tree-2` · `graph`               |
| Hybrid Tables           | layered table               | Snowflake "Hybrid Tables" official · Lucide `Layers`              |
| Vocabulary & Taxonomy   | open book · library         | Lucide `BookOpen` · `Library` · Tabler `book-2`                   |
| SCD2 dims               | clock + table               | Lucide `History` + `Table`                                        |
| Vector embeddings       | scattered dots / cluster    | Lucide `ScatterChart` · Tabler `vector`                           |
| Quality / DMF / SHACL   | shield with check           | Lucide `ShieldCheck` · `BadgeCheck`                               |
| Performance             | gauge / lightning           | Lucide `Gauge` · `Zap`                                            |
| Search Optimization     | magnifier + lightning       | Snowflake "Search Optimization" icon · Lucide `SearchCheck`       |

### 8.4 Semantic (Gold) column

| Box                  | Icon concept                  | Where to get it                                                           |
| -------------------- | ----------------------------- | ------------------------------------------------------------------------- |
| Business interface   | open contract / view          | Lucide `BookOpenCheck` · `Eye`                                            |
| Semantic Views       | layered eye                   | Snowflake "Semantic View" official · Lucide `LayoutDashboard`             |
| Cortex Analyst       | Cortex swirl + chat            | Snowflake "Cortex Analyst" official · Lucide `MessageSquareCode`          |
| Cortex Search        | Cortex swirl + magnifier      | Snowflake "Cortex Search" official · Lucide `Search`                      |
| Graph RAG            | network + sparkles            | Lucide `Network` + `Sparkles` · Tabler `brain`                            |
| Cortex Guard         | shield + cortex                | Snowflake "Cortex Guard" official · Lucide `ShieldAlert`                  |
| Recursive CTE        | recurring arrow               | Lucide `Repeat2` · `RefreshCcw`                                           |
| p_graph_rag agent    | bot + graph                   | Lucide `Bot` overlay on `Network`                                         |
| Data products        | gift box                      | Lucide `Package` · Tabler `package`                                       |
| KPIs / dashboards    | bar chart / trend up          | Lucide `BarChart3` · `TrendingUp`                                         |
| Blast-radius walker  | radar / target                | Lucide `Radar` · `Crosshair`                                              |

### 8.5 Activation column (new "three rings")

| Box                              | Icon concept                  | Where to get it                                                  |
| -------------------------------- | ----------------------------- | ---------------------------------------------------------------- |
| Ring 1 header — Consume          | concentric inner ring         | Lucide `Circle` (filled) inside two outline circles              |
| Streamlit-in-Snowflake           | Streamlit logo                | Simple Icons → `streamlit`                                       |
| Snowflake Notebooks              | notebook + snowflake          | Snowflake "Notebooks" official · Lucide `BookOpen`               |
| Cortex Agents                    | Cortex swirl + bot             | Snowflake "Cortex Agents" official · Lucide `Bot`                |
| Tableau / Power BI / Sigma / Hex | brand marks                   | Simple Icons → `tableau` `powerbi` `sigma` (use `hex` text mark) |
| Embedded apps (REST/SQL)         | curly braces + arrow          | Lucide `Code2` · `Webhook`                                       |
| Reverse-ETL                      | reversed arrow                | Lucide `ArrowLeftRight` · Tabler `arrows-exchange`               |
| Ring 2 header — Align            | two overlapping circles       | Lucide `Combine` · `LayoutGrid`                                  |
| Internal Marketplace             | building + storefront          | Lucide `Store` · `Building2`                                     |
| Cross-BU semantic views          | linked layers                 | Lucide `Network` · `Layers`                                      |
| Enterprise KPIs                  | trend up                      | Lucide `TrendingUp` · `BarChart3`                                |
| Workforce / supply-chain         | chain links                   | Lucide `Link` · Tabler `chain`                                   |
| Reader accounts                  | book + cloud                  | Lucide `BookOpen` · `Cloud`                                      |
| Ring 3 header — Exchange         | two-way arrow / handshake     | Lucide `Handshake` · `ArrowLeftRight`                            |
| Secure Data Shares               | share icon + lock             | Snowflake "Secure Share" official · Lucide `Share2` + `Lock`     |
| Snowflake Marketplace            | Marketplace mark              | Snowflake "Marketplace" official                                 |
| Data Clean Rooms                 | sparkle in walled room         | Snowflake "Clean Rooms" official · Lucide `LockKeyhole`          |
| Native Apps                      | app window + snowflake         | Snowflake "Native Apps" official · Lucide `AppWindow`            |
| Partner Data                     | handshake                     | Lucide `Handshake`                                               |

### 8.6 Cross-cutting bands

| Band     | Icon concept                  | Where to get it                                                                |
| -------- | ----------------------------- | ------------------------------------------------------------------------------ |
| Cortex   | purple Cortex swirl           | Snowflake official Cortex mark                                                 |
| Ontology | RDF triangle / linked nodes   | custom 3-node triangle · Lucide `Network` · `BookText`                         |
| Taxonomy | folder tree                   | Lucide `FolderTree` · `ListTree` · Tabler `binary-tree`                        |
| Horizon  | horizon line + shield         | Snowflake "Horizon" official mark · Lucide `Shield` + `Eye`                    |
| Data Platform | snowflake mark            | Snowflake official corporate mark                                              |
| Snow Grid     | globe / grid              | Snowflake "Snow Grid" mark · Lucide `Globe2` · `Grid3x3`                       |

### 8.7 One-page download / linking strategy

If you don't want to chase 60 SVGs, do this:

1. **Lucid Shape Library → enable "Snowflake"** → covers all Snowflake primitives.
2. **One Simple Icons CDN URL pattern** for vendor logos:
   `https://cdn.simpleicons.org/<brand>/<hex-color>` — e.g.
   `https://cdn.simpleicons.org/salesforce/00A1E0`. Drop the URL into Lucid's *Insert Image*.
3. **One Lucide CDN URL pattern** for concept icons:
   `https://unpkg.com/lucide-static@latest/icons/<icon-name>.svg` — e.g.
   `https://unpkg.com/lucide-static@latest/icons/network.svg`.

That covers ~95% of the diagram with three sources and zero downloads.

### 8.8 Color discipline (so the icons read as a system)

- **Snowflake blue** `#29B5E8` for Snowflake-native primitives.
- **Vendor-native colors** for source systems and BI (Oracle red, SAP blue, Tableau orange, …).
- **Neutral graphite** `#3E4D58` for concept icons (identity, graph, taxonomy, …).
- **Cortex purple** `#7B61FF` for any Cortex-branded box.
- **Horizon green** `#1FB47A` for governance / observability icons.

Apply these as the icon stroke color in Lucid (right-click image → recolor). The diagram will
look intentional instead of stock.

---

## 9. Companion files in this folder

- `dc-data-mesh-architecture.mmd` — Mermaid source (auto-rendered to PNG).
- `dc-data-mesh-architecture.png` — rendered Mermaid output.
- `dc-data-mesh-architecture.drawio` — draw.io XML (editable in app.diagrams.net or VS Code drawio extension). *Not used in current workflow but kept for reference.*
- `dc-data-mesh-architecture.ascii.md` — **this file**.
