#!/usr/bin/env python3
"""
Workday HCM Data Center Operations Data Generator for Snowflake DCA Demo

Generates synthetic Workday HCM data for data center operations technicians
with SCD Type 6 columns: technicians, certifications, shifts, skill assignments,
teams, time off, and training completions.

Usage:
    python generate_workday_dcim_data.py --output ../data
    python generate_workday_dcim_data.py --output ../data --quick
    python generate_workday_dcim_data.py --output ../data --scale 2.0
"""

import os
import sys
import random
import hashlib
import json
import uuid
import argparse
from datetime import datetime, timedelta, date
from typing import List, Dict, Any, Optional

# ---------------------------------------------------------------------------
# Base infrastructure import
# ---------------------------------------------------------------------------
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', '..', 'tools'))
from data_generator import SourceSystemGenerator, save_to_csv as base_save_to_csv

from faker import Faker

# ============================================================================
# CONSTANTS
# ============================================================================

DEFAULT_COUNTS = {
    'technicians': 500,
    'certifications': 3000,
    'shifts': 50000,
    'skill_assignments': 2000,
    'teams': 50,
    'time_off': 5000,
    'training_completions': 8000,
}

CERTIFICATION_TYPES = [
    "Fiber Splicing - Level 1",
    "Fiber Splicing - Level 2",
    "Fiber Splicing - Level 3",
    "High-Voltage Electrical",
    "Cisco CCNP Data Center",
    "Juniper JNCIS-DC",
    "CDCP (Certified Data Center Professional)",
    "CDCS (Certified Data Center Specialist)",
    "CDFOM (Certified Data Facility Operations Manager)",
    "Fire Suppression Systems",
    "Environmental Controls (HVAC)",
    "Physical Security Clearance",
]

SKILL_TYPES = [
    "Network Troubleshooting",
    "Fiber Optics",
    "Power Systems",
    "Cooling Systems",
    "Rack & Stack",
    "Cable Management",
    "Firmware Management",
    "Incident Response",
    "Capacity Planning",
    "Physical Security",
]

JOB_TITLES = [
    "Data Center Technician I",
    "Data Center Technician II",
    "Data Center Technician III",
    "Senior Data Center Technician",
    "Lead Data Center Engineer",
    "Data Center Operations Manager",
    "Network Operations Technician",
    "Facilities Engineer",
    "Infrastructure Specialist",
    "Cable Plant Technician",
]

SHIFT_PATTERNS = ['4x10', '3x12', '5x8', 'Panama', 'DuPont', 'Pitman']

SPECIALTY_AREAS = [
    "Network Infrastructure", "Power & Cooling", "Physical Security",
    "Capacity Management", "Incident Response", "Decommissioning",
    "Fiber Plant", "Firmware & Patching", "Environmental Controls",
    "Cross-Connect Operations",
]

TRAINING_COURSES = [
    "DCIM Fundamentals", "Advanced Fiber Splicing", "High-Voltage Safety",
    "Network Protocol Essentials", "HVAC Operations for DC", "Fire Safety & Suppression",
    "Rack & Stack Best Practices", "Cable Management Standards",
    "Emergency Response Procedures", "Change Management Process",
    "ITIL Foundations", "Capacity Planning Workshop",
    "BGP/OSPF Troubleshooting", "Power Distribution Unit Operations",
    "Environmental Monitoring Systems", "Physical Access Control Systems",
    "Data Center Decommissioning", "Firmware Upgrade Procedures",
    "Incident Command System", "Safety Compliance Annual Review",
]


# ============================================================================
# WORKDAY DCIM GENERATOR
# ============================================================================

