# DCIM Demo Script — 30-Minute Walkthrough

> A structured presentation demonstrating how Snowflake unifies ServiceNow, Workday, Network Observability, and Siemens Desigo CC into a real-time data center operations platform.

---

## Prerequisites

- All deploy phases (1–6) completed successfully
- Streamlit Command Center running
- RAI SPCS service healthy
- At least one active incident in the system

---

## Part 1: Opening (1 minute)

### Talk Track

> "Data centers cost millions per minute in downtime. When a critical switch fails at 2 AM, three questions determine whether you resolve in minutes or hours:
>
> 1. *What* is actually failing — and what's the blast radius?
> 2. *Who* is qualified, on-shift, and physically close enough to fix it?
> 3. *When* did the degradation start — and what changed?
>
> Today, these questions require searching three different systems. We're going to show you a platform that answers all three in under 5 seconds."

---

## Part 2: Governed Infrastructure Platform (3 minutes)

### Talk Track

> "Let's start with what Snowflake gives us as a foundation — not just a data lake, but a governed, tagged, access-controlled platform."

### Demo Steps

**Show the three source schemas:**

```sql
SHOW SCHEMAS IN DATABASE DCA_DEMO LIKE 'RAW%';
```

**Show object tags on a sensitive table:**

```sql
SELECT *
FROM TABLE(DCA_DEMO.INFORMATION_SCHEMA.TAG_REFERENCES(
    'DCA_DEMO.RAW_DEV.WORKDAY_DCIM.TECHNICIANS', 'TABLE'
));
```

**Demonstrate masking in action:**

```sql
-- As DCA_ANALYST: full access
USE ROLE DCA_ANALYST;
SELECT technician_id, first_name, last_name, email, phone
FROM DCA_DEMO.CURATED_DEV.DIM_TECHNICIAN
LIMIT 5;

-- As DCA_NOC: PII masked
USE ROLE DCA_NOC;
SELECT technician_id, first_name, last_name, email, phone
FROM DCA_DEMO.CURATED_DEV.DIM_TECHNICIAN
LIMIT 5;
```

**Show Dynamic Table freshness:**

```sql
SELECT name, target_lag, refresh_mode, 
       DATEDIFF('second', last_refresh_time, CURRENT_TIMESTAMP()) AS seconds_since_refresh
FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLES())
WHERE schema_name = 'CURATED_DEV'
ORDER BY target_lag;
```

### Key Message

> "Every column is tagged, every access is audited, and data freshness is declarative — not a cron job someone hopes is still running."

---

## Part 3: SCD6 Time Travel (4 minutes)

### Talk Track

> "When an incident occurs, the first question from the post-mortem is always: 'What changed?' In most environments, that's a multi-day investigation. With SCD Type 6 in our raw layer, it's a single procedure call."

### Demo Steps

**Pick a switch with state changes:**

```sql
SELECT switch_id, COUNT(*) AS state_changes
FROM DCA_DEMO.RAW_DEV.SERVICENOW.SWITCHES
WHERE _VALID_TO IS NOT NULL
GROUP BY switch_id
ORDER BY state_changes DESC
LIMIT 5;
```

**Call the Time Travel procedure:**

```sql
CALL DCA_DEMO.GOVERNANCE.SP_DCIM_TIME_TRAVEL(
    'SWITCH',
    '<switch_id from above>',
    DATEADD('day', -90, CURRENT_TIMESTAMP()),
    CURRENT_TIMESTAMP()
);
```

**Show drift detection:**

```sql
SELECT switch_id, 
       ORIGINAL_FIRMWARE_VERSION,
       CURRENT_FIRMWARE_VERSION,
       _VALID_FROM AS last_change_date
FROM DCA_DEMO.RAW_DEV.SERVICENOW.SWITCHES
WHERE _VALID_TO IS NULL
  AND CURRENT_FIRMWARE_VERSION != ORIGINAL_FIRMWARE_VERSION
LIMIT 10;
```

### Key Message

> "Every entity in this platform has a complete, queryable history. Current state, historical state at any point, and original deployment state — all in one row, no Time Travel retention limits."

---

## Part 4: Real-Time Telemetry (3 minutes)

### Talk Track

