#!/bin/bash
set -euo pipefail
#
# ============================================================================
# HCLS DEMO — END-TO-END DEPLOYMENT
# ============================================================================
#
# Deploys the complete HCLS Staffing-Outcomes-Payer Intelligence Platform
# to a Snowflake Business Critical account.
#
# Usage:
#   ./deploy.sh --connection default
#   ./deploy.sh --connection default --quick          # 10% data for testing
#   ./deploy.sh --connection default --skip-data      # Skip data generation (reuse existing)
#   ./deploy.sh --connection default --skip-hardening # Skip network/BCDR
#   ./deploy.sh --connection default --data-only      # Only generate + load data
#   ./deploy.sh --connection default --sql-only       # Only run SQL scripts
#   ./deploy.sh --help
#
# Prerequisites:
#   - Python 3.9+ with faker and snowflake-connector-python
#   - snow CLI (Snowflake CLI) installed
#   - Snowflake Business Critical account with ACCOUNTADMIN access
#
# Deployment Order (follows DEPLOYMENT_RUNBOOK.md):
#   Phase 1: Data Generation (local)
#   Phase 2: Foundation SQL (01_setup, 03_raw, 07_governance, etc.)
#   Phase 3: Data Upload & Load
#   Phase 4: HCLS Graph Extensions (scripts 01-07)
#   Phase 5: Security Hardening (optional, interactive)
#   Phase 6: Validation
#
# ============================================================================

# ---------------------------------------------------------------------------
# Directory layout
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOOLS_DIR="${SCRIPT_DIR}/tools"
SQL_DIR="${SCRIPT_DIR}/sql"
CORE_SQL_DIR="${REPO_ROOT}/sql"
DATA_DIR="${SCRIPT_DIR}/data"

# ---------------------------------------------------------------------------
# Defaults (overridden by CLI flags)
# ---------------------------------------------------------------------------
CONNECTION=""
QUICK=false
SCALE="1.0"
SKIP_DATA=false
SKIP_HARDENING=false
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
    echo "║  HCLS DEMO — END-TO-END DEPLOYMENT                        ║"
    echo "║  Staffing · Outcomes · Payer Intelligence Platform         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "  Started : $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "  Conn    : ${CONNECTION}"
    echo "  Quick   : ${QUICK}  (scale=${SCALE})"
    echo "  Flags   : skip-data=${SKIP_DATA} skip-hardening=${SKIP_HARDENING}"
    echo "            data-only=${DATA_ONLY} sql-only=${SQL_ONLY}"
    echo ""
}

usage() {
    cat <<EOF
Usage: $(basename "$0") --connection <NAME> [OPTIONS]

Required:
  --connection NAME       Snowflake CLI connection name (e.g. default)

Options:
  --quick                 Generate ~10 % data for fast testing
  --scale FLOAT           Data scale factor (default: 1.0, --quick sets 0.1)
  --skip-data             Skip Phase 1 data generation (reuse existing files)
  --skip-hardening        Skip Phase 5 network hardening / BCDR
  --data-only             Run only Phases 1 + 3 (generate + load)
  --sql-only              Run only Phases 2 + 4 (foundation + extensions SQL)
  -h, --help              Show this help message

Examples:
  ./deploy.sh --connection default
  ./deploy.sh --connection default --quick
  ./deploy.sh --connection default --skip-hardening
  ./deploy.sh --connection default --data-only --quick
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --connection)   CONNECTION="$2"; shift 2 ;;
            --quick)        QUICK=true; SCALE="0.1"; shift ;;
            --scale)        SCALE="$2"; shift 2 ;;
            --skip-data)    SKIP_DATA=true; shift ;;
            --skip-hardening) SKIP_HARDENING=true; shift ;;
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

    # snowflake-connector-python
    if python3 -c "import snowflake.connector" 2>/dev/null; then
        echo -e "  ${GREEN}[OK]${NC} snowflake-connector-python"
    else
        echo -e "  ${RED}[MISSING]${NC} snowflake-connector-python"; ok=false
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
    # Use _run_sql.py which handles SQL Scripting (BEGIN/END) correctly.
    # The snow sql CLI naively splits on semicolons, breaking stored procedures.
    if python3 "${TOOLS_DIR}/_run_sql.py" --connection "${CONNECTION}" --file "${file_path}"; then
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
    cd "${TOOLS_DIR}"

    QUICK_FLAG=""
    if [ "${QUICK}" = "true" ]; then QUICK_FLAG="--quick"; fi

    echo "  Generating FHIR clinical data..."
    python3 generate_hcls_data.py --output "${DATA_DIR}" --scale "${SCALE}" ${QUICK_FLAG}

    echo "  Generating Workday HCM data..."
    python3 generate_workday_hcm_data.py --output "${DATA_DIR}" --scale "${SCALE}" ${QUICK_FLAG}

    echo "  Generating Payer data..."
    python3 generate_payer_data.py --output "${DATA_DIR}" --scale "${SCALE}" ${QUICK_FLAG}

    echo ""
    echo -e "  ${GREEN}[OK]${NC} Data generation complete. Files in ${DATA_DIR}/"
    ls -lh "${DATA_DIR}"/fhir/ "${DATA_DIR}"/workday_hcm/ "${DATA_DIR}"/payer/ 2>/dev/null | tail -30 || true
    echo ""
}

