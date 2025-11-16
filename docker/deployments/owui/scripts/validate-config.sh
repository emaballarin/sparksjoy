#!/usr/bin/env bash

# ============================================================================
# Configuration Validation Script
# ============================================================================
#
# This script validates the OpenWebUI deployment configuration.
# It can be run standalone or integrated into CI/CD pipelines.
#
# USAGE:
#   ./scripts/validate-config.sh [--strict] [--env FILE]
#
# OPTIONS:
#   --strict    Exit with error on warnings (default: warnings only)
#   --env FILE  Path to .env file (default: .env)
#   --help      Show this help message
#
# EXIT CODES:
#   0 - All validations passed
#   1 - Critical errors found
#   2 - Warnings found (only in --strict mode)
#
# ============================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Default values
ENV_FILE="${PROJECT_ROOT}/.env"
STRICT_MODE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
ERRORS=0
WARNINGS=0

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
    echo -e "${YELLOW}[⚠]${NC} $1"
    ((WARNINGS++))
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    ((ERRORS++))
}

show_help() {
    head -n 22 "$0" | tail -n +3 | sed 's/^# //; s/^#//'
}

# ============================================================================
# Parse Arguments
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --strict)
            STRICT_MODE=true
            shift
            ;;
        --env)
            ENV_FILE="$2"
            shift 2
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
# Validation Functions
# ============================================================================

validate_env_file() {
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error ".env file not found at: $ENV_FILE"
        return 1
    fi
    log_success ".env file exists"
    return 0
}

get_env_value() {
    local key=$1
    grep "^${key}=" "$ENV_FILE" 2>/dev/null | cut -d= -f2 || echo ""
}

validate_secret_key() {
    local secret_key
    secret_key=$(get_env_value "WEBUI_SECRET_KEY")

    if [[ -z "$secret_key" ]]; then
        log_error "WEBUI_SECRET_KEY is not set"
        return 1
    elif [[ "$secret_key" == "INVALID_PLEASE_RUN_SETUP_SCRIPT_FIRST" ]]; then
        log_error "WEBUI_SECRET_KEY is set to invalid default value"
        log_error "  → Run: ./scripts/setup.sh to generate a secure key"
        return 1
    elif [[ "${#secret_key}" -lt 32 ]]; then
        log_error "WEBUI_SECRET_KEY is too short (${#secret_key} characters, minimum 32)"
        log_error "  → Generate a new key with: openssl rand -base64 32"
        return 1
    else
        log_success "WEBUI_SECRET_KEY validation passed (${#secret_key} characters)"
        return 0
    fi
}

validate_domain() {
    local domain
    domain=$(get_env_value "DOMAIN")

    if [[ -z "$domain" ]]; then
        log_warning "DOMAIN is not set"
        return 0
    fi

    # Validate domain format
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        log_error "DOMAIN has invalid format: $domain"
        log_error "  → Must contain only letters, numbers, hyphens, and dots"
        log_error "  → Cannot start/end with hyphen or contain consecutive dots"
        return 1
    fi

    if [[ "$domain" == "localhost" ]]; then
        log_warning "DOMAIN is set to 'localhost' (development only)"
        log_warning "  → For production, set to your actual domain name"
        return 0
    else
        log_success "DOMAIN is valid: $domain"
        return 0
    fi
}

validate_urls() {
    local webui_url cors_origin
    webui_url=$(get_env_value "WEBUI_URL")
    cors_origin=$(get_env_value "CORS_ALLOW_ORIGIN")

    if [[ -z "$webui_url" ]]; then
        log_error "WEBUI_URL is not set"
        return 1
    fi

    if [[ -z "$cors_origin" ]]; then
        log_error "CORS_ALLOW_ORIGIN is not set"
        return 1
    fi

    if [[ "$cors_origin" != "$webui_url" ]]; then
        log_warning "CORS_ALLOW_ORIGIN and WEBUI_URL do not match"
        log_warning "  → CORS_ALLOW_ORIGIN: $cors_origin"
        log_warning "  → WEBUI_URL: $webui_url"
        return 0
    fi

    log_success "URL configuration is consistent"
    return 0
}

validate_jwt() {
    local jwt_expires
    jwt_expires=$(get_env_value "JWT_EXPIRES_IN")

    if [[ -z "$jwt_expires" ]]; then
        log_warning "JWT_EXPIRES_IN is not set (using default)"
        return 0
    fi

    # Validate format (should be like: 7d, 4w, 12h, etc.)
    if [[ ! "$jwt_expires" =~ ^[0-9]+[smhdw]$ ]]; then
        log_error "JWT_EXPIRES_IN has invalid format: $jwt_expires"
        log_error "  → Valid formats: 7d (days), 4w (weeks), 12h (hours), 30m (minutes), 60s (seconds)"
        return 1
    fi

    log_success "JWT_EXPIRES_IN is valid: $jwt_expires"
    return 0
}

