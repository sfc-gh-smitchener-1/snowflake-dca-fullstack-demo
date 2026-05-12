-- ============================================================================
-- DCIM DATA LOADING — Automated Loader Stored Procedure
-- ============================================================================
-- Scans DCIM folders on stage, infers schema, creates tables, loads data.
-- Wraps the same INFER_SCHEMA → CREATE → COPY pattern from 04_load_data.sql.
--
-- STAGE PATH CONVENTION:
--   @RAW_DEV.STAGING.DATA_STAGE/servicenow/*.csv
--   @RAW_DEV.STAGING.DATA_STAGE/workday_dcim/*.csv
--   @RAW_DEV.STAGING.DATA_STAGE/telemetry/*.csv
--
-- PREREQUISITES:
--   - sql/01_setup.sql executed (databases, roles exist)
--   - sql/03_raw_layer.sql executed (stage, formats exist)
--   - 01_dcim_schemas.sql executed (DCIM schemas exist)
--   - CSV files uploaded to stage (via PUT or deploy.sh)
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE RAW_DEV;
USE WAREHOUSE INGEST_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- SP_LOAD_DCIM_DATA — Automated DCIM Loader
-- ═══════════════════════════════════════════════════════════════════════════
-- Scans DCIM folders on stage, infers schema, creates tables, loads data.
-- Wraps the same INFER_SCHEMA → CREATE → COPY pattern from SP_LOAD_HCLS_DATA.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE RAW_DEV.STAGING.SP_LOAD_DCIM_DATA()
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var results = [];

    // DCIM source systems → stage folder + schema + file format
    var dcimSystems = [
        {schema: 'SERVICENOW',  folder: 'servicenow',   format: 'CSV'},
        {schema: 'WORKDAY_DCIM', folder: 'workday_dcim', format: 'CSV'},
        {schema: 'TELEMETRY',   folder: 'telemetry',     format: 'CSV'},
        {schema: 'SIEMENS_DCIM', folder: 'siemens_dcim', format: 'CSV'}
    ];

    for (var s = 0; s < dcimSystems.length; s++) {
        var sys = dcimSystems[s];
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
                        "COMMENT = 'DCIM auto-loaded from " + fileNameWithExt + "'";
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

GRANT USAGE ON PROCEDURE RAW_DEV.STAGING.SP_LOAD_DCIM_DATA() TO ROLE DATA_ENGINEER;

-- ═══════════════════════════════════════════════════════════════════════════
-- MANUAL COPY INTO REFERENCE — All 18 DCIM Tables
-- ═══════════════════════════════════════════════════════════════════════════
-- Use these if you prefer explicit control over table creation and loading.
-- Each block: INFER → CREATE → COPY.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── SERVICENOW (7 tables) ────────────────────────────────────────────────

-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SERVICENOW', 'DATA_CENTERS',      'CSV', 'servicenow/data_centers.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SERVICENOW', 'HALLS',             'CSV', 'servicenow/halls.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SERVICENOW', 'RACKS',             'CSV', 'servicenow/racks.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SERVICENOW', 'SWITCHES',          'CSV', 'servicenow/switches.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SERVICENOW', 'PORTS',             'CSV', 'servicenow/ports.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SERVICENOW', 'INCIDENTS',         'CSV', 'servicenow/incidents.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SERVICENOW', 'CHANGE_REQUESTS',   'CSV', 'servicenow/change_requests.csv.gz');

-- ─── WORKDAY_DCIM (7 tables) ─────────────────────────────────────────────

-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('WORKDAY_DCIM', 'TECHNICIANS',          'CSV', 'workday_dcim/technicians.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('WORKDAY_DCIM', 'CERTIFICATIONS',       'CSV', 'workday_dcim/certifications.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('WORKDAY_DCIM', 'SHIFTS',               'CSV', 'workday_dcim/shifts.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('WORKDAY_DCIM', 'SKILL_ASSIGNMENTS',    'CSV', 'workday_dcim/skill_assignments.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('WORKDAY_DCIM', 'TEAMS',                'CSV', 'workday_dcim/teams.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('WORKDAY_DCIM', 'TIME_OFF',             'CSV', 'workday_dcim/time_off.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('WORKDAY_DCIM', 'TRAINING_COMPLETIONS', 'CSV', 'workday_dcim/training_completions.csv.gz');

-- ─── TELEMETRY (4 tables) ────────────────────────────────────────────────

-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('TELEMETRY', 'PORT_METRICS',           'CSV', 'telemetry/port_metrics.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('TELEMETRY', 'SWITCH_HEALTH',          'CSV', 'telemetry/switch_health.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('TELEMETRY', 'ENVIRONMENTAL_SENSORS',  'CSV', 'telemetry/environmental_sensors.csv.gz');
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('TELEMETRY', 'ALERTS',                 'CSV', 'telemetry/alerts.csv.gz');

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES
-- ═══════════════════════════════════════════════════════════════════════════

-- DCIM table inventory
SELECT
    TABLE_SCHEMA  AS SOURCE_SYSTEM,
    TABLE_NAME,
    ROW_COUNT,
    CREATED       AS LOADED_AT
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_CATALOG = 'RAW_DEV'
  AND TABLE_SCHEMA IN ('SERVICENOW', 'WORKDAY_DCIM', 'TELEMETRY')
  AND TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_SCHEMA, TABLE_NAME;

-- Row count summary by schema
SELECT
    TABLE_SCHEMA           AS SOURCE_SYSTEM,
    COUNT(*)               AS TABLE_COUNT,
    SUM(ROW_COUNT)         AS TOTAL_ROWS
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_CATALOG = 'RAW_DEV'
  AND TABLE_SCHEMA IN ('SERVICENOW', 'WORKDAY_DCIM', 'TELEMETRY')
  AND TABLE_TYPE = 'BASE TABLE'
GROUP BY TABLE_SCHEMA
ORDER BY TABLE_SCHEMA;

SELECT '02_dcim_load_data.sql completed successfully' AS STATUS;
