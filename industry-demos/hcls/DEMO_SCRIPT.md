# HCLS Demo Script — 30 Minute Walkthrough

## Overview

Structured 30-minute demonstration of Snowflake's governed healthcare platform. Three integrated clinical systems — **Epic/FHIR** (clinical), **Workday HCM** (workforce), and **Payer** (financial) — unified under automated PHI governance, cross-system analytics, and continuous compliance scoring.

| # | Part | Duration |
|---|------|----------|
| — | Opening | 1 min |
| 1 | Governed Clinical Data Platform | 3 min |
| 2 | Automated PHI Detection | 3 min |
| 3 | Patient Entity Resolution | 3 min |
| 4 | HIPAA Compliance Scores | 3 min |
| 5 | Streamlit Visualization | 2 min |
| 6 | Staffing-Outcomes Correlation | 5 min |
| 7 | Comorbidity Intelligence | 5 min |
| 8 | Payer Response Analysis | 5 min |
| | **Total** | **~30 min** |

## Prerequisites

1. Core DCA demo deployed (scripts 01-15)
2. FHIR data generated and loaded
3. Workday HCM data generated and loaded
4. Payer data generated and loaded
5. HCLS graph extensions deployed (all 7 scripts):
   ```sql
   @demos/hcls/sql/01_hcls_graph_populate.sql
   @demos/hcls/sql/02_hcls_hipaa_gaps.sql
   @demos/hcls/sql/03_hcls_rai_inference.sql
   @demos/hcls/sql/04_hcls_workday_populate.sql
   @demos/hcls/sql/05_hcls_staffing_outcomes.sql
   @demos/hcls/sql/06_hcls_comorbidity_payer.sql
   @demos/hcls/sql/07_hcls_run_all.sql
   ```
6. Streamlit app deployed with Page 6 (Knowledge Graph) and Page 7 (Signal Graph)

## Demo Flow

### Opening (1 min)

Talk Track:
> "Healthcare data carries the strongest regulatory requirements of any industry. Today I'll show you how Snowflake automatically classifies PHI, enforces role-based masking, and scores compliance continuously across every table, column, and pipeline. No manual audits. No external tools. One governed platform, three clinical systems, complete HIPAA visibility."

### Part 1: Governed Clinical Data Platform (3 min)

Setup:
> "We've unified Epic, Workday, and Payer data under a single governance framework. The platform automatically tracks entities, relationships, and lineage across all three systems."

Show the graph structure:
```sql
USE ROLE ONTOLOGY_ADMIN;
-- Clinical node distribution
SELECT node_type, source_system, COUNT(*) AS cnt
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
WHERE source_system = 'FHIR' OR layer = 'METADATA'
GROUP BY node_type, source_system
ORDER BY cnt DESC;
```

> "We have [X] clinical nodes — patients, encounters, conditions, medications — linked to [Y] metadata nodes representing the actual Snowflake objects that store them. The platform connects the clinical world to the technical world under one governance perimeter."

Show a Patient 360:
```sql
-- All relationships for a single patient
SELECT e.edge_type, n2.node_type, n2.display_name, n2.source_system
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n ON e.source_node_id = n.node_id
JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n2 ON e.target_node_id = n2.node_id
WHERE n.node_type = 'PATIENT'
LIMIT 1;
-- (Expand with specific patient lookup)
```

> "One query gives us the complete patient picture: encounters, diagnoses, medications, practitioners — all linked."

### Part 2: Automated PHI Detection (3 min)

```sql
-- PHI propagation recommendations
SELECT severity, description, suggested_action
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS
WHERE recommendation_type = 'PII_PROPAGATION'
ORDER BY CASE severity WHEN 'HIGH' THEN 1 WHEN 'MEDIUM' THEN 2 ELSE 3 END;
```

> "The platform traced data lineage and found columns receiving patient data from PHI-tagged sources — but the receiving columns have no HIPAA classification. These are your compliance blind spots. Without automated lineage tracing, you'd need a manual audit to find them."

### Part 3: Patient Entity Resolution (3 min)

```sql
-- Cross-system patient matches
SELECT c.cluster_id, c.cluster_label, c.confidence,
       n.display_name, n.source_system, n.node_type
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_ENTITY_CLUSTERS c
JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n ON c.node_id = n.node_id
WHERE n.node_type IN ('PATIENT', 'EMPLOYEE')
  AND c.confidence > 0.8
ORDER BY c.cluster_id, c.confidence DESC;
```

> "Automated matching resolved patients across FHIR and Workday using name and demographic similarity. Cluster 1 shows the same person appearing in both systems — no external MPI needed. Snowflake does it natively with stored procedures."

### Part 4: HIPAA Compliance Scores (3 min)

