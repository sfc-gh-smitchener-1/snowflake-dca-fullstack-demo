#!/usr/bin/env python3
"""Generate committed per-source TBox artifacts from the curated mapping specs.

For each source system this writes two files under ``demo/ontologies/``:

  <system>.sql  — idempotent MERGE loaders for namespace/class/property/shape/
                  constraint into the shared SILVER TBox.
  <system>.ttl  — the same ontology in OWL/SHACL Turtle (human-readable source
                  of truth / documentation).

Because both are derived from the same :class:`MappingSpec` that produces the
ABox, the TBox is guaranteed to contain a row for every class and predicate the
generated data uses (no dangling foreign keys at load time).

Run after editing any ``mappings/<system>.py``:
    python tools/generate_tbox.py
"""
from __future__ import annotations

import importlib
from pathlib import Path

from ontology_adapter import MappingSpec, derive_tbox

SYSTEMS = ["sap", "salesforce", "oracle", "fhir", "workday", "servicenow"]
ONTOLOGIES_DIR = Path(__file__).resolve().parent.parent / "ontologies"


def _sql_str(value) -> str:
    if value is None:
        return "NULL"
    return "'" + str(value).replace("'", "''") + "'"


def _sql_int(value) -> str:
    return "NULL" if value is None else str(int(value))


def build_sql(spec: MappingSpec, tbox: dict) -> str:
    ns_iri, prefix, ns_desc = tbox["namespace"]
    L = []
    L.append("-- " + "=" * 76)
    L.append(f"-- {spec.system.upper()} ontology (TBox) — generated from mappings/{spec.system}.py")
    L.append("-- " + "=" * 76)
    L.append("-- Do not edit by hand. Regenerate with: python tools/generate_tbox.py")
    L.append("-- Mirrors ontologies/" + spec.system + ".ttl. Loads namespace/class/property/")
    L.append("-- shape/constraint into the shared SILVER TBox. The matching ABox comes from:")
    L.append(f"--     python tools/generate_ontology_data.py --system {spec.system}")
    L.append(f'--     snow sql -D "SYSTEM={spec.system}" -f 02b_load_source_ontology.sql')
    L.append("-- Prereqs: 01_setup_database.sql, 02_load_synthetic_data.sql, 00_shared_tbox.sql")
    L.append("-- Idempotent (MERGE).")
    L.append("-- " + "=" * 76)
    L.append("")
    L.append("USE ROLE      ONT_DEMO_BUILDER_ROLE;")
    L.append("USE DATABASE  ONT_DEMO;")
    L.append("USE SCHEMA    SILVER;")
    L.append("USE WAREHOUSE ONT_DEMO_INGEST_WH;")
    L.append("")

    # namespace
    L.append("-- 0. Namespace")
    L.append("MERGE INTO namespace AS t")
    L.append("USING (SELECT column1 AS namespace_iri, column2 AS prefix, column3 AS description")
    L.append("       FROM VALUES (%s, %s, %s)) s" % (_sql_str(ns_iri), _sql_str(prefix), _sql_str(ns_desc)))
    L.append("ON t.namespace_iri = s.namespace_iri")
    L.append("WHEN NOT MATCHED THEN INSERT VALUES (s.namespace_iri, s.prefix, s.description);")
    L.append("")

    # classes
    L.append("-- 1. Classes")
    L.append("MERGE INTO class AS t")
    L.append("USING (SELECT column1 AS class_iri, column2 AS namespace_iri, column3 AS label,")
    L.append("              column4 AS definition, column5 AS sub_class_of")
    L.append("       FROM VALUES")
    rows = []
    for c in tbox["classes"]:
        rows.append("         (%s, %s, %s, %s, %s)" % (
            _sql_str(c[0]), _sql_str(c[1]), _sql_str(c[2]), _sql_str(c[3]), _sql_str(c[4])))
    L.append(",\n".join(rows))
    L.append("       ) s ON t.class_iri = s.class_iri")
    L.append("WHEN NOT MATCHED THEN INSERT VALUES")
    L.append("    (s.class_iri, s.namespace_iri, s.label, s.definition, s.sub_class_of);")
    L.append("")

    # properties
    L.append("-- 2. Properties")
    L.append("MERGE INTO property AS t")
    L.append("USING (SELECT column1 AS property_iri, column2 AS namespace_iri, column3 AS label,")
    L.append("              column4 AS kind, column5 AS domain_class_iri, column6 AS range_class_iri,")
    L.append("              column7 AS range_datatype, column8 AS range_domain_iri,")
    L.append("              column9 AS min_count, column10 AS max_count, column11 AS sub_property_of")
    L.append("       FROM VALUES")
    rows = []
    for p in tbox["properties"]:
        # p = [iri, ns, label, kind, domain, range_class, range_datatype, min, max]
        rows.append("         (%s, %s, %s, %s, %s, %s, %s, NULL, %s, %s, NULL)" % (
            _sql_str(p[0]), _sql_str(p[1]), _sql_str(p[2]), _sql_str(p[3]),
            _sql_str(p[4]), _sql_str(p[5]), _sql_str(p[6]),
            _sql_int(p[7]), _sql_int(p[8])))
    L.append(",\n".join(rows))
    L.append("       ) s ON t.property_iri = s.property_iri")
    L.append("WHEN NOT MATCHED THEN INSERT VALUES")
    L.append("    (s.property_iri, s.namespace_iri, s.label, s.kind, s.domain_class_iri,")
    L.append("     s.range_class_iri, s.range_datatype, s.range_domain_iri,")
    L.append("     s.min_count::INTEGER, s.max_count::INTEGER, s.sub_property_of);")
    L.append("")

    # shapes
    L.append("-- 3. Shapes")
    L.append("MERGE INTO shape AS t")
    L.append("USING (SELECT column1 AS shape_iri, column2 AS target_class_iri, column3 AS label")
    L.append("       FROM VALUES")
    rows = ["         (%s, %s, %s)" % (_sql_str(s[0]), _sql_str(s[1]), _sql_str(s[2]))
            for s in tbox["shapes"]]
    L.append(",\n".join(rows))
    L.append("       ) s ON t.shape_iri = s.shape_iri")
    L.append("WHEN NOT MATCHED THEN INSERT VALUES (s.shape_iri, s.target_class_iri, s.label);")
    L.append("")

    # constraints
    if tbox["constraints"]:
        L.append("-- 4. Constraints")
        L.append("MERGE INTO constraint AS t")
        L.append("USING (SELECT column1 AS constraint_id, column2 AS shape_iri, column3 AS kind,")
        L.append("              column4 AS property_iri, column5 AS body")
        L.append("       FROM VALUES")
        rows = ["         (%s, %s, %s, %s, %s)" % (
            _sql_str(c[0]), _sql_str(c[1]), _sql_str(c[2]), _sql_str(c[3]), _sql_str(c[4]))
            for c in tbox["constraints"]]
        L.append(",\n".join(rows))
        L.append("       ) s ON t.constraint_id = s.constraint_id")
        L.append("WHEN NOT MATCHED THEN INSERT VALUES")
        L.append("    (s.constraint_id, s.shape_iri, s.kind, s.property_iri, s.body);")
        L.append("")

    L.append(f"SELECT '{spec.system.upper()} ontology (TBox) loaded' AS status,")
    L.append(f"       (SELECT COUNT(*) FROM class WHERE namespace_iri = {_sql_str(ns_iri)})    AS classes,")
    L.append(f"       (SELECT COUNT(*) FROM property WHERE namespace_iri = {_sql_str(ns_iri)}) AS properties;")
    L.append("")
    return "\n".join(L)


