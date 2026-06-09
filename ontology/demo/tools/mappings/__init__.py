"""Curated source-system -> ontology mapping specs.

Each module in this package exposes ``SPEC: MappingSpec`` describing how one
source system's generated tables map onto ontology classes and properties.
The mappings are intentionally curated (not auto-derived): table->class choices,
labels, datatype properties, and FK->object-property edges all encode real
domain semantics for that system.
"""

SYSTEMS = ["sap", "salesforce", "oracle", "fhir", "workday", "servicenow"]
