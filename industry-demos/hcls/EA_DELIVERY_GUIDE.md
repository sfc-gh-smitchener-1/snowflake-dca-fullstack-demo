# HCLS Enterprise Delivery Guide

## For Enterprise Architects & Industry Team

### Document Purpose

This guide enables Snowflake Enterprise Architects and Industry Specialists to deliver a technically rigorous HCLS demo that demonstrates the full power of the Snowflake platform for healthcare. It is designed for pointed delivery to VP+ decision-makers at health systems, payer organizations, and life sciences companies.

This is one of the most comprehensive Snowflake HCLS demos ever built — three integrated source systems, automated PHI governance, cross-system analytics with statistical correlation, comorbidity indexing, and payer intelligence. All running on Business Critical with cross-region failover. Treat it accordingly.

---

## 1. Positioning Statement (30 Seconds)

> "This is a HIPAA-governed healthcare platform running on Snowflake Business Critical. Three source systems — Epic, Workday, Payer — unified under a single security perimeter with automated PHI classification, role-based masking, cross-region failover, and continuous compliance scoring. One BAA. One audit trail. One platform. No middleware, no additional vendors, no data movement outside your control."

---

## 2. Audience Targeting Matrix

| Audience | Primary Pain | Demo Focus | Key Parts | Close Move |
|---|---|---|---|---|
| **CMIO / CMO** | Outcomes variability, quality reporting | Staffing-outcomes correlation, care pathways | Parts 1, 6, 7 | "Can we run this against your FACT_ENCOUNTERS?" |
| **CNO / VP Nursing** | Staffing models, burnout, ratios | Workday integration, shift-level analysis | Parts 6, Signal Graph | "What's your current ratio monitoring approach?" |
| **CFO / VP Revenue Cycle** | Denial rates, AR days, underpayment | Payer response by CCI, care gap analysis | Parts 7, 8 | "What's your current denial rate by payer?" |
| **CPO / Compliance** | HIPAA gaps, PHI governance | Continuous compliance scoring, PHI detection | Parts 2, 3, 4 | "Can you prove PHI classification completeness today?" |
| **CIO / VP Data** | Platform consolidation, total cost | Full platform architecture, security posture, 3-system unification | All parts | "How many tools and BAAs are you managing today?" |
| **VP Population Health** | Risk stratification, care gaps | CCI, comorbidity clusters, HEDIS measures | Parts 7, quality measures | "What's your current risk stratification method?" |
| **Payer Medical Director** | Utilization management, network adequacy | UR analytics, plan-of-care gaps | Part 8, auth turnaround | "How do you prioritize UR cases today?" |

---

## 3. Pre-Demo Checklist (SE Setup)

Complete every item before the customer arrives. No exceptions.

### Environment

- [ ] Snowflake Business Critical account with ACCOUNTADMIN access and ONTOLOGY_ADMIN role
- [ ] Core DCA scripts 01-15 deployed and verified
- [ ] Inference service running (background)
- [ ] Verify Business Critical edition: `SELECT SYSTEM$IS_APPLICATION_ROLE_ENABLED('SNOWFLAKE.SECURITY');`
- [ ] Verify network policy active: `SHOW PARAMETERS LIKE 'NETWORK_POLICY' IN ACCOUNT;`
- [ ] Verify failover group healthy: check replication lag < 15 min

### Data

- [ ] FHIR data generated: `python generate_hcls_data.py --output ../data`
- [ ] Workday data generated: `python generate_workday_hcm_data.py --output ../data`
- [ ] Payer data generated: `python generate_payer_data.py --output ../data`
- [ ] All CSVs uploaded and loaded into RAW/CURATED layers

### Analytics & Governance

- [ ] HCLS SQL scripts 01-07 deployed
- [ ] `CALL SP_HCLS_MASTER_ORCHESTRATOR();` completed successfully (check HCLS_MASTER_RUN snapshot)
- [ ] Verify node counts: `SELECT source_system, COUNT(*) FROM ONTOLOGY_GRAPH_NODES GROUP BY 1;`
  - Expected: FHIR (~70K+), WORKDAY_HCM (~50K+), PAYER (~30K+)
- [ ] Verify edge counts: `SELECT edge_type, COUNT(*) FROM ONTOLOGY_GRAPH_EDGES GROUP BY 1 ORDER BY 2 DESC;`

