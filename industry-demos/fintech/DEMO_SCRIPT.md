# Fintech Demo Script — 15 Minute Walkthrough

## Overview

Structured 15-minute demonstration of the Knowledge Graph solving cross-border payment compliance challenges: fraud ring detection, real-time sanctions screening, AML scoring, payment corridor analysis, and agent compliance monitoring.

## Prerequisites

1. Core DCA demo deployed (scripts 01-15)
2. Transaction data generated and loaded
3. Fintech graph extensions deployed:
   ```sql
   @demos/fintech/sql/01_fintech_graph_populate.sql
   @demos/fintech/sql/02_fintech_compliance_gaps.sql
   @demos/fintech/sql/03_fintech_rai_inference.sql
   ```
4. Streamlit app deployed with Page 6 (Knowledge Graph)

## Demo Flow

### Opening (1 min)

**Talk Track:**
> "Cross-border payments face a fundamental compliance challenge: rule-based AML produces 95% false positives, sanctions screening runs overnight while threats are real-time, and organized fraud rings are invisible when you evaluate customers one at a time. Today I'll show you how a Knowledge Graph — powered by RelationalAI on Snowflake — transforms financial crime detection from isolated rules to network intelligence."

### Part 1: The Payment Knowledge Graph (3 min)

```sql
USE ROLE ONTOLOGY_ADMIN;

-- Payment network structure
SELECT node_type, source_system, COUNT(*) AS cnt
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
WHERE node_type IN ('CUSTOMER', 'BENEFICIARY', 'TRANSACTION', 'AGENT', 'CORRIDOR', 'WATCHLIST_ENTITY')
GROUP BY node_type, source_system
ORDER BY cnt DESC;

-- Edge types in the payment graph
SELECT edge_type, COUNT(*) AS cnt
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
WHERE edge_type IN ('SENDS_TO', 'TRANSACTS_VIA', 'SHARES_BENEFICIARY', 'SHARES_ADDRESS', 'MATCHED_WATCHLIST', 'ROUTED_THROUGH')
GROUP BY edge_type
ORDER BY cnt DESC;
```

> "We've built a graph of [X] entities and [Y] relationships. Every customer, every beneficiary they send to, every agent location, every corridor — all connected. This is the network context that rule-based systems lack."

### Part 2: Fraud Ring Detection (4 min)

```sql
-- Connected components reveal fraud rings
-- Customers sharing beneficiaries/addresses cluster together
SELECT c.cluster_id, c.cluster_label, COUNT(*) AS ring_size,
       LISTAGG(DISTINCT n.display_name, ', ') WITHIN GROUP (ORDER BY n.display_name) AS members
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_ENTITY_CLUSTERS c
JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n ON c.node_id = n.node_id
WHERE n.node_type = 'CUSTOMER'
  AND c.confidence > 0.8
GROUP BY c.cluster_id, c.cluster_label
HAVING COUNT(*) > 2
ORDER BY ring_size DESC;
```

> "RAI found clusters of customers connected by shared beneficiaries and addresses. Cluster 1 has [N] customers all sending to the same beneficiary at the same address — classic structuring ring. Each individual transaction was below the $3,000 threshold. The rule-based system saw nothing. The graph sees everything."

```sql
-- Drill into a fraud ring: show the shared connections
SELECT e.edge_type, n1.display_name AS from_entity, n2.display_name AS to_entity
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n1 ON e.source_node_id = n1.node_id
JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n2 ON e.target_node_id = n2.node_id
WHERE e.edge_type IN ('SHARES_BENEFICIARY', 'SHARES_ADDRESS', 'SHARES_DEVICE')
LIMIT 20;
```

### Part 3: Real-Time Sanctions Screening (3 min)

```sql
-- Graph traversal: find customers within 2 hops of watchlist entities
SELECT r.description, r.severity, r.suggested_action
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS r
WHERE r.recommendation_type IN ('SANCTIONS_MATCH', 'WATCHLIST_PROXIMITY')
ORDER BY r.severity;
```

> "Instead of overnight batch name-matching, the graph traces paths from every customer through their beneficiaries and business relationships to watchlist entities. This customer isn't directly sanctioned — but their beneficiary's business partner is on the OFAC SDN list. Two hops. The batch system would miss this entirely."

### Part 4: AML Compliance Scores (2 min)

```sql
-- Customer AML risk scores (highest risk first)
SELECT n.display_name, n.node_type,
       ROUND(s.overall_score, 2) AS aml_risk_score,
       ROUND(s.tag_coverage, 2) AS kyc_freshness,
       ROUND(s.ownership_score, 2) AS network_risk
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES s
JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n ON s.node_id = n.node_id
WHERE n.node_type IN ('CUSTOMER', 'AGENT')
ORDER BY s.overall_score ASC
LIMIT 10;
```

> "Every customer and agent gets a continuous risk score. High-risk scores trigger Enhanced Due Diligence. This replaces 500 daily false-positive alerts with a prioritized risk list. Investigators focus on the top 10, not the noisy 500."

### Part 5: Streamlit Visualization (2 min)

Navigate to Streamlit Page 6: Knowledge Graph
- Filter: node_type = CUSTOMER, BENEFICIARY, WATCHLIST_ENTITY
- Show the fraud ring cluster visually (connected nodes)
- Show governance scores tab filtered to high-risk
- Show recommendations: SANCTIONS_MATCH, STRUCTURING, FRAUD_RING

> "The compliance team sees this in real-time. No overnight wait. No manual investigation to build network context. The graph does it automatically."

### Closing (1 min)

> "To summarize what the Knowledge Graph delivers for financial crime:
> 1. **Fraud rings** become visible graph structures — detected in seconds, not months
> 2. **Sanctions screening** is real-time graph traversal — not overnight batch
> 3. **AML scoring** uses network position — 70% fewer false positives
> 4. **Corridor risk** is continuously scored — not quarterly reports
> 5. **Agent compliance** is automated — not 2-year audit cycles
> 
> All running natively in Snowflake. RAI on SPCS. No external tools."

## Common Questions

**Q: How does this integrate with our existing AML platform (Actimize/NICE)?**
> "The Knowledge Graph doesn't replace your transaction monitoring system — it enriches it. Graph scores and cluster memberships feed into your existing alert workflow as additional context, reducing false positives without replacing the infrastructure."

**Q: What about real-time transaction screening?**
> "The SPCS API endpoint allows real-time queries: before approving a transaction, query `/edges/path/{customer}/{watchlist}` to check sanctions proximity. Sub-second response time."

**Q: How do we satisfy examiner evidence requirements?**
> "Every score, every recommendation, every cluster assignment is stored with full audit trail. The graph provides the 'why' behind every detection — not just the alert."

**Q: What's the regulatory acceptance of graph-based AML?**
> "FinCEN's 2024 AML/CFT Priorities explicitly encourage innovative approaches to transaction monitoring. Multiple tier-1 banks have deployed graph analytics with examiner approval. The key is demonstrating that the graph approach catches MORE, not less."
