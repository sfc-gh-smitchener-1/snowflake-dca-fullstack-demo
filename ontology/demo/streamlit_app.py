"""
Ontology Console — a single-page Streamlit consumer of the Snowflake-native
ontology substrate built by 01–11_*.sql + the multi-source synthetic data load.

The console is SOURCE-AWARE: a sidebar selector picks one of the loaded source
systems (SAP, Salesforce, Oracle EBS, FHIR, Workday, ServiceNow, CPG, …) and
every tab drives its class / predicate / view lists from SILVER metadata
(silver.namespace / silver.class / silver.property) for that source.

Tabs
----
  1. Chat            — Cortex Analyst over @CONFIG.CORTEX_ANALYST_MODELS/analytics_<source>.yaml
  2. Graph RAG       — Hybrid vector + graph retrieval through SILVER.P_GRAPH_RAG;
                       small-model synthesis (llama3.1-8b default) with inline
                       citations and the retrieved subgraph rendered visually
  3. Recall          — One-click impact / blast-radius walk from any entity
                       (GOLD.V_BLAST_RADIUS) for the business demo
  4. Health          — DMF dashboard over SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS
  5. CISO Audit      — Policies + tags + Cortex query history + RAG feedback log
  6. Browse          — paginated lookups against the generated GOLD.V_<SOURCE>_* views
  7. Search          — Cortex Search service (node_search_svc) — semantic discovery
  8. Explore         — recursive-CTE n-hop walk from any individual

Deployment
----------
This file is designed to run as a Streamlit-in-Snowflake (SiS) app. The
`get_active_session()` call binds to the role/compute the SiS runtime
provides. To run locally, set SNOWFLAKE_* env vars and uncomment the
`Session.builder` block below.

    snow streamlit deploy --replace
"""
from __future__ import annotations

import json
import re
from datetime import datetime
from typing import Any

import pandas as pd
import streamlit as st
from snowflake.snowpark.context import get_active_session

# Local-laptop fallback (uncomment + set creds in env if running outside SiS):
#
# from snowflake.snowpark import Session
# import os
# def get_active_session():
#     return Session.builder.configs({
#         "account":   os.environ["SNOWFLAKE_ACCOUNT"],
#         "user":      os.environ["SNOWFLAKE_USER"],
#         "password":  os.environ["SNOWFLAKE_PASSWORD"],
#         "role":      os.environ.get("SNOWFLAKE_ROLE", "ONT_DEMO_BUILDER_ROLE"),
#         "warehouse": os.environ.get("SNOWFLAKE_WAREHOUSE", "ONT_DEMO_AGENT_WH"),
#         "database":  "ONT_DEMO",
#         "schema":    "GOLD",
#     }).create()


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

DB             = "ONT_DEMO"
SEARCH_SERVICE = "ONT_DEMO.SILVER.NODE_SEARCH_SVC"

# Friendly labels for the source-system prefixes the demo ships with. Any
# prefix discovered at runtime that isn't listed here falls back to UPPER().
SOURCE_LABELS = {
    "sap":  "SAP S/4HANA",
    "sfdc": "Salesforce",
    "ora":  "Oracle EBS",
    "fhir": "HL7 FHIR",
    "wd":   "Workday HCM",
    "snow": "ServiceNow",
    "cpg":  "CPG (reference vertical)",
}

# Cortex Analyst (analytics) model file per source prefix. These live in the
# CORTEX_ANALYST_MODELS stage and are produced by tools/generate_semantic_models.py.
# Keep in sync with FILE_SLUG in that generator.
SOURCE_MODELS = {
    "sap":  "analytics_sap.yaml",
    "sfdc": "analytics_salesforce.yaml",
    "ora":  "analytics_oracle_ebs.yaml",
    "fhir": "analytics_fhir.yaml",
    "wd":   "analytics_workday.yaml",
    "snow": "analytics_servicenow.yaml",
}

# Illustrative natural-language prompts per source for the Chat / Graph RAG
# tabs. GENERIC_PROMPTS is used for any source not listed here.
SOURCE_PROMPTS = {
    "sap":  ["Which 10 customers have the largest sales orders?",
             "List materials that never appear on a sales-order item.",
             "Top vendors by purchase-order count."],
    "sfdc": ["Which 10 accounts have the most open opportunities?",
             "Average opportunity amount by stage.",
             "Which contacts belong to the largest accounts?"],
    "ora":  ["Top suppliers by payables-invoice total.",
             "Which parties have the most sales orders?",
             "List inventory items that never appear on an order line."],
    "fhir": ["Which practitioners have the most encounters?",
             "Most common conditions by patient count.",
             "Which patients have an open medication request?"],
    "wd":   ["Which job profiles have the most workers?",
             "Average compensation by organization.",
             "List workers with time-off in this period."],
    "snow": ["Which configuration items have the most incidents?",
             "Open change requests by assignment group.",
             "Top callers by incident count."],
    "cpg":  ["Which 10 brands have the most products?",
             "What is the average price by product class?",
             "Which products are missing a GTIN?"],
}
GENERIC_PROMPTS = [
    "How many individuals exist per class?",
    "Show me everything connected to a single entity.",
    "Which classes have the most instances?",
]


# ---------------------------------------------------------------------------
# Page
# ---------------------------------------------------------------------------

st.set_page_config(page_title="Ontology Console", layout="wide")
st.title("Ontology Console")
st.caption(
    "A consumer for the Snowflake-native ontology substrate "
    "(triple store + property graph + Cortex), across every loaded source system."
)

session = get_active_session()


@st.cache_data(ttl=60)
def run_sql(sql: str, params: tuple = ()) -> pd.DataFrame:
    return session.sql(sql, params=list(params)).to_pandas()


# ---------------------------------------------------------------------------
# Source-system metadata helpers (drive every tab from SILVER metadata)
# ---------------------------------------------------------------------------

def source_label(prefix: str) -> str:
    return SOURCE_LABELS.get(prefix, prefix.upper())


def gold_view(prefix: str, class_iri: str) -> str:
    """GOLD view name produced by 06_gold_views.sql for (prefix, class)."""
    local = class_iri.split(":", 1)[-1]
    token = re.sub(r"[^A-Za-z0-9]", "_", local).upper()
    return f"{DB}.GOLD.V_{prefix.upper()}_{token}"


@st.cache_data(ttl=300)
def get_sources() -> list[str]:
    """Source-system prefixes that have classes loaded (excludes shared/standard
    vocabularies like schema:, owl:, xsd:)."""
    try:
        df = run_sql(
            f"""
            SELECT DISTINCT ns.prefix AS prefix
            FROM {DB}.SILVER.namespace ns
            JOIN {DB}.SILVER.class c ON c.namespace_iri = ns.namespace_iri
            WHERE ns.prefix NOT IN
                  ('schema','owl','rdfs','rdf','xsd','sh','dcterms','skos','ex')
            ORDER BY ns.prefix
            """
        )
        return df["PREFIX"].tolist() if not df.empty else []
    except Exception:
        return []


