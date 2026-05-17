# RE: Follow-ups from May 1 Session

Hi Jaskaran,

Great questions across the board. We'll get the recording over to you as soon as it's processed — expect it within the next few days. In the meantime, here's our take on each item:

---

## 1. Pillar 2 — Openflow Networking

Dana will send over the full networking doc, but here's the quick summary to unblock your planning:

Openflow has two deployment models:
- **Snowflake Deployments** — runs on Snowflake-managed infrastructure (AWS, Azure, GCP)
- **BYOC (Bring Your Own Cloud)** — runs in your AWS VPC

Both support **PrivateLink**. If your networking team is already configuring AWS PrivateLink / Direct Connect for Snowflake, you're most of the way there for Openflow as well. The key prerequisites:

1. PrivateLink must be enabled on your Snowflake account (sounds like this is already in-flight)
2. For Snowflake Deployments: you create a VPC endpoint pointing to the same `privatelink-vpce-id` that your Snowflake PrivateLink uses, then add CNAME records for the Openflow-specific URLs (retrievable via `SYSTEM$GET_PRIVATELINK_CONFIG()`)
3. For BYOC: your VPC needs 2 private subnets across 2 AZs, NAT gateways, and appropriate security group rules — Snowflake provides a CloudFormation template and a pre-flight validator script

**Our recommendation:** Since you already have PrivateLink on the radar, request a Snowflake Deployment first (simpler ops), and validate that your existing VPC endpoint can be extended with the Openflow DNS records. BYOC is only needed if you have strict data-residency or egress-control requirements that mandate the runtime lives in your VPC.

---

## 2. Pillar 4 — DR Posture (Enterprise Edition)

You're right that Enterprise gives you **replication only, no failover**. Here's what's realistic:

**What you CAN do on Enterprise:**
- **Database replication** to a second Snowflake account in another AWS region (same org). You'd schedule refreshes (e.g., every 10 min, hourly, daily — your call on cost vs. RPO).
- **Share replication** — replicate shares alongside databases via replication groups.
- Replicate multiple databases in a single replication group.

**What you CANNOT do without Business Critical:**
- Automated failover/failback (the `FAILOVER GROUP` promotion is a BC feature)
- Client Redirect (automatic connection rerouting)
- Replication of account-level objects (roles, users, warehouses, integrations)

**A realistic DR posture for your footprint:**

| | Enterprise (current) | Business Critical (upgrade path) |
|---|---|---|
| RPO | Defined by replication schedule (e.g., 1 hour) | Same |
| RTO | Manual — update connection strings, re-grant roles in target account | Automated — `ALTER FAILOVER GROUP ... PRIMARY` + Client Redirect |
| Scope | Databases + shares only | Full account objects |

**What we'd recommend right now:**
1. Stand up a second Snowflake account in a different AWS region (within your org — ORGADMIN can do this)
2. Create a replication group with your critical databases, schedule refresh at an interval that matches your RPO tolerance
3. Document a runbook for manual failover (connection string rotation, role re-grants)
4. Test the runbook quarterly

This gives you a defensible DR story without the BC upgrade. When/if you need automated failover and sub-minute RTO, that's the trigger for the edition conversation.

---

## 3. Pillar 6 — Schemachange First-Deploy Speed

The 30–40 min bottleneck is a known pain point with Schemachange's serial execution model. Three options, from least to most disruptive:

### Option A: Parallelize with GitHub Actions Matrix (quick win)

Split your deployment into a matrix job — one job per database. Each runs Schemachange independently and in parallel:

```yaml
strategy:
  matrix:
    database: [DB_A, DB_B, DB_C]
steps:
  - run: schemachange deploy --root-folder ./migrations/${{ matrix.database }}
```

This cuts your wall-clock time to roughly `longest_single_db + overhead` instead of `sum_of_all_three`. On free-tier runners you get up to 20 concurrent jobs.

### Option B: Pre-clone + differential deploy

On sandbox creation, clone PROD databases first (zero-copy, near-instant), then run Schemachange only for net-new migrations that haven't been applied. This means your sandbox isn't walking every historical file — only the delta.

### Option C: Migrate to Snowflake-native CI/CD (longer-term)

Snowflake now offers:
- **DCM (Declarative Configuration Management)** — `snow dcm plan` / `snow dcm deploy` with built-in parallelism
- **dbt Projects on Snowflake** — native dbt execution with GitHub Actions integration, parallel model builds

