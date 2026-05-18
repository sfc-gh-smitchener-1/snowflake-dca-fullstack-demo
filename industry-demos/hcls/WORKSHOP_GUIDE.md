# Healthcare & Life Sciences — Workshop Facilitation Guide

> **Knowledge Graph-Governed Clinical Data Platform** — "From Manual HIPAA Audits to Automated Compliance Scoring"

## Session Details

| Field | Detail |
|-------|--------|
| **Duration** | 4 hours |
| **Format** | Whiteboard-led workshop with live Knowledge Graph demo, interactive handouts |
| **Audience** | CMIO, CNO, CPO, VP Data/Analytics, VP Revenue Cycle, Data Engineering, Compliance/Privacy team |

## Attendees

**Snowflake**: Enterprise Data Architect (Lead), Account Team, Healthcare Industry SA

**Customer**: Chief Medical Information Officer, Chief Nursing Officer, Chief Privacy Officer, VP Data & Analytics, VP Revenue Cycle / Payer Relations, Data Engineering Lead, Compliance/Privacy Team, Clinical Informatics Lead

## HCLS Pain Points — Workshop Coverage Map

Every pain point raised in discovery must land in a specific workshop moment. This matrix is the facilitator's accountability checklist.

| # | HCLS Pain Point | Workshop Segment | Live Demo Moment |
|---|----------------|-----------------|-----------------|
| 1 | **PHI Propagating Without Classification** — Clinical columns flow through ETL pipelines into analytics extracts without HIPAA tags; manual audits miss them | Seg 1 (Gap Map), Seg 2 (Knowledge Graph architecture) | Show graph inference detecting unclassified PHI columns via name pattern matching + lineage tracing |
| 2 | **No Cross-System Patient Matching** — Same patient exists in FHIR, Claims, Workday with no automated resolution; duplicates cause over-counting and care gaps | Seg 1 (Gap Map), Seg 3 (Entity Resolution demo) | Show the graph resolving same patient across FHIR + Workday using name similarity |
| 3 | **Manual HIPAA Audit Process** — Annual compliance assessments done in spreadsheets; no continuous monitoring; findings are stale by the time they're reported | Seg 1 (Compliance lane), Seg 3 (Scoring demo) | Show governance scores with HIPAA-specific breakdown (classification, access, BAA, audit trail, de-id) |
| 4 | **Orphaned Research Datasets** — ML and research tables derived from PHI with no IRB reference, no de-identification lineage, no accountable data steward | Seg 2 (Contracts), Seg 3 (Recommendations demo) | Show graph inference flagging datasets without contract edges or IRB provenance |
| 5 | **Care Pathway Fragmentation** — Clinical data siloed by encounter; no temporal view of patient journey across encounters, conditions, and treatments | Seg 2 (Clinical Graph), Seg 3 (Pathway demo) | Show traversal from Patient → Encounters → Conditions → Medications with temporal sequencing |

## Pre-Work (Distribute 5 Business Days Before)

| Item | Owner | Purpose |
|------|-------|---------|
| Current PHI inventory (known PHI locations across systems) | Customer | Informs gap analysis in Segment 1 |
| HIPAA risk assessment (last audit findings, OCR correspondence) | Customer | Seeds the compliance gap map |
| System inventory (EHR, Claims, Lab, Pharmacy, HR — with data volumes) | Customer | Informs architecture whiteboard in Segment 2 |
| DCA Knowledge Graph Overview (1-pager) | Snowflake | Context on graph-based governance approach |
| HCLS Pain Point Worksheet (printed) | Snowflake | One per attendee — 5 pain points with blank "current cost" and "target state" columns |
| HIPAA Compliance Scoring Rubric (printed) | Snowflake | Shows the 5-dimension scoring model |
| Current nurse-to-patient ratios by unit type | Customer | Informs staffing-outcomes analysis in Segment 6 |
| Trailing 12-month RN turnover data | Customer | Benchmarking against industry in Segment 6 |
| Top 3 payer denial rates (by payer name) | Customer | Informs payer intelligence discussion in Segment 7 |
| Confirm Workday or equivalent HCM system availability | Customer | Required for staffing data mapping |
| Printed STAFFING_OUTCOMES.md reference | Snowflake | One per attendee — staffing correlation benchmarks |
| Printed COMORBIDITY_PAYER.md reference | Snowflake | One per attendee — CCI tier definitions and payer patterns |
| CCI mapping table (printed) | Snowflake | Charlson Comorbidity Index condition weights |
| Denial reason code reference sheet | Snowflake | Top 20 denial codes with descriptions |

## Agenda at a Glance

| Time | Segment | Duration |
|------|---------|----------|
| 0:00 | **Segment 1** — The Problem: Mapping HIPAA Compliance Gaps | 30 min |
| 0:30 | **Segment 2** — The Pattern: Knowledge Graph for Clinical Governance | 45 min |
| 1:15 | BREAK | 15 min |
| 1:30 | **Segment 3** — The Proof: Live Knowledge Graph Demo | 45 min |
| 2:15 | **Segment 4** — The Path: 30/60/90 HCLS Roadmap | 30 min |
| 2:45 | **Segment 5** — Working Discussion: Pilot Selection | 15 min |
| 3:00 | BREAK | 10 min |
| 3:10 | **Segment 6** — Staffing-Outcomes Intelligence | 35 min |
| 3:45 | **Segment 7** — Comorbidity & Payer Intelligence | 35 min |
| 4:20 | CLOSE | — |

