"""
Page 8: DCIM Command Center
Interactive operations dashboard for data center infrastructure management.
Four views: Live Infrastructure Graph, SCD6 Time-Slider, Observability Heatmap,
and Dispatch Recommendations.
"""

import streamlit as st
import pandas as pd
from datetime import datetime, timedelta

st.set_page_config(page_title="DCIM Command Center", page_icon="\U0001f3d7\ufe0f", layout="wide")

# ── Signal Definitions (Ontological Intelligence Layer) ───────────────────

SIGNAL_DEFINITIONS = {
    "nodes": {
        "DATA_CENTER": (
            "Physical facility housing IT infrastructure. Classified by Uptime Institute tier "
            "(I-IV) determining redundancy requirements and SLA guarantees. Tier-4 facilities "
            "guarantee 99.995% uptime ($17K/minute downtime cost)."
        ),
        "HALL": (
            "Subdivision of a data center floor, typically aligned with cooling zones. "
            "Each hall has independent CRAC/CRAH units and power distribution. Hall-level "
            "isolation enables maintenance without full-DC impact."
        ),
        "RACK": (
            "42U standard equipment cabinet housing switches, servers, and patch panels. "
            "Power draw monitored per-rack for capacity planning. Position within hall "
            "determines cooling efficiency and cable run lengths."
        ),
        "SWITCH": (
            "Network switching equipment (L2/L3) providing connectivity to servers and "
            "uplinks. Primary subject of health monitoring, risk scoring, and dispatch. "
            "Firmware version and model determine required certification for service."
        ),
        "INCIDENT": (
            "ServiceNow ITSM incident record indicating equipment failure or degradation. "
            "Priority levels P1-P4 determine SLA response times. MTTR tracked from creation "
            "to resolution. Assigned technician must hold valid certification."
        ),
        "TECHNICIAN": (
            "Field engineer from Workday HCM with certifications, campus assignment, and "
            "shift schedule. Dispatch scoring evaluates campus proximity, certification match, "
            "shift status, and proficiency level for optimal assignment."
        ),
        "CERTIFICATION": (
            "Vendor or industry certification held by a technician (e.g., Cisco CCNP, Juniper "
            "JNCIS, CompTIA Network+). Status can be ACTIVE, EXPIRING_SOON, or EXPIRED. "
            "Equipment service requires matching active certification."
        ),
        "TEAM": (
            "Organizational unit grouping technicians by campus and specialty. Teams have "
            "managers, coverage schedules, and escalation paths. Team capacity affects "
            "MTTR when incidents exceed individual technician availability."
        ),
    },
    "metrics": {
        "Risk Score": (
            "Composite score (0-100) combining telemetry error rate (40%), certification "
            "gap severity (30%), and SLA tier business impact (30%). Scores above 75 indicate "
            "HIGH risk requiring immediate qualified dispatch."
        ),
        "Dispatch Score": (
            "Candidate ranking (0-100) for technician assignment. Weights: campus proximity "
            "(35%), certification match (25%), on-shift status (25%), proficiency level (15%). "
            "Highest-scoring candidate is the optimal dispatch choice."
        ),
        "MTTR (Minutes)": (
            "Mean Time To Repair from incident creation to resolution. Varies by priority "
            "(P1: target 30min, P2: 2hr, P3: 8hr, P4: 24hr) and data center staffing levels. "
            "Strong inverse correlation with staff availability percentage."
        ),
        "Error Rate (%)": (
            "Percentage of packets with errors on switch ports over a 5-minute interval. "
            "Normal: <0.1%, Elevated: 0.5-2%, Problem: 2-8%. Degrading switches show "
            "progressive increase over 7 days before failure."
        ),
        "Health Score": (
            "Port-level health composite: 100 minus weighted penalty for error rate, "
            "packet loss, and utilization saturation. Aggregated to switch level as average "
            "across all active ports."
        ),
    },
}


# ── Sample Data for Demo/Fallback Mode ────────────────────────────────────

