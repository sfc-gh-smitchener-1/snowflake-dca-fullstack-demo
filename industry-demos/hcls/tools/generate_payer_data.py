#!/usr/bin/env python3
"""
Payer / Claims Adjudication Data Generator

Generates realistic synthetic payer data for the HCLS DCA demo:
  - plans: 50 insurance plan definitions
  - members: 10,000 plan memberships linked to FHIR patients
  - coverage_periods: 12,000 enrollment history records
  - claims_detail: 80,000 line-level claims
  - prior_authorizations: 15,000 prior auth requests
  - utilization_reviews: 10,000 medical necessity reviews
  - plan_of_care: 25,000 care plans with payer involvement
  - quality_measures: 5,000 HEDIS/STAR ratings per member

Usage:
    python generate_payer_data.py --output ../data
    python generate_payer_data.py --output ../data --quick       # Small test set
    python generate_payer_data.py --output ../data --scale 2.0   # Double size
"""

import os
import sys
import random
import hashlib
import json
import csv
import argparse
import uuid
from datetime import datetime, timedelta, date
from typing import List, Dict, Any

# Import base generator infrastructure from the core data_generator
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', '..', 'tools'))
from data_generator import SourceSystemGenerator, save_to_csv as base_save_to_csv

try:
    from faker import Faker
except ImportError:
    print("ERROR: Faker not installed. Run: pip install faker")
    sys.exit(1)


# ============================================================================
# REFERENCE DATA
# ============================================================================

PAYER_NAMES = [
    "UnitedHealthcare", "Aetna", "Cigna", "Blue Cross", "Humana",
    "Kaiser", "Centene", "Molina", "Anthem", "Oscar",
]

PLAN_TYPES = [
    ("HMO", 0.20), ("PPO", 0.25), ("POS", 0.08), ("HDHP", 0.15),
    ("MEDICARE_ADVANTAGE", 0.15), ("MEDICAID_MANAGED", 0.10), ("EXCHANGE", 0.07),
]

NETWORK_TIERS = ["IN_NETWORK", "OUT_OF_NETWORK", "PREFERRED"]
FORMULARY_TIERS = ["TIER_1_GENERIC", "TIER_2_PREFERRED", "TIER_3_NON_PREFERRED", "TIER_4_SPECIALTY"]

COVERAGE_TYPES = ["MEDICAL", "DENTAL", "VISION", "PHARMACY", "BEHAVIORAL_HEALTH"]
COVERAGE_STATUSES = ["ACTIVE", "TERMED", "COBRA", "PENDING"]
MEMBER_RELATIONSHIPS = ["SELF", "SPOUSE", "DEPENDENT"]

# Claim status with denial rates varying by payer type
CLAIM_STATUSES = ["PAID", "DENIED", "PENDING", "ADJUSTED", "APPEALED"]

# Denial reason codes
DENIAL_REASONS = {
    "CO-4": "The procedure code is inconsistent with the modifier",
    "CO-45": "Charges exceed your contracted/legislated fee arrangement",
    "CO-50": "Non-covered services",
    "CO-96": "Non-covered charge(s)",
    "CO-97": "Payment adjusted due to benefit maximum",
    "CO-197": "Precertification/authorization/notification absent",
    "PR-1": "Deductible amount",
    "PR-2": "Coinsurance amount",
    "PR-3": "Co-payment amount",
    "OA-23": "Payment adjusted due to impact of prior payer(s) adjudication",
}

# CPT codes for claims
CPT_CODES = [
    ("99213", "Office visit, established, low"), ("99214", "Office visit, established, moderate"),
    ("99284", "ED visit, high complexity"), ("99285", "ED visit, highest complexity"),
    ("99223", "Initial hospital care, high"), ("27447", "Total knee replacement"),
    ("27130", "Total hip replacement"), ("43239", "Upper GI endoscopy with biopsy"),
    ("45378", "Colonoscopy, diagnostic"), ("93000", "ECG, 12-lead"),
    ("71046", "Chest X-ray, 2 views"), ("70553", "MRI brain w/wo contrast"),
    ("74177", "CT abdomen/pelvis w/ contrast"), ("93306", "Echocardiography"),
    ("36415", "Venipuncture"), ("99232", "Subsequent hospital care"),
    ("47562", "Lap cholecystectomy"), ("92928", "PCI stent placement"),
    ("33533", "CABG, single"), ("20610", "Joint injection, major"),
]

