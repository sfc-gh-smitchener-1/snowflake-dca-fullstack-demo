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
    var fileFormatName = 'RAW_DEV.STAGING.' + fileFormat + '_FORMAT';
    var schemaName = 'RAW_DEV.' + sourceSystem;
    
    try {
        // List all files in the source system folder
        var listSql = `LIST @RAW_DEV.STAGING.DATA_STAGE/${folder}/`;
        var listStmt = snowflake.createStatement({sqlText: listSql});
        var listResult = listStmt.execute();
        
        var files = [];
        while (listResult.next()) {
            var fileName = listResult.getColumnValue(1);
            // Filter by file extension
            if (fileName.toLowerCase().endsWith(fileExtension) || 
                fileName.toLowerCase().endsWith(fileExtension + '.gz')) {
                files.push(fileName);
            }
        }
        
        if (files.length === 0) {
            return {
                status: 'WARNING',
                message: 'No ' + fileExtension + ' files found in ' + folder + '/',
                tables_loaded: 0
            };
        }
        
        // Process each file
        for (var i = 0; i < files.length; i++) {
            var fullPath = files[i];
            
            // Extract table name from file path
            // e.g., "sap_s4hana/KNA1.csv.gz" -> "KNA1"
            var parts = fullPath.split('/');
            var fileName = parts[parts.length - 1];
            var tableName = fileName.replace(/\.(csv|json|parquet)(\.gz)?$/i, '').toUpperCase();
            
            // Get relative path for INFER_SCHEMA
            var stagePath = folder + '/' + fileName;
            
            try {
                // Infer schema
                var inferSql = `
                    SELECT LISTAGG('"' || COLUMN_NAME || '" ' || TYPE, ', ') 
                           WITHIN GROUP (ORDER BY ORDER_ID) AS COL_DEFS
                    FROM TABLE(
                        INFER_SCHEMA(
                            LOCATION => '@RAW_DEV.STAGING.DATA_STAGE/${stagePath}',
                            FILE_FORMAT => '${fileFormatName}',
                            MAX_RECORDS_PER_FILE => 1000
                        )
                    )
                `;
                
                var inferStmt = snowflake.createStatement({sqlText: inferSql});
                var inferResult = inferStmt.execute();
                
                if (!inferResult.next()) {
                    results.push({
                        table: tableName,
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
                        status: 'ERROR',
                        message: 'No columns detected',
                        rows: 0
                    });
                    continue;
                }
                
                var fullTableName = schemaName + '.' + tableName;
                
                // Create table
                var createSql = `CREATE OR REPLACE TABLE ${fullTableName} (${columnDefs}) 
                                 COMMENT = 'Auto-loaded from ${stagePath}'`;
                var createStmt = snowflake.createStatement({sqlText: createSql});
                createStmt.execute();
                
                // Load data
                var copySql = `COPY INTO ${fullTableName} 
                               FROM @RAW_DEV.STAGING.DATA_STAGE/${stagePath}
                               FILE_FORMAT = ${fileFormatName}
                               MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
                               ON_ERROR = CONTINUE`;
                var copyStmt = snowflake.createStatement({sqlText: copySql});
                copyStmt.execute();
                
                // Get row count
                var countSql = `SELECT COUNT(*) FROM ${fullTableName}`;
                var countStmt = snowflake.createStatement({sqlText: countSql});
                var countResult = countStmt.execute();
                countResult.next();
                var rowCount = countResult.getColumnValue(1);
                
                results.push({
                    table: tableName,
                    status: 'SUCCESS',
                    message: 'Created and loaded',
                    rows: rowCount
                });
                
            } catch (fileErr) {
                results.push({
                    table: tableName,
                    status: 'ERROR',
                    message: fileErr.message,
                    rows: 0
                });
            }
        }
        
        // Summary
        var successCount = results.filter(r => r.status === 'SUCCESS').length;
        var errorCount = results.filter(r => r.status === 'ERROR').length;
        var totalRows = results.reduce((sum, r) => sum + r.rows, 0);
        
        return {
            status: errorCount === 0 ? 'SUCCESS' : 'PARTIAL',
            source_system: sourceSystem,
            folder: folder,
            tables_loaded: successCount,
            tables_failed: errorCount,
            total_rows: totalRows,
            details: results
        };
        
    } catch (err) {
        return {
            status: 'ERROR',
            message: err.message,
            source_system: sourceSystem
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
    
    for (var i = 0; i < sourceSystems.length; i++) {
        var sys = sourceSystems[i];
        
        try {
            // Check if folder has files
            var listSql = `LIST @RAW_DEV.STAGING.DATA_STAGE/${sys.folder}/`;
            var listStmt = snowflake.createStatement({sqlText: listSql});
            var listResult = listStmt.execute();
            
            var hasFiles = listResult.next();
            
            if (hasFiles) {
                // Call LOAD_SOURCE_SYSTEM
                var loadSql = `CALL RAW_DEV.STAGING.LOAD_SOURCE_SYSTEM('${sys.name}', '${sys.format}')`;
                var loadStmt = snowflake.createStatement({sqlText: loadSql});
                var loadResult = loadStmt.execute();
                loadResult.next();
                
                var result = JSON.parse(loadResult.getColumnValue(1));
                allResults[sys.name] = result;
                
                if (result.tables_loaded) totalTablesLoaded += result.tables_loaded;
                if (result.tables_failed) totalTablesFailed += result.tables_failed;
                if (result.total_rows) totalRows += result.total_rows;
            } else {
                allResults[sys.name] = {
                    status: 'SKIPPED',
                    message: 'No files in ' + sys.folder + '/'
                };
            }
            
        } catch (err) {
            allResults[sys.name] = {
                status: 'SKIPPED',
                message: 'Folder not found or empty'
            };
        }
    }
    
    return {
        status: totalTablesFailed === 0 ? 'SUCCESS' : 'PARTIAL',
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
            tables_tagged: results.filter(r => r.status === 'SUCCESS').length,
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
-- CALL RAW_DEV.STAGING.INFER_AND_CREATE_TABLE('SAP', 'KNA1', 'CSV', 'sap_s4hana/KNA1.csv');

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
