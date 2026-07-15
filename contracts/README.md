# Data Contracts on Snowflake Horizon

A Horizon-native **data contract enforcement layer** for the DCA full-stack demo. It composes Snowflake's built-in governance primitives — **Data Metric Functions, object tags, `ACCOUNT_USAGE` lineage, and Alerts** — into enforceable contracts covering **schema, quality, SLA, and lineage**, with **BLOCK / ALERT / MONITOR** gates.

> **Why this exists.** Horizon does not ship a single object called a "data contract." Instead it gives you the primitives that enforce what a contract *promises*. This folder is the registry + orchestration that binds those primitives together and decides **BLOCK vs ALERT** on breach. It is a richer, Horizon-grounded successor to the basic `sql/08_contracts.sql`.

---

## The mental model

```
CONTRACT (intent + agreement)  ──drives──▶  HORIZON PRIMITIVES (enforcement + evidence)
  CONTRACT / CONTRACT_BINDING                  Data Metric Functions
  QUALITY_RULE / SLA_RULE                      Object Tags + TAG_REFERENCES
  LINEAGE_ASSERTION                            OBJECT_DEPENDENCIES / ACCESS_HISTORY
  SCHEMA_FINGERPRINT                           INFORMATION_SCHEMA + Horizon Context
                                               Alerts + Serverless Tasks
```

The registry stores **what** was promised and by whom; Horizon provides the **how it's enforced and proven**.

### How each contract dimension maps to Horizon

| Dimension | Declared in (registry) | Enforced / evidenced by (Horizon) | Script |
|-----------|------------------------|-----------------------------------|--------|
| **Schema** | `SCHEMA_FINGERPRINT`, `TAG_SCHEMA_STABILITY` | `INFORMATION_SCHEMA.COLUMNS` diff, tags, projection policies | `03` |
| **Quality** | `QUALITY_RULE` | System + custom **Data Metric Functions** → `SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS` | `02`, `04` |
| **SLA** | `SLA_RULE` | `FRESHNESS` / `ROW_COUNT` DMFs, Dynamic Table refresh, **Alerts** | `05` |
| **Lineage** | `LINEAGE_ASSERTION` | `OBJECT_DEPENDENCIES`, `ACCESS_HISTORY`, **Horizon Context** cross-platform lineage | `06` |
| **Enforcement** | `ENFORCEMENT_MODE` (`BLOCK`/`ALERT`/`MONITOR`) | validation gate proc (throws on BLOCK) + Alerts + Task | `07` |

**The honest 80/20:** Horizon natively gives you *monitoring, evidence, and access enforcement* (DMFs, lineage views, policies, Trust Center). The remaining 20% — hard **DDL-time gating** and the **producer↔consumer agreement metadata** — is not a native object, which is exactly what this registry + `VALIDATE_CONTRACT` gate provides.

---

## Folder layout

```
contracts/
├── README.md                        ← you are here
├── deploy.sh                        ← one-shot deploy (snow CLI)
├── sql/
│   ├── 00_setup.sql                 ← schema + contract-binding TAGS + grants
│   ├── 01_registry.sql              ← 9 registry tables (intent + evidence)
│   ├── 02_dmf_library.sql           ← 5 custom DMFs + ATTACH_DMF helper
│   ├── 03_schema_contracts.sql      ← CAPTURE_SCHEMA_FINGERPRINT + DETECT_SCHEMA_DRIFT
│   ├── 04_quality_contracts.sql     ← APPLY_QUALITY_RULES + EVALUATE_QUALITY
│   ├── 05_sla_contracts.sql         ← EVALUATE_SLA + ALERT_SLA_BREACH
│   ├── 06_lineage_contracts.sql     ← EVALUATE_LINEAGE (deps + access + Horizon Context)
│   ├── 07_enforcement.sql           ← VALIDATE_CONTRACT gate + ENFORCE_PIPELINE_GATE + TASK
│   ├── 08_seed_demo_contracts.sql   ← 3 end-to-end demo contracts
│   └── 09_views_dashboard.sql       ← 5 dashboard views
└── streamlit/
    └── contracts_page.py            ← drop-in SiS page (4 tabs)
```

---

## What gets created

**Schema:** `GOVERNANCE.DATA_CONTRACTS`

**Tables (9):** `CONTRACT`, `CONTRACT_BINDING`, `SCHEMA_FINGERPRINT`, `QUALITY_RULE`, `SLA_RULE`, `LINEAGE_ASSERTION`, `VALIDATION_RUN`, `VALIDATION_RESULT`, `BREACH_LOG`

**Tags (4):** `TAG_CONTRACT_ID`, `TAG_CONTRACT_VERSION`, `TAG_SCHEMA_STABILITY`, `TAG_CONTRACT_ENFORCEMENT`

**Custom DMFs (5):** `DMF_NEGATIVE_AMOUNT_COUNT`, `DMF_FUTURE_DATE_COUNT`, `DMF_INVALID_EMAIL_COUNT`, `DMF_ORPHAN_KEY_COUNT`, `DMF_SCD2_INTEGRITY_COUNT`

