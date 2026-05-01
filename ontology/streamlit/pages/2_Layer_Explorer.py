"""
Page 2: Layer Explorer
Live browse of RAW → CURATED → SEMANTIC tables.
Queries INFORMATION_SCHEMA for table metadata.
"""

import streamlit as st
import pandas as pd
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="Layer Explorer | DCA Demo", layout="wide")
session = get_active_session()

# ── Helpers ───────────────────────────────────────────────────

@st.cache_data(ttl=60)
def get_tables(schema: str) -> pd.DataFrame:
    return session.sql(f"""
        SELECT
            TABLE_NAME,
            COALESCE(ROW_COUNT, 0)              AS row_count,
            COALESCE(TABLE_OWNER, 'UNKNOWN')    AS owner,
            COALESCE(COMMENT, '')               AS comment,
            LAST_ALTERED::DATE                  AS last_altered,
            BYTES
        FROM DCA_DEMO.INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA = '{schema}'
          AND TABLE_TYPE   = 'BASE TABLE'
        ORDER BY TABLE_NAME
    """).to_pandas()


@st.cache_data(ttl=60)
def get_columns(schema: str, table: str) -> pd.DataFrame:
    return session.sql(f"""
        SELECT
            COLUMN_NAME,
            DATA_TYPE,
            IS_NULLABLE,
            COALESCE(COMMENT, '') AS comment
        FROM DCA_DEMO.INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = '{schema}'
          AND TABLE_NAME   = '{table}'
        ORDER BY ORDINAL_POSITION
    """).to_pandas()


def ontological_badge(schema: str) -> str:
    mapping = {
        "RAW":              ("Brute Fact",                    "#29B5E8"),
        "CURATED":          ("Institutional Fact in Formation", "#FFC107"),
        "SEMANTIC_FINANCE": ("Full Institutional Fact",       "#28A745"),
        "SEMANTIC_SALES":   ("Full Institutional Fact",       "#28A745"),
    }
    label, colour = mapping.get(schema, ("Unknown", "#888"))
    return (
        f'<span style="background:{colour};color:#000;padding:3px 10px;'
        f'border-radius:12px;font-size:0.8em;font-weight:600;">{label}</span>'
    )


def layer_description(schema: str) -> str:
    desc = {
        "RAW": (
            "Data as received from source systems — no quality guarantees, no governance obligations. "
            "Contains duplicates, mixed currencies, and nullable fields by design. "
            "**Only data engineers and the ingestion service should access this layer.**"
        ),
        "CURATED": (
            "Cleaned, conformed, and deduplicated data. Surrogate keys applied. Currencies normalised to USD. "
            "PII columns tagged with `pii_category` and protected by masking policies. "
            "**Domain owners and data engineers access this layer. Consumers do not.**"
        ),
        "SEMANTIC_FINANCE": (
            "Finance data products governed by active data contracts. "
            "Each table has a declared owner, version, purpose, and freshness SLA. "
            "**Consumers access only this layer — never Raw or Curated.**"
        ),
        "SEMANTIC_SALES": (
            "Sales data products governed by active data contracts. "
            "**Consumers access only this layer — never Raw or Curated.**"
        ),
    }
    return desc.get(schema, "")


# ── Page header ───────────────────────────────────────────────
st.title("Layer Explorer")
st.markdown(
    "Browse the three data layers. Each layer represents a different ontological status — "
    "from raw ingested facts to fully governed data products."
)
st.markdown("---")

# ── Layer tabs ────────────────────────────────────────────────
tab_raw, tab_cur, tab_fin, tab_sal = st.tabs([
    "RAW", "CURATED", "SEMANTIC — Finance", "SEMANTIC — Sales"
])

for tab, schema in [
    (tab_raw, "RAW"),
    (tab_cur, "CURATED"),
    (tab_fin, "SEMANTIC_FINANCE"),
    (tab_sal, "SEMANTIC_SALES"),
]:
    with tab:
        st.markdown(
            f"### {schema.replace('_', ' ')}  &nbsp;&nbsp;"
            + ontological_badge(schema),
            unsafe_allow_html=True,
        )
        st.markdown(layer_description(schema))

        try:
            df = get_tables(schema)
        except Exception as e:
            st.error(f"Could not query INFORMATION_SCHEMA: {e}")
            continue

        if df.empty:
            st.info("No tables found. Run the setup SQL files first.")
            continue

        st.markdown(f"**{len(df)} table(s)** in this layer")
        st.markdown("---")

        for _, row in df.iterrows():
            with st.expander(
                f"**{row['TABLE_NAME']}**  —  "
                f"{row['ROW_COUNT']:,} rows  |  "
                f"Owner: `{row['OWNER']}`"
            ):
                col_left, col_right = st.columns([2, 1])

                with col_left:
                    if row["COMMENT"]:
                        st.markdown(f"*{row['COMMENT']}*")
                    else:
                        st.markdown(
                            "*No table comment — this object has no declared meaning.*"
                        )
                    # Column list
                    try:
                        cols_df = get_columns(schema, row["TABLE_NAME"])
                        cols_df.columns = [
                            c.replace("_", " ").title() for c in cols_df.columns
                        ]
                        st.dataframe(cols_df, use_container_width=True, hide_index=True)
                    except Exception:
                        st.warning("Could not load column metadata.")

                with col_right:
                    st.metric("Rows",         f"{row['ROW_COUNT']:,}")
                    st.metric("Last Altered", str(row["LAST_ALTERED"]))
                    st.metric("Owner Role",   row["OWNER"])
                    if row["BYTES"]:
                        kb = round(row["BYTES"] / 1024, 1)
                        st.metric("Storage", f"{kb} KB")
