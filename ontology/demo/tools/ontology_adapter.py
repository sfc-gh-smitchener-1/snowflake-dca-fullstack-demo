#!/usr/bin/env python3
"""Source-system -> ontology adapter.

Turns the relational output of the repository's main synthetic data generator
(`tools/data_generator.py`, which returns ``Dict[table_name -> List[record]]``)
into the demo's triple-store load format:

    individuals.csv          INDIVIDUAL_UID, CANONICAL_IRI, CLASS_IRI, LABEL
    statements_object.csv    STATEMENT_ID, SUBJECT_UID, PREDICATE_IRI, OBJECT_UID
    statements_literal.csv   STATEMENT_ID, SUBJECT_UID, PREDICATE_IRI, OBJECT_LITERAL, OBJECT_DATATYPE

The mapping from a source system's tables/columns to ontology classes and
properties is described declaratively by a :class:`MappingSpec` (one curated
spec per source system lives under ``mappings/``). This module is the generic
engine that consumes a spec plus generated rows and emits the three CSVs; it
has no knowledge of any particular source system.

The output is loaded by ``02b_load_source_ontology.sql`` and is intentionally
column-compatible with the legacy CPG loader's BRONZE landing tables.
"""
from __future__ import annotations

import csv
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Union

# A label can be a column name (str) or a function of the whole record.
LabelSpec = Union[str, Callable[[Dict[str, Any]], str]]


@dataclass
class PropMap:
    """Map a source column to a datatype (literal) property.

    For flat columns set ``column``. For nested record structures (e.g. FHIR
    resources) provide ``getter`` to extract the value from the whole record;
    ``column`` is then only a human-readable label.
    """
    column: str
    predicate_iri: str
    datatype: str = "xsd:string"
    # Optional transform applied to the raw cell value before emitting.
    transform: Optional[Callable[[Any], Any]] = None
    # Optional extractor taking the whole record; overrides ``column`` lookup.
    getter: Optional[Callable[[Dict[str, Any]], Any]] = None


@dataclass
class EdgeMap:
    """Map a source FK column to an object property (an edge between individuals).

    ``target_table`` names another :class:`TableMap` in the same spec; the FK
    value in ``column`` (or extracted by ``getter``) is resolved against that
    table's business ``key`` to find the object individual's UID.
    """
    column: str
    predicate_iri: str
    target_table: str
    # If the FK references a key other than the target's primary key.
    target_key: Optional[str] = None
    # Optional extractor taking the whole record; overrides ``column`` lookup.
    getter: Optional[Callable[[Dict[str, Any]], Any]] = None


@dataclass
class TableMap:
    """How to turn one generated table into individuals + statements."""
    table: str                 # key in the generator's output dict (e.g. "KNA1")
    class_iri: str             # ontology class IRI (e.g. "sap:Customer")
    uid_prefix: str            # UID namespace (e.g. "SAP-CUST")
    # Business key: a column name, or a callable building a composite key.
    key: Union[str, Callable[[Dict[str, Any]], Any]]
    label: Optional[LabelSpec] = None
    literals: List[PropMap] = field(default_factory=list)
    edges: List[EdgeMap] = field(default_factory=list)
    # Local fragment used to build the canonical IRI; defaults to a slug of class.
    iri_local: Optional[str] = None


@dataclass
class MappingSpec:
    system: str                # short system key, e.g. "sap"
    namespace_prefix: str      # ontology prefix, e.g. "sap"
    tables: List[TableMap]

    def table_by_name(self, name: str) -> Optional[TableMap]:
        for t in self.tables:
            if t.table == name:
                return t
        return None


# ---------------------------------------------------------------------------
# Engine
# ---------------------------------------------------------------------------

CSV_HEADERS = {
    "individuals": ["INDIVIDUAL_UID", "CANONICAL_IRI", "CLASS_IRI", "LABEL"],
    "statements_object": ["STATEMENT_ID", "SUBJECT_UID", "PREDICATE_IRI", "OBJECT_UID"],
    "statements_literal": [
        "STATEMENT_ID", "SUBJECT_UID", "PREDICATE_IRI", "OBJECT_LITERAL", "OBJECT_DATATYPE"
    ],
}


def _is_blank(v: Any) -> bool:
    return v is None or (isinstance(v, str) and v.strip() == "")