### Streamlit & Presentation

- [ ] Streamlit app accessible — Page 6 (Knowledge Graph) and Page 7 (Signal Graph) render
- [ ] SQL Worksheet pre-loaded with all 8 demo queries in separate tabs (copy from DEMO_SCRIPT.md)
- [ ] Test every query from DEMO_SCRIPT.md — confirm non-zero results
- [ ] Have backup screenshots of Signal Graph and governance dashboards (network failure contingency)
- [ ] ARCHITECTURE_STRATEGY.md Mermaid diagrams rendered as images (use `md-to-gdoc` or browser screenshot)
- [ ] ONTOLOGY_MAP.md open in a separate tab for deep technical reference

### Logistics

- [ ] Arrive 15 min early to test connectivity and projector
- [ ] HDMI/USB-C adapter confirmed working
- [ ] Video conferencing link tested for remote participants

---

## 4. Talk Track — Full 30-Minute Delivery

### Opening Hook (2 min)

Choose based on audience. Deliver with conviction — these numbers are real.

**For Health Systems:**
> "Healthcare runs on trust — trust that patient data is classified, masked, and auditable at every layer. Today I'll show you how Snowflake's platform eliminates HIPAA blind spots automatically. Every PHI column tagged. Every access masked by role. Every pipeline monitored. Every bit replicated to a failover region. And from that governed foundation, we derive staffing-outcome correlations and payer intelligence that no single system can produce alone."

**For Payers:**
> "Your compliance team spends months on audits. Your revenue cycle team fights denials blind. Your medical directors review prior auths without comorbidity context. What if one governed platform — with automated classification, real-time access controls, and cross-system analytics — could give all three teams what they need? That's what we'll show you in 30 minutes."

**For Life Sciences:**
> "Real-world evidence requires governed data. Snowflake gives you HIPAA-compliant governance at the platform level — automated PHI tagging, de-identification provenance tracking, role-based access enforcement — so your research teams can focus on science, not compliance paperwork."

---

### Part 1: Governed Clinical Data Platform (3 min)

**Transition**: "Let me show you what this looks like."

**Setup**: We've unified Epic, Workday, and Payer data under a single governance framework. The platform automatically tracks entities, relationships, and lineage across all three systems.

**Key Query**:
```sql
SELECT node_type, source_system, COUNT(*) AS cnt
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
WHERE source_system = 'FHIR' OR layer = 'METADATA'
GROUP BY node_type, source_system
ORDER BY cnt DESC;
```

**Insight Callout**: "We have [X] clinical nodes linked to [Y] metadata nodes. The platform connects the clinical world to the technical world — every patient record knows which Snowflake table stores it, which masking policy protects it, and who last accessed it."

**Pause Point**: "How do you currently link your clinical data model to your data governance inventory?"

**Objection Handling**:
- *"We already have a data catalog."* → "Catalogs describe tables. This platform describes relationships — between patients, between systems, between data and governance. It's the layer above a catalog."
- *"This seems like a lot of nodes."* → "Each node is a real entity with real governance implications. The question isn't whether you have too many nodes — it's whether you know which ones contain PHI."

---

### Part 2: Automated PHI Detection (3 min)

**Transition**: "Now let's see what happens when we ask the platform: where is PHI propagating without HIPAA classification?"

**Setup**: The platform traces data lineage and flags columns receiving patient data from PHI-tagged sources that lack their own classification — no manual audit required.

**Key Query**:
```sql
SELECT severity, description, suggested_action
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS
WHERE recommendation_type = 'PII_PROPAGATION'
ORDER BY CASE severity WHEN 'HIGH' THEN 1 WHEN 'MEDIUM' THEN 2 ELSE 3 END;
```

**Insight Callout**: "These are compliance blind spots — columns receiving PHI without HIPAA tags. Without automated lineage tracing, you'd need a manual audit across every pipeline to find them."

**Pause Point**: "How confident are you that every downstream copy of PHI is classified in your environment?"

**Objection Handling**:
- *"Our EHR vendor handles HIPAA."* → "For data at rest in the EHR, yes. But what about data extracted for analytics, research, or population health? That's where gaps appear."
- *"We do annual HIPAA audits."* → "Annual means 364 days of drift. This is continuous — every pipeline refresh re-evaluates."

---

