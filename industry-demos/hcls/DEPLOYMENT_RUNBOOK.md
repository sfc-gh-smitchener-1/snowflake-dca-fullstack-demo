# HCLS Demo — Business Critical Deployment Runbook

> **Bulletproof deployment guide for Snowflake Solutions Engineers.**
> Follow this document start-to-finish for a working HCLS demo on Business Critical accounts with cross-region failover, HIPAA-grade network security, and three-system analytics.

---

## Prerequisites

| Requirement | Details |
|---|---|
| **Primary account** | Snowflake Business Critical edition, us-west-2 (or customer region) |
| **Secondary account** | Snowflake Business Critical edition, us-east-1 (or DR region) |
| **Organization** | Both accounts in the same Snowflake organization |
| **Org-level replication** | Enabled (contact Snowflake support if not) |
| **Access** | ACCOUNTADMIN on both accounts |
| **Local tools** | Python 3.9+ with `faker` library, Git, SnowSQL or Snowflake CLI |
| **Repository** | `git clone https://github.com/sfc-gh-smitchener-1/snowflake-dca-fullstack-demo.git` |

## Environment Setup

| Setting | Primary | Secondary |
|---|---|---|
| Account | OAB74379 | OZC55031 |
| Region | AWS us-west-2 | AWS us-east-1 |
| Organization | SFSENORTHAMERICA | SFSENORTHAMERICA |
| Connection | SNOW_BCDR_PRIMARY | SNOW_BCDR_SECONDARY |
| Edition | Business Critical | Business Critical |

> **Note:** Replace account identifiers, regions, and org name with your actual values throughout this runbook.

---

## Deployment Steps (Exact Order)

### Phase 1: Data Generation (Local Machine)

Generate synthetic data for all three source systems. This runs locally — no Snowflake connection required.

```bash
cd demos/hcls/tools
pip install faker

# FHIR clinical data (~100MB, 10 tables, 320K+ records)
python generate_hcls_data.py --output ../data --scale 1.0

# Workday HCM workforce data (~60MB, 8 tables, 307K+ records)
python generate_workday_hcm_data.py --output ../data --scale 1.0

# Payer financial data (~40MB, 8 tables, 172K+ records)
python generate_payer_data.py --output ../data --scale 1.0
```

**Quick mode** (for testing only — ~10% scale):
```bash
python generate_hcls_data.py --output ../data --quick
python generate_workday_hcm_data.py --output ../data --quick
python generate_payer_data.py --output ../data --quick
```

**Verify:** 26 CSV files in `demos/hcls/data/` (~220MB total at full scale).

```bash
ls -la ../data/*.csv | wc -l
# Expected: 26
du -sh ../data/
# Expected: ~220M (full scale) or ~22M (quick mode)
```

---

### Phase 2: Primary Account — Foundation

> **Connect to:** SNOW_BCDR_PRIMARY (OAB74379)

Run each script in order. Verify after each step before proceeding.

#### Step 2.1: Core Setup

```sql
-- Run: sql/01_setup.sql
-- Creates: databases, schemas, warehouses, roles, grants
```

**Verify:**
```sql
SHOW ROLES LIKE 'DATA_%';
-- Expected: DATA_ADMIN, DATA_ENGINEER, DATA_ANALYST, DATA_SCIENTIST (+ others)

SHOW DATABASES LIKE 'GOVERNANCE';
SHOW DATABASES LIKE 'RAW_DEV';
SHOW DATABASES LIKE 'CURATED_DEV';
SHOW DATABASES LIKE 'SEM_DEV';
-- All four must exist
```

#### Step 2.2: Governance Framework

```sql
-- Run: sql/07_governance.sql
-- Creates: masking policies, tags, row access policies
```

**Verify:**
```sql
SHOW MASKING POLICIES IN DATABASE GOVERNANCE;
-- Expected: 7 policies (MASK_NAME, MASK_SSN, MASK_DOB, MASK_EMAIL, MASK_PHONE, MASK_ADDRESS, MASK_FINANCIAL)

SHOW TAGS IN DATABASE GOVERNANCE;
-- Expected: HIPAA_CATEGORY, PII_TYPE, DATA_CLASSIFICATION (+ others)
```

#### Step 2.3: Raw Layer + Data Load

```sql
-- Run: sql/03_raw_layer.sql
-- Creates: raw schemas and tables for FHIR, WORKDAY_HCM, PAYER

-- Run: sql/04_load_data.sql (or load manually):
```

