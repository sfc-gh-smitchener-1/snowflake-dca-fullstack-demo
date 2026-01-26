# Data Generation Guide

## Overview

The Snowflake DCA Demo includes a **source system-aware data generator** that produces realistic synthetic data mirroring actual enterprise systems. This isn't generic fake data — it's data structured exactly like what comes from SAP, Salesforce, Oracle, FHIR, Workday, and ServiceNow.

### Supported Source Systems

| System | Modules/Domains | Tables/Objects |
|--------|----------------|----------------|
| **SAP S/4HANA** | Sales, Procurement, Finance, HR | KNA1, MARA, VBAK, VBAP, LFA1, EKKO, BKPF, PA0001, PA0002 |
| **Salesforce** | Sales, Service, Marketing | Account, Contact, Opportunity, Case, Lead, Product2, Campaign, Task |
| **Oracle EBS** | Order Mgmt, AP, AR, GL, HR | HZ_PARTIES, OE_ORDER_*, AP_*, RA_*, GL_JE_LINES, HR_* |
| **FHIR R4** | Clinical, Billing, Providers | Patient, Encounter, Condition, Observation, Practitioner, Claim |
| **Workday** | HCM, Compensation, Benefits | Workers, Organizations, Compensation, Time_Off, Benefits |
| **ServiceNow** | ITSM, CMDB, Knowledge | incident, change_request, problem, cmdb_ci, sc_request, kb_knowledge |

---

## Quick Start

```bash
cd tools
pip install -r requirements.txt

# SAP Full Suite
python data_generator.py --system sap --domain all --output ../data

# Salesforce Sales Cloud
python data_generator.py --system salesforce --domain sales --output ../data

# Oracle EBS Financials
python data_generator.py --system oracle --domain payables --output ../data

# FHIR Clinical Data
python data_generator.py --system fhir --domain clinical --output ../data

# Workday HCM Full
python data_generator.py --system workday --domain hcm --output ../data

# ServiceNow ITSM
python data_generator.py --system servicenow --domain itsm --output ../data
```

---

## SAP S/4HANA

### Available Domains

| Domain | Tables Generated | Description |
|--------|-----------------|-------------|
| `customers` | KNA1 | Customer master data |
| `materials` | MARA | Material/product master |
| `sales` | KNA1, MARA, VBAK, VBAP | Complete sales order flow |
| `procurement` | LFA1, EKKO | Vendor master and purchase orders |
| `finance` | BKPF | FI accounting documents |
| `hr` | PA0001, PA0002 | HR infotypes |
| `all` | All above | Full SAP dataset |

### Tables Generated

| Table | Description | Key Fields |
|-------|-------------|------------|
| **KNA1** | Customer Master (General) | MANDT, KUNNR, NAME1, LAND1, ORT01, KTOKD |
| **MARA** | Material Master (General) | MANDT, MATNR, MTART, MATKL, MEINS, MAKTX |
| **VBAK** | Sales Document Header | MANDT, VBELN, VKORG, AUART, KUNNR, NETWR |
| **VBAP** | Sales Document Item | MANDT, VBELN, POSNR, MATNR, KWMENG, NETWR |
| **LFA1** | Vendor Master (General) | MANDT, LIFNR, NAME1, LAND1, KTOKK |
| **EKKO** | Purchase Order Header | MANDT, EBELN, BUKRS, LIFNR, BEDAT, RLWRT |
| **BKPF** | FI Document Header | MANDT, BUKRS, BELNR, GJAHR, BLART, BUDAT |
| **PA0001** | HR Org Assignment | MANDT, PERNR, BUKRS, WERKS, KOSTL, ORGEH |
| **PA0002** | HR Personal Data | MANDT, PERNR, VORNA, NACHN, GBDAT, GESSION |

### Example Commands

```bash
# Full SAP dataset for migration demo
python data_generator.py --system sap --domain all --output ../data

# Just sales orders with customers and materials
python data_generator.py --system sap --domain sales --output ../data

# Procurement data only
python data_generator.py --system sap --domain procurement --output ../data

# Scale up for load testing
python data_generator.py --system sap --domain all --scale 10 --output ../data
```

---

## Salesforce

### Available Domains

