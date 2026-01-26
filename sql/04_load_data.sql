-- ============================================================================
-- DATA LOADING - Dynamic Schema Detection and Table Creation
-- ============================================================================
-- 
-- This script automatically detects files in the stage and creates tables
-- dynamically using INFER_SCHEMA. No manual table definitions required.
--
-- WORKFLOW:
--   1. Upload source system files to stage (PUT or Snowsight)
--   2. Run LOAD_ALL_SOURCE_SYSTEMS() to auto-detect and load everything
--   -- OR --
--   2. Run LOAD_SOURCE_SYSTEM('SAP') to load a specific source system
--
-- SUPPORTED SOURCE SYSTEMS:
--   - SAP S/4HANA:  sap_s4hana/*.csv
--   - Salesforce:   salesforce/*.csv
--   - Oracle EBS:   oracle_ebs/*.csv
--   - FHIR R4:      fhir_r4/*.json
--   - Workday:      workday/*.csv
--   - ServiceNow:   servicenow/*.csv
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE WAREHOUSE INGEST_WH;
USE DATABASE RAW_DEV;

-- ═══════════════════════════════════════════════════════════════════════════
-- DYNAMIC BULK LOADER - Load All Files for a Source System
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Scans the stage directory for a source system, detects all files,
-- infers schema from each file, creates tables, and loads data.
--
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE RAW_DEV.STAGING.LOAD_SOURCE_SYSTEM(
    P_SOURCE_SYSTEM VARCHAR,
    P_FILE_FORMAT VARCHAR DEFAULT 'CSV'
)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var results = [];
    
    // Map source system to stage folder
    var folderMap = {
        'SAP': 'sap_s4hana',
        'SALESFORCE': 'salesforce',
        'ORACLE': 'oracle_ebs',
        'FHIR': 'fhir_r4',
        'WORKDAY': 'workday',
        'SERVICENOW': 'servicenow'
    };
    
    var sourceSystem = P_SOURCE_SYSTEM.toUpperCase();
    var folder = folderMap[sourceSystem] || P_SOURCE_SYSTEM.toLowerCase();
    var fileFormat = P_FILE_FORMAT.toUpperCase();
    var fileExtension = fileFormat === 'JSON' ? '.json' : '.csv';
    // Use separate formats: INFER format has PARSE_HEADER=TRUE, COPY format has SKIP_HEADER=1
    var inferFormatName = fileFormat === 'CSV' ? 'RAW_DEV.STAGING.CSV_INFER_FORMAT' : 'RAW_DEV.STAGING.' + fileFormat + '_FORMAT';
    var copyFormatName = 'RAW_DEV.STAGING.' + fileFormat + '_FORMAT';
    var schemaName = 'RAW_DEV.' + sourceSystem;
    
    try {
        // List all files in the source system folder
        var listSql = `LIST @RAW_DEV.STAGING.DATA_STAGE/${folder}/`;
        var listStmt = snowflake.createStatement({sqlText: listSql});
        var listResult = listStmt.execute();
        
        var files = [];
        while (listResult.next()) {
            // Column 1 is "name" which contains the full path like:
            // s3://bucket/path/sap_s4hana/KNA1.csv.gz or
            // @RAW_DEV.STAGING.DATA_STAGE/sap_s4hana/KNA1.csv.gz
            var fullPath = listResult.getColumnValue(1);
            
            // Filter by file extension (handle .gz compression)
            var lowerPath = fullPath.toLowerCase();
            if (lowerPath.endsWith(fileExtension) || lowerPath.endsWith(fileExtension + '.gz')) {
                files.push(fullPath);
            }
        }
        
        if (files.length === 0) {
            return {
                status: 'WARNING',
                message: 'No ' + fileExtension + ' files found in ' + folder + '/',
                tables_loaded: 0,
                folder: folder
            };
        }
        
        // Process each file
        for (var i = 0; i < files.length; i++) {
            var fullStagePath = files[i];
            
            // fullStagePath from LIST is like: @"RAW_DEV"."STAGING"."DATA_STAGE"/sap_s4hana/KNA1.csv
            // Extract just the filename
            var pathParts = fullStagePath.split('/');
            var fileNameWithExt = pathParts[pathParts.length - 1];
            
            // Extract table name by removing extension(s)
            var tableName = fileNameWithExt
                .replace(/\.gz$/i, '')
                .replace(/\.(csv|json|parquet)$/i, '')
                .toUpperCase();
            
            try {
                // Infer schema - use the full stage path directly from LIST
                var inferSql = `
                    SELECT LISTAGG('"' || COLUMN_NAME || '" ' || TYPE, ', ') 
                           WITHIN GROUP (ORDER BY ORDER_ID) AS COL_DEFS
                    FROM TABLE(
                        INFER_SCHEMA(
                            LOCATION => '${fullStagePath}',
                            FILE_FORMAT => '${inferFormatName}',
                            MAX_RECORDS_PER_FILE => 1000
                        )
                    )
                `;
                
                var inferStmt = snowflake.createStatement({sqlText: inferSql});
                var inferResult = inferStmt.execute();
                
                if (!inferResult.next()) {
                    results.push({
                        table: tableName,
                        file: fileNameWithExt,
                        status: 'ERROR',
                        message: 'Could not infer schema',
                        rows: 0
                    });
                    continue;
                }
                
                var columnDefs = inferResult.getColumnValue(1);
                
                if (!columnDefs || columnDefs.trim() === '') {
                    results.push({
                        table: tableName,
                        file: fileNameWithExt,
                        status: 'ERROR',
                        message: 'No columns detected',
                        rows: 0
                    });
                    continue;
                }
                
                var fullTableName = schemaName + '.' + tableName;
                
                // Create table
                var createSql = `CREATE OR REPLACE TABLE ${fullTableName} (${columnDefs}) 
                                 COMMENT = 'Auto-loaded from ${fileNameWithExt}'`;
                var createStmt = snowflake.createStatement({sqlText: createSql});
                createStmt.execute();
                
                // Load data (using COPY format with SKIP_HEADER=1, FORCE=TRUE to reload)
                // Use the full stage path directly from LIST
                var copySql = `COPY INTO ${fullTableName} 
                               FROM '${fullStagePath}'
                               FILE_FORMAT = ${copyFormatName}
                               ON_ERROR = CONTINUE
                               FORCE = TRUE`;
                var copyStmt = snowflake.createStatement({sqlText: copySql});
                var copyResult = copyStmt.execute();
                
                // Capture COPY result details
                var copyDetails = [];
                while (copyResult.next()) {
                    copyDetails.push({
                        file: copyResult.getColumnValue(1),
                        status: copyResult.getColumnValue(2),
                        rows_parsed: copyResult.getColumnValue(3),
                        rows_loaded: copyResult.getColumnValue(4),
                        errors_seen: copyResult.getColumnValue(5),
                        first_error: copyResult.getColumnValue(6)
                    });
                }
                
                // Get row count
                var countSql = `SELECT COUNT(*) FROM ${fullTableName}`;
                var countStmt = snowflake.createStatement({sqlText: countSql});
                var countResult = countStmt.execute();
                countResult.next();
                var rowCount = countResult.getColumnValue(1);
                
                results.push({
                    table: tableName,
                    file: fileNameWithExt,
                    status: 'SUCCESS',
                    message: 'Created and loaded',
                    rows: rowCount,
                    copy_details: copyDetails
                });
                
            } catch (fileErr) {
                results.push({
                    table: tableName,
                    file: fileNameWithExt,
                    status: 'ERROR',
                    message: fileErr.message,
                    rows: 0
                });
            }
        }
        
        // Summary
        var successCount = results.filter(function(r) { return r.status === 'SUCCESS'; }).length;
        var errorCount = results.filter(function(r) { return r.status === 'ERROR'; }).length;
        var totalRows = results.reduce(function(sum, r) { return sum + r.rows; }, 0);
        
        return {
            status: errorCount === 0 ? 'SUCCESS' : 'PARTIAL',
            source_system: sourceSystem,
            folder: folder,
            files_found: files.length,
            tables_loaded: successCount,
            tables_failed: errorCount,
            total_rows: totalRows,
            details: results
        };
        
    } catch (err) {
        return {
            status: 'ERROR',
            message: err.message,
            source_system: sourceSystem,
            folder: folder
        };
    }
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- LOAD ALL SOURCE SYSTEMS
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Scans the entire stage and loads ALL source systems automatically.
--
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE RAW_DEV.STAGING.LOAD_ALL_SOURCE_SYSTEMS()
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var allResults = {};
    
    // Source systems with their default file formats
    var sourceSystems = [
        {name: 'SAP', folder: 'sap_s4hana', format: 'CSV'},
        {name: 'SALESFORCE', folder: 'salesforce', format: 'CSV'},
        {name: 'ORACLE', folder: 'oracle_ebs', format: 'CSV'},
        {name: 'FHIR', folder: 'fhir_r4', format: 'JSON'},
        {name: 'WORKDAY', folder: 'workday', format: 'CSV'},
        {name: 'SERVICENOW', folder: 'servicenow', format: 'CSV'}
    ];
    
    var totalTablesLoaded = 0;
    var totalTablesFailed = 0;
    var totalRows = 0;
    var systemsProcessed = 0;
    
    for (var i = 0; i < sourceSystems.length; i++) {
        var sys = sourceSystems[i];
        
        try {
            // Directly call LOAD_SOURCE_SYSTEM - it will handle empty folders gracefully
            var loadSql = `CALL RAW_DEV.STAGING.LOAD_SOURCE_SYSTEM('${sys.name}', '${sys.format}')`;
            var loadStmt = snowflake.createStatement({sqlText: loadSql});
            var loadResult = loadStmt.execute();
            loadResult.next();
            
            var resultStr = loadResult.getColumnValue(1);
            var result;
            
            // Parse the result (it's a VARIANT returned as string)
            if (typeof resultStr === 'string') {
                result = JSON.parse(resultStr);
            } else {
                result = resultStr;
            }
            
            allResults[sys.name] = result;
            
            if (result.tables_loaded) {
                totalTablesLoaded += result.tables_loaded;
                systemsProcessed++;
            }
            if (result.tables_failed) totalTablesFailed += result.tables_failed;
            if (result.total_rows) totalRows += result.total_rows;
            
        } catch (err) {
            allResults[sys.name] = {
                status: 'ERROR',
                message: err.message
            };
        }
    }
    
    return {
        status: totalTablesFailed === 0 && totalTablesLoaded > 0 ? 'SUCCESS' : 
                totalTablesLoaded > 0 ? 'PARTIAL' : 'NO_DATA',
        systems_with_data: systemsProcessed,
        total_tables_loaded: totalTablesLoaded,
        total_tables_failed: totalTablesFailed,
        total_rows: totalRows,
        source_systems: allResults
    };
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- APPLY TAGS TO ALL TABLES IN A SOURCE SYSTEM
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE RAW_DEV.STAGING.APPLY_TAGS_TO_SOURCE_SYSTEM(
    P_SOURCE_SYSTEM VARCHAR
)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var results = [];
    var sourceSystem = P_SOURCE_SYSTEM.toUpperCase();
    var schemaName = 'RAW_DEV.' + sourceSystem;
    
    var domainMap = {
        'SAP': {domain: 'ERP', classification: 'CONFIDENTIAL'},
        'SALESFORCE': {domain: 'CRM', classification: 'CONFIDENTIAL'},
        'ORACLE': {domain: 'ERP', classification: 'CONFIDENTIAL'},
        'FHIR': {domain: 'HEALTHCARE', classification: 'RESTRICTED'},
        'WORKDAY': {domain: 'HCM', classification: 'RESTRICTED'},
        'SERVICENOW': {domain: 'ITSM', classification: 'INTERNAL'}
    };
    
    var config = domainMap[sourceSystem] || {domain: 'OTHER', classification: 'INTERNAL'};
    
    try {
        // Get all tables in the schema
        var tablesSql = `
            SELECT TABLE_NAME 
            FROM INFORMATION_SCHEMA.TABLES 
            WHERE TABLE_CATALOG = 'RAW_DEV' 
              AND TABLE_SCHEMA = '${sourceSystem}'
              AND TABLE_TYPE = 'BASE TABLE'
        `;
        
        var tablesStmt = snowflake.createStatement({sqlText: tablesSql});
        var tablesResult = tablesStmt.execute();
        
        while (tablesResult.next()) {
            var tableName = tablesResult.getColumnValue(1);
            var fullTableName = schemaName + '.' + tableName;
            
            try {
                var tagSql = `ALTER TABLE ${fullTableName} SET TAG 
                    GOVERNANCE.TAGS.DATA_CLASSIFICATION = '${config.classification}',
                    GOVERNANCE.TAGS.DATA_DOMAIN = '${config.domain}',
                    GOVERNANCE.TAGS.DATA_QUALITY_TIER = 'BRONZE',
                    GOVERNANCE.TAGS.SOURCE_SYSTEM = '${sourceSystem}'`;
                
                var tagStmt = snowflake.createStatement({sqlText: tagSql});
                tagStmt.execute();
                
                results.push({table: tableName, status: 'SUCCESS'});
                
            } catch (tagErr) {
                results.push({table: tableName, status: 'ERROR', message: tagErr.message});
            }
        }
        
        return {
            status: 'SUCCESS',
            source_system: sourceSystem,
            tables_tagged: results.filter(function(r) { return r.status === 'SUCCESS'; }).length,
            details: results
        };
        
    } catch (err) {
        return {
            status: 'ERROR',
            message: err.message
        };
    }
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

GRANT USAGE ON PROCEDURE RAW_DEV.STAGING.LOAD_SOURCE_SYSTEM(VARCHAR, VARCHAR) TO ROLE DATA_ENGINEER;
GRANT USAGE ON PROCEDURE RAW_DEV.STAGING.LOAD_ALL_SOURCE_SYSTEMS() TO ROLE DATA_ENGINEER;
GRANT USAGE ON PROCEDURE RAW_DEV.STAGING.APPLY_TAGS_TO_SOURCE_SYSTEM(VARCHAR) TO ROLE DATA_ENGINEER;

-- ═══════════════════════════════════════════════════════════════════════════
-- USAGE INSTRUCTIONS
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- STEP 1: Generate source system data (local machine)
-- ─────────────────────────────────────────────────────────────────────────────
--   cd tools
--   python data_generator.py --system sap --domain all --output ../data
--   python data_generator.py --system salesforce --domain all --output ../data
--   python data_generator.py --system fhir --domain all --format json --output ../data
--
-- STEP 2: Upload files to Snowflake stage
-- ─────────────────────────────────────────────────────────────────────────────
--   PUT file:///path/to/data/sap_s4hana/*.csv @RAW_DEV.STAGING.DATA_STAGE/sap_s4hana/ AUTO_COMPRESS=TRUE;
--   PUT file:///path/to/data/salesforce/*.csv @RAW_DEV.STAGING.DATA_STAGE/salesforce/ AUTO_COMPRESS=TRUE;
--   PUT file:///path/to/data/fhir_r4/*.json @RAW_DEV.STAGING.DATA_STAGE/fhir_r4/ AUTO_COMPRESS=TRUE;
--
-- STEP 3: Verify files are uploaded
-- ─────────────────────────────────────────────────────────────────────────────

LIST @RAW_DEV.STAGING.DATA_STAGE;

-- STEP 4: Load data (choose one)
-- ─────────────────────────────────────────────────────────────────────────────

-- Option A: Load ALL source systems at once (recommended)
-- CALL RAW_DEV.STAGING.LOAD_ALL_SOURCE_SYSTEMS();

-- Option B: Load specific source system
-- CALL RAW_DEV.STAGING.LOAD_SOURCE_SYSTEM('SAP', 'CSV');
-- CALL RAW_DEV.STAGING.LOAD_SOURCE_SYSTEM('SALESFORCE', 'CSV');
-- CALL RAW_DEV.STAGING.LOAD_SOURCE_SYSTEM('FHIR', 'JSON');
-- CALL RAW_DEV.STAGING.LOAD_SOURCE_SYSTEM('WORKDAY', 'CSV');
-- CALL RAW_DEV.STAGING.LOAD_SOURCE_SYSTEM('SERVICENOW', 'CSV');

-- Option C: Load individual table
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SAP', 'KNA1', 'CSV', 'sap_s4hana/KNA1.csv.gz');

-- STEP 5: Apply governance tags
-- ─────────────────────────────────────────────────────────────────────────────

-- CALL RAW_DEV.STAGING.APPLY_TAGS_TO_SOURCE_SYSTEM('SAP');
-- CALL RAW_DEV.STAGING.APPLY_TAGS_TO_SOURCE_SYSTEM('SALESFORCE');
-- CALL RAW_DEV.STAGING.APPLY_TAGS_TO_SOURCE_SYSTEM('FHIR');

-- STEP 6: Verify loaded tables
-- ─────────────────────────────────────────────────────────────────────────────

SELECT 
    TABLE_SCHEMA AS SOURCE_SYSTEM,
    TABLE_NAME,
    ROW_COUNT,
    CREATED AS LOADED_AT
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_CATALOG = 'RAW_DEV'
  AND TABLE_SCHEMA IN ('SAP', 'SALESFORCE', 'ORACLE', 'FHIR', 'WORKDAY', 'SERVICENOW')
  AND TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_SCHEMA, TABLE_NAME;

-- ═══════════════════════════════════════════════════════════════════════════

SELECT '04_load_data.sql completed successfully' AS STATUS;
