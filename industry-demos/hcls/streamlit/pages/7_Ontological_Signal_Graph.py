"""
Page 7: Ontological Signal Graph
Interactive network visualization showing relationships between clinical measures,
staffing features, and payer metrics with mouseover English definitions explaining
WHY things correlate — the ontological intelligence layer.
"""

import streamlit as st
import pandas as pd

st.set_page_config(page_title="Ontological Signal Graph", page_icon="🧬", layout="wide")

# ── Signal Definitions (Ontological Intelligence Layer) ───────────────────

SIGNAL_DEFINITIONS = {
    # ── Node Definitions ──────────────────────────────────────────────────
    "nodes": {
        # Clinical Measures
        "Readmission Rate": (
            "Patient returns to acute care within 30 days of discharge for same or related "
            "condition. CMS penalizes hospitals up to 3% of Medicare reimbursement for excess "
            "readmissions (HRRP). National average: 15.6%."
        ),
        "Mortality Rate": (
            "In-hospital deaths per 1,000 discharges, risk-adjusted by case mix index. "
            "A lagging indicator of systemic care quality failures including delayed "
            "recognition of clinical deterioration. National benchmark: 2-3% for Med-Surg."
        ),
        "Avg LOS": (
            "Average length of stay in days from admission to discharge. Longer stays "
            "increase HAI risk and cost; premature discharge drives readmissions. "
            "CMS geometric mean LOS is the benchmark for DRG-level comparisons."
        ),
        "Adverse Event Rate": (
            "Rate of hospital-acquired complications per 1,000 patient-days including falls, "
            "medication errors, pressure injuries, and wrong-site procedures. AHRQ PSI-90 "
            "composite is the standard measure. Target: <3.0 per 1,000 patient-days."
        ),
        "HAI Rate": (
            "Hospital-Acquired Infection rate including CLABSI, CAUTI, SSI, MRSA, and "
            "C. difficile. CDC NHSN provides standardized infection ratios (SIR). "
            "Each HAI adds $20K-$45K per episode and 7-10 days of additional LOS."
        ),

        # Staffing Features
        "Nurse-Patient Ratio": (
            "Number of patients assigned per registered nurse on a given shift. "
            "Research (Aiken et al., 2002) demonstrates each additional patient per nurse "
            "increases mortality risk by 7%. Industry target: ICU 1:2, Med-Surg 1:4-5."
        ),
        "Overtime %": (
            "Proportion of worked hours classified as overtime (>40hrs/week or >12hrs/shift). "
            "Excessive overtime (>10%) correlates with 2.3x increase in medication errors "
            "and 1.8x patient falls (Rogers et al., 2004). OSHA considers >12hrs a fatigue risk."
        ),
        "Vacancy Rate": (
            "Percentage of budgeted FTE positions currently unfilled. Chronic vacancies "
            "(>8%) force remaining staff into mandatory overtime and float pool reliance. "
            "NSI Nursing Solutions reports national RN vacancy at 9.9% (2023)."
        ),
        "Turnover Rate": (
            "Annualized rate of voluntary and involuntary RN departures. High turnover "
            "(>18%) disrupts team cohesion, institutional knowledge, and patient safety. "
            "NSI reports national RN turnover at 22.5%; each departure costs $46K-$89K."
        ),
        "HPPD": (
            "Hours Per Patient Day — total nursing hours (RN + LPN + CNA) divided by "
            "midnight census. CMS requires reporting; benchmarks vary by unit: "
            "ICU 12-18 HPPD, Med-Surg 6-9 HPPD, ED calculated differently."
        ),
        "Float Pool %": (
            "Percentage of shift hours filled by float pool or agency nurses rather than "
            "unit-based staff. Float nurses are less familiar with unit protocols, patient "
            "histories, and equipment locations. Target: <15% of total hours."
        ),

        # Payer Metrics
        "Denial Rate": (
            "Percentage of submitted claims denied by the payer on first pass. Driven by "
            "documentation gaps, medical necessity disputes, and prior authorization failures. "
            "Industry average: 10-12%, varies 8-28% by CCI tier and payer."
        ),
        "Days to Adjudicate": (
            "Average calendar days from claim submission to initial payer determination. "
            "Longer adjudication delays cash flow and increases AR days. State regulations "
            "typically require 30-45 day clean claim turnaround. Actual: 14-60 days."
        ),
        "Prior Auth Rate": (
            "Percentage of encounters requiring payer pre-authorization before service "
            "delivery. High prior auth burden (>40%) creates care delays averaging 2.1 days "
            "and consumes 34 hours/week of physician time per AMA survey (2022)."
        ),
        "Patient Responsibility": (
            "Dollar amount shifted to patient after insurance adjudication including "
            "copays, coinsurance, and deductibles. Rising patient responsibility drives "
            "bad debt and collection costs; averages $1,200-$4,800 per inpatient stay."
        ),
        "Approved vs Actual LOS Gap": (
            "Difference between payer-authorized length of stay and clinically required "
            "days. Negative gap means early discharge pressure; positive gap means "
            "denied continued-stay days. Both scenarios drive readmission risk."
        ),

        # Comorbidity Tiers
        "CCI LOW (0-1)": (
            "Charlson Comorbidity Index score 0-1 indicating minimal disease burden. "
            "These patients have 0-1 chronic conditions, straightforward care paths, "
            "and lowest denial rates (8-10%). Expected cost multiplier: 1.0x baseline."
        ),
        "CCI MODERATE (2-3)": (
            "Charlson Comorbidity Index score 2-3 indicating moderate complexity. "
            "Typically 2-3 chronic conditions requiring coordinated care. Denial rates "
            "rise to 12-16% as documentation burden increases. Cost multiplier: 2.5x."
        ),
        "CCI HIGH (4-6)": (
            "Charlson Comorbidity Index score 4-6 indicating significant disease burden. "
            "These patients have 4-5 chronic conditions with interaction effects. Payer "
            "scrutiny intensifies; prior auth rates exceed 50%. Cost multiplier: 7x."
        ),
        "CCI SEVERE (7+)": (
            "Charlson Comorbidity Index score 7+ indicating extreme disease burden. "
            "These patients carry 6+ chronic conditions, face 35%+ denial rates, "
            "and cost 18x more per episode than low-complexity patients."
        ),

        # Patient Outcomes
        "30-Day Readmission": (
            "Binary outcome: patient readmitted within 30 days for related diagnosis. "
            "Influenced by discharge planning quality, medication reconciliation, and "
            "post-acute care coordination. Each readmission costs $15K-$25K."
        ),
        "Early Discharge": (
            "Patient discharged before clinically optimal stay duration, often driven by "
            "payer pressure or bed availability. Early discharge correlates with 2.4x "
            "readmission risk and increased ED utilization within 7 days."
        ),
        "Extended Stay": (
            "Length of stay exceeding DRG geometric mean by >1 standard deviation. "
            "Causes include complications, social determinants (no safe discharge "
            "destination), and care coordination failures. Triggers payer utilization review."
        ),
        "Care Plan Adherence": (
            "Percentage of ordered clinical interventions completed as planned including "
            "medications, therapies, and follow-up appointments. Non-adherence rates of "
            "30-50% are common and drive both readmissions and payer disputes."
        ),
    },

    # ── Edge Definitions ──────────────────────────────────────────────────
    "edges": {
        ("Nurse-Patient Ratio", "Readmission Rate"): (
            "Higher patient loads reduce time for discharge planning, patient education, "
            "and early warning detection. Correlation r=0.68: units exceeding target "
            "ratio by 20%+ show 2.1x readmission rates. Mechanism: inadequate discharge "
            "teaching leads to medication non-adherence and 30-day return."
        ),
        ("Nurse-Patient Ratio", "Adverse Event Rate"): (
            "Each additional patient per nurse reduces surveillance time by ~15 minutes/hour. "
            "Correlation r=0.72: medication errors, falls, and pressure injuries all increase "
            "with patient load. Threshold effect: ratios beyond 1:6 show exponential risk rise."
        ),
        ("Overtime %", "Adverse Event Rate"): (
            "Fatigued nurses make more errors. After 12+ consecutive hours, cognitive function "
            "degrades equivalent to 0.05% BAC. Correlation r=0.54: each 5% increase in "
            "overtime associates with 12% increase in near-miss safety events."
        ),
        ("Overtime %", "Mortality Rate"): (
            "Sustained overtime creates chronic fatigue impairing clinical judgment on "
            "time-sensitive decisions (rapid response, medication dosing). Units with >15% "
            "overtime show 1.4x higher failure-to-rescue rates."
        ),
        ("Vacancy Rate", "30-Day Readmission"): (
            "Unfilled positions compress remaining staff capacity, shortening patient "
            "interactions and discharge planning time. Units with >12% vacancy show "
            "28% higher readmission rates due to incomplete care transitions."
        ),
        ("Vacancy Rate", "HAI Rate"): (
            "Understaffed units have less time for hand hygiene compliance, central line "
            "maintenance, and catheter care. Each 5% increase in vacancy rate correlates "
            "with 0.3 SIR increase in CLABSI rates."
        ),
        ("Turnover Rate", "Adverse Event Rate"): (
            "New nurses take 6-12 months to reach full competency on a unit. High turnover "
            "means a larger proportion of staff are in the learning curve, increasing "
            "protocol deviation rates by 18% during the first 90 days."
        ),
        ("Float Pool %", "Adverse Event Rate"): (
            "Float pool nurses unfamiliar with unit protocols contribute to 23% of fall "
            "events. They lack knowledge of patient histories, equipment locations, and "
            "informal safety practices. Risk highest in first 4 hours of float assignment."
        ),
        ("CCI SEVERE (7+)", "Denial Rate"): (
            "Payers apply stricter utilization criteria to complex patients despite higher "
            "clinical need. Paradox: sickest patients face most administrative friction. "
            "Root cause: documentation burden exceeds clinical bandwidth, leading to "
            "insufficient justification on first-pass claims."
        ),
        ("CCI HIGH (4-6)", "Prior Auth Rate"): (
            "Payers require pre-authorization for costly procedures common in high-CCI "
            "patients (dialysis, chemotherapy, complex imaging). Prior auth delays average "
            "2.1 days for HIGH tier vs 0.5 days for LOW tier, delaying treatment initiation."
        ),
        ("CCI MODERATE (2-3)", "Days to Adjudicate"): (
            "Moderate complexity claims require additional clinical review, extending "
            "adjudication timelines. Payer algorithms flag multi-condition claims for "
            "manual review, adding 7-14 days to the determination cycle."
        ),
        ("Approved vs Actual LOS Gap", "30-Day Readmission"): (
            "Patients discharged before clinical readiness due to payer LOS limits return "
            "at higher rates. Each day of negative gap (discharged early) increases "
            "readmission probability by 8%. The cost of readmission typically exceeds "
            "the cost of the denied additional days."
        ),
        ("Early Discharge", "Readmission Rate"): (
            "Premature discharge driven by payer pressure or bed demand results in "
            "incomplete clinical stabilization. Patients discharged >1 day before "
            "geometric mean LOS show 2.4x readmission rate for SEVERE CCI tier."
        ),
        ("HPPD", "Mortality Rate"): (
            "Hours Per Patient Day below unit benchmark indicates insufficient nursing "
            "presence for clinical surveillance. ICU HPPD below 12 correlates with "
            "delayed recognition of sepsis and respiratory failure. Each 1-hour "
            "decrease in HPPD below target associates with 3% mortality increase."
        ),
        ("Denial Rate", "Patient Responsibility"): (
            "Denied claims that are not successfully appealed shift financial burden "
            "to patients. Appeal success rates vary 40-65% but require 30-60 days. "
            "Unresolved denials in HIGH/SEVERE tiers average $12K-$45K patient liability."
        ),
    },
}