def _label_for(tm: TableMap, record: Dict[str, Any], uid: str) -> str:
    if tm.label is None:
        return uid
    if callable(tm.label):
        try:
            val = tm.label(record)
        except Exception:
            val = None
    else:
        val = record.get(tm.label)
    if _is_blank(val):
        return uid
    return str(val)


def _iri_local(tm: TableMap) -> str:
    if tm.iri_local:
        return tm.iri_local
    # Strip the "<prefix>:" from the class IRI and lowercase.
    local = tm.class_iri.split(":", 1)[-1]
    return local[0].lower() + local[1:] if local else "thing"


class _Emitter:
    def __init__(self, spec: MappingSpec):
        self.spec = spec
        self.individuals: List[List[str]] = []
        self.obj_stmts: List[List[str]] = []
        self.lit_stmts: List[List[str]] = []
        self._seq = 0
        # business-key value -> uid, per table name
        self._index: Dict[str, Dict[str, str]] = {}

    def _next_id(self, kind: str) -> str:
        self._seq += 1
        return f"{self.spec.system}-{kind}{self._seq:09d}"

    @staticmethod
    def _uid(tm: TableMap, key_value: Any) -> str:
        return f"{tm.uid_prefix}-{key_value}"

    @staticmethod
    def _key_of(tm: TableMap, record: Dict[str, Any]) -> Any:
        return tm.key(record) if callable(tm.key) else record.get(tm.key)

    def build_index(self, data: Dict[str, List[Dict[str, Any]]]) -> None:
        for tm in self.spec.tables:
            rows = data.get(tm.table) or []
            idx: Dict[str, str] = {}
            for r in rows:
                kv = self._key_of(tm, r)
                if _is_blank(kv):
                    continue
                idx[str(kv)] = self._uid(tm, kv)
            self._index[tm.table] = idx

    def emit(self, data: Dict[str, List[Dict[str, Any]]]) -> None:
        self.build_index(data)
        for tm in self.spec.tables:
            rows = data.get(tm.table) or []
            local = _iri_local(tm)
            for r in rows:
                kv = self._key_of(tm, r)
                if _is_blank(kv):
                    continue
                uid = self._uid(tm, kv)
                canonical = f"{self.spec.namespace_prefix}:{local}/{kv}"
                label = _label_for(tm, r, uid)
                self.individuals.append([uid, canonical, tm.class_iri, label])

                for pm in tm.literals:
                    val = pm.getter(r) if pm.getter is not None else r.get(pm.column)
                    if pm.transform is not None and not _is_blank(val):
                        val = pm.transform(val)
                    if _is_blank(val):
                        continue
                    self.lit_stmts.append([
                        self._next_id("sl"), uid, pm.predicate_iri, str(val), pm.datatype
                    ])

                for em in tm.edges:
                    fk = em.getter(r) if em.getter is not None else r.get(em.column)
                    if _is_blank(fk):
                        continue
                    target_idx = self._index.get(em.target_table, {})
                    obj_uid = target_idx.get(str(fk))
                    if obj_uid is None:
                        continue
                    self.obj_stmts.append([
                        self._next_id("so"), uid, em.predicate_iri, obj_uid
                    ])

    # ----- output -----
    def counts(self) -> Dict[str, int]:
        return {
            "individuals": len(self.individuals),
            "statements_object": len(self.obj_stmts),
            "statements_literal": len(self.lit_stmts),
        }

    def write(self, out_dir: Path) -> Dict[str, Path]:
        out_dir.mkdir(parents=True, exist_ok=True)
        paths = {
            "individuals": out_dir / "individuals.csv",
            "statements_object": out_dir / "statements_object.csv",
            "statements_literal": out_dir / "statements_literal.csv",
        }
        rows = {
            "individuals": self.individuals,
            "statements_object": self.obj_stmts,
            "statements_literal": self.lit_stmts,
        }
        for key, path in paths.items():
            with open(path, "w", newline="", encoding="utf-8") as f:
                w = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
                w.writerow(CSV_HEADERS[key])
                w.writerows(rows[key])
        return paths


# ---------------------------------------------------------------------------
# TBox derivation (so the ontology metadata always matches the ABox predicates)
# ---------------------------------------------------------------------------

# schema.org / xsd predicates are provided by the base substrate
# (02_load_synthetic_data.sql) and 00_shared_tbox.sql, so per-source TBox
# loaders never redefine them.
_SHARED_PREFIXES = ("schema", "xsd", "rdf", "rdfs", "owl")