SAMPLE_RISK_SCORES = pd.DataFrame([
    {"switch_name": "SW-CORE-NYC-001", "data_center": "NYC-DC1", "error_rate_pct": 5.2,
     "technician_name": "James Rodriguez", "cert_status": "EXPIRED", "risk_level": "HIGH",
     "risk_score": 89, "sla_tier": "CRITICAL", "business_impact": "Revenue-impacting"},
    {"switch_name": "SW-DIST-NYC-014", "data_center": "NYC-DC1", "error_rate_pct": 3.1,
     "technician_name": "Sarah Chen", "cert_status": "EXPIRING_SOON", "risk_level": "HIGH",
     "risk_score": 78, "sla_tier": "HIGH", "business_impact": "Customer-facing"},
    {"switch_name": "SW-CORE-LON-003", "data_center": "LON-DC2", "error_rate_pct": 1.8,
     "technician_name": "Ahmed Hassan", "cert_status": "ACTIVE", "risk_level": "MEDIUM",
     "risk_score": 52, "sla_tier": "HIGH", "business_impact": "Customer-facing"},
    {"switch_name": "SW-ACCESS-SFO-007", "data_center": "SFO-DC3", "error_rate_pct": 0.9,
     "technician_name": "Maria Santos", "cert_status": "ACTIVE", "risk_level": "LOW",
     "risk_score": 31, "sla_tier": "MEDIUM", "business_impact": "Internal"},
    {"switch_name": "SW-DIST-TKY-002", "data_center": "TKY-DC4", "error_rate_pct": 0.3,
     "technician_name": "Yuki Tanaka", "cert_status": "ACTIVE", "risk_level": "NOMINAL",
     "risk_score": 15, "sla_tier": "LOW", "business_impact": "Non-critical"},
])

SAMPLE_DISPATCH = pd.DataFrame([
    {"switch_id": "sw-001", "incident_id": "INC-4421", "tech_name": "Ahmed Hassan",
     "campus_match": True, "cert_type": "Cisco CCNP", "cert_status": "ACTIVE",
     "proficiency_level": "Expert", "on_shift": True, "dispatch_score": 94,
     "reasoning": "Same campus, active CCNP, on-shift, expert proficiency"},
    {"switch_id": "sw-001", "incident_id": "INC-4421", "tech_name": "Sarah Chen",
     "campus_match": True, "cert_type": "Cisco CCNP", "cert_status": "EXPIRING_SOON",
     "proficiency_level": "Advanced", "on_shift": True, "dispatch_score": 78,
     "reasoning": "Same campus, cert expiring in 14 days, on-shift, advanced proficiency"},
    {"switch_id": "sw-001", "incident_id": "INC-4421", "tech_name": "James Rodriguez",
     "campus_match": False, "cert_type": "Cisco CCNP", "cert_status": "ACTIVE",
     "proficiency_level": "Expert", "on_shift": False, "dispatch_score": 45,
     "reasoning": "Cross-campus (45min travel), active cert, off-shift, expert proficiency"},
    {"switch_id": "sw-014", "incident_id": "INC-4435", "tech_name": "Maria Santos",
     "campus_match": True, "cert_type": "Juniper JNCIS", "cert_status": "ACTIVE",
     "proficiency_level": "Advanced", "on_shift": True, "dispatch_score": 87,
     "reasoning": "Same campus, active JNCIS, on-shift, advanced proficiency"},
])

SAMPLE_MTTR = pd.DataFrame([
    {"dc_name": "NYC-DC1", "priority": "P1", "avg_mttr_minutes": 42, "median_mttr_minutes": 35,
     "p95_mttr_minutes": 95, "incidents_count": 145, "staff_available_pct": 72.0},
    {"dc_name": "NYC-DC1", "priority": "P2", "avg_mttr_minutes": 128, "median_mttr_minutes": 110,
     "p95_mttr_minutes": 280, "incidents_count": 320, "staff_available_pct": 72.0},
    {"dc_name": "LON-DC2", "priority": "P1", "avg_mttr_minutes": 38, "median_mttr_minutes": 30,
     "p95_mttr_minutes": 82, "incidents_count": 98, "staff_available_pct": 85.0},
    {"dc_name": "LON-DC2", "priority": "P2", "avg_mttr_minutes": 105, "median_mttr_minutes": 90,
     "p95_mttr_minutes": 220, "incidents_count": 210, "staff_available_pct": 85.0},
    {"dc_name": "SFO-DC3", "priority": "P1", "avg_mttr_minutes": 55, "median_mttr_minutes": 48,
     "p95_mttr_minutes": 120, "incidents_count": 67, "staff_available_pct": 60.0},
    {"dc_name": "TKY-DC4", "priority": "P1", "avg_mttr_minutes": 31, "median_mttr_minutes": 25,
     "p95_mttr_minutes": 70, "incidents_count": 52, "staff_available_pct": 92.0},
])

SAMPLE_HISTORICAL = pd.DataFrame([
    {"entity_type": "SWITCH", "entity_name": "SW-CORE-NYC-001", "changes_since_original": 3,
     "current_rack": "RACK-A12", "historical_rack": "RACK-B07", "original_rack": "RACK-B07",
     "current_firmware": "16.12.4", "historical_firmware": "16.11.2", "original_firmware": "16.9.1",
     "last_change_date": "2025-01-10"},
    {"entity_type": "SWITCH", "entity_name": "SW-DIST-NYC-014", "changes_since_original": 2,
     "current_rack": "RACK-C03", "historical_rack": "RACK-A09", "original_rack": "RACK-A09",
     "current_firmware": "15.8.3", "historical_firmware": "15.7.1", "original_firmware": "15.5.0",
     "last_change_date": "2025-01-08"},
    {"entity_type": "RACK", "entity_name": "RACK-A12", "changes_since_original": 1,
     "current_rack": "HALL-N2", "historical_rack": "HALL-N1", "original_rack": "HALL-N1",
     "current_firmware": "N/A", "historical_firmware": "N/A", "original_firmware": "N/A",
     "last_change_date": "2025-01-09"},
])