> "Let's look at what's happening right now in our data centers. Telemetry flows in at 5-minute intervals — 500K port metrics, 100K switch health readings, 50K environmental sensors per week."

### Demo Steps

**Current switch health overview:**

```sql
SELECT dc.campus_name, 
       COUNT(DISTINCT sh.switch_id) AS switches,
       AVG(sh.cpu_percent) AS avg_cpu,
       MAX(sh.temperature_c) AS max_temp,
       SUM(CASE WHEN sh.cpu_percent > 80 THEN 1 ELSE 0 END) AS hot_switches
FROM DCA_DEMO.CURATED_DEV.FACT_SWITCH_HEALTH sh
JOIN DCA_DEMO.CURATED_DEV.DIM_SWITCH s ON sh.switch_id = s.switch_id
JOIN DCA_DEMO.CURATED_DEV.DIM_DATA_CENTER dc ON s.campus_id = dc.campus_id
WHERE sh.collected_at > DATEADD('hour', -1, CURRENT_TIMESTAMP())
GROUP BY dc.campus_name
ORDER BY hot_switches DESC;
```

**Active alerts with equipment context:**

```sql
SELECT a.alert_id, a.severity, a.threshold_type,
       s.model AS switch_model, dc.campus_name,
       a.triggered_at
FROM DCA_DEMO.CURATED_DEV.FACT_ALERTS a
JOIN DCA_DEMO.CURATED_DEV.DIM_SWITCH s ON a.switch_id = s.switch_id
JOIN DCA_DEMO.CURATED_DEV.DIM_DATA_CENTER dc ON s.campus_id = dc.campus_id
WHERE a.status = 'ACTIVE'
ORDER BY a.severity, a.triggered_at DESC
LIMIT 10;
```

### Key Message

> "Telemetry without CMDB context is just noise. By joining to our infrastructure dimension, every alert immediately tells you *what* it is, *where* it is, and *who* is responsible."

---

## Part 5: Critical Maintenance Gap Detection (5 minutes)

### Talk Track

> "Now for the intelligence layer. We score every switch by composite risk: 40% error rate from telemetry, 30% certification gap from Workday, and 30% SLA tier from ServiceNow. This is the cross-system insight that no single tool can provide."

### Demo Steps

**Show the risk scoring formula in action:**

```sql
CALL DCA_DEMO.GOVERNANCE.SP_DCIM_RISK_SCORING();
```

**View top-risk equipment:**

```sql
SELECT rs.switch_id, s.model, dc.campus_name,
       rs.error_rate_score, rs.cert_gap_score, rs.sla_tier_score,
       rs.composite_risk_score,
       rs.risk_category
FROM DCA_DEMO.GOVERNANCE.DCIM_RISK_SCORES rs
JOIN DCA_DEMO.CURATED_DEV.DIM_SWITCH s ON rs.switch_id = s.switch_id
JOIN DCA_DEMO.CURATED_DEV.DIM_DATA_CENTER dc ON s.campus_id = dc.campus_id
WHERE rs.risk_category = 'CRITICAL'
ORDER BY rs.composite_risk_score DESC
LIMIT 10;
```

**Certification gap detail:**

```sql
SELECT dc.campus_name, s.model,
       COUNT(DISTINCT s.switch_id) AS switches_needing_cert,
       COUNT(DISTINCT c.technician_id) AS qualified_techs,
       CASE WHEN COUNT(DISTINCT c.technician_id) = 0 THEN 'NO COVERAGE'
            WHEN COUNT(DISTINCT c.technician_id) < 2 THEN 'SINGLE POINT OF FAILURE'
            ELSE 'ADEQUATE'
       END AS coverage_status
FROM DCA_DEMO.CURATED_DEV.DIM_SWITCH s
JOIN DCA_DEMO.CURATED_DEV.DIM_DATA_CENTER dc ON s.campus_id = dc.campus_id
LEFT JOIN DCA_DEMO.CURATED_DEV.DIM_CERTIFICATION c 
    ON c.vendor = SPLIT_PART(s.model, '-', 1)
    AND c.expiry_date > CURRENT_DATE()
GROUP BY dc.campus_name, s.model
HAVING COUNT(DISTINCT c.technician_id) < 2
ORDER BY switches_needing_cert DESC;
```

### Key Message

