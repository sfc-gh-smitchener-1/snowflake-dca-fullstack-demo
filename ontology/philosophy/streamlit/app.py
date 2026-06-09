"""
DCA Demo — Main Page (Home)
Streamlit in Snowflake entry point.
"""

import streamlit as st
from snowflake.snowpark.context import get_active_session

# ── Page config ───────────────────────────────────────────────
st.set_page_config(
    page_title="DCA Demo",
    page_icon="❄️",
    layout="wide",
    initial_sidebar_state="expanded",
)

# ── Session ───────────────────────────────────────────────────
session = get_active_session()

# ── Sidebar ───────────────────────────────────────────────────
with st.sidebar:
    st.markdown("## Data Contracts Architecture")
    st.markdown("*SE Enablement Demo*")
    st.divider()
    st.markdown(
        """
**Pages**

1. Architecture — The dependency chain
2. Layer Explorer — Raw → Curated → Semantic
3. Governance Health — Platform health check
4. Contract Registry — Data product catalogue
5. Diagnostic Tool — Five discovery questions
        """
    )
    st.divider()
    try:
        current_role = session.sql("SELECT CURRENT_ROLE()").collect()[0][0]
        current_db   = session.sql("SELECT CURRENT_DATABASE()").collect()[0][0]
        st.caption(f"Role: `{current_role}`")
        st.caption(f"DB: `{current_db}`")
    except Exception:
        st.caption("Session active")

# ── Main content ──────────────────────────────────────────────
st.title("Data Contracts Architecture")
st.subheader("Why most data platforms fail — and how to fix them.")

st.markdown("---")

col1, col2, col3 = st.columns([1, 1, 1])

with col1:
    st.markdown(
        """
<div style="background:#1a1a2e;border-left:4px solid #29B5E8;padding:20px;border-radius:6px;">
<h3 style="color:#29B5E8;margin-top:0;">The Failure Pattern</h3>
<p style="color:#e0e0e0;">
Data platforms accumulate complexity faster than they accumulate meaning.
Tables proliferate. Ownership blurs. Definitions drift.
By the time automation arrives, the foundation is already unstable.
</p>
<p style="color:#e0e0e0;">
The result: <strong style="color:#FF6B6B;">correct data, wrong decisions</strong>.
</p>
</div>
        """,
        unsafe_allow_html=True,
    )

with col2:
    st.markdown(
        """
<div style="background:#1a1a2e;border-left:4px solid #28A745;padding:20px;border-radius:6px;">
<h3 style="color:#28A745;margin-top:0;">The Dependency Chain</h3>
<p style="color:#e0e0e0;">
Data platforms have an ontological dependency chain that cannot be reversed:
</p>
<p style="color:#29B5E8;font-size:1.1em;text-align:center;">
<strong>People → Data → Governance → Automation</strong>
</p>
<p style="color:#e0e0e0;">
Governance cannot exist without people who create institutional facts.
Automation cannot be trusted without governance that enforces them.
</p>
</div>
        """,
        unsafe_allow_html=True,
    )

with col3:
    st.markdown(
        """
<div style="background:#1a1a2e;border-left:4px solid #FFC107;padding:20px;border-radius:6px;">
<h3 style="color:#FFC107;margin-top:0;">The DCA Framework</h3>
<p style="color:#e0e0e0;">
Data Contracts Architecture (DCA) makes the dependency chain explicit.
It identifies <em>who owns what</em>, <em>what it means</em>,
and <em>who is accountable</em> when it breaks.
</p>
<p style="color:#e0e0e0;">
DCA is not a product. It is an <strong>ontological commitment</strong>
made by people, enforced by Snowflake.
</p>
</div>
        """,
        unsafe_allow_html=True,
    )

st.markdown("---")

st.markdown("## This Demo Environment")

col_a, col_b, col_c, col_d = st.columns(4)

try:
    bronze_count = session.sql(
        "SELECT COUNT(*) FROM DCA_DEMO.INFORMATION_SCHEMA.TABLES "
        "WHERE TABLE_SCHEMA = 'RAW' AND TABLE_TYPE = 'BASE TABLE'"
    ).collect()[0][0]
    silver_count = session.sql(
        "SELECT COUNT(*) FROM DCA_DEMO.INFORMATION_SCHEMA.TABLES "
        "WHERE TABLE_SCHEMA = 'CURATED' AND TABLE_TYPE = 'BASE TABLE'"
    ).collect()[0][0]
    gold_count = session.sql(
        "SELECT COUNT(*) FROM DCA_DEMO.INFORMATION_SCHEMA.TABLES "
        "WHERE TABLE_SCHEMA IN ('SEMANTIC_FINANCE','SEMANTIC_SALES') AND TABLE_TYPE = 'BASE TABLE'"
    ).collect()[0][0]
    contract_count = session.sql(
        "SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.DATA_PRODUCT_CATALOG "
        "WHERE CONTRACT_STATUS = 'ACTIVE'"
    ).collect()[0][0]

    col_a.metric("Raw Tables",      bronze_count,   help="Raw ingestion layer — uninterpreted brute facts")
    col_b.metric("Curated Tables",  silver_count,   help="Cleaned & conformed layer — institutional facts in formation")
    col_c.metric("Semantic Tables", gold_count,     help="Analytics-ready data products — full institutional facts")
    col_d.metric("Active Contracts", contract_count, help="Registered data contracts")

except Exception as e:
    st.warning(f"Run the setup SQL files first to populate the demo environment. ({e})")

st.markdown("---")
st.markdown(
    """
**Navigate using the sidebar** to explore the data layers, review governance health,
browse the data product contract registry, or run the interactive diagnostic tool.

> *Start with the **Diagnostic Tool** (page 5) to see the customer-facing discovery experience.*
    """
)