**Procedures:** `ATTACH_DMF`, `CAPTURE_SCHEMA_FINGERPRINT`, `DETECT_SCHEMA_DRIFT`, `APPLY_QUALITY_RULES`, `EVALUATE_QUALITY`, `EVALUATE_SLA`, `EVALUATE_LINEAGE`, `VALIDATE_CONTRACT`, `ENFORCE_PIPELINE_GATE`, `RUN_ALL_CONTRACTS`

**Alert + Task:** `ALERT_SLA_BREACH`, `TASK_MONITOR_CONTRACTS` (both created **suspended**)

**Views (5):** `V_CONTRACT_HEALTH`, `V_CONTRACT_SCORECARD`, `V_BREACH_FEED`, `V_CONTRACT_COVERAGE`, `V_VALIDATION_TIMELINE`

**Seed contracts (3):**
| Contract | Object | Class | Enforcement |
|----------|--------|-------|-------------|
| `CONTRACT-SALESFORCE-ACCOUNT` | `RAW_DEV.SALESFORCE.ACCOUNT` | CONFIDENTIAL | ALERT |
| `CONTRACT-SAP-FACT-REVENUE` | `CURATED_DEV.SAP.FACT_REVENUE` | CONFIDENTIAL | **BLOCK** |
| `CONTRACT-WORKDAY-WORKERS` | `RAW_DEV.WORKDAY.WORKERS` | RESTRICTED | ALERT |

---

## Prerequisites

1. **Core DCA demo deployed** — `RAW_DEV`, `CURATED_DEV`, and the `DATA_ADMIN` / `DATA_STEWARD` / `DATA_ENGINEER` roles must exist (`sql/01`–`09`).
2. **(Recommended) Horizon Context deployed** — `sql/17_select_star_horizon_context.sql`, which powers the `CROSS_PLATFORM` lineage assertions.
3. **Serverless / ACCOUNT_USAGE grants** (run once as `ACCOUNTADMIN`):

```bash
./deploy.sh --print-grants     # prints the exact GRANT statements
```

```sql
USE ROLE ACCOUNTADMIN;
GRANT EXECUTE DATA METRIC FUNCTION ON ACCOUNT TO ROLE DATA_ADMIN;
GRANT DATABASE ROLE SNOWFLAKE.DATA_METRIC_USER TO ROLE DATA_ADMIN;
GRANT APPLICATION ROLE SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER TO ROLE DATA_ADMIN;
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE DATA_ADMIN;   -- ACCOUNT_USAGE lineage
GRANT EXECUTE TASK ON ACCOUNT TO ROLE DATA_ADMIN;                     -- monitoring task
```

---

## Deploy

```bash
# Full deploy + seed the 3 demo contracts
./contracts/deploy.sh --connection default

# Deploy, seed, and immediately run a validation
./contracts/deploy.sh --connection default --validate

# Deploy schema/logic only (no demo contracts)
./contracts/deploy.sh --connection default --no-seed
```

Or run the SQL manually in order: `00 → 01 → 02 → 03 → 04 → 05 → 06 → 07 → 09`, then `08` to seed.

---

## Run it

```sql
-- Validate a single contract across all four dimensions
CALL GOVERNANCE.DATA_CONTRACTS.VALIDATE_CONTRACT('CONTRACT-SAP-FACT-REVENUE', '_LOADED_AT', 'MANUAL');

-- Use as a pipeline gate (throws → halts the calling task on BLOCK)
CALL GOVERNANCE.DATA_CONTRACTS.ENFORCE_PIPELINE_GATE('CONTRACT-SAP-FACT-REVENUE', '_LOADED_AT');

-- Validate everything (what the monitoring task runs)
CALL GOVERNANCE.DATA_CONTRACTS.RUN_ALL_CONTRACTS();

-- See health + breaches
SELECT * FROM GOVERNANCE.DATA_CONTRACTS.V_CONTRACT_HEALTH;
SELECT * FROM GOVERNANCE.DATA_CONTRACTS.V_BREACH_FEED;

-- Arm always-on monitoring + alerting
ALTER TASK  GOVERNANCE.DATA_CONTRACTS.TASK_MONITOR_CONTRACTS RESUME;
ALTER ALERT GOVERNANCE.DATA_CONTRACTS.ALERT_SLA_BREACH RESUME;
```

### Author a new contract

