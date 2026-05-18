# Snowflake DR: Failover & Fallback — Data Flow Diagrams & Response

**Prerequisites:** Business Critical Edition (or higher), Failover Groups configured with replication schedules.

---

## Data Flow Diagrams

### Normal Operations — Steady State

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         NORMAL OPERATIONS                                │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────┐          ┌─────────────────────────────┐
│      PRIMARY ACCOUNT        │          │        DR ACCOUNT           │
│         (Read/Write)        │          │       (Read-Only)           │
│                             │          │                             │
│  ┌───────────────────────┐  │   FG     │  ┌───────────────────────┐  │
│  │  Failover Group (FG)  │──┼──────────┼─▶│  Failover Group (FG)  │  │
│  │  ┌─────────────────┐  │  │ Schedule │  │  ┌─────────────────┐  │  │
│  │  │ Databases       │  │  │ (auto)   │  │  │ Databases       │  │  │
│  │  │ Roles/Users     │  │  │          │  │  │ Roles/Users     │  │  │
│  │  │ Warehouses      │  │  │          │  │  │ Warehouses      │  │  │
│  │  │ Tasks (active)  │  │  │          │  │  │ Tasks (dormant) │  │  │
│  │  │ Integrations    │  │  │          │  │  │ Integrations    │  │  │
│  │  └─────────────────┘  │  │          │  │  └─────────────────┘  │  │
│  └───────────────────────┘  │          │  └───────────────────────┘  │
│                             │          │                             │
│  ┌───────────────────────┐  │   NOT    │                             │
│  │  NON-REPLICATED       │  │ ──────▶  │  (These objects DO NOT      │
│  │  • Hybrid Tables      │  │Replicate │   exist on DR)              │
│  │  • External Tables    │  │          │                             │
│  │  • Event Tables       │  │          │                             │
│  │  • Temporary Tables   │  │          │                             │
│  └───────────────────────┘  │          │                             │
└─────────────────────────────┘          └─────────────────────────────┘
```

---

### Failover: Primary → DR

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    FAILOVER EVENT (Primary → DR)                        │
└─────────────────────────────────────────────────────────────────────────┘

  Step 1: ALTER FAILOVER GROUP <fg_name> PRIMARY;  (executed from DR account)

┌─────────────────────────────┐          ┌─────────────────────────────┐
│   FORMER PRIMARY ACCOUNT    │          │     DR ACCOUNT (Promoted)   │
│      (Now Read-Only)        │          │       (Now Read/Write)      │
│                             │          │                             │
│  ┌───────────────────────┐  │          │  ┌───────────────────────┐  │
│  │  Failover Group (FG)  │  │◀ ─ ─ ─ ─ │  │  Failover Group (FG)  │  │
│  │  SECONDARY            │  │ Schedule │  │  PRIMARY              │  │
│  │  (schedule SUSPENDED) │  │SUSPENDED │  │  (active, writable)   │  │
│  │  ┌─────────────────┐  │  │          │  │  ┌─────────────────┐  │  │
│  │  │ Databases (R/O)    │  │          │  │  │ Databases (R/W) │  │  │
│  │  │ Tasks (dormant) │  │  │          │  │  │ Tasks (ACTIVE)  │  │  │
│  │  └─────────────────┘  │  │          │  │  └─────────────────┘  │  │
│  └───────────────────────┘  │          │  └───────────────────────┘  │
│                             │          │                             │
│  ┌───────────────────────┐  │          │  ┌───────────────────────┐  │
│  │  NON-REPLICATED       │  │          │  │  NON-REPLICATED       │  │
│  │  • Hybrid Tables ✓    │  │          │  │  • (DO NOT EXIST)     │  │
│  │  • External Tables ✓  │  │          │  │  • Must recreate      │  │
│  │  (Still intact,       │  │          │  │    manually if needed │  │
│  │   but read-only DB)   │  │          │  │                       │  │
│  └───────────────────────┘  │          │  └───────────────────────┘  │
└─────────────────────────────┘          └─────────────────────────────┘

  Step 2 (MANUAL): ALTER FAILOVER GROUP <fg_name> RESUME;
                   (run from former primary to start replication DR → Primary)
```

---

### Post-Failover: Replication Resumed (DR → Former Primary)

