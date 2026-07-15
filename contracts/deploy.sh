#!/bin/bash
set -euo pipefail
# ============================================================================
# DATA CONTRACTS ON HORIZON — DEPLOYMENT SCRIPT
# ============================================================================
#
# Deploys the Horizon-native data contract layer (GOVERNANCE.DATA_CONTRACTS)
# into an existing DCA demo account.
#
# Prerequisites:
#   - Core DCA demo deployed (sql/01..09 at minimum; RAW_DEV/CURATED_DEV present)
#   - Optional but recommended: sql/17_select_star_horizon_context.sql
#     (enables CROSS_PLATFORM lineage assertions)
#   - snow CLI installed with a configured connection
#   - Serverless DMF grants applied once as ACCOUNTADMIN (see --print-grants)
#
# Usage:
#   ./deploy.sh --connection default                 # full deploy + seed
#   ./deploy.sh --connection default --no-seed        # skip demo contracts
#   ./deploy.sh --connection default --validate        # deploy, seed, run a validation
#   ./deploy.sh --print-grants                         # print the ACCOUNTADMIN grants and exit
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SQL_DIR="${SCRIPT_DIR}/sql"

CONNECTION=""
SEED=true
VALIDATE=false

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

print_grants() {
    cat <<'EOF'
-- Run ONCE as ACCOUNTADMIN before deploying (enables serverless DMFs + ACCOUNT_USAGE):
USE ROLE ACCOUNTADMIN;
GRANT EXECUTE DATA METRIC FUNCTION ON ACCOUNT TO ROLE DATA_ADMIN;
GRANT DATABASE ROLE SNOWFLAKE.DATA_METRIC_USER TO ROLE DATA_ADMIN;
GRANT APPLICATION ROLE SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER TO ROLE DATA_ADMIN;
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE DATA_ADMIN;   -- ACCOUNT_USAGE lineage
GRANT EXECUTE TASK ON ACCOUNT TO ROLE DATA_ADMIN;                     -- monitoring task
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --connection) CONNECTION="$2"; shift 2;;
        --no-seed)    SEED=false; shift;;
        --validate)   VALIDATE=true; shift;;
        --print-grants) print_grants; exit 0;;
        *) echo -e "${RED}Unknown arg: $1${NC}"; exit 1;;
    esac
done

if [[ -z "${CONNECTION}" ]]; then
    echo -e "${RED}Error: --connection is required.${NC}"
    echo "Usage: ./deploy.sh --connection <name> [--no-seed] [--validate]"
    exit 1
fi

echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  DATA CONTRACTS ON HORIZON — DEPLOYMENT                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "  Connection : ${CONNECTION}"
echo "  Seed demo  : ${SEED}"
echo "  Validate   : ${VALIDATE}"
echo ""

run_sql() {
    local file="$1"
    echo -e "${CYAN}▶ Running $(basename "$file")…${NC}"
    if snow sql --connection "${CONNECTION}" --filename "${file}" >/tmp/contracts_deploy.log 2>&1; then
        echo -e "${GREEN}  ✓ $(basename "$file")${NC}"
    else
        echo -e "${RED}  ✗ $(basename "$file") failed${NC}"
        tail -n 30 /tmp/contracts_deploy.log
        exit 1
    fi
}

# Core deploy order
CORE_FILES=(
    "00_setup.sql"
    "01_registry.sql"
    "02_dmf_library.sql"
    "03_schema_contracts.sql"
    "04_quality_contracts.sql"
    "05_sla_contracts.sql"
    "06_lineage_contracts.sql"
    "07_enforcement.sql"
    "09_views_dashboard.sql"
)

for f in "${CORE_FILES[@]}"; do
    run_sql "${SQL_DIR}/${f}"
done

if [[ "${SEED}" == "true" ]]; then
    run_sql "${SQL_DIR}/08_seed_demo_contracts.sql"
fi

if [[ "${VALIDATE}" == "true" ]]; then
    echo -e "${CYAN}▶ Running a sample validation (CONTRACT-SAP-FACT-REVENUE)…${NC}"
    snow sql --connection "${CONNECTION}" \
        --query "CALL GOVERNANCE.DATA_CONTRACTS.VALIDATE_CONTRACT('CONTRACT-SAP-FACT-REVENUE','_LOADED_AT','MANUAL');" \
        || echo -e "${YELLOW}  (validation returned non-zero — check object/column names)${NC}"
fi

echo ""
echo -e "${GREEN}${BOLD}✓ Data contract layer deployed.${NC}"
echo ""
echo "Next steps:"
echo "  • Inspect health:  SELECT * FROM GOVERNANCE.DATA_CONTRACTS.V_CONTRACT_HEALTH;"
echo "  • Arm monitoring:  ALTER TASK  GOVERNANCE.DATA_CONTRACTS.TASK_MONITOR_CONTRACTS RESUME;"
echo "  • Arm SLA alert:   ALTER ALERT GOVERNANCE.DATA_CONTRACTS.ALERT_SLA_BREACH RESUME;"
echo "  • Streamlit page:  see contracts/README.md → Streamlit integration"
echo ""
