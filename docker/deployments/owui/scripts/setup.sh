#!/usr/bin/env bash

# ============================================================================
# OpenWebUI Setup Script
# ============================================================================
#
# This script automates the initial setup of the OpenWebUI deployment:
# - Creates .env file from template
# - Generates TLS certificates (Tailscale or self-signed)
# - Creates required directory structure
# - Sets proper permissions
# - Validates configuration
#
# USAGE:
#   ./scripts/setup.sh [OPTIONS]
#
# OPTIONS:
#   --domain DOMAIN       Domain name for certificates (default: localhost)
#   --email EMAIL         Admin email for Let's Encrypt (optional)
#   --use-tailscale       Use Tailscale certificates (requires tailscale CLI)
#   --force               Overwrite existing configuration
#   --skip-certs          Skip certificate generation
#   --help                Show this help message
#
# ============================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ============================================================================
# Error Handling
# ============================================================================

cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo ""
        echo -e "${RED}[ERROR]${NC} Setup failed with exit code: $exit_code"
        echo ""
        echo "Check the error messages above for details."
        echo "If .env.backup was created, you can restore it:"
        echo "  mv .env.backup .env"
        echo ""
    fi
    exit $exit_code
}

# Set up trap for cleanup on error
trap cleanup_on_error EXIT ERR INT TERM

# Default values
DOMAIN="${DOMAIN:-localhost}"
ADMIN_EMAIL="${ADMIN_EMAIL:-}"
FORCE=false
SKIP_CERTS=false
USE_TAILSCALE=false

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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    head -n 25 "$0" | tail -n +3 | sed 's/^# //; s/^#//'
}

validate_domain_format() {
    local domain=$1
    # Validate domain format (RFC 1123)
    # - Must start and end with alphanumeric
    # - Can contain hyphens but not at start/end
    # - Each label max 63 chars
    # - Valid chars: a-z, A-Z, 0-9, hyphen, dot
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    return 0
}

validate_email() {
    local email=$1
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

# ============================================================================
# Parse Arguments
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --email)
            ADMIN_EMAIL="$2"
            shift 2
            ;;
        --use-tailscale)
            USE_TAILSCALE=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --skip-certs)
            SKIP_CERTS=true
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
# Input Validation
# ============================================================================

# Validate domain format
if ! validate_domain_format "$DOMAIN"; then
    log_error "Invalid domain format: $DOMAIN"
    echo ""
    echo "Domain must:"
    echo "  • Start and end with alphanumeric characters"
    echo "  • Contain only letters, numbers, hyphens, and dots"
    echo "  • Not have consecutive dots or hyphens at start/end"
    echo ""
    echo "Examples of valid domains:"
    echo "  • localhost"
    echo "  • example.com"
    echo "  • sub.example.com"
    echo "  • my-server.local"
    echo ""
    exit 1
fi

# Validate admin email format (if provided)
if [[ -n "$ADMIN_EMAIL" ]]; then
    if ! validate_email "$ADMIN_EMAIL"; then
        log_error "Invalid email format: $ADMIN_EMAIL"
        echo "Provide a valid email address (e.g., admin@example.com)"
        exit 1
    fi
fi

# ============================================================================
# Main Setup Process
# ============================================================================

log_info "Starting OpenWebUI setup..."
echo ""

# Change to project root
cd "$PROJECT_ROOT"

# ============================================================================
# Step 1: Create .env file
# ============================================================================

log_info "Step 1: Creating .env configuration file..."

if [[ -f .env ]] && [[ "$FORCE" != true ]]; then
    log_warning ".env file already exists. Use --force to overwrite."
    log_info "Skipping .env creation."
