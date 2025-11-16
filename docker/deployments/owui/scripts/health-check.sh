#!/usr/bin/env bash

# ============================================================================
# Health Check Script
# ============================================================================
#
# This script validates that all services are running correctly and healthy.
#
# USAGE:
#   ./scripts/health-check.sh [--verbose]
#
# OPTIONS:
#   --verbose    Show detailed health information
#   --help       Show this help message
#
# EXIT CODES:
#   0 - All services healthy
#   1 - One or more services unhealthy
#
# ============================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

show_help() {
    head -n 17 "$0" | tail -n +3 | sed 's/^# //; s/^#//'
}

# ============================================================================
# Parse Arguments
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# ============================================================================
# Load Environment
# ============================================================================

cd "$PROJECT_ROOT"

if [[ -f .env ]]; then
    # shellcheck disable=SC1091
    source .env
fi

DOMAIN="${DOMAIN:-localhost}"
CADDY_HTTPS_PORT="${CADDY_HTTPS_PORT:-8443}"

# ============================================================================
# Health Check Functions
# ============================================================================

check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        return 1
    fi
    log_success "Docker is installed"
    return 0
}

check_docker_compose() {
    if ! command -v docker compose &> /dev/null && ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose is not installed"
        return 1
    fi
    log_success "Docker Compose is installed"
    return 0
}

check_container_status() {
    local container_name="$1"
    local status

    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        log_error "Container ${container_name} is not running"
        return 1
    fi

    status=$(docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null)

    if [[ "$status" != "running" ]]; then
        log_error "Container ${container_name} status: ${status}"
        return 1
    fi

    log_success "Container ${container_name} is running"

    if [[ "$VERBOSE" == true ]]; then
        local health
        health=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "no healthcheck")
        echo "          Health: ${health}"

        local uptime
        uptime=$(docker inspect --format='{{.State.StartedAt}}' "$container_name" 2>/dev/null)
        echo "          Started: ${uptime}"
    fi

    return 0
}

check_container_health() {
    local container_name="$1"
    local health

    health=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "no healthcheck")

    if [[ "$health" == "healthy" ]]; then
        log_success "Container ${container_name} health check: ${health}"
        return 0
    elif [[ "$health" == "no healthcheck" ]]; then
        log_warning "Container ${container_name} has no health check configured"
        return 0
    else
        log_error "Container ${container_name} health check: ${health}"
        return 1
    fi
}

