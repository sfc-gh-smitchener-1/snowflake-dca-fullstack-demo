# DCA Ontology — Navigation

A deep-dive into the philosophical and human foundations of the
Snowflake Data Cloud Architecture framework.

---

## What This Folder Is

The DCA is not primarily a technical architecture. It is a framework for making
human agreements durable inside a data platform. This folder explores it through
the lens of applied ontology — the formal study of what exists, how things relate,
and what makes systems stable or fragile.

Built on the [Enterprise Architecture Guide for the Snowflake Data Cloud v7](../EnterpriseArchitecture/Enterprise-Architecture-Guide-Snowflake-v7.md)
and the [DCA Synthesis](../EnterpriseArchitecture/enterprise-architecture-guide-synthesis.md).

---

## Reading Order

| File | What It Covers | Read When |
|------|---------------|-----------|
| [01 — Philosophical Foundations](01-philosophical-foundations.md) | Searle, BFO, Guarino. Why ontology matters for data architecture. The dependency chain as ontological structure. | Start here |
| [02 — Object Ontology](02-object-ontology.md) | Formal taxonomy of Snowflake objects — types, identity conditions, dependence relationships, medallion layers as ontological zones. | After 01 |
| [03 — Human Ontology](03-human-ontology.md) | CDO/RDO/Data Teams as status functions. Trust as load-bearing structure. Collective intentionality and governance. | After 01 |
| [04 — DCA Ontological Synthesis](04-dca-ontological-synthesis.md) | Where the object and human ontologies converge. The six critical interfaces. Multi-account structure as boundary enforcement. Diagnostic questions. | After 02 + 03 |
| [05 — SE Enablement Lab](05-se-enablement-lab.md) | Hands-on SQL walkthrough for internal SEs. Six modules from role architecture to cross-account sharing. Diagnostic scenarios. The five discovery questions. | Standalone or after 04 |

---

## The Core Claim (in one paragraph)

Every Snowflake object that carries institutional meaning — a governed table,
a data contract, a masking policy, a share — is a materialised human agreement.
The platform's durability is the durability of those agreements. A governance
policy with no collective intentionality behind it is a document, not a policy.
A data contract without both parties' acceptance is a proposal, not a contract.
The platform executes what has been made explicit. The job of the architect
is to surface the human work that must happen before the platform can deliver
its promise.

---

## The Five Discovery Questions

Take these into any customer conversation:

1. "If I ask five different people what 'revenue' means, will I get five different answers?"
2. "Who is personally accountable when the Orders table has wrong data?"
3. "How do consumers find out when a schema has changed?"
4. "Does your CDO have the authority to mandate a definition that Engineering must implement?"
5. "Do your data scientists use the governed tables, or do they keep their own copies?"

---

## Operational Implementation — Knowledge Graph

The philosophical framework in this folder is now **operationalized** as a working Snowflake-native Knowledge Graph. The abstract ontological map from [04 — DCA Ontological Synthesis](04-dca-ontological-synthesis.md) is materialized as queryable nodes and edges with SQL-based inference (recursive CTEs + stored procedures).

### Implementation Files

| File | What It Does | Ontological Role |
|------|-------------|-----------------|
| `sql/11_rai_setup.sql` | Creates RAI engine, compute pool, roles | Infrastructure for graph computation |
| `sql/12_ontology_graph_tables.sql` | Creates node/edge tables | The ontological substrate — where entities and relations live |
| `sql/13_ontology_graph_populate.sql` | Populates graph from metadata + business data | Grounds the ontology in actual platform state |
| `sql/14_rai_graph_sync.sql` | Syncs to RAI, runs inference | Applies ontological reasoning (inference rules) |
| `sql/15_ontology_sharing.sql` | Makes graph shareable | Extends institutional facts across boundaries |
| `python/rai_models/ontology_graph.rel` | Rel inference model | The formal ontology expressed as computable rules |
| `ontology/philosophy/streamlit/` | Streamlit foundations app | Makes the ontology visible and navigable |

> **Note:** the earlier Neo4j sidecar / SPCS FastAPI service and the dual-backend
> Knowledge Graph page have been removed for now. The Snowflake-native ontology
> reference architecture lives in [`ontology/demo/`](../demo/) and is documented
> in [docs/ONTOLOGY.md](../../docs/ONTOLOGY.md).

### How Philosophy Maps to Implementation

| Ontological Concept (from 01-04) | Implementation |
|----------------------------------|----------------|
| Institutional facts (Searle) | Nodes with `layer=METADATA` — tags, roles, policies exist by collective agreement |
| Identity conditions (Guarino) | `node_id` = MD5 of fully qualified name — identity grounded in naming |
| Dependence relationships | Edges encode what depends on what (LINEAGE_FROM, HAS_COLUMN) |
| Status functions | Role nodes and GRANTED_TO edges — who has authority over what |
| Constitutive rules | Data contracts as edges linking producers to quality expectations |
| The six critical interfaces | Detectable as edge patterns between layers |

### Full Documentation

See [docs/KNOWLEDGE_GRAPH.md](../docs/KNOWLEDGE_GRAPH.md) for deployment instructions, API reference, and troubleshooting.
