# ============================================================================
# DATA CONTRACTS ON HORIZON — STREAMLIT PAGE (drop-in)
# ============================================================================
#
# A self-contained Streamlit-in-Snowflake page for the Horizon-native data
# contract layer (GOVERNANCE.DATA_CONTRACTS).
#
# TWO WAYS TO USE:
#   1. Standalone: deploy this file as its own SiS app (snowflake.yml pointing here).
#   2. Integrated: copy render_contracts_v2_page() + its helpers into
#      streamlit/app.py and add "📜 Data Contracts" to the sidebar nav +
#      the main() routing block (see contracts/README.md → "Streamlit integration").
#
# Requires: plotly, pandas (already in the SiS environment.yml).
# ============================================================================

import streamlit as st
import pandas as pd

try:
    import plotly.graph_objects as go
    _HAS_PLOTLY = True
except Exception:
    _HAS_PLOTLY = False

from snowflake.snowpark.context import get_active_session

_CDB = "GOVERNANCE.DATA_CONTRACTS"

_STATUS_STYLE = {
    "HEALTHY":       ("✅", "#18794E", "#F0FDF4"),
    "DEGRADED":      ("⚠️", "#AD5700", "#FFFBEB"),
    "BREACHED":      ("❌", "#CD2B31", "#FFF1F2"),
    "BLOCKED":       ("🛑", "#7F1D1D", "#FEF2F2"),
    "NOT_VALIDATED": ("⏳", "#64748B", "#F8FAFC"),
}
_DIM_ICON = {"SCHEMA": "🧬", "QUALITY": "🎯", "SLA": "⏱️", "LINEAGE": "🗺️"}


@st.cache_resource
def _session():
    return get_active_session()


@st.cache_data(ttl=30)
def _q(sql: str) -> pd.DataFrame:
    try:
        return _session().sql(sql).to_pandas()
    except Exception as e:
        st.session_state["_last_error"] = str(e)
        return pd.DataFrame()


def get_contract_health():
    return _q(f"SELECT * FROM {_CDB}.V_CONTRACT_HEALTH ORDER BY "
              f"CASE CONSUMER_CRITICALITY WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2 "
              f"WHEN 'MEDIUM' THEN 3 ELSE 4 END, CONTRACT_ID")


def get_scorecard(contract_id: str):
    return _q(f"SELECT * FROM {_CDB}.V_CONTRACT_SCORECARD "
              f"WHERE CONTRACT_ID = '{contract_id}'")


def get_results(contract_id: str):
    return _q(f"""
        SELECT vr.DIMENSION, vr.CHECK_NAME, vr.OBSERVED_VALUE, vr.EXPECTED_VALUE,
               vr.STATUS, vr.SEVERITY, vr.MESSAGE
        FROM {_CDB}.VALIDATION_RESULT vr
        JOIN (SELECT RUN_ID FROM {_CDB}.VALIDATION_RUN
              WHERE CONTRACT_ID = '{contract_id}'
              ORDER BY RUN_START DESC LIMIT 1) lr ON vr.RUN_ID = lr.RUN_ID
        ORDER BY CASE vr.STATUS WHEN 'FAIL' THEN 1 WHEN 'WARN' THEN 2 ELSE 3 END
    """)


def get_breaches():
    return _q(f"SELECT * FROM {_CDB}.V_BREACH_FEED WHERE STATUS = 'OPEN' LIMIT 50")


def get_coverage():
    return _q(f"SELECT * FROM {_CDB}.V_CONTRACT_COVERAGE")


def get_timeline(contract_id: str):
    return _q(f"SELECT * FROM {_CDB}.V_VALIDATION_TIMELINE "
              f"WHERE CONTRACT_ID = '{contract_id}' ORDER BY RUN_START")


def run_validation(contract_id: str, freshness_col: str = "_LOADED_AT"):
    try:
        df = _session().sql(
            f"CALL {_CDB}.VALIDATE_CONTRACT('{contract_id}', '{freshness_col}', 'MANUAL')"
        ).to_pandas()
        get_contract_health.clear() if hasattr(get_contract_health, "clear") else None
        _q.clear()
        return df.iloc[0, 0] if not df.empty else "Validation complete."
    except Exception as e:
        return f"Error: {e}"


