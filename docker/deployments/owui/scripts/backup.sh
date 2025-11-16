#!/usr/bin/env bash

# ============================================================================
# Backup Script
# ============================================================================
#
# This script creates compressed backups of OpenWebUI data, configuration,
# and certificates.
#
# USAGE:
#   ./scripts/backup.sh [--output DIR] [--name NAME] [--stop-services]
#
# OPTIONS:
#   --output DIR     Backup output directory (default: ./backups)
#   --name NAME      Backup name prefix (default: owui-backup)
#   --compress       Compression format: gzip, bzip2, xz (default: gzip)
#   --encrypt        Enable GPG encryption (recommended for production)
#   --gpg-recipient  GPG recipient email (default: from BACKUP_GPG_RECIPIENT env)
#   --stop-services  Stop services before backup for data consistency (recommended)
#   --help           Show this help message
#
# BACKUP INCLUDES:
#   - OpenWebUI data (volumes/data)
#   - Cache (volumes/cache)
#   - Vector database (volumes/chroma)
#   - Configuration files (.env, config/)
#   - TLS certificates (certs/)
#   - Docker Compose files
#
# ============================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Temp directory tracking for cleanup
TEMP_DIR_CREATED=""

# ============================================================================
# Cleanup and Error Handling
# ============================================================================

cleanup() {
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo ""
        log_error "Backup failed with exit code: $exit_code"
    fi

    # Clean up temp directory if it exists
    if [[ -n "${TEMP_DIR_CREATED}" ]] && [[ -d "${TEMP_DIR_CREATED}" ]]; then
        log_info "Cleaning up temporary files..."
        rm -rf "${TEMP_DIR_CREATED}"
    fi

    # Restart services if they were stopped and backup failed
    if [[ $exit_code -ne 0 ]] && [[ "${SERVICES_WERE_STOPPED:-false}" == true ]]; then
        log_warning "Attempting to restart services after backup failure..."
        cd "$PROJECT_ROOT" 2>/dev/null || true
        docker compose start 2>/dev/null || log_error "Failed to restart services"
    fi

    exit $exit_code
}

# Set up trap for cleanup on exit, error, interrupt, or termination
trap cleanup EXIT ERR INT TERM

# Default values
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_ROOT}/backups}"
BACKUP_NAME="${BACKUP_NAME:-owui-backup}"
COMPRESS="${COMPRESS:-gzip}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ENCRYPT=false
GPG_RECIPIENT="${BACKUP_GPG_RECIPIENT:-}"
STOP_SERVICES=false

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

human_readable_size() {
    local size=$1
    if command -v numfmt &> /dev/null; then
        numfmt --to=iec-i --suffix=B "$size"
    else
        echo "${size} bytes"
    fi
}

validate_email() {
    local email=$1
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

validate_compress_format() {
    local format=$1
    case "$format" in
        gzip|bzip2|xz)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ============================================================================
# Parse Arguments
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --name)
            BACKUP_NAME="$2"
            shift 2
            ;;
        --compress)
            COMPRESS="$2"
            shift 2
            ;;
        --encrypt)
            ENCRYPT=true
            shift
            ;;
        --gpg-recipient)
            GPG_RECIPIENT="$2"
            shift 2
            ;;
        --stop-services)
            STOP_SERVICES=true
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

# Load .env if it exists for BACKUP_GPG_RECIPIENT
if [[ -f "${PROJECT_ROOT}/.env" ]] && [[ -z "$GPG_RECIPIENT" ]]; then
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/.env" 2>/dev/null || true
    GPG_RECIPIENT="${BACKUP_GPG_RECIPIENT:-}"
fi

# ============================================================================
# Input Validation
# ============================================================================

# Validate output directory
if [[ ! -d "$OUTPUT_DIR" ]]; then
    log_error "Output directory does not exist: $OUTPUT_DIR"
    echo "Create it first: mkdir -p $OUTPUT_DIR"
    exit 1
fi

if [[ ! -w "$OUTPUT_DIR" ]]; then
    log_error "Output directory is not writable: $OUTPUT_DIR"
    echo "Check permissions: ls -ld $OUTPUT_DIR"
    exit 1
fi