_ORG_LOCALS = {
    "customer", "vendor", "account", "party", "organization", "supplier",
    "campaign", "lead",
}
_PERSON_LOCALS = {
    "employee", "worker", "user", "contact", "patient", "practitioner",
}


def namespace_iri_for(prefix: str) -> str:
    return f"http://example.com/ont/{prefix}/"


def _super_class_for(class_iri: str) -> str:
    local = class_iri.split(":", 1)[-1].lower()
    if local in _ORG_LOCALS:
        return "schema:Organization"
    if local in _PERSON_LOCALS:
        return "schema:Person"
    return "schema:Thing"


def _humanize(local: str) -> str:
    out = []
    for i, ch in enumerate(local):
        if ch.isupper() and i > 0 and not local[i - 1].isupper():
            out.append(" ")
        out.append(ch)
    return "".join(out).strip()


def _is_shared(iri: str) -> bool:
    return iri.split(":", 1)[0] in _SHARED_PREFIXES


def derive_tbox(spec: MappingSpec) -> Dict[str, Any]:
    """Derive namespace/class/property/shape/constraint metadata from a spec.

    Deriving the TBox from the same curated mapping that produces the ABox
    guarantees every ``class_iri`` and ``predicate_iri`` in the data has a
    matching row in the metadata tables (referential integrity at load time).
    Only source-namespace terms are emitted; shared schema.org/xsd terms come
    from the base substrate.
    """
    ns_iri = namespace_iri_for(spec.namespace_prefix)

    classes: Dict[str, tuple] = {}
    for tm in spec.tables:
        if tm.class_iri in classes or _is_shared(tm.class_iri):
            continue
        local = tm.class_iri.split(":", 1)[-1]
        classes[tm.class_iri] = (
            tm.class_iri, ns_iri, _humanize(local),
            f"{spec.system.upper()} {tm.table}", _super_class_for(tm.class_iri),
        )

    # class for each table (needed to resolve object-property ranges)
    table_class = {tm.table: tm.class_iri for tm in spec.tables}

    properties: Dict[str, list] = {}
    for tm in spec.tables:
        for pm in tm.literals:
            if _is_shared(pm.predicate_iri) or pm.predicate_iri in properties:
                continue
            local = pm.predicate_iri.split(":", 1)[-1]
            properties[pm.predicate_iri] = [
                pm.predicate_iri, ns_iri, _humanize(local), "datatype",
                tm.class_iri, None, pm.datatype, 0, 1,
            ]
        for em in tm.edges:
            if _is_shared(em.predicate_iri) or em.predicate_iri in properties:
                continue
            local = em.predicate_iri.split(":", 1)[-1]
            range_class = table_class.get(em.target_table)
            properties[em.predicate_iri] = [
                em.predicate_iri, ns_iri, _humanize(local), "object",
                tm.class_iri, range_class, None, 0, 1,
            ]

    shapes = []
    constraints = []
    seq = 0
    name_classes = {tm.class_iri for tm in spec.tables
                    if any(pm.predicate_iri == "schema:name" for pm in tm.literals)}
    for class_iri in classes:
        local = class_iri.split(":", 1)[-1]
        shape_iri = f"{spec.namespace_prefix}:{local}Shape"
        shapes.append((shape_iri, class_iri, f"{_humanize(local)} data-quality contract"))
        if class_iri in name_classes:
            seq += 1
            constraints.append(
                (f"{spec.system}-c{seq:02d}", shape_iri, "minCount", "schema:name", "1")
            )

    return {
        "namespace": (ns_iri, spec.namespace_prefix,
                      f"{spec.system.upper()} source-system ontology"),
        "classes": list(classes.values()),
        "properties": list(properties.values()),
        "shapes": shapes,
        "constraints": constraints,
    }


def emit_triples(
    spec: MappingSpec,
    data: Dict[str, List[Dict[str, Any]]],
    out_dir: Path,
) -> Dict[str, Any]:
    """Convert generated source rows into triple CSVs using ``spec``.

    Returns a small manifest dict (counts + file paths).
    """
    em = _Emitter(spec)
    em.emit(data)
    paths = em.write(out_dir)
    return {
        "system": spec.system,
        "counts": em.counts(),
        "files": {k: str(v) for k, v in paths.items()},
    }
