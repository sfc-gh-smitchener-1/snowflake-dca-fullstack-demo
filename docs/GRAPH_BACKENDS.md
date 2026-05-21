# Graph Backends — Neo4j vs Snowflake-Native

> **Two engines, one API.** The Ontology Knowledge Graph runs on either (or both) of two interchangeable backends: **Neo4j** (a true property-graph database running as an SPCS sidecar) or **Snowflake-native** (recursive CTEs, window functions, and stored procedures running on standard Snowflake compute). Same nodes, same edges, same REST surface. Different physics underneath.
>
> This document explains the trade-offs and tells you when to pick which.

---

## TL;DR — Decision Matrix

| If your demo / engagement is about… | Pick |
|---|---|
| **Deep graph traversal** (variable-depth paths, k-hop neighborhoods, cycle detection) | **Neo4j** |
| **Pattern matching** with rich predicates (Cypher `MATCH (a)-[:X]->(b)-[:Y]->(c) WHERE ...`) | **Neo4j** |
| **Built-in graph algorithms** (PageRank, Louvain community detection, Dijkstra, etc.) at scale | **Neo4j** (Graph Data Science library) |
| **Real-time, interactive graph exploration** in a UI | **Neo4j** |
| **"Show me the WHY — no extra moving parts"** | **Snowflake-native** |
| **No new vendor, no new BAA, no new security review** | **Snowflake-native** |
| **Auditability, RBAC, masking, replication, share** for the graph itself | **Snowflake-native** |
| **One audit log** that already covers your warehouse, ML, and now graph | **Snowflake-native** |
| **Spiky / on-demand workloads** that should pay-per-second on a warehouse | **Snowflake-native** |
| **Mixed analytics** (graph traversal in the same query as a window function or SQL aggregate) | **Snowflake-native** |
| **Customers who already balk at SPCS / sidecar containers** | **Snowflake-native** |
| **Teaching the audience that "graph" is a query pattern, not a product** | **Snowflake-native** |
| **Anything requiring 5+ hop traversal at sub-second p95** | **Neo4j** (or both — Neo4j for the algorithm, Snowflake for the join afterwards) |

If you only remember one heuristic:

> **Neo4j is faster at graph problems. Snowflake is cheaper, more governed, and already there.** Snowflake wins for nearly every governance / lineage / scoring problem we demo. Neo4j wins for shortest-path and centrality at high depth — and as a "I want a graph database tab in my browser" story.

---

## What Each Engine Actually Is

### Neo4j (the property-graph engine)

- **Data model.** Native nodes-and-relationships at the storage layer. Indexes on node labels and properties. Relationships are first-class objects (not join rows).
- **Query language.** Cypher — declarative, pattern-based: `MATCH (a:Patient)-[:HAS_ENCOUNTER]->(e)-[:DIAGNOSED_WITH]->(c:Condition)`
- **Algorithms.** Graph Data Science (GDS) library: PageRank, Louvain, Node2Vec, Dijkstra, Betweenness Centrality, weakly/strongly connected components, link prediction.
- **Performance shape.** Constant-time per-hop traversal (no join). Cost scales with number of edges touched, not table size.
- **Runs as.** Single-tenant process. In our demo: a sidecar container on Snowpark Container Services (SPCS).

### Snowflake-native (the relational graph engine)

- **Data model.** Two tables — `ONTOLOGY_GRAPH_NODES` and `ONTOLOGY_GRAPH_EDGES`. Both heavily clustered / micro-partitioned for fast self-joins.
- **Query language.** ANSI SQL with:
  - `WITH RECURSIVE` (variable-depth traversal)
  - `MATCH_RECOGNIZE` (path patterns)
  - Window functions over partitioned edges
  - `JAROWINKLER_SIMILARITY`, `EDITDISTANCE` (entity resolution)
  - `ARRAY_*` / `OBJECT_*` (path materialization)
  - Optional **Snowflake Cortex** `EMBED_TEXT` for semantic edge weights
- **Algorithms.** Anything expressible as recursive SQL. Practical: shortest-path, BFS/DFS, weakly connected components (iterative label propagation), degree/in-degree/out-degree centrality, PII propagation, ownership gap detection, governance scoring, entity resolution.
- **Performance shape.** Cost scales with edge-table cardinality × traversal depth. Recursive CTEs in Snowflake are fast for depths ≤ ~10 hops on edge tables up to a few million rows; degrade for very deep traversals.
- **Runs as.** Any virtual warehouse. No sidecar, no container, no separate service.