@st.cache_data(ttl=300)
def get_classes(prefix: str) -> pd.DataFrame:
    """Classes (IRI + label) for one source, with live instance counts."""
    return run_sql(
        f"""
        SELECT c.class_iri AS class_iri, c.label AS label,
               (SELECT COUNT(*) FROM {DB}.SILVER.individual i
                 WHERE i.class_iri = c.class_iri AND i.valid_to IS NULL) AS n
        FROM {DB}.SILVER.class c
        JOIN {DB}.SILVER.namespace ns ON ns.namespace_iri = c.namespace_iri
        WHERE ns.prefix = ?
        ORDER BY n DESC, c.label
        """,
        (prefix,),
    )


@st.cache_data(ttl=300)
def get_predicates(prefix: str) -> list[str]:
    """Object-property (walkable) predicate IRIs for one source."""
    try:
        df = run_sql(
            f"""
            SELECT p.property_iri AS property_iri
            FROM {DB}.SILVER.property p
            JOIN {DB}.SILVER.namespace ns ON ns.namespace_iri = p.namespace_iri
            WHERE ns.prefix = ? AND p.kind = 'object'
            ORDER BY p.property_iri
            """,
            (prefix,),
        )
        return df["PROPERTY_IRI"].tolist() if not df.empty else []
    except Exception:
        return []


# ---------------------------------------------------------------------------
# Sidebar — source selector + context + headline counts
# ---------------------------------------------------------------------------

SOURCES = get_sources()

with st.sidebar:
    st.markdown("### Source system")
    if SOURCES:
        source = st.selectbox(
            "Active source",
            SOURCES,
            format_func=source_label,
            key="source",
        )
    else:
        source = None
        st.warning("No source systems loaded yet. Run 02b_load_source_ontology.sql.")

    st.divider()
    st.markdown("### Substrate")
    counts = run_sql(
        f"""
        SELECT
            (SELECT COUNT(*) FROM {DB}.SILVER.individual WHERE valid_to IS NULL) AS individuals,
            (SELECT COUNT(*) FROM {DB}.SILVER.statement  WHERE valid_to IS NULL) AS triples,
            (SELECT COUNT(*) FROM {DB}.SILVER.class)                             AS classes,
            (SELECT COUNT(*) FROM {DB}.SILVER.property)                          AS properties
        """
    )
    if not counts.empty:
        row = counts.iloc[0]
        for label in ["INDIVIDUALS", "TRIPLES", "CLASSES", "PROPERTIES"]:
            st.metric(label.title(), f"{int(row[label]):,}")

    if source:
        sc = run_sql(
            f"""
            SELECT COUNT(*) AS n
            FROM {DB}.SILVER.individual i
            JOIN {DB}.SILVER.class c     ON c.class_iri = i.class_iri
            JOIN {DB}.SILVER.namespace ns ON ns.namespace_iri = c.namespace_iri
            WHERE ns.prefix = ? AND i.valid_to IS NULL
            """,
            (source,),
        )
        if not sc.empty:
            st.metric(f"{source_label(source)} individuals", f"{int(sc.iloc[0]['N']):,}")

    st.divider()
    st.markdown(
        "Companion docs: "
        "[Reference Architecture](../README.md)"
        + (f" · [{source_label(source)} TBox](./ontologies/{source}.ttl)" if source else "")
    )


# ---------------------------------------------------------------------------
# Tabs
# ---------------------------------------------------------------------------

(
    tab_chat, tab_graph_rag, tab_signal, tab_recall, tab_health,
    tab_ciso, tab_browse, tab_search, tab_explore,
) = st.tabs(
    ["Chat", "Graph RAG", "Signal Graph", "Recall", "Health",
     "CISO Audit", "Browse", "Search", "Explore"]
)


# ---------------------------------------------------------------------------
# Tab 1 — Chat (Cortex Analyst, semantic-model grounded)
# ---------------------------------------------------------------------------

def call_cortex_analyst(question: str) -> dict[str, Any]:
    """Call Cortex Analyst via the SiS REST bridge (_snowflake.send_snow_api_request).

    This is the correct surface for Cortex Analyst in Streamlit-in-Snowflake.
    The function is not available as a SQL scalar; it is a REST endpoint.
    """
    import _snowflake  # available in SiS runtime only
    active = st.session_state.get("source") or "sap"
    # Analytics models live at the root of the CORTEX_ANALYST_MODELS stage, named
    # analytics_<source>.yaml. (LS echoes the stage name as a path prefix, but the
    # files themselves live at the stage root.)
    model_file = SOURCE_MODELS.get(active, f"analytics_{active}.yaml")
    semantic_model_file = f"@{DB}.CONFIG.CORTEX_ANALYST_MODELS/{model_file}"
    body = {
        "messages": [
            {
                "role": "user",
                "content": [{"type": "text", "text": question}],
            }
        ],
        "semantic_model_file": semantic_model_file,
    }
    resp = _snowflake.send_snow_api_request(
        "POST",
        "/api/v2/cortex/analyst/message",
        {},   # headers
        {},   # query params
        body,
        {},   # request config
        30000,  # timeout ms
    )
    if resp.get("status") != 200:
        raise RuntimeError(
            f"Cortex Analyst returned status {resp.get('status')}: "
            f"{resp.get('content', '(no body)')}"
        )
    raw = resp["content"]
    return raw if isinstance(raw, dict) else json.loads(raw)


with tab_chat:
    st.subheader("Ask in plain English")
    _active = st.session_state.get("source") or "sap"
    st.caption(
        f"Backed by Cortex Analyst, grounded on `{_active}.yaml`. "
        "Try the suggestions or type your own."
    )

    suggestions = SOURCE_PROMPTS.get(_active, GENERIC_PROMPTS)
    cols = st.columns(3)
    for i, q in enumerate(suggestions):
        if cols[i % 3].button(q, key=f"sug-{i}"):
            st.session_state["_chat_input"] = q

    user_q = st.text_input(
        "Question",
        value=st.session_state.get("_chat_input", ""),
        placeholder="e.g. Which products are sold by the most retailers?",
    )

    if user_q:
        with st.spinner("Cortex Analyst is grounding…"):
            try:
                resp = call_cortex_analyst(user_q)
            except Exception as exc:  # pragma: no cover
                st.error(f"Analyst call failed: {exc}")
                resp = None

        if resp:
            # Cortex Analyst returns a structured answer with `messages` →
            # `content` array containing `text` and possibly `sql` parts.
            sql_text = None
            text_parts: list[str] = []
            for msg in resp.get("messages", []) or []:
                for part in msg.get("content", []) or []:
                    if part.get("type") == "text":
                        text_parts.append(part.get("text", ""))
                    elif part.get("type") == "sql":
                        sql_text = part.get("statement")
            if text_parts:
                st.markdown("\n\n".join(text_parts))
            if sql_text:
                with st.expander("Generated SQL", expanded=False):
                    st.code(sql_text, language="sql")
                try:
                    result_df = run_sql(sql_text)
                    st.dataframe(result_df, use_container_width=True)
                except Exception as exc:  # pragma: no cover
                    st.warning(f"Could not run the SQL: {exc}")