SAMPLE_INFRASTRUCTURE = pd.DataFrame([
    {"node_type": "DATA_CENTER", "display_name": "NYC-DC1", "source_system": "SERVICENOW",
     "risk_level": "HIGH", "child_count": 5},
    {"node_type": "DATA_CENTER", "display_name": "LON-DC2", "source_system": "SERVICENOW",
     "risk_level": "MEDIUM", "child_count": 4},
    {"node_type": "DATA_CENTER", "display_name": "SFO-DC3", "source_system": "SERVICENOW",
     "risk_level": "LOW", "child_count": 3},
    {"node_type": "DATA_CENTER", "display_name": "TKY-DC4", "source_system": "SERVICENOW",
     "risk_level": "NOMINAL", "child_count": 4},
])


# ── Data Loading ──────────────────────────────────────────────────────────

def _get_session():
    """Get Snowflake session, return None if unavailable."""
    try:
        from snowflake.snowpark.context import get_active_session
        return get_active_session()
    except Exception:
        return None


@st.cache_data(ttl=60)
def load_risk_scores() -> pd.DataFrame:
    """Load current risk scores for all monitored switches."""
    session = _get_session()
    if session is None:
        return pd.DataFrame()
    try:
        return session.sql("""
            SELECT switch_id, switch_name, data_center, rack_id,
                   error_rate_pct, assigned_technician_id, technician_name,
                   cert_status, cert_expiry_date, risk_level, risk_score,
                   sla_tier, business_impact, calculated_at
            FROM DCA_DEMO.GOVERNANCE.DCIM_RISK_SCORES
            ORDER BY risk_score DESC
        """).to_pandas()
    except Exception:
        return pd.DataFrame()


@st.cache_data(ttl=60)
def load_dispatch_recommendations() -> pd.DataFrame:
    """Load dispatch recommendations for open incidents."""
    session = _get_session()
    if session is None:
        return pd.DataFrame()
    try:
        return session.sql("""
            SELECT recommendation_id, switch_id, incident_id,
                   recommended_technician_id, tech_name,
                   campus_match, cert_type, cert_status, proficiency_level,
                   on_shift, dispatch_score, reasoning, created_at
            FROM DCA_DEMO.GOVERNANCE.DCIM_DISPATCH_RECOMMENDATIONS
            ORDER BY dispatch_score DESC
        """).to_pandas()
    except Exception:
        return pd.DataFrame()


@st.cache_data(ttl=60)
def load_mttr_metrics() -> pd.DataFrame:
    """Load MTTR analysis by data center and priority."""
    session = _get_session()
    if session is None:
        return pd.DataFrame()
    try:
        return session.sql("""
            SELECT data_center_id, dc_name, priority,
                   avg_mttr_minutes, median_mttr_minutes, p95_mttr_minutes,
                   incidents_count, staff_available_pct, calculated_at
            FROM DCA_DEMO.GOVERNANCE.DCIM_MTTR_METRICS
            ORDER BY avg_mttr_minutes DESC
        """).to_pandas()
    except Exception:
        return pd.DataFrame()


@st.cache_data(ttl=60)
def load_historical_snapshots() -> pd.DataFrame:
    """Load SCD6 historical snapshots."""
    session = _get_session()
    if session is None:
        return pd.DataFrame()
    try:
        return session.sql("""
            SELECT snapshot_id, snapshot_timestamp, entity_type, entity_id,
                   entity_name, current_state, historical_state, original_state,
                   changes_since_original, last_change_date, created_at
            FROM DCA_DEMO.GOVERNANCE.DCIM_HISTORICAL_SNAPSHOTS
            ORDER BY changes_since_original DESC
        """).to_pandas()
    except Exception:
        return pd.DataFrame()


@st.cache_data(ttl=60)
def load_infrastructure_nodes() -> pd.DataFrame:
    """Load infrastructure graph nodes with hierarchy."""
    session = _get_session()
    if session is None:
        return pd.DataFrame()
    try:
        return session.sql("""
            SELECT n.node_id, n.node_type, n.display_name, n.source_system,
                   n.properties
            FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
            WHERE n.source_system IN ('SERVICENOW', 'WORKDAY', 'NETWORK_OBSERVABILITY')
              AND n.node_type IN ('DATA_CENTER', 'HALL', 'RACK', 'SWITCH',
                                  'TECHNICIAN', 'CERTIFICATION', 'TEAM', 'INCIDENT')
            ORDER BY n.node_type, n.display_name
        """).to_pandas()
    except Exception:
        return pd.DataFrame()


