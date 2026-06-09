# Healthcare & Life Sciences — 30/60/90 Execution Roadmap

> Phased deployment of Snowflake's governed healthcare platform with automated HIPAA compliance, cross-system analytics, and Business Critical resilience.

## Roadmap Overview

```mermaid
flowchart LR
    subgraph P0["PHASE 0 — Pre-Deploy"]
        H["PLATFORM HARDENING\nBC Provisioning\nNetwork Security\nCross-Region Replication\nFailover Testing"]
    end
    subgraph P1["PHASE 1 — 30 Days"]
        F["DATA PLATFORM &\nGOVERNANCE\nClinical Data Landing\nPHI Classification\nCompliance Detection\nHIPAA Baseline"]
    end
    subgraph P2["PHASE 2 — 60 Days"]
        I["INTELLIGENCE\nEntity Resolution\nCare Pathways\nPHI Detection at Scale\nClinical Analytics API"]
    end
    subgraph P3["PHASE 3 — 90 Days"]
        FED["FEDERATION\nResearch Enablement\nExternal Sharing\nContinuous Compliance\nRegulatory Reporting"]
    end
    P0 --> P1 --> P2 --> P3
```

---

## Phase 0: Platform Hardening (Pre-Deployment)

**Theme**: Establish HIPAA-grade security baseline on Business Critical before any clinical data lands.

### 0.1 Business Critical Provisioning

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Provision BC accounts (primary + secondary) | Two accounts in same organization, different regions | Platform / SE | ☐ |
| Enable organization-level replication | Contact Snowflake support if not already enabled | Platform | ☐ |
| Configure Tri-Secret Secure | If customer requires customer-managed keys (CMK via AWS KMS / Azure KV) | Security + Platform | ☐ |
| Verify BC edition features active | `SELECT SYSTEM$IS_APPLICATION_ROLE_ENABLED('SNOWFLAKE.SECURITY')` | SE | ☐ |

### 0.2 Network Security

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Deploy network policies (HCLS_RESTRICTED_ACCESS) | IP allowlisting with customer corporate CIDRs | Security Engineer | ☐ |
| Configure PrivateLink (if customer requires) | Eliminate public internet exposure entirely | Security + Infrastructure | ☐ |
| Set session policies (30-min idle timeout) | HIPAA §164.312(a)(2)(iii) automatic logoff | Security Engineer | ☐ |
| Test: verify blocked access from unauthorized IPs | Login from allowed IP succeeds, other IPs fail with 390144 | SE | ☐ |

### 0.3 Cross-Region Replication

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Create failover group (DCA_BCDR_DB_FG) | GOVERNANCE, RAW_DEV, CURATED_DEV, SEM_DEV on 10-min schedule | Data Engineering | ☐ |
| Create client-redirect connection (DCA_DEMO_CONNECTION) | Transparent failover — no connection string changes needed | Data Engineering | ☐ |
| Configure 10-minute replication schedule | Aligned with healthcare RPO target | Data Engineering | ☐ |
| Verify initial replication succeeds | All 4 databases visible as SECONDARY on DR account | SE | ☐ |
| Deploy Streamlit warm standby on secondary | BCDR_DEMO.STREAMLIT.DCA_DEMO_APP pointing to replicated stage | Data Engineering | ☐ |

### 0.4 Failover Drill

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Execute planned failover to secondary | ALTER FAILOVER GROUP DCA_BCDR_DB_FG PRIMARY on secondary | SE + Platform | ☐ |
| Verify application availability < 5 min (RTO) | Streamlit app accessible on secondary account | SE | ☐ |
| Verify data loss < 10 min (RPO) | Compare pre/post failover timestamps | SE | ☐ |
| Execute failback to primary | Return primary role to original account, verify sync | SE + Platform | ☐ |
| Document drill results | Record timing, issues, and governance score comparison | SE | ☐ |

### Phase 0 Success Criteria

- [ ] BC edition verified on both accounts
- [ ] Network policy active and tested
- [ ] Replication lag < 15 minutes consistently
- [ ] Failover drill completed successfully
- [ ] Session policy enforced

---

## Phase 1: Data Platform & Governance (30 Days)

**Theme**: Land clinical data into governed platform with automated PHI classification, compliance detection, and HIPAA baseline scoring.

### Workstreams

#### 1.1 Governed Data Platform Deployment

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Deploy core DCA scripts 01-07 | Setup, governance, raw/curated layers, tags, masking, RBAC | Data Engineering | ☐ |
| Deploy HCLS graph extensions | Run 01_hcls_graph_populate.sql for clinical node/edge types | Data Engineering | ☐ |
| Verify governance analytics populated | Confirm FHIR nodes (PATIENT, ENCOUNTER, CONDITION) appear in ontology | Data Engineering | ☐ |
| Run SP_REFRESH_GRAPH() | Full metadata + business layer graph refresh | Data Engineering | ☐ |

