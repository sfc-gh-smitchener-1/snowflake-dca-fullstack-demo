# Snowflake DR: Failover & Fallback — Mermaid Diagrams

> Companion to `DR_FAILOVER_FALLBACK.md`. All diagrams use **Mermaid** syntax that imports cleanly into **Excalidraw** (via *File → Import → Mermaid…*).
> Stick to `flowchart`, `sequenceDiagram`, and `classDiagram` blocks — these are the types Excalidraw's `mermaid-to-excalidraw` library renders natively.

**Prerequisites:** Business Critical Edition (or higher), Failover Groups configured with replication schedules, `ENABLE_STREAM_TASK_REPLICATION = TRUE`.

---

## Legend (shared styling)

All diagrams use the **Snowflake brand palette** — *Snowflake Blue* + *Star Blue* as basics, *Valencia*, *Greenery*, and *Vivid Pink* as accents. Copy this `classDef` block into Excalidraw if you want the colors to carry over.

| Style | Meaning | Snowflake Color |
|---|---|---|
| **Snowflake Blue** | Primary / Read-Write | `#29B5E8` (basic) |
| **Star Blue** | Secondary / Read-Only | `#11567F` (basic) |
| **Ice, dashed** | Dormant / Suspended | `#E8EEF2` |
| **Valencia Orange** | Manual action required | `#FF9F36` (accent) |
| **Greenery** | Automatic behavior | `#75CD7E` (accent) |
| **Vivid Pink, dashed** | Non-replicated object | `#FF5F97` (accent) |

```mermaid
flowchart LR
    A["Primary / Read-Write"]:::primary
    B["Secondary / Read-Only"]:::secondary
    C["Dormant / Suspended"]:::dormant
    D["Manual Action Required"]:::manual
    E["Non-Replicated Object"]:::nonrepl
    F["Automatic Behavior"]:::auto

    classDef primary  fill:#29B5E8,stroke:#11567F,color:#0F2745,stroke-width:2px
    classDef secondary fill:#11567F,stroke:#0F2745,color:#FFFFFF,stroke-width:2px
    classDef dormant  fill:#E8EEF2,stroke:#5B6770,color:#1F2937,stroke-dasharray: 4 3
    classDef manual   fill:#FF9F36,stroke:#B45309,color:#0F2745,stroke-width:2px
    classDef auto     fill:#75CD7E,stroke:#1F7A2E,color:#0F2745,stroke-width:2px
    classDef nonrepl  fill:#FF5F97,stroke:#9B1259,color:#FFFFFF,stroke-dasharray: 6 3
```

---

## 1. High-Level Architecture (Two-Account DR Topology)

```mermaid
flowchart LR
    subgraph CLIENTS["Clients / Applications"]
        APP["Apps, BI Tools,<br/>Streamlit, dbt"]:::primary
    end

    subgraph CONN["Snowflake Connection Object"]
        URL[("ALTER CONNECTION ... PRIMARY<br/>controls active endpoint")]:::manual
    end

    subgraph PRIM["PRIMARY ACCOUNT — Region A"]
        direction TB
        FG_P["Failover Group<br/>state = PRIMARY"]:::primary
        DB_P[("Databases R/W")]:::primary
        RU_P["Roles / Users / Grants"]:::primary
        WH_P["Warehouses"]:::primary
        TK_P["Tasks: ACTIVE"]:::auto
        INT_P["Integrations / Stages"]:::primary
        NR_P["NON-REPLICATED:<br/>Hybrid Tables<br/>External Tables<br/>Event Tables<br/>Temp Tables / Stages"]:::nonrepl
    end

    subgraph DR["DR ACCOUNT — Region B"]
        direction TB
        FG_D["Failover Group<br/>state = SECONDARY"]:::secondary
        DB_D[("Databases R/O")]:::secondary
        RU_D["Roles / Users / Grants"]:::secondary
        WH_D["Warehouses"]:::secondary
        TK_D["Tasks: DORMANT"]:::dormant
        INT_D["Integrations / Stages"]:::secondary
        NR_D["NON-REPLICATED:<br/>DO NOT EXIST"]:::nonrepl
    end

    APP --> URL
    URL -->|active| FG_P
    URL -.->|standby| FG_D

    FG_P ==>|"Failover Group<br/>refresh schedule"| FG_D
    NR_P -. "not replicated" .-> NR_D

    classDef primary   fill:#29B5E8,stroke:#11567F,color:#0F2745,stroke-width:2px
    classDef secondary fill:#11567F,stroke:#0F2745,color:#FFFFFF,stroke-width:2px
    classDef dormant   fill:#E8EEF2,stroke:#5B6770,color:#1F2937,stroke-dasharray: 4 3
    classDef manual    fill:#FF9F36,stroke:#B45309,color:#0F2745,stroke-width:2px
    classDef auto      fill:#75CD7E,stroke:#1F7A2E,color:#0F2745,stroke-width:2px
    classDef nonrepl   fill:#FF5F97,stroke:#9B1259,color:#FFFFFF,stroke-dasharray: 6 3
```

