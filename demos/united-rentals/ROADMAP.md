# United Rentals — 30/60/90 Execution Roadmap

> Phased transition from fragmented multi-account architecture to a Federated Data Product Factory.

## Roadmap Overview

```
         PHASE 1                    PHASE 2                    PHASE 3
         30 Days                    60 Days                    90 Days
  ┌─────────────────┐       ┌─────────────────┐       ┌─────────────────┐
  │  FOUNDATION      │       │  MARKETPLACE     │       │  FEDERATION      │
  │                  │       │                  │       │                  │
  │  Identity Plane  │       │  Internal Data   │       │  Federated       │
  │  Container-by-DB │──────►│  Exchange         │──────►│  Governance      │
  │  SSO + RBAC      │       │  First Provider  │       │  External Mktpl  │
  │  Pilot Domain    │       │  CI/CD Pipeline  │       │  Cortex AI Prod  │
  └─────────────────┘       └─────────────────┘       └─────────────────┘
```

---

## Phase 1: Foundation (30 Days)

**Theme**: Standardize the Container-by-DB pattern for the Primary Hub and unify identity.

### Workstreams

#### 1.1 Identity Plane — SSO Harmonization

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Audit current auth models | Document local auth (Prod), SSO (Discovery), service accounts | UR Platform | ☐ |
| Design unified IdP integration | Single SSO layer wrapping both Production and Discovery accounts | UR Security + Snowflake | ☐ |
| Implement MFA for Production | Align Prod security with Discovery's SSO/MFA standard | UR Security | ☐ |
| Design RBAC hierarchy | Map roles across Prod, Dev, and Discovery — operational vs. financial vs. domain-specific | Joint | ☐ |

#### 1.2 Container-by-DB — Primary Hub Standardization

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Define naming conventions | Standardize database naming: `RAW_<DOMAIN>`, `CURATED_<DOMAIN>`, `SEMANTIC_<DOMAIN>` | Joint | ☐ |
| Create Manning container | Dedicated RAW/CURATED/SEMANTIC databases for Manning team | UR Data Eng | ☐ |
| Create Sales Ops container | Dedicated RAW/CURATED/SEMANTIC databases for Sales Ops team | UR Data Eng | ☐ |
| Implement zero-copy cloning | Dev/test environments for each domain via cloning from production databases | UR Platform | ☐ |
| Apply Snowflake Horizon tags | Tag all objects with DATA_CLASSIFICATION, PII_TYPE, AI_ALLOWED | UR Data Steward | ☐ |

#### 1.3 Pilot Domain Selection

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Select pilot domain | Choose one domain from workshop (Fleet, Telematics, or EDW subset) | Joint — workshop output | ☐ |
| Define pilot data contract | Schema, quality rules, SLA, governance requirements for the pilot | Joint | ☐ |
| Implement pilot RAW → CURATED | Build transformation pipeline using Dynamic Tables or dbt | UR Data Eng | ☐ |
| Validate pilot against contract | Run contract validation; confirm quality gates pass | UR Data Eng + Snowflake | ☐ |

### Phase 1 Success Criteria

- [ ] All accounts accessible via single SSO
- [ ] Manning and Sales Ops have isolated Container-by-DB environments
- [ ] Pilot domain has working RAW → CURATED → SEMANTIC pipeline
- [ ] Snowflake Horizon tags applied to pilot domain objects
- [ ] Zero-copy clone process documented and tested

---

## Phase 2: Marketplace (60 Days)

**Theme**: Launch the UR Private Data Exchange and onboard the first Internal Provider.

### Workstreams

#### 2.1 Internal Data Exchange

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Design marketplace topology | Hub-and-Spoke: which domains are providers, which are consumers | Joint | ☐ |
| Configure secure data sharing | Set up Snowflake Secure Shares for internal marketplace | UR Platform | ☐ |
| Define listing standards | What metadata, documentation, and quality thresholds qualify a data product for listing | UR Data Steward | ☐ |
| Build self-service discovery | Snowflake Horizon catalog for browse-and-subscribe | UR Platform + Snowflake | ☐ |

#### 2.2 First Provider Onboarding — Telematics

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Publish Telematics data product | First domain to "publish" to the internal marketplace | Telematics Team | ☐ |
| Define consumer access patterns | Who consumes telematics data, what access controls apply | Joint | ☐ |
| Validate cross-domain sharing | Confirm Horizon policies travel with shared data | UR Platform | ☐ |
| Measure consumption | Track who subscribes and how the data product is used | UR Data Steward | ☐ |

#### 2.3 CI/CD Pipeline — SDLC Bridge

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Connect Git integration | Snowflake Git integration or external Git repo (GitHub/Azure DevOps) | UR Data Eng | ☐ |
| Build promotion pipeline | Automated promotion from Discovery → Dev → Prod governed by Promotion Role | UR Data Eng + Snowflake | ☐ |
| Define promotion gates | Code review, contract validation, governance check, test pass | Joint | ☐ |
| Test end-to-end promotion | Promote one workload from Discovery through to Production | UR Data Eng | ☐ |