> "This is the insight that lives between systems. ServiceNow knows the equipment. Workday knows the certifications. Neither knows you have zero qualified coverage for 47 critical switches across 3 campuses."

---

## Part 6: Nearest Qualified Technician (5 minutes)

### Talk Track

> "When an incident fires, the NOC needs to dispatch immediately. Today that's a phone tree. With graph-based dispatch, we find the technician who is certified for this equipment model, currently on shift, and physically closest — in milliseconds."

### Demo Steps

**Pick an active incident:**

```sql
SELECT incident_id, switch_id, severity, sla_tier, status
FROM DCA_DEMO.CURATED_DEV.FACT_INCIDENTS
WHERE status = 'OPEN'
  AND severity <= 2
ORDER BY created_at DESC
LIMIT 5;
```

**Run the dispatch procedure:**

```sql
CALL DCA_DEMO.GOVERNANCE.SP_DCIM_NEAREST_QUALIFIED_TECH(
    '<incident_id from above>'
);
```

**View dispatch recommendations:**

```sql
SELECT dr.incident_id, dr.recommended_technician_id,
       t.first_name || ' ' || t.last_name AS technician_name,
       dr.qualification_match, dr.shift_status,
       dr.proximity_rank, dr.overall_score
FROM DCA_DEMO.GOVERNANCE.DCIM_DISPATCH_RECOMMENDATIONS dr
JOIN DCA_DEMO.CURATED_DEV.DIM_TECHNICIAN t 
    ON dr.recommended_technician_id = t.technician_id
WHERE dr.incident_id = '<incident_id>'
ORDER BY dr.overall_score DESC;
```

**Compare to baseline:**

> "Without this system, the NOC would call the on-call phone tree — which doesn't check certifications. 35% of the time, the dispatched tech can't actually fix the equipment and has to escalate. That's 2+ hours of wasted MTTR per incident."

### Key Message

> "The graph traversal considers infrastructure hierarchy, certification qualifications, shift schedules, and physical proximity — all in one query across three source systems."

---

## Part 7: MTTR & Staff Correlation (4 minutes)

### Talk Track

> "Let's look at the macro picture. How does staffing correlate with resolution time? And how does risk weighting change the story?"

### Demo Steps

**Run MTTR analysis:**

```sql
CALL DCA_DEMO.GOVERNANCE.SP_DCIM_MTTR_ANALYSIS();
```

**View risk-weighted MTTR by campus:**

```sql
SELECT campus_name, 
       avg_mttr_hours,
       risk_weighted_mttr_hours,
       total_incidents,
       certified_tech_ratio,
       avg_shift_coverage_pct
FROM DCA_DEMO.GOVERNANCE.DCIM_MTTR_METRICS
ORDER BY risk_weighted_mttr_hours DESC;
```

**Use semantic view for natural-language query:**

```sql
-- Semantic view: plain-English analytics
SELECT *
FROM DCA_DEMO.SEM_DEV.DCIM_ANALYTICS.DCIM_SYSTEM_UPTIME_VS_STAFF_AVAILABILITY
LIMIT 20;
```

### Key Message

> "Risk-weighted MTTR tells a different story than raw averages. Campus A might have lower average MTTR — but all their fast resolutions are on low-risk, well-covered equipment. Their *critical* equipment takes 3x longer because of certification gaps."

---

## Part 8: Acquisition Integration (5 minutes)

### Talk Track

> "Six months ago, we acquired a competitor running 2,000 data centers on Siemens Desigo CC. Different naming conventions — German-influenced field names. Different rack IDs for the same physical hardware. Different maintenance workflows. Let me show you how Snowflake's Knowledge Graph resolves this without a multi-year data migration..."

### Demo Steps

**Show the scale of the acquisition:**

```sql
-- 2,000 net-new facilities from Siemens
SELECT REGION, BUILDING_TYPE, COUNT(*) AS facilities, SUM(RACK_CAPACITY) AS total_rack_capacity
FROM CURATED_DEV.SIEMENS_DCIM.DIM_FACILITY
GROUP BY REGION, BUILDING_TYPE
ORDER BY facilities DESC;
```

> "2,000 data centers, 100,000 racks, half a million BMS sensors — all flowing into Snowflake within weeks of close. No ETL rewrite. No schema migration. Just load and govern."

