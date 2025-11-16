#!/usr/bin/env bash
# ============================================================================
# ComfyUI Configuration Validation Script
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

ERRORS=0
WARNINGS=0

print_info "Validating ComfyUI configuration..."

# Check .env file
if [[ ! -f "${PROJECT_DIR}/.env" ]]; then
    print_error ".env file not found"
    ((ERRORS++))
else
    print_success ".env file exists"

    # Source .env
    set -a
    source "${PROJECT_DIR}/.env"
    set +a

    # Validate domain
    if [[ -z "${DOMAIN:-}" ]]; then
        print_warning "DOMAIN not set in .env"
        ((WARNINGS++))
    fi

    # Validate network subnet
    if [[ -n "${NETWORK_SUBNET:-}" ]]; then
        if [[ ! "${NETWORK_SUBNET}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
            print_error "Invalid NETWORK_SUBNET format: ${NETWORK_SUBNET}"
            ((ERRORS++))
        fi
    fi
fi

# Check docker-compose.yml
if [[ ! -f "${PROJECT_DIR}/docker-compose.yml" ]]; then
    print_error "docker-compose.yml not found"
    ((ERRORS++))
else
    print_success "docker-compose.yml exists"
fi

# Check certificates
if [[ ! -f "${PROJECT_DIR}/certs/server.crt" ]] || [[ ! -f "${PROJECT_DIR}/certs/server.key" ]]; then
    print_warning "TLS certificates not found. Run: ./scripts/generate-certs.sh"
    ((WARNINGS++))
else
    print_success "TLS certificates exist"

    # Check certificate permissions
    KEY_PERMS=$(stat -c %a "${PROJECT_DIR}/certs/server.key" 2>/dev/null || stat -f %Lp "${PROJECT_DIR}/certs/server.key" 2>/dev/null)
    if [[ "${KEY_PERMS}" != "600" ]]; then
        print_warning "server.key has insecure permissions: ${KEY_PERMS} (should be 600)"
        ((WARNINGS++))
    fi
fi

# Check acme.json
if [[ -f "${PROJECT_DIR}/config/acme.json" ]]; then
    ACME_PERMS=$(stat -c %a "${PROJECT_DIR}/config/acme.json" 2>/dev/null || stat -f %Lp "${PROJECT_DIR}/config/acme.json" 2>/dev/null)
    if [[ "${ACME_PERMS}" != "600" ]]; then
        print_error "acme.json has insecure permissions: ${ACME_PERMS} (must be 600)"
        ((ERRORS++))
    else
        print_success "acme.json permissions correct"
    fi
fi

# Check directories
for dir in volumes logs certs backups; do
    if [[ ! -d "${PROJECT_DIR}/${dir}" ]]; then
        print_warning "Directory missing: ${dir}"
        ((WARNINGS++))
    fi
done

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ ${ERRORS} -eq 0 ]] && [[ ${WARNINGS} -eq 0 ]]; then
    print_success "Configuration validation passed with no issues"
    exit 0
elif [[ ${ERRORS} -eq 0 ]]; then
    print_warning "Configuration validation passed with ${WARNINGS} warning(s)"
    exit 0
else
    print_error "Configuration validation failed with ${ERRORS} error(s) and ${WARNINGS} warning(s)"
    exit 1
fi
