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
