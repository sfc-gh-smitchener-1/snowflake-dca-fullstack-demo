# DCIM — 3-Hour Workshop Facilitation Guide

> A structured workshop for data center operators evaluating unified operations analytics on Snowflake.

---

## Workshop Overview

| Item | Detail |
|------|--------|
| **Duration** | 3 hours (with two 10-minute breaks) |
| **Format** | Discovery → Architecture → Live Demo → Whiteboard → ROI |
| **Audience** | VP Infrastructure, NOC Director, Facilities Mgr, Data/Platform Engineering leads |
| **Outcome** | Agreed pain points, architecture direction, ROI model, next-step commitment |
| **Materials** | Whiteboard/Miro, printed DISCOVERY.md, laptop with demo environment |

---

## Audience Profiles

| Role | Cares About | Skeptical Of | Win Condition |
|------|-------------|--------------|---------------|
| **VP Infrastructure** | Uptime SLAs, capital efficiency, board-level metrics | New platforms that add complexity | "Reduces audit findings AND improves MTTR" |
| **NOC Director** | Dispatch speed, shift coverage, incident resolution | Anything that adds steps to incident workflow | "Gets me the right tech in 30 seconds" |
| **Facilities Manager** | Power/cooling capacity, maintenance windows, safety | Automation replacing human judgment | "Shows me coverage gaps before they matter" |
| **Data Engineer** | Pipeline reliability, schema stability, freshness SLAs | Yet another ETL tool to maintain | "Dynamic Tables handle refresh; I set target lag" |
| **Enterprise Architect** | Integration patterns, vendor lock-in, governance | SPCS/RAI complexity | "Core value works without RAI; graph is additive" |

---

## Agenda

| Time | Block | Duration | Lead |
|------|-------|----------|------|
| 0:00 | Opening & Introductions | 10 min | Facilitator |
| 0:10 | **Discovery: The Three Silos** | 40 min | Facilitator + Group |
| 0:50 | *Break* | 10 min | — |
| 1:00 | **Architecture Deep-Dive** | 35 min | Solution Architect |
| 1:35 | **Live Demo** | 30 min | Demo Engineer |
| 2:05 | *Break* | 10 min | — |
| 2:15 | **Whiteboard: Your Environment** | 25 min | Facilitator + Group |
| 2:40 | **ROI Framework** | 15 min | Facilitator |
| 2:55 | **Next Steps & Close** | 5 min | Account Lead |

---

## Block 1: Discovery (40 minutes)

### Objective

Surface pain points in the customer's own words. Map to the three-silo pattern.

### Discovery Questions

**Infrastructure Operations:**
1. "Walk me through what happens when a P1 switch failure occurs at 2 AM. Who gets called? How do they know what to do?"
2. "How do you currently know if a technician is certified for a specific equipment model?"
3. "When was the last time a change caused an incident? How long did root-cause take?"
4. "How do you track firmware drift from baseline across your fleet?"

**Workforce Management:**
5. "How do you ensure shift coverage for critical certifications at every campus?"
6. "When a certification expires, how quickly does that propagate to dispatch eligibility?"
7. "Can you tell me right now which campuses have single-point-of-failure cert coverage?"

**Telemetry & Monitoring:**
8. "When an alert fires, how do you establish CMDB context (what is this device, where is it, who owns it)?"
9. "How do you correlate telemetry degradation patterns with upcoming maintenance windows?"
10. "If I asked 'which switches are trending toward failure?' — could you answer today?"

### Facilitation Tips

- Write each pain point on a sticky note / Miro card
- Group into: **Dispatch**, **Visibility**, **Compliance**, **Capacity**
- Ask "What does this cost you?" for each group — even rough estimates
- Reference DISCOVERY.md pain points to validate or extend

### Expected Outcomes

Customers typically identify 4-6 of the 8 pain points from DISCOVERY.md unprompted. The facilitator fills gaps by sharing anonymized examples:

> "Other data center operators we work with report that 35% of P1 dispatches require re-assignment because the NOC lacks certification visibility. Does that resonate?"

---

## Block 2: Architecture Deep-Dive (35 minutes)

### Objective

Show the three-stage architecture evolution. Position Snowflake-native capabilities as the foundation.

### Structure

1. **Current state** (5 min) — Sketch customer's architecture on whiteboard
2. **Stage 1: Governed Data Lake** (10 min) — Dynamic Tables, tags, masking
3. **Stage 2: Cross-System Intelligence** (10 min) — Risk scoring, MTTR, dispatch
4. **Stage 3: Predictive Operations** (5 min) — ML, automation (future state)
5. **Q&A** (5 min)

### Key Points to Emphasize