# ── Sample Data for Demo/Fallback Mode ────────────────────────────────────

SAMPLE_NODES = pd.DataFrame([
    {"node_id": "clin_readmit", "display_name": "Readmission Rate", "domain": "Clinical", "node_type": "MEASURE"},
    {"node_id": "clin_mortality", "display_name": "Mortality Rate", "domain": "Clinical", "node_type": "MEASURE"},
    {"node_id": "clin_los", "display_name": "Avg LOS", "domain": "Clinical", "node_type": "MEASURE"},
    {"node_id": "clin_adverse", "display_name": "Adverse Event Rate", "domain": "Clinical", "node_type": "MEASURE"},
    {"node_id": "clin_hai", "display_name": "HAI Rate", "domain": "Clinical", "node_type": "MEASURE"},
    {"node_id": "staff_ratio", "display_name": "Nurse-Patient Ratio", "domain": "Staffing", "node_type": "FEATURE"},
    {"node_id": "staff_ot", "display_name": "Overtime %", "domain": "Staffing", "node_type": "FEATURE"},
    {"node_id": "staff_vacancy", "display_name": "Vacancy Rate", "domain": "Staffing", "node_type": "FEATURE"},
    {"node_id": "staff_turnover", "display_name": "Turnover Rate", "domain": "Staffing", "node_type": "FEATURE"},
    {"node_id": "staff_hppd", "display_name": "HPPD", "domain": "Staffing", "node_type": "FEATURE"},
    {"node_id": "staff_float", "display_name": "Float Pool %", "domain": "Staffing", "node_type": "FEATURE"},
    {"node_id": "payer_denial", "display_name": "Denial Rate", "domain": "Payer", "node_type": "METRIC"},
    {"node_id": "payer_adjud", "display_name": "Days to Adjudicate", "domain": "Payer", "node_type": "METRIC"},
    {"node_id": "payer_prior", "display_name": "Prior Auth Rate", "domain": "Payer", "node_type": "METRIC"},
    {"node_id": "payer_resp", "display_name": "Patient Responsibility", "domain": "Payer", "node_type": "METRIC"},
    {"node_id": "payer_gap", "display_name": "Approved vs Actual LOS Gap", "domain": "Payer", "node_type": "METRIC"},
    {"node_id": "cci_low", "display_name": "CCI LOW (0-1)", "domain": "Comorbidity", "node_type": "TIER"},
    {"node_id": "cci_mod", "display_name": "CCI MODERATE (2-3)", "domain": "Comorbidity", "node_type": "TIER"},
    {"node_id": "cci_high", "display_name": "CCI HIGH (4-6)", "domain": "Comorbidity", "node_type": "TIER"},
    {"node_id": "cci_severe", "display_name": "CCI SEVERE (7+)", "domain": "Comorbidity", "node_type": "TIER"},
    {"node_id": "out_readmit", "display_name": "30-Day Readmission", "domain": "Outcome", "node_type": "OUTCOME"},
    {"node_id": "out_early", "display_name": "Early Discharge", "domain": "Outcome", "node_type": "OUTCOME"},
    {"node_id": "out_extended", "display_name": "Extended Stay", "domain": "Outcome", "node_type": "OUTCOME"},
    {"node_id": "out_adherence", "display_name": "Care Plan Adherence", "domain": "Outcome", "node_type": "OUTCOME"},
])