check_endpoint() {
    local url="$1"
    local name="$2"
    local expected_code="${3:-200}"

    local response_code
    response_code=$(curl -k -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")

    if [[ "$response_code" == "$expected_code" ]]; then
        log_success "${name} endpoint is responding (HTTP ${response_code})"
        return 0
    else
        log_error "${name} endpoint failed (HTTP ${response_code}, expected ${expected_code})"
        return 1
    fi
}

check_network() {
    local network_name="${NETWORK_NAME:-owui-network}"

    if ! docker network ls --format '{{.Name}}' | grep -q "^${network_name}$"; then
        log_error "Network ${network_name} does not exist"
        return 1
    fi

    log_success "Network ${network_name} exists"
    return 0
}

check_volumes() {
    local errors=0

    for dir in "volumes/data" "volumes/cache" "logs/openwebui" "logs/caddy"; do
        if [[ ! -d "$dir" ]]; then
            log_error "Directory ${dir} does not exist"
            ((errors++))
        elif [[ ! -w "$dir" ]]; then
            log_error "Directory ${dir} is not writable"
            ((errors++))
        fi
    done

    if [[ $errors -eq 0 ]]; then
        log_success "All volume directories are accessible"
        return 0
    else
        return 1
    fi
}

check_certificates() {
    if [[ ! -f "certs/server.crt" ]] || [[ ! -f "certs/server.key" ]]; then
        log_warning "TLS certificates not found in certs/"
        return 1
    fi

    # Check certificate expiration
    local expiry
    expiry=$(openssl x509 -in certs/server.crt -noout -enddate 2>/dev/null | cut -d= -f2)

    local expiry_epoch
    expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry" +%s 2>/dev/null)

    local now_epoch
    now_epoch=$(date +%s)

    local days_remaining=$(( (expiry_epoch - now_epoch) / 86400 ))

    if [[ $days_remaining -lt 0 ]]; then
        log_error "TLS certificate has expired"
        return 1
    elif [[ $days_remaining -lt 30 ]]; then
        log_warning "TLS certificate expires in ${days_remaining} days"
    else
        log_success "TLS certificates are valid (expires in ${days_remaining} days)"
    fi

    return 0
}

check_configuration() {
    local errors=0

    # Check if .env exists
    if [[ ! -f ".env" ]]; then
        log_error ".env file not found"
        return 1
    fi

    # Validate WEBUI_SECRET_KEY
    local secret_key
    secret_key=$(grep "^WEBUI_SECRET_KEY=" .env | cut -d= -f2)

    if [[ -z "$secret_key" ]]; then
        log_error "WEBUI_SECRET_KEY is not set in .env"
        ((errors++))
    elif [[ "$secret_key" == "INVALID_PLEASE_RUN_SETUP_SCRIPT_FIRST" ]]; then
        log_error "WEBUI_SECRET_KEY is still set to invalid default value"
        log_error "Run: ./scripts/setup.sh to generate a secure key"
        ((errors++))
    elif [[ "${#secret_key}" -lt 32 ]]; then
        log_error "WEBUI_SECRET_KEY is too short (${#secret_key} characters, minimum 32)"
        log_warning "Generate a new key with: openssl rand -base64 32"
        ((errors++))
    fi

    # Check DOMAIN is set
    local domain
    domain=$(grep "^DOMAIN=" .env | cut -d= -f2)
    if [[ -z "$domain" || "$domain" == "localhost" ]]; then
        log_warning "DOMAIN is set to localhost (development only)"
    fi

    # Check CORS_ALLOW_ORIGIN matches WEBUI_URL
    local cors_origin webui_url
    cors_origin=$(grep "^CORS_ALLOW_ORIGIN=" .env | cut -d= -f2)
    webui_url=$(grep "^WEBUI_URL=" .env | cut -d= -f2)
    if [[ "$cors_origin" != "$webui_url" ]]; then
        log_warning "CORS_ALLOW_ORIGIN and WEBUI_URL do not match"
        log_warning "  CORS_ALLOW_ORIGIN: $cors_origin"
        log_warning "  WEBUI_URL: $webui_url"
    fi

    if [[ $errors -eq 0 ]]; then
        log_success "Configuration validation passed"
        return 0
    else
        log_error "Configuration validation failed with $errors error(s)"
        return 1
    fi
}

# ============================================================================
# Main Health Check Process
# ============================================================================

log_info "Starting health check..."
echo ""

HEALTH_PASSED=true

# Check prerequisites
log_info "Checking prerequisites..."
check_docker || HEALTH_PASSED=false
check_docker_compose || HEALTH_PASSED=false
echo ""

# Check configuration
log_info "Checking configuration..."
check_configuration || HEALTH_PASSED=false
echo ""

# Check network
log_info "Checking Docker network..."
check_network || HEALTH_PASSED=false
echo ""

# Check volumes
log_info "Checking volumes and directories..."
check_volumes || HEALTH_PASSED=false
echo ""

# Check certificates
log_info "Checking TLS certificates..."
check_certificates || true  # Don't fail on certificate warnings
echo ""

# Check container status
log_info "Checking container status..."
PROJECT_NAME="${PROJECT_NAME:-owui}"
check_container_status "${PROJECT_NAME}-caddy" || HEALTH_PASSED=false
check_container_status "${PROJECT_NAME}-openwebui" || HEALTH_PASSED=false
echo ""

# Check container health
log_info "Checking container health..."
check_container_health "${PROJECT_NAME}-caddy" || HEALTH_PASSED=false
check_container_health "${PROJECT_NAME}-openwebui" || HEALTH_PASSED=false
echo ""

# Note: External endpoint checks disabled (HTTPS-only, no dashboard)
# Internal Docker health checks are sufficient
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ "$HEALTH_PASSED" == true ]]; then
    log_success "All health checks passed!"
    echo ""
    echo "🌐 Access URL:"
    echo "   OpenWebUI (HTTPS-only): ${GREEN}https://${DOMAIN}:${CADDY_HTTPS_PORT}${NC}"
    echo ""
    exit 0
else
    log_error "Some health checks failed!"
    echo ""
    echo "📋 Troubleshooting:"
    echo "   1. Check logs: ${BLUE}docker compose logs -f${NC}"
    echo "   2. Restart services: ${BLUE}docker compose restart${NC}"
    echo "   3. Check TROUBLESHOOTING.md for common issues"
    echo ""
    exit 1
fi