# ============================================================================
# PAGE
# ============================================================================

def render_contracts_v2_page():
    st.markdown("""
    <div style="background:linear-gradient(135deg,#29B5E8 0%,#11567F 100%);
                padding:1.5rem 2rem;border-radius:16px;margin-bottom:1.5rem;color:white;">
        <h1 style="margin:0;font-size:1.75rem;">📜 Data Contracts on Horizon</h1>
        <p style="margin:.5rem 0 0;opacity:.9;">
        Schema · Quality · SLA · Lineage — enforced with Data Metric Functions, tags,
        ACCOUNT_USAGE lineage, and BLOCK/ALERT gates</p>
    </div>
    """, unsafe_allow_html=True)

    health = get_contract_health()
    breaches = get_breaches()
    coverage = get_coverage()

    if health.empty:
        st.warning(
            "No contracts found. Deploy the contract layer first:\n\n"
            "`./contracts/deploy.sh --connection <name>`\n\n"
            "or run `contracts/sql/00_*..09_*.sql` in order."
        )
        if st.session_state.get("_last_error"):
            st.caption(f"Last error: {st.session_state['_last_error']}")
        return

    # ---- Top metrics ----
    total = len(health)
    healthy = int((health["HEALTH_STATUS"] == "HEALTHY").sum())
    breached = int(health["HEALTH_STATUS"].isin(["BREACHED", "BLOCKED"]).sum())
    open_breaches = 0 if breaches.empty else len(breaches)
    avg_cov = 0 if coverage.empty else round(coverage["COVERAGE_PCT"].mean(), 0)

    m1, m2, m3, m4, m5 = st.columns(5)
    for col, val, label, hint in [
        (m1, total, "Active Contracts", "Bound to physical objects"),
        (m2, healthy, "Healthy", "Passed last validation"),
        (m3, breached, "Breached/Blocked", "Need attention"),
        (m4, open_breaches, "Open Breaches", "In breach ledger"),
        (m5, f"{avg_cov:.0f}%", "Estate Coverage", "Objects under contract"),
    ]:
        col.markdown(f"""
        <div style="background:white;border-radius:12px;padding:1.1rem;
                    border-left:4px solid #29B5E8;box-shadow:0 2px 8px rgba(0,0,0,.06);">
            <div style="font-size:1.6rem;font-weight:700;color:#11567F;">{val}</div>
            <strong>{label}</strong><br><small style="color:#64748B;">{hint}</small>
        </div>""", unsafe_allow_html=True)

    st.divider()
    tab_overview, tab_detail, tab_breaches, tab_coverage = st.tabs(
        ["📋 Contracts", "🔬 Contract Detail", "🚨 Breach Ledger", "📊 Coverage"]
    )

    # ---- TAB 1: Overview list ----
    with tab_overview:
        st.caption("One row per contract-bound object. Click a contract in the Detail tab to drill in.")
        for _, r in health.iterrows():
            icon, color, bg = _STATUS_STYLE.get(r["HEALTH_STATUS"], ("❓", "#64748B", "#F8FAFC"))
            enf = r.get("EFFECTIVE_ENFORCEMENT", "ALERT")
            enf_badge = {"BLOCK": "🛑 BLOCK", "ALERT": "🔔 ALERT", "MONITOR": "👁 MONITOR"}.get(enf, enf)
            dims = " ".join(
                f"{_DIM_ICON[d]}{'✅' if r.get(d + '_STATUS') == 'PASS' else '⚠️' if r.get(d + '_STATUS') == 'WARN' else '❌' if r.get(d + '_STATUS') == 'FAIL' else '·'}"
                for d in ["SCHEMA", "QUALITY", "SLA", "LINEAGE"]
            )
            st.markdown(f"""
            <div style="background:{bg};border-radius:10px;padding:.8rem 1rem;
                        border-left:4px solid {color};margin-bottom:.5rem;">
              <div style="display:flex;justify-content:space-between;align-items:center;">
                <div>
                  <span style="font-size:1.05rem;">{icon} <strong>{r['CONTRACT_NAME']}</strong></span>
                  <span style="color:#64748B;font-size:.82rem;margin-left:8px;">{r['FULL_OBJECT_PATH']}</span>
                </div>
                <div style="text-align:right;font-size:.8rem;">
                  <span style="color:{color};font-weight:700;">{r['HEALTH_STATUS']}</span> ·
                  {enf_badge} · <span style="color:#64748B;">{r.get('CONSUMER_CRITICALITY','')}</span>
                </div>
              </div>
              <div style="margin-top:.35rem;font-size:.95rem;letter-spacing:2px;">{dims}</div>
            </div>""", unsafe_allow_html=True)

    # ---- TAB 2: Detail ----
    with tab_detail:
        options = health["CONTRACT_ID"].tolist()
        labels = {r["CONTRACT_ID"]: f"{r['CONTRACT_NAME']} ({r['CONTRACT_ID']})"
                  for _, r in health.iterrows()}
        selected = st.selectbox("Contract", options, format_func=lambda x: labels.get(x, x))
        row = health[health["CONTRACT_ID"] == selected].iloc[0]

        c1, c2 = st.columns([3, 1])
        with c1:
            st.markdown(f"### {row['CONTRACT_NAME']}")
            st.markdown(
                f"**Object:** `{row['FULL_OBJECT_PATH']}`  ·  **Layer:** {row.get('DATA_LAYER','')}  ·  "
                f"**Classification:** {row.get('DATA_CLASSIFICATION','')}  ·  "
                f"**Producer:** {row.get('PRODUCER_TEAM','')}"
            )
        with c2:
            fresh_col = st.text_input("Freshness column", value="_LOADED_AT",
                                      help="Timestamp column used for SLA freshness")
            if st.button("▶️ Run Validation", type="primary", use_container_width=True):
                with st.spinner("Validating contract across all four dimensions…"):
                    result = run_validation(selected, fresh_col)
                st.success("Validation complete")
                st.json(result if isinstance(result, (dict, list)) else {"result": str(result)})
                st.rerun()

        # Scorecard
        score = get_scorecard(selected)
        if not score.empty:
            st.markdown("#### Dimension Scorecard (latest run)")
            dcols = st.columns(4)
            for i, dim in enumerate(["SCHEMA", "QUALITY", "SLA", "LINEAGE"]):
                d = score[score["DIMENSION"] == dim]
                with dcols[i]:
                    if d.empty:
                        st.markdown(f"**{_DIM_ICON[dim]} {dim}**  \n_not evaluated_")
                    else:
                        dd = d.iloc[0]
                        pct = dd.get("PASS_PCT", 0) or 0
                        clr = "#18794E" if pct == 100 else "#AD5700" if pct >= 50 else "#CD2B31"
                        st.markdown(
                            f"**{_DIM_ICON[dim]} {dim}**  \n"
                            f"<span style='font-size:1.5rem;font-weight:700;color:{clr};'>{pct:.0f}%</span>  \n"
                            f"<small>{int(dd['PASSED'])}✅ {int(dd['WARNED'])}⚠️ {int(dd['FAILED'])}❌</small>",
                            unsafe_allow_html=True,
                        )

        # Detailed check results
        results = get_results(selected)
        if not results.empty:
            st.markdown("#### Check Results")
            for _, res in results.iterrows():
                sc = {"PASS": "#18794E", "WARN": "#AD5700", "FAIL": "#CD2B31"}.get(res["STATUS"], "#64748B")
                si = {"PASS": "✅", "WARN": "⚠️", "FAIL": "❌"}.get(res["STATUS"], "·")
                st.markdown(f"""
                <div style="border-left:3px solid {sc};padding:.4rem .8rem;margin-bottom:.3rem;
                            background:white;border-radius:6px;font-size:.86rem;">
                  {si} <b>{_DIM_ICON.get(res['DIMENSION'],'')} {res['DIMENSION']}</b> —
                  {res['CHECK_NAME']}<br>
                  <span style="color:#475569;">{res['MESSAGE']}</span>
                </div>""", unsafe_allow_html=True)
        else:
            st.info("No validation results yet. Click **Run Validation** above.")

        # Timeline
        tl = get_timeline(selected)
        if _HAS_PLOTLY and not tl.empty and len(tl) > 1:
            st.markdown("#### Validation Timeline")
            status_val = {"PASS": 2, "WARN": 1, "FAIL": 0}
            tl["_v"] = tl["OVERALL_STATUS"].map(status_val)
            tl["RUN_START"] = pd.to_datetime(tl["RUN_START"])
            fig = go.Figure(go.Scatter(
                x=tl["RUN_START"], y=tl["_v"], mode="lines+markers",
                line=dict(color="#29B5E8", width=2),
                marker=dict(size=8, color=tl["_v"].map({2: "#18794E", 1: "#AD5700", 0: "#CD2B31"})),
            ))
            fig.update_layout(
                height=220, margin=dict(l=10, r=10, t=10, b=10),
                yaxis=dict(tickvals=[0, 1, 2], ticktext=["FAIL", "WARN", "PASS"], range=[-0.3, 2.3]),
                plot_bgcolor="white", paper_bgcolor="white",
            )
            st.plotly_chart(fig, use_container_width=True)

    # ---- TAB 3: Breaches ----
    with tab_breaches:
        if breaches.empty:
            st.success("No open breaches. All contracts are being honored. 🎉")
        else:
            st.caption(f"{len(breaches)} open breach(es), newest first")
            for _, b in breaches.iterrows():
                sev = b.get("SEVERITY", "ERROR")
                act = b.get("ENFORCEMENT_ACTION", "ALERTED")
                act_badge = {"BLOCKED": "🛑 BLOCKED", "ALERTED": "🔔 ALERTED",
                             "MONITORED": "👁 MONITORED"}.get(act, act)
                st.markdown(f"""
                <div style="background:#FFF1F2;border-radius:10px;padding:.8rem 1rem;
                            border-left:4px solid #CD2B31;margin-bottom:.5rem;">
                  <div style="display:flex;justify-content:space-between;">
                    <b>{_DIM_ICON.get(b['DIMENSION'],'')} {b['DIMENSION']} breach</b>
                    <span style="font-size:.8rem;">{act_badge} · {int(b.get('AGE_MINUTES',0))}m ago</span>
                  </div>
                  <div style="color:#7F1D1D;font-size:.87rem;margin-top:.3rem;">{b['SUMMARY']}</div>
                  <div style="color:#64748B;font-size:.78rem;margin-top:.2rem;">
                    {b.get('FULL_OBJECT_PATH','')} · criticality {b.get('CONSUMER_CRITICALITY','')}
                  </div>
                </div>""", unsafe_allow_html=True)

    # ---- TAB 4: Coverage ----
    with tab_coverage:
        st.markdown("### Estate Contract Coverage")
        st.caption("What share of the data estate is governed by a contract, by layer.")
        if coverage.empty:
            st.info("Coverage view returned no rows.")
        else:
            for _, c in coverage.iterrows():
                pct = c.get("COVERAGE_PCT", 0) or 0
                clr = "#18794E" if pct >= 60 else "#AD5700" if pct >= 25 else "#CD2B31"
                st.markdown(f"""
                <div style="background:white;border-radius:10px;padding:.8rem 1rem;
                            border:1px solid #E2E8F0;margin-bottom:.5rem;">
                  <div style="display:flex;justify-content:space-between;">
                    <b>{c['DATA_LAYER']} layer</b>
                    <span style="color:{clr};font-weight:700;">{pct:.0f}%</span>
                  </div>
                  <div style="background:#E2E8F0;border-radius:4px;height:8px;margin-top:.4rem;">
                    <div style="width:{pct}%;height:8px;border-radius:4px;background:{clr};"></div>
                  </div>
                  <small style="color:#64748B;">
                    {int(c['CONTRACTED_OBJECTS'])} of {int(c['TOTAL_OBJECTS'])} objects under contract</small>
                </div>""", unsafe_allow_html=True)


# Standalone entry point
if __name__ == "__main__":
    st.set_page_config(page_title="Data Contracts on Horizon", page_icon="📜", layout="wide")
    render_contracts_v2_page()
