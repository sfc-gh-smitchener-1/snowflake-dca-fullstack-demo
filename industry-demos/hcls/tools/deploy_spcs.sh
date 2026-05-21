#!/bin/bash
set -euo pipefail
#
# HCLS SPCS Deployment — Build, Push, and Create Service
#
# Builds the Ontology Graph API container image, pushes it to the
# Snowflake Image Repository, and creates/updates the SPCS service.
#
# Prerequisites:
#   - Docker installed and running
#   - snow CLI (snowflake-cli) installed
#   - sql/11_rai_setup.sql has been run (compute pool + image repo exist)
#   - ACCOUNTADMIN or ONTOLOGY_ADMIN role access
#
# Usage:
#   ./deploy_spcs.sh --org SFSENORTHAMERICA --account OAB74379
#   ./deploy_spcs.sh --org SFSENORTHAMERICA --account OAB74379 --rebuild
#   ./deploy_spcs.sh --org SFSENORTHAMERICA --account OAB74379 --restart-only
#   ./deploy_spcs.sh --org SFSENORTHAMERICA --account OAB74379 --backend snowflake
#   ./deploy_spcs.sh --help
#
# Graph backend selection (--backend):
#   both       (default) — FastAPI + Neo4j sidecar; dispatch per request via ?backend=
#   snowflake             — FastAPI only, no Neo4j image pull/push; uses service-spec.snowflake-only.yaml
#   neo4j                 — same image set as "both" but defaults requests to Neo4j
#
# See docs/GRAPH_BACKENDS.md for the compare/contrast and when to choose which.

# ── Defaults ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
SPCS_DIR="${REPO_ROOT}/ontology/spcs"

ORG=""
ACCOUNT=""
CONNECTION=""
TAG="latest"
REBUILD=false
RESTART_ONLY=false
BACKEND="both"   # snowflake | neo4j | both

IMAGE_NAME="ontology-graph-api"
NEO4J_IMAGE="neo4j:5-community"
NEO4J_TARGET_NAME="neo4j-community"

# ── Functions ───────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") --org <ORG> --account <ACCOUNT> [OPTIONS]

Required:
  --org         Snowflake organization name (e.g., SFSENORTHAMERICA)
  --account     Snowflake account locator  (e.g., OAB74379)

Options:
  --connection  Snowflake CLI connection name (for snow sql / token auth)
  --tag         Docker image tag          (default: latest)
  --rebuild     Force Docker build with --no-cache
  --restart-only  Skip build/push, just restart the SPCS service
  --backend     Graph backend: snowflake | neo4j | both  (default: both)
                  snowflake → Snowflake-native only (no Neo4j sidecar; lighter footprint)
                  neo4j     → both engines deployed; default request routes to Neo4j
                  both      → both engines deployed; default request routes to Snowflake
                See docs/GRAPH_BACKENDS.md for the trade-off and decision matrix.
  --help        Show this help
EOF
    exit 0
}

log()  { echo "[$(date +%H:%M:%S)] $*"; }
ok()   { echo "[$(date +%H:%M:%S)] [OK] $*"; }
fail() { echo "[$(date +%H:%M:%S)] [FAIL] $*" >&2; }

snow_sql() {
    local sql="$1"
    if [ -n "${CONNECTION}" ]; then
        snow sql --connection "${CONNECTION}" -q "${sql}"
    else
        snow sql -q "${sql}"
    fi
}

# ── Argument parsing ────────────────────────────────────────────────────

while [ $# -gt 0 ]; do
    case "$1" in
        --org)         ORG="$2";        shift 2 ;;
        --account)     ACCOUNT="$2";    shift 2 ;;
        --connection)  CONNECTION="$2";  shift 2 ;;
        --tag)         TAG="$2";        shift 2 ;;
        --rebuild)     REBUILD=true;    shift   ;;
        --restart-only) RESTART_ONLY=true; shift ;;
        --backend)     BACKEND="$2";    shift 2 ;;
        --help|-h)     usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