**Upload CSVs to stage:**
```sql
PUT file:///path/to/demos/hcls/data/*.csv @RAW_DEV.STAGING.DATA_STAGE/hcls/ AUTO_COMPRESS=TRUE;
```

**Load data:**
```sql
CALL RAW_DEV.STAGING.LOAD_SOURCE_SYSTEM('FHIR', 'CSV');
CALL RAW_DEV.STAGING.LOAD_SOURCE_SYSTEM('WORKDAY_HCM', 'CSV');
CALL RAW_DEV.STAGING.LOAD_SOURCE_SYSTEM('PAYER', 'CSV');
```

**Verify:**
```sql
SELECT 'PATIENTS' AS TBL, COUNT(*) AS ROWS FROM RAW_DEV.FHIR.PATIENTS
UNION ALL SELECT 'ENCOUNTERS', COUNT(*) FROM RAW_DEV.FHIR.ENCOUNTERS
UNION ALL SELECT 'WORKERS', COUNT(*) FROM RAW_DEV.WORKDAY_HCM.WORKERS
UNION ALL SELECT 'SHIFTS', COUNT(*) FROM RAW_DEV.WORKDAY_HCM.SHIFTS
UNION ALL SELECT 'CLAIMS_DETAIL', COUNT(*) FROM RAW_DEV.PAYER.CLAIMS_DETAIL;
-- All should return non-zero counts
```

#### Step 2.4: Curated Layer

```sql
-- Run: sql/05_curated_layer.sql
-- Creates: Dynamic Tables for cross-system transformations
```

**Verify:**
```sql
SHOW DYNAMIC TABLES IN DATABASE CURATED_DEV;
-- All should show SCHEDULING_STATE = 'ACTIVE'
```

#### Step 2.5: Semantic Layer + Contracts

```sql
-- Run: sql/06_semantic_layer.sql
-- Run: sql/08_contracts.sql
```

#### Step 2.6: Ontology Graph Foundation (Core Scripts 11–15)

```sql
-- Run: sql/11_rai_setup.sql
-- Run: sql/12_ontology_graph_tables.sql
-- Run: sql/13_ontology_graph_populate.sql
-- Run: sql/14_rai_graph_sync.sql
-- Run: sql/15_ontology_sharing.sql
```

**Verify:**
```sql
SELECT node_type, COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES GROUP BY 1 ORDER BY 2 DESC;
SELECT edge_type, COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES GROUP BY 1 ORDER BY 2 DESC;
-- Both should return rows
```

---

### Phase 3: HCLS Graph Extensions

> **Connect to:** SNOW_BCDR_PRIMARY (OAB74379)

Run the seven HCLS-specific SQL scripts in order.

```sql
-- 1. Clinical knowledge graph (FHIR entities + edges)
-- Run: demos/hcls/sql/01_hcls_graph_populate.sql

-- 2. Intentional HIPAA governance gaps (for demo purposes)
-- Run: demos/hcls/sql/02_hcls_hipaa_gaps.sql

-- 3. Inference rules (care pathways, entity resolution, compliance scoring)
-- Run: demos/hcls/sql/03_hcls_rai_inference.sql

-- 4. Workday HCM graph population (workers, departments, cross-system linkage)
-- Run: demos/hcls/sql/04_hcls_workday_populate.sql

-- 5. Staffing-outcomes correlation analysis (Pearson, Fisher z-transform)
-- Run: demos/hcls/sql/05_hcls_staffing_outcomes.sql

-- 6. Comorbidity indexing + payer response analytics (CCI, denial patterns)
-- Run: demos/hcls/sql/06_hcls_comorbidity_payer.sql

-- 7. Master orchestrator (registers all pipelines in dependency order)
-- Run: demos/hcls/sql/07_hcls_run_all.sql
```

#### Run the Master Orchestrator

```sql
-- Full pipeline (15 steps, all three domains)
CALL DCA_DEMO.GOVERNANCE.SP_HCLS_MASTER_ORCHESTRATOR();

-- Quick refresh (7 steps, skip heavy recomputation) — use for subsequent runs
CALL DCA_DEMO.GOVERNANCE.SP_HCLS_QUICK_REFRESH();
```

