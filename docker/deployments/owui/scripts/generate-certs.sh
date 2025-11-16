#!/usr/bin/env bash

# ============================================================================
# TLS Certificate Generation Script
# ============================================================================
#
# This script generates TLS certificates for HTTPS access using either:
# - Tailscale certificates (preferred, automatically trusted)
# - Self-signed certificates (for local development)
# For production deployments, consider using Let's Encrypt instead.
#
# USAGE:
#   ./scripts/generate-certs.sh [OPTIONS]
#
# OPTIONS:
#   --domain DOMAIN       Domain name for certificate (default: localhost)
#   --days DAYS           Certificate validity in days (default: 365)
#   --use-tailscale       Use Tailscale certificates (requires tailscale CLI)
#   --force               Overwrite existing certificates
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
CERTS_DIR="${PROJECT_ROOT}/certs"

# Default values
DOMAIN="${DOMAIN:-localhost}"
DAYS="${DAYS:-365}"
FORCE=false
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
    head -n 18 "$0" | tail -n +3 | sed 's/^# //; s/^#//'
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
        --days)
            DAYS="$2"
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
# Validation
# ============================================================================

# Validate Tailscale requirements
if [[ "$USE_TAILSCALE" == true ]]; then
    # Check if tailscale is installed
    if ! command -v tailscale &> /dev/null; then
        log_error "Tailscale is not installed or not in PATH."
        log_error "Install from: https://tailscale.com/download"
        log_warning "Falling back to self-signed certificates..."
        USE_TAILSCALE=false
    else
        log_info "Tailscale binary found: $(command -v tailscale)"
    fi
fi

# Check if openssl is installed (needed for self-signed certs)
if [[ "$USE_TAILSCALE" != true ]]; then
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is not installed. Please install it first."
        exit 1
    fi
fi

# Create certs directory if it doesn't exist
mkdir -p "$CERTS_DIR"

# Check if certificates already exist
if [[ -f "${CERTS_DIR}/server.crt" ]] && [[ "$FORCE" != true ]]; then
    log_warning "Certificates already exist in ${CERTS_DIR}"
    log_warning "Use --force to regenerate"
    exit 0
fi

# ============================================================================
# Generate Certificates
# ============================================================================

if [[ "$USE_TAILSCALE" == true ]]; then
    # ==========================================================================
    # Tailscale Certificate Generation
    # ==========================================================================

    log_info "Generating Tailscale TLS certificate for domain: ${DOMAIN}"
    echo ""

    cd "$CERTS_DIR"

    # Generate Tailscale certificate
    log_info "Requesting certificate from Tailscale..."
    if tailscale cert --cert-file server.crt --key-file server.key "$DOMAIN" 2>&1; then
        log_success "Tailscale certificate generated successfully!"

        # Set proper permissions
        chmod 644 server.crt
        chmod 600 server.key

        echo ""
        log_info "Certificate information:"
        echo ""
        openssl x509 -in server.crt -noout -text | grep -A 2 "Subject:"
        openssl x509 -in server.crt -noout -text | grep -A 10 "Subject Alternative Name:" || true
        openssl x509 -in server.crt -noout -dates

        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "📄 Generated files:"
        echo "   ${GREEN}${CERTS_DIR}/server.crt${NC} - Tailscale certificate"
        echo "   ${GREEN}${CERTS_DIR}/server.key${NC} - Private key"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "✅ Tailscale certificates are automatically trusted within your Tailscale network!"
        echo ""
        echo "Benefits:"
        echo "  • No browser security warnings for Tailscale clients"
        echo "  • No manual CA certificate installation required"
        echo "  • Automatic certificate rotation by Tailscale"
        echo "  • Valid certificates (not self-signed)"
        echo ""
        echo "Note: Devices accessing via Tailscale will trust this certificate automatically."
        echo "      Non-Tailscale clients will still see certificate warnings."
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    else
        log_error "Failed to generate Tailscale certificate"
        log_error "Common causes:"
        log_error "  • Domain not accessible via Tailscale (must be MagicDNS name or .ts.net domain)"
        log_error "  • Tailscale not running or not authenticated"
        log_error "  • Domain not properly configured in Tailscale"
        echo ""
        log_warning "Falling back to self-signed certificate generation..."
        USE_TAILSCALE=false
    fi
fi

if [[ "$USE_TAILSCALE" != true ]]; then
    # ==========================================================================
    # Self-Signed Certificate Generation
    # ==========================================================================

    log_info "Generating self-signed TLS certificate for domain: ${DOMAIN}"
    log_info "Validity: ${DAYS} days"
    echo ""

    cd "$CERTS_DIR"

    # Create OpenSSL configuration file
    cat > openssl.cnf <<EOF