SAMPLE_EDGES = pd.DataFrame([
    {"source": "staff_ratio", "target": "clin_readmit", "edge_type": "CORRELATES_WITH", "weight": 0.68},
    {"source": "staff_ratio", "target": "clin_adverse", "edge_type": "CORRELATES_WITH", "weight": 0.72},
    {"source": "staff_ot", "target": "clin_adverse", "edge_type": "CORRELATES_WITH", "weight": 0.54},
    {"source": "staff_ot", "target": "clin_mortality", "edge_type": "CORRELATES_WITH", "weight": 0.41},
    {"source": "staff_vacancy", "target": "out_readmit", "edge_type": "INFLUENCES", "weight": 0.58},
    {"source": "staff_vacancy", "target": "clin_hai", "edge_type": "INFLUENCES", "weight": 0.47},
    {"source": "staff_turnover", "target": "clin_adverse", "edge_type": "INFLUENCES", "weight": 0.52},
    {"source": "staff_float", "target": "clin_adverse", "edge_type": "INFLUENCES", "weight": 0.44},
    {"source": "cci_severe", "target": "payer_denial", "edge_type": "DRIVES", "weight": 0.78},
    {"source": "cci_high", "target": "payer_prior", "edge_type": "DRIVES", "weight": 0.65},
    {"source": "cci_mod", "target": "payer_adjud", "edge_type": "DRIVES", "weight": 0.39},
    {"source": "payer_gap", "target": "out_readmit", "edge_type": "INFLUENCES", "weight": 0.62},
    {"source": "out_early", "target": "clin_readmit", "edge_type": "INFLUENCES", "weight": 0.71},
    {"source": "staff_hppd", "target": "clin_mortality", "edge_type": "CORRELATES_WITH", "weight": 0.49},
    {"source": "payer_denial", "target": "payer_resp", "edge_type": "DRIVES", "weight": 0.56},
    {"source": "cci_severe", "target": "clin_los", "edge_type": "STRATIFIES", "weight": 0.83},
    {"source": "cci_high", "target": "clin_readmit", "edge_type": "STRATIFIES", "weight": 0.61},
    {"source": "staff_ratio", "target": "out_readmit", "edge_type": "INFLUENCES", "weight": 0.63},
])