| Domain | Objects Generated | Description |
|--------|------------------|-------------|
| `sales` | Account, Contact, Opportunity, Lead | Sales Cloud core |
| `service` | Account, Contact, Case | Service Cloud |
| `marketing` | Account, Contact, Lead, Campaign | Marketing Cloud |
| `products` | Product2 | Product catalog |
| `activities` | Account, Contact, Task | Activity tracking |
| `all` | All above | Full Salesforce org |

### Objects Generated

| Object | Description | Key Fields |
|--------|-------------|------------|
| **Account** | Company/organization | Id, Name, Industry, AnnualRevenue, Type |
| **Contact** | Person record | Id, AccountId, FirstName, LastName, Email |
| **Opportunity** | Sales deal | Id, AccountId, Amount, StageName, CloseDate |
| **Case** | Support case | Id, CaseNumber, Subject, Status, Priority |
| **Lead** | Prospect | Id, Company, FirstName, LastName, Status |
| **Product2** | Product | Id, Name, ProductCode, Family, IsActive |
| **Campaign** | Marketing campaign | Id, Name, Type, Status, BudgetedCost |
| **Task** | Activity | Id, Subject, WhoId, WhatId, Status, Priority |

### Example Commands

```bash
# Full Sales Cloud
python data_generator.py --system salesforce --domain sales --output ../data

# Service Cloud for case management demo
python data_generator.py --system salesforce --domain service --output ../data

# Everything
python data_generator.py --system salesforce --domain all --output ../data
```

---

## Oracle E-Business Suite

### Available Domains

| Domain | Tables Generated | Description |
|--------|-----------------|-------------|
| `customers` | HZ_PARTIES | TCA customer master |
| `products` | MTL_SYSTEM_ITEMS_B | Inventory items |
| `orders` | OE_ORDER_HEADERS_ALL, OE_ORDER_LINES_ALL | Order management |
| `procurement` | AP_SUPPLIERS | Supplier master |
| `payables` | AP_SUPPLIERS, AP_INVOICES_ALL | Accounts payable |
| `receivables` | HZ_PARTIES, RA_CUSTOMER_TRX_ALL | Accounts receivable |
| `gl` | GL_JE_LINES | General ledger |
| `hr` | HR_ALL_PEOPLE_F | Human resources |
| `all` | All above | Full Oracle EBS |

### Tables Generated

| Table | Description | Key Fields |
|-------|-------------|------------|
| **HZ_PARTIES** | TCA Party Master | PARTY_ID, PARTY_NAME, PARTY_TYPE, STATUS |
| **MTL_SYSTEM_ITEMS_B** | Inventory Items | INVENTORY_ITEM_ID, SEGMENT1, DESCRIPTION |
| **OE_ORDER_HEADERS_ALL** | Order Headers | HEADER_ID, ORDER_NUMBER, ORG_ID, FLOW_STATUS_CODE |
| **OE_ORDER_LINES_ALL** | Order Lines | LINE_ID, HEADER_ID, ORDERED_QUANTITY, UNIT_SELLING_PRICE |
| **AP_SUPPLIERS** | Vendor Master | VENDOR_ID, VENDOR_NAME, SEGMENT1, ENABLED_FLAG |
| **AP_INVOICES_ALL** | Payables Invoices | INVOICE_ID, INVOICE_NUM, VENDOR_ID, INVOICE_AMOUNT |
| **RA_CUSTOMER_TRX_ALL** | Receivables Invoices | CUSTOMER_TRX_ID, TRX_NUMBER, BILL_TO_CUSTOMER_ID |
| **GL_JE_LINES** | GL Journal Lines | JE_HEADER_ID, JE_LINE_NUM, ENTERED_DR, ENTERED_CR |
| **HR_ALL_PEOPLE_F** | Employee Master | PERSON_ID, EMPLOYEE_NUMBER, FIRST_NAME, LAST_NAME |

### Example Commands

```bash
# Full Oracle EBS Suite
python data_generator.py --system oracle --domain all --output ../data

# Just financials (AP, AR, GL)
python data_generator.py --system oracle --domain payables --output ../data
python data_generator.py --system oracle --domain receivables --output ../data
python data_generator.py --system oracle --domain gl --output ../data
```

---

## HL7 FHIR R4

### Available Domains

