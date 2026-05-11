#!/usr/bin/env python3
"""
Network Observability Telemetry Data Generator

Generates synthetic time-series telemetry data for the DCIM DCA demo:
  - port_metrics: 500,000 port-level 5-minute interval metrics over 7 days
  - switch_health: 100,000 switch-level health metrics every 5 minutes
  - environmental_sensors: 50,000 DC environmental monitoring readings
  - alerts: 10,000 threshold-crossing alerts

This is APPEND-ONLY time-series data — no SCD6 columns.

Usage:
    python generate_telemetry_data.py --output ../data
    python generate_telemetry_data.py --output ../data --quick       # Small test set
    python generate_telemetry_data.py --output ../data --scale 2.0   # Double size
"""

import os
import sys
import random
import hashlib
import json
import csv
import argparse
import uuid
import math
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

# Link statuses with weights
LINK_STATUSES = [("UP", 0.92), ("DOWN", 0.03), ("FLAPPING", 0.05)]

# Fan statuses
FAN_STATUSES = ["OK", "OK", "OK", "OK", "OK", "OK", "OK", "OK", "WARNING", "FAILED"]

# Alert severities with weights
ALERT_SEVERITIES = [("CRITICAL", 0.05), ("HIGH", 0.15), ("MEDIUM", 0.45), ("LOW", 0.35)]

# Alert types per source
ALERT_TYPES = {
    "PORT": [
        "CRC_ERROR_THRESHOLD", "UTILIZATION_HIGH", "INPUT_ERRORS_SPIKE",
        "OUTPUT_ERRORS_SPIKE", "LINK_FLAP_DETECTED", "LINK_DOWN",
    ],
    "SWITCH": [
        "CPU_THRESHOLD", "MEMORY_THRESHOLD", "TEMPERATURE_HIGH",
        "FAN_FAILURE", "BGP_PEER_DOWN", "ERROR_RATE_CRITICAL",
        "POWER_DRAW_HIGH", "UPTIME_RESET",
    ],
    "ENVIRONMENT": [
        "TEMPERATURE_HIGH", "TEMPERATURE_LOW", "HUMIDITY_HIGH",
        "HUMIDITY_LOW", "POWER_SPIKE", "COOLING_INEFFICIENT",
        "AIRFLOW_ANOMALY",
    ],
}

# Alert description templates
ALERT_DESCRIPTIONS = {
    "CRC_ERROR_THRESHOLD": "CRC error rate exceeded threshold of {threshold}% on port {port}",
    "UTILIZATION_HIGH": "Port utilization reached {val}%, exceeding {threshold}% threshold",
    "INPUT_ERRORS_SPIKE": "Input error rate spiked to {val} errors/sec on port {port}",
    "OUTPUT_ERRORS_SPIKE": "Output error rate spiked to {val} errors/sec on port {port}",
    "LINK_FLAP_DETECTED": "Link flap detected: {val} state changes in last 5 minutes",
    "LINK_DOWN": "Link down on port {port} — no carrier detected",
    "CPU_THRESHOLD": "Switch CPU utilization at {val}%, threshold {threshold}%",
    "MEMORY_THRESHOLD": "Switch memory utilization at {val}%, threshold {threshold}%",
    "TEMPERATURE_HIGH": "Temperature reading {val}°C exceeds threshold of {threshold}°C",
    "TEMPERATURE_LOW": "Temperature reading {val}°C below minimum threshold of {threshold}°C",
    "FAN_FAILURE": "Fan unit {unit} reported FAILED status",
    "BGP_PEER_DOWN": "BGP peer {peer} transitioned to DOWN state",
    "ERROR_RATE_CRITICAL": "Switch error rate at {val}%, exceeds critical threshold of {threshold}%",
    "POWER_DRAW_HIGH": "Power draw {val}W exceeds rated capacity threshold of {threshold}W",
    "UPTIME_RESET": "Switch uptime reset detected — possible reboot or crash",
    "HUMIDITY_HIGH": "Humidity at {val}% exceeds threshold of {threshold}%",
    "HUMIDITY_LOW": "Humidity at {val}% below minimum threshold of {threshold}%",
    "POWER_SPIKE": "Power draw spiked to {val}kW, {pct}% above baseline",
    "COOLING_INEFFICIENT": "PUE degraded to {val}, exceeding threshold of {threshold}",
    "AIRFLOW_ANOMALY": "Airflow at {val} CFM, {pct}% deviation from expected",
}

