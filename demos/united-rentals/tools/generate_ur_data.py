#!/usr/bin/env python3
"""
United Rentals Equipment Rental Data Generator

Generates realistic synthetic data for the United Rentals DCA demo:
  - branches: 100 branch/yard locations across the US with real coordinates
  - equipment: 5,000 fleet assets with geospatial coordinates
  - customers: 1,000 customer accounts
  - rental_contracts: 10,000 rental transactions
  - maintenance_records: 3,000 maintenance events
  - telematics: 20,000 IoT/GPS readings

Usage:
    python generate_ur_data.py --output ../data
    python generate_ur_data.py --output ../data --quick       # Small test set
    python generate_ur_data.py --output ../data --scale 2.0   # Double size
"""

import os
import sys
import random
import hashlib
import json
import csv
import argparse
from datetime import datetime, timedelta, date
from typing import List, Dict, Any

try:
    from faker import Faker
except ImportError:
    print("ERROR: Faker not installed. Run: pip install faker")
    sys.exit(1)


# ============================================================================
# REFERENCE DATA
# ============================================================================

# US metro areas with real coordinates — branches spread across UR's footprint
METROS = [
    # (city, state, lat, lon, region)
    # Northeast
    ("New York", "NY", 40.7128, -74.0060, "NORTHEAST"),
    ("Boston", "MA", 42.3601, -71.0589, "NORTHEAST"),
    ("Philadelphia", "PA", 39.9526, -75.1652, "NORTHEAST"),
    ("Pittsburgh", "PA", 40.4406, -79.9959, "NORTHEAST"),
    ("Hartford", "CT", 41.7658, -72.6734, "NORTHEAST"),
    ("Baltimore", "MD", 39.2904, -76.6122, "NORTHEAST"),
    ("Newark", "NJ", 40.7357, -74.1724, "NORTHEAST"),
    # Southeast
    ("Atlanta", "GA", 33.7490, -84.3880, "SOUTHEAST"),
    ("Charlotte", "NC", 35.2271, -80.8431, "SOUTHEAST"),
    ("Miami", "FL", 25.7617, -80.1918, "SOUTHEAST"),
    ("Tampa", "FL", 27.9506, -82.4572, "SOUTHEAST"),
    ("Nashville", "TN", 36.1627, -86.7816, "SOUTHEAST"),
    ("Raleigh", "NC", 35.7796, -78.6382, "SOUTHEAST"),
    ("Jacksonville", "FL", 30.3322, -81.6557, "SOUTHEAST"),
    ("Richmond", "VA", 37.5407, -77.4360, "SOUTHEAST"),
    # Midwest
    ("Chicago", "IL", 41.8781, -87.6298, "MIDWEST"),
    ("Detroit", "MI", 42.3314, -83.0458, "MIDWEST"),
    ("Columbus", "OH", 39.9612, -82.9988, "MIDWEST"),
    ("Indianapolis", "IN", 39.7684, -86.1581, "MIDWEST"),
    ("Minneapolis", "MN", 44.9778, -93.2650, "MIDWEST"),
    ("Kansas City", "MO", 39.0997, -94.5786, "MIDWEST"),
    ("St. Louis", "MO", 38.6270, -90.1994, "MIDWEST"),
    ("Cincinnati", "OH", 39.1031, -84.5120, "MIDWEST"),
    # Southwest
    ("Dallas", "TX", 32.7767, -96.7970, "SOUTHWEST"),
    ("Houston", "TX", 29.7604, -95.3698, "SOUTHWEST"),
    ("San Antonio", "TX", 29.4241, -98.4936, "SOUTHWEST"),
    ("Austin", "TX", 30.2672, -97.7431, "SOUTHWEST"),
    ("Phoenix", "AZ", 33.4484, -112.0740, "SOUTHWEST"),
    ("Tulsa", "OK", 36.1540, -95.9928, "SOUTHWEST"),
    ("El Paso", "TX", 31.7619, -106.4850, "SOUTHWEST"),
    # West
    ("Los Angeles", "CA", 34.0522, -118.2437, "WEST"),
    ("San Francisco", "CA", 37.7749, -122.4194, "WEST"),
    ("Denver", "CO", 39.7392, -104.9903, "WEST"),
    ("Seattle", "WA", 47.6062, -122.3321, "WEST"),
    ("Portland", "OR", 45.5155, -122.6789, "WEST"),
    ("Las Vegas", "NV", 36.1699, -115.1398, "WEST"),
    ("Salt Lake City", "UT", 40.7608, -111.8910, "WEST"),
    ("Sacramento", "CA", 38.5816, -121.4944, "WEST"),
    ("San Diego", "CA", 32.7157, -117.1611, "WEST"),
]

