#!/usr/bin/env bash

# ============================================================================
# Restore Script with Integrity Verification
# ============================================================================
#
# This script restores OpenWebUI from a backup file with automatic
# integrity verification and optional decryption.
#
# USAGE:
#   ./scripts/restore.sh <backup-file>
#
# OPTIONS:
#   --skip-verify     Skip checksum verification (not recommended)
#   --no-stop         Don't stop services before restore
#   --no-start        Don't start services after restore
#   --help            Show this help message
#
# EXAMPLES:
#   ./scripts/restore.sh backups/owui-backup-20250113-120000.tar.gz
#   ./scripts/restore.sh backup.tar.gz.gpg
#   ./scripts/restore.sh backup.tar.gz --skip-verify
#
# ============================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Temp files tracking for cleanup
TEMP_DIR_CREATED=""
DECRYPTED_FILE_CREATED=""
SAFETY_BACKUP_DIR=""

# ============================================================================
# Cleanup and Error Handling
# ============================================================================

cleanup() {
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo ""
        log_error "Restore failed with exit code: $exit_code"

        # Offer to restore from safety backup if it exists
        if [[ -n "$SAFETY_BACKUP_DIR" ]] && [[ -d "$SAFETY_BACKUP_DIR" ]]; then
            echo ""
            log_warning "A safety backup was created at: $SAFETY_BACKUP_DIR"
            log_warning "To manually roll back, copy files from there"
        fi
    fi

    # Clean up temp directory
    if [[ -n "$TEMP_DIR_CREATED" ]] && [[ -d "$TEMP_DIR_CREATED" ]]; then
        rm -rf "$TEMP_DIR_CREATED" 2>/dev/null || true
    fi

    # Clean up decrypted file
    if [[ -n "$DECRYPTED_FILE_CREATED" ]] && [[ -f "$DECRYPTED_FILE_CREATED" ]]; then
        rm -f "$DECRYPTED_FILE_CREATED" 2>/dev/null || true
    fi

    exit $exit_code
}

# Set up trap for cleanup on exit, error, interrupt, or termination
trap cleanup EXIT ERR INT TERM

# Default options
SKIP_VERIFY=false
STOP_SERVICES=true
START_SERVICES=true

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

# ============================================================================
# Parse Arguments
# ============================================================================

BACKUP_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-verify)
            SKIP_VERIFY=true
            shift
            ;;
        --no-stop)
            STOP_SERVICES=false
            shift
            ;;
        --no-start)
            START_SERVICES=false
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            if [[ -z "$BACKUP_FILE" ]]; then
                BACKUP_FILE="$1"
                shift
            else
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
            fi
            ;;
    esac
done

if [[ -z "$BACKUP_FILE" ]]; then
    log_error "No backup file specified"
    echo "Use --help for usage information"
    exit 1
fi

# ============================================================================
# Input Validation
# ============================================================================

# Validate backup file path
if [[ "$BACKUP_FILE" == *".."* ]]; then
    log_error "Backup file path contains '..' (potential path traversal)"
    exit 1
fi

# Validate backup file exists
if [[ ! -f "$BACKUP_FILE" ]]; then
    log_error "Backup file not found: $BACKUP_FILE"
    echo ""
    echo "Check the file path and try again"
    exit 1
fi

# Validate backup file format
BACKUP_EXTENSION="${BACKUP_FILE##*.}"
case "$BACKUP_EXTENSION" in
    gz|gpg)
        # Valid extensions
        ;;
    *)
        log_warning "Unexpected backup file extension: .$BACKUP_EXTENSION"
        log_warning "Expected: .tar.gz or .tar.gz.gpg"
        echo ""
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Restore cancelled by user"
            exit 0
        fi
        ;;
esac

# ============================================================================
# Main Restore Process
# ============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_info "OpenWebUI Restore Process"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd "$PROJECT_ROOT"

# ============================================================================
# Step 1: Validate backup file
# ============================================================================

log_info "Step 1: Validating backup file..."

if [[ ! -f "$BACKUP_FILE" ]]; then
    log_error "Backup file not found: $BACKUP_FILE"
    exit 1
fi

log_success "Backup file found"
echo ""

# ============================================================================
# Step 2: Verify integrity (if not skipped)
# ============================================================================

