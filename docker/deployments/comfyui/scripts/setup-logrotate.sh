#!/usr/bin/env bash
# ============================================================================
# ComfyUI Logrotate Setup Script
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
print_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

print_info "Installing logrotate configuration for ComfyUI..."

LOGROTATE_CONF="/etc/logrotate.d/comfyui"

if [[ -f "${LOGROTATE_CONF}" ]]; then
    print_info "Existing logrotate configuration found, backing up..."
    cp "${LOGROTATE_CONF}" "${LOGROTATE_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Copy configuration
cp "${PROJECT_DIR}/config/logrotate.conf" "${LOGROTATE_CONF}"
chmod 644 "${LOGROTATE_CONF}"

print_success "Logrotate configuration installed"
print_info "Configuration file: ${LOGROTATE_CONF}"

# Test configuration
print_info "Testing logrotate configuration..."
if logrotate -d "${LOGROTATE_CONF}" &>/dev/null; then
    print_success "Configuration syntax is valid"
else
    print_error "Configuration syntax error"
    exit 1
fi

print_success "Logrotate setup completed successfully"
print_info "Logs will be rotated daily and kept for 14 days"