Both eliminate the serial-migration bottleneck entirely because they're declarative (desired-state) rather than imperative (migration-file-ordered). Worth evaluating as you mature your DevOps posture.

**Our recommendation:** Option A is a same-day fix. Option B pairs well with it. Option C is the strategic direction if you're open to a tooling shift.

---

## 4. Workday Migration (RAAS via SnapLogic)

You're correct — the **Openflow Workday connector is truncate-and-load only** (no incremental). It uses the RaaS API under the hood and only supports advanced reports in JSON format. So your decision to scope extraction via Workday RAAS through SnapLogic is sound.

**Dos:**
- **Design your raw layer for SCD Type 2 from day one.** Even though RAAS delivers full snapshots, land them with `_LOADED_AT` timestamps and build your SCD2 tracking in the curated layer (Dynamic Tables handle this well). This gives you full history regardless of source limitations.
- **Abstract the Workday source behind views/Dynamic Tables immediately.** When you cut over to Workday Student, downstream consumers won't need to change — only the raw-layer landing zone shifts.
- **Use staged rollout:** Run SnapLogic → Snowflake in parallel with your current system for a validation period before cutover.
- **Plan for schema drift.** Workday Student will have different report schemas than your current SIS. Build your pipelines to handle schema evolution (Snowflake's INFER_SCHEMA + schema-on-read patterns help here).

**Don'ts:**
- **Don't build tight coupling to current Workday field names** in your curated/semantic layers. Map to canonical entity names (student, enrollment, course) that survive the Student migration.
- **Don't skip data validation contracts.** Set up row-count and freshness checks on every RAAS load — SnapLogic can fail silently.
- **Don't over-index on Openflow for Workday right now.** The connector's truncate-and-load model means large Workday reports get fully reloaded every sync. At your data volumes, SnapLogic with incremental RAAS reports + merge logic will be more efficient and gives you finer control.

---

## 5. Prod-to-Dev Data Sync

**We'd strongly recommend Snowflake database replication over the S3 cross-bucket approach.** Here's why:

| | Database Replication | S3 Cross-Bucket |
|---|---|---|
| Edition requirement | Enterprise (you have this) | N/A |
| Setup complexity | ~10 SQL statements | S3 replication rules, IAM roles, external stages, COPY INTO pipelines |
| Data freshness | Scheduled (as frequent as you want) | Depends on replication lag + pipeline trigger |
| Consistency | Transactionally consistent snapshot | File-level, no transactional guarantee |
| Maintenance | Zero — Snowflake manages it | You maintain IAM, bucket policies, pipeline code |
| Cost | Replication compute (minimal for periodic refresh) | S3 transfer + storage + compute for COPY INTO |

**How it works for your PROD → DEV pattern:**

```sql
-- In PROD account (one-time setup):
CREATE REPLICATION GROUP prod_to_dev
  OBJECT_TYPES = DATABASES
  ALLOWED_DATABASES = PROD_DB_A, PROD_DB_B
  ALLOWED_ACCOUNTS = your_org.dev_account;

-- In DEV account (one-time setup):
CREATE REPLICATION GROUP prod_to_dev
  AS REPLICA OF your_org.prod_account.prod_to_dev;

-- Periodic refresh (schedule or trigger manually):
ALTER REPLICATION GROUP prod_to_dev REFRESH;
```

You can automate the refresh on a schedule using `REPLICATION_SCHEDULE` on the primary group, or trigger it via a task/CI step.

**Important note:** The replicated databases in DEV will be read-only secondaries. If your devs need write access, the pattern is:
1. Replicate to DEV account
2. Clone the replicated database: `CREATE DATABASE dev_working_copy CLONE replicated_db;`
3. Devs work against the clone (full read-write)
4. On next refresh cycle, re-clone

This gives you fresh prod data in DEV without any S3 plumbing, IAM headaches, or file-format concerns.

---

## 6. Remaining Slides

Happy to do this async — we can annotate the remaining sections and send back commentary via email, or if there are specific sections you'd like to dig into, let us know which ones and we'll prioritize those. Also open to a 30-min follow-up call if that's easier to schedule than the full group.

---

Let us know if any of these need deeper treatment or if you'd like to jump on a call for any specific topic. Happy to go as deep as needed.

Best,
Steve, Dana & Sam