class WorkdayDCIMGenerator(SourceSystemGenerator):
    """Generates Workday HCM data for data center operations workforce."""

    SYSTEM_NAME = "WORKDAY"

    def __init__(self, seed: int = 42):
        super().__init__(seed)
        self.now = datetime.now()
        # Number of data centers must match ServiceNow generator (default 20)
        self.num_campuses = 20

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------
    def _id(self, prefix: str, index: int) -> str:
        return str(uuid.uuid5(uuid.NAMESPACE_OID, f'{prefix}_{self.seed}_{index}'))

    def _hash(self, record: Dict) -> str:
        data = {k: v for k, v in record.items() if not k.startswith('_')}
        return hashlib.sha256(json.dumps(data, sort_keys=True, default=str).encode()).hexdigest()

    def _scd6_current(self, record: Dict, valid_from: datetime) -> Dict:
        record['_VALID_FROM'] = valid_from.isoformat()
        record['_VALID_TO'] = '9999-12-31T00:00:00'
        record['_IS_CURRENT'] = True
        record['_VERSION'] = 1
        record['_SOURCE_SYSTEM'] = self.SYSTEM_NAME
        record['_LOADED_AT'] = self.now.isoformat()
        record['_ROW_HASH'] = self._hash(record)
        return record

    def _scd6_historical(self, record: Dict, valid_from: datetime,
                         valid_to: datetime, version: int) -> Dict:
        record['_VALID_FROM'] = valid_from.isoformat()
        record['_VALID_TO'] = valid_to.isoformat()
        record['_IS_CURRENT'] = False
        record['_VERSION'] = version
        record['_SOURCE_SYSTEM'] = self.SYSTEM_NAME
        record['_LOADED_AT'] = self.now.isoformat()
        record['_ROW_HASH'] = self._hash(record)
        return record

    # ------------------------------------------------------------------
    # TEAMS
    # ------------------------------------------------------------------
    def generate_teams(self, count: int) -> List[Dict]:
        print(f"  Generating {count} teams...")
        records = []

        for i in range(count):
            campus_idx = i % self.num_campuses
            campus_id = self._id('campus', campus_idx)
            manager_idx = i  # Each team has a unique manager from technicians pool
            specialty = SPECIALTY_AREAS[i % len(SPECIALTY_AREAS)]

            record = {
                'team_id': self._id('team', i),
                'team_name': f"{specialty} Team {campus_idx + 1:02d}-{i % 5 + 1}",
                'campus_id': campus_id,
                'manager_id': self._id('technician', manager_idx),
                'specialty_area': specialty,
                'headcount_target': random.randint(8, 20),
                'created_date': self.fake.date_between(start_date='-10y', end_date='-1y').isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_LOADED_AT': self.now.isoformat(),
            }
            record['_ROW_HASH'] = self._hash(record)
            records.append(record)

        self._teams = records
        return records

    # ------------------------------------------------------------------
    # TECHNICIANS
    # ------------------------------------------------------------------
    def generate_technicians(self, count: int) -> List[Dict]:
        print(f"  Generating {count} technicians...")
        records = []
        team_ids = [t['team_id'] for t in self._teams]

        move_pct = 0.15  # 15% have moved campuses

        for i in range(count):
            worker_id = self._id('technician', i)
            campus_idx = i % self.num_campuses
            campus_id = self._id('campus', campus_idx)
            team_id = team_ids[i % len(team_ids)]
            job_title = random.choice(JOB_TITLES)
            shift_pattern = random.choice(SHIFT_PATTERNS)
            hire_date = self.fake.date_between(start_date='-15y', end_date='-30d')

            has_move = random.random() < move_pct
            original_campus_idx = (campus_idx + random.randint(1, 10)) % self.num_campuses if has_move else campus_idx
            original_campus_id = self._id('campus', original_campus_idx)
            original_team_id = team_ids[(i + random.randint(1, 10)) % len(team_ids)] if has_move else team_id

            record = {
                'worker_id': worker_id,
                'employee_id': f"EMP{i+1:06d}",
                'first_name': self.fake.first_name(),
                'last_name': self.fake.last_name(),
                'full_name': None,  # set below
                'job_title': job_title,
                'job_family': 'Data Center Operations',
                'hire_date': hire_date.isoformat(),
                'campus_assignment': campus_id,
                'team': team_id,
                'shift_pattern': shift_pattern,
                'pay_grade': random.choice(['L3', 'L4', 'L5', 'L6', 'L7']),
                'manager_id': self._id('technician', max(0, i - random.randint(1, 20))),
                'email': f"tech{i+1:06d}@datacenter-ops.example.com",
                'phone': self.fake.phone_number(),
                'employment_status': random.choices(
                    ['ACTIVE', 'ACTIVE', 'ACTIVE', 'ACTIVE', 'ON_LEAVE', 'TERMINATED'],
                    weights=[60, 60, 60, 60, 5, 2]
                )[0],
                # SCD6
                'current_campus_assignment': campus_id,
                'historical_campus_assignment': campus_id if not has_move else original_campus_id,
                'original_campus_assignment': original_campus_id,
                'current_team': team_id,
                'historical_team': team_id if not has_move else original_team_id,
                'original_team': original_team_id,
            }
            record['full_name'] = f"{record['first_name']} {record['last_name']}"

            valid_from = datetime.combine(hire_date, datetime.min.time())

            if has_move:
                move_date = self.fake.date_between(start_date=hire_date, end_date='today')
                hist = dict(record)
                hist['campus_assignment'] = original_campus_id
                hist['team'] = original_team_id
                hist['historical_campus_assignment'] = original_campus_id
                hist['historical_team'] = original_team_id
                hist['current_campus_assignment'] = campus_id  # always latest
                hist['current_team'] = team_id
                self._scd6_historical(hist, valid_from, datetime.combine(move_date, datetime.min.time()), 1)
                records.append(hist)

                record['_VERSION'] = 2
                valid_from = datetime.combine(move_date, datetime.min.time())

            self._scd6_current(record, valid_from)
            records.append(record)

        self._technicians = [r for r in records if r['_IS_CURRENT']]
        return records

    # ------------------------------------------------------------------
    # CERTIFICATIONS
    # ------------------------------------------------------------------
    def generate_certifications(self, count: int) -> List[Dict]:
        print(f"  Generating {count} certifications...")
        records = []
        tech_ids = [t['worker_id'] for t in self._technicians]

        for i in range(count):
            cert_type = random.choice(CERTIFICATION_TYPES)
            worker_id = random.choice(tech_ids)
            issue_date = self.fake.date_between(start_date='-8y', end_date='-30d')
            validity_years = random.choice([1, 2, 3, 3, 5])
            expiry_date = issue_date + timedelta(days=validity_years * 365)

            if expiry_date < date.today():
                status = random.choice(['EXPIRED', 'EXPIRED', 'PENDING_RENEWAL'])
            else:
                status = 'ACTIVE'

            ce_hours = random.randint(8, 80)

            # SCD6: track status changes (~20% of expired certs have been renewed)
            has_renewal = status == 'EXPIRED' and random.random() < 0.20
            original_status = 'ACTIVE'

            record = {
                'cert_id': self._id('cert', i),
                'worker_id': worker_id,
                'cert_type': cert_type,
                'issuing_body': random.choice([
                    'Uptime Institute', 'BICSI', 'Cisco Systems', 'Juniper Networks',
                    'CompTIA', 'EPI', 'NFPA', 'ASHRAE', 'ASIS International',
                ]),
                'issue_date': issue_date.isoformat(),
                'expiry_date': expiry_date.isoformat(),
                'status': status,
                'ce_hours': ce_hours,
                'ce_hours_required': random.choice([20, 30, 40, 60]),
                # SCD6
                'current_status': status,
                'historical_status': status if not has_renewal else 'ACTIVE',
                'original_status': original_status,
            }

            valid_from = datetime.combine(issue_date, datetime.min.time())

            if has_renewal:
                # The cert went from ACTIVE -> EXPIRED, so historical shows it at ACTIVE before expiry
                expiry_dt = datetime.combine(expiry_date, datetime.min.time())
                hist = dict(record)
                hist['status'] = 'ACTIVE'
                hist['current_status'] = status  # always points to latest
                hist['historical_status'] = 'ACTIVE'
                self._scd6_historical(hist, valid_from, expiry_dt, 1)
                records.append(hist)

                record['_VERSION'] = 2
                valid_from = expiry_dt

            self._scd6_current(record, valid_from)
            records.append(record)

        return records

    # ------------------------------------------------------------------
    # SHIFTS
    # ------------------------------------------------------------------
    def generate_shifts(self, count: int) -> List[Dict]:
        print(f"  Generating {count} shifts...")
        records = []
        tech_ids = [t['worker_id'] for t in self._technicians]
        tech_campus = {t['worker_id']: t['campus_assignment'] for t in self._technicians}

        shift_types = ['DAY', 'SWING', 'NIGHT']
        shift_hours = {
            'DAY': ('06:00', '18:00', 12),
            'SWING': ('14:00', '22:00', 8),
            'NIGHT': ('22:00', '06:00', 8),
        }

        for i in range(count):
            worker_id = random.choice(tech_ids)
            shift_type = random.choices(shift_types, weights=[50, 25, 25])[0]
            shift_date = self.fake.date_between(start_date='-90d', end_date='today')
            start_time, end_time, base_hours = shift_hours[shift_type]
            hours_worked = round(base_hours + random.uniform(-0.5, 2.0), 1)

            record = {
                'shift_id': self._id('shift', i),
                'worker_id': worker_id,
                'campus_id': tech_campus.get(worker_id, self._id('campus', 0)),
                'shift_date': shift_date.isoformat(),
                'start_time': start_time,
                'end_time': end_time,
                'hours_worked': max(0.5, hours_worked),
                'shift_type': shift_type,
                'overtime': hours_worked > base_hours,
                'status': random.choices(
                    ['COMPLETED', 'COMPLETED', 'COMPLETED', 'SCHEDULED', 'CANCELLED', 'NO_SHOW'],
                    weights=[70, 70, 70, 10, 3, 2]
                )[0],
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_LOADED_AT': self.now.isoformat(),
            }
            record['_ROW_HASH'] = self._hash(record)
            records.append(record)

        return records

    # ------------------------------------------------------------------
    # SKILL ASSIGNMENTS
    # ------------------------------------------------------------------
    def generate_skill_assignments(self, count: int) -> List[Dict]:
        print(f"  Generating {count} skill assignments...")
        records = []
        tech_ids = [t['worker_id'] for t in self._technicians]

        for i in range(count):
            skill_type = random.choice(SKILL_TYPES)
            assessed_date = self.fake.date_between(start_date='-3y', end_date='today')

            record = {
                'skill_id': self._id('skill', i),
                'worker_id': random.choice(tech_ids),
                'skill_type': skill_type,
                'proficiency_level': random.randint(1, 5),
                'last_assessed_date': assessed_date.isoformat(),
                'assessment_method': random.choice(['Practical Exam', 'Peer Review', 'Manager Assessment', 'Certification', 'Self-Assessment']),
                'notes': None,
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_LOADED_AT': self.now.isoformat(),
            }
            record['_ROW_HASH'] = self._hash(record)
            records.append(record)

        return records

    # ------------------------------------------------------------------
    # TIME OFF
    # ------------------------------------------------------------------
    def generate_time_off(self, count: int) -> List[Dict]:
        print(f"  Generating {count} time off requests...")
        records = []
        tech_ids = [t['worker_id'] for t in self._technicians]

        leave_types = ['PTO', 'SICK', 'TRAINING']
        leave_weights = [50, 30, 20]
        statuses = ['APPROVED', 'APPROVED', 'APPROVED', 'PENDING', 'DENIED', 'CANCELLED']

        for i in range(count):
            worker_id = random.choice(tech_ids)
            leave_type = random.choices(leave_types, weights=leave_weights)[0]
            start_date = self.fake.date_between(start_date='-180d', end_date='+30d')
            duration_days = {'PTO': random.randint(1, 10), 'SICK': random.randint(1, 5), 'TRAINING': random.randint(1, 5)}[leave_type]
            end_date = start_date + timedelta(days=duration_days)

            record = {
                'request_id': self._id('timeoff', i),
                'worker_id': worker_id,
                'type': leave_type,
                'start_date': start_date.isoformat(),
                'end_date': end_date.isoformat(),
                'duration_days': duration_days,
                'status': random.choice(statuses),
                'submitted_date': (start_date - timedelta(days=random.randint(1, 30))).isoformat(),
                'reason': None if leave_type != 'TRAINING' else random.choice(TRAINING_COURSES),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_LOADED_AT': self.now.isoformat(),
            }
            record['_ROW_HASH'] = self._hash(record)
            records.append(record)

        return records

    # ------------------------------------------------------------------
    # TRAINING COMPLETIONS
    # ------------------------------------------------------------------
    def generate_training_completions(self, count: int) -> List[Dict]:
        print(f"  Generating {count} training completions...")
        records = []
        tech_ids = [t['worker_id'] for t in self._technicians]

        # Map courses to certifications they support
        cert_course_map = {
            "Advanced Fiber Splicing": "Fiber Splicing - Level 2",
            "High-Voltage Safety": "High-Voltage Electrical",
            "Network Protocol Essentials": "Cisco CCNP Data Center",
            "HVAC Operations for DC": "Environmental Controls (HVAC)",
            "Fire Safety & Suppression": "Fire Suppression Systems",
            "DCIM Fundamentals": "CDCP (Certified Data Center Professional)",
            "Physical Access Control Systems": "Physical Security Clearance",
        }

        for i in range(count):
            course = random.choice(TRAINING_COURSES)
            completion_date = self.fake.date_between(start_date='-3y', end_date='today')
            score = random.randint(60, 100)

            record = {
                'completion_id': self._id('training', i),
                'worker_id': random.choice(tech_ids),
                'course_name': course,
                'completion_date': completion_date.isoformat(),
                'score': score,
                'passed': score >= 70,
                'credit_hours': random.choice([4, 8, 16, 24, 40]),
                'required_for_cert': cert_course_map.get(course),
                'delivery_method': random.choice(['In-Person', 'Virtual', 'Self-Paced', 'Lab-Based']),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_LOADED_AT': self.now.isoformat(),
            }
            record['_ROW_HASH'] = self._hash(record)
            records.append(record)

        return records

    # ------------------------------------------------------------------
    # ORCHESTRATOR
    # ------------------------------------------------------------------
    def generate(self, counts: Dict[str, int]) -> Dict[str, List[Dict]]:
        data = {}
        # Teams first (technicians reference them)
        data['teams'] = self.generate_teams(counts.get('teams', 50))

        # Core: technicians
        data['technicians'] = self.generate_technicians(counts.get('technicians', 500))

        # Dependent tables
        data['certifications'] = self.generate_certifications(counts.get('certifications', 3000))
        data['shifts'] = self.generate_shifts(counts.get('shifts', 50000))
        data['skill_assignments'] = self.generate_skill_assignments(counts.get('skill_assignments', 2000))
        data['time_off'] = self.generate_time_off(counts.get('time_off', 5000))
        data['training_completions'] = self.generate_training_completions(counts.get('training_completions', 8000))

        return data


# ============================================================================
# OUTPUT
# ============================================================================

def save_to_csv(data: Dict[str, List[Dict]], output_dir: str):
    """Save using the base data_generator's save_to_csv."""
    base_save_to_csv(data, output_dir, "workday_dcim")


# ============================================================================
# CLI
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Generate Workday HCM data center operations data for Snowflake DCA demo",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python generate_workday_dcim_data.py --output ../data
  python generate_workday_dcim_data.py --output ../data --quick
  python generate_workday_dcim_data.py --output ../data --scale 2.0
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
    print("WORKDAY DCIM DATA GENERATOR")
    print("=" * 60)
    print(f"  Seed:   {args.seed}")
    print(f"  Scale:  {'quick (10%)' if args.quick else f'{args.scale}x'}")
    print(f"  Output: {args.output}")
    print(f"  Counts: {counts}")
    print()

    generator = WorkdayDCIMGenerator(seed=args.seed)
    data = generator.generate(counts)

    print()
    print("=" * 60)
    print("GENERATION COMPLETE")
    print("=" * 60)
    for table, recs in data.items():
        print(f"  {table:25s} {len(recs):>10,} records")

    print()
    save_to_csv(data, args.output)
    print("\nDone!")


if __name__ == "__main__":
    main()
