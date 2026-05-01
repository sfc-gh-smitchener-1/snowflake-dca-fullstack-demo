"""
Page 1: Architecture
The People → Data → Governance → Automation dependency chain.
Static narrative page — no live queries.
"""

import streamlit as st

st.set_page_config(page_title="Architecture | DCA Demo", layout="wide")

st.title("The Dependency Chain")
st.markdown(
    "Data platforms have an ontological dependency that cannot be reversed. "
    "Understanding it explains why most platforms fail — and how to fix them."
)
st.markdown("---")

# ── Main dependency chain ─────────────────────────────────────
st.markdown("## The Four-Layer Dependency")

col1, col2, col3, col4 = st.columns(4)

with col1:
    st.markdown(
        """
<div style="background:#1a1a2e;border:2px solid #29B5E8;border-radius:10px;padding:24px;text-align:center;min-height:220px;">
  <div style="font-size:2em;">👥</div>
  <h3 style="color:#29B5E8;margin:8px 0;">People</h3>
  <p style="color:#c0c0c0;font-size:0.9em;">
    CDOs, RDOs, Data Owners, Consumers.<br><br>
    Only people can assign <strong>meaning</strong> to data.
    Without accountable humans, governance is theatre.
  </p>
  <div style="background:#0d1117;border-radius:6px;padding:8px;margin-top:12px;">
    <code style="color:#29B5E8;font-size:0.75em;">dca_governance_admin<br>finance_data_owner<br>sales_data_consumer</code>
  </div>
</div>
        """,
        unsafe_allow_html=True,
    )

with col2:
    st.markdown(
        """
<div style="background:#1a1a2e;border:2px solid #28A745;border-radius:10px;padding:24px;text-align:center;min-height:220px;">
  <div style="font-size:2em;">🗄️</div>
  <h3 style="color:#28A745;margin:8px 0;">Data</h3>
  <p style="color:#c0c0c0;font-size:0.9em;">
    Three layers of increasing meaning.<br><br>
    <strong>Raw</strong> → brute facts.<br>
    <strong>Curated</strong> → conformance.<br>
    <strong>Semantic</strong> → declared meaning.
  </p>
  <div style="background:#0d1117;border-radius:6px;padding:8px;margin-top:12px;">
    <code style="color:#28A745;font-size:0.75em;">RAW → CURATED<br>→ SEMANTIC_FINANCE<br>→ SEMANTIC_SALES</code>
  </div>
</div>
        """,
        unsafe_allow_html=True,
    )

with col3:
    st.markdown(
        """
<div style="background:#1a1a2e;border:2px solid #FFC107;border-radius:10px;padding:24px;text-align:center;min-height:220px;">
  <div style="font-size:2em;">🏛️</div>
  <h3 style="color:#FFC107;margin:8px 0;">Governance</h3>
  <p style="color:#c0c0c0;font-size:0.9em;">
    The institutional facts that give data meaning.<br><br>
    Tags, masking policies, data contracts, quality metrics.
    Without governance, data has no <em>standing</em>.
  </p>
  <div style="background:#0d1117;border-radius:6px;padding:8px;margin-top:12px;">
    <code style="color:#FFC107;font-size:0.75em;">Tags · Policies<br>Contracts · DMFs<br>Ownership</code>
  </div>
</div>
        """,
        unsafe_allow_html=True,
    )

with col4:
    st.markdown(
        """
<div style="background:#1a1a2e;border:2px solid #9B59B6;border-radius:10px;padding:24px;text-align:center;min-height:220px;">
  <div style="font-size:2em;">⚡</div>
  <h3 style="color:#9B59B6;margin:8px 0;">Automation</h3>
  <p style="color:#c0c0c0;font-size:0.9em;">
    Pipelines, Cortex AI, dashboards, agents.<br><br>
    Automation can only be trusted when the data
    it operates on has been <strong>governed</strong>.
  </p>
  <div style="background:#0d1117;border-radius:6px;padding:8px;margin-top:12px;">
    <code style="color:#9B59B6;font-size:0.75em;">Tasks · Streams<br>Cortex · Agents<br>Marketplace</code>
  </div>
</div>
        """,
        unsafe_allow_html=True,
    )