# Equipment catalog: category -> list of (make, model, description, base_daily_rate)
EQUIPMENT_CATALOG = {
    "Aerial": [
        ("JLG", "460SJ", "Boom Lift 46ft Straight", 350),
        ("JLG", "600S", "Boom Lift 60ft Straight", 500),
        ("JLG", "800S", "Boom Lift 80ft Straight", 700),
        ("Genie", "GS-1930", "Scissor Lift 19ft Electric", 125),
        ("Genie", "GS-2632", "Scissor Lift 26ft Electric", 150),
        ("Genie", "GS-3246", "Scissor Lift 32ft Electric", 200),
        ("Skyjack", "SJ6826RT", "Scissor Lift 26ft Rough Terrain", 250),
        ("JLG", "G10-55A", "Telehandler 10K 55ft", 450),
        ("Genie", "GTH-636", "Telehandler 6K 36ft", 350),
        ("Haulotte", "HA20LE", "Articulating Boom 66ft Electric", 550),
    ],
    "Earthmoving": [
        ("Kubota", "KX040", "Mini Excavator 4T", 300),
        ("Cat", "314", "Excavator 14T", 600),
        ("Cat", "330", "Excavator 30T", 900),
        ("Bobcat", "S650", "Skid Steer Loader", 275),
        ("Bobcat", "T770", "Compact Track Loader", 350),
        ("Case", "580SN", "Backhoe Loader", 400),
        ("Cat", "926M", "Wheel Loader", 500),
        ("John Deere", "450K", "Crawler Dozer", 550),
    ],
    "Material Handling": [
        ("Toyota", "8FGU25", "Forklift 5K Cushion", 150),
        ("Hyster", "H80FT", "Forklift 8K Pneumatic", 200),
        ("Yale", "GDP120", "Forklift 12K Diesel", 275),
        ("Cat", "TH255C", "Rough Terrain Forklift", 350),
        ("Tadano", "GR-300XL", "Rough Terrain Crane 30T", 1200),
        ("Liebherr", "LTM 1050", "All Terrain Crane 50T", 1800),
    ],
    "General Tools": [
        ("Atlas Copco", "XAS 185", "Air Compressor 185 CFM", 175),
        ("Atlas Copco", "XAS 375", "Air Compressor 375 CFM", 275),
        ("Lincoln", "Vantage 300", "Welder Generator 300A", 150),
        ("Miller", "Big Blue 500", "Welder Generator 500A", 200),
        ("Generac", "MLT6S", "Light Tower 6kW", 100),
        ("Wacker Neuson", "PT3A", "Trash Pump 3in", 125),
        ("Multiquip", "QP-6TZ", "Trash Pump 6in", 175),
        ("Landa", "PGHW", "Hot Water Pressure Washer", 150),
    ],
    "Power & HVAC": [
        ("Cat", "DE22", "Generator 20kW Diesel", 200),
        ("Cummins", "C60", "Generator 60kW Diesel", 400),
        ("Cat", "XQ100", "Generator 100kW Diesel", 600),
        ("Cummins", "C200", "Generator 200kW Diesel", 900),
        ("Carrier", "30RB", "Air-Cooled Chiller 5T", 250),
        ("Flagro", "FVO-400", "Indirect Fired Heater 400K BTU", 125),
        ("Marley", "NC Series", "Cooling Tower", 350),
    ],
    "Trench Safety": [
        ("Efficiency", "Steel Box 8x16", "Trench Box 8ft", 125),
        ("Speed Shore", "8x20 Box", "Trench Box 12ft", 175),
        ("Pro-Tec", "Hydraulic", "Hydraulic Shoring System", 200),
        ("GME", "SR Series", "Slide Rail System", 300),
        ("Kundel", "V-Panel", "Manhole Box", 150),
        ("Checkers", "RP5x8", "Road Plate 5x8ft", 50),
    ],
}