| Domain | Resources Generated | Description |
|--------|-------------------|-------------|
| `patients` | Patient | Patient demographics |
| `providers` | Practitioner, Organization | Healthcare providers |
| `encounters` | Patient, Encounter | Patient visits |
| `clinical` | Patient, Encounter, Condition, Observation, Procedure | Clinical data |
| `medications` | Patient, Practitioner, MedicationRequest | Prescriptions |
| `billing` | Patient, Organization, Claim | Healthcare claims |
| `all` | All above | Full clinical dataset |

### Resources Generated

| Resource | Description | Key Elements |
|----------|-------------|--------------|
| **Patient** | Individual receiving care | identifier, name, birthDate, gender, address |
| **Practitioner** | Healthcare provider | identifier (NPI), name, qualification |
| **Organization** | Hospital/clinic | identifier, name, type, address |
| **Encounter** | Patient visit | status, class, subject, period |
| **Condition** | Diagnosis | code (ICD-10), clinicalStatus, subject |
| **Observation** | Labs, vitals | code (LOINC), valueQuantity, status |
| **MedicationRequest** | Prescription | medication (RxNorm), dosageInstruction |
| **Procedure** | Medical procedure | code (SNOMED), status, performedDateTime |
| **Claim** | Healthcare claim | type, patient, provider, total |

### Medical Code Systems

| System | Used For | Examples |
|--------|----------|----------|
| ICD-10 | Diagnoses | E11.9, I10, J45.909 |
| LOINC | Labs/Vitals | 8867-4, 8480-6, 2339-0 |
| SNOMED CT | Procedures | 80146002, 73761001 |
| RxNorm | Medications | 197361, 310965 |
| NPI | Provider IDs | 10-digit identifiers |

### Example Commands

```bash
# Full clinical dataset for analytics
python data_generator.py --system fhir --domain all --output ../data

# Clinical data without billing
python data_generator.py --system fhir --domain clinical --output ../data

# Just patient demographics
python data_generator.py --system fhir --domain patients --output ../data
```

---

## Workday HCM

### Available Domains

| Domain | Reports Generated | Description |
|--------|------------------|-------------|
| `workers` | Workers | Employee/contingent workers |
| `organizations` | Organizations | Supervisory orgs |
| `jobs` | Job_Profiles | Job catalog |
| `compensation` | Workers, Compensation | Pay data |
| `time` | Workers, Time_Off | Leave requests |
| `benefits` | Workers, Benefit_Elections | Benefit enrollments |
| `hcm` | All HCM data | Full HCM suite |
| `all` | All above | Complete Workday dataset |

### Reports Generated

| Report | Description | Key Fields |
|--------|-------------|------------|
| **Workers** | Employee master | Worker_WID, Employee_ID, Legal_Name, Hire_Date, Active_Status |
| **Organizations** | Supervisory orgs | Organization_WID, Organization_Name, Manager_WID |
| **Job_Profiles** | Job catalog | Job_Profile_WID, Job_Profile_Name, Job_Family, Job_Level |
| **Compensation** | Pay data | Worker_WID, Base_Pay_Amount, Total_Compensation, Compa_Ratio |
| **Time_Off** | Leave requests | Worker_WID, Time_Off_Type, Start_Date, Total_Days, Status |
| **Benefit_Elections** | Enrollments | Worker_WID, Benefit_Plan_Type, Coverage_Level, Employee_Cost |

### Example Commands

```bash
# Full HCM suite
python data_generator.py --system workday --domain hcm --output ../data

# Just workers and compensation
python data_generator.py --system workday --domain compensation --output ../data

# Benefits open enrollment analysis
python data_generator.py --system workday --domain benefits --output ../data
```

---

## ServiceNow

### Available Domains

| Domain | Tables Generated | Description |
|--------|-----------------|-------------|
| `users` | sys_user | User accounts |
| `incidents` | sys_user, incident | IT incidents |
| `changes` | sys_user, change_request | Change management |
| `problems` | sys_user, problem | Problem management |
| `cmdb` | cmdb_ci | Configuration items |
| `requests` | sys_user, sc_request | Service catalog |
| `knowledge` | sys_user, kb_knowledge | Knowledge base |
| `itsm` | Users + Incidents + Changes + Problems | Core ITSM |
| `all` | All above | Full ServiceNow |

### Tables Generated