```
┌─────────────────────────────────────────────────────────────────────────┐
│              POST-FAILOVER: Replication Resumed                         │
└─────────────────────────────────────────────────────────────────────────┘

  After manual: ALTER FAILOVER GROUP <fg_name> RESUME;

┌─────────────────────────────┐          ┌─────────────────────────────┐
│   FORMER PRIMARY ACCOUNT    │          │     DR ACCOUNT (Primary)    │
│       (Secondary)           │          │       (Read/Write)          │
│                             │          │                             │
│  ┌───────────────────────┐  │   FG     │  ┌───────────────────────┐  │
│  │  Failover Group (FG)  │◀─┼──────────┼──│  Failover Group (FG)  │  │
│  │  SECONDARY            │  │ Schedule │  │  PRIMARY              │  │
│  │  (schedule RESUMED)   │  │ (active) │  │                       │  │
│  │  ┌─────────────────┐  │  │          │  │  ┌─────────────────┐  │  │
│  │  │ Receiving       │  │  │  ◀─────  │  │  │ Replicating     │  │  │
│  │  │ refreshes from  │  │  │  data    │  │  │ to former       │  │  │
│  │  │ DR              │  │  │  flow    │  │  │ primary         │  │  │
│  │  └─────────────────┘  │  │          │  │  └─────────────────┘  │  │
│  └───────────────────────┘  │          │  └───────────────────────┘  │
└─────────────────────────────┘          └─────────────────────────────┘
```

---

### Fallback: DR → Original Primary

```
┌─────────────────────────────────────────────────────────────────────────┐
│                   FALLBACK EVENT (DR → Original Primary)                │
└─────────────────────────────────────────────────────────────────────────┘

  Step 1: ALTER FAILOVER GROUP <fg_name> SUSPEND;    (on secondary, stop refresh)
  Step 2: Verify no refresh in-progress
  Step 3: ALTER FAILOVER GROUP <fg_name> PRIMARY;    (from original primary account)
  Step 4: ALTER FAILOVER GROUP <fg_name> RESUME;     (from DR, now secondary again)
  Step 5: ALTER CONNECTION <name> PRIMARY;           (redirect clients back)

┌─────────────────────────────┐          ┌─────────────────────────────┐
│   ORIGINAL PRIMARY ACCOUNT  │          │      DR ACCOUNT             │
│     (Re-promoted Primary)   │          │    (Back to Secondary)      │
│       (Read/Write)          │          │      (Read-Only)            │
│                             │          │                             │
│  ┌───────────────────────┐  │   FG     │  ┌───────────────────────┐  │
│  │  Failover Group (FG)  │──┼──────────┼─▶│  Failover Group (FG)  │  │
│  │  PRIMARY              │  │ Schedule │  │  SECONDARY            │  │
│  │  (active, writable)   │  │ (after   │  │  (schedule RESUMED)   │  │
│  │  ┌─────────────────┐  │  │ manual   │  │  ┌─────────────────┐  │  │
│  │  │ Databases (R/W) │  │  │ resume)  │  │  │ Databases (R/O) │  │  │
│  │  │ Tasks (ACTIVE)  │  │  │          │  │  │ Tasks (dormant) │  │  │
│  │  └─────────────────┘  │  │          │  │  └─────────────────┘  │  │
│  └───────────────────────┘  │          │  └───────────────────────┘  │
│                             │          │                             │
│  ┌───────────────────────┐  │          │                             │
│  │  NON-REPLICATED       │  │          │                             │
│  │  • Hybrid Tables ✓    │  │          │                             │
│  │  • External Tables ✓  │  │          │                             │
│  │  (Fully available     │  │          │                             │
│  │   again, writable)    │  │          │                             │
│  └───────────────────────┘  │          │                             │
└─────────────────────────────┘          └─────────────────────────────┘
```

---

### Task Lifecycle During Failover/Fallback

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      TASK STATE TRANSITIONS                             │
└─────────────────────────────────────────────────────────────────────────┘

  NORMAL STATE
  ┌──────────────────────────┐      ┌──────────────────────────┐
  │ PRIMARY: Tasks ACTIVE    │      │ DR: Tasks DORMANT        │
  │ (scheduled, executing)   │      │ (replicated, not running)│
  └──────────────────────────┘      └──────────────────────────┘

            │ FAILOVER EVENT                      │
            ▼                                     ▼

  ┌──────────────────────────┐      ┌──────────────────────────┐
  │ FORMER PRIMARY:          │      │ DR (Promoted):           │
  │ Tasks become DORMANT     │      │Tasks RESUME AUTOMATICALLY│
  │ (stop executing)         │      │ (begin scheduled runs)   │
  └──────────────────────────┘      └──────────────────────────┘

            │ FALLBACK EVENT                      │
            ▼                                     ▼

  ┌──────────────────────────┐      ┌──────────────────────────┐
  │ ORIGINAL PRIMARY:        │      │ DR (Demoted):            │
  │ Tasks RESUME AUTOMATICALLY│     │ Tasks become DORMANT     │
  │ (begin scheduled runs)   │      │ (stop executing)         │
  └──────────────────────────┘      └──────────────────────────┘

  ⚠️  PREREQUISITE: ENABLE_STREAM_TASK_REPLICATION = TRUE
  ⚠️  Tasks referencing streams: both DBs must be in same Failover Group
