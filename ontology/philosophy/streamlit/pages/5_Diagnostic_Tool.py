"""
Page 5: Diagnostic Tool
Interactive version of the five discovery questions.
Computes an ontological health score and maps weak answers
to DCA remediation steps.
"""

import streamlit as st

st.set_page_config(page_title="Diagnostic Tool | DCA Demo", layout="wide")

# ── Questions definition ───────────────────────────────────────

QUESTIONS = [
    {
        "id": "q1",
        "number": 1,
        "title": "Ownership",
        "question": (
            "Can you name the person — not a team, not a system — who is accountable "
            "when the data in your most critical reporting table is wrong?"
        ),
        "probe": (
            "If the answer involves a team, a shared mailbox, or 'it depends,' "
            "the ownership is diffuse. Diffuse ownership means no one is actually accountable."
        ),
        "strong_means": (
            "A named individual (or a named role filled by a named individual) who has "
            "authority to approve schema changes and is on-call for SLA breaches."
        ),
        "weak_means": (
            "Multiple teams share responsibility, or ownership was inherited when someone left, "
            "or no one has been formally assigned."
        ),
        "failure_mode": (
            "Without an accountable owner, data contracts cannot be enforced. "
            "Schema changes happen without notification. SLA breaches have no one to escalate to."
        ),
        "dca_fix": (
            "Assign a **Role Data Owner (RDO)** to each Semantic domain. "
            "Tag every Semantic table with `data_contract_owner`. "
            "The RDO is the institutional authority — they sign the contract."
        ),
        "snowflake_objects": ["Role hierarchy", "data_contract_owner tag", "GOVERNANCE.DATA_PRODUCT_CATALOG"],
    },
    {
        "id": "q2",
        "number": 2,
        "title": "Meaning",
        "question": (
            "If your Finance team and your Sales team both have a column called 'revenue,' "
            "are they measuring the same thing?"
        ),
        "probe": (
            "Ask them both to define it precisely — including whether it includes tax, "
            "how refunds are treated, and whether it is recognised or booked. "
            "Then compare the definitions."
        ),
        "strong_means": (
            "Both teams reference the same upstream Semantic table, "
            "or their definitions are documented and reconciled in a shared data contract."
        ),
        "weak_means": (
            "The definitions are different, or no one is sure, "
            "or they produce different numbers from 'the same' query."
        ),
        "failure_mode": (
            "Conflicting definitions produce the 'two versions of the truth' problem. "
            "Board meetings are derailed. Trust in data collapses."
        ),
        "dca_fix": (
            "Define a single canonical metric in a governed Semantic table. "
            "Attach a `data_contract_version` tag. "
            "Both domains must consume from the same source — no local copies without "
            "explicit contract amendments."
        ),
        "snowflake_objects": ["data_contract_version tag", "Semantic layer tables", "Table COMMENT field"],
    },
    {
        "id": "q3",
        "number": 3,
        "title": "Access Control",
        "question": (
            "Can an analyst who should only see aggregated revenue data "
            "actually query the raw transaction table with individual customer names and amounts?"
        ),
        "probe": (
            "This is a Snowflake privilege question. Try it — "
            "switch to the analyst role and run SELECT * on the raw table."
        ),
        "strong_means": (
            "The analyst role has USAGE only on SEMANTIC schemas. "
            "No access to RAW or CURATED. Masking policies are applied to PII columns. "
            "The access model is encoded in roles, not enforced by convention."
        ),
        "weak_means": (
            "Analysts were 'told' not to query raw tables, or access is controlled by a shared "
            "password, or the raw table is 'just not mentioned' in documentation."
        ),
        "failure_mode": (
            "Convention-based access control fails the moment a curious analyst or "
            "a misconfigured pipeline bypasses it. PII exposure and regulatory risk follow."
        ),
        "dca_fix": (
            "Implement layer-based access: consumers only get USAGE on SEMANTIC schemas. "
            "Apply masking policies to PII columns in CURATED. "
            "Remove all direct grants on RAW tables to consumer roles."
        ),
        "snowflake_objects": ["Role hierarchy", "Masking policies", "Schema-level USAGE grants", "pii_category tag"],
    },
    {
        "id": "q4",
        "number": 4,
        "title": "Quality & Freshness",
        "question": (
            "Before you use a critical dashboard today, how do you know the underlying "
            "data is fresh enough to make a decision from?"
        ),
        "probe": (
            "Is there an automated check, an alert, a timestamp on the dashboard? "
            "Or do you just assume it ran last night?"
        ),
        "strong_means": (
            "A freshness SLA is declared on the data product. "
            "An automated monitor checks against it. "
            "Consumers are notified — or the dashboard shows a staleness warning — "
            "when the SLA is breached."
        ),
        "weak_means": (
            "There is a pipeline that 'should' run nightly. "
            "If it fails, someone usually notices within a day or two."
        ),
        "failure_mode": (
            "Stale data used as if it were current. Decisions made on yesterday's (or last week's) "
            "numbers presented as today's. No one is accountable because no SLA was ever declared."
        ),
        "dca_fix": (
            "Declare `sla_freshness_hours` on every Semantic table via tag. "
            "Attach a `freshness_hours` Data Metric Function. "
            "Register freshness SLA in DATA_PRODUCT_CATALOG. "
            "Set up alerts via Snowflake notifications."
        ),
        "snowflake_objects": ["sla_freshness_hours tag", "Data Metric Functions (DMFs)", "GOVERNANCE.DATA_PRODUCT_CATALOG.SLA_FRESHNESS_HOURS"],
    },
    {
        "id": "q5",
        "number": 5,
        "title": "Automation Trust",
        "question": (
            "When your automated pipeline — or your AI model, or your Cortex agent — "
            "reads data to make a decision, does it know whether that data has been "
            "validated for its intended use?"
        ),
        "probe": (
            "Does the pipeline check data quality before acting? "
            "Does the AI model's training data have a contract version? "
            "If the upstream table changes schema, does the pipeline fail gracefully or silently produce garbage?"
        ),
        "strong_means": (
            "Automation consumes only from versioned, governed Semantic tables. "
            "Contract version is pinned in the pipeline configuration. "
            "Schema changes trigger a version bump and a review — not silent breakage."
        ),
        "weak_means": (
            "The pipeline reads from whatever table was there when it was built. "
            "No contract version. No quality gate before automation acts."
        ),
        "failure_mode": (
            "Automation amplifies bad data at machine speed. "
            "An ungoverned AI agent acting on stale or conflicted data "
            "produces decisions that are confidently wrong at scale."
        ),
        "dca_fix": (
            "Pin automation to specific contract versions. "
            "Implement pre-flight quality checks (DMF assertions) before pipeline execution. "
            "Treat contract version bumps as a deployment event — test before promoting."
        ),
        "snowflake_objects": ["data_contract_version tag", "DMF quality gates", "Streams + Tasks with quality assertions"],
    },
]