if [ -z "${ORG}" ] || [ -z "${ACCOUNT}" ]; then
    echo "ERROR: --org and --account are required."
    usage
fi

case "${BACKEND}" in
    snowflake|neo4j|both) ;;
    *) echo "ERROR: --backend must be 'snowflake', 'neo4j', or 'both' (got '${BACKEND}')"; exit 1 ;;
esac

# Choose service spec file based on backend selection.
# "snowflake" deploys without a Neo4j sidecar; the other two share the dual-backend spec.
if [ "${BACKEND}" = "snowflake" ]; then
    SERVICE_SPEC_FILE="service-spec.snowflake-only.yaml"
else
    SERVICE_SPEC_FILE="service-spec.yaml"
fi

# ── Derived variables ──────────────────────────────────────────────────

REGISTRY="${ORG,,}-${ACCOUNT,,}.registry.snowflakecomputing.com"
IMAGE_PATH="dca_demo/governance/ontology_graph_repo/${IMAGE_NAME}"
FULL_IMAGE="${REGISTRY}/${IMAGE_PATH}:${TAG}"
NEO4J_IMAGE_PATH="dca_demo/governance/ontology_graph_repo/${NEO4J_TARGET_NAME}"
FULL_NEO4J_IMAGE="${REGISTRY}/${NEO4J_IMAGE_PATH}:${TAG}"

# ── Prerequisites ──────────────────────────────────────────────────────

check_prerequisites() {
    log "Checking prerequisites..."

    if ! command -v docker &>/dev/null; then
        fail "Docker is not installed. Install from https://docs.docker.com/get-docker/"
        exit 1
    fi

    if ! docker info &>/dev/null; then
        fail "Docker daemon is not running. Start Docker Desktop and retry."
        exit 1
    fi

    if ! command -v snow &>/dev/null; then
        fail "Snowflake CLI (snow) is not installed. Install with: pip install snowflake-cli"
        exit 1
    fi

    if [ ! -f "${SPCS_DIR}/Dockerfile" ]; then
        fail "Dockerfile not found at ${SPCS_DIR}/Dockerfile"
        exit 1
    fi

    if [ ! -f "${SPCS_DIR}/${SERVICE_SPEC_FILE}" ]; then
        fail "Service spec not found at ${SPCS_DIR}/${SERVICE_SPEC_FILE}"
        exit 1
    fi

    ok "All prerequisites met"
    log "  Registry     : ${REGISTRY}"
    log "  Image        : ${FULL_IMAGE}"
    log "  SPCS dir     : ${SPCS_DIR}"
    log "  Graph backend: ${BACKEND}"
    log "  Service spec : ${SERVICE_SPEC_FILE}"
}

# ── Docker Build ───────────────────────────────────────────────────────

docker_build() {
    log "=== BUILDING CONTAINER IMAGES ==="

    local build_args=(-t "${IMAGE_NAME}:${TAG}" "${SPCS_DIR}")
    if [ "${REBUILD}" = "true" ]; then
        log "  (forced rebuild, no cache)"
        build_args=(--no-cache "${build_args[@]}")
    fi
    docker build "${build_args[@]}"
    ok "API image built: ${IMAGE_NAME}:${TAG}"

    if [ "${BACKEND}" = "snowflake" ]; then
        log "  Skipping Neo4j image (backend=snowflake only)"
    else
        log "  Pulling Neo4j Community..."
        docker pull "${NEO4J_IMAGE}"
        ok "Neo4j pulled: ${NEO4J_IMAGE}"
    fi
}

# ── Docker Tag ─────────────────────────────────────────────────────────

docker_tag() {
    log "=== TAGGING FOR SNOWFLAKE REGISTRY ==="
    docker tag "${IMAGE_NAME}:${TAG}" "${FULL_IMAGE}"
    ok "Tagged: ${FULL_IMAGE}"
    if [ "${BACKEND}" != "snowflake" ]; then
        docker tag "${NEO4J_IMAGE}" "${FULL_NEO4J_IMAGE}"
        ok "Tagged: ${FULL_NEO4J_IMAGE}"
    fi
}