#### 1.2 PHI Classification

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Audit known PHI columns | Document all columns in FHIR schema containing PHI elements | Privacy/Compliance | ☐ |
| Apply HIPAA_CATEGORY tags | Tag all DIM_PATIENT, FACT_ENCOUNTERS PHI columns | Data Steward | ☐ |
| Run SP_REFRESH_GRAPH() | Re-populate graph with new tag relationships | Data Engineering | ☐ |
| Validate tag propagation | Confirm TAGGED_WITH edges exist for all PHI columns | Joint | ☐ |

#### 1.3 Initial Compliance Detection

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Run automated inference | Execute compliance detection against FHIR-populated graph | Data Engineering | ☐ |
| Run SP_HCLS_PHI_DETECTION() | HCLS-specific PHI propagation detection across all schemas | Data Engineering | ☐ |
| Review recommendations with CPO | Walk through HIGH severity findings | Joint — CPO + Data Eng | ☐ |
| Prioritize remediation | Rank gaps by regulatory risk and data sensitivity | Privacy/Compliance | ☐ |

#### 1.4 HIPAA Gap Baseline

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Record initial governance scores | Snapshot all FHIR object scores as compliance baseline | Data Steward | ☐ |
| Document known gaps | Record intentional gaps (demo) vs. real gaps (production) | Privacy/Compliance | ☐ |
| Establish scoring thresholds | Define acceptable score ranges (e.g., >0.7 = compliant) | Joint — CPO + Legal | ☐ |
| Create baseline report | Generate first HIPAA compliance evidence package | Privacy/Compliance | ☐ |

### Phase 1 Success Criteria

- [ ] Graph populated with FHIR metadata + business nodes
- [ ] All DIM_PATIENT columns tagged with HIPAA_CATEGORY
- [ ] Automated detection finding at least 3 PHI propagation gaps
- [ ] Baseline compliance score recorded
- [ ] Masking policies verified across all roles

---

## Phase 2: Intelligence (60 Days)

**Theme**: Entity resolution, care pathways, automated PHI detection at scale, clinical analytics API.

### Workstreams

#### 2.1 Patient Entity Resolution

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Run SP_HCLS_PATIENT_RESOLUTION() | Cross-system matching (FHIR + Workday) via stored procedures | Data Engineering | ☐ |
| Configure confidence thresholds | Set minimum Jaccard similarity for auto-match vs. manual review | Joint | ☐ |
| Validate match accuracy | Manually verify sample of entity clusters | Clinical Informatics | ☐ |
| Extend to Claims system | Add claims subscriber matching to resolution logic | Data Engineering | ☐ |

#### 2.2 Care Pathway Construction

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Run SP_HCLS_CARE_PATHWAY() | Build temporal encounter→condition→medication edges | Data Engineering | ☐ |
| Validate pathway completeness | Confirm full journey traversable for sample patients | Clinical Informatics | ☐ |
| Add procedure edges | Link FACT_PROCEDURES to encounters and practitioners | Data Engineering | ☐ |
| Test pathway queries | Verify care gap detection works via relationship analysis | Analytics | ☐ |

#### 2.3 PHI Detection Expansion

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Extend detection to all schemas | Run PHI detection beyond FHIR — include RAW, SEMANTIC layers | Data Engineering | ☐ |
| Add Claims PHI patterns | Extend pattern matching for claims-specific PHI identifiers | Data Engineering | ☐ |
| Add Lab/Pharmacy patterns | Detect PHI in raw JSON blob columns from lab systems | Data Engineering | ☐ |
| Validate false positive rate | Review and tune detection patterns to minimize noise | Joint | ☐ |

#### 2.4 Automated Remediation

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Configure SP_APPLY_RECOMMENDATIONS() | Set auto-tagging rules for HIGH-confidence recommendations | Data Steward + Security | ☐ |
| Define approval workflow | Which recommendations auto-apply vs. require CPO approval | Privacy/Compliance | ☐ |
| Test auto-remediation | Run on sample gaps, verify correct tags applied | Data Engineering | ☐ |
| Monitor remediation history | Track recommendations applied vs. outstanding over time | Data Steward | ☐ |

#### 2.5 Clinical Analytics API

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Deploy analytics API for clinical apps | Endpoint returning patient 360 + governance scores | Data Engineering | ☐ |
| Integrate with clinical decision support | Connect API to downstream clinical applications | App Development | ☐ |
| Add HIPAA scoring endpoint | API returns compliance posture for any object/patient | Data Engineering | ☐ |
| Load test API | Validate performance under clinical workload patterns | Platform | ☐ |

### Phase 2 Success Criteria

- [ ] 90%+ patient match rate across FHIR and Claims
- [ ] Care pathways traversable for any patient
- [ ] PHI detection covers all RAW, CURATED, SEMANTIC schemas
- [ ] Clinical analytics API returning governance scores

---

## Phase 3: Federation (90 Days)

**Theme**: Research enablement, external partner sharing, continuous compliance.

### Workstreams

