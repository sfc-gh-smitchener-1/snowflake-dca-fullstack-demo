"""
Page 3: Governance Health
Four health metrics: ownership, contracts, PII classification, quality coverage.
Drills down to show which objects are failing each check.
"""

import streamlit as st
import pandas as pd
import plotly.graph_objects as go
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="Governance Health | DCA Demo", layout="wide")
session = get_active_session()

# ── Helpers ───────────────────────────────────────────────────

@st.cache_data(ttl=30)
def get_ownership_health() -> dict:
    """Check what % of Semantic tables have a non-SYSADMIN owner."""
    df = session.sql("""
        SELECT
            TABLE_SCHEMA,
            TABLE_NAME,
            COALESCE(TABLE_OWNER, 'UNKNOWN') AS owner,
            IFF(UPPER(COALESCE(TABLE_OWNER, 'SYSADMIN')) IN ('SYSADMIN','ACCOUNTADMIN'),
                'UNOWNED', 'OWNED') AS status
        FROM DCA_DEMO.INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA IN ('SEMANTIC_FINANCE','SEMANTIC_SALES')
          AND TABLE_TYPE = 'BASE TABLE'
        ORDER BY TABLE_SCHEMA, TABLE_NAME
    """).to_pandas()
    total = len(df)
    owned = len(df[df["STATUS"] == "OWNED"])
    return {"pct": round(owned / total * 100) if total else 0, "df": df, "total": total, "ok": owned}


@st.cache_data(ttl=30)
def get_contract_health() -> dict:
    """Check what % of Semantic tables are registered in DATA_PRODUCT_CATALOG."""
    semantic_df = session.sql("""
        SELECT TABLE_SCHEMA, TABLE_NAME
        FROM DCA_DEMO.INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA IN ('SEMANTIC_FINANCE','SEMANTIC_SALES')
          AND TABLE_TYPE = 'BASE TABLE'
    """).to_pandas()

    catalog_df = session.sql("""
        SELECT SCHEMA_NAME, TABLE_NAME, DATA_CONTRACT_VERSION, CONTRACT_STATUS
        FROM DCA_DEMO.GOVERNANCE.DATA_PRODUCT_CATALOG
    """).to_pandas()

    merged = semantic_df.merge(
        catalog_df,
        left_on=["TABLE_SCHEMA", "TABLE_NAME"],
        right_on=["SCHEMA_NAME", "TABLE_NAME"],
        how="left",
    )
    merged["status"] = merged["CONTRACT_STATUS"].apply(
        lambda x: "ACTIVE" if x == "ACTIVE" else ("DRAFT" if x == "DRAFT" else "MISSING")
    )
    total = len(merged)
    ok    = len(merged[merged["status"] == "ACTIVE"])
    return {"pct": round(ok / total * 100) if total else 0, "df": merged, "total": total, "ok": ok}


@st.cache_data(ttl=30)
def get_pii_health() -> dict:
    """Check PII classification coverage on columns in RAW and CURATED."""
    df = session.sql("""
        SELECT
            c.TABLE_SCHEMA,
            c.TABLE_NAME,
            c.COLUMN_NAME,
            c.DATA_TYPE,
            IFF(LOWER(c.COLUMN_NAME) IN ('email','phone','full_name','phone_masked'),
                'PII_CANDIDATE', 'NOT_PII') AS pii_candidate,
            COALESCE(c.COMMENT, '')         AS col_comment
        FROM DCA_DEMO.INFORMATION_SCHEMA.COLUMNS c
        WHERE c.TABLE_SCHEMA IN ('RAW','CURATED')
          AND (LOWER(c.COLUMN_NAME) LIKE '%email%'
               OR LOWER(c.COLUMN_NAME) LIKE '%phone%'
               OR LOWER(c.COLUMN_NAME) IN ('full_name','name'))
        ORDER BY c.TABLE_SCHEMA, c.TABLE_NAME, c.COLUMN_NAME
    """).to_pandas()
    total = len(df)
    # Simulate tag check: columns with masking comment are "tagged"
    tagged = len(df[df["COL_COMMENT"].str.contains("PII|masked|mask", case=False, na=False)])
    return {"pct": round(tagged / total * 100) if total else 0, "df": df, "total": total, "ok": tagged}


