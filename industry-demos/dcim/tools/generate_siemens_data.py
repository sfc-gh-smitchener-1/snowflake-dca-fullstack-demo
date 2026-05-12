#!/usr/bin/env python3
"""
Siemens Desigo CC / MindSphere DCIM Data Generator for Snowflake DCA Demo

Generates synthetic data representing an ACQUIRED company's 2,000 data centers
running Siemens Desigo CC as their primary DCIM. This creates entity resolution
challenges with the existing ServiceNow CMDB — Siemens tracks its own rack
inventory, facilities, and maintenance orders with DIFFERENT IDs.

The acquisition story:
  A hyperscaler/colo operator acquired a competitor that uses Siemens Desigo CC
  for physical plant management (HVAC, power, cooling, fire suppression) AND has
  its own rack/asset inventory that OVERLAPS with ServiceNow.

Tables generated:
  - facilities          (2,000)  — Siemens sites (Standort/Gebaeude)
  - zones               (20,000) — HVAC/cooling zones per facility
  - power_distribution_units (40,000) — PDUs, UPS, switchgear
  - cooling_loops        (10,000) — Chiller plants, CRAH units
  - fire_suppression     (4,000)  — Fire protection systems
  - rack_inventory      (100,000) — Siemens rack tracking (OVERLAPS ServiceNow)
  - bms_sensors         (500,000) — BMS time-series readings
  - maintenance_orders   (15,000) — Siemens maintenance work orders

Cross-system linkage:
  - facility_id uses uuid5(NAMESPACE_OID, 'siemens_facility_{seed}_{i}')
  - siemens_rack_id uses uuid5(NAMESPACE_OID, 'siemens_rack_{seed}_{i}')
  - ~5% of rack_inventory get servicenow_correlation_id matching ServiceNow's
    rack IDs (uuid5(NAMESPACE_OID, 'rack_{seed}_{correlated_index}'))

Usage:
    python generate_siemens_data.py --output ../data
    python generate_siemens_data.py --output ../data --quick
    python generate_siemens_data.py --output ../data --scale 2.0
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
    'facilities': 2000,
    'zones': 20000,
    'power_distribution_units': 40000,
    'cooling_loops': 10000,
    'fire_suppression': 4000,
    'rack_inventory': 100000,
    'bms_sensors': 500000,
    'maintenance_orders': 15000,
}

# ---------------------------------------------------------------------------
# Global facility locations — 40% EMEA, 30% APAC, 20% Americas, 10% MEA
# ---------------------------------------------------------------------------

EMEA_LOCATIONS = [
    ('Frankfurt', 'DE', 'EMEA'), ('Munich', 'DE', 'EMEA'),
    ('Berlin', 'DE', 'EMEA'), ('Hamburg', 'DE', 'EMEA'),
    ('London', 'GB', 'EMEA'), ('Manchester', 'GB', 'EMEA'),
    ('Amsterdam', 'NL', 'EMEA'), ('Paris', 'FR', 'EMEA'),
    ('Marseille', 'FR', 'EMEA'), ('Dublin', 'IE', 'EMEA'),
    ('Stockholm', 'SE', 'EMEA'), ('Oslo', 'NO', 'EMEA'),
    ('Helsinki', 'FI', 'EMEA'), ('Zurich', 'CH', 'EMEA'),
    ('Milan', 'IT', 'EMEA'), ('Madrid', 'ES', 'EMEA'),
    ('Warsaw', 'PL', 'EMEA'), ('Prague', 'CZ', 'EMEA'),
    ('Vienna', 'AT', 'EMEA'), ('Brussels', 'BE', 'EMEA'),
]

APAC_LOCATIONS = [
    ('Tokyo', 'JP', 'APAC'), ('Osaka', 'JP', 'APAC'),
    ('Singapore', 'SG', 'APAC'), ('Hong Kong', 'HK', 'APAC'),
    ('Sydney', 'AU', 'APAC'), ('Melbourne', 'AU', 'APAC'),
    ('Mumbai', 'IN', 'APAC'), ('Chennai', 'IN', 'APAC'),
    ('Seoul', 'KR', 'APAC'), ('Taipei', 'TW', 'APAC'),
    ('Jakarta', 'ID', 'APAC'), ('Bangkok', 'TH', 'APAC'),
    ('Kuala Lumpur', 'MY', 'APAC'), ('Manila', 'PH', 'APAC'),
    ('Auckland', 'NZ', 'APAC'),
]

AMERICAS_LOCATIONS = [
    ('Ashburn', 'US', 'Americas'), ('Dallas', 'US', 'Americas'),
    ('Chicago', 'US', 'Americas'), ('Phoenix', 'US', 'Americas'),
    ('Santa Clara', 'US', 'Americas'), ('Los Angeles', 'US', 'Americas'),
    ('New York', 'US', 'Americas'), ('Atlanta', 'US', 'Americas'),
    ('Seattle', 'US', 'Americas'), ('Denver', 'US', 'Americas'),
    ('Toronto', 'CA', 'Americas'), ('Montreal', 'CA', 'Americas'),
    ('Sao Paulo', 'BR', 'Americas'), ('Santiago', 'CL', 'Americas'),
    ('Mexico City', 'MX', 'Americas'),
]

MEA_LOCATIONS = [
    ('Dubai', 'AE', 'MEA'), ('Riyadh', 'SA', 'MEA'),
    ('Johannesburg', 'ZA', 'MEA'), ('Cape Town', 'ZA', 'MEA'),
    ('Nairobi', 'KE', 'MEA'), ('Lagos', 'NG', 'MEA'),
    ('Cairo', 'EG', 'MEA'), ('Bahrain', 'BH', 'MEA'),
    ('Muscat', 'OM', 'MEA'), ('Tel Aviv', 'IL', 'MEA'),
]

# Weighted location pools for region distribution
LOCATION_POOLS = [
    (EMEA_LOCATIONS, 0.40),
    (APAC_LOCATIONS, 0.30),
    (AMERICAS_LOCATIONS, 0.20),
    (MEA_LOCATIONS, 0.10),
]

# Gebaeude (building) types — weighted
GEBAEUDE_TYPES = ['COLOCATION', 'ENTERPRISE', 'HYPERSCALE', 'EDGE']
GEBAEUDE_WEIGHTS = [40, 30, 20, 10]

# Zone types
ZONE_TYPES = ['HOT_AISLE', 'COLD_AISLE', 'MIXING', 'CONTAINMENT', 'MECHANICAL']
COOLING_TYPES = ['CRAH', 'CRAC', 'IN_ROW', 'REAR_DOOR', 'FREE_COOLING']

# Power equipment
POWER_EQUIPMENT_TYPES = ['PDU', 'UPS', 'ATS', 'SWITCHGEAR', 'BUSWAY']
SIEMENS_POWER_MODELS = [
    'Siemens SITOP PSU8600', 'Siemens SITOP PSU3800',
    'Siemens SINAMICS S120', 'Siemens SINAMICS G120',
    'Siemens SENTRON ATS', 'Siemens SENTRON 3WL',
    'Siemens SIVACON S8', 'Siemens ALPHA 3200',
]

# Cooling loop types
COOLING_LOOP_TYPES = [
    'PRIMARY_CHILLER', 'SECONDARY_CHILLER', 'CRAH', 'CRAC',
    'COOLING_TOWER', 'FREE_COOLING',
]
REFRIGERANT_TYPES = ['R410A', 'R134a', 'R1234ze']

# Fire suppression
FIRE_SYSTEM_TYPES = [
    'FM200', 'NOVEC_1230', 'PRE_ACTION_SPRINKLER',
    'VESDA_DETECTION', 'INERGEN',
]

# BMS sensor types
SENSOR_TYPES = [
    'TEMPERATURE', 'HUMIDITY', 'POWER', 'WATER_FLOW',
    'AIRFLOW', 'PRESSURE', 'VIBRATION',
]
SENSOR_UNITS = {
    'TEMPERATURE': 'celsius',
    'HUMIDITY': 'percent',
    'POWER': 'kW',
    'WATER_FLOW': 'lpm',
    'AIRFLOW': 'cfm',
    'PRESSURE': 'kPa',
    'VIBRATION': 'mm/s',
}
SENSOR_RANGES = {
    'TEMPERATURE': (15.0, 45.0),
    'HUMIDITY': (20.0, 80.0),
    'POWER': (0.5, 500.0),
    'WATER_FLOW': (10.0, 2000.0),
    'AIRFLOW': (100.0, 5000.0),
    'PRESSURE': (95.0, 110.0),
    'VIBRATION': (0.01, 5.0),
}

QUALITY_STATES = ['GOOD', 'UNCERTAIN', 'BAD']
QUALITY_WEIGHTS = [95, 4, 1]

ALARM_STATES = ['NORMAL', 'WARNING', 'ALARM', 'CRITICAL']
ALARM_WEIGHTS = [96.4, 3.0, 0.5, 0.1]

# Maintenance
MAINTENANCE_ORDER_TYPES = ['PREVENTIVE', 'CORRECTIVE', 'EMERGENCY', 'INSPECTION']
MAINTENANCE_STATUSES = ['OPEN', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED']
MAINTENANCE_STATUS_WEIGHTS = [15, 20, 55, 10]

MAINTENANCE_EQUIPMENT_TYPES = [
    'PDU', 'UPS', 'CHILLER', 'CRAH', 'ATS', 'GENERATOR',
    'FIRE_PANEL', 'BMS_CONTROLLER', 'COOLING_TOWER', 'BUSWAY',
]

MAINTENANCE_TEAMS = [
    'Kuehlung-Team-Alpha', 'Kuehlung-Team-Beta',
    'Elektro-Team-Nord', 'Elektro-Team-Sued',
    'Brandschutz-Team', 'BMS-Wartung',
    'Anlage-Service-A', 'Anlage-Service-B',
    'Gebaeude-Technik', 'Notfall-Einsatz',
]

# Siemens BMS controller models (for naming)
SIEMENS_BMS_MODELS = [
    'Siemens Desigo PXC', 'Siemens Desigo PXM',
    'Siemens Climatix IC', 'Siemens Climatix ECO',
]


# ============================================================================
# SIEMENS DCIM GENERATOR
# ============================================================================

class SiemensDCIMGenerator(SourceSystemGenerator):
    """Generates Siemens Desigo CC / MindSphere DCIM data for an acquired company."""

    SYSTEM_NAME = "SIEMENS_DCIM"

    def __init__(self, seed: int = 42):
        super().__init__(seed)
        self.now = datetime.now()
        # Pre-build the location assignment list for deterministic distribution
        self._location_pool = self._build_location_pool()

    def _build_location_pool(self) -> List[tuple]:
        """Build a large shuffled pool of locations respecting regional weights."""
        pool = []
        pool_size = 10000  # large enough to sample from
        for locations, weight in LOCATION_POOLS:
            n = int(pool_size * weight)
            for _ in range(n):
                pool.append(random.choice(locations))
        random.shuffle(pool)
        return pool

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------
    def _id(self, prefix: str, index: int) -> str:
        return str(uuid.uuid5(uuid.NAMESPACE_OID, f'{prefix}_{self.seed}_{index}'))

    def _hash(self, record: Dict) -> str:
        data = {k: v for k, v in record.items() if not k.startswith('_')}
        return hashlib.sha256(json.dumps(data, sort_keys=True, default=str).encode()).hexdigest()

    def _scd6_current(self, record: Dict, valid_from: datetime) -> Dict:
        """Add SCD6 metadata for a current record."""
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
        """Add SCD6 metadata for a historical record."""
        record['_VALID_FROM'] = valid_from.isoformat()
        record['_VALID_TO'] = valid_to.isoformat()
        record['_IS_CURRENT'] = False
        record['_VERSION'] = version
        record['_SOURCE_SYSTEM'] = self.SYSTEM_NAME
        record['_LOADED_AT'] = self.now.isoformat()
        record['_ROW_HASH'] = self._hash(record)
        return record

    def _get_location(self, index: int) -> tuple:
        """Get a deterministic location from the weighted pool."""
        return self._location_pool[index % len(self._location_pool)]

    # ------------------------------------------------------------------
    # FACILITIES (Standorte / Gebaeude)
    # ------------------------------------------------------------------
    def generate_facilities(self, count: int) -> List[Dict]:
        print(f"  Generating {count} facilities (Standorte)...")
        records = []

        for i in range(count):
            city, country, region = self._get_location(i)
            facility_id = self._id('siemens_facility', i)
            gebaeude_typ = random.choices(GEBAEUDE_TYPES, weights=GEBAEUDE_WEIGHTS)[0]
            tier = random.choices([1, 2, 3, 4], weights=[5, 15, 50, 30])[0]

            # Power varies by type
            power_mw = {
                'HYPERSCALE': round(random.uniform(50, 200), 1),
                'COLOCATION': round(random.uniform(10, 80), 1),
                'ENTERPRISE': round(random.uniform(5, 30), 1),
                'EDGE': round(random.uniform(0.5, 5), 1),
            }[gebaeude_typ]

            cooling_mw = round(power_mw * random.uniform(0.8, 1.2), 1)
            rack_cap = {
                'HYPERSCALE': random.randint(2000, 10000),
                'COLOCATION': random.randint(500, 3000),
                'ENTERPRISE': random.randint(100, 800),
                'EDGE': random.randint(10, 100),
            }[gebaeude_typ]

            commissioning = self.fake.date_between(start_date='-15y', end_date='-6m')
            # Acquisition date: all in 2024-2025 range
            acquisition = self.fake.date_between(
                start_date=date(2024, 1, 1),
                end_date=date(2025, 6, 30),
            )

            standort_name = f"SIE-{country}-{city[:3].upper()}-{i+1:04d}"

            # 8% had name changes (rebrand after acquisition)
            has_rename = random.random() < 0.08
            original_name = f"ACQ-{country}-{city[:3].upper()}-{i+1:04d}" if has_rename else standort_name
            historical_name = original_name if has_rename else standort_name

            record = {
                'facility_id': facility_id,
                'standort_name': standort_name,
                'gebaeude_typ': gebaeude_typ,
                'region': region,
                'country': country,
                'city': city,
                'tier_level': tier,
                'total_power_mw': power_mw,
                'total_cooling_mw': cooling_mw,
                'rack_capacity': rack_cap,
                'commissioning_date': commissioning.isoformat(),
                'acquisition_date': acquisition.isoformat(),
                # SCD6 dimension columns
                'current_standort_name': standort_name,
                'historical_standort_name': historical_name,
                'original_standort_name': original_name,
            }

            valid_from = datetime.combine(commissioning, datetime.min.time())

            if has_rename:
                # Historical record with original name
                rename_date = self.fake.date_between(start_date=acquisition, end_date='today')
                hist = dict(record)
                hist['standort_name'] = original_name
                hist['current_standort_name'] = standort_name
                hist['historical_standort_name'] = original_name
                self._scd6_historical(hist, valid_from, datetime.combine(rename_date, datetime.min.time()), 1)
                records.append(hist)

                record['_VERSION'] = 2
                valid_from = datetime.combine(rename_date, datetime.min.time())

            self._scd6_current(record, valid_from)
            records.append(record)

        self._facilities = [r for r in records if r['_IS_CURRENT']]
        return records

    # ------------------------------------------------------------------
    # ZONES (Kuehlung-Zonen)
    # ------------------------------------------------------------------
    def generate_zones(self, count: int) -> List[Dict]:
        print(f"  Generating {count} zones (Kuehlung-Zonen)...")
        records = []
        facility_ids = [f['facility_id'] for f in self._facilities]

        for i in range(count):
            fac_idx = i % len(facility_ids)
            zone_id = self._id('siemens_zone', i)
            zone_type = random.choice(ZONE_TYPES)
            floor = random.randint(-1, 4)
            area = random.randint(50, 2000)

            record = {
                'zone_id': zone_id,
                'facility_id': facility_ids[fac_idx],
                'zone_name': f"Zone-{zone_type[:4]}-{floor}F-{i % 10 + 1:02d}",
                'zone_type': zone_type,
                'floor_level': floor,
                'area_sqm': area,
                'target_temp_celsius': round(random.uniform(18.0, 27.0), 1),
                'target_humidity_pct': round(random.uniform(40.0, 60.0), 1),
                'max_power_kw': round(area * random.uniform(0.5, 2.0), 1),
                'cooling_type': random.choice(COOLING_TYPES),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_LOADED_AT': self.now.isoformat(),
            }
            record['_ROW_HASH'] = self._hash(record)
            records.append(record)

        self._zones = records
        return records

    # ------------------------------------------------------------------
    # POWER DISTRIBUTION UNITS (Stromverteilung)
    # ------------------------------------------------------------------
    def generate_power_distribution_units(self, count: int) -> List[Dict]:
        print(f"  Generating {count} power distribution units (Stromverteilung)...")
        records = []
        facility_ids = [f['facility_id'] for f in self._facilities]
        zone_ids = [z['zone_id'] for z in self._zones]
        zone_to_fac = {z['zone_id']: z['facility_id'] for z in self._zones}

        for i in range(count):
            zone_idx = i % len(zone_ids)
            zone_id = zone_ids[zone_idx]
            facility_id = zone_to_fac[zone_id]
            pdu_id = self._id('siemens_pdu', i)
            equip_type = random.choice(POWER_EQUIPMENT_TYPES)
            model = random.choice(SIEMENS_POWER_MODELS)

            capacity_kva = random.choice([10, 20, 30, 50, 100, 200, 500, 1000])
            voltage = random.choice([208, 230, 400, 480])
            install_date = self.fake.date_between(start_date='-12y', end_date='-3m')
            last_maint = self.fake.date_between(start_date=install_date, end_date='today')

            record = {
                'pdu_id': pdu_id,
                'facility_id': facility_id,
                'zone_id': zone_id,
                'equipment_type': equip_type,
                'model': model,
                'capacity_kva': capacity_kva,
                'current_load_pct': round(random.uniform(20.0, 95.0), 1),
                'redundancy': random.choice(['N', 'N+1', '2N']),
                'phase': random.choice(['SINGLE', 'THREE']),
                'voltage': voltage,
                'install_date': install_date.isoformat(),
                'last_maintenance_date': last_maint.isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_LOADED_AT': self.now.isoformat(),
            }
            record['_ROW_HASH'] = self._hash(record)
            records.append(record)

        self._pdus = records
        return records

    # ------------------------------------------------------------------
    # COOLING LOOPS (Kuehlung-Kreislauf)
    # ------------------------------------------------------------------
    def generate_cooling_loops(self, count: int) -> List[Dict]:
        print(f"  Generating {count} cooling loops (Kuehlung-Kreislauf)...")
        records = []
        facility_ids = [f['facility_id'] for f in self._facilities]
        zone_ids = [z['zone_id'] for z in self._zones]
        zone_to_fac = {z['zone_id']: z['facility_id'] for z in self._zones}

        for i in range(count):
            zone_idx = i % len(zone_ids)
            zone_id = zone_ids[zone_idx]
            facility_id = zone_to_fac[zone_id]
            loop_id = self._id('siemens_cooling', i)
            loop_type = random.choice(COOLING_LOOP_TYPES)

            supply_temp = round(random.uniform(5.0, 15.0), 1)
            return_temp = round(supply_temp + random.uniform(5.0, 15.0), 1)

            record = {
                'loop_id': loop_id,
                'facility_id': facility_id,
                'zone_id': zone_id,
                'loop_type': loop_type,
                'capacity_kw': round(random.uniform(50, 2000), 1),
                'supply_temp_celsius': supply_temp,
                'return_temp_celsius': return_temp,
                'flow_rate_lpm': round(random.uniform(100, 5000), 1),
                'efficiency_cop': round(random.uniform(3.0, 6.0), 2),
                'refrigerant_type': random.choice(REFRIGERANT_TYPES),
                'last_service_date': self.fake.date_between(start_date='-2y', end_date='today').isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_LOADED_AT': self.now.isoformat(),
            }
            record['_ROW_HASH'] = self._hash(record)
            records.append(record)

        self._cooling_loops = records
        return records

    # ------------------------------------------------------------------
    # FIRE SUPPRESSION (Brandschutz)
    # ------------------------------------------------------------------
    def generate_fire_suppression(self, count: int) -> List[Dict]:
        print(f"  Generating {count} fire suppression systems (Brandschutz)...")
        records = []
        facility_ids = [f['facility_id'] for f in self._facilities]
        zone_ids = [z['zone_id'] for z in self._zones]
        zone_to_fac = {z['zone_id']: z['facility_id'] for z in self._zones}

        for i in range(count):
            zone_idx = i % len(zone_ids)
            zone_id = zone_ids[zone_idx]
            facility_id = zone_to_fac[zone_id]
            system_id = self._id('siemens_fire', i)
            system_type = random.choice(FIRE_SYSTEM_TYPES)

            last_inspection = self.fake.date_between(start_date='-1y', end_date='today')
            next_inspection = last_inspection + timedelta(days=random.choice([90, 180, 365]))

            # VESDA is detection-only, no cylinders
            is_detection_only = system_type == 'VESDA_DETECTION'

            record = {
                'system_id': system_id,
                'facility_id': facility_id,
                'zone_id': zone_id,
                'system_type': system_type,
                'coverage_area_sqm': random.randint(100, 5000),
                'last_inspection_date': last_inspection.isoformat(),
                'next_inspection_date': next_inspection.isoformat(),
                'cylinder_pressure_bar': None if is_detection_only else round(random.uniform(20.0, 60.0), 1),
                'agent_quantity_kg': None if is_detection_only else round(random.uniform(10.0, 500.0), 1),
                'is_compliant': random.random() > 0.03,  # ~97% compliant
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_LOADED_AT': self.now.isoformat(),
            }
            record['_ROW_HASH'] = self._hash(record)
            records.append(record)

        self._fire_suppression = records
        return records

    # ------------------------------------------------------------------
    # RACK INVENTORY (Schrank-Inventar) — OVERLAPS ServiceNow
    # ------------------------------------------------------------------
    def generate_rack_inventory(self, count: int) -> List[Dict]:
        print(f"  Generating {count} rack inventory (Schrank-Inventar)...")
        records = []
        facility_ids = [f['facility_id'] for f in self._facilities]
        zone_ids = [z['zone_id'] for z in self._zones]
        zone_to_fac = {z['zone_id']: z['facility_id'] for z in self._zones}

        # Customer names for colo racks
        customer_pool = [
            'GlobalTech Corp', 'NeuralNet AI', 'CloudScale Inc',
            'DataStream Ltd', 'QuantumBit GmbH', 'CyberShield SA',
            'MegaByte Holdings', 'PixelForge Studios', 'AgriData Systems',
            'HealthCloud EU', 'FinServ Digital', 'EduTech Alliance',
            'GreenEnergy Analytics', 'RetailPulse', 'LogiChain Global',
            'AutoDrive Technologies', 'SpaceNet Communications', 'BioGenix',
            'SmartCity Solutions', 'AeroData Corp',
        ]

        # Correlation: ~5% get a servicenow_correlation_id
        correlation_pct = 0.05

        change_pct = 0.04  # 4% have customer changes

        for i in range(count):
            zone_idx = i % len(zone_ids)
            zone_id = zone_ids[zone_idx]
            facility_id = zone_to_fac[zone_id]
            siemens_rack_id = self._id('siemens_rack', i)
            u_cap = random.choice([42, 48])
            u_used = random.randint(0, u_cap)
            power_kw = round(random.uniform(5, 30), 1)
            weight_cap = random.choice([1000, 1200, 1500, 2000])
            customer = random.choice(customer_pool) if random.random() > 0.2 else None

            has_change = random.random() < change_pct and customer is not None
            original_customer = random.choice(customer_pool) if has_change else customer

            # Entity resolution hook: ~5% get correlated to ServiceNow rack IDs
            sn_correlation = None
            if random.random() < correlation_pct:
                # Match ServiceNow generator's pattern: uuid5(NAMESPACE_OID, 'rack_{seed}_{i}')
                correlated_idx = random.randint(0, 1999)  # ServiceNow has 2000 racks
                sn_correlation = str(uuid.uuid5(uuid.NAMESPACE_OID, f'rack_{self.seed}_{correlated_idx}'))

            install_date = self.fake.date_between(start_date='-10y', end_date='-3m')

            record = {
                'siemens_rack_id': siemens_rack_id,
                'facility_id': facility_id,
                'zone_id': zone_id,
                'row_number': f"Reihe-{chr(65 + (i % 26))}",
                'position_in_row': (i % 30) + 1,
                'u_capacity': u_cap,
                'u_used': u_used,
                'power_allocation_kw': power_kw,
                'weight_capacity_kg': weight_cap,
                'current_weight_kg': round(weight_cap * random.uniform(0.1, 0.9), 1),
                'customer_name': customer,
                'contract_id': f"SIE-CTR-{random.randint(100000, 999999)}" if customer else None,
                'servicenow_correlation_id': sn_correlation,
                # SCD6
                'current_customer_name': customer,
                'historical_customer_name': customer if not has_change else original_customer,
                'original_customer_name': original_customer,
            }

            valid_from = datetime.combine(install_date, datetime.min.time())

            if has_change:
                change_date = self.fake.date_between(start_date=install_date, end_date='today')
                hist = dict(record)
                hist['customer_name'] = original_customer
                hist['current_customer_name'] = customer
                hist['historical_customer_name'] = original_customer
                self._scd6_historical(hist, valid_from, datetime.combine(change_date, datetime.min.time()), 1)
                records.append(hist)

                record['_VERSION'] = 2
                valid_from = datetime.combine(change_date, datetime.min.time())

            self._scd6_current(record, valid_from)
            records.append(record)

        self._rack_inventory = [r for r in records if r['_IS_CURRENT']]
        return records

    # ------------------------------------------------------------------
    # BMS SENSORS (Gebaeudeautomation-Sensoren)
    # ------------------------------------------------------------------
    def generate_bms_sensors(self, count: int) -> List[Dict]:
        print(f"  Generating {count} BMS sensor readings (Gebaeudeautomation)...")
        records = []
        facility_ids = [f['facility_id'] for f in self._facilities]
        zone_ids = [z['zone_id'] for z in self._zones]
        zone_to_fac = {z['zone_id']: z['facility_id'] for z in self._zones}

        # Pre-create a pool of sensor IDs (roughly 10 sensors per zone)
        num_sensors = len(zone_ids) * 10
        sensor_pool = []
        for s in range(num_sensors):
            z_idx = s // 10
            if z_idx < len(zone_ids):
                sensor_pool.append({
                    'sensor_id': self._id('siemens_sensor', s),
                    'zone_id': zone_ids[z_idx],
                    'facility_id': zone_to_fac[zone_ids[z_idx]],
                    'sensor_type': SENSOR_TYPES[s % len(SENSOR_TYPES)],
                })

        # Generate readings distributed across sensors
        base_time = self.now - timedelta(hours=24)

        for i in range(count):
            sensor = sensor_pool[i % len(sensor_pool)]
            sensor_type = sensor['sensor_type']
            val_range = SENSOR_RANGES[sensor_type]

            # Timestamp spread over last 24 hours
            ts = base_time + timedelta(seconds=random.randint(0, 86400))

            quality = random.choices(QUALITY_STATES, weights=QUALITY_WEIGHTS)[0]
            alarm = random.choices(ALARM_STATES, weights=ALARM_WEIGHTS)[0]

            # Adjust value for alarm states
            value = round(random.uniform(val_range[0], val_range[1]), 2)
            if alarm == 'WARNING':
                value = round(val_range[1] * random.uniform(0.9, 1.05), 2)
            elif alarm == 'ALARM':
                value = round(val_range[1] * random.uniform(1.05, 1.2), 2)
            elif alarm == 'CRITICAL':
                value = round(val_range[1] * random.uniform(1.2, 1.5), 2)

            record = {
                'reading_id': self._id('siemens_reading', i),
                'sensor_id': sensor['sensor_id'],
                'facility_id': sensor['facility_id'],
                'zone_id': sensor['zone_id'],
                'timestamp': ts.isoformat(),
                'sensor_type': sensor_type,
                'value': value,
                'unit': SENSOR_UNITS[sensor_type],
                'quality': quality,
                'alarm_state': alarm,
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_LOADED_AT': self.now.isoformat(),
            }
            record['_ROW_HASH'] = self._hash(record)
            records.append(record)

        return records

    # ------------------------------------------------------------------
    # MAINTENANCE ORDERS (Wartungsauftraege)
    # ------------------------------------------------------------------
    def generate_maintenance_orders(self, count: int) -> List[Dict]:
        print(f"  Generating {count} maintenance orders (Wartungsauftraege)...")
        records = []
        facility_ids = [f['facility_id'] for f in self._facilities]
        zone_ids = [z['zone_id'] for z in self._zones]
        zone_to_fac = {z['zone_id']: z['facility_id'] for z in self._zones}

        descriptions_by_type = {
            'PREVENTIVE': [
                'Scheduled filter replacement on {equip}',
                'Quarterly inspection of {equip} per Siemens SOP',
                'Firmware update for {equip} controller',
                'Calibration of sensors on {equip}',
                'Belt and bearing inspection on {equip}',
            ],
            'CORRECTIVE': [
                'Repair failed compressor on {equip}',
                'Replace faulty relay in {equip}',
                'Fix communication fault on {equip} BACnet interface',
                'Address refrigerant leak in {equip}',
                'Repair damaged power cable on {equip}',
            ],
            'EMERGENCY': [
                'CRITICAL: {equip} total failure — immediate response',
                'EMERGENCY: Water leak detected near {equip}',
                'URGENT: {equip} overtemperature shutdown',
                'CRITICAL: {equip} phase imbalance alarm',
            ],
            'INSPECTION': [
                'Annual compliance inspection of {equip}',
                'Insurance audit of {equip} installation',
                'Post-acquisition review of {equip} documentation',
                'Siemens OEM certification check for {equip}',
            ],
        }

        for i in range(count):
            zone_idx = i % len(zone_ids)
            zone_id = zone_ids[zone_idx]
            facility_id = zone_to_fac[zone_id]
            order_id = self._id('siemens_maint', i)

            order_type = random.choice(MAINTENANCE_ORDER_TYPES)
            equip_type = random.choice(MAINTENANCE_EQUIPMENT_TYPES)
            equip_id = self._id(f'siemens_{equip_type.lower()}', random.randint(0, 9999))
            priority = random.randint(1, 4)
            status = random.choices(MAINTENANCE_STATUSES, weights=MAINTENANCE_STATUS_WEIGHTS)[0]

            created_at = self.fake.date_time_between(start_date='-180d', end_date='now')
            scheduled = created_at + timedelta(days=random.randint(0, 30))

            completed_at = None
            resolution_hours = None
            if status == 'COMPLETED':
                resolution_hours = round(random.uniform(0.5, 120.0), 1)
                completed_at = created_at + timedelta(hours=resolution_hours)
            elif status == 'CANCELLED':
                completed_at = created_at + timedelta(days=random.randint(1, 7))

            desc_templates = descriptions_by_type[order_type]
            description = random.choice(desc_templates).format(equip=equip_type)

            record = {
                'order_id': order_id,
                'facility_id': facility_id,
                'zone_id': zone_id,
                'equipment_type': equip_type,
                'equipment_id': equip_id,
                'order_type': order_type,
                'priority': priority,
                'description': description,
                'assigned_team': random.choice(MAINTENANCE_TEAMS),
                'status': status,
                'created_at': created_at.isoformat(),
                'scheduled_date': scheduled.isoformat(),
                'completed_at': completed_at.isoformat() if completed_at else None,
                'resolution_hours': resolution_hours,
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
        # Stage 1: Facility hierarchy
        data['facilities'] = self.generate_facilities(counts.get('facilities', 2000))
        data['zones'] = self.generate_zones(counts.get('zones', 20000))

        # Stage 2: Physical plant systems
        data['power_distribution_units'] = self.generate_power_distribution_units(
            counts.get('power_distribution_units', 40000))
        data['cooling_loops'] = self.generate_cooling_loops(
            counts.get('cooling_loops', 10000))
        data['fire_suppression'] = self.generate_fire_suppression(
            counts.get('fire_suppression', 4000))

        # Stage 3: Rack inventory (entity resolution target)
        data['rack_inventory'] = self.generate_rack_inventory(
            counts.get('rack_inventory', 100000))

        # Stage 4: Time-series and operations
        data['bms_sensors'] = self.generate_bms_sensors(
            counts.get('bms_sensors', 500000))
        data['maintenance_orders'] = self.generate_maintenance_orders(
            counts.get('maintenance_orders', 15000))

        return data


# ============================================================================
# OUTPUT
# ============================================================================

def save_to_csv(data: Dict[str, List[Dict]], output_dir: str):
    """Save using the base data_generator's save_to_csv."""
    base_save_to_csv(data, output_dir, "siemens_dcim")


# ============================================================================
# CLI
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Generate Siemens Desigo CC / MindSphere DCIM data for Snowflake DCA demo",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python generate_siemens_data.py --output ../data
  python generate_siemens_data.py --output ../data --quick
  python generate_siemens_data.py --output ../data --scale 2.0
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
    print("SIEMENS DESIGO CC / MINDSPHERE DCIM DATA GENERATOR")
    print("=" * 60)
    print(f"  Seed:   {args.seed}")
    print(f"  Scale:  {'quick (10%)' if args.quick else f'{args.scale}x'}")
    print(f"  Output: {args.output}")
    print(f"  Counts: {counts}")
    print()

    generator = SiemensDCIMGenerator(seed=args.seed)
    data = generator.generate(counts)

    print()
    print("=" * 60)
    print("GENERATION COMPLETE")
    print("=" * 60)
    for table, recs in data.items():
        print(f"  {table:30s} {len(recs):>10,} records")

    print()
    save_to_csv(data, args.output)
    print("\nDone!")


if __name__ == "__main__":
    main()