**Verify — all analytics tables must have data:**
```sql
SELECT 'ONTOLOGY_GRAPH_NODES' AS OBJECT_NAME, COUNT(*) AS ROW_COUNT
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
WHERE SOURCE_SYSTEM IN ('FHIR', 'WORKDAY_HCM', 'PAYER')
UNION ALL SELECT 'ONTOLOGY_GRAPH_EDGES', COUNT(*)
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
WHERE EDGE_ID LIKE 'HCLS_%' OR EDGE_ID LIKE 'WD_%' OR EDGE_ID LIKE 'STAFF_%' OR EDGE_ID LIKE 'PYR_%'
UNION ALL SELECT 'HCLS_STAFFING_CONTEXT', COUNT(*)
FROM DCA_DEMO.GOVERNANCE.HCLS_STAFFING_CONTEXT
UNION ALL SELECT 'HCLS_CORRELATION_RESULTS', COUNT(*)
FROM DCA_DEMO.GOVERNANCE.HCLS_CORRELATION_RESULTS
UNION ALL SELECT 'HCLS_PATIENT_COMORBIDITY', COUNT(*)
FROM DCA_DEMO.GOVERNANCE.HCLS_PATIENT_COMORBIDITY
UNION ALL SELECT 'HCLS_COMORBIDITY_PAIRS', COUNT(*)
FROM DCA_DEMO.GOVERNANCE.HCLS_COMORBIDITY_PAIRS
UNION ALL SELECT 'HCLS_PAYER_METRICS', COUNT(*)
FROM DCA_DEMO.GOVERNANCE.HCLS_PAYER_METRICS
UNION ALL SELECT 'HCLS_CARE_GAPS', COUNT(*)
FROM DCA_DEMO.GOVERNANCE.HCLS_CARE_GAPS
UNION ALL SELECT 'HCLS_STAFFING_OUTCOME_METRICS', COUNT(*)
FROM DCA_DEMO.GOVERNANCE.HCLS_STAFFING_OUTCOME_METRICS;
-- All rows should show ROW_COUNT > 0
```

---

### Phase 4: Security Hardening

> **Connect to:** SNOW_BCDR_PRIMARY (OAB74379)

Run `demos/hcls/sql/09_hcls_network_hardening.sql` — but **read it carefully first** and replace placeholder CIDRs with the customer's actual IP ranges.

#### Step 4.1: Replace Placeholder CIDRs

In `09_hcls_network_hardening.sql`, find the `HCLS_CORPORATE_ACCESS` network rule and replace the placeholder CIDRs:

```sql
-- BEFORE (placeholder):
VALUE_LIST = ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16')

-- AFTER (example — use customer's actual ranges):
VALUE_LIST = ('203.0.113.0/24', '198.51.100.0/24')
```

#### Step 4.2: Deploy Network Security (Parts 1–5)

Run the script. It creates:
- `HCLS_CORPORATE_ACCESS` — ingress network rule (CIDR allowlist)
- `HCLS_SNOWFLAKE_INTERNAL` — egress rule for Snowflake services
- `HCLS_RESTRICTED_ACCESS` — network policy combining the rules
- `HCLS_SESSION_POLICY` — 30-min idle timeout, 15-min UI timeout
- `HCLS_SPCS_EGRESS` — container egress isolation
- Account parameter: `PREVENT_UNLOAD_TO_INLINE_URL = TRUE`

#### Step 4.3: Test Network Policy (DO NOT SKIP)

```sql
-- Apply to a test user first:
ALTER USER <YOUR_TEST_USER> SET NETWORK_POLICY = 'HCLS_RESTRICTED_ACCESS';

-- Test: login from an allowed IP (should succeed)
-- Test: login from an unauthorized IP (should fail)

-- Only after both tests pass, apply account-wide:
ALTER ACCOUNT SET NETWORK_POLICY = 'HCLS_RESTRICTED_ACCESS';
```

> **LOCKOUT RECOVERY:** If locked out, contact Snowflake Support or use an exempt service account:
> ```sql
> ALTER ACCOUNT UNSET NETWORK_POLICY;
> ```

#### Step 4.4: Apply Session Policy

```sql
-- Test on admin user first:
ALTER USER <ADMIN_USER> SET SESSION_POLICY = 'DCA_DEMO.GOVERNANCE.HCLS_SESSION_POLICY';

-- After confirming it works correctly, apply account-wide:
ALTER ACCOUNT SET SESSION_POLICY = 'DCA_DEMO.GOVERNANCE.HCLS_SESSION_POLICY';
```

