"""
Page 4: Contract Registry
Browse data products from GOVERNANCE.DATA_PRODUCT_CATALOG.
Shows contract metadata, consumers, SLA status, and gap flags.
"""

import streamlit as st
import pandas as pd
from datetime import datetime, timezone
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="Contract Registry | DCA Demo", layout="wide")
session = get_active_session()

# ── Data load ─────────────────────────────────────────────────

@st.cache_data(ttl=30)
def get_catalog() -> pd.DataFrame:
    return session.sql("""
        SELECT
            CATALOG_ID,
            SCHEMA_NAME,
            TABLE_NAME,
            DISPLAY_NAME,
            DESCRIPTION,
            DATA_CONTRACT_VERSION,
            CONTRACT_OWNER_ROLE,
            DATA_PURPOSE,
            SLA_FRESHNESS_HOURS,
            CONSUMER_ROLES::VARCHAR      AS consumer_roles_raw,
            IS_PII_IN_SCOPE,
            CONTRACT_STATUS,
            REGISTERED_AT,
            LAST_REVIEWED_AT,
            NOTES
        FROM DCA_DEMO.GOVERNANCE.DATA_PRODUCT_CATALOG
        ORDER BY SCHEMA_NAME, TABLE_NAME
    """).to_pandas()


@st.cache_data(ttl=30)
def get_ungoverned() -> pd.DataFrame:
    """Semantic tables NOT in the catalog."""
    return session.sql("""
        SELECT t.TABLE_SCHEMA, t.TABLE_NAME,
               COALESCE(t.TABLE_OWNER, 'UNKNOWN') AS owner,
               COALESCE(t.ROW_COUNT, 0)           AS row_count
        FROM DCA_DEMO.INFORMATION_SCHEMA.TABLES t
        LEFT JOIN DCA_DEMO.GOVERNANCE.DATA_PRODUCT_CATALOG c
               ON c.SCHEMA_NAME = t.TABLE_SCHEMA
              AND c.TABLE_NAME  = t.TABLE_NAME
        WHERE t.TABLE_SCHEMA IN ('SEMANTIC_FINANCE','SEMANTIC_SALES')
          AND t.TABLE_TYPE = 'BASE TABLE'
          AND c.CATALOG_ID IS NULL
        ORDER BY t.TABLE_SCHEMA, t.TABLE_NAME
    """).to_pandas()


@st.cache_data(ttl=60)
def get_row_count(schema: str, table: str) -> int:
    try:
        result = session.sql(
            f"SELECT COUNT(*) FROM DCA_DEMO.{schema}.{table}"
        ).collect()
        return result[0][0]
    except Exception:
        return -1


def status_chip(status: str) -> str:
    colours = {"ACTIVE": "#28A745", "DRAFT": "#FFC107", "DEPRECATED": "#888"}
    colour = colours.get(status, "#888")
    return (
        f'<span style="background:{colour};color:#000;padding:2px 10px;'
        f'border-radius:10px;font-size:0.8em;font-weight:700;">{status}</span>'
    )


def purpose_chip(purpose: str) -> str:
    colours = {
        "REPORTING": "#29B5E8", "ANALYTICS": "#9B59B6",
        "OPERATIONAL": "#E67E22", "REGULATORY": "#E74C3C", "INTERNAL": "#888"
    }
    colour = colours.get(purpose, "#888")
    return (
        f'<span style="background:transparent;color:{colour};border:1px solid {colour};'
        f'padding:2px 8px;border-radius:10px;font-size:0.8em;">{purpose}</span>'
    )


# ── Page header ───────────────────────────────────────────────
st.title("Data Contract Registry")
st.markdown(
    "All governed data products registered in `DCA_DEMO.GOVERNANCE.DATA_PRODUCT_CATALOG`. "
    "Each product has a declared owner, versioned contract, stated purpose, and consumer list."
)
st.markdown("---")

try:
    catalog    = get_catalog()
    ungoverned = get_ungoverned()
except Exception as e:
    st.error(f"Could not load catalog. Run the setup SQL files first. ({e})")
    st.stop()