# ---------------------------------------------------------------------------
# Tab 2 — Graph RAG (hybrid retrieval + small-model synthesis)
# ---------------------------------------------------------------------------

# Preferred ordering for the dropdown: small/cheap models first (the headline
# pitch), then everything else the account can actually serve, alphabetically.
_MODEL_PREFERENCE = ["llama3.1-8b", "llama3.3-70b", "llama3.1-70b", "mistral-large2"]

# Used only if the discovery catalog is missing/empty (e.g. 12_model_discovery
# has not been run). These are deliberately conservative, broadly-available IDs.
_MODEL_FALLBACK = ["llama3.1-8b", "llama3.3-70b", "llama3.1-70b", "mistral-large2"]


@st.cache_data(ttl=300)
def get_cortex_models() -> list[str]:
    """Read the live list of usable Cortex models from the discovery catalog
    (SILVER.AVAILABLE_MODELS, populated by 12_model_discovery.sql). This avoids
    a hard-coded list that rots as Snowflake adds/retires models per region."""
    try:
        df = run_sql(
            f"""
            SELECT model_name
            FROM {DB}.SILVER.AVAILABLE_MODELS
            WHERE is_available
            """
        )
        avail = sorted(df["MODEL_NAME"].tolist()) if not df.empty else []
    except Exception:
        avail = []
    if not avail:
        return _MODEL_FALLBACK
    preferred = [m for m in _MODEL_PREFERENCE if m in avail]
    rest = [m for m in avail if m not in preferred]
    return preferred + rest


CORTEX_MODELS = get_cortex_models()

def graph_rag_suggestions() -> list[str]:
    """Source-aware Graph RAG prompts (curated per source, generic fallback)."""
    active = st.session_state.get("source") or "sap"
    return SOURCE_PROMPTS.get(active, GENERIC_PROMPTS)


def call_graph_rag(question: str, top_k: int, max_hops: int,
                   model: str, guarded: bool) -> dict[str, Any]:
    proc = "SILVER.P_GRAPH_RAG_GUARDED" if guarded else "SILVER.P_GRAPH_RAG"
    df = run_sql(
        f"CALL {proc}(?, ?, ?, ?)",
        (question, int(top_k), int(max_hops), model),
    )
    raw = df.iloc[0, 0]
    return raw if isinstance(raw, dict) else json.loads(raw)


def render_subgraph_dot(subgraph: dict[str, Any]) -> str:
    """Render the retrieved subgraph as Graphviz DOT for st.graphviz_chart."""
    nodes = subgraph.get("nodes") or []
    edges = subgraph.get("edges") or []
    lines = ["digraph G {", '  rankdir=LR;', '  node [shape=box,style="rounded,filled",fontname="Helvetica"];']
    palette = {
        0: "#fff4c2",   # seed — yellow
        1: "#cfe8ff",   # 1-hop — blue
        2: "#e6dcff",   # 2-hop — purple
        3: "#dddddd",
    }
    for n in nodes:
        nid = n.get("node_uid", "")
        label = (n.get("label") or nid).replace('"', "'")
        cls = (n.get("class_iri") or "").replace('"', "'")
        depth = int(n.get("depth", 0))
        fill = palette.get(min(depth, 3), "#eeeeee")
        lines.append(
            f'  "{nid}" [label=<<b>{label}</b><br/><font point-size="9">{cls}</font>>,'
            f'fillcolor="{fill}"];'
        )
    for e in edges:
        s = e.get("src_uid", "")
        d = e.get("dst_uid", "")
        p = (e.get("predicate_iri") or "").replace('"', "'")
        lines.append(f'  "{s}" -> "{d}" [label="{p}",fontsize=9,color="#666"];')
    lines.append("}")
    return "\n".join(lines)


def log_rag_round_trip(question: str, model: str, payload: dict[str, Any],
                       guarded: bool) -> str | None:
    try:
        sql = """
            CALL SILVER.P_LOG_RAG(?, ?, ?, PARSE_JSON(?), PARSE_JSON(?), ?, ?, PARSE_JSON(?))
        """
        df = run_sql(
            sql,
            (
                question,
                model,
                payload.get("answer") or "",
                json.dumps(payload.get("citations") or []),
                json.dumps(payload.get("subgraph") or {}),
                int(payload.get("latency_ms") or 0),
                bool(guarded),
                json.dumps(payload.get("verdict") or {}),
            ),
        )
        return df.iloc[0, 0] if not df.empty else None
    except Exception as exc:  # pragma: no cover
        st.warning(f"Could not log feedback: {exc}")
        return None


def log_thumbs(feedback_id: str, thumbs: str, comment: str = "") -> None:
    try:
        run_sql("CALL SILVER.P_LOG_THUMBS(?, ?, ?)", (feedback_id, thumbs, comment))
    except Exception as exc:  # pragma: no cover
        st.warning(f"Could not record thumbs: {exc}")