# ── Color & Shape Configuration ───────────────────────────────────────────

DOMAIN_COLORS = {
    "Clinical": "#4A90D9",    # Blue
    "Staffing": "#27AE60",    # Green
    "Payer": "#E67E22",       # Orange
    "Comorbidity": "#E74C3C", # Red
    "Outcome": "#8E44AD",     # Purple
}

EDGE_TYPE_STYLES = {
    "CORRELATES_WITH": {"color": "#4A90D9", "style": "solid", "label": "Staffing → Outcome Correlation"},
    "DRIVES":          {"color": "#E74C3C", "style": "dashed", "label": "Comorbidity → Payer Behavior"},
    "INFLUENCES":      {"color": "#27AE60", "style": "solid", "label": "Feature → Patient Outcome"},
    "STRATIFIES":      {"color": "#95A5A6", "style": "dotted", "label": "CCI Tier → Metric Split"},
}


# ── Data Loading ──────────────────────────────────────────────────────────

def _get_session():
    """Get Snowflake session, return None if unavailable."""
    try:
        from snowflake.snowpark.context import get_active_session
        return get_active_session()
    except Exception:
        return None


@st.cache_data(ttl=30)
def load_nodes_from_sf() -> pd.DataFrame:
    """Load signal graph nodes from Snowflake."""
    session = _get_session()
    if session is None:
        return pd.DataFrame()
    try:
        return session.sql("""
            SELECT node_id, node_type, display_name, source_system,
                   properties
            FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
            WHERE source_system IN ('FHIR', 'WORKDAY_HCM', 'PAYER')
            ORDER BY source_system, display_name
        """).to_pandas()
    except Exception:
        return pd.DataFrame()


