#!/usr/bin/env python3
"""
Enterprise Source System Data Generator for Snowflake DCA Demo

This generator creates realistic synthetic data that MIRRORS actual source systems:
  - SAP ECC/S4HANA - German field naming, MANDT client, standard tables
  - Oracle EBS - Oracle naming conventions, standard modules
  - Salesforce - API field names, SF ID format, standard objects
  - ServiceNow - ServiceNow table structure and sys_id format
  - FHIR R4 - HL7 FHIR healthcare resources
  - Workday - Workday HCM field conventions

Each system generator produces data with:
  - Authentic field names matching the real system
  - Proper data formats and ID conventions
  - Realistic relationships and hierarchies
  - System-specific metadata columns

Usage:
    # SAP S/4HANA Customer Master (KNA1)
    python data_generator.py --system sap --domain customers --output ../data
    
    # Salesforce Accounts and Opportunities
    python data_generator.py --system salesforce --domain sales --output ../data
    
    # Oracle EBS Order Management
    python data_generator.py --system oracle --domain orders --output ../data
    
    # FHIR R4 Patient Resources
    python data_generator.py --system fhir --domain patients --output ../data
    
    # Workday HCM Workers
    python data_generator.py --system workday --domain workers --output ../data

For Snowflake deployment:
    Upload generated files to a stage and use COPY INTO for bulk loading.
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
from typing import List, Dict, Any, Optional, Tuple
from dataclasses import dataclass, field, asdict
from abc import ABC, abstractmethod

# ============================================================================
# FAKER SETUP
# ============================================================================

try:
    from faker import Faker
    from faker.providers import BaseProvider
except ImportError:
    print("ERROR: Faker not installed. Run: pip install faker")
    sys.exit(1)

# ============================================================================
# BASE GENERATOR CLASS
# ============================================================================

class SourceSystemGenerator(ABC):
    """Abstract base class for source system generators"""
    
    SYSTEM_NAME = "GENERIC"
    
    def __init__(self, seed: int = 42):
        self.seed = seed
        random.seed(seed)
        self.fake = Faker()
        self.fake.seed_instance(seed)
        
        # Multi-locale fakers for diverse names
        self.fakers = {}
        for i, locale in enumerate(['en_US', 'de_DE', 'fr_FR', 'es_ES', 'ja_JP', 'zh_CN', 'pt_BR']):
            try:
                f = Faker(locale)
                f.seed_instance(seed + i)
                self.fakers[locale] = f
            except:
                pass
        
        self.data = {}
    
    def _get_faker(self, locale: str = 'en_US') -> Faker:
        return self.fakers.get(locale, self.fake)
    
    def _calculate_hash(self, data: Dict) -> str:
        """Calculate row hash for SCD Type 2"""
        hash_data = {k: v for k, v in data.items() if not k.startswith('_')}
        hash_str = json.dumps(hash_data, sort_keys=True, default=str)
        return hashlib.sha256(hash_str.encode()).hexdigest()
    
    @abstractmethod
    def generate(self, counts: Dict[str, int]) -> Dict[str, List[Dict]]:
        """Generate all data for this system"""
        pass
    
    def get_metadata_columns(self) -> Dict[str, Any]:
        """Return standard metadata columns for SCD Type 2"""
        return {
            '_LOADED_AT': datetime.now().isoformat(),
            '_SOURCE_SYSTEM': self.SYSTEM_NAME,
            '_ROW_HASH': None,  # Calculated per row
            '_IS_CURRENT': True,
            '_VALID_FROM': datetime.now().isoformat(),
            '_VALID_TO': '9999-12-31T00:00:00'
        }


# ============================================================================
# SAP GENERATOR
# ============================================================================

class SAPGenerator(SourceSystemGenerator):
    """
    SAP ECC/S/4HANA Data Generator
    
    Generates data matching SAP standard tables:
      - KNA1: Customer Master (General)
      - KNVV: Customer Master (Sales)
      - MARA: Material Master (General)
      - VBAK: Sales Document Header
      - VBAP: Sales Document Item
      - PA0001: HR Master - Org Assignment
      - PA0002: HR Master - Personal Data
    
    SAP Conventions:
      - MANDT: Client number (3 digits)
      - German abbreviations (KUNNR=Customer Number, MATNR=Material Number)
      - Date format: YYYYMMDD
      - Packed numbers for amounts
    """
    
    SYSTEM_NAME = "SAP_S4HANA"
    
    def __init__(self, seed: int = 42, mandt: str = "100"):
        super().__init__(seed)
        self.mandt = mandt  # SAP Client
        
        # SAP-specific value sets
        self.sales_orgs = ['1000', '1100', '2000', '3000']
        self.dist_channels = ['10', '20', '30']
        self.divisions = ['00', '10', '20']
        self.plants = ['1000', '1100', '2000', '2100', '3000']
        self.company_codes = ['1000', '2000', '3000']
        self.countries = ['US', 'DE', 'GB', 'FR', 'JP', 'CN']
        self.currencies = ['USD', 'EUR', 'GBP', 'JPY', 'CNY']
    
    def _sap_date(self, d: date) -> str:
        """Convert date to SAP format YYYYMMDD"""
        return d.strftime('%Y%m%d')
    
    def _sap_customer_id(self, seq: int) -> str:
        """Generate SAP customer number (10 digits, zero-padded)"""
        return f"{seq:010d}"
    
    def _sap_material_id(self, seq: int) -> str:
        """Generate SAP material number (18 chars)"""
        return f"MAT{seq:015d}"
    
    def _sap_doc_number(self, seq: int) -> str:
        """Generate SAP document number (10 digits)"""
        return f"{seq:010d}"
    
    def generate_kna1(self, count: int) -> List[Dict]:
        """Generate SAP KNA1 - Customer Master (General Data)"""
        print(f"Generating SAP KNA1 (Customer Master): {count:,} records...")
        records = []
        
        for i in range(count):
            country = random.choice(self.countries)
            faker = self._get_faker('de_DE' if country == 'DE' else 'en_US')
            
            record = {
                # Key fields
                'MANDT': self.mandt,
                'KUNNR': self._sap_customer_id(i + 1),
                
                # General data
                'NAME1': faker.company()[:35],
                'NAME2': faker.company_suffix()[:35] if random.random() > 0.7 else '',
                'SORTL': faker.company()[:10].upper(),
                'STRAS': faker.street_address()[:35],
                'ORT01': faker.city()[:35],
                'PSTLZ': faker.postcode()[:10],
                'LAND1': country,
                'REGIO': faker.state_abbr() if country == 'US' else '',
                'SPRAS': 'E' if country != 'DE' else 'D',
                
                # Communication
                'TELF1': faker.phone_number()[:16],
                'TELFX': faker.phone_number()[:16] if random.random() > 0.5 else '',
                'SMTP_ADDR': faker.company_email()[:241],
                
                # Control data
                'KTOKD': random.choice(['0001', '0002', 'CPDA']),  # Account group
                'ERDAT': self._sap_date(self.fake.date_between(start_date='-5y', end_date='today')),
                'ERNAM': f"USER{random.randint(1, 100):03d}",
                'LOEVM': '',  # Deletion flag
                'SPERR': '',  # Central block
                'AUFSD': '',  # Order block
                
                # Industry/Classification
                'BRSCH': random.choice(['0001', '0002', '0003', '0004', '0005']),
                'KUKLA': random.choice(['01', '02', '03']),  # Customer classification
                
                # Tax
                'STCEG': f"{country}{random.randint(100000000, 999999999)}" if random.random() > 0.3 else '',
            }
            
            record['_SOURCE_TABLE'] = 'KNA1'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records
    
    def generate_mara(self, count: int) -> List[Dict]:
        """Generate SAP MARA - Material Master (General Data)"""
        print(f"Generating SAP MARA (Material Master): {count:,} records...")
        records = []
        
        material_types = ['FERT', 'HALB', 'ROH', 'HAWA', 'DIEN']  # Finished, Semi, Raw, Trading, Service
        material_groups = ['001', '002', '003', '004', '005', '006']
        uoms = ['EA', 'KG', 'L', 'M', 'PC', 'ST']
        
        for i in range(count):
            mtart = random.choice(material_types)
            
            record = {
                # Key fields
                'MANDT': self.mandt,
                'MATNR': self._sap_material_id(i + 1),
                
                # Basic data
                'MTART': mtart,  # Material type
                'MATKL': random.choice(material_groups),  # Material group
                'MBRSH': random.choice(['M', 'C', 'P']),  # Industry sector
                'MEINS': random.choice(uoms),  # Base unit
                'BSTME': random.choice(uoms),  # Order unit
                
                # Description
                'MAKTX': f"{self.fake.word().title()} {random.choice(['Pro', 'Plus', 'Max', 'Standard'])} {self.fake.word().title()}"[:40],
                
                # Weights
                'BRGEW': round(random.uniform(0.1, 100), 3) if mtart in ['FERT', 'HALB', 'ROH'] else 0,
                'NTGEW': round(random.uniform(0.1, 100), 3) if mtart in ['FERT', 'HALB', 'ROH'] else 0,
                'GEWEI': 'KG',
                
                # Dimensions  
                'VOLUM': round(random.uniform(0.001, 10), 3) if mtart in ['FERT', 'HALB'] else 0,
                'VOLEH': 'M3',
                
                # Control
                'LVORM': '',  # Deletion flag
                'ERSDA': self._sap_date(self.fake.date_between(start_date='-3y', end_date='today')),
                'ERNAM': f"USER{random.randint(1, 100):03d}",
                
                # Classification
                'PRDHA': f"{random.randint(1,9)}{random.randint(0,9)}{random.randint(0,9)}00000",  # Product hierarchy
            }
            
            record['_SOURCE_TABLE'] = 'MARA'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records
    
    def generate_vbak(self, count: int, customer_ids: List[str]) -> List[Dict]:
        """Generate SAP VBAK - Sales Document Header"""
        print(f"Generating SAP VBAK (Sales Orders): {count:,} records...")
        records = []
        
        doc_types = ['TA', 'OR', 'SO', 'RE']  # Standard order types
        
        for i in range(count):
            vkorg = random.choice(self.sales_orgs)
            audat = self.fake.date_between(start_date='-2y', end_date='today')
            
            record = {
                # Key fields
                'MANDT': self.mandt,
                'VBELN': self._sap_doc_number(i + 1),
                
                # Organizational data
                'VKORG': vkorg,
                'VTWEG': random.choice(self.dist_channels),
                'SPART': random.choice(self.divisions),
                'VKBUR': f"{vkorg[:2]}01",  # Sales office
                'VKGRP': f"{random.randint(1, 20):03d}",  # Sales group
                
                # Document data
                'AUART': random.choice(doc_types),
                'AUDAT': self._sap_date(audat),
                'ERDAT': self._sap_date(audat),
                'ERZET': f"{random.randint(0, 23):02d}{random.randint(0, 59):02d}{random.randint(0, 59):02d}",
                'ERNAM': f"USER{random.randint(1, 100):03d}",
                
                # Partners
                'KUNNR': random.choice(customer_ids) if customer_ids else self._sap_customer_id(random.randint(1, 1000)),
                
                # Status
                'GBSTK': random.choice(['A', 'B', 'C']),  # Overall status
                'NETWR': round(random.uniform(100, 50000), 2),  # Net value
                'WAERK': random.choice(self.currencies),
                
                # Dates
                'VDATU': self._sap_date(audat + timedelta(days=random.randint(1, 30))),  # Requested delivery
                'BSTNK': f"PO-{random.randint(100000, 999999)}",  # Customer PO
            }
            
            record['_SOURCE_TABLE'] = 'VBAK'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records
    
    def generate_pa0001(self, count: int) -> List[Dict]:
        """Generate SAP PA0001 - HR Master Organizational Assignment"""
        print(f"Generating SAP PA0001 (HR Org Assignment): {count:,} records...")
        records = []
        
        for i in range(count):
            begda = self.fake.date_between(start_date='-15y', end_date='today')
            
            record = {
                # Key fields
                'MANDT': self.mandt,
                'PERNR': f"{i + 1:08d}",  # Personnel number
                'SUBTY': '0',  # Subtype
                'OBJPS': '',
                'SPRPS': '',
                'ENDDA': '99991231',
                'BEGDA': self._sap_date(begda),
                'SEQNR': '000',
                
                # Organizational data
                'BUKRS': random.choice(self.company_codes),
                'WERKS': random.choice(self.plants),
                'PERSG': random.choice(['1', '2', '3']),  # Employee group
                'PERSK': random.choice(['01', '02', '03', '04']),  # Employee subgroup
                'KOSTL': f"CC{random.randint(1000, 9999)}",  # Cost center
                'ORGEH': f"{random.randint(10000000, 99999999)}",  # Org unit
                'PLANS': f"{random.randint(10000000, 99999999)}",  # Position
                'STELL': f"{random.randint(10000000, 99999999)}",  # Job
                
                # Administrative
                'BTRTL': random.choice(['0001', '0002', '0003']),  # Personnel subarea
                'ABKRS': random.choice(['01', '02', 'M1']),  # Payroll area
            }
            
            record['_SOURCE_TABLE'] = 'PA0001'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate_pa0002(self, count: int, pernr_list: List[str]) -> List[Dict]:
        """Generate SAP PA0002 - HR Personal Data"""
        print(f"Generating SAP PA0002 (HR Personal Data): {count:,} records...")
        records = []
        
        for i, pernr in enumerate(pernr_list[:count]):
            dob = self.fake.date_of_birth(minimum_age=22, maximum_age=65)
            
            record = {
                'MANDT': self.mandt,
                'PERNR': pernr,
                'SUBTY': '0',
                'ENDDA': '99991231',
                'BEGDA': self._sap_date(self.fake.date_between(start_date='-15y', end_date='today')),
                'SEQNR': '000',
                
                'VORNA': self.fake.first_name()[:40],  # First name
                'NACHN': self.fake.last_name()[:40],   # Last name
                'GBDAT': self._sap_date(dob),          # Birth date
                'GESSION': random.choice(['1', '2']),      # Gender
                'FAMST': random.choice(['0', '1', '2', '3']),  # Marital status
                'NATIO': random.choice(['US', 'DE', 'GB', 'FR']),  # Nationality
                'SPRSL': 'E',  # Language
            }
            
            record['_SOURCE_TABLE'] = 'PA0002'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate_lfa1(self, count: int) -> List[Dict]:
        """Generate SAP LFA1 - Vendor Master (General)"""
        print(f"Generating SAP LFA1 (Vendor Master): {count:,} records...")
        records = []
        
        for i in range(count):
            country = random.choice(self.countries)
            faker = self._get_faker('de_DE' if country == 'DE' else 'en_US')
            
            record = {
                'MANDT': self.mandt,
                'LIFNR': f"{i + 1:010d}",  # Vendor number
                
                'NAME1': faker.company()[:35],
                'NAME2': faker.company_suffix()[:35] if random.random() > 0.7 else '',
                'SORTL': faker.company()[:10].upper(),
                'STRAS': faker.street_address()[:35],
                'ORT01': faker.city()[:35],
                'PSTLZ': faker.postcode()[:10],
                'LAND1': country,
                'REGIO': faker.state_abbr() if country == 'US' else '',
                'SPRAS': 'E' if country != 'DE' else 'D',
                
                'TELF1': faker.phone_number()[:16],
                'SMTP_ADDR': faker.company_email()[:241],
                
                'KTOKK': random.choice(['0001', '0002', 'KRED']),  # Account group
                'ERDAT': self._sap_date(self.fake.date_between(start_date='-5y', end_date='today')),
                'ERNAM': f"USER{random.randint(1, 100):03d}",
                'LOEVM': '',
                'SPERR': '',
            }
            
            record['_SOURCE_TABLE'] = 'LFA1'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate_ekko(self, count: int, vendor_ids: List[str]) -> List[Dict]:
        """Generate SAP EKKO - Purchasing Document Header"""
        print(f"Generating SAP EKKO (Purchase Orders): {count:,} records...")
        records = []
        
        for i in range(count):
            bedat = self.fake.date_between(start_date='-2y', end_date='today')
            
            record = {
                'MANDT': self.mandt,
                'EBELN': f"45{i + 1:08d}",  # PO number
                
                'BUKRS': random.choice(self.company_codes),
                'BSTYP': 'F',  # Document category
                'BSART': random.choice(['NB', 'UB', 'FO']),  # Document type
                'BEDAT': self._sap_date(bedat),
                'ERNAM': f"USER{random.randint(1, 100):03d}",
                'LIFNR': random.choice(vendor_ids) if vendor_ids else f"{random.randint(1, 1000):010d}",
                
                'EKORG': random.choice(['1000', '2000']),  # Purchasing org
                'EKGRP': f"{random.randint(1, 50):03d}",   # Purchasing group
                'WAERS': random.choice(self.currencies),
                
                'STATU': random.choice(['I', 'A', 'C']),  # Status
                'RLWRT': round(random.uniform(1000, 100000), 2),  # Total value
            }
            
            record['_SOURCE_TABLE'] = 'EKKO'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate_bkpf(self, count: int) -> List[Dict]:
        """Generate SAP BKPF - Accounting Document Header"""
        print(f"Generating SAP BKPF (FI Documents): {count:,} records...")
        records = []
        
        for i in range(count):
            budat = self.fake.date_between(start_date='-2y', end_date='today')
            
            record = {
                'MANDT': self.mandt,
                'BUKRS': random.choice(self.company_codes),
                'BELNR': f"{i + 1:010d}",
                'GJAHR': budat.year,
                
                'BLART': random.choice(['SA', 'AB', 'KR', 'RE', 'DA']),  # Document type
                'BUDAT': self._sap_date(budat),
                'BLDAT': self._sap_date(budat - timedelta(days=random.randint(0, 5))),
                'MONAT': budat.month,
                'CPUDT': self._sap_date(budat),
                'USNAM': f"USER{random.randint(1, 100):03d}",
                
                'WAERS': random.choice(self.currencies),
                'XBLNR': f"REF{random.randint(100000, 999999)}",
                'BKTXT': f"Document {self.fake.word()}"[:25],
                
                'STBLG': '',  # Reversal doc
                'BSTAT': '',  # Status
            }
            
            record['_SOURCE_TABLE'] = 'BKPF'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate_vbap(self, count: int, order_ids: List[str], material_ids: List[str]) -> List[Dict]:
        """Generate SAP VBAP - Sales Document Item"""
        print(f"Generating SAP VBAP (Sales Order Items): {count:,} records...")
        records = []
        
        for i in range(count):
            record = {
                'MANDT': self.mandt,
                'VBELN': random.choice(order_ids) if order_ids else self._sap_doc_number(random.randint(1, 1000)),
                'POSNR': f"{(i % 10 + 1) * 10:06d}",  # Item number
                
                'MATNR': random.choice(material_ids) if material_ids else self._sap_material_id(random.randint(1, 500)),
                'ARKTX': f"{self.fake.word().title()} Product"[:40],
                'KWMENG': round(random.uniform(1, 100), 0),
                'VRKME': random.choice(['EA', 'PC', 'KG']),
                
                'NETWR': round(random.uniform(100, 10000), 2),
                'WAERK': random.choice(self.currencies),
                'NETPR': round(random.uniform(10, 1000), 2),
                
                'WERKS': random.choice(self.plants),
                'LGORT': random.choice(['0001', '0002', '0003']),
                
                'ABGRU': '' if random.random() > 0.1 else random.choice(['01', '02']),  # Rejection reason
            }
            
            record['_SOURCE_TABLE'] = 'VBAP'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate(self, counts: Dict[str, int]) -> Dict[str, List[Dict]]:
        """Generate all SAP data"""
        result = {}
        
        # Customer Master
        if counts.get('customers', 0) > 0:
            kna1 = self.generate_kna1(counts['customers'])
            result['KNA1'] = kna1
            customer_ids = [r['KUNNR'] for r in kna1]
        else:
            customer_ids = [self._sap_customer_id(i) for i in range(1, 101)]
        
        # Material Master
        if counts.get('products', 0) > 0:
            mara = self.generate_mara(counts['products'])
            result['MARA'] = mara
            material_ids = [r['MATNR'] for r in mara]
        else:
            material_ids = [self._sap_material_id(i) for i in range(1, 101)]
        
        # Sales Orders
        if counts.get('orders', 0) > 0:
            vbak = self.generate_vbak(counts['orders'], customer_ids)
            result['VBAK'] = vbak
            order_ids = [r['VBELN'] for r in vbak]
            
            # Order line items (3x orders)
            vbap = self.generate_vbap(counts['orders'] * 3, order_ids, material_ids)
            result['VBAP'] = vbap
        
        # HR Data
        if counts.get('employees', 0) > 0:
            pa0001 = self.generate_pa0001(counts['employees'])
            result['PA0001'] = pa0001
            pernr_list = [r['PERNR'] for r in pa0001]
            
            pa0002 = self.generate_pa0002(counts['employees'], pernr_list)
            result['PA0002'] = pa0002
        
        # Vendor Master
        if counts.get('vendors', 0) > 0:
            lfa1 = self.generate_lfa1(counts['vendors'])
            result['LFA1'] = lfa1
            vendor_ids = [r['LIFNR'] for r in lfa1]
            
            # Purchase Orders
            if counts.get('purchase_orders', 0) > 0:
                ekko = self.generate_ekko(counts['purchase_orders'], vendor_ids)
                result['EKKO'] = ekko
        
        # Finance Documents
        if counts.get('fi_documents', 0) > 0:
            bkpf = self.generate_bkpf(counts['fi_documents'])
            result['BKPF'] = bkpf
        
        return result


# ============================================================================
# SALESFORCE GENERATOR
# ============================================================================

class SalesforceGenerator(SourceSystemGenerator):
    """
    Salesforce Data Generator
    
    Generates data matching Salesforce standard objects:
      - Account: Company/organization records
      - Contact: People associated with accounts
      - Opportunity: Sales deals
      - Lead: Prospective customers
      - Case: Support cases
      - User: Salesforce users
    
    Salesforce Conventions:
      - 18-character case-insensitive IDs
      - API field names (CamelCase)
      - Record Types, Owner references
      - Standard picklist values
    """
    
    SYSTEM_NAME = "SALESFORCE"
    
    def __init__(self, seed: int = 42, org_id: str = "00D5f000000XXXX"):
        super().__init__(seed)
        self.org_id = org_id
    
    def _sf_id(self, prefix: str = "001") -> str:
        """Generate Salesforce-style 18-character ID"""
        # Format: 3-char prefix + 12 random alphanum + 3 checksum
        chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
        base = prefix + ''.join(random.choice(chars) for _ in range(12))
        # Simplified checksum (real SF uses case-fold algorithm)
        checksum = ''.join(random.choice('ABCDEFGHIJKLMNOPQRSTUVWXYZ') for _ in range(3))
        return base + checksum
    
    def _sf_datetime(self, dt: datetime = None) -> str:
        """Format datetime for Salesforce (ISO 8601)"""
        if dt is None:
            dt = datetime.now()
        return dt.strftime('%Y-%m-%dT%H:%M:%S.000Z')
    
    def generate_account(self, count: int) -> List[Dict]:
        """Generate Salesforce Account records"""
        print(f"Generating Salesforce Account: {count:,} records...")
        records = []
        
        industries = [
            'Agriculture', 'Apparel', 'Banking', 'Biotechnology', 'Chemicals',
            'Communications', 'Construction', 'Consulting', 'Education', 'Electronics',
            'Energy', 'Engineering', 'Entertainment', 'Environmental', 'Finance',
            'Food & Beverage', 'Government', 'Healthcare', 'Hospitality', 'Insurance',
            'Machinery', 'Manufacturing', 'Media', 'Not For Profit', 'Recreation',
            'Retail', 'Shipping', 'Technology', 'Telecommunications', 'Transportation',
            'Utilities', 'Other'
        ]
        
        types = ['Prospect', 'Customer - Direct', 'Customer - Channel', 'Channel Partner / Reseller', 
                 'Installation Partner', 'Technology Partner', 'Other']
        
        ratings = ['Hot', 'Warm', 'Cold']
        
        for i in range(count):
            created_date = self.fake.date_time_between(start_date='-5y', end_date='now')
            
            record = {
                # System fields
                'Id': self._sf_id('001'),
                'IsDeleted': False,
                'CreatedDate': self._sf_datetime(created_date),
                'CreatedById': self._sf_id('005'),
                'LastModifiedDate': self._sf_datetime(created_date + timedelta(days=random.randint(0, 365))),
                'LastModifiedById': self._sf_id('005'),
                'SystemModstamp': self._sf_datetime(),
                
                # Account fields
                'Name': self.fake.company(),
                'Type': random.choice(types),
                'Industry': random.choice(industries),
                'AnnualRevenue': round(random.uniform(100000, 100000000), 2) if random.random() > 0.3 else None,
                'NumberOfEmployees': random.randint(1, 10000) if random.random() > 0.2 else None,
                'Rating': random.choice(ratings),
                
                # Address
                'BillingStreet': self.fake.street_address(),
                'BillingCity': self.fake.city(),
                'BillingState': self.fake.state_abbr(),
                'BillingPostalCode': self.fake.postcode(),
                'BillingCountry': 'United States',
                
                'ShippingStreet': self.fake.street_address(),
                'ShippingCity': self.fake.city(),
                'ShippingState': self.fake.state_abbr(),
                'ShippingPostalCode': self.fake.postcode(),
                'ShippingCountry': 'United States',
                
                # Contact info
                'Phone': self.fake.phone_number(),
                'Fax': self.fake.phone_number() if random.random() > 0.7 else None,
                'Website': f"https://www.{self.fake.domain_name()}",
                
                # Ownership
                'OwnerId': self._sf_id('005'),
                
                # Custom fields (example)
                'Customer_Segment__c': random.choice(['Enterprise', 'Mid-Market', 'SMB', 'Startup']),
                'Lifecycle_Stage__c': random.choice(['Lead', 'Prospect', 'Customer', 'Churned']),
            }
            
            record['_SOURCE_TABLE'] = 'Account'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records
    
    def generate_contact(self, count: int, account_ids: List[str]) -> List[Dict]:
        """Generate Salesforce Contact records"""
        print(f"Generating Salesforce Contact: {count:,} records...")
        records = []
        
        salutations = ['Mr.', 'Ms.', 'Mrs.', 'Dr.', 'Prof.', None]
        lead_sources = ['Web', 'Phone Inquiry', 'Partner Referral', 'Purchased List', 
                       'Trade Show', 'Employee Referral', 'External Referral', 'Other']
        
        for i in range(count):
            created_date = self.fake.date_time_between(start_date='-5y', end_date='now')
            
            record = {
                # System fields
                'Id': self._sf_id('003'),
                'IsDeleted': False,
                'CreatedDate': self._sf_datetime(created_date),
                'CreatedById': self._sf_id('005'),
                'LastModifiedDate': self._sf_datetime(created_date + timedelta(days=random.randint(0, 365))),
                'LastModifiedById': self._sf_id('005'),
                
                # Relationships
                'AccountId': random.choice(account_ids) if account_ids else None,
                'OwnerId': self._sf_id('005'),
                
                # Name
                'Salutation': random.choice(salutations),
                'FirstName': self.fake.first_name(),
                'LastName': self.fake.last_name(),
                'Title': self.fake.job()[:80],
                'Department': random.choice(['Sales', 'Marketing', 'Engineering', 'Finance', 'HR', 'Operations', None]),
                
                # Contact info
                'Email': self.fake.company_email(),
                'Phone': self.fake.phone_number(),
                'MobilePhone': self.fake.phone_number() if random.random() > 0.4 else None,
                
                # Address
                'MailingStreet': self.fake.street_address(),
                'MailingCity': self.fake.city(),
                'MailingState': self.fake.state_abbr(),
                'MailingPostalCode': self.fake.postcode(),
                'MailingCountry': 'United States',
                
                # Other
                'LeadSource': random.choice(lead_sources),
                'Birthdate': str(self.fake.date_of_birth(minimum_age=22, maximum_age=70)) if random.random() > 0.7 else None,
                'HasOptedOutOfEmail': random.random() < 0.05,
            }
            
            record['_SOURCE_TABLE'] = 'Contact'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records
    
    def generate_opportunity(self, count: int, account_ids: List[str]) -> List[Dict]:
        """Generate Salesforce Opportunity records"""
        print(f"Generating Salesforce Opportunity: {count:,} records...")
        records = []
        
        stages = [
            ('Prospecting', 10),
            ('Qualification', 20),
            ('Needs Analysis', 30),
            ('Value Proposition', 40),
            ('Id. Decision Makers', 50),
            ('Perception Analysis', 60),
            ('Proposal/Price Quote', 70),
            ('Negotiation/Review', 80),
            ('Closed Won', 100),
            ('Closed Lost', 0)
        ]
        
        types = ['Existing Customer - Upgrade', 'Existing Customer - Replacement', 
                 'Existing Customer - Downgrade', 'New Customer']
        
        for i in range(count):
            created_date = self.fake.date_time_between(start_date='-2y', end_date='now')
            stage_name, probability = random.choice(stages)
            close_date = created_date + timedelta(days=random.randint(30, 180))
            
            record = {
                # System fields
                'Id': self._sf_id('006'),
                'IsDeleted': False,
                'CreatedDate': self._sf_datetime(created_date),
                'CreatedById': self._sf_id('005'),
                'LastModifiedDate': self._sf_datetime(created_date + timedelta(days=random.randint(0, 90))),
                
                # Relationships
                'AccountId': random.choice(account_ids) if account_ids else None,
                'OwnerId': self._sf_id('005'),
                
                # Opportunity fields
                'Name': f"{self.fake.company()} - {random.choice(['Q1', 'Q2', 'Q3', 'Q4'])} Deal",
                'Amount': round(random.uniform(5000, 500000), 2),
                'CloseDate': close_date.strftime('%Y-%m-%d'),
                'StageName': stage_name,
                'Probability': probability,
                'Type': random.choice(types),
                
                # Tracking
                'LeadSource': random.choice(['Web', 'Partner', 'Trade Show', 'Cold Call', 'Referral']),
                'NextStep': random.choice(['Send proposal', 'Schedule demo', 'Follow up call', 'Contract review', None]),
                'Description': self.fake.paragraph(nb_sentences=2) if random.random() > 0.5 else None,
                
                # Status
                'IsClosed': stage_name in ['Closed Won', 'Closed Lost'],
                'IsWon': stage_name == 'Closed Won',
                'ForecastCategory': 'Pipeline' if probability < 50 else ('Best Case' if probability < 80 else 'Commit'),
                
                # Fiscal
                'FiscalQuarter': random.randint(1, 4),
                'FiscalYear': created_date.year,
            }
            
            record['_SOURCE_TABLE'] = 'Opportunity'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records
    
    def generate_case(self, count: int, account_ids: List[str], contact_ids: List[str]) -> List[Dict]:
        """Generate Salesforce Case records"""
        print(f"Generating Salesforce Case: {count:,} records...")
        records = []
        
        statuses = ['New', 'Working', 'Escalated', 'Closed']
        priorities = ['Low', 'Medium', 'High', 'Critical']
        types = ['Mechanical', 'Electrical', 'Electronic', 'Structural', 'Other']
        origins = ['Email', 'Phone', 'Web', 'Chat']
        
        for i in range(count):
            created_date = self.fake.date_time_between(start_date='-1y', end_date='now')
            status = random.choice(statuses)
            
            record = {
                'Id': self._sf_id('500'),
                'IsDeleted': False,
                'CaseNumber': f"{10000 + i:08d}",
                'CreatedDate': self._sf_datetime(created_date),
                'ClosedDate': self._sf_datetime(created_date + timedelta(days=random.randint(1, 30))) if status == 'Closed' else None,
                
                'AccountId': random.choice(account_ids) if account_ids else None,
                'ContactId': random.choice(contact_ids) if contact_ids else None,
                'OwnerId': self._sf_id('005'),
                
                'Subject': f"Issue with {self.fake.word()} - {random.choice(['Error', 'Question', 'Request', 'Problem'])}",
                'Description': self.fake.paragraph(nb_sentences=3),
                'Status': status,
                'Priority': random.choice(priorities),
                'Type': random.choice(types),
                'Origin': random.choice(origins),
                
                'IsClosed': status == 'Closed',
                'IsEscalated': status == 'Escalated',
            }
            
            record['_SOURCE_TABLE'] = 'Case'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records
    
    def generate_lead(self, count: int) -> List[Dict]:
        """Generate Salesforce Lead records"""
        print(f"Generating Salesforce Lead: {count:,} records...")
        records = []
        
        statuses = ['Open - Not Contacted', 'Working - Contacted', 'Closed - Converted', 'Closed - Not Converted']
        ratings = ['Hot', 'Warm', 'Cold']
        
        for i in range(count):
            created_date = self.fake.date_time_between(start_date='-1y', end_date='now')
            status = random.choice(statuses)
            
            record = {
                'Id': self._sf_id('00Q'),
                'IsDeleted': False,
                'CreatedDate': self._sf_datetime(created_date),
                'CreatedById': self._sf_id('005'),
                
                'LastName': self.fake.last_name(),
                'FirstName': self.fake.first_name(),
                'Salutation': random.choice(['Mr.', 'Ms.', 'Mrs.', 'Dr.', None]),
                'Title': self.fake.job()[:80],
                'Company': self.fake.company(),
                
                'Email': self.fake.company_email(),
                'Phone': self.fake.phone_number(),
                'MobilePhone': self.fake.phone_number() if random.random() > 0.5 else None,
                'Website': f"https://www.{self.fake.domain_name()}" if random.random() > 0.5 else None,
                
                'Street': self.fake.street_address(),
                'City': self.fake.city(),
                'State': self.fake.state_abbr(),
                'PostalCode': self.fake.postcode(),
                'Country': 'United States',
                
                'Status': status,
                'LeadSource': random.choice(['Web', 'Phone Inquiry', 'Partner Referral', 'Trade Show', 'Other']),
                'Rating': random.choice(ratings),
                'Industry': random.choice(['Technology', 'Healthcare', 'Finance', 'Manufacturing', 'Retail']),
                'NumberOfEmployees': random.randint(10, 5000) if random.random() > 0.3 else None,
                'AnnualRevenue': round(random.uniform(100000, 50000000), 2) if random.random() > 0.4 else None,
                
                'IsConverted': status == 'Closed - Converted',
                'ConvertedDate': created_date.strftime('%Y-%m-%d') if status == 'Closed - Converted' else None,
                'ConvertedAccountId': self._sf_id('001') if status == 'Closed - Converted' else None,
                'ConvertedContactId': self._sf_id('003') if status == 'Closed - Converted' else None,
                
                'OwnerId': self._sf_id('005'),
            }
            
            record['_SOURCE_TABLE'] = 'Lead'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate_product(self, count: int) -> List[Dict]:
        """Generate Salesforce Product2 records"""
        print(f"Generating Salesforce Product2: {count:,} records...")
        records = []
        
        families = ['Hardware', 'Software', 'Service', 'Subscription', 'Support', 'Training']
        
        for i in range(count):
            created_date = self.fake.date_time_between(start_date='-3y', end_date='now')
            
            record = {
                'Id': self._sf_id('01t'),
                'IsDeleted': False,
                'CreatedDate': self._sf_datetime(created_date),
                
                'Name': f"{self.fake.word().title()} {random.choice(['Pro', 'Plus', 'Enterprise', 'Standard'])}",
                'ProductCode': f"SKU-{random.randint(10000, 99999)}",
                'Description': self.fake.paragraph(nb_sentences=2),
                'Family': random.choice(families),
                
                'IsActive': random.random() > 0.1,
                'QuantityUnitOfMeasure': random.choice(['Each', 'License', 'Hour', 'Month']),
                
                'StockKeepingUnit': f"SKU{i+1:06d}",
            }
            
            record['_SOURCE_TABLE'] = 'Product2'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate_campaign(self, count: int) -> List[Dict]:
        """Generate Salesforce Campaign records"""
        print(f"Generating Salesforce Campaign: {count:,} records...")
        records = []
        
        types = ['Conference', 'Webinar', 'Trade Show', 'Public Relations', 'Partners', 'Referral Program', 'Email', 'Advertising']
        statuses = ['Planned', 'In Progress', 'Completed', 'Aborted']
        
        for i in range(count):
            start_date = self.fake.date_between(start_date='-1y', end_date='+3m')
            
            record = {
                'Id': self._sf_id('701'),
                'IsDeleted': False,
                'CreatedDate': self._sf_datetime(self.fake.date_time_between(start_date='-2y', end_date='now')),
                
                'Name': f"{self.fake.word().title()} {random.choice(['Summit', 'Launch', 'Campaign', 'Initiative'])} {start_date.year}",
                'Type': random.choice(types),
                'Status': random.choice(statuses),
                
                'StartDate': start_date.strftime('%Y-%m-%d'),
                'EndDate': (start_date + timedelta(days=random.randint(1, 90))).strftime('%Y-%m-%d'),
                
                'BudgetedCost': round(random.uniform(5000, 100000), 2),
                'ActualCost': round(random.uniform(5000, 100000), 2) if random.random() > 0.3 else None,
                'ExpectedRevenue': round(random.uniform(50000, 500000), 2),
                
                'NumberSent': random.randint(100, 10000),
                'ExpectedResponse': round(random.uniform(1, 10), 2),
                
                'IsActive': random.random() > 0.2,
                'OwnerId': self._sf_id('005'),
            }
            
            record['_SOURCE_TABLE'] = 'Campaign'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate_task(self, count: int, account_ids: List[str], contact_ids: List[str]) -> List[Dict]:
        """Generate Salesforce Task records"""
        print(f"Generating Salesforce Task: {count:,} records...")
        records = []
        
        subjects = ['Call', 'Email', 'Send Quote', 'Send Letter', 'Follow Up', 'Meeting', 'Other']
        statuses = ['Not Started', 'In Progress', 'Completed', 'Waiting on someone else', 'Deferred']
        priorities = ['High', 'Normal', 'Low']
        
        for i in range(count):
            created_date = self.fake.date_time_between(start_date='-6m', end_date='now')
            status = random.choice(statuses)
            
            record = {
                'Id': self._sf_id('00T'),
                'IsDeleted': False,
                'CreatedDate': self._sf_datetime(created_date),
                
                'WhoId': random.choice(contact_ids) if contact_ids and random.random() > 0.3 else None,
                'WhatId': random.choice(account_ids) if account_ids and random.random() > 0.3 else None,
                'OwnerId': self._sf_id('005'),
                
                'Subject': random.choice(subjects),
                'Status': status,
                'Priority': random.choice(priorities),
                
                'ActivityDate': (created_date + timedelta(days=random.randint(1, 30))).strftime('%Y-%m-%d'),
                'Description': self.fake.paragraph(nb_sentences=1) if random.random() > 0.5 else None,
                
                'IsClosed': status == 'Completed',
                'IsHighPriority': random.random() < 0.2,
                'IsRecurrence': False,
            }
            
            record['_SOURCE_TABLE'] = 'Task'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate(self, counts: Dict[str, int]) -> Dict[str, List[Dict]]:
        """Generate all Salesforce data"""
        result = {}
        
        # Accounts
        if counts.get('accounts', 0) > 0:
            accounts = self.generate_account(counts['accounts'])
            result['Account'] = accounts
            account_ids = [r['Id'] for r in accounts]
        else:
            account_ids = []
        
        # Contacts
        if counts.get('contacts', 0) > 0:
            contacts = self.generate_contact(counts['contacts'], account_ids)
            result['Contact'] = contacts
            contact_ids = [r['Id'] for r in contacts]
        else:
            contact_ids = []
        
        # Opportunities
        if counts.get('opportunities', 0) > 0:
            opportunities = self.generate_opportunity(counts['opportunities'], account_ids)
            result['Opportunity'] = opportunities
        
        # Cases
        if counts.get('cases', 0) > 0:
            cases = self.generate_case(counts['cases'], account_ids, contact_ids)
            result['Case'] = cases
        
        # Leads
        if counts.get('leads', 0) > 0:
            leads = self.generate_lead(counts['leads'])
            result['Lead'] = leads
        
        # Products
        if counts.get('products', 0) > 0:
            products = self.generate_product(counts['products'])
            result['Product2'] = products
        
        # Campaigns
        if counts.get('campaigns', 0) > 0:
            campaigns = self.generate_campaign(counts['campaigns'])
            result['Campaign'] = campaigns
        
        # Tasks
        if counts.get('tasks', 0) > 0:
            tasks = self.generate_task(counts['tasks'], account_ids, contact_ids)
            result['Task'] = tasks
        
        return result


# ============================================================================
# ORACLE EBS GENERATOR
# ============================================================================

class OracleEBSGenerator(SourceSystemGenerator):
    """
    Oracle E-Business Suite Data Generator
    
    Generates data matching Oracle EBS standard tables:
      - HZ_PARTIES: TCA Party master
      - HZ_CUST_ACCOUNTS: Customer accounts
      - OE_ORDER_HEADERS_ALL: Order headers
      - OE_ORDER_LINES_ALL: Order lines
      - HR_ALL_PEOPLE_F: Employee master
    
    Oracle Conventions:
      - _ID suffix for primary keys
      - _ALL suffix for multi-org tables
      - WHO columns (CREATED_BY, CREATION_DATE, etc.)
      - ORG_ID for operating unit
    """
    
    SYSTEM_NAME = "ORACLE_EBS"
    
    def __init__(self, seed: int = 42, org_id: int = 204):
        super().__init__(seed)
        self.org_id = org_id
    
    def _oracle_id(self) -> int:
        """Generate Oracle-style sequence ID"""
        return random.randint(100000, 99999999)
    
    def _who_columns(self, created_date: datetime = None) -> Dict:
        """Return Oracle WHO audit columns"""
        if created_date is None:
            created_date = datetime.now()
        return {
            'CREATED_BY': random.randint(1, 1000),
            'CREATION_DATE': created_date.strftime('%Y-%m-%d %H:%M:%S'),
            'LAST_UPDATED_BY': random.randint(1, 1000),
            'LAST_UPDATE_DATE': (created_date + timedelta(days=random.randint(0, 30))).strftime('%Y-%m-%d %H:%M:%S'),
            'LAST_UPDATE_LOGIN': random.randint(1, 100000),
        }
    
    def generate_hz_parties(self, count: int) -> List[Dict]:
        """Generate Oracle HZ_PARTIES - Trading Community Architecture Party"""
        print(f"Generating Oracle HZ_PARTIES: {count:,} records...")
        records = []
        
        party_types = ['ORGANIZATION', 'PERSON']
        
        for i in range(count):
            party_type = random.choice(party_types)
            created_date = self.fake.date_time_between(start_date='-5y', end_date='now')
            
            record = {
                'PARTY_ID': self._oracle_id(),
                'PARTY_NUMBER': f"P{i+1:08d}",
                'PARTY_NAME': self.fake.company() if party_type == 'ORGANIZATION' else self.fake.name(),
                'PARTY_TYPE': party_type,
                'STATUS': random.choice(['A', 'I']),  # Active/Inactive
                
                # Address
                'ADDRESS1': self.fake.street_address(),
                'ADDRESS2': self.fake.secondary_address() if random.random() > 0.7 else None,
                'CITY': self.fake.city(),
                'STATE': self.fake.state_abbr(),
                'POSTAL_CODE': self.fake.postcode(),
                'COUNTRY': 'US',
                
                # Classification
                'CATEGORY_CODE': random.choice(['CUSTOMER', 'PROSPECT', 'PARTNER']),
                'SIC_CODE': str(random.randint(1000, 9999)),
                'DUNS_NUMBER': str(random.randint(100000000, 999999999)) if random.random() > 0.5 else None,
            }
            
            record.update(self._who_columns(created_date))
            record['_SOURCE_TABLE'] = 'HZ_PARTIES'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records
    
    def generate_oe_order_headers(self, count: int, party_ids: List[int]) -> List[Dict]:
        """Generate Oracle OE_ORDER_HEADERS_ALL"""
        print(f"Generating Oracle OE_ORDER_HEADERS_ALL: {count:,} records...")
        records = []
        
        order_types = [1000, 1001, 1002, 1003]  # Standard, Rush, Return, Blanket
        
        for i in range(count):
            order_date = self.fake.date_time_between(start_date='-2y', end_date='now')
            
            record = {
                'HEADER_ID': self._oracle_id(),
                'ORDER_NUMBER': i + 100000,
                'ORG_ID': self.org_id,
                
                'ORDERED_DATE': order_date.strftime('%Y-%m-%d %H:%M:%S'),
                'ORDER_TYPE_ID': random.choice(order_types),
                
                'SOLD_TO_ORG_ID': random.choice(party_ids) if party_ids else self._oracle_id(),
                'SHIP_TO_ORG_ID': random.choice(party_ids) if party_ids else self._oracle_id(),
                'INVOICE_TO_ORG_ID': random.choice(party_ids) if party_ids else self._oracle_id(),
                
                'TRANSACTIONAL_CURR_CODE': random.choice(['USD', 'EUR', 'GBP']),
                'FLOW_STATUS_CODE': random.choice(['ENTERED', 'BOOKED', 'CLOSED', 'CANCELLED']),
                'BOOKED_FLAG': 'Y' if random.random() > 0.2 else 'N',
                
                'SALESREP_ID': random.randint(1, 100),
                'PRICE_LIST_ID': random.randint(1000, 1010),
                'PAYMENT_TERM_ID': random.randint(1, 10),
                
                'SHIPPING_METHOD_CODE': random.choice(['GROUND', 'AIR', 'EXPRESS', 'FREIGHT']),
                'FREIGHT_TERMS_CODE': random.choice(['PREPAID', 'COLLECT', 'PREPAIDANDBILLCUST']),
            }
            
            record.update(self._who_columns(order_date))
            record['_SOURCE_TABLE'] = 'OE_ORDER_HEADERS_ALL'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records
    
    def generate_hr_all_people(self, count: int) -> List[Dict]:
        """Generate Oracle HR_ALL_PEOPLE_F - Employee Master"""
        print(f"Generating Oracle HR_ALL_PEOPLE_F: {count:,} records...")
        records = []
        
        for i in range(count):
            hire_date = self.fake.date_between(start_date='-15y', end_date='today')
            dob = self.fake.date_of_birth(minimum_age=22, maximum_age=65)
            
            record = {
                'PERSON_ID': self._oracle_id(),
                'EMPLOYEE_NUMBER': f"E{i+1:06d}",
                'BUSINESS_GROUP_ID': random.randint(1, 5),
                
                'EFFECTIVE_START_DATE': hire_date.strftime('%Y-%m-%d'),
                'EFFECTIVE_END_DATE': '4712-12-31',
                
                'FIRST_NAME': self.fake.first_name(),
                'MIDDLE_NAMES': self.fake.first_name() if random.random() > 0.5 else None,
                'LAST_NAME': self.fake.last_name(),
                'FULL_NAME': None,  # Derived
                
                'NATIONAL_IDENTIFIER': f"{random.randint(100,999)}-{random.randint(10,99)}-{random.randint(1000,9999)}",
                'DATE_OF_BIRTH': dob.strftime('%Y-%m-%d'),
                'SEX': random.choice(['M', 'F']),
                'MARITAL_STATUS': random.choice(['S', 'M', 'D', 'W', None]),
                
                'EMAIL_ADDRESS': self.fake.company_email(),
                'CURRENT_EMPLOYEE_FLAG': 'Y' if random.random() > 0.1 else 'N',
                
                'PERSON_TYPE_ID': random.randint(1, 10),
            }
            
            record['FULL_NAME'] = f"{record['LAST_NAME']}, {record['FIRST_NAME']}"
            record.update(self._who_columns(datetime.combine(hire_date, datetime.min.time())))
            record['_SOURCE_TABLE'] = 'HR_ALL_PEOPLE_F'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records
    
    def generate_oe_order_lines(self, count: int, header_ids: List[int]) -> List[Dict]:
        """Generate Oracle OE_ORDER_LINES_ALL"""
        print(f"Generating Oracle OE_ORDER_LINES_ALL: {count:,} records...")
        records = []
        
        for i in range(count):
            order_date = self.fake.date_time_between(start_date='-2y', end_date='now')
            
            record = {
                'LINE_ID': self._oracle_id(),
                'HEADER_ID': random.choice(header_ids) if header_ids else self._oracle_id(),
                'LINE_NUMBER': (i % 10) + 1,
                'ORG_ID': self.org_id,
                
                'ORDERED_ITEM': f"ITEM-{random.randint(10000, 99999)}",
                'INVENTORY_ITEM_ID': random.randint(100000, 999999),
                'ORDERED_QUANTITY': round(random.uniform(1, 100), 0),
                'ORDER_QUANTITY_UOM': random.choice(['Ea', 'Kg', 'Lb', 'Cs']),
                
                'UNIT_SELLING_PRICE': round(random.uniform(10, 1000), 2),
                'UNIT_LIST_PRICE': round(random.uniform(10, 1000), 2),
                
                'SCHEDULE_SHIP_DATE': order_date.strftime('%Y-%m-%d'),
                'ACTUAL_SHIPMENT_DATE': (order_date + timedelta(days=random.randint(1, 7))).strftime('%Y-%m-%d') if random.random() > 0.3 else None,
                
                'FLOW_STATUS_CODE': random.choice(['ENTERED', 'AWAITING_SHIPPING', 'SHIPPED', 'CLOSED']),
                'CANCELLED_FLAG': 'N' if random.random() > 0.05 else 'Y',
            }
            
            record.update(self._who_columns(order_date))
            record['_SOURCE_TABLE'] = 'OE_ORDER_LINES_ALL'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate_ap_invoices(self, count: int, vendor_ids: List[int]) -> List[Dict]:
        """Generate Oracle AP_INVOICES_ALL - Payables Invoices"""
        print(f"Generating Oracle AP_INVOICES_ALL: {count:,} records...")
        records = []
        
        for i in range(count):
            invoice_date = self.fake.date_time_between(start_date='-2y', end_date='now')
            
            record = {
                'INVOICE_ID': self._oracle_id(),
                'INVOICE_NUM': f"INV-{i+1:08d}",
                'ORG_ID': self.org_id,
                
                'VENDOR_ID': random.choice(vendor_ids) if vendor_ids else self._oracle_id(),
                'VENDOR_SITE_ID': self._oracle_id(),
                
                'INVOICE_DATE': invoice_date.strftime('%Y-%m-%d'),
                'INVOICE_AMOUNT': round(random.uniform(100, 100000), 2),
                'INVOICE_CURRENCY_CODE': random.choice(['USD', 'EUR', 'GBP']),
                
                'INVOICE_TYPE_LOOKUP_CODE': random.choice(['STANDARD', 'CREDIT', 'DEBIT', 'PREPAYMENT']),
                'SOURCE': random.choice(['Manual', 'SelfService', 'ERS']),
                
                'TERMS_ID': random.randint(1, 10),
                'TERMS_DATE': invoice_date.strftime('%Y-%m-%d'),
                'PAYMENT_STATUS_FLAG': random.choice(['Y', 'N', 'P']),
                
                'APPROVAL_STATUS': random.choice(['APPROVED', 'NEEDS REAPPROVAL', 'NEVER APPROVED']),
                'CANCELLED_DATE': None,
            }
            
            record.update(self._who_columns(invoice_date))
            record['_SOURCE_TABLE'] = 'AP_INVOICES_ALL'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate_ar_invoices(self, count: int, party_ids: List[int]) -> List[Dict]:
        """Generate Oracle RA_CUSTOMER_TRX_ALL - Receivables Invoices"""
        print(f"Generating Oracle RA_CUSTOMER_TRX_ALL: {count:,} records...")
        records = []
        
        for i in range(count):
            trx_date = self.fake.date_time_between(start_date='-2y', end_date='now')
            
            record = {
                'CUSTOMER_TRX_ID': self._oracle_id(),
                'TRX_NUMBER': f"AR-{i+1:08d}",
                'ORG_ID': self.org_id,
                
                'BILL_TO_CUSTOMER_ID': random.choice(party_ids) if party_ids else self._oracle_id(),
                'SHIP_TO_CUSTOMER_ID': random.choice(party_ids) if party_ids else self._oracle_id(),
                
                'TRX_DATE': trx_date.strftime('%Y-%m-%d'),
                'INVOICE_CURRENCY_CODE': random.choice(['USD', 'EUR', 'GBP']),
                
                'CUST_TRX_TYPE_ID': random.randint(1, 10),
                'COMPLETE_FLAG': 'Y' if random.random() > 0.1 else 'N',
                'STATUS_TRX': random.choice(['OP', 'CL', 'VD']),  # Open, Closed, Void
                
                'TERM_ID': random.randint(1, 10),
                'PRIMARY_SALESREP_ID': random.randint(1, 100),
            }
            
            record.update(self._who_columns(trx_date))
            record['_SOURCE_TABLE'] = 'RA_CUSTOMER_TRX_ALL'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate_gl_je_lines(self, count: int) -> List[Dict]:
        """Generate Oracle GL_JE_LINES - General Ledger Journal Lines"""
        print(f"Generating Oracle GL_JE_LINES: {count:,} records...")
        records = []
        
        for i in range(count):
            effective_date = self.fake.date_between(start_date='-2y', end_date='today')
            
            record = {
                'JE_HEADER_ID': self._oracle_id(),
                'JE_LINE_NUM': (i % 20) + 1,
                'LEDGER_ID': random.randint(1, 5),
                
                'CODE_COMBINATION_ID': self._oracle_id(),
                'PERIOD_NAME': f"{effective_date.strftime('%b').upper()}-{effective_date.year % 100:02d}",
                'EFFECTIVE_DATE': effective_date.strftime('%Y-%m-%d'),
                
                'ENTERED_DR': round(random.uniform(0, 50000), 2) if random.random() > 0.5 else 0,
                'ENTERED_CR': round(random.uniform(0, 50000), 2) if random.random() > 0.5 else 0,
                'ACCOUNTED_DR': round(random.uniform(0, 50000), 2) if random.random() > 0.5 else 0,
                'ACCOUNTED_CR': round(random.uniform(0, 50000), 2) if random.random() > 0.5 else 0,
                
                'CURRENCY_CODE': random.choice(['USD', 'EUR', 'GBP']),
                'STATUS': random.choice(['U', 'P']),  # Unposted, Posted
                
                'DESCRIPTION': f"Journal entry {self.fake.word()}"[:240],
            }
            
            record.update(self._who_columns(datetime.combine(effective_date, datetime.min.time())))
            record['_SOURCE_TABLE'] = 'GL_JE_LINES'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate_po_vendors(self, count: int) -> List[Dict]:
        """Generate Oracle AP_SUPPLIERS (PO_VENDORS)"""
        print(f"Generating Oracle AP_SUPPLIERS: {count:,} records...")
        records = []
        
        for i in range(count):
            created_date = self.fake.date_time_between(start_date='-5y', end_date='now')
            
            record = {
                'VENDOR_ID': self._oracle_id(),
                'VENDOR_NAME': self.fake.company(),
                'SEGMENT1': f"V{i+1:06d}",  # Vendor number
                
                'VENDOR_TYPE_LOOKUP_CODE': random.choice(['SUPPLIER', 'CONTRACTOR', 'EMPLOYEE']),
                'ENABLED_FLAG': 'Y' if random.random() > 0.1 else 'N',
                
                'NUM_1099': f"{random.randint(10,99)}-{random.randint(1000000,9999999)}" if random.random() > 0.5 else None,
                'VAT_CODE': None,
                
                'PAYMENT_METHOD_LOOKUP_CODE': random.choice(['CHECK', 'EFT', 'WIRE']),
                'PAY_GROUP_LOOKUP_CODE': random.choice(['STANDARD', 'PRIORITY']),
                'PAYMENT_PRIORITY': random.randint(1, 99),
                
                'TERMS_ID': random.randint(1, 10),
            }
            
            record.update(self._who_columns(created_date))
            record['_SOURCE_TABLE'] = 'AP_SUPPLIERS'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate_mtl_system_items(self, count: int) -> List[Dict]:
        """Generate Oracle MTL_SYSTEM_ITEMS_B - Inventory Items"""
        print(f"Generating Oracle MTL_SYSTEM_ITEMS_B: {count:,} records...")
        records = []
        
        for i in range(count):
            created_date = self.fake.date_time_between(start_date='-3y', end_date='now')
            
            record = {
                'INVENTORY_ITEM_ID': self._oracle_id(),
                'ORGANIZATION_ID': random.randint(1, 5),
                'SEGMENT1': f"ITEM-{i+1:06d}",
                
                'DESCRIPTION': f"{self.fake.word().title()} {random.choice(['Standard', 'Premium', 'Basic'])}"[:240],
                'PRIMARY_UOM_CODE': random.choice(['Ea', 'Kg', 'Lb', 'Cs', 'Pk']),
                
                'ITEM_TYPE': random.choice(['I', 'K', 'M', 'O', 'P']),  # Inventory, Kit, Model, Option, Purchased
                'INVENTORY_ITEM_FLAG': 'Y',
                'STOCK_ENABLED_FLAG': 'Y' if random.random() > 0.2 else 'N',
                'PURCHASING_ENABLED_FLAG': 'Y',
                'CUSTOMER_ORDER_ENABLED_FLAG': 'Y' if random.random() > 0.3 else 'N',
                
                'LIST_PRICE_PER_UNIT': round(random.uniform(10, 1000), 2),
                'UNIT_WEIGHT': round(random.uniform(0.1, 100), 2) if random.random() > 0.3 else None,
                'WEIGHT_UOM_CODE': 'Lb',
            }
            
            record.update(self._who_columns(created_date))
            record['_SOURCE_TABLE'] = 'MTL_SYSTEM_ITEMS_B'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate(self, counts: Dict[str, int]) -> Dict[str, List[Dict]]:
        """Generate all Oracle EBS data"""
        result = {}
        
        # TCA Parties (Customers)
        if counts.get('customers', 0) > 0:
            parties = self.generate_hz_parties(counts['customers'])
            result['HZ_PARTIES'] = parties
            party_ids = [r['PARTY_ID'] for r in parties]
        else:
            party_ids = []
        
        # Vendors/Suppliers
        if counts.get('vendors', 0) > 0:
            vendors = self.generate_po_vendors(counts['vendors'])
            result['AP_SUPPLIERS'] = vendors
            vendor_ids = [r['VENDOR_ID'] for r in vendors]
        else:
            vendor_ids = []
        
        # Inventory Items
        if counts.get('products', 0) > 0:
            items = self.generate_mtl_system_items(counts['products'])
            result['MTL_SYSTEM_ITEMS_B'] = items
        
        # Sales Orders
        if counts.get('orders', 0) > 0:
            orders = self.generate_oe_order_headers(counts['orders'], party_ids)
            result['OE_ORDER_HEADERS_ALL'] = orders
            header_ids = [r['HEADER_ID'] for r in orders]
            
            # Order Lines (3x orders)
            lines = self.generate_oe_order_lines(counts['orders'] * 3, header_ids)
            result['OE_ORDER_LINES_ALL'] = lines
        
        # HR Employees
        if counts.get('employees', 0) > 0:
            employees = self.generate_hr_all_people(counts['employees'])
            result['HR_ALL_PEOPLE_F'] = employees
        
        # AP Invoices
        if counts.get('ap_invoices', 0) > 0:
            ap_invoices = self.generate_ap_invoices(counts['ap_invoices'], vendor_ids)
            result['AP_INVOICES_ALL'] = ap_invoices
        
        # AR Invoices
        if counts.get('ar_invoices', 0) > 0:
            ar_invoices = self.generate_ar_invoices(counts['ar_invoices'], party_ids)
            result['RA_CUSTOMER_TRX_ALL'] = ar_invoices
        
        # GL Journal Lines
        if counts.get('gl_entries', 0) > 0:
            gl_lines = self.generate_gl_je_lines(counts['gl_entries'])
            result['GL_JE_LINES'] = gl_lines
        
        return result


# ============================================================================
# FHIR R4 GENERATOR
# ============================================================================

class FHIRGenerator(SourceSystemGenerator):
    """
    HL7 FHIR R4 Data Generator
    
    Generates FHIR resources:
      - Patient: Individual receiving care
      - Practitioner: Healthcare provider
      - Organization: Hospital/clinic
      - Encounter: Patient visit
      - Condition: Diagnosis
      - Observation: Lab results, vitals
    
    FHIR Conventions:
      - resourceType field
      - id as UUID
      - reference format: "ResourceType/id"
      - CodeableConcept for coded values
    """
    
    SYSTEM_NAME = "FHIR_R4"
    
    def __init__(self, seed: int = 42):
        super().__init__(seed)
        
        # ICD-10 codes (simplified)
        self.conditions = [
            ('J06.9', 'Acute upper respiratory infection'),
            ('M54.5', 'Low back pain'),
            ('E11.9', 'Type 2 diabetes mellitus'),
            ('I10', 'Essential hypertension'),
            ('J45.909', 'Unspecified asthma'),
            ('F32.9', 'Major depressive disorder'),
            ('K21.0', 'Gastro-esophageal reflux disease'),
            ('G43.909', 'Migraine'),
        ]
        
        # LOINC codes for observations
        self.observations = [
            ('8867-4', 'Heart rate', 'beats/min', 60, 100),
            ('8310-5', 'Body temperature', 'Cel', 36.1, 37.2),
            ('8480-6', 'Systolic blood pressure', 'mm[Hg]', 90, 140),
            ('8462-4', 'Diastolic blood pressure', 'mm[Hg]', 60, 90),
            ('2339-0', 'Glucose', 'mg/dL', 70, 110),
            ('2093-3', 'Cholesterol', 'mg/dL', 150, 240),
        ]
    
    def _fhir_id(self) -> str:
        """Generate FHIR-style UUID"""
        return str(uuid.uuid4())
    
    def _fhir_reference(self, resource_type: str, id: str) -> Dict:
        """Create FHIR reference"""
        return {'reference': f"{resource_type}/{id}"}
    
    def _codeable_concept(self, system: str, code: str, display: str) -> Dict:
        """Create FHIR CodeableConcept"""
        return {
            'coding': [{
                'system': system,
                'code': code,
                'display': display
            }],
            'text': display
        }
    
    def generate_patient(self, count: int) -> List[Dict]:
        """Generate FHIR Patient resources"""
        print(f"Generating FHIR Patient: {count:,} resources...")
        records = []
        
        for i in range(count):
            dob = self.fake.date_of_birth(minimum_age=0, maximum_age=100)
            
            record = {
                'resourceType': 'Patient',
                'id': self._fhir_id(),
                
                'identifier': [{
                    'system': 'http://hospital.org/mrn',
                    'value': f"MRN{i+1:08d}"
                }, {
                    'system': 'http://hl7.org/fhir/sid/us-ssn',
                    'value': f"{random.randint(100,999)}-{random.randint(10,99)}-{random.randint(1000,9999)}"
                }],
                
                'active': True,
                
                'name': [{
                    'use': 'official',
                    'family': self.fake.last_name(),
                    'given': [self.fake.first_name(), self.fake.first_name()[0] + '.'],
                }],
                
                'telecom': [{
                    'system': 'phone',
                    'value': self.fake.phone_number(),
                    'use': 'home'
                }, {
                    'system': 'email',
                    'value': self.fake.email()
                }],
                
                'gender': random.choice(['male', 'female', 'other', 'unknown']),
                'birthDate': dob.strftime('%Y-%m-%d'),
                
                'address': [{
                    'use': 'home',
                    'line': [self.fake.street_address()],
                    'city': self.fake.city(),
                    'state': self.fake.state_abbr(),
                    'postalCode': self.fake.postcode(),
                    'country': 'US'
                }],
                
                'maritalStatus': self._codeable_concept(
                    'http://terminology.hl7.org/CodeSystem/v3-MaritalStatus',
                    random.choice(['S', 'M', 'D', 'W']),
                    random.choice(['Never Married', 'Married', 'Divorced', 'Widowed'])
                ),
                
                'communication': [{
                    'language': self._codeable_concept(
                        'urn:ietf:bcp:47', 'en', 'English'
                    ),
                    'preferred': True
                }],
            }
            
            record['_SOURCE_TABLE'] = 'Patient'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records
    
    def generate_encounter(self, count: int, patient_ids: List[str]) -> List[Dict]:
        """Generate FHIR Encounter resources"""
        print(f"Generating FHIR Encounter: {count:,} resources...")
        records = []
        
        classes = [
            ('AMB', 'ambulatory'),
            ('IMP', 'inpatient'),
            ('EMER', 'emergency'),
            ('HH', 'home health')
        ]
        
        for i in range(count):
            start = self.fake.date_time_between(start_date='-2y', end_date='now')
            enc_class = random.choice(classes)
            
            record = {
                'resourceType': 'Encounter',
                'id': self._fhir_id(),
                
                'status': random.choice(['planned', 'arrived', 'in-progress', 'finished', 'cancelled']),
                
                'class': {
                    'system': 'http://terminology.hl7.org/CodeSystem/v3-ActCode',
                    'code': enc_class[0],
                    'display': enc_class[1]
                },
                
                'type': [self._codeable_concept(
                    'http://snomed.info/sct',
                    '308335008',
                    'Patient encounter procedure'
                )],
                
                'subject': self._fhir_reference('Patient', random.choice(patient_ids)),
                
                'period': {
                    'start': start.strftime('%Y-%m-%dT%H:%M:%S+00:00'),
                    'end': (start + timedelta(hours=random.randint(1, 72))).strftime('%Y-%m-%dT%H:%M:%S+00:00')
                },
                
                'reasonCode': [self._codeable_concept(
                    'http://snomed.info/sct',
                    '183452005',
                    'General medical examination'
                )],
            }
            
            record['_SOURCE_TABLE'] = 'Encounter'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records
    
    def generate_condition(self, count: int, patient_ids: List[str], encounter_ids: List[str]) -> List[Dict]:
        """Generate FHIR Condition resources (diagnoses)"""
        print(f"Generating FHIR Condition: {count:,} resources...")
        records = []
        
        for i in range(count):
            code, display = random.choice(self.conditions)
            onset = self.fake.date_between(start_date='-5y', end_date='today')
            
            record = {
                'resourceType': 'Condition',
                'id': self._fhir_id(),
                
                'clinicalStatus': self._codeable_concept(
                    'http://terminology.hl7.org/CodeSystem/condition-clinical',
                    random.choice(['active', 'recurrence', 'relapse', 'inactive', 'remission', 'resolved']),
                    'Active'
                ),
                
                'verificationStatus': self._codeable_concept(
                    'http://terminology.hl7.org/CodeSystem/condition-ver-status',
                    random.choice(['confirmed', 'provisional', 'differential']),
                    'Confirmed'
                ),
                
                'category': [self._codeable_concept(
                    'http://terminology.hl7.org/CodeSystem/condition-category',
                    'encounter-diagnosis',
                    'Encounter Diagnosis'
                )],
                
                'severity': self._codeable_concept(
                    'http://snomed.info/sct',
                    random.choice(['24484000', '6736007', '255604002']),
                    random.choice(['Severe', 'Moderate', 'Mild'])
                ),
                
                'code': self._codeable_concept(
                    'http://hl7.org/fhir/sid/icd-10-cm',
                    code,
                    display
                ),
                
                'subject': self._fhir_reference('Patient', random.choice(patient_ids)),
                'encounter': self._fhir_reference('Encounter', random.choice(encounter_ids)) if encounter_ids else None,
                
                'onsetDateTime': onset.strftime('%Y-%m-%d'),
            }
            
            record['_SOURCE_TABLE'] = 'Condition'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records
    
    def generate_observation(self, count: int, patient_ids: List[str]) -> List[Dict]:
        """Generate FHIR Observation resources (vitals, labs)"""
        print(f"Generating FHIR Observation: {count:,} resources...")
        records = []
        
        for i in range(count):
            obs = random.choice(self.observations)
            code, display, unit, min_val, max_val = obs
            value = round(random.uniform(min_val, max_val), 1)
            
            record = {
                'resourceType': 'Observation',
                'id': self._fhir_id(),
                
                'status': random.choice(['final', 'preliminary', 'amended']),
                
                'category': [self._codeable_concept(
                    'http://terminology.hl7.org/CodeSystem/observation-category',
                    'vital-signs',
                    'Vital Signs'
                )],
                
                'code': self._codeable_concept(
                    'http://loinc.org',
                    code,
                    display
                ),
                
                'subject': self._fhir_reference('Patient', random.choice(patient_ids)),
                
                'effectiveDateTime': self.fake.date_time_between(start_date='-1y', end_date='now').strftime('%Y-%m-%dT%H:%M:%S+00:00'),
                
                'valueQuantity': {
                    'value': value,
                    'unit': unit,
                    'system': 'http://unitsofmeasure.org',
                    'code': unit
                },
                
                'interpretation': [self._codeable_concept(
                    'http://terminology.hl7.org/CodeSystem/v3-ObservationInterpretation',
                    'N' if min_val <= value <= max_val else ('H' if value > max_val else 'L'),
                    'Normal' if min_val <= value <= max_val else ('High' if value > max_val else 'Low')
                )],
            }
            
            record['_SOURCE_TABLE'] = 'Observation'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records
    
    def generate_practitioner(self, count: int) -> List[Dict]:
        """Generate FHIR Practitioner resources"""
        print(f"Generating FHIR Practitioner: {count:,} resources...")
        records = []
        
        specialties = [
            ('394802001', 'General medicine'),
            ('394585009', 'Obstetrics and gynecology'),
            ('394582007', 'Dermatology'),
            ('394579002', 'Cardiology'),
            ('394587001', 'Psychiatry'),
            ('394583002', 'Endocrinology'),
        ]
        
        for i in range(count):
            specialty = random.choice(specialties)
            
            record = {
                'resourceType': 'Practitioner',
                'id': self._fhir_id(),
                
                'identifier': [{
                    'system': 'http://hl7.org/fhir/sid/us-npi',
                    'value': f"{random.randint(1000000000, 9999999999)}"
                }],
                
                'active': True,
                
                'name': [{
                    'use': 'official',
                    'family': self.fake.last_name(),
                    'given': [self.fake.first_name()],
                    'prefix': [random.choice(['Dr.', 'MD', 'DO'])]
                }],
                
                'telecom': [{
                    'system': 'phone',
                    'value': self.fake.phone_number(),
                    'use': 'work'
                }, {
                    'system': 'email',
                    'value': self.fake.company_email()
                }],
                
                'gender': random.choice(['male', 'female']),
                
                'qualification': [{
                    'code': self._codeable_concept(
                        'http://snomed.info/sct',
                        specialty[0],
                        specialty[1]
                    )
                }],
            }
            
            record['_SOURCE_TABLE'] = 'Practitioner'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate_organization(self, count: int) -> List[Dict]:
        """Generate FHIR Organization resources"""
        print(f"Generating FHIR Organization: {count:,} resources...")
        records = []
        
        types = [
            ('prov', 'Healthcare Provider'),
            ('dept', 'Hospital Department'),
            ('ins', 'Insurance Company'),
            ('pay', 'Payer'),
        ]
        
        for i in range(count):
            org_type = random.choice(types)
            
            record = {
                'resourceType': 'Organization',
                'id': self._fhir_id(),
                
                'identifier': [{
                    'system': 'http://hl7.org/fhir/sid/us-npi',
                    'value': f"{random.randint(1000000000, 9999999999)}"
                }],
                
                'active': True,
                
                'type': [self._codeable_concept(
                    'http://terminology.hl7.org/CodeSystem/organization-type',
                    org_type[0],
                    org_type[1]
                )],
                
                'name': f"{self.fake.city()} {random.choice(['Medical Center', 'Hospital', 'Health System', 'Clinic'])}",
                
                'telecom': [{
                    'system': 'phone',
                    'value': self.fake.phone_number()
                }],
                
                'address': [{
                    'line': [self.fake.street_address()],
                    'city': self.fake.city(),
                    'state': self.fake.state_abbr(),
                    'postalCode': self.fake.postcode(),
                    'country': 'US'
                }],
            }
            
            record['_SOURCE_TABLE'] = 'Organization'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate_medication_request(self, count: int, patient_ids: List[str], practitioner_ids: List[str]) -> List[Dict]:
        """Generate FHIR MedicationRequest resources"""
        print(f"Generating FHIR MedicationRequest: {count:,} resources...")
        records = []
        
        medications = [
            ('197361', 'Lisinopril 10 MG Oral Tablet'),
            ('310965', 'Metformin hydrochloride 500 MG Oral Tablet'),
            ('314076', 'Omeprazole 20 MG Delayed Release Oral Capsule'),
            ('197319', 'Amlodipine 5 MG Oral Tablet'),
            ('311989', 'Atorvastatin 20 MG Oral Tablet'),
            ('311995', 'Levothyroxine Sodium 0.05 MG Oral Tablet'),
        ]
        
        for i in range(count):
            med = random.choice(medications)
            authored = self.fake.date_time_between(start_date='-1y', end_date='now')
            
            record = {
                'resourceType': 'MedicationRequest',
                'id': self._fhir_id(),
                
                'status': random.choice(['active', 'completed', 'stopped', 'cancelled']),
                'intent': random.choice(['order', 'proposal', 'plan']),
                
                'medicationCodeableConcept': self._codeable_concept(
                    'http://www.nlm.nih.gov/research/umls/rxnorm',
                    med[0],
                    med[1]
                ),
                
                'subject': self._fhir_reference('Patient', random.choice(patient_ids)),
                'requester': self._fhir_reference('Practitioner', random.choice(practitioner_ids)) if practitioner_ids else None,
                
                'authoredOn': authored.strftime('%Y-%m-%dT%H:%M:%S+00:00'),
                
                'dosageInstruction': [{
                    'text': f"Take {random.randint(1, 2)} tablet(s) by mouth {random.choice(['once', 'twice', 'three times'])} daily",
                    'timing': {
                        'repeat': {
                            'frequency': random.randint(1, 3),
                            'period': 1,
                            'periodUnit': 'd'
                        }
                    },
                    'doseAndRate': [{
                        'doseQuantity': {
                            'value': random.randint(1, 2),
                            'unit': 'tablet',
                            'system': 'http://unitsofmeasure.org',
                            'code': '{tbl}'
                        }
                    }]
                }],
                
                'dispenseRequest': {
                    'numberOfRepeatsAllowed': random.randint(0, 3),
                    'quantity': {
                        'value': random.choice([30, 60, 90]),
                        'unit': 'tablets'
                    }
                },
            }
            
            record['_SOURCE_TABLE'] = 'MedicationRequest'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate_procedure(self, count: int, patient_ids: List[str], encounter_ids: List[str]) -> List[Dict]:
        """Generate FHIR Procedure resources"""
        print(f"Generating FHIR Procedure: {count:,} resources...")
        records = []
        
        procedures = [
            ('80146002', 'Appendectomy'),
            ('73761001', 'Colonoscopy'),
            ('18286008', 'Catheterization of heart'),
            ('387713003', 'Surgical procedure'),
            ('71388002', 'Procedure on lower limb'),
        ]
        
        for i in range(count):
            proc = random.choice(procedures)
            performed = self.fake.date_time_between(start_date='-2y', end_date='now')
            
            record = {
                'resourceType': 'Procedure',
                'id': self._fhir_id(),
                
                'status': random.choice(['completed', 'in-progress', 'not-done', 'stopped']),
                
                'code': self._codeable_concept(
                    'http://snomed.info/sct',
                    proc[0],
                    proc[1]
                ),
                
                'subject': self._fhir_reference('Patient', random.choice(patient_ids)),
                'encounter': self._fhir_reference('Encounter', random.choice(encounter_ids)) if encounter_ids else None,
                
                'performedDateTime': performed.strftime('%Y-%m-%dT%H:%M:%S+00:00'),
                
                'outcome': self._codeable_concept(
                    'http://snomed.info/sct',
                    '385669000',
                    'Successful'
                ) if random.random() > 0.1 else None,
            }
            
            record['_SOURCE_TABLE'] = 'Procedure'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate_claim(self, count: int, patient_ids: List[str], organization_ids: List[str]) -> List[Dict]:
        """Generate FHIR Claim resources"""
        print(f"Generating FHIR Claim: {count:,} resources...")
        records = []
        
        for i in range(count):
            created = self.fake.date_time_between(start_date='-1y', end_date='now')
            
            record = {
                'resourceType': 'Claim',
                'id': self._fhir_id(),
                
                'status': random.choice(['active', 'cancelled', 'draft', 'entered-in-error']),
                'use': random.choice(['claim', 'preauthorization', 'predetermination']),
                
                'type': self._codeable_concept(
                    'http://terminology.hl7.org/CodeSystem/claim-type',
                    random.choice(['institutional', 'professional', 'pharmacy']),
                    'Claim Type'
                ),
                
                'patient': self._fhir_reference('Patient', random.choice(patient_ids)),
                'provider': self._fhir_reference('Organization', random.choice(organization_ids)) if organization_ids else None,
                
                'created': created.strftime('%Y-%m-%d'),
                
                'priority': self._codeable_concept(
                    'http://terminology.hl7.org/CodeSystem/processpriority',
                    random.choice(['stat', 'normal', 'deferred']),
                    'Priority'
                ),
                
                'total': {
                    'value': round(random.uniform(100, 50000), 2),
                    'currency': 'USD'
                },
            }
            
            record['_SOURCE_TABLE'] = 'Claim'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate(self, counts: Dict[str, int]) -> Dict[str, List[Dict]]:
        """Generate all FHIR resources"""
        result = {}
        
        # Patients
        if counts.get('patients', 0) > 0:
            patients = self.generate_patient(counts['patients'])
            result['Patient'] = patients
            patient_ids = [r['id'] for r in patients]
        else:
            patient_ids = []
        
        # Practitioners
        if counts.get('practitioners', 0) > 0:
            practitioners = self.generate_practitioner(counts['practitioners'])
            result['Practitioner'] = practitioners
            practitioner_ids = [r['id'] for r in practitioners]
        else:
            practitioner_ids = []
        
        # Organizations
        if counts.get('organizations', 0) > 0:
            organizations = self.generate_organization(counts['organizations'])
            result['Organization'] = organizations
            organization_ids = [r['id'] for r in organizations]
        else:
            organization_ids = []
        
        # Encounters
        if counts.get('encounters', 0) > 0 and patient_ids:
            encounters = self.generate_encounter(counts['encounters'], patient_ids)
            result['Encounter'] = encounters
            encounter_ids = [r['id'] for r in encounters]
        else:
            encounter_ids = []
        
        # Conditions
        if counts.get('conditions', 0) > 0 and patient_ids:
            conditions = self.generate_condition(counts['conditions'], patient_ids, encounter_ids)
            result['Condition'] = conditions
        
        # Observations
        if counts.get('observations', 0) > 0 and patient_ids:
            observations = self.generate_observation(counts['observations'], patient_ids)
            result['Observation'] = observations
        
        # Medication Requests
        if counts.get('medications', 0) > 0 and patient_ids:
            medications = self.generate_medication_request(counts['medications'], patient_ids, practitioner_ids)
            result['MedicationRequest'] = medications
        
        # Procedures
        if counts.get('procedures', 0) > 0 and patient_ids:
            procedures = self.generate_procedure(counts['procedures'], patient_ids, encounter_ids)
            result['Procedure'] = procedures
        
        # Claims
        if counts.get('claims', 0) > 0 and patient_ids:
            claims = self.generate_claim(counts['claims'], patient_ids, organization_ids)
            result['Claim'] = claims
        
        return result


# ============================================================================
# WORKDAY GENERATOR
# ============================================================================

class WorkdayGenerator(SourceSystemGenerator):
    """
    Workday HCM Data Generator
    
    Generates Workday report-style data:
      - Workers: Employee master
      - Organizations: Supervisory orgs
      - Positions: Job positions
      - Compensation: Pay data
    
    Workday Conventions:
      - WID (Workday ID) format
      - Reference IDs
      - Effective dated records
      - Worker subtypes
    """
    
    SYSTEM_NAME = "WORKDAY"
    
    def __init__(self, seed: int = 42, tenant: str = "company"):
        super().__init__(seed)
        self.tenant = tenant
    
    def _workday_id(self) -> str:
        """Generate Workday-style WID"""
        return f"{uuid.uuid4()}"
    
    def _workday_ref_id(self, prefix: str, seq: int) -> str:
        """Generate Workday Reference ID"""
        return f"{prefix}_{seq:06d}"
    
    def generate_workers(self, count: int) -> List[Dict]:
        """Generate Workday Worker data"""
        print(f"Generating Workday Workers: {count:,} records...")
        records = []
        
        worker_types = ['Employee', 'Contingent Worker']
        pay_types = ['Salary', 'Hourly']
        
        for i in range(count):
            hire_date = self.fake.date_between(start_date='-15y', end_date='today')
            dob = self.fake.date_of_birth(minimum_age=22, maximum_age=65)
            worker_type = random.choice(worker_types)
            
            record = {
                # IDs
                'Worker_WID': self._workday_id(),
                'Worker_ID': self._workday_ref_id('EMP', i + 1),
                'Employee_ID': f"E{i+1:06d}",
                
                # Personal
                'Legal_First_Name': self.fake.first_name(),
                'Legal_Last_Name': self.fake.last_name(),
                'Preferred_First_Name': None,
                'Date_of_Birth': dob.strftime('%Y-%m-%d'),
                'Gender': random.choice(['Male', 'Female', 'Not Declared']),
                'Marital_Status': random.choice(['Single', 'Married', 'Domestic Partner', None]),
                'National_ID': f"{random.randint(100,999)}-{random.randint(10,99)}-{random.randint(1000,9999)}",
                
                # Contact
                'Email_Work': self.fake.company_email(),
                'Email_Personal': self.fake.email() if random.random() > 0.5 else None,
                'Phone_Work': self.fake.phone_number(),
                'Phone_Mobile': self.fake.phone_number() if random.random() > 0.3 else None,
                
                # Address
                'Address_Line_1': self.fake.street_address(),
                'Address_Line_2': self.fake.secondary_address() if random.random() > 0.7 else None,
                'City': self.fake.city(),
                'State_Province': self.fake.state_abbr(),
                'Postal_Code': self.fake.postcode(),
                'Country': 'United States',
                
                # Employment
                'Worker_Type': worker_type,
                'Worker_Sub_Type': 'Regular' if worker_type == 'Employee' else 'Contractor',
                'Hire_Date': hire_date.strftime('%Y-%m-%d'),
                'Original_Hire_Date': hire_date.strftime('%Y-%m-%d'),
                'Continuous_Service_Date': hire_date.strftime('%Y-%m-%d'),
                'Termination_Date': (hire_date + timedelta(days=random.randint(365, 2000))).strftime('%Y-%m-%d') if random.random() < 0.1 else None,
                'Active_Status': 'Active' if random.random() > 0.1 else 'Terminated',
                
                # Job
                'Job_Title': self.fake.job()[:100],
                'Job_Family': random.choice(['Engineering', 'Sales', 'Marketing', 'Finance', 'HR', 'Operations', 'IT', 'Legal']),
                'Job_Level': random.choice(['Individual Contributor', 'Senior', 'Lead', 'Manager', 'Director', 'VP', 'Executive']),
                'Business_Title': self.fake.job()[:100],
                'Work_Location': f"{self.fake.city()} Office",
                
                # Organization
                'Supervisory_Organization_WID': self._workday_id(),
                'Supervisory_Organization_Name': f"{random.choice(['Engineering', 'Sales', 'Marketing', 'Finance'])} - {random.choice(['East', 'West', 'Central', 'Global'])}",
                'Manager_WID': self._workday_id() if random.random() > 0.1 else None,
                'Company_Name': 'ACME Corporation',
                'Cost_Center': f"CC{random.randint(1000, 9999)}",
                
                # Compensation
                'Pay_Rate_Type': random.choice(pay_types),
                'Annual_Salary': round(random.uniform(50000, 250000), 2) if random.random() > 0.3 else None,
                'Hourly_Rate': round(random.uniform(25, 150), 2) if random.random() > 0.7 else None,
                'Currency': 'USD',
                'Compensation_Grade': f"Grade {random.randint(1, 12)}",
                'Pay_Group': random.choice(['Salaried - Exempt', 'Hourly - Non-Exempt', 'Executive']),
                
                # Time
                'Time_Type': random.choice(['Full time', 'Part time']),
                'FTE': 1.0 if random.random() > 0.1 else round(random.uniform(0.5, 0.9), 1),
                
                # Effective Dating
                'Effective_Date': hire_date.strftime('%Y-%m-%d'),
            }
            
            record['_SOURCE_TABLE'] = 'Workers'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records
    
    def generate_organizations(self, count: int) -> List[Dict]:
        """Generate Workday Supervisory Organizations"""
        print(f"Generating Workday Organizations: {count:,} records...")
        records = []
        
        org_types = ['Supervisory', 'Cost Center', 'Region', 'Company', 'Matrix']
        
        for i in range(count):
            record = {
                'Organization_WID': self._workday_id(),
                'Organization_Reference_ID': self._workday_ref_id('ORG', i + 1),
                
                'Organization_Name': f"{random.choice(['Engineering', 'Sales', 'Marketing', 'Finance', 'HR', 'IT', 'Operations', 'Legal'])} - {random.choice(['North', 'South', 'East', 'West', 'Global', 'EMEA', 'APAC'])}",
                'Organization_Code': f"ORG{i+1:04d}",
                'Organization_Type': random.choice(org_types),
                'Organization_Subtype': random.choice(['Department', 'Division', 'Team', 'Group']),
                
                'Superior_Organization_WID': self._workday_id() if random.random() > 0.2 else None,
                'Manager_WID': self._workday_id(),
                
                'Location_WID': self._workday_id(),
                'Company_WID': self._workday_id(),
                
                'Is_Active': random.random() > 0.05,
                'Effective_Date': self.fake.date_between(start_date='-5y', end_date='today').strftime('%Y-%m-%d'),
            }
            
            record['_SOURCE_TABLE'] = 'Organizations'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate_job_profiles(self, count: int) -> List[Dict]:
        """Generate Workday Job Profiles"""
        print(f"Generating Workday Job Profiles: {count:,} records...")
        records = []
        
        job_families = ['Engineering', 'Sales', 'Marketing', 'Finance', 'HR', 'Operations', 'IT', 'Legal', 'Executive']
        
        for i in range(count):
            job_family = random.choice(job_families)
            
            record = {
                'Job_Profile_WID': self._workday_id(),
                'Job_Profile_Reference_ID': self._workday_ref_id('JP', i + 1),
                
                'Job_Profile_Name': self.fake.job()[:100],
                'Job_Code': f"JC{i+1:04d}",
                'Job_Description': self.fake.paragraph(nb_sentences=2)[:500],
                
                'Job_Family_WID': self._workday_id(),
                'Job_Family_Name': job_family,
                
                'Job_Level': random.choice(['Entry', 'Associate', 'Senior', 'Lead', 'Manager', 'Director', 'VP', 'Executive']),
                'Management_Level': random.choice(['Individual Contributor', 'Manager', 'Executive']),
                
                'Is_Critical_Job': random.random() < 0.1,
                'Is_Active': random.random() > 0.05,
            }
            
            record['_SOURCE_TABLE'] = 'Job_Profiles'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate_compensation(self, count: int, worker_ids: List[str]) -> List[Dict]:
        """Generate Workday Compensation records"""
        print(f"Generating Workday Compensation: {count:,} records...")
        records = []
        
        for i, worker_id in enumerate(worker_ids[:count]):
            effective_date = self.fake.date_between(start_date='-3y', end_date='today')
            
            record = {
                'Compensation_WID': self._workday_id(),
                'Worker_WID': worker_id,
                
                'Effective_Date': effective_date.strftime('%Y-%m-%d'),
                'Compensation_Plan': random.choice(['Base Salary', 'Hourly', 'Commission', 'Executive']),
                
                'Base_Pay_Amount': round(random.uniform(50000, 300000), 2),
                'Base_Pay_Currency': 'USD',
                'Base_Pay_Frequency': random.choice(['Annual', 'Monthly', 'Bi-Weekly', 'Hourly']),
                
                'Total_Compensation': round(random.uniform(50000, 400000), 2),
                'Bonus_Target_Percent': round(random.uniform(0, 50), 1) if random.random() > 0.3 else None,
                
                'Compensation_Grade_WID': self._workday_id(),
                'Compensation_Grade': f"Grade {random.randint(1, 15)}",
                
                'Pay_Range_Minimum': round(random.uniform(40000, 200000), 2),
                'Pay_Range_Maximum': round(random.uniform(80000, 400000), 2),
                'Compa_Ratio': round(random.uniform(0.8, 1.2), 2),
            }
            
            record['_SOURCE_TABLE'] = 'Compensation'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate_time_off(self, count: int, worker_ids: List[str]) -> List[Dict]:
        """Generate Workday Time Off requests"""
        print(f"Generating Workday Time Off: {count:,} records...")
        records = []
        
        time_off_types = ['Vacation', 'Sick', 'Personal', 'Bereavement', 'Jury Duty', 'FMLA', 'Parental']
        
        for i in range(count):
            request_date = self.fake.date_between(start_date='-1y', end_date='+1m')
            days = random.randint(1, 10)
            
            record = {
                'Time_Off_Request_WID': self._workday_id(),
                'Worker_WID': random.choice(worker_ids) if worker_ids else self._workday_id(),
                
                'Time_Off_Type': random.choice(time_off_types),
                'Start_Date': request_date.strftime('%Y-%m-%d'),
                'End_Date': (request_date + timedelta(days=days)).strftime('%Y-%m-%d'),
                'Total_Days': days,
                'Total_Hours': days * 8,
                
                'Status': random.choice(['Submitted', 'Approved', 'Denied', 'Cancelled']),
                'Submitted_Date': self.fake.date_between(start_date='-1y', end_date='today').strftime('%Y-%m-%d'),
                
                'Approver_WID': self._workday_id(),
            }
            
            record['_SOURCE_TABLE'] = 'Time_Off'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate_benefits(self, count: int, worker_ids: List[str]) -> List[Dict]:
        """Generate Workday Benefit Elections"""
        print(f"Generating Workday Benefit Elections: {count:,} records...")
        records = []
        
        benefit_plans = [
            ('Medical', ['PPO Gold', 'PPO Silver', 'HDHP', 'HMO']),
            ('Dental', ['Standard', 'Premium']),
            ('Vision', ['Basic', 'Enhanced']),
            ('Life', ['1x Salary', '2x Salary', '3x Salary']),
            ('401k', ['Traditional', 'Roth']),
        ]
        
        for i in range(count):
            plan_type, options = random.choice(benefit_plans)
            
            record = {
                'Benefit_Election_WID': self._workday_id(),
                'Worker_WID': random.choice(worker_ids) if worker_ids else self._workday_id(),
                
                'Benefit_Plan_Type': plan_type,
                'Benefit_Plan_Name': random.choice(options),
                'Coverage_Level': random.choice(['Employee Only', 'Employee + Spouse', 'Employee + Children', 'Family']),
                
                'Election_Date': self.fake.date_between(start_date='-2y', end_date='today').strftime('%Y-%m-%d'),
                'Coverage_Begin_Date': self.fake.date_between(start_date='-2y', end_date='today').strftime('%Y-%m-%d'),
                'Coverage_End_Date': None,
                
                'Employee_Cost': round(random.uniform(50, 500), 2),
                'Employer_Cost': round(random.uniform(200, 1500), 2),
                
                'Is_Active': random.random() > 0.05,
            }
            
            record['_SOURCE_TABLE'] = 'Benefit_Elections'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate(self, counts: Dict[str, int]) -> Dict[str, List[Dict]]:
        """Generate all Workday data"""
        result = {}
        
        # Workers
        if counts.get('workers', 0) > 0:
            workers = self.generate_workers(counts['workers'])
            result['Workers'] = workers
            worker_ids = [r['Worker_WID'] for r in workers]
        else:
            worker_ids = []
        
        # Organizations
        if counts.get('organizations', 0) > 0:
            orgs = self.generate_organizations(counts['organizations'])
            result['Organizations'] = orgs
        
        # Job Profiles
        if counts.get('job_profiles', 0) > 0:
            jobs = self.generate_job_profiles(counts['job_profiles'])
            result['Job_Profiles'] = jobs
        
        # Compensation
        if counts.get('compensation', 0) > 0 and worker_ids:
            comp = self.generate_compensation(min(counts['compensation'], len(worker_ids)), worker_ids)
            result['Compensation'] = comp
        
        # Time Off
        if counts.get('time_off', 0) > 0 and worker_ids:
            time_off = self.generate_time_off(counts['time_off'], worker_ids)
            result['Time_Off'] = time_off
        
        # Benefits
        if counts.get('benefits', 0) > 0 and worker_ids:
            benefits = self.generate_benefits(counts['benefits'], worker_ids)
            result['Benefit_Elections'] = benefits
        
        return result


# ============================================================================
# SERVICENOW GENERATOR
# ============================================================================

class ServiceNowGenerator(SourceSystemGenerator):
    """
    ServiceNow Data Generator
    
    Generates ServiceNow table data:
      - incident: IT incidents
      - sys_user: Users
      - cmdb_ci: Configuration items
      - change_request: Changes
    
    ServiceNow Conventions:
      - sys_id (32-char GUID)
      - sys_created_on, sys_updated_on
      - Reference fields as sys_id
    """
    
    SYSTEM_NAME = "SERVICENOW"
    
    def _sn_sysid(self) -> str:
        """Generate ServiceNow sys_id (32 hex chars)"""
        return uuid.uuid4().hex
    
    def _sn_datetime(self, dt: datetime = None) -> str:
        """Format datetime for ServiceNow"""
        if dt is None:
            dt = datetime.now()
        return dt.strftime('%Y-%m-%d %H:%M:%S')
    
    def generate_incidents(self, count: int, user_ids: List[str] = None) -> List[Dict]:
        """Generate ServiceNow incident records"""
        print(f"Generating ServiceNow incident: {count:,} records...")
        records = []
        
        states = [
            (1, 'New'), (2, 'In Progress'), (3, 'On Hold'),
            (6, 'Resolved'), (7, 'Closed'), (8, 'Cancelled')
        ]
        
        priorities = [(1, '1 - Critical'), (2, '2 - High'), (3, '3 - Moderate'), (4, '4 - Low'), (5, '5 - Planning')]
        impacts = [(1, '1 - High'), (2, '2 - Medium'), (3, '3 - Low')]
        urgencies = [(1, '1 - High'), (2, '2 - Medium'), (3, '3 - Low')]
        
        categories = [
            'Hardware', 'Software', 'Network', 'Database', 
            'Security', 'Email', 'Inquiry / Help', 'Request'
        ]
        
        for i in range(count):
            opened_at = self.fake.date_time_between(start_date='-1y', end_date='now')
            state = random.choice(states)
            
            record = {
                'sys_id': self._sn_sysid(),
                'number': f"INC{i+1:07d}",
                
                'sys_created_on': self._sn_datetime(opened_at),
                'sys_updated_on': self._sn_datetime(opened_at + timedelta(hours=random.randint(1, 72))),
                'sys_created_by': 'admin',
                'sys_updated_by': f"user{random.randint(1, 100):03d}",
                
                'opened_at': self._sn_datetime(opened_at),
                'opened_by': user_ids[random.randint(0, len(user_ids)-1)] if user_ids else self._sn_sysid(),
                
                'short_description': f"{random.choice(['Cannot access', 'Error in', 'Issue with', 'Problem with'])} {random.choice(['application', 'system', 'network', 'email', 'printer'])}",
                'description': self.fake.paragraph(nb_sentences=3),
                
                'state': state[0],
                'state_display': state[1],
                
                'priority': random.choice(priorities)[0],
                'impact': random.choice(impacts)[0],
                'urgency': random.choice(urgencies)[0],
                
                'category': random.choice(categories),
                'subcategory': random.choice(['Hardware Issue', 'Software Issue', 'Other']),
                
                'assignment_group': self._sn_sysid(),
                'assigned_to': user_ids[random.randint(0, len(user_ids)-1)] if user_ids else self._sn_sysid(),
                
                'caller_id': user_ids[random.randint(0, len(user_ids)-1)] if user_ids else self._sn_sysid(),
                
                'resolved_at': self._sn_datetime(opened_at + timedelta(hours=random.randint(1, 168))) if state[0] in [6, 7] else None,
                'closed_at': self._sn_datetime(opened_at + timedelta(hours=random.randint(1, 168))) if state[0] == 7 else None,
                
                'active': state[0] not in [6, 7, 8],
            }
            
            record['_SOURCE_TABLE'] = 'incident'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records
    
    def generate_sys_users(self, count: int) -> List[Dict]:
        """Generate ServiceNow sys_user records"""
        print(f"Generating ServiceNow sys_user: {count:,} records...")
        records = []
        
        for i in range(count):
            created = self.fake.date_time_between(start_date='-3y', end_date='now')
            
            record = {
                'sys_id': self._sn_sysid(),
                'user_name': f"user{i+1:05d}",
                
                'sys_created_on': self._sn_datetime(created),
                'sys_updated_on': self._sn_datetime(created + timedelta(days=random.randint(0, 365))),
                
                'first_name': self.fake.first_name(),
                'last_name': self.fake.last_name(),
                'name': None,  # Derived
                'email': self.fake.company_email(),
                'phone': self.fake.phone_number(),
                'mobile_phone': self.fake.phone_number() if random.random() > 0.4 else None,
                
                'title': self.fake.job()[:100],
                'department': self._sn_sysid(),
                'company': self._sn_sysid(),
                'location': self._sn_sysid(),
                'manager': self._sn_sysid() if random.random() > 0.2 else None,
                
                'active': random.random() > 0.05,
                'locked_out': random.random() < 0.02,
                'vip': random.random() < 0.05,
                
                'time_zone': 'US/Eastern',
            }
            
            record['name'] = f"{record['first_name']} {record['last_name']}"
            record['_SOURCE_TABLE'] = 'sys_user'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records
    
    def generate_change_request(self, count: int, user_ids: List[str]) -> List[Dict]:
        """Generate ServiceNow change_request records"""
        print(f"Generating ServiceNow change_request: {count:,} records...")
        records = []
        
        states = [(1, 'New'), (2, 'Assess'), (3, 'Authorize'), (4, 'Scheduled'), (5, 'Implement'), (6, 'Review'), (7, 'Closed'), (8, 'Cancelled')]
        types = ['Standard', 'Normal', 'Emergency']
        risks = ['High', 'Moderate', 'Low']
        
        for i in range(count):
            opened_at = self.fake.date_time_between(start_date='-1y', end_date='now')
            state = random.choice(states)
            
            record = {
                'sys_id': self._sn_sysid(),
                'number': f"CHG{i+1:07d}",
                
                'sys_created_on': self._sn_datetime(opened_at),
                'sys_updated_on': self._sn_datetime(opened_at + timedelta(hours=random.randint(1, 168))),
                
                'short_description': f"{random.choice(['Upgrade', 'Patch', 'Deploy', 'Configure', 'Migrate'])} {random.choice(['server', 'database', 'application', 'network', 'storage'])}",
                'description': self.fake.paragraph(nb_sentences=3),
                
                'state': state[0],
                'state_display': state[1],
                'type': random.choice(types),
                'risk': random.choice(risks),
                'impact': random.choice([1, 2, 3]),
                
                'start_date': self._sn_datetime(opened_at + timedelta(days=random.randint(1, 14))),
                'end_date': self._sn_datetime(opened_at + timedelta(days=random.randint(15, 30))),
                
                'assignment_group': self._sn_sysid(),
                'assigned_to': random.choice(user_ids) if user_ids else self._sn_sysid(),
                'requested_by': random.choice(user_ids) if user_ids else self._sn_sysid(),
                
                'cab_required': random.random() < 0.3,
                'cab_date': self._sn_datetime(opened_at + timedelta(days=random.randint(1, 7))) if random.random() < 0.3 else None,
            }
            
            record['_SOURCE_TABLE'] = 'change_request'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate_problem(self, count: int, user_ids: List[str]) -> List[Dict]:
        """Generate ServiceNow problem records"""
        print(f"Generating ServiceNow problem: {count:,} records...")
        records = []
        
        states = [(1, 'New'), (2, 'Assess'), (3, 'Root Cause Analysis'), (4, 'Fix in Progress'), (5, 'Resolved'), (6, 'Closed')]
        
        for i in range(count):
            opened_at = self.fake.date_time_between(start_date='-1y', end_date='now')
            state = random.choice(states)
            
            record = {
                'sys_id': self._sn_sysid(),
                'number': f"PRB{i+1:07d}",
                
                'sys_created_on': self._sn_datetime(opened_at),
                'sys_updated_on': self._sn_datetime(opened_at + timedelta(hours=random.randint(1, 720))),
                
                'short_description': f"Recurring issue with {random.choice(['application', 'server', 'network', 'database'])}",
                'description': self.fake.paragraph(nb_sentences=3),
                
                'state': state[0],
                'state_display': state[1],
                'priority': random.choice([1, 2, 3, 4]),
                'impact': random.choice([1, 2, 3]),
                'urgency': random.choice([1, 2, 3]),
                
                'assignment_group': self._sn_sysid(),
                'assigned_to': random.choice(user_ids) if user_ids else self._sn_sysid(),
                
                'known_error': random.random() < 0.2,
                'workaround': self.fake.paragraph(nb_sentences=2) if random.random() < 0.3 else None,
                'cause': self.fake.paragraph(nb_sentences=2) if state[0] >= 4 else None,
            }
            
            record['_SOURCE_TABLE'] = 'problem'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate_cmdb_ci(self, count: int) -> List[Dict]:
        """Generate ServiceNow cmdb_ci (Configuration Items)"""
        print(f"Generating ServiceNow cmdb_ci: {count:,} records...")
        records = []
        
        ci_classes = [
            ('cmdb_ci_server', 'Server'),
            ('cmdb_ci_computer', 'Computer'),
            ('cmdb_ci_app_server', 'Application Server'),
            ('cmdb_ci_database', 'Database'),
            ('cmdb_ci_network_gear', 'Network Gear'),
            ('cmdb_ci_storage_device', 'Storage Device'),
        ]
        
        for i in range(count):
            ci_class = random.choice(ci_classes)
            
            record = {
                'sys_id': self._sn_sysid(),
                'name': f"{ci_class[1][:3].upper()}-{random.choice(['PROD', 'DEV', 'QA', 'STG'])}-{random.randint(1, 999):03d}",
                
                'sys_class_name': ci_class[0],
                'sys_class_path': f"/cmdb_ci/{ci_class[0]}",
                
                'sys_created_on': self._sn_datetime(self.fake.date_time_between(start_date='-3y', end_date='now')),
                'sys_updated_on': self._sn_datetime(self.fake.date_time_between(start_date='-1y', end_date='now')),
                
                'short_description': f"{ci_class[1]} for {random.choice(['Production', 'Development', 'Testing'])} environment",
                'asset_tag': f"AST{random.randint(100000, 999999)}",
                'serial_number': f"SN{random.randint(1000000, 9999999)}",
                
                'install_status': random.choice([1, 2, 6, 7]),  # Installed, In Maintenance, Retired, etc.
                'operational_status': random.choice([1, 2, 3, 4]),
                
                'ip_address': f"10.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(1, 254)}",
                'mac_address': ':'.join([f"{random.randint(0, 255):02x}" for _ in range(6)]),
                
                'manufacturer': self._sn_sysid(),
                'vendor': self._sn_sysid(),
                'model_id': self._sn_sysid(),
                
                'location': self._sn_sysid(),
                'department': self._sn_sysid(),
                'assigned_to': self._sn_sysid() if random.random() > 0.3 else None,
                
                'cost': round(random.uniform(500, 50000), 2),
                'cost_cc': 'USD',
            }
            
            record['_SOURCE_TABLE'] = 'cmdb_ci'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate_sc_request(self, count: int, user_ids: List[str]) -> List[Dict]:
        """Generate ServiceNow sc_request (Service Catalog Requests)"""
        print(f"Generating ServiceNow sc_request: {count:,} records...")
        records = []
        
        states = [(1, 'Pending Approval'), (2, 'Approved'), (3, 'Rejected'), (4, 'Closed Complete'), (5, 'Closed Incomplete')]
        
        for i in range(count):
            opened_at = self.fake.date_time_between(start_date='-1y', end_date='now')
            state = random.choice(states)
            
            record = {
                'sys_id': self._sn_sysid(),
                'number': f"REQ{i+1:07d}",
                
                'sys_created_on': self._sn_datetime(opened_at),
                'sys_updated_on': self._sn_datetime(opened_at + timedelta(hours=random.randint(1, 72))),
                
                'short_description': f"Request for {random.choice(['laptop', 'software', 'access', 'equipment', 'service'])}",
                
                'request_state': state[1],
                'stage': random.choice(['Request Submitted', 'Waiting for Approval', 'Fulfillment', 'Delivery', 'Completed']),
                
                'requested_for': random.choice(user_ids) if user_ids else self._sn_sysid(),
                'opened_by': random.choice(user_ids) if user_ids else self._sn_sysid(),
                
                'price': round(random.uniform(0, 5000), 2),
                'expected_start': self._sn_datetime(opened_at + timedelta(days=random.randint(1, 7))),
            }
            
            record['_SOURCE_TABLE'] = 'sc_request'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate_kb_knowledge(self, count: int, user_ids: List[str]) -> List[Dict]:
        """Generate ServiceNow kb_knowledge (Knowledge Articles)"""
        print(f"Generating ServiceNow kb_knowledge: {count:,} records...")
        records = []
        
        workflows = ['draft', 'review', 'published', 'retired']
        
        for i in range(count):
            created = self.fake.date_time_between(start_date='-2y', end_date='now')
            
            record = {
                'sys_id': self._sn_sysid(),
                'number': f"KB{i+1:07d}",
                
                'sys_created_on': self._sn_datetime(created),
                'sys_updated_on': self._sn_datetime(created + timedelta(days=random.randint(0, 180))),
                
                'short_description': f"How to {random.choice(['resolve', 'fix', 'configure', 'setup', 'troubleshoot'])} {random.choice(['email', 'VPN', 'printer', 'password', 'application'])} issues",
                'text': self.fake.paragraph(nb_sentences=5),
                
                'workflow_state': random.choice(workflows),
                'valid_to': (created + timedelta(days=365)).strftime('%Y-%m-%d'),
                
                'author': random.choice(user_ids) if user_ids else self._sn_sysid(),
                'kb_knowledge_base': self._sn_sysid(),
                'kb_category': self._sn_sysid(),
                
                'view_count': random.randint(0, 10000),
                'rating': round(random.uniform(1, 5), 1),
                'helpful_count': random.randint(0, 500),
            }
            
            record['_SOURCE_TABLE'] = 'kb_knowledge'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        
        return records

    def generate(self, counts: Dict[str, int]) -> Dict[str, List[Dict]]:
        """Generate all ServiceNow data"""
        result = {}
        
        # Users
        if counts.get('users', 0) > 0:
            users = self.generate_sys_users(counts['users'])
            result['sys_user'] = users
            user_ids = [r['sys_id'] for r in users]
        else:
            user_ids = []
        
        # Incidents
        if counts.get('incidents', 0) > 0:
            incidents = self.generate_incidents(counts['incidents'], user_ids)
            result['incident'] = incidents
        
        # Change Requests
        if counts.get('changes', 0) > 0:
            changes = self.generate_change_request(counts['changes'], user_ids)
            result['change_request'] = changes
        
        # Problems
        if counts.get('problems', 0) > 0:
            problems = self.generate_problem(counts['problems'], user_ids)
            result['problem'] = problems
        
        # CMDB CIs
        if counts.get('cmdb', 0) > 0:
            cis = self.generate_cmdb_ci(counts['cmdb'])
            result['cmdb_ci'] = cis
        
        # Service Catalog Requests
        if counts.get('requests', 0) > 0:
            requests = self.generate_sc_request(counts['requests'], user_ids)
            result['sc_request'] = requests
        
        # Knowledge Articles
        if counts.get('knowledge', 0) > 0:
            articles = self.generate_kb_knowledge(counts['knowledge'], user_ids)
            result['kb_knowledge'] = articles
        
        return result


# ============================================================================
# OUTPUT FUNCTIONS
# ============================================================================

def save_to_csv(data: Dict[str, List[Dict]], output_dir: str, system_name: str):
    """Save data to CSV files"""
    system_dir = os.path.join(output_dir, system_name.lower())
    os.makedirs(system_dir, exist_ok=True)
    
    for table_name, records in data.items():
        if not records:
            continue
        
        filepath = os.path.join(system_dir, f"{table_name}.csv")
        print(f"Writing {filepath}...")
        
        # Flatten nested structures for CSV
        flat_records = []
        for r in records:
            flat = {}
            for k, v in r.items():
                if isinstance(v, (dict, list)):
                    flat[k] = json.dumps(v)
                else:
                    flat[k] = v
            flat_records.append(flat)
        
        with open(filepath, 'w', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=flat_records[0].keys())
            writer.writeheader()
            writer.writerows(flat_records)


def save_to_json(data: Dict[str, List[Dict]], output_dir: str, system_name: str):
    """Save data to JSON files"""
    system_dir = os.path.join(output_dir, system_name.lower())
    os.makedirs(system_dir, exist_ok=True)
    
    for table_name, records in data.items():
        if not records:
            continue
        
        filepath = os.path.join(system_dir, f"{table_name}.json")
        print(f"Writing {filepath}...")
        
        with open(filepath, 'w', encoding='utf-8') as f:
            json.dump(records, f, indent=2, default=str)


def save_to_parquet(data: Dict[str, List[Dict]], output_dir: str, system_name: str):
    """Save data to Parquet files using pyarrow."""
    try:
        import pyarrow as pa
        import pyarrow.parquet as pq
    except ImportError:
        print("ERROR: pyarrow not installed. Run: pip install pyarrow")
        sys.exit(1)

    system_dir = os.path.join(output_dir, system_name.lower())
    os.makedirs(system_dir, exist_ok=True)

    for table_name, records in data.items():
        if not records:
            continue

        filepath = os.path.join(system_dir, f"{table_name}.parquet")
        print(f"Writing {filepath}...")

        # Flatten nested structures to JSON strings so every column is scalar
        flat_records = []
        for r in records:
            flat = {}
            for k, v in r.items():
                if isinstance(v, (dict, list)):
                    flat[k] = json.dumps(v, default=str)
                elif isinstance(v, (datetime, date)):
                    flat[k] = str(v)
                else:
                    flat[k] = v
            flat_records.append(flat)

        table = pa.Table.from_pylist(flat_records)
        pq.write_table(table, filepath, compression='snappy')


def save_to_xml(data: Dict[str, List[Dict]], output_dir: str, system_name: str):
    """Save data to XML files (one file per table, one <record> element per row)."""
    import xml.etree.ElementTree as ET

    system_dir = os.path.join(output_dir, system_name.lower())
    os.makedirs(system_dir, exist_ok=True)

    def _safe_tag(name: str) -> str:
        """Ensure element tag is a valid XML name (replace spaces/special chars)."""
        return name.replace(' ', '_').replace('/', '_').replace('.', '_')

    def _to_text(value) -> str:
        if value is None:
            return ''
        if isinstance(value, (dict, list)):
            return json.dumps(value, default=str)
        if isinstance(value, bool):
            return 'true' if value else 'false'
        return str(value)

    for table_name, records in data.items():
        if not records:
            continue

        filepath = os.path.join(system_dir, f"{table_name}.xml")
        print(f"Writing {filepath}...")

        root = ET.Element(_safe_tag(table_name))
        root.set('system', system_name)
        root.set('table', table_name)
        root.set('generated_at', datetime.utcnow().isoformat() + 'Z')
        root.set('record_count', str(len(records)))

        for record in records:
            rec_el = ET.SubElement(root, 'record')
            for field_name, value in record.items():
                field_el = ET.SubElement(rec_el, _safe_tag(field_name))
                field_el.text = _to_text(value)

        # Pretty-print (Python 3.9+); fall back to plain dump for older Python
        try:
            ET.indent(root, space='  ')
        except AttributeError:
            pass

        tree = ET.ElementTree(root)
        with open(filepath, 'wb') as f:
            tree.write(f, encoding='utf-8', xml_declaration=True)


# ============================================================================
# CLI ENTRY POINT
# ============================================================================

SYSTEM_GENERATORS = {
    'sap': SAPGenerator,
    'salesforce': SalesforceGenerator,
    'oracle': OracleEBSGenerator,
    'fhir': FHIRGenerator,
    'workday': WorkdayGenerator,
    'servicenow': ServiceNowGenerator,
}

SYSTEM_DOMAINS = {
    'sap': {
        'customers': {'customers': 1000},
        'materials': {'products': 500},
        'sales': {'customers': 1000, 'products': 500, 'orders': 5000},
        'procurement': {'vendors': 500, 'purchase_orders': 2000},
        'finance': {'fi_documents': 5000},
        'hr': {'employees': 1000},
        'all': {
            'customers': 1000, 'products': 500, 'orders': 5000,
            'employees': 500, 'vendors': 300, 'purchase_orders': 1000, 'fi_documents': 2000
        },
    },
    'salesforce': {
        'sales': {'accounts': 1000, 'contacts': 3000, 'opportunities': 2000, 'leads': 1500},
        'service': {'accounts': 500, 'contacts': 1500, 'cases': 3000},
        'marketing': {'accounts': 500, 'contacts': 2000, 'leads': 3000, 'campaigns': 100},
        'products': {'products': 500},
        'activities': {'accounts': 500, 'contacts': 1000, 'tasks': 5000},
        'all': {
            'accounts': 1000, 'contacts': 3000, 'opportunities': 2000,
            'cases': 1000, 'leads': 1500, 'products': 300, 'campaigns': 50, 'tasks': 2000
        },
    },
    'oracle': {
        'customers': {'customers': 1000},
        'products': {'products': 500},
        'orders': {'customers': 500, 'orders': 5000},
        'procurement': {'vendors': 500, 'products': 300},
        'payables': {'vendors': 500, 'ap_invoices': 3000},
        'receivables': {'customers': 500, 'ar_invoices': 3000},
        'gl': {'gl_entries': 10000},
        'hr': {'employees': 1000},
        'all': {
            'customers': 1000, 'vendors': 500, 'products': 500, 'orders': 3000,
            'employees': 500, 'ap_invoices': 2000, 'ar_invoices': 2000, 'gl_entries': 5000
        },
    },
    'fhir': {
        'patients': {'patients': 1000},
        'providers': {'practitioners': 200, 'organizations': 50},
        'encounters': {'patients': 500, 'encounters': 3000},
        'clinical': {'patients': 500, 'encounters': 2000, 'conditions': 1500, 'observations': 5000, 'procedures': 1000},
        'medications': {'patients': 500, 'practitioners': 100, 'medications': 3000},
        'billing': {'patients': 500, 'organizations': 50, 'claims': 3000},
        'all': {
            'patients': 1000, 'practitioners': 200, 'organizations': 50,
            'encounters': 5000, 'conditions': 3000, 'observations': 10000,
            'medications': 3000, 'procedures': 2000, 'claims': 2000
        },
    },
    'workday': {
        'workers': {'workers': 1000},
        'organizations': {'organizations': 100},
        'jobs': {'job_profiles': 200},
        'compensation': {'workers': 500, 'compensation': 500},
        'time': {'workers': 500, 'time_off': 2000},
        'benefits': {'workers': 500, 'benefits': 1500},
        'hcm': {
            'workers': 1000, 'organizations': 100, 'job_profiles': 150,
            'compensation': 1000, 'time_off': 2000, 'benefits': 2000
        },
        'all': {
            'workers': 1000, 'organizations': 100, 'job_profiles': 200,
            'compensation': 1000, 'time_off': 3000, 'benefits': 2000
        },
    },
    'servicenow': {
        'users': {'users': 500},
        'incidents': {'users': 300, 'incidents': 5000},
        'changes': {'users': 300, 'changes': 1000},
        'problems': {'users': 300, 'problems': 500},
        'cmdb': {'cmdb': 2000},
        'requests': {'users': 300, 'requests': 2000},
        'knowledge': {'users': 100, 'knowledge': 500},
        'itsm': {'users': 500, 'incidents': 5000, 'changes': 1000, 'problems': 300},
        'all': {
            'users': 500, 'incidents': 5000, 'changes': 1000, 'problems': 500,
            'cmdb': 2000, 'requests': 2000, 'knowledge': 300
        },
    },
}


def main():
    parser = argparse.ArgumentParser(
        description="Generate source system-specific synthetic data for Snowflake",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # SAP S/4HANA data
  python data_generator.py --system sap --domain customers --output ../data
  
  # Salesforce Sales Cloud
  python data_generator.py --system salesforce --domain sales --output ../data
  
  # Oracle EBS
  python data_generator.py --system oracle --domain all --output ../data
  
  # FHIR R4 Healthcare
  python data_generator.py --system fhir --domain patients --output ../data
  
  # Workday HCM
  python data_generator.py --system workday --domain workers --output ../data
  
  # ServiceNow ITSM
  python data_generator.py --system servicenow --domain itsm --output ../data
  
  # Quick test
  python data_generator.py --system sap --domain customers --quick --output ../data
        """
    )
    
    parser.add_argument("--system", "-s", required=True, choices=SYSTEM_GENERATORS.keys(),
                       help="Source system to simulate")
    parser.add_argument("--domain", "-d", default="all",
                       help="Data domain to generate (system-specific)")
    parser.add_argument("--output", "-o", default="./data",
                       help="Output directory")
    parser.add_argument("--format", "-f", choices=["csv", "json", "parquet", "xml"], default="csv",
                       help="Output format (csv, json, parquet, or xml)")
    parser.add_argument("--seed", type=int, default=42,
                       help="Random seed")
    parser.add_argument("--quick", action="store_true",
                       help="Generate small test dataset")
    parser.add_argument("--scale", type=float, default=1.0,
                       help="Scale factor for record counts")
    
    args = parser.parse_args()
    
    print("=" * 70)
    print(f"SOURCE SYSTEM DATA GENERATOR")
    print(f"System: {args.system.upper()}")
    print(f"Domain: {args.domain}")
    print("=" * 70)
    
    # Get generator
    generator_class = SYSTEM_GENERATORS[args.system]
    generator = generator_class(seed=args.seed)
    
    # Get counts for domain
    domains = SYSTEM_DOMAINS.get(args.system, {})
    counts = domains.get(args.domain, domains.get('all', {}))
    
    if not counts:
        print(f"Unknown domain '{args.domain}' for system {args.system}")
        print(f"Available domains: {list(domains.keys())}")
        sys.exit(1)
    
    # Apply scale and quick mode
    if args.quick:
        counts = {k: max(10, v // 10) for k, v in counts.items()}
    else:
        counts = {k: int(v * args.scale) for k, v in counts.items()}
    
    print(f"Record counts: {counts}")
    print()
    
    # Generate
    data = generator.generate(counts)
    
    print()
    print("=" * 70)
    print("GENERATION COMPLETE")
    print("=" * 70)
    for table, records in data.items():
        print(f"  {table}: {len(records):,} records")
    
    # Save
    print()
    print(f"Saving to {args.output}/{args.system.lower()}/...")
    
    if args.format == "csv":
        save_to_csv(data, args.output, generator.SYSTEM_NAME)
    elif args.format == "json":
        save_to_json(data, args.output, generator.SYSTEM_NAME)
    elif args.format == "parquet":
        save_to_parquet(data, args.output, generator.SYSTEM_NAME)
    elif args.format == "xml":
        save_to_xml(data, args.output, generator.SYSTEM_NAME)
    
    print()
    print("Done!")


if __name__ == "__main__":
    main()
