#!/bin/bash
set -euo pipefail
#
# ============================================================================
# DCIM DEMO — ONE-SHOT DEPLOYMENT SCRIPT
# ============================================================================
#
# Generates synthetic data, uploads to Snowflake stage, loads into RAW layer,
# builds curated Dynamic Tables, and deploys Knowledge Graph extensions.
#
# Prerequisites:
#   - Core DCA demo deployed (scripts 01-15)
#   - Python 3.8+ with faker package
#   - snow CLI (Snowflake CLI) installed
#   - A valid Snowflake connection configured
#
# Usage:
#   ./deploy.sh --connection default              # Full deployment
#   ./deploy.sh --connection default --quick       # Quick mode (10% data scale)
#   ./deploy.sh --connection default --data-only   # Only generate and load data
#   ./deploy.sh --connection default --sql-only    # Only run SQL scripts (data already loaded)
#
# ============================================================================

# ---------------------------------------------------------------------------
# Directory layout
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOOLS_DIR="${SCRIPT_DIR}/tools"
SQL_DIR="${SCRIPT_DIR}/sql"
DATA_DIR="${SCRIPT_DIR}/data"

# ---------------------------------------------------------------------------
# Defaults (overridden by CLI flags)
# ---------------------------------------------------------------------------
CONNECTION=""
QUICK=false
SCALE="1.0"
DATA_ONLY=false
SQL_ONLY=false

# ---------------------------------------------------------------------------
# Colours / formatting helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Colour

# ============================================================================
# FUNCTIONS
# ============================================================================

print_banner() {
    echo ""
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  DCIM DEMO — ONE-SHOT DEPLOYMENT                          ║"
    echo "║  Data Center Infrastructure Management Platform            ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "  Started : $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "  Conn    : ${CONNECTION}"
    echo "  Quick   : ${QUICK}  (scale=${SCALE})"
    echo "  Flags   : data-only=${DATA_ONLY} sql-only=${SQL_ONLY}"
    echo ""
}

usage() {
    cat <<EOF
Usage: $(basename "$0") --connection <NAME> [OPTIONS]

Required:
  --connection NAME       Snowflake CLI connection name (e.g. default)

Options:
  --quick                 Generate ~10% data for fast testing
  --scale FLOAT           Data scale factor (default: 1.0, --quick sets 0.1)
  --data-only             Run only data generation + upload + load
  --sql-only              Run only SQL scripts (assumes data already loaded)
  -h, --help              Show this help message

Examples:
  ./deploy.sh --connection default
  ./deploy.sh --connection default --quick
  ./deploy.sh --connection default --data-only --quick
  ./deploy.sh --connection default --sql-only
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --connection)   CONNECTION="$2"; shift 2 ;;
            --quick)        QUICK=true; SCALE="0.1"; shift ;;
            --scale)        SCALE="$2"; shift 2 ;;
            --data-only)    DATA_ONLY=true; shift ;;
            --sql-only)     SQL_ONLY=true; shift ;;
            -h|--help)      usage ;;
            *)
                echo -e "${RED}[ERROR] Unknown option: $1${NC}" >&2
                echo "Run with --help for usage." >&2
                exit 1
                ;;
        esac
    done

    if [ -z "${CONNECTION}" ]; then
        echo -e "${RED}[ERROR] --connection is required.${NC}" >&2
        echo "Run with --help for usage." >&2
        exit 1
    fi

    if [ "${DATA_ONLY}" = "true" ] && [ "${SQL_ONLY}" = "true" ]; then
        echo -e "${RED}[ERROR] --data-only and --sql-only are mutually exclusive.${NC}" >&2
        exit 1
    fi
}

check_prerequisites() {
    echo -e "${BOLD}Checking prerequisites...${NC}"
    local ok=true

    # Python 3
    if command -v python3 &>/dev/null; then
        echo -e "  ${GREEN}[OK]${NC} python3  $(python3 --version 2>&1)"
    else
        echo -e "  ${RED}[MISSING]${NC} python3"; ok=false
    fi

    # faker
    if python3 -c "import faker" 2>/dev/null; then
        echo -e "  ${GREEN}[OK]${NC} faker    $(python3 -c 'import faker; print(faker.__version__)')"
    else
        echo -e "  ${RED}[MISSING]${NC} faker (pip install faker)"; ok=false
    fi

    # snow CLI
    if command -v snow &>/dev/null; then
        echo -e "  ${GREEN}[OK]${NC} snow CLI $(snow --version 2>&1 | head -1)"
    else
        echo -e "  ${RED}[MISSING]${NC} snow CLI (https://docs.snowflake.com/en/developer-guide/snowflake-cli)"; ok=false
    fi

    echo ""
    if [ "${ok}" = "false" ]; then
        echo -e "${RED}[FATAL] Missing prerequisites. Install them and retry.${NC}"
        exit 1
    fi
}