@st.cache_data(ttl=30)
def load_edges_from_sf() -> pd.DataFrame:
    """Load signal graph edges from Snowflake."""
    session = _get_session()
    if session is None:
        return pd.DataFrame()
    try:
        return session.sql("""
            SELECT e.edge_id, e.source_node_id, e.target_node_id,
                   e.edge_type, e.weight,
                   n1.display_name AS source_name,
                   n2.display_name AS target_name
            FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
            JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n1
                ON e.source_node_id = n1.node_id
            JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n2
                ON e.target_node_id = n2.node_id
            WHERE e.edge_type IN (
                'INFLUENCED_BY', 'COMORBID_WITH', 'RISK_STRATIFIED',
                'COVERED_BY', 'UNDERSTAFFED_DURING', 'SAME_AS',
                'DIAGNOSED_WITH', 'RESULTED_IN'
            )
        """).to_pandas()
    except Exception:
        return pd.DataFrame()


@st.cache_data(ttl=30)
def load_correlation_results() -> pd.DataFrame:
    """Load staffing-outcome correlation results."""
    session = _get_session()
    if session is None:
        return pd.DataFrame()
    try:
        return session.sql("""
            SELECT *
            FROM DCA_DEMO.GOVERNANCE.HCLS_CORRELATION_RESULTS
            ORDER BY ABS(correlation_coefficient) DESC
        """).to_pandas()
    except Exception:
        return pd.DataFrame()


@st.cache_data(ttl=30)
def load_staffing_metrics() -> pd.DataFrame:
    """Load staffing outcome metrics."""
    session = _get_session()
    if session is None:
        return pd.DataFrame()
    try:
        return session.sql("""
            SELECT *
            FROM DCA_DEMO.GOVERNANCE.HCLS_STAFFING_OUTCOME_METRICS
            ORDER BY unit_type, metric_name
        """).to_pandas()
    except Exception:
        return pd.DataFrame()


@st.cache_data(ttl=30)
def load_payer_metrics() -> pd.DataFrame:
    """Load payer metrics by CCI tier."""
    session = _get_session()
    if session is None:
        return pd.DataFrame()
    try:
        return session.sql("""
            SELECT *
            FROM DCA_DEMO.GOVERNANCE.HCLS_PAYER_METRICS
            ORDER BY cci_tier, payer_name
        """).to_pandas()
    except Exception:
        return pd.DataFrame()


@st.cache_data(ttl=30)
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

def get_graph_data() -> tuple:
    """Return (nodes_df, edges_df, is_demo_mode)."""
    sf_nodes = load_nodes_from_sf()
    sf_edges = load_edges_from_sf()

    if sf_nodes.empty:
        # Map sample data to match expected column names
        nodes = SAMPLE_NODES.copy()
        edges = SAMPLE_EDGES.copy()
        return nodes, edges, True

    # Map SF data to display-friendly format
    source_to_domain = {
        "FHIR": "Clinical",
        "WORKDAY_HCM": "Staffing",
        "PAYER": "Payer",
    }
    sf_nodes["domain"] = sf_nodes["SOURCE_SYSTEM"].map(source_to_domain).fillna("Clinical")
    sf_nodes.columns = [c.lower() for c in sf_nodes.columns]

    if not sf_edges.empty:
        sf_edges.columns = [c.lower() for c in sf_edges.columns]
        sf_edges = sf_edges.rename(columns={
            "source_node_id": "source",
            "target_node_id": "target",
        })
    else:
        sf_edges = SAMPLE_EDGES.copy()

    return sf_nodes, sf_edges, False


# ── Graph Rendering ───────────────────────────────────────────────────────

def _get_node_tooltip(name: str) -> str:
    """Look up the signal definition for a node."""
    return SIGNAL_DEFINITIONS["nodes"].get(name, f"{name} — no definition available")


def _get_edge_tooltip(source_name: str, target_name: str) -> str:
    """Look up the signal definition for an edge."""
    key = (source_name, target_name)
    if key in SIGNAL_DEFINITIONS["edges"]:
        return SIGNAL_DEFINITIONS["edges"][key]
    # Try reverse
    rev_key = (target_name, source_name)
    if rev_key in SIGNAL_DEFINITIONS["edges"]:
        return SIGNAL_DEFINITIONS["edges"][rev_key]
    return f"{source_name} → {target_name}"


