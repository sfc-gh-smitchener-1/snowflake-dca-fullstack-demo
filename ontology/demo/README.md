# Snowflake Ontology Reference — Demo

Runnable scaffolding for the architecture in the
[repository README](../README.md).

This demo is **source-system agnostic**. Instead of a hand-rolled, CPG-only
synthetic generator, it drives the repository's canonical multi-source data
generator (`tools/data_generator.py` at the repo root) and projects each
system into the ontology triple store through curated mapping specs. Six source
systems ship out of the box:

| Prefix | Source system | Example classes |
|---|---|---|
| `sap`  | SAP S/4HANA   | `sap:Customer`, `sap:Material`, `sap:SalesOrder`, `sap:Vendor` |
| `sfdc` | Salesforce    | `sfdc:Account`, `sfdc:Contact`, `sfdc:Opportunity`, `sfdc:Case` |
| `ora`  | Oracle EBS    | `ora:Party`, `ora:Supplier`, `ora:InventoryItem`, `ora:PayablesInvoice` |
| `fhir` | HL7 FHIR R4   | `fhir:Patient`, `fhir:Encounter`, `fhir:Condition`, `fhir:Observation` |
| `wd`   | Workday HCM   | `wd:Worker`, `wd:Organization`, `wd:JobProfile`, `wd:Compensation` |
| `snow` | ServiceNow    | `snow:User`, `snow:Incident`, `snow:ChangeRequest`, `snow:ConfigurationItem` |

A seventh vertical, **CPG** (`cpg:*`), is preserved as an optional reference
ontology (`ontologies/cpg.ttl` + `ontologies/cpg.sql`) but no longer ships a
bespoke data generator.

| Scale | Run | Use it for |
|---|---|---|
| **Small demo** (5 classes · 17 individuals · 35 triples) | `01 → 02 → 03 → 04 → 05` | First read-through; end-to-end smoke test |
| **Single-source demo** (one of the six systems) | `01 → 02 → 03 → 04 →` per-source loop `→ 06 → 07 → streamlit` | A vertical-specific analyst pattern (e.g. SAP order-to-cash, FHIR patient graph) |
| **Multi-source + Graph RAG + Governance** (all six + small-model graph RAG + RAP/masking/audit/feedback + blog-aligned enrichment) | `01 → 02 → 03 → 04 →` per-source loop `→ 06 → 06b → 07 → 08 → 09 → 10 → 11 → streamlit` | The CISO / CTO / Business pitch — every controls story Snowflake has, across heterogeneous sources, in one app |

## Files

