#!/usr/bin/env bash
# =============================================================================
# Model Download Script for SGLang on DGX Spark
# =============================================================================
# Downloads models from HuggingFace Hub with resume support and validation
#
# Usage:
#   ./scripts/download-model.sh <model-id> [--token <hf-token>] [--revision <branch>]
#
# Examples:
#   ./scripts/download-model.sh Qwen/Qwen2.5-Math-1.5B-Instruct
#   ./scripts/download-model.sh mistralai/Mistral-7B-Instruct-v0.2
#   ./scripts/download-model.sh TheBloke/Llama-2-7B-Chat-AWQ --revision main
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
MODEL_ID=""
HF_TOKEN="${HF_TOKEN:-}"
REVISION="main"
MODELS_DIR="${PROJECT_DIR}/volumes/models"
CACHE_DIR="${PROJECT_DIR}/volumes/cache"

# =============================================================================
# Helper Functions
# =============================================================================

print_usage() {
    echo "Usage: $0 <model-id> [OPTIONS]"
    echo ""
    echo "Arguments:"
    echo "  model-id              HuggingFace model ID (e.g., Qwen/Qwen2.5-Math-1.5B-Instruct)"
    echo ""
    echo "Options:"
    echo "  --token <token>       HuggingFace API token (for private/gated models)"
    echo "  --revision <branch>   Model revision/branch (default: main)"
    echo "  --cache-only          Download to cache only (don't copy to models dir)"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 Qwen/Qwen2.5-Math-1.5B-Instruct"
    echo "  $0 mistralai/Mistral-7B-Instruct-v0.2 --token hf_xxx"
    echo "  $0 Qwen/Qwen2-7B-Instruct --revision main"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# =============================================================================
# Parse Arguments
# =============================================================================

CACHE_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --token)
            HF_TOKEN="$2"
            shift 2
            ;;
        --revision)
            REVISION="$2"
            shift 2
            ;;
        --cache-only)
            CACHE_ONLY=true
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        -*)
            print_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
        *)
            if [[ -z "$MODEL_ID" ]]; then
                MODEL_ID="$1"
            else
                print_error "Multiple model IDs specified"
                print_usage
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$MODEL_ID" ]]; then
    print_error "Model ID is required"
    print_usage
    exit 1
fi

# =============================================================================
# Check Dependencies
# =============================================================================

check_dependencies() {
    print_info "Checking dependencies..."

    # Check for Python
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is required but not installed"
        exit 1
    fi

    # Check for pip
    if ! command -v pip3 &> /dev/null && ! command -v pip &> /dev/null; then
        print_error "pip is required but not installed"
        exit 1
    fi


# We will install this via `uv tool`
# TODO: Fix detection!
#    # Check/install huggingface-hub
#    if ! python3 -c "import huggingface_hub" 2>/dev/null; then
#        print_info "Installing huggingface-hub..."
#        pip3 install --user huggingface_hub[cli] || {
#            print_error "Failed to install huggingface-hub"
#            exit 1
#        }
#    fi

    print_success "Dependencies OK"
}

# =============================================================================
# Download Model
# =============================================================================

download_model() {
    print_info "Downloading model: $MODEL_ID (revision: $REVISION)"
    print_info "Target directory: $MODELS_DIR"

    # Create directories
    mkdir -p "$MODELS_DIR"
    mkdir -p "$CACHE_DIR"

    # Set HuggingFace cache location
    export HF_HOME="$CACHE_DIR"
    export TRANSFORMERS_CACHE="$CACHE_DIR"
    export HF_HUB_CACHE="$CACHE_DIR/hub"
    export HF_HUB_ENABLE_HF_TRANSFER=1
    export HF_HUB_DISABLE_EXPERIMENTAL_WARNING=1
    export HF_HUB_DISABLE_TELEMETRY=1

    # Build download command
    local download_cmd="hf download"
    download_cmd+=" \"$MODEL_ID\""
    download_cmd+=" --revision \"$REVISION\""
    download_cmd+=" --cache-dir \"$CACHE_DIR\""

    if [[ ! "$CACHE_ONLY" == true ]]; then
        export HF_HUB_DISABLE_SYMLINKS_WARNING=0
        download_cmd+=" --local-dir \"$MODELS_DIR/$MODEL_ID\""
    fi

    if [[ -n "$HF_TOKEN" ]]; then
        download_cmd+=" --token \"$HF_TOKEN\""
    fi

    print_info "Running: hf download $MODEL_ID..."

    # Execute download
    eval "$download_cmd" || {
        print_error "Download failed"
        exit 1
    }

    print_success "Download completed!"
}

# =============================================================================
# Verify Download
# =============================================================================

verify_download() {
    print_info "Verifying download..."

    local model_path="$MODELS_DIR/$MODEL_ID"

    if [[ "$CACHE_ONLY" == true ]]; then
        print_info "Cache-only mode: skipping verification"
        return 0
    fi

    if [[ ! -d "$model_path" ]]; then
        print_error "Model directory not found: $model_path"
        return 1
    fi

    # Check for essential files
    local essential_files=("config.json")
    local found_files=0

    for file in "${essential_files[@]}"; do
        if [[ -f "$model_path/$file" ]]; then
            ((found_files++))
        fi
    done

    if [[ $found_files -eq 0 ]]; then
        print_warning "No essential model files found (config.json)"
    else
        print_success "Essential files verified"
    fi

    # List downloaded files
    print_info "Downloaded files:"
    du -sh "$model_path" 2>/dev/null || echo "  Unable to calculate size"

    # Show key files
    if [[ -f "$model_path/config.json" ]]; then
        echo "  ✓ config.json"
    fi
    if ls "$model_path"/*.safetensors &>/dev/null || ls "$model_path"/*.bin &>/dev/null; then
        echo "  ✓ model weights"
    fi
    if [[ -f "$model_path/tokenizer.json" ]] || [[ -f "$model_path/tokenizer_config.json" ]]; then
        echo "  ✓ tokenizer"
    fi
}

# =============================================================================
# Print Usage Instructions
# =============================================================================

print_instructions() {
    echo ""
    print_info "Model ready to use!"
    echo ""
    echo "To use this model with SGLang, update your .env file:"
    echo "  ${BLUE}SGLANG_MODEL=$MODEL_ID${NC}"
    echo ""
    echo "Then start/restart SGLang:"
    echo "  ${BLUE}docker compose up -d sglang${NC}"
    echo ""
    echo "Or use the full path in docker-compose.yml:"
    echo "  ${BLUE}SGLANG_MODEL=/app/models/$MODEL_ID${NC}"
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    echo "════════════════════════════════════════"
    echo "  Model Download for SGLang on DGX Spark  "
    echo "════════════════════════════════════════"
    echo ""

    check_dependencies
    download_model
    verify_download
    print_instructions

    print_success "All done!"
}

# Run main
main
