"""
Page 6: Knowledge Graph
Interactive visualization of the Ontology Knowledge Graph powered by RAI.
Explore nodes, edges, governance scores, and RAI-generated recommendations.
"""

import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="Knowledge Graph | DCA Demo", layout="wide")
session = get_active_session()

# ── Data Loaders ─────────────────────────────────────────────────────────


@st.cache_data(ttl=30)
def get_nodes(layer_filter: str, source_systems: list, node_types: list, score_threshold: float) -> pd.DataFrame:
    """Load graph nodes with applied filters."""
    query = """
        SELECT n.node_id, n.node_type, n.layer, n.source_system,
               n.fqn, n.display_name, n.properties, n.created_at
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
        WHERE 1=1
    """
    if layer_filter != "ALL":
        query += f" AND n.layer = '{layer_filter}'"
    if source_systems:
        systems_str = ",".join(f"'{s}'" for s in source_systems)
        query += f" AND n.source_system IN ({systems_str})"
    if node_types:
        types_str = ",".join(f"'{t}'" for t in node_types)
        query += f" AND n.node_type IN ({types_str})"
    if score_threshold > 0:
        query += f"""
            AND n.node_id IN (
                SELECT node_id FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES
                WHERE overall_score >= {score_threshold}
            )
        """
    query += " LIMIT 200"
    return session.sql(query).to_pandas()


@st.cache_data(ttl=30)
def get_edges(node_ids: list) -> pd.DataFrame:
    """Load edges for the given set of node IDs."""
    if not node_ids:
        return pd.DataFrame()
    ids_str = ",".join(f"'{n}'" for n in node_ids)
    return session.sql(f"""
        SELECT edge_id, source_node_id, target_node_id, edge_type, layer, weight
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
        WHERE source_node_id IN ({ids_str})
           OR target_node_id IN ({ids_str})
    """).to_pandas()


@st.cache_data(ttl=30)
def get_node_types() -> list:
    """Get distinct node types for filtering."""
    df = session.sql("""
        SELECT DISTINCT node_type
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        ORDER BY node_type
    """).to_pandas()
    return df["NODE_TYPE"].tolist() if not df.empty else []


@st.cache_data(ttl=30)
def get_governance_scores() -> pd.DataFrame:
    """Load governance scores joined with node display names."""
    return session.sql("""
        SELECT s.node_id, n.display_name, n.node_type, n.source_system,
               s.overall_score, s.tag_coverage, s.contract_coverage,
               s.ownership_score, s.quality_score, s.scored_at
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES s
        LEFT JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
            ON s.node_id = n.node_id
        ORDER BY s.overall_score ASC
    """).to_pandas()


@st.cache_data(ttl=30)
def get_recommendations() -> pd.DataFrame:
    """Load open RAI recommendations."""
    return session.sql("""
        SELECT recommendation_id, recommendation_type, severity,
               source_node_id, target_node_id, description,
               suggested_action, status, created_at
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS
        WHERE status = 'OPEN'
        ORDER BY
            CASE severity WHEN 'HIGH' THEN 1 WHEN 'MEDIUM' THEN 2 ELSE 3 END,
            created_at DESC
    """).to_pandas()


@st.cache_data(ttl=30)
def get_snapshot_info() -> pd.DataFrame:
    """Load latest graph snapshot info."""
    return session.sql("""
        SELECT snapshot_time, node_count, edge_count
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SNAPSHOTS
        ORDER BY snapshot_id DESC
        LIMIT 1
    """).to_pandas()


# ── Sidebar Filters ──────────────────────────────────────────────────────

st.sidebar.header("Graph Filters")

layer_filter = st.sidebar.radio(
    "Layer",
    options=["ALL", "METADATA", "BUSINESS"],
    index=0
)

source_systems = st.sidebar.multiselect(
    "Source Systems",
    options=["SNOWFLAKE", "SAP", "ORACLE", "SALESFORCE", "FHIR", "WORKDAY", "SERVICENOW"],
    default=[]
)

available_types = get_node_types()
node_type_filter = st.sidebar.multiselect(
    "Node Types",
    options=available_types,
    default=[]
)

score_threshold = st.sidebar.slider(
    "Min Governance Score",
    min_value=0.0,
    max_value=1.0,
    value=0.0,
    step=0.05
)

# ── Page Header ──────────────────────────────────────────────────────────

st.title("Ontology Knowledge Graph")
st.caption("Interactive explorer for cross-system metadata and business entity relationships")

# ── Main Content Tabs ────────────────────────────────────────────────────

tab_graph, tab_scores, tab_recs = st.tabs(["Graph Explorer", "Governance Scores", "RAI Recommendations"])

