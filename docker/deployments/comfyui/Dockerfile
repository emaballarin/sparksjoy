# ComfyUI Docker Image for aarch64/arm64 (DGX Spark)
# Built on NVIDIA PyTorch 25.10 container with PyTorch 2.9, CUDA 13.0, Python 3.12

# ============================================================================
# Stage 1: Baseline - Capture NVIDIA's original package state
# ============================================================================
FROM nvcr.io/nvidia/pytorch:25.10-py3 AS baseline

# Capture the baseline package state from NVIDIA's image
# This will be used later to determine which packages we added
RUN pip freeze > /baseline.txt

# ============================================================================
# Stage 2: Builder - Install ComfyUI and dependencies
# ============================================================================
FROM nvcr.io/nvidia/pytorch:25.10-py3 AS builder

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Install system dependencies (minimal - PyTorch base has most)
# Only add what's specifically needed for ComfyUI and custom nodes
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Clone ComfyUI from official repository
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /app/ComfyUI

# Install ComfyUI Manager (web-based custom node management)
WORKDIR /app/ComfyUI/custom_nodes
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git

# Clone popular custom nodes
# Using || true to prevent build failures from optional nodes

# ComfyUI-ControlNet-Preprocessors
RUN git clone https://github.com/Fannovel16/comfyui_controlnet_aux.git || true

# ComfyUI-IPAdapter-plus
RUN git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git || true

# ComfyUI-Impact-Pack (image processing utilities)
RUN git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git || true

# ComfyUI-Inspire-Pack (additional utility nodes)
RUN git clone https://github.com/ltdrdata/ComfyUI-Inspire-Pack.git || true

# WAS Node Suite (extensive node collection)
RUN git clone https://github.com/WASasquatch/was-node-suite-comfyui.git || true

# Civitai ComfyUI nodes (model loader from Civitai using AIR identifiers)
RUN git clone https://github.com/civitai/civitai_comfy_nodes.git || true

# Merge all requirements.txt files for build dependencies
# This ensures pip resolves all dependencies together, avoiding version conflicts
WORKDIR /app/ComfyUI
RUN find . -name "requirements.txt" -type f -exec cat {} \; | sort -u > /combined-build-requirements.txt && \
    echo "=== Combined build requirements ===" && \
    cat /combined-build-requirements.txt

# Install all build dependencies at once with NVIDIA constraints
# Single installation pass prevents pip from flip-flopping package versions
RUN pip install --constraint /etc/pip/constraint.txt --no-cache-dir -r /combined-build-requirements.txt

# ============================================================================
# Cleanup: Remove unnecessary files to reduce image size
# ============================================================================
RUN cd /app/ComfyUI && \
    # Remove all .git directories (version control history not needed at runtime)
    find . -type d -name ".git" -exec rm -rf {} + 2>/dev/null || true && \
    # Remove pytest cache
    find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true && \
    # Remove test directories (not needed at runtime)
    find ./custom_nodes -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true && \
    find ./custom_nodes -type d -name "test" -exec rm -rf {} + 2>/dev/null || true && \
    # Remove example directories (can be large)
    find ./custom_nodes -type d -name "examples" -exec rm -rf {} + 2>/dev/null || true && \
    find ./custom_nodes -type d -name "example" -exec rm -rf {} + 2>/dev/null || true && \
    # Remove documentation source files (keep built docs if any)
    find ./custom_nodes -type d -name "docs" -exec rm -rf {} + 2>/dev/null || true && \
    # Remove CI/CD configuration files
    find . -name ".github" -type d -exec rm -rf {} + 2>/dev/null || true && \
    find . -name ".gitlab-ci.yml" -delete 2>/dev/null || true && \
    find . -name ".travis.yml" -delete 2>/dev/null || true && \
    # Remove editor configurations
    find . -name ".vscode" -type d -exec rm -rf {} + 2>/dev/null || true && \
    find . -name ".idea" -type d -exec rm -rf {} + 2>/dev/null || true && \
    # Remove linting configurations
    find . -name ".pylintrc" -delete 2>/dev/null || true && \
    find . -name ".flake8" -delete 2>/dev/null || true && \
    find . -name ".mypy_cache" -type d -exec rm -rf {} + 2>/dev/null || true && \
    # Remove package build artifacts
    find . -name "build" -type d -exec rm -rf {} + 2>/dev/null || true && \
    find . -name "dist" -type d -exec rm -rf {} + 2>/dev/null || true && \
    # Remove README files in custom nodes (keep main ComfyUI README)
    find ./custom_nodes -name "README*" -type f -delete 2>/dev/null || true && \
    find ./custom_nodes -name "LICENSE*" -type f -delete 2>/dev/null || true && \
    # Remove any leftover temporary files
    find . -name "*.tmp" -delete 2>/dev/null || true && \
    find . -name "*.log" -delete 2>/dev/null || true