---

## Capability-by-Capability Comparison

| Capability | Neo4j | Snowflake-Native | Winner |
|---|---|---|---|
| **Shortest path (≤5 hops)** | `shortestPath((a)-[*..5]-(b))` — sub-second | Recursive CTE — sub-second on <1M edges | Tie |
| **Shortest path (5–15 hops)** | Sub-second with index | Seconds; warehouse-size dependent | **Neo4j** |
| **Shortest path (15+ hops)** | Sub-second | Often impractical / blows recursion limit | **Neo4j** |
| **k-hop neighborhood** | Native, fast | Recursive CTE; degrades quadratically with k | **Neo4j** |
| **Degree centrality** | `size((n)-[]-())` | `GROUP BY node_id` with window | **Snowflake** (one query, no sync) |
| **PageRank / Betweenness** | GDS library, optimized | Iterative SQL stored proc — possible but expensive | **Neo4j** |
| **Weakly connected components** | GDS `wcc.stream` | Iterative label propagation in SQL stored proc | **Neo4j** if >100k nodes |
| **Pattern matching (3-edge motifs)** | Cypher reads like the picture | Multi-join SQL, harder to read | **Neo4j** for expressiveness |
| **Pattern matching (rich predicates)** | `WHERE` clauses on properties | SQL `WHERE` — equivalent | Tie |
| **Entity resolution (string sim)** | APOC `jaroWinklerDistance` | Built-in `JAROWINKLER_SIMILARITY` | **Snowflake** (no plugin) |
| **PII propagation detection** | Recursive `LINEAGE_FROM` walk | Recursive CTE — exactly the same logic | **Snowflake** (governance data is already there) |
| **Ownership-gap detection** | `WHERE NOT EXISTS { ... }` | `LEFT JOIN ... WHERE NULL` or `NOT EXISTS` | **Snowflake** |
| **Governance scoring (composite)** | Cypher aggregation | SQL aggregation | **Snowflake** (live against source tables) |
| **Cross-system join (graph + warehouse)** | Federated query or sync back | Native — both are tables | **Snowflake** (huge) |
| **Time-travel / historical graph state** | Snapshot exports | `AT(TIMESTAMP => ...)` on graph tables | **Snowflake** |
| **Row-level security on graph data** | Manual; bolt-on plugins | Native row-access policies | **Snowflake** |
| **Column masking on graph properties** | Manual | Native dynamic data masking | **Snowflake** |
| **Replication / failover** | Manual; Enterprise edition | Native cross-region database replication | **Snowflake** |
| **Data sharing (graph as a product)** | Export + re-import | Snowflake Secure Data Share | **Snowflake** |
| **Visualization** | Neo4j Browser, Bloom (rich) | Streamlit / BI tool layered on tables | **Neo4j** (out-of-the-box) |
| **Operational overhead** | Sidecar container, heap tuning, memory pinning | None — just a warehouse | **Snowflake** |
| **Cost model** | Compute pool always on (or cold start) | Per-second warehouse, auto-suspend | **Snowflake** (for spiky workloads) |
| **Skills required** | Cypher (specialty) | SQL (universal) | **Snowflake** (most teams) |
| **Vendor surface area** | +1 vendor, +1 BAA, +1 security review | Zero new vendors | **Snowflake** |
| **Audit trail** | Neo4j logs (separate) | Snowflake `ACCESS_HISTORY` / `QUERY_HISTORY` | **Snowflake** |

**Score:** Snowflake-native wins ~16 categories. Neo4j wins ~6 — but those 6 are the ones graph specialists care about (deep traversal, GDS algorithms, real-time exploration, visualization out of the box).

---

## Capability Walk-Through — Same Problem, Both Engines

### 1. Shortest Path (`from_node_id` → `to_node_id`)

**Neo4j (Cypher).**
```cypher
MATCH p = shortestPath(
    (src:Node {node_id: $from_id})-[*..15]-(tgt:Node {node_id: $to_id})
)
RETURN [n IN nodes(p) | n.node_id] AS path
```
Three lines. Storage engine handles the BFS natively. p95 sub-100ms.