```
demo/
├── 01_setup_database.sql                Database, schemas, virtual compute, roles, Cortex grants
├── 02_load_synthetic_data.sql           Small demo TBox + ABox  (5 classes, 17 individuals)
├── 03_query_patterns.sql                Dynamic Tables (node, edge), Gold views, search optimization,
│                                        all four query patterns, Cortex Search service
├── 04_dbt_tests_and_dmfs.sql            6 DMFs derived from the demo SHACL shapes
├── 05_semantic_model.yaml               Cortex Analyst semantic model for the small demo
│
├── 00_shared_tbox.sql                   Common schema.org properties shared by every source
├── 02b_load_source_ontology.sql         Generic, source-parameterized BRONZE→SILVER triple loader
│                                        (snow sql -D "SYSTEM=<prefix>"); writes source_system tag
├── 06_gold_views.sql                    Metadata-driven Gold view generator (SP_BUILD_GOLD_VIEWS):
│                                        one wide GOLD.V_<SOURCE>_<CLASS> view per class, per source
├── 06b_stage_semantic_models.sql        Stages the generated per-source analytics YAMLs to
│                                        @CONFIG.CORTEX_ANALYST_MODELS
├── 07_dmfs.sql                          Generic DMFs (minCount / pattern / enum) driven by
│                                        SILVER.constraint + live GOLD.v_ontology_health view
│
├── 08_graph_rag.sql                     Node embeddings (Snowflake-Arctic 768d) · hybrid vector+graph
│                                        retriever (f_retrieve_subgraph) · synthesis stored proc
│                                        (p_graph_rag) · source-generic GOLD.v_blast_radius view
├── 09_governance_policies.sql           Source-system-scoped row access policy on `statement` ·
│                                        column masking on PII literals · Horizon tags ·
│                                        Cortex Guard wrapper · demo users (SAP_ANALYST,
│                                        SALESFORCE_ANALYST, CISO_DEMO)
├── 10_rag_feedback.sql                  Append-only RAG log · thumbs procs · KPI views ·
│                                        commented scheduled task that fine-tunes llama3-8b
├── 11_blog_enrichments.sql              class_profile descendant rollup + per-source synonym
│                                        seeds; redefines f_retrieve_subgraph / p_graph_rag
├── 12_model_discovery.sql               Probes which Cortex COMPLETE models are live →
│                                        SILVER.AVAILABLE_MODELS (drives the model dropdown)
│
├── streamlit_app.py                     Ontology Console — source-aware, 9 tabs:
│                                        Chat · Graph RAG · Signal Graph · Recall · Health ·
│                                        CISO Audit · Browse · Search · Explore
├── snowflake.yml                        Streamlit-in-Snowflake deploy descriptor
├── environment.yml                      SiS conda environment
├── cleanup.sql                          Tear-down (drops ONT_DEMO + demo users + virtual compute)
│
├── ontologies/                          ── ONTOLOGY (knowledge) layer ──
│   │                                    Per-source TBox (generated) + optional CPG vertical
│   ├── 00_shared_tbox.sql               (symlink/companion of the shared properties)
│   ├── <source>.sql                     Generated TBox loader (namespace/class/property/shape/constraint)
│   ├── <source>.ttl                     Generated OWL/SHACL Turtle documentation
│   └── cpg.sql / cpg.ttl                Optional CPG reference vertical
│
├── analytics_models/                    ── ANALYTICS (Cortex Analyst) layer ──
│   └── analytics_<source>.yaml          Generated per-source Cortex Analyst models (the BI
│                                        projection over GOLD views); staged to
│                                        @CONFIG.CORTEX_ANALYST_MODELS
│
└── tools/
    ├── requirements.txt                 faker + adapter deps
    ├── ontology_adapter.py              Generic relational→triple engine (MappingSpec, emit_triples,
    │                                    derive_tbox); shared by every generator below
    ├── generate_ontology_data.py        ABox: data_generator.py → data/<source>/*.csv
    ├── generate_tbox.py                 TBox: mappings → ontologies/<source>.{sql,ttl}
    ├── generate_semantic_models.py      Cortex Analyst: mappings → analytics_models/analytics_<source>.yaml
    └── mappings/                        Curated mapping specs (one module per source)
        ├── sap.py  salesforce.py  oracle.py  fhir.py  workday.py  servicenow.py
```

## Prerequisites

- Snowflake account with Cortex enabled
- `ACCOUNTADMIN` for the initial setup (roles, virtual compute)
- Snow CLI (`snow`) installed and a connection profile configured
- Python 3.11+ (for the data / TBox / semantic-model generators)

```bash
cd demo
python3 -m venv .venv && source .venv/bin/activate
pip install -r tools/requirements.txt
```

## Run order — small demo (5 minutes)

```bash
snow sql -f 01_setup_database.sql
snow sql -f 02_load_synthetic_data.sql
snow sql -f 03_query_patterns.sql
snow sql -f 04_dbt_tests_and_dmfs.sql
snow stage put 05_semantic_model.yaml @ont_demo.config.cortex_analyst_models/
```

Then open Snowsight → Cortex Analyst, point it at
`@ont_demo.config.cortex_analyst_models/05_semantic_model.yaml`, and ask:

- *"How many customers are in California?"*
- *"List all accounts for Acme Inc. with their statuses."*
- *"What products has Acme Inc. ever ordered?"*

## The ontology adapter (how source data becomes triples)

Everything source-specific is generated from one input: a curated
`MappingSpec` per source (`tools/mappings/<source>.py`). Each spec declares,
per source table:

- `class_iri` — the ontology class each row becomes an individual of
- `uid_prefix` + `key` — how to mint a stable individual UID (callables allowed
  for composite keys)