---

## 2. Normal Operations — Steady State

```mermaid
flowchart LR
    subgraph PRIM["PRIMARY ACCOUNT — Read/Write"]
        direction TB
        FGP["Failover Group<br/>state = PRIMARY<br/>schedule = ACTIVE"]:::primary
        subgraph PCONT["Replicated Objects"]
            DBP[("Databases")]:::primary
            RP["Roles / Users"]:::primary
            WP["Warehouses"]:::primary
            TP["Tasks: ACTIVE"]:::auto
            IP["Integrations"]:::primary
        end
        subgraph PNR["Non-Replicated"]
            HP["Hybrid Tables"]:::nonrepl
            EP["External Tables"]:::nonrepl
            EVP["Event Tables"]:::nonrepl
            TMP["Temp Tables / Stages"]:::nonrepl
        end
        FGP --- DBP
    end

    subgraph DR["DR ACCOUNT — Read-Only"]
        direction TB
        FGD["Failover Group<br/>state = SECONDARY<br/>schedule = ACTIVE"]:::secondary
        subgraph DCONT["Replicated Objects (R/O copies)"]
            DBD[("Databases")]:::secondary
            RD["Roles / Users"]:::secondary
            WD["Warehouses"]:::secondary
            TD["Tasks: DORMANT"]:::dormant
            ID["Integrations"]:::secondary
        end
        subgraph DNR["Non-Replicated"]
            GAP["do not exist on DR"]:::nonrepl
        end
        FGD --- DBD
    end

    FGP ==>|"scheduled refresh<br/>snapshot plus delta"| FGD
    PNR -. "NOT replicated" .-> DNR

    classDef primary   fill:#29B5E8,stroke:#11567F,color:#0F2745,stroke-width:2px
    classDef secondary fill:#11567F,stroke:#0F2745,color:#FFFFFF,stroke-width:2px
    classDef dormant   fill:#E8EEF2,stroke:#5B6770,color:#1F2937,stroke-dasharray: 4 3
    classDef auto      fill:#75CD7E,stroke:#1F7A2E,color:#0F2745,stroke-width:2px
    classDef nonrepl   fill:#FF5F97,stroke:#9B1259,color:#FFFFFF,stroke-dasharray: 6 3
```

---

## 3. Failover: Primary → DR