# ============================================================================
# Build wheels for git-cloned packages (source builds)
# ============================================================================
# Only build wheels for packages we installed from git (not available on PyPI)
# PyPI packages will be resolved and installed in Stage 3
RUN mkdir -p /wheels && \
    # Build wheel for ComfyUI (main application)
    cd /app/ComfyUI && pip wheel --no-deps --wheel-dir=/wheels . && \
    # Build wheels for custom nodes from git
    cd /app/ComfyUI/custom_nodes/ComfyUI-Manager && pip wheel --no-deps --wheel-dir=/wheels . || true && \
    cd /app/ComfyUI/custom_nodes/comfyui_controlnet_aux && pip wheel --no-deps --wheel-dir=/wheels . || true && \
    cd /app/ComfyUI/custom_nodes/ComfyUI_IPAdapter_plus && pip wheel --no-deps --wheel-dir=/wheels . || true && \
    cd /app/ComfyUI/custom_nodes/ComfyUI-Impact-Pack && pip wheel --no-deps --wheel-dir=/wheels . || true && \
    cd /app/ComfyUI/custom_nodes/ComfyUI-Inspire-Pack && pip wheel --no-deps --wheel-dir=/wheels . || true && \
    cd /app/ComfyUI/custom_nodes/was-node-suite-comfyui && pip wheel --no-deps --wheel-dir=/wheels . || true && \
    cd /app/ComfyUI/custom_nodes/civitai_comfy_nodes && pip wheel --no-deps --wheel-dir=/wheels . || true

# ============================================================================
# Stage 3: Test Install - Validate working state with full dependency resolution
# ============================================================================
FROM nvcr.io/nvidia/pytorch:25.10-py3 AS validator

# Copy wheels and ComfyUI application from builder
COPY --from=builder /wheels /wheels
COPY --from=builder /app/ComfyUI /app/ComfyUI

# Install system dependencies needed for some packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Install all packages from Stage 2 and let pip do FULL dependency resolution
# This replicates the complete Stage 2 environment with full dependency resolution
WORKDIR /app/ComfyUI

# Merge all requirements.txt files for complete dependency resolution
# This ensures pip resolves all dependencies together in one pass
RUN find . -name "requirements.txt" -type f -exec cat {} \; | sort -u > /combined-all-requirements.txt && \
    echo "=== Combined all requirements ===" && \
    cat /combined-all-requirements.txt

# Install all requirements at once WITHOUT constraints
# Single installation pass prevents version conflicts and allows full dependency resolution
RUN pip install --no-cache-dir -r /combined-all-requirements.txt