@st.cache_data(ttl=60)
def load_port_health_view() -> pd.DataFrame:
    """Load port health by business priority semantic view."""
    session = _get_session()
    if session is None:
        return pd.DataFrame()
    try:
        return session.sql("""
            SELECT *
            FROM CURATED_DEV.TELEMETRY.DCIM_PORT_HEALTH_BY_BUSINESS_PRIORITY
            ORDER BY 1
        """).to_pandas()
    except Exception:
        return pd.DataFrame()


@st.cache_data(ttl=60)
def load_snapshot_info() -> pd.DataFrame:
    """Load latest graph snapshot timestamp."""
    session = _get_session()
    if session is None:
        return pd.DataFrame()
    try:
        return session.sql("""
            SELECT snapshot_time, node_count, edge_count
            FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SNAPSHOTS
            ORDER BY snapshot_id DESC
            LIMIT 1
        """).to_pandas()
    except Exception:
        return pd.DataFrame()


# ── Determine Data Source ─────────────────────────────────────────────────

def get_risk_data() -> tuple:
    """Return (risk_df, is_demo_mode)."""
    sf_data = load_risk_scores()
    if sf_data.empty:
        return SAMPLE_RISK_SCORES.copy(), True
    sf_data.columns = [c.lower() for c in sf_data.columns]
    return sf_data, False


def get_dispatch_data() -> tuple:
    """Return (dispatch_df, is_demo_mode)."""
    sf_data = load_dispatch_recommendations()
    if sf_data.empty:
        return SAMPLE_DISPATCH.copy(), True
    sf_data.columns = [c.lower() for c in sf_data.columns]
    return sf_data, False


def get_mttr_data() -> tuple:
    """Return (mttr_df, is_demo_mode)."""
    sf_data = load_mttr_metrics()
    if sf_data.empty:
        return SAMPLE_MTTR.copy(), True
    sf_data.columns = [c.lower() for c in sf_data.columns]
    return sf_data, False


def get_historical_data() -> tuple:
    """Return (historical_df, is_demo_mode)."""
    sf_data = load_historical_snapshots()
    if sf_data.empty:
        return SAMPLE_HISTORICAL.copy(), True
    sf_data.columns = [c.lower() for c in sf_data.columns]
    return sf_data, False


def get_infrastructure_data() -> tuple:
    """Return (nodes_df, is_demo_mode)."""
    sf_data = load_infrastructure_nodes()
    if sf_data.empty:
        return SAMPLE_INFRASTRUCTURE.copy(), True
    sf_data.columns = [c.lower() for c in sf_data.columns]
    return sf_data, False


# ── Color/Style Helpers ───────────────────────────────────────────────────

RISK_COLORS = {
    "HIGH": "#E74C3C",
    "MEDIUM": "#F39C12",
    "LOW": "#27AE60",
    "NOMINAL": "#3498DB",
}

RISK_BADGES = {
    "HIGH": "\U0001f534 HIGH",
    "MEDIUM": "\U0001f7e0 MEDIUM",
    "LOW": "\U0001f7e2 LOW",
    "NOMINAL": "\U0001f535 NOMINAL",
}


def risk_badge(level: str) -> str:
    """Return colored risk badge string."""
    return RISK_BADGES.get(level, level)


# ── Page Header ───────────────────────────────────────────────────────────

st.title("\U0001f3d7\ufe0f DCIM Command Center")
st.caption(
    "Unified operations dashboard — ServiceNow CMDB, Workday HCM, and Network Observability "
    "integrated through the Ontology Knowledge Graph."
)

# Check demo mode
risk_df, is_demo = get_risk_data()
if is_demo:
    st.info(
        "\U0001f4cb **Demo Mode** — Showing sample data. Connect to Snowflake and deploy "
        "DCIM scripts (01-10) to see live operational data.",
        icon="\u2139\ufe0f",
    )

# ── KPI Summary Row ──────────────────────────────────────────────────────

col1, col2, col3, col4, col5 = st.columns(5)

high_count = len(risk_df[risk_df["risk_level"] == "HIGH"]) if not risk_df.empty else 0
medium_count = len(risk_df[risk_df["risk_level"] == "MEDIUM"]) if not risk_df.empty else 0
total_switches = len(risk_df) if not risk_df.empty else 0
avg_score = risk_df["risk_score"].mean() if not risk_df.empty else 0

dispatch_df, _ = get_dispatch_data()
dispatch_count = dispatch_df["incident_id"].nunique() if not dispatch_df.empty else 0