```mermaid
flowchart LR
    subgraph FORMER["FORMER PRIMARY — now Read-Only"]
        direction TB
        FGFP["Failover Group<br/>state = SECONDARY<br/>schedule = SUSPENDED"]:::secondary
        DBFP[("Databases R/O")]:::secondary
        TFP["Tasks: DORMANT"]:::dormant
        NRFP["Hybrid / External Tables<br/>STILL PRESENT but R/O"]:::nonrepl
    end

    subgraph DRP["DR ACCOUNT — Promoted, Read/Write"]
        direction TB
        FGDR["Failover Group<br/>state = PRIMARY<br/>schedule = SUSPENDED"]:::primary
        DBDR[("Databases R/W")]:::primary
        TDR["Tasks: ACTIVE<br/>auto-resume"]:::auto
        NRDR["Hybrid / External Tables<br/>DO NOT EXIST<br/>recreate if needed"]:::nonrepl
    end

    CMD1["Step 1 — on DR account:<br/>ALTER FAILOVER GROUP fg PRIMARY"]:::manual
    CMD2["Step 2 — clients:<br/>ALTER CONNECTION name PRIMARY"]:::manual
    CMD3["Step 3 OPTIONAL — on former primary:<br/>ALTER FAILOVER GROUP fg RESUME<br/>starts DR to Former Primary replication"]:::manual

    CMD1 --> FGDR
    CMD2 -->|"redirect client traffic"| FGDR
    FGDR -. "no auto refresh" .-> FGFP
    CMD3 -. "if executed" .-> FGFP

    classDef primary   fill:#29B5E8,stroke:#11567F,color:#0F2745,stroke-width:2px
    classDef secondary fill:#11567F,stroke:#0F2745,color:#FFFFFF,stroke-width:2px
    classDef dormant   fill:#E8EEF2,stroke:#5B6770,color:#1F2937,stroke-dasharray: 4 3
    classDef manual    fill:#FF9F36,stroke:#B45309,color:#0F2745,stroke-width:2px
    classDef auto      fill:#75CD7E,stroke:#1F7A2E,color:#0F2745,stroke-width:2px
    classDef nonrepl   fill:#FF5F97,stroke:#9B1259,color:#FFFFFF,stroke-dasharray: 6 3
```

---

## 4. Post-Failover: Replication Resumed (DR → Former Primary)

```mermaid
flowchart LR
    subgraph DRP["DR ACCOUNT — PRIMARY, Read/Write"]
        direction TB
        FGDR["Failover Group<br/>state = PRIMARY<br/>schedule = ACTIVE"]:::primary
        DBDR[("Databases R/W")]:::primary
        TDR["Tasks: ACTIVE"]:::auto
    end

    subgraph FORMER["FORMER PRIMARY — SECONDARY, Read-Only"]
        direction TB
        FGFP["Failover Group<br/>state = SECONDARY<br/>schedule = RESUMED"]:::secondary
        DBFP[("Databases R/O")]:::secondary
        TFP["Tasks: DORMANT"]:::dormant
        NRFP["Hybrid / External Tables<br/>still intact R/O"]:::nonrepl
    end

    TRIGGER["Manually run on former primary:<br/>ALTER FAILOVER GROUP fg RESUME"]:::manual

    TRIGGER --> FGFP
    FGDR ==>|"scheduled refreshes<br/>DR to Former Primary"| FGFP

    NOTE["WARNING: Once resumed, DR writes flow back<br/>to former primary. To discard DR changes later,<br/>you must Time-Travel before failback."]:::manual

    FGFP --- NOTE

    classDef primary   fill:#29B5E8,stroke:#11567F,color:#0F2745,stroke-width:2px
    classDef secondary fill:#11567F,stroke:#0F2745,color:#FFFFFF,stroke-width:2px
    classDef dormant   fill:#E8EEF2,stroke:#5B6770,color:#1F2937,stroke-dasharray: 4 3
    classDef manual    fill:#FF9F36,stroke:#B45309,color:#0F2745,stroke-width:2px
    classDef auto      fill:#75CD7E,stroke:#1F7A2E,color:#0F2745,stroke-width:2px
    classDef nonrepl   fill:#FF5F97,stroke:#9B1259,color:#FFFFFF,stroke-dasharray: 6 3
```

---

## 5. Fallback: DR → Original Primary