### Part 3: Cross-System Patient Resolution (3 min)

**Transition**: "PHI governance requires knowing which person is behind each record. Let's see how the platform resolves patient identity across systems."

**Setup**: Snowflake's stored procedures match patients across systems using probabilistic rules (Jaccard similarity on name tokens + DOB) — no external MPI appliance required.

**Key Query**:
```sql
SELECT c.cluster_id, c.cluster_label, c.confidence,
       n.display_name, n.source_system, n.node_type
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_ENTITY_CLUSTERS c
JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n ON c.node_id = n.node_id
WHERE n.node_type IN ('PATIENT', 'EMPLOYEE')
  AND c.confidence > 0.8
ORDER BY c.cluster_id, c.confidence DESC;
```

**Insight Callout**: "Same person, two systems, resolved automatically. No external MPI needed — Snowflake does it natively with stored procedures."

**Pause Point**: "What's your current approach to patient matching across EHR and workforce systems?"

**Objection Handling**:
- *"Entity resolution is an MPI problem."* → "Traditional MPIs require expensive appliances and deterministic rules. Automated matching uses probabilistic rules that improve with each refresh."
- *"0.8 confidence isn't high enough."* → "Configurable threshold. In production, add MRN cross-references and confidence rises above 0.95."

---

### Part 4: Continuous Compliance Scoring (3 min)

**Transition**: "Now that we know where PHI lives and who it belongs to — can we score compliance continuously?"

**Setup**: Every data object gets a HIPAA governance score from 0 to 1, computed from tag coverage, ownership, access controls, BAA status, and de-identification tracking. This replaces your annual assessment with continuous, automated scoring.

**Key Query**:
```sql
SELECT n.display_name, n.node_type,
       ROUND(s.overall_score, 2) AS hipaa_score,
       ROUND(s.tag_coverage, 2) AS classification,
       ROUND(s.ownership_score, 2) AS ownership
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES s
JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n ON s.node_id = n.node_id
WHERE n.source_system IN ('FHIR', 'SNOWFLAKE')
ORDER BY s.overall_score ASC
LIMIT 10;
```

**Insight Callout**: "Anything below 0.4 needs immediate attention. This replaces your annual manual assessment with continuous, automated scoring."

**Pause Point**: "If I told you one of your clinical tables scores 0.2 on HIPAA compliance — what would you do with that information?"

**Objection Handling**:
- *"How is the score calculated?"* → "Weighted composite: tag coverage (30%), ownership (20%), access controls (20%), BAA coverage (15%), de-identification tracking (15%). All configurable."
- *"Can this satisfy an OCR audit?"* → "The governance scores, recommendation history, and access edges provide documentary evidence of continuous compliance monitoring — stronger than point-in-time audits."

---

### Part 5: Streamlit Visualization (2 min)

**Transition**: "Let me show you what the privacy officer sees."

Navigate to Streamlit:
1. **Page 6: Knowledge Graph** — Filter: Source System = FHIR, Layer = BUSINESS. Show clinical graph with patient-centered view.
2. **Governance Scores tab** — Filter to scores < 0.4. Show red/yellow/green distribution.
3. **Recommendations tab** — Filter to HIPAA-specific recommendations.

> "The privacy officer can see compliance posture in real-time. No more waiting for the annual audit to discover gaps."

---

### Part 6: Staffing-Outcomes Correlation (5 min)

**Transition**: "We've covered governance. Now let's connect clinical data to workforce data. This is where the CNO gets excited."

**Setup**: When we overlay Workday staffing on clinical outcomes, powerful patterns emerge that no single system could reveal alone. Pearson correlation with Fisher z-transform p-values — cross-system analytics that connect workforce decisions to patient outcomes.

**Key Query 1** — Units with highest adverse event correlation:
```sql
SELECT 
    sc.unit_type, sc.department_name,
    ROUND(AVG(sc.actual_ratio), 1) AS avg_nurse_ratio,
    ROUND(AVG(sc.overtime_pct) * 100, 1) AS overtime_pct,
    ROUND(SUM(CASE WHEN e.readmission_30day THEN 1 ELSE 0 END)::FLOAT 
          / NULLIF(COUNT(*), 0) * 100, 1) AS readmission_rate_pct,
    COUNT(*) AS encounter_count
FROM SEM_DEV.HCLS_ANALYTICS.HCLS_STAFFING_CONTEXT sc
JOIN CURATED_DEV.FHIR.FACT_ENCOUNTERS e 
    ON sc.org_id = e.org_id AND e.admit_date = sc.shift_date
WHERE sc.actual_ratio > sc.target_nurse_ratio * 1.2
GROUP BY 1, 2
ORDER BY readmission_rate_pct DESC
LIMIT 10;
```

