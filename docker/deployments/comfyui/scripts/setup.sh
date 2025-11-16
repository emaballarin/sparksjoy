#!/usr/bin/env bash
# ============================================================================
# ComfyUI Deployment Setup Script
# ============================================================================
# This script automates the initial setup of the ComfyUI deployment
#
# Usage:
#   ./scripts/setup.sh [OPTIONS]
#
# Options:
#   --domain DOMAIN       Domain name for certificates and routing
#   --use-tailscale       Use Tailscale certificates
#   --skip-certs          Skip certificate generation
#   -h, --help            Show this help message

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Default values
DOMAIN="${DOMAIN:-localhost}"
USE_TAILSCALE=false
SKIP_CERTS=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Functions
# ============================================================================

print_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

show_help() {
    cat << EOF
ComfyUI Deployment Setup Script

Usage:
  ./scripts/setup.sh [OPTIONS]

Options:
  --domain DOMAIN       Domain name for certificates and routing (default: localhost)
  --use-tailscale       Use Tailscale certificates
  --skip-certs          Skip certificate generation (use existing certificates)
  -h, --help            Show this help message

Examples:
  # Setup with default settings (localhost)
  ./scripts/setup.sh

  # Setup with Tailscale
  ./scripts/setup.sh --domain your-device.ts.net --use-tailscale

  # Setup with custom domain
  ./scripts/setup.sh --domain comfyui.yourdomain.com

EOF
}

check_prerequisites() {
    print_info "Checking prerequisites..."

    # Check if running in project directory
    if [[ ! -f "${PROJECT_DIR}/docker-compose.yml" ]]; then
        print_error "docker-compose.yml not found. Please run this script from the project directory."
        exit 1
    fi

    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi

    # Check if Docker Compose is available
    if ! docker compose version &> /dev/null; then
        print_error "Docker Compose is not available. Please install Docker Compose."
        exit 1
    fi

    print_success "Prerequisites check passed"
}

create_env_file() {
    print_info "Setting up environment file..."

    if [[ -f "${PROJECT_DIR}/.env" ]]; then
        print_warning ".env file already exists. Backing up to .env.backup"
        cp "${PROJECT_DIR}/.env" "${PROJECT_DIR}/.env.backup.$(date +%Y%m%d_%H%M%S)"
    fi

    # Copy .env.example to .env
    cp "${PROJECT_DIR}/.env.example" "${PROJECT_DIR}/.env"

    # Update DOMAIN in .env
    sed -i "s/^DOMAIN=.*/DOMAIN=${DOMAIN}/" "${PROJECT_DIR}/.env"

    # Update USE_TAILSCALE_CERTS in .env
    if [[ "${USE_TAILSCALE}" == "true" ]]; then
        sed -i "s/^USE_TAILSCALE_CERTS=.*/USE_TAILSCALE_CERTS=true/" "${PROJECT_DIR}/.env"
    fi

    print_success "Environment file created: ${PROJECT_DIR}/.env"
    print_info "  Domain: ${DOMAIN}"
    print_info "  Tailscale certs: ${USE_TAILSCALE}"
}

create_directories() {
    print_info "Creating directory structure..."

    # Create directories if they don't exist
    mkdir -p "${PROJECT_DIR}/volumes/models/checkpoints"
    mkdir -p "${PROJECT_DIR}/volumes/models/vae"
    mkdir -p "${PROJECT_DIR}/volumes/models/loras"
    mkdir -p "${PROJECT_DIR}/volumes/models/upscale_models"
    mkdir -p "${PROJECT_DIR}/volumes/models/embeddings"
    mkdir -p "${PROJECT_DIR}/volumes/models/controlnet"
    mkdir -p "${PROJECT_DIR}/volumes/models/ipadapter"
    mkdir -p "${PROJECT_DIR}/volumes/models/clip"
    mkdir -p "${PROJECT_DIR}/volumes/models/clip_vision"
    mkdir -p "${PROJECT_DIR}/volumes/custom_nodes"
    mkdir -p "${PROJECT_DIR}/volumes/output"
    mkdir -p "${PROJECT_DIR}/volumes/input"
    mkdir -p "${PROJECT_DIR}/volumes/temp"
    mkdir -p "${PROJECT_DIR}/volumes/caddy-data"
    mkdir -p "${PROJECT_DIR}/volumes/caddy-config"
    mkdir -p "${PROJECT_DIR}/logs/comfyui"
    mkdir -p "${PROJECT_DIR}/logs/caddy"
    mkdir -p "${PROJECT_DIR}/certs"
    mkdir -p "${PROJECT_DIR}/backups"

    # Set permissions
    chmod 755 "${PROJECT_DIR}/volumes"
    chmod 755 "${PROJECT_DIR}/logs"
    chmod 700 "${PROJECT_DIR}/certs"
    chmod 700 "${PROJECT_DIR}/backups"

    print_success "Directory structure created"
}