```

---

### Decision Tree: Discard vs. Keep DR Changes

```
┌─────────────────────────────────────────────────────────────────────────┐
│             DECISION: DISCARD or KEEP DR CHANGES?                       │
└─────────────────────────────────────────────────────────────────────────┘

                    After Failover to DR
                           │
                           ▼
              ┌────────────────────────┐
              │  Did you RESUME        │
              │  replication back to   │
              │  former primary?       │
              └────────────────────────┘
                    │              │
                   YES             NO
                    │              │
                    ▼              ▼
    ┌────────────────────┐  ┌────────────────────────────┐
    │ DR changes ARE     │  │ Former primary retains     │
    │ flowing to former  │  │ pre-failover state.        │
    │ primary.           │  │                            │
    │                    │  │ FALLBACK = clean rollback  │
    │ To discard:        │  │ (DR changes discarded      │
    │ 1. SUSPEND refresh │  │  from primary perspective) │
    │ 2. Time Travel on  │  └────────────────────────────┘
    │    former primary  │
    │    to pre-failover │
    │    state           │
    │ 3. Then failback   │
    └────────────────────┘

  ✅ BEST PRACTICE for DR Drills:
     Do NOT resume replication to former primary → clean fallback guaranteed
```

---

### Replication Schedule State Machine

```
┌─────────────────────────────────────────────────────────────────────────┐
│              REPLICATION SCHEDULE STATE MACHINE                         │
└─────────────────────────────────────────────────────────────────────────┘

  ┌──────────────┐                              ┌──────────────┐
  │   ACTIVE     │                              │  SUSPENDED   │
  │  (running    │──── FAILOVER EVENT ─────────▶│  (paused,    │
  │   on sched.) │                              │   no refresh)│
  └──────────────┘                              └──────────────┘
         ▲                                             │
         │                                             │
         │              MANUAL ACTION                  │
         │◀────── ALTER FAILOVER GROUP ... RESUME ─────┘
         │
         │         ⚠️ NEVER automatic
         │         ⚠️ Must run from secondary account
         │

  Schedule DEFINITION is preserved across failover/fallback.
  Only the ACTIVE/SUSPENDED state changes.
  No recreation of FG or schedule is needed.
```

---

### Non-Replicated Objects Lifecycle

```
┌─────────────────────────────────────────────────────────────────────────┐
│              NON-REPLICATED OBJECTS LIFECYCLE                           │
└─────────────────────────────────────────────────────────────────────────┘

  Objects NOT replicated (per Snowflake documentation):
  ┌──────────────────┬──────────────────────────────────────────────┐
  │ Object Type      │ DR Impact                                    │
  ├──────────────────┼──────────────────────────────────────────────┤
  │ Hybrid Tables    │ Not on DR. No Fail-safe. Limited Time Travel │
  │ External Tables  │ Not replicated. Recreate manually on DR      │
  │ Event Tables     │ Not replicated                               │
  │ Temporary Tables │ Session-scoped, never replicated             │
  │ Temporary Stages │ Not replicated                               │
  │ Inbound Shares   │ Not replicated (shares FROM providers)       │
  │ Class Instances  │ Not replicated (except CUSTOM_CLASSIFIER)    │
  │ Online Feat. Tbl │ Not replicated                               │
  └──────────────────┴──────────────────────────────────────────────┘

  Timeline:
  ─────────────────────────────────────────────────────────────────────

  NORMAL:    [Hybrid Tables exist on PRIMARY, writable]
                     │
  FAILOVER:  [Hybrid Tables still on former PRIMARY, but DB is read-only]
             [Hybrid Tables DO NOT exist on DR — gap in service]
                     │
  FALLBACK:  [Hybrid Tables on original PRIMARY, writable again ✓]
             [No data loss for these objects]

  ─────────────────────────────────────────────────────────────────────
