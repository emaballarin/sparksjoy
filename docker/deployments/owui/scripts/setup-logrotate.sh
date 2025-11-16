#!/usr/bin/env bash

# ============================================================================
# Logrotate Setup Script
# ============================================================================
#
# This script installs and configures logrotate for OpenWebUI application logs.
# Docker container logs are managed by Docker's logging driver configuration.
#
# USAGE:
#   sudo ./scripts/setup-logrotate.sh
#
# NOTE: Requires root privileges to install system-wide logrotate configuration
#
# ============================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

LOGROTATE_CONF="${PROJECT_ROOT}/config/logrotate.conf"
LOGROTATE_DEST="/etc/logrotate.d/openwebui"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# ============================================================================
# Main Setup
# ============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_info "OpenWebUI Logrotate Setup"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

# Check if logrotate is installed
if ! command -v logrotate &> /dev/null; then
    log_error "logrotate is not installed"
    echo ""
    echo "Install logrotate:"
    echo "  • Debian/Ubuntu: sudo apt install logrotate"
    echo "  • RHEL/CentOS:   sudo yum install logrotate"
    echo "  • macOS:         brew install logrotate"
    echo ""
    exit 1
fi

log_success "logrotate is installed: $(logrotate --version | head -n1)"
echo ""

# Check if config file exists
if [[ ! -f "$LOGROTATE_CONF" ]]; then
    log_error "Logrotate configuration not found: $LOGROTATE_CONF"
    exit 1
fi

# Update paths in configuration file to use absolute paths
log_info "Creating configuration with absolute paths..."

# Create temporary config with absolute paths
TEMP_CONF=$(mktemp)
sed "s|/home/emaballarin/repositories/sparksjoy/docker/owui|${PROJECT_ROOT}|g" "$LOGROTATE_CONF" > "$TEMP_CONF"

# Backup existing config if present
if [[ -f "$LOGROTATE_DEST" ]]; then
    log_warning "Existing configuration found, backing up..."
    cp "$LOGROTATE_DEST" "${LOGROTATE_DEST}.backup"
    log_success "Backup created: ${LOGROTATE_DEST}.backup"
fi

# Install configuration
log_info "Installing logrotate configuration..."
cp "$TEMP_CONF" "$LOGROTATE_DEST"
chmod 644 "$LOGROTATE_DEST"
rm "$TEMP_CONF"

log_success "Configuration installed: $LOGROTATE_DEST"
echo ""

# Validate configuration
log_info "Validating configuration..."
if logrotate -d "$LOGROTATE_DEST" 2>&1 | grep -i error; then
    log_error "Configuration validation failed"
    echo ""
    echo "Check configuration with:"
    echo "  sudo logrotate -d $LOGROTATE_DEST"
    exit 1
fi

log_success "Configuration is valid"
echo ""

# Create log directories if they don't exist
log_info "Ensuring log directories exist..."
mkdir -p "${PROJECT_ROOT}/logs/openwebui"
mkdir -p "${PROJECT_ROOT}/logs/caddy"
log_success "Log directories ready"
echo ""

# Show status
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_success "Logrotate setup completed successfully!"
echo ""
echo "📋 Configuration Details:"
echo "   Config file: ${GREEN}$LOGROTATE_DEST${NC}"
echo "   Rotation:    ${GREEN}Daily${NC}"
echo "   Retention:   ${GREEN}7 days${NC}"
echo "   Compression: ${GREEN}Enabled${NC}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "💡 Useful Commands:"
echo ""
echo "Test configuration (dry run):"
echo "   ${BLUE}sudo logrotate -d $LOGROTATE_DEST${NC}"
echo ""
echo "Force rotation (for testing):"
echo "   ${BLUE}sudo logrotate -f $LOGROTATE_DEST${NC}"
echo ""
echo "View rotation status:"
echo "   ${BLUE}cat /var/lib/logrotate/status${NC}"
echo ""
echo "Check log directory:"
echo "   ${BLUE}ls -lh ${PROJECT_ROOT}/logs/openwebui/${NC}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "⚠️  Note: Logrotate runs automatically via cron (typically daily at 6:25 AM)"
echo "   Check cron schedule: ${BLUE}ls -l /etc/cron.daily/logrotate${NC}"
echo ""
