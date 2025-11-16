#!/usr/bin/env bash
# ============================================================================
# ComfyUI Restore Script
# ============================================================================
# Restores ComfyUI data from backup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
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

print_info "Restoring from: ${BACKUP_FILE}"

# Verify checksum if available
if [[ -f "${BACKUP_FILE}.sha256" ]]; then
    print_info "Verifying checksum..."
    if sha256sum -c "${BACKUP_FILE}.sha256" 2>/dev/null; then
        print_success "Checksum verified"
    else
        print_error "Checksum verification failed!"
        exit 1
    fi
fi

# Decrypt if encrypted
if [[ "${BACKUP_FILE}" == *.gpg ]]; then
    print_info "Decrypting backup..."
    DECRYPTED_FILE="${BACKUP_FILE%.gpg}"
    gpg --decrypt --output "${DECRYPTED_FILE}" "${BACKUP_FILE}"
    BACKUP_FILE="${DECRYPTED_FILE}"
fi

# Stop services
print_info "Stopping services..."
cd "${PROJECT_DIR}" && docker compose down

# Create safety backup
print_info "Creating safety backup of current state..."
SAFETY_BACKUP="${PROJECT_DIR}/backups/pre_restore_$(date +%Y%m%d_%H%M%S).tar.gz"
tar -czf "${SAFETY_BACKUP}" volumes/ config/ certs/ 2>/dev/null || true

# Restore backup
print_info "Extracting backup..."
cd "${PROJECT_DIR}"
tar -xf "${BACKUP_FILE}"

# Restart services
print_info "Starting services..."
docker compose up -d

print_success "Restore completed successfully"
print_info "Safety backup saved to: ${SAFETY_BACKUP}"