with tab_graph_rag:
    st.subheader("Graph RAG — hybrid vector + ontology retrieval")
    st.caption(
        "Vector search seeds the walk · property graph constrains it · "
        "class profiles carry pre-aggregated descendant context · curated "
        "synonyms override composite terms · small Cortex model writes the "
        "final sentence. Nothing leaves the account. "
        "(Architecture follows the May-25-2026 Snowflake-Cortex blog "
        "*Ontology-grounded Reasoning with Cortex Agents*.)"
    )

    cols = st.columns([3, 1, 1, 1, 1])
    g_question = cols[0].text_input(
        "Question",
        value=st.session_state.get("_grag_input", ""),
        placeholder="e.g. Which gluten-free snacks are sold in California?",
    )
    g_top_k    = cols[1].slider("Seeds (top-K)", 3, 20, 8)
    g_max_hops = cols[2].slider("Hops",          1,  3, 2)
    g_model    = cols[3].selectbox("Model",      CORTEX_MODELS, index=0)
    g_guard    = cols[4].checkbox("Cortex Guard",  value=True,
                                help="Pre-filter prompts via SILVER.P_GRAPH_RAG_GUARDED")

    sug_cols = st.columns(3)
    for i, q in enumerate(graph_rag_suggestions()):
        if sug_cols[i % 3].button(q, key=f"grag-sug-{i}"):
            st.session_state["_grag_input"] = q
            st.experimental_rerun()

    if g_question:
        with st.spinner(f"Retrieving subgraph and asking {g_model}…"):
            try:
                payload = call_graph_rag(g_question, g_top_k, g_max_hops, g_model, g_guard)
            except Exception as exc:
                st.error(f"Graph RAG call failed: {exc}")
                payload = None

        if payload:
            left, right = st.columns([3, 2])

            subgraph = payload.get("subgraph") or {}
            classes = subgraph.get("classes") or []
            synonyms = subgraph.get("synonyms") or []
            nodes = subgraph.get("nodes") or []
            edges = subgraph.get("edges") or []

            with left:
                st.markdown("#### Answer")
                if payload.get("answer"):
                    st.markdown(payload["answer"])
                cites = payload.get("citations") or []
                if cites:
                    st.caption("**Citations:** " + " · ".join(f"`{c}`" for c in cites))

                # Blog-aligned overlays — only render when they fired.
                if synonyms:
                    with st.expander(
                        f"Curated terminology overrides applied ({len(synonyms)}) — "
                        f"closes the 'last-mile' gap per the May-25 Cortex blog",
                        expanded=False,
                    ):
                        for s in synonyms:
                            label = f"**{s.get('surface_form')}**"
                            tail = s.get("notes") or s.get("canonical_iri") or ""
                            st.markdown(f"- {label}: {tail}")
                if classes:
                    with st.expander(
                        f"Class-profile matches ({len(classes)}) — "
                        f"descendant attributes pre-rolled-up at index time",
                        expanded=False,
                    ):
                        for c in classes:
                            st.markdown(
                                f"- `{c.get('class_iri')}` · score "
                                f"{float(c.get('score') or 0):.3f} · {c.get('snippet')}"
                            )

                meta = st.columns(6)
                meta[0].metric("Model",     payload.get("model", "?"))
                meta[1].metric("Latency",   f"{payload.get('latency_ms', 0)} ms")
                meta[2].metric("Classes",   len(classes))
                meta[3].metric("Nodes",     len(nodes))
                meta[4].metric("Edges",     len(edges))
                meta[5].metric("Synonyms",  len(synonyms))

                fid = log_rag_round_trip(g_question, g_model, payload, g_guard)
                if fid:
                    fb_cols = st.columns([1, 1, 6])
                    if fb_cols[0].button("👍", key=f"thumbs-up-{fid}"):
                        log_thumbs(fid, "up")
                        st.toast("Thanks — logged.")
                    if fb_cols[1].button("👎", key=f"thumbs-down-{fid}"):
                        log_thumbs(fid, "down")
                        st.toast("Logged — we'll review.")

                with st.expander("Prompt sent to the model", expanded=False):
                    st.code(payload.get("prompt") or "(no prompt captured)", language="markdown")

            with right:
                st.markdown("#### Retrieved subgraph")
                if nodes:
                    st.graphviz_chart(render_subgraph_dot(subgraph), use_container_width=True)
                elif classes:
                    st.info(
                        "No instance subgraph — answer was sourced entirely "
                        "from the matched class profiles (descendant attributes "
                        "pre-aggregated at index time)."
                    )
                with st.expander("Raw subgraph JSON", expanded=False):
                    st.json(subgraph)


# ---------------------------------------------------------------------------
# Tab 3 — Signal Graph (interactive, importance-weighted relationship map)
# ---------------------------------------------------------------------------
# Two modes:
#   * Ontology schema  — classes are nodes, predicates are weighted edges, edge
#                        weight = number of triples of that shape, node
#                        importance = total triple volume touching the class.
#   * Individual ego   — a recursive neighborhood around one individual, with
#                        node importance = local degree.
# Colour encodes importance; size echoes it; edge width tracks weight. Rendered
# with Plotly (zoom / pan / hover) and falls back to Graphviz if Plotly is not
# present in the Streamlit-in-Snowflake environment.


@st.cache_data(ttl=300)
def load_schema_signal() -> pd.DataFrame:
    return run_sql(
        f"""
        SELECT s.class_iri AS src, e.predicate_iri AS predicate,
               d.class_iri AS dst, COUNT(*) AS weight
        FROM {DB}.SILVER.edge e
        JOIN {DB}.SILVER.node s ON e.src_uid = s.node_uid
        JOIN {DB}.SILVER.node d ON e.dst_uid = d.node_uid
        GROUP BY 1, 2, 3
        """
    )


@st.cache_data(ttl=120)
def load_ego_signal(start_uid: str, hops: int, cap: int) -> pd.DataFrame:
    return run_sql(
        f"""
        WITH RECURSIVE walk AS (
            SELECT e.src_uid, e.predicate_iri, e.dst_uid, 1 AS depth
            FROM {DB}.SILVER.edge e
            WHERE e.src_uid = ?
            UNION ALL
            SELECT e.src_uid, e.predicate_iri, e.dst_uid, w.depth + 1
            FROM {DB}.SILVER.edge e
            JOIN walk w ON e.src_uid = w.dst_uid
            WHERE w.depth < ?
        )
        SELECT src_uid AS src, predicate_iri AS predicate, dst_uid AS dst,
               COUNT(*) AS weight
        FROM walk
        GROUP BY 1, 2, 3
        ORDER BY weight DESC
        LIMIT ?
        """,
        (start_uid, int(hops), int(cap)),
    )


@st.cache_data(ttl=120)
def load_relationship_instances(src_class: str, predicate: str,
                                dst_class: str, cap: int = 50) -> pd.DataFrame:
    """Actual instance pairs behind one class→predicate→class relationship."""
    return run_sql(
        f"""
        SELECT s.node_uid AS src_uid,
               COALESCE(s.name, s.label, s.node_uid) AS src_label,
               d.node_uid AS dst_uid,
               COALESCE(d.name, d.label, d.node_uid) AS dst_label
        FROM {DB}.SILVER.edge e
        JOIN {DB}.SILVER.node s ON e.src_uid = s.node_uid
        JOIN {DB}.SILVER.node d ON e.dst_uid = d.node_uid
        WHERE s.class_iri = ? AND e.predicate_iri = ? AND d.class_iri = ?
        LIMIT ?
        """,
        (src_class, predicate, dst_class, int(cap)),
    )


def _signal_spring_layout(node_ids, edges, iterations=160, seed=7):
    """Tiny Fruchterman-Reingold layout (numpy only, no networkx)."""
    import numpy as np

    n = len(node_ids)
    idx = {nid: i for i, nid in enumerate(node_ids)}
    rng = np.random.default_rng(seed)
    pos = rng.normal(size=(n, 2))
    if n <= 1:
        return {nid: pos[idx[nid]] for nid in node_ids}
    k = 1.0 / np.sqrt(n)
    E = [(idx[a], idx[b], w) for a, b, w in edges if a in idx and b in idx]
    wmax = max((w for *_, w in E), default=1.0) or 1.0
    for it in range(iterations):
        disp = np.zeros((n, 2))
        for i in range(n):                              # repulsion
            delta = pos[i] - pos
            dist = np.sqrt((delta ** 2).sum(1)) + 1e-9
            force = (k * k / dist)[:, None] * (delta / dist[:, None])
            force[i] = 0.0
            disp[i] += force.sum(0)
        for a, b, w in E:                               # attraction (weighted)
            delta = pos[a] - pos[b]
            dist = np.sqrt((delta ** 2).sum()) + 1e-9
            f = (dist * dist / k) * (0.4 + 0.6 * (w / wmax)) * (delta / dist)
            disp[a] -= f
            disp[b] += f
        length = np.sqrt((disp ** 2).sum(1)) + 1e-9
        cap = 0.1 * (1 - it / iterations) + 0.01
        pos += (disp / length[:, None]) * np.minimum(length, cap)[:, None]
    pos -= pos.mean(0)
    pos /= (np.abs(pos).max() + 1e-9)
    return {nid: pos[idx[nid]] for nid in node_ids}