@st.cache_data(ttl=30)
def get_quality_health() -> dict:
    """Check what % of Semantic tables have quality monitoring notes in catalog."""
    df = session.sql("""
        SELECT
            SCHEMA_NAME,
            TABLE_NAME,
            SLA_FRESHNESS_HOURS,
            IFF(SLA_FRESHNESS_HOURS IS NOT NULL, 'MONITORED', 'UNMONITORED') AS monitor_status,
            NOTES
        FROM DCA_DEMO.GOVERNANCE.DATA_PRODUCT_CATALOG
        ORDER BY SCHEMA_NAME, TABLE_NAME
    """).to_pandas()
    # Also count Semantic tables not in catalog at all
    semantic_df = session.sql("""
        SELECT COUNT(*) AS cnt
        FROM DCA_DEMO.INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA IN ('SEMANTIC_FINANCE','SEMANTIC_SALES')
          AND TABLE_TYPE = 'BASE TABLE'
    """).to_pandas()
    total     = semantic_df["CNT"].iloc[0]
    monitored = len(df[df["MONITOR_STATUS"] == "MONITORED"])
    return {"pct": round(monitored / total * 100) if total else 0,
            "df": df, "total": total, "ok": monitored}


def gauge(label: str, pct: int, ok: int, total: int) -> go.Figure:
    colour = "#28A745" if pct >= 80 else ("#FFC107" if pct >= 50 else "#FF4444")
    fig = go.Figure(go.Indicator(
        mode="gauge+number",
        value=pct,
        title={"text": label, "font": {"size": 14, "color": "#e0e0e0"}},
        number={"suffix": "%", "font": {"size": 28, "color": colour}},
        gauge={
            "axis": {"range": [0, 100], "tickcolor": "#555"},
            "bar":  {"color": colour, "thickness": 0.3},
            "bgcolor": "#1a1a2e",
            "steps": [
                {"range": [0,  50], "color": "#2a1010"},
                {"range": [50, 80], "color": "#2a2a10"},
                {"range": [80,100], "color": "#102a10"},
            ],
            "threshold": {"line": {"color": colour, "width": 3},
                          "thickness": 0.8, "value": pct},
        },
    ))
    fig.update_layout(
        paper_bgcolor="#0d1117",
        plot_bgcolor="#0d1117",
        height=220,
        margin=dict(l=20, r=20, t=40, b=10),
        font={"color": "#e0e0e0"},
    )
    return fig


def status_label(pct: int) -> str:
    if pct >= 80:
        return "🟢 Healthy"
    if pct >= 50:
        return "🟡 At Risk"
    return "🔴 Critical"


# ── Page header ───────────────────────────────────────────────
st.title("Governance Health")
st.markdown(
    "Live health metrics for the DCA_DEMO platform. "
    "Each metric measures a dimension of ontological completeness — "
    "whether the data has the institutional facts needed to be trusted."
)
st.markdown("---")

try:
    ownership = get_ownership_health()
    contracts = get_contract_health()
    pii       = get_pii_health()
    quality   = get_quality_health()
except Exception as e:
    st.error(f"Could not load health data. Run the setup SQL files first. ({e})")
    st.stop()

# ── Gauge row ─────────────────────────────────────────────────
col1, col2, col3, col4 = st.columns(4)

with col1:
    st.plotly_chart(gauge("Ownership Coverage", ownership["pct"],
                          ownership["ok"], ownership["total"]),
                    use_container_width=True)
    st.markdown(f"<center>{status_label(ownership['pct'])}<br>"
                f"<small>{ownership['ok']}/{ownership['total']} Semantic tables have an assigned owner</small></center>",
                unsafe_allow_html=True)