# ---------------------------------------------------------------------------
# Phase 2 — Foundation SQL
# ---------------------------------------------------------------------------
phase_2_foundation_sql() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}PHASE 2: FOUNDATION SQL${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    run_sql_file "${CORE_SQL_DIR}/01_setup.sql"                 "Account setup (roles, warehouses, databases)"
    run_sql_file "${CORE_SQL_DIR}/03_raw_layer.sql"             "RAW layer (stages, formats, procedures)"
    run_sql_file "${SQL_DIR}/10_hcls_load_data.sql"             "HCLS schemas + load procedure"
    run_sql_file "${CORE_SQL_DIR}/05_curated_layer.sql"         "Curated layer (Dynamic Tables)"
    run_sql_file "${CORE_SQL_DIR}/07_governance.sql"            "Governance (masking, RLS, tags)"

    # Ontology Knowledge Graph — Snowflake-native (recursive CTEs on the
    # nodes/edges tables, no sidecar or container service).
    # See docs/KNOWLEDGE_GRAPH.md for the graph model and query patterns.
    run_sql_file "${CORE_SQL_DIR}/11_rai_setup.sql"               "Ontology graph roles & grants"
    run_sql_file "${CORE_SQL_DIR}/12_ontology_graph_tables.sql"   "Graph tables (nodes, edges, scores)"
    run_sql_file "${CORE_SQL_DIR}/13_ontology_graph_populate.sql" "Graph population procedures"
    run_sql_file "${CORE_SQL_DIR}/14_rai_graph_sync.sql"          "Graph inference procedures (pure SQL, batch)"
    run_sql_file "${CORE_SQL_DIR}/16_graph_algorithms.sql"        "On-demand graph algorithms (views + SPs, Snowflake-native)"
    # Note: 15_ontology_sharing.sql runs in Phase 4 after graph data is populated

    echo ""
    echo -e "  ${GREEN}[OK]${NC} Foundation SQL complete"
    echo ""
}

# ---------------------------------------------------------------------------
# Phase 3 — Data Upload & Load
# ---------------------------------------------------------------------------
phase_3_upload_and_load() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}PHASE 3: DATA UPLOAD & LOAD${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    python3 "${TOOLS_DIR}/build_and_load.py" \
        --connection "${CONNECTION}" \
        --load-only \
        --data-dir "${DATA_DIR}"

    echo ""
    echo -e "  ${GREEN}[OK]${NC} Data upload & load complete"
    echo ""
}