```sql
-- 1) Register the contract
INSERT INTO GOVERNANCE.DATA_CONTRACTS.CONTRACT
  (CONTRACT_ID, CONTRACT_VERSION, CONTRACT_NAME, STATUS, PRODUCER_TEAM, PRODUCER_EMAIL,
   CONSUMER_CRITICALITY, DATA_CLASSIFICATION, DEFAULT_ENFORCEMENT, SCHEMA_STABILITY, DESCRIPTION)
SELECT 'CONTRACT-ORACLE-GL','1.0.0','Oracle GL Contract','ACTIVE','Finance Ops','finops@co.com',
       'HIGH','CONFIDENTIAL','ALERT','STABLE','GL journal entries from Oracle EBS';

-- 2) Bind it to an object
INSERT INTO GOVERNANCE.DATA_CONTRACTS.CONTRACT_BINDING
  (BINDING_ID, CONTRACT_ID, CONTRACT_VERSION, OBJECT_DATABASE, OBJECT_SCHEMA, OBJECT_NAME, OBJECT_TYPE, DATA_LAYER)
SELECT 'BIND-ORA-GL','CONTRACT-ORACLE-GL','1.0.0','RAW_DEV','ORACLE','GL_JE_HEADERS','TABLE','RAW';

-- 3) Add rules (quality/SLA/lineage) — see 08_seed_demo_contracts.sql for full examples
-- 4) Capture the schema baseline + attach DMFs
CALL GOVERNANCE.DATA_CONTRACTS.CAPTURE_SCHEMA_FINGERPRINT('BIND-ORA-GL');
CALL GOVERNANCE.DATA_CONTRACTS.APPLY_QUALITY_RULES('CONTRACT-ORACLE-GL','TRIGGER_ON_CHANGES');
```

---

## Demo script (5 minutes)

1. **Show coverage** — open the Streamlit page → *Coverage* tab. "Here's what share of the estate is under contract."
2. **Show a healthy contract** — *Contracts* tab → `CONTRACT-SAP-FACT-REVENUE`. Four green dimension chips.
3. **Break quality** — `INSERT INTO CURATED_DEV.SAP.FACT_REVENUE (...) VALUES (net_revenue = -500 ...)` (or point a rule at a column with known nulls).
4. **Break schema** — `ALTER TABLE CURATED_DEV.SAP.FACT_REVENUE DROP COLUMN <required_col>;`
5. **Re-validate** — *Contract Detail* → **Run Validation**. Because this contract is **BLOCK**, `VALIDATE_CONTRACT` throws and writes a `BREACHED/BLOCKED` row + a `BREACH_LOG` entry.
6. **Show the gate** — `CALL ENFORCE_PIPELINE_GATE('CONTRACT-SAP-FACT-REVENUE','_LOADED_AT');` returns `BLOCKED` → "this is what halts the RAW→CURATED promotion task."
7. **Show cross-platform lineage** — the lineage assertion proves the Tableau *Executive Revenue Dashboard* consumes this table (via Horizon Context) → "breaking this column breaks that dashboard; the contract knows."
8. **Contrast ALERT** — repeat on `CONTRACT-SALESFORCE-ACCOUNT` (ALERT mode): breach is logged and alerted but the pipeline proceeds.

---

## Streamlit integration

**Option A — standalone SiS app:** deploy `contracts/streamlit/contracts_page.py` on its own.

**Option B — add a page to the main app** (`streamlit/app.py`):

1. Copy `render_contracts_v2_page()` and its `_q` / `get_*` / `run_validation` helpers into `app.py` (rename to avoid clashing with the existing `render_contracts_page`).
2. Add to the sidebar nav list:
   ```python
   "🔮 Governance", "🌟 Horizon Context", "📜 Data Contracts", "📋 Contracts", "ℹ️ About"
   ```
3. Add routing in `main()`:
   ```python
   elif page == "📜 Data Contracts":
       render_contracts_v2_page()
   ```

The page has 4 tabs: **Contracts** (health list), **Contract Detail** (scorecard + check results + timeline + a live *Run Validation* button), **Breach Ledger**, and **Coverage**.

---

## How this relates to the rest of the repo

| Repo asset | Relationship |
|------------|--------------|
| `sql/08_contracts.sql` | The basic contract registry. This folder is the Horizon-native successor (real DMFs, schema drift, lineage, BLOCK gate). They can coexist — different schemas (`GOVERNANCE.CONTRACTS` vs `GOVERNANCE.DATA_CONTRACTS`). |
| `sql/07_governance.sql` | Masking / RLS / tags — the *access* clause of a contract. |
| `sql/17_select_star_horizon_context.sql` | Powers `CROSS_PLATFORM` lineage assertions (external DB / BI / dbt lineage). |
| `docs/SNOWFLAKE_HORIZON_AND_SELECT_STAR.md` | Conceptual background on Horizon + Horizon Context. |

---

## Notes & limitations

- **DDL gating is soft.** Snowflake does not block `ALTER TABLE` against a contract. Enforcement happens at the *pipeline boundary* via `ENFORCE_PIPELINE_GATE` (BLOCK throws) and continuously via `TASK_MONITOR_CONTRACTS`. For hard DDL prevention, restrict `ALTER`/`DROP` privileges on contracted objects to a change-controlled role.
- **ACCOUNT_USAGE latency.** `OBJECT_DEPENDENCIES` (~3h) and `ACCESS_HISTORY` (~45m) are not real-time. `CROSS_PLATFORM` assertions resolve instantly against Horizon Context tables.
- **DMF scheduling.** DMF results populate `DATA_QUALITY_MONITORING_RESULTS` after the scheduled/triggered run. `EVALUATE_QUALITY` reports `NO_DATA` until the first measurement lands.
- **Column names in seed** (`08`) are illustrative — unmatched DMF attaches are logged and skipped, unmeasured rules report `NO_DATA`, so seeding is always safe. Adjust `TARGET_COLUMN` values to your deployed schema for live results.