col1.metric("Total Monitored", f"{total_switches} switches")
col2.metric("\U0001f534 HIGH Risk", f"{high_count}")
col3.metric("\U0001f7e0 MEDIUM Risk", f"{medium_count}")
col4.metric("Avg Risk Score", f"{avg_score:.0f}/100")
col5.metric("Active Dispatches", f"{dispatch_count}")

st.divider()

# ── Tabs ──────────────────────────────────────────────────────────────────

tab1, tab2, tab3, tab4 = st.tabs([
    "\U0001f310 Live Infrastructure",
    "\u23f3 SCD6 Time-Slider",
    "\U0001f4ca Observability Heatmap",
    "\U0001f6e0\ufe0f Dispatch Recommendations",
])


# ── TAB 1: Live Infrastructure Graph ─────────────────────────────────────

with tab1:
    st.subheader("Infrastructure Hierarchy with Risk Overlay")

    infra_df, infra_demo = get_infrastructure_data()

    # Sidebar-style filters in columns
    filter_col1, filter_col2 = st.columns(2)
    with filter_col1:
        if not infra_demo and "node_type" in infra_df.columns:
            available_types = sorted(infra_df["node_type"].unique().tolist())
        else:
            available_types = ["DATA_CENTER", "HALL", "RACK", "SWITCH", "TECHNICIAN"]
        type_filter = st.multiselect(
            "Filter by Node Type", available_types,
            default=["DATA_CENTER", "SWITCH"],
            key="infra_type_filter",
        )
    with filter_col2:
        risk_filter = st.multiselect(
            "Filter by Risk Level",
            ["HIGH", "MEDIUM", "LOW", "NOMINAL"],
            default=["HIGH", "MEDIUM"],
            key="infra_risk_filter",
        )

    # Display infrastructure hierarchy
    if not risk_df.empty and risk_filter:
        filtered_risk = risk_df[risk_df["risk_level"].isin(risk_filter)]

        if not filtered_risk.empty:
            # Group by data center
            for dc_name in sorted(filtered_risk["data_center"].unique()):
                dc_switches = filtered_risk[filtered_risk["data_center"] == dc_name]
                dc_risk = dc_switches["risk_level"].value_counts().to_dict()

                badge_str = " | ".join(
                    f"{risk_badge(level)}: {count}"
                    for level, count in dc_risk.items()
                )
                with st.expander(f"\U0001f3e2 **{dc_name}** — {badge_str}", expanded=(high_count > 0)):
                    st.dataframe(
                        dc_switches[[
                            "switch_name", "risk_level", "risk_score",
                            "error_rate_pct", "technician_name", "cert_status",
                            "sla_tier", "business_impact",
                        ]].sort_values("risk_score", ascending=False),
                        use_container_width=True,
                        hide_index=True,
                        column_config={
                            "switch_name": st.column_config.TextColumn("Switch"),
                            "risk_level": st.column_config.TextColumn("Risk"),
                            "risk_score": st.column_config.ProgressColumn(
                                "Score", min_value=0, max_value=100, format="%d"
                            ),
                            "error_rate_pct": st.column_config.NumberColumn(
                                "Error %", format="%.1f%%"
                            ),
                            "technician_name": st.column_config.TextColumn("Assigned Tech"),
                            "cert_status": st.column_config.TextColumn("Cert Status"),
                            "sla_tier": st.column_config.TextColumn("SLA Tier"),
                            "business_impact": st.column_config.TextColumn("Impact"),
                        },
                    )
        else:
            st.info("No switches match the selected risk filters.")
    elif risk_df.empty:
        st.info("No risk score data available. Run SP_DCIM_MASTER_ORCHESTRATOR() to generate.")

    # Signal definitions expander
    with st.expander("\U0001f4d6 Node Type Definitions"):
        for node_type, definition in SIGNAL_DEFINITIONS["nodes"].items():
            st.markdown(f"**{node_type}**: {definition}")


# ── TAB 2: SCD6 Time-Slider ──────────────────────────────────────────────