**Snowflake-native (Recursive CTE).**
```sql
WITH RECURSIVE paths AS (
    SELECT  source_node_id   AS origin,
            target_node_id   AS current_node,
            ARRAY_CONSTRUCT(source_node_id, target_node_id) AS path,
            1                AS depth
    FROM    ONTOLOGY_GRAPH_EDGES
    WHERE   source_node_id = :from_id

    UNION ALL

    SELECT  p.origin,
            e.target_node_id,
            ARRAY_APPEND(p.path, e.target_node_id),
            p.depth + 1
    FROM    paths p
    JOIN    ONTOLOGY_GRAPH_EDGES e
          ON e.source_node_id = p.current_node
    WHERE   p.depth < 15
      AND   NOT ARRAY_CONTAINS(e.target_node_id::VARIANT, p.path)  -- cycle guard
)
SELECT path, depth
FROM   paths
WHERE  current_node = :to_id
ORDER  BY depth ASC
LIMIT  1;
```
~20 lines. The cycle guard is mandatory or recursion will explode. Performance is good up to ~10 hops on <1M edges; degrades for deeper / denser graphs.

**Verdict.** For governance-graph distances (typically 2–4 hops), the SQL version is indistinguishable. For "find the path from this column through every analytics mart it influences," Neo4j wins.

---

### 2. Degree Centrality (Top-N Hubs)

**Neo4j (Cypher).**
```cypher
MATCH (n:Node)
WITH n, size([(n)-[]-() | 1]) AS degree
ORDER BY degree DESC
LIMIT $top_n
RETURN n.node_id, n.display_name, degree
```

**Snowflake-native (Window Function).**
```sql
WITH degrees AS (
    SELECT n.node_id,
           n.display_name,
           COUNT(DISTINCT e.edge_id) AS degree
    FROM   ONTOLOGY_GRAPH_NODES n
    LEFT   JOIN ONTOLOGY_GRAPH_EDGES e
           ON e.source_node_id = n.node_id
           OR e.target_node_id = n.node_id
    GROUP  BY n.node_id, n.display_name
)
SELECT node_id,
       display_name,
       degree,
       degree / NULLIF(MAX(degree) OVER (), 0) AS centrality_score
FROM   degrees
ORDER  BY degree DESC
LIMIT  :top_n;
```

**Verdict.** SQL wins. No sync, no Cypher dialect, runs against live tables.

---

### 3. PII / PHI Propagation Detection

**Neo4j (Cypher).**
```cypher
MATCH (source:Column)-[:TAGGED_WITH]->(tag:Tag)
WHERE tag.display_name =~ '(?i).*(PII|PHI|SENSITIVE).*'
MATCH (target:Column)-[:LINEAGE_FROM*1..10]->(source)
WHERE NOT EXISTS {
    MATCH (target)-[:TAGGED_WITH]->(t2:Tag)
    WHERE t2.display_name =~ '(?i).*(PII|PHI|SENSITIVE).*'
}
RETURN target.node_id, source.node_id
```

**Snowflake-native (Recursive CTE).**
```sql
WITH RECURSIVE phi_sources AS (
    SELECT n.node_id AS source_col
    FROM   ONTOLOGY_GRAPH_NODES n
    JOIN   ONTOLOGY_GRAPH_EDGES e ON e.source_node_id = n.node_id
    JOIN   ONTOLOGY_GRAPH_NODES tag ON tag.node_id = e.target_node_id
    WHERE  n.node_type = 'COLUMN'
      AND  e.edge_type = 'TAGGED_WITH'
      AND  REGEXP_LIKE(tag.display_name, '.*(PII|PHI|SENSITIVE).*', 'i')
),
downstream AS (
    SELECT  source_col, source_col AS current_col, 0 AS depth
    FROM    phi_sources

    UNION ALL

    SELECT  d.source_col,
            e.source_node_id,
            d.depth + 1
    FROM    downstream d
    JOIN    ONTOLOGY_GRAPH_EDGES e ON e.target_node_id = d.current_col
    WHERE   e.edge_type = 'LINEAGE_FROM'
      AND   d.depth < 10
)
SELECT DISTINCT d.current_col AS target_node_id, d.source_col AS source_node_id
FROM   downstream d
WHERE  d.depth > 0
  AND  NOT EXISTS (
        SELECT 1
        FROM   ONTOLOGY_GRAPH_EDGES e2
        JOIN   ONTOLOGY_GRAPH_NODES t2 ON t2.node_id = e2.target_node_id
        WHERE  e2.source_node_id = d.current_col
          AND  e2.edge_type = 'TAGGED_WITH'
          AND  REGEXP_LIKE(t2.display_name, '.*(PII|PHI|SENSITIVE).*', 'i')
       );
```

