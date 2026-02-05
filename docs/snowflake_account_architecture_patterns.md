# Snowflake Account Architecture Patterns

Reference architectures for organizing Snowflake accounts for CDO/Innovation teams alongside IT-managed production environments.

---

## Option 1: Sandbox Account in Existing Organization

A new account (e.g., `ORG-CDO_LAB`) created under your current organization umbrella.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         SNOWFLAKE ORGANIZATION                              │
│                         (Single Org Contract)                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────┐     ┌─────────────────────────────┐        │
│  │     IT PRODUCTION ACCOUNT   │     │      CDO SANDBOX ACCOUNT    │        │
│  │     (ORG-PROD)              │     │      (ORG-CDO_LAB)          │        │
│  │                             │     │                             │        │
│  │  ┌─────────────────────┐    │     │  ┌─────────────────────┐    │        │
│  │  │ ACCOUNTADMIN        │    │     │  │ ACCOUNTADMIN        │    │        │
│  │  │ (IT Controlled)     │    │     │  │ (CDO Controlled)    │    │        │
│  │  └─────────────────────┘    │     │  └─────────────────────┘    │        │
│  │                             │     │                             │        │
│  │  ┌─────────────────────┐    │     │  ┌─────────────────────┐    │        │
│  │  │ Production Data     │    │     │  │ DATA_ADMIN Role     │    │        │
│  │  │ • Strict SDLC       │    │     │  │ • Full freedom      │    │        │
│  │  │ • Change Control    │◄── ┼──┬──┼──│ • Rapid prototyping │    │        │
│  │  │ • Audit Compliance  │    │  │  │  │ • POC development   │    │        │
│  │  └─────────────────────┘    │  │  │  └─────────────────────┘    │        │
│  │                             │  │  │                             │        │
│  │  ┌─────────────────────┐    │  │  │  ┌─────────────────────┐    │        │
│  │  │ Validated Work      │    │  │  │  │ Resource Monitor    │    │        │
│  │  │ (After SDLC)        │◄── ┼──┘  │  │ (Budget Cap)        │    │        │
│  │  └─────────────────────┘    │     │  │ $X/month limit      │    │        │
│  │                             │     │  └─────────────────────┘    │        │
│  └─────────────────────────────┘     └─────────────────────────────┘        │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    ORGANIZATION-LEVEL FEATURES                      │    │
│  │  • Shared Identity (Organization Users - same person in both)       │    │
│  │  • Account Replication (IT pulls validated work into SDLC)          │    │
│  │  • Centralized Billing (Single contract, split cost centers)        │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

                           ACCOUNT REPLICATION
                    ┌─────────────────────────────────┐
                    │                                 │
   CDO_LAB Account  │  ────────────────────────────►  │  PROD Account
   (Innovation)     │        Validated Objects        │  (SDLC Process)
                    │        Replicated to IT         │
                    │                                 │
                    └─────────────────────────────────┘
```

### Pros

```
┌────────────────────────────────────────────────────────────────────────────┐
│  ✓ SHARED IDENTITY                                                         │
│    Organization Users - data scientist is the same person in both accounts │
│                                                                            │
│  ✓ EASY PROMOTION                                                          │
│    IT uses Account Replication to "pull" validated work into SDLC          │
│                                                                            │
│  ✓ COST CONTROL                                                            │
│    Account-level Resource Monitor prevents budget overruns                 │
└────────────────────────────────────────────────────────────────────────────┘
```

### Cons

```
┌────────────────────────────────────────────────────────────────────────────┐
│  ✗ EDITION DIFFERENCES                                                     │
│    If CDO needs different edition (Business Critical vs Enterprise),       │
│    costs must be managed separately                                        │
│                                                                            │
│  ✗ NO CROSS-ACCOUNT CLONING                                                │
│    Must pay for data transfer/storage when replicating large datasets      │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Option 2: Entirely New Organization