with tab2:
    st.subheader("SCD Type 6 — Point-in-Time State Reconstruction")

    st.markdown(
        "Reconstruct the exact state of any infrastructure entity at any past timestamp. "
        "SCD6 preserves current, historical, and original state columns for full audit trail."
    )

    # Time selection
    time_col1, time_col2, time_col3 = st.columns(3)
    with time_col1:
        selected_date = st.date_input(
            "Select Date",
            value=datetime.now().date() - timedelta(days=3),
            max_value=datetime.now().date(),
            key="scd6_date",
        )
    with time_col2:
        selected_time = st.time_input(
            "Select Time",
            value=datetime.strptime("12:00", "%H:%M").time(),
            key="scd6_time",
        )
    with time_col3:
        entity_type_filter = st.selectbox(
            "Entity Type",
            ["ALL", "SWITCH", "RACK", "DATA_CENTER"],
            key="scd6_entity_type",
        )

    historical_df, hist_demo = get_historical_data()

    if not historical_df.empty:
        # Filter by entity type
        if entity_type_filter != "ALL":
            display_df = historical_df[historical_df["entity_type"] == entity_type_filter]
        else:
            display_df = historical_df

        if not display_df.empty:
            # Summary metrics
            m_col1, m_col2, m_col3 = st.columns(3)
            m_col1.metric("Entities with Changes", len(display_df))
            m_col2.metric(
                "Max Changes (single entity)",
                int(display_df["changes_since_original"].max()),
            )
            m_col3.metric(
                "Entity Types Tracked",
                display_df["entity_type"].nunique(),
            )

            st.divider()

            # Before/After comparison
            st.markdown("#### State Comparison")

            for _, row in display_df.head(10).iterrows():
                with st.expander(
                    f"\U0001f504 **{row['entity_name']}** ({row['entity_type']}) "
                    f"— {row['changes_since_original']} change(s)",
                    expanded=False,
                ):
                    comp_col1, comp_col2, comp_col3 = st.columns(3)

                    with comp_col1:
                        st.markdown("**\U0001f7e2 Current State**")
                        if "current_rack" in row.index:
                            st.code(f"Rack: {row.get('current_rack', 'N/A')}\n"
                                    f"Firmware: {row.get('current_firmware', 'N/A')}")
                        elif "current_state" in row.index:
                            st.json(row["current_state"] if isinstance(row["current_state"], dict)
                                    else {"state": str(row["current_state"])})

                    with comp_col2:
                        st.markdown("**\U0001f7e1 Historical State**")
                        if "historical_rack" in row.index:
                            st.code(f"Rack: {row.get('historical_rack', 'N/A')}\n"
                                    f"Firmware: {row.get('historical_firmware', 'N/A')}")
                        elif "historical_state" in row.index:
                            st.json(row["historical_state"] if isinstance(row["historical_state"], dict)
                                    else {"state": str(row["historical_state"])})

                    with comp_col3:
                        st.markdown("**\u26aa Original State**")
                        if "original_rack" in row.index:
                            st.code(f"Rack: {row.get('original_rack', 'N/A')}\n"
                                    f"Firmware: {row.get('original_firmware', 'N/A')}")
                        elif "original_state" in row.index:
                            st.json(row["original_state"] if isinstance(row["original_state"], dict)
                                    else {"state": str(row["original_state"])})

                    if "last_change_date" in row.index:
                        st.caption(f"Last changed: {row['last_change_date']}")
        else:
            st.info(f"No historical changes found for entity type: {entity_type_filter}")
    else:
        st.info(
            "No historical snapshot data available. "
            "Run SP_DCIM_TIME_TRAVEL() to generate point-in-time snapshots."
        )

    # Explanation
    with st.expander("\U0001f4d6 How SCD Type 6 Works"):
        st.markdown("""
**SCD Type 6** combines three approaches into a single pattern:

| Column | Purpose | Behavior |
|--------|---------|----------|
| `current_*` | Present-day value | Overwritten on each change (Type 1) |
| `historical_*` | Previous value | Stores the value before the last change (Type 3) |
| `original_*` | First-ever value | Never changes after initial load (immutable) |
| `_VALID_FROM` | When current state started | Updated on each change (Type 2 temporal) |
| `_VALID_TO` | When current state ended | NULL = still active |

This enables: "What was the rack assignment of switch X on January 8th at 3 PM?"
without any external CDC tooling or log analysis.
        """)


# ── TAB 3: Observability Heatmap ─────────────────────────────────────────