# Validate compression format
if ! validate_compress_format "$COMPRESS"; then
    log_error "Invalid compression format: $COMPRESS"
    echo "Valid options: gzip, bzip2, xz"
    exit 1
fi

# Validate GPG recipient email if encryption is enabled
if [[ "$ENCRYPT" == true ]] && [[ -n "$GPG_RECIPIENT" ]]; then
    if ! validate_email "$GPG_RECIPIENT"; then
        log_error "Invalid GPG recipient email format: $GPG_RECIPIENT"
        echo "Provide a valid email address"
        exit 1
    fi
fi

# ============================================================================
# Validation
# ============================================================================

# Check if GPG encryption is requested
if [[ "$ENCRYPT" == true ]]; then
    # Verify GPG is installed
    if ! command -v gpg &> /dev/null; then
        log_error "GPG encryption requested but gpg command not found"
        echo "Install GPG: sudo apt install gnupg (Debian/Ubuntu) or brew install gnupg (macOS)"
        exit 1
    fi

    # Verify recipient is specified
    if [[ -z "$GPG_RECIPIENT" ]]; then
        log_error "GPG encryption enabled but no recipient specified"
        echo "Set BACKUP_GPG_RECIPIENT in .env or use --gpg-recipient option"
        exit 1
    fi

    log_success "GPG encryption enabled for recipient: ${GPG_RECIPIENT}"
else
    log_warning "Backup encryption disabled - backup will contain sensitive data in plain text"
    log_warning "Enable encryption with: --encrypt --gpg-recipient your-email@example.com"
fi

echo ""

# Check compression format
case "$COMPRESS" in
    gzip)
        TAR_COMPRESS_FLAG="z"
        EXTENSION="tar.gz"
        ;;
    bzip2)
        TAR_COMPRESS_FLAG="j"
        EXTENSION="tar.bz2"
        ;;
    xz)
        TAR_COMPRESS_FLAG="J"
        EXTENSION="tar.xz"
        ;;
    *)
        log_error "Invalid compression format: $COMPRESS"
        echo "Valid options: gzip, bzip2, xz"
        exit 1
        ;;
esac

# Note: Output directory validation moved to Input Validation section above

# ============================================================================
# Backup Process
# ============================================================================

BACKUP_FILE="${OUTPUT_DIR}/${BACKUP_NAME}-${TIMESTAMP}.${EXTENSION}"
TEMP_DIR=$(mktemp -d)
TEMP_DIR_CREATED="$TEMP_DIR"  # Track for cleanup

log_info "Starting backup process..."
log_info "Backup file: ${BACKUP_FILE}"
echo ""

cd "$PROJECT_ROOT"

# ============================================================================
# Step 1: Stop services (optional, for consistency)
# ============================================================================

SERVICES_WERE_STOPPED=false

if [[ "$STOP_SERVICES" == true ]]; then
    log_info "Stopping services for data consistency..."

    if docker compose ps | grep -q "Up"; then
        docker compose stop
        SERVICES_WERE_STOPPED=true
        log_success "Services stopped"
    else
        log_info "Services are already stopped"
    fi
    echo ""
else
    log_warning "Services will NOT be stopped during backup"
    log_warning "For data consistency, use --stop-services flag"
    echo ""
fi

# ============================================================================
# Step 2: Create backup structure
# ============================================================================

log_info "Preparing backup..."

BACKUP_TEMP="${TEMP_DIR}/${BACKUP_NAME}-${TIMESTAMP}"
mkdir -p "$BACKUP_TEMP"

# ============================================================================
# Step 3: Backup data volumes
# ============================================================================

log_info "Backing up data volumes..."

if [[ -d "volumes/data" ]]; then
    cp -r volumes/data "$BACKUP_TEMP/"
    log_success "Backed up: volumes/data"
else
    log_warning "volumes/data not found, skipping"
fi

if [[ -d "volumes/cache" ]]; then
    cp -r volumes/cache "$BACKUP_TEMP/"
    log_success "Backed up: volumes/cache"
else
    log_warning "volumes/cache not found, skipping"
fi

if [[ -d "volumes/chroma" ]]; then
    cp -r volumes/chroma "$BACKUP_TEMP/"
    log_success "Backed up: volumes/chroma"