# ── Docker Login ───────────────────────────────────────────────────────

docker_login() {
    log "=== AUTHENTICATING TO SNOWFLAKE REGISTRY ==="

    local logged_in=false

    # Try token-based auth via snow CLI first
    if command -v snow &>/dev/null && [ -n "${CONNECTION}" ]; then
        local token
        token=$(snow connection token --connection "${CONNECTION}" 2>/dev/null || true)
        if [ -n "${token}" ]; then
            echo "${token}" | docker login "${REGISTRY}" --username 0sessiontoken --password-stdin 2>/dev/null
            logged_in=true
            ok "Authenticated via snow CLI token"
        fi
    fi

    # Fall back to interactive login
    if [ "${logged_in}" = "false" ]; then
        log "Token auth unavailable. Falling back to interactive login."
        docker login "${REGISTRY}"
    fi
}

# ── Docker Push ────────────────────────────────────────────────────────

docker_push() {
    log "=== PUSHING IMAGES TO SNOWFLAKE ==="
    docker push "${FULL_IMAGE}"
    ok "Pushed: ${FULL_IMAGE}"
    if [ "${BACKEND}" != "snowflake" ]; then
        docker push "${FULL_NEO4J_IMAGE}"
        ok "Pushed: ${FULL_NEO4J_IMAGE}"
    fi
}

# ── Create / Restart SPCS Service ──────────────────────────────────────

create_service() {
    log "=== CREATING / UPDATING SPCS SERVICE ==="
    log "  Using spec: ${SERVICE_SPEC_FILE}  (backend=${BACKEND})"

    local spec
    spec=$(cat "${SPCS_DIR}/${SERVICE_SPEC_FILE}")

    snow_sql "
USE ROLE ONTOLOGY_ADMIN;
USE DATABASE DCA_DEMO;
USE SCHEMA GOVERNANCE;

CREATE SERVICE IF NOT EXISTS DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SERVICE
    IN COMPUTE POOL RAI_COMPUTE_POOL
    FROM SPECIFICATION \$\$
${spec}
\$\$
    MIN_INSTANCES = 1
    MAX_INSTANCES = 1;
"
    ok "Service CREATE issued"
}

restart_service() {
    log "=== RESTARTING SPCS SERVICE ==="
    snow_sql "
USE ROLE ONTOLOGY_ADMIN;
ALTER SERVICE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SERVICE SUSPEND;
ALTER SERVICE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SERVICE RESUME;
"
    ok "Service restarted"
}

# ── Wait for READY ────────────────────────────────────────────────────

wait_for_ready() {
    log "=== WAITING FOR SERVICE TO BE READY ==="
    for i in $(seq 1 30); do
        local status
        status=$(snow_sql "SELECT SYSTEM\$GET_SERVICE_STATUS('DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SERVICE');" 2>/dev/null || true)
        if echo "${status}" | grep -q '"READY"'; then
            ok "Service is READY!"
            return 0
        fi
        log "  Waiting... (${i}/30, checking every 10s)"
        sleep 10
    done
    fail "Service did not reach READY within 5 minutes. Check logs:"
    log "  snow sql -q \"CALL SYSTEM\$GET_SERVICE_LOGS('DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SERVICE', '0', 'ontology-graph-api', 50);\""
    return 1
}

# ── Show Endpoint ─────────────────────────────────────────────────────

show_endpoint() {
    log "=== DEPLOYMENT COMPLETE ==="
    snow_sql "SHOW ENDPOINTS IN SERVICE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SERVICE;"
}

# ── Main ──────────────────────────────────────────────────────────────

main() {
    check_prerequisites

    if [ "${RESTART_ONLY}" = "true" ]; then
        restart_service
        wait_for_ready
        show_endpoint
        return 0
    fi

    docker_build
    docker_tag
    docker_login
    docker_push
    create_service
    wait_for_ready
    show_endpoint
}

main
