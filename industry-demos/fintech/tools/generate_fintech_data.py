#!/usr/bin/env python3
"""
Fintech Cross-Border Payments Data Generator

Generates realistic synthetic data for the Fintech DCA demo:
  - customers: 50,000 sender profiles with KYC data
  - beneficiaries: 30,000 payment recipients
  - transactions: 200,000 cross-border payment transactions
  - agents: 5,000 payment agent locations
  - corridors: 100 country-to-country payment corridors
  - watchlist_entities: 200 fictional sanctioned entities
  - devices: 20,000 customer device fingerprints
  - sars: 500 suspicious activity reports

Usage:
    python generate_fintech_data.py --output ../data
    python generate_fintech_data.py --output ../data --quick       # Small test set
    python generate_fintech_data.py --output ../data --scale 2.0   # Double size
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

# Sender origin countries with weights
SENDER_COUNTRIES = [
    ("US", 0.70), ("MX", 0.05), ("PH", 0.03), ("IN", 0.03),
    ("GT", 0.02), ("CO", 0.02), ("UK", 0.05), ("DE", 0.04),
    ("FR", 0.03), ("AE", 0.03),
]

# Receiver destination countries with weights
RECEIVER_COUNTRIES = [
    ("MX", 0.25), ("PH", 0.12), ("IN", 0.15), ("GT", 0.08),
    ("CO", 0.07), ("PK", 0.08), ("NG", 0.06), ("TR", 0.05),
    ("MA", 0.04), ("BD", 0.05), ("SV", 0.03), ("HN", 0.02),
]

# Banks by country
BANKS_BY_COUNTRY = {
    "MX": ["Banorte", "BBVA Mexico", "Santander Mexico", "Banamex", "Banco Azteca"],
    "PH": ["BDO Unibank", "BPI", "Metrobank", "Landbank", "UnionBank"],
    "IN": ["State Bank of India", "HDFC Bank", "ICICI Bank", "Punjab National Bank", "Bank of Baroda"],
    "GT": ["Banco Industrial", "Banrural", "BAM Guatemala", "Banco G&T Continental"],
    "CO": ["Bancolombia", "Banco de Bogota", "Davivienda", "BBVA Colombia"],
    "PK": ["Habib Bank", "United Bank", "MCB Bank", "Allied Bank", "Bank Alfalah"],
    "NG": ["First Bank Nigeria", "Zenith Bank", "Access Bank", "GTBank", "UBA"],
    "TR": ["Ziraat Bankasi", "Is Bankasi", "Garanti BBVA", "Akbank", "Yapi Kredi"],
    "MA": ["Attijariwafa Bank", "BMCE Bank", "Banque Populaire", "CIH Bank"],
    "BD": ["Sonali Bank", "Janata Bank", "Agrani Bank", "Bangladesh Krishi Bank", "BRAC Bank"],
    "SV": ["Banco Agricola", "Banco Cuscatlan", "Davivienda El Salvador"],
    "HN": ["Banco Atlantida", "BAC Credomatic", "Ficohsa"],
}

# Exchange rates (approximate USD to local currency)
EXCHANGE_RATES = {
    "MXN": 17.2, "PHP": 56.0, "INR": 83.5, "GTQ": 7.8,
    "COP": 3950.0, "PKR": 280.0, "NGN": 1550.0, "TRY": 32.0,
    "MAD": 10.0, "BDT": 110.0, "GBP": 0.79, "EUR": 0.92,
    "AED": 3.67, "SVC": 8.75, "HNL": 24.7,
}

# Country to currency mapping
COUNTRY_CURRENCY = {
    "US": "USD", "MX": "MXN", "PH": "PHP", "IN": "INR",
    "GT": "GTQ", "CO": "COP", "PK": "PKR", "NG": "NGN",
    "TR": "TRY", "MA": "MAD", "BD": "BDT", "UK": "GBP",
    "DE": "EUR", "FR": "EUR", "AE": "AED", "SV": "SVC", "HN": "HNL",
}

# Corridors with risk levels
CORRIDOR_RISK = {
    "US_MX": "LOW", "US_PH": "LOW", "US_IN": "LOW", "US_GT": "MEDIUM",
    "US_CO": "MEDIUM", "US_PK": "HIGH", "US_NG": "HIGH", "US_TR": "MEDIUM",
    "US_MA": "MEDIUM", "US_BD": "MEDIUM", "UK_PK": "HIGH", "UK_NG": "HIGH",
    "DE_TR": "MEDIUM", "FR_MA": "LOW", "AE_PK": "HIGH", "AE_BD": "HIGH",
    "US_SV": "MEDIUM", "US_HN": "MEDIUM",
}

# Sanctioned-adjacent corridors (near Iran, North Korea, Syria, etc.)
SANCTIONED_ADJACENT_CORRIDORS = {
    "AE_PK", "US_PK", "UK_PK", "AE_BD",
}

CUSTOMER_TYPES = ["INDIVIDUAL", "BUSINESS"]
CUSTOMER_TYPE_WEIGHTS = [0.85, 0.15]

KYC_STATUSES = ["VERIFIED", "PENDING", "EXPIRED", "ENHANCED_DUE_DILIGENCE"]
KYC_STATUS_WEIGHTS = [0.75, 0.10, 0.10, 0.05]

KYC_METHODS = ["IN_PERSON", "REMOTE_VIDEO", "DOCUMENT_UPLOAD"]
KYC_METHOD_WEIGHTS = [0.40, 0.25, 0.35]

RISK_LEVELS = ["LOW", "MEDIUM", "HIGH", "PROHIBITED"]
RISK_LEVEL_WEIGHTS = [0.60, 0.25, 0.12, 0.03]

SOURCE_OF_FUNDS = ["EMPLOYMENT", "BUSINESS_INCOME", "INVESTMENT", "FAMILY_SUPPORT", "RETIREMENT"]
SOURCE_WEIGHTS = [0.50, 0.20, 0.10, 0.12, 0.08]

CHANNELS = ["AGENT", "ONLINE", "MOBILE_APP"]
CHANNEL_WEIGHTS = [0.40, 0.30, 0.30]

RELATIONSHIPS = ["FAMILY", "BUSINESS", "SELF", "FRIEND", "OTHER"]
RELATIONSHIP_WEIGHTS = [0.45, 0.20, 0.15, 0.12, 0.08]

AGENT_TIERS = ["PLATINUM", "GOLD", "SILVER", "BRONZE"]
AGENT_TIER_WEIGHTS = [0.05, 0.15, 0.40, 0.40]

AGENT_STATUSES = ["ACTIVE", "SUSPENDED", "TERMINATED", "UNDER_REVIEW"]
AGENT_STATUS_WEIGHTS = [0.88, 0.05, 0.03, 0.04]

TXN_STATUSES = ["COMPLETED", "PENDING", "CANCELLED", "HELD_FOR_REVIEW"]
TXN_STATUS_WEIGHTS = [0.85, 0.07, 0.03, 0.05]

SAR_ACTIVITY_TYPES = [
    "STRUCTURING", "THIRD_PARTY_MONEY_LAUNDERING", "IDENTITY_FRAUD",
    "UNUSUAL_PATTERN", "SANCTIONS_EVASION", "FUNNEL_ACCOUNT",
]

SAR_FILING_STATUSES = ["FILED", "DRAFT", "REJECTED", "CONTINUING_ACTIVITY"]
SAR_FILING_WEIGHTS = [0.55, 0.20, 0.10, 0.15]

WATCHLIST_TYPES = ["SDN", "PEP", "ADVERSE_MEDIA", "EU_SANCTIONS", "UN_SANCTIONS"]
WATCHLIST_PROGRAMS = ["NARCOTICS", "TERRORISM", "WEAPONS", "CORRUPTION", "HUMAN_RIGHTS"]
ENTITY_TYPES = ["INDIVIDUAL", "ORGANIZATION", "VESSEL", "AIRCRAFT"]

# Fictional watchlist entity names
WATCHLIST_NAMES = [
    "OCEANIC TRADING CONSORTIUM", "DESERT STAR HOLDINGS", "NORTHBRIDGE CAPITAL GROUP",
    "CRIMSON WAVE LOGISTICS", "GOLDEN PHOENIX ENTERPRISES", "IRON GATE SHIPPING LLC",
    "SILVER CRESCENT IMPORTS", "BLUE HORIZON VENTURES", "DARK RIVER COMMODITIES",
    "ATLAS PEAK FINANCIAL", "SAHARA WIND TRADING", "EMERALD PATH SOLUTIONS",
    "THUNDER BAY EXPORTS", "COPPER RIDGE MINING", "JADE MOUNTAIN HOLDINGS",
    "ARCTIC FLAME ENERGY", "CANYON BRIDGE CAPITAL", "PEARL HARBOR LOGISTICS",
    "FALCON RIDGE AVIATION", "STORM GATE INDUSTRIES", "SHADOW VALLEY RESOURCES",
    "SUNBURST GLOBAL TRADE", "MOONLIGHT MARITIME", "REDSTONE DEFENSE CORP",
    "CRYSTAL LAKE FINANCE", "GRANITE PEAK METALS", "OPAL COAST SHIPPING",
    "WILDFIRE ENERGY GROUP", "NIGHTFALL TECHNOLOGIES", "COBALT STREAM MINING",
]

# US cities for agents/customers
US_CITIES = [
    ("New York", "NY"), ("Los Angeles", "CA"), ("Chicago", "IL"), ("Houston", "TX"),
    ("Phoenix", "AZ"), ("Philadelphia", "PA"), ("San Antonio", "TX"), ("San Diego", "CA"),
    ("Dallas", "TX"), ("San Jose", "CA"), ("Austin", "TX"), ("Jacksonville", "FL"),
    ("Fort Worth", "TX"), ("Columbus", "OH"), ("Charlotte", "NC"), ("Indianapolis", "IN"),
    ("San Francisco", "CA"), ("Seattle", "WA"), ("Denver", "CO"), ("Nashville", "TN"),
    ("Miami", "FL"), ("Atlanta", "GA"), ("Portland", "OR"), ("Las Vegas", "NV"),
    ("Memphis", "TN"), ("Louisville", "KY"), ("Baltimore", "MD"), ("Milwaukee", "WI"),
    ("Albuquerque", "NM"), ("Tucson", "AZ"), ("Fresno", "CA"), ("Sacramento", "CA"),
    ("Mesa", "AZ"), ("Kansas City", "MO"), ("Omaha", "NE"), ("El Paso", "TX"),
    ("Raleigh", "NC"), ("Cleveland", "OH"), ("Tampa", "FL"), ("New Orleans", "LA"),
]

# Agent store name templates
AGENT_NAME_TEMPLATES = [
    "QuickSend #{num}", "MoneyGram Express - {city}", "PayPoint {city} #{num}",
    "FastCash {city}", "GlobalRemit - {city} #{num}", "SendRight {city}",
    "WireNow - {city} Downtown", "CashExpress {city} #{num}",
    "United Transfers - {city}", "SpeedPay {city} #{num}",
    "Remit Hub {city}", "TransferMax - {city} #{num}",
]

OCCUPATIONS = [
    "Construction Worker", "Restaurant Worker", "Healthcare Aide",
    "Driver", "Retail Associate", "Warehouse Worker", "IT Professional",
    "Engineer", "Teacher", "Small Business Owner", "Nurse",
    "Housekeeper", "Landscaper", "Factory Worker", "Office Worker",
]

PLATFORMS = ["IOS", "ANDROID", "WEB_BROWSER"]
PLATFORM_WEIGHTS = [0.40, 0.45, 0.15]


DEFAULT_COUNTS = {
    'customers': 50000,
    'beneficiaries': 30000,
    'transactions': 200000,
    'agents': 5000,
    'corridors': 100,
    'watchlist_entities': 200,
    'devices': 20000,
    'sars': 500,
}


# ============================================================================
# GENERATOR
# ============================================================================

class FintechGenerator(SourceSystemGenerator):
    """Generates synthetic cross-border payment data with fraud patterns."""

    SYSTEM_NAME = "FINTECH_PAYMENTS"

    def __init__(self, seed: int = 42):
        self.seed = seed
        random.seed(seed)
        self.fake = Faker('en_US')
        self.fake.seed_instance(seed)
        self.customers: List[Dict] = []
        self.beneficiaries: List[Dict] = []
        self.agents: List[Dict] = []
        self.corridors: List[Dict] = []
        # Fraud ring tracking
        self.fraud_ring_customers: List[List[int]] = []  # 5 groups of customer indices
        self.shared_beneficiary_ids: List[str] = []
        self.shared_device_customers: List[List[int]] = []  # 3 groups of customer indices
        self.shared_device_ids: List[str] = []

    def _hash(self, record: Dict) -> str:
        data = {k: v for k, v in record.items() if not k.startswith('_')}
        return hashlib.sha256(json.dumps(data, sort_keys=True, default=str).encode()).hexdigest()

    def _weighted_choice(self, items: list, weights: list):
        return random.choices(items, weights=weights, k=1)[0]

    # ------------------------------------------------------------------
    # CUSTOMERS
    # ------------------------------------------------------------------
    def generate_customers(self, count: int) -> List[Dict]:
        print(f"  Generating {count} customers...")
        records = []

        # Pre-assign fraud ring members (5 groups of 10-15)
        all_indices = list(range(count))
        random.shuffle(all_indices)
        idx_offset = 0
        for ring in range(5):
            ring_size = random.randint(10, 15)
            self.fraud_ring_customers.append(all_indices[idx_offset:idx_offset + ring_size])
            idx_offset += ring_size

        # Pre-assign shared device clusters (3 groups of 8-12)
        for cluster in range(3):
            cluster_size = random.randint(8, 12)
            self.shared_device_customers.append(all_indices[idx_offset:idx_offset + cluster_size])
            idx_offset += cluster_size

        sender_countries = [c[0] for c in SENDER_COUNTRIES]
        sender_weights = [c[1] for c in SENDER_COUNTRIES]

        for i in range(count):
            country = self._weighted_choice(sender_countries, sender_weights)

            if country == "US":
                city, state = random.choice(US_CITIES)
                first = self.fake.first_name()
                last = self.fake.last_name()
            else:
                city = self.fake.city()
                state = ""
                first = self.fake.first_name()
                last = self.fake.last_name()

            customer_type = self._weighted_choice(CUSTOMER_TYPES, CUSTOMER_TYPE_WEIGHTS)
            kyc_status = self._weighted_choice(KYC_STATUSES, KYC_STATUS_WEIGHTS)
            kyc_method = self._weighted_choice(KYC_METHODS, KYC_METHOD_WEIGHTS)
            risk_level = self._weighted_choice(RISK_LEVELS, RISK_LEVEL_WEIGHTS)

            # 10% have stale KYC (> 3 years old)
            if random.random() < 0.10:
                kyc_date = self.fake.date_between(start_date='-6y', end_date='-3y')
            else:
                kyc_date = self.fake.date_between(start_date='-3y', end_date='today')

            account_open_date = self.fake.date_between(start_date='-5y', end_date='today')
            channel = self._weighted_choice(CHANNELS, CHANNEL_WEIGHTS)

            rec = {
                'customer_id': f"CU-{100000 + i:07d}",
                'first_name': first,
                'last_name': last,
                'date_of_birth': self.fake.date_of_birth(minimum_age=18, maximum_age=75).isoformat(),
                'ssn_last4': f"{random.randint(1000, 9999)}",
                'country': country,
                'city': city,
                'state': state,
                'address': self.fake.street_address(),
                'phone': self.fake.phone_number(),
                'email': self.fake.email(),
                'customer_type': customer_type,
                'kyc_date': kyc_date.isoformat(),
                'kyc_status': kyc_status,
                'kyc_method': kyc_method,
                'risk_level': risk_level,
                'occupation': random.choice(OCCUPATIONS),
                'source_of_funds': self._weighted_choice(SOURCE_OF_FUNDS, SOURCE_WEIGHTS),
                'account_open_date': account_open_date.isoformat(),
                'channel': channel,
                'created_at': datetime.combine(account_open_date, datetime.min.time()).isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        self.customers = records
        return records

    # ------------------------------------------------------------------
    # BENEFICIARIES
    # ------------------------------------------------------------------
    def generate_beneficiaries(self, count: int) -> List[Dict]:
        if not self.customers:
            raise ValueError("Must generate customers first")
        print(f"  Generating {count} beneficiaries...")
        records = []

        receiver_countries = [c[0] for c in RECEIVER_COUNTRIES]
        receiver_weights = [c[1] for c in RECEIVER_COUNTRIES]

        # Create 5 "shared" beneficiaries for fraud rings first
        for ring_idx in range(5):
            country = self._weighted_choice(receiver_countries, receiver_weights)
            banks = BANKS_BY_COUNTRY.get(country, ["International Bank"])
            bene_id = f"BN-{200000 + ring_idx:07d}"
            self.shared_beneficiary_ids.append(bene_id)

            # This beneficiary is referenced by multiple customers in the ring
            creator_idx = self.fraud_ring_customers[ring_idx][0]
            creator = self.customers[creator_idx]

            rec = {
                'beneficiary_id': bene_id,
                'name': self.fake.name(),
                'relationship': 'BUSINESS',
                'country': country,
                'city': self.fake.city(),
                'bank_name': random.choice(banks),
                'account_number_masked': f"****{random.randint(1000, 9999)}",
                'phone': self.fake.phone_number(),
                'created_by_customer_id': creator['customer_id'],
                'created_at': self.fake.date_time_between(start_date='-2y', end_date='now').isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        # Generate remaining beneficiaries
        remaining = count - len(records)
        for i in range(remaining):
            country = self._weighted_choice(receiver_countries, receiver_weights)
            banks = BANKS_BY_COUNTRY.get(country, ["International Bank"])
            relationship = self._weighted_choice(RELATIONSHIPS, RELATIONSHIP_WEIGHTS)
            creator = random.choice(self.customers)

            rec = {
                'beneficiary_id': f"BN-{200005 + i:07d}",
                'name': self.fake.name(),
                'relationship': relationship,
                'country': country,
                'city': self.fake.city(),
                'bank_name': random.choice(banks),
                'account_number_masked': f"****{random.randint(1000, 9999)}",
                'phone': self.fake.phone_number(),
                'created_by_customer_id': creator['customer_id'],
                'created_at': self.fake.date_time_between(start_date='-2y', end_date='now').isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        self.beneficiaries = records
        return records

    # ------------------------------------------------------------------
    # AGENTS
    # ------------------------------------------------------------------
    def generate_agents(self, count: int) -> List[Dict]:
        print(f"  Generating {count} agents...")
        records = []

        # 80% US, 20% international
        us_count = int(count * 0.80)
        intl_count = count - us_count

        # Identify anomaly agents (2% with volume spikes)
        anomaly_indices = set(random.sample(range(count), max(1, int(count * 0.02))))

        for i in range(count):
            if i < us_count:
                city, state = random.choice(US_CITIES)
                country = "US"
                region = state
            else:
                intl_countries = ["MX", "PH", "IN", "UK", "DE"]
                country = random.choice(intl_countries)
                city = self.fake.city()
                state = ""
                region = country

            tier = self._weighted_choice(AGENT_TIERS, AGENT_TIER_WEIGHTS)
            status = self._weighted_choice(AGENT_STATUSES, AGENT_STATUS_WEIGHTS)

            # Generate agent name
            template = random.choice(AGENT_NAME_TEMPLATES)
            agent_name = template.format(city=city, num=random.randint(100, 9999))
            agent_code = f"AG-{300000 + i:06d}"

            onboard_date = self.fake.date_between(start_date='-8y', end_date='-6m')
            monthly_volume_avg = random.randint(50000, 2000000)

            # 2% have anomalous current month volume (5-10x average)
            if i in anomaly_indices:
                current_month_volume = monthly_volume_avg * random.randint(5, 10)
            else:
                current_month_volume = int(monthly_volume_avg * random.uniform(0.6, 1.5))

            compliance_score = round(random.uniform(0.5, 1.0), 2)
            if tier == "PLATINUM":
                compliance_score = round(random.uniform(0.85, 1.0), 2)
            elif tier == "BRONZE":
                compliance_score = round(random.uniform(0.5, 0.8), 2)

            rec = {
                'agent_id': agent_code,
                'agent_name': agent_name,
                'agent_code': agent_code,
                'city': city,
                'state': state,
                'country': country,
                'region': region,
                'tier': tier,
                'onboard_date': onboard_date.isoformat(),
                'monthly_volume_avg': monthly_volume_avg,
                'current_month_volume': current_month_volume,
                'compliance_score': compliance_score,
                'last_audit_date': self.fake.date_between(start_date='-1y', end_date='today').isoformat(),
                'sar_count_ytd': random.choices([0, 1, 2, 3, 4, 5], weights=[0.60, 0.20, 0.10, 0.05, 0.03, 0.02])[0],
                'active_customers': random.randint(50, 5000),
                'status': status,
                'created_at': datetime.combine(onboard_date, datetime.min.time()).isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        self.agents = records
        return records

    # ------------------------------------------------------------------
    # CORRIDORS
    # ------------------------------------------------------------------
    def generate_corridors(self, count: int) -> List[Dict]:
        print(f"  Generating {count} corridors...")
        records = []

        # Major corridors first
        origin_countries = ["US", "UK", "DE", "FR", "AE", "CA", "AU", "JP", "KR", "IT"]
        dest_countries = ["MX", "PH", "IN", "GT", "CO", "PK", "NG", "TR", "MA", "BD",
                         "SV", "HN", "VN", "CN", "EG", "ET", "KE", "GH", "NP", "LK"]

        corridor_set = set()
        # Add known corridors first
        for corridor_code, risk in CORRIDOR_RISK.items():
            origin, dest = corridor_code.split('_')
            corridor_set.add((origin, dest))

        # Fill to count
        while len(corridor_set) < count:
            origin = random.choice(origin_countries)
            dest = random.choice(dest_countries)
            if origin != dest:
                corridor_set.add((origin, dest))

        for idx, (origin, dest) in enumerate(corridor_set):
            if len(records) >= count:
                break

            corridor_code = f"{origin}_{dest}"
            risk = CORRIDOR_RISK.get(corridor_code, random.choice(["LOW", "MEDIUM", "HIGH"]))
            sanctioned_adj = corridor_code in SANCTIONED_ADJACENT_CORRIDORS

            # Regulatory designation
            if risk == "HIGH" or sanctioned_adj:
                reg = random.choices(
                    ['NONE', 'GTO', 'ENHANCED_MONITORING'], weights=[0.3, 0.3, 0.4]
                )[0]
            elif risk == "MEDIUM":
                reg = random.choices(
                    ['NONE', 'GTO', 'ENHANCED_MONITORING'], weights=[0.6, 0.2, 0.2]
                )[0]
            else:
                reg = random.choices(
                    ['NONE', 'GTO', 'ENHANCED_MONITORING'], weights=[0.9, 0.05, 0.05]
                )[0]

            rec = {
                'corridor_id': f"CR-{400000 + idx:06d}",
                'origin_country': origin,
                'destination_country': dest,
                'corridor_code': corridor_code,
                'risk_level': risk,
                'avg_daily_volume': random.randint(100000, 50000000),
                'avg_transaction_size': random.randint(100, 2000),
                'sanctioned_adjacent': str(sanctioned_adj).upper(),
                'regulatory_designation': reg,
                'monthly_sar_count': random.randint(0, 50) if risk in ("HIGH", "VERY_HIGH") else random.randint(0, 10),
                'active_agents': random.randint(50, 5000),
                'created_at': self.fake.date_time_between(start_date='-5y', end_date='-1y').isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        self.corridors = records
        return records

    # ------------------------------------------------------------------
    # TRANSACTIONS
    # ------------------------------------------------------------------
    def generate_transactions(self, count: int) -> List[Dict]:
        if not self.customers or not self.beneficiaries or not self.agents:
            raise ValueError("Must generate customers, beneficiaries, and agents first")
        print(f"  Generating {count} transactions...")
        records = []

        active_agents = [a for a in self.agents if a['status'] == 'ACTIVE'] or self.agents

        # Gather all fraud ring customer IDs for structuring detection
        fraud_ring_customer_ids = set()
        for ring in self.fraud_ring_customers:
            for idx in ring:
                if idx < len(self.customers):
                    fraud_ring_customer_ids.add(self.customers[idx]['customer_id'])

        # Build a mapping of fraud ring customers to their shared beneficiary
        customer_to_shared_bene = {}
        for ring_idx, ring_members in enumerate(self.fraud_ring_customers):
            bene_id = self.shared_beneficiary_ids[ring_idx]
            for idx in ring_members:
                if idx < len(self.customers):
                    customer_to_shared_bene[self.customers[idx]['customer_id']] = bene_id

        # High-risk corridors for 2% of transactions
        high_risk_dest = ["IR", "KP", "SY", "YE", "MM"]

        for i in range(count):
            customer = random.choice(self.customers)
            cust_id = customer['customer_id']
            agent = random.choice(active_agents)

            # Determine if this is a fraud ring transaction
            is_fraud_ring = cust_id in fraud_ring_customer_ids and random.random() < 0.7

            if is_fraud_ring:
                # Structuring: amounts just under $3K
                amount_send = round(random.uniform(2800, 2999), 2)
                bene_id = customer_to_shared_bene.get(cust_id, random.choice(self.beneficiaries)['beneficiary_id'])
            else:
                # Normal distribution: $50-$5000, median ~$300
                amount_send = round(random.lognormvariate(5.7, 1.0), 2)
                amount_send = max(50, min(5000, amount_send))
                bene = random.choice(self.beneficiaries)
                bene_id = bene['beneficiary_id']

            # Find beneficiary country for corridor
            bene_record = next((b for b in self.beneficiaries if b['beneficiary_id'] == bene_id), None)
            if bene_record:
                dest_country = bene_record['country']
            else:
                dest_country = random.choice([c[0] for c in RECEIVER_COUNTRIES])

            origin_country = customer['country']
            currency_send = COUNTRY_CURRENCY.get(origin_country, "USD")
            currency_receive = COUNTRY_CURRENCY.get(dest_country, "USD")

            # Exchange rate
            if currency_send == "USD":
                rate = EXCHANGE_RATES.get(currency_receive, 1.0)
                rate = rate * random.uniform(0.97, 1.03)  # slight variance
                amount_receive = round(amount_send * rate, 2)
            else:
                rate = 1.0 / EXCHANGE_RATES.get(currency_send, 1.0) * EXCHANGE_RATES.get(currency_receive, 1.0)
                rate = rate * random.uniform(0.97, 1.03)
                amount_receive = round(amount_send * rate, 2)

            corridor = f"{origin_country}\u2192{dest_country}"
            channel = self._weighted_choice(CHANNELS, CHANNEL_WEIGHTS)
            txn_date = self.fake.date_between(start_date='-2y', end_date='today')
            txn_time = self.fake.time()

            status = self._weighted_choice(TXN_STATUSES, TXN_STATUS_WEIGHTS)
            compliance_hold = "TRUE" if random.random() < 0.03 else "FALSE"
            if compliance_hold == "TRUE":
                status = "HELD_FOR_REVIEW"

            # 2% to high-risk corridors
            if random.random() < 0.02 and not is_fraud_ring:
                dest_country = random.choice(high_risk_dest)
                corridor = f"{origin_country}\u2192{dest_country}"
                compliance_hold = "TRUE"
                status = "HELD_FOR_REVIEW"

            fee = round(amount_send * random.uniform(0.02, 0.08), 2)

            rec = {
                'txn_id': f"TX-{500000 + i:08d}",
                'sender_id': cust_id,
                'beneficiary_id': bene_id,
                'agent_id': agent['agent_id'],
                'amount_send': amount_send,
                'currency_send': currency_send,
                'amount_receive': round(amount_receive, 2),
                'currency_receive': currency_receive,
                'exchange_rate': round(rate, 4),
                'corridor': corridor,
                'channel': channel,
                'txn_date': txn_date.isoformat(),
                'txn_time': txn_time,
                'status': status,
                'fee': fee,
                'compliance_hold': compliance_hold,
                'device_id': '',  # Will be populated after devices are generated
                'created_at': datetime.combine(txn_date, datetime.min.time()).isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        return records

    # ------------------------------------------------------------------
    # DEVICES
    # ------------------------------------------------------------------
    def generate_devices(self, count: int) -> List[Dict]:
        if not self.customers:
            raise ValueError("Must generate customers first")
        print(f"  Generating {count} devices...")
        records = []

        # Create shared device IDs for clusters
        for cluster_idx in range(3):
            device_id = f"DV-{600000 + cluster_idx:07d}"
            self.shared_device_ids.append(device_id)

        # Generate shared device records first (one per cluster)
        for cluster_idx, cluster_members in enumerate(self.shared_device_customers):
            device_id = self.shared_device_ids[cluster_idx]
            fingerprint = hashlib.sha256(f"shared_device_{cluster_idx}_{self.seed}".encode()).hexdigest()
            platform = self._weighted_choice(PLATFORMS, PLATFORM_WEIGHTS)

            for member_idx in cluster_members:
                if member_idx < len(self.customers):
                    customer = self.customers[member_idx]
                    first_seen = self.fake.date_between(start_date='-2y', end_date='-6m')
                    last_seen = self.fake.date_between(start_date='-6m', end_date='today')

                    # Determine IP country (might be different from customer country - suspicious)
                    ip_country = customer['country'] if random.random() < 0.7 else random.choice(["US", "UK", "NG", "GH"])

                    rec = {
                        'device_id': device_id,
                        'device_fingerprint': fingerprint,
                        'customer_id': customer['customer_id'],
                        'platform': platform,
                        'os_version': self._generate_os_version(platform),
                        'first_seen_date': first_seen.isoformat(),
                        'last_seen_date': last_seen.isoformat(),
                        'ip_country': ip_country,
                        'is_rooted': "TRUE" if random.random() < 0.15 else "FALSE",  # Higher for shared
                        'created_at': datetime.combine(first_seen, datetime.min.time()).isoformat(),
                        '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                        '_ROW_HASH': None,
                    }
                    rec['_ROW_HASH'] = self._hash(rec)
                    records.append(rec)

        # Generate remaining normal devices
        remaining = count - len(records)
        device_counter = 3  # Start after shared devices

        for i in range(remaining):
            customer = random.choice(self.customers)
            device_id = f"DV-{600000 + device_counter + i:07d}"
            fingerprint = hashlib.sha256(f"device_{device_counter + i}_{self.seed}".encode()).hexdigest()
            platform = self._weighted_choice(PLATFORMS, PLATFORM_WEIGHTS)
            first_seen = self.fake.date_between(start_date='-2y', end_date='-1m')
            last_seen = self.fake.date_between(start_date='-1m', end_date='today')

            rec = {
                'device_id': device_id,
                'device_fingerprint': fingerprint,
                'customer_id': customer['customer_id'],
                'platform': platform,
                'os_version': self._generate_os_version(platform),
                'first_seen_date': first_seen.isoformat(),
                'last_seen_date': last_seen.isoformat(),
                'ip_country': customer['country'],
                'is_rooted': "TRUE" if random.random() < 0.05 else "FALSE",
                'created_at': datetime.combine(first_seen, datetime.min.time()).isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        return records

    def _generate_os_version(self, platform: str) -> str:
        if platform == "IOS":
            return f"iOS {random.choice(['16.0', '16.5', '17.0', '17.1', '17.2', '17.4', '17.5', '18.0'])}"
        elif platform == "ANDROID":
            return f"Android {random.choice(['12', '13', '14', '15'])}"
        else:
            return f"Chrome {random.randint(110, 125)}"

    # ------------------------------------------------------------------
    # WATCHLIST ENTITIES
    # ------------------------------------------------------------------
    def generate_watchlist_entities(self, count: int) -> List[Dict]:
        print(f"  Generating {count} watchlist entities...")
        records = []

        # Use predefined names + generate more if needed
        names = list(WATCHLIST_NAMES)
        while len(names) < count:
            adj = random.choice(["DARK", "GOLDEN", "IRON", "SILVER", "SHADOW", "THUNDER",
                                "CRYSTAL", "FALCON", "ARCTIC", "CORAL", "GRANITE", "ONYX"])
            noun = random.choice(["PEAK", "RIVER", "GATE", "BRIDGE", "COAST", "RIDGE",
                                 "VALLEY", "HARBOR", "MOUNTAIN", "CREEK", "CANYON", "BAY"])
            suffix = random.choice(["HOLDINGS", "TRADING", "LOGISTICS", "ENTERPRISES",
                                   "SHIPPING", "CAPITAL", "INDUSTRIES", "VENTURES"])
            name = f"{adj} {noun} {suffix}"
            if name not in names:
                names.append(name)

        # Country distribution: 30% Middle East/Central Asia, 30% Africa, 40% other
        me_ca_countries = ["Fictional Republic of Zaristan", "North Kaldavia",
                          "Greater Turkmenabad", "East Qalamistan", "Republic of Durvania"]
        african_countries = ["Republic of Bandara", "North Zamunda", "Kaluvia",
                           "Republic of Marothi", "East Gondwana"]
        other_countries = ["Novaria", "Republic of Eastholm", "South Valdoria",
                         "West Karelian Republic", "Republic of Meridia", "Borealian Federation"]

        for i in range(count):
            name = names[i] if i < len(names) else f"ENTITY_{i}"
            list_type = random.choice(WATCHLIST_TYPES)
            entity_type = random.choice(ENTITY_TYPES)
            programs = random.sample(WATCHLIST_PROGRAMS, random.randint(1, 3))

            # Country assignment
            roll = random.random()
            if roll < 0.30:
                country = random.choice(me_ca_countries)
            elif roll < 0.60:
                country = random.choice(african_countries)
            else:
                country = random.choice(other_countries)

            # Aliases
            alias_count = random.randint(1, 3)
            aliases = []
            for _ in range(alias_count):
                if entity_type == "INDIVIDUAL":
                    aliases.append(self.fake.name())
                else:
                    aliases.append(f"{random.choice(['GLOBAL', 'INTERNATIONAL', 'PACIFIC', 'ATLANTIC'])} {name.split()[1]} LTD")

            rec = {
                'entity_id': f"WL-{700000 + i:06d}",
                'entity_name': name,
                'list_type': list_type,
                'designation_date': self.fake.date_between(start_date='-10y', end_date='today').isoformat(),
                'programs': json.dumps(programs),
                'country': country,
                'aliases': json.dumps(aliases),
                'entity_type': entity_type,
                'created_at': self.fake.date_time_between(start_date='-10y', end_date='now').isoformat(),
                '_SOURCE_SYSTEM': self.SYSTEM_NAME,
                '_ROW_HASH': None,
            }
            rec['_ROW_HASH'] = self._hash(rec)
            records.append(rec)

        return records

    # ------------------------------------------------------------------
    # SARS (Suspicious Activity Reports)
    # ------------------------------------------------------------------
    def generate_sars(self, count: int) -> List[Dict]:
        if not self.customers:
            raise ValueError("Must generate customers first")
        print(f"  Generating {count} SARs...")
        records = []

        # Narratives templates
        narratives = [
            "Customer conducted {txn_count} transactions totaling ${amount:,.0f} over {days} days, all to same beneficiary in amounts below $3,000",
            "Multiple customers using same device sent funds to single beneficiary in {country}, total ${amount:,.0f}",
            "Customer received and immediately forwarded ${amount:,.0f} from {count} different sources within 24 hours",
            "Account holder's transaction pattern changed dramatically: volume increased {mult}x over 30-day baseline",
            "Identity documents appear altered; customer unable to verify source of funds totaling ${amount:,.0f}",
            "Series of rapid-fire transactions totaling ${amount:,.0f} sent to high-risk corridor within {hours} hours",
            "Customer's stated occupation inconsistent with transaction volume of ${amount:,.0f}/month",
            "Funnel account pattern detected: {count} unrelated senders directing funds through single account",
        ]

        for i in range(count):
            customer = random.choice(self.customers)
            activity_type = random.choice(SAR_ACTIVITY_TYPES)
            filing_status = self._weighted_choice(SAR_FILING_STATUSES, SAR_FILING_WEIGHTS)
            amount = random.uniform(5000, 500000)
            txn_count = random.randint(5, 50)

            # Generate narrative
            narrative_template = random.choice(narratives)
            narrative = narrative_template.format(
                txn_count=txn_count,
                amount=amount,
                days=random.randint(3, 30),
                country=random.choice([c[0] for c in RECEIVER_COUNTRIES]),
                count=random.randint(3, 15),
                mult=random.randint(3, 10),
                hours=random.randint(2, 48),
            )

            filing_date = self.fake.date_between(start_date='-2y', end_date='today')

            rec = {
                'sar_id': f"SAR-{800000 + i:06d}",
                'customer_id': customer['customer_id'],
                'filing_date': filing_date.isoformat(),
                'suspicious_activity_type': activity_type,
                'narrative_summary': narrative,
                'amount_involved': round(amount, 2),
                'transaction_count': txn_count,
                'filing_status': filing_status,
                'investigator_id': f"INV-{random.randint(100, 999)}",
                'created_at': datetime.combine(filing_date, datetime.min.time()).isoformat(),
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
        data['customers'] = self.generate_customers(counts.get('customers', 50000))
        data['beneficiaries'] = self.generate_beneficiaries(counts.get('beneficiaries', 30000))
        data['agents'] = self.generate_agents(counts.get('agents', 5000))
        data['corridors'] = self.generate_corridors(counts.get('corridors', 100))
        data['transactions'] = self.generate_transactions(counts.get('transactions', 200000))
        data['devices'] = self.generate_devices(counts.get('devices', 20000))
        data['watchlist_entities'] = self.generate_watchlist_entities(counts.get('watchlist_entities', 200))
        data['sars'] = self.generate_sars(counts.get('sars', 500))
        return data


# ============================================================================
# OUTPUT — delegates to base data_generator.save_to_csv
# ============================================================================

def save_to_csv(data: Dict[str, List[Dict]], output_dir: str):
    """Save using the base data_generator's save_to_csv (unchanged)."""
    base_save_to_csv(data, output_dir, "FINTECH_PAYMENTS")


# ============================================================================
# CLI
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Generate Fintech cross-border payments data for Snowflake DCA demo",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python generate_fintech_data.py --output ../data
  python generate_fintech_data.py --output ../data --quick
  python generate_fintech_data.py --output ../data --scale 2.0
  python generate_fintech_data.py --output ../data --seed 123
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
    print("FINTECH CROSS-BORDER PAYMENTS DATA GENERATOR")
    print("=" * 60)
    print(f"  Seed:   {args.seed}")
    print(f"  Scale:  {'quick (10%)' if args.quick else f'{args.scale}x'}")
    print(f"  Output: {args.output}")
    print(f"  Counts: {counts}")
    print()

    generator = FintechGenerator(seed=args.seed)
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