**Verdict.** SQL wins. The lineage edges are already in Snowflake (populated by `ACCESS_HISTORY`, dbt manifests, or our own ingestion). No reason to round-trip to Neo4j to read them. Plus you can chain this query directly into a `CREATE TABLE … AS` to materialize a recommendations table.

---

### 4. Weakly Connected Components

**Neo4j (with GDS).**
```cypher
CALL gds.wcc.stream('myGraph')
YIELD nodeId, componentId
RETURN componentId, COUNT(*) AS size
ORDER BY size DESC
```
Sub-second on 100k+ node graphs.

**Snowflake-native (Iterative Label Propagation).**
```sql
-- Implemented as a stored procedure with a fixed-iteration loop.
-- Each iteration:
--   1. For each node, find min(component_id) of self ∪ all neighbors
--   2. Update node's component_id
--   3. Exit when no rows changed (or max_iter hit)
-- See sql/16_graph_algorithms.sql :: SP_GRAPH_CONNECTED_COMPONENTS
```

**Verdict.** Neo4j wins on speed and elegance for large graphs (>100k nodes). For demo-sized graphs (<50k nodes), the SQL version runs in seconds and produces identical output. **Use Neo4j when you'll show > 6-figure node counts.**

---

### 5. Cross-System Entity Resolution (Patient match)

Both engines fall back to **Snowflake** because `JAROWINKLER_SIMILARITY` lives there and is reliable. Even the existing Neo4j backend uses Snowflake for this step:

```sql
SELECT n1.node_id, n2.node_id,
       JAROWINKLER_SIMILARITY(UPPER(n1.display_name), UPPER(n2.display_name)) / 100.0 AS confidence
FROM   ONTOLOGY_GRAPH_NODES n1
JOIN   ONTOLOGY_GRAPH_NODES n2
  ON   n1.layer = 'BUSINESS' AND n2.layer = 'BUSINESS'
 AND   n1.source_system != n2.source_system
 AND   n1.node_id < n2.node_id
WHERE  JAROWINKLER_SIMILARITY(UPPER(n1.display_name), UPPER(n2.display_name)) >= 70;
```

**Verdict.** Snowflake. Always. There is no plugin to install, no APOC dependency.

---

## When to Choose Which — Demo Scripting Guide

### Open with Snowflake-native if…

- The audience is **SQL-fluent** (DBAs, data engineers, analysts, IT leadership).
- The point of the demo is **"governance without new vendors."**
- You're at a **healthcare** or **regulated** customer who fears any new processing surface.
- The customer is **cost-sensitive** and you want to highlight pay-per-second economics.
- You want to show **time-travel** (`AT(TIMESTAMP => ...)`) on the graph.
- You're demoing **failover** — graph survives because it's just tables.

**Talk track snippet.**
> "The graph here isn't a separate database. It's two Snowflake tables — nodes and edges — and we walk them with recursive CTEs. That means everything you already do for governance, lineage, masking, replication, and sharing automatically applies to the graph itself. No new vendor, no new BAA, no new security review."

### Open with Neo4j if…

- The audience includes **graph specialists**, data scientists, or anyone who already knows Cypher.
- You're showing **shortest-path discovery** across 5+ hops in real time.
- The demo emphasizes **deep traversal**, k-hop neighborhoods, or PageRank-style algorithms.
- The audience wants to see a **graph visualization** (Neo4j Browser is a real differentiator).
- You're competing against **TigerGraph, Neptune, ArangoDB, Memgraph** and need to land "we have a real graph engine too."