ANSWER_WEIGHTS = {"Strong": 20, "Weak": 5, "Unknown": 0}

SCORE_BANDS = [
    (85, 100, "Institutionally Mature",
     "#28A745",
     "Your platform has strong ontological foundations. "
     "The dependency chain is intact: people are accountable, data has declared meaning, "
     "governance is enforced, and automation can be trusted. "
     "Focus now on maintaining maturity as the platform scales."),
    (60, 84, "Structurally Incomplete",
     "#FFC107",
     "You have the right instincts but gaps in execution. "
     "Some objects are governed; others are not. The platform works today but is fragile — "
     "a team change or a schema drift will expose the gaps. "
     "Prioritise the weak answers below and work through them systematically."),
    (30, 59, "Pre-Institutional",
     "#E67E22",
     "Your platform has data but limited governance. "
     "Objects exist without declared meaning, ownership is diffuse, "
     "and automation is running on trust rather than enforcement. "
     "The risk of a 'two versions of the truth' incident is high. "
     "Start with ownership (Q1) and work forward through the chain."),
    (0, 29, "Brute Fact Repository",
     "#FF4444",
     "Your platform is a collection of uninterpreted brute facts. "
     "Data exists but institutional meaning does not. "
     "Governance is aspirational rather than enforced. "
     "No automation built on this foundation can be trusted. "
     "Begin at the beginning: assign accountable owners before doing anything else."),
]


def get_band(score: int):
    for lo, hi, label, colour, desc in SCORE_BANDS:
        if lo <= score <= hi:
            return label, colour, desc
    return SCORE_BANDS[-1][2:]


# ── Page header ───────────────────────────────────────────────
st.title("Diagnostic Tool")
st.markdown(
    "Five discovery questions that expose the ontological health of a data platform. "
    "Score each question based on what you observe — not what the documentation says."
)
st.markdown("---")

# ── Instructions ──────────────────────────────────────────────
with st.expander("How to use this tool", expanded=False):
    st.markdown(
        """
**For SE-led discovery:** Ask each question aloud with the customer.
Listen for hedging language: "usually," "I think," "the team does that."
Score based on evidence, not confidence.

**Answer key:**
- **Strong** — Enforced by technology, documented, and demonstrable right now
- **Weak** — True in principle, inconsistently applied, relies on convention
- **Unknown** — Not known, never discussed, or "that's a good question"

**Score bands:**
| Score | Status |
|-------|--------|
| 85–100 | Institutionally Mature |
| 60–84  | Structurally Incomplete |
| 30–59  | Pre-Institutional |
| 0–29   | Brute Fact Repository |
        """
    )