# Install source-built wheels (our git packages) at the end
# This ensures our custom packages are installed after their dependencies
RUN pip install --no-cache-dir --find-links=/wheels /wheels/*.whl

# Capture the final working state after full dependency resolution
# This represents a proven working configuration
RUN pip freeze > /final-working.txt

# ============================================================================
# Stage 4: Final - Runtime image with exact package replication
# ============================================================================
FROM nvcr.io/nvidia/pytorch:25.10-py3 AS final

# Copy package manifests from previous stages
COPY --from=baseline /baseline.txt /baseline.txt
COPY --from=validator /final-working.txt /final-working.txt
COPY --from=validator /wheels /wheels

# Copy ComfyUI application from builder
COPY --from=builder /app/ComfyUI /app/ComfyUI

# Install runtime system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

# Install packages with exact versions from validated state
# Strategy: Install only packages that differ from NVIDIA baseline, with --no-deps
# This replicates the proven working state from Stage 3 without re-resolving dependencies
RUN set -ex && \
    echo "=== Extracting package names from baseline ===" && \
    # Extract package names from baseline, handling both == and @ formats
    # Format: "package==1.0.0" or "package @ git+https://..." -> "package"
    sed -E 's/^([a-zA-Z0-9._-]+)[ =@].*/\1/' /baseline.txt | sort -u > /baseline-names.txt && \
    echo "Baseline packages (first 10):" && head -10 /baseline-names.txt && \
    \
    echo "=== Extracting package names from final working state ===" && \
    sed -E 's/^([a-zA-Z0-9._-]+)[ =@].*/\1/' /final-working.txt | sort -u > /final-names.txt && \
    echo "Final packages (first 10):" && head -10 /final-names.txt && \
    \
    echo "=== Computing diff (packages to install) ===" && \
    # Find packages that exist in final but NOT in baseline (our additions only)
    comm -13 /baseline-names.txt /final-names.txt > /packages-to-install.txt && \
    echo "Packages to install:" && cat /packages-to-install.txt && \
    \
    echo "=== Installing packages ===" && \
    # Install each package from the diff
    while IFS= read -r pkg; do \
        # Normalize package name for comparison (replace _ with -, lowercase)
        pkg_normalized=$(echo "$pkg" | tr '_' '-' | tr '[:upper:]' '[:lower:]'); \
        \
        # Double-check this package is NOT in baseline (safety check)
        if grep -qFx "$pkg" /baseline-names.txt; then \
            echo "ERROR: Package $pkg is in baseline, skipping!"; \
            continue; \
        fi; \
        \
        # Get the full package spec with version from final-working.txt
        # Handle both == and @ formats
        pkg_spec=$(grep -E "^${pkg}(==|@| @)" /final-working.txt | head -n1 || echo ""); \
        \
        if [ -z "$pkg_spec" ]; then \
            echo "WARNING: Could not find spec for $pkg in final-working.txt, skipping"; \
            continue; \
        fi; \
        \
        # Check if we have a wheel for this package (try multiple name formats)
        wheel_file=""; \
        for name_variant in "$pkg" "$pkg_normalized" $(echo "$pkg" | tr '-' '_'); do \
            found=$(ls /wheels/${name_variant}-*.whl 2>/dev/null | head -n1 || echo ""); \
            if [ -n "$found" ]; then \
                wheel_file="$found"; \
                break; \
            fi; \
        done; \
        \
        if [ -n "$wheel_file" ]; then \
            echo ">>> Installing from wheel: $wheel_file"; \
            pip install --constraint /etc/pip/constraint.txt --no-deps --no-cache-dir "$wheel_file"; \
        else \
            echo ">>> Installing from PyPI: $pkg_spec"; \
            pip install --constraint /etc/pip/constraint.txt --no-deps --no-cache-dir "$pkg_spec"; \
        fi; \
    done < /packages-to-install.txt && \
    \
    echo "=== Installation complete ===" && \
    # Cleanup temporary files
    rm -rf /wheels /baseline.txt /final-working.txt /baseline-names.txt /final-names.txt /packages-to-install.txt

# Set working directory
WORKDIR /app/ComfyUI

# Create directories for volume mounts (will be overridden by Docker volumes)
RUN mkdir -p models/checkpoints \
    models/vae \
    models/vae_approx \
    models/loras \
    models/upscale_models \
    models/embeddings \
    models/controlnet \
    models/ipadapter \
    models/clip \
    models/clip_vision \
    custom_nodes \
    output \
    input \
    temp

# Download TAESD models for high-quality previews
# These enable better preview quality during generation vs blocky latent previews
RUN cd models/vae_approx && \
    curl -L -o taesd_decoder.pth https://github.com/madebyollin/taesd/raw/main/taesd_decoder.pth && \
    curl -L -o taesdxl_decoder.pth https://github.com/madebyollin/taesd/raw/main/taesdxl_decoder.pth && \
    curl -L -o taesd3_decoder.pth https://github.com/madebyollin/taesd/raw/main/taesd3_decoder.pth && \
    curl -L -o taef1_decoder.pth https://github.com/madebyollin/taesd/raw/main/taef1_decoder.pth

# Set permissions
RUN chmod -R 755 /app/ComfyUI

# Expose ComfyUI port
EXPOSE 8188

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl -f http://localhost:8188/ || exit 1

# Environment variables
ENV COMFYUI_PATH=/app/ComfyUI \
    PYTHONPATH=/app/ComfyUI \
    PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512

# Entrypoint: Start ComfyUI server
# Listen on all interfaces (0.0.0.0) for Docker networking
# Use --preview-method auto for optimal preview generation
CMD ["python", "main.py", "--listen", "0.0.0.0", "--port", "8188", "--preview-method", "auto"]