**Verify:**
```sql
SHOW NETWORK POLICIES;
-- Expected: HCLS_RESTRICTED_ACCESS

SHOW NETWORK RULES IN DATABASE DCA_DEMO;
-- Expected: HCLS_CORPORATE_ACCESS, HCLS_SNOWFLAKE_INTERNAL, HCLS_SPCS_EGRESS

SHOW SESSION POLICIES IN DATABASE DCA_DEMO;
-- Expected: HCLS_SESSION_POLICY

SHOW PARAMETERS LIKE 'NETWORK_POLICY' IN ACCOUNT;
-- Expected: HCLS_RESTRICTED_ACCESS (if applied account-wide)
```

---

### Phase 5: BC/DR Setup

This phase requires **both accounts**. Follow the connection switches carefully.

#### Step 5.1: Primary — Pre-flight + Failover Group (Parts 1–4)

> **Connect to:** SNOW_BCDR_PRIMARY (OAB74379)

```sql
-- Run: sql/02_bcdr.sql Parts 1–4
-- Creates:
--   - Git Repository in GOVERNANCE.LINEAGE
--   - DCA_BCDR_DB_FG failover group (GOVERNANCE, RAW_DEV, CURATED_DEV, SEM_DEV)
--   - DCA_DEMO_CONNECTION client-redirect connection
--   - Replication schedule: 10 minutes
```

**Verify on primary:**
```sql
SHOW FAILOVER GROUPS LIKE 'DCA_BCDR_DB_FG';
-- Should show OBJECT_TYPES = DATABASES, REPLICATION_SCHEDULE = '10 MINUTE'

SHOW CONNECTIONS LIKE 'DCA_DEMO_CONNECTION';
-- Should show the connection with failover enabled
```

#### Step 5.2: Secondary — Replica Setup (Parts 5–8)

> **Connect to:** SNOW_BCDR_SECONDARY (OZC55031)

```sql
-- Run: sql/02_bcdr.sql Parts 5–8
-- Creates:
--   - GIT_API integration on secondary
--   - DCA_BCDR_DB_FG replica failover group
--   - DCA_DEMO_CONNECTION replica
--   - Initial replication refresh (may take 5–15 minutes)
--   - BCDR_DEMO database with Streamlit warm standby
```

**Verify on secondary:**
```sql
-- Confirm correct account
SELECT CURRENT_ACCOUNT() AS ACCOUNT, CURRENT_REGION() AS REGION;
-- Expected: OZC55031, AWS_US_EAST_1

-- Verify failover group replica
SHOW FAILOVER GROUPS LIKE 'DCA_BCDR_DB_FG';
-- secondary_state should show STARTED

-- Verify databases are visible as replicas
SHOW DATABASES LIKE 'GOVERNANCE';
SHOW DATABASES LIKE 'RAW_DEV';
SHOW DATABASES LIKE 'CURATED_DEV';
SHOW DATABASES LIKE 'SEM_DEV';
```

#### Step 5.3: HCLS BC/DR Validation

> **Connect to:** SNOW_BCDR_PRIMARY first, then SNOW_BCDR_SECONDARY

```sql
-- Run: demos/hcls/sql/08_hcls_bcdr_deploy.sql
-- Parts 1-4 on PRIMARY, Parts 5-7 on SECONDARY
-- Validates:
--   - Business Critical edition and security parameters
--   - All HCLS governance objects present on primary
--   - Masking policies, tags, and row access policies
--   - Data completeness baselines (primary vs secondary)
--   - Replication lag against 15-minute RPO target
--   - Streamlit and Signal Graph dependencies on secondary
```

**Verify replication lag:**
```sql
-- Run on PRIMARY:
SELECT
    REPLICATION_GROUP_NAME,
    MAX(END_TIME) AS LAST_SUCCESSFUL_REFRESH,
    DATEDIFF('minute', MAX(END_TIME), CURRENT_TIMESTAMP()) AS LAG_MINUTES,
    IFF(DATEDIFF('minute', MAX(END_TIME), CURRENT_TIMESTAMP()) > 15,
        '*** ALERT: Replication lag exceeds 15-minute RPO target ***',
        'OK: Replication within RPO target') AS RPO_STATUS
FROM SNOWFLAKE.ACCOUNT_USAGE.REPLICATION_GROUP_REFRESH_HISTORY
WHERE REPLICATION_GROUP_NAME = 'DCA_BCDR_DB_FG'
  AND PHASE_NAME = 'COMPLETED'
GROUP BY REPLICATION_GROUP_NAME;
-- LAG_MINUTES should be < 15
```