| Table | Description | Key Fields |
|-------|-------------|------------|
| **sys_user** | User records | sys_id, user_name, name, email, active |
| **incident** | IT incidents | sys_id, number, state, priority, short_description |
| **change_request** | Changes | sys_id, number, state, type, risk, start_date |
| **problem** | Problems | sys_id, number, state, known_error, cause |
| **cmdb_ci** | Config items | sys_id, name, sys_class_name, install_status, ip_address |
| **sc_request** | Service requests | sys_id, number, request_state, requested_for, price |
| **kb_knowledge** | KB articles | sys_id, number, short_description, workflow_state, view_count |

### Example Commands

```bash
# Core ITSM data
python data_generator.py --system servicenow --domain itsm --output ../data

# CMDB for asset management demo
python data_generator.py --system servicenow --domain cmdb --output ../data

# Full ServiceNow dataset
python data_generator.py --system servicenow --domain all --output ../data
```

---

## Command Reference

```
python data_generator.py [OPTIONS]

Required:
  --system, -s    Source system: sap, salesforce, oracle, fhir, workday, servicenow

Optional:
  --domain, -d    Data domain (see tables above, default: all)
  --output, -o    Output directory (default: ./data)
  --format, -f    Output format: csv, json (default: csv)
  --seed          Random seed for reproducibility (default: 42)
  --quick         Generate small test dataset (1/10th size)
  --scale         Scale factor for record counts (default: 1.0)
```

---

## Loading into Snowflake

### 1. Upload to Stage

```bash
# Upload all generated data
snowsql -q "PUT file://data/*/*.csv @RAW_DEV.STAGING.DATA_STAGE/ auto_compress=true"
```

### 2. Create Source-Specific Schemas

```sql
-- Create schemas for each source system
CREATE SCHEMA IF NOT EXISTS RAW_DEV.SAP;
CREATE SCHEMA IF NOT EXISTS RAW_DEV.SALESFORCE;
CREATE SCHEMA IF NOT EXISTS RAW_DEV.ORACLE;
CREATE SCHEMA IF NOT EXISTS RAW_DEV.FHIR;
CREATE SCHEMA IF NOT EXISTS RAW_DEV.WORKDAY;
CREATE SCHEMA IF NOT EXISTS RAW_DEV.SERVICENOW;
```

### 3. Load with COPY INTO

```sql
-- Example: Load SAP KNA1
COPY INTO RAW_DEV.SAP.KNA1
FROM @RAW_DEV.STAGING.DATA_STAGE/sap_s4hana/KNA1.csv
FILE_FORMAT = (TYPE = 'CSV' SKIP_HEADER = 1 FIELD_OPTIONALLY_ENCLOSED_BY = '"')
ON_ERROR = 'CONTINUE';
```

---

## Best Practices

1. **Match Your Source System**: Use the generator that matches your actual source for realistic demos
2. **Use Consistent Seeds**: Same seed produces identical data for reproducible testing
3. **Start Small**: Use `--quick` for development, scale up for load testing
4. **Combine Domains**: Generate related domains together for referential integrity
5. **Use JSON for FHIR**: FHIR data preserves nested structures better in JSON format

```bash
# FHIR as JSON for nested CodeableConcepts
python data_generator.py --system fhir --domain all --format json --output ../data
```

---

## Extending for Custom Systems

Add a new generator by extending `SourceSystemGenerator`:

```python
class MyERPGenerator(SourceSystemGenerator):
    SYSTEM_NAME = "MY_ERP"
    
    def generate(self, counts: Dict[str, int]) -> Dict[str, List[Dict]]:
        result = {}
        if counts.get('customers', 0) > 0:
            result['CUSTOMERS'] = self.generate_customers(counts['customers'])
        return result
    
    def generate_customers(self, count: int) -> List[Dict]:
        records = []
        for i in range(count):
            record = {
                'CUST_ID': f"C{i+1:08d}",
                'CUST_NAME': self.fake.company(),
                # ... your system-specific fields
            }
            record['_SOURCE_TABLE'] = 'CUSTOMERS'
            record['_ROW_HASH'] = self._calculate_hash(record)
            record.update(self.get_metadata_columns())
            records.append(record)
        return records

# Register the generator
SYSTEM_GENERATORS['myerp'] = MyERPGenerator
SYSTEM_DOMAINS['myerp'] = {
    'customers': {'customers': 1000},
    'all': {'customers': 1000}
}
```
