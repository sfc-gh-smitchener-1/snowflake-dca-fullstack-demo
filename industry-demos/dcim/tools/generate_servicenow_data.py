#!/usr/bin/env python3
"""
ServiceNow CMDB/DCIM Data Generator for Snowflake DCA Demo

Generates synthetic ServiceNow CMDB asset data with SCD Type 6 (hybrid) columns
for data center infrastructure: data centers, halls, racks, switches, ports,
incidents, and change requests.

Usage:
    python generate_servicenow_data.py --output ../data
    python generate_servicenow_data.py --output ../data --quick
    python generate_servicenow_data.py --output ../data --scale 2.0
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
    'data_centers': 20,
    'halls': 100,
    'racks': 2000,
    'switches': 8000,
    'ports': 64000,
    'incidents': 5000,
    'change_requests': 3000,
}

DC_LOCATIONS = [
    ('US-East-1', 'Ashburn', 'VA', 'US', 'Americas'),
    ('US-East-2', 'Ashburn', 'VA', 'US', 'Americas'),
    ('US-West-1', 'The Dalles', 'OR', 'US', 'Americas'),
    ('US-West-2', 'Santa Clara', 'CA', 'US', 'Americas'),
    ('US-Central-1', 'Council Bluffs', 'IA', 'US', 'Americas'),
    ('EU-West-1', 'Dublin', '', 'IE', 'EMEA'),
    ('EU-West-2', 'London', '', 'GB', 'EMEA'),
    ('EU-Central-1', 'Frankfurt', '', 'DE', 'EMEA'),
    ('EU-North-1', 'Stockholm', '', 'SE', 'EMEA'),
    ('APAC-East-1', 'Tokyo', '', 'JP', 'APAC'),
    ('APAC-East-2', 'Osaka', '', 'JP', 'APAC'),
    ('APAC-South-1', 'Singapore', '', 'SG', 'APAC'),
    ('APAC-South-2', 'Mumbai', '', 'IN', 'APAC'),
    ('APAC-East-3', 'Sydney', '', 'AU', 'APAC'),
    ('SA-East-1', 'Sao Paulo', '', 'BR', 'Americas'),
    ('ME-South-1', 'Bahrain', '', 'BH', 'EMEA'),
    ('CA-Central-1', 'Montreal', '', 'CA', 'Americas'),
    ('AF-South-1', 'Cape Town', '', 'ZA', 'EMEA'),
    ('EU-South-1', 'Milan', '', 'IT', 'EMEA'),
    ('APAC-SE-1', 'Jakarta', '', 'ID', 'APAC'),
]

SWITCH_MODELS = [
    ('Cloud-Scale Spine 9300', 'SPINE', 128),
    ('Aggregation Router 7500', 'AGGREGATION', 96),
    ('Top-of-Rack 5200', 'TOR', 48),
    ('Edge Leaf 3100', 'LEAF', 24),
]

FIRMWARE_VERSIONS = [
    'NX-OS 10.4(1)', 'NX-OS 10.3(3)', 'NX-OS 10.2(5)',
    'EOS 4.30.1F', 'EOS 4.29.3F', 'EOS 4.28.5M',
    'Junos 23.2R1', 'Junos 22.4R2', 'Junos 22.2R3',
    'SONiC 202311', 'SONiC 202305',
]

PORT_SPEEDS = ['1G', '10G', '25G', '40G', '100G']

INCIDENT_CATEGORIES = [
    'Hardware Failure', 'Link Flap', 'CRC Errors', 'Power Event',
    'Cooling Alert', 'Firmware Bug', 'Configuration Drift', 'Capacity Threshold',
]

SLA_TIERS = [
    ('PLATINUM', 99.999),
    ('GOLD', 99.99),
    ('SILVER', 99.9),
    ('BRONZE', 99.0),
]

CHANGE_TYPES = [
    'Firmware Upgrade', 'Rack Migration', 'Decommission', 'Capacity Expansion',
    'Cable Remediation', 'Power Redistribution', 'Cooling Optimization',
    'Security Patching', 'Configuration Update', 'Hardware Replacement',
]


# ============================================================================
# SERVICENOW DCIM GENERATOR
# ============================================================================

class ServiceNowDCIMGenerator(SourceSystemGenerator):
    """Generates ServiceNow CMDB data for data center infrastructure."""

    SYSTEM_NAME = "SERVICENOW"

    def __init__(self, seed: int = 42):
        super().__init__(seed)
        self.now = datetime.now()

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

    # ------------------------------------------------------------------
    # DATA CENTERS
    # ------------------------------------------------------------------
    def generate_data_centers(self, count: int) -> List[Dict]:
        print(f"  Generating {count} data centers...")
        records = []
        locations = DC_LOCATIONS[:count]

        for i in range(count):
            loc = locations[i % len(locations)]
            dc_id = self._id('dc', i)
            campus_id = self._id('campus', i)
            tier = random.choice([1, 2, 3, 3, 3, 4, 4])
            sla = SLA_TIERS[min(tier - 1, 3)]
            power_mw = round(random.uniform(10, 120), 1)
            build_date = self.fake.date_between(start_date='-15y', end_date='-1y')

            record = {
                'dc_id': dc_id,
                'campus_id': campus_id,
                'dc_name': f"{loc[0]}-DC{i+1:02d}",
                'region_code': loc[0],
                'city': loc[1],
                'state_province': loc[2],
                'country_code': loc[3],
                'geo_region': loc[4],
                'tier_level': tier,
                'sla_tier': sla[0],
                'sla_uptime_pct': sla[1],
                'power_capacity_mw': power_mw,
                'current_power_draw_mw': round(power_mw * random.uniform(0.4, 0.85), 1),
                'cooling_type': random.choice(['Chilled Water', 'Direct Liquid', 'Free Air', 'Hybrid']),
                'build_date': build_date.isoformat(),
                'status': random.choice(['OPERATIONAL', 'OPERATIONAL', 'OPERATIONAL', 'MAINTENANCE', 'EXPANSION']),
                # SCD6 dimension columns
                'current_status': None,  # filled below
                'historical_status': None,
                'original_status': 'OPERATIONAL',
                'current_power_capacity_mw': power_mw,
                'historical_power_capacity_mw': power_mw,
                'original_power_capacity_mw': power_mw,
            }
            record['current_status'] = record['status']
            record['historical_status'] = record['status']

            valid_from = datetime.combine(build_date, datetime.min.time())
            self._scd6_current(record, valid_from)
            records.append(record)

        self._data_centers = records
        return records

    # ------------------------------------------------------------------
    # HALLS
    # ------------------------------------------------------------------
    def generate_halls(self, count: int) -> List[Dict]:
        print(f"  Generating {count} halls...")
        records = []
        dc_ids = [dc['dc_id'] for dc in self._data_centers]

        for i in range(count):
            dc_idx = i % len(dc_ids)
            hall_id = self._id('hall', i)
            floor_area = random.randint(5000, 50000)
            cooling_kw = round(floor_area * random.uniform(0.15, 0.35), 1)
            build_date = self.fake.date_between(start_date='-12y', end_date='-6m')

            record = {
                'hall_id': hall_id,
                'dc_id': dc_ids[dc_idx],
                'hall_name': f"Hall-{chr(65 + (i % 26))}{i // 26 + 1:02d}",
                'floor_number': random.randint(1, 4),
                'floor_area_sqft': floor_area,
                'rack_capacity': floor_area // 25,
                'cooling_capacity_kw': cooling_kw,
                'current_cooling_load_kw': round(cooling_kw * random.uniform(0.3, 0.9), 1),
                'fire_suppression_type': random.choice(['FM-200', 'Novec 1230', 'Inergen', 'Pre-Action Sprinkler']),
                'status': random.choice(['OPERATIONAL', 'OPERATIONAL', 'OPERATIONAL', 'MAINTENANCE']),
                'build_date': build_date.isoformat(),
                # SCD6
                'current_status': None,
                'historical_status': None,
                'original_status': 'OPERATIONAL',
                'current_cooling_capacity_kw': cooling_kw,
                'historical_cooling_capacity_kw': cooling_kw,
                'original_cooling_capacity_kw': cooling_kw,
            }
            record['current_status'] = record['status']
            record['historical_status'] = record['status']

            valid_from = datetime.combine(build_date, datetime.min.time())
            self._scd6_current(record, valid_from)
            records.append(record)

        self._halls = records
        return records

    # ------------------------------------------------------------------
    # RACKS
    # ------------------------------------------------------------------
    def generate_racks(self, count: int) -> List[Dict]:
        print(f"  Generating {count} racks...")
        records = []
        hall_ids = [h['hall_id'] for h in self._halls]
        dc_map = {h['hall_id']: h['dc_id'] for h in self._halls}

        change_pct = 0.05  # 5% have power allocation changes

        for i in range(count):
            hall_idx = i % len(hall_ids)
            rack_id = self._id('rack', i)
            power_kw = round(random.uniform(5, 30), 1)
            install_date = self.fake.date_between(start_date='-10y', end_date='-3m')

            has_change = random.random() < change_pct
            original_power = round(power_kw * random.uniform(0.5, 0.8), 1) if has_change else power_kw

            record = {
                'rack_id': rack_id,
                'hall_id': hall_ids[hall_idx],
                'dc_id': dc_map[hall_ids[hall_idx]],
                'rack_name': f"R{i+1:05d}",
                'rack_units': 42,
                'rack_units_used': random.randint(10, 42),
                'power_allocation_kw': power_kw,
                'current_power_draw_kw': round(power_kw * random.uniform(0.3, 0.95), 1),
                'weight_capacity_kg': random.choice([1000, 1200, 1500, 2000]),
                'row_position': f"Row-{chr(65 + (i % 20))}",
                'rack_position': i % 30 + 1,
                'install_date': install_date.isoformat(),
                'status': random.choice(['ACTIVE', 'ACTIVE', 'ACTIVE', 'ACTIVE', 'DECOMMISSIONING', 'RESERVED']),
                # SCD6
                'current_power_allocation_kw': power_kw,
                'historical_power_allocation_kw': power_kw if not has_change else original_power,
                'original_power_allocation_kw': original_power,
                'current_status': None,
                'historical_status': None,
                'original_status': 'ACTIVE',
            }
            record['current_status'] = record['status']
            record['historical_status'] = record['status']

            valid_from = datetime.combine(install_date, datetime.min.time())

            if has_change:
                # Historical record
                change_date = self.fake.date_between(start_date=install_date, end_date='today')
                hist = dict(record)
                hist['power_allocation_kw'] = original_power
                hist['current_power_draw_kw'] = round(original_power * random.uniform(0.3, 0.95), 1)
                hist['historical_power_allocation_kw'] = original_power
                self._scd6_historical(hist, valid_from, datetime.combine(change_date, datetime.min.time()), 1)
                records.append(hist)

                # Current record (version 2)
                record['_VERSION'] = 2
                valid_from = datetime.combine(change_date, datetime.min.time())

            self._scd6_current(record, valid_from)
            records.append(record)

        self._racks = [r for r in records if r['_IS_CURRENT']]
        return records

    # ------------------------------------------------------------------
    # SWITCHES
    # ------------------------------------------------------------------
    def generate_switches(self, count: int) -> List[Dict]:
        print(f"  Generating {count} switches...")
        records = []
        rack_ids = [r['rack_id'] for r in self._racks]
        rack_to_dc = {r['rack_id']: r['dc_id'] for r in self._racks}
        rack_to_hall = {r['rack_id']: r['hall_id'] for r in self._racks}

        move_pct = 0.10  # 10% have had rack moves

        for i in range(count):
            rack_idx = i % len(rack_ids)
            switch_id = self._id('switch', i)
            model_info = random.choice(SWITCH_MODELS)
            firmware = random.choice(FIRMWARE_VERSIONS)
            install_date = self.fake.date_between(start_date='-8y', end_date='-1m')

            has_move = random.random() < move_pct
            original_rack_id = rack_ids[(rack_idx + random.randint(1, 50)) % len(rack_ids)] if has_move else rack_ids[rack_idx]

            record = {
                'switch_id': switch_id,
                'rack_id': rack_ids[rack_idx],
                'hall_id': rack_to_hall[rack_ids[rack_idx]],
                'dc_id': rack_to_dc[rack_ids[rack_idx]],
                'switch_name': f"sw-{model_info[1].lower()[:3]}-{i+1:06d}",
                'model': model_info[0],
                'switch_role': model_info[1],
                'port_count': model_info[2],
                'firmware_version': firmware,
                'management_ip': f"10.{random.randint(1,254)}.{random.randint(0,254)}.{random.randint(1,254)}",
                'serial_number': f"SN-{self.fake.bothify('??##??##??').upper()}",
                'install_date': install_date.isoformat(),
                'last_reboot': self.fake.date_time_between(start_date='-90d', end_date='now').isoformat(),
                'status': random.choices(
                    ['ACTIVE', 'ACTIVE', 'ACTIVE', 'ACTIVE', 'DEGRADED', 'MAINTENANCE', 'FAILED'],
                    weights=[40, 40, 40, 40, 5, 3, 2]
                )[0],
                # SCD6
                'current_rack_id': rack_ids[rack_idx],
                'historical_rack_id': rack_ids[rack_idx] if not has_move else original_rack_id,
                'original_rack_id': original_rack_id,
                'current_firmware_version': firmware,
                'historical_firmware_version': firmware,
                'original_firmware_version': firmware,
                'current_status': None,
                'historical_status': None,
                'original_status': 'ACTIVE',
            }
            record['current_status'] = record['status']
            record['historical_status'] = record['status']

            valid_from = datetime.combine(install_date, datetime.min.time())

            if has_move:
                move_date = self.fake.date_between(start_date=install_date, end_date='today')
                hist = dict(record)
                hist['rack_id'] = original_rack_id
                hist['hall_id'] = rack_to_hall.get(original_rack_id, hist['hall_id'])
                hist['dc_id'] = rack_to_dc.get(original_rack_id, hist['dc_id'])
                hist['current_rack_id'] = rack_ids[rack_idx]  # current always points to latest
                hist['historical_rack_id'] = original_rack_id
                self._scd6_historical(hist, valid_from, datetime.combine(move_date, datetime.min.time()), 1)
                records.append(hist)

                record['_VERSION'] = 2
                valid_from = datetime.combine(move_date, datetime.min.time())

            self._scd6_current(record, valid_from)
            records.append(record)

        self._switches = [r for r in records if r['_IS_CURRENT']]
        return records

    # ------------------------------------------------------------------
    # PORTS
    # ------------------------------------------------------------------
    def generate_ports(self, count: int) -> List[Dict]:
        print(f"  Generating {count} ports...")
        records = []
        switch_list = self._switches

        ports_per_switch = max(1, count // len(switch_list))

        port_idx = 0
        for sw in switch_list:
            n_ports = min(ports_per_switch, sw['port_count'])
            for p in range(n_ports):
                if port_idx >= count:
                    break
                speed = random.choice(PORT_SPEEDS)
                record = {
                    'port_id': self._id('port', port_idx),
                    'switch_id': sw['switch_id'],
                    'port_name': f"Eth{p // 4 + 1}/{p % 4 + 1}",
                    'port_index': p,
                    'speed': speed,
                    'media_type': 'SFP+' if speed in ('10G', '25G') else ('QSFP28' if speed in ('40G', '100G') else 'RJ45'),
                    'connected_device_type': random.choice([
                        'SERVER', 'SERVER', 'SERVER', 'STORAGE', 'SWITCH_UPLINK',
                        'FIREWALL', 'LOAD_BALANCER', 'PDU', 'UNCONNECTED'
                    ]),
                    'vlan_id': random.choice([None, 100, 200, 300, 400, 500, 1000, 2000]),
                    'status': random.choices(
                        ['UP', 'UP', 'UP', 'DOWN', 'ADMIN_DOWN', 'ERR_DISABLED'],
                        weights=[70, 70, 70, 5, 3, 2]
                    )[0],
                    'last_state_change': self.fake.date_time_between(start_date='-30d', end_date='now').isoformat(),
                    '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                    '_LOADED_AT': self.now.isoformat(),
                }
                record['_ROW_HASH'] = self._hash(record)
                records.append(record)
                port_idx += 1
            if port_idx >= count:
                break

        # Fill remaining if switches didn't cover all
        while port_idx < count:
            sw = random.choice(switch_list)
            speed = random.choice(PORT_SPEEDS)
            record = {
                'port_id': self._id('port', port_idx),
                'switch_id': sw['switch_id'],
                'port_name': f"Eth{port_idx // 4 + 1}/{port_idx % 4 + 1}",
                'port_index': port_idx % 48,
                'speed': speed,
                'media_type': 'SFP+' if speed in ('10G', '25G') else ('QSFP28' if speed in ('40G', '100G') else 'RJ45'),
                'connected_device_type': random.choice([
                    'SERVER', 'STORAGE', 'SWITCH_UPLINK', 'FIREWALL', 'UNCONNECTED'
                ]),
                'vlan_id': random.choice([None, 100, 200, 300, 500]),
                'status': random.choices(['UP', 'DOWN', 'ADMIN_DOWN'], weights=[85, 10, 5])[0],
                'last_state_change': self.fake.date_time_between(start_date='-30d', end_date='now').isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_LOADED_AT': self.now.isoformat(),
            }
            record['_ROW_HASH'] = self._hash(record)
            records.append(record)
            port_idx += 1

        return records

    # ------------------------------------------------------------------
    # INCIDENTS
    # ------------------------------------------------------------------
    def generate_incidents(self, count: int) -> List[Dict]:
        print(f"  Generating {count} incidents...")
        records = []
        switch_ids = [sw['switch_id'] for sw in self._switches]
        dc_ids = [dc['dc_id'] for dc in self._data_centers]
        # Technician IDs for cross-system linkage with Workday
        num_technicians = 500

        priorities = ['P1', 'P2', 'P3', 'P4']
        priority_weights = [5, 15, 40, 40]
        states = ['New', 'In Progress', 'On Hold', 'Resolved', 'Closed']
        state_weights = [5, 15, 5, 30, 45]

        for i in range(count):
            priority = random.choices(priorities, weights=priority_weights)[0]
            state = random.choices(states, weights=state_weights)[0]
            category = random.choice(INCIDENT_CATEGORIES)
            opened_at = self.fake.date_time_between(start_date='-180d', end_date='now')

            # Resolution time depends on priority
            resolution_mins = None
            if state in ('Resolved', 'Closed'):
                base_mins = {'P1': 30, 'P2': 120, 'P3': 480, 'P4': 1440}[priority]
                resolution_mins = int(base_mins * random.uniform(0.5, 3.0))

            tech_idx = random.randint(0, num_technicians - 1)

            record = {
                'incident_id': self._id('incident', i),
                'incident_number': f"INC{i+1:07d}",
                'dc_id': random.choice(dc_ids),
                'affected_switch_id': random.choice(switch_ids),
                'assigned_technician': self._id('technician', tech_idx),
                'priority': priority,
                'state': state,
                'category': category,
                'subcategory': f"{category} - {random.choice(['Primary', 'Secondary', 'Intermittent', 'Persistent'])}",
                'short_description': f"{category} detected on {random.choice(['spine', 'leaf', 'tor', 'aggregation'])} switch",
                'opened_at': opened_at.isoformat(),
                'resolved_at': (opened_at + timedelta(minutes=resolution_mins)).isoformat() if resolution_mins else None,
                'closed_at': (opened_at + timedelta(minutes=resolution_mins + random.randint(0, 60))).isoformat() if resolution_mins and state == 'Closed' else None,
                'resolution_time_minutes': resolution_mins,
                'sla_breached': resolution_mins is not None and resolution_mins > {'P1': 60, 'P2': 240, 'P3': 960, 'P4': 2880}[priority],
                'impact': random.choice(['1 - High', '2 - Medium', '3 - Low']),
                'urgency': random.choice(['1 - High', '2 - Medium', '3 - Low']),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_LOADED_AT': self.now.isoformat(),
            }
            record['_ROW_HASH'] = self._hash(record)
            records.append(record)

        return records

    # ------------------------------------------------------------------
    # CHANGE REQUESTS
    # ------------------------------------------------------------------
    def generate_change_requests(self, count: int) -> List[Dict]:
        print(f"  Generating {count} change requests...")
        records = []
        switch_ids = [sw['switch_id'] for sw in self._switches]
        dc_ids = [dc['dc_id'] for dc in self._data_centers]
        num_technicians = 500

        risk_levels = ['Low', 'Medium', 'High', 'Critical']
        risk_weights = [30, 40, 20, 10]
        states = ['New', 'Assess', 'Authorize', 'Scheduled', 'Implement', 'Review', 'Closed', 'Cancelled']
        state_weights = [5, 5, 5, 10, 10, 10, 50, 5]

        for i in range(count):
            change_type = random.choice(CHANGE_TYPES)
            risk = random.choices(risk_levels, weights=risk_weights)[0]
            state = random.choices(states, weights=state_weights)[0]
            requested_at = self.fake.date_time_between(start_date='-120d', end_date='now')
            planned_start = requested_at + timedelta(days=random.randint(1, 14))
            planned_end = planned_start + timedelta(hours=random.randint(1, 48))

            tech_idx = random.randint(0, num_technicians - 1)

            record = {
                'change_id': self._id('change', i),
                'change_number': f"CHG{i+1:07d}",
                'dc_id': random.choice(dc_ids),
                'affected_switch_id': random.choice(switch_ids),
                'requested_by': self._id('technician', tech_idx),
                'assigned_to': self._id('technician', random.randint(0, num_technicians - 1)),
                'change_type': change_type,
                'category': 'Infrastructure',
                'risk_level': risk,
                'state': state,
                'short_description': f"{change_type} for {random.choice(['spine', 'leaf', 'tor', 'agg'])} switch",
                'justification': f"Required for {random.choice(['capacity planning', 'security compliance', 'performance optimization', 'end-of-life replacement', 'vendor advisory'])}",
                'requested_at': requested_at.isoformat(),
                'planned_start': planned_start.isoformat(),
                'planned_end': planned_end.isoformat(),
                'actual_start': planned_start.isoformat() if state in ('Implement', 'Review', 'Closed') else None,
                'actual_end': planned_end.isoformat() if state in ('Review', 'Closed') else None,
                'backout_plan': f"Revert {change_type.lower()} using snapshot from {(planned_start - timedelta(hours=1)).strftime('%Y-%m-%d %H:%M')}",
                'success': state == 'Closed' and random.random() > 0.05,
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
        # Stage 1: Hierarchy
        data['data_centers'] = self.generate_data_centers(counts.get('data_centers', 20))
        data['halls'] = self.generate_halls(counts.get('halls', 100))
        data['racks'] = self.generate_racks(counts.get('racks', 2000))
        data['switches'] = self.generate_switches(counts.get('switches', 8000))

        # Stage 2: Port-level detail
        data['ports'] = self.generate_ports(counts.get('ports', 64000))

        # Stage 3: ITSM events
        data['incidents'] = self.generate_incidents(counts.get('incidents', 5000))
        data['change_requests'] = self.generate_change_requests(counts.get('change_requests', 3000))

        return data


# ============================================================================
# OUTPUT
# ============================================================================

def save_to_csv(data: Dict[str, List[Dict]], output_dir: str):
    """Save using the base data_generator's save_to_csv."""
    base_save_to_csv(data, output_dir, "servicenow")


# ============================================================================
# CLI
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Generate ServiceNow CMDB/DCIM data for Snowflake DCA demo",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python generate_servicenow_data.py --output ../data
  python generate_servicenow_data.py --output ../data --quick
  python generate_servicenow_data.py --output ../data --scale 2.0
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
    print("SERVICENOW CMDB/DCIM DATA GENERATOR")
    print("=" * 60)
    print(f"  Seed:   {args.seed}")
    print(f"  Scale:  {'quick (10%)' if args.quick else f'{args.scale}x'}")
    print(f"  Output: {args.output}")
    print(f"  Counts: {counts}")
    print()

    generator = ServiceNowDCIMGenerator(seed=args.seed)
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