---

## Segment 1 — The Problem: Mapping HIPAA Compliance Gaps

**Time**: 0:00 - 0:30 (30 minutes)

**Objective**: Shared understanding that HIPAA compliance gaps are structural (architecture-caused), not procedural — and that manual audit processes create a false sense of security between annual assessments.

### 0:00-0:05 | Opening and Introductions (5 min)

**Setup**: Stand at the whiteboard. Do not use slides. Have the HCLS Pain Point Worksheet on each chair.

**Talk Track**:
> "Healthcare data carries the strongest regulatory requirements of any industry. HIPAA doesn't just say 'protect data' — it demands you PROVE you know where PHI exists, who can access it, that access is minimally necessary, and that Business Associate Agreements cover every external touchpoint."
>
> "Today we'll map where those proofs break down in your current architecture, show you how a Knowledge Graph can automate that proof continuously, and leave with a named pilot. Everything you see today uses real clinical data structures — FHIR patients, encounters, conditions, medications — so it maps directly to your world."

**Align on workshop outcomes**: Leave with (1) a consensus on which HIPAA gaps are highest-priority, (2) an understanding of how the Knowledge Graph approach addresses each gap, and (3) a named pilot workload with owners and 30-day milestone.

### 0:05-0:25 | Compliance Gap Mapping (20 min)

**Action**: Walk through all five pain points. Use the printed Pain Point Worksheet as a guide. Ask the room to validate, amend, or add to each one. Write them on the whiteboard under five lanes.

**Whiteboard Layout** — Five lanes:

```
┌─────────────────┬─────────────────┬─────────────────┬─────────────────┬─────────────────┐
│ PHI             │ PATIENT         │ ACCESS          │ RESEARCH        │ CLINICAL        │
│ CLASSIFICATION  │ IDENTITY        │ GOVERNANCE      │ COMPLIANCE      │ INTEGRATION     │
│─────────────────│─────────────────│─────────────────│─────────────────│─────────────────│
│ Columns flow    │ Same patient in │ Non-covered     │ ML tables from  │ No temporal     │
│ without tags    │ 3+ systems      │ entities get    │ PHI without     │ view of patient │
│ through ETL     │ No matching     │ PHI access      │ IRB or lineage  │ journey         │
│ into analytics  │ Duplicates in   │ No BAA docs     │ No de-id proof  │ Encounters are  │
│ No masking      │ pop health      │ Audit = annual  │ SYSADMIN owns   │ isolated events │
└─────────────────┴─────────────────┴─────────────────┴─────────────────┴─────────────────┘
```

**Facilitation prompts for each lane**:

| Lane | Key Question | Expected Response |
|------|-------------|-------------------|
| PHI Classification | "When a new analytics table is created from clinical data, how do you ensure every PHI column gets tagged?" | Manual review, or "we don't consistently" |
| Patient Identity | "How many systems contain patient data? How do you know two records refer to the same person?" | 3-5 systems; answer is usually "we don't match them automatically" |
| Access Governance | "When an external partner gets access to clinical data, where is the BAA documented? How do you audit it?" | Spreadsheet, legal team files, no automated check |
| Research Compliance | "When a research dataset is derived from PHI, what proves the de-identification? Who is accountable?" | "The researcher" or "nobody clearly" |
| Clinical Integration | "Can you show a patient's complete care journey — every encounter, diagnosis, treatment — in one query?" | Multiple queries across multiple tables; no unified view |

### 0:25-0:30 | Quantify the Risk (5 min)

For each lane, capture on the whiteboard:
- **Regulatory exposure**: HIPAA violation fines ($100-$50K per violation, up to $1.5M annually per category)
- **Operational cost**: Hours spent on manual audits, patient matching, lineage documentation
- **Patient impact**: Duplicate records causing treatment errors, delayed care coordination

> "These aren't theoretical risks. OCR published $X in HIPAA penalties last year. The average health system spends Y FTE-months annually on manual compliance documentation. Let's turn these manual heroics into automated graph inference."

---

## Segment 2 — The Pattern: Knowledge Graph for Clinical Governance

**Time**: 0:30 - 1:15 (45 minutes)

**Objective**: Demonstrate how the Ontology Knowledge Graph represents clinical entities, metadata, and governance relationships — and how graph inference automates HIPAA compliance detection.

### 0:30-0:45 | The Knowledge Graph Concept (15 min)

**Action**: Whiteboard the three-layer graph model using clinical examples.