**Verify governance replication on secondary:**
```sql
-- Run on SECONDARY:
SELECT POLICY_NAME, POLICY_KIND
FROM GOVERNANCE.INFORMATION_SCHEMA.MASKING_POLICIES
ORDER BY POLICY_NAME;
-- Should match primary (7 masking policies)

SHOW TAGS IN DATABASE GOVERNANCE;
-- Tags should be replicated
```

---

### Phase 6: Streamlit Deployment

> **Connect to:** SNOW_BCDR_PRIMARY (OAB74379)

```sql
-- Run: sql/09_streamlit.sql
-- Deploys the Streamlit app with all pages including the Signal Graph
```

**Verify:**
```sql
SHOW STREAMLITS IN DATABASE SEM_DEV;
-- Should show the Streamlit app

-- Open the Streamlit URL in a browser
-- Navigate to Page 7 (Ontological Signal Graph)
-- Verify it renders with HCLS data from all three source systems
```

**Warm standby on secondary** is created automatically by `sql/02_bcdr.sql` Part 8.

---

## Post-Deployment Verification Checklist

Run these SQL queries and confirm each check passes.

- [ ] **Governance nodes populated:**
  ```sql
  SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES;
  -- Expected: > 100,000
  ```

- [ ] **Governance edges populated:**
  ```sql
  SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES;
  -- Expected: > 50,000
  ```

- [ ] **Three source systems represented:**
  ```sql
  SELECT SOURCE_SYSTEM, COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES GROUP BY 1;
  -- Expected: FHIR, WORKDAY_HCM, PAYER — all with non-zero counts
  ```

- [ ] **Staffing-outcomes correlations computed:**
  ```sql
  SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.HCLS_CORRELATION_RESULTS;
  -- Expected: > 0
  ```

- [ ] **Comorbidity analysis populated:**
  ```sql
  SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.HCLS_PATIENT_COMORBIDITY;
  -- Expected: > 0
  ```

- [ ] **Payer metrics computed:**
  ```sql
  SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.HCLS_PAYER_METRICS;
  -- Expected: > 0
  ```

- [ ] **Comorbidity pairs identified:**
  ```sql
  SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.HCLS_COMORBIDITY_PAIRS;
  -- Expected: > 0
  ```

- [ ] **Care gaps detected:**
  ```sql
  SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.HCLS_CARE_GAPS;
  -- Expected: > 0
  ```

- [ ] **Failover group active:**
  ```sql
  SHOW FAILOVER GROUPS LIKE 'DCA_BCDR_DB_FG';
  -- Should show STARTED status
  ```

- [ ] **Replication lag within target:**
  ```sql
  SELECT DATEDIFF('minute', MAX(END_TIME), CURRENT_TIMESTAMP()) AS LAG_MINUTES
  FROM SNOWFLAKE.ACCOUNT_USAGE.REPLICATION_GROUP_REFRESH_HISTORY
  WHERE REPLICATION_GROUP_NAME = 'DCA_BCDR_DB_FG' AND PHASE_NAME = 'COMPLETED';
  -- Expected: < 15
  ```

- [ ] **Network policy active:**
  ```sql
  SHOW PARAMETERS LIKE 'NETWORK_POLICY' IN ACCOUNT;
  -- Expected: HCLS_RESTRICTED_ACCESS
  ```

- [ ] **Session policy active:**
  ```sql
  SHOW SESSION POLICIES IN DATABASE DCA_DEMO;
  -- Expected: HCLS_SESSION_POLICY
  ```

- [ ] **Streamlit app accessible:**
  ```sql
  SHOW STREAMLITS IN DATABASE SEM_DEV;
  -- Open the URL and confirm Signal Graph page renders
  ```

- [ ] **Business Critical verified:**
  ```sql
  SELECT SYSTEM$IS_APPLICATION_ROLE_ENABLED('SNOWFLAKE.SECURITY') AS BC_FEATURES;
  -- Expected: TRUE
  ```

- [ ] **Periodic data rekeying active:**
  ```sql
  SHOW PARAMETERS LIKE 'PERIODIC_DATA_REKEYING' IN ACCOUNT;
  -- Expected: TRUE (auto-enabled on Business Critical)
  ```

- [ ] **All 8 demo queries from DEMO_SCRIPT.md return results** (run each manually)

---

## Failover Drill Procedure

Execute monthly and document results for CMS Conditions of Participation compliance.

### Pre-Failover (Run on PRIMARY)

**Step 1:** Record pre-failover governance state.
```sql
SELECT COUNT(*) AS PRE_NODES FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES;
SELECT COUNT(*) AS PRE_EDGES FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES;
SELECT MAX(CREATED_AT) AS LAST_SNAPSHOT FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SNAPSHOTS;
-- Record these values for post-failover RPO verification
```