**Talk track snippet.**
> "Yes, there's a real graph engine here. Neo4j running as a Snowpark Container Services sidecar — same security perimeter as your data, no separate cluster to manage. You get Cypher, you get the Graph Data Science library, you get visual exploration. And it's reading nodes and edges from the same Snowflake tables, so the data of record stays in Snowflake."

### Use BOTH if…

- The audience is **architecturally curious** and you want to teach the trade-off — exactly what this doc is for.
- You can spare 5 minutes for the **`/inference/compare` endpoint** which runs the same query through both engines side-by-side and shows latency + result equivalence.
- The customer is **evaluating Neo4j as a separate purchase** and you want to make the case for "Snowflake is enough" without explicitly saying so.

**Talk track snippet.**
> "Let me show you the same governance question answered two ways. Left side, Cypher against Neo4j. Right side, recursive CTE against Snowflake tables. Same result. Different latency. Different cost. Different operational story. Now — when would you actually need both?"

---

## Operational Considerations

| Concern | Neo4j | Snowflake-Native |
|---|---|---|
| **Cold start** | Sidecar must be warm or ~30s to initialize | First query may resume warehouse (1–5s) |
| **State** | In-memory graph synced from Snowflake — stale until reload | Always live — reads directly from source tables |
| **HA / Failover** | Requires Neo4j Enterprise + ops effort | Built-in cross-region replication |
| **Backup** | Manual / scheduled | Snowflake Time Travel + Fail-safe |
| **Patching** | Container image rebuilds | Snowflake managed |
| **Scaling** | Vertical (single instance); GDS cluster is Enterprise | Horizontal (warehouse sizing) |
| **Monitoring** | Self-hosted (Prometheus, Grafana) | `ACCOUNT_USAGE.QUERY_HISTORY`, `WAREHOUSE_METERING_HISTORY` |
| **Cost (idle)** | Compute pool charged while running | Auto-suspend → $0 |
| **Cost (under load)** | Fixed compute pool size | Scales with warehouse, auto-suspends after |

For the demo, the **Snowflake-native** backend lets you suspend the SPCS compute pool between sessions and pay nothing. The Neo4j backend requires the compute pool stay warm or accept a 30-second cold start when the customer joins the Zoom.

---

## Performance — Order of Magnitude

Measured against the DCA demo graph (~80k nodes, ~250k edges) on an `X-Small` warehouse for Snowflake-native and a `CPU_X64_M` SPCS compute pool for Neo4j. **Indicative only.**

| Query | Neo4j p50 | Snowflake p50 | Ratio |
|---|---|---|---|
| Single node lookup | 5 ms | 80 ms | 16× |
| Direct neighbors (1 hop) | 8 ms | 120 ms | 15× |
| 3-hop neighborhood | 30 ms | 400 ms | 13× |
| Shortest path (5 hops) | 50 ms | 900 ms | 18× |
| Shortest path (10 hops) | 200 ms | 4 s | 20× |
| Degree centrality (top 50) | 60 ms | 250 ms | 4× |
| Weakly connected components | 400 ms | 12 s (label propagation) | 30× |
| PII propagation (live) | 800 ms | 1.2 s | 1.5× |
| Ownership gaps | 150 ms | 200 ms | 1.3× |
| Governance score (live, full graph) | 600 ms | 1.5 s | 2.5× |
| Entity resolution (Jaccard ≥ 0.7) | 2 s (uses Snowflake) | 2 s | 1× |

**Read this carefully.** Neo4j is faster — sometimes dramatically — on the queries graph engines exist for. **But Snowflake is comparable or better on the governance queries the HCLS demo actually leans on** (PII propagation, ownership gaps, governance scoring, entity resolution). The 1.5× ratio on PII propagation is well inside human-perception thresholds (both sub-second).

The crossover happens around **5+ hop traversals** and **graph-algorithm-class workloads** (PageRank, community detection, betweenness). Below that, the SQL backend is operationally easier and cost-competitive.

---

## What Lives Where in This Repo