with col2:
    st.plotly_chart(gauge("Contract Coverage", contracts["pct"],
                          contracts["ok"], contracts["total"]),
                    use_container_width=True)
    st.markdown(f"<center>{status_label(contracts['pct'])}<br>"
                f"<small>{contracts['ok']}/{contracts['total']} Semantic tables have an ACTIVE contract</small></center>",
                unsafe_allow_html=True)

with col3:
    st.plotly_chart(gauge("PII Classification", pii["pct"],
                          pii["ok"], pii["total"]),
                    use_container_width=True)
    st.markdown(f"<center>{status_label(pii['pct'])}<br>"
                f"<small>{pii['ok']}/{pii['total']} PII-candidate columns are classified</small></center>",
                unsafe_allow_html=True)

with col4:
    st.plotly_chart(gauge("Quality Coverage", quality["pct"],
                          quality["ok"], quality["total"]),
                    use_container_width=True)
    st.markdown(f"<center>{status_label(quality['pct'])}<br>"
                f"<small>{quality['ok']}/{quality['total']} Semantic tables have SLA monitoring</small></center>",
                unsafe_allow_html=True)

st.markdown("---")

# ── Detail drilldown ──────────────────────────────────────────
st.markdown("## Detail Drilldown")
metric_choice = st.selectbox(
    "Inspect metric:",
    ["Ownership Coverage", "Contract Coverage", "PII Classification", "Quality Coverage"],
)

if metric_choice == "Ownership Coverage":
    st.markdown("### Ownership Status — Semantic Layer")
    st.markdown(
        "Tables owned by SYSADMIN or ACCOUNTADMIN have no accountable domain owner. "
        "This means there is no one to call when the SLA is breached."
    )
    df = ownership["df"].copy()
    df.columns = [c.title() for c in df.columns]
    df["Status"] = df["Status"].apply(
        lambda x: "✅ Owned" if x == "OWNED" else "❌ Unowned"
    )
    st.dataframe(df, use_container_width=True, hide_index=True)

elif metric_choice == "Contract Coverage":
    st.markdown("### Contract Status — Semantic Layer")
    st.markdown(
        "Tables not registered in the DATA_PRODUCT_CATALOG have no declared consumers, "
        "no versioned contract, and no stated SLA — they are institutional facts without recognition."
    )
    df = contracts["df"].copy()
    cols = ["TABLE_SCHEMA", "TABLE_NAME", "DATA_CONTRACT_VERSION", "status"]
    df = df[[c for c in cols if c in df.columns]]
    df.columns = ["Schema", "Table", "Contract Version", "Status"]
    df["Status"] = df["Status"].apply(
        lambda x: "✅ Active" if x == "ACTIVE" else ("⚠️ Draft" if x == "DRAFT" else "❌ Missing")
    )
    st.dataframe(df, use_container_width=True, hide_index=True)

elif metric_choice == "PII Classification":
    st.markdown("### PII Column Classification")
    st.markdown(
        "PII-candidate columns (email, phone, name) should carry a `pii_category` tag "
        "and have a masking policy applied. Gaps here expose personal data to unauthorised consumers."
    )
    df = pii["df"].copy()
    df.columns = [c.title() for c in df.columns]
    st.dataframe(df, use_container_width=True, hide_index=True)
    if pii["pct"] < 100:
        st.warning(
            f"{pii['total'] - pii['ok']} PII-candidate column(s) have no masking evidence. "
            "See CURATED.CUSTOMER_PII_EXTRACT for the most critical gap."
        )

elif metric_choice == "Quality Coverage":
    st.markdown("### Quality Monitoring — Semantic Layer")
    st.markdown(
        "Tables without an `sla_freshness_hours` value in the catalog have no agreed-upon "
        "freshness SLA. Consumers cannot know whether the data is stale."
    )
    df = quality["df"].copy()
    df.columns = [c.title() for c in df.columns]
    df["Monitor Status"] = df["Monitor Status"].apply(
        lambda x: "✅ Monitored" if x == "MONITORED" else "❌ Unmonitored"
    )
    st.dataframe(df[["Schema Name", "Table Name", "Sla Freshness Hours",
                      "Monitor Status"]], use_container_width=True, hide_index=True)