Treating the CDO's team like an outside company with complete separation.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                    IT ORGANIZATION                                  │   │
│   │                    (Org Contract #1)                                │   │
│   │                                                                     │   │
│   │  ┌──────────────────────┐  ┌──────────────────────┐                 │   │
│   │  │  ORGADMIN            │  │  IT PRODUCTION       │                 │   │
│   │  │  (IT Controlled)     │  │  ACCOUNT             │                 │   │
│   │  └──────────────────────┘  │                      │                 │   │
│   │                            │  • Strict SDLC       │                 │   │
│   │                            │  • Prod Data         │                 │   │
│   │                            │  • Audit Trail       │                 │   │
│   │                            └──────────────────────┘                 │   │
│   │                                                                     │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│                          ╔═══════════════════╗                              │
│                          ║   FIREWALL        ║                              │
│                          ║   (Complete       ║                              │
│                          ║    Isolation)     ║                              │
│                          ╚═══════════════════╝                              │
│                                   │                                         │
│                                   │  External Data Sharing                  │
│                                   │  (Like sharing with                     │
│                                   │   an outside company)                   │
│                                   ▼                                         │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                    CDO ORGANIZATION                                 │   │
│   │                    (Org Contract #2)                                │   │
│   │                                                                     │   │
│   │  ┌──────────────────────┐  ┌──────────────────────┐                 │   │
│   │  │  ORGADMIN            │  │  CDO INNOVATION      │                 │   │
│   │  │  (CDO Controlled)    │  │  ACCOUNT             │                 │   │
│   │  │  • Own accounts      │  │                      │                 │   │
│   │  │  • Full autonomy     │  │  • DATA_ADMIN        │                 │   │
│   │  └──────────────────────┘  │  • Rapid POCs        │                 │   │
│   │                            │  • No IT dependency  │                 │   │
│   │                            └──────────────────────┘                 │   │
│   │                                                                     │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

                    CROSS-ORG DATA MOVEMENT
        ┌─────────────────────────────────────────────┐
        │                                             │
        │   CDO Org ◄══════════════════════► IT Org   │
        │                                             │
        │   • External Data Sharing Only              │
        │   • Separate Contracts                      │
        │   • Separate Security Audits                │
        │   • Separate Credentials                    │
        │                                             │
        └─────────────────────────────────────────────┘
```

### Pros

```
┌────────────────────────────────────────────────────────────────────────────┐
│  ✓ ULTIMATE AUTONOMY                                                       │
│    CDO has own ORGADMIN, creates accounts without asking IT                │
│                                                                            │
│  ✓ ZERO LEAKAGE                                                            │
│    Impossible for CDO config error to affect IT production                 │
└────────────────────────────────────────────────────────────────────────────┘
```

### Cons

```
┌────────────────────────────────────────────────────────────────────────────┐
│  ✗ MASSIVE FRICTION                                                        │
│    Moving "Public Preview" objects requires External Data Sharing          │
│    You are essentially sharing with yourself as an outside company         │
│                                                                            │
│  ✗ ADMIN OVERHEAD                                                          │
│    Double the credentials, contracts, and security audits                  │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Option 3: Hub-and-Spoke (RECOMMENDED)

The most successful high-velocity teams use this hybrid model within a Single Organization.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         SNOWFLAKE ORGANIZATION                              │
│                      (Single Org - Hub & Spoke Model)                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                        ┌───────────────────────┐                            │
│                        │      THE BRIDGE       │                            │
│                        │  (Secure Data Share)  │                            │
│                        │  • Zero Cost          │                            │
│                        │  • Real-Time          │                            │
│                        │  • No Data Movement   │                            │
│                        └───────────┬───────────┘                            │
│                                    │                                        │
│              ┌─────────────────────┼─────────────────────┐                  │
│              │                     │                     │                  │
│              ▼                     │                     ▼                  │
│  ┌───────────────────────┐         │         ┌───────────────────────┐      │
│  │                       │         │         │                       │      │
│  │    THE HUB            │         │         │    THE SPOKE          │      │
│  │    (IT Account)       │◄────────┴────────►│    (CDO Account)      │      │
│  │                       │   Data Sharing    │                       │      │
│  │  ┌─────────────────┐  │   (Both Ways)     │  ┌─────────────────┐  │      │
│  │  │ PRODUCTION DATA │  │                   │  │ DATA_ADMIN      │  │      │
│  │  │                 │──┼──────────────────►│  │ Role Rules      │  │      │
│  │  │ • Curated       │  │  IT shares prod   │  │                 │  │      │
│  │  │ • Validated     │  │  data to CDO      │  │ • Experiment    │  │      │
│  │  │ • Production    │  │                   │  │ • Prototype     │  │      │
│  │  └─────────────────┘  │                   │  │ • Build Logic   │  │      │
│  │                       │                   │  └─────────────────┘  │      │
│  │  ┌─────────────────┐  │                   │                       │      │
│  │  │ STRICT SDLC     │  │                   │  ┌─────────────────┐  │      │
│  │  │                 │◄─┼───────────────────┼──│ NEW LOGIC       │  │      │
│  │  │ • Change Ctrl   │  │  CDO shares new   │  │                 │  │      │
│  │  │ • Code Review   │  │  logic back to IT │  │ • ML Models     │  │      │
│  │  │ • Testing       │  │                   │  │ • Analytics     │  │      │
│  │  │ • Deployment    │  │                   │  │ • Dashboards    │  │      │
│  │  └─────────────────┘  │                   │  └─────────────────┘  │      │
│  │                       │                   │                       │      │
│  │  ┌─────────────────┐  │                   │  ┌─────────────────┐  │      │
│  │  │ RESTRICTED      │  │                   │  │ FREEDOM TO      │  │      │
│  │  │ ACCESS          │  │                   │  │ EXPERIMENT      │  │      │
│  │  └─────────────────┘  │                   │  └─────────────────┘  │      │
│  │                       │                   │                       │      │
│  └───────────────────────┘                   └───────────────────────┘      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### The Workflow

```
                           THE WORKFLOW
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│   1. SHARE                    2. BUILD                   3. RETURN          │
│   ─────────                   ─────────                  ─────────          │
│                                                                             │
│   ┌─────────┐                ┌─────────┐                ┌─────────┐         │
│   │   IT    │   Secure       │   CDO   │   Secure       │   IT    │         │
│   │   HUB   │───Share───────►│  SPOKE  │───Share───────►│   HUB   │         │
│   │         │   (Zero $)     │         │   (Zero $)     │         │         │
│   └─────────┘                └─────────┘                └─────────┘         │
│                                                                             │
│   IT shares                  CDO builds new             IT copies logic     │
│   production data            logic on shared            into Git repo       │
│   to CDO account             data (no copy!)            for formal SDLC     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Secure Data Sharing Details

```
                    SECURE DATA SHARING DETAILS
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│   IT ACCOUNT                                      CDO ACCOUNT               │
│   ──────────                                      ───────────               │
│                                                                             │
│   ┌─────────────────────┐                        ┌─────────────────────┐    │
│   │ SALES_DB.PROD       │    ════════════════►   │ SHARED_DATA.SALES   │    │
│   │ (Source of Truth)   │    CREATE SHARE        │ (Read-Only View)    │    │
│   └─────────────────────┘    Zero-Copy           └─────────────────────┘    │
│                              Real-Time                                      │
│   ┌─────────────────────┐    No ETL              ┌─────────────────────┐    │
│   │ CUSTOMER_DB.PROD    │    ════════════════►   │ SHARED_DATA.CUST    │    │
│   │                     │                        │                     │    │
│   └─────────────────────┘                        └─────────────────────┘    │
│                                                                             │
│                                                                             │
│   ┌─────────────────────┐                        ┌─────────────────────┐    │
│   │ CDO_VALIDATED.      │    ◄════════════════   │ CDO_LAB.MODELS      │    │
│   │ ML_MODELS           │    CDO shares back     │ (CDO Development)   │    │
│   │ (Ready for SDLC)    │    after validation    └─────────────────────┘    │
│   └─────────────────────┘                                                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Comparison Matrix

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          COMPARISON MATRIX                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   Criteria              Sandbox    Separate Org    Hub-Spoke (Winner)       │
│   ────────              ───────    ────────────    ──────────────────       │
│                                                                             │
│   Data Sharing Cost      Medium       High             ★ Zero               │
│                                                                             │
│   Real-Time Access       Yes          No               ★ Yes                │
│                                                                             │
│   Identity Management    ★ Shared     Separate         ★ Shared             │
│                                                                             │
│   CDO Autonomy           Medium       ★ Full           ★ Full               │
│                                                                             │
│   IT Governance          ★ Strong     Weak             ★ Strong             │
│                                                                             │
│   Admin Overhead         Low          ★★ High          ★ Low                │
│                                                                             │
│   SDLC Integration       Medium       Hard             ★ Easy               │
│                                                                             │
│   Security Isolation     Medium       ★ Maximum        Strong               │
│                                                                             │
│   Production Impact      Possible     ★ None           ★ None               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Benefits

```
                    KEY BENEFITS OF HUB-AND-SPOKE

    ┌────────────────────────────────────────────────────────────────┐
    │                                                                │
    │   ✓ Zero-Copy Data Sharing (No storage duplication)            │
    │                                                                │
    │   ✓ Real-Time Data (CDO always sees current production)        │
    │                                                                │
    │   ✓ Clear Ownership (IT owns prod, CDO owns innovation)        │
    │                                                                │
    │   ✓ Easy Promotion (Share back → Copy to Git → SDLC)           │
    │                                                                │
    │   ✓ Budget Control (Resource Monitors per account)             │
    │                                                                │
    │   ✓ Single Contract (One vendor relationship)                  │
    │                                                                │
    │   ✓ Shared Identity (SSO, same user across accounts)           │
    │                                                                │
    └────────────────────────────────────────────────────────────────┘
```

---

## Implementation Quick Start

### Setup Sequence

```
                        IMPLEMENTATION SEQUENCE

    ┌──────────────┐      ┌──────────────┐      ┌──────────────┐
    │   STEP 1     │      │   STEP 2     │      │   STEP 3     │
    │              │      │              │      │              │
    │  ORGADMIN    │─────►│  IT ACCOUNT  │─────►│ CDO ACCOUNT  │
    │  creates     │      │  creates     │      │  mounts      │
    │  CDO account │      │  share       │      │  share       │
    └──────────────┘      └──────────────┘      └──────────────┘
           │                                           │
           │                                           ▼
           │                                   ┌──────────────┐
           │                                   │   STEP 4     │
           │                                   │              │
           │                                   │  CDO builds  │
           │                                   │  models      │
           │                                   └──────────────┘
           │                                           │
           ▼                                           ▼
    ┌──────────────┐      ┌──────────────┐      ┌──────────────┐
    │   STEP 6     │      │   STEP 5     │      │   STEP 5     │
    │              │      │              │      │              │
    │  IT begins   │◄─────│  IT mounts   │◄─────│  CDO shares  │
    │  SDLC        │      │  CDO share   │      │  back to IT  │
    └──────────────┘      └──────────────┘      └──────────────┘
```

### SQL Implementation

```sql
-- =============================================================================
-- STEP 1: Create CDO Account (ORGADMIN in IT's Org)
-- =============================================================================
USE ROLE ORGADMIN;

CREATE ACCOUNT CDO_LAB
    ADMIN_NAME = 'cdo_admin'
    ADMIN_PASSWORD = 'InitialPassword123!'
    EMAIL = 'cdo@company.com'
    EDITION = 'ENTERPRISE'
    REGION = 'AWS_US_WEST_2'
    COMMENT = 'CDO Innovation Lab - Hub-and-Spoke Model';

-- =============================================================================
-- STEP 2: Create Share from IT to CDO (IT Account)
-- =============================================================================
USE ROLE ACCOUNTADMIN;  -- In IT Account

-- Create outbound share
CREATE SHARE IT_TO_CDO_SHARE
    COMMENT = 'Production data shared to CDO for analysis';

-- Grant access to databases/schemas
GRANT USAGE ON DATABASE PRODUCTION_DB TO SHARE IT_TO_CDO_SHARE;
GRANT USAGE ON SCHEMA PRODUCTION_DB.ANALYTICS TO SHARE IT_TO_CDO_SHARE;
GRANT SELECT ON ALL TABLES IN SCHEMA PRODUCTION_DB.ANALYTICS TO SHARE IT_TO_CDO_SHARE;

-- Add CDO account as consumer
ALTER SHARE IT_TO_CDO_SHARE ADD ACCOUNTS = CDO_LAB;

-- =============================================================================
-- STEP 3: Mount Share in CDO Account (CDO Account)
-- =============================================================================
USE ROLE ACCOUNTADMIN;  -- In CDO Account

-- Create database from share
CREATE DATABASE PROD_DATA_SHARED FROM SHARE IT_ACCOUNT.IT_TO_CDO_SHARE;

-- Grant access to DATA_ADMIN
GRANT IMPORTED PRIVILEGES ON DATABASE PROD_DATA_SHARED TO ROLE DATA_ADMIN;

-- =============================================================================
-- STEP 4: CDO Shares Back to IT (CDO Account)
-- =============================================================================
USE ROLE ACCOUNTADMIN;  -- In CDO Account

-- Create outbound share for validated work
CREATE SHARE CDO_TO_IT_SHARE
    COMMENT = 'CDO validated work ready for IT SDLC';

GRANT USAGE ON DATABASE CDO_LAB_DB TO SHARE CDO_TO_IT_SHARE;
GRANT USAGE ON SCHEMA CDO_LAB_DB.VALIDATED TO SHARE CDO_TO_IT_SHARE;
GRANT SELECT ON ALL VIEWS IN SCHEMA CDO_LAB_DB.VALIDATED TO SHARE CDO_TO_IT_SHARE;

-- Add IT account as consumer
ALTER SHARE CDO_TO_IT_SHARE ADD ACCOUNTS = IT_PROD_ACCOUNT;

-- =============================================================================
-- STEP 5: Resource Monitor for CDO Budget (CDO Account)
-- =============================================================================
USE ROLE ACCOUNTADMIN;  -- In CDO Account

CREATE RESOURCE MONITOR CDO_MONTHLY_BUDGET
    WITH 
        CREDIT_QUOTA = 1000  -- $3000/month at $3/credit
        FREQUENCY = MONTHLY
        START_TIMESTAMP = IMMEDIATELY
        TRIGGERS
            ON 75 PERCENT DO NOTIFY
            ON 90 PERCENT DO NOTIFY
            ON 100 PERCENT DO SUSPEND;

-- Apply to all warehouses
ALTER ACCOUNT SET RESOURCE_MONITOR = CDO_MONTHLY_BUDGET;
```

---

## Decision Flowchart

```
                              DECISION TREE

                    ┌─────────────────────────────┐
                    │  How should we organize     │
                    │  CDO's Snowflake access?    │
                    └─────────────┬───────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────────┐
                    │  Does CDO need COMPLETE     │
                    │  autonomy from IT?          │
                    └─────────────┬───────────────┘
                                  │
                    ┌─────────────┴───────────────┐
                    │                             │
                   NO                            YES
                    │                             │
                    ▼                             ▼
    ┌───────────────────────────┐   ┌───────────────────────────┐
    │                           │   │  Is data sharing          │
    │  OPTION 1: SANDBOX        │   │  FRICTION acceptable?     │
    │                           │   │                           │
    │  ✓ Shared identity        │   └─────────────┬─────────────┘
    │  ✓ Easy replication       │                 │
    │  ✗ Some coupling          │   ┌─────────────┴───────────────┐
    │                           │   │                             │
    └───────────────────────────┘  YES                           NO
                                    │                             │
                                    ▼                             ▼
                    ┌───────────────────────────┐   ┌───────────────────────────┐
                    │                           │   │                           │
                    │  OPTION 2: SEPARATE ORG   │   │  OPTION 3: HUB-SPOKE ⭐   │
                    │                           │   │                           │
                    │  ✓ Complete isolation     │   │  ✓ Zero-cost sharing      │
                    │  ✗ High friction          │   │  ✓ Real-time data         │
                    │  ✗ Double admin           │   │  ✓ Easy promotion         │
                    │                           │   │  ✓ RECOMMENDED            │
                    └───────────────────────────┘   └───────────────────────────┘
```

---

## Reference

- [Snowflake Organizations](https://docs.snowflake.com/en/user-guide/organizations)
- [Secure Data Sharing](https://docs.snowflake.com/en/user-guide/data-sharing-intro)
- [Account Replication](https://docs.snowflake.com/en/user-guide/account-replication-intro)
- [Resource Monitors](https://docs.snowflake.com/en/user-guide/resource-monitors)
