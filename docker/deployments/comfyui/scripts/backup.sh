#!/usr/bin/env bash
# ============================================================================
# ComfyUI Backup Script
# ============================================================================
# Creates encrypted/compressed backups of ComfyUI data

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKUP_DIR="${PROJECT_DIR}/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="comfyui_backup_${TIMESTAMP}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
print_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Parse arguments
ENCRYPT=false
STOP_SERVICES=false
COMPRESSION="gzip"

while [[ $# -gt 0 ]]; do
    case $1 in
        --encrypt) ENCRYPT=true; shift ;;
        --stop-services) STOP_SERVICES=true; shift ;;
        --compression) COMPRESSION="$2"; shift 2 ;;
        *) print_error "Unknown option: $1"; exit 1 ;;
    esac
done

mkdir -p "${BACKUP_DIR}"

print_info "Starting ComfyUI backup..."

# Stop services if requested
if [[ "${STOP_SERVICES}" == "true" ]]; then
    print_info "Stopping services..."
    cd "${PROJECT_DIR}" && docker compose stop
fi

# Create backup
print_info "Creating backup archive..."
cd "${PROJECT_DIR}"

case "${COMPRESSION}" in
    gzip) tar -czf "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" volumes/ config/ certs/ docker-compose.yml .env 2>/dev/null || true ;;
    bzip2) tar -cjf "${BACKUP_DIR}/${BACKUP_NAME}.tar.bz2" volumes/ config/ certs/ docker-compose.yml .env 2>/dev/null || true ;;
    xz) tar -cJf "${BACKUP_DIR}/${BACKUP_NAME}.tar.xz" volumes/ config/ certs/ docker-compose.yml .env 2>/dev/null || true ;;
    *) print_error "Unknown compression: ${COMPRESSION}"; exit 1 ;;
esac

BACKUP_FILE=$(ls -t "${BACKUP_DIR}/${BACKUP_NAME}".* 2>/dev/null | head -n1)

# Generate checksum
print_info "Generating checksum..."
sha256sum "${BACKUP_FILE}" > "${BACKUP_FILE}.sha256"

# Encrypt if requested
if [[ "${ENCRYPT}" == "true" ]]; then
    print_info "Encrypting backup..."
    if command -v gpg &> /dev/null; then
        gpg --symmetric --cipher-algo AES256 "${BACKUP_FILE}"
        rm "${BACKUP_FILE}"
        BACKUP_FILE="${BACKUP_FILE}.gpg"
        print_success "Backup encrypted"
    else
        print_error "GPG not found, skipping encryption"
    fi
fi

# Restart services if stopped
if [[ "${STOP_SERVICES}" == "true" ]]; then
    print_info "Starting services..."
    cd "${PROJECT_DIR}" && docker compose start
fi

print_success "Backup completed: ${BACKUP_FILE}"
print_info "Size: $(du -h "${BACKUP_FILE}" | cut -f1)"
