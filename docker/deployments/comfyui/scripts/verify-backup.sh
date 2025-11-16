#!/usr/bin/env bash
# ============================================================================
# ComfyUI Backup Verification Script
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
print_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

if [[ $# -lt 1 ]]; then
    print_error "Usage: $0 <backup_file>"
    exit 1
fi

BACKUP_FILE="$1"

if [[ ! -f "${BACKUP_FILE}" ]]; then
    print_error "Backup file not found: ${BACKUP_FILE}"
    exit 1
fi

print_info "Verifying backup: ${BACKUP_FILE}"

# Check checksum
if [[ -f "${BACKUP_FILE}.sha256" ]]; then
    print_info "Verifying checksum..."
    if sha256sum -c "${BACKUP_FILE}.sha256" 2>/dev/null; then
        print_success "Checksum: VALID"
    else
        print_error "Checksum: INVALID"
        exit 1
    fi
else
    print_info "No checksum file found, skipping verification"
fi

# Test archive integrity
print_info "Testing archive integrity..."
if tar -tzf "${BACKUP_FILE}" &>/dev/null || tar -tjf "${BACKUP_FILE}" &>/dev/null || tar -tJf "${BACKUP_FILE}" &>/dev/null; then
    print_success "Archive: VALID"
else
    print_error "Archive: CORRUPTED"
    exit 1
fi

# Show backup info
print_info "Backup information:"
echo "  Size: $(du -h "${BACKUP_FILE}" | cut -f1)"
echo "  Modified: $(stat -c %y "${BACKUP_FILE}" 2>/dev/null || stat -f %Sm "${BACKUP_FILE}" 2>/dev/null)"

print_success "Backup verification completed successfully"
