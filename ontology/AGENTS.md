# Agent guide — Snowflake Data Cloud Ontology Reference Architecture

Durable context and conventions for AI agents working in this repo. (Session-
specific operational state lives in the gitignored `HANDOFF.local.md`.)

## What this repo is

A **public** (Apache-2.0) reference implementation of a Snowflake-native
ontology / knowledge-graph substrate: a triple store + property graph that live
entirely in the Snowflake Data Cloud, governed by Horizon and reasoned over with
Cortex — no external graph DB, no vector DB, no inference cluster.

- `README.md` — the single source of architecture truth. The written reference
  architecture (§0–§9) was **blended into the README**; there is no separate
  architecture doc. Edit the README, not a separate file.
- `demo/` — runnable build: numbered SQL `01`–`12`, `streamlit_app.py`,
  `ontologies/` (ontology layer: generated per-source SQL + OWL/SHACL Turtle),
  `analytics_models/` (analytics layer: generated Cortex Analyst YAMLs named
  `analytics_<source>.yaml`), `tools/` (source-to-ontology adapter that
  consumes the repo's main `tools/data_generator.py`). The ontology (knowledge)
  and analytics (Cortex Analyst) artifacts are kept in separate folders/stages.
- `diagrams/` — Mermaid `.mmd` sources + rendered `.png` (referenced by README).
- `_tools/render_mermaid.py` — renders Mermaid → PNG; its slug map / DEFAULT_FILES
  point at `README.md`.

**All data is synthetic.** Never add real customer data, customer names, or
account locators to committed files.

## Terminology rules (important)

- "**Data Cloud**" / "**data platform**" are the approved terms for Snowflake.
- **Never** write "**data warehouse**." The word "warehouse" is allowed only for
  (a) a Snowflake **virtual warehouse** / compute object (`ONT_DEMO_*_WH`, the
  `WAREHOUSE` SQL keyword, `qh.warehouse_name`), or (b) a physical/domain object
  (`cpg:WholesaleWarehouse`, "warehouse-club SKU").
- Narrative data layers are **Raw / Curated / Semantic**. The SQL keeps schema
  names `BRONZE` / `SILVER` / `GOLD` (1:1). Use Bronze/Silver/Gold only when
  naming a specific SQL object, not in prose.

## Implementation conventions (don't regress these)

- **Cortex model list is discovered at runtime.** `demo/12_model_discovery.sql`
  probes which `COMPLETE` models work in the account/region and writes
  `SILVER.AVAILABLE_MODELS`. The Streamlit app reads that table. **Do not
  hard-code Cortex model names** (older IDs like `claude-3-5-sonnet`,
  `snowflake-arctic` are retired in some regions).
- **Cortex Search is queried from SQL via `SNOWFLAKE.CORTEX.SEARCH_PREVIEW(service, json)`**
  which returns `{"results":[...]}`. The `service!QUERY(...)` table form exists
  only in the REST/Python APIs — never use it in SQL.
- **Streamlit packages** are declared in `demo/environment.yml`
  (`plotly`, `numpy`). The Signal Graph uses a self-contained numpy spring layout
  — **no `networkx` dependency**. Keep a Graphviz fallback for any Plotly render.
- The Streamlit console has **9 tabs**: Chat · Graph RAG · Signal Graph · Recall ·
  Health · CISO Audit · Browse · Search · Explore.
- Owner's-rights Streamlit-in-Snowflake: `CURRENT_USER()`/`CURRENT_ROLE()` can be
  NULL — `COALESCE` them before inserting into NOT NULL columns.
- Dynamic Tables behind subquery-based row-access policies can't refresh
  incrementally — use `REFRESH_MODE = FULL` (see `statement_bu` in `09`).

## Deploy (Snow CLI)

```bash
cd demo
# Tier 1 (small demo)
snow sql -f 01_setup_database.sql
snow sql -f 02_load_synthetic_data.sql
snow sql -f 03_query_patterns.sql
snow sql -f 04_dbt_tests_and_dmfs.sql
snow stage put 05_semantic_model.yaml @ont_demo.config.cortex_analyst_models/
# Tier 2/3: 02b → 06 → 07 → 08 → 09 → 10 → 11 → 12  (see demo/README.md)
# Source-system data: python tools/generate_ontology_data.py --system sap
snow streamlit deploy --replace --database ONT_DEMO --schema CONFIG
```

## Git

Fresh history (not carved from any other repo). Keep customer/account specifics
out of commits. Confirm intent before creating a public remote or force-pushing.