```mermaid
flowchart LR
    subgraph ORIG["ORIGINAL PRIMARY — Re-promoted, R/W"]
        direction TB
        FGOP["Failover Group<br/>state = PRIMARY<br/>schedule = ACTIVE"]:::primary
        DBOP[("Databases R/W")]:::primary
        TOP["Tasks: ACTIVE<br/>auto-resume"]:::auto
        NROP["Hybrid / External Tables<br/>fully writable"]:::nonrepl
    end

    subgraph DRBACK["DR ACCOUNT — back to SECONDARY"]
        direction TB
        FGDR["Failover Group<br/>state = SECONDARY<br/>schedule = RESUMED"]:::secondary
        DBDR[("Databases R/O")]:::secondary
        TDR["Tasks: DORMANT"]:::dormant
    end

    S1["Step 1 — on current secondary aka former primary:<br/>ALTER FAILOVER GROUP fg SUSPEND"]:::manual
    S2["Step 2 — verify no refresh in-progress<br/>REPLICATION_GROUP_REFRESH_HISTORY"]:::manual
    S3["Step 3 — on original primary:<br/>ALTER FAILOVER GROUP fg PRIMARY"]:::manual
    S4["Step 4 — on DR, now secondary:<br/>ALTER FAILOVER GROUP fg RESUME"]:::manual
    S5["Step 5 — clients:<br/>ALTER CONNECTION name PRIMARY"]:::manual

    S1 --> S2 --> S3 --> S4 --> S5
    S3 --> FGOP
    S4 --> FGDR
    FGOP ==>|"scheduled refreshes"| FGDR

    classDef primary   fill:#29B5E8,stroke:#11567F,color:#0F2745,stroke-width:2px
    classDef secondary fill:#11567F,stroke:#0F2745,color:#FFFFFF,stroke-width:2px
    classDef dormant   fill:#E8EEF2,stroke:#5B6770,color:#1F2937,stroke-dasharray: 4 3
    classDef manual    fill:#FF9F36,stroke:#B45309,color:#0F2745,stroke-width:2px
    classDef auto      fill:#75CD7E,stroke:#1F7A2E,color:#0F2745,stroke-width:2px
    classDef nonrepl   fill:#FF5F97,stroke:#9B1259,color:#FFFFFF,stroke-dasharray: 6 3
```

---

## 6. End-to-End Sequence: Failover → Operate on DR → Fallback

Operator-perspective sequence covering the full DR lifecycle. Useful for runbook walk-throughs.

```mermaid
sequenceDiagram
    autonumber
    actor OPS as DR Operator
    participant PRIM as Primary Account
    participant DR as DR Account
    participant CONN as Connection Object
    participant APP as Client Apps

    Note over PRIM,DR: NORMAL — PRIMARY R/W, DR R/O, FG schedule ACTIVE

    PRIM->>DR: Scheduled FG refresh (auto)
    APP->>CONN: Resolve hostname
    CONN->>PRIM: Route traffic

    Note over OPS: FAILOVER EVENT

    OPS->>DR: ALTER FAILOVER GROUP fg SUSPEND
    OPS->>DR: ALTER FAILOVER GROUP fg PRIMARY
    DR-->>DR: Tasks auto-resume; DB becomes R/W
    PRIM-->>PRIM: Becomes SECONDARY R/O; tasks dormant
    OPS->>CONN: ALTER CONNECTION name PRIMARY
    APP->>CONN: Re-resolve
    CONN->>DR: Route traffic

    opt Resume replication back to former primary
        OPS->>PRIM: ALTER FAILOVER GROUP fg RESUME
        DR->>PRIM: Scheduled refreshes (DR to Former Primary)
    end

    Note over OPS: FALLBACK EVENT

    OPS->>PRIM: ALTER FAILOVER GROUP fg SUSPEND
    OPS->>PRIM: Verify REPLICATION_GROUP_REFRESH_HISTORY idle
    OPS->>PRIM: ALTER FAILOVER GROUP fg PRIMARY
    PRIM-->>PRIM: R/W restored; tasks auto-resume
    DR-->>DR: Becomes SECONDARY; tasks dormant
    OPS->>DR: ALTER FAILOVER GROUP fg RESUME
    OPS->>CONN: ALTER CONNECTION name PRIMARY
    APP->>CONN: Re-resolve
    CONN->>PRIM: Route traffic

    Note over PRIM,DR: STEADY STATE RESTORED
```

---

## 7. Task Lifecycle During Failover/Fallback

```mermaid
flowchart TB
    subgraph N["NORMAL"]
        N1["Primary: Tasks ACTIVE<br/>scheduled and executing"]:::auto
        N2["DR: Tasks DORMANT<br/>replicated but not running"]:::dormant
    end

    subgraph F["FAILOVER"]
        F1["Former Primary:<br/>Tasks become DORMANT"]:::dormant
        F2["DR Promoted:<br/>Tasks AUTO-RESUME"]:::auto
    end

    subgraph B["FALLBACK"]
        B1["Original Primary:<br/>Tasks AUTO-RESUME"]:::auto
        B2["DR Demoted:<br/>Tasks become DORMANT"]:::dormant
    end

    N1 -->|"ALTER FG PRIMARY on DR"| F1
    N2 -->|"ALTER FG PRIMARY on DR"| F2
    F1 -->|"ALTER FG PRIMARY on original"| B1
    F2 -->|"ALTER FG PRIMARY on original"| B2

    PREREQ["PREREQS<br/>1. ENABLE_STREAM_TASK_REPLICATION = TRUE<br/>2. Tasks referencing streams require both DBs<br/>   in the same Failover Group"]:::manual

    F --- PREREQ

    classDef auto    fill:#75CD7E,stroke:#1F7A2E,color:#0F2745,stroke-width:2px
    classDef dormant fill:#E8EEF2,stroke:#5B6770,color:#1F2937,stroke-dasharray: 4 3
    classDef manual  fill:#FF9F36,stroke:#B45309,color:#0F2745,stroke-width:2px
```