**Whiteboard — Clinical Knowledge Graph Architecture**:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         METADATA LAYER                                       │
│  ┌──────────┐    HAS_COLUMN    ┌──────────┐    TAGGED_WITH    ┌──────────┐ │
│  │  TABLE   │────────────────→ │  COLUMN  │────────────────→  │   TAG    │ │
│  │DIM_PATIENT│                  │BIRTH_DATE│                   │HIPAA_PHI │ │
│  └──────────┘                  └──────────┘                   └──────────┘ │
│       ↑                                                                     │
│       │ STORED_IN (cross-layer)                                            │
│       │                                                                     │
├───────┼─────────────────────────────────────────────────────────────────────┤
│       │                    BUSINESS LAYER                                    │
│  ┌──────────┐  HAS_ENCOUNTER  ┌──────────┐  RESULTED_IN  ┌──────────┐     │
│  │ PATIENT  │────────────────→│ENCOUNTER │───────────────→│CONDITION │     │
│  └──────────┘                 └──────────┘                └──────────┘     │
│       │                            │                           │            │
│       │ DIAGNOSED_WITH             │ PERFORMED_BY              │TREATMENT_ │
│       │                            ↓                           │ PLAN      │
│       │                      ┌──────────┐                     ↓            │
│       └─────────────────────→│PRACTIONER│          ┌──────────────┐        │
│                              └──────────┘          │  MEDICATION  │        │
│                                    │               └──────────────┘        │
│                                    │ PRESCRIBED           ↑                │
│                                    └──────────────────────┘                │
├─────────────────────────────────────────────────────────────────────────────┤
│                         CROSS LAYER                                          │
│  PATIENT node ←── SAME_AS ──→ EMPLOYEE node (entity resolution)            │
│  ENCOUNTER node ── STORED_IN ──→ FACT_ENCOUNTERS table node                │
│  CONDITION node ── STORED_IN ──→ FACT_CONDITIONS table node                │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Talk Track**:
> "The Knowledge Graph connects two worlds: the clinical world — patients, encounters, diagnoses, medications, practitioners — and the technical world — tables, columns, tags, policies, roles. The graph engine reasons across BOTH layers simultaneously."
>
> "This is the key insight: it can detect that a COLUMN in an analytics extract received data from a PHI-tagged source column, even through 3 layers of transformation. Or that an ENCOUNTER node links to a TABLE node that has a GRANT to an external role without a BAA edge."

### 0:45-1:00 | Graph Inference Rules (15 min)

**Action**: Walk through each inference procedure with a clinical example. Use the whiteboard to draw the inference path.

| Rule | What It Does | Example |
|------|--------------|---------|
| **PHI Detection** | Scans COLUMN nodes for PHI name patterns (SSN, DOB, MRN, etc.) that lack HIPAA tags | `PATIENT_ANALYTICS_EXTRACT.birth_date` has no HIPAA_CATEGORY tag → HIGH severity finding |
| **Lineage Propagation** | Follows LINEAGE_FROM edges to find untagged columns receiving from tagged PHI sources | `DIM_PATIENT.BIRTH_DATE` (tagged) → ETL → `analytics.patient_dob` (untagged) → flag |
| **Entity Resolution** | Matches PATIENT nodes (FHIR) with EMPLOYEE nodes (Workday) on name tokens | "John Smith" in FHIR matches "J. Smith" in Workday → 0.85 confidence SAME_AS edge |
| **HIPAA Scoring** | 5-dimension scoring: classification, access controls, BAA, audit trail, de-identification | Each FHIR-sourced node gets 0.0-1.0 composite score; low scores surface as recommendations |
| **Care Pathways** | Temporal ordering of encounters per patient; links conditions to treatments via encounter | Patient A: Emergency → Inpatient → Follow-up; each with diagnosis → medication chain |

**Talk Track for PHI Detection**:
> "Here's how it works. The graph engine scans every COLUMN node. It applies name-pattern matching: does this column name contain 'SSN', 'DOB', 'MRN', 'BIRTH', 'ADDRESS'? If yes, does a TAGGED_WITH edge connect it to a PII or HIPAA tag node? If not — that's a finding."
>
> "But it goes further. Even if a column is named 'analytics_field_42' with no obvious PHI pattern, the engine follows LINEAGE_FROM edges upstream. If the source column IS tagged as PHI, the downstream column inherits the risk — and it flags it."

### 1:00-1:15 | Target Architecture (15 min)

**Action**: Whiteboard the target-state architecture showing data flow from source systems through the Knowledge Graph.

```
Sources              RAW                CURATED              KNOWLEDGE GRAPH         CONSUMPTION
─────────           ─────              ────────             ───────────────         ───────────
┌─────┐            ┌─────┐            ┌─────────┐         ┌───────────────┐       ┌──────────┐
│ EHR │──────────→ │ RAW │──────────→ │CURATED  │────────→│ GRAPH NODES   │──────→│Streamlit │
│(FHIR)│           │FHIR │            │  FHIR   │         │ GRAPH EDGES   │       │Dashboard │
└─────┘            └─────┘            └─────────┘         ├───────────────┤       ├──────────┤
┌─────┐            ┌─────┐            ┌─────────┐         │ NEO4J ENGINE  │       │Compliance│
│Claims│──────────→│ RAW │──────────→ │CURATED  │────────→│  - PHI Detect │──────→│  Reports │
│     │            │CLAIMS│           │ CLAIMS  │         │  - Resolution │       ├──────────┤
└─────┘            └─────┘            └─────────┘         │  - Pathways   │       │ SPCS API │
┌─────┐            ┌─────┐            ┌─────────┐         │  - Scoring    │──────→│ Clinical │
│ HR  │──────────→ │ RAW │──────────→ │CURATED  │────────→│               │       │  Apps    │
│(WDay)│           │WKDAY│            │ WORKDAY │         └───────────────┘       └──────────┘
└─────┘            └─────┘            └─────────┘                │
                                                                  ↓
                                                         ┌───────────────┐
                                                         │ OUTPUTS:      │
                                                         │ • Recommends  │
                                                         │ • Scores      │
                                                         │ • Clusters    │
                                                         │ • Pathways    │
                                                         └───────────────┘
```

