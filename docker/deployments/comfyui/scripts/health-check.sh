#!/usr/bin/env bash
# ============================================================================
# ComfyUI Health Check Script
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
print_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

VERBOSE=false
if [[ "${1:-}" == "--verbose" ]] || [[ "${1:-}" == "-v" ]]; then
    VERBOSE=true
fi

print_info "ComfyUI Health Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "${PROJECT_DIR}"

# Check if Docker is running
if ! docker info &>/dev/null; then
    print_error "Docker daemon is not running"
    exit 1
fi

# Check containers
print_info "Checking container status..."
if docker compose ps --format json &>/dev/null; then
    CONTAINER_COUNT=$(docker compose ps --format json 2>/dev/null | jq -s 'length')
    RUNNING_COUNT=$(docker compose ps --format json 2>/dev/null | jq -s '[.[] | select(.State == "running")] | length')

    echo "  Total containers: ${CONTAINER_COUNT}"
    echo "  Running: ${RUNNING_COUNT}"

    if [[ "${VERBOSE}" == "true" ]]; then
        docker compose ps
    fi

    if [[ ${RUNNING_COUNT} -lt ${CONTAINER_COUNT} ]]; then
        print_warning "Some containers are not running"
    else
        print_success "All containers running"
    fi
fi

# Check container health
print_info "Checking container health..."
for container in $(docker compose ps -q 2>/dev/null); do
    CONTAINER_NAME=$(docker inspect --format='{{.Name}}' "${container}" | sed 's/^\/\///')
    HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "${container}" 2>/dev/null || echo "no healthcheck")

    case "${HEALTH_STATUS}" in
        healthy)
            print_success "${CONTAINER_NAME}: healthy"
            ;;
        unhealthy)
            print_error "${CONTAINER_NAME}: unhealthy"
            ;;
        starting)
            print_info "${CONTAINER_NAME}: starting..."
            ;;
        "no healthcheck")
            print_info "${CONTAINER_NAME}: no healthcheck defined"
            ;;
        *)
            print_warning "${CONTAINER_NAME}: ${HEALTH_STATUS}"
            ;;
    esac
done

# Check disk space
print_info "Checking disk space..."
DISK_USAGE=$(df -h "${PROJECT_DIR}" | awk 'NR==2 {print $5}' | sed 's/%//')
if [[ ${DISK_USAGE} -gt 90 ]]; then
    print_error "Disk usage: ${DISK_USAGE}% (critical)"
elif [[ ${DISK_USAGE} -gt 80 ]]; then
    print_warning "Disk usage: ${DISK_USAGE}% (high)"
else
    print_success "Disk usage: ${DISK_USAGE}%"
fi

# Check GPU
if command -v nvidia-smi &>/dev/null; then
    print_info "Checking GPU status..."
    if nvidia-smi &>/dev/null; then
        print_success "GPU accessible"
        if [[ "${VERBOSE}" == "true" ]]; then
            nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total --format=csv,noheader
        fi
    else
        print_warning "GPU not accessible"
    fi
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_success "Health check completed"