# ---------------------------------------------------------------------------
# Phase 4 — HCLS Graph Extensions
# ---------------------------------------------------------------------------
phase_4_hcls_extensions() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}PHASE 4: HCLS GRAPH EXTENSIONS${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    run_sql_file "${SQL_DIR}/01_hcls_graph_populate.sql"   "Clinical graph nodes"
    run_sql_file "${SQL_DIR}/02_hcls_hipaa_gaps.sql"       "HIPAA compliance gaps (demo)"
    run_sql_file "${SQL_DIR}/03_hcls_rai_inference.sql"    "Inference procedures"
    run_sql_file "${SQL_DIR}/04_hcls_workday_populate.sql" "Workday graph nodes"
    run_sql_file "${SQL_DIR}/05_hcls_staffing_outcomes.sql" "Staffing-outcomes analytics"
    run_sql_file "${SQL_DIR}/06_hcls_comorbidity_payer.sql" "Comorbidity + payer analytics"
    run_sql_file "${SQL_DIR}/07_hcls_run_all.sql"          "Master orchestrator procedure"

    echo ""
    echo -e "  ${CYAN}[EXEC]${NC} Running SP_HCLS_MASTER_ORCHESTRATOR()..."
    snow sql --connection "${CONNECTION}" \
        -q "USE ROLE DATA_ADMIN; CALL DCA_DEMO.GOVERNANCE.SP_HCLS_MASTER_ORCHESTRATOR();"
    echo -e "  ${GREEN}[OK]${NC} Master orchestrator complete"

    # Sharing configuration (runs after graph is populated)
    run_sql_file "${CORE_SQL_DIR}/15_ontology_sharing.sql" "Ontology sharing configuration" || true
    echo ""
}

# ---------------------------------------------------------------------------
# Phase 5 — Security Hardening
# ---------------------------------------------------------------------------
phase_5_hardening() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}PHASE 5: SECURITY HARDENING (interactive)${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    echo -e "  ${YELLOW}NOTE:${NC} Network hardening requires customer-specific IP CIDRs."
    echo "  Edit ${SQL_DIR}/09_hcls_network_hardening.sql with your CIDRs first."
    echo ""

    read -p "  Run network hardening now? (y/N): " CONFIRM
    if [ "${CONFIRM}" = "y" ] || [ "${CONFIRM}" = "Y" ]; then
        run_sql_file "${SQL_DIR}/09_hcls_network_hardening.sql" "Network hardening"
    else
        echo -e "  ${YELLOW}[SKIP]${NC} Network hardening — run manually when ready"
    fi

    echo ""
    run_sql_file "${SQL_DIR}/08_hcls_bcdr_deploy.sql" "BC/DR validation"
    echo ""
}

# ---------------------------------------------------------------------------
# Phase 6 — Validation
# ---------------------------------------------------------------------------
phase_6_validation() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}PHASE 6: VALIDATION${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    echo -e "  ${CYAN}[CHECK]${NC} Running validation queries..."
    snow sql --connection "${CONNECTION}" -q "
USE ROLE DATA_ADMIN;

SELECT '=== NODE COUNTS ===' AS section;
SELECT source_system, COUNT(*) AS nodes
  FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
 GROUP BY 1 ORDER BY 2 DESC;

SELECT '=== EDGE COUNTS ===' AS section;
SELECT edge_type, COUNT(*) AS edges
  FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
 GROUP BY 1 ORDER BY 2 DESC LIMIT 10;

SELECT '=== ANALYTICS TABLES ===' AS section;
SELECT 'HCLS_CORRELATION_RESULTS' AS tbl, COUNT(*) AS rows FROM SEM_DEV.HCLS_ANALYTICS.HCLS_CORRELATION_RESULTS
UNION ALL SELECT 'HCLS_PAYER_METRICS',        COUNT(*) FROM SEM_DEV.HCLS_ANALYTICS.HCLS_PAYER_METRICS
UNION ALL SELECT 'HCLS_PATIENT_COMORBIDITY',   COUNT(*) FROM SEM_DEV.HCLS_ANALYTICS.HCLS_PATIENT_COMORBIDITY
UNION ALL SELECT 'HCLS_STAFFING_CONTEXT',      COUNT(*) FROM SEM_DEV.HCLS_ANALYTICS.HCLS_STAFFING_CONTEXT;
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
    echo "║  DEPLOYMENT COMPLETE                                       ║"
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
    echo "    2. Open Streamlit app -> Ontological Signal Graph page"
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
        phase_3_upload_and_load
    elif [ "${SQL_ONLY}" = "true" ]; then
        phase_2_foundation_sql
        phase_4_hcls_extensions
    else
        [ "${SKIP_DATA}" = "false" ] && phase_1_generate_data
        phase_2_foundation_sql
        phase_3_upload_and_load
        phase_4_hcls_extensions
        [ "${SKIP_HARDENING}" = "false" ] && phase_5_hardening
        phase_6_validation
    fi

    END_TIME=$(date +%s)
    print_summary $((END_TIME - START_TIME))
}

main "$@"