if [[ "$SKIP_VERIFY" == false ]]; then
    log_info "Step 2: Verifying backup integrity..."

    if [[ -f "${BACKUP_FILE}.sha256" ]]; then
        if "${SCRIPT_DIR}/verify-backup.sh" "$BACKUP_FILE" > /dev/null 2>&1; then
            log_success "Backup integrity verified"
        else
            log_error "Backup integrity verification failed!"
            echo ""
            echo "The backup file may be corrupted. Restoration aborted."
            echo ""
            echo "To restore anyway (not recommended), use: --skip-verify"
            exit 1
        fi
    else
        log_warning "No checksum file found, skipping verification"
    fi
else
    log_warning "Step 2: Skipping integrity verification (--skip-verify)"
fi

echo ""

# ============================================================================
# Step 3: Decrypt if needed
# ============================================================================

WORKING_FILE="$BACKUP_FILE"

if [[ "$BACKUP_FILE" == *.gpg ]]; then
    log_info "Step 3: Decrypting backup..."

    DECRYPTED_FILE="${BACKUP_FILE%.gpg}"

    if gpg --decrypt --output "$DECRYPTED_FILE" "$BACKUP_FILE"; then
        log_success "Backup decrypted successfully"
        WORKING_FILE="$DECRYPTED_FILE"
        DECRYPTED_FILE_CREATED="$DECRYPTED_FILE"  # Track for cleanup
    else
        log_error "Decryption failed"
        exit 1
    fi
else
    log_info "Step 3: Backup is not encrypted, skipping decryption"
fi

echo ""

# ============================================================================
# Step 4: Stop services
# ============================================================================

if [[ "$STOP_SERVICES" == true ]]; then
    log_info "Step 4: Stopping services..."

    if docker compose ps | grep -q "Up"; then
        docker compose down
        log_success "Services stopped"
    else
        log_info "Services are already stopped"
    fi
else
    log_warning "Step 4: Skipping service stop (--no-stop)"
fi

echo ""

# ============================================================================
# Step 5: Extract backup
# ============================================================================

log_info "Step 5: Extracting backup..."

TEMP_DIR=$(mktemp -d)
TEMP_DIR_CREATED="$TEMP_DIR"  # Track for cleanup
tar -xzf "$WORKING_FILE" -C "$TEMP_DIR"

# Find the backup directory (should be only one)
BACKUP_DIR=$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n1)

if [[ -z "$BACKUP_DIR" ]]; then
    log_error "No backup directory found in archive"
    rm -rf "$TEMP_DIR"
    exit 1
fi

log_success "Backup extracted to temporary location"
echo ""

# ============================================================================
# Step 6: Restore files
# ============================================================================

log_info "Step 6: Restoring files..."

# Backup existing data (just in case)
BACKUP_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
if [[ -d "volumes/data" ]]; then
    log_info "Creating safety backup of current data..."
    SAFETY_BACKUP_DIR=".restore-backup-${BACKUP_TIMESTAMP}"
    mkdir -p "$SAFETY_BACKUP_DIR"
    cp -r volumes "$SAFETY_BACKUP_DIR/" 2>/dev/null || true
    log_success "Safety backup created in $SAFETY_BACKUP_DIR"
fi

# Restore files
cp -r "$BACKUP_DIR"/* .

log_success "Files restored"
echo ""

# ============================================================================
# Step 7: Cleanup
# ============================================================================

log_info "Step 7: Cleaning up..."

rm -rf "$TEMP_DIR"

# Remove decrypted file if we created one
if [[ "$WORKING_FILE" != "$BACKUP_FILE" ]] && [[ -f "$WORKING_FILE" ]]; then
    rm -f "$WORKING_FILE"
fi

log_success "Cleanup complete"
echo ""

# ============================================================================
# Step 8: Start services
# ============================================================================

if [[ "$START_SERVICES" == true ]]; then
    log_info "Step 8: Starting services..."

    docker compose up -d
    log_success "Services started"
else
    log_warning "Step 8: Skipping service start (--no-start)"
fi

echo ""

# ============================================================================
# Summary
# ============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_success "Restore completed successfully!"
echo ""
echo "📋 Next Steps:"
echo ""
echo "1. Check service status:"
echo "   ${GREEN}docker compose ps${NC}"
echo ""
echo "2. View logs:"
echo "   ${GREEN}docker compose logs -f${NC}"
echo ""
echo "3. Access OpenWebUI:"
echo "   ${GREEN}https://localhost:8443${NC}"
echo ""
echo "4. Safety backup location (if applicable):"
echo "   ${BLUE}.restore-backup-${BACKUP_TIMESTAMP}/${NC}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