**Insight Callout**: "Units where nurse-patient ratios exceeded targets by 20%+ show [X]% readmissions vs [Y]% when adequately staffed. Cross-system analytics computed this correlation automatically."

**Key Query 2** — Cross-system relationship edges:
```sql
SELECT e.edge_type, n1.display_name AS encounter, n2.display_name AS staffing_context,
       e.properties:correlation_strength::FLOAT AS correlation
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n1 ON e.source_node_id = n1.node_id
JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n2 ON e.target_node_id = n2.node_id
WHERE e.edge_type = 'INFLUENCED_BY'
ORDER BY correlation DESC
LIMIT 5;
```

**Insight Callout**: "Cross-system analytics made this connection automatically — INFLUENCED_BY edges with correlation strength. Traditional BI would require manually joining 5+ tables across two systems."

**Pause Point**: "Do you currently have any visibility into how staffing decisions affect clinical outcomes?"

**Objection Handling**:
- *"Correlation isn't causation."* → "Correct. But r=0.68 with p<0.01 is a signal worth investigating. The platform gives you the hypothesis — your clinical team validates it."
- *"Can we use this for predictive staffing?"* → "Yes. The time-series data enables forecasting models. The platform preserves the temporal dimension for trend analysis."

---

### Part 7: Comorbidity Intelligence (5 min)

**Transition**: "Staffing affects outcomes. But comorbidity affects EVERYTHING — cost, LOS, denial rates, readmissions. Let me show you how."

**Setup**: Charlson Comorbidity Index computed from ICD-10 codes, stratified into LOW/MODERATE/HIGH/SEVERE tiers. Drives both clinical risk assessment and payer behavior analysis.

**Key Query 1** — CCI distribution and cost impact:
```sql
SELECT 
    pc.cci_tier,
    COUNT(DISTINCT pc.patient_id) AS patient_count,
    ROUND(AVG(pc.cci_score), 1) AS avg_score,
    ROUND(AVG(e.total_charges), 0) AS avg_cost_per_encounter,
    ROUND(AVG(e.los_days), 1) AS avg_los,
    ROUND(SUM(CASE WHEN e.readmission_30day THEN 1 ELSE 0 END)::FLOAT 
          / NULLIF(COUNT(*), 0) * 100, 1) AS readmission_pct
FROM SEM_DEV.HCLS_ANALYTICS.HCLS_PATIENT_COMORBIDITY pc
JOIN CURATED_DEV.FHIR.FACT_ENCOUNTERS e ON pc.patient_id = e.patient_id
WHERE e.encounter_class = 'INPATIENT'
GROUP BY 1
ORDER BY CASE pc.cci_tier 
    WHEN 'LOW' THEN 1 WHEN 'MODERATE' THEN 2 
    WHEN 'HIGH' THEN 3 WHEN 'SEVERE' THEN 4 END;
```

**Insight Callout**: "SEVERE tier patients cost [X]x more per encounter with [Y]x longer stays. This is where population health and payer negotiations intersect."

**Key Query 2** — Top comorbidity clusters:
```sql
SELECT condition_a_desc, condition_b_desc, shared_patient_count, 
       ROUND(co_occurrence_rate * 100, 1) AS co_occurrence_pct
FROM SEM_DEV.HCLS_ANALYTICS.HCLS_COMORBIDITY_PAIRS
ORDER BY shared_patient_count DESC
LIMIT 10;
```

**Insight Callout**: "Diabetes + Hypertension appears in [X]% of the population. These clusters predict which patients will consume the most resources and face the most payer friction."

**Pause Point**: "What's your current approach to comorbidity stratification? Is it manual chart review, or automated?"

**Objection Handling**:
- *"We already use CMS risk adjustment (HCC)."* → "CCI and HCC measure different things — CCI predicts mortality, HCC predicts cost. This platform can compute both. The point is: comorbidity data should drive operational decisions, not just actuarial models."
- *"Our population health team does this."* → "Do they have payer response data correlated against comorbidity? That's what Part 8 delivers."