validate_network() {
    local subnet
    subnet=$(get_env_value "NETWORK_SUBNET")

    if [[ -z "$subnet" ]]; then
        log_warning "NETWORK_SUBNET is not set"
        return 0
    fi

    # Basic CIDR validation
    if [[ ! "$subnet" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        log_error "NETWORK_SUBNET has invalid CIDR format: $subnet"
        return 1
    fi

    log_success "NETWORK_SUBNET is valid: $subnet"
    return 0
}

validate_ports() {
    local https_port
    https_port=$(get_env_value "CADDY_HTTPS_PORT")

    if [[ -z "$https_port" ]]; then
        log_warning "CADDY_HTTPS_PORT is not set (using default 8443)"
        return 0
    fi

    if [[ ! "$https_port" =~ ^[0-9]+$ ]] || [[ "$https_port" -lt 1 ]] || [[ "$https_port" -gt 65535 ]]; then
        log_error "CADDY_HTTPS_PORT is invalid: $https_port"
        return 1
    fi

    log_success "Port configuration is valid"
    return 0
}

validate_resource_limits() {
    local openwebui_mem caddy_mem
    openwebui_mem=$(get_env_value "OPENWEBUI_MEMORY_LIMIT")
    caddy_mem=$(get_env_value "CADDY_MEMORY_LIMIT")

    if [[ -z "$openwebui_mem" ]]; then
        log_warning "OPENWEBUI_MEMORY_LIMIT is not set"
    fi

    if [[ -z "$caddy_mem" ]]; then
        log_warning "CADDY_MEMORY_LIMIT is not set"
    fi

    return 0
}

validate_security() {
    local webui_auth cookie_secure
    webui_auth=$(get_env_value "WEBUI_AUTH")
    cookie_secure=$(get_env_value "WEBUI_SESSION_COOKIE_SECURE")

    if [[ "$webui_auth" == "false" ]]; then
        log_warning "WEBUI_AUTH is disabled (not recommended for production)"
        log_warning "  → Enable authentication in production environments"
    fi

    if [[ "$cookie_secure" == "false" ]]; then
        log_warning "WEBUI_SESSION_COOKIE_SECURE is disabled"
        log_warning "  → Enable secure cookies for HTTPS deployments"
    fi

    return 0
}

validate_backup_encryption() {
    local encrypt_enabled gpg_recipient
    encrypt_enabled=$(get_env_value "BACKUP_ENABLE_ENCRYPTION")
    gpg_recipient=$(get_env_value "BACKUP_GPG_RECIPIENT")

    if [[ "$encrypt_enabled" == "false" ]] || [[ -z "$encrypt_enabled" ]]; then
        log_warning "Backup encryption is disabled"
        log_warning "  → Backups will contain sensitive data in plain text"
        log_warning "  → Set BACKUP_ENABLE_ENCRYPTION=true and configure BACKUP_GPG_RECIPIENT"
        return 0
    fi

    if [[ -z "$gpg_recipient" ]]; then
        log_error "BACKUP_ENABLE_ENCRYPTION is true but BACKUP_GPG_RECIPIENT is not set"
        return 1
    fi

    log_success "Backup encryption is configured"
    return 0
}

validate_api_keys() {
    local openai_key
    openai_key=$(get_env_value "OPENAI_API_KEY")

    if [[ -z "$openai_key" ]]; then
        log_info "No OpenAI API key configured (optional)"
    fi

    # Don't validate key format - too provider-specific
    return 0
}

validate_letsencrypt() {
    local acme_email use_letsencrypt
    acme_email=$(get_env_value "ACME_EMAIL")
    use_letsencrypt=$(get_env_value "USE_LETSENCRYPT")

    if [[ "$use_letsencrypt" != "true" ]]; then
        log_info "Let's Encrypt disabled (using manual certificates)"
        return 0
    fi

    if [[ -z "$acme_email" ]]; then
        log_error "USE_LETSENCRYPT is true but ACME_EMAIL is not set"
        return 1
    fi

    # Basic email validation
    if [[ ! "$acme_email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_error "ACME_EMAIL has invalid format: $acme_email"
        return 1
    fi

    log_success "Let's Encrypt email is valid: $acme_email"
    return 0
}

# ============================================================================
# Main Validation Process
# ============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_info "OpenWebUI Configuration Validation"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd "$PROJECT_ROOT"

# Run all validations
validate_env_file || exit 1
echo ""

log_info "Validating critical security settings..."
validate_secret_key
validate_jwt
echo ""

log_info "Validating network configuration..."
validate_domain
validate_urls
validate_network
validate_ports
echo ""

log_info "Validating security settings..."
validate_security
validate_backup_encryption
validate_letsencrypt
echo ""

log_info "Validating resource configuration..."
validate_resource_limits
echo ""

log_info "Validating optional settings..."
validate_api_keys
echo ""

# ============================================================================
# Summary
# ============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ $ERRORS -eq 0 ]] && [[ $WARNINGS -eq 0 ]]; then
    log_success "All validations passed!"
    echo ""
    exit 0
elif [[ $ERRORS -eq 0 ]] && [[ $WARNINGS -gt 0 ]]; then
    echo -e "${YELLOW}Validation completed with ${WARNINGS} warning(s)${NC}"
    echo ""
    if [[ "$STRICT_MODE" == true ]]; then
        log_error "Failing due to --strict mode"
        echo ""
        exit 2
    else
        log_info "Warnings do not prevent deployment (use --strict to fail on warnings)"
        echo ""
        exit 0
    fi
else
    echo -e "${RED}Validation failed with ${ERRORS} error(s) and ${WARNINGS} warning(s)${NC}"
    echo ""
    exit 1
fi