with tab3:
    st.subheader("Port Health by Business Priority")

    # Load semantic view data
    port_health_df = load_port_health_view()

    if port_health_df.empty:
        # Use risk data as a proxy heatmap
        st.markdown("#### Switch Health Summary (from Risk Scores)")

        if not risk_df.empty:
            # Summary metrics
            h_col1, h_col2, h_col3, h_col4 = st.columns(4)
            healthy_pct = len(risk_df[risk_df["risk_level"].isin(["NOMINAL", "LOW"])]) / len(risk_df) * 100
            degraded_pct = len(risk_df[risk_df["risk_level"] == "MEDIUM"]) / len(risk_df) * 100
            critical_pct = len(risk_df[risk_df["risk_level"] == "HIGH"]) / len(risk_df) * 100

            h_col1.metric("Total Switches", len(risk_df))
            h_col2.metric("\U0001f7e2 Healthy", f"{healthy_pct:.0f}%")
            h_col3.metric("\U0001f7e1 Degraded", f"{degraded_pct:.0f}%")
            h_col4.metric("\U0001f534 Critical", f"{critical_pct:.0f}%")

            st.divider()

            # Filter controls
            hm_col1, hm_col2 = st.columns(2)
            with hm_col1:
                dc_options = sorted(risk_df["data_center"].unique().tolist())
                dc_filter = st.multiselect(
                    "Filter by Data Center", dc_options,
                    default=dc_options,
                    key="heatmap_dc_filter",
                )
            with hm_col2:
                sla_options = sorted(risk_df["sla_tier"].unique().tolist())
                sla_filter = st.multiselect(
                    "Filter by SLA Tier", sla_options,
                    default=sla_options,
                    key="heatmap_sla_filter",
                )

            # Filtered view
            hm_filtered = risk_df[
                risk_df["data_center"].isin(dc_filter) &
                risk_df["sla_tier"].isin(sla_filter)
            ]

            if not hm_filtered.empty:
                # Heatmap-style table
                st.dataframe(
                    hm_filtered[[
                        "data_center", "switch_name", "sla_tier",
                        "error_rate_pct", "risk_score", "risk_level",
                        "cert_status", "business_impact",
                    ]].sort_values(["data_center", "risk_score"], ascending=[True, False]),
                    use_container_width=True,
                    hide_index=True,
                    column_config={
                        "data_center": st.column_config.TextColumn("Data Center"),
                        "switch_name": st.column_config.TextColumn("Switch"),
                        "sla_tier": st.column_config.TextColumn("SLA Tier"),
                        "error_rate_pct": st.column_config.NumberColumn(
                            "Error Rate", format="%.2f%%"
                        ),
                        "risk_score": st.column_config.ProgressColumn(
                            "Risk Score", min_value=0, max_value=100, format="%d"
                        ),
                        "risk_level": st.column_config.TextColumn("Risk Level"),
                        "cert_status": st.column_config.TextColumn("Cert Status"),
                        "business_impact": st.column_config.TextColumn("Business Impact"),
                    },
                )

                # Per-DC summary
                st.markdown("#### Per-Data Center Summary")
                dc_summary = hm_filtered.groupby("data_center").agg(
                    switches=("switch_name", "count"),
                    avg_risk=("risk_score", "mean"),
                    avg_error_rate=("error_rate_pct", "mean"),
                    high_risk_count=("risk_level", lambda x: (x == "HIGH").sum()),
                ).reset_index()

                st.dataframe(
                    dc_summary,
                    use_container_width=True,
                    hide_index=True,
                    column_config={
                        "data_center": st.column_config.TextColumn("Data Center"),
                        "switches": st.column_config.NumberColumn("Switches"),
                        "avg_risk": st.column_config.ProgressColumn(
                            "Avg Risk", min_value=0, max_value=100, format="%.0f"
                        ),
                        "avg_error_rate": st.column_config.NumberColumn(
                            "Avg Error %", format="%.2f%%"
                        ),
                        "high_risk_count": st.column_config.NumberColumn("HIGH Risk"),
                    },
                )
            else:
                st.info("No switches match the selected filters.")
        else:
            st.info("No observability data available. Deploy DCIM scripts and run the orchestrator.")
    else:
        # Live semantic view data
        port_health_df.columns = [c.lower() for c in port_health_df.columns]
        st.dataframe(port_health_df, use_container_width=True, hide_index=True)

    # Metric definitions
    with st.expander("\U0001f4d6 Metric Definitions"):
        for metric, definition in SIGNAL_DEFINITIONS["metrics"].items():
            st.markdown(f"**{metric}**: {definition}")


# ── TAB 4: Dispatch Recommendations ──────────────────────────────────────

