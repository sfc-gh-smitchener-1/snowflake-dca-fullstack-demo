-- ============================================================================
-- HCLS DATA LOADING — Schema Setup & Manual Load Helpers
-- ============================================================================
-- NOTE: After loading raw data, run BUILD_CURATED_LAYER for each source system
-- to create Dynamic Tables in CURATED_DEV (FHIR, WORKDAY_HCM, PAYER schemas).
-- Creates HCLS-specific schemas in RAW_DEV and provides COPY INTO
-- statements for manual loading. Use this if the automated
-- build_and_load.py script isn't available.
--
-- STAGE PATH CONVENTION:
--   @RAW_DEV.STAGING.DATA_STAGE/fhir/*.csv
--   @RAW_DEV.STAGING.DATA_STAGE/workday_hcm/*.csv
--   @RAW_DEV.STAGING.DATA_STAGE/payer/*.csv
--
-- PREREQUISITES:
--   - sql/01_setup.sql executed (databases, roles exist)
--   - sql/03_raw_layer.sql executed (stage, formats exist)
--   - CSV files uploaded to stage (via PUT or build_and_load.py)
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE RAW_DEV;
USE WAREHOUSE INGEST_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- HCLS SOURCE SYSTEM SCHEMAS
-- ═══════════════════════════════════════════════════════════════════════════

-- FHIR R4 clinical data (patients, encounters, conditions, etc.)
CREATE SCHEMA IF NOT EXISTS RAW_DEV.FHIR
    COMMENT = 'HL7 FHIR R4 healthcare resources (Patient, Encounter, etc.)';

-- Workday HCM staffing data (workers, shifts, certifications, etc.)
CREATE SCHEMA IF NOT EXISTS RAW_DEV.WORKDAY_HCM
    COMMENT = 'Workday HCM healthcare workforce data (workers, shifts, certifications)';

-- Payer / Claims data (plans, members, claims, prior auth, etc.)
CREATE SCHEMA IF NOT EXISTS RAW_DEV.PAYER
    COMMENT = 'Payer claims and utilization data (plans, members, claims_detail)';

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS — DATA_ENGINEER and DATA_STEWARD access
-- ═══════════════════════════════════════════════════════════════════════════

-- DATA_ENGINEER: full control on HCLS schemas
GRANT ALL ON SCHEMA RAW_DEV.FHIR TO ROLE DATA_ENGINEER;
GRANT ALL ON SCHEMA RAW_DEV.WORKDAY_HCM TO ROLE DATA_ENGINEER;
GRANT ALL ON SCHEMA RAW_DEV.PAYER TO ROLE DATA_ENGINEER;

-- DATA_STEWARD: read-only
GRANT USAGE ON SCHEMA RAW_DEV.FHIR TO ROLE DATA_STEWARD;
GRANT USAGE ON SCHEMA RAW_DEV.WORKDAY_HCM TO ROLE DATA_STEWARD;
GRANT USAGE ON SCHEMA RAW_DEV.PAYER TO ROLE DATA_STEWARD;

GRANT SELECT ON ALL TABLES IN SCHEMA RAW_DEV.FHIR TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL TABLES IN SCHEMA RAW_DEV.WORKDAY_HCM TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL TABLES IN SCHEMA RAW_DEV.PAYER TO ROLE DATA_STEWARD;

GRANT SELECT ON FUTURE TABLES IN SCHEMA RAW_DEV.FHIR TO ROLE DATA_STEWARD;
GRANT SELECT ON FUTURE TABLES IN SCHEMA RAW_DEV.WORKDAY_HCM TO ROLE DATA_STEWARD;
GRANT SELECT ON FUTURE TABLES IN SCHEMA RAW_DEV.PAYER TO ROLE DATA_STEWARD;

-- ═══════════════════════════════════════════════════════════════════════════
-- SP_LOAD_HCLS_DATA — Automated HCLS Loader
-- ═══════════════════════════════════════════════════════════════════════════
-- Scans HCLS folders on stage, infers schema, creates tables, loads data.
-- Wraps the same INFER_SCHEMA → CREATE → COPY pattern from 04_load_data.sql.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE RAW_DEV.STAGING.SP_LOAD_HCLS_DATA()
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var results = [];

    // HCLS source systems → stage folder + schema + file format
    var hclsSystems = [
        {schema: 'FHIR',        folder: 'fhir',        format: 'CSV'},
        {schema: 'WORKDAY_HCM', folder: 'workday_hcm', format: 'CSV'},
        {schema: 'PAYER',       folder: 'payer',        format: 'CSV'}
    ];

    for (var s = 0; s < hclsSystems.length; s++) {
        var sys = hclsSystems[s];
        var schemaName = 'RAW_DEV.' + sys.schema;
        var fileExtension = sys.format === 'JSON' ? '.json' : '.csv';
        var inferFormat = sys.format === 'CSV'
            ? 'RAW_DEV.STAGING.CSV_INFER_FORMAT'
            : 'RAW_DEV.STAGING.' + sys.format + '_FORMAT';

        try {
            // List files in the folder
            var listSql = "LIST @RAW_DEV.STAGING.DATA_STAGE/" + sys.folder + "/";
            var listStmt = snowflake.createStatement({sqlText: listSql});
            var listResult = listStmt.execute();

            var files = [];
            while (listResult.next()) {
                var fullPath = listResult.getColumnValue(1);
                var lowerPath = fullPath.toLowerCase();
                if (lowerPath.endsWith(fileExtension) || lowerPath.endsWith(fileExtension + '.gz')) {
                    files.push(fullPath);
                }
            }

            if (files.length === 0) {
                results.push({
                    schema: sys.schema,
                    folder: sys.folder,
                    status: 'SKIPPED',
                    message: 'No ' + fileExtension + ' files found',
                    tables: 0,
                    rows: 0
                });
                continue;
            }

            var sysTablesLoaded = 0;
            var sysTablesFailed = 0;
            var sysTotalRows = 0;
            var sysDetails = [];

            for (var i = 0; i < files.length; i++) {
                var listedPath = files[i];
                var pathParts = listedPath.split('/');
                var fileNameWithExt = pathParts[pathParts.length - 1];

                // Derive table name from filename
                var tableName = fileNameWithExt
                    .replace(/\.gz$/i, '')
                    .replace(/\.(csv|json|parquet)$/i, '')
                    .toUpperCase();

                var stagePath = '@RAW_DEV.STAGING.DATA_STAGE/' + sys.folder + '/' + fileNameWithExt;
                var fullTableName = schemaName + '.' + tableName;

                try {
                    // Step 1: INFER_SCHEMA
                    var inferSql = "SELECT LISTAGG('\"' || COLUMN_NAME || '\" ' || TYPE, ', ') " +
                        "WITHIN GROUP (ORDER BY ORDER_ID) AS COL_DEFS " +
                        "FROM TABLE(INFER_SCHEMA(" +
                        "LOCATION => '" + stagePath + "', " +
                        "FILE_FORMAT => '" + inferFormat + "', " +
                        "MAX_RECORDS_PER_FILE => 1000))";

                    var inferStmt = snowflake.createStatement({sqlText: inferSql});
                    var inferResult = inferStmt.execute();

                    if (!inferResult.next()) {
                        sysDetails.push({table: tableName, status: 'ERROR', message: 'Infer failed', rows: 0});
                        sysTablesFailed++;
                        continue;
                    }

                    var columnDefs = inferResult.getColumnValue(1);
                    if (!columnDefs || columnDefs.trim() === '') {
                        sysDetails.push({table: tableName, status: 'ERROR', message: 'No columns', rows: 0});
                        sysTablesFailed++;
                        continue;
                    }

                    // Step 2: CREATE TABLE
                    var createSql = "CREATE OR REPLACE TABLE " + fullTableName + " (" + columnDefs + ") " +
                        "COMMENT = 'HCLS auto-loaded from " + fileNameWithExt + "'";
                    snowflake.createStatement({sqlText: createSql}).execute();

                    // Step 3: COPY INTO with MATCH_BY_COLUMN_NAME
                    var copySql = "COPY INTO " + fullTableName +
                        " FROM " + stagePath +
                        " FILE_FORMAT = " + inferFormat +
                        " MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE" +
                        " ON_ERROR = CONTINUE FORCE = TRUE";
                    snowflake.createStatement({sqlText: copySql}).execute();

                    // Step 4: Row count
                    var countSql = "SELECT COUNT(*) FROM " + fullTableName;
                    var countResult = snowflake.createStatement({sqlText: countSql}).execute();
                    countResult.next();
                    var rowCount = countResult.getColumnValue(1);

                    sysDetails.push({table: tableName, status: 'SUCCESS', rows: rowCount});
                    sysTablesLoaded++;
                    sysTotalRows += rowCount;

                } catch (fileErr) {
                    sysDetails.push({table: tableName, status: 'ERROR', message: fileErr.message, rows: 0});
                    sysTablesFailed++;
                }
            }

            results.push({
                schema: sys.schema,
                folder: sys.folder,
                status: sysTablesFailed === 0 ? 'SUCCESS' : 'PARTIAL',
                tables: sysTablesLoaded,
                failed: sysTablesFailed,
                rows: sysTotalRows,
                details: sysDetails
            });

        } catch (sysErr) {
            results.push({
                schema: sys.schema,
                folder: sys.folder,
                status: 'ERROR',
                message: sysErr.message,
                tables: 0,
                rows: 0
            });
        }
    }

    // Summary
    var totalTables = 0, totalRows = 0, totalFailed = 0;
    for (var r = 0; r < results.length; r++) {
        totalTables += results[r].tables || 0;
        totalRows   += results[r].rows   || 0;
        totalFailed += results[r].failed  || 0;
    }

    return {
        status: totalFailed === 0 && totalTables > 0 ? 'SUCCESS' :
                totalTables > 0 ? 'PARTIAL' : 'NO_DATA',
        total_tables: totalTables,
        total_failed: totalFailed,
        total_rows: totalRows,
        systems: results
    };
$$;

GRANT USAGE ON PROCEDURE RAW_DEV.STAGING.SP_LOAD_HCLS_DATA() TO ROLE DATA_ENGINEER;

-- ═══════════════════════════════════════════════════════════════════════════
-- MANUAL COPY INTO REFERENCE — All 26 HCLS Tables
-- ═══════════════════════════════════════════════════════════════════════════
-- Use these if you prefer explicit control over table creation and loading.
-- Each block: INFER → CREATE → COPY.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── FHIR (10 tables) ────────────────────────────────────────────────────

-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('FHIR', 'PATIENTS',           'CSV', 'fhir/patients.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('FHIR', 'PRACTITIONERS',      'CSV', 'fhir/practitioners.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('FHIR', 'ORGANIZATIONS',      'CSV', 'fhir/organizations.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('FHIR', 'ENCOUNTERS',         'CSV', 'fhir/encounters.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('FHIR', 'CONDITIONS',         'CSV', 'fhir/conditions.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('FHIR', 'OBSERVATIONS',       'CSV', 'fhir/observations.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('FHIR', 'MEDICATIONS',        'CSV', 'fhir/medications.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('FHIR', 'PROCEDURES',         'CSV', 'fhir/procedures.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('FHIR', 'CLAIMS',             'CSV', 'fhir/claims.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('FHIR', 'COMORBIDITY_SCORES', 'CSV', 'fhir/comorbidity_scores.csv.gz');

-- ─── WORKDAY_HCM (8 tables) ─────────────────────────────────────────────

-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('WORKDAY_HCM', 'WORKERS',              'CSV', 'workday_hcm/workers.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('WORKDAY_HCM', 'DEPARTMENTS',           'CSV', 'workday_hcm/departments.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('WORKDAY_HCM', 'STAFFING_ASSIGNMENTS',  'CSV', 'workday_hcm/staffing_assignments.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('WORKDAY_HCM', 'SHIFTS',                'CSV', 'workday_hcm/shifts.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('WORKDAY_HCM', 'CERTIFICATIONS',        'CSV', 'workday_hcm/certifications.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('WORKDAY_HCM', 'TIME_OFF',              'CSV', 'workday_hcm/time_off.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('WORKDAY_HCM', 'TURNOVER_EVENTS',       'CSV', 'workday_hcm/turnover_events.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('WORKDAY_HCM', 'COMPENSATION_HISTORY',  'CSV', 'workday_hcm/compensation_history.csv.gz');

-- ─── PAYER (8 tables) ───────────────────────────────────────────────────

-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('PAYER', 'PLANS',                'CSV', 'payer/plans.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('PAYER', 'MEMBERS',              'CSV', 'payer/members.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('PAYER', 'COVERAGE_PERIODS',     'CSV', 'payer/coverage_periods.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('PAYER', 'CLAIMS_DETAIL',        'CSV', 'payer/claims_detail.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('PAYER', 'PRIOR_AUTHORIZATIONS', 'CSV', 'payer/prior_authorizations.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('PAYER', 'UTILIZATION_REVIEWS',  'CSV', 'payer/utilization_reviews.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('PAYER', 'PLAN_OF_CARE',         'CSV', 'payer/plan_of_care.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('PAYER', 'QUALITY_MEASURES',     'CSV', 'payer/quality_measures.csv.gz');

-- ═══════════════════════════════════════════════════════════════════════════
-- GOVERNANCE TAGS — HCLS data is PHI / RESTRICTED
-- ═══════════════════════════════════════════════════════════════════════════

-- CALL RAW_DEV.STAGING.APPLY_TAGS_TO_SOURCE_SYSTEM('FHIR');
-- CALL RAW_DEV.STAGING.APPLY_TAGS_TO_SOURCE_SYSTEM('WORKDAY_HCM');
-- CALL RAW_DEV.STAGING.APPLY_TAGS_TO_SOURCE_SYSTEM('PAYER');

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES
-- ═══════════════════════════════════════════════════════════════════════════

-- HCLS table inventory
SELECT
    TABLE_SCHEMA  AS SOURCE_SYSTEM,
    TABLE_NAME,
    ROW_COUNT,
    CREATED       AS LOADED_AT
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_CATALOG = 'RAW_DEV'
  AND TABLE_SCHEMA IN ('FHIR', 'WORKDAY_HCM', 'PAYER')
  AND TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_SCHEMA, TABLE_NAME;

-- Row count summary by schema
SELECT
    TABLE_SCHEMA           AS SOURCE_SYSTEM,
    COUNT(*)               AS TABLE_COUNT,
    SUM(ROW_COUNT)         AS TOTAL_ROWS
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_CATALOG = 'RAW_DEV'
  AND TABLE_SCHEMA IN ('FHIR', 'WORKDAY_HCM', 'PAYER')
  AND TABLE_TYPE = 'BASE TABLE'
GROUP BY TABLE_SCHEMA
ORDER BY TABLE_SCHEMA;

SELECT '10_hcls_load_data.sql completed successfully' AS STATUS;