**Key architectural decisions to discuss**:
1. Graph sits in the GOVERNANCE schema — separate from source data
2. Inference runs as stored procedures — scheduled or on-demand
3. Scores and recommendations are queryable tables — consumable by any BI tool
4. Entity clusters enable cross-system patient matching without an MPI appliance

---

## BREAK (15 min)

---

## Segment 3 — The Proof: Live Knowledge Graph Demo

**Time**: 1:30 - 2:15 (45 minutes)

**Objective**: Prove the pattern works with live SQL execution against the Knowledge Graph. Show each pain point being addressed in real time.

### Demo 1: Patient 360 via Graph (10 min)

**Setup**: Snowflake UI open to `DCA_DEMO.GOVERNANCE` schema.

```sql
-- Show all entities connected to a single patient through the graph
SELECT
    e.edge_type,
    n2.node_type,
    n2.display_name,
    n2.source_system
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n1 ON e.source_node_id = n1.node_id
JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n2 ON e.target_node_id = n2.node_id
WHERE n1.node_type = 'PATIENT'
  AND n1.display_name LIKE 'John%'
ORDER BY e.edge_type, n2.node_type;
```

**Talk Track**:
> "One query gives us the complete patient picture: every encounter, every diagnosis, every medication, every practitioner — linked through the graph. No joins across 5 different source tables. No manual assembly. The graph IS the patient 360."

**What to highlight**: Show multiple edge types radiating from a single patient. Point out the cross-system edges (SAME_AS to Workday employee).

### Demo 2: PHI Detection Results (10 min)

```sql
-- Show graph inference recommendations for unclassified PHI
SELECT
    recommendation_type,
    severity,
    description,
    metadata:detection_method::VARCHAR AS method,
    metadata:remediation::VARCHAR AS fix
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS
WHERE recommendation_type = 'PII_PROPAGATION'
  AND recommendation_id LIKE 'HCLS_%'
ORDER BY
    CASE severity WHEN 'HIGH' THEN 1 WHEN 'MEDIUM' THEN 2 ELSE 3 END;
```

**Talk Track**:
> "The graph engine found these columns receiving clinical data from PHI-tagged sources that aren't classified themselves. These are your HIPAA blind spots — the columns that pass through manual audits because nobody realized they carry PHI."
>
> "Notice the two detection methods: 'name_pattern' caught obvious ones like 'SSN' and 'BIRTH_DATE'. But 'lineage_propagation' caught columns that were RENAMED during ETL — the graph followed the data flow upstream and found the PHI origin."

### Demo 3: HIPAA Compliance Scores (10 min)

```sql
-- Show HIPAA scoring breakdown for clinical objects
SELECT
    display_name,
    node_type,
    hipaa_classification,
    access_controls,
    baa_coverage,
    audit_trail,
    de_identification,
    composite_score
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES
WHERE node_id IN (
    SELECT node_id FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
    WHERE source_system = 'FHIR'
)
ORDER BY composite_score ASC
LIMIT 15;
```

**Talk Track**:
> "Every clinical object is scored 0.0 to 1.0 across five HIPAA dimensions. Red items — scores below 0.5 — need immediate attention. This replaces your annual manual audit with continuous automated scoring."
>
> "Look at PATIENT_MATCH_STAGING: hipaa_classification = 0, access_controls = 0. That's an SSN column with no tag and no masking. In your current process, when would you have caught that?"

**Facilitator note**: Let the compliance team react. They will immediately see value in automated detection.

### Demo 4: Entity Resolution (10 min)

```sql
-- Show patient-employee matches across systems
SELECT
    c.cluster_id,
    c.confidence_score,
    c.metadata:patient_display::VARCHAR AS patient_name,
    c.metadata:employee_display::VARCHAR AS employee_name,
    c.metadata:match_criteria::VARCHAR AS match_method
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_ENTITY_CLUSTERS c
WHERE c.cluster_type = 'PATIENT_EMPLOYEE'
ORDER BY c.confidence_score DESC
LIMIT 10;
```

**Talk Track**:
> "The graph matched patients across FHIR and Workday using name similarity. No MPI appliance needed — the graph does entity resolution natively. 0.95 confidence means exact full name match. 0.85 means last name + first initial."
>
> "Why does this matter for HIPAA? Because if the same person exists in two systems with different access controls, you have inconsistent PHI protection. The graph makes that visible."

### Demo 5: Care Pathway Traversal (5 min)

```sql
-- Show temporal care pathway for a patient
SELECT
    n1.display_name AS from_encounter,
    n1.properties:period_start::VARCHAR AS start_date,
    e.edge_type,
    n2.display_name AS to_entity,
    n2.node_type AS entity_type
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n1 ON e.source_node_id = n1.node_id
JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n2 ON e.target_node_id = n2.node_id
WHERE n1.node_type = 'ENCOUNTER'
  AND n1.node_id LIKE 'HCLS_ENC_%'
  AND e.edge_type IN ('NEXT_ENCOUNTER', 'RESULTED_IN', 'PERFORMED_BY')
ORDER BY n1.properties:period_start
LIMIT 20;
```