**Step 2:** Record current replication lag.
```sql
SELECT MAX(END_TIME) AS LAST_REFRESH
FROM SNOWFLAKE.ACCOUNT_USAGE.REPLICATION_GROUP_REFRESH_HISTORY
WHERE REPLICATION_GROUP_NAME = 'DCA_BCDR_DB_FG'
  AND PHASE_NAME = 'COMPLETED';
-- Record this timestamp
```

### Failover Execution (Run on SECONDARY)

**Step 3:** Promote secondary to primary (target: < 2 minutes).
```sql
ALTER FAILOVER GROUP DCA_BCDR_DB_FG PRIMARY;
```

**Step 4:** Promote client-redirect connection.
```sql
ALTER CONNECTION DCA_DEMO_CONNECTION PRIMARY;
```

### Post-Failover Validation (Run on SECONDARY — now primary)

**Step 5:** Verify Streamlit app is accessible (target: < 1 minute).
```sql
SHOW STREAMLITS IN SCHEMA BCDR_DEMO.STREAMLIT;
-- Open the Streamlit URL in a browser to confirm
```

**Step 6:** Run quick refresh to verify pipeline functionality (target: < 10 minutes).
```sql
CALL DCA_DEMO.GOVERNANCE.SP_HCLS_QUICK_REFRESH();
```

**Step 7:** Compare governance counts with pre-failover baseline.
```sql
SELECT COUNT(*) AS POST_NODES FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES;
SELECT COUNT(*) AS POST_EDGES FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES;
-- POST_NODES should match PRE_NODES from Step 1 (RPO verification)
-- POST_EDGES should match PRE_EDGES from Step 1
```

**Step 8:** Calculate actual RPO and RTO achieved.
```
RPO = CURRENT_TIMESTAMP() - LAST_REFRESH (from Step 2)
  Target: < 10 minutes

RTO = Time from Step 3 start to Step 5 completion
  Target: < 5 minutes for application availability
```

### Failback (After Primary is Recovered)

**Step 9:** On the recovered original primary:
```sql
CREATE FAILOVER GROUP IF NOT EXISTS DCA_BCDR_DB_FG
    AS REPLICA OF SFSENORTHAMERICA.SNOW_BCDR_SECONDARY.DCA_BCDR_DB_FG;
-- Wait for initial replication to complete
```

**Step 10:** On current primary (original secondary):
```sql
ALTER FAILOVER GROUP DCA_BCDR_DB_FG
    ALLOWED_ACCOUNTS = SFSENORTHAMERICA.SNOW_BCDR_PRIMARY;
```

**Step 11:** On original primary — promote back:
```sql
ALTER FAILOVER GROUP DCA_BCDR_DB_FG PRIMARY;
ALTER CONNECTION DCA_DEMO_CONNECTION PRIMARY;
```

**Step 12:** Document drill results — record date, RPO achieved, RTO achieved, issues encountered.

---

## Troubleshooting Guide

| Symptom | Likely Cause | Resolution |
|---|---|---|
| Replication not starting | Org-level replication not enabled | Contact Snowflake support to enable ORGADMIN replication |
| `DCA_BCDR_DB_FG` not visible on secondary | Part 3 not completed on primary | Return to primary, run `SHOW FAILOVER GROUPS LIKE 'DCA_BCDR_DB_FG'` and verify |
| Network policy lockout | Policy applied before testing from current IP | Connect via SnowSQL with exempt user and run `ALTER ACCOUNT UNSET NETWORK_POLICY` |
| Session timeout too aggressive | Session policy applied account-wide | `ALTER ACCOUNT UNSET SESSION_POLICY` to remove, adjust timeouts, reapply |
| Streamlit 404 on secondary | Stage not replicated yet | Wait for next replication cycle (10 min), then check `SHOW STREAMLITS` |
| `SP_HCLS_MASTER_ORCHESTRATOR` fails | Missing prerequisite tables | Run scripts in order (Phase 2 then Phase 3). Check which SP step fails in snapshot table |
| Signal Graph page blank | No data in `ONTOLOGY_GRAPH_NODES` | Run `CALL SP_HCLS_QUICK_REFRESH()` to repopulate |
| Failover group shows ERROR | Database has active streams/tasks | Pause streams and tasks before failover: `ALTER TASK ... SUSPEND` |
| `COPY INTO` fails during data load | Stage path incorrect or files not uploaded | Verify PUT completed: `LIST @RAW_DEV.STAGING.DATA_STAGE/hcls/` |
| Dynamic Tables stuck in SUSPENDED | Upstream table missing or schema changed | Check `SHOW DYNAMIC TABLES` for error messages, run prerequisite scripts |
| Replication lag > 15 minutes | Large data changes or network issues | Check `REPLICATION_GROUP_REFRESH_HISTORY` for errors, verify network connectivity |
| Git repository fetch fails | GIT_API integration missing or URL wrong | `SHOW API INTEGRATIONS LIKE 'GIT_API'` — recreate if missing |
| `PREVENT_UNLOAD_TO_INLINE_URL` blocking legitimate exports | Account parameter set too broadly | Create a storage integration for approved export destinations |