else
    log_warning "volumes/chroma not found, skipping"
fi

echo ""

# ============================================================================
# Step 4: Backup configuration
# ============================================================================

log_info "Backing up configuration files..."

if [[ -f ".env" ]]; then
    cp .env "$BACKUP_TEMP/"
    log_success "Backed up: .env"
else
    log_warning ".env not found, skipping"
fi

if [[ -d "config" ]]; then
    cp -r config "$BACKUP_TEMP/"
    log_success "Backed up: config/"
else
    log_warning "config/ not found, skipping"
fi

echo ""

# ============================================================================
# Step 5: Backup certificates
# ============================================================================

log_info "Backing up TLS certificates..."

if [[ -d "certs" ]]; then
    mkdir -p "$BACKUP_TEMP/certs"
    if [[ -f "certs/server.crt" ]]; then
        cp certs/server.crt "$BACKUP_TEMP/certs/"
    fi
    if [[ -f "certs/server.key" ]]; then
        cp certs/server.key "$BACKUP_TEMP/certs/"
    fi
    if [[ -f "certs/ca.crt" ]]; then
        cp certs/ca.crt "$BACKUP_TEMP/certs/"
    fi
    log_success "Backed up: certs/"
else
    log_warning "certs/ not found, skipping"
fi

echo ""

# ============================================================================
# Step 6: Backup Docker Compose files
# ============================================================================

log_info "Backing up Docker Compose files..."

if [[ -f "docker-compose.yml" ]]; then
    cp "docker-compose.yml" "$BACKUP_TEMP/"
    log_success "Backed up: docker-compose.yml"
fi

echo ""

# ============================================================================
# Step 7: Create backup manifest
# ============================================================================

log_info "Creating backup manifest..."

cat > "$BACKUP_TEMP/BACKUP_INFO.txt" <<EOF
OpenWebUI Backup
================

Backup Date: $(date)
Timestamp: ${TIMESTAMP}
Hostname: $(hostname)
User: $(whoami)

Backup Contents:
----------------
EOF

find "$BACKUP_TEMP" -type f -o -type d | sed "s|${BACKUP_TEMP}/||" | sort >> "$BACKUP_TEMP/BACKUP_INFO.txt"

log_success "Created backup manifest"
echo ""

# ============================================================================
# Step 8: Compress backup
# ============================================================================

log_info "Compressing backup (${COMPRESS})..."

cd "$TEMP_DIR"
tar -c${TAR_COMPRESS_FLAG}f "$BACKUP_FILE" "$(basename "$BACKUP_TEMP")"

log_success "Backup compressed"
echo ""

# ============================================================================
# Step 8a: Encrypt backup (if enabled)
# ============================================================================

if [[ "$ENCRYPT" == true ]]; then
    log_info "Encrypting backup with GPG..."

    # Encrypt the backup file
    if gpg --encrypt --recipient "$GPG_RECIPIENT" --trust-model always --output "${BACKUP_FILE}.gpg" "$BACKUP_FILE" 2>/dev/null; then
        # Remove unencrypted file
        rm "$BACKUP_FILE"
        BACKUP_FILE="${BACKUP_FILE}.gpg"
        log_success "Backup encrypted successfully"
    else
        log_error "GPG encryption failed"
        log_warning "Keeping unencrypted backup at: $BACKUP_FILE"
        log_warning "Check that GPG key exists for: $GPG_RECIPIENT"
        echo ""
        echo "To generate a GPG key:"
        echo "  gpg --full-generate-key"
        echo ""
        echo "To list available keys:"
        echo "  gpg --list-keys"
        echo ""
        # Don't exit - user may want the unencrypted backup
    fi
    echo ""
fi

# ============================================================================
# Step 9: Cleanup
# ============================================================================

log_info "Cleaning up temporary files..."
rm -rf "$TEMP_DIR"
log_success "Cleanup complete"
echo ""

# ============================================================================
# Step 10: Restart services (if stopped)
# ============================================================================

if [[ "$SERVICES_WERE_STOPPED" == true ]]; then
    log_info "Restarting services..."
    docker compose start
    log_success "Services restarted"
    echo ""
fi

# ============================================================================
# Step 11: Generate checksum for integrity verification
# ============================================================================