CATEGORY_WEIGHTS = {"Aerial": 0.30, "Earthmoving": 0.20, "Material Handling": 0.15,
                    "General Tools": 0.15, "Power & HVAC": 0.12, "Trench Safety": 0.08}

STATUS_WEIGHTS = {"AVAILABLE": 0.35, "RENTED": 0.45, "MAINTENANCE": 0.12,
                  "TRANSPORT": 0.05, "DECOMMISSIONED": 0.03}

CONDITION_WEIGHTS = {"EXCELLENT": 0.20, "GOOD": 0.45, "FAIR": 0.25, "POOR": 0.10}

CUSTOMER_TYPES = ["Construction", "Industrial", "Infrastructure", "Residential",
                  "Government", "Utility", "Oil & Gas", "Mining", "Events"]

BRANCH_TYPES = ["BRANCH", "SPECIALTY", "TOOL_RENTAL", "POWER_AND_HVAC", "TRENCH_SAFETY"]

MAINTENANCE_TYPES = ["PREVENTIVE", "CORRECTIVE", "INSPECTION", "EMERGENCY"]

FAULT_CODES = [
    ("E001", "Low oil pressure"), ("E002", "High coolant temperature"),
    ("E003", "Battery voltage low"), ("E004", "Hydraulic pressure warning"),
    ("E005", "Air filter restricted"), ("E006", "Fuel filter clogged"),
    ("E007", "Engine RPM out of range"), ("E008", "Transmission fault"),
    ("E009", "Boom sensor malfunction"), ("E010", "Safety interlock triggered"),
] + [(None, None)] * 20  # ~67% chance of no fault

DEFAULT_COUNTS = {
    "branches": 100, "equipment": 5000, "customers": 1000,
    "rental_contracts": 10000, "maintenance_records": 3000, "telematics": 20000,
}


# ============================================================================
# GENERATOR
# ============================================================================

