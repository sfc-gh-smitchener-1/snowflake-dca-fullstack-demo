-- ============================================================================
-- HCLS DEMO — INTENTIONAL HIPAA GOVERNANCE GAPS
-- ============================================================================
-- Creates demonstration objects that exhibit HIPAA compliance failures
-- the Knowledge Graph should detect via RAI inference.
--
-- Gaps introduced:
--   1. PHI column propagated without HIPAA classification
--   2. Clinical dataset shared to non-HIPAA-compliant role
--   3. Patient matching table with SSNs and no masking
--   4. Research dataset from PHI without de-identification record
--   5. External role accessing encounter data without BAA
--
-- RUN AS: SYSADMIN (after base scripts)
-- ============================================================================

USE ROLE SYSADMIN;
USE DATABASE CURATED_DEV;
USE WAREHOUSE COMPUTE_WH;

-- ── Gap 1: PHI propagated without HIPAA classification ────────────────────
-- An analytics extract that pulls PHI columns (birthDate, gender, zip)
-- from DIM_PATIENT but has NO HIPAA_CATEGORY tags applied.
-- No masking policy protects downstream consumers.

CREATE OR REPLACE TABLE CURATED_DEV.FHIR.PATIENT_ANALYTICS_EXTRACT (
    patient_id      VARCHAR(100)  COMMENT 'Patient identifier — PHI',
    birth_date      DATE          COMMENT 'Date of birth — PHI (no HIPAA tag applied)',
    gender          VARCHAR(20)   COMMENT 'Patient gender — PHI (no HIPAA tag applied)',
    zip_code        VARCHAR(10)   COMMENT 'Postal code — PHI geographic identifier (no HIPAA tag applied)',
    ethnicity       VARCHAR(100),
    language        VARCHAR(50),
    extracted_at    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Analytics extract from DIM_PATIENT. WARNING: Contains PHI columns without HIPAA_CATEGORY classification. No masking policy applied. Created for population health dashboard — pending governance review.';

INSERT INTO CURATED_DEV.FHIR.PATIENT_ANALYTICS_EXTRACT
    (patient_id, birth_date, gender, zip_code, ethnicity, language)
SELECT
    PATIENT_ID,
    BIRTH_DATE,
    GENDER,
    ZIP_CODE,
    ETHNICITY,
    LANGUAGE
FROM CURATED_DEV.FHIR.DIM_PATIENT;

-- INTENTIONAL OMISSION: No HIPAA_CATEGORY tag applied to birth_date, gender, zip_code.
-- No masking policy. No data_contract_owner. No data_purpose tag.
-- This table will be flagged by SP_HCLS_PHI_DETECTION() as untagged PHI.

GRANT SELECT ON TABLE CURATED_DEV.FHIR.PATIENT_ANALYTICS_EXTRACT TO ROLE HEALTHCARE_CONSUMER;

-- ── Gap 2: Clinical dataset shared to non-HIPAA-compliant role ────────────
-- FACT_ENCOUNTERS contains patient_key, dates, and clinical data.
-- Granting SELECT to a non-healthcare role violates minimum necessary access.
-- No BAA documentation exists for this role.

GRANT SELECT ON TABLE CURATED_DEV.FHIR.FACT_ENCOUNTERS TO ROLE MARKETPLACE_CONSUMER;

-- INTENTIONAL VIOLATION: MARKETPLACE_CONSUMER is not a HIPAA-covered entity.
-- No Business Associate Agreement (BAA) edge exists in the Knowledge Graph.
-- The RAI inference should flag this as a compliance violation.

-- ── Gap 3: Patient matching table with SSNs and no masking ────────────────
-- Created for Master Patient Index (MPI) reconciliation.
-- Contains SSNs in plaintext with no masking policy.
-- Highest-severity PHI exposure.

CREATE OR REPLACE TABLE CURATED_DEV.FHIR.PATIENT_MATCH_STAGING (
    patient_id      VARCHAR(100)  COMMENT 'Internal patient identifier',
    full_name       VARCHAR(200)  COMMENT 'Full legal name — PHI',
    ssn             VARCHAR(11)   COMMENT 'Social Security Number — CRITICAL PHI (no masking applied)',
    dob             DATE          COMMENT 'Date of birth — PHI',
    source_system   VARCHAR(50)   COMMENT 'Origin system (FHIR, Workday, etc.)',
    match_status    VARCHAR(20)   DEFAULT 'PENDING',
    loaded_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'MPI staging table for patient matching across systems. CRITICAL: Contains unmasked SSN. No masking policy. No HIPAA_CATEGORY tag. Pending security review.';

-- Simulate loading MPI candidates
INSERT INTO CURATED_DEV.FHIR.PATIENT_MATCH_STAGING
    (patient_id, full_name, ssn, dob, source_system)
SELECT
    PATIENT_ID,
    COALESCE(FIRST_NAME || ' ' || LAST_NAME, 'UNKNOWN'),
    -- Simulated SSN (not real data — deterministic hash for demo)
    SUBSTRING(MD5(PATIENT_ID), 1, 3) || '-' ||
    SUBSTRING(MD5(PATIENT_ID), 4, 2) || '-' ||
    SUBSTRING(MD5(PATIENT_ID), 6, 4) AS ssn,
    BIRTH_DATE,
    'FHIR'
FROM CURATED_DEV.FHIR.DIM_PATIENT;

-- INTENTIONAL OMISSION: No masking policy on SSN column.
-- No HIPAA_CATEGORY tag. No pii_category tag. No encryption at column level.
-- Accessible to any role with FHIR schema privileges.

-- ── Gap 4: Research dataset from PHI without de-identification record ─────
-- Derived from patient encounters for readmission research.
-- No data_contract_owner, no IRB reference, no de-identification audit trail.
-- Owned by SYSADMIN — no accountable clinical data steward.

USE DATABASE DCA_DEMO;

CREATE OR REPLACE TABLE DCA_DEMO.SEMANTIC_FINANCE.READMISSION_RESEARCH (
    patient_cohort_id   VARCHAR(100)  COMMENT 'Derived patient identifier',
    admission_count     INTEGER       COMMENT 'Number of admissions in study period',
    avg_los_days        FLOAT         COMMENT 'Average length of stay in days',
    primary_diagnosis   VARCHAR(200)  COMMENT 'Most frequent diagnosis code',
    readmit_30_day      BOOLEAN       COMMENT 'Readmitted within 30 days flag',
    age_at_first_admit  INTEGER       COMMENT 'Age at first admission — derived PHI',
    zip_3_digit         VARCHAR(3)    COMMENT 'First 3 digits of zip — geographic PHI',
    study_period_start  DATE,
    study_period_end    DATE,
    generated_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Readmission research dataset. ISSUES: No data_contract_owner. No IRB reference. No DE_IDENTIFIED_FROM lineage edge. Owned by SYSADMIN (no clinical steward). Contains quasi-identifiers (age + zip3 + diagnosis).';

-- Simulate research data derivation
INSERT INTO DCA_DEMO.SEMANTIC_FINANCE.READMISSION_RESEARCH
    (patient_cohort_id, admission_count, avg_los_days, primary_diagnosis,
     readmit_30_day, age_at_first_admit, zip_3_digit, study_period_start, study_period_end)
SELECT
    MD5(PATIENT_ID) AS patient_cohort_id,
    ABS(MOD(HASH(PATIENT_ID || 'admissions'), 8)) + 1 AS admission_count,
    ROUND(ABS(MOD(HASH(PATIENT_ID || 'los'), 14)) + 1 + RANDOM() / 1e18, 1) AS avg_los_days,
    CASE MOD(ABS(HASH(PATIENT_ID)), 5)
        WHEN 0 THEN 'J18.9 - Pneumonia'
        WHEN 1 THEN 'I50.9 - Heart failure'
        WHEN 2 THEN 'J44.1 - COPD exacerbation'
        WHEN 3 THEN 'N17.9 - Acute kidney failure'
        ELSE 'E11.65 - Type 2 diabetes'
    END AS primary_diagnosis,
    MOD(ABS(HASH(PATIENT_ID || 'readmit')), 4) = 0 AS readmit_30_day,
    DATEDIFF('year', BIRTH_DATE, CURRENT_DATE()) AS age_at_first_admit,
    LEFT(ZIP_CODE, 3) AS zip_3_digit,
    '2024-01-01'::DATE AS study_period_start,
    '2024-12-31'::DATE AS study_period_end
FROM CURATED_DEV.FHIR.DIM_PATIENT;

-- INTENTIONAL OMISSIONS: No data_contract_version tag. No data_contract_owner.
-- No data_purpose tag. No IRB approval reference. No DE_IDENTIFIED_FROM edge.
-- Table owner is SYSADMIN — violates clinical data stewardship requirements.

-- ── Gap 5: External role accessing encounter data without BAA ─────────────
-- EXTERNAL_PARTNER role gets SELECT on encounter data.
-- No Business Associate Agreement (BAA) documentation exists.
-- No governance edge records this access grant in the Knowledge Graph.

USE DATABASE CURATED_DEV;

-- Create the external partner role if it doesn't exist
CREATE ROLE IF NOT EXISTS EXTERNAL_PARTNER
    COMMENT = 'External partner role for data sharing. NOTE: No BAA on file.';

GRANT USAGE ON DATABASE CURATED_DEV TO ROLE EXTERNAL_PARTNER;
GRANT USAGE ON SCHEMA CURATED_DEV.FHIR TO ROLE EXTERNAL_PARTNER;
GRANT SELECT ON TABLE CURATED_DEV.FHIR.FACT_ENCOUNTERS TO ROLE EXTERNAL_PARTNER;

-- INTENTIONAL VIOLATION: External access to PHI without BAA.
-- No governance edge in the Knowledge Graph records BAA status.
-- SP_HCLS_HIPAA_SCORING() should flag baa_coverage = 0 for this grant.

-- ═══════════════════════════════════════════════════════════════════════════
-- GAP SUMMARY
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'HCLS HIPAA gaps created — 5 intentional compliance failures' AS status;

SELECT gap_id, gap_type, severity, object_name, gap_description FROM VALUES
    (1, 'PHI without HIPAA classification', 'HIGH',
     'CURATED_DEV.FHIR.PATIENT_ANALYTICS_EXTRACT',
     'Contains birth_date, gender, zip_code from DIM_PATIENT with no HIPAA_CATEGORY tags. No masking policy applied.'),
    (2, 'PHI shared to non-covered entity', 'CRITICAL',
     'CURATED_DEV.FHIR.FACT_ENCOUNTERS → MARKETPLACE_CONSUMER',
     'Clinical encounter data (patient_key, dates, diagnoses) accessible by non-healthcare role without BAA.'),
    (3, 'Unmasked SSN in staging table', 'CRITICAL',
     'CURATED_DEV.FHIR.PATIENT_MATCH_STAGING',
     'MPI staging contains plaintext SSN column. No masking policy. No HIPAA tag. Highest-severity PHI exposure.'),
    (4, 'Research data without de-identification', 'HIGH',
     'DCA_DEMO.SEMANTIC_FINANCE.READMISSION_RESEARCH',
     'Derived from PHI without IRB reference or DE_IDENTIFIED_FROM lineage. Contains quasi-identifiers. No data steward.'),
    (5, 'External access without BAA', 'CRITICAL',
     'CURATED_DEV.FHIR.FACT_ENCOUNTERS → EXTERNAL_PARTNER',
     'External role granted SELECT on encounter PHI. No Business Associate Agreement documented in governance graph.')
    AS t(gap_id, gap_type, severity, object_name, gap_description)
ORDER BY gap_id;