**Talk Track**:
> "This is the care pathway — temporal sequencing of encounters with the conditions diagnosed and treatments prescribed at each step. Care coordination teams can see the full patient journey in one graph traversal."

---

## Segment 4 — The Path: 30/60/90 HCLS Roadmap

**Time**: 2:15 - 2:45 (30 minutes)

**Objective**: Convert enthusiasm into commitment with a phased execution plan.

**Action**: Walk through the phases in [ROADMAP.md](ROADMAP.md). Use the whiteboard to capture customer-specific adjustments.

### Phase 1 — Foundation (Days 1-30)

| Milestone | What It Delivers |
|-----------|-----------------|
| Deploy Knowledge Graph schema + procedures | Graph infrastructure ready |
| Classify PHI columns across FHIR tables | Immediate HIPAA visibility |
| Run initial graph inference (PHI Detection) | First findings report |
| Deploy Streamlit compliance dashboard | Self-service governance view |

**Talk Track**:
> "In 30 days you have automated PHI detection running against your clinical tables. Every unclassified column that carries patient data is surfaced. Your compliance team gets a dashboard instead of a spreadsheet."

### Phase 2 — Intelligence (Days 31-60)

| Milestone | What It Delivers |
|-----------|-----------------|
| Entity resolution across FHIR + HR systems | Patient-employee matching |
| Care pathway construction | Temporal clinical graph |
| HIPAA scoring across all FHIR objects | Continuous compliance scores |
| Automated recommendations + alerting | Proactive governance |

### Phase 3 — Scale (Days 61-90)

| Milestone | What It Delivers |
|-----------|-----------------|
| Research dataset provenance tracking | IRB/de-id lineage |
| External sharing with BAA validation | Governed data partnerships |
| Cortex Agent for natural-language compliance queries | "Is patient data X compliant?" |
| Integration with GRC tools (export findings) | Enterprise compliance workflow |

### Whiteboard Exercise (10 min)

Draw the 30/60/90 timeline on the whiteboard. For each phase, ask:
1. "Which of your systems maps to this phase?"
2. "Who in your org would own this?"
3. "What's blocking this today?"

Capture names and systems directly on the whiteboard.

---

## Segment 5 — Working Discussion: Pilot Selection

**Time**: 2:45 - 3:00 (15 minutes)

**Objective**: Leave with a named pilot, a named owner, and a 30-day milestone.

### Candidate Pilots