class UnitedRentalsGenerator:
    """Generates synthetic equipment rental data with geospatial coordinates."""

    SYSTEM_NAME = "UNITED_RENTALS"

    def __init__(self, seed: int = 42):
        self.seed = seed
        random.seed(seed)
        self.fake = Faker('en_US')
        self.fake.seed_instance(seed)
        self.branches: List[Dict] = []
        self.equipment: List[Dict] = []
        self.customers: List[Dict] = []

    def _metadata(self, source_table: str) -> Dict[str, Any]:
        return {
            '_SOURCE_TABLE': source_table,
            '_ROW_HASH': None,
            '_LOADED_AT': datetime.now().isoformat(),
            '_SOURCE_SYSTEM': self.SYSTEM_NAME,
            '_IS_CURRENT': True,
            '_VALID_FROM': datetime.now().isoformat(),
            '_VALID_TO': '9999-12-31T00:00:00',
        }

    def _hash(self, record: Dict) -> str:
        data = {k: v for k, v in record.items() if not k.startswith('_')}
        return hashlib.sha256(json.dumps(data, sort_keys=True, default=str).encode()).hexdigest()

    def _jitter(self, value: float, max_offset: float = 0.05) -> float:
        return value + random.uniform(-max_offset, max_offset)

    def _weighted_choice(self, weights: Dict[str, float]) -> str:
        items = list(weights.keys())
        probs = list(weights.values())
        return random.choices(items, weights=probs, k=1)[0]

    # ------------------------------------------------------------------
    # BRANCHES
    # ------------------------------------------------------------------
    def generate_branches(self, count: int) -> List[Dict]:
        print(f"  Generating {count} branches...")
        records = []
        branches_per_metro = max(1, count // len(METROS))
        remaining = count - (branches_per_metro * len(METROS))

        branch_id = 1000
        for metro_idx, (city, state, lat, lon, region) in enumerate(METROS):
            n = branches_per_metro + (1 if metro_idx < remaining else 0)
            for j in range(n):
                if len(records) >= count:
                    break
                branch_id += 1
                btype = BRANCH_TYPES[j % len(BRANCH_TYPES)] if j > 0 else "BRANCH"
                suffix_map = {"BRANCH": "", "SPECIALTY": " Specialty", "TOOL_RENTAL": " Tool Rental",
                              "POWER_AND_HVAC": " Power & HVAC", "TRENCH_SAFETY": " Trench Safety"}
                suffix = suffix_map.get(btype, "")
                name = f"{city}{suffix} #{j + 1}" if n > 1 else f"{city}{suffix}"

                rec = {
                    'BRANCH_ID': f"BR-{branch_id:05d}",
                    'BRANCH_NAME': f"United Rentals - {name}",
                    'BRANCH_TYPE': btype,
                    'ADDRESS': self.fake.street_address(),
                    'CITY': city,
                    'STATE': state,
                    'ZIP_CODE': self.fake.zipcode(),
                    'LATITUDE': round(self._jitter(lat, 0.03 if j > 0 else 0.01), 6),
                    'LONGITUDE': round(self._jitter(lon, 0.03 if j > 0 else 0.01), 6),
                    'REGION': region,
                    'DISTRICT': f"{state}-{region[:3]}",
                    'PHONE': self.fake.phone_number(),
                    'MANAGER_NAME': self.fake.name(),
                    'OPEN_DATE': self.fake.date_between(start_date='-20y', end_date='-1y').isoformat(),
                    'EMPLOYEE_COUNT': random.randint(8, 45),
                    'IS_ACTIVE': True,
                }
                rec.update(self._metadata('UR_BRANCHES'))
                rec['_ROW_HASH'] = self._hash(rec)
                records.append(rec)

        self.branches = records
        return records

    # ------------------------------------------------------------------
    # EQUIPMENT
    # ------------------------------------------------------------------
    def generate_equipment(self, count: int) -> List[Dict]:
        if not self.branches:
            raise ValueError("Must generate branches first")
        print(f"  Generating {count} equipment records...")
        records = []

        for i in range(count):
            category = self._weighted_choice(CATEGORY_WEIGHTS)
            make, model, desc, base_daily = random.choice(EQUIPMENT_CATALOG[category])
            branch = random.choice(self.branches)
            status = self._weighted_choice(STATUS_WEIGHTS)
            condition = self._weighted_choice(CONDITION_WEIGHTS)

            if status in ("RENTED", "TRANSPORT"):
                equip_lat = self._jitter(branch['LATITUDE'], 0.15)
                equip_lon = self._jitter(branch['LONGITUDE'], 0.15)
            else:
                equip_lat = self._jitter(branch['LATITUDE'], 0.005)
                equip_lon = self._jitter(branch['LONGITUDE'], 0.005)

            year = random.randint(2015, 2024)
            acq_date = self.fake.date_between(
                start_date=date(year, 1, 1),
                end_date=date(min(year + 1, 2024), 12, 31)
            )
            rate_factor = random.uniform(0.85, 1.15)
            daily = round(base_daily * rate_factor, 2)
            weekly = round(daily * 3, 2)
            monthly = round(daily * 9, 2)
            hour_meter = random.randint(500, 15000) if category != "Trench Safety" else 0
            cat_key = category.upper().replace(' ', '_').replace('&', 'AND')

            rec = {
                'EQUIPMENT_ID': f"EQ-{10000 + i:06d}",
                'SERIAL_NUMBER': f"{make[:3].upper()}{random.randint(100000, 999999)}{chr(random.randint(65, 90))}",
                'MAKE': make,
                'MODEL': model,
                'CATEGORY': cat_key,
                'SUBCATEGORY': desc.split(' ')[0] if ' ' in desc else category,
                'DESCRIPTION': desc,
                'YEAR_MANUFACTURED': year,
                'ACQUISITION_DATE': acq_date.isoformat(),
                'ACQUISITION_COST': round(base_daily * random.randint(200, 400), 2),
                'REPLACEMENT_COST': round(base_daily * random.randint(250, 500), 2),
                'BRANCH_ID': branch['BRANCH_ID'],
                'STATUS': status,
                'CONDITION': condition,
                'LATITUDE': round(equip_lat, 6),
                'LONGITUDE': round(equip_lon, 6),
                'LAST_SERVICE_DATE': self.fake.date_between(start_date='-6m', end_date='today').isoformat(),
                'NEXT_SERVICE_DUE': self.fake.date_between(start_date='today', end_date='+6m').isoformat(),
                'HOUR_METER_READING': hour_meter,
                'DAILY_RATE': daily,
                'WEEKLY_RATE': weekly,
                'MONTHLY_RATE': monthly,
            }
            rec.update(self._metadata('UR_EQUIPMENT'))
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        self.equipment = records
        return records

    # ------------------------------------------------------------------
    # CUSTOMERS
    # ------------------------------------------------------------------
    def generate_customers(self, count: int) -> List[Dict]:
        print(f"  Generating {count} customers...")
        records = []

        for i in range(count):
            metro = random.choice(METROS)
            cust_type = random.choice(CUSTOMER_TYPES)

            if cust_type in ("Construction", "Infrastructure"):
                company = f"{self.fake.last_name()} {random.choice(['Construction', 'Builders', 'Contracting', 'Development', 'Engineering'])}"
            elif cust_type == "Government":
                company = f"{metro[0]} {random.choice(['County', 'City of', 'Water District', 'School District', 'Parks Dept'])}"
            elif cust_type == "Utility":
                company = f"{metro[1]} {random.choice(['Electric', 'Power', 'Gas', 'Water', 'Energy'])} Co"
            elif cust_type == "Oil & Gas":
                company = f"{self.fake.last_name()} {random.choice(['Energy', 'Petroleum', 'Drilling', 'Pipeline'])}"
            else:
                company = self.fake.company()

            credit = random.choices(['A', 'B', 'C', 'D'], weights=[0.3, 0.4, 0.2, 0.1])[0]
            credit_limits = {'A': (100000, 500000), 'B': (50000, 200000), 'C': (10000, 100000), 'D': (5000, 25000)}
            cl_min, cl_max = credit_limits[credit]
            cust_key = cust_type.upper().replace(' ', '_').replace('&', 'AND')

            rec = {
                'CUSTOMER_ID': f"CU-{20000 + i:06d}",
                'COMPANY_NAME': company,
                'CONTACT_FIRST_NAME': self.fake.first_name(),
                'CONTACT_LAST_NAME': self.fake.last_name(),
                'EMAIL': self.fake.company_email(),
                'PHONE': self.fake.phone_number(),
                'ADDRESS': self.fake.street_address(),
                'CITY': metro[0],
                'STATE': metro[1],
                'ZIP_CODE': self.fake.zipcode(),
                'LATITUDE': round(self._jitter(metro[2], 0.08), 6),
                'LONGITUDE': round(self._jitter(metro[3], 0.08), 6),
                'CUSTOMER_TYPE': cust_key,
                'CREDIT_RATING': credit,
                'ACCOUNT_STATUS': random.choices(['ACTIVE', 'INACTIVE', 'SUSPENDED'], weights=[0.85, 0.10, 0.05])[0],
                'CREDIT_LIMIT': round(random.uniform(cl_min, cl_max), 2),
                'YTD_REVENUE': round(random.uniform(5000, 500000), 2),
            }
            rec.update(self._metadata('UR_CUSTOMERS'))
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        self.customers = records
        return records

    # ------------------------------------------------------------------
    # RENTAL CONTRACTS
    # ------------------------------------------------------------------
    def generate_rental_contracts(self, count: int) -> List[Dict]:
        if not self.equipment or not self.customers:
            raise ValueError("Must generate equipment and customers first")
        print(f"  Generating {count} rental contracts...")
        records = []
        active_customers = [c for c in self.customers if c['ACCOUNT_STATUS'] == 'ACTIVE'] or self.customers

        for i in range(count):
            equip = random.choice(self.equipment)
            cust = random.choice(active_customers)
            start = self.fake.date_between(start_date='-2y', end_date='today')
            duration = random.choices(
                [random.randint(1, 7), random.randint(7, 30), random.randint(30, 180)],
                weights=[0.4, 0.4, 0.2]
            )[0]
            end = start + timedelta(days=duration)

            if duration <= 7:
                total = equip['DAILY_RATE'] * duration
            elif duration <= 30:
                total = equip['WEEKLY_RATE'] * max(1, duration // 7)
            else:
                total = equip['MONTHLY_RATE'] * max(1, duration // 30)

            if end < date.today():
                status = random.choices(['COMPLETED', 'CANCELLED'], weights=[0.9, 0.1])[0]
            else:
                status = random.choices(['ACTIVE', 'OVERDUE'], weights=[0.85, 0.15])[0]

            rec = {
                'CONTRACT_ID': f"RC-{30000 + i:06d}",
                'CUSTOMER_ID': cust['CUSTOMER_ID'],
                'EQUIPMENT_ID': equip['EQUIPMENT_ID'],
                'BRANCH_ID': equip['BRANCH_ID'],
                'RENTAL_START_DATE': start.isoformat(),
                'RENTAL_END_DATE': end.isoformat(),
                'DURATION_DAYS': duration,
                'DAILY_RATE': equip['DAILY_RATE'],
                'WEEKLY_RATE': equip['WEEKLY_RATE'],
                'MONTHLY_RATE': equip['MONTHLY_RATE'],
                'TOTAL_AMOUNT': round(total, 2),
                'STATUS': status,
                'DELIVERY_ADDRESS': self.fake.street_address(),
                'DELIVERY_CITY': cust['CITY'],
                'DELIVERY_STATE': cust['STATE'],
                'DELIVERY_LATITUDE': round(self._jitter(cust['LATITUDE'], 0.05), 6),
                'DELIVERY_LONGITUDE': round(self._jitter(cust['LONGITUDE'], 0.05), 6),
                'PO_NUMBER': f"PO-{random.randint(100000, 999999)}",
                'SALES_REP': self.fake.name(),
            }
            rec.update(self._metadata('UR_RENTAL_CONTRACTS'))
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        return records

    # ------------------------------------------------------------------
    # MAINTENANCE RECORDS
    # ------------------------------------------------------------------
    def generate_maintenance_records(self, count: int) -> List[Dict]:
        if not self.equipment:
            raise ValueError("Must generate equipment first")
        print(f"  Generating {count} maintenance records...")
        records = []

        for i in range(count):
            equip = random.choice(self.equipment)
            mtype = random.choices(MAINTENANCE_TYPES, weights=[0.40, 0.30, 0.20, 0.10])[0]
            scheduled = self.fake.date_between(start_date='-1y', end_date='+1m')
            started = scheduled + timedelta(days=random.randint(0, 3))
            hours = round(random.uniform(0.5, 24.0), 1)
            completed = started + timedelta(hours=int(hours) + random.randint(0, 48))
            parts_cost = round(random.uniform(50, 5000), 2) if mtype != "INSPECTION" else 0.0
            labor_cost = round(hours * random.uniform(75, 150), 2)

            if completed < date.today():
                status = 'COMPLETED'
            else:
                status = random.choices(['SCHEDULED', 'IN_PROGRESS', 'COMPLETED'], weights=[0.3, 0.2, 0.5])[0]

            rec = {
                'RECORD_ID': f"MR-{40000 + i:06d}",
                'EQUIPMENT_ID': equip['EQUIPMENT_ID'],
                'BRANCH_ID': equip['BRANCH_ID'],
                'MAINTENANCE_TYPE': mtype,
                'DESCRIPTION': f"{mtype.title()} maintenance - {equip['DESCRIPTION']}",
                'SCHEDULED_DATE': scheduled.isoformat(),
                'START_DATE': started.isoformat(),
                'COMPLETION_DATE': completed.isoformat() if status == 'COMPLETED' else None,
                'LABOR_HOURS': hours,
                'PARTS_COST': parts_cost,
                'LABOR_COST': labor_cost,
                'TOTAL_COST': round(parts_cost + labor_cost, 2),
                'TECHNICIAN_NAME': self.fake.name(),
                'STATUS': status,
            }
            rec.update(self._metadata('UR_MAINTENANCE_RECORDS'))
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        return records

    # ------------------------------------------------------------------
    # TELEMATICS
    # ------------------------------------------------------------------
    def generate_telematics(self, count: int) -> List[Dict]:
        if not self.equipment:
            raise ValueError("Must generate equipment first")
        print(f"  Generating {count} telematics readings...")
        records = []
        active_equip = [e for e in self.equipment
                        if e['STATUS'] != 'DECOMMISSIONED'
                        and e['CATEGORY'] != 'TRENCH_SAFETY']
        if not active_equip:
            active_equip = self.equipment

        for i in range(count):
            equip = random.choice(active_equip)
            ts = self.fake.date_time_between(start_date='-30d', end_date='now')
            is_running = random.random() < 0.6 if equip['STATUS'] == 'RENTED' else random.random() < 0.1
            fault = random.choice(FAULT_CODES)

            rec = {
                'READING_ID': f"TL-{50000 + i:07d}",
                'EQUIPMENT_ID': equip['EQUIPMENT_ID'],
                'READING_TIMESTAMP': ts.isoformat(),
                'LATITUDE': round(self._jitter(equip['LATITUDE'], 0.002), 6),
                'LONGITUDE': round(self._jitter(equip['LONGITUDE'], 0.002), 6),
                'ENGINE_HOURS': equip['HOUR_METER_READING'] + round(random.uniform(0, 50), 1),
                'FUEL_LEVEL_PCT': round(random.uniform(10, 100), 1),
                'BATTERY_VOLTAGE': round(random.uniform(11.5, 14.5), 1),
                'IS_RUNNING': is_running,
                'SPEED_MPH': round(random.uniform(0, 15), 1) if is_running else 0.0,
                'AMBIENT_TEMP_F': round(random.uniform(20, 105), 1),
                'FAULT_CODE': fault[0],
                'FAULT_DESCRIPTION': fault[1],
            }
            rec.update(self._metadata('UR_TELEMATICS'))
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        return records

    # ------------------------------------------------------------------
    # ORCHESTRATOR
    # ------------------------------------------------------------------
    def generate(self, counts: Dict[str, int]) -> Dict[str, List[Dict]]:
        data = {}
        data['branches'] = self.generate_branches(counts.get('branches', 100))
        data['equipment'] = self.generate_equipment(counts.get('equipment', 5000))
        data['customers'] = self.generate_customers(counts.get('customers', 1000))
        data['rental_contracts'] = self.generate_rental_contracts(counts.get('rental_contracts', 10000))
        data['maintenance_records'] = self.generate_maintenance_records(counts.get('maintenance_records', 3000))
        data['telematics'] = self.generate_telematics(counts.get('telematics', 20000))
        return data


# ============================================================================
# OUTPUT
# ============================================================================

def save_to_csv(data: Dict[str, List[Dict]], output_dir: str):
    os.makedirs(output_dir, exist_ok=True)
    for table_name, records in data.items():
        if not records:
            continue
        filepath = os.path.join(output_dir, f"{table_name}.csv")
        print(f"  Writing {filepath} ({len(records):,} rows)...")
        flat_records = []
        for r in records:
            flat = {}
            for k, v in r.items():
                if isinstance(v, (dict, list)):
                    flat[k] = json.dumps(v)
                elif isinstance(v, bool):
                    flat[k] = str(v).upper()
                elif v is None:
                    flat[k] = ''
                else:
                    flat[k] = v
            flat_records.append(flat)
        with open(filepath, 'w', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=flat_records[0].keys())
            writer.writeheader()
            writer.writerows(flat_records)
    print(f"\n  All files written to {output_dir}/")


# ============================================================================
# CLI
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Generate United Rentals equipment rental data for Snowflake DCA demo",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python generate_ur_data.py --output ../data
  python generate_ur_data.py --output ../data --quick
  python generate_ur_data.py --output ../data --scale 2.0
  python generate_ur_data.py --output ../data --seed 123
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
    print("UNITED RENTALS DATA GENERATOR")
    print("=" * 60)
    print(f"  Seed:   {args.seed}")
    print(f"  Scale:  {'quick (10%)' if args.quick else f'{args.scale}x'}")
    print(f"  Output: {args.output}")
    print(f"  Counts: {counts}")
    print()

    generator = UnitedRentalsGenerator(seed=args.seed)
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