---

## RPO/RTO Targets

| Metric | Target | How to Measure |
|---|---|---|
| **RPO** (Recovery Point Objective) | 10 minutes | Max data loss = 1 replication cycle |
| **RTO** (Recovery Time Objective) | 5 minutes | Time from failover command to application availability |
| **Failover drill frequency** | Monthly | Document results in `ONTOLOGY_GRAPH_SNAPSHOTS` with `snapshot_type = 'BCDR_DRILL'` |
| **Replication monitoring** | Continuous | Alert if lag > 15 minutes |
| **Failback time** | < 30 minutes | Time to return to original primary after recovery |

---

## Security Configuration Reference

Quick reference for all security objects deployed by this runbook.

### Network Security

| Object | Type | Purpose |
|---|---|---|
| `HCLS_CORPORATE_ACCESS` | Network Rule (ingress) | Corporate CIDR allowlist — replace placeholders with customer IPs |
| `HCLS_SNOWFLAKE_INTERNAL` | Network Rule (egress) | Required egress for Snowflake services and SPCS |
| `HCLS_SPCS_EGRESS` | Network Rule (egress) | Container isolation — SPCS restricted to Snowflake internal only |
| `HCLS_RESTRICTED_ACCESS` | Network Policy | Combines rules — only authorized corporate networks allowed |

### Session Security

| Object | Setting | HIPAA Reference |
|---|---|---|
| `HCLS_SESSION_POLICY` | 30-min idle timeout | §164.312(a)(2)(iii) — Automatic Logoff |
| `HCLS_SESSION_POLICY` | 15-min UI timeout | Snowsight/Streamlit inactivity |

### Data Protection

| Control | Setting | Notes |
|---|---|---|
| Masking policies | 7 policies | Name, email, phone, address, SSN, DOB, financial |
| Row access policies | Geographic/department filtering | Restricts row visibility by role |
| Tags | HIPAA_CATEGORY, PII_TYPE, DATA_CLASSIFICATION | Applied to all PHI columns |
| `PREVENT_UNLOAD_TO_INLINE_URL` | TRUE | Blocks uncontrolled data exports |
| Encryption | AES-256 at rest | Periodic rekeying auto-enabled on Business Critical |
| Replication | 10-minute schedule, cross-region | GOVERNANCE, RAW_DEV, CURATED_DEV, SEM_DEV |

### PrivateLink (Optional — Customer Dependent)

If the customer requires PrivateLink, follow the template in `demos/hcls/sql/09_hcls_network_hardening.sql` Part 6. Steps:
1. Customer creates VPC Endpoint targeting Snowflake's PrivateLink service
2. Snowflake authorizes via `SYSTEM$AUTHORIZE_PRIVATELINK()`
3. Customer configures DNS for `*.privatelink.snowflakecomputing.com`
4. After testing, block all public access with a PrivateLink-only network policy

---

## Script Execution Order — Complete Reference

