# Fintech Cross-Border Payments — Workshop Facilitation Guide

> **Knowledge Graph-Powered Financial Crime Detection** — "From 95% False Positives to Network-Based Intelligence"

## Session Details

| Field | Detail |
|-------|--------|
| **Duration** | 3 hours |
| **Format** | Whiteboard-led workshop with live Knowledge Graph demo |
| **Audience** | CCO, FIU leadership, Fraud Operations, Agent Compliance, Data Engineering |

## Pain Points — Workshop Coverage Map

| # | Pain Point | Workshop Segment | Live Demo Moment |
|---|-----------|-----------------|-----------------|
| 1 | AML 95% false positives | Seg 1 (Cost of noise), Seg 2 (Network scoring) | Show graph-based scoring vs rule-based: same customer, different verdict |
| 2 | Invisible fraud rings | Seg 1 (Blind spots), Seg 3 (Connected components demo) | Show 15-customer ring sharing same beneficiary — invisible to rules |
| 3 | Sanctions batch lag | Seg 1 (Risk window), Seg 3 (Graph traversal demo) | Show 2-hop path from customer to OFAC entity in milliseconds |
| 4 | Corridor risk opacity | Seg 2 (Corridor model), Seg 3 (Scoring demo) | Show corridor risk heatmap with volume anomalies |
| 5 | Agent compliance manual | Seg 2 (Agent graph), Seg 3 (Agent score demo) | Show agent compliance score with contributing factors |

## Pre-Work

| Item | Owner | Purpose |
|------|-------|---------|
| Current AML alert volume and SAR conversion rate | Customer | Quantifies false positive problem |
| Top 5 corridors by volume and risk classification | Customer | Seeds corridor discussion |
| Recent regulatory findings/MRAs (if shareable) | Customer | Contextualizes urgency |
| Agent network size and current audit cycle | Customer | Informs agent scoring model |
| Knowledge Graph Overview (1-pager) | Snowflake | Context on approach |

## Agenda

| Time | Segment | Duration |
|------|---------|----------|
| 0:00 | **Segment 1** — The Problem: Quantifying Compliance Gaps | 30 min |
| 0:30 | **Segment 2** — The Pattern: Knowledge Graph for Financial Crime | 45 min |
| 1:15 | BREAK | 15 min |
| 1:30 | **Segment 3** — The Proof: Live Demo (Fraud Rings, Sanctions, Scoring) | 45 min |
| 2:15 | **Segment 4** — The Path: 30/60/90 Roadmap | 30 min |
| 2:45 | **Segment 5** — Pilot Selection | 15 min |
| 3:00 | CLOSE | — |

---

## Segment 1 — The Problem: Quantifying Compliance Gaps (30 min)

### Opening (5 min)

**Talk Track:**
> "Your compliance team processes 500+ AML alerts per day. Your SAR conversion rate is under 5%. That means 95% of the work your investigators do produces no regulatory value. Meanwhile, actual fraud rings operate undetected because each individual transaction looks normal. Sanctions screening runs overnight — which means there's a 12-24 hour window every day where a newly sanctioned entity can still transact. These aren't hypothetical risks — they're the gaps that produce consent orders."

### Cost Quantification Exercise (25 min)

Walk through each gap. For each:
1. What's the current metric? (alert volume, FP rate, screening lag, audit cycle)
2. What's the annual cost? (ops team, fraud losses, regulatory fines)
3. What would a 70% improvement deliver? (headcount redeploy, loss prevention, exam readiness)

Whiteboard format — 5 lanes:
- AML Noise ($ cost of false positives)
- Fraud Losses ($ undetected rings)
- Sanctions Risk ($ potential OFAC fines)
- Corridor Blindness (regulatory findings)
- Agent Oversight (consent order risk)

---

## Segment 2 — The Pattern: Knowledge Graph for Financial Crime (45 min)

### Network Intelligence Concept (15 min)

Whiteboard the graph model:
- Draw CUSTOMER in center
- Add SENDS_TO edge to BENEFICIARY
- Add SHARES_BENEFICIARY edge to another CUSTOMER
- Now draw 10 more CUSTOMERS all connected to same BENEFICIARY → "That's a fraud ring"
- Add WATCHLIST_ENTITY 2 hops away → "That's a sanctions traversal"
- Add AGENT node → "That's agent compliance scoring"

