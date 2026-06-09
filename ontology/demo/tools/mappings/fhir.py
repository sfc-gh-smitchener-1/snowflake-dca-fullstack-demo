"""HL7 FHIR R4 -> ontology mapping (curated).

FHIR resources are nested JSON, so most fields are pulled with small extractor
helpers rather than flat column lookups.

Resources (from the main generator's FHIRGenerator):
  Patient           -> fhir:Patient
  Practitioner      -> fhir:Practitioner
  Organization      -> fhir:Organization
  Encounter         -> fhir:Encounter        (subject -> Patient)
  Condition         -> fhir:Condition        (subject -> Patient, encounter -> Encounter)
  Observation       -> fhir:Observation      (subject -> Patient)
  MedicationRequest -> fhir:MedicationRequest(subject -> Patient, requester -> Practitioner)
  Procedure         -> fhir:Procedure        (subject -> Patient, encounter -> Encounter)
  Claim             -> fhir:Claim            (patient -> Patient, provider -> Organization)
"""
from typing import Any, Dict, Optional

from ontology_adapter import EdgeMap, MappingSpec, PropMap, TableMap


def ref_id(field: str):
    """Return a getter that extracts the id from a FHIR reference field."""
    def _get(r: Dict[str, Any]) -> Optional[str]:
        ref = r.get(field)
        if isinstance(ref, dict):
            value = ref.get("reference", "")
            return value.split("/")[-1] if "/" in value else None
        return None
    return _get


def human_name(r: Dict[str, Any]) -> Optional[str]:
    names = r.get("name")
    if isinstance(names, list) and names:
        n = names[0]
        given = " ".join(n.get("given", []) or [])
        return f"{given} {n.get('family', '')}".strip()
    return None


def cc_text(field: str):
    """Getter for a CodeableConcept's display text."""
    def _get(r: Dict[str, Any]) -> Optional[str]:
        cc = r.get(field)
        if isinstance(cc, dict):
            if cc.get("text"):
                return cc["text"]
            coding = cc.get("coding")
            if isinstance(coding, list) and coding:
                return coding[0].get("display")
        return None
    return _get


def cc_code(field: str):
    def _get(r: Dict[str, Any]) -> Optional[str]:
        cc = r.get(field)
        if isinstance(cc, dict):
            coding = cc.get("coding")
            if isinstance(coding, list) and coding:
                return coding[0].get("code")
        return None
    return _get


def identifier_value(system_substr: str):
    def _get(r: Dict[str, Any]) -> Optional[str]:
        for ident in r.get("identifier", []) or []:
            if system_substr in (ident.get("system") or ""):
                return ident.get("value")
        return None
    return _get


def value_quantity(r: Dict[str, Any]) -> Optional[Any]:
    vq = r.get("valueQuantity")
    return vq.get("value") if isinstance(vq, dict) else None


def value_unit(r: Dict[str, Any]) -> Optional[str]:
    vq = r.get("valueQuantity")
    return vq.get("unit") if isinstance(vq, dict) else None


def total_value(r: Dict[str, Any]) -> Optional[Any]:
    t = r.get("total")
    return t.get("value") if isinstance(t, dict) else None


def enc_class(r: Dict[str, Any]) -> Optional[str]:
    c = r.get("class")
    return c.get("display") if isinstance(c, dict) else None