setup_acme_json() {
    print_info "Setting up acme.json for Let's Encrypt..."

    local acme_file="${PROJECT_DIR}/config/acme.json"

    if [[ ! -f "${acme_file}" ]]; then
        echo "{}" > "${acme_file}"
    fi

    chmod 600 "${acme_file}"

    print_success "acme.json configured with secure permissions"
}

generate_certificates() {
    if [[ "${SKIP_CERTS}" == "true" ]]; then
        print_info "Skipping certificate generation (--skip-certs)"
        return
    fi

    print_info "Generating TLS certificates..."

    local cert_script="${SCRIPT_DIR}/generate-certs.sh"

    if [[ ! -f "${cert_script}" ]]; then
        print_error "Certificate generation script not found: ${cert_script}"
        exit 1
    fi

    # Make sure the script is executable
    chmod +x "${cert_script}"

    # Generate certificates
    if [[ "${USE_TAILSCALE}" == "true" ]]; then
        "${cert_script}" --use-tailscale --domain "${DOMAIN}"
    else
        "${cert_script}" --domain "${DOMAIN}"
    fi

    print_success "TLS certificates generated"
}

validate_configuration() {
    print_info "Validating configuration..."

    local validate_script="${SCRIPT_DIR}/validate-config.sh"

    if [[ -f "${validate_script}" ]]; then
        chmod +x "${validate_script}"
        if "${validate_script}"; then
            print_success "Configuration validation passed"
        else
            print_error "Configuration validation failed"
            exit 1
        fi
    else
        print_warning "Validation script not found, skipping validation"
    fi
}

show_next_steps() {
    cat << EOF

${GREEN}========================================================================${NC}
${GREEN}Setup completed successfully!${NC}
${GREEN}========================================================================${NC}

Next steps:

  1. Review and customize .env file:
     ${BLUE}nano ${PROJECT_DIR}/.env${NC}

  2. Build the ComfyUI Docker image on DGX Spark:
     ${BLUE}cd ${PROJECT_DIR}${NC}
     ${BLUE}./scripts/build-image.sh${NC}

  3. Download models (optional, can be done after deployment):
     - Download Stable Diffusion checkpoints to: ${PROJECT_DIR}/volumes/models/checkpoints/
     - Or use ComfyUI Manager after deployment to download models

  4. Start the deployment:
     ${BLUE}docker compose up -d${NC}

  5. Check deployment status:
     ${BLUE}docker compose ps${NC}
     ${BLUE}docker compose logs -f${NC}

  6. Access ComfyUI:
     ${BLUE}https://${DOMAIN}:8444${NC}

  7. Monitor health:
     ${BLUE}./scripts/health-check.sh${NC}

For more information:
  - README.md: Comprehensive deployment guide
  - QUICKSTART.md: Quick start guide
  - BUILD.md: Docker image build instructions
  - TROUBLESHOOTING.md: Common issues and solutions

${YELLOW}Important notes:${NC}
  - The Docker image must be built on DGX Spark before deployment
  - Models are not included in the image and must be downloaded separately
  - ComfyUI Manager is pre-installed for easy custom node management
  - Backups can be automated with: ./scripts/backup.sh

EOF
}

# ============================================================================
# Main
# ============================================================================

main() {
    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --use-tailscale)
                USE_TAILSCALE=true
                shift
                ;;
            --skip-certs)
                SKIP_CERTS=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    print_info "ComfyUI Deployment Setup"
    print_info "========================="

    # Run setup steps
    check_prerequisites
    create_directories
    create_env_file
    setup_acme_json
    generate_certificates
    validate_configuration
    show_next_steps
}

main "$@"