> "Rules ask: 'Is this transaction suspicious?' The graph asks: 'Is this customer's NETWORK suspicious?' That's the paradigm shift."

### Scoring Models (15 min)

Present the three scoring models:
1. Customer AML Score: network position (30%) + behavior (25%) + KYC (20%) + corridor (15%) + watchlist proximity (10%)
2. Agent Compliance Score: volume anomaly (25%) + SAR rate (25%) + KYC completion (20%) + structuring (20%) + history (10%)
3. Corridor Risk Score: sanctions adjacency (30%) + volume deviation (25%) + concentration (20%) + SAR density (15%) + regulatory designation (10%)

### Architecture Diagram (15 min)

Whiteboard: Sources → Knowledge Graph (Nodes + Edges in Snowflake) → **Two query engines** (Snowflake-native recursive CTEs, default; Neo4j sidecar on SPCS, optional) → Outputs (Scores, Rings, Traversals, Reports).

> "The graph of record lives in two Snowflake tables. Two engines read from it. Snowflake-native handles fraud-ring detection, AML scoring, corridor and agent scoring — all in pure SQL with no sidecar to operate. The Neo4j sidecar steps in for the deep traversal cases — beneficial-ownership chains four or more hops to a sanctioned ultimate beneficial owner, and sub-100 ms shortest-path queries on the payment authorization path. You pick per request with a query parameter. Most customers run Snowflake-native in production and add Neo4j once they hit the deep-traversal use case."

---

## Segment 3 — The Proof: Live Demo (45 min)

### Demo 1: Fraud Ring Detection (15 min)

```sql
-- Show connected components (fraud ring clusters)
SELECT c.cluster_id, c.cluster_label, COUNT(*) AS ring_size
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_ENTITY_CLUSTERS c
JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n ON c.node_id = n.node_id
WHERE n.node_type = 'CUSTOMER' AND c.confidence > 0.8
GROUP BY c.cluster_id, c.cluster_label
HAVING COUNT(*) > 2
ORDER BY ring_size DESC;
```

> "Each cluster is a group of customers connected by shared infrastructure — same beneficiary, same address, same device. Individual transactions all under threshold. Together: clear structuring ring."

### Demo 2: Sanctions Graph Traversal (10 min)

```sql
-- Sanctions proximity: customers within N hops of watchlist
SELECT r.severity, r.description, r.suggested_action
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS r
WHERE r.recommendation_type = 'SANCTIONS_MATCH'
ORDER BY r.severity;
```

```bash
# Real-time path query at payment authorization time — pick the engine per request
curl "https://<spcs-endpoint>/edges/path/{customer_id}/{watchlist_id}?backend=snowflake"
curl "https://<spcs-endpoint>/edges/path/{customer_id}/{watchlist_id}?backend=neo4j"

# Compare both engines side-by-side (same answer, different timing)
curl "https://<spcs-endpoint>/inference/compare?endpoint=path&from={customer_id}&to={watchlist_id}"
```

> "Real-time. No batch. The graph finds indirect connections that name-matching never would. Two engines answer the same question — Snowflake-native handles 1-3 hops in tens of milliseconds without leaving the warehouse; the Neo4j sidecar handles deeper beneficial-ownership chains in sub-100 ms. The `compare` endpoint lets you prove they agree, then pick the right one for each integration point."

### Demo 3: AML Risk Scores (10 min)

```sql
-- Highest risk customers
SELECT n.display_name, s.overall_score
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES s
JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n ON s.node_id = n.node_id
WHERE n.node_type = 'CUSTOMER'
ORDER BY s.overall_score ASC LIMIT 10;
```

> "500 noisy alerts become a ranked risk list. Investigators work the top 10. The other 490 are scored low-risk with evidence."

### Demo 4: Streamlit Graph Visualization (10 min)

Page 6 → filter CUSTOMER/BENEFICIARY/WATCHLIST_ENTITY → show fraud ring cluster → show sanctions path

---

## Segment 4 — The Path: 30/60/90 (30 min)

Walk through [ROADMAP.md](ROADMAP.md).

---

## Segment 5 — Pilot Selection (15 min)