st.markdown("---")

# ── Question scoring ──────────────────────────────────────────
answers = {}

for q in QUESTIONS:
    with st.container():
        st.markdown(f"### Question {q['number']}: {q['title']}")

        col_q, col_a = st.columns([3, 1])

        with col_q:
            st.markdown(f"**{q['question']}**")
            with st.expander("Probing question + what to listen for"):
                st.markdown(f"**Probe:** {q['probe']}")
                st.markdown(f"**Strong signal:** {q['strong_means']}")
                st.markdown(f"**Weak signal:** {q['weak_means']}")

        with col_a:
            answer = st.radio(
                "Score:",
                options=["Strong", "Weak", "Unknown"],
                key=q["id"],
                horizontal=False,
            )
            answers[q["id"]] = answer
            score_pts = ANSWER_WEIGHTS[answer]
            colour = {"Strong": "#28A745", "Weak": "#FFC107", "Unknown": "#FF4444"}[answer]
            st.markdown(
                f'<div style="text-align:center;font-size:1.8em;color:{colour};">'
                f'<strong>{score_pts}</strong><br>'
                f'<span style="font-size:0.5em;color:#999;">/ 20 pts</span></div>',
                unsafe_allow_html=True,
            )

        st.markdown("---")

# ── Score calculation ─────────────────────────────────────────
total_score = sum(ANSWER_WEIGHTS[v] for v in answers.values())
band_label, band_colour, band_desc = get_band(total_score)

# ── Results panel ─────────────────────────────────────────────
st.markdown("## Results")

score_col, label_col = st.columns([1, 3])

with score_col:
    st.markdown(
        f"""
<div style="background:{band_colour};border-radius:16px;padding:24px;text-align:center;">
  <div style="font-size:3.5em;font-weight:900;color:#000;">{total_score}</div>
  <div style="font-size:1em;color:#000;opacity:0.7;">out of 100</div>
</div>
        """,
        unsafe_allow_html=True,
    )

with label_col:
    st.markdown(
        f"""
<div style="background:#1a1a2e;border-left:5px solid {band_colour};
            padding:20px;border-radius:8px;min-height:100px;">
  <h3 style="color:{band_colour};margin-top:0;">{band_label}</h3>
  <p style="color:#c0c0c0;">{band_desc}</p>
</div>
        """,
        unsafe_allow_html=True,
    )

# ── Remediation map ───────────────────────────────────────────
weak_questions = [q for q in QUESTIONS if answers.get(q["id"]) in ("Weak", "Unknown")]

if weak_questions:
    st.markdown("---")
    st.markdown("## Remediation Plan")
    st.markdown(
        f"**{len(weak_questions)} question(s)** scored Weak or Unknown. "
        "Address them in order — the dependency chain means Q1 gaps block progress on Q3–Q5."
    )

    for i, q in enumerate(weak_questions, 1):
        answer_val = answers.get(q["id"])
        colour = "#FFC107" if answer_val == "Weak" else "#FF4444"

        with st.expander(
            f"{'⚠️' if answer_val == 'Weak' else '❌'} Q{q['number']}: {q['title']} — {answer_val}"
        ):
            col_prob, col_fix = st.columns(2)

            with col_prob:
                st.markdown("**Failure mode**")
                st.markdown(q["failure_mode"])

            with col_fix:
                st.markdown("**DCA remediation**")
                st.markdown(q["dca_fix"])
                st.markdown("**Snowflake objects involved:**")
                for obj in q["snowflake_objects"]:
                    st.markdown(f"- `{obj}`")
else:
    st.markdown("---")
    st.success(
        "All five questions scored Strong. "
        "The dependency chain is intact. "
        "Continue to the Contract Registry to verify your governance metadata is complete."
    )

# ── Export summary ────────────────────────────────────────────
st.markdown("---")
st.markdown("## Session Summary")

summary_lines = [f"DCA Diagnostic — Score: {total_score}/100 ({band_label})", ""]
for q in QUESTIONS:
    a = answers.get(q["id"], "Unknown")
    summary_lines.append(f"Q{q['number']} {q['title']}: {a} ({ANSWER_WEIGHTS[a]} pts)")
summary_lines.append("")
if weak_questions:
    summary_lines.append("Priority remediations:")
    for q in weak_questions:
        summary_lines.append(f"  - Q{q['number']} {q['title']}: {q['dca_fix'][:80]}...")

st.code("\n".join(summary_lines), language="text")