# ── Tab 1: Graph Explorer ────────────────────────────────────────────────

with tab_graph:
    nodes_df = get_nodes(layer_filter, source_systems, node_type_filter, score_threshold)

    if nodes_df.empty:
        st.info("No graph data found. Run the graph population procedure (SP_REFRESH_GRAPH) to populate nodes and edges.")
    else:
        if len(nodes_df) >= 200:
            st.warning("Showing first 200 nodes. Apply filters to narrow the view.")

        node_ids = nodes_df["NODE_ID"].tolist()
        edges_df = get_edges(node_ids)

        # Compute node degrees for sizing
        degree_map = {}
        if not edges_df.empty:
            for _, edge in edges_df.iterrows():
                src = edge["SOURCE_NODE_ID"]
                tgt = edge["TARGET_NODE_ID"]
                degree_map[src] = degree_map.get(src, 0) + 1
                degree_map[tgt] = degree_map.get(tgt, 0) + 1

        # Color mapping by layer
        layer_colors = {"METADATA": "#1f77b4", "BUSINESS": "#2ca02c", "CROSS": "#9467bd"}
        source_colors = {
            "SNOWFLAKE": "#29B5E8", "SAP": "#F0AB00", "ORACLE": "#C74634",
            "SALESFORCE": "#00A1E0", "FHIR": "#E84E35", "WORKDAY": "#005CB9",
            "SERVICENOW": "#81B5A1"
        }

        try:
            from streamlit_agraph import agraph, Node, Edge, Config

            agraph_nodes = []
            for _, row in nodes_df.iterrows():
                nid = row["NODE_ID"]
                degree = degree_map.get(nid, 1)
                size = min(10 + degree * 3, 50)
                color = layer_colors.get(row["LAYER"], "#7f7f7f")
                agraph_nodes.append(Node(
                    id=nid,
                    label=row["DISPLAY_NAME"][:25],
                    size=size,
                    color=color,
                    title=f"{row['NODE_TYPE']} | {row['SOURCE_SYSTEM']}\n{row['DISPLAY_NAME']}"
                ))

            agraph_edges = []
            if not edges_df.empty:
                # Only include edges where both endpoints are in the current node set
                node_id_set = set(node_ids)
                for _, edge in edges_df.iterrows():
                    if edge["SOURCE_NODE_ID"] in node_id_set and edge["TARGET_NODE_ID"] in node_id_set:
                        agraph_edges.append(Edge(
                            source=edge["SOURCE_NODE_ID"],
                            target=edge["TARGET_NODE_ID"],
                            label=edge["EDGE_TYPE"],
                            type="CURVE_SMOOTH"
                        ))

            config = Config(
                width=1200,
                height=600,
                directed=True,
                physics=True,
                hierarchical=False,
                nodeHighlightBehavior=True,
                highlightColor="#F7A7A6",
                collapsible=True
            )

            selected_node = agraph(
                nodes=agraph_nodes,
                edges=agraph_edges,
                config=config
            )

            # Show node details on selection
            if selected_node:
                with st.expander(f"Node Details: {selected_node}", expanded=True):
                    node_row = nodes_df[nodes_df["NODE_ID"] == selected_node]
                    if not node_row.empty:
                        row = node_row.iloc[0]
                        col1, col2, col3 = st.columns(3)
                        col1.metric("Type", row["NODE_TYPE"])
                        col2.metric("Layer", row["LAYER"])
                        col3.metric("Source", row["SOURCE_SYSTEM"])
                        if row["FQN"]:
                            st.code(row["FQN"], language="text")
                        if row["PROPERTIES"]:
                            st.json(row["PROPERTIES"])

        except ImportError:
            st.warning("Install `streamlit-agraph` for interactive graph visualization. Showing tabular view instead.")
            st.subheader("Nodes")
            st.dataframe(nodes_df[["NODE_ID", "DISPLAY_NAME", "NODE_TYPE", "LAYER", "SOURCE_SYSTEM"]], use_container_width=True)
            if not edges_df.empty:
                st.subheader("Edges")
                st.dataframe(edges_df[["SOURCE_NODE_ID", "TARGET_NODE_ID", "EDGE_TYPE", "LAYER"]], use_container_width=True)

# ── Tab 2: Governance Scores ─────────────────────────────────────────────