def build_ttl(spec: MappingSpec, tbox: dict) -> str:
    ns_iri, prefix, ns_desc = tbox["namespace"]
    L = []
    L.append(f"# {spec.system.upper()} source-system ontology (OWL/SHACL)")
    L.append(f"# Generated from mappings/{spec.system}.py — regenerate with tools/generate_tbox.py")
    L.append("")
    L.append("@prefix owl:  <http://www.w3.org/2002/07/owl#> .")
    L.append("@prefix rdf:  <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .")
    L.append("@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .")
    L.append("@prefix sh:   <http://www.w3.org/ns/shacl#> .")
    L.append("@prefix xsd:  <http://www.w3.org/2001/XMLSchema#> .")
    L.append("@prefix schema: <http://schema.org/> .")
    L.append(f"@prefix {prefix}: <{ns_iri}> .")
    L.append("")
    L.append(f"<{ns_iri}> a owl:Ontology ; rdfs:label \"{ns_desc}\" .")
    L.append("")
    L.append("# --- Classes ---")
    for c in tbox["classes"]:
        L.append(f"{c[0]} a owl:Class ;")
        L.append(f"    rdfs:label \"{c[2]}\" ;")
        L.append(f"    rdfs:subClassOf {c[4]} .")
    L.append("")
    L.append("# --- Properties ---")
    for p in tbox["properties"]:
        ptype = "owl:ObjectProperty" if p[3] == "object" else "owl:DatatypeProperty"
        L.append(f"{p[0]} a {ptype} ;")
        L.append(f"    rdfs:label \"{p[2]}\" ;")
        L.append(f"    rdfs:domain {p[4]} ;")
        rng = p[5] if p[3] == "object" else p[6]
        L.append(f"    rdfs:range {rng} .")
    L.append("")
    L.append("# --- SHACL shapes ---")
    cons_by_shape = {}
    for c in tbox["constraints"]:
        cons_by_shape.setdefault(c[1], []).append(c)
    for s in tbox["shapes"]:
        L.append(f"{s[0]} a sh:NodeShape ;")
        line = f"    sh:targetClass {s[1]}"
        cons = cons_by_shape.get(s[0], [])
        if not cons:
            L.append(line + " .")
        else:
            L.append(line + " ;")
            for i, c in enumerate(cons):
                term = " ." if i == len(cons) - 1 else " ;"
                L.append(f"    sh:property [ sh:path {c[3]} ; sh:minCount {c[4]} ]{term}")
    L.append("")
    return "\n".join(L)


def main() -> int:
    ONTOLOGIES_DIR.mkdir(parents=True, exist_ok=True)
    for system in SYSTEMS:
        mod = importlib.import_module(f"mappings.{system}")
        spec: MappingSpec = mod.SPEC
        # Key files by the namespace PREFIX so they align with the data dir,
        # the semantic models, and the SQL `SYSTEM` variable.
        prefix = spec.namespace_prefix
        tbox = derive_tbox(spec)
        (ONTOLOGIES_DIR / f"{prefix}.sql").write_text(build_sql(spec, tbox), encoding="utf-8")
        (ONTOLOGIES_DIR / f"{prefix}.ttl").write_text(build_ttl(spec, tbox), encoding="utf-8")
        print(f"{system} ({prefix}): {len(tbox['classes'])} classes, "
              f"{len(tbox['properties'])} properties, "
              f"{len(tbox['shapes'])} shapes -> ontologies/{prefix}.sql + .ttl")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