[req]
default_bits = 4096
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C = US
ST = State
L = City
O = Organization
OU = IT Department
CN = ${DOMAIN}

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN}
DNS.2 = *.${DOMAIN}
DNS.3 = localhost
DNS.4 = 127.0.0.1
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

    # Generate private key
    log_info "Generating private key..."
    openssl genrsa -out server.key 4096 2>/dev/null

    # Generate certificate signing request
    log_info "Generating certificate signing request..."
    openssl req -new -key server.key -out server.csr -config openssl.cnf 2>/dev/null

    # Generate self-signed certificate
    log_info "Generating self-signed certificate..."
    openssl x509 -req -days "$DAYS" \
        -in server.csr \
        -signkey server.key \
        -out server.crt \
        -extensions v3_req \
        -extfile openssl.cnf \
        2>/dev/null

    # Generate CA certificate (for browsers to trust)
    log_info "Generating CA certificate..."
    openssl req -new -x509 -days "$DAYS" \
        -key server.key \
        -out ca.crt \
        -config openssl.cnf \
        2>/dev/null

    # Set proper permissions
    chmod 644 server.crt
    chmod 600 server.key
    chmod 644 ca.crt

    # Clean up temporary files
    rm -f openssl.cnf server.csr

    echo ""
    log_success "TLS certificates generated successfully!"
    echo ""

    # ==========================================================================
    # Display Certificate Information
    # ==========================================================================

    log_info "Certificate information:"
    echo ""
    openssl x509 -in server.crt -noout -text | grep -A 2 "Subject:"
    openssl x509 -in server.crt -noout -text | grep -A 10 "Subject Alternative Name:"
    openssl x509 -in server.crt -noout -dates

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📄 Generated files:"
    echo "   ${GREEN}${CERTS_DIR}/server.crt${NC} - Certificate"
    echo "   ${GREEN}${CERTS_DIR}/server.key${NC} - Private key"
    echo "   ${GREEN}${CERTS_DIR}/ca.crt${NC}     - CA certificate"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "⚠️  Browser Trust Warning:"
    echo ""
    echo "Self-signed certificates will show security warnings in browsers."
    echo "This is expected behavior. To remove the warning:"
    echo ""
    echo "1. ${BLUE}Chrome/Edge:${NC}"
    echo "   • Visit ${GREEN}chrome://settings/certificates${NC}"
    echo "   • Go to 'Authorities' tab"
    echo "   • Import ${GREEN}${CERTS_DIR}/ca.crt${NC}"
    echo "   • Check 'Trust this certificate for identifying websites'"
    echo ""
    echo "2. ${BLUE}Firefox:${NC}"
    echo "   • Visit ${GREEN}about:preferences#privacy${NC}"
    echo "   • Scroll to 'Certificates' → 'View Certificates'"
    echo "   • Go to 'Authorities' tab → 'Import'"
    echo "   • Import ${GREEN}${CERTS_DIR}/ca.crt${NC}"
    echo "   • Check 'Trust this CA to identify websites'"
    echo ""
    echo "3. ${BLUE}macOS:${NC}"
    echo "   • Open 'Keychain Access' app"
    echo "   • Drag ${GREEN}${CERTS_DIR}/ca.crt${NC} to 'System' keychain"
    echo "   • Double-click certificate → Trust → 'Always Trust'"
    echo ""
    echo "4. ${BLUE}Linux:${NC}"
    echo "   • Copy ${GREEN}${CERTS_DIR}/ca.crt${NC} to ${GREEN}/usr/local/share/ca-certificates/${NC}"
    echo "   • Run: ${GREEN}sudo update-ca-certificates${NC}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "💡 For production deployments, use Let's Encrypt or Tailscale certificates:"
    echo ""
    echo "   ${BLUE}Tailscale (Recommended for Tailscale networks):${NC}"
    echo "   • Run: ${GREEN}./scripts/generate-certs.sh --use-tailscale --domain your-device.ts.net${NC}"
    echo "   • Automatically trusted within your Tailscale network"
    echo "   • No browser warnings for Tailscale clients"
    echo ""
    echo "   ${BLUE}Let's Encrypt (For public domains):${NC}"
    echo "   • Update config/traefik.yml with your email"
    echo "   • Change certResolver from 'file' to 'letsencrypt'"
    echo "   • Ensure ports 80/443 are publicly accessible"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
fi