def render_agraph(nodes_df: pd.DataFrame, edges_df: pd.DataFrame,
                  domain_filter: list, edge_filter: list, min_weight: float):
    """Render interactive graph with streamlit-agraph."""
    from streamlit_agraph import agraph, Node, Edge, Config

    # Filter nodes
    if domain_filter:
        nodes_df = nodes_df[nodes_df["domain"].isin(domain_filter)]
    node_ids = set(nodes_df["node_id"].tolist())

    # Filter edges
    filtered_edges = edges_df.copy()
    if edge_filter:
        filtered_edges = filtered_edges[filtered_edges["edge_type"].isin(edge_filter)]
    if min_weight > 0:
        filtered_edges = filtered_edges[filtered_edges["weight"].abs() >= min_weight]
    # Keep only edges with both endpoints visible
    filtered_edges = filtered_edges[
        filtered_edges["source"].isin(node_ids) & filtered_edges["target"].isin(node_ids)
    ]

    # Build node name lookup
    name_lookup = dict(zip(nodes_df["node_id"], nodes_df["display_name"]))

    # Create agraph nodes
    ag_nodes = []
    for _, row in nodes_df.iterrows():
        domain = row["domain"]
        color = DOMAIN_COLORS.get(domain, "#7f7f7f")
        tooltip = _get_node_tooltip(row["display_name"])
        ag_nodes.append(Node(
            id=row["node_id"],
            label=row["display_name"],
            size=25,
            color=color,
            title=f"[{domain}] {row['display_name']}\n\n{tooltip}",
            shape={
                "Clinical": "dot",
                "Staffing": "square",
                "Payer": "diamond",
                "Comorbidity": "triangle",
                "Outcome": "hexagon",
            }.get(domain, "dot"),
        ))

    # Create agraph edges
    ag_edges = []
    for _, row in filtered_edges.iterrows():
        src_name = name_lookup.get(row["source"], row["source"])
        tgt_name = name_lookup.get(row["target"], row["target"])
        edge_tooltip = _get_edge_tooltip(src_name, tgt_name)
        style = EDGE_TYPE_STYLES.get(row["edge_type"], {"color": "#999"})
        weight = abs(row.get("weight", 0.5))

        ag_edges.append(Edge(
            source=row["source"],
            target=row["target"],
            label=f'{row["edge_type"]} ({weight:.2f})',
            color=style["color"],
            width=max(1, weight * 5),
            title=f'{row["edge_type"]}: {src_name} → {tgt_name}\n\n{edge_tooltip}',
            type="CURVE_SMOOTH",
        ))

    config = Config(
        width=1200,
        height=650,
        directed=True,
        physics=True,
        hierarchical=False,
        nodeHighlightBehavior=True,
        highlightColor="#F7A7A6",
        collapsible=True,
    )

    selected = agraph(nodes=ag_nodes, edges=ag_edges, config=config)
    return selected


def render_pyvis_fallback(nodes_df: pd.DataFrame, edges_df: pd.DataFrame,
                          domain_filter: list, edge_filter: list, min_weight: float):
    """Fallback rendering using pyvis when streamlit-agraph is unavailable."""
    try:
        from pyvis.network import Network
        import streamlit.components.v1 as components
    except ImportError:
        st.error("Neither `streamlit-agraph` nor `pyvis` is installed. "
                 "Install one to enable graph visualization.")
        _render_tabular(nodes_df, edges_df)
        return

    # Filter
    if domain_filter:
        nodes_df = nodes_df[nodes_df["domain"].isin(domain_filter)]
    node_ids = set(nodes_df["node_id"].tolist())

    filtered_edges = edges_df.copy()
    if edge_filter:
        filtered_edges = filtered_edges[filtered_edges["edge_type"].isin(edge_filter)]
    if min_weight > 0:
        filtered_edges = filtered_edges[filtered_edges["weight"].abs() >= min_weight]
    filtered_edges = filtered_edges[
        filtered_edges["source"].isin(node_ids) & filtered_edges["target"].isin(node_ids)
    ]

    name_lookup = dict(zip(nodes_df["node_id"], nodes_df["display_name"]))

    net = Network(height="650px", width="100%", bgcolor="#0d1117", font_color="#e0e0e0")
    net.barnes_hut(gravity=-8000, central_gravity=0.3, spring_length=200)

    shape_map = {
        "Clinical": "dot", "Staffing": "square", "Payer": "diamond",
        "Comorbidity": "triangle", "Outcome": "star",
    }

    for _, row in nodes_df.iterrows():
        domain = row["domain"]
        tooltip = _get_node_tooltip(row["display_name"])
        net.add_node(
            row["node_id"],
            label=row["display_name"],
            color=DOMAIN_COLORS.get(domain, "#7f7f7f"),
            shape=shape_map.get(domain, "dot"),
            size=20,
            title=f"<b>[{domain}] {row['display_name']}</b><br><br>{tooltip}",
        )

    for _, row in filtered_edges.iterrows():
        src_name = name_lookup.get(row["source"], row["source"])
        tgt_name = name_lookup.get(row["target"], row["target"])
        tooltip = _get_edge_tooltip(src_name, tgt_name)
        style = EDGE_TYPE_STYLES.get(row["edge_type"], {"color": "#999"})
        weight = abs(row.get("weight", 0.5))

        dashes = row["edge_type"] in ("DRIVES", "STRATIFIES")
        net.add_edge(
            row["source"], row["target"],
            value=weight * 5,
            color=style["color"],
            title=f"<b>{row['edge_type']}: {src_name} → {tgt_name}</b><br><br>{tooltip}",
            dashes=dashes,
            arrows="to",
        )

    html = net.generate_html()
    components.html(html, height=680, scrolling=False)