---

### Part 8: Payer Response Analysis (5 min)

**Transition**: "Now the payer dimension. How do insurance companies respond to patients with high comorbidity burden? This analysis reveals patterns that inform contract negotiation, prior auth strategy, and revenue cycle operations."

**Key Query 1** — Denial rate by CCI tier and payer:
```sql
SELECT cci_tier, payer_name, 
       ROUND(denial_rate * 100, 1) AS denial_pct,
       ROUND(avg_adjudication_days, 0) AS days_to_decide,
       ROUND(prior_auth_rate * 100, 1) AS prior_auth_pct,
       total_claims
FROM SEM_DEV.HCLS_ANALYTICS.HCLS_PAYER_METRICS
WHERE total_claims > 100
ORDER BY cci_tier, denial_rate DESC;
```

**Insight Callout**: "SEVERE tier patients face [X]% denial rates with [Y]-day adjudication cycles. That's a revenue cycle problem hiding in comorbidity data that only cross-system analytics connects."

**Key Query 2** — Plan of care gaps:
```sql
SELECT cci_tier, payer_name,
       ROUND(AVG(approved_days), 1) AS avg_approved,
       ROUND(AVG(actual_days), 1) AS avg_actual,
       ROUND(AVG(variance_days), 1) AS avg_gap,
       ROUND(SUM(CASE WHEN readmitted_30day THEN 1 ELSE 0 END)::FLOAT 
             / NULLIF(COUNT(*), 0) * 100, 1) AS readmit_pct
FROM SEM_DEV.HCLS_ANALYTICS.HCLS_CARE_GAPS
WHERE gap_type = 'EARLY_DISCHARGE'
GROUP BY 1, 2
ORDER BY avg_gap DESC;
```

**Insight Callout**: "Patients discharged before clinical need have a [X]% readmission rate for SEVERE comorbidity. This is the data you bring to payer negotiations."

**Pause Point**: "What data do you currently use when renegotiating payer contracts?"

**Objection Handling**:
- *"Our revenue cycle team handles payer negotiations."* → "This arms them with data they've never had — comorbidity-adjusted denial rates by payer. Ask them if they'd want this."
- *"Payer data is messy."* → "The generator creates clean synthetic data. For production, 837/835 claim files land in RAW and the curated layer normalizes them. Same pattern."

---

### Part 9: Signal Graph (if time permits, 2 min)

Navigate to **Page 7: Ontological Signal Graph** in Streamlit.

> "This is the visual representation of the entire analytics platform — clinical nodes in blue, workforce in green, payer in gold, governance in red. Edges show the cross-system relationships we've been querying. The thicker the edge, the stronger the signal."

Use this to answer "show me the big picture" requests or to visually demonstrate the three-system integration.

---

### Closing (2 min)

Choose based on audience engagement during the demo:

**Technical Close** (audience asked detailed questions):
> "We can deploy this against your actual data in a proof of value. What system should we connect first — Epic, Workday, or your claims warehouse?"

**Business Close** (audience focused on outcomes):
> "Based on what we've seen today, which of these three areas — staffing optimization, denial prevention, or compliance automation — would deliver the most value in your first 90 days?"

**Expansion Close** (existing Snowflake customer):
> "This is running on Snowflake today. Your existing Snowflake investment can do this — we're not adding tools, we're unlocking capability you already own."

**Platform Close** (for existing Snowflake customers):
> "Everything you just saw runs natively on Snowflake Business Critical — the same platform you already own. Automated governance, cross-region failover, role-based masking, and three-system analytics. No new vendors, no new BAAs, no new security reviews. When can we deploy this in your environment?"

---

## 5. Technical Depth Cards

For when the audience asks "how does this actually work?" — deliver these in 3 sentences or fewer.

**"How does the governance intelligence work?"**
Stored procedures running on your Snowflake compute analyze metadata, lineage, and tag propagation. The Ontology Knowledge Graph is queried natively with recursive CTEs — no sidecar or container service. All results materialize into standard Snowflake tables — fully queryable, fully governed.