# ICD-10 codes for claims and conditions
ICD10_CODES = [
    ("E11.9", "Type 2 diabetes without complications"),
    ("I10", "Essential hypertension"),
    ("E78.5", "Hyperlipidemia, unspecified"),
    ("I50.9", "Heart failure, unspecified"),
    ("N18.3", "Chronic kidney disease, stage 3"),
    ("J44.1", "COPD with acute exacerbation"),
    ("I48.91", "Unspecified atrial fibrillation"),
    ("E66.9", "Obesity, unspecified"),
    ("J18.9", "Pneumonia, unspecified"),
    ("I25.10", "Atherosclerotic heart disease"),
    ("G47.33", "Obstructive sleep apnea"),
    ("M54.5", "Low back pain"),
    ("F32.9", "Major depressive disorder"),
    ("K21.0", "GERD with esophagitis"),
    ("N39.0", "Urinary tract infection"),
    ("I63.9", "Cerebral infarction"),
    ("C50.919", "Breast cancer, unspecified"),
    ("C34.90", "Lung cancer, unspecified"),
    ("D64.9", "Anemia, unspecified"),
    ("E03.9", "Hypothyroidism, unspecified"),
]

# High-comorbidity ICD-10 triad: diabetes + hypertension + CKD
HIGH_COMORBIDITY_CODES = {"E11.9", "I10", "N18.3"}

PLACE_OF_SERVICE = [
    ("11", "Office"), ("21", "Inpatient Hospital"), ("22", "Outpatient Hospital"),
    ("23", "Emergency Room"), ("31", "Skilled Nursing Facility"),
    ("32", "Nursing Facility"), ("51", "Inpatient Psychiatric"), ("81", "Independent Lab"),
]

PRIOR_AUTH_URGENCY = ["ROUTINE", "URGENT", "EMERGENT"]
PRIOR_AUTH_STATUS = ["APPROVED", "DENIED", "PENDING", "EXPIRED", "PARTIALLY_APPROVED"]

REVIEW_TYPES = ["PRECERTIFICATION", "CONCURRENT", "RETROSPECTIVE"]
LEVELS_OF_CARE = ["INPATIENT", "OBSERVATION", "SNF", "REHAB", "HOME_HEALTH"]
REVIEWER_TYPES = ["RN", "MD", "ALGORITHM"]
CLINICAL_CRITERIA = ["INTERQUAL", "MILLIMAN", "MCG"]
UR_DETERMINATIONS = ["APPROVED", "DENIED", "MODIFIED", "PEND_INFO"]

INTERVENTION_TYPES = ["MEDICATION", "THERAPY", "DME", "HOME_HEALTH", "BEHAVIORAL", "SURGERY"]
POC_STATUSES = ["ACTIVE", "COMPLETED", "DISCONTINUED", "EXPIRED"]

# HEDIS/STAR quality measure codes
QUALITY_MEASURE_CODES = [
    ("CDC_HBA1C", "Comprehensive Diabetes Care: HbA1c Testing"),
    ("BCS", "Breast Cancer Screening"),
    ("COL", "Colorectal Cancer Screening"),
    ("PCR", "Plan All-Cause Readmissions"),
    ("PQA_PDC_DIABETES", "Proportion of Days Covered: Diabetes Medications"),
    ("PQA_PDC_HTN", "Proportion of Days Covered: Hypertension Medications"),
    ("AMB_ED", "Ambulatory Care: ED Visits"),
    ("IET", "Initiation/Engagement of Alcohol/Drug Treatment"),
]

# Denial rates by plan type
DENIAL_RATES = {
    "MEDICARE_ADVANTAGE": 0.08,
    "PPO": 0.12,
    "HMO": 0.13,
    "POS": 0.13,
    "MEDICAID_MANAGED": 0.15,
    "EXCHANGE": 0.16,
    "HDHP": 0.18,
}

# Prior auth category CPT ranges requiring authorization
PRIOR_AUTH_CPT_CATEGORIES = [
    "27xxx", "33xxx", "43xxx", "47xxx", "59xxx",  # surgeries
    "70xxx", "71xxx", "72xxx", "73xxx", "74xxx",  # imaging
    "92xxx", "93xxx",  # cardiac testing
]

DEFAULT_COUNTS = {
    'plans': 50,
    'members': 10000,
    'coverage_periods': 12000,
    'claims_detail': 80000,
    'prior_authorizations': 15000,
    'utilization_reviews': 10000,
    'plan_of_care': 25000,
    'quality_measures': 5000,
}


# ============================================================================
# GENERATOR
# ============================================================================