```sql
-- HIPAA governance scores for clinical objects
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

> "Every object gets a HIPAA governance score from 0 to 1. Scores below 0.4 need immediate attention. This replaces your annual manual assessment with continuous, automated scoring."

### Part 5: Streamlit Visualization (2 min)

Navigate to Page 6: Knowledge Graph
- Filter: Source System = FHIR, Layer = BUSINESS
- Show clinical graph with patient-centered view
- Switch to Governance Scores tab — filter to scores < 0.4
- Show Recommendations tab — HIPAA-specific recommendations

> "The privacy officer can see compliance posture in real-time. No more waiting for the annual audit to discover gaps."

### Part 6: Staffing-Outcomes Correlation (5 min)

Talk Track:
> "Now let's connect clinical data to workforce data. When we overlay Workday staffing on clinical outcomes, powerful patterns emerge that no single system could reveal alone."

SQL 1 — Show units with highest adverse event correlation:
```sql
-- Staffing metrics vs outcome rates by unit
SELECT 
    sc.unit_type,
    sc.department_name,
    ROUND(AVG(sc.actual_ratio), 1) AS avg_nurse_ratio,
    ROUND(AVG(sc.overtime_pct) * 100, 1) AS overtime_pct,
    ROUND(SUM(CASE WHEN e.readmission_30day THEN 1 ELSE 0 END)::FLOAT / NULLIF(COUNT(*), 0) * 100, 1) AS readmission_rate_pct,
    COUNT(*) AS encounter_count
FROM DCA_DEMO.GOVERNANCE.HCLS_STAFFING_CONTEXT sc
JOIN CURATED_DEV.FHIR.FACT_ENCOUNTERS e 
    ON sc.org_id = e.org_id AND e.admit_date = sc.shift_date
WHERE sc.actual_ratio > sc.target_nurse_ratio * 1.2
GROUP BY 1, 2
ORDER BY readmission_rate_pct DESC
LIMIT 10;
```

> "These are units where nurse-patient ratios exceeded targets by 20%+. Notice the correlation with readmission rates — the understaffed ICU shows [X]% readmissions vs [Y]% when adequately staffed."

SQL 2 — Cross-system analytics: encounters influenced by understaffing:
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

> "Cross-system analytics made this connection automatically. INFLUENCED_BY edges with correlation strength show exactly which encounters were affected by understaffing. Traditional BI would require manually joining 5+ tables across two systems."

Q&A:
- "How is the correlation computed?" — Pearson coefficient on monthly aggregates, stored in HCLS_CORRELATION_RESULTS with Fisher z-transform p-values.
- "Can we use this for predictive staffing?" — Yes, the time-series data enables forecasting models. The platform preserves the temporal dimension for trend analysis.

### Part 7: Comorbidity Intelligence (5 min)

Talk Track:
> "Let's look at comorbidity burden — the Charlson Comorbidity Index tells us which patients carry the most clinical complexity. This drives everything from LOS to cost to payer behavior."

SQL 1 — CCI distribution and cost impact:
```sql
-- Comorbidity tier distribution and average cost
SELECT 
    pc.cci_tier,
    COUNT(DISTINCT pc.patient_id) AS patient_count,
    ROUND(AVG(pc.cci_score), 1) AS avg_score,
    ROUND(AVG(e.total_charges), 0) AS avg_cost_per_encounter,
    ROUND(AVG(e.los_days), 1) AS avg_los,
    ROUND(SUM(CASE WHEN e.readmission_30day THEN 1 ELSE 0 END)::FLOAT / NULLIF(COUNT(*), 0) * 100, 1) AS readmission_pct
FROM DCA_DEMO.GOVERNANCE.HCLS_PATIENT_COMORBIDITY pc
JOIN CURATED_DEV.FHIR.FACT_ENCOUNTERS e ON pc.patient_id = e.patient_id
WHERE e.encounter_class = 'INPATIENT'
GROUP BY 1
ORDER BY CASE pc.cci_tier WHEN 'LOW' THEN 1 WHEN 'MODERATE' THEN 2 WHEN 'HIGH' THEN 3 WHEN 'SEVERE' THEN 4 END;
```

> "SEVERE tier patients cost [X]x more per encounter with [Y]x longer stays. This is where population health and payer negotiations intersect."

SQL 2 — Top comorbidity clusters (condition co-occurrence):
```sql
-- Most common comorbidity pairs
SELECT condition_a_desc, condition_b_desc, shared_patient_count, 
       ROUND(co_occurrence_rate * 100, 1) AS co_occurrence_pct