# ── Summary metrics ───────────────────────────────────────────
col1, col2, col3, col4 = st.columns(4)
col1.metric("Registered Products",  len(catalog))
col2.metric("Active Contracts",     len(catalog[catalog["CONTRACT_STATUS"] == "ACTIVE"]))
col3.metric("Ungoverned Semantic",   len(ungoverned),
            delta=f"-{len(ungoverned)} gaps" if len(ungoverned) > 0 else None,
            delta_color="inverse")
col4.metric("Domains Covered",
            catalog["SCHEMA_NAME"].nunique())

st.markdown("---")

# ── Filter bar ────────────────────────────────────────────────
col_f1, col_f2 = st.columns([1, 1])
with col_f1:
    domain_filter = st.multiselect(
        "Filter by domain:",
        options=catalog["SCHEMA_NAME"].unique().tolist(),
        default=catalog["SCHEMA_NAME"].unique().tolist(),
    )
with col_f2:
    status_filter = st.multiselect(
        "Filter by status:",
        options=catalog["CONTRACT_STATUS"].unique().tolist(),
        default=catalog["CONTRACT_STATUS"].unique().tolist(),
    )

filtered = catalog[
    catalog["SCHEMA_NAME"].isin(domain_filter) &
    catalog["CONTRACT_STATUS"].isin(status_filter)
]

st.markdown("---")

# ── Product cards ─────────────────────────────────────────────
for _, row in filtered.iterrows():
    col_left, col_right = st.columns([3, 1])

    with col_left:
        st.markdown(
            f"### {row['DISPLAY_NAME'] or row['TABLE_NAME']} &nbsp;&nbsp;"
            + status_chip(row["CONTRACT_STATUS"])
            + "&nbsp;"
            + purpose_chip(row["DATA_PURPOSE"] or ""),
            unsafe_allow_html=True,
        )
        st.markdown(
            f"`DCA_DEMO.{row['SCHEMA_NAME']}.{row['TABLE_NAME']}`"
        )
        if row["DESCRIPTION"]:
            st.markdown(row["DESCRIPTION"])

    with col_right:
        st.markdown(
            f"**Version:** `{row['DATA_CONTRACT_VERSION']}`  \n"
            f"**Owner:** `{row['CONTRACT_OWNER_ROLE']}`  \n"
            f"**SLA:** {row['SLA_FRESHNESS_HOURS']}h freshness"
        )
        if row["CONSUMER_ROLES_RAW"]:
            consumers = row["CONSUMER_ROLES_RAW"].strip('[]').replace('"', '').split(",")
            for c in consumers:
                st.markdown(f"- Consumer: `{c.strip()}`")

    with st.expander("Contract details"):
        detail_col1, detail_col2 = st.columns(2)
        with detail_col1:
            st.markdown(f"**Registered:** {str(row['REGISTERED_AT'])[:10]}")
            st.markdown(f"**Last reviewed:** {str(row['LAST_REVIEWED_AT'])[:10]}")
            st.markdown(f"**PII in scope:** {'Yes' if row['IS_PII_IN_SCOPE'] else 'No'}")
        with detail_col2:
            if row["NOTES"]:
                st.markdown(f"**Notes:** {row['NOTES']}")
            rc = get_row_count(row["SCHEMA_NAME"], row["TABLE_NAME"])
            if rc >= 0:
                st.metric("Current row count", f"{rc:,}")

    st.divider()

# ── Ungoverned objects ────────────────────────────────────────
if not ungoverned.empty:
    st.markdown("---")
    st.markdown("## Ungoverned Semantic Objects")
    st.warning(
        f"{len(ungoverned)} table(s) exist in the Semantic layer but are **not registered** "
        "in the Data Product Catalog. These objects have no declared owner, no versioned "
        "contract, and no stated consumers. They are institutional facts without recognition."
    )
    ungoverned.columns = [c.title() for c in ungoverned.columns]
    st.dataframe(ungoverned, use_container_width=True, hide_index=True)

    st.markdown(
        """
**To remediate:** For each ungoverned object, the domain owner should either:
1. Register it in `GOVERNANCE.DATA_PRODUCT_CATALOG` with a contract version and owner, or
2. Drop it if it has no active consumers and no declared purpose (see Gap 3: CHURN_RISK_SCORE).
        """
    )
