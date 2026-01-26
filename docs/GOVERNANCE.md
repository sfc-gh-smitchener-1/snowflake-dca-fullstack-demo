# Governance Documentation

## Overview

This document details the compliance and governance framework implemented in the Snowflake DCA Full Stack Demo. The architecture supports multiple regulatory frameworks through a unified tag-based governance model.

## Supported Compliance Frameworks

| Framework | Region | Key Requirements | Demo Implementation |
|-----------|--------|------------------|---------------------|
| **GDPR** | EU | Right to erasure, consent tracking, data minimization | `RESIDENCY_REGION`, `GDPR_CATEGORY`, consent columns |
| **HIPAA** | US | PHI protection, access controls, audit trails | `HIPAA_CATEGORY`, restricted access, audit logging |
| **FERPA** | US | Educational records protection | `FERPA_CATEGORY` tag for education data |
| **CCPA** | California | Consumer privacy rights, opt-out | Consent tracking, data deletion support |
| **PCI-DSS** | Global | Payment card data protection | Credit card masking policy |
| **SOC2** | Global | Security controls, availability | Access history, role-based controls |

## Governance Tag Hierarchy

### Data Classification

Defines the sensitivity level of data:

```
DATA_CLASSIFICATION
├── PUBLIC          → No restrictions, publicly available
├── INTERNAL        → Internal employees only
├── CONFIDENTIAL    → Need-to-know basis, business sensitive
└── RESTRICTED      → Highly protected, regulatory requirements
```

### PII Type

Identifies personal information:

```
PII_TYPE
├── NONE            → No personal information
├── INDIRECT        → Quasi-identifiers (zip code, age range)
├── DIRECT          → Direct identifiers (name, email, phone)
└── SENSITIVE       → Highly sensitive (SSN, health, financial)
```

### AI Eligibility

Controls exposure to AI/ML workloads:

```
AI_ALLOWED
├── TRUE            → Safe for all AI workloads
├── FALSE           → Never expose to AI systems
├── PSEUDONYMIZED   → Hash/tokenize before AI use
└── AGGREGATED      → Only in aggregate form for AI
```

### Data Residency

Enforces geographic data requirements:

```
RESIDENCY_REGION
├── GLOBAL          → Can be stored/processed anywhere
├── US_ONLY         → Must remain in United States
├── EU_ONLY         → Must remain in European Union
├── UK_ONLY         → Must remain in United Kingdom
└── ORIGIN          → Must remain in originating region
```

## Masking Policy Matrix

| Policy | Full Access | Partial Access | Masked | NULL |
|--------|-------------|----------------|--------|------|
| `MASK_SSN` | DATA_ADMIN, PII_VIEWER | MANAGER (last 4) | All others | - |
| `MASK_DOB` | DATA_ADMIN, PII_VIEWER | MANAGER, ANALYST (year) | - | AI_AGENT |
| `MASK_EMAIL` | DATA_ADMIN, PII_VIEWER, MANAGER | ANALYST (domain only) | All others | - |
| `MASK_PHONE` | DATA_ADMIN, PII_VIEWER, MANAGER | ANALYST (last 4) | All others | - |
| `MASK_ADDRESS` | DATA_ADMIN, PII_VIEWER | MANAGER (city only) | All others | - |
| `MASK_SALARY` | DATA_ADMIN, PII_VIEWER | MANAGER (rounded) | - | All others |
| `MASK_CREDIT_CARD` | None (PCI) | DATA_ADMIN (last 4) | All | - |

## Row Access Policies

### Geographic Filtering (GDPR)

```sql
-- EU/UK data requires specific authorization
ROW_ACCESS_BY_REGION(data_region STRING)
    → Full access roles: DATA_ADMIN, PII_VIEWER, DATA_STEWARD
    → Non-EU data: Accessible to all internal roles
    → EU/UK data: Restricted from EXTERNAL_PARTNER
```

### Classification Filtering

```sql
-- Filter by sensitivity level
ROW_ACCESS_BY_CLASSIFICATION(classification STRING)
    → PUBLIC: Everyone
    → INTERNAL: All internal roles
    → CONFIDENTIAL: MANAGER, ANALYST, DATA_STEWARD, DATA_ENGINEER
    → RESTRICTED: DATA_ADMIN, PII_VIEWER only
```

## Role-Based Access Control (RBAC)

### Role Hierarchy

```
ACCOUNTADMIN
    └── SYSADMIN
        └── DATA_ADMIN          ← Demo object owner
            ├── DATA_ENGINEER   ← Pipeline management
            ├── DATA_STEWARD    ← Governance management
            │   ├── ANALYST     ← Business analytics
            │   ├── MANAGER     ← Department access
            │   └── AUDITOR     ← Compliance monitoring
            └── PII_VIEWER      ← Privileged PII access
```

### Access by Layer

| Role | GOVERNANCE | RAW | CURATED | SEMANTIC | MARKETPLACE |
|------|------------|-----|---------|----------|-------------|
| DATA_ADMIN | Full | Full | Full | Full | Full |
| DATA_ENGINEER | Read | Full | Full | Read | - |
| DATA_STEWARD | Full | Read | Read | Read | Read |
| ANALYST | - | - | - | Read | Read |
| MANAGER | - | - | - | Read | Read |
| VIEWER | - | - | - | Aggregates | Read |
| AI_AGENT | - | - | - | Pseudonymized | Read |
| EXTERNAL_PARTNER | - | - | - | - | Limited |