def render_signal_graph(edges_df: pd.DataFrame, *, label_map=None,
                        max_edges=140, height=620, colorscale="YlOrRd",
                        select_key=None, highlight=None):
    """Render a weighted relationship graph. edges_df: src, dst, predicate,
    weight. Node importance = total incident weight.

    If select_key is given and the Streamlit runtime supports Plotly selection
    events, clicking a node returns the list of clicked node ids (so callers
    can drill in). Returns None otherwise."""
    if edges_df.empty:
        st.info("No relationships to plot.")
        return None

    df = edges_df.sort_values("WEIGHT", ascending=False).head(max_edges)
    edges = list(zip(df["SRC"], df["DST"], df["WEIGHT"]))

    importance: dict[str, float] = {}
    for a, b, w in edges:
        importance[a] = importance.get(a, 0.0) + float(w)
        importance[b] = importance.get(b, 0.0) + float(w)
    node_ids = list(importance.keys())
    label_map = label_map or {}

    try:
        import numpy as np
        import plotly.graph_objects as go
    except Exception:                                   # graphviz fallback
        _render_signal_graphviz(edges, importance, label_map)
        return

    pos = _signal_spring_layout(node_ids, edges)
    imps = np.array([importance[n] for n in node_ids], dtype=float)
    imin, imax = imps.min(), imps.max()
    span = (imax - imin) or 1.0
    sizes = 14 + 40 * (imps - imin) / span
    wmax = max((w for *_, w in edges), default=1.0) or 1.0

    fig = go.Figure()
    for a, b, w in edges:                               # one trace per edge (widths)
        xa, ya = pos[a]; xb, yb = pos[b]
        fig.add_trace(go.Scatter(
            x=[xa, xb], y=[ya, yb], mode="lines",
            line=dict(width=0.6 + 4.5 * (np.log1p(w) / np.log1p(wmax)),
                      color="rgba(120,120,120,0.45)"),
            hoverinfo="skip", showlegend=False,
        ))
    # Edge hover markers at midpoints (predicate + weight).
    fig.add_trace(go.Scatter(
        x=[(pos[a][0] + pos[b][0]) / 2 for a, b, _ in edges],
        y=[(pos[a][1] + pos[b][1]) / 2 for a, b, _ in edges],
        mode="markers",
        marker=dict(size=6, color="rgba(120,120,120,0.0)"),
        hovertext=[f"{label_map.get(a, a)} —[{p}]→ {label_map.get(b, b)}<br>"
                   f"<b>{int(w):,}</b> triples"
                   for (a, b, w), p in zip(edges, df["PREDICATE"])],
        hoverinfo="text", showlegend=False,
    ))
    border_w = [4.0 if n == highlight else 1.0 for n in node_ids]
    border_c = ["#1769ff" if n == highlight else "#333" for n in node_ids]
    fig.add_trace(go.Scatter(
        x=[pos[n][0] for n in node_ids],
        y=[pos[n][1] for n in node_ids],
        mode="markers+text",
        text=[label_map.get(n, n) for n in node_ids],
        textposition="top center",
        textfont=dict(size=10),
        customdata=node_ids,
        marker=dict(
            size=sizes, color=imps, colorscale=colorscale, showscale=True,
            colorbar=dict(title="Signal<br>(triples)"),
            line=dict(width=border_w, color=border_c), opacity=0.95,
        ),
        hovertext=[f"<b>{label_map.get(n, n)}</b><br>signal: "
                   f"{int(importance[n]):,} triples<br>"
                   "<i>click to drill in</i>" for n in node_ids],
        hoverinfo="text", showlegend=False,
    ))
    fig.update_layout(
        height=height, margin=dict(l=10, r=10, t=10, b=10),
        xaxis=dict(visible=False), yaxis=dict(visible=False),
        plot_bgcolor="white", dragmode="pan",
    )
    cfg = {"scrollZoom": True, "displaylogo": False}
    if select_key:
        try:
            event = st.plotly_chart(
                fig, use_container_width=True, config=cfg,
                key=select_key, on_select="rerun", selection_mode=("points",),
            )
            sel = getattr(event, "selection", None)
            pts = (sel or {}).get("points", []) if isinstance(sel, dict) \
                else getattr(sel, "points", []) or []
            picked = []
            for p in pts:
                cd = p.get("customdata") if isinstance(p, dict) else None
                if isinstance(cd, (list, tuple)):
                    cd = cd[0] if cd else None
                if cd:
                    picked.append(cd)
            return picked or None
        except TypeError:
            # Older Streamlit (no selection events) — render plain.
            st.plotly_chart(fig, use_container_width=True, config=cfg)
            return None
    st.plotly_chart(fig, use_container_width=True, config=cfg)
    return None


def _render_signal_graphviz(edges, importance, label_map):
    imin = min(importance.values()); imax = max(importance.values())
    span = (imax - imin) or 1.0

    def fill(v):
        t = (v - imin) / span                           # white -> deep orange
        r, g, b = 255, int(245 - 150 * t), int(235 - 200 * t)
        return f"#{r:02x}{g:02x}{b:02x}"

    lines = ['digraph G {', '  layout=fdp; overlap=false; splines=true;',
             '  node [shape=circle,style=filled,fontname="Helvetica",fontsize=10];']
    for n, v in importance.items():
        lab = (label_map.get(n, n)).replace('"', "'")
        lines.append(f'  "{n}" [label="{lab}",fillcolor="{fill(v)}",'
                     f'width={0.4 + 1.6 * (v - imin) / span:.2f}];')
    wmax = max((w for *_, w in edges), default=1.0) or 1.0
    for a, b, w in edges:
        lines.append(f'  "{a}" -> "{b}" [penwidth={0.5 + 4 * (w / wmax):.2f},'
                     f'color="#888",tooltip="{int(w)} triples"];')
    lines.append("}")
    st.graphviz_chart("\n".join(lines), use_container_width=True)


def _short(iri: str) -> str:
    return iri.split(":")[-1] if iri else iri


def _jump_to_ego(uid: str) -> None:
    """Queue a switch into ego-net mode focused on a specific individual.
    We only stash a non-widget flag here and rerun; the actual widget-state
    writes happen at the top of the tab, before those widgets are created
    (Streamlit forbids mutating a widget's state after it is instantiated)."""
    st.session_state["_sig_pending_seed"] = uid
    try:
        st.rerun()
    except Exception:
        st.experimental_rerun()