**"How is this secured?"**
Business Critical edition. AES-256 encryption at rest with annual key rotation. TLS 1.2+ in transit. Network policies restricting access to your corporate CIDR. Cross-region failover with 10-minute RPO. HITRUST CSF certified. Your data never leaves Snowflake's security perimeter.

**"What about disaster recovery?"**
Cross-region database replication with client-redirect failover. Primary in us-west-2, secondary in us-east-1. 10-minute replication schedule. Transparent failover — applications reconnect automatically via Connection objects. We demo the failover in the deployment runbook.

**"Is this real-time?"**
Dynamic Tables in the CURATED layer refresh on configurable lag (1min-1hr). Inference runs on schedule or on-demand via SP_HCLS_MASTER_ORCHESTRATOR(). Streamlit dashboards pull live from the analytics tables.

**"How do you handle PHI?"**
Every column is classified via automated inference. Row-access and masking policies enforce HIPAA minimum necessary. The platform scores compliance 0-1 per object and flags violations automatically.

**"What about data quality?"**
Data contracts validate schema at the CURATED layer. Automated analysis detects orphaned datasets, missing classifications, and broken lineage. Governance scoring penalizes objects with quality gaps.

**"Can we bring our own data?"**
The data generators create synthetic data. For production, you'd land Epic FHIR Bulk Export, Workday RaaS reports, and 837/835 claim files into the RAW layer. Same curated/analytics pipeline applies.

**"What about Epic Caboodle/Clarity?"**
This complements — not replaces — your clinical data warehouse. The platform federates insights across systems that Caboodle doesn't touch (Workday, payer data, governance metadata). Most customers run both.

**"How is this different from a BI dashboard?"**
BI shows you what happened. Cross-system analytics shows you WHY — by connecting entities across systems and computing correlations that no single-system query can produce. The ontological signal graph makes those connections visual and explorable.

**"How is the correlation computed?"**
Pearson coefficient on monthly aggregates with Fisher z-transform for p-values. Computed by SP_HCLS_STAFFING_CORRELATION() using UNPIVOT to test every staffing metric against every outcome metric. Stored in HCLS_CORRELATION_RESULTS.

**"How is CCI calculated?"**
SP_HCLS_COMORBIDITY_INDEX() matches ICD-10 prefixes against the 17-category Charlson weight table. Patients are tiered: LOW (0-1), MODERATE (2-3), HIGH (4-6), SEVERE (7+). Refreshed on each pipeline refresh.

**"What about HCC vs CCI?"**
CCI predicts mortality (Charlson weights); HCC predicts cost (CMS grouper). Both measure patient complexity from different angles. The platform can compute both — the point is connecting comorbidity to operational decisions.

---

## 6. Competitive Positioning

| Competitor Approach | Limitation | Our Advantage |
|---|---|---|
| **Databricks + Unity Catalog** | No built-in governance framework, no native masking policies, no HITRUST certification at platform level | Automated governance, native masking + tagging, HITRUST CSF certified, Business Critical security |
| **Health Catalyst DOS** | Another vendor to BAA, another security review, another point of failure | Single security perimeter, single BAA, customer owns all data, Marketplace ecosystem |
| **Epic Caboodle/Clarity** | No cross-system governance, no automated PHI detection across derived datasets | Cross-system analytics connecting clinical, workforce, and payer with governed lineage |
| **Palantir Foundry** | Additional security perimeter, additional BAA, extremely expensive, proprietary lock-in | Transparent SQL-based analytics, no additional BAA, existing Snowflake investment |
| **Custom Python/Airflow** | Maintenance burden, no governance, fragile pipelines | Managed platform, automatic governance, Dynamic Tables eliminate middleware |
| **Tableau/Power BI** | Visualization only, no cross-system reasoning, no inference | Cross-system analytics discovers insights that dashboards can't — platform does the reasoning |

### Key Differentiator Talking Points

1. **One security perimeter**: Three source systems, one BAA, one set of masking policies, one audit trail.
2. **Automated governance**: PHI classification, compliance scoring, and access analysis run continuously — not annually.
3. **Zero-ETL pipelines**: Dynamic Tables eliminate middleware — no Airflow, no Spark, no external schedulers to secure.
4. **Business Critical resilience**: Cross-region failover, encryption at rest, network isolation — HIPAA-grade by default.
5. **Platform economics**: No per-seat licensing, no per-bed pricing — consumption-based, scales with usage.

---

## 7. Follow-Up Playbook

