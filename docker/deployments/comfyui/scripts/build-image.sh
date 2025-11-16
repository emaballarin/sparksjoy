#!/usr/bin/env bash
# ============================================================================
# ComfyUI Docker Image Build Script
# ============================================================================
# This script builds the ComfyUI Docker image for aarch64/arm64 (DGX Spark)
# Run this script on the DGX Spark to build the image locally
#
# Usage:
#   ./scripts/build-image.sh [OPTIONS]
#
# Options:
#   -t, --tag TAG         Image tag (default: comfyui:latest-arm64)
#   -n, --no-cache        Build without using cache
#   --build-arg ARG=VAL   Pass build argument to Docker
#   -h, --help            Show this help message

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Default values
IMAGE_TAG="${COMFYUI_IMAGE:-comfyui:latest-arm64}"
NO_CACHE=""
BUILD_ARGS=()
VERBOSE=false

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
ComfyUI Docker Image Build Script

Usage:
  ./scripts/build-image.sh [OPTIONS]

Options:
  -t, --tag TAG         Image tag (default: comfyui:latest-arm64)
  -n, --no-cache        Build without using cache
  --build-arg ARG=VAL   Pass build argument to Docker
  -v, --verbose         Enable verbose output
  -h, --help            Show this help message

Examples:
  # Build with default settings
  ./scripts/build-image.sh

  # Build with custom tag
  ./scripts/build-image.sh -t comfyui:v1.0.0

  # Build without cache
  ./scripts/build-image.sh --no-cache

  # Build with custom build args
  ./scripts/build-image.sh --build-arg PYTORCH_VERSION=2.5.0

Environment Variables:
  COMFYUI_IMAGE         Default image tag (overridden by --tag)
  DOCKER_BUILDKIT       Enable BuildKit (default: 1)

EOF
}

check_prerequisites() {
    print_info "Checking prerequisites..."

    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi

    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running. Please start Docker."
        exit 1
    fi

    # Check if NVIDIA Docker runtime is available
    if ! docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu22.04 nvidia-smi &> /dev/null; then
        print_warning "NVIDIA Docker runtime test failed. GPU support may not work."
        print_warning "Continuing anyway, but image may not work correctly."
    fi

    # Check if Dockerfile exists
    if [[ ! -f "${PROJECT_DIR}/Dockerfile" ]]; then
        print_error "Dockerfile not found at ${PROJECT_DIR}/Dockerfile"
        exit 1
    fi

    print_success "Prerequisites check passed"
}

get_architecture() {
    local arch
    arch="$(uname -m)"
    case "${arch}" in
        aarch64|arm64)
            echo "arm64"
            ;;
        x86_64|amd64)
            echo "amd64"
            ;;
        *)
            print_error "Unsupported architecture: ${arch}"
            exit 1
            ;;
    esac
}

build_image() {
    local arch
    arch="$(get_architecture)"

    print_info "Building ComfyUI Docker image..."
    print_info "  Image tag: ${IMAGE_TAG}"
    print_info "  Architecture: ${arch}"
    print_info "  Platform: linux/${arch}"
    print_info "  Build context: ${PROJECT_DIR}"

    # Prepare Docker build command
    local build_cmd=(
        docker build
        --platform "linux/${arch}"
        --tag "${IMAGE_TAG}"
        --file "${PROJECT_DIR}/Dockerfile"
    )

    # Add no-cache flag if requested
    if [[ -n "${NO_CACHE}" ]]; then
        build_cmd+=(--no-cache)
        print_info "  Cache: disabled"
    fi

    # Add build arguments
    for arg in "${BUILD_ARGS[@]}"; do
        build_cmd+=(--build-arg "${arg}")
    done

    # Add build context
    build_cmd+=("${PROJECT_DIR}")

    # Enable BuildKit for better performance
    export DOCKER_BUILDKIT=1

    print_info "Running Docker build command..."
    if [[ "${VERBOSE}" == "true" ]]; then
        print_info "Command: ${build_cmd[*]}"
    fi

    # Execute build
    if "${build_cmd[@]}"; then
        print_success "Docker image built successfully: ${IMAGE_TAG}"
    else
        print_error "Docker build failed"
        exit 1
    fi
}

verify_image() {
    print_info "Verifying image..."

    # Check if image exists
    if ! docker image inspect "${IMAGE_TAG}" &> /dev/null; then
        print_error "Image not found: ${IMAGE_TAG}"
        exit 1
    fi

    # Get image details
    local image_id size created
    image_id="$(docker image inspect "${IMAGE_TAG}" --format '{{.Id}}' | cut -d: -f2 | cut -c1-12)"
    size="$(docker image inspect "${IMAGE_TAG}" --format '{{.Size}}' | awk '{printf "%.2f GB", $1/1024/1024/1024}')"
    created="$(docker image inspect "${IMAGE_TAG}" --format '{{.Created}}' | cut -d. -f1 | sed 's/T/ /')"

    print_success "Image verified successfully"
    print_info "  Image ID: ${image_id}"
    print_info "  Size: ${size}"
    print_info "  Created: ${created}"
}

show_next_steps() {
    cat << EOF

${GREEN}========================================================================${NC}
${GREEN}Build completed successfully!${NC}
${GREEN}========================================================================${NC}

Next steps:

  1. Verify the image:
     ${BLUE}docker images ${IMAGE_TAG}${NC}

  2. Test the image locally (optional):
     ${BLUE}docker run --rm --gpus all -p 8188:8188 ${IMAGE_TAG}${NC}
     Then visit: http://localhost:8188

  3. Update .env file (if needed):
     ${BLUE}COMFYUI_IMAGE=${IMAGE_TAG}${NC}

  4. Deploy with Docker Compose:
     ${BLUE}cd ${PROJECT_DIR}${NC}
     ${BLUE}docker compose up -d${NC}

  5. Check deployment:
     ${BLUE}docker compose ps${NC}
     ${BLUE}docker compose logs -f comfyui${NC}

For more information, see:
  - ${PROJECT_DIR}/BUILD.md
  - ${PROJECT_DIR}/README.md

EOF
}

# ============================================================================
# Main
# ============================================================================

main() {
    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--tag)
                IMAGE_TAG="$2"
                shift 2
                ;;
            -n|--no-cache)
                NO_CACHE="--no-cache"
                shift
                ;;
            --build-arg)
                BUILD_ARGS+=("$2")
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
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

    print_info "ComfyUI Docker Image Build Script"
    print_info "==================================="

    # Run build process
    check_prerequisites
    build_image
    verify_image
    show_next_steps
}

main "$@"