# Arrow connectors
st.markdown(
    """
<div style="text-align:center;font-size:1.5em;color:#555;margin:16px 0;letter-spacing:0.5em;">
→ → →
</div>
    """,
    unsafe_allow_html=True,
)

st.markdown("---")

# ── Why the chain breaks ──────────────────────────────────────
st.markdown("## Where Most Platforms Break")

col_a, col_b = st.columns([1, 1])

with col_a:
    st.markdown("#### The Inversion Problem")
    st.markdown(
        """
Most organisations build in the wrong order:

1. They buy tooling *(Automation first)*
2. They ingest data *(Data second)*  
3. They add governance retroactively *(Governance third)*
4. They never clarify accountability *(People assumed)*

The result is **automation running on ungoverned data** —
correct pipelines producing wrong decisions because the
institutional meaning was never established.
        """
    )

with col_b:
    st.markdown("#### The Ontological Test")
    st.markdown(
        """
For any table in your platform, ask five questions:

| # | Question | Failure signal |
|---|----------|----------------|
| 1 | Who owns this? | No owner role |
| 2 | What does it mean? | No contract or comment |
| 3 | Who can consume it? | No access policy |
| 4 | Is it fresh enough to trust? | No quality monitor |
| 5 | Are the definitions aligned? | Conflicting columns across domains |

If you cannot answer all five, the object is a **brute fact**
masquerading as an institutional fact.

> *Use the Diagnostic Tool (page 5) to score your environment.*
        """
    )

st.markdown("---")

# ── Three account topology ────────────────────────────────────
st.markdown("## The Three-Account Topology")
st.markdown(
    "In a fully deployed DCA, the three layers map to separate Snowflake accounts "
    "with distinct governance zones. This demo simulates all three in a single account "
    "using schema-level isolation."
)

col_x, col_y, col_z = st.columns(3)

with col_x:
    st.markdown(
        """
<div style="background:#0d1117;border:1px solid #29B5E8;border-radius:8px;padding:20px;">
  <h4 style="color:#29B5E8;">Innovation Account</h4>
  <p style="color:#999;font-size:0.85em;">Exploration, prototyping, ad-hoc analysis.</p>
  <ul style="color:#c0c0c0;font-size:0.85em;">
    <li>No governance obligations</li>
    <li>Direct RAW access for analysts</li>
    <li>No downstream consumers</li>
    <li>Data deleted after 90 days</li>
  </ul>
  <div style="color:#29B5E8;font-size:0.75em;margin-top:8px;">Demo: RAW schema</div>
</div>
        """,
        unsafe_allow_html=True,
    )

with col_y:
    st.markdown(
        """
<div style="background:#0d1117;border:1px solid #FFC107;border-radius:8px;padding:20px;">
  <h4 style="color:#FFC107;">Pre-Production Account</h4>
  <p style="color:#999;font-size:0.85em;">Governed development. Contracts drafted.</p>
  <ul style="color:#c0c0c0;font-size:0.85em;">
    <li>CURATED layer with masking enforced</li>
    <li>Contract version = DRAFT</li>
    <li>Ownership assigned before promotion</li>
    <li>Quality gates before Production</li>
  </ul>
  <div style="color:#FFC107;font-size:0.75em;margin-top:8px;">Demo: CURATED schema</div>
</div>
        """,
        unsafe_allow_html=True,
    )

with col_z:
    st.markdown(
        """
<div style="background:#0d1117;border:1px solid #28A745;border-radius:8px;padding:20px;">
  <h4 style="color:#28A745;">Production Account</h4>
  <p style="color:#999;font-size:0.85em;">Governed data products. Contracts ACTIVE.</p>
  <ul style="color:#c0c0c0;font-size:0.85em;">
    <li>SEMANTIC layer only for consumers</li>
    <li>All contracts ACTIVE + versioned</li>
    <li>SLA monitoring + alerting live</li>
    <li>Marketplace-ready listings</li>
  </ul>
  <div style="color:#28A745;font-size:0.75em;margin-top:8px;">Demo: SEMANTIC_* schemas</div>
</div>
        """,
        unsafe_allow_html=True,
    )