SPEC = MappingSpec(
    system="fhir",
    namespace_prefix="fhir",
    tables=[
        TableMap(
            table="Patient", class_iri="fhir:Patient", uid_prefix="FHIR-PAT", key="id",
            label=human_name,
            literals=[
                PropMap("name", "schema:name", getter=human_name),
                PropMap("identifier", "fhir:mrn", getter=identifier_value("mrn")),
                PropMap("gender", "fhir:gender"),
                PropMap("birthDate", "fhir:birthDate", "xsd:date"),
                PropMap("address", "schema:addressRegion",
                        getter=lambda r: (r.get("address") or [{}])[0].get("state")),
            ],
        ),
        TableMap(
            table="Practitioner", class_iri="fhir:Practitioner", uid_prefix="FHIR-PRAC", key="id",
            label=human_name,
            literals=[
                PropMap("name", "schema:name", getter=human_name),
                PropMap("identifier", "fhir:npi", getter=identifier_value("npi")),
                PropMap("gender", "fhir:gender"),
                PropMap("qualification", "fhir:specialty",
                        getter=lambda r: cc_text("code")((r.get("qualification") or [{}])[0])),
            ],
        ),
        TableMap(
            table="Organization", class_iri="fhir:Organization", uid_prefix="FHIR-ORG", key="id",
            label="name",
            literals=[
                PropMap("name", "schema:name"),
                PropMap("type", "fhir:organizationType", getter=cc_text("type")),
                PropMap("identifier", "fhir:npi", getter=identifier_value("npi")),
            ],
        ),
        TableMap(
            table="Encounter", class_iri="fhir:Encounter", uid_prefix="FHIR-ENC", key="id",
            label=lambda r: f"Encounter ({enc_class(r) or 'visit'})",
            literals=[
                PropMap("status", "fhir:status"),
                PropMap("class", "fhir:encounterClass", getter=enc_class),
                PropMap("type", "schema:name", getter=cc_text("type")),
            ],
            edges=[EdgeMap("subject", "fhir:subject", "Patient", getter=ref_id("subject"))],
        ),
        TableMap(
            table="Condition", class_iri="fhir:Condition", uid_prefix="FHIR-COND", key="id",
            label=cc_text("code"),
            literals=[
                PropMap("code", "schema:name", getter=cc_text("code")),
                PropMap("code", "fhir:icd10Code", getter=cc_code("code")),
                PropMap("clinicalStatus", "fhir:clinicalStatus", getter=cc_text("clinicalStatus")),
                PropMap("severity", "fhir:severity", getter=cc_text("severity")),
                PropMap("onsetDateTime", "fhir:onsetDate", "xsd:date"),
            ],
            edges=[
                EdgeMap("subject", "fhir:subject", "Patient", getter=ref_id("subject")),
                EdgeMap("encounter", "fhir:partOfEncounter", "Encounter", getter=ref_id("encounter")),
            ],
        ),
        TableMap(
            table="Observation", class_iri="fhir:Observation", uid_prefix="FHIR-OBS", key="id",
            label=cc_text("code"),
            literals=[
                PropMap("code", "schema:name", getter=cc_text("code")),
                PropMap("code", "fhir:loincCode", getter=cc_code("code")),
                PropMap("status", "fhir:status"),
                PropMap("valueQuantity", "fhir:value", "xsd:decimal", getter=value_quantity),
                PropMap("valueQuantity", "fhir:unit", getter=value_unit),
            ],
            edges=[EdgeMap("subject", "fhir:subject", "Patient", getter=ref_id("subject"))],
        ),
        TableMap(
            table="MedicationRequest", class_iri="fhir:MedicationRequest", uid_prefix="FHIR-MED",
            key="id", label=cc_text("medicationCodeableConcept"),
            literals=[
                PropMap("medicationCodeableConcept", "schema:name",
                        getter=cc_text("medicationCodeableConcept")),
                PropMap("medicationCodeableConcept", "fhir:rxNormCode",
                        getter=cc_code("medicationCodeableConcept")),
                PropMap("status", "fhir:status"),
                PropMap("intent", "fhir:intent"),
            ],
            edges=[
                EdgeMap("subject", "fhir:subject", "Patient", getter=ref_id("subject")),
                EdgeMap("requester", "fhir:requester", "Practitioner", getter=ref_id("requester")),
            ],
        ),
        TableMap(
            table="Procedure", class_iri="fhir:Procedure", uid_prefix="FHIR-PROC", key="id",
            label=cc_text("code"),
            literals=[
                PropMap("code", "schema:name", getter=cc_text("code")),
                PropMap("code", "fhir:snomedCode", getter=cc_code("code")),
                PropMap("status", "fhir:status"),
                PropMap("performedDateTime", "fhir:performedDate"),
            ],
            edges=[
                EdgeMap("subject", "fhir:subject", "Patient", getter=ref_id("subject")),
                EdgeMap("encounter", "fhir:partOfEncounter", "Encounter", getter=ref_id("encounter")),
            ],
        ),
        TableMap(
            table="Claim", class_iri="fhir:Claim", uid_prefix="FHIR-CLM", key="id",
            label=lambda r: f"Claim {r.get('id', '')[:8]}",
            literals=[
                PropMap("type", "fhir:claimType", getter=cc_text("type")),
                PropMap("status", "fhir:status"),
                PropMap("use", "fhir:use"),
                PropMap("total", "fhir:totalValue", "xsd:decimal", getter=total_value),
                PropMap("created", "fhir:createdDate", "xsd:date"),
            ],
            edges=[
                EdgeMap("patient", "fhir:subject", "Patient", getter=ref_id("patient")),
                EdgeMap("provider", "fhir:provider", "Organization", getter=ref_id("provider")),
            ],
        ),
    ],
)