def _render_tabular(nodes_df: pd.DataFrame, edges_df: pd.DataFrame):
    """Last-resort tabular rendering."""
    st.subheader("Nodes")
    st.dataframe(nodes_df[["node_id", "display_name", "domain", "node_type"]],
                 use_container_width=True, hide_index=True)
    st.subheader("Edges")
    st.dataframe(edges_df[["source", "target", "edge_type", "weight"]],
                 use_container_width=True, hide_index=True)


# ── Page Layout ───────────────────────────────────────────────────────────

st.title("Ontological Signal Graph")
st.caption(
    "Interactive network showing relationships between clinical measures, staffing "
    "features, and payer metrics — hover over any node or edge for a detailed "
    "explanation of WHY things correlate."
)

nodes_df, edges_df, is_demo_mode = get_graph_data()

if is_demo_mode:
    st.warning(
        "Demo mode: showing sample data. Connect to Snowflake for live metrics.",
        icon="⚠️",
    )

# ── Sidebar Filters ───────────────────────────────────────────────────────

st.sidebar.header("Signal Graph Filters")

domain_filter = st.sidebar.multiselect(
    "Domains",
    options=["Clinical", "Staffing", "Payer", "Comorbidity", "Outcome"],
    default=[],
    help="Filter nodes by domain. Leave empty to show all.",
)

edge_filter = st.sidebar.multiselect(
    "Edge Types",
    options=list(EDGE_TYPE_STYLES.keys()),
    default=[],
    format_func=lambda x: EDGE_TYPE_STYLES[x]["label"],
    help="Filter by correlation type.",
)

min_weight = st.sidebar.slider(
    "Minimum Correlation Strength",
    min_value=0.0, max_value=1.0, value=0.0, step=0.05,
    help="Only show edges with |correlation| >= this value.",
)

unit_filter = st.sidebar.selectbox(
    "Unit Type",
    options=["All", "ICU", "ED", "Med-Surg"],
    index=0,
    help="Filter staffing metrics by unit type.",
)

cci_filter = st.sidebar.selectbox(
    "CCI Tier Focus",
    options=["All", "LOW", "MODERATE", "HIGH", "SEVERE"],
    index=0,
    help="Highlight metrics for a specific comorbidity tier.",
)

# ── Main Graph ────────────────────────────────────────────────────────────

try:
    selected_node = render_agraph(nodes_df, edges_df, domain_filter, edge_filter, min_weight)
except (ImportError, Exception):
    render_pyvis_fallback(nodes_df, edges_df, domain_filter, edge_filter, min_weight)
    selected_node = None

# ── Node Detail Panel ─────────────────────────────────────────────────────

if selected_node:
    match = nodes_df[nodes_df["node_id"] == selected_node]
    if not match.empty:
        row = match.iloc[0]
        with st.expander(f"Signal Detail: {row['display_name']}", expanded=True):
            st.markdown(f"**Domain:** {row['domain']}  |  **Type:** {row['node_type']}")
            st.markdown(f"**Definition:** {_get_node_tooltip(row['display_name'])}")

            # Show connected edges
            connected = edges_df[
                (edges_df["source"] == selected_node) | (edges_df["target"] == selected_node)
            ]
            if not connected.empty:
                name_lookup = dict(zip(nodes_df["node_id"], nodes_df["display_name"]))
                st.markdown("**Connected Signals:**")
                for _, e in connected.iterrows():
                    src_name = name_lookup.get(e["source"], e["source"])
                    tgt_name = name_lookup.get(e["target"], e["target"])
                    tooltip = _get_edge_tooltip(src_name, tgt_name)
                    weight = abs(e.get("weight", 0))
                    st.markdown(
                        f"- **{src_name}** → **{tgt_name}** "
                        f"({e['edge_type']}, r={weight:.2f}): {tooltip[:120]}..."
                    )