| Order | Script | Phase | Connection |
|---|---|---|---|
| 1 | `sql/01_setup.sql` | Foundation | PRIMARY |
| 2 | `sql/07_governance.sql` | Foundation | PRIMARY |
| 3 | `sql/03_raw_layer.sql` | Foundation | PRIMARY |
| 4 | `sql/04_load_data.sql` + PUT/COPY | Data Load | PRIMARY |
| 5 | `sql/05_curated_layer.sql` | Foundation | PRIMARY |
| 6 | `sql/06_semantic_layer.sql` | Foundation | PRIMARY |
| 7 | `sql/08_contracts.sql` | Foundation | PRIMARY |
| 8 | `sql/11_rai_setup.sql` | Ontology | PRIMARY |
| 9 | `sql/12_ontology_graph_tables.sql` | Ontology | PRIMARY |
| 10 | `sql/13_ontology_graph_populate.sql` | Ontology | PRIMARY |
| 11 | `sql/14_rai_graph_sync.sql` | Ontology | PRIMARY |
| 12 | `sql/15_ontology_sharing.sql` | Ontology | PRIMARY |
| 13 | `demos/hcls/sql/01_hcls_graph_populate.sql` | HCLS | PRIMARY |
| 14 | `demos/hcls/sql/02_hcls_hipaa_gaps.sql` | HCLS | PRIMARY |
| 15 | `demos/hcls/sql/03_hcls_rai_inference.sql` | HCLS | PRIMARY |
| 16 | `demos/hcls/sql/04_hcls_workday_populate.sql` | HCLS | PRIMARY |
| 17 | `demos/hcls/sql/05_hcls_staffing_outcomes.sql` | HCLS | PRIMARY |
| 18 | `demos/hcls/sql/06_hcls_comorbidity_payer.sql` | HCLS | PRIMARY |
| 19 | `demos/hcls/sql/07_hcls_run_all.sql` | HCLS | PRIMARY |
| 20 | `CALL SP_HCLS_MASTER_ORCHESTRATOR()` | HCLS | PRIMARY |
| 21 | `demos/hcls/sql/09_hcls_network_hardening.sql` | Security | PRIMARY |
| 22 | `sql/02_bcdr.sql` Parts 1–4 | BC/DR | PRIMARY |
| 23 | `sql/02_bcdr.sql` Parts 5–8 | BC/DR | SECONDARY |
| 24 | `demos/hcls/sql/08_hcls_bcdr_deploy.sql` Parts 1–4 | Validation | PRIMARY |
| 25 | `demos/hcls/sql/08_hcls_bcdr_deploy.sql` Parts 5–7 | Validation | SECONDARY |
| 26 | `sql/09_streamlit.sql` | Streamlit | PRIMARY |

---

## Monitoring Queries (Ongoing Operations)

Run these regularly or configure as Snowflake Alerts.

**Failed logins (potential brute force):**
```sql
SELECT USER_NAME, CLIENT_IP, ERROR_CODE, ERROR_MESSAGE, EVENT_TIMESTAMP
FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
WHERE IS_SUCCESS = 'NO'
  AND EVENT_TIMESTAMP > DATEADD('hour', -24, CURRENT_TIMESTAMP())
ORDER BY EVENT_TIMESTAMP DESC
LIMIT 50;
```

**Logins from unexpected IPs:**
```sql
SELECT USER_NAME, CLIENT_IP, REPORTED_CLIENT_TYPE, EVENT_TIMESTAMP
FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
WHERE IS_SUCCESS = 'YES'
  AND CLIENT_IP NOT LIKE '10.%'
  AND CLIENT_IP NOT LIKE '172.16.%'
  AND CLIENT_IP NOT LIKE '192.168.%'
  AND EVENT_TIMESTAMP > DATEADD('hour', -24, CURRENT_TIMESTAMP())
ORDER BY EVENT_TIMESTAMP DESC
LIMIT 50;
```

**Users without MFA:**
```sql
SELECT NAME AS USER_NAME, LOGIN_NAME, HAS_MFA, LAST_SUCCESS_LOGIN
FROM SNOWFLAKE.ACCOUNT_USAGE.USERS
WHERE DELETED_ON IS NULL AND HAS_MFA = 'false'
ORDER BY LAST_SUCCESS_LOGIN DESC;
```

**Large data exports (potential exfiltration):**
```sql
SELECT USER_NAME, QUERY_TEXT, ROWS_PRODUCED, BYTES_SCANNED, START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE QUERY_TYPE = 'UNLOAD'
  AND START_TIME > DATEADD('hour', -24, CURRENT_TIMESTAMP())
ORDER BY BYTES_SCANNED DESC
LIMIT 20;
```

**Replication health:**
```sql
SELECT
    REPLICATION_GROUP_NAME,
    MAX(END_TIME) AS LAST_REFRESH,
    DATEDIFF('minute', MAX(END_TIME), CURRENT_TIMESTAMP()) AS LAG_MINUTES
FROM SNOWFLAKE.ACCOUNT_USAGE.REPLICATION_GROUP_REFRESH_HISTORY
WHERE REPLICATION_GROUP_NAME = 'DCA_BCDR_DB_FG'
  AND PHASE_NAME = 'COMPLETED'
GROUP BY REPLICATION_GROUP_NAME;
```
