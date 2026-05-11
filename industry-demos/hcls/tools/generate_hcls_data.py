#!/usr/bin/env python3
"""
HCLS (Healthcare & Life Sciences) Data Generator

Generates realistic synthetic FHIR clinical data for the HCLS DCA demo:
  - patients: 10,000 patient records with PHI
  - practitioners: 500 healthcare providers
  - organizations: 50 healthcare facilities
  - encounters: 50,000 clinical encounters (with staffing context and readmission flags)
  - conditions: 30,000 diagnoses (ICD-10)
  - observations: 100,000 lab/vitals (LOINC)
  - medications: 25,000 prescriptions (RxNorm)
  - procedures: 15,000 procedures (CPT)
  - claims: 40,000 insurance claims
  - comorbidity_scores: Charlson CCI per patient (derived from conditions)

Usage:
    python generate_hcls_data.py --output ../data
    python generate_hcls_data.py --output ../data --quick       # Small test set
    python generate_hcls_data.py --output ../data --scale 2.0   # Double size
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
# This ensures we reuse SourceSystemGenerator, save_to_csv, etc. verbatim
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

# Insurance payers
INSURANCE_PAYERS = [
    ("Medicare", 0.20), ("Medicaid", 0.15), ("UnitedHealthcare", 0.15),
    ("Aetna", 0.10), ("Cigna", 0.10), ("Blue Cross", 0.12),
    ("Humana", 0.08), ("Kaiser", 0.05), ("Self-Pay", 0.05),
]

# Specialties
SPECIALTIES = [
    "Internal Medicine", "Cardiology", "Oncology", "Orthopedics", "Pediatrics",
    "Emergency Medicine", "Family Medicine", "Psychiatry", "Neurology",
    "General Surgery", "Radiology", "Anesthesiology", "Dermatology",
    "Endocrinology", "Gastroenterology",
]

# Organization types
ORG_TYPES = ["HOSPITAL", "CLINIC", "URGENT_CARE", "LAB", "PHARMACY", "REHABILITATION", "NURSING_FACILITY"]
TRAUMA_LEVELS = ["LEVEL_I", "LEVEL_II", "LEVEL_III", "NONE"]

# Encounter classes
ENCOUNTER_CLASSES = ["EMERGENCY", "INPATIENT", "OUTPATIENT", "AMBULATORY", "OBSERVATION"]
ENCOUNTER_STATUSES = ["FINISHED", "IN_PROGRESS", "CANCELLED"]

# ICD-10 codes (50 common diagnoses)
ICD10_CODES = [
    ("E11.9", "Type 2 diabetes mellitus without complications"),
    ("I10", "Essential (primary) hypertension"),
    ("J06.9", "Acute upper respiratory infection, unspecified"),
    ("M54.5", "Low back pain"),
    ("F32.9", "Major depressive disorder, single episode, unspecified"),
    ("J44.1", "Chronic obstructive pulmonary disease with acute exacerbation"),
    ("K21.0", "Gastro-esophageal reflux disease with esophagitis"),
    ("N39.0", "Urinary tract infection, site not specified"),
    ("E78.5", "Hyperlipidemia, unspecified"),
    ("I25.10", "Atherosclerotic heart disease of native coronary artery"),
    ("J18.9", "Pneumonia, unspecified organism"),
    ("M79.3", "Panniculitis, unspecified"),
    ("E03.9", "Hypothyroidism, unspecified"),
    ("G47.33", "Obstructive sleep apnea"),
    ("I48.91", "Unspecified atrial fibrillation"),
    ("J45.20", "Mild intermittent asthma, uncomplicated"),
    ("K57.30", "Diverticulosis of large intestine without perforation"),
    ("M17.11", "Primary osteoarthritis, right knee"),
    ("F41.1", "Generalized anxiety disorder"),
    ("E66.9", "Obesity, unspecified"),
    ("I50.9", "Heart failure, unspecified"),
    ("N18.3", "Chronic kidney disease, stage 3"),
    ("G43.909", "Migraine, unspecified, not intractable"),
    ("L40.0", "Psoriasis vulgaris"),
    ("M81.0", "Age-related osteoporosis without current pathological fracture"),
    ("B34.9", "Viral infection, unspecified"),
    ("R10.9", "Unspecified abdominal pain"),
    ("R05.9", "Cough, unspecified"),
    ("R51.9", "Headache, unspecified"),
    ("J02.9", "Acute pharyngitis, unspecified"),
    ("K59.00", "Constipation, unspecified"),
    ("R11.2", "Nausea with vomiting, unspecified"),
    ("H66.90", "Otitis media, unspecified, unspecified ear"),
    ("S62.509A", "Fracture of unspecified phalanx of other finger, initial"),
    ("M25.511", "Pain in right shoulder"),
    ("J20.9", "Acute bronchitis, unspecified"),
    ("L30.9", "Dermatitis, unspecified"),
    ("R42", "Dizziness and giddiness"),
    ("N40.0", "Benign prostatic hyperplasia without lower urinary tract symptoms"),
    ("I63.9", "Cerebral infarction, unspecified"),
    ("C50.919", "Malignant neoplasm of unspecified site of unspecified female breast"),
    ("C34.90", "Malignant neoplasm of unspecified part of unspecified bronchus or lung"),
    ("D64.9", "Anemia, unspecified"),
    ("E55.9", "Vitamin D deficiency, unspecified"),
    ("G20", "Parkinson's disease"),
    ("I73.9", "Peripheral vascular disease, unspecified"),
    ("J96.00", "Acute respiratory failure, unspecified"),
    ("K80.20", "Calculus of gallbladder without cholecystitis"),
    ("M48.06", "Spinal stenosis, lumbar region"),
    ("R07.9", "Chest pain, unspecified"),
]

# LOINC codes (30 common observations)
LOINC_CODES = [
    # (code, description, unit, low, high, normal_low, normal_high)
    ("8867-4", "Heart rate", "bpm", 40, 150, 60, 100),
    ("8310-5", "Body temperature", "degF", 95.0, 104.0, 97.0, 99.5),
    ("8480-6", "Systolic blood pressure", "mmHg", 80, 200, 90, 120),
    ("8462-4", "Diastolic blood pressure", "mmHg", 40, 120, 60, 80),
    ("9279-1", "Respiratory rate", "breaths/min", 8, 40, 12, 20),
    ("2708-6", "Oxygen saturation", "%", 80, 100, 95, 100),
    ("29463-7", "Body weight", "kg", 40, 180, 50, 100),
    ("8302-2", "Body height", "cm", 140, 210, 155, 185),
    ("39156-5", "Body mass index", "kg/m2", 15, 50, 18.5, 25.0),
    ("2093-3", "Total cholesterol", "mg/dL", 100, 350, 125, 200),
    ("2571-8", "Triglycerides", "mg/dL", 30, 500, 40, 150),
    ("2085-9", "HDL cholesterol", "mg/dL", 20, 100, 40, 60),
    ("13457-7", "LDL cholesterol", "mg/dL", 40, 250, 50, 100),
    ("2345-7", "Glucose", "mg/dL", 50, 400, 70, 100),
    ("4548-4", "Hemoglobin A1c", "%", 4.0, 14.0, 4.0, 5.7),
    ("2160-0", "Creatinine", "mg/dL", 0.3, 8.0, 0.6, 1.2),
    ("3094-0", "Blood urea nitrogen", "mg/dL", 5, 80, 7, 20),
    ("6298-4", "Potassium", "mmol/L", 2.5, 7.0, 3.5, 5.0),
    ("2951-2", "Sodium", "mmol/L", 120, 160, 136, 145),
    ("718-7", "Hemoglobin", "g/dL", 6.0, 20.0, 12.0, 17.5),
    ("4544-3", "Hematocrit", "%", 20, 60, 36, 51),
    ("6690-2", "White blood cell count", "10*3/uL", 1.0, 30.0, 4.5, 11.0),
    ("777-3", "Platelet count", "10*3/uL", 50, 600, 150, 400),
    ("1742-6", "ALT", "U/L", 5, 200, 7, 56),
    ("1920-8", "AST", "U/L", 5, 200, 10, 40),
    ("1975-2", "Total bilirubin", "mg/dL", 0.1, 10.0, 0.1, 1.2),
    ("2532-0", "LDH", "U/L", 100, 500, 140, 280),
    ("33914-3", "eGFR", "mL/min/1.73m2", 10, 120, 60, 120),
    ("30313-1", "Hemoglobin in blood", "g/dL", 6.0, 20.0, 12.0, 17.5),
    ("14959-1", "Microalbumin/Creatinine ratio", "mg/g", 0, 500, 0, 30),
]

# Medications (40 common drugs)
MEDICATIONS = [
    # (rxnorm_code, name, dosage, unit, route)
    ("860975", "Metformin", "500", "mg", "ORAL"),
    ("314076", "Lisinopril", "10", "mg", "ORAL"),
    ("259255", "Atorvastatin", "20", "mg", "ORAL"),
    ("372562", "Omeprazole", "20", "mg", "ORAL"),
    ("329526", "Amlodipine", "5", "mg", "ORAL"),
    ("866514", "Metoprolol Succinate", "50", "mg", "ORAL"),
    ("197361", "Levothyroxine", "50", "mcg", "ORAL"),
    ("310798", "Hydrochlorothiazide", "25", "mg", "ORAL"),
    ("861004", "Losartan", "50", "mg", "ORAL"),
    ("312961", "Gabapentin", "300", "mg", "ORAL"),
    ("197696", "Prednisone", "10", "mg", "ORAL"),
    ("198240", "Albuterol", "90", "mcg", "INHALED"),
    ("312938", "Furosemide", "40", "mg", "ORAL"),
    ("856903", "Warfarin", "5", "mg", "ORAL"),
    ("197591", "Amoxicillin", "500", "mg", "ORAL"),
    ("197517", "Azithromycin", "250", "mg", "ORAL"),
    ("312617", "Cephalexin", "500", "mg", "ORAL"),
    ("197884", "Ciprofloxacin", "500", "mg", "ORAL"),
    ("310404", "Fluticasone", "50", "mcg", "INHALED"),
    ("312615", "Cetirizine", "10", "mg", "ORAL"),
    ("197319", "Sertraline", "50", "mg", "ORAL"),
    ("312036", "Escitalopram", "10", "mg", "ORAL"),
    ("860981", "Metformin ER", "1000", "mg", "ORAL"),
    ("199247", "Tramadol", "50", "mg", "ORAL"),
    ("197803", "Ibuprofen", "400", "mg", "ORAL"),
    ("197650", "Acetaminophen", "500", "mg", "ORAL"),
    ("312289", "Duloxetine", "60", "mg", "ORAL"),
    ("860995", "Sitagliptin", "100", "mg", "ORAL"),
    ("261106", "Clopidogrel", "75", "mg", "ORAL"),
    ("311700", "Pantoprazole", "40", "mg", "ORAL"),
    ("199026", "Tamsulosin", "0.4", "mg", "ORAL"),
    ("198211", "Insulin Glargine", "100", "units/mL", "SUBCUTANEOUS"),
    ("206833", "Enoxaparin", "40", "mg", "SUBCUTANEOUS"),
    ("197461", "Morphine", "2", "mg", "IV"),
    ("312289", "Ondansetron", "4", "mg", "IV"),
    ("197512", "Aspirin", "81", "mg", "ORAL"),
    ("197436", "Montelukast", "10", "mg", "ORAL"),
    ("199314", "Trazodone", "50", "mg", "ORAL"),
    ("197381", "Lorazepam", "1", "mg", "ORAL"),
    ("866041", "Rosuvastatin", "10", "mg", "ORAL"),
]

FREQUENCIES = ["DAILY", "BID", "TID", "QID", "PRN", "WEEKLY"]
ROUTES = ["ORAL", "IV", "IM", "SUBCUTANEOUS", "TOPICAL", "INHALED"]
MED_STATUSES = ["ACTIVE", "COMPLETED", "STOPPED"]

# CPT codes (30 common procedures)
CPT_CODES = [
    ("99213", "Office/outpatient visit, established patient, low complexity"),
    ("99214", "Office/outpatient visit, established patient, moderate complexity"),
    ("99284", "Emergency department visit, high complexity"),
    ("99285", "Emergency department visit, highest complexity"),
    ("99223", "Initial hospital care, high complexity"),
    ("27447", "Total knee replacement"),
    ("27130", "Total hip replacement"),
    ("43239", "Upper GI endoscopy with biopsy"),
    ("45378", "Colonoscopy, diagnostic"),
    ("45380", "Colonoscopy with biopsy"),
    ("93000", "Electrocardiogram, 12-lead"),
    ("71046", "Chest X-ray, 2 views"),
    ("70553", "MRI brain without and with contrast"),
    ("74177", "CT abdomen and pelvis with contrast"),
    ("76856", "Ultrasound, pelvic, complete"),
    ("93306", "Echocardiography, complete"),
    ("36415", "Venipuncture"),
    ("99232", "Subsequent hospital care, moderate complexity"),
    ("47562", "Laparoscopic cholecystectomy"),
    ("49505", "Inguinal hernia repair"),
    ("59400", "Obstetrical care, vaginal delivery"),
    ("59510", "Cesarean delivery"),
    ("29881", "Arthroscopy, knee, surgical"),
    ("20610", "Joint injection, major joint"),
    ("64483", "Epidural injection, lumbar/sacral"),
    ("92928", "Percutaneous coronary stent placement"),
    ("33533", "Coronary artery bypass, single"),
    ("43644", "Laparoscopic gastric bypass"),
    ("55700", "Prostate biopsy"),
    ("19301", "Partial mastectomy"),
]

PROCEDURE_OUTCOMES = ["SUCCESSFUL", "COMPLICATED", "CANCELLED"]

# Clinical severity
SEVERITIES = ["MILD", "MODERATE", "SEVERE"]
CLINICAL_STATUSES = ["ACTIVE", "RESOLVED", "RECURRENCE"]

# Discharge dispositions
DISCHARGE_DISPOSITIONS = ["HOME", "HOME_HEALTH", "SNF", "REHAB", "EXPIRED", "AMA", "TRANSFER"]

# DRG codes (sample)
DRG_CODES = [
    "470", "871", "872", "291", "292", "193", "194", "690", "683", "392",
    "378", "775", "766", "065", "069", "190", "191", "302", "313", "481",
]

# US states and languages
US_STATES = ["CA", "TX", "FL", "NY", "IL", "PA", "OH", "GA", "NC", "MI",
             "NJ", "VA", "WA", "AZ", "MA", "TN", "IN", "MO", "MD", "WI"]

LANGUAGES = ["English", "Spanish", "Mandarin", "Vietnamese", "Tagalog",
             "Arabic", "Korean", "Russian", "Portuguese", "Haitian Creole"]

RACES = ["White", "Black or African American", "Asian", "American Indian or Alaska Native",
         "Native Hawaiian or Other Pacific Islander", "Other"]

ETHNICITIES = ["Not Hispanic or Latino", "Hispanic or Latino"]

GENDERS = ["Male", "Female", "Other"]

# Charlson Comorbidity Index — ICD-10 mapping
# Maps each CCI category to (weight, [icd10_prefix_list])
CHARLSON_ICD10_MAP = {
    "Myocardial Infarction":          (1, ["I21", "I22", "I25.2"]),
    "Congestive Heart Failure":       (1, ["I50", "I11.0", "I13.0", "I13.2"]),
    "Peripheral Vascular Disease":    (1, ["I70", "I71", "I73", "I77.1"]),
    "Cerebrovascular Disease":        (1, ["I60", "I61", "I62", "I63", "I64", "I65", "I66", "I67", "I68", "I69", "G45", "G46"]),
    "Dementia":                       (1, ["F00", "F01", "F02", "F03", "G30", "G31.1"]),
    "Chronic Pulmonary Disease":      (1, ["J40", "J41", "J42", "J43", "J44", "J45", "J46", "J47", "J60", "J61", "J62", "J63", "J64", "J65", "J66", "J67"]),
    "Rheumatic Disease":              (1, ["M05", "M06", "M32", "M33", "M34", "M35.1", "M35.3"]),
    "Peptic Ulcer Disease":           (1, ["K25", "K26", "K27", "K28"]),
    "Mild Liver Disease":             (1, ["B18", "K70.0", "K70.1", "K70.2", "K70.3", "K73", "K74", "K76.0"]),
    "Diabetes without Complications": (1, ["E10.0", "E10.1", "E10.9", "E11.0", "E11.1", "E11.9", "E13.0", "E13.1", "E13.9"]),
    "Diabetes with Complications":    (2, ["E10.2", "E10.3", "E10.4", "E10.5", "E10.6", "E10.7", "E10.8",
                                            "E11.2", "E11.3", "E11.4", "E11.5", "E11.6", "E11.7", "E11.8",
                                            "E13.2", "E13.3", "E13.4", "E13.5", "E13.6", "E13.7", "E13.8"]),
    "Hemiplegia/Paraplegia":          (2, ["G04.1", "G11.4", "G80", "G81", "G82"]),
    "Renal Disease":                  (2, ["N18", "N19", "N05", "I12.0", "I13.1"]),
    "Malignancy":                     (2, ["C0", "C1", "C2", "C30", "C31", "C32", "C33", "C34", "C37", "C38",
                                            "C39", "C40", "C41", "C43", "C45", "C46", "C47", "C48", "C49",
                                            "C50", "C51", "C52", "C53", "C54", "C55", "C56", "C57", "C58",
                                            "C60", "C61", "C62", "C63", "C64", "C65", "C66", "C67", "C68",
                                            "C69", "C70", "C71", "C72", "C73", "C74", "C75", "C76",
                                            "C81", "C82", "C83", "C84", "C85", "C88", "C90", "C91", "C92",
                                            "C93", "C94", "C95", "C96", "C97"]),
    "Moderate/Severe Liver Disease":  (3, ["K70.4", "K71.1", "K72", "K76.5", "K76.6", "K76.7", "I85"]),
    "Metastatic Solid Tumor":         (6, ["C77", "C78", "C79", "C80"]),
    "AIDS/HIV":                       (6, ["B20", "B21", "B22", "B24"]),
}

# Expected LOS by encounter class (days) for outlier detection
EXPECTED_LOS = {
    "INPATIENT": 5,
    "EMERGENCY": 1,
    "OBSERVATION": 1,
    "OUTPATIENT": 0,
    "AMBULATORY": 0,
}

# Target nurse-patient ratios by encounter class for staffing simulation
TARGET_NP_RATIOS = {
    "INPATIENT": (4.0, 6.5),     # Med-Surg range
    "EMERGENCY": (3.0, 5.0),     # ED range
    "OBSERVATION": (4.0, 5.0),
    "OUTPATIENT": None,           # N/A
    "AMBULATORY": None,           # N/A
}

DEFAULT_COUNTS = {
    'patients': 10000,
    'practitioners': 500,
    'organizations': 50,
    'encounters': 50000,
    'conditions': 30000,
    'observations': 100000,
    'medications': 25000,
    'procedures': 15000,
    'claims': 40000,
    # comorbidity_scores count is derived from patients — not an independent count
}


# ============================================================================
# GENERATOR
# ============================================================================

class HCLSGenerator(SourceSystemGenerator):
    """Generates synthetic FHIR clinical data with realistic clinical patterns."""

    SYSTEM_NAME = "FHIR"

    def __init__(self, seed: int = 42):
        self.seed = seed
        random.seed(seed)
        self.fake = Faker('en_US')
        self.fake.seed_instance(seed)
        self.patients: List[Dict] = []
        self.practitioners: List[Dict] = []
        self.organizations: List[Dict] = []
        self.encounters: List[Dict] = []
        # Track frequent utilizers (15% of patients with 10+ encounters)
        self.frequent_utilizer_indices: set = set()
        # Track diabetic patients for clinical correlation
        self.diabetic_patient_ids: set = set()

    def _hash(self, record: Dict) -> str:
        data = {k: v for k, v in record.items() if not k.startswith('_')}
        return hashlib.sha256(json.dumps(data, sort_keys=True, default=str).encode()).hexdigest()

    # ------------------------------------------------------------------
    # PATIENTS
    # ------------------------------------------------------------------
    def generate_patients(self, count: int) -> List[Dict]:
        print(f"  Generating {count} patients...")
        records = []

        # 15% are frequent utilizers
        freq_count = int(count * 0.15)
        self.frequent_utilizer_indices = set(random.sample(range(count), freq_count))

        for i in range(count):
            gender = random.choices(GENDERS, weights=[0.48, 0.50, 0.02])[0]
            if gender == "Male":
                first_name = self.fake.first_name_male()
            elif gender == "Female":
                first_name = self.fake.first_name_female()
            else:
                first_name = self.fake.first_name()

            payer_name = random.choices(
                [p[0] for p in INSURANCE_PAYERS],
                weights=[p[1] for p in INSURANCE_PAYERS]
            )[0]

            rec = {
                'patient_id': str(uuid.uuid5(uuid.NAMESPACE_OID, f"patient_{self.seed}_{i}")),
                'mrn': f"MRN-{1000000 + i:07d}",
                'first_name': first_name,
                'last_name': self.fake.last_name(),
                'birth_date': self.fake.date_of_birth(minimum_age=1, maximum_age=95).isoformat(),
                'gender': gender,
                'ssn': f"{random.randint(100, 999)}-{random.randint(10, 99)}-{random.randint(1000, 9999)}",
                'address_line1': self.fake.street_address(),
                'city': self.fake.city(),
                'state': random.choice(US_STATES),
                'zip_code': self.fake.zipcode(),
                'phone': self.fake.phone_number(),
                'email': self.fake.email(),
                'insurance_id': f"INS-{random.randint(100000000, 999999999)}",
                'insurance_payer': payer_name,
                'primary_language': random.choices(LANGUAGES, weights=[0.70, 0.13, 0.03, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02])[0],
                'race': random.choices(RACES, weights=[0.58, 0.13, 0.06, 0.01, 0.005, 0.215])[0],
                'ethnicity': random.choices(ETHNICITIES, weights=[0.81, 0.19])[0],
                'created_at': datetime.now().isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        self.patients = records
        return records

    # ------------------------------------------------------------------
    # PRACTITIONERS
    # ------------------------------------------------------------------
    def generate_practitioners(self, count: int) -> List[Dict]:
        print(f"  Generating {count} practitioners...")
        records = []

        for i in range(count):
            specialty = random.choice(SPECIALTIES)
            # NPI: 10-digit number
            npi = f"{random.randint(1000000000, 9999999999)}"
            # DEA: 2 letters + 7 digits
            dea_prefix = random.choice("ABCDEFGM") + random.choice("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
            dea_number = f"{dea_prefix}{random.randint(1000000, 9999999)}"

            rec = {
                'practitioner_id': str(uuid.uuid5(uuid.NAMESPACE_OID, f"practitioner_{self.seed}_{i}")),
                'npi': npi,
                'first_name': self.fake.first_name(),
                'last_name': self.fake.last_name(),
                'specialty': specialty,
                'org_id': '',  # Will be set after orgs are generated
                'license_state': random.choice(US_STATES),
                'dea_number': dea_number,
                'email': self.fake.email(),
                'phone': self.fake.phone_number(),
                'created_at': datetime.now().isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        self.practitioners = records
        return records

    # ------------------------------------------------------------------
    # ORGANIZATIONS
    # ------------------------------------------------------------------
    def generate_organizations(self, count: int) -> List[Dict]:
        print(f"  Generating {count} organizations...")
        records = []

        hospital_names = [
            "Memorial", "Regional Medical Center", "General Hospital", "Community Health",
            "University Hospital", "Children's Hospital", "Veterans Medical Center",
            "Sacred Heart", "Providence", "Mercy", "St. Joseph's", "Good Samaritan",
            "Northwestern", "Mount Sinai", "Johns Hopkins", "Mayo Clinic",
        ]

        for i in range(count):
            org_type = random.choices(ORG_TYPES, weights=[0.30, 0.25, 0.10, 0.10, 0.10, 0.08, 0.07])[0]

            if org_type == "HOSPITAL":
                name = f"{self.fake.city()} {random.choice(hospital_names)}"
                bed_count = random.randint(50, 800)
                trauma = random.choices(TRAUMA_LEVELS, weights=[0.1, 0.2, 0.3, 0.4])[0]
            elif org_type == "CLINIC":
                name = f"{self.fake.last_name()} {random.choice(['Medical Group', 'Health Clinic', 'Family Practice', 'Wellness Center'])}"
                bed_count = 0
                trauma = "NONE"
            elif org_type == "URGENT_CARE":
                name = f"{random.choice(['FastMed', 'MinuteClinic', 'CareNow', 'MedExpress', 'NextCare'])} - {self.fake.city()}"
                bed_count = 0
                trauma = "NONE"
            elif org_type == "LAB":
                name = f"{random.choice(['Quest Diagnostics', 'LabCorp', 'BioReference', 'ARUP'])} - {self.fake.city()}"
                bed_count = 0
                trauma = "NONE"
            else:
                name = f"{self.fake.city()} {org_type.replace('_', ' ').title()}"
                bed_count = random.randint(0, 100)
                trauma = "NONE"

            org_id = str(uuid.uuid5(uuid.NAMESPACE_OID, f"org_{self.seed}_{i}"))
            rec = {
                'org_id': org_id,
                'name': name,
                'type': org_type,
                'address': self.fake.street_address(),
                'city': self.fake.city(),
                'state': random.choice(US_STATES),
                'zip_code': self.fake.zipcode(),
                'phone': self.fake.phone_number(),
                'bed_count': bed_count,
                'trauma_level': trauma,
                'created_at': datetime.now().isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        self.organizations = records

        # Assign practitioners to organizations
        for prac in self.practitioners:
            org = random.choice(self.organizations)
            prac['org_id'] = org['org_id']
            prac['_ROW_HASH'] = self._hash(prac)

        return records

    # ------------------------------------------------------------------
    # ENCOUNTERS
    # ------------------------------------------------------------------
    def generate_encounters(self, count: int) -> List[Dict]:
        if not self.patients or not self.practitioners or not self.organizations:
            raise ValueError("Must generate patients, practitioners, and organizations first")
        print(f"  Generating {count} encounters...")
        records = []

        # Frequent utilizers get more encounters
        freq_patient_indices = list(self.frequent_utilizer_indices)
        normal_patient_indices = [i for i in range(len(self.patients)) if i not in self.frequent_utilizer_indices]

        for i in range(count):
            # 40% of encounters go to frequent utilizers (who are 15% of patients)
            if random.random() < 0.40 and freq_patient_indices:
                patient_idx = random.choice(freq_patient_indices)
            else:
                patient_idx = random.choice(normal_patient_indices) if normal_patient_indices else random.randint(0, len(self.patients) - 1)

            patient = self.patients[patient_idx]
            practitioner = random.choice(self.practitioners)
            org = random.choice(self.organizations)

            encounter_class = random.choices(
                ENCOUNTER_CLASSES,
                weights=[0.15, 0.20, 0.35, 0.20, 0.10]
            )[0]

            admit_date = self.fake.date_between(start_date='-3y', end_date='today')

            # Duration depends on encounter class
            if encounter_class in ("OUTPATIENT", "AMBULATORY"):
                duration_days = 0
            elif encounter_class == "EMERGENCY":
                duration_days = random.choices([0, 1, 2], weights=[0.5, 0.3, 0.2])[0]
            elif encounter_class == "OBSERVATION":
                duration_days = random.randint(0, 2)
            else:  # INPATIENT
                duration_days = random.randint(1, 14)

            discharge_date = admit_date + timedelta(days=duration_days)

            if discharge_date <= date.today():
                status = random.choices(["FINISHED", "CANCELLED"], weights=[0.95, 0.05])[0]
            else:
                status = "IN_PROGRESS"

            # Pick a diagnosis
            diag_code, diag_desc = random.choice(ICD10_CODES)

            # Track diabetic patients
            if diag_code in ("E11.9",):
                self.diabetic_patient_ids.add(patient['patient_id'])

            disposition = random.choice(DISCHARGE_DISPOSITIONS) if status == "FINISHED" and encounter_class == "INPATIENT" else "HOME"
            drg = random.choice(DRG_CODES) if encounter_class == "INPATIENT" else ""

            # Total charges
            if encounter_class == "INPATIENT":
                total_charges = round(random.uniform(5000, 150000), 2)
            elif encounter_class == "EMERGENCY":
                total_charges = round(random.uniform(500, 25000), 2)
            else:
                total_charges = round(random.uniform(100, 3000), 2)

            rec = {
                'encounter_id': str(uuid.uuid5(uuid.NAMESPACE_OID, f"encounter_{self.seed}_{i}")),
                'patient_id': patient['patient_id'],
                'practitioner_id': practitioner['practitioner_id'],
                'org_id': org['org_id'],
                'encounter_class': encounter_class,
                'status': status,
                'admit_date': admit_date.isoformat(),
                'discharge_date': discharge_date.isoformat() if duration_days > 0 or status == "FINISHED" else '',
                'discharge_disposition': disposition,
                'primary_diagnosis_code': diag_code,
                'drg_code': drg,
                'total_charges': total_charges,
                'created_at': datetime.now().isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        self.encounters = records
        return records

    # ------------------------------------------------------------------
    # CONDITIONS
    # ------------------------------------------------------------------
    def generate_conditions(self, count: int) -> List[Dict]:
        if not self.patients or not self.encounters:
            raise ValueError("Must generate patients and encounters first")
        print(f"  Generating {count} conditions...")
        records = []

        for i in range(count):
            encounter = random.choice(self.encounters)
            patient_id = encounter['patient_id']

            # Use encounter's diagnosis sometimes for consistency
            if random.random() < 0.3:
                code = encounter['primary_diagnosis_code']
                desc = next((d for c, d in ICD10_CODES if c == code), "Unknown")
            else:
                code, desc = random.choice(ICD10_CODES)

            # Track diabetics
            if code in ("E11.9",):
                self.diabetic_patient_ids.add(patient_id)

            onset_date = self.fake.date_between(start_date='-5y', end_date='today')
            clinical_status = random.choices(CLINICAL_STATUSES, weights=[0.60, 0.30, 0.10])[0]
            abatement_date = ''
            if clinical_status == "RESOLVED":
                abatement_date = (onset_date + timedelta(days=random.randint(7, 365))).isoformat()

            rec = {
                'condition_id': str(uuid.uuid5(uuid.NAMESPACE_OID, f"condition_{self.seed}_{i}")),
                'patient_id': patient_id,
                'encounter_id': encounter['encounter_id'],
                'icd10_code': code,
                'icd10_description': desc,
                'clinical_status': clinical_status,
                'onset_date': onset_date.isoformat(),
                'abatement_date': abatement_date,
                'severity': random.choices(SEVERITIES, weights=[0.40, 0.40, 0.20])[0],
                'created_at': datetime.now().isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        return records

    # ------------------------------------------------------------------
    # OBSERVATIONS
    # ------------------------------------------------------------------
    def generate_observations(self, count: int) -> List[Dict]:
        if not self.patients or not self.encounters:
            raise ValueError("Must generate patients and encounters first")
        print(f"  Generating {count} observations...")
        records = []

        for i in range(count):
            encounter = random.choice(self.encounters)
            patient_id = encounter['patient_id']

            # Select observation type
            loinc = random.choice(LOINC_CODES)
            code, desc, unit, val_min, val_max, normal_low, normal_high = loinc

            # 15% abnormal values
            if random.random() < 0.15:
                # Generate abnormal value
                if random.random() < 0.5:
                    value = round(random.uniform(val_min, normal_low * 0.9), 1)
                else:
                    value = round(random.uniform(normal_high * 1.1, val_max), 1)
            else:
                value = round(random.uniform(normal_low, normal_high), 1)

            # Clinical correlation: diabetic patients have higher HbA1c
            if code == "4548-4" and patient_id in self.diabetic_patient_ids:
                value = round(random.uniform(6.5, 12.0), 1)

            effective_date = self.fake.date_between(start_date='-3y', end_date='today')

            rec = {
                'observation_id': str(uuid.uuid5(uuid.NAMESPACE_OID, f"obs_{self.seed}_{i}")),
                'patient_id': patient_id,
                'encounter_id': encounter['encounter_id'],
                'loinc_code': code,
                'loinc_description': desc,
                'value_quantity': value,
                'value_unit': unit,
                'reference_range_low': normal_low,
                'reference_range_high': normal_high,
                'status': random.choices(["final", "preliminary", "amended"], weights=[0.90, 0.07, 0.03])[0],
                'effective_date': effective_date.isoformat(),
                'created_at': datetime.now().isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        return records

    # ------------------------------------------------------------------
    # MEDICATIONS
    # ------------------------------------------------------------------
    def generate_medications(self, count: int) -> List[Dict]:
        if not self.patients or not self.practitioners or not self.encounters:
            raise ValueError("Must generate patients, practitioners, and encounters first")
        print(f"  Generating {count} medications...")
        records = []

        for i in range(count):
            encounter = random.choice(self.encounters)
            patient_id = encounter['patient_id']
            practitioner = random.choice(self.practitioners)

            # Clinical correlation: diabetic patients get metformin
            if patient_id in self.diabetic_patient_ids and random.random() < 0.5:
                med = MEDICATIONS[0]  # Metformin
            else:
                med = random.choice(MEDICATIONS)

            rxnorm_code, med_name, dosage, dosage_unit, route = med
            frequency = random.choice(FREQUENCIES)
            start_date = self.fake.date_between(start_date='-3y', end_date='today')
            status = random.choices(MED_STATUSES, weights=[0.50, 0.35, 0.15])[0]

            if status == "COMPLETED":
                end_date = (start_date + timedelta(days=random.randint(7, 365))).isoformat()
            elif status == "STOPPED":
                end_date = (start_date + timedelta(days=random.randint(1, 180))).isoformat()
            else:
                end_date = ''

            rec = {
                'medication_id': str(uuid.uuid5(uuid.NAMESPACE_OID, f"med_{self.seed}_{i}")),
                'patient_id': patient_id,
                'practitioner_id': practitioner['practitioner_id'],
                'encounter_id': encounter['encounter_id'],
                'rxnorm_code': rxnorm_code,
                'medication_name': med_name,
                'dosage': dosage,
                'dosage_unit': dosage_unit,
                'frequency': frequency,
                'route': route,
                'start_date': start_date.isoformat(),
                'end_date': end_date,
                'status': status,
                'created_at': datetime.now().isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        return records

    # ------------------------------------------------------------------
    # PROCEDURES
    # ------------------------------------------------------------------
    def generate_procedures(self, count: int) -> List[Dict]:
        if not self.patients or not self.practitioners or not self.encounters:
            raise ValueError("Must generate patients, practitioners, and encounters first")
        print(f"  Generating {count} procedures...")
        records = []

        for i in range(count):
            encounter = random.choice(self.encounters)
            patient_id = encounter['patient_id']
            practitioner = random.choice(self.practitioners)
            cpt_code, cpt_desc = random.choice(CPT_CODES)

            performed_date = self.fake.date_between(start_date='-3y', end_date='today')

            # Duration based on procedure type
            if "visit" in cpt_desc.lower():
                duration = random.randint(10, 45)
            elif "replacement" in cpt_desc.lower() or "bypass" in cpt_desc.lower():
                duration = random.randint(120, 360)
            elif "endoscopy" in cpt_desc.lower() or "colonoscopy" in cpt_desc.lower():
                duration = random.randint(30, 90)
            else:
                duration = random.randint(15, 120)

            rec = {
                'procedure_id': str(uuid.uuid5(uuid.NAMESPACE_OID, f"proc_{self.seed}_{i}")),
                'patient_id': patient_id,
                'encounter_id': encounter['encounter_id'],
                'practitioner_id': practitioner['practitioner_id'],
                'cpt_code': cpt_code,
                'cpt_description': cpt_desc,
                'performed_date': performed_date.isoformat(),
                'duration_minutes': duration,
                'outcome': random.choices(PROCEDURE_OUTCOMES, weights=[0.85, 0.10, 0.05])[0],
                'created_at': datetime.now().isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        return records

    # ------------------------------------------------------------------
    # CLAIMS
    # ------------------------------------------------------------------
    def generate_claims(self, count: int) -> List[Dict]:
        if not self.patients or not self.encounters or not self.organizations:
            raise ValueError("Must generate patients, encounters, and organizations first")
        print(f"  Generating {count} claims...")
        records = []

        for i in range(count):
            encounter = random.choice(self.encounters)
            patient_id = encounter['patient_id']
            patient = next((p for p in self.patients if p['patient_id'] == patient_id), None)
            org = random.choice(self.organizations)

            total_charge = encounter['total_charges']
            # Allowed: 60-90% of charge
            allowed_pct = random.uniform(0.60, 0.90)
            allowed_amount = round(total_charge * allowed_pct, 2)
            # Paid: 70-100% of allowed
            paid_pct = random.uniform(0.70, 1.00)
            paid_amount = round(allowed_amount * paid_pct, 2)
            patient_responsibility = round(allowed_amount - paid_amount, 2)

            payer_name = patient['insurance_payer'] if patient else "Self-Pay"

            service_date = self.fake.date_between(start_date='-3y', end_date='today')
            submitted_date = service_date + timedelta(days=random.randint(1, 14))
            adjudicated_date = submitted_date + timedelta(days=random.randint(7, 90))

            claim_status = random.choices(
                ["PAID", "DENIED", "PENDING", "APPEALED"],
                weights=[0.70, 0.10, 0.12, 0.08]
            )[0]

            rec = {
                'claim_id': f"CLM-{900000 + i:08d}",
                'patient_id': patient_id,
                'encounter_id': encounter['encounter_id'],
                'org_id': org['org_id'],
                'payer_id': f"PYR-{hash(payer_name) % 1000:03d}",
                'payer_name': payer_name,
                'total_charge': total_charge,
                'allowed_amount': allowed_amount,
                'paid_amount': paid_amount,
                'patient_responsibility': patient_responsibility,
                'claim_status': claim_status,
                'service_date': service_date.isoformat(),
                'submitted_date': submitted_date.isoformat(),
                'adjudicated_date': adjudicated_date.isoformat() if claim_status != "PENDING" else '',
                'created_at': datetime.now().isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        return records

    # ------------------------------------------------------------------
    # STAFFING CONTEXT (lightweight simulation on encounters)
    # ------------------------------------------------------------------
    def add_staffing_context(self) -> None:
        """Add staffing context columns to each encounter for cross-system analysis.

        Simulates unit staffing at encounter time. Must be called BEFORE
        flag_readmissions() so readmission probability can use staffing data.
        """
        if not self.encounters:
            return
        print("  Adding staffing context to encounters...")

        for rec in self.encounters:
            enc_class = rec['encounter_class']
            ratio_range = TARGET_NP_RATIOS.get(enc_class)
            if ratio_range is None:
                # Outpatient/Ambulatory: staffing context not applicable
                rec['unit_census'] = None
                rec['nurse_patient_ratio'] = None
                rec['staffing_adequacy'] = None
                continue

            # Find org bed count for census simulation
            org = next((o for o in self.organizations if o['org_id'] == rec['org_id']), None)
            bed_count = org['bed_count'] if org and org['bed_count'] > 0 else 100

            # Simulate census (40-90% occupancy)
            occupancy = random.uniform(0.40, 0.90)
            rec['unit_census'] = max(1, int(bed_count * occupancy))

            # Simulate nurse-patient ratio with some variance
            target_low, target_high = ratio_range
            target_mid = (target_low + target_high) / 2.0

            # 25% chance of understaffing (ratio above target range)
            if random.random() < 0.25:
                rec['nurse_patient_ratio'] = round(random.uniform(target_high, target_high * 1.5), 1)
                rec['staffing_adequacy'] = 'UNDERSTAFFED'
            # 15% chance of marginal staffing
            elif random.random() < 0.20:
                rec['nurse_patient_ratio'] = round(random.uniform(target_mid, target_high), 1)
                rec['staffing_adequacy'] = 'MARGINAL'
            else:
                rec['nurse_patient_ratio'] = round(random.uniform(target_low * 0.7, target_mid), 1)
                rec['staffing_adequacy'] = 'ADEQUATE'

    # ------------------------------------------------------------------
    # READMISSION FLAGS
    # ------------------------------------------------------------------
    def flag_readmissions(self) -> None:
        """Flag 30-day readmissions on encounters.

        Must be called AFTER add_staffing_context() so understaffing can
        influence readmission probability.
        """
        if not self.encounters:
            return
        print("  Flagging 30-day readmissions...")

        # Group encounters by patient, sorted by admit_date
        from collections import defaultdict
        patient_encounters: Dict[str, List[Dict]] = defaultdict(list)
        for rec in self.encounters:
            patient_encounters[rec['patient_id']].append(rec)

        for pid, encs in patient_encounters.items():
            encs.sort(key=lambda e: e['admit_date'])

            for idx, rec in enumerate(encs):
                # Compute LOS
                if rec['discharge_date']:
                    admit = date.fromisoformat(rec['admit_date'])
                    discharge = date.fromisoformat(rec['discharge_date'])
                    rec['los_days'] = (discharge - admit).days
                else:
                    rec['los_days'] = 0

                # LOS outlier detection
                expected = EXPECTED_LOS.get(rec['encounter_class'], 1)
                rec['los_outlier'] = rec['los_days'] > (2 * expected) if expected > 0 else False

                # Days since last encounter for this patient
                if idx > 0:
                    prev_discharge = encs[idx - 1].get('discharge_date') or encs[idx - 1]['admit_date']
                    days_gap = (date.fromisoformat(rec['admit_date']) - date.fromisoformat(prev_discharge)).days
                    rec['days_since_last_encounter'] = max(0, days_gap)
                else:
                    rec['days_since_last_encounter'] = None

                # 30-day readmission: check if next encounter for same patient is within 30 days
                if idx < len(encs) - 1:
                    current_discharge = rec.get('discharge_date') or rec['admit_date']
                    next_admit = encs[idx + 1]['admit_date']
                    days_to_next = (date.fromisoformat(next_admit) - date.fromisoformat(current_discharge)).days

                    # Base readmission probability based on days
                    if 0 <= days_to_next <= 30:
                        base_readmit = True
                    else:
                        base_readmit = False

                    # Understaffed encounters have 2x readmission probability
                    # For encounters outside 30-day window but within 45 days,
                    # understaffing can push them into "readmission" territory
                    if not base_readmit and rec.get('staffing_adequacy') == 'UNDERSTAFFED' and 30 < days_to_next <= 45:
                        base_readmit = random.random() < 0.30  # 30% chance for understaffed near-misses

                    rec['readmission_30day'] = base_readmit
                else:
                    rec['readmission_30day'] = False

    # ------------------------------------------------------------------
    # COMORBIDITY SCORING (Charlson CCI)
    # ------------------------------------------------------------------
    def compute_comorbidity_scores(self, conditions: List[Dict]) -> List[Dict]:
        """Compute Charlson Comorbidity Index for each patient from conditions.

        Args:
            conditions: List of condition records (must have patient_id and icd10_code).

        Returns:
            List of dicts with: patient_id, cci_score, cci_tier, condition_count,
            top_conditions (comma-separated top 3 ICD-10 descriptions).
        """
        print("  Computing comorbidity scores (Charlson CCI)...")
        from collections import defaultdict

        # Build per-patient condition sets
        patient_conditions: Dict[str, List[tuple]] = defaultdict(list)
        for cond in conditions:
            patient_conditions[cond['patient_id']].append(
                (cond['icd10_code'], cond.get('icd10_description', ''))
            )

        records = []
        for patient in self.patients:
            pid = patient['patient_id']
            conds = patient_conditions.get(pid, [])

            # Determine which CCI categories are triggered (each counted once)
            triggered_categories = {}
            for code, desc in conds:
                for category, (weight, prefixes) in CHARLSON_ICD10_MAP.items():
                    if category in triggered_categories:
                        continue
                    for prefix in prefixes:
                        if code.startswith(prefix):
                            triggered_categories[category] = weight
                            break

            cci_score = sum(triggered_categories.values())

            # Tier assignment
            if cci_score <= 1:
                cci_tier = "LOW"
            elif cci_score <= 3:
                cci_tier = "MODERATE"
            elif cci_score <= 6:
                cci_tier = "HIGH"
            else:
                cci_tier = "SEVERE"

            # Top 3 conditions by frequency
            desc_counts: Dict[str, int] = defaultdict(int)
            for code, desc in conds:
                if desc:
                    desc_counts[desc] += 1
            top_3 = sorted(desc_counts.items(), key=lambda x: -x[1])[:3]
            top_conditions = ", ".join(d for d, _ in top_3)

            rec = {
                'patient_id': pid,
                'cci_score': cci_score,
                'cci_tier': cci_tier,
                'condition_count': len(conds),
                'top_conditions': top_conditions,
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
        # Stage 1: Core entities
        data['patients'] = self.generate_patients(counts.get('patients', 10000))
        data['practitioners'] = self.generate_practitioners(counts.get('practitioners', 500))
        data['organizations'] = self.generate_organizations(counts.get('organizations', 50))
        data['encounters'] = self.generate_encounters(counts.get('encounters', 50000))

        # Stage 2: Staffing context + readmission flags (order matters)
        self.add_staffing_context()          # adds context columns to encounters
        self.flag_readmissions()             # uses staffing to influence readmission probability

        # Stage 3: Clinical details
        data['conditions'] = self.generate_conditions(counts.get('conditions', 30000))
        data['observations'] = self.generate_observations(counts.get('observations', 100000))
        data['medications'] = self.generate_medications(counts.get('medications', 25000))
        data['procedures'] = self.generate_procedures(counts.get('procedures', 15000))
        data['claims'] = self.generate_claims(counts.get('claims', 40000))

        # Stage 4: Comorbidity scoring (needs conditions)
        data['comorbidity_scores'] = self.compute_comorbidity_scores(data['conditions'])

        return data


# ============================================================================
# OUTPUT — delegates to base data_generator.save_to_csv
# ============================================================================

def save_to_csv(data: Dict[str, List[Dict]], output_dir: str):
    """Save using the base data_generator's save_to_csv (unchanged)."""
    base_save_to_csv(data, output_dir, "FHIR")


# ============================================================================
# CLI
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Generate HCLS clinical data for Snowflake DCA demo",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python generate_hcls_data.py --output ../data
  python generate_hcls_data.py --output ../data --quick
  python generate_hcls_data.py --output ../data --scale 2.0
  python generate_hcls_data.py --output ../data --seed 123
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
    print("HCLS CLINICAL DATA GENERATOR")
    print("=" * 60)
    print(f"  Seed:   {args.seed}")
    print(f"  Scale:  {'quick (10%)' if args.quick else f'{args.scale}x'}")
    print(f"  Output: {args.output}")
    print(f"  Counts: {counts}")
    print()

    generator = HCLSGenerator(seed=args.seed)
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