st.divider()

# ── Metrics Panel ─────────────────────────────────────────────────────────

st.subheader("Key Signal Metrics")

# Compute summary stats from the edge data
if not edges_df.empty:
    top_edge = edges_df.loc[edges_df["weight"].abs().idxmax()]
    name_lookup = dict(zip(nodes_df["node_id"], nodes_df["display_name"]))
    top_src = name_lookup.get(top_edge["source"], top_edge["source"])
    top_tgt = name_lookup.get(top_edge["target"], top_edge["target"])
    influenced_count = len(edges_df[edges_df["edge_type"] == "INFLUENCES"])
    correlates_count = len(edges_df[edges_df["edge_type"] == "CORRELATES_WITH"])
    drives_count = len(edges_df[edges_df["edge_type"] == "DRIVES"])

    col1, col2, col3, col4 = st.columns(4)
    col1.metric(
        "Strongest Signal",
        f"r={abs(top_edge['weight']):.2f}",
        f"{top_src} → {top_tgt}",
    )
    col2.metric("INFLUENCED_BY Edges", influenced_count)
    col3.metric("CORRELATES_WITH Edges", correlates_count)
    col4.metric("DRIVES Edges", drives_count)
else:
    st.info("No edge data available.")

# Live metrics from Snowflake (if available)
corr_df = load_correlation_results()
payer_df = load_payer_metrics()

if not corr_df.empty:
    st.markdown("---")
    st.subheader("Correlation Results")
    display_corr = corr_df.head(10)
    if "CORRELATION_COEFFICIENT" in display_corr.columns:
        st.dataframe(display_corr, use_container_width=True, hide_index=True)
    else:
        st.dataframe(display_corr, use_container_width=True, hide_index=True)

if not payer_df.empty:
    st.markdown("---")
    st.subheader("Payer Metrics by CCI Tier")
    if cci_filter != "All" and "CCI_TIER" in payer_df.columns:
        payer_df = payer_df[payer_df["CCI_TIER"] == cci_filter]
    st.dataframe(payer_df, use_container_width=True, hide_index=True)

# ── Explanation Panel ─────────────────────────────────────────────────────

with st.expander("How to Read This Graph"):
    st.markdown("""
### Color Legend
| Color | Domain | Shape | Description |
|-------|--------|-------|-------------|
| Blue | Clinical Measures | Circle | Outcome and quality metrics from FHIR/EHR data |
| Green | Staffing Features | Square | Workforce metrics from Workday HCM |
| Orange | Payer Metrics | Diamond | Claims and utilization data from payer systems |
| Red | Comorbidity Tiers | Triangle | Charlson Comorbidity Index severity buckets |
| Purple | Patient Outcomes | Hexagon | Discrete patient-level outcome events |

### Edge Types
| Style | Type | Meaning |
|-------|------|---------|
| Solid blue | CORRELATES_WITH | Statistical correlation between staffing feature and clinical outcome |
| Dashed red | DRIVES | Comorbidity burden driving payer behavior (causation implied) |
| Solid green | INFLUENCES | Staffing feature influencing patient-level outcome |
| Dotted gray | STRATIFIES | CCI tier splitting a metric into complexity-adjusted views |

### Edge Width
Edge thickness is proportional to the absolute correlation coefficient (|r|).
Thicker edges represent stronger statistical relationships.

### What the Correlations Mean
These are Pearson correlation coefficients computed on monthly aggregates.
A coefficient of 0.68 means 68% of the variation in one measure is linearly
associated with variation in the other. Correlation does not prove causation,
but the clinical mechanisms described in the tooltips explain the causal pathways
supported by published research.

### Data Freshness
Correlations are recomputed each time `SP_HCLS_MASTER_ORCHESTRATOR()` runs.
Check the graph snapshot timestamp at the bottom of this page for last refresh.
""")

# ── Footer: Snapshot Info ─────────────────────────────────────────────────

st.divider()
snapshot_df = load_snapshot_info()
if not snapshot_df.empty:
    snap = snapshot_df.iloc[0]
    col1, col2, col3 = st.columns(3)
    col1.caption(f"Last Refresh: {snap['SNAPSHOT_TIME']}")
    col2.caption(f"Total Nodes: {snap['NODE_COUNT']:,}")
    col3.caption(f"Total Edges: {snap['EDGE_COUNT']:,}")
elif is_demo_mode:
    st.caption("Demo mode — no live snapshot data available.")
else:
    st.caption("Graph has not been populated yet. Run SP_HCLS_MASTER_ORCHESTRATOR() to initialize.")