- "Dynamic Tables are declarative — you define the transform and the freshness target. Snowflake handles scheduling, retries, and dependency ordering."
- "SCD6 is in *our* raw layer, not Snowflake Time Travel. No retention limit, no storage premium, full state reconstruction forever."
- "The graph is a *projection* of Snowflake data, not a copy. RAI reads from curated views. If RAI is unavailable, everything else still works."
- "Governance is baked in from day one — not bolted on after the fact."

### Architecture Questions to Ask

- "Which of your source systems already has a Fivetran/Airbyte connector?"
- "What's your current Snowflake edition? (Enterprise needed for Dynamic Tables)"
- "Do you have existing RBAC roles we should align with?"
- "What's your telemetry volume? (Helps size Snowpipe Streaming)"

---

## Block 3: Live Demo (30 minutes)

Follow DEMO_SCRIPT.md Parts 2–7 (skip Opening and Command Center — save Command Center for after whiteboard to close strong).

### Demo Customization

Before the workshop, configure the demo data to match the customer:
- Set campus names to their actual locations (or similar)
- Use their switch vendor names in the model field
- Match their shift patterns (12-hour vs. 8-hour)
- Use their SLA tier naming convention

---

## Block 4: Whiteboard Exercise (25 minutes)

### Objective

Map the demo architecture to the customer's specific environment.

### Exercise: "Your Three Systems"

Draw three columns on the whiteboard:

| Their ServiceNow Equivalent | Their Workday Equivalent | Their Telemetry Stack |
|---|---|---|
| (Customer fills in) | (Customer fills in) | (Customer fills in) |

### Guiding Questions

1. "What's your system of record for equipment inventory?"
2. "Where do technician certifications live today?"
3. "What generates your operational alerts?"
4. "What cross-system joins do you wish you could do but can't?"

### Outcome

A customer-specific version of the Architecture diagram with their system names, their table names, and their identified linkage keys.

---

## Block 5: ROI Framework (15 minutes)

### Quantification Model

| Metric | How to Measure | Typical Improvement |
|--------|---------------|-------------------|
| **MTTR reduction** | Avg resolution time for P1/P2 | 35-45% reduction |
| **Dispatch accuracy** | % first-try correct dispatch | 65% → 92% |
| **Audit prep time** | Person-weeks per SOC2/ISO audit | 6 weeks → 2 days |
| **Cert lapse events** | Annual uncovered-equipment-days | 90% reduction |
| **Change-induced incidents** | Incidents caused by changes/year | 80% reduction |

### ROI Calculation Template

```
Annual P1 incidents:               ___
Avg downtime cost per minute:      $___
Current avg MTTR (hours):          ___
Expected MTTR improvement:         35%

Avoided downtime = incidents × (current_mttr - improved_mttr) × 60 × cost_per_min
                 = ___ × ___ × 60 × $___
                 = $___/year
```

### Additional Value Drivers

- **Headcount avoidance**: Better dispatch means fewer redundant technicians needed
- **Insurance/compliance**: Demonstrable controls may reduce premiums
- **Capital efficiency**: Proactive maintenance extends equipment lifecycle
- **Retention**: Technicians prefer intelligent dispatch over fire-drill culture

---

## Block 6: Next Steps & Close (5 minutes)

### Standard Next Steps

1. **Technical Proof of Concept** — Load customer's anonymized data into the platform
2. **Data Readiness Assessment** — Evaluate source system connectors and data quality
3. **RBAC Workshop** — Map existing roles to DCA governance model
4. **Phase 1 Deployment** — Governed data lake with Dynamic Tables (first deliverable)

### Success Criteria to Agree

Ask the group: "If we built this for your environment, what would success look like in 90 days?"

Typical answers:
- "I can answer 'who is qualified and closest?' in under 10 seconds"
- "Zero certification lapses go undetected"
- "Post-mortem time-to-root-cause drops from days to minutes"
- "Audit evidence is a query, not a project"

---

## Facilitator Notes

### Common Pitfalls

| Pitfall | Mitigation |
|---------|-----------|
| Demo environment down | Have screenshots/video backup; lead with whiteboard |
| "We don't use ServiceNow" | Architecture is source-agnostic; swap in their ITSM tool |
| One person dominates | Direct questions to quieter roles: "NOC perspective?" |
| Conversation goes too deep on one topic | "Let's capture that for follow-up and keep moving" |
| Skepticism about RAI/graph | Emphasize: "Core platform works without RAI. Graph adds dispatch optimization as an enhancement." |

### Pre-Workshop Checklist

- [ ] Demo environment running and validated
- [ ] Customer's system names researched (for whiteboard exercise)
- [ ] Printed copies of DISCOVERY.md (one per attendee)
- [ ] Whiteboard markers (4 colors)
- [ ] ROI template pre-filled with industry averages
- [ ] Follow-up email template ready with next-step options