| Timing | Action | Deliverable |
|--------|--------|-------------|
| **Same day** | Send personalized summary email | 3 key findings mapped to their specific challenges |
| **Day 2** | Share architecture docs | ARCHITECTURE_STRATEGY.md + ROADMAP.md (rendered as PDF) |
| **Day 5** | Propose Proof of Value scope | Which data sources, which analytical questions |
| **Day 10** | Confirm PoV logistics | Data access requirements, Snowflake account provisioning |
| **PoV delivery** | Working demo against their data | 3 published insights + governance score baseline |

### Email Template (Same Day)

> Subject: Snowflake HCLS Platform — Key Findings from Today's Session
>
> [Name],
>
> Thank you for your time today. Based on our discussion, here are three areas where we see immediate impact:
>
> 1. **[Finding 1 — mapped to their stated pain]**
> 2. **[Finding 2 — mapped to an insight they reacted to during demo]**
> 3. **[Finding 3 — mapped to a competitive displacement or cost reduction]**
>
> We'd like to propose a Proof of Value connecting [their priority data source] to demonstrate [their priority analytical question]. I'll send over the scope document this week.
>
> [EA Name]

---

## 8. Common Objections & Responses

| # | Objection | Response |
|---|-----------|----------|
| 1 | "We already have a clinical data warehouse." | "This complements your CDW. The platform federates insights across systems that Caboodle/Clarity doesn't touch — Workday, payer data, governance metadata. Most customers run both." |
| 2 | "Our data isn't clean enough for this." | "The platform FINDS the quality gaps — orphaned datasets, missing classifications, broken lineage. It's the diagnostic tool, not the patient." |
| 3 | "We don't have Workday." | "The workforce integration works with any HCM system — Kronos, UKG, API feeds, even flat files. Workday is the demo example. The pattern is the same." |
| 4 | "HIPAA concerns with consolidating data." | "Snowflake is HITRUST CSF certified. Business Critical provides AES-256 encryption, network isolation, cross-region failover. Row-level security, dynamic masking, and column-level encryption are built in. The platform PROVES compliance — it doesn't weaken it." |
| 5 | "This seems complex to maintain." | "Dynamic Tables + stored procedures = zero ETL maintenance. SP_HCLS_MASTER_ORCHESTRATOR() runs the entire pipeline. SP_HCLS_QUICK_REFRESH() for lightweight updates. Cross-region failover is automatic." |
| 6 | "We're locked into the Epic ecosystem." | "FHIR Bulk Export is an ONC-mandated standard. No vendor dependency required. We land FHIR R4 bundles and normalize them in the CURATED layer." |
| 7 | "Our IT team is too small for this." | "After initial deployment, this runs itself — pipeline refresh is automated, governance scoring is continuous, Streamlit dashboards pull live data. Cross-region failover is hands-off. No ongoing development required." |
| 8 | "We need to involve Legal/Compliance." | "They should be sponsors, not blockers. The platform PROVES compliance — governance scores, recommendation history, and audit trails are exactly what Legal needs for the next OCR audit." |
| 9 | "What's the cost?" | "Runs on existing Snowflake consumption credits — no new licenses, no per-seat fees, no per-bed pricing. The inference service runs on your Snowflake compute." |
| 10 | "Can we see customer references?" | "This is cutting-edge — we're building the reference cohort now. We offer a PoV so you can BE the reference. Early adopters get priority EA support." |

---

## 9. Metrics That Matter (By Audience)

| Metric | Source Table | Industry Benchmark | Demo Value | Business Impact |
|--------|-------------|-------------------|------------|-----------------|
| Nurse-Patient Ratio → Readmission Correlation | HCLS_CORRELATION_RESULTS | r > 0.5 is significant | r = 0.68 | $521M CMS HRRP penalties (2023) |
| Denial Rate by CCI Tier | HCLS_PAYER_METRICS | 10-12% average | 8% (LOW) → 28% (SEVERE) | $262B denied claims annually |
| PHI Classification Coverage | RAI_GOVERNANCE_SCORES | 100% target | Show gaps → remediation | $1.5M average HIPAA fine |
| Time to Compliance Insight | Manual vs Automated | Weeks (manual audit) | Seconds (platform query) | FTE reduction in compliance team |
| Cost per Encounter by CCI Tier | HCLS_PAYER_METRICS | Varies by region | LOW ~$4.2K → SEVERE ~$78K | Risk adjustment accuracy |
| Prior Auth Turnaround | HCLS_PAYER_METRICS | 3-5 days target | Varies by payer/tier | Care delay impact |
| Comorbidity Co-occurrence Rate | HCLS_COMORBIDITY_PAIRS | DM+HTN ~30% | Check live results | Population health program design |
| Staffing Adequacy | HCLS_STAFFING_CONTEXT | >80% adequate | 60% adequate, 25% understaffed | Nurse retention, burnout prevention |