```

---

## Detailed Responses

### SECTION 1: Failover from Primary to DR

#### Q1: Hybrid Tables, Time Travel, Failsafe — removed from primary after failover?

**No.** Non-replicated objects are NOT removed from the original primary. After failover:
- The original primary becomes a **read-only secondary**
- All objects (including Hybrid Tables) remain **intact** on the former primary
- They are simply not writable while in secondary mode
- On DR: these objects **do not exist** (they were never replicated)

**Time Travel:** The `DATA_RETENTION_TIME_IN_DAYS` parameter IS replicated. However, Time Travel history from the original primary is NOT transferred — DR starts fresh from each refresh snapshot.

**Failsafe:** Operates independently per account. The 7-day window on DR begins from the refresh point forward.

#### Q2: What happens to the FG replication schedule on primary?

- The FG on the former primary becomes a **secondary**
- **All scheduled refreshes are SUSPENDED automatically**
- The schedule definition is **preserved** (no recreation needed)

#### Q3: Does replication start from DR to primary automatically?

**No.** Manual action required:
```sql
-- From the former-primary account (now secondary):
ALTER FAILOVER GROUP <fg_name> RESUME;
```

#### Q4: How to discard DR changes for fallback?

**Do NOT resume replication to the former primary.** Then simply failback — the former primary retains its pre-failover state. See Decision Tree diagram above.

#### Q5: What happens to scheduled Tasks?

- Tasks on DR **resume automatically** after promotion
- Tasks on former primary **become dormant**
- Requires `ENABLE_STREAM_TASK_REPLICATION = TRUE`

---

### SECTION 2: Fallback from DR to Primary

#### Q1: Non-replicated objects still available?

**Yes.** They were never deleted. After re-promoting the original primary, Hybrid Tables and other non-replicated objects are **fully writable again**.

#### Q2: FG replication schedule?

Same pattern: schedule definitions persist, state becomes SUSPENDED, manual RESUME required.

#### Q3: Replication resume automatically?

**No.** Manual action required:
```sql
-- From DR account (now secondary again):
ALTER FAILOVER GROUP <fg_name> RESUME;
```

#### Q4: Scheduled Tasks — how to ensure they resume?

Tasks **resume automatically** on re-promotion. Validate with:
```sql
SHOW TASKS IN DATABASE <db>;
SELECT * FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
  WHERE DATABASE_NAME = '<db>'
  ORDER BY SCHEDULED_TIME DESC LIMIT 50;
```

---

## SQL Runbook

### Failover Procedure

```sql
-- PRE-FAILOVER: Verify replication lag
SELECT * FROM TABLE(INFORMATION_SCHEMA.REPLICATION_GROUP_REFRESH_HISTORY('<fg_name>'));

-- STEP 1: Suspend refresh on DR (prevent conflicts)
-- Run from DR account:
ALTER FAILOVER GROUP <fg_name> SUSPEND;

-- STEP 2: Promote DR to primary
-- Run from DR account:
ALTER FAILOVER GROUP <fg_name> PRIMARY;

-- STEP 3: Redirect clients
ALTER CONNECTION <connection_name> PRIMARY;

-- STEP 4 (OPTIONAL): Resume replication back to former primary
-- Run from former-primary account:
ALTER FAILOVER GROUP <fg_name> RESUME;

-- POST-FAILOVER: Validate tasks
SHOW TASKS IN DATABASE <db>;
```

### Fallback Procedure

```sql
-- STEP 1: Suspend refresh on former primary (now secondary)
-- Run from former-primary account:
ALTER FAILOVER GROUP <fg_name> SUSPEND;

-- STEP 2: Verify no refresh in-progress
SELECT * FROM TABLE(INFORMATION_SCHEMA.REPLICATION_GROUP_REFRESH_HISTORY('<fg_name>'));

-- STEP 3: Re-promote original primary
-- Run from original-primary account:
ALTER FAILOVER GROUP <fg_name> PRIMARY;

-- STEP 4: Redirect clients back
ALTER CONNECTION <connection_name> PRIMARY;

-- STEP 5: Resume replication to DR
-- Run from DR account (now secondary again):
ALTER FAILOVER GROUP <fg_name> RESUME;

-- POST-FALLBACK: Validate
SHOW TASKS IN DATABASE <db>;
SHOW HYBRID TABLES IN DATABASE <db>;
```

---

## Action Items

| # | Action | Priority |
|---|--------|----------|
| 1 | Audit non-replicated objects: `SHOW HYBRID TABLES IN ACCOUNT;` | High |
| 2 | Verify `ENABLE_STREAM_TASK_REPLICATION = TRUE` at account level | High |
| 3 | Build operational runbook with account-specific FG names | High |
| 4 | Establish "no-resume" policy for DR drills | Medium |
| 5 | Document Hybrid Table mitigation strategy | Medium |
| 6 | Schedule and execute DR drill | Medium |