#### 3.1 De-identification Provenance

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Track research datasets | Record DE_IDENTIFIED_FROM edges for all research-derived tables | Data Engineering | ☐ |
| Document de-identification methods | Store method (Safe Harbor, Expert Determination) as edge properties | Privacy/Compliance | ☐ |
| Link to IRB approvals | Create IRB_APPROVED edges from research datasets to protocol references | Privacy/Compliance | ☐ |
| Validate provenance queries | Confirm any research dataset can trace back to source PHI with method | Joint | ☐ |

#### 3.2 External Partner Sharing

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Configure ONTOLOGY_GRAPH_DATA_SHARE | Set up governed share for approved external partners | Platform | ☐ |
| Define sharing policies | Which data, what de-identification level, which partners | Privacy/Compliance + Legal | ☐ |
| Validate governance travels with share | Confirm masking/RAP policies apply to shared data | Security | ☐ |
| Onboard first external partner | Execute end-to-end sharing workflow with pilot partner | Joint | ☐ |

#### 3.3 Continuous Compliance Dashboard

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Deploy Streamlit compliance page | Real-time HIPAA posture for CPO with trend analysis | Data Engineering | ☐ |
| Add trend visualizations | Score history, remediation velocity, gap aging | Data Engineering | ☐ |
| Configure alerting | Notify CPO when scores drop below threshold | Platform | ☐ |
| Validate with privacy office | CPO acceptance testing of dashboard for audit readiness | Privacy/Compliance | ☐ |

#### 3.4 Regulatory Reporting

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Generate HIPAA compliance evidence | Automated evidence packages from platform data (access, classification, audit) | Data Engineering | ☐ |
| Map to HIPAA safeguards | Link evidence to specific §164.312 requirements | Privacy/Compliance | ☐ |
| Test with mock audit | Simulate OCR audit using generated evidence | Legal + Compliance | ☐ |
| Document audit response process | Playbook for using governance analytics during real audits | Privacy/Compliance | ☐ |

#### 3.5 Integration with Existing GRC Tools

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Export scores to ServiceNow/Archer | Push governance scores and recommendations to GRC platform | Platform + GRC Team | ☐ |
| Configure bidirectional sync | Pull remediation status back from GRC into analytics | Data Engineering | ☐ |
| Validate workflow integration | Confirm GRC tickets created automatically for HIGH findings | Joint | ☐ |
| Document integration architecture | API contracts and data flow for GRC integration | Data Engineering | ☐ |

### Phase 3 Success Criteria

- [ ] Research datasets have provable de-identification lineage
- [ ] External partners access de-identified data via governed share
- [ ] CPO has real-time compliance dashboard (no manual audits)
- [ ] HIPAA audit evidence generated automatically

---

## Pilot Selection Framework

Use this framework during the workshop (Segment 5) to select the initial pilot:

| Criterion | Weight | Candidate 1 | Candidate 2 | Candidate 3 |
|-----------|--------|------------|------------|------------|
| **Regulatory urgency** — does solving this reduce audit risk now? | High | | | |
| **Data readiness** — is the FHIR/clinical data loaded and accessible? | High | | | |
| **Team availability** — can Privacy + Engineering staff this? | Medium | | | |
| **Architecture coverage** — does it exercise governance, detection, and scoring? | Medium | | | |
| **Research potential** — does it enable downstream research use cases? | Low | | | |

**Likely pilot candidates** (based on discovery):
1. **PHI Classification Sweep** — Run automated detection against existing CURATED tables, remediate top-10 gaps
2. **Patient Matching for Population Health** — FHIR + Claims entity resolution for cohort identification
3. **Research Dataset Provenance** — Track de-identification lineage for existing ML training datasets

## Accountability Matrix

| Role | Phase 0 Responsibility | Phase 1 Responsibility | Phase 2 Responsibility | Phase 3 Responsibility |
|------|----------------------|----------------------|----------------------|----------------------|
| **Security Engineer** | Network policies, encryption, failover testing, PrivateLink | Validate masking policies, session enforcement | Graph governance review, in-database access controls | External sharing security validation |
| **Chief Privacy Officer** | Approve security baseline | Define HIPAA thresholds, approve baseline | Approve auto-remediation rules | Accept compliance dashboard, sign-off on evidence |
| **CMIO** | — | Validate clinical data structure | Validate care pathways and entity resolution | Validate research enablement workflow |
| **VP Data & Analytics** | Executive sponsor for BC provisioning | Resource allocation, governance strategy | API integration decisions | GRC integration, external sharing strategy |
| **Data Engineer** | Deploy BC/DR scripts, verify replication | Deploy scripts, populate graph, run detection | Extend detection, build pathways, deploy API | Build dashboard, evidence generation, GRC export |
| **Snowflake EA** | BC architecture review, failover design | Governance architecture guidance | Clinical analytics API design review | Federation and sharing governance review |

## References

- [Discovery & Current State](DISCOVERY.md)
- [Architecture Strategy](ARCHITECTURE_STRATEGY.md)
- [Workshop Facilitation Guide](WORKSHOP_GUIDE.md)
- [Deployment Runbook](DEPLOYMENT_RUNBOOK.md)
- [Platform Security](PLATFORM_SECURITY.md)
- [Governance Framework](../../docs/GOVERNANCE.md)