with tab4:
    st.subheader("Intelligent Dispatch — Nearest Qualified Technician")

    st.markdown(
        "Graph-powered dispatch evaluates every candidate technician against four dimensions: "
        "**campus proximity** (35%), **certification match** (25%), **on-shift status** (25%), "
        "and **proficiency level** (15%)."
    )

    dispatch_df, disp_demo = get_dispatch_data()

    if not dispatch_df.empty:
        # Summary
        d_col1, d_col2, d_col3 = st.columns(3)
        incidents_needing_dispatch = dispatch_df["incident_id"].nunique()
        avg_top_score = dispatch_df.groupby("incident_id")["dispatch_score"].max().mean()
        on_shift_available = dispatch_df[dispatch_df["on_shift"] == True]["tech_name"].nunique()

        d_col1.metric("Incidents Needing Dispatch", incidents_needing_dispatch)
        d_col2.metric("Avg Top Candidate Score", f"{avg_top_score:.0f}/100")
        d_col3.metric("Technicians On-Shift", on_shift_available)

        st.divider()

        # Filter controls
        disp_col1, disp_col2 = st.columns(2)
        with disp_col1:
            min_score = st.slider(
                "Minimum Dispatch Score",
                min_value=0, max_value=100, value=50,
                key="dispatch_min_score",
            )
        with disp_col2:
            show_off_shift = st.checkbox("Include Off-Shift Candidates", value=False, key="dispatch_off_shift")

        # Filter
        filtered_dispatch = dispatch_df[dispatch_df["dispatch_score"] >= min_score]
        if not show_off_shift:
            filtered_dispatch = filtered_dispatch[filtered_dispatch["on_shift"] == True]

        if not filtered_dispatch.empty:
            # Group by incident
            for incident_id in sorted(filtered_dispatch["incident_id"].unique()):
                inc_candidates = filtered_dispatch[filtered_dispatch["incident_id"] == incident_id]
                top_candidate = inc_candidates.iloc[0]

                with st.expander(
                    f"\U0001f6a8 **{incident_id}** — Top: {top_candidate['tech_name']} "
                    f"(Score: {top_candidate['dispatch_score']})",
                    expanded=True,
                ):
                    # Recommended technician card
                    st.markdown(f"**\u2705 Recommended**: {top_candidate['tech_name']}")
                    rec_col1, rec_col2, rec_col3, rec_col4 = st.columns(4)
                    rec_col1.metric(
                        "Campus Match",
                        "\u2705 Yes" if top_candidate["campus_match"] else "\u274c No",
                    )
                    rec_col2.metric("Cert Status", top_candidate["cert_status"])
                    rec_col3.metric(
                        "On Shift",
                        "\u2705 Yes" if top_candidate["on_shift"] else "\u274c No",
                    )
                    rec_col4.metric("Proficiency", top_candidate["proficiency_level"])

                    st.caption(f"\U0001f4ac Reasoning: {top_candidate['reasoning']}")

                    # All candidates table
                    if len(inc_candidates) > 1:
                        st.markdown("**All Candidates:**")
                        st.dataframe(
                            inc_candidates[[
                                "tech_name", "campus_match", "cert_status",
                                "on_shift", "proficiency_level", "dispatch_score",
                            ]].sort_values("dispatch_score", ascending=False),
                            use_container_width=True,
                            hide_index=True,
                            column_config={
                                "tech_name": st.column_config.TextColumn("Technician"),
                                "campus_match": st.column_config.CheckboxColumn("Campus Match"),
                                "cert_status": st.column_config.TextColumn("Cert Status"),
                                "on_shift": st.column_config.CheckboxColumn("On Shift"),
                                "proficiency_level": st.column_config.TextColumn("Proficiency"),
                                "dispatch_score": st.column_config.ProgressColumn(
                                    "Score", min_value=0, max_value=100, format="%d"
                                ),
                            },
                        )
        else:
            st.info(
                "No dispatch candidates match the current filters. "
                "Try lowering the minimum score or including off-shift candidates."
            )
    else:
        st.info(
            "No dispatch recommendations available. "
            "Run SP_DCIM_NEAREST_QUALIFIED_TECH() to generate recommendations."
        )


# ── Footer ────────────────────────────────────────────────────────────────

st.divider()

# Snapshot info
snapshot_df = load_snapshot_info()
if not snapshot_df.empty:
    snap = snapshot_df.iloc[0]
    st.caption(
        f"Graph snapshot: {snap.get('SNAPSHOT_TIME', snap.get('snapshot_time', 'N/A'))} | "
        f"Nodes: {snap.get('NODE_COUNT', snap.get('node_count', 'N/A'))} | "
        f"Edges: {snap.get('EDGE_COUNT', snap.get('edge_count', 'N/A'))}"
    )
elif is_demo:
    st.caption("Demo mode — sample data shown. Deploy DCIM scripts for live operational intelligence.")

# MTTR sidebar context
with st.sidebar:
    st.markdown("### \U0001f4c8 MTTR Overview")
    mttr_df, _ = get_mttr_data()
    if not mttr_df.empty:
        for _, row in mttr_df.head(6).iterrows():
            dc = row.get("dc_name", "Unknown")
            pri = row.get("priority", "?")
            avg = row.get("avg_mttr_minutes", 0)
            staff = row.get("staff_available_pct", 0)
            st.markdown(f"**{dc}** ({pri}): {avg:.0f} min avg | {staff:.0f}% staff")
    else:
        st.caption("MTTR data unavailable")

    st.divider()
    st.markdown("### \U0001f4d6 Quick Reference")
    st.markdown("""
    - **Risk Score**: 0-100 composite (error + cert + SLA)
    - **Dispatch Score**: 0-100 candidate ranking
    - **SCD6**: Current / Historical / Original states
    - **MTTR**: Mean Time To Repair (minutes)
    """)