---

## 8. Decision Tree: Discard vs. Keep DR Changes

```mermaid
flowchart TB
    START(["After Failover to DR"]):::manual
    Q{{"Did you RESUME replication<br/>back to former primary?"}}:::manual

    YES["YES — DR changes ARE<br/>flowing to former primary"]:::secondary
    NO["NO — Former primary retains<br/>pre-failover state"]:::primary

    KEEP["KEEP DR CHANGES<br/>1. Suspend refresh on former primary<br/>2. ALTER FG PRIMARY on original<br/>3. RESUME on DR, now secondary"]:::auto

    DISCARD["DISCARD DR CHANGES<br/>1. SUSPEND refresh<br/>2. Time Travel former primary<br/>   to pre-failover timestamp<br/>3. Then failback"]:::manual

    CLEAN["CLEAN ROLLBACK<br/>Just failback. Former primary still<br/>holds pre-failover state.<br/>DR writes are discarded."]:::auto

    BP["DR DRILL BEST PRACTICE<br/>Do NOT resume replication to<br/>former primary — clean fallback guaranteed"]:::auto

    START --> Q
    Q -->|YES| YES
    Q -->|NO| NO
    YES --> KEEP
    YES --> DISCARD
    NO --> CLEAN
    NO --> BP

    classDef primary   fill:#29B5E8,stroke:#11567F,color:#0F2745,stroke-width:2px
    classDef secondary fill:#11567F,stroke:#0F2745,color:#FFFFFF,stroke-width:2px
    classDef manual    fill:#FF9F36,stroke:#B45309,color:#0F2745,stroke-width:2px
    classDef auto      fill:#75CD7E,stroke:#1F7A2E,color:#0F2745,stroke-width:2px
```

---

## 9. Replication Schedule State Machine

> Excalidraw's Mermaid importer prefers `flowchart` over `stateDiagram-v2`. This is the state machine drawn as a flowchart for portability.

```mermaid
flowchart LR
    A(["ACTIVE<br/>running on schedule"]):::auto
    S(["SUSPENDED<br/>no refresh"]):::dormant

    A -->|"FAILOVER EVENT<br/>auto-suspend on both accounts"| S
    S -->|"ALTER FAILOVER GROUP fg RESUME<br/>manual, from secondary"| A

    NOTE["RULES<br/>1. Transition to SUSPENDED is automatic on failover<br/>2. Transition back to ACTIVE is ALWAYS manual<br/>3. Schedule DEFINITION is preserved — no recreate needed<br/>4. RESUME must be issued from the secondary account"]:::manual

    A --- NOTE
    S --- NOTE

    classDef auto    fill:#75CD7E,stroke:#1F7A2E,color:#0F2745,stroke-width:2px
    classDef dormant fill:#E8EEF2,stroke:#5B6770,color:#1F2937,stroke-dasharray: 4 3
    classDef manual  fill:#FF9F36,stroke:#B45309,color:#0F2745,stroke-width:2px
```

---

## 10. Non-Replicated Objects — Lifecycle Timeline