- `literals` — datatype properties (`PropMap`: column → predicate + xsd type)
- `edges` — object properties / foreign keys (`EdgeMap`: column → predicate +
  target `uid_prefix`)

From that single spec, three generators (all in `tools/`) stay in lock-step:

| Generator | Reads | Writes | Purpose |
|---|---|---|---|
| `generate_ontology_data.py` | `data_generator.py` output + spec | `data/<source>/*.csv` | **ABox** — individuals + object/literal statements |
| `generate_tbox.py` | spec (`derive_tbox`) | `ontologies/<source>.{sql,ttl}` | **TBox** — namespace/class/property/shape/constraint |
| `generate_semantic_models.py` | spec | `analytics_models/analytics_<source>.yaml` | **Cortex Analyst** (analytics) model over the Gold views |

Because all three derive from the same `MappingSpec`, every predicate emitted
into the ABox is guaranteed to have a matching TBox definition and a Gold
column. See [`docs/DATA_GENERATION.md`](../../../docs/DATA_GENERATION.md) for
the full adapter walkthrough.

Generate everything for all six systems at once:

```bash
cd demo
python tools/generate_ontology_data.py --system all      # data/<source>/*.csv
python tools/generate_tbox.py                            # ontologies/<source>.{sql,ttl}
python tools/generate_semantic_models.py                 # analytics_models/analytics_<source>.yaml
```

## Run order — a single source (≈10 minutes)

The substrate (`01–04`) is shared. Then load one source by setting `SYSTEM`:

```bash
# 1. Substrate (skip if already done)
snow sql -f 01_setup_database.sql
snow sql -f 02_load_synthetic_data.sql
snow sql -f 03_query_patterns.sql
snow sql -f 04_dbt_tests_and_dmfs.sql
snow sql -f ontologies/00_shared_tbox.sql

# 2. Generate this source's CSVs + TBox + analytics model
#    (--system uses the CLI name; ontology outputs are keyed by the namespace prefix)
python tools/generate_ontology_data.py --system sap
python tools/generate_tbox.py
python tools/generate_semantic_models.py

# 3. Load the TBox, then the ABox (SYSTEM is the namespace prefix)
snow sql -D "SYSTEM=sap" -f ontologies/sap.sql
snow sql -D "SYSTEM=sap" -f 02b_load_source_ontology.sql

# 4. Build Gold views + DMFs + stage the semantic models
snow sql -f 06_gold_views.sql
snow sql -f 06b_stage_semantic_models.sql
snow sql -f 07_dmfs.sql

# 5. Deploy the Streamlit consumer (pick the source in the sidebar)
snow streamlit deploy --replace
```

The `--system` flag uses the **CLI name** (`sap`, `salesforce`, `oracle`,
`fhir`, `workday`, `servicenow`). Everything downstream — the `data/<prefix>/`
folder, `ontologies/<prefix>.{sql,ttl}`, and the SQL `SYSTEM` variable — is keyed
by the **namespace prefix** (`sap`, `sfdc`, `ora`, `fhir`, `wd`, `snow`). The
analytics models are named for readability instead — `analytics_models/analytics_<source>.yaml`
(e.g. `analytics_salesforce.yaml`). The `02b` loader tags every triple with
`source_system = UPPER(SYSTEM)`, so multiple sources coexist in one substrate.

## Run order — all six sources + Graph RAG + Governance (30–45 minutes)