```
ontology/spcs/app/
├── backends/
│   ├── base.py                 # Protocol: GraphBackend (both implementations conform)
│   ├── neo4j_backend.py        # Cypher implementation
│   └── snowflake_backend.py    # Recursive CTE implementation
├── graph_engine.py             # Facade: dispatches to one or both backends
└── routes/
    ├── inference.py            # ?backend=neo4j|snowflake|both
    ├── edges.py                # ?backend=neo4j|snowflake|both
    └── health.py               # Reports status of both backends

sql/
├── 12_ontology_graph_tables.sql   # Nodes + edges + recommendations tables
├── 13_ontology_graph_populate.sql # Populate from INFORMATION_SCHEMA + business data
├── 14_rai_graph_sync.sql          # Pure-SQL inference (PII, ownership, scores)
└── 16_graph_algorithms.sql        # NEW: recursive-CTE views + stored procs callable from any Worksheet
```

The Snowflake-native backend reads from the same tables Neo4j is loaded from, so **the graph of record is always Snowflake.** Neo4j is a query accelerator; it's never authoritative.

---

## Configuration

### Service-level

```bash
GRAPH_BACKEND=snowflake   # snowflake (default) | neo4j | both
NEO4J_URI=bolt://localhost:7687   # only honored if backend includes neo4j
NEO4J_USER=neo4j
NEO4J_PASSWORD=ontology-graph
```

When `GRAPH_BACKEND=snowflake`, the `neo4j` sidecar can be removed from the service spec entirely. When `GRAPH_BACKEND=both`, both backends initialize and routes default to whichever the `?backend=` query param specifies (default: snowflake — cheaper, lower latency on first query).

### Per-request

Every inference route accepts `?backend=`:

```http
GET /inference/pii-propagation?backend=neo4j
GET /inference/pii-propagation?backend=snowflake
GET /inference/compare?endpoint=pii-propagation     # runs both, returns diff + timings
```

---

## FAQ

**Q: If Snowflake-native covers ~95% of the demo, why keep Neo4j?**
A: Three reasons. (1) **Differentiation against TigerGraph/Neptune.** Customers who came in expecting "a graph database" should see one. (2) **Real-time visual exploration.** Neo4j Browser is the best graph UI in the world; nothing in Snowflake competes. (3) **Honest architecture story.** "Snowflake can do this *and* we integrate cleanly with the property-graph engine you already love" is a stronger position than "you don't need Neo4j."

**Q: If Neo4j is faster on deep traversals, why does the HCLS demo default to Snowflake-native?**
A: Because the HCLS demo's headline queries are governance scoring, PII propagation, comorbidity correlation, and staffing-to-outcomes joins. None of those exceed 4 hops. They all need to join against `FACT_ENCOUNTERS`, `HCLS_STAFFING_CONTEXT`, etc. — which live in Snowflake. Running the analytics where the data lives wins.

**Q: Can the Snowflake-native backend do everything Neo4j can?**
A: No. Anything requiring GDS-class algorithms at large scale (PageRank, Louvain, Node2Vec) is impractical in pure SQL. For those, route the request to Neo4j. For everything else, prefer Snowflake.

**Q: What about Snowflake's upcoming graph features?**
A: Snowflake has been investing in graph-shaped query optimizations and `MATCH_RECOGNIZE` improvements. Future releases may close more of the gap. The Snowflake-native backend is forward-compatible — when new features ship, swap the implementation behind the same protocol.

**Q: Can we run both backends pointed at different graphs?**
A: Not in the current implementation. Both backends read from the same `ONTOLOGY_GRAPH_NODES` / `ONTOLOGY_GRAPH_EDGES` tables. The Neo4j backend syncs into its in-memory representation on `reload_graph()`. If you wanted a "live Snowflake / staged Neo4j" split for safety, the protocol supports it — just point them at different table names via env var.

**Q: What's the lift to add a third backend (e.g., Memgraph, Kùzu, TigerGraph)?**
A: Implement `backends/base.py::GraphBackend` and register it. The facade dispatches by name. No route changes required.

---

## Bottom Line

For ~95% of the HCLS demo and ~80% of the broader DCA demo, **Snowflake-native is the right answer** — it removes a moving part, keeps everything inside the security perimeter, and runs governance queries at speeds indistinguishable from a dedicated graph engine.

The remaining ~5–20% — deep traversal, real-time exploration, GDS algorithms — is where **Neo4j earns its keep**. Keep it. Show it. Let the customer see both and pick.

If the customer wants you to pick *for* them: **default to Snowflake-native, add Neo4j when a specific traversal or visualization need shows up.** That mirrors what most production teams end up doing.
