# Fintech Cross-Border Payments — Architecture Strategy

> Target architecture using the Ontology Knowledge Graph for real-time financial crime detection, graph-based AML scoring, sanctions traversal, and agent compliance monitoring.

## Strategic Thesis

Financial crime detection fails at scale because it evaluates transactions and customers in isolation. AML rules ask "Is this transaction suspicious?" — but the real question is "Is this customer's NETWORK suspicious?" The Knowledge Graph shifts compliance from isolated rule-matching to network-based intelligence, where fraud rings become visible graph structures, sanctions screening becomes graph traversal, and compliance scoring becomes continuous and automated.

## Architecture Principles

| Principle | Fintech Application |
|-----------|-------------------|
| Network-First Detection | Graph topology (connections, clusters, paths) reveals what individual transactions cannot |
| Real-Time Traversal | Sanctions screening happens via graph query, not overnight batch matching |
| Continuous Scoring | Every customer, agent, and corridor has a live compliance score — not point-in-time |
| Automated Intelligence | RAI inference produces actionable recommendations, not just alerts |
| Regulatory Transparency | Graph provides auditable evidence trail for every detection and score |

## Architecture Evolution — Three Stages

### Stage 1: Current State (Siloed Rule-Based Compliance)

```mermaid
flowchart LR
    TXN["Transaction\nProcessing"] -->|"Batch feed"| AML["Rule-Based AML\n(95% false positive)"]
    TXN -->|"Overnight"| SANC["Sanctions Batch\n(24h lag)"]
    TXN -->|"Individual"| FRAUD["Fraud Rules\n(No network context)"]
    AML -->|"500+ daily"| INV["Manual Investigation"]
    SANC -->|"Stale hits"| INV
    FRAUD -->|"Isolated alerts"| INV
    INV -->|"30 days"| SAR["SAR Filing"]
```

### Stage 2: Knowledge Graph-Powered Compliance

```mermaid
flowchart TB
    subgraph SOURCES["TRANSACTION SOURCES"]
        CORE["Core Banking"]
        AGENTS["Agent Network"]
        DIGITAL["Digital Channels"]
        WATCHLISTS["OFAC/SDN/PEP Lists"]
    end
    subgraph GRAPH["KNOWLEDGE GRAPH (Real-Time, Graph of Record in Snowflake)"]
        NODES["CUSTOMER | BENEFICIARY | AGENT\nTRANSACTION | CORRIDOR | WATCHLIST"]
        EDGES["SENDS_TO | SHARES_ADDRESS |\nSHARES_BENEFICIARY | MATCHED_WATCHLIST |\nOPERATES_IN | ROUTED_THROUGH"]
    end
    subgraph ENGINE["GRAPH ENGINE (Snowflake-native)"]
        SF_ENG["Recursive CTEs + label propagation\n(sql/16_graph_algorithms.sql)"]
    end
    subgraph INF["GRAPH INFERENCE WORKLOADS"]
        FRAUD_RING["Fraud Ring Detection\n(Connected Components)"]
        AML_SCORE["AML Risk Scoring\n(Network Position)"]
        SANC_TRAV["Sanctions Traversal\n(1-3 hop graph query)"]
        CORRIDOR["Corridor Risk Scoring"]
        AGENT_COMP["Agent Compliance Scoring"]
    end
    subgraph OUTPUT["ACTIONABLE OUTPUT"]
        ALERTS["Prioritized Alerts\n(70% fewer false positives)"]
        SARS["Auto-Generated SAR Narratives"]
        SCORES["Continuous Compliance Scores"]
        REPORT["Regulatory Reports"]
    end
    SOURCES --> GRAPH --> ENGINE --> INF --> OUTPUT
```

The Snowflake-native engine reads directly from the `ONTOLOGY_GRAPH_NODES` / `ONTOLOGY_GRAPH_EDGES` tables and handles fraud-ring detection, AML scoring, corridor scoring, agent scoring, and sanctions traversal — including beneficial-ownership chains and shortest-path queries from a customer to a watchlist entity in the payment authorization path. Everything runs in SQL inside the warehouse. See [docs/KNOWLEDGE_GRAPH.md](../../docs/KNOWLEDGE_GRAPH.md) for the graph model and algorithms.

### Stage 3: Federated Financial Intelligence Network

```mermaid
flowchart TB
    subgraph INTERNAL["INTERNAL INTELLIGENCE"]
        GRAPH["Knowledge Graph (Nodes + Edges in Snowflake)"]
        ENG["Graph Engine\nSnowflake-native (recursive CTEs)"]
    end
    subgraph EXTERNAL["EXTERNAL INTELLIGENCE"]
        OFAC["OFAC/SDN Updates\n(Real-time ingestion)"]
        FINCEN["FinCEN 314(b)\n(Info sharing)"]
        PARTNER["Correspondent Banks\n(Shared intelligence)"]
    end
    subgraph REGULATORY["REGULATORY AUTOMATION"]
        SAR_AUTO["Auto-SAR Generation"]
        CTR["CTR Auto-Filing"]
        EXAM["Exam-Ready Evidence"]
    end
    INTERNAL --> REGULATORY
    EXTERNAL --> INTERNAL
```