class PayerGenerator(SourceSystemGenerator):
    """Generates synthetic payer/claims adjudication data for healthcare analytics."""

    SYSTEM_NAME = "PAYER"

    def __init__(self, seed: int = 42):
        self.seed = seed
        random.seed(seed)
        self.fake = Faker('en_US')
        self.fake.seed_instance(seed)
        self.plans: List[Dict] = []
        self.members: List[Dict] = []
        # Track high-comorbidity patients (diabetes + hypertension + CKD)
        self.high_comorbidity_member_ids: set = set()

    def _hash(self, record: Dict) -> str:
        data = {k: v for k, v in record.items() if not k.startswith('_')}
        return hashlib.sha256(json.dumps(data, sort_keys=True, default=str).encode()).hexdigest()

    def _get_denial_rate(self, plan_type: str) -> float:
        """Get denial rate based on plan type."""
        return DENIAL_RATES.get(plan_type, 0.12)

    # ------------------------------------------------------------------
    # PLANS
    # ------------------------------------------------------------------
    def generate_plans(self, count: int) -> List[Dict]:
        print(f"  Generating {count} plans...")
        records = []

        for i in range(count):
            plan_type = random.choices(
                [pt[0] for pt in PLAN_TYPES],
                weights=[pt[1] for pt in PLAN_TYPES]
            )[0]
            payer_name = random.choice(PAYER_NAMES)
            network_tier = random.choice(NETWORK_TIERS)

            # Deductible and costs vary by plan type
            if plan_type == "HDHP":
                annual_deductible = random.choice([1500, 2000, 2800, 3000, 5000])
                max_oop = random.choice([5000, 6500, 7000, 8000])
                copay_primary = 0  # HDHP uses coinsurance after deductible
                copay_specialist = 0
                copay_emergency = 0
                coinsurance_rate = round(random.uniform(0.10, 0.30), 2)
            elif plan_type == "HMO":
                annual_deductible = random.choice([0, 250, 500])
                max_oop = random.choice([3000, 4000, 5000, 6000])
                copay_primary = random.choice([10, 15, 20, 25])
                copay_specialist = random.choice([25, 35, 40, 50])
                copay_emergency = random.choice([100, 150, 200, 250])
                coinsurance_rate = round(random.uniform(0.10, 0.20), 2)
            elif plan_type in ("MEDICARE_ADVANTAGE", "MEDICAID_MANAGED"):
                annual_deductible = random.choice([0, 100, 200])
                max_oop = random.choice([3000, 4000, 5000])
                copay_primary = random.choice([0, 5, 10])
                copay_specialist = random.choice([10, 20, 30])
                copay_emergency = random.choice([50, 75, 100])
                coinsurance_rate = round(random.uniform(0.0, 0.20), 2)
            else:  # PPO, POS, EXCHANGE
                annual_deductible = random.choice([500, 750, 1000, 1500, 2000])
                max_oop = random.choice([4000, 5000, 6000, 7000, 8000])
                copay_primary = random.choice([20, 25, 30, 35])
                copay_specialist = random.choice([35, 40, 50, 60])
                copay_emergency = random.choice([150, 200, 250, 300])
                coinsurance_rate = round(random.uniform(0.15, 0.30), 2)

            formulary_tier = random.choice(FORMULARY_TIERS)

            # Prior auth required categories
            num_categories = random.randint(2, 5)
            prior_auth_cats = random.sample(PRIOR_AUTH_CPT_CATEGORIES, num_categories)

            plan_name = f"{payer_name} {plan_type.replace('_', ' ').title()} {chr(65 + (i % 26))}{i // 26 + 1}"

            rec = {
                'plan_id': str(uuid.uuid5(uuid.NAMESPACE_OID, f"plan_{self.seed}_{i}")),
                'plan_name': plan_name,
                'plan_type': plan_type,
                'payer_name': payer_name,
                'network_tier': network_tier,
                'formulary_tier': formulary_tier,
                'annual_deductible': annual_deductible,
                'max_oop': max_oop,
                'copay_primary': copay_primary,
                'copay_specialist': copay_specialist,
                'copay_emergency': copay_emergency,
                'coinsurance_rate': coinsurance_rate,
                'prior_auth_required_categories': json.dumps(prior_auth_cats),
                'created_at': datetime.now().isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        self.plans = records
        return records

    # ------------------------------------------------------------------
    # MEMBERS
    # ------------------------------------------------------------------
    def generate_members(self, count: int) -> List[Dict]:
        if not self.plans:
            raise ValueError("Must generate plans first")
        print(f"  Generating {count} members...")
        records = []

        for i in range(count):
            # CRITICAL: Use same uuid5 pattern as generate_hcls_data.py for patient linkage
            patient_id = str(uuid.uuid5(uuid.NAMESPACE_OID, f"patient_{self.seed}_{i}"))
            plan = random.choice(self.plans)

            effective_date = self.fake.date_between(start_date='-5y', end_date='-30d')
            # ~10% have terminated
            terminated = random.random() < 0.10
            termination_date = (effective_date + timedelta(days=random.randint(180, 1825))).isoformat() if terminated else ''

            relationship = random.choices(
                MEMBER_RELATIONSHIPS,
                weights=[0.65, 0.20, 0.15]
            )[0]

            # PCP practitioner (use same uuid5 pattern as FHIR)
            pcp_idx = random.randint(0, 499)  # 500 practitioners in FHIR
            pcp_practitioner_id = str(uuid.uuid5(uuid.NAMESPACE_OID, f"practitioner_{self.seed}_{pcp_idx}"))

            rec = {
                'member_id': str(uuid.uuid5(uuid.NAMESPACE_OID, f"member_{self.seed}_{i}")),
                'patient_id': patient_id,
                'plan_id': plan['plan_id'],
                'subscriber_id': f"SUB-{800000 + i:08d}",
                'group_number': f"GRP-{random.randint(1000, 9999)}",
                'effective_date': effective_date.isoformat(),
                'termination_date': termination_date,
                'relationship': relationship,
                'pcp_practitioner_id': pcp_practitioner_id,
                'created_at': datetime.now().isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        self.members = records

        # Mark ~8% as high-comorbidity for correlation
        high_comorbid_count = int(count * 0.08)
        high_comorbid_indices = random.sample(range(count), high_comorbid_count)
        self.high_comorbidity_member_ids = {self.members[idx]['member_id'] for idx in high_comorbid_indices}

        return records

    # ------------------------------------------------------------------
    # COVERAGE PERIODS
    # ------------------------------------------------------------------
    def generate_coverage_periods(self, count: int) -> List[Dict]:
        if not self.members or not self.plans:
            raise ValueError("Must generate members and plans first")
        print(f"  Generating {count} coverage periods...")
        records = []

        for i in range(count):
            member = random.choice(self.members)
            plan = random.choice(self.plans)

            start_date = self.fake.date_between(start_date='-5y', end_date='-30d')
            end_date = start_date + timedelta(days=random.randint(90, 730))
            coverage_type = random.choices(
                COVERAGE_TYPES,
                weights=[0.50, 0.15, 0.10, 0.15, 0.10]
            )[0]
            status = random.choices(
                COVERAGE_STATUSES,
                weights=[0.60, 0.25, 0.05, 0.10]
            )[0]

            rec = {
                'coverage_id': str(uuid.uuid5(uuid.NAMESPACE_OID, f"coverage_{self.seed}_{i}")),
                'member_id': member['member_id'],
                'plan_id': plan['plan_id'],
                'start_date': start_date.isoformat(),
                'end_date': end_date.isoformat(),
                'coverage_type': coverage_type,
                'status': status,
                'created_at': datetime.now().isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        return records

    # ------------------------------------------------------------------
    # CLAIMS DETAIL
    # ------------------------------------------------------------------
    def generate_claims_detail(self, count: int) -> List[Dict]:
        if not self.members or not self.plans:
            raise ValueError("Must generate members and plans first")
        print(f"  Generating {count} claims detail records...")
        records = []

        # Build member-to-plan lookup for denial rates
        member_plan_map = {}
        for m in self.members:
            plan = next((p for p in self.plans if p['plan_id'] == m['plan_id']), None)
            if plan:
                member_plan_map[m['member_id']] = plan

        for i in range(count):
            # High-comorbidity patients generate more claims (weighted selection)
            if random.random() < 0.25 and self.high_comorbidity_member_ids:
                member_id = random.choice(list(self.high_comorbidity_member_ids))
                member = next((m for m in self.members if m['member_id'] == member_id), random.choice(self.members))
            else:
                member = random.choice(self.members)

            patient_id = member['patient_id']
            plan = member_plan_map.get(member['member_id'])
            plan_type = plan['plan_type'] if plan else "PPO"

            # Encounter linkage: use FHIR encounter uuid5 pattern
            encounter_idx = random.randint(0, 49999)  # 50k encounters in FHIR
            encounter_id = str(uuid.uuid5(uuid.NAMESPACE_OID, f"encounter_{self.seed}_{encounter_idx}"))

            service_date = self.fake.date_between(start_date='-3y', end_date='today')
            cpt_code, cpt_desc = random.choice(CPT_CODES)
            icd_primary_code, icd_primary_desc = random.choice(ICD10_CODES)
            icd_secondary_code, icd_secondary_desc = random.choice(ICD10_CODES)

            # DRG for inpatient
            pos_code, pos_desc = random.choice(PLACE_OF_SERVICE)
            drg_code = f"{random.randint(1, 999):03d}" if pos_code == "21" else ''

            # NPI for providers
            rendering_npi = f"{random.randint(1000000000, 9999999999)}"
            billing_npi = f"{random.randint(1000000000, 9999999999)}"

            # Amounts based on place of service
            if pos_code == "21":  # Inpatient
                billed_amount = round(random.uniform(5000, 150000), 2)
            elif pos_code == "23":  # ER
                billed_amount = round(random.uniform(500, 25000), 2)
            elif pos_code == "31":  # SNF
                billed_amount = round(random.uniform(2000, 30000), 2)
            else:
                billed_amount = round(random.uniform(75, 5000), 2)

            allowed_amount = round(billed_amount * random.uniform(0.55, 0.90), 2)

            # Denial rate based on plan type + comorbidity
            denial_rate = self._get_denial_rate(plan_type)
            if member['member_id'] in self.high_comorbidity_member_ids:
                denial_rate *= 1.5  # 50% more denials for high-comorbidity

            # Determine claim status
            if random.random() < denial_rate:
                claim_status = "DENIED"
                paid_amount = 0.0
                denial_code = random.choice(list(DENIAL_REASONS.keys()))
                denial_desc = DENIAL_REASONS[denial_code]
                # Some denials get appealed
                if random.random() < 0.30:
                    claim_status = "APPEALED"
            else:
                claim_status = random.choices(
                    ["PAID", "PENDING", "ADJUSTED"],
                    weights=[0.80, 0.12, 0.08]
                )[0]
                denial_code = ''
                denial_desc = ''
                if claim_status == "PAID":
                    paid_amount = round(allowed_amount * random.uniform(0.70, 1.00), 2)
                elif claim_status == "ADJUSTED":
                    paid_amount = round(allowed_amount * random.uniform(0.50, 0.85), 2)
                else:  # PENDING
                    paid_amount = 0.0

            copay = plan['copay_primary'] if plan else 25.0
            coinsurance = round(allowed_amount * (plan['coinsurance_rate'] if plan else 0.20), 2)
            deductible_applied = round(random.uniform(0, min(500, allowed_amount * 0.20)), 2)
            patient_responsibility = round(copay + coinsurance + deductible_applied, 2)

            adjudication_date = service_date + timedelta(days=random.randint(7, 90))
            days_to_adjudicate = (adjudication_date - service_date).days

            # High-comorbidity patients take longer to adjudicate
            if member['member_id'] in self.high_comorbidity_member_ids:
                days_to_adjudicate = int(days_to_adjudicate * random.uniform(1.3, 2.0))
                adjudication_date = service_date + timedelta(days=days_to_adjudicate)

            rec = {
                'claim_id': str(uuid.uuid5(uuid.NAMESPACE_OID, f"claim_{self.seed}_{i}")),
                'claim_line_id': f"{i + 1:06d}-01",
                'member_id': member['member_id'],
                'patient_id': patient_id,
                'encounter_id': encounter_id,
                'service_date': service_date.isoformat(),
                'cpt_code': cpt_code,
                'cpt_description': cpt_desc,
                'icd10_primary': icd_primary_code,
                'icd10_secondary': icd_secondary_code,
                'drg_code': drg_code,
                'place_of_service': pos_code,
                'rendering_provider_npi': rendering_npi,
                'billing_provider_npi': billing_npi,
                'billed_amount': billed_amount,
                'allowed_amount': allowed_amount,
                'paid_amount': paid_amount,
                'copay': copay,
                'coinsurance': coinsurance,
                'deductible_applied': deductible_applied,
                'patient_responsibility': patient_responsibility,
                'claim_status': claim_status,
                'denial_reason_code': denial_code,
                'denial_reason_description': denial_desc,
                'adjudication_date': adjudication_date.isoformat() if claim_status != "PENDING" else '',
                'days_to_adjudicate': days_to_adjudicate if claim_status != "PENDING" else None,
                'created_at': datetime.now().isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        return records

    # ------------------------------------------------------------------
    # PRIOR AUTHORIZATIONS
    # ------------------------------------------------------------------
    def generate_prior_authorizations(self, count: int) -> List[Dict]:
        if not self.members:
            raise ValueError("Must generate members first")
        print(f"  Generating {count} prior authorizations...")
        records = []

        for i in range(count):
            # High-comorbidity patients need more auths
            if random.random() < 0.30 and self.high_comorbidity_member_ids:
                member_id = random.choice(list(self.high_comorbidity_member_ids))
                member = next((m for m in self.members if m['member_id'] == member_id), random.choice(self.members))
            else:
                member = random.choice(self.members)

            requesting_npi = f"{random.randint(1000000000, 9999999999)}"

            procedure_code, procedure_desc = random.choice(CPT_CODES)
            diagnosis_code, diagnosis_desc = random.choice(ICD10_CODES)

            urgency = random.choices(
                PRIOR_AUTH_URGENCY,
                weights=[0.65, 0.25, 0.10]
            )[0]

            request_date = self.fake.date_between(start_date='-2y', end_date='today')

            # Decision time based on urgency
            if urgency == "ROUTINE":
                days_to_decision = random.randint(3, 14)
            elif urgency == "URGENT":
                days_to_decision = random.randint(1, 3)
            else:  # EMERGENT
                days_to_decision = 0  # same-day

            # High-comorbidity patients have longer auth times
            if member['member_id'] in self.high_comorbidity_member_ids:
                days_to_decision = int(days_to_decision * random.uniform(1.3, 2.5))

            decision_date = request_date + timedelta(days=days_to_decision)

            # Status determination
            status = random.choices(
                PRIOR_AUTH_STATUS,
                weights=[0.55, 0.18, 0.10, 0.07, 0.10]
            )[0]

            # High-comorbidity patients get more denials
            if member['member_id'] in self.high_comorbidity_member_ids and random.random() < 0.15:
                status = "DENIED"

            approved_units = 0
            approved_duration_days = 0
            denial_reason = ''
            appeal_status = ''
            clinical_rationale = ''

            if status in ("APPROVED", "PARTIALLY_APPROVED"):
                approved_units = random.randint(1, 20)
                approved_duration_days = random.randint(7, 180)
                clinical_rationale = "Meets medical necessity criteria per clinical guidelines"
            elif status == "DENIED":
                denial_reason = random.choice([
                    "Does not meet medical necessity criteria",
                    "Alternative treatment available",
                    "Insufficient clinical documentation",
                    "Experimental/investigational procedure",
                    "Out-of-network provider, in-network alternative available",
                ])
                appeal_status = random.choices(
                    ["NOT_APPEALED", "APPEAL_PENDING", "APPEAL_APPROVED", "APPEAL_DENIED"],
                    weights=[0.50, 0.20, 0.15, 0.15]
                )[0]
                clinical_rationale = "Does not meet criteria per clinical review guidelines"

            reviewer_id = f"REV-{random.randint(1000, 9999)}"

            rec = {
                'auth_id': str(uuid.uuid5(uuid.NAMESPACE_OID, f"auth_{self.seed}_{i}")),
                'member_id': member['member_id'],
                'requesting_provider_npi': requesting_npi,
                'procedure_code': procedure_code,
                'procedure_description': procedure_desc,
                'diagnosis_code': diagnosis_code,
                'diagnosis_description': diagnosis_desc,
                'urgency': urgency,
                'status': status,
                'request_date': request_date.isoformat(),
                'decision_date': decision_date.isoformat() if status != "PENDING" else '',
                'days_to_decision': days_to_decision if status != "PENDING" else None,
                'approved_units': approved_units,
                'approved_duration_days': approved_duration_days,
                'denial_reason': denial_reason,
                'appeal_status': appeal_status,
                'reviewer_id': reviewer_id,
                'clinical_rationale': clinical_rationale,
                'created_at': datetime.now().isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        return records

    # ------------------------------------------------------------------
    # UTILIZATION REVIEWS
    # ------------------------------------------------------------------
    def generate_utilization_reviews(self, count: int) -> List[Dict]:
        if not self.members:
            raise ValueError("Must generate members first")
        print(f"  Generating {count} utilization reviews...")
        records = []

        for i in range(count):
            member = random.choice(self.members)

            # Encounter linkage
            encounter_idx = random.randint(0, 49999)
            encounter_id = str(uuid.uuid5(uuid.NAMESPACE_OID, f"encounter_{self.seed}_{encounter_idx}"))

            review_type = random.choices(
                REVIEW_TYPES,
                weights=[0.40, 0.35, 0.25]
            )[0]

            loc_requested = random.choices(
                LEVELS_OF_CARE,
                weights=[0.35, 0.20, 0.15, 0.15, 0.15]
            )[0]

            # Sometimes approved at a different level
            if random.random() < 0.20:
                loc_approved = random.choice(LEVELS_OF_CARE)
            else:
                loc_approved = loc_requested

            review_date = self.fake.date_between(start_date='-2y', end_date='today')
            reviewer_type = random.choices(REVIEWER_TYPES, weights=[0.45, 0.35, 0.20])[0]
            clinical_criteria = random.choice(CLINICAL_CRITERIA)

            determination = random.choices(
                UR_DETERMINATIONS,
                weights=[0.55, 0.18, 0.15, 0.12]
            )[0]

            # Approved days and variance
            if loc_requested == "INPATIENT":
                approved_days = random.randint(1, 14)
                actual_days = approved_days + random.randint(-2, 5)
            elif loc_requested == "SNF":
                approved_days = random.randint(7, 60)
                actual_days = approved_days + random.randint(-5, 15)
            elif loc_requested == "REHAB":
                approved_days = random.randint(5, 30)
                actual_days = approved_days + random.randint(-3, 10)
            else:
                approved_days = random.randint(1, 7)
                actual_days = approved_days + random.randint(-1, 3)

            actual_days = max(1, actual_days)
            variance_days = actual_days - approved_days

            # Cost savings estimate
            daily_cost = random.uniform(800, 3500)
            cost_savings = round(max(0, variance_days * -1 * daily_cost), 2) if variance_days < 0 else 0.0

            rec = {
                'review_id': str(uuid.uuid5(uuid.NAMESPACE_OID, f"ur_{self.seed}_{i}")),
                'member_id': member['member_id'],
                'encounter_id': encounter_id,
                'review_type': review_type,
                'level_of_care_requested': loc_requested,
                'level_of_care_approved': loc_approved,
                'review_date': review_date.isoformat(),
                'reviewer_type': reviewer_type,
                'clinical_criteria': clinical_criteria,
                'determination': determination,
                'approved_days': approved_days,
                'actual_days': actual_days,
                'variance_days': variance_days,
                'cost_savings_estimate': cost_savings,
                'created_at': datetime.now().isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        return records

    # ------------------------------------------------------------------
    # PLAN OF CARE
    # ------------------------------------------------------------------
    def generate_plan_of_care(self, count: int) -> List[Dict]:
        if not self.members:
            raise ValueError("Must generate members first")
        print(f"  Generating {count} plan of care records...")
        records = []

        # Condition descriptions for care plans
        care_conditions = [
            ("E11.9", "Type 2 Diabetes Management"),
            ("I10", "Hypertension Management"),
            ("I50.9", "Heart Failure Care"),
            ("N18.3", "CKD Stage 3 Management"),
            ("J44.1", "COPD Management"),
            ("M54.5", "Chronic Pain Management"),
            ("F32.9", "Depression Treatment"),
            ("E66.9", "Obesity/Weight Management"),
            ("I25.10", "Coronary Artery Disease Care"),
            ("I48.91", "Atrial Fibrillation Management"),
        ]

        goal_templates = [
            "Maintain HbA1c below 7.0%",
            "Achieve blood pressure below 130/80",
            "Reduce readmission risk",
            "Improve functional mobility",
            "Reduce pain to manageable levels",
            "Achieve medication adherence >80%",
            "Complete recommended screenings",
            "Stabilize weight within target range",
            "Improve depression screening scores",
            "Maintain eGFR above baseline",
        ]

        outcome_measures = [
            "HbA1c", "Blood Pressure", "PHQ-9 Score", "6-Minute Walk Distance",
            "Pain Scale (0-10)", "PDC Ratio", "BMI", "eGFR", "BNP Level", "LDL Cholesterol",
        ]

        for i in range(count):
            member = random.choice(self.members)

            # Encounter linkage
            encounter_idx = random.randint(0, 49999)
            encounter_id = str(uuid.uuid5(uuid.NAMESPACE_OID, f"encounter_{self.seed}_{encounter_idx}"))

            condition_code, condition_desc = random.choice(care_conditions)
            goal = random.choice(goal_templates)
            intervention_type = random.choice(INTERVENTION_TYPES)

            responsible_npi = f"{random.randint(1000000000, 9999999999)}"

            start_date = self.fake.date_between(start_date='-2y', end_date='-30d')
            target_duration = random.randint(30, 365)
            target_end_date = start_date + timedelta(days=target_duration)

            status = random.choices(POC_STATUSES, weights=[0.40, 0.30, 0.15, 0.15])[0]

            if status == "COMPLETED":
                actual_end_date = target_end_date + timedelta(days=random.randint(-30, 30))
            elif status == "DISCONTINUED":
                actual_end_date = start_date + timedelta(days=random.randint(7, target_duration // 2))
            else:
                actual_end_date = None

            payer_approved = random.random() < 0.72
            approved_visits = random.randint(4, 52) if payer_approved else 0
            used_visits = random.randint(0, approved_visits) if payer_approved else 0

            outcome_measure = random.choice(outcome_measures)
            outcome_value = round(random.uniform(0.5, 15.0), 1)

            rec = {
                'poc_id': str(uuid.uuid5(uuid.NAMESPACE_OID, f"poc_{self.seed}_{i}")),
                'member_id': member['member_id'],
                'encounter_id': encounter_id,
                'condition_code': condition_code,
                'condition_description': condition_desc,
                'goal_description': goal,
                'intervention_type': intervention_type,
                'responsible_provider_npi': responsible_npi,
                'start_date': start_date.isoformat(),
                'target_end_date': target_end_date.isoformat(),
                'actual_end_date': actual_end_date.isoformat() if actual_end_date else '',
                'payer_approved': payer_approved,
                'approved_visits': approved_visits,
                'used_visits': used_visits,
                'status': status,
                'outcome_measure': outcome_measure,
                'outcome_value': outcome_value,
                'created_at': datetime.now().isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        return records

    # ------------------------------------------------------------------
    # QUALITY MEASURES
    # ------------------------------------------------------------------
    def generate_quality_measures(self, count: int) -> List[Dict]:
        if not self.members:
            raise ValueError("Must generate members first")
        print(f"  Generating {count} quality measures...")
        records = []

        for i in range(count):
            member = random.choice(self.members)
            measure_code, measure_name = random.choice(QUALITY_MEASURE_CODES)

            measurement_year = random.choice([2022, 2023, 2024, 2025])

            # Numerator/denominator flags
            denominator_flag = True  # All selected members are in denominator
            exclusion_flag = random.random() < 0.05
            numerator_flag = not exclusion_flag and random.random() < 0.72

            # Value and benchmark
            value = round(random.uniform(0.40, 1.00), 3) if numerator_flag else round(random.uniform(0.10, 0.50), 3)
            benchmark = round(random.uniform(0.75, 0.95), 3)

            # Star rating based on value vs benchmark
            if value >= benchmark * 1.05:
                star_rating = 5
            elif value >= benchmark:
                star_rating = 4
            elif value >= benchmark * 0.90:
                star_rating = 3
            elif value >= benchmark * 0.75:
                star_rating = 2
            else:
                star_rating = 1

            gap_in_care = not numerator_flag and not exclusion_flag

            rec = {
                'measure_id': str(uuid.uuid5(uuid.NAMESPACE_OID, f"qm_{self.seed}_{i}")),
                'member_id': member['member_id'],
                'measure_code': measure_code,
                'measure_name': measure_name,
                'measurement_year': measurement_year,
                'numerator_flag': numerator_flag,
                'denominator_flag': denominator_flag,
                'exclusion_flag': exclusion_flag,
                'value': value,
                'benchmark': benchmark,
                'star_rating': star_rating,
                'gap_in_care': gap_in_care,
                'created_at': datetime.now().isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        return records

    # ------------------------------------------------------------------
    # ORCHESTRATOR
    # ------------------------------------------------------------------
    def generate(self, counts: Dict[str, int]) -> Dict[str, List[Dict]]:
        data = {}
        data['plans'] = self.generate_plans(counts.get('plans', 50))
        data['members'] = self.generate_members(counts.get('members', 10000))
        data['coverage_periods'] = self.generate_coverage_periods(counts.get('coverage_periods', 12000))
        data['claims_detail'] = self.generate_claims_detail(counts.get('claims_detail', 80000))
        data['prior_authorizations'] = self.generate_prior_authorizations(counts.get('prior_authorizations', 15000))
        data['utilization_reviews'] = self.generate_utilization_reviews(counts.get('utilization_reviews', 10000))
        data['plan_of_care'] = self.generate_plan_of_care(counts.get('plan_of_care', 25000))
        data['quality_measures'] = self.generate_quality_measures(counts.get('quality_measures', 5000))
        return data


# ============================================================================
# OUTPUT — delegates to base data_generator.save_to_csv
# ============================================================================

def save_to_csv(data: Dict[str, List[Dict]], output_dir: str):
    """Save using the base data_generator's save_to_csv (unchanged)."""
    base_save_to_csv(data, output_dir, "PAYER")


# ============================================================================
# CLI
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Generate Payer/Claims data for Snowflake HCLS DCA demo",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python generate_payer_data.py --output ../data
  python generate_payer_data.py --output ../data --quick
  python generate_payer_data.py --output ../data --scale 2.0
  python generate_payer_data.py --output ../data --seed 123
        """
    )
    parser.add_argument("--output", "-o", default="../data",
                       help="Output directory (default: ../data)")
    parser.add_argument("--seed", type=int, default=42,
                       help="Random seed for reproducibility (default: 42)")
    parser.add_argument("--quick", action="store_true",
                       help="Generate small test dataset (~10%% of default)")
    parser.add_argument("--scale", type=float, default=1.0,
                       help="Scale factor for record counts (default: 1.0)")

    args = parser.parse_args()
    counts = dict(DEFAULT_COUNTS)
    if args.quick:
        counts = {k: max(10, v // 10) for k, v in counts.items()}
    else:
        counts = {k: int(v * args.scale) for k, v in counts.items()}

    print("=" * 60)
    print("PAYER / CLAIMS DATA GENERATOR")
    print("=" * 60)
    print(f"  Seed:   {args.seed}")
    print(f"  Scale:  {'quick (10%)' if args.quick else f'{args.scale}x'}")
    print(f"  Output: {args.output}")
    print(f"  Counts: {counts}")
    print()

    generator = PayerGenerator(seed=args.seed)
    data = generator.generate(counts)

    print()
    print("=" * 60)
    print("GENERATION COMPLETE")
    print("=" * 60)
    for table, records in data.items():
        print(f"  {table}: {len(records):,} records")

    print()
    save_to_csv(data, args.output)
    print("\nDone!")


if __name__ == "__main__":
    main()