```mermaid
flowchart LR
    subgraph T1["NORMAL"]
        T1A["PRIMARY:<br/>Hybrid Tables exist<br/>writable"]:::primary
        T1B["DR:<br/>do not exist"]:::nonrepl
    end

    subgraph T2["FAILOVER"]
        T2A["FORMER PRIMARY:<br/>Hybrid Tables STILL THERE<br/>but DB is READ-ONLY"]:::secondary
        T2B["DR Promoted:<br/>Hybrid Tables MISSING<br/>service gap unless recreated"]:::nonrepl
    end

    subgraph T3["FALLBACK"]
        T3A["ORIGINAL PRIMARY:<br/>Hybrid Tables writable again<br/>no data loss"]:::primary
        T3B["DR Demoted:<br/>still missing"]:::nonrepl
    end

    T1 --> T2 --> T3

    classDef primary   fill:#29B5E8,stroke:#11567F,color:#0F2745,stroke-width:2px
    classDef secondary fill:#11567F,stroke:#0F2745,color:#FFFFFF,stroke-width:2px
    classDef nonrepl   fill:#FF5F97,stroke:#9B1259,color:#FFFFFF,stroke-dasharray: 6 3
```

### Non-Replicated Object Reference

| Object Type           | DR Impact                                              |
|-----------------------|--------------------------------------------------------|
| Hybrid Tables         | Not on DR. No Fail-safe. Limited Time Travel.          |
| External Tables       | Not replicated. Recreate manually on DR.               |
| Event Tables          | Not replicated.                                        |
| Temporary Tables      | Session-scoped, never replicated.                      |
| Temporary Stages      | Not replicated.                                        |
| Inbound Shares        | Not replicated (shares **from** providers).            |
| Class Instances       | Not replicated (except `CUSTOM_CLASSIFIER`).           |
| Online Feature Tables | Not replicated.                                        |

---

## 11. Account / Object Class Map (Optional — for Excalidraw class import)

A `classDiagram` view of which object types live where and what state they occupy. Useful as a one-page reference card.

```mermaid
classDiagram
    class FailoverGroup {
      +name
      +objectTypes
      +allowedAccounts
      +replicationSchedule
      +state PRIMARY_or_SECONDARY
      +scheduleState ACTIVE_or_SUSPENDED
    }

    class PrimaryAccount {
      +databases_RW
      +rolesUsersGrants
      +warehouses
      +tasksACTIVE
      +integrations
    }

    class DRAccount {
      +databases_RO
      +rolesUsersGrants
      +warehouses
      +tasksDORMANT
      +integrations
    }

    class NonReplicated {
      +hybridTables
      +externalTables
      +eventTables
      +tempTables
      +tempStages
      +inboundShares
      +classInstances
      +onlineFeatureTables
    }

    class Connection {
      +name
      +primaryAccount
      +alterConnectionPrimary()
    }

    FailoverGroup "1" --> "1..*" PrimaryAccount : owned_by
    FailoverGroup "1" --> "1..*" DRAccount : replicated_to
    PrimaryAccount "1" --> "1" NonReplicated : holds_locally
    DRAccount ..> NonReplicated : missing_on_DR
    Connection "1" --> "1" PrimaryAccount : routes_to
    Connection ..> DRAccount : can_switch_to
```

---

## SQL Runbook (reference)

### Failover Procedure

```sql
-- PRE-FAILOVER: Verify replication lag
SELECT *
FROM TABLE(INFORMATION_SCHEMA.REPLICATION_GROUP_REFRESH_HISTORY('<fg_name>'));

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
SELECT *
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
WHERE DATABASE_NAME = '<db>'
ORDER BY SCHEDULED_TIME DESC
LIMIT 50;
```

### Fallback Procedure

```sql
-- STEP 1: Suspend refresh on former primary (now secondary)
-- Run from former-primary account:
ALTER FAILOVER GROUP <fg_name> SUSPEND;

-- STEP 2: Verify no refresh in-progress
SELECT *
FROM TABLE(INFORMATION_SCHEMA.REPLICATION_GROUP_REFRESH_HISTORY('<fg_name>'));

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

---

## Importing into Excalidraw

1. Open Excalidraw → **Generate → Mermaid to Excalidraw** (or *File → Import → Mermaid…*).
2. Copy the contents of any ```` ```mermaid ```` block above (just the code between the fences).
3. Paste, click **Insert**, then tweak colors/positions in Excalidraw.
4. Excalidraw's importer fully supports `flowchart` and `sequenceDiagram`. `classDiagram` is supported with minor fidelity loss. State diagrams (`stateDiagram-v2`) are **not** supported — that's why §9 is drawn as a flowchart.