with tab_signal:
    # Apply any queued navigation BEFORE the mode/seed widgets are created.
    _pending = st.session_state.pop("_sig_pending_seed", None)
    if _pending:
        st.session_state["signal_mode"] = "Individual ego-net"
        st.session_state["signal_seed"] = _pending

    st.subheader("Signal graph — relationships weighted by importance")
    st.caption(
        "Colour and size encode **signal** (how much of the graph flows through "
        "a node); edge width tracks the number of triples of that shape. "
        "Drag to pan, scroll to zoom, hover, and **click a node to drill in**."
    )

    mode = st.radio(
        "View", ["Ontology schema (class-level)", "Individual ego-net"],
        horizontal=True, key="signal_mode",
    )

    if mode.startswith("Ontology"):
        raw = load_schema_signal()
        if raw.empty:
            st.info("No edges loaded yet.")
        else:
            cmin, cmax = int(raw["WEIGHT"].min()), int(raw["WEIGHT"].max())
            c1, c2 = st.columns([3, 1])
            floor = c1.slider(
                "Minimum edge weight (triples)", cmin, cmax,
                value=min(cmin, cmax) if cmax == cmin else max(cmin, cmax // 50),
            )
            scale = c2.selectbox(
                "Colour scale", ["YlOrRd", "Viridis", "Plasma", "Turbo", "Blues"],
            )
            shown = raw[raw["WEIGHT"] >= floor]

            classes = (raw.groupby("SRC")["WEIGHT"].sum()
                          .add(raw.groupby("DST")["WEIGHT"].sum(), fill_value=0)
                          .sort_values(ascending=False))
            class_ids = list(classes.index)
            label_map = {c: _short(c) for c in class_ids}

            picked = render_signal_graph(
                shown, label_map=label_map, colorscale=scale,
                select_key="sig_schema_graph",
                highlight=st.session_state.get("sig_class_select"),
            )
            if picked and picked[0] in class_ids:
                st.session_state["sig_class_select"] = picked[0]

            st.caption("Highest-signal classes: " + " · ".join(
                f"{_short(c)} ({int(v):,})" for c, v in classes.head(8).items()))

            st.divider()
            st.markdown("#### Drill in")
            focus = st.selectbox(
                "Class to inspect", class_ids,
                format_func=lambda c: f"{_short(c)}  ({int(classes[c]):,} signal)",
                key="sig_class_select",
            )

            rel = raw[(raw["SRC"] == focus) | (raw["DST"] == focus)].copy()
            rel["DIRECTION"] = rel["SRC"].apply(
                lambda s: "outgoing →" if s == focus else "← incoming")
            rel["FROM"] = rel["SRC"].apply(_short)
            rel["TO"] = rel["DST"].apply(_short)
            rel["PREDICATE"] = rel["PREDICATE"].apply(_short)
            rel = rel.sort_values("WEIGHT", ascending=False)

            dc1, dc2 = st.columns([1, 1])
            with dc1:
                st.markdown(f"**Relationships of `{_short(focus)}`**")
                st.dataframe(
                    rel[["DIRECTION", "FROM", "PREDICATE", "TO", "WEIGHT"]],
                    use_container_width=True, hide_index=True,
                )
            with dc2:
                # Focused neighbourhood (this class + its direct neighbours).
                neigh = raw[(raw["SRC"] == focus) | (raw["DST"] == focus)]
                nlabels = {c: _short(c) for c in
                           set(neigh["SRC"]) | set(neigh["DST"])}
                render_signal_graph(
                    neigh, label_map=nlabels, colorscale=scale, height=360,
                    highlight=focus,
                )

            st.markdown("**Inspect the individuals behind one relationship**")
            rel_opts = {
                f'{r.FROM} —[{r.PREDICATE}]→ {r.TO}  ({int(r.WEIGHT):,})':
                    (r.SRC, raw.loc[r.Index, "PREDICATE"], r.DST)
                for r in rel.itertuples()
            }
            chosen = st.selectbox("Relationship", list(rel_opts.keys()))
            if chosen:
                s_cls, pred, d_cls = rel_opts[chosen]
                pairs = load_relationship_instances(s_cls, pred, d_cls, cap=50)
                st.dataframe(pairs, use_container_width=True, hide_index=True)
                if not pairs.empty:
                    pick_uid = st.selectbox(
                        "Open an individual's ego-net",
                        pairs["SRC_UID"].tolist() + pairs["DST_UID"].tolist(),
                    )
                    if st.button("Open ego-net →", key="sig_jump"):
                        _jump_to_ego(pick_uid)
    else:
        c1, c2, c3 = st.columns([2, 1, 1])
        seed = c1.text_input("Start individual UID", value="SKU-0000000",
                             key="signal_seed")
        hops = c2.slider("Hops", 1, 3, 2, key="signal_hops")
        cap = c3.slider("Max edges", 20, 200, 80, key="signal_cap")
        if seed:
            ego = load_ego_signal(seed, hops, cap)
            if ego.empty:
                st.info(f"No outgoing relationships from `{seed}`.")
            else:
                uids = list(set(ego["SRC"]) | set(ego["DST"]))
                labels = run_sql(
                    f"""
                    SELECT node_uid, COALESCE(name, label, node_uid) AS lbl
                    FROM {DB}.SILVER.node
                    WHERE node_uid IN ({','.join(['?'] * len(uids))})
                    """,
                    tuple(uids),
                )
                label_map = dict(zip(labels["NODE_UID"], labels["LBL"]))
                label_map[seed] = label_map.get(seed, seed)
                picked = render_signal_graph(
                    ego, label_map=label_map, colorscale="Viridis",
                    select_key="sig_ego_graph", highlight=seed,
                )
                st.caption(
                    "Click any node to re-center the ego-net on it. "
                    f"Currently centred on **{label_map.get(seed, seed)}**."
                )
                if picked and picked[0] != seed:
                    _jump_to_ego(picked[0])


# ---------------------------------------------------------------------------
# Tab 4 — Recall blast radius (the headline business demo)
# ---------------------------------------------------------------------------

with tab_recall:
    st.subheader("Impact / blast-radius walker")
    st.caption(
        "Pick any entity. The graph returns every related individual within 3 "
        "hops — the recall list, the breach radius, the affected workers — "
        "what you'd need to call, contain, or relabel within the hour."
    )

    if not source:
        st.info("Select a source system in the sidebar.")
    else:
        classes = get_classes(source)
        classes = classes[classes["N"] > 0]
        if classes.empty:
            st.info(f"No {source_label(source)} individuals loaded yet.")
        else:
            cls_labels = {
                f"{r.LABEL or r.CLASS_IRI} ({int(r.N):,})": r.CLASS_IRI
                for r in classes.itertuples()
            }
            cls_pick = st.selectbox("Root entity class", list(cls_labels.keys()))
            root_class = cls_labels[cls_pick]

            roots = run_sql(
                f"""
                SELECT node_uid, COALESCE(name, label, node_uid) AS display
                FROM   {DB}.SILVER.node
                WHERE  class_iri = ?
                ORDER  BY display
                LIMIT  500
                """,
                (root_class,),
            )
            if roots.empty:
                st.info("No individuals of that class.")
            else:
                root_labels = {
                    f"{r.DISPLAY} — {r.NODE_UID}": r.NODE_UID
                    for r in roots.itertuples()
                }
                pick = st.selectbox("Root entity", list(root_labels.keys()))
                root_uid = root_labels[pick]

                radius = run_sql(
                    f"""
                    SELECT depth, via_predicate, reached_uid, reached_class,
                           reached_name, reached_label
                    FROM   {DB}.GOLD.V_BLAST_RADIUS
                    WHERE  root_uid = ?
                    ORDER  BY depth, reached_class
                    """,
                    (root_uid,),
                )

                if radius.empty:
                    st.info("No outbound relationships within 3 hops.")
                else:
                    by_class = (
                        radius.groupby("REACHED_CLASS")["REACHED_UID"]
                        .nunique()
                        .sort_values(ascending=False)
                    )
                    top = by_class.head(5)
                    summary_cols = st.columns(max(len(top), 1))
                    for i, (cls_iri, n) in enumerate(top.items()):
                        summary_cols[i].metric(cls_iri.split(":", 1)[-1], int(n))

                st.dataframe(radius, use_container_width=True, height=420)

                with st.expander("Generated SQL (for the auditor)", expanded=False):
                    st.code(
                        f"SELECT * FROM {DB}.GOLD.V_BLAST_RADIUS\n"
                        f"WHERE root_uid = '{root_uid}'\nORDER BY depth;",
                        language="sql",
                    )


# ---------------------------------------------------------------------------
# Tab 5 — Health (DMFs)
# ---------------------------------------------------------------------------

with tab_health:
    st.subheader("Ontology health — SHACL → DMF dashboard")
    st.caption(
        "Each row is a `DATA_METRIC_FUNCTION` derived from a SHACL constraint "
        "in `silver.shape` / `silver.constraint`. **0 = healthy.**"
    )

    # Per-DMF latest measurement
    health_sql = """
        SELECT
            metric_name,
            measurement_time,
            value AS violation_count
        FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS
        WHERE table_database = 'ONT_DEMO'
          AND metric_name LIKE 'DMF\\_%' ESCAPE '\\\\'
        QUALIFY ROW_NUMBER() OVER (PARTITION BY metric_name
                                   ORDER BY measurement_time DESC) = 1
        ORDER BY violation_count DESC, metric_name
    """
    try:
        h = run_sql(health_sql)
    except Exception as exc:
        st.warning(
            "No DMF results yet (or `DATA_QUALITY_MONITORING_RESULTS` not "
            f"accessible by the current role). Wait one schedule tick and refresh.\n\n{exc}"
        )
        h = pd.DataFrame()

    if not h.empty:
        # DMF results can arrive as strings; coerce so comparisons work.
        h["VIOLATION_COUNT"] = pd.to_numeric(h["VIOLATION_COUNT"], errors="coerce").fillna(0)
        red = (h["VIOLATION_COUNT"] > 0).sum()
        green = len(h) - red
        c1, c2, c3 = st.columns(3)
        c1.metric("Total DMFs",          len(h))
        c2.metric("Healthy",              green)
        c3.metric("With violations",      red, delta=None if red == 0 else f"{red}")

        def _row_style(row: pd.Series) -> list[str]:
            color = "background-color: #fdecea" if (row["VIOLATION_COUNT"] or 0) > 0 else "background-color: #e8f5e9"
            return [color] * len(row)

        st.dataframe(h.style.apply(_row_style, axis=1), use_container_width=True)


# ---------------------------------------------------------------------------
# Tab 6 — CISO Audit (policies + tags + Cortex history + feedback log)
# ---------------------------------------------------------------------------

with tab_ciso:
    st.subheader("CISO audit — governance follows the data")
    st.caption(
        "Everything Cortex does is a SQL call. So the same controls — row "
        "access policies, masking, tags, ACCESS_HISTORY — apply to the AI "
        "path. This tab proves it from one screen."
    )

    sec_a, sec_b, sec_c = st.tabs(
        ["Policies & Tags", "Cortex query history", "RAG feedback log"]
    )

    with sec_a:
        c1, c2 = st.columns(2)

        with c1:
            st.markdown("**Policy inventory** — every RAP and masking policy applied")
            try:
                pi = run_sql(f"SELECT * FROM {DB}.GOLD.V_CISO_POLICY_INVENTORY ORDER BY kind, policy")
                st.dataframe(pi, use_container_width=True, height=320)
            except Exception as exc:
                st.warning(f"Cannot read POLICY_REFERENCES (ACCOUNTADMIN only?): {exc}")

            st.markdown("**Active BU membership** — what each demo user can see")
            try:
                bu = run_sql(f"SELECT * FROM {DB}.SILVER.BU_MEMBERSHIP ORDER BY user_name")
                st.dataframe(bu, use_container_width=True, height=200)
            except Exception as exc:
                st.warning(f"Could not read BU membership: {exc}")

        with c2:
            st.markdown("**Tag inventory** — Horizon Catalog sensitivity tags")
            try:
                ti = run_sql(f"SELECT * FROM {DB}.GOLD.V_CISO_TAG_INVENTORY ORDER BY tag, tag_value")
                st.dataframe(ti, use_container_width=True, height=320)
            except Exception as exc:
                st.warning(f"Cannot read TAG_REFERENCES (ACCOUNTADMIN only?): {exc}")

            st.markdown("**Current session**")
            who = run_sql("SELECT CURRENT_USER() AS user_name, CURRENT_ROLE() AS role_name, CURRENT_WAREHOUSE() AS wh")
            st.dataframe(who, use_container_width=True)

        st.info(
            "**Demo move:** switch role to `ONT_DEMO_CONSUMER_ROLE` and "
            "re-login as `SAP_ANALYST`. Re-ask the same Graph RAG question. "
            "The subgraph shrinks to SAP-only triples — automatically."
        )

    with sec_b:
        st.markdown("**Cortex query history** (last 100) — every AI call is a tracked SQL statement")
        try:
            qh = run_sql(f"SELECT * FROM {DB}.GOLD.V_CISO_CORTEX_CALLS LIMIT 100")
            st.dataframe(qh, use_container_width=True, height=520)
        except Exception as exc:
            st.warning(
                "ACCOUNT_USAGE.QUERY_HISTORY is ACCOUNTADMIN-readable. "
                "Switch role to view, or wait for the ~45-min latency on a "
                f"fresh account.\n\n{exc}"
            )

    with sec_c:
        st.markdown("**RAG feedback log** — full prompt, model, citations, thumbs")
        try:
            fb = run_sql(
                f"""
                SELECT asked_at, user_name, role_name, model, latency_ms,
                       guarded, thumbs,
                       LEFT(question, 100) AS question_preview,
                       LEFT(answer,   200) AS answer_preview,
                       ARRAY_SIZE(citations) AS n_citations
                FROM {DB}.SILVER.RAG_FEEDBACK
                ORDER BY asked_at DESC
                LIMIT 200
                """
            )
            st.dataframe(fb, use_container_width=True, height=400)
        except Exception as exc:
            st.info(f"No RAG feedback yet (or table not created). Ask something in Graph RAG.\n\n{exc}")

        st.markdown("**Daily KPI roll-up**")
        try:
            kpi = run_sql(f"SELECT * FROM {DB}.GOLD.V_RAG_FEEDBACK_SUMMARY LIMIT 30")
            st.dataframe(kpi, use_container_width=True)
        except Exception as exc:
            st.info(f"Summary view unavailable yet: {exc}")


# ---------------------------------------------------------------------------
# Tab 7 — Browse
# ---------------------------------------------------------------------------

with tab_browse:
    st.subheader("Browse the generated Gold views")
    if not source:
        st.info("Select a source system in the sidebar.")
    else:
        st.caption(
            f"Each class in **{source_label(source)}** is projected into a wide "
            "`GOLD.V_<SOURCE>_<CLASS>` view by 06_gold_views.sql."
        )
        classes = get_classes(source)
        classes = classes[classes["N"] > 0]
        if classes.empty:
            st.info(f"No {source_label(source)} individuals loaded yet.")
        else:
            cls_labels = {
                f"{r.LABEL or r.CLASS_IRI} ({int(r.N):,})": r.CLASS_IRI
                for r in classes.itertuples()
            }
            pick = st.selectbox("Class", list(cls_labels.keys()))
            class_iri = cls_labels[pick]
            view = gold_view(source, class_iri)

            search = st.text_input(
                "Filter (matches label / name)", placeholder="optional substring"
            ).strip()

            where = ""
            params: tuple = ()
            if search:
                where = "WHERE label ILIKE ? OR name ILIKE ?"
                params = (f"%{search}%", f"%{search}%")

            try:
                df = run_sql(
                    f"SELECT * FROM {view} {where} LIMIT 1000", params
                )
                st.caption(f"`{view}` — showing up to 1000 rows.")
                st.dataframe(df, use_container_width=True, height=550)
            except Exception as exc:
                st.warning(
                    f"Could not read {view}. Run 06_gold_views.sql for this "
                    f"source first.\n\n({exc})"
                )


# ---------------------------------------------------------------------------
# Tab 8 — Search (Cortex Search)
# ---------------------------------------------------------------------------

with tab_search:
    st.subheader("Semantic search across all individuals")
    st.caption(
        "Cortex Search service `NODE_SEARCH_SVC` (lexical + semantic) ranks "
        "node labels and address text together."
    )
    q = st.text_input("Search", placeholder='e.g. an entity name, location, or code')
    k = st.slider("Results", 5, 50, 15)
    if q:
        try:
            # Cortex Search is queried from SQL via SEARCH_PREVIEW, which returns
            # a JSON document {"results":[...]}. (The service!QUERY() table form
            # only exists in the REST / Python APIs, not in SQL.)
            payload = json.dumps({
                "query": q,
                "columns": ["node_uid", "class_iri", "search_text"],
                "limit": int(k),
            })
            raw = run_sql(
                f"SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW('{SEARCH_SERVICE}', ?) AS r",
                (payload,),
            ).iloc[0, 0]
            results = (json.loads(raw) if isinstance(raw, str) else raw).get("results", [])
            df = pd.DataFrame([
                {
                    "node_uid": r.get("node_uid"),
                    "class_iri": r.get("class_iri"),
                    "search_text": r.get("search_text"),
                    "score": round((r.get("@scores") or {}).get("reranker_score", 0.0), 4),
                }
                for r in results
            ])
            if df.empty:
                st.info("No matches.")
            else:
                st.dataframe(df, use_container_width=True)
        except Exception as exc:
            st.warning(
                "Cortex Search service not available; falling back to LIKE on the node DT.\n\n"
                f"({exc})"
            )
            df = run_sql(
                f"""
                SELECT node_uid, class_iri, name, label
                FROM {DB}.SILVER.node
                WHERE name ILIKE ? OR label ILIKE ?
                LIMIT ?
                """,
                (f"%{q}%", f"%{q}%", k),
            )
            st.dataframe(df, use_container_width=True)


# ---------------------------------------------------------------------------
# Tab 9 — Explore (recursive walk)
# ---------------------------------------------------------------------------

with tab_explore:
    st.subheader("N-hop explorer (recursive CTE walk)")
    st.caption(
        "Pick a starting individual and a set of predicates. The query walks "
        "the property-graph projection (`silver.edge`, predicate-clustered) "
        "up to `max_depth` hops, with cycle protection."
    )

    pred_options = get_predicates(source) if source else []
    col1, col2, col3 = st.columns([2, 2, 1])
    start_uid = col1.text_input("Start individual UID", value="")
    predicates = col2.multiselect(
        "Predicates to walk",
        pred_options,
        default=pred_options[:3],
    )
    max_depth = col3.slider("Max depth", 1, 6, 3)
    if source and not pred_options:
        st.info(f"No object properties defined for {source_label(source)}.")

    if start_uid and predicates:
        sql = f"""
            WITH RECURSIVE walk AS (
                SELECT src_uid, predicate_iri, dst_uid, 1 AS depth,
                       ARRAY_CONSTRUCT(src_uid, dst_uid) AS path
                FROM {DB}.SILVER.edge
                WHERE src_uid = ?
                  AND predicate_iri IN ({",".join(f"'{p}'" for p in predicates)})
                UNION ALL
                SELECT e.src_uid, e.predicate_iri, e.dst_uid, w.depth + 1,
                       ARRAY_APPEND(w.path, e.dst_uid)
                FROM {DB}.SILVER.edge e
                JOIN walk w ON e.src_uid = w.dst_uid
                WHERE e.predicate_iri IN ({",".join(f"'{p}'" for p in predicates)})
                  AND w.depth < {max_depth}
                  AND NOT ARRAY_CONTAINS(e.dst_uid::variant, w.path)
            )
            SELECT w.depth, w.src_uid, w.predicate_iri, w.dst_uid,
                   i.label     AS dst_label,
                   i.class_iri AS dst_class
            FROM walk w
            LEFT JOIN {DB}.SILVER.individual i ON i.individual_uid = w.dst_uid
            ORDER BY w.depth, w.src_uid
            LIMIT 500
        """
        try:
            df = run_sql(sql, (start_uid,))
            st.metric("Edges in walk", len(df))
            st.dataframe(df, use_container_width=True, height=550)
        except Exception as exc:  # pragma: no cover
            st.error(f"Walk failed: {exc}")