# Technician names for acknowledgment
TECHNICIAN_NAMES = [
    "jchen", "mgarcia", "asmith", "tkumar", "lwong",
    "rjohnson", "dlee", "kpatel", "bwilson", "jkim",
    "nthompson", "crodriguez", "mwilliams", "sbrown", "ajonas",
]

DEFAULT_COUNTS = {
    'port_metrics': 500000,
    'switch_health': 100000,
    'environmental_sensors': 50000,
    'alerts': 10000,
}


# ============================================================================
# GENERATOR
# ============================================================================

class TelemetryGenerator(SourceSystemGenerator):
    """Generates synthetic network observability telemetry time-series data."""

    SYSTEM_NAME = "NETWORK_OBSERVABILITY"

    def __init__(self, seed: int = 42):
        self.seed = seed
        random.seed(seed)
        self.fake = Faker('en_US')
        self.fake.seed_instance(seed)

        # Cross-system linkage: these ID patterns MUST match ServiceNow generator
        self.num_dcs = 20
        self.num_switches = 8000
        self.num_ports_per_switch = 8  # 64000 / 8000
        self.num_halls = 100
        self.num_racks = 2000

        # Pre-compute IDs for linkage
        self.dc_ids = [
            str(uuid.uuid5(uuid.NAMESPACE_OID, f'dc_{seed}_{i}'))
            for i in range(self.num_dcs)
        ]
        self.switch_ids = [
            str(uuid.uuid5(uuid.NAMESPACE_OID, f'switch_{seed}_{i}'))
            for i in range(self.num_switches)
        ]
        self.port_ids = [
            str(uuid.uuid5(uuid.NAMESPACE_OID, f'port_{seed}_{i}'))
            for i in range(self.num_switches * self.num_ports_per_switch)
        ]
        self.hall_ids = [
            str(uuid.uuid5(uuid.NAMESPACE_OID, f'hall_{seed}_{i}'))
            for i in range(self.num_halls)
        ]
        self.rack_ids = [
            str(uuid.uuid5(uuid.NAMESPACE_OID, f'rack_{seed}_{i}'))
            for i in range(self.num_racks)
        ]

        # Identify "problem children" switches (~2% with persistent high error rates)
        num_problem = max(1, int(self.num_switches * 0.02))
        self.problem_switches = set(random.sample(range(self.num_switches), num_problem))

        # Additional ~3% with elevated but not critical error rates
        remaining = [i for i in range(self.num_switches) if i not in self.problem_switches]
        num_elevated = max(1, int(self.num_switches * 0.03))
        self.elevated_switches = set(random.sample(remaining, num_elevated))

        # Degrading switches: subset of healthy switches that degrade over the 7-day window
        healthy = [i for i in range(self.num_switches)
                   if i not in self.problem_switches and i not in self.elevated_switches]
        num_degrading = max(1, int(len(healthy) * 0.01))
        self.degrading_switches = set(random.sample(healthy, num_degrading))

        # Time window: 7 days of 5-minute intervals
        self.base_time = datetime(2025, 1, 6, 0, 0, 0)  # Monday
        self.interval_minutes = 5
        self.total_intervals = (7 * 24 * 60) // self.interval_minutes  # 2016

    def _hash(self, record: Dict) -> str:
        data = {k: v for k, v in record.items() if not k.startswith('_')}
        return hashlib.sha256(json.dumps(data, sort_keys=True, default=str).encode()).hexdigest()

    def _get_timestamp(self, interval_idx: int) -> str:
        """Get ISO timestamp for a given interval index."""
        ts = self.base_time + timedelta(minutes=interval_idx * self.interval_minutes)
        return ts.isoformat()

    def _degradation_factor(self, switch_idx: int, interval_idx: int) -> float:
        """For degrading switches, returns a factor 0.0→1.0 over the 7-day window."""
        if switch_idx not in self.degrading_switches:
            return 0.0
        # Linear degradation from 0 at start to 1.0 at end of window
        return interval_idx / max(1, self.total_intervals - 1)

    # ------------------------------------------------------------------
    # PORT METRICS
    # ------------------------------------------------------------------
    def generate_port_metrics(self, count: int) -> List[Dict]:
        """Generate 5-minute interval port-level telemetry."""
        print(f"  Generating {count:,} port metrics...")
        records = []

        # Determine how many ports and intervals we need
        # count = num_ports_sampled * num_intervals_sampled
        # We'll sample a subset of ports across all intervals
        target_ports = max(10, count // self.total_intervals)
        if target_ports > len(self.port_ids):
            target_ports = len(self.port_ids)
        num_intervals = max(1, count // target_ports)
        if num_intervals > self.total_intervals:
            num_intervals = self.total_intervals

        # Sample ports deterministically
        port_indices = list(range(min(target_ports, len(self.port_ids))))
        # Sample intervals evenly across the 7-day window
        interval_step = max(1, self.total_intervals // num_intervals)
        interval_indices = list(range(0, self.total_intervals, interval_step))[:num_intervals]

        metric_counter = 0
        for p_idx in port_indices:
            port_id = self.port_ids[p_idx]
            switch_idx = p_idx // self.num_ports_per_switch
            switch_id = self.switch_ids[switch_idx] if switch_idx < len(self.switch_ids) else self.switch_ids[-1]

            is_problem = switch_idx in self.problem_switches
            is_elevated = switch_idx in self.elevated_switches
            is_degrading = switch_idx in self.degrading_switches

            for int_idx in interval_indices:
                if metric_counter >= count:
                    break

                timestamp = self._get_timestamp(int_idx)
                degrade = self._degradation_factor(switch_idx, int_idx)

                # Base utilization
                if is_problem:
                    utilization = random.uniform(60, 95)
                    crc_errors = random.randint(5, 50)
                    input_errors = random.randint(2, 30)
                    output_errors = random.randint(1, 20)
                elif is_elevated:
                    utilization = random.uniform(40, 75)
                    crc_errors = random.randint(1, 10)
                    input_errors = random.randint(0, 5)
                    output_errors = random.randint(0, 3)
                elif is_degrading:
                    # Starts healthy, ends problematic
                    utilization = random.uniform(10, 40) + degrade * 50
                    crc_errors = int(degrade * random.randint(5, 30))
                    input_errors = int(degrade * random.randint(2, 15))
                    output_errors = int(degrade * random.randint(1, 10))
                else:
                    utilization = random.uniform(10, 60)
                    crc_errors = 0 if random.random() > 0.02 else random.randint(1, 3)
                    input_errors = 0 if random.random() > 0.01 else random.randint(1, 2)
                    output_errors = 0

                # Bytes and packets scale with utilization
                base_bps = utilization / 100.0 * 10_000_000_000  # 10G link
                bytes_in = int(base_bps * 300 / 8 * random.uniform(0.4, 0.6))  # 5 min
                bytes_out = int(base_bps * 300 / 8 * random.uniform(0.4, 0.6))
                packets_in = bytes_in // random.randint(500, 1500)
                packets_out = bytes_out // random.randint(500, 1500)

                # Link status
                if is_problem and random.random() < 0.05:
                    link_status = random.choice(["DOWN", "FLAPPING"])
                elif is_degrading and degrade > 0.8 and random.random() < 0.03:
                    link_status = "FLAPPING"
                else:
                    link_status = random.choices(
                        [s[0] for s in LINK_STATUSES],
                        weights=[s[1] for s in LINK_STATUSES]
                    )[0]

                rec = {
                    'metric_id': str(uuid.uuid5(uuid.NAMESPACE_OID,
                                                f'pm_{self.seed}_{p_idx}_{int_idx}')),
                    'port_id': port_id,
                    'switch_id': switch_id,
                    'timestamp': timestamp,
                    'bytes_in': bytes_in,
                    'bytes_out': bytes_out,
                    'packets_in': packets_in,
                    'packets_out': packets_out,
                    'crc_errors': crc_errors,
                    'input_errors': input_errors,
                    'output_errors': output_errors,
                    'utilization_pct': round(min(utilization, 100.0), 2),
                    'link_status': link_status,
                    '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                    '_LOADED_AT': datetime.now().isoformat(),
                }
                records.append(rec)
                metric_counter += 1

            if metric_counter >= count:
                break

        return records

    # ------------------------------------------------------------------
    # SWITCH HEALTH
    # ------------------------------------------------------------------
    def generate_switch_health(self, count: int) -> List[Dict]:
        """Generate switch-level health metrics every 5 minutes."""
        print(f"  Generating {count:,} switch health metrics...")
        records = []

        # Determine switches and intervals
        target_switches = max(10, count // self.total_intervals)
        if target_switches > self.num_switches:
            target_switches = self.num_switches
        num_intervals = max(1, count // target_switches)
        if num_intervals > self.total_intervals:
            num_intervals = self.total_intervals

        switch_indices = list(range(target_switches))
        interval_step = max(1, self.total_intervals // num_intervals)
        interval_indices = list(range(0, self.total_intervals, interval_step))[:num_intervals]

        metric_counter = 0
        for sw_idx in switch_indices:
            switch_id = self.switch_ids[sw_idx]
            is_problem = sw_idx in self.problem_switches
            is_elevated = sw_idx in self.elevated_switches
            is_degrading = sw_idx in self.degrading_switches

            # Stable per-switch characteristics
            base_cpu = random.uniform(15, 40) if not is_problem else random.uniform(50, 75)
            base_mem = random.uniform(30, 55) if not is_problem else random.uniform(60, 80)
            base_temp = random.uniform(28, 38) if not is_problem else random.uniform(38, 50)
            base_power = random.uniform(150, 350)
            bgp_total = random.choice([2, 4, 6, 8])
            base_uptime = random.randint(86400, 31536000)  # 1 day to 1 year

            for int_idx in interval_indices:
                if metric_counter >= count:
                    break

                timestamp = self._get_timestamp(int_idx)
                degrade = self._degradation_factor(sw_idx, int_idx)

                # CPU/Memory with noise
                if is_degrading:
                    cpu = base_cpu + degrade * 40 + random.uniform(-3, 3)
                else:
                    cpu = base_cpu + random.uniform(-5, 8)
                cpu = round(max(1, min(cpu, 100)), 1)

                if is_degrading:
                    mem = base_mem + degrade * 25 + random.uniform(-2, 2)
                else:
                    mem = base_mem + random.uniform(-3, 5)
                mem = round(max(5, min(mem, 100)), 1)

                # Temperature
                if is_degrading:
                    temp = base_temp + degrade * 15 + random.uniform(-1, 1)
                else:
                    temp = base_temp + random.uniform(-2, 3)
                temp = round(max(15, min(temp, 65)), 1)

                # Fan status
                if is_problem and random.random() < 0.03:
                    fan = "FAILED"
                elif is_degrading and degrade > 0.7 and random.random() < 0.02:
                    fan = "WARNING"
                else:
                    fan = random.choice(FAN_STATUSES)

                # Power draw
                power = round(base_power + random.uniform(-20, 30), 1)

                # Uptime increments by interval unless problem switch resets
                uptime = base_uptime + int_idx * self.interval_minutes * 60
                if is_problem and random.random() < 0.005:
                    uptime = random.randint(60, 3600)  # Recent reboot

                # BGP peers
                if is_problem:
                    bgp_established = max(0, bgp_total - random.randint(0, 2))
                elif is_degrading and degrade > 0.6:
                    bgp_established = max(0, bgp_total - (1 if random.random() < 0.1 else 0))
                else:
                    bgp_established = bgp_total

                # Error rate
                if is_problem:
                    error_rate = round(random.uniform(2.0, 8.0), 3)
                elif is_elevated:
                    error_rate = round(random.uniform(0.5, 2.0), 3)
                elif is_degrading:
                    error_rate = round(degrade * random.uniform(2.0, 5.0), 3)
                else:
                    error_rate = round(random.uniform(0, 0.3), 3)

                rec = {
                    'metric_id': str(uuid.uuid5(uuid.NAMESPACE_OID,
                                                f'sh_{self.seed}_{sw_idx}_{int_idx}')),
                    'switch_id': switch_id,
                    'timestamp': timestamp,
                    'cpu_utilization': cpu,
                    'memory_utilization': mem,
                    'temperature_celsius': temp,
                    'fan_status': fan,
                    'power_draw_watts': power,
                    'uptime_seconds': uptime,
                    'bgp_peers_established': bgp_established,
                    'bgp_peers_total': bgp_total,
                    'error_rate_pct': error_rate,
                    '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                    '_LOADED_AT': datetime.now().isoformat(),
                }
                records.append(rec)
                metric_counter += 1

            if metric_counter >= count:
                break

        return records

    # ------------------------------------------------------------------
    # ENVIRONMENTAL SENSORS
    # ------------------------------------------------------------------
    def generate_environmental_sensors(self, count: int) -> List[Dict]:
        """Generate DC environmental monitoring sensor readings."""
        print(f"  Generating {count:,} environmental sensor readings...")
        records = []

        # Sensors per location: distribute across DCs, halls, racks
        num_sensor_locations = max(5, min(200, count // self.total_intervals))
        num_intervals = max(1, count // num_sensor_locations)
        if num_intervals > self.total_intervals:
            num_intervals = self.total_intervals

        interval_step = max(1, self.total_intervals // num_intervals)
        interval_indices = list(range(0, self.total_intervals, interval_step))[:num_intervals]

        sensor_counter = 0
        for s_idx in range(num_sensor_locations):
            if sensor_counter >= count:
                break

            sensor_id = str(uuid.uuid5(uuid.NAMESPACE_OID, f'sensor_{self.seed}_{s_idx}'))
            dc_idx = s_idx % self.num_dcs
            hall_idx = s_idx % self.num_halls
            rack_idx = s_idx % self.num_racks

            dc_id = self.dc_ids[dc_idx]
            hall_id = self.hall_ids[hall_idx]
            rack_id = self.rack_ids[rack_idx]

            # Per-sensor baseline characteristics
            base_temp = random.uniform(18, 24)
            base_humidity = random.uniform(40, 60)
            base_power = random.uniform(5, 25)  # kW per rack/area
            base_pue = random.uniform(1.2, 1.6)
            base_airflow = random.uniform(800, 2000)  # CFM

            # Some sensors in "hot" locations
            is_hot_spot = random.random() < 0.08
            if is_hot_spot:
                base_temp += random.uniform(3, 8)
                base_pue += random.uniform(0.2, 0.5)

            for int_idx in interval_indices:
                if sensor_counter >= count:
                    break

                timestamp = self._get_timestamp(int_idx)

                # Diurnal pattern: slightly warmer during business hours
                hour = (self.base_time + timedelta(
                    minutes=int_idx * self.interval_minutes)).hour
                diurnal_offset = 1.5 * math.sin((hour - 6) * math.pi / 12) if 6 <= hour <= 18 else 0

                temp = round(base_temp + diurnal_offset + random.uniform(-1.5, 1.5), 1)
                humidity = round(base_humidity + random.uniform(-5, 5), 1)
                humidity = max(20, min(humidity, 85))
                power = round(base_power + random.uniform(-2, 3), 2)
                pue = round(base_pue + random.uniform(-0.1, 0.15), 2)
                pue = max(1.0, pue)
                airflow = round(base_airflow + random.uniform(-100, 150), 0)

                rec = {
                    'sensor_id': sensor_id,
                    'data_center_id': dc_id,
                    'hall_id': hall_id,
                    'rack_id': rack_id,
                    'timestamp': timestamp,
                    'temperature_celsius': temp,
                    'humidity_pct': humidity,
                    'power_draw_kw': power,
                    'cooling_efficiency_pue': pue,
                    'airflow_cfm': int(airflow),
                    '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                    '_LOADED_AT': datetime.now().isoformat(),
                }
                records.append(rec)
                sensor_counter += 1

        return records

    # ------------------------------------------------------------------
    # ALERTS
    # ------------------------------------------------------------------
    def generate_alerts(self, count: int) -> List[Dict]:
        """Generate alerts from threshold crossings."""
        print(f"  Generating {count:,} alerts...")
        records = []

        source_types = ["PORT", "SWITCH", "ENVIRONMENT"]
        source_weights = [0.40, 0.40, 0.20]

        for i in range(count):
            source_type = random.choices(source_types, weights=source_weights)[0]

            # Pick source entity
            if source_type == "PORT":
                source_id = random.choice(self.port_ids)
            elif source_type == "SWITCH":
                # Bias toward problem/elevated switches for alerts
                if random.random() < 0.6:
                    problem_list = list(self.problem_switches | self.elevated_switches)
                    if problem_list:
                        sw_idx = random.choice(problem_list)
                    else:
                        sw_idx = random.randint(0, self.num_switches - 1)
                else:
                    sw_idx = random.randint(0, self.num_switches - 1)
                source_id = self.switch_ids[sw_idx]
            else:
                source_id = random.choice(self.dc_ids)

            # Timestamp spread across the 7-day window
            interval_idx = random.randint(0, self.total_intervals - 1)
            timestamp = self._get_timestamp(interval_idx)

            severity = random.choices(
                [s[0] for s in ALERT_SEVERITIES],
                weights=[s[1] for s in ALERT_SEVERITIES]
            )[0]

            alert_type = random.choice(ALERT_TYPES[source_type])

            # Build description from template
            template = ALERT_DESCRIPTIONS.get(alert_type, f"{alert_type} alert triggered")
            desc = template.format(
                val=round(random.uniform(50, 99), 1),
                threshold=round(random.uniform(70, 95), 0),
                port=source_id[:8] if source_type == "PORT" else "N/A",
                unit=random.randint(1, 4),
                peer=f"10.{random.randint(0,255)}.{random.randint(0,255)}.{random.randint(1,254)}",
                pct=random.randint(10, 50),
            )

            # Acknowledgment: most alerts get acknowledged
            acknowledged = random.random() < 0.75
            acknowledged_by = random.choice(TECHNICIAN_NAMES) if acknowledged else None

            # Resolution time: CRITICAL resolved faster (escalation), LOW may linger
            if acknowledged:
                if severity == "CRITICAL":
                    resolution_time = random.randint(5, 60)
                elif severity == "HIGH":
                    resolution_time = random.randint(15, 120)
                elif severity == "MEDIUM":
                    resolution_time = random.randint(30, 480)
                else:
                    resolution_time = random.randint(60, 1440)
            else:
                resolution_time = None

            rec = {
                'alert_id': str(uuid.uuid5(uuid.NAMESPACE_OID, f'alert_{self.seed}_{i}')),
                'source_type': source_type,
                'source_id': source_id,
                'timestamp': timestamp,
                'severity': severity,
                'alert_type': alert_type,
                'description': desc,
                'acknowledged': acknowledged,
                'acknowledged_by': acknowledged_by,
                'resolution_time_minutes': resolution_time,
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_LOADED_AT': datetime.now().isoformat(),
            }
            records.append(rec)

        return records

    # ------------------------------------------------------------------
    # ORCHESTRATOR
    # ------------------------------------------------------------------
    def generate(self, counts: Dict[str, int]) -> Dict[str, List[Dict]]:
        data = {}
        data['port_metrics'] = self.generate_port_metrics(
            counts.get('port_metrics', 500000))
        data['switch_health'] = self.generate_switch_health(
            counts.get('switch_health', 100000))
        data['environmental_sensors'] = self.generate_environmental_sensors(
            counts.get('environmental_sensors', 50000))
        data['alerts'] = self.generate_alerts(
            counts.get('alerts', 10000))
        return data


# ============================================================================
# OUTPUT — delegates to base data_generator.save_to_csv
# ============================================================================

def save_to_csv(data: Dict[str, List[Dict]], output_dir: str):
    """Save using the base data_generator's save_to_csv under telemetry/ subfolder."""
    base_save_to_csv(data, output_dir, "telemetry")


# ============================================================================
# CLI
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Generate network observability telemetry data for Snowflake DCIM demo",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python generate_telemetry_data.py --output ../data
  python generate_telemetry_data.py --output ../data --quick
  python generate_telemetry_data.py --output ../data --scale 2.0
  python generate_telemetry_data.py --output ../data --seed 123
        """
    )
    parser.add_argument("--output", "-o", default="../data",
                       help="Output directory (default: ../data)")
    parser.add_argument("--seed", type=int, default=42,
                       help="Random seed for reproducibility (default: 42)")
    parser.add_argument("--quick", action="store_true",
                       help="Generate small test dataset (~10%% — fewer intervals, same device count)")
    parser.add_argument("--scale", type=float, default=1.0,
                       help="Scale factor for record counts (default: 1.0)")

    args = parser.parse_args()
    counts = dict(DEFAULT_COUNTS)
    if args.quick:
        # Quick mode: 10% scale — fewer time intervals, NOT fewer devices
        counts = {k: max(100, v // 10) for k, v in counts.items()}
    else:
        counts = {k: int(v * args.scale) for k, v in counts.items()}

    print("=" * 60)
    print("NETWORK OBSERVABILITY TELEMETRY DATA GENERATOR")
    print("=" * 60)
    print(f"  Seed:   {args.seed}")
    print(f"  Scale:  {'quick (10%)' if args.quick else f'{args.scale}x'}")
    print(f"  Output: {args.output}")
    print(f"  Counts: {counts}")
    print()

    generator = TelemetryGenerator(seed=args.seed)
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
