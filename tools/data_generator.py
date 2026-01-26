#!/usr/bin/env python3
"""
Pluggable Synthetic Data Generator for Snowflake DCA Demo

This generator creates realistic, diverse synthetic data that can be adapted
to any source system (Oracle, SAP, Salesforce, ServiceNow, etc.).

Features:
    - Domain-agnostic with pluggable domain configurations
    - Culturally diverse names via Faker locales
    - Realistic address and contact generation
    - Referential integrity across all tables
    - SCD Type 2 ready with hash columns
    - Configurable record counts
    - Multiple output formats (CSV, JSON, Parquet)

Usage:
    # CRM domain (default)
    python data_generator.py --domain crm --output ../data
    
    # HR domain
    python data_generator.py --domain hr --output ../data
    
    # Quick test dataset
    python data_generator.py --domain crm --output ../data --quick
    
    # Custom counts
    python data_generator.py --domain crm --customers 50000 --orders 200000

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
from datetime import datetime, timedelta, date
from typing import List, Dict, Any, Optional, Tuple
from dataclasses import dataclass, field, asdict

# ============================================================================
# FAKER SETUP
# ============================================================================

try:
    from faker import Faker
    from faker.providers import BaseProvider
except ImportError:
    print("ERROR: Faker not installed. Run: pip install faker")
    print("       pip install -r requirements.txt")
    sys.exit(1)

# ============================================================================
# CONSTANTS
# ============================================================================

# Geographic regions
REGIONS = ['North America', 'EMEA', 'APAC', 'LATAM']
COUNTRIES_BY_REGION = {
    'North America': ['United States', 'Canada', 'Mexico'],
    'EMEA': ['United Kingdom', 'Germany', 'France', 'Netherlands', 'Spain', 'Italy'],
    'APAC': ['Australia', 'Japan', 'Singapore', 'India', 'South Korea'],
    'LATAM': ['Brazil', 'Argentina', 'Chile', 'Colombia']
}

# Industry verticals
INDUSTRIES = [
    'Technology', 'Healthcare', 'Finance', 'Retail', 'Manufacturing',
    'Education', 'Government', 'Media', 'Telecommunications', 'Energy',
    'Transportation', 'Real Estate', 'Professional Services', 'Hospitality'
]

# Customer segments
CUSTOMER_SEGMENTS = ['Enterprise', 'Mid-Market', 'SMB', 'Startup', 'Consumer']
CUSTOMER_TYPES = ['Business', 'Individual', 'Government', 'Non-Profit']
CUSTOMER_STATUSES = ['Active', 'Inactive', 'Prospect', 'Churned', 'Suspended']

# Order statuses
ORDER_STATUSES = ['Pending', 'Processing', 'Shipped', 'Delivered', 'Cancelled', 'Returned']
ORDER_TYPES = ['New', 'Renewal', 'Upsell', 'Cross-sell', 'Replacement']
ORDER_PRIORITIES = ['Low', 'Medium', 'High', 'Critical']
SALES_CHANNELS = ['Direct', 'Partner', 'Online', 'Field Sales', 'Inside Sales', 'Marketplace']

# Product categories
PRODUCT_CATEGORIES = {
    'Software': ['SaaS', 'On-Premise', 'Mobile App', 'API Service'],
    'Hardware': ['Servers', 'Networking', 'Storage', 'Endpoints'],
    'Services': ['Consulting', 'Implementation', 'Training', 'Support'],
    'Subscriptions': ['Monthly', 'Annual', 'Multi-Year', 'Usage-Based']
}

# Employment
DEPARTMENTS = [
    'Engineering', 'Sales', 'Marketing', 'Finance', 'Human Resources',
    'Operations', 'Customer Success', 'Legal', 'IT', 'Product', 'Executive'
]

JOB_LEVELS = ['Individual Contributor', 'Senior', 'Lead', 'Manager', 'Director', 'VP', 'C-Level']

EMPLOYMENT_TYPES = ['Full-Time', 'Part-Time', 'Contract', 'Intern']
EMPLOYMENT_STATUSES = ['Active', 'On Leave', 'Terminated', 'Retired']

# ============================================================================
# FAKER PROVIDERS
# ============================================================================

class BusinessProvider(BaseProvider):
    """Custom Faker provider for business data"""
    
    def region(self) -> str:
        return self.random_element(REGIONS)
    
    def country_for_region(self, region: str) -> str:
        countries = COUNTRIES_BY_REGION.get(region, ['United States'])
        return self.random_element(countries)
    
    def industry(self) -> str:
        return self.random_element(INDUSTRIES)
    
    def customer_segment(self) -> str:
        return self.random_element(CUSTOMER_SEGMENTS)
    
    def customer_type(self) -> str:
        return self.random_element(CUSTOMER_TYPES)
    
    def customer_status(self) -> str:
        return self.random_element(CUSTOMER_STATUSES)
    
    def order_status(self) -> str:
        return self.random_element(ORDER_STATUSES)
    
    def order_type(self) -> str:
        return self.random_element(ORDER_TYPES)
    
    def order_priority(self) -> str:
        return self.random_element(ORDER_PRIORITIES)
    
    def sales_channel(self) -> str:
        return self.random_element(SALES_CHANNELS)
    
    def product_category(self) -> Tuple[str, str]:
        category = self.random_element(list(PRODUCT_CATEGORIES.keys()))
        subcategory = self.random_element(PRODUCT_CATEGORIES[category])
        return category, subcategory
    
    def department(self) -> str:
        return self.random_element(DEPARTMENTS)
    
    def job_level(self) -> str:
        return self.random_element(JOB_LEVELS)
    
    def employment_type(self) -> str:
        return self.random_element(EMPLOYMENT_TYPES)
    
    def employment_status(self) -> str:
        return self.random_element(EMPLOYMENT_STATUSES)

# ============================================================================
# DATA GENERATOR CLASS
# ============================================================================

class SyntheticDataGenerator:
    """
    Pluggable synthetic data generator for Snowflake DCA demos.
    
    Supports multiple domains and source system simulations.
    """
    
    def __init__(self, seed: int = 42):
        """Initialize generator with random seed for reproducibility"""
        self.seed = seed
        random.seed(seed)
        
        # Initialize Faker with multiple locales for diversity
        self.fakers = self._init_fakers(seed)
        self.fake = self.fakers['en_US']  # Default
        
        # Add custom provider
        for f in self.fakers.values():
            f.add_provider(BusinessProvider)
        
        # Storage
        self.customers: List[Dict] = []
        self.products: List[Dict] = []
        self.orders: List[Dict] = []
        self.order_lines: List[Dict] = []
        self.employees: List[Dict] = []
        self.departments: List[Dict] = []
        self.locations: List[Dict] = []
        
        # Lookup maps
        self.customer_ids: List[str] = []
        self.product_ids: List[str] = []
        self.employee_ids: List[str] = []
        self.department_ids: List[str] = []
        
        # Name uniqueness tracking
        self.used_emails: set = set()
    
    def _init_fakers(self, seed: int) -> Dict[str, Faker]:
        """Initialize Faker instances for multiple locales"""
        locales = [
            'en_US', 'en_GB', 'de_DE', 'fr_FR', 'es_ES', 'it_IT',
            'pt_BR', 'ja_JP', 'zh_CN', 'ko_KR', 'hi_IN', 'ar_SA'
        ]
        
        fakers = {}
        for i, locale in enumerate(locales):
            try:
                f = Faker(locale)
                f.seed_instance(seed + i)
                fakers[locale] = f
            except:
                pass  # Skip unsupported locales
        
        # Ensure we have at least en_US
        if 'en_US' not in fakers:
            fakers['en_US'] = Faker('en_US')
            fakers['en_US'].seed_instance(seed)
        
        return fakers
    
    def _get_faker_for_region(self, region: str) -> Faker:
        """Get appropriate Faker locale for region"""
        locale_map = {
            'North America': ['en_US'],
            'EMEA': ['en_GB', 'de_DE', 'fr_FR', 'es_ES', 'it_IT'],
            'APAC': ['ja_JP', 'zh_CN', 'ko_KR', 'hi_IN'],
            'LATAM': ['pt_BR', 'es_ES']
        }
        
        locales = locale_map.get(region, ['en_US'])
        for locale in locales:
            if locale in self.fakers:
                return self.fakers[locale]
        
        return self.fake
    
    def _generate_unique_email(self, first_name: str, last_name: str, domain: str = None) -> str:
        """Generate a unique email address"""
        if domain is None:
            domain = random.choice([
                'example.com', 'acme.com', 'company.com', 'corp.net',
                'business.io', 'enterprise.com', 'org.com'
            ])
        
        base_email = f"{first_name.lower()}.{last_name.lower()}@{domain}"
        email = base_email
        counter = 1
        
        while email in self.used_emails:
            email = f"{first_name.lower()}.{last_name.lower()}{counter}@{domain}"
            counter += 1
        
        self.used_emails.add(email)
        return email
    
    def _calculate_hash(self, data: Dict) -> str:
        """Calculate row hash for SCD Type 2"""
        hash_data = {k: v for k, v in data.items() if not k.startswith('_')}
        hash_str = json.dumps(hash_data, sort_keys=True, default=str)
        return hashlib.sha256(hash_str.encode()).hexdigest()
    
    def _generate_ssn(self) -> str:
        """Generate fake SSN (for demo only)"""
        return f"{random.randint(100,999):03d}-{random.randint(10,99):02d}-{random.randint(1000,9999):04d}"
    
    def _generate_phone(self, region: str = 'North America') -> str:
        """Generate phone number for region"""
        if region == 'North America':
            area = random.randint(200, 999)
            exchange = random.randint(200, 999)
            subscriber = random.randint(1000, 9999)
            return f"+1-{area}-{exchange}-{subscriber}"
        else:
            return self.fake.phone_number()
    
    # =========================================================================
    # CUSTOMER GENERATION
    # =========================================================================
    
    def generate_customers(self, count: int = 10000) -> List[Dict]:
        """Generate customer records"""
        print(f"Generating {count:,} customers...")
        
        for i in range(count):
            if i % 5000 == 0 and i > 0:
                print(f"  Generated {i:,} customers...")
            
            region = self.fake.region()
            country = self.fake.country_for_region(region)
            faker = self._get_faker_for_region(region)
            
            # Generate name
            first_name = faker.first_name()
            last_name = faker.last_name()
            
            # Company (70% have company)
            is_business = random.random() < 0.7
            company_name = faker.company() if is_business else None
            
            # Dates
            created_date = self.fake.date_between(start_date='-5y', end_date='today')
            first_purchase = created_date + timedelta(days=random.randint(0, 90)) if random.random() > 0.2 else None
            last_purchase = first_purchase + timedelta(days=random.randint(0, 365*3)) if first_purchase else None
            if last_purchase and last_purchase > date.today():
                last_purchase = date.today() - timedelta(days=random.randint(0, 30))
            
            # Lifetime value based on segment
            segment = self.fake.customer_segment()
            ltv_ranges = {
                'Enterprise': (50000, 500000),
                'Mid-Market': (10000, 75000),
                'SMB': (1000, 15000),
                'Startup': (500, 10000),
                'Consumer': (50, 2000)
            }
            ltv_min, ltv_max = ltv_ranges.get(segment, (100, 10000))
            lifetime_value = round(random.uniform(ltv_min, ltv_max), 2)
            
            customer_id = f"CUST-{i+1:08d}"
            
            customer = {
                'CUSTOMER_ID': customer_id,
                'FIRST_NAME': first_name,
                'LAST_NAME': last_name,
                'EMAIL': self._generate_unique_email(first_name, last_name),
                'PHONE': self._generate_phone(region),
                'MOBILE_PHONE': self._generate_phone(region) if random.random() > 0.3 else None,
                'ADDRESS_LINE1': faker.street_address(),
                'ADDRESS_LINE2': faker.secondary_address() if random.random() > 0.7 else None,
                'CITY': faker.city(),
                'STATE_PROVINCE': faker.state() if region == 'North America' else faker.city(),
                'POSTAL_CODE': faker.postcode(),
                'COUNTRY': country,
                'COMPANY_NAME': company_name,
                'INDUSTRY': self.fake.industry() if is_business else None,
                'COMPANY_SIZE': random.choice(['1-10', '11-50', '51-200', '201-1000', '1000+']) if is_business else None,
                'CUSTOMER_TYPE': 'Business' if is_business else 'Individual',
                'CUSTOMER_STATUS': self.fake.customer_status(),
                'CUSTOMER_SEGMENT': segment,
                'LIFETIME_VALUE': lifetime_value,
                'CREDIT_LIMIT': round(lifetime_value * random.uniform(0.5, 2), 2),
                'PAYMENT_TERMS': random.choice(['Net 30', 'Net 45', 'Net 60', 'Due on Receipt']),
                'CURRENCY_CODE': 'USD',
                'CREATED_DATE': str(created_date),
                'FIRST_PURCHASE_DATE': str(first_purchase) if first_purchase else None,
                'LAST_PURCHASE_DATE': str(last_purchase) if last_purchase else None,
                'CHURN_DATE': str(created_date + timedelta(days=random.randint(180, 1000))) if random.random() < 0.1 else None,
                'ACCOUNT_OWNER_ID': f"EMP-{random.randint(1, 500):06d}" if is_business else None,
                'PARENT_CUSTOMER_ID': None,
                'REGION': region,
                'TERRITORY': f"{region}-{random.randint(1, 10):02d}",
                'MARKETING_CONSENT': random.random() > 0.3,
                'DATA_PROCESSING_CONSENT': True,
                'CONSENT_DATE': str(created_date),
                'GDPR_DELETE_REQUESTED': False,
                '_SOURCE_SYSTEM': 'CRM',
                '_SOURCE_TABLE': 'CUSTOMER'
            }
            
            customer['_ROW_HASH'] = self._calculate_hash(customer)
            
            self.customers.append(customer)
            self.customer_ids.append(customer_id)
        
        return self.customers
    
    # =========================================================================
    # PRODUCT GENERATION
    # =========================================================================
    
    def generate_products(self, count: int = 500) -> List[Dict]:
        """Generate product records"""
        print(f"Generating {count:,} products...")
        
        for i in range(count):
            category, subcategory = self.fake.product_category()
            
            # Pricing based on category
            price_ranges = {
                'Software': (99, 9999),
                'Hardware': (199, 49999),
                'Services': (500, 25000),
                'Subscriptions': (9, 999)
            }
            price_min, price_max = price_ranges.get(category, (10, 1000))
            list_price = round(random.uniform(price_min, price_max), 2)
            cost_price = round(list_price * random.uniform(0.3, 0.7), 2)
            
            product_id = f"PROD-{i+1:06d}"
            launch_date = self.fake.date_between(start_date='-3y', end_date='today')
            
            product = {
                'PRODUCT_ID': product_id,
                'PRODUCT_CODE': f"{category[:3].upper()}-{subcategory[:3].upper()}-{i+1:04d}",
                'PRODUCT_NAME': f"{self.fake.word().title()} {subcategory} {random.choice(['Pro', 'Plus', 'Enterprise', 'Basic', 'Standard'])}",
                'PRODUCT_DESCRIPTION': self.fake.paragraph(nb_sentences=3),
                'PRODUCT_CATEGORY': category,
                'PRODUCT_SUBCATEGORY': subcategory,
                'PRODUCT_LINE': f"{category} Solutions",
                'BRAND': random.choice(['TechCorp', 'DataFlow', 'CloudFirst', 'InnovateTech', 'NextGen']),
                'LIST_PRICE': list_price,
                'COST_PRICE': cost_price,
                'CURRENCY_CODE': 'USD',
                'PRODUCT_STATUS': random.choice(['Active', 'Active', 'Active', 'Discontinued', 'Preview']),
                'IS_ACTIVE': random.random() > 0.1,
                'LAUNCH_DATE': str(launch_date),
                'DISCONTINUE_DATE': None,
                'REORDER_POINT': random.randint(10, 100) if category == 'Hardware' else None,
                'SAFETY_STOCK': random.randint(5, 50) if category == 'Hardware' else None,
                'LEAD_TIME_DAYS': random.randint(1, 30) if category == 'Hardware' else None,
                'WEIGHT': round(random.uniform(0.1, 50), 2) if category == 'Hardware' else None,
                'WEIGHT_UNIT': 'kg' if category == 'Hardware' else None,
                'SIZE_DIMENSIONS': None,
                'COLOR': None,
                '_SOURCE_SYSTEM': 'ERP',
                '_SOURCE_TABLE': 'PRODUCT'
            }
            
            product['_ROW_HASH'] = self._calculate_hash(product)
            
            self.products.append(product)
            self.product_ids.append(product_id)
        
        return self.products
    
    # =========================================================================
    # ORDER GENERATION
    # =========================================================================
    
    def generate_orders(self, count: int = 50000) -> List[Dict]:
        """Generate order records"""
        print(f"Generating {count:,} orders...")
        
        if not self.customer_ids:
            raise ValueError("Must generate customers first")
        
        for i in range(count):
            if i % 10000 == 0 and i > 0:
                print(f"  Generated {i:,} orders...")
            
            customer_id = random.choice(self.customer_ids)
            
            # Order dates
            order_date = self.fake.date_between(start_date='-2y', end_date='today')
            ship_date = order_date + timedelta(days=random.randint(1, 5))
            delivery_date = ship_date + timedelta(days=random.randint(1, 10))
            
            # Financials
            subtotal = round(random.uniform(50, 5000), 2)
            discount_pct = random.choice([0, 0, 0, 5, 10, 15, 20]) / 100
            discount_amount = round(subtotal * discount_pct, 2)
            tax_rate = random.choice([0.05, 0.06, 0.07, 0.08, 0.085, 0.09, 0.095])
            tax_amount = round((subtotal - discount_amount) * tax_rate, 2)
            shipping = round(random.uniform(0, 50), 2)
            order_total = round(subtotal - discount_amount + tax_amount + shipping, 2)
            
            region = random.choice(REGIONS)
            
            order = {
                'ORDER_ID': f"ORD-{i+1:010d}",
                'ORDER_NUMBER': f"SO-{order_date.year}-{i+1:08d}",
                'CUSTOMER_ID': customer_id,
                'ACCOUNT_ID': customer_id,
                'SALES_REP_ID': f"EMP-{random.randint(1, 200):06d}",
                'ORDER_DATE': str(order_date),
                'ORDER_STATUS': self.fake.order_status(),
                'ORDER_TYPE': self.fake.order_type(),
                'ORDER_PRIORITY': self.fake.order_priority(),
                'SUBTOTAL': subtotal,
                'DISCOUNT_AMOUNT': discount_amount,
                'TAX_AMOUNT': tax_amount,
                'SHIPPING_AMOUNT': shipping,
                'ORDER_TOTAL': order_total,
                'CURRENCY_CODE': 'USD',
                'SHIP_DATE': str(ship_date),
                'DELIVERY_DATE': str(delivery_date),
                'SHIPPING_METHOD': random.choice(['Standard', 'Express', 'Next Day', 'Economy']),
                'TRACKING_NUMBER': self.fake.uuid4()[:12].upper() if random.random() > 0.3 else None,
                'SHIP_ADDRESS_LINE1': self.fake.street_address(),
                'SHIP_ADDRESS_LINE2': None,
                'SHIP_CITY': self.fake.city(),
                'SHIP_STATE': self.fake.state(),
                'SHIP_POSTAL_CODE': self.fake.postcode(),
                'SHIP_COUNTRY': self.fake.country_for_region(region),
                'SALES_CHANNEL': self.fake.sales_channel(),
                'SOURCE_CAMPAIGN': f"Campaign-{random.randint(1, 50):03d}" if random.random() > 0.5 else None,
                'REGION': region,
                '_SOURCE_SYSTEM': 'CRM',
                '_SOURCE_TABLE': 'ORDER'
            }
            
            order['_ROW_HASH'] = self._calculate_hash(order)
            
            self.orders.append(order)
        
        return self.orders
    
    # =========================================================================
    # EMPLOYEE GENERATION
    # =========================================================================
    
    def generate_employees(self, count: int = 1000) -> List[Dict]:
        """Generate employee records"""
        print(f"Generating {count:,} employees...")
        
        for i in range(count):
            region = random.choice(['North America', 'EMEA', 'APAC'])
            faker = self._get_faker_for_region(region)
            
            first_name = faker.first_name()
            last_name = faker.last_name()
            
            # Dates
            today = date.today()
            dob = self.fake.date_of_birth(minimum_age=22, maximum_age=65)
            hire_date = self.fake.date_between(start_date='-15y', end_date='today')
            
            # Compensation based on level
            level = self.fake.job_level()
            salary_ranges = {
                'Individual Contributor': (50000, 90000),
                'Senior': (80000, 130000),
                'Lead': (100000, 160000),
                'Manager': (120000, 180000),
                'Director': (150000, 250000),
                'VP': (200000, 400000),
                'C-Level': (300000, 800000)
            }
            sal_min, sal_max = salary_ranges.get(level, (50000, 100000))
            salary = round(random.uniform(sal_min, sal_max), 2)
            
            department = self.fake.department()
            emp_id = f"EMP-{i+1:06d}"
            
            employee = {
                'EMPLOYEE_ID': emp_id,
                'EMPLOYEE_NUMBER': f"E{i+1:06d}",
                'FIRST_NAME': first_name,
                'MIDDLE_NAME': faker.first_name() if random.random() > 0.5 else None,
                'LAST_NAME': last_name,
                'PREFERRED_NAME': first_name if random.random() > 0.8 else None,
                'EMAIL': self._generate_unique_email(first_name, last_name, 'company.com'),
                'PERSONAL_EMAIL': self._generate_unique_email(first_name, last_name, 'gmail.com'),
                'PHONE_WORK': self._generate_phone(region),
                'PHONE_MOBILE': self._generate_phone(region),
                'SSN': self._generate_ssn(),
                'DATE_OF_BIRTH': str(dob),
                'GENDER': random.choice(['Male', 'Female', 'Non-binary', 'Prefer not to say']),
                'NATIONALITY': faker.country(),
                'HOME_ADDRESS_LINE1': faker.street_address(),
                'HOME_ADDRESS_LINE2': faker.secondary_address() if random.random() > 0.7 else None,
                'HOME_CITY': faker.city(),
                'HOME_STATE': faker.state() if region == 'North America' else faker.city(),
                'HOME_POSTAL_CODE': faker.postcode(),
                'HOME_COUNTRY': self.fake.country_for_region(region),
                'HIRE_DATE': str(hire_date),
                'TERMINATION_DATE': str(hire_date + timedelta(days=random.randint(365, 2000))) if random.random() < 0.1 else None,
                'EMPLOYMENT_STATUS': self.fake.employment_status(),
                'EMPLOYMENT_TYPE': self.fake.employment_type(),
                'JOB_TITLE': f"{level} {department} {'Manager' if 'Manager' in level else 'Specialist'}",
                'JOB_LEVEL': level,
                'DEPARTMENT_ID': f"DEPT-{DEPARTMENTS.index(department)+1:03d}",
                'DEPARTMENT_NAME': department,
                'DIVISION': random.choice(['Corporate', 'Commercial', 'Consumer', 'Enterprise']),
                'COST_CENTER': f"CC-{random.randint(100, 999)}",
                'MANAGER_ID': f"EMP-{random.randint(1, max(1, i)):06d}" if i > 0 and level not in ['VP', 'C-Level'] else None,
                'MANAGER_NAME': None,
                'WORK_LOCATION': f"{faker.city()} Office",
                'WORK_CITY': faker.city(),
                'WORK_STATE': faker.state() if region == 'North America' else None,
                'WORK_COUNTRY': self.fake.country_for_region(region),
                'REMOTE_WORKER': random.random() > 0.6,
                'BASE_SALARY': salary,
                'SALARY_CURRENCY': 'USD',
                'PAY_FREQUENCY': 'Bi-Weekly',
                'BONUS_TARGET_PERCENT': random.choice([0, 5, 10, 15, 20, 25, 30]),
                'STOCK_OPTIONS': random.randint(0, 10000) if level in ['Lead', 'Manager', 'Director', 'VP', 'C-Level'] else 0,
                '_SOURCE_SYSTEM': 'HR',
                '_SOURCE_TABLE': 'EMPLOYEE'
            }
            
            employee['_ROW_HASH'] = self._calculate_hash(employee)
            
            self.employees.append(employee)
            self.employee_ids.append(emp_id)
        
        return self.employees
    
    # =========================================================================
    # DEPARTMENT GENERATION
    # =========================================================================
    
    def generate_departments(self) -> List[Dict]:
        """Generate department records"""
        print(f"Generating departments...")
        
        for i, dept_name in enumerate(DEPARTMENTS):
            dept_id = f"DEPT-{i+1:03d}"
            
            department = {
                'DEPARTMENT_ID': dept_id,
                'DEPARTMENT_CODE': dept_name[:3].upper(),
                'DEPARTMENT_NAME': dept_name,
                'DEPARTMENT_DESCRIPTION': f"The {dept_name} department handles all {dept_name.lower()}-related functions.",
                'PARENT_DEPARTMENT_ID': None,
                'DIVISION': random.choice(['Corporate', 'Commercial', 'Consumer', 'Enterprise']),
                'BUSINESS_UNIT': 'Main',
                'DEPARTMENT_HEAD_ID': f"EMP-{random.randint(1, 100):06d}",
                'DEPARTMENT_HEAD_NAME': None,
                'COST_CENTER': f"CC-{100 + i * 10}",
                'BUDGET_AMOUNT': round(random.uniform(500000, 5000000), 2),
                'HEADCOUNT_BUDGET': random.randint(10, 200),
                'IS_ACTIVE': True,
                'EFFECTIVE_DATE': '2020-01-01',
                'END_DATE': None,
                'PRIMARY_LOCATION': 'Headquarters',
                '_SOURCE_SYSTEM': 'HR',
                '_SOURCE_TABLE': 'DEPARTMENT'
            }
            
            department['_ROW_HASH'] = self._calculate_hash(department)
            
            self.departments.append(department)
            self.department_ids.append(dept_id)
        
        return self.departments
    
    # =========================================================================
    # MASTER GENERATION
    # =========================================================================
    
    def generate_all(self,
                     num_customers: int = 10000,
                     num_products: int = 500,
                     num_orders: int = 50000,
                     num_employees: int = 1000) -> Dict[str, List[Dict]]:
        """Generate all synthetic data"""
        
        print("=" * 60)
        print("SYNTHETIC DATA GENERATOR")
        print("Snowflake Data Cloud Architecture Demo")
        print("=" * 60)
        
        # Generate in dependency order
        self.generate_departments()
        self.generate_employees(num_employees)
        self.generate_customers(num_customers)
        self.generate_products(num_products)
        self.generate_orders(num_orders)
        
        print("\n" + "=" * 60)
        print("GENERATION COMPLETE")
        print("=" * 60)
        print(f"  Departments:    {len(self.departments):,}")
        print(f"  Employees:      {len(self.employees):,}")
        print(f"  Customers:      {len(self.customers):,}")
        print(f"  Products:       {len(self.products):,}")
        print(f"  Orders:         {len(self.orders):,}")
        print("=" * 60)
        
        return {
            'departments': self.departments,
            'employees': self.employees,
            'customers': self.customers,
            'products': self.products,
            'orders': self.orders
        }


# ============================================================================
# OUTPUT FUNCTIONS
# ============================================================================

def save_to_csv(data: Dict[str, List[Dict]], output_dir: str):
    """Save data to CSV files"""
    os.makedirs(output_dir, exist_ok=True)
    
    for table_name, records in data.items():
        if not records:
            continue
        
        filepath = os.path.join(output_dir, f"{table_name}.csv")
        print(f"Writing {filepath}...")
        
        with open(filepath, 'w', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=records[0].keys())
            writer.writeheader()
            writer.writerows(records)


def save_to_json(data: Dict[str, List[Dict]], output_dir: str):
    """Save data to JSON files"""
    os.makedirs(output_dir, exist_ok=True)
    
    for table_name, records in data.items():
        if not records:
            continue
        
        filepath = os.path.join(output_dir, f"{table_name}.json")
        print(f"Writing {filepath}...")
        
        with open(filepath, 'w', encoding='utf-8') as f:
            json.dump(records, f, indent=2, default=str)


def save_to_parquet(data: Dict[str, List[Dict]], output_dir: str):
    """Save data to Parquet files"""
    try:
        import pyarrow as pa
        import pyarrow.parquet as pq
    except ImportError:
        print("pyarrow not installed. Run: pip install pyarrow")
        print("Falling back to CSV format...")
        save_to_csv(data, output_dir)
        return
    
    os.makedirs(output_dir, exist_ok=True)
    
    for table_name, records in data.items():
        if not records:
            continue
        
        filepath = os.path.join(output_dir, f"{table_name}.parquet")
        print(f"Writing {filepath}...")
        
        table = pa.Table.from_pylist(records)
        pq.write_table(table, filepath)


# ============================================================================
# CLI ENTRY POINT
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Generate synthetic data for Snowflake DCA demo",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate default CRM dataset
  python data_generator.py --output ../data
  
  # Quick test dataset
  python data_generator.py --output ../data --quick
  
  # Custom counts
  python data_generator.py --customers 50000 --orders 200000 --output ../data
  
  # Parquet output
  python data_generator.py --output ../data --format parquet
        """
    )
    
    parser.add_argument(
        "--output", "-o",
        default="./data",
        help="Output directory (default: ./data)"
    )
    
    parser.add_argument(
        "--format", "-f",
        choices=["csv", "json", "parquet"],
        default="csv",
        help="Output format (default: csv)"
    )
    
    parser.add_argument(
        "--seed", "-s",
        type=int,
        default=42,
        help="Random seed for reproducibility (default: 42)"
    )
    
    parser.add_argument(
        "--customers",
        type=int,
        default=10000,
        help="Number of customers (default: 10000)"
    )
    
    parser.add_argument(
        "--products",
        type=int,
        default=500,
        help="Number of products (default: 500)"
    )
    
    parser.add_argument(
        "--orders",
        type=int,
        default=50000,
        help="Number of orders (default: 50000)"
    )
    
    parser.add_argument(
        "--employees",
        type=int,
        default=1000,
        help="Number of employees (default: 1000)"
    )
    
    parser.add_argument(
        "--quick",
        action="store_true",
        help="Generate small test dataset"
    )
    
    parser.add_argument(
        "--domain",
        choices=["crm", "hr", "all"],
        default="all",
        help="Domain to generate (default: all)"
    )
    
    args = parser.parse_args()
    
    # Quick mode overrides
    if args.quick:
        args.customers = 1000
        args.products = 100
        args.orders = 5000
        args.employees = 100
    
    # Generate data
    generator = SyntheticDataGenerator(seed=args.seed)
    data = generator.generate_all(
        num_customers=args.customers,
        num_products=args.products,
        num_orders=args.orders,
        num_employees=args.employees
    )
    
    # Save output
    print(f"\nSaving to {args.output} in {args.format} format...")
    
    if args.format == "csv":
        save_to_csv(data, args.output)
    elif args.format == "json":
        save_to_json(data, args.output)
    elif args.format == "parquet":
        save_to_parquet(data, args.output)
    
    print(f"\nDone! Files saved to: {args.output}/")
    print("\nTo load into Snowflake:")
    print(f"  1. PUT file://{args.output}/*.{args.format} @RAW_DEV.STAGING.DATA_STAGE")
    print("  2. Run sql/04_load_data.sql to load into RAW tables")


if __name__ == "__main__":
    main()