run_sql_file() {
    local file_path="$1"
    local description="$2"

    if [ ! -f "${file_path}" ]; then
        echo -e "  ${RED}[ERROR] SQL file not found: ${file_path}${NC}"
        return 1
    fi

    echo -e "  ${CYAN}[SQL]${NC} Running: ${description}..."
    if snow sql --connection "${CONNECTION}" --filename "${file_path}"; then
        echo -e "  ${GREEN}[OK]${NC}  ${description} complete"
    else
        echo -e "  ${RED}[FAIL]${NC} ${description} — see error above"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Phase 1 — Data Generation
# ---------------------------------------------------------------------------
phase_1_generate_data() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}PHASE 1: DATA GENERATION${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    mkdir -p "${DATA_DIR}"

    QUICK_FLAG=""
    if [ "${QUICK}" = "true" ]; then QUICK_FLAG="--quick"; fi

    echo "  Generating ServiceNow CMDB data..."
    python3 "${TOOLS_DIR}/generate_servicenow_data.py" --output "${DATA_DIR}" --scale "${SCALE}" ${QUICK_FLAG}

    echo "  Generating Workday DCIM data..."
    python3 "${TOOLS_DIR}/generate_workday_dcim_data.py" --output "${DATA_DIR}" --scale "${SCALE}" ${QUICK_FLAG}

    echo "  Generating Telemetry data..."
    python3 "${TOOLS_DIR}/generate_telemetry_data.py" --output "${DATA_DIR}" --scale "${SCALE}" ${QUICK_FLAG}

    echo "  Generating Siemens DCIM data (acquired portfolio — 2K DCs)..."
    python3 "${TOOLS_DIR}/generate_siemens_data.py" --output "${DATA_DIR}" ${QUICK_FLAG}

    echo ""
    echo -e "  ${GREEN}[OK]${NC} Data generation complete. Files in ${DATA_DIR}/"
    ls -lh "${DATA_DIR}"/servicenow/ "${DATA_DIR}"/workday_dcim/ "${DATA_DIR}"/telemetry/ 2>/dev/null | tail -30 || true
    echo ""
}

# ---------------------------------------------------------------------------
# Phase 2 — Upload & Load
# ---------------------------------------------------------------------------
phase_2_upload_and_load() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}PHASE 2: DATA UPLOAD & LOAD${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    echo "  Uploading ServiceNow data to stage..."
    snow sql --connection "${CONNECTION}" \
        -q "PUT file://${DATA_DIR}/servicenow/*.csv @RAW_DEV.STAGING.DATA_STAGE/servicenow/ AUTO_COMPRESS=TRUE OVERWRITE=TRUE;"
    echo -e "  ${GREEN}[OK]${NC} ServiceNow data uploaded"

    echo "  Uploading Workday DCIM data to stage..."
    snow sql --connection "${CONNECTION}" \
        -q "PUT file://${DATA_DIR}/workday_dcim/*.csv @RAW_DEV.STAGING.DATA_STAGE/workday_dcim/ AUTO_COMPRESS=TRUE OVERWRITE=TRUE;"
    echo -e "  ${GREEN}[OK]${NC} Workday data uploaded"

    echo "  Uploading Telemetry data to stage..."
    snow sql --connection "${CONNECTION}" \
        -q "PUT file://${DATA_DIR}/telemetry/*.csv @RAW_DEV.STAGING.DATA_STAGE/telemetry/ AUTO_COMPRESS=TRUE OVERWRITE=TRUE;"
    echo -e "  ${GREEN}[OK]${NC} Telemetry data uploaded"

    echo "  Uploading Siemens DCIM data..."
    snow sql --connection "${CONNECTION}" \
        -q "PUT file://${DATA_DIR}/siemens_dcim/*.csv @RAW_DEV.STAGING.DATA_STAGE/siemens_dcim/ AUTO_COMPRESS=TRUE OVERWRITE=TRUE;"
    echo -e "  ${GREEN}[OK]${NC} Siemens data uploaded"

    echo ""
    echo "  Loading data into RAW tables..."
    snow sql --connection "${CONNECTION}" \
        -q "USE ROLE DATA_ADMIN; CALL RAW_DEV.STAGING.SP_LOAD_DCIM_DATA();"
    echo -e "  ${GREEN}[OK]${NC} Data load complete"
    echo ""
}

# ---------------------------------------------------------------------------
# Phase 3 — SQL Scripts (Schemas + Curated + Graph + Analytics)
# ---------------------------------------------------------------------------
phase_3_sql_scripts() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}PHASE 3: SQL SCRIPTS${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    run_sql_file "${SQL_DIR}/01_dcim_schemas.sql"          "DCIM schemas (ServiceNow, Workday, Telemetry)"
    run_sql_file "${SQL_DIR}/02_dcim_load_data.sql"        "Data loader stored procedure"
    run_sql_file "${SQL_DIR}/03_dcim_curated_layer.sql"    "Curated Dynamic Tables"
    run_sql_file "${SQL_DIR}/04_dcim_graph_populate.sql"    "Infrastructure graph nodes"
    run_sql_file "${SQL_DIR}/04b_dcim_siemens_graph_populate.sql" "Siemens graph extensions"
    run_sql_file "${SQL_DIR}/05_dcim_workday_populate.sql" "Workday graph nodes"
    run_sql_file "${SQL_DIR}/06_dcim_risk_scoring.sql"     "Risk scoring procedures"
    run_sql_file "${SQL_DIR}/07_dcim_rai_inference.sql"    "RAI inference procedures"
    run_sql_file "${SQL_DIR}/08_dcim_scd6_time_travel.sql" "SCD6 time-travel views"
    run_sql_file "${SQL_DIR}/09_dcim_run_all.sql"          "Master orchestrator procedure"
    run_sql_file "${SQL_DIR}/10_dcim_semantic_views.sql"   "Semantic views for Cortex Analyst"

    echo ""
    echo -e "  ${GREEN}[OK]${NC} All SQL scripts complete"
    echo ""
}