---

## 10. Demo Day Logistics

### Presentation Setup

- Use **presenter mode** in Streamlit — hide sidebar initially, reveal progressively as you navigate
- Have **SQL Worksheet** pre-loaded with all 8 demo queries in separate tabs, named by Part number
- Keep **ONTOLOGY_MAP.md** open for reference if deep technical questions arise about node/edge types
- Have **DEMO_SCRIPT.md** on a second screen or printed as a reference card
- Set your SQL Worksheet context: `USE ROLE ONTOLOGY_ADMIN; USE WAREHOUSE COMPUTE_WH;`

### Contingency Plans

| Issue | Recovery |
|-------|----------|
| **Network drops** | Switch to pre-captured screenshots. "The platform has [X] thousand nodes — let me show you the result we captured this morning." |
| **Signal Graph slow to render** | "In production, we'd pre-compute these views. Let me show you the cached result." Switch to screenshot. |
| **Query returns zero rows** | Re-run `CALL SP_HCLS_QUICK_REFRESH();` in background. Pivot to a different part. "Let me show you this while the pipeline refreshes." |
| **Inference service unavailable** | Show analytics tables directly (ONTOLOGY_GRAPH_NODES/EDGES). "The inference ran earlier — here are the materialized results." |
| **Audience asks about a feature not in the demo** | "That's on the roadmap. Let me show you ROADMAP.md — here's where that fits." |

### Pacing Guidelines

- **If audience is technical and engaged**: Let them drive. Spend more time on Parts 6-8 (staffing, comorbidity, payer). Let them inspect SQL.
- **If audience is executive and impatient**: Skip Part 5 (Streamlit walkthrough). Jump from Part 4 → Part 6 with: "Let me show you the business value."
- **If audience is skeptical**: Spend extra time on Part 4 (governance scores) and Part 8 (payer analysis). These are hardest to dismiss — they produce concrete, verifiable numbers.
- **If you're running long**: Cut Part 3 (entity resolution) — it's impressive but not essential to the staffing/comorbidity/payer story.

---

## Appendix: Quick Reference — All SQL Stored Procedures

| Script | Procedure | Output Table |
|--------|-----------|-------------|
| 01 | SP_HCLS_POPULATE_CLINICAL_GRAPH() | ONTOLOGY_GRAPH_NODES/EDGES (FHIR nodes) |
| 02 | SP_HCLS_CREATE_HIPAA_GAPS() | ONTOLOGY_GRAPH_NODES (intentional gaps) |
| 03 | SP_HCLS_RAI_INFERENCE() | RAI_RECOMMENDATIONS, RAI_ENTITY_CLUSTERS, RAI_GOVERNANCE_SCORES |
| 04 | SP_HCLS_POPULATE_WORKDAY_GRAPH() | ONTOLOGY_GRAPH_NODES/EDGES (WD_ prefixed) |
| 05 | SP_HCLS_STAFFING_RUN_ALL() | SEM_DEV.HCLS_ANALYTICS: HCLS_STAFFING_CONTEXT, HCLS_STAFFING_OUTCOME_METRICS, HCLS_CORRELATION_RESULTS |
| 06 | SP_HCLS_COMORBIDITY_PAYER_RUN_ALL() | SEM_DEV.HCLS_ANALYTICS: HCLS_PATIENT_COMORBIDITY, HCLS_COMORBIDITY_PAIRS, HCLS_PAYER_METRICS, HCLS_CARE_GAPS |
| 07 | SP_HCLS_MASTER_ORCHESTRATOR() | HCLS_MASTER_RUN (execution snapshot) |
| 07 | SP_HCLS_QUICK_REFRESH() | HCLS_QUICK_REFRESH (lightweight snapshot) |