FROM DCA_DEMO.GOVERNANCE.HCLS_COMORBIDITY_PAIRS
ORDER BY shared_patient_count DESC
LIMIT 10;
```

> "Diabetes + Hypertension appears in [X]% of our population. These clusters aren't just clinical trivia — they predict which patients will consume the most resources and face the most payer friction."

### Part 8: Payer Response Analysis (5 min)

Talk Track:
> "Now the payer dimension. How do insurance companies respond to patients with high comorbidity burden? This analysis reveals patterns that inform contract negotiation, prior auth strategy, and revenue cycle operations."

SQL 1 — Denial rate by CCI tier and payer:
```sql
-- Payer denial patterns by comorbidity
SELECT cci_tier, payer_name, 
       ROUND(denial_rate * 100, 1) AS denial_pct,
       ROUND(avg_adjudication_days, 0) AS days_to_decide,
       ROUND(prior_auth_rate * 100, 1) AS prior_auth_pct,
       total_claims
FROM DCA_DEMO.GOVERNANCE.HCLS_PAYER_METRICS
WHERE total_claims > 100
ORDER BY cci_tier, denial_rate DESC;
```

> "Look at the SEVERE tier — [payer X] denies [Y]% of claims and takes [Z] days to adjudicate. That's a revenue cycle problem hiding in comorbidity data that only cross-system analytics connects."

SQL 2 — Plan of care gaps (approved vs actual):
```sql
-- Care plan gaps: Where payers approve less than clinical need
SELECT cci_tier, payer_name,
       ROUND(AVG(approved_days), 1) AS avg_approved,
       ROUND(AVG(actual_days), 1) AS avg_actual,
       ROUND(AVG(variance_days), 1) AS avg_gap,
       ROUND(SUM(CASE WHEN readmitted_30day THEN 1 ELSE 0 END)::FLOAT / NULLIF(COUNT(*), 0) * 100, 1) AS readmit_pct_early_discharge
FROM DCA_DEMO.GOVERNANCE.HCLS_CARE_GAPS
WHERE gap_type = 'EARLY_DISCHARGE'
GROUP BY 1, 2
ORDER BY avg_gap DESC;
```

> "Patients discharged before payer-approved end date have a [X]% readmission rate for SEVERE comorbidity vs [Y]% for those held to clinical need. This is the data you bring to payer negotiations."

### Closing (1 min)

> "To summarize:
> 1. Snowflake governs three clinical systems under one security perimeter
> 2. Automated PHI detection eliminates compliance blind spots
> 3. Cross-system patient resolution without external MPI appliances
> 4. Continuous compliance scoring replaces annual manual audits
> 5. Staffing-outcome correlations reveal patterns no single system can produce
> 6. Comorbidity stratification drives population health and payer strategy
> 7. Payer behavior analysis arms revenue cycle with data-driven negotiation leverage
> 8. All running on Business Critical with cross-region failover, network isolation, and HITRUST certification"

## Common Questions

**Q: How accurate is the entity resolution?**
> "Configurable confidence threshold. Default 0.7 Jaccard similarity on name tokens + exact DOB match. In production, you'd add MRN cross-references where available."

**Q: Can this satisfy an OCR audit?**
> "The governance scores, recommendation history, and access edges provide documentary evidence of continuous compliance monitoring — stronger than point-in-time manual audits."

**Q: What about de-identification for research?**
> "The platform tracks DE_IDENTIFIED_FROM edges. If a research dataset was derived from PHI, the provenance is recorded and auditable."

**Q: Does this replace our existing HIPAA tools?**
> "It complements them. The platform integrates with GRC tools (export scores to ServiceNow/Archer) and provides the data-layer evidence that compliance tools need."

**Q: How is the correlation computed?**
> "Pearson coefficient on monthly aggregates with Fisher z-transform for p-values, stored in HCLS_CORRELATION_RESULTS. Computed by SP_HCLS_STAFFING_CORRELATION() using UNPIVOT to test every staffing metric against every outcome metric."

**Q: Is the CCI calculated in real-time?**
> "Yes — SP_HCLS_COMORBIDITY_INDEX() refreshes on each pipeline refresh using ICD-10 pattern matching against the Charlson weight table. Scores are stored in HCLS_PATIENT_COMORBIDITY and tiered as LOW/MODERATE/HIGH/SEVERE."

**Q: How does this compare to CMS risk adjustment?**
> "CCI is one input; HCC risk adjustment uses a different grouper logic (HHS-HCC for ACA, CMS-HCC for Medicare). Both measure patient complexity but CCI focuses on mortality prediction while HCC focuses on cost prediction."

**Q: Can we share comorbidity/payer analysis with payers?**
> "Yes, de-identified via the platform's DE_IDENTIFIED_FROM edge provenance. Aggregate metrics by CCI tier are shareable without PHI concerns."

**Q: How is this secured in production?**
> "Business Critical edition with AES-256 encryption, network policies restricting access to corporate CIDRs, 30-minute session timeouts, cross-region failover with 10-minute RPO, and HITRUST CSF certification. Your data never leaves Snowflake's security perimeter."