# ---------------------------------------------------------------------------
# Phase 4 — Run Orchestrator
# ---------------------------------------------------------------------------
phase_4_orchestrate() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}PHASE 4: ORCHESTRATION${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    echo -e "  ${CYAN}[EXEC]${NC} Running SP_DCIM_MASTER_ORCHESTRATOR()..."
    snow sql --connection "${CONNECTION}" \
        -q "USE ROLE DATA_ADMIN; CALL DCA_DEMO.GOVERNANCE.SP_DCIM_MASTER_ORCHESTRATOR();"
    echo -e "  ${GREEN}[OK]${NC} Master orchestrator complete"
    echo ""
}

# ---------------------------------------------------------------------------
# Phase 5 — Validation
# ---------------------------------------------------------------------------
phase_5_validation() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}PHASE 5: VALIDATION${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    echo -e "  ${CYAN}[CHECK]${NC} Running validation queries..."
    snow sql --connection "${CONNECTION}" -q "
USE ROLE ONTOLOGY_ADMIN;

SELECT '=== NODE COUNTS ===' AS section;
SELECT source_system, COUNT(*) AS nodes
  FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
 WHERE source_system IN ('SERVICENOW', 'WORKDAY', 'NETWORK_OBSERVABILITY')
 GROUP BY 1 ORDER BY 2 DESC;

SELECT '=== EDGE COUNTS ===' AS section;
SELECT edge_type, COUNT(*) AS edges
  FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
 WHERE source_system IN ('SERVICENOW', 'WORKDAY', 'NETWORK_OBSERVABILITY')
 GROUP BY 1 ORDER BY 2 DESC LIMIT 10;

SELECT '=== RAW TABLE COUNTS ===' AS section;
SELECT 'SERVICENOW.DATA_CENTERS' AS tbl, COUNT(*) AS rows FROM RAW_DEV.SERVICENOW.DATA_CENTERS
UNION ALL SELECT 'SERVICENOW.SWITCHES',     COUNT(*) FROM RAW_DEV.SERVICENOW.SWITCHES
UNION ALL SELECT 'SERVICENOW.INCIDENTS',     COUNT(*) FROM RAW_DEV.SERVICENOW.INCIDENTS
UNION ALL SELECT 'WORKDAY_DCIM.TECHNICIANS', COUNT(*) FROM RAW_DEV.WORKDAY_DCIM.TECHNICIANS
UNION ALL SELECT 'TELEMETRY.PORT_METRICS',   COUNT(*) FROM RAW_DEV.TELEMETRY.PORT_METRICS
UNION ALL SELECT 'TELEMETRY.ALERTS',         COUNT(*) FROM RAW_DEV.TELEMETRY.ALERTS;
"

    echo ""
    echo -e "  ${GREEN}[OK]${NC} Validation complete — review counts above"
    echo ""
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_summary() {
    local elapsed=$1
    local mins=$((elapsed / 60))
    local secs=$((elapsed % 60))

    echo ""
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  DCIM DEPLOYMENT COMPLETE                                  ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "  Duration     : ${mins}m ${secs}s"
    echo "  Connection   : ${CONNECTION}"
    echo "  Data scale   : ${SCALE}"
    echo ""
    echo "  Streamlit    : Deploy via Snowsight or:"
    echo "    snow streamlit deploy --connection ${CONNECTION}"
    echo ""
    echo "  Next steps   :"
    echo "    1. Run queries in DEMO_SCRIPT.md to verify end-to-end"
    echo "    2. Open Streamlit app -> DCIM Command Center page"
    echo "    3. Review WORKSHOP_GUIDE.md for guided walkthrough"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    parse_args "$@"
    print_banner
    check_prerequisites

    START_TIME=$(date +%s)

    if [ "${DATA_ONLY}" = "true" ]; then
        phase_1_generate_data
        phase_2_upload_and_load
    elif [ "${SQL_ONLY}" = "true" ]; then
        phase_3_sql_scripts
        phase_4_orchestrate
    else
        phase_1_generate_data
        phase_2_upload_and_load
        phase_3_sql_scripts
        phase_4_orchestrate
        phase_5_validation
    fi

    END_TIME=$(date +%s)
    print_summary $((END_TIME - START_TIME))
}

main "$@"
