#!/usr/bin/env python3
"""Generate per-source Cortex Analyst semantic model YAMLs from the mappings.

Cortex Analyst needs a static semantic-model file, so we generate one per source
system from the same curated :class:`MappingSpec` that drives the data + TBox.
Each YAML describes the source's GOLD views (one logical table per class):

    GOLD.V_<SYSTEM>_<CLASS>  ->  logical table <class>

Literal predicates become dimensions (text/date/boolean) or facts (numbers);
object edges become *_uid dimensions. Column names match those emitted by the
GOLD view generator (06_gold_views.sql).

Output: demo/analytics_models/analytics_<source>.yaml  (committed; staged by
06b_stage_semantic_models.sql to @ONT_DEMO.CONFIG.CORTEX_ANALYST_MODELS/).

The files are named analytics_<source>.yaml (e.g. analytics_salesforce.yaml) so
they group together and read clearly in the Cortex Analyst model picker — the
analytics layer is kept deliberately separate from the ontology (TBox) artifacts
in demo/ontologies/.

    python tools/generate_semantic_models.py
"""
from __future__ import annotations

import importlib
import re
from pathlib import Path

from ontology_adapter import MappingSpec

SYSTEMS = ["sap", "salesforce", "oracle", "fhir", "workday", "servicenow"]

# Friendly file slug per source system (what appears in the Cortex Analyst model
# picker). Keep in sync with SOURCE_MODELS in streamlit_app.py.
FILE_SLUG = {
    "sap":        "sap",
    "salesforce": "salesforce",
    "oracle":     "oracle_ebs",
    "fhir":       "fhir",
    "workday":    "workday",
    "servicenow": "servicenow",
}
OUT_DIR = Path(__file__).resolve().parent.parent / "analytics_models"

_NUMERIC = {"xsd:decimal", "xsd:integer", "xsd:float", "xsd:double", "xsd:long"}


def col_alias(predicate_iri: str) -> str:
    local = predicate_iri.split(":", 1)[-1]
    return re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", local).lower()


def data_type_for(datatype: str) -> str:
    if datatype in _NUMERIC:
        return "number"
    if datatype == "xsd:boolean":
        return "boolean"
    if datatype == "xsd:date":
        return "date"
    return "text"


def class_local(class_iri: str) -> str:
    return class_iri.split(":", 1)[-1]


def view_name(prefix: str, class_iri: str) -> str:
    token = re.sub(r"[^A-Za-z0-9]", "_", class_local(class_iri)).upper()
    return f"V_{prefix.upper()}_{token}"


def build_yaml(spec: MappingSpec) -> str:
    prefix = spec.namespace_prefix
    lines = [
        f"name: {spec.system}_ontology",
        f"description: >-",
        f"  Cortex Analyst semantic model for the {spec.system.upper()} ontology, generated",
        f"  from mappings/{spec.system}.py. One logical table per ontology class, backed by",
        f"  the GOLD.V_{prefix.upper()}_* views.",
        "tables:",
    ]

    # Collapse multiple TableMaps that share a class (e.g. SAP PA0001/PA0002).
    seen_classes = set()
    for tm in spec.tables:
        if tm.class_iri in seen_classes:
            continue
        seen_classes.add(tm.class_iri)

        # Gather all literal/edge columns for this class across tables.
        lits = {}
        edges = {}
        for t2 in spec.tables:
            if t2.class_iri != tm.class_iri:
                continue
            for pm in t2.literals:
                lits.setdefault(col_alias(pm.predicate_iri), pm.datatype)
            for em in t2.edges:
                edges.setdefault(col_alias(em.predicate_iri) + "_uid", True)

        local = class_local(tm.class_iri)
        # Prefix the logical table name with the source so it can never collide
        # with a Snowflake reserved keyword (e.g. sfdc:Case -> sfdc_case,
        # snow:User -> snow_user, sfdc:Account -> sfdc_account). Cortex Analyst
        # rejects logical table names that are reserved keywords.
        local_snake = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", local).lower()
        logical = f"{prefix}_{local_snake}"
        lines.append(f"  - name: {logical}")
        lines.append(f"    description: {spec.system.upper()} {local}")
        lines.append(f"    base_table:")
        lines.append(f"      database: ONT_DEMO")
        lines.append(f"      schema: GOLD")
        lines.append(f"      table: {view_name(prefix, tm.class_iri)}")
        lines.append(f"    primary_key:")
        lines.append(f"      columns:")
        lines.append(f"        - uid")

        dimensions = [("uid", "text"), ("label", "text"), ("name", "text")]
        facts = []
        for alias, dt in sorted(lits.items()):
            if alias in ("name",):
                continue
            if data_type_for(dt) == "number":
                facts.append((alias, "number"))
            else:
                dimensions.append((alias, data_type_for(dt)))
        for alias in sorted(edges):
            dimensions.append((alias, "text"))

        lines.append(f"    dimensions:")
        for name, dt in dimensions:
            lines.append(f"      - name: {name}")
            lines.append(f"        expr: {name}")
            lines.append(f"        data_type: {dt}")
        if facts:
            lines.append(f"    facts:")
            for name, dt in facts:
                lines.append(f"      - name: {name}")
                lines.append(f"        expr: {name}")
                lines.append(f"        data_type: {dt}")

    return "\n".join(lines) + "\n"


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for system in SYSTEMS:
        spec: MappingSpec = importlib.import_module(f"mappings.{system}").SPEC
        slug = FILE_SLUG.get(system, system)
        fname = f"analytics_{slug}.yaml"
        (OUT_DIR / fname).write_text(build_yaml(spec), encoding="utf-8")
        print(f"{system} ({spec.namespace_prefix}): wrote analytics_models/{fname}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