### Phase 2 Success Criteria

- [ ] At least one domain publishing data products to the internal exchange
- [ ] At least two consumer teams subscribing to marketplace data products
- [ ] CI/CD pipeline successfully promotes one workload from Discovery → Prod
- [ ] Horizon policies verified to travel with shared data
- [ ] Self-service catalog accessible to authorized users

---

## Phase 3: Federation (90 Days)

**Theme**: Establish federated governance and extend the platform to external data and production AI.

### Workstreams

#### 3.1 Federated Governance

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Extend Horizon policies | Apply governance policies uniformly across all domains in the hub | UR Data Steward | ☐ |
| Implement masking policies | Dynamic masking for PII (customer SSN/EIN), contract pricing, sensitive ops data | UR Security | ☐ |
| Implement row access policies | Region-based, branch-based, and customer-segment filtering | UR Security | ☐ |
| Validate lineage end-to-end | Trace from Fivetran ingestion → transformation → Cortex AI output | UR Data Eng + Snowflake | ☐ |

#### 3.2 External Marketplace Integration

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Identify external data sources | OEM telematics, weather, economic indicators, market data | UR Analytics | ☐ |
| Mount external datasets | Subscribe to Snowflake Marketplace listings — no ETL | UR Platform | ☐ |
| Integrate external data into domains | Enrich Fleet and Telematics domains with external data | UR Data Eng | ☐ |
| Apply governance to external data | Tag and classify external data under the same Horizon framework | UR Data Steward | ☐ |

#### 3.3 Production Cortex AI

| Task | Detail | Owner | Status |
|------|--------|-------|--------|
| Promote first AI model to Production | Use CI/CD pipeline to move validated Cortex model from Discovery → Prod | UR AI/ML + Snowflake | ☐ |
| Build Semantic Views for Cortex Analyst | Create production semantic layer for branch-level natural language queries | UR Data Eng + Snowflake | ☐ |
| Configure branch manager access | Cortex Analyst access governed by row access policies (region/branch filtering) | UR Security | ☐ |
| Validate "Branch Manager AI" | Test: "What assets can I rent within 50 miles?" returns correct, governed results | Joint | ☐ |

### Phase 3 Success Criteria

- [ ] Masking and row access policies active across all domains
- [ ] End-to-end lineage visible from ingestion to Cortex AI output
- [ ] At least one external marketplace dataset integrated into a domain
- [ ] At least one Cortex AI model running in Production
- [ ] Branch manager can ask natural language questions via Cortex Analyst with role-appropriate results

---

## Pilot Selection Framework

Use this framework during the workshop (Segment 5) to select the 4-week pilot:

| Criterion | Weight | Candidate 1 | Candidate 2 | Candidate 3 |
|-----------|--------|------------|------------|------------|
| **Leadership visibility** — will solving this make noise? | High | | | |
| **Data readiness** — is the source data accessible now? | High | | | |
| **Team availability** — can we staff this in 4 weeks? | Medium | | | |
| **Architecture coverage** — does it exercise Container-by-DB, contracts, and governance? | Medium | | | |
| **AI potential** — does it lead to a Cortex use case? | Low | | | |

**Likely pilot candidates** (based on discovery):
1. **Fleet Availability** — Cortex Analyst answers "What can I rent within 50 miles?" using telematics + rental data
2. **Discovery → Prod Promotion** — Automate one existing AI MVP from Discovery to Production
3. **SSO Unification** — Single identity across Prod and Discovery, enabling seamless user movement

## Accountability Matrix

| Role | Phase 1 Responsibility | Phase 2 Responsibility | Phase 3 Responsibility |
|------|----------------------|----------------------|----------------------|
| **UR Director of Enterprise Data** | Executive sponsor, remove blockers | Marketplace strategy decisions | Federated governance sign-off |
| **UR EDW/Prod Owner** | Container-by-DB implementation, naming standards | CI/CD pipeline, promotion gates | Production Cortex AI deployment |
| **UR Discovery/AI Owner** | SSO harmonization, pilot domain selection | First provider onboarding | Branch Manager AI validation |
| **UR Data Engineer** | Pilot pipeline (DT or dbt), Git integration | End-to-end promotion test | External data integration |
| **Snowflake EA** | Architecture guidance, DCA demo support | Marketplace design review | Federated governance review |

## References

- [Discovery & Current State](DISCOVERY.md)
- [Architecture Strategy](ARCHITECTURE_STRATEGY.md)
- [Workshop Facilitation Guide](WORKSHOP_GUIDE.md)
- [Core SDLC Architecture](../../docs/SDLC_ARCHITECTURE.md)
- [Governance Framework](../../docs/GOVERNANCE.md)