## Compliance Implementation

### GDPR Requirements

1. **Right to Erasure (Article 17)**
   - `GDPR_DELETE_REQUESTED` flag on customer records
   - Stored procedures for data deletion requests
   - Audit trail of deletion actions

2. **Consent Tracking (Article 7)**
   - `MARKETING_CONSENT` column
   - `DATA_PROCESSING_CONSENT` column
   - `CONSENT_DATE` timestamp

3. **Data Minimization (Article 5)**
   - Semantic layer exposes only necessary columns
   - Aggregate views for analytics
   - Pseudonymization for AI workloads

### HIPAA Requirements

1. **Access Controls**
   - Role-based access to PHI
   - Minimum necessary access principle
   - Emergency access procedures

2. **Audit Trail**
   - Snowflake ACCESS_HISTORY captures all queries
   - Login history tracking
   - Policy enforcement logging

3. **Encryption**
   - Data encrypted at rest (Snowflake default)
   - Data encrypted in transit (TLS 1.2+)

### PCI-DSS Requirements

1. **Cardholder Data Protection**
   - `MASK_CREDIT_CARD` policy shows max last 4 digits
   - No role sees full card numbers
   - Tokenization for processing

2. **Access Restriction**
   - Principle of least privilege
   - Separation of duties
   - Regular access reviews

## Audit and Monitoring

### Key Monitoring Views

| View | Purpose |
|------|---------|
| `VW_ACCESS_AUDIT` | Recent data access by user/role |
| `VW_LOGIN_HISTORY` | Authentication events |
| `VW_POLICY_USAGE` | Masking/row policy effectiveness |
| `VW_TAG_COVERAGE` | Governance tag completeness |
| `VW_COMPLIANCE_SUMMARY` | Overall compliance metrics |

### Sample Audit Query

```sql
-- Recent PII access
SELECT 
    user_name,
    role_name,
    query_start_time,
    objects_accessed
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY
WHERE ARRAY_CONTAINS('PII_TYPE=SENSITIVE'::VARIANT, 
      FLATTEN(objects_modified_by_ddl):tags)
  AND query_start_time > DATEADD('day', -7, CURRENT_TIMESTAMP())
ORDER BY query_start_time DESC;
```

## Source System Governance Mapping

Each source system has different field naming conventions. The data generator automatically adds governance metadata:

| Source System | PII Fields | Sensitive Fields | Governance Tags |
|--------------|------------|------------------|-----------------|
| **SAP S/4HANA** | NAME1, STRAS, TELF1, SMTP_ADDR | STCEG (VAT) | _SOURCE_SYSTEM, _SOURCE_TABLE |
| **Salesforce** | Email, Phone, BillingStreet | AnnualRevenue | _SOURCE_SYSTEM, _SOURCE_TABLE |
| **Oracle EBS** | PARTY_NAME, ADDRESS1, EMAIL_ADDRESS | NATIONAL_IDENTIFIER | _SOURCE_SYSTEM, _SOURCE_TABLE |
| **FHIR R4** | name.family, telecom, address, identifier | birthDate, SSN | _SOURCE_SYSTEM, _SOURCE_TABLE |
| **Workday** | Legal_First_Name, Email_Work, National_ID | Annual_Salary | _SOURCE_SYSTEM, _SOURCE_TABLE |
| **ServiceNow** | first_name, last_name, email, phone | N/A | _SOURCE_SYSTEM, _SOURCE_TABLE |

All generated records include:
- `_SOURCE_SYSTEM`: Origin system identifier (SAP_S4HANA, SALESFORCE, etc.)
- `_SOURCE_TABLE`: Original table/object name (KNA1, Account, Patient, etc.)
- `_ROW_HASH`: SHA-256 hash for SCD Type 2 change detection
- `_LOADED_AT`: Ingestion timestamp
- `_IS_CURRENT`, `_VALID_FROM`, `_VALID_TO`: SCD Type 2 tracking

## Best Practices

1. **Tag Everything**
   - Apply tags at column level, not just table level
   - Use consistent tag values across the organization
   - Review tag coverage regularly
   - Map source system fields to governance tags during ingestion

2. **Least Privilege**
   - Start with minimal access
   - Add permissions as needed
   - Document justification for elevated access

3. **Defense in Depth**
   - Combine column masking with row access
   - Use network policies where applicable
   - Enable multi-factor authentication

4. **Regular Reviews**
   - Quarterly access reviews
   - Annual policy reviews
   - Continuous monitoring for anomalies

5. **Source System Awareness**
   - Understand PII locations in each source system
   - Apply masking policies based on `_SOURCE_TABLE` metadata
   - Track lineage from source to consumption layer

## References

- [Snowflake Horizon](https://www.snowflake.com/en/data-cloud/horizon/)
- [Object Tagging](https://docs.snowflake.com/en/user-guide/object-tagging)
- [Dynamic Data Masking](https://docs.snowflake.com/en/user-guide/security-column-ddm-intro)
- [Row Access Policies](https://docs.snowflake.com/en/user-guide/security-row-intro)
- [GDPR Guide](https://gdpr.eu/)
- [HIPAA Guide](https://www.hhs.gov/hipaa/)