**Show entity resolution in action:**

```sql
-- Racks that exist in BOTH systems (same physical asset, different IDs)
SELECT
    e.edge_type,
    e.weight AS confidence,
    src.display_name AS siemens_rack,
    tgt.display_name AS servicenow_rack,
    e.properties:match_method::VARCHAR AS match_method
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES src ON e.source_node_id = src.node_id
JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES tgt ON e.target_node_id = tgt.node_id
WHERE e.edge_type IN ('SAME_AS', 'CANDIDATE_SAME_AS')
AND src.source_system = 'SIEMENS_DCIM'
LIMIT 20;
```

> "The Knowledge Graph automatically identified 5,000+ rack matches — some confirmed manually, some discovered algorithmically by matching capacity and location attributes."

**Show governance gaps on acquired estate:**

```sql
-- Facilities not yet integrated into ServiceNow governance
SELECT GOVERNANCE_STATUS, COUNT(*) AS facilities, 
       ROUND(AVG(MAPPING_COMPLETENESS_PCT), 1) AS avg_mapping_pct
FROM DCA_DEMO.GOVERNANCE.DCIM_ACQUISITION_INTEGRATION_STATUS
GROUP BY GOVERNANCE_STATUS;
```

> "We can see exactly which of the 2,000 acquired facilities are fully governed, partially mapped, or still ungoverned. This drives the integration roadmap — highest risk facilities get migrated first."

**Show cross-platform risk:**

```sql
-- Unified risk view: both estates in one query
SELECT SOURCE_SYSTEM, RISK_LEVEL, COUNT(*) AS entities, 
       ROUND(AVG(RISK_SCORE), 1) AS avg_score
FROM DCA_DEMO.GOVERNANCE.DCIM_CROSS_PLATFORM_RISK
GROUP BY SOURCE_SYSTEM, RISK_LEVEL
ORDER BY SOURCE_SYSTEM, avg_score DESC;
```

> "One view. Both estates. The NOC sees everything — whether it's a ServiceNow switch with a cert gap or a Siemens facility with cooling degradation. No tab-switching between systems."

---

## Part 9: Command Center (5 minutes)

### Talk Track

> "Everything we've shown in SQL is also available through the Streamlit Command Center — designed for the NOC Director who lives in this view 8 hours a day."

### Demo Steps

1. **Open Streamlit Command Center**
2. **Infrastructure Health tab** — Show campus-level heatmap of risk scores
3. **Active Incidents panel** — Show real-time incident list with dispatch status
4. **Technician Dispatch** — Click an incident, show recommended technicians
5. **Time Travel Explorer** — Select a switch, show state change timeline
6. **Certification Matrix** — Show coverage gaps by campus × model

### Closing

> "This platform turns four disconnected systems into a unified operations intelligence layer. The data center operator goes from reactive phone-tree dispatch to proactive, risk-aware, graph-optimized operations — all on Snowflake-native capabilities.
>
> Questions?"

---

## Objection Handling

| Objection | Response |
|-----------|----------|
| "We already have ServiceNow dashboards" | "ServiceNow shows you *what* is broken. It can't tell you *who* is qualified and available — that requires Workday data it doesn't have." |
| "Why not build this in ServiceNow?" | "ServiceNow isn't designed for sub-minute telemetry ingestion or graph-based dispatch optimization. Snowflake handles the analytical workload while ServiceNow remains the system of record." |
| "What about the RAI dependency?" | "RAI is optional. The risk scoring, MTTR analysis, and SCD6 time travel all work without it. RAI adds the graph-based dispatch optimization as an enhancement." |
| "How long to implement?" | "Phase 1 (governed data lake) is deployable with existing Fivetran/Airbyte connectors. The analytical layer builds incrementally on top." |
| "What about data freshness SLAs?" | "Dynamic Tables provide declarative freshness — you set target lag, Snowflake guarantees it. No cron jobs, no 'did the ETL run?' questions." |
| "How do you handle the Siemens acquisition data?" | "We load Siemens data as-is into Snowflake — no schema migration, no ETL rewrite. The Knowledge Graph resolves overlapping rack IDs through entity resolution edges, and governance scoring flags ungoverned facilities for prioritized integration." |