Candidate pilots:
1. Fraud ring detection on top 3 corridors (quick win, immediate loss reduction)
2. Real-time sanctions screening for new customer onboarding
3. Agent compliance scoring for top 100 highest-volume agents

Leave with: Named pilot, named owner, success criteria, 30-day milestone.

---

## Post-Workshop Deliverables

| Deliverable | Owner | Timeline |
|-------------|-------|----------|
| Whiteboard photos (Gap Map, Architecture, Pilot Plan) | Snowflake | Same day |
| AML Scoring Model documentation (completed with customer weights) | Snowflake | 3 business days |
| Knowledge Graph deployment scripts (SQL files from `demos/fintech/sql/`) | Snowflake | Same day (already in Git) |
| Streamlit dashboard demo environment (available for exploration) | Snowflake | Same day |
| Finalized 30/60/90 Roadmap with customer-specific corridors and owners | Joint | 5 business days |
| Pilot kick-off meeting | Joint | Within 1 week |

## Materials Checklist

- [ ] Whiteboard markers (multiple colors — use different colors for each compliance lane)
- [ ] Printed Pain Point Worksheets (one per attendee — 5 gaps with blank "current cost" columns)
- [ ] Printed AML Scoring Rubric (one per attendee — shows 3 scoring models)
- [ ] Printed Architecture Diagram (one per attendee — graph model)
- [ ] Laptop with Knowledge Graph demo ready:
  - [ ] Snowflake UI open to `DCA_DEMO.GOVERNANCE` schema
  - [ ] SQL worksheet with Demo 1-4 queries pre-loaded
  - [ ] Streamlit app running (verify Knowledge Graph page renders)
  - [ ] Snowflake UI tab ready for `ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS` query
  - [ ] Snowflake UI tab ready for `ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES` query
- [ ] Backup: Screenshots of Knowledge Graph Streamlit page (in case of connectivity issues)
- [ ] Video conferencing link for remote participants
- [ ] Camera/phone for whiteboard captures
- [ ] HDMI/USB-C adapter for projecting from laptop

## Facilitator Notes

### Handling Common Objections

| Objection | Response |
|-----------|----------|
| "We already have an AML platform (Actimize/NICE)" | "The graph doesn't replace your TMS — it enriches it. Graph scores feed into your existing alert workflow as additional context, reducing false positives without ripping out infrastructure." |
| "Our sanctions screening vendor handles OFAC" | "For direct name matches, yes. But beneficial ownership traversal — Entity A owns 51% of Entity B which controls Entity C on the SDN list — requires graph analysis." |
| "Regulators haven't approved graph-based AML" | "FinCEN's 2024 AML/CFT Priorities explicitly encourage innovative approaches. Multiple tier-1 banks have deployed graph analytics with examiner approval. The key is proving the graph catches MORE." |
| "We have 500K agents — this can't scale" | "The graph scores all agents continuously. That's the point — replacing the 2-year audit cycle with real-time scoring. The graph scales linearly with node count." |
| "Our data isn't ready" | "The demo maps to standard transaction data you already have. Customer, beneficiary, amount, corridor, agent — that's your core banking output." |
| "Why not just use a dedicated graph database?" | "We do — optionally. The platform ships a Neo4j sidecar for deep traversal and GDS algorithms when you need them. But for fraud-ring detection, AML scoring, and corridor/agent scoring, Snowflake-native recursive CTEs are plenty fast and have zero extra operational cost. Most workloads stay on Snowflake-native; Neo4j is reserved for the deep multi-hop sanctions and beneficial-ownership cases. Pick per request with `?backend=`." |
| "Won't running both add operational burden?" | "One container, one secret, one health check. The application code is identical because both engines implement the same `GraphBackend` interface — switching backends is a query parameter, not a code change. See `docs/GRAPH_BACKENDS.md`." |

### Key Transitions

- **Segment 1 → 2**: "We've quantified the gaps. Now let me show you the architecture that closes them."
- **Segment 2 → 3**: "That's the theory. Let's prove it works with live queries against real payment network data."
- **Segment 3 → 4**: "You've seen it work. The question is: how do we get THIS running against YOUR transaction data?"
- **Segment 4 → 5**: "The roadmap shows what's possible. Let's pick ONE thing and commit to delivering it in 30 days."