else
    if [[ -f .env ]]; then
        log_warning "Backing up existing .env to .env.backup"
        cp .env .env.backup
    fi

    cp .env.example .env
    log_success ".env file created from template"

    # Generate random secret key (minimum 32 characters)
    SECRET_KEY=$(openssl rand -base64 32 | tr -d '\n')

    # Validate secret key strength
    if [[ ${#SECRET_KEY} -lt 32 ]]; then
        log_error "Generated secret key is too short (${#SECRET_KEY} characters, minimum 32)"
        exit 1
    fi

    log_success "Generated strong secret key (${#SECRET_KEY} characters)"

    # Update .env with generated values
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s|WEBUI_SECRET_KEY=.*|WEBUI_SECRET_KEY=${SECRET_KEY}|" .env
        sed -i '' "s|DOMAIN=.*|DOMAIN=${DOMAIN}|" .env
        sed -i '' "s|WEBUI_URL=.*|WEBUI_URL=https://${DOMAIN}:8443|" .env
        sed -i '' "s|CORS_ALLOW_ORIGIN=.*|CORS_ALLOW_ORIGIN=https://${DOMAIN}:8443|" .env
        [[ -n "$ADMIN_EMAIL" ]] && sed -i '' "s|ADMIN_EMAIL=.*|ADMIN_EMAIL=${ADMIN_EMAIL}|" .env
    else
        # Linux
        sed -i "s|WEBUI_SECRET_KEY=.*|WEBUI_SECRET_KEY=${SECRET_KEY}|" .env
        sed -i "s|DOMAIN=.*|DOMAIN=${DOMAIN}|" .env
        sed -i "s|WEBUI_URL=.*|WEBUI_URL=https://${DOMAIN}:8443|" .env
        sed -i "s|CORS_ALLOW_ORIGIN=.*|CORS_ALLOW_ORIGIN=https://${DOMAIN}:8443|" .env
        [[ -n "$ADMIN_EMAIL" ]] && sed -i "s|ADMIN_EMAIL=.*|ADMIN_EMAIL=${ADMIN_EMAIL}|" .env
    fi

    log_success "Generated WEBUI_SECRET_KEY and updated configuration"
fi

echo ""

# ============================================================================
# Step 2: Create directory structure
# ============================================================================

log_info "Step 2: Creating directory structure..."

DIRECTORIES=(
    "config"
    "scripts"
    "certs"
    "volumes/data"
    "volumes/cache"
    "volumes/chroma"
    "volumes/models"
    "volumes/vllm-cache"
    "volumes/caddy-data"
    "volumes/caddy-config"
    "logs/openwebui"
    "logs/caddy"
    "logs/vllm"
    "backups"
)

for dir in "${DIRECTORIES[@]}"; do
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        log_success "Created directory: $dir"
    else
        log_info "Directory already exists: $dir"
    fi
done

echo ""

# ============================================================================
# Step 3: Generate TLS certificates
# ============================================================================

if [[ "$SKIP_CERTS" == true ]]; then
    log_info "Step 3: Skipping certificate generation (--skip-certs)"
else
    if [[ "$USE_TAILSCALE" == true ]]; then
        log_info "Step 3: Generating Tailscale TLS certificates..."
    else
        log_info "Step 3: Generating self-signed TLS certificates..."
    fi

    if [[ -f "${SCRIPT_DIR}/generate-certs.sh" ]]; then
        CERT_ARGS="--domain $DOMAIN"
        if [[ "$USE_TAILSCALE" == true ]]; then
            CERT_ARGS="$CERT_ARGS --use-tailscale"
        fi
        bash "${SCRIPT_DIR}/generate-certs.sh" $CERT_ARGS
    else
        log_warning "Certificate generation script not found, skipping..."
    fi
fi

echo ""

# ============================================================================
# Step 4: Set permissions
# ============================================================================

log_info "Step 4: Setting directory permissions..."

# Make scripts executable
chmod +x scripts/*.sh 2>/dev/null || true

# Set proper permissions for volumes
chmod 755 volumes 2>/dev/null || true
chmod 755 volumes/data 2>/dev/null || true
chmod 755 volumes/cache 2>/dev/null || true
chmod 755 volumes/chroma 2>/dev/null || true
chmod 755 volumes/models 2>/dev/null || true
chmod 755 volumes/vllm-cache 2>/dev/null || true

# Set proper permissions for logs
chmod 755 logs 2>/dev/null || true
chmod 755 logs/openwebui 2>/dev/null || true
chmod 755 logs/caddy 2>/dev/null || true
chmod 755 logs/vllm 2>/dev/null || true

# Set proper permissions for Caddy volumes
chmod 755 volumes/caddy-data 2>/dev/null || true
chmod 755 volumes/caddy-config 2>/dev/null || true

log_success "Permissions configured"

echo ""

# ============================================================================
# Step 5: Validate configuration
# ============================================================================

log_info "Step 5: Validating configuration..."

VALIDATION_PASSED=true

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed"
    VALIDATION_PASSED=false
fi

# Check if Docker Compose is installed
if ! command -v docker compose &> /dev/null && ! command -v docker-compose &> /dev/null; then
    log_error "Docker Compose is not installed"
    VALIDATION_PASSED=false
fi

# Check if .env exists
if [[ ! -f .env ]]; then
    log_error ".env file not found"
    VALIDATION_PASSED=false
else
    # Validate WEBUI_SECRET_KEY
    SECRET_KEY_FROM_ENV=$(grep "^WEBUI_SECRET_KEY=" .env | cut -d= -f2)

    if [[ -z "$SECRET_KEY_FROM_ENV" ]]; then
        log_error "WEBUI_SECRET_KEY is not set in .env"
        VALIDATION_PASSED=false
    elif [[ "$SECRET_KEY_FROM_ENV" == "INVALID_PLEASE_RUN_SETUP_SCRIPT_FIRST" ]]; then
        log_error "WEBUI_SECRET_KEY is still set to invalid default value"
        log_error "This should not happen - setup script should have generated a key"
        VALIDATION_PASSED=false
    elif [[ ${#SECRET_KEY_FROM_ENV} -lt 32 ]]; then
        log_error "WEBUI_SECRET_KEY is too short (${#SECRET_KEY_FROM_ENV} characters, minimum 32)"
        log_warning "Generate a new key with: openssl rand -base64 32"
        VALIDATION_PASSED=false
    else
        log_success "WEBUI_SECRET_KEY validation passed (${#SECRET_KEY_FROM_ENV} characters)"
    fi
fi

# Check if certificates exist (unless skipped)
if [[ "$SKIP_CERTS" != true ]]; then
    if [[ ! -f certs/server.crt ]] || [[ ! -f certs/server.key ]]; then
        log_warning "TLS certificates not found in certs/"
        log_warning "Run: ./scripts/generate-certs.sh --domain $DOMAIN"
    fi
fi

if [[ "$VALIDATION_PASSED" == true ]]; then
    log_success "Configuration validation passed"
else
    log_error "Configuration validation failed"
    exit 1
fi

echo ""

# ============================================================================
# Summary
# ============================================================================

log_success "Setup completed successfully!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Next Steps:"
echo ""
echo "1. Review and customize .env file if needed:"
echo "   ${BLUE}nano .env${NC}"
echo ""
echo "2. Start the services:"
echo "   ${GREEN}docker compose up -d${NC}"
echo ""
echo "3. Check service status:"
echo "   ${GREEN}docker compose ps${NC}"
echo ""
echo "4. View logs:"
echo "   ${GREEN}docker compose logs -f${NC}"
echo ""
echo "5. Access OpenWebUI (HTTPS-only):"
echo "   ${GREEN}https://${DOMAIN}:8443${NC}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "⚠️  Important Notes:"
echo ""
echo "  • Self-signed certificates will show browser warnings (expected)"
echo "  • First login creates the admin account"
echo "  • Configure external LLM providers in Settings → Connections"
echo "  • Automatic updates enabled via Watchtower (daily at 4 AM UTC)"
echo "  • View update logs: ${BLUE}docker compose logs -f watchtower${NC}"
echo "  • Check TROUBLESHOOTING.md for common issues"
echo ""
echo "💡 Optional vLLM Integration:"
echo ""
echo "  • Start vLLM service: ${GREEN}docker compose up -d vllm${NC}"
echo "  • Download a model: ${BLUE}./scripts/download-model.sh <model-id>${NC}"
echo "  • Configure in OpenWebUI: Add OpenAI endpoint ${BLUE}http://vllm:8000/v1${NC}"
echo "  • Example model: ${BLUE}./scripts/download-model.sh Qwen/Qwen2.5-7B${NC}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