Present three options (facilitator recommends based on customer's biggest pain point from Segment 1):

| Pilot | Pain Point Addressed | Scope | 30-Day Deliverable |
|-------|---------------------|-------|-------------------|
| **A: PHI Classification Sweep** | #1 (unclassified PHI) | Run SP_HCLS_PHI_DETECTION against existing CURATED tables | Report of all unclassified PHI columns with remediation priorities |
| **B: Patient Entity Resolution** | #2 (cross-system matching) | Run SP_HCLS_PATIENT_RESOLUTION across FHIR + Workday | Matched patient clusters with confidence scores; duplicates quantified |
| **C: Research Provenance** | #4 (orphaned research data) | Track de-identification lineage for 3-5 research datasets | Provenance graph showing PHI → de-id → research with accountability chain |

### Decision Framework

Ask the room:
1. "Which gap causes the most regulatory risk TODAY?"
2. "Which would deliver the most visible value in 30 days?"
3. "Who would own the pilot?"

**Capture on whiteboard**:
- Selected pilot: ___
- Owner (customer): ___
- Owner (Snowflake): ___
- 30-day checkpoint date: ___
- Success criteria: ___

---

## BREAK (10 min)

---

## Segment 6 — Staffing-Outcomes Intelligence

**Time**: 3:10 - 3:45 (35 minutes)

**Objective**: Demonstrate how cross-system analytics (Workday + FHIR) reveals staffing-outcome correlations that no single system can surface independently.

**Setup**:
- Whiteboard: Draw the join path diagram (Workday Shifts → Departments → Organizations → FHIR Encounters)
- Pull up `HCLS_STAFFING_OUTCOME_METRICS` table in Snowflake UI

### 3:10-3:15 | Concept Introduction (5 min)

**Talk Track**:
> "Traditional approaches analyze staffing and outcomes in silos. HR sees turnover. Quality sees readmissions. Nobody connects them. The Knowledge Graph does."
>
> "We've ingested Workday HCM data — shifts, assignments, certifications, overtime — and linked it to FHIR encounters through the organizational hierarchy. The graph's INFLUENCED_BY edges represent statistically validated correlations between staffing features and patient outcomes."

**Whiteboard — INFLUENCED_BY Edge Pattern**:

```
┌──────────────────┐    INFLUENCED_BY    ┌──────────────────┐
│  STAFFING_CONTEXT │──────────────────→  │  PATIENT_OUTCOME │
│  Nurse Ratio: 1:6 │   r=0.68           │  Readmission: Y  │
│  Unit: ICU         │                    │  30-day return    │
│  Overtime: 18%     │                    │                   │
└──────────────────┘                     └──────────────────┘
```

### 3:15-3:25 | Live Demo: Staffing Context (10 min)

**Query 1 — Unit-level staffing at shift granularity**:

```sql
-- Show staffing context: unit-level nurse ratios and overtime
SELECT
    unit_type,
    department_name,
    ROUND(AVG(actual_ratio), 1) AS avg_nurse_ratio,
    ROUND(AVG(target_nurse_ratio), 1) AS target_ratio,
    ROUND(AVG(actual_ratio) / NULLIF(AVG(target_nurse_ratio), 0) * 100, 0) AS pct_of_target,
    ROUND(AVG(overtime_pct) * 100, 1) AS overtime_pct,
    COUNT(DISTINCT shift_date) AS shifts_observed
FROM SEM_DEV.HCLS_ANALYTICS.HCLS_STAFFING_CONTEXT
GROUP BY 1, 2
ORDER BY pct_of_target DESC;
```

**Talk Track**:
> "This is unit-level staffing at shift granularity. Look at the ICU — actual ratio 1:3 vs target 1:2. That unit is 50% over target. Every shift at that ratio increases mortality risk by 7% according to the Aiken research."

**Query 2 — Overtime trending**:

```sql
-- Overtime trending over 3 months
SELECT
    DATE_TRUNC('week', shift_date) AS week,
    unit_type,
    ROUND(AVG(overtime_pct) * 100, 1) AS overtime_pct,
    COUNT(DISTINCT worker_id) AS unique_nurses
FROM SEM_DEV.HCLS_ANALYTICS.HCLS_STAFFING_CONTEXT
WHERE shift_date >= DATEADD('month', -3, CURRENT_DATE())
GROUP BY 1, 2
ORDER BY 1, 2;
```

> "Overtime trending up over 3 months. This isn't a one-time staffing crunch — it's a structural problem. And we can now correlate it directly with patient outcomes."

### 3:25-3:35 | Live Demo: Correlation Results (10 min)

```sql
-- Staffing-outcome Pearson correlations
SELECT
    staffing_feature,
    outcome_measure,
    ROUND(correlation_coefficient, 3) AS pearson_r,
    sample_size,
    CASE
        WHEN ABS(correlation_coefficient) >= 0.7 THEN 'STRONG'
        WHEN ABS(correlation_coefficient) >= 0.4 THEN 'MODERATE'
        ELSE 'WEAK'
    END AS strength
FROM SEM_DEV.HCLS_ANALYTICS.HCLS_CORRELATION_RESULTS
ORDER BY ABS(correlation_coefficient) DESC;
```

**Talk Track**:
> "Nurse ratio correlates at r=0.68 with readmission rate. That's statistically significant and actionable. This isn't just 'staffing is bad' — it quantifies HOW MUCH worse each ratio point makes outcomes."
>
> "Compare to the Aiken et al. literature: they found r=0.65-0.72 in a 168-hospital study. Our data is consistent with published research — which validates the model AND gives you confidence to act on it."

**Key Knowledge Graph query**:

```sql
-- Which encounters were influenced by understaffing?
SELECT e.edge_type, n1.display_name AS encounter, n2.display_name AS staffing_context,
       e.properties:correlation_strength::FLOAT AS correlation
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n1 ON e.source_node_id = n1.node_id
JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n2 ON e.target_node_id = n2.node_id
WHERE e.edge_type = 'INFLUENCED_BY'
ORDER BY correlation DESC
LIMIT 10;
```

> "The Knowledge Graph made this connection automatically. Traditional BI would require manually joining 5+ tables across two systems."

### 3:35-3:45 | Discussion: Customer's Staffing Data (10 min)

**Facilitation prompts**:

| Question | What You're Looking For |
|----------|------------------------|
| "Do you have this data accessible? What HR/workforce system do you use?" | Workday, Kronos, API Health, or homegrown — determines integration path |
| "Can you tell me your current nurse-to-patient ratios by unit?" | Validates whether they track this at all; compare to benchmarks |
| "What's your RN turnover rate trailing 12 months?" | National avg is 22.5%; anything above 18% is actionable |
| "Do you track overtime at the shift level?" | Many orgs only track at pay period level — shift-level needed for correlation |

**Whiteboard**: Map their data sources to our ontology model. Draw edges from their systems to the Knowledge Graph node types.

**Materials**: Printed STAFFING_OUTCOMES.md for reference, benchmark targets table

---

## Segment 7 — Comorbidity & Payer Intelligence

**Time**: 3:45 - 4:20 (35 minutes)

**Objective**: Show how comorbidity stratification reveals payer behavior patterns and informs revenue cycle strategy.

### 3:45-3:50 | Concept Introduction (5 min)

**Talk Track**:
> "The Charlson Comorbidity Index has been the gold standard in clinical research for 30 years. We're applying it to payer analytics — stratifying denial rates, prior auth friction, and plan-of-care gaps by patient complexity."
>
> "The insight is counterintuitive: sicker patients face MORE administrative friction, not less. Understanding this pattern by payer and by CCI tier transforms revenue cycle strategy."

**CCI Tier Definitions** (write on whiteboard):

| Tier | CCI Score | Typical Profile | Expected Cost Multiplier |
|------|-----------|----------------|------------------------|
| LOW | 0-1 | Healthy, single acute event | 1.0x |
| MODERATE | 2-3 | 2-3 chronic conditions | 2.5x |
| HIGH | 4-6 | Multi-morbid, polypharmacy | 7x |
| SEVERE | 7+ | Complex, frequent utilizer | 18x |

### 3:50-4:00 | Live Demo: Comorbidity Landscape (10 min)

**Query 1 — CCI distribution**:

```sql
-- Comorbidity tier distribution and impact
SELECT
    cci_tier,
    COUNT(DISTINCT patient_id) AS patient_count,
    ROUND(AVG(cci_score), 1) AS avg_score,
    ROUND(COUNT(DISTINCT patient_id)::FLOAT /
        (SELECT COUNT(DISTINCT patient_id) FROM SEM_DEV.HCLS_ANALYTICS.HCLS_PATIENT_COMORBIDITY) * 100, 1
    ) AS pct_of_population,
    contributing_conditions_top3
FROM SEM_DEV.HCLS_ANALYTICS.HCLS_PATIENT_COMORBIDITY
GROUP BY 1, 5
ORDER BY CASE cci_tier
    WHEN 'LOW' THEN 1 WHEN 'MODERATE' THEN 2
    WHEN 'HIGH' THEN 3 WHEN 'SEVERE' THEN 4
END;
```

**Talk Track**:
> "Your SEVERE tier (CCI 7+) is only 8% of patients but drives 35% of total cost. This is where population health and payer negotiations intersect."

**Query 2 — Top co-occurring condition pairs**:

```sql
-- Most common comorbidity pairs
SELECT condition_a_desc, condition_b_desc, shared_patient_count,
       ROUND(co_occurrence_rate * 100, 1) AS co_occurrence_pct
FROM SEM_DEV.HCLS_ANALYTICS.HCLS_COMORBIDITY_PAIRS
ORDER BY shared_patient_count DESC
LIMIT 10;
```

> "Diabetes + Hypertension appears in the largest cluster. These aren't just clinical trivia — they predict which patients will consume the most resources and face the most payer friction."

**Knowledge Graph traversal** — show COMORBID_WITH edges:

```sql
-- Comorbidity clusters in the Knowledge Graph
SELECT n1.display_name AS condition_a, n2.display_name AS condition_b,
       e.weight AS co_occurrence_strength
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n1 ON e.source_node_id = n1.node_id
JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n2 ON e.target_node_id = n2.node_id
WHERE e.edge_type = 'COMORBID_WITH'
ORDER BY e.weight DESC
LIMIT 10;
```

### 4:00-4:10 | Live Demo: Payer Response Patterns (10 min)

**Query 1 — Denial rates by CCI tier and payer**:

```sql
-- Payer denial patterns by comorbidity
SELECT cci_tier, payer_name,
       ROUND(denial_rate * 100, 1) AS denial_pct,
       ROUND(avg_adjudication_days, 0) AS days_to_decide,
       ROUND(prior_auth_rate * 100, 1) AS prior_auth_pct,
       total_claims
FROM SEM_DEV.HCLS_ANALYTICS.HCLS_PAYER_METRICS
WHERE total_claims > 100
ORDER BY cci_tier, denial_rate DESC;
```

**Talk Track**:
> "Look at the SEVERE tier — [payer X] denies [Y]% of claims and takes [Z] days to adjudicate. That's a revenue cycle problem hiding in comorbidity data that only the Knowledge Graph connects."
>
> "Key insight: your sickest patients face the most administrative friction. The 28% denial rate at $78K average — that's $X million in underpayment risk for this payer alone."

**Query 2 — Plan of care gaps (approved vs actual)**:

```sql
-- Care plan gaps: Where payers approve less than clinical need
SELECT cci_tier, payer_name,
       ROUND(AVG(approved_days), 1) AS avg_approved,
       ROUND(AVG(actual_days), 1) AS avg_actual,
       ROUND(AVG(variance_days), 1) AS avg_gap,
       ROUND(SUM(CASE WHEN readmitted_30day THEN 1 ELSE 0 END)::FLOAT /
             NULLIF(COUNT(*), 0) * 100, 1) AS readmit_pct_early_discharge
FROM SEM_DEV.HCLS_ANALYTICS.HCLS_CARE_GAPS
WHERE gap_type = 'EARLY_DISCHARGE'
GROUP BY 1, 2
ORDER BY avg_gap DESC;
```

> "Patients discharged before payer-approved end date have a [X]% readmission rate for SEVERE comorbidity vs [Y]% for those held to clinical need. Sending patients home too early costs more than the extended stay. This is the data you bring to payer negotiations."

### 4:10-4:20 | Discussion: Revenue Cycle Application (10 min)

**Facilitation prompts**:

| Question | What You're Looking For |
|----------|------------------------|
| "What's your current denial rate by payer? Do you stratify by patient complexity?" | Most don't stratify by CCI — this is the gap |
| "How do you prioritize prior auth requests?" | Usually FIFO; should be by CCI tier and payer pattern |
| "Can you quantify the cost of prior auth delays?" | Few can; the graph provides this visibility |
| "Which payer relationships would benefit most from this analysis?" | Identify top 3 payers to analyze first |

**Whiteboard**: Map their payer contracts to our analytical framework. Identify top 3 payer relationships to analyze first.

**Q&A for Segments 6-7**:

| Question | Response |
|----------|----------|
| "Is the CCI calculated in real-time?" | Yes, `SP_HCLS_COMORBIDITY_INDEX()` refreshes on each graph run |
| "How does this compare to CMS risk adjustment?" | CCI is one input; HCC risk adjustment is complementary but uses different grouper logic |
| "Can we share this with payers?" | Yes, de-identified via the Knowledge Graph's DE_IDENTIFIED_FROM edge provenance |
| "How is the correlation computed?" | Pearson coefficient on monthly aggregates, stored in HCLS_CORRELATION_RESULTS |
| "Can we use this for predictive staffing?" | Yes, the time-series data enables forecasting models |

**Materials**: Printed COMORBIDITY_PAYER.md, CCI mapping table, denial reason code reference

---

## Post-Workshop Deliverables

| Deliverable | Owner | Timeline |
|-------------|-------|----------|
| Whiteboard photos (Gap Map, Architecture, Pilot Plan) | Snowflake | Same day |
| HIPAA Compliance Scoring Rubric (completed with customer-specific weights) | Snowflake | 3 business days |
| Knowledge Graph deployment scripts (SQL files from `demos/hcls/sql/`) | Snowflake | Same day (already in Git) |
| Streamlit dashboard demo environment (available for customer exploration) | Snowflake | Same day |
| Finalized 30/60/90 Roadmap with customer-specific systems and owners | Joint | 5 business days |
| Pilot kick-off meeting | Joint | Within 1 week |
| Staffing-outcome correlation analysis plan (which units to analyze first) | Joint | 5 business days |
| Payer stratification roadmap (which contracts to focus on) | Joint | 5 business days |
| Comorbidity risk model proposal (CCI implementation plan) | Snowflake | 5 business days |

## Materials Checklist

- [ ] Whiteboard markers (multiple colors — use different colors for each compliance lane)
- [ ] Printed HCLS Pain Point Worksheets (one per attendee — 5 pain points with blank columns)
- [ ] Printed HIPAA Compliance Scoring Rubric (one per attendee — shows 5-dimension model)
- [ ] Printed Architecture Diagram (one per attendee — three-layer graph model)
- [ ] Printed STAFFING_OUTCOMES.md (one per attendee — staffing correlation benchmarks)
- [ ] Printed COMORBIDITY_PAYER.md (one per attendee — CCI tiers and payer patterns)
- [ ] Printed CCI Mapping Table (Charlson condition weights)
- [ ] Printed Denial Reason Code Reference (top 20 codes)
- [ ] Laptop with Knowledge Graph demo ready:
  - [ ] Snowflake UI open to `DCA_DEMO.GOVERNANCE` schema
  - [ ] SQL worksheet with Demo 1-5 queries pre-loaded (Segments 1-5)
  - [ ] SQL worksheet with Segment 6-7 queries pre-loaded (staffing, comorbidity, payer)
  - [ ] Workday and Payer data generators run and loaded
  - [ ] Scripts 04-07 deployed (`SP_HCLS_MASTER_ORCHESTRATOR()` run successfully)
  - [ ] Streamlit app running (verify Knowledge Graph page renders)
  - [ ] Snowflake UI tab ready for `ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS` query
  - [ ] Snowflake UI tab ready for `ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES` query
- [ ] Backup: Screenshots of Knowledge Graph Streamlit page (in case of connectivity issues)
- [ ] Video conferencing link for remote participants
- [ ] Camera/phone for whiteboard captures
- [ ] HDMI/USB-C adapter for projecting from laptop

## Facilitator Notes

### Handling Common Objections

| Objection | Response |
|-----------|----------|
| "We already have a PHI inventory" | "Great — let's validate it against the graph. In every engagement we've done, the graph finds 15-30% more PHI locations than manual inventories." |
| "Our EHR vendor handles HIPAA compliance" | "For data at rest in the EHR, yes. But what about data that's been extracted for analytics, research, or population health? That's where gaps appear." |
| "We need to involve Legal/Compliance before a pilot" | "Absolutely — they should be sponsors, not blockers. The pilot output is a HIPAA findings report, which is exactly what they need for the next OCR audit." |
| "Entity resolution is an MPI problem" | "Traditional MPIs require expensive appliances and deterministic matching rules. The graph approach uses probabilistic matching and improves with each inference run." |
| "Can this integrate with our GRC tool?" | "Yes — governance scores and recommendations are standard Snowflake tables. Any GRC tool that can query Snowflake (or receive a data share) can consume them." |

### Key Transitions

- **Segment 1 → 2**: "We've named the gaps. Now let me show you the architecture that closes them."
- **Segment 2 → 3**: "That's the theory. Let's prove it works with live queries against real clinical data structures."
- **Segment 3 → 4**: "You've seen it work. The question is: how do we get THIS running against YOUR data?"
- **Segment 4 → 5**: "The roadmap shows what's possible. Let's pick ONE thing and commit to delivering it in 30 days."
- **Segment 5 → 6**: "We've committed to a pilot. Now let me show you what's possible when we connect workforce data to clinical outcomes — this is where the CNO gets excited."
- **Segment 6 → 7**: "Staffing affects outcomes. But comorbidity affects EVERYTHING — cost, LOS, denial rates, readmissions. Let me show you how payers respond differently to patient complexity."