```bash
# 1. Substrate
snow sql -f 01_setup_database.sql
snow sql -f 02_load_synthetic_data.sql
snow sql -f 03_query_patterns.sql
snow sql -f 04_dbt_tests_and_dmfs.sql
snow sql -f ontologies/00_shared_tbox.sql

# 2. Generate everything
python tools/generate_ontology_data.py --system all
python tools/generate_tbox.py
python tools/generate_semantic_models.py

# 3. Load every source (TBox then ABox). SYSTEM = the namespace PREFIX, which
#    is also the data-dir / TBox / semantic-model file name.
for P in sap sfdc ora fhir wd snow; do
  snow sql -D "SYSTEM=$P" -f ontologies/$P.sql
  snow sql -D "SYSTEM=$P" -f 02b_load_source_ontology.sql
done

# 4. Gold views, semantic models, DMFs
snow sql -f 06_gold_views.sql
snow sql -f 06b_stage_semantic_models.sql
snow sql -f 07_dmfs.sql

# 5. Graph RAG plumbing (waits for node_embedding DT to populate)
snow sql -f 08_graph_rag.sql

# 6. Governance overlay — RAP, masking, tags, Cortex Guard, demo users
snow sql -f 09_governance_policies.sql

# 7. RAG feedback log + KPI views
snow sql -f 10_rag_feedback.sql

# 8. Blog-aligned enrichment (class profile rollup + per-source synonyms)
snow sql -f 11_blog_enrichments.sql

# 9. Live model discovery + Streamlit
snow sql -f 12_model_discovery.sql
snow streamlit deploy --replace
```

> Note: `generate_ontology_data.py` uses the CLI names
> (`sap`, `salesforce`, `oracle`, `fhir`, `workday`, `servicenow`), while the
> SQL `SYSTEM` variable uses the **namespace prefix**
> (`sap`, `sfdc`, `ora`, `fhir`, `wd`, `snow`). The loop above maps between them.

## The Streamlit console (9 source-aware tabs)

Pick the active source system in the sidebar; every tab redraws its class,
predicate, and view lists from `SILVER.namespace` / `SILVER.class` /
`SILVER.property` for that source.

| Tab | What it does |
|---|---|
| **Chat**       | Cortex Analyst over `analytics_models/analytics_<source>.yaml` |
| **Graph RAG**  | Hybrid vector + graph retrieval; small-model synthesis with citations |
| **Signal Graph** | Force-directed view of the property graph projection |
| **Recall**     | Impact / blast-radius walk from any entity (`GOLD.V_BLAST_RADIUS`) |
| **Health**     | Live DMF dashboard (each row is a SHACL constraint, 0 = healthy) |
| **CISO Audit** | Policies + tags + Cortex query history + RAG feedback log |
| **Browse**     | Paginated lookups across the generated `GOLD.V_<SOURCE>_<CLASS>` views |
| **Search**     | Cortex Search service (`NODE_SEARCH_SVC`) over labels + literals |
| **Explore**    | Recursive-CTE n-hop walk from any individual along any predicate set |

## How the layers map to the reference architecture

| Reference layer (L0–L7 in the doc) | Manifestation in this demo |
|---|---|
| **L0 Sources & Standards** | `tools/data_generator.py` simulates SAP / Salesforce / Oracle / FHIR / Workday / ServiceNow |
| **L1 Ingest (Bronze)** | `BRONZE.SRC_*` landing tables loaded via stage + `COPY INTO` (`02b`) |
| **L2 Identifiers** | `silver.individual` — `uid_prefix`-namespaced UID + canonical IRI |
| **L3 Vocabulary** | `silver.constraint` enum / pattern bodies (per-source, generated) |
| **L4 Taxonomy** | `class.sub_class_of` hierarchy (generated TBox) |
| **L5 Ontology** | `silver.namespace/class/property/shape/constraint` (from `ontologies/<source>.sql`) |
| **L6 Semantic Layer** | `gold.v_<source>_*` views + `node`/`edge` DTs + per-source Cortex Analyst models |
| **L7 Activation** | `streamlit_app.py` (source-aware chat + browse + RAG + governance) |

## Governance model

Each **source system is a business unit**. `09_governance_policies.sql` derives
the BU from the namespace prefix of each individual's class IRI
(`v_individual_bu`), seeds `bu_membership` with one analyst per source
(`SAP_ANALYST`, `SALESFORCE_ANALYST`, …, plus an all-seeing `CISO_DEMO`), and
applies a row access policy so a consumer sees only their source's slice of the
graph. The Graph RAG path inherits the same policy automatically — switch role,
re-ask, watch the subgraph shrink.

## Tearing down

```bash
snow sql -f cleanup.sql
```

drops `ONT_DEMO` plus the virtual compute services, roles, and the demo users
created by `09_governance_policies.sql`. (The Streamlit deployment is removed
when the database goes; nothing else to clean up.)