log_info "Generating SHA256 checksum..."

CHECKSUM_FILE="${BACKUP_FILE}.sha256"
cd "$(dirname "$BACKUP_FILE")"
BACKUP_FILENAME="$(basename "$BACKUP_FILE")"

# Generate checksum
if command -v sha256sum &> /dev/null; then
    sha256sum "$BACKUP_FILENAME" > "$CHECKSUM_FILE"
elif command -v shasum &> /dev/null; then
    shasum -a 256 "$BACKUP_FILENAME" > "$CHECKSUM_FILE"
else
    log_warning "Neither sha256sum nor shasum found, skipping checksum generation"
    CHECKSUM_FILE=""
fi

if [[ -n "$CHECKSUM_FILE" ]]; then
    CHECKSUM=$(cut -d' ' -f1 "$CHECKSUM_FILE")
    log_success "Checksum generated: $CHECKSUM"
else
    CHECKSUM=""
fi

cd "$PROJECT_ROOT"
echo ""

# ============================================================================
# Summary
# ============================================================================

BACKUP_SIZE=$(stat -f%z "$BACKUP_FILE" 2>/dev/null || stat -c%s "$BACKUP_FILE" 2>/dev/null)
BACKUP_SIZE_HUMAN=$(human_readable_size "$BACKUP_SIZE")

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_success "Backup completed successfully!"
echo ""
echo "📦 Backup Details:"
echo "   File:      ${GREEN}${BACKUP_FILE}${NC}"
echo "   Size:      ${GREEN}${BACKUP_SIZE_HUMAN}${NC}"
echo "   Format:    ${GREEN}${EXTENSION}${NC}"
if [[ "$ENCRYPT" == true ]]; then
    echo "   Encrypted: ${GREEN}Yes (GPG)${NC}"
    echo "   Recipient: ${GREEN}${GPG_RECIPIENT}${NC}"
else
    echo "   Encrypted: ${YELLOW}No${NC}"
fi
if [[ -n "$CHECKSUM" ]]; then
    echo "   Checksum:  ${GREEN}${CHECKSUM}${NC}"
    echo "   Verify:    ${BLUE}./scripts/verify-backup.sh ${BACKUP_FILE}${NC}"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Restore Instructions:"
echo ""
if [[ "$ENCRYPT" == true ]]; then
    echo "1. Decrypt backup:"
    echo "   ${BLUE}gpg --decrypt --output ${BACKUP_FILE%.gpg} ${BACKUP_FILE}${NC}"
    echo ""
    echo "2. Stop services:"
    echo "   ${BLUE}docker compose down${NC}"
    echo ""
    echo "3. Extract backup:"
    echo "   ${BLUE}tar -x${TAR_COMPRESS_FLAG}f ${BACKUP_FILE%.gpg} -C /tmp${NC}"
    echo ""
    echo "4. Restore files:"
    echo "   ${BLUE}cp -r /tmp/${BACKUP_NAME}-${TIMESTAMP}/* ${PROJECT_ROOT}/${NC}"
    echo ""
    echo "5. Start services:"
    echo "   ${BLUE}docker compose up -d${NC}"
else
    echo "1. Stop services:"
    echo "   ${BLUE}docker compose down${NC}"
    echo ""
    echo "2. Extract backup:"
    echo "   ${BLUE}tar -x${TAR_COMPRESS_FLAG}f ${BACKUP_FILE} -C /tmp${NC}"
    echo ""
    echo "3. Restore files:"
    echo "   ${BLUE}cp -r /tmp/${BACKUP_NAME}-${TIMESTAMP}/* ${PROJECT_ROOT}/${NC}"
    echo ""
    echo "4. Start services:"
    echo "   ${BLUE}docker compose up -d${NC}"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "💡 Tips:"
echo "   • Store backups in a secure, off-site location"
echo "   • Test restore procedures regularly"
echo "   • Implement automated backup schedules (cron)"
echo "   • Keep multiple backup versions"
if [[ "$ENCRYPT" != true ]]; then
    echo "   • ${YELLOW}⚠️  Enable encryption for production backups (--encrypt)${NC}"
    echo "   • ${YELLOW}⚠️  Backups contain sensitive data: API keys, secrets, certificates${NC}"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