with tab_scores:
    scores_df = get_governance_scores()

    if scores_df.empty:
        st.info("No governance scores available. Run SP_RUN_INFERENCE() to compute scores.")
    else:
        # Summary metrics
        avg_score = scores_df["OVERALL_SCORE"].mean()
        above_threshold = len(scores_df[scores_df["OVERALL_SCORE"] >= score_threshold]) if score_threshold > 0 else len(scores_df[scores_df["OVERALL_SCORE"] >= 0.7])
        pct_above = round(above_threshold / len(scores_df) * 100) if len(scores_df) > 0 else 0
        worst_5 = scores_df.nsmallest(5, "OVERALL_SCORE")

        col1, col2, col3 = st.columns(3)
        col1.metric("Average Score", f"{avg_score:.2f}")
        col2.metric("% Nodes Above Threshold", f"{pct_above}%")
        col3.metric("Total Scored Nodes", len(scores_df))

        st.subheader("Worst 5 Nodes")
        st.dataframe(
            worst_5[["DISPLAY_NAME", "NODE_TYPE", "OVERALL_SCORE", "TAG_COVERAGE", "CONTRACT_COVERAGE", "OWNERSHIP_SCORE", "QUALITY_SCORE"]],
            use_container_width=True
        )

        # Color-coded score table
        st.subheader("All Governance Scores")

        def score_color(val):
            """Color scores: red < 0.4, yellow 0.4-0.7, green > 0.7."""
            if pd.isna(val):
                return ""
            if val < 0.4:
                return "background-color: #ffcccc"
            elif val < 0.7:
                return "background-color: #fff3cd"
            else:
                return "background-color: #d4edda"

        score_cols = ["OVERALL_SCORE", "TAG_COVERAGE", "CONTRACT_COVERAGE", "OWNERSHIP_SCORE", "QUALITY_SCORE"]
        styled_df = scores_df[["DISPLAY_NAME", "NODE_TYPE", "SOURCE_SYSTEM"] + score_cols].style.applymap(
            score_color, subset=score_cols
        )
        st.dataframe(styled_df, use_container_width=True)

        # Heatmap
        st.subheader("Score Distribution")
        fig = px.histogram(
            scores_df, x="OVERALL_SCORE", nbins=20,
            color_discrete_sequence=["#1f77b4"],
            labels={"OVERALL_SCORE": "Overall Governance Score"}
        )
        fig.add_vline(x=0.4, line_dash="dash", line_color="red", annotation_text="Critical")
        fig.add_vline(x=0.7, line_dash="dash", line_color="orange", annotation_text="Warning")
        fig.update_layout(height=300)
        st.plotly_chart(fig, use_container_width=True)

# ── Tab 3: RAI Recommendations ──────────────────────────────────────────

with tab_recs:
    recs_df = get_recommendations()

    if recs_df.empty:
        st.info("No open recommendations. Run SP_RUN_INFERENCE() to generate recommendations.")
    else:
        # Metric cards by type
        type_counts = recs_df["RECOMMENDATION_TYPE"].value_counts()
        cols = st.columns(min(len(type_counts), 4))
        for i, (rec_type, count) in enumerate(type_counts.items()):
            cols[i % len(cols)].metric(rec_type.replace("_", " ").title(), count)

        # Severity badges
        severity_colors = {"HIGH": "red", "MEDIUM": "orange", "LOW": "yellow"}

        st.subheader("Recommendations by Type")
        for rec_type in recs_df["RECOMMENDATION_TYPE"].unique():
            with st.expander(f"{rec_type} ({len(recs_df[recs_df['RECOMMENDATION_TYPE'] == rec_type])})", expanded=True):
                type_df = recs_df[recs_df["RECOMMENDATION_TYPE"] == rec_type].copy()
                type_df["SEVERITY_BADGE"] = type_df["SEVERITY"].apply(
                    lambda s: f":{severity_colors.get(s, 'gray')}[{s}]"
                )
                st.dataframe(
                    type_df[["SEVERITY", "DESCRIPTION", "SUGGESTED_ACTION", "SOURCE_NODE_ID", "TARGET_NODE_ID", "CREATED_AT"]],
                    use_container_width=True,
                    column_config={
                        "SEVERITY": st.column_config.TextColumn("Severity", width="small"),
                        "DESCRIPTION": st.column_config.TextColumn("Description", width="large"),
                        "SUGGESTED_ACTION": st.column_config.TextColumn("Suggested Action", width="medium"),
                    }
                )

# ── Footer: Snapshot Info ────────────────────────────────────────────────

st.divider()
snapshot_df = get_snapshot_info()
if not snapshot_df.empty:
    snap = snapshot_df.iloc[0]
    col1, col2, col3 = st.columns(3)
    col1.caption(f"Last Refresh: {snap['SNAPSHOT_TIME']}")
    col2.caption(f"Total Nodes: {snap['NODE_COUNT']:,}")
    col3.caption(f"Total Edges: {snap['EDGE_COUNT']:,}")
else:
    st.caption("Graph has not been populated yet. Run SP_REFRESH_GRAPH() to initialize.")
