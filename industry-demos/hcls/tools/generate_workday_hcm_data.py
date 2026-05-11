#!/usr/bin/env python3
"""
Workday HCM (Human Capital Management) Data Generator — Healthcare Edition

Generates realistic synthetic Workday HCM data for the HCLS DCA demo:
  - workers: 8,000 healthcare employees (RN, MD, techs, admin)
  - departments: 200 clinical units (ED, ICU, Med-Surg, etc.)
  - staffing_assignments: 50,000 worker-to-unit assignments
  - shifts: 200,000 actual worked shifts with census/acuity
  - certifications: 15,000 clinical certifications (BLS, ACLS, CCRN, etc.)
  - time_off: 20,000 PTO/sick/FMLA requests
  - turnover_events: 2,000 resignations/terminations/retirements
  - compensation_history: 12,000 pay change records

Usage:
    python generate_workday_hcm_data.py --output ../data
    python generate_workday_hcm_data.py --output ../data --quick       # Small test set
    python generate_workday_hcm_data.py --output ../data --scale 2.0   # Double size
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

# Job families and titles
JOB_FAMILIES = {
    "NURSING": {
        "titles": [
            ("Registered Nurse", "RN", 0.35),
            ("Licensed Practical Nurse", "LPN", 0.10),
            ("Nurse Practitioner", "NP", 0.05),
            ("Charge Nurse", "RN", 0.05),
            ("Nurse Manager", "RN", 0.03),
            ("Clinical Nurse Specialist", "CNS", 0.02),
        ],
        "weight": 0.45,
    },
    "PHYSICIAN": {
        "titles": [
            ("Attending Physician", "MD", 0.10),
            ("Resident Physician", "MD", 0.05),
            ("Physician Assistant", "PA", 0.04),
            ("Hospitalist", "MD", 0.03),
            ("Chief Medical Officer", "MD", 0.005),
        ],
        "weight": 0.15,
    },
    "ALLIED_HEALTH": {
        "titles": [
            ("Respiratory Therapist", "RT", 0.04),
            ("Physical Therapist", "PT", 0.03),
            ("Occupational Therapist", "OT", 0.02),
            ("Pharmacist", "PharmD", 0.03),
            ("Lab Technologist", "MLT", 0.04),
            ("Radiology Technologist", "RT(R)", 0.03),
            ("Surgical Technologist", "CST", 0.02),
            ("Dietitian", "RD", 0.01),
            ("Social Worker", "LCSW", 0.02),
        ],
        "weight": 0.25,
    },
    "ADMIN": {
        "titles": [
            ("Unit Secretary", None, 0.04),
            ("Patient Access Representative", None, 0.03),
            ("Health Information Technician", None, 0.02),
            ("Medical Coder", None, 0.02),
            ("Scheduling Coordinator", None, 0.01),
        ],
        "weight": 0.08,
    },
    "SUPPORT": {
        "titles": [
            ("Certified Nursing Assistant", "CNA", 0.05),
            ("Patient Care Technician", "PCT", 0.04),
            ("Environmental Services", None, 0.02),
            ("Transport Aide", None, 0.01),
        ],
        "weight": 0.07,
    },
}

# Specialties (for physicians, NPs, PAs)
CLINICAL_SPECIALTIES = [
    "Internal Medicine", "Cardiology", "Oncology", "Orthopedics", "Pediatrics",
    "Emergency Medicine", "Family Medicine", "Psychiatry", "Neurology",
    "General Surgery", "Radiology", "Anesthesiology", "Critical Care",
    "Endocrinology", "Gastroenterology", "Pulmonology", "Nephrology",
    "Infectious Disease", "Hematology", "Rheumatology",
]

# Unit types and their properties
UNIT_TYPES = {
    "ED": {"bed_range": (30, 80), "target_ratio": 4.0, "weight": 0.08},
    "ICU": {"bed_range": (12, 30), "target_ratio": 2.0, "weight": 0.06},
    "MICU": {"bed_range": (10, 24), "target_ratio": 2.0, "weight": 0.04},
    "SICU": {"bed_range": (10, 24), "target_ratio": 2.0, "weight": 0.04},
    "CCU": {"bed_range": (8, 20), "target_ratio": 2.0, "weight": 0.03},
    "NICU": {"bed_range": (15, 40), "target_ratio": 2.0, "weight": 0.03},
    "MED_SURG": {"bed_range": (24, 50), "target_ratio": 5.0, "weight": 0.15},
    "TELEMETRY": {"bed_range": (20, 40), "target_ratio": 4.0, "weight": 0.08},
    "OR": {"bed_range": (8, 20), "target_ratio": 1.0, "weight": 0.06},
    "PACU": {"bed_range": (8, 16), "target_ratio": 2.0, "weight": 0.04},
    "L_AND_D": {"bed_range": (10, 30), "target_ratio": 2.0, "weight": 0.04},
    "ONCOLOGY": {"bed_range": (15, 35), "target_ratio": 4.0, "weight": 0.05},
    "CARDIOLOGY": {"bed_range": (15, 35), "target_ratio": 4.0, "weight": 0.04},
    "ORTHOPEDICS": {"bed_range": (15, 30), "target_ratio": 5.0, "weight": 0.04},
    "NEURO": {"bed_range": (12, 28), "target_ratio": 4.0, "weight": 0.04},
    "REHAB": {"bed_range": (20, 50), "target_ratio": 6.0, "weight": 0.04},
    "PSYCH": {"bed_range": (15, 40), "target_ratio": 5.0, "weight": 0.04},
    "PHARMACY": {"bed_range": (0, 0), "target_ratio": 0.0, "weight": 0.03},
    "LAB": {"bed_range": (0, 0), "target_ratio": 0.0, "weight": 0.03},
    "RADIOLOGY": {"bed_range": (0, 0), "target_ratio": 0.0, "weight": 0.03},
    "ADMIN": {"bed_range": (0, 0), "target_ratio": 0.0, "weight": 0.04},
}

# Certifications by job family
CERTIFICATIONS_BY_FAMILY = {
    "NURSING": ["BLS", "ACLS", "PALS", "TNCC", "CCRN", "CEN", "OCN", "RNC", "CNOR"],
    "PHYSICIAN": ["BLS", "ACLS", "ATLS", "PALS", "Board Certification"],
    "ALLIED_HEALTH": ["BLS", "ACLS", "RRT", "CPFT", "ASCP", "RT(R)", "RDMS"],
    "ADMIN": ["RHIT", "CPC", "CPMA"],
    "SUPPORT": ["BLS", "CNA"],
}

# Time-off types
TIME_OFF_TYPES = [
    ("SICK", 0.25), ("PTO", 0.40), ("FMLA", 0.10),
    ("BEREAVEMENT", 0.05), ("JURY_DUTY", 0.03), ("UNPAID", 0.17),
]

# Turnover reasons
TURNOVER_REASONS = [
    ("BURNOUT", 0.25), ("COMPENSATION", 0.20), ("RELOCATION", 0.12),
    ("CAREER_GROWTH", 0.15), ("RETIREMENT", 0.12),
    ("WORKPLACE_SAFETY", 0.06), ("PERFORMANCE", 0.10),
]

# Pay grades
PAY_GRADES = {
    "NURSING": {"RN": (55000, 95000), "LPN": (38000, 55000), "NP": (95000, 140000),
                "CNS": (80000, 115000), "Charge Nurse": (65000, 105000),
                "Nurse Manager": (85000, 130000)},
    "PHYSICIAN": {"MD": (200000, 450000), "PA": (90000, 140000),
                  "Resident": (55000, 75000), "CMO": (350000, 550000)},
    "ALLIED_HEALTH": {"RT": (50000, 75000), "PT": (65000, 95000), "OT": (60000, 90000),
                      "PharmD": (110000, 150000), "MLT": (45000, 65000),
                      "RT(R)": (50000, 75000), "CST": (40000, 60000),
                      "RD": (50000, 72000), "LCSW": (48000, 72000)},
    "ADMIN": {"default": (32000, 55000)},
    "SUPPORT": {"CNA": (28000, 40000), "PCT": (30000, 42000), "default": (25000, 38000)},
}

SHIFT_TYPES = ["DAY", "NIGHT", "SWING"]
SHIFT_PREFERENCES = ["DAY", "NIGHT", "SWING", "ROTATING"]
ASSIGNMENT_STATUSES = ["ACTIVE", "COMPLETED", "CANCELLED"]

US_STATES = [
    "CA", "TX", "FL", "NY", "IL", "PA", "OH", "GA", "NC", "MI",
    "NJ", "VA", "WA", "AZ", "MA", "TN", "IN", "MO", "MD", "WI",
]

GENDERS = ["Male", "Female", "Other"]

DEFAULT_COUNTS = {
    'workers': 8000,
    'departments': 200,
    'staffing_assignments': 50000,
    'shifts': 200000,
    'certifications': 15000,
    'time_off': 20000,
    'turnover_events': 2000,
    'compensation_history': 12000,
}


# ============================================================================
# GENERATOR
# ============================================================================

class WorkdayHCMGenerator(SourceSystemGenerator):
    """Generates synthetic Workday HCM data for healthcare workforce analytics."""

    SYSTEM_NAME = "WORKDAY_HCM"

    def __init__(self, seed: int = 42):
        self.seed = seed
        random.seed(seed)
        self.fake = Faker('en_US')
        self.fake.seed_instance(seed)
        self.workers: List[Dict] = []
        self.departments: List[Dict] = []
        # Track departments that tend to be understaffed (for staffing-outcomes correlation)
        self.understaffed_dept_ids: set = set()
        # Track high-overtime workers
        self.high_overtime_worker_ids: set = set()

    def _hash(self, record: Dict) -> str:
        data = {k: v for k, v in record.items() if not k.startswith('_')}
        return hashlib.sha256(json.dumps(data, sort_keys=True, default=str).encode()).hexdigest()

    def _get_salary_range(self, job_family: str, credential: str) -> tuple:
        """Get salary range for a job family and credential."""
        family_grades = PAY_GRADES.get(job_family, PAY_GRADES["ADMIN"])
        if credential and credential in family_grades:
            return family_grades[credential]
        for key, val in family_grades.items():
            if key != "default" and credential and key.lower() in credential.lower():
                return val
        return family_grades.get("default", (35000, 60000))

    # ------------------------------------------------------------------
    # WORKERS
    # ------------------------------------------------------------------
    def generate_workers(self, count: int) -> List[Dict]:
        print(f"  Generating {count} workers...")
        records = []

        # Build weighted title list
        all_titles = []
        all_weights = []
        all_families = []
        for family, info in JOB_FAMILIES.items():
            for title, credential, title_weight in info["titles"]:
                all_titles.append((title, credential, family))
                all_weights.append(title_weight)

        # Normalize weights
        total_w = sum(all_weights)
        all_weights = [w / total_w for w in all_weights]

        for i in range(count):
            title, credential, job_family = random.choices(all_titles, weights=all_weights)[0]

            gender = random.choices(GENDERS, weights=[0.28, 0.70, 0.02])[0]
            if gender == "Male":
                first_name = self.fake.first_name_male()
            elif gender == "Female":
                first_name = self.fake.first_name_female()
            else:
                first_name = self.fake.first_name()

            hire_date = self.fake.date_between(start_date='-20y', end_date='-30d')
            # ~15% have terminated
            terminated = random.random() < 0.15
            termination_date = (hire_date + timedelta(days=random.randint(90, 3650))).isoformat() if terminated else None
            active_status = "INACTIVE" if terminated else "ACTIVE"

            # Shift preference: physicians mostly DAY, nurses spread across
            if job_family == "PHYSICIAN":
                shift_pref = random.choices(SHIFT_PREFERENCES, weights=[0.60, 0.10, 0.10, 0.20])[0]
            elif job_family == "NURSING":
                shift_pref = random.choices(SHIFT_PREFERENCES, weights=[0.30, 0.25, 0.15, 0.30])[0]
            else:
                shift_pref = random.choices(SHIFT_PREFERENCES, weights=[0.50, 0.15, 0.10, 0.25])[0]

            # FTE: mostly 1.0, some part-time
            fte = random.choices([1.0, 0.8, 0.6, 0.5], weights=[0.75, 0.10, 0.08, 0.07])[0]

            salary_low, salary_high = self._get_salary_range(job_family, credential)
            annual_salary = round(random.uniform(salary_low, salary_high), 2)
            hourly_rate = round(annual_salary / 2080, 2)

            # Job level based on title
            if "Manager" in title or "Chief" in title:
                job_level = random.choice(["M3", "M4", "M5"])
            elif "Charge" in title or "Specialist" in title or "Attending" in title:
                job_level = random.choice(["P3", "P4"])
            elif "Resident" in title:
                job_level = random.choice(["P1", "P2"])
            else:
                job_level = random.choice(["P1", "P2", "P3"])

            # NPI for physicians, NPs, and PAs
            npi = None
            if job_family == "PHYSICIAN" or credential in ("NP", "PA"):
                npi = f"{random.randint(1000000000, 9999999999)}"

            # Specialty for clinical roles
            specialty = None
            if job_family == "PHYSICIAN" or credential in ("NP", "CNS"):
                specialty = random.choice(CLINICAL_SPECIALTIES)

            # Credentials list
            creds = []
            if credential:
                creds.append(credential)
            family_certs = CERTIFICATIONS_BY_FAMILY.get(job_family, [])
            # Add 1-3 additional certifications
            extra = random.sample(family_certs, min(random.randint(1, 3), len(family_certs)))
            creds.extend(extra)

            license_number = None
            license_state = None
            if credential in ("RN", "LPN", "NP", "CNS", "MD", "PA", "PharmD"):
                license_state = random.choice(US_STATES)
                license_number = f"{license_state}-{credential}-{random.randint(100000, 999999)}"

            rec = {
                'worker_id': str(uuid.uuid5(uuid.NAMESPACE_OID, f"worker_{self.seed}_{i}")),
                'employee_id': f"EMP-{100000 + i:06d}",
                'first_name': first_name,
                'last_name': self.fake.last_name(),
                'date_of_birth': self.fake.date_of_birth(minimum_age=22, maximum_age=68).isoformat(),
                'gender': gender,
                'hire_date': hire_date.isoformat(),
                'termination_date': termination_date if terminated else '',
                'active_status': active_status,
                'job_title': title,
                'job_family': job_family,
                'job_level': job_level,
                'department_id': '',  # Set after departments are generated
                'credentials': json.dumps(creds),
                'license_number': license_number or '',
                'license_state': license_state or '',
                'npi': npi or '',
                'specialty': specialty or '',
                'shift_preference': shift_pref,
                'fte': fte,
                'annual_salary': annual_salary,
                'hourly_rate': hourly_rate,
                'pay_grade': job_level,
                'created_at': datetime.now().isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        self.workers = records
        return records

    # ------------------------------------------------------------------
    # DEPARTMENTS
    # ------------------------------------------------------------------
    def generate_departments(self, count: int) -> List[Dict]:
        print(f"  Generating {count} departments...")
        records = []

        unit_type_list = list(UNIT_TYPES.keys())
        unit_weights = [UNIT_TYPES[u]["weight"] for u in unit_type_list]

        # Use same org_id seed pattern as generate_hcls_data.py
        # FHIR generator creates 50 orgs: uuid5(NAMESPACE_OID, f"org_{seed}_{i}") for i in range(50)
        num_orgs = 50
        org_ids = [str(uuid.uuid5(uuid.NAMESPACE_OID, f"org_{self.seed}_{i}")) for i in range(num_orgs)]

        # Select ~30% of departments as chronically understaffed
        understaffed_count = int(count * 0.30)
        understaffed_indices = set(random.sample(range(count), understaffed_count))

        for i in range(count):
            unit_type = random.choices(unit_type_list, weights=unit_weights)[0]
            unit_info = UNIT_TYPES[unit_type]

            bed_low, bed_high = unit_info["bed_range"]
            bed_count = random.randint(bed_low, bed_high) if bed_high > 0 else 0
            target_ratio = unit_info["target_ratio"]

            # Map to FHIR orgs
            org_id = random.choice(org_ids)

            dept_id = str(uuid.uuid5(uuid.NAMESPACE_OID, f"dept_{self.seed}_{i}"))

            # Assign a manager from existing workers (if any nursing/physician managers)
            manager_id = ''
            manager_candidates = [w for w in self.workers
                                  if "Manager" in w['job_title'] or "Chief" in w['job_title']]
            if manager_candidates:
                manager_id = random.choice(manager_candidates)['worker_id']

            cost_center = f"CC-{5000 + i:04d}"

            dept_name_map = {
                "ED": "Emergency Department",
                "ICU": "Intensive Care Unit",
                "MICU": "Medical Intensive Care Unit",
                "SICU": "Surgical Intensive Care Unit",
                "CCU": "Coronary Care Unit",
                "NICU": "Neonatal Intensive Care Unit",
                "MED_SURG": "Medical-Surgical Unit",
                "TELEMETRY": "Telemetry Unit",
                "OR": "Operating Room",
                "PACU": "Post-Anesthesia Care Unit",
                "L_AND_D": "Labor and Delivery",
                "ONCOLOGY": "Oncology Unit",
                "CARDIOLOGY": "Cardiology Unit",
                "ORTHOPEDICS": "Orthopedics Unit",
                "NEURO": "Neuroscience Unit",
                "REHAB": "Rehabilitation Unit",
                "PSYCH": "Behavioral Health Unit",
                "PHARMACY": "Pharmacy",
                "LAB": "Clinical Laboratory",
                "RADIOLOGY": "Radiology Department",
                "ADMIN": "Administration",
            }
            dept_name = f"{dept_name_map.get(unit_type, unit_type)} - {chr(65 + (i % 26))}{i // 26 + 1}"

            rec = {
                'department_id': dept_id,
                'department_name': dept_name,
                'unit_type': unit_type,
                'org_id': org_id,
                'bed_count': bed_count,
                'target_nurse_ratio': target_ratio,
                'manager_worker_id': manager_id,
                'cost_center': cost_center,
                'created_at': datetime.now().isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

            if i in understaffed_indices:
                self.understaffed_dept_ids.add(dept_id)

        self.departments = records

        # Assign workers to departments
        clinical_depts = [d for d in self.departments if d['unit_type'] not in ("PHARMACY", "LAB", "RADIOLOGY", "ADMIN")]
        support_depts = [d for d in self.departments if d['unit_type'] in ("PHARMACY", "LAB", "RADIOLOGY", "ADMIN")]

        for worker in self.workers:
            if worker['job_family'] in ("NURSING", "PHYSICIAN", "SUPPORT"):
                dept = random.choice(clinical_depts) if clinical_depts else random.choice(self.departments)
            elif worker['job_family'] == "ALLIED_HEALTH":
                # Allied health can be in clinical or support departments
                if "Pharmacist" in worker['job_title']:
                    dept = random.choice([d for d in self.departments if d['unit_type'] == "PHARMACY"] or self.departments)
                elif "Lab" in worker['job_title']:
                    dept = random.choice([d for d in self.departments if d['unit_type'] == "LAB"] or self.departments)
                elif "Radiology" in worker['job_title']:
                    dept = random.choice([d for d in self.departments if d['unit_type'] == "RADIOLOGY"] or self.departments)
                else:
                    dept = random.choice(clinical_depts) if clinical_depts else random.choice(self.departments)
            else:
                dept = random.choice(support_depts) if support_depts else random.choice(self.departments)

            worker['department_id'] = dept['department_id']
            worker['_ROW_HASH'] = self._hash(worker)

        return records

    # ------------------------------------------------------------------
    # STAFFING ASSIGNMENTS
    # ------------------------------------------------------------------
    def generate_staffing_assignments(self, count: int) -> List[Dict]:
        if not self.workers or not self.departments:
            raise ValueError("Must generate workers and departments first")
        print(f"  Generating {count} staffing assignments...")
        records = []

        active_workers = [w for w in self.workers if w['active_status'] == "ACTIVE"]

        for i in range(count):
            worker = random.choice(active_workers)
            dept = random.choice(self.departments)

            shift_type = random.choices(SHIFT_TYPES, weights=[0.45, 0.35, 0.20])[0]
            start_date = self.fake.date_between(start_date='-3y', end_date='today')
            # Assignment duration: 1-180 days
            duration = random.randint(1, 180)
            end_date = start_date + timedelta(days=duration)

            is_float_pool = random.random() < 0.12
            is_overtime = random.random() < 0.15
            hours_scheduled = random.choices(
                [8.0, 10.0, 12.0, 4.0],
                weights=[0.30, 0.15, 0.45, 0.10]
            )[0]

            if is_overtime:
                self.high_overtime_worker_ids.add(worker['worker_id'])

            rec = {
                'assignment_id': str(uuid.uuid5(uuid.NAMESPACE_OID, f"assign_{self.seed}_{i}")),
                'worker_id': worker['worker_id'],
                'department_id': dept['department_id'],
                'start_date': start_date.isoformat(),
                'end_date': end_date.isoformat(),
                'shift_type': shift_type,
                'is_float_pool': is_float_pool,
                'is_overtime': is_overtime,
                'hours_scheduled': hours_scheduled,
                'assignment_status': random.choices(ASSIGNMENT_STATUSES, weights=[0.50, 0.40, 0.10])[0],
                'created_at': datetime.now().isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        return records

    # ------------------------------------------------------------------
    # SHIFTS
    # ------------------------------------------------------------------
    def generate_shifts(self, count: int) -> List[Dict]:
        if not self.workers or not self.departments:
            raise ValueError("Must generate workers and departments first")
        print(f"  Generating {count} shifts...")
        records = []

        active_workers = [w for w in self.workers if w['active_status'] == "ACTIVE"]
        # Nursing workers for ratio computation
        nursing_workers = [w for w in active_workers if w['job_family'] == "NURSING"]
        clinical_depts = [d for d in self.departments
                          if d['unit_type'] not in ("PHARMACY", "LAB", "RADIOLOGY", "ADMIN")]

        # Ratio ranges by unit type (nurse-to-patient)
        ratio_ranges = {
            "ICU": (1.5, 2.5), "MICU": (1.5, 2.5), "SICU": (1.5, 2.5),
            "CCU": (1.5, 2.5), "NICU": (1.5, 2.5),
            "ED": (3.0, 5.0),
            "MED_SURG": (4.0, 6.5), "REHAB": (5.0, 7.0),
            "TELEMETRY": (3.0, 5.0), "PSYCH": (4.0, 6.0),
            "OR": (1.0, 1.5), "PACU": (1.5, 2.5),
            "L_AND_D": (1.5, 3.0),
            "ONCOLOGY": (3.0, 5.0), "CARDIOLOGY": (3.0, 5.0),
            "ORTHOPEDICS": (4.0, 6.0), "NEURO": (3.0, 5.0),
        }

        for i in range(count):
            worker = random.choice(active_workers)
            dept = random.choice(clinical_depts) if clinical_depts else random.choice(self.departments)

            shift_date = self.fake.date_between(start_date='-3y', end_date='today')
            shift_type = random.choices(SHIFT_TYPES, weights=[0.45, 0.35, 0.20])[0]

            if shift_type == "DAY":
                shift_start = datetime.combine(shift_date, datetime.min.time().replace(hour=7))
            elif shift_type == "NIGHT":
                shift_start = datetime.combine(shift_date, datetime.min.time().replace(hour=19))
            else:  # SWING
                shift_start = datetime.combine(shift_date, datetime.min.time().replace(hour=15))

            # Shift duration: mostly 12h, some 8h and 10h
            hours_worked = random.choices([8.0, 10.0, 12.0, 13.0, 16.0],
                                          weights=[0.20, 0.10, 0.55, 0.10, 0.05])[0]
            shift_end = shift_start + timedelta(hours=hours_worked)

            is_overtime = hours_worked > 12.0 or random.random() < 0.12
            is_call_in = random.random() < 0.08

            # Unit census and nurse-patient ratio
            unit_type = dept['unit_type']
            bed_count = dept['bed_count']
            if bed_count > 0:
                # Occupancy 40-95%
                occupancy = random.uniform(0.40, 0.95)
                # Understaffed departments run hotter
                if dept['department_id'] in self.understaffed_dept_ids:
                    occupancy = random.uniform(0.70, 0.98)
                unit_census = max(1, int(bed_count * occupancy))
            else:
                unit_census = 0

            # Nurse-patient ratio
            ratio_low, ratio_high = ratio_ranges.get(unit_type, (3.0, 6.0))
            if dept['department_id'] in self.understaffed_dept_ids:
                # Understaffed units have worse ratios
                nurse_patient_ratio = round(random.uniform(ratio_high * 0.9, ratio_high * 1.5), 1)
            else:
                nurse_patient_ratio = round(random.uniform(ratio_low, ratio_high), 1)

            patient_count = max(0, int(nurse_patient_ratio)) if unit_census > 0 else 0

            acuity_score = random.choices([1, 2, 3, 4, 5],
                                          weights=[0.05, 0.20, 0.40, 0.25, 0.10])[0]
            # ICUs have higher acuity
            if unit_type in ("ICU", "MICU", "SICU", "CCU"):
                acuity_score = random.choices([3, 4, 5], weights=[0.20, 0.45, 0.35])[0]

            rec = {
                'shift_id': str(uuid.uuid5(uuid.NAMESPACE_OID, f"shift_{self.seed}_{i}")),
                'worker_id': worker['worker_id'],
                'department_id': dept['department_id'],
                'shift_date': shift_date.isoformat(),
                'shift_start': shift_start.isoformat(),
                'shift_end': shift_end.isoformat(),
                'hours_worked': hours_worked,
                'shift_type': shift_type,
                'patient_count': patient_count,
                'unit_census': unit_census,
                'nurse_patient_ratio': nurse_patient_ratio,
                'is_overtime': is_overtime,
                'is_call_in': is_call_in,
                'acuity_score': acuity_score,
                'created_at': datetime.now().isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        return records

    # ------------------------------------------------------------------
    # CERTIFICATIONS
    # ------------------------------------------------------------------
    def generate_certifications(self, count: int) -> List[Dict]:
        if not self.workers:
            raise ValueError("Must generate workers first")
        print(f"  Generating {count} certifications...")
        records = []

        for i in range(count):
            worker = random.choice(self.workers)
            job_family = worker['job_family']
            available_certs = CERTIFICATIONS_BY_FAMILY.get(job_family, ["BLS"])
            cert_type = random.choice(available_certs)

            issue_date = self.fake.date_between(start_date='-5y', end_date='today')
            # Most certifications expire in 2 years
            expiration_date = issue_date + timedelta(days=random.choice([365, 730, 1095]))

            is_expired = expiration_date < date.today()
            ce_hours = random.randint(4, 40) if not is_expired else random.randint(0, 20)

            rec = {
                'cert_id': str(uuid.uuid5(uuid.NAMESPACE_OID, f"cert_{self.seed}_{i}")),
                'worker_id': worker['worker_id'],
                'certification_type': cert_type,
                'issue_date': issue_date.isoformat(),
                'expiration_date': expiration_date.isoformat(),
                'ce_hours_completed': ce_hours,
                'is_expired': is_expired,
                'created_at': datetime.now().isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        return records

    # ------------------------------------------------------------------
    # TIME OFF
    # ------------------------------------------------------------------
    def generate_time_off(self, count: int) -> List[Dict]:
        if not self.workers or not self.departments:
            raise ValueError("Must generate workers and departments first")
        print(f"  Generating {count} time off requests...")
        records = []

        active_workers = [w for w in self.workers if w['active_status'] == "ACTIVE"]

        for i in range(count):
            worker = random.choice(active_workers)
            dept_id = worker['department_id']

            time_off_type = random.choices(
                [t[0] for t in TIME_OFF_TYPES],
                weights=[t[1] for t in TIME_OFF_TYPES]
            )[0]

            start_date = self.fake.date_between(start_date='-2y', end_date='today')

            # Duration based on type
            if time_off_type == "SICK":
                duration_days = random.choices([1, 2, 3, 5, 10], weights=[0.40, 0.25, 0.15, 0.12, 0.08])[0]
            elif time_off_type == "PTO":
                duration_days = random.choices([1, 2, 3, 5, 7, 10], weights=[0.20, 0.20, 0.15, 0.25, 0.10, 0.10])[0]
            elif time_off_type == "FMLA":
                duration_days = random.randint(5, 60)
            elif time_off_type == "BEREAVEMENT":
                duration_days = random.randint(3, 5)
            elif time_off_type == "JURY_DUTY":
                duration_days = random.randint(1, 10)
            else:  # UNPAID
                duration_days = random.randint(1, 14)

            end_date = start_date + timedelta(days=duration_days)
            total_hours = duration_days * 8.0

            status = random.choices(
                ["APPROVED", "DENIED", "PENDING", "CANCELLED"],
                weights=[0.70, 0.08, 0.12, 0.10]
            )[0]

            # Coverage assessment
            coverage_filled = random.random() < 0.65
            if not coverage_filled:
                shift_impact = random.choices(
                    ["UNDERSTAFFED", "PARTIAL"],
                    weights=[0.60, 0.40]
                )[0]
            else:
                shift_impact = "COVERED"

            rec = {
                'request_id': str(uuid.uuid5(uuid.NAMESPACE_OID, f"timeoff_{self.seed}_{i}")),
                'worker_id': worker['worker_id'],
                'department_id': dept_id,
                'time_off_type': time_off_type,
                'start_date': start_date.isoformat(),
                'end_date': end_date.isoformat(),
                'total_hours': total_hours,
                'status': status,
                'coverage_filled': coverage_filled,
                'shift_impact': shift_impact,
                'created_at': datetime.now().isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        return records

    # ------------------------------------------------------------------
    # TURNOVER EVENTS
    # ------------------------------------------------------------------
    def generate_turnover_events(self, count: int) -> List[Dict]:
        if not self.workers or not self.departments:
            raise ValueError("Must generate workers and departments first")
        print(f"  Generating {count} turnover events...")
        records = []

        # Use terminated workers first, then sample from active
        terminated_workers = [w for w in self.workers if w['active_status'] == "INACTIVE"]
        active_workers = [w for w in self.workers if w['active_status'] == "ACTIVE"]

        for i in range(count):
            if terminated_workers and random.random() < 0.70:
                worker = random.choice(terminated_workers)
            else:
                worker = random.choice(active_workers)

            dept_id = worker['department_id']

            # Event type distribution
            event_type = random.choices(
                ["RESIGNATION", "TERMINATION", "RETIREMENT", "TRANSFER_OUT"],
                weights=[0.55, 0.15, 0.15, 0.15]
            )[0]

            reason_code = random.choices(
                [r[0] for r in TURNOVER_REASONS],
                weights=[r[1] for r in TURNOVER_REASONS]
            )[0]

            # Retirement overrides reason
            if event_type == "RETIREMENT":
                reason_code = "RETIREMENT"

            hire_date = date.fromisoformat(worker['hire_date'])
            earliest_event = hire_date + timedelta(days=90)
            if earliest_event >= date.today():
                earliest_event = hire_date + timedelta(days=1)
            if earliest_event >= date.today():
                earliest_event = date.today() - timedelta(days=1)
            event_date = self.fake.date_between(start_date=earliest_event, end_date='today')
            tenure_months = max(1, (event_date - hire_date).days // 30)

            # Critical role: charge nurses, NPs, specialized roles
            was_critical_role = any(kw in worker['job_title']
                                    for kw in ["Charge", "Specialist", "Practitioner", "Attending", "Chief"])

            # Replacement time correlates with role criticality
            if was_critical_role:
                replacement_days = random.randint(45, 180)
            else:
                replacement_days = random.randint(14, 90)

            rec = {
                'event_id': str(uuid.uuid5(uuid.NAMESPACE_OID, f"turnover_{self.seed}_{i}")),
                'worker_id': worker['worker_id'],
                'department_id': dept_id,
                'event_type': event_type,
                'event_date': event_date.isoformat(),
                'reason_code': reason_code,
                'tenure_months': tenure_months,
                'was_critical_role': was_critical_role,
                'replacement_days': replacement_days,
                'created_at': datetime.now().isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        return records

    # ------------------------------------------------------------------
    # COMPENSATION HISTORY
    # ------------------------------------------------------------------
    def generate_compensation_history(self, count: int) -> List[Dict]:
        if not self.workers:
            raise ValueError("Must generate workers first")
        print(f"  Generating {count} compensation history records...")
        records = []

        active_workers = [w for w in self.workers if w['active_status'] == "ACTIVE"]

        comp_change_types = [
            ("MERIT", 0.40), ("PROMOTION", 0.15),
            ("MARKET_ADJUST", 0.25), ("STEP_INCREASE", 0.20),
        ]

        for i in range(count):
            worker = random.choice(active_workers)
            hire_date = date.fromisoformat(worker['hire_date'])

            effective_date = self.fake.date_between(start_date=hire_date, end_date='today')

            change_type = random.choices(
                [c[0] for c in comp_change_types],
                weights=[c[1] for c in comp_change_types]
            )[0]

            # Change percentage
            if change_type == "MERIT":
                change_pct = round(random.uniform(1.5, 5.0), 1)
            elif change_type == "PROMOTION":
                change_pct = round(random.uniform(8.0, 20.0), 1)
            elif change_type == "MARKET_ADJUST":
                change_pct = round(random.uniform(3.0, 12.0), 1)
            else:  # STEP_INCREASE
                change_pct = round(random.uniform(2.0, 4.0), 1)

            base_salary = worker['annual_salary']
            new_salary = round(base_salary * (1 + change_pct / 100), 2)
            new_hourly = round(new_salary / 2080, 2)

            rec = {
                'comp_id': str(uuid.uuid5(uuid.NAMESPACE_OID, f"comp_{self.seed}_{i}")),
                'worker_id': worker['worker_id'],
                'effective_date': effective_date.isoformat(),
                'annual_salary': new_salary,
                'hourly_rate': new_hourly,
                'pay_grade': worker['pay_grade'],
                'comp_change_type': change_type,
                'change_percent': change_pct,
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
        data['workers'] = self.generate_workers(counts.get('workers', 8000))
        data['departments'] = self.generate_departments(counts.get('departments', 200))
        data['staffing_assignments'] = self.generate_staffing_assignments(counts.get('staffing_assignments', 50000))
        data['shifts'] = self.generate_shifts(counts.get('shifts', 200000))
        data['certifications'] = self.generate_certifications(counts.get('certifications', 15000))
        data['time_off'] = self.generate_time_off(counts.get('time_off', 20000))
        data['turnover_events'] = self.generate_turnover_events(counts.get('turnover_events', 2000))
        data['compensation_history'] = self.generate_compensation_history(counts.get('compensation_history', 12000))
        return data


# ============================================================================
# OUTPUT — delegates to base data_generator.save_to_csv
# ============================================================================

def save_to_csv(data: Dict[str, List[Dict]], output_dir: str):
    """Save using the base data_generator's save_to_csv (unchanged)."""
    base_save_to_csv(data, output_dir, "WORKDAY_HCM")


# ============================================================================
# CLI
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Generate Workday HCM data for Snowflake HCLS DCA demo",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python generate_workday_hcm_data.py --output ../data
  python generate_workday_hcm_data.py --output ../data --quick
  python generate_workday_hcm_data.py --output ../data --scale 2.0
  python generate_workday_hcm_data.py --output ../data --seed 123
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
    print("WORKDAY HCM DATA GENERATOR")
    print("=" * 60)
    print(f"  Seed:   {args.seed}")
    print(f"  Scale:  {'quick (10%)' if args.quick else f'{args.scale}x'}")
    print(f"  Output: {args.output}")
    print(f"  Counts: {counts}")
    print()

    generator = WorkdayHCMGenerator(seed=args.seed)
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