## BSA/AML Compliance Mapping

| BSA/AML Requirement | Knowledge Graph Implementation |
|--------------------|-----------------------------|
| §5318(h) — AML Program | Graph-based risk assessment replaces rule-based monitoring |
| §5318(g) — SAR Filing | RAI recommendations auto-generate SAR narratives with graph evidence |
| §5318(j) — Correspondent Banking | AGENT→CORRIDOR edges with compliance scores per relationship |
| §5312 — CTR Reporting | TRANSACTION aggregation via graph: all txns > $10K per customer/day |
| OFAC — Sanctions Screening | Graph traversal: CUSTOMER → (N hops) → WATCHLIST_ENTITY |
| FATF Rec 16 — Wire Transfer Rules | TRANSACTION → BENEFICIARY edges with full originator/beneficiary data |
| FinCEN CDD Rule — Beneficial Ownership | Ownership edges traversal: ENTITY → OWNS → ENTITY → CONTROLS → ENTITY |

## Compliance Scoring Model

### Customer AML Risk Score (0.0 - 1.0)

| Component | Weight | Factors |
|-----------|--------|---------|
| Transaction Behavior | 25% | Velocity deviation, amount deviation, structuring patterns |
| Network Position | 30% | Proximity to known bad actors (graph distance), cluster membership, degree centrality |
| KYC Freshness | 20% | Days since last verification, EDD completion, adverse media |
| Corridor Risk | 15% | Corridor risk score of primary corridors used |
| Watchlist Proximity | 10% | Hops to nearest watchlist entity (inverse: fewer hops = higher risk) |

### Agent Compliance Score (0.0 - 1.0)

| Component | Weight | Factors |
|-----------|--------|---------|
| Volume Anomaly | 25% | Current volume vs. 90-day baseline (z-score) |
| SAR Filing Rate | 25% | SAR filings / suspicious patterns detected (should be > 0) |
| KYC Completion | 20% | % of agent's customers with current KYC |
| Structuring Detection | 20% | Count of sub-threshold structuring patterns at this agent |
| Regulatory History | 10% | Prior violations, remediation status |

### Corridor Risk Score (0.0 - 1.0)

| Component | Weight | Factors |
|-----------|--------|---------|
| Sanctioned-Country Adjacency | 30% | Does corridor touch or transit sanctioned jurisdictions |
| Volume Deviation | 25% | Current period vs baseline (anomaly detection) |
| Concentration (HHI) | 20% | Is corridor dominated by few agents/customers (Herfindahl index) |
| SAR Density | 15% | SARs filed per $M volume on this corridor |
| Regulatory Designation | 10% | Is corridor flagged by FinCEN Geographic Targeting Orders |

## Architecture Comparison Scorecard

| Capability | Current (Rule-Based) | Stage 2 (Knowledge Graph) | Stage 3 (Federated Intel) | Impact |
|-----------|---------------------|--------------------------|--------------------------|--------|
| AML Detection | Rules: $X in Y hours | Network topology + behavior + proximity | Cross-institution graph intel | 70%+ FP reduction |
| Fraud Rings | Invisible (isolated evaluation) | Connected components in seconds | Multi-institution ring detection | $10M+ loss prevention |
| Sanctions | Overnight batch (24h lag) | Real-time graph traversal (ms) | Live OFAC feed + beneficial ownership | Zero-lag compliance |
| Corridor Risk | Quarterly manual reports | Continuous automated scoring | Cross-border regulatory sharing | Proactive risk mgmt |
| Agent Oversight | 2-3 year audit cycle | Continuous per-agent scoring | Industry-wide agent reputation | Instant risk visibility |
| Regulatory Reporting | Manual SAR (30 days) | Auto-narrative generation | Cross-filing intelligence | 80% SAR time reduction |

## References

- [Bank Secrecy Act (BSA)](https://www.fincen.gov/resources/statutes-regulations/bank-secrecy-act)
- [FinCEN AML Requirements](https://www.fincen.gov/resources/statutes-regulations)
- [OFAC Sanctions Programs](https://ofac.treasury.gov/sanctions-programs-and-country-information)
- [FATF Recommendations](https://www.fatf-gafi.org/recommendations.html)
- [DCA Knowledge Graph Documentation](../../docs/KNOWLEDGE_GRAPH.md)
