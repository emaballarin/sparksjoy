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

# Initialize build log for tracking optional component installations
RUN echo "=== ComfyUI Build Log ===" > /build.log && \
    echo "Build started: $(date)" >> /build.log && \
    echo "" >> /build.log

# Clone ComfyUI from official repository
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /app/ComfyUI

# Install ComfyUI Manager (web-based custom node management)
WORKDIR /app/ComfyUI/custom_nodes
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git

# ComfyUI-IPAdapter-plus
RUN echo "=== Cloning ComfyUI_IPAdapter_plus ===" >> /build.log && \
    git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git >> /build.log 2>&1 || \
    (echo "FAILED: ComfyUI_IPAdapter_plus" >> /build.log && true)

# Civitai ComfyUI nodes (model loader from Civitai using AIR identifiers)
RUN echo "=== Cloning civitai_comfy_nodes ===" >> /build.log && \
    git clone https://github.com/civitai/civitai_comfy_nodes.git >> /build.log 2>&1 || \
    (echo "FAILED: civitai_comfy_nodes" >> /build.log && true)

# Merge all requirements.txt files and extract dependencies from pyproject.toml files
# This ensures pip resolves all dependencies together, avoiding version conflicts
WORKDIR /app/ComfyUI

# Extract dependencies from pyproject.toml files using Python's tomllib
RUN python3 << 'PYEOF' > /pyproject-dependencies.txt
import tomllib
from pathlib import Path

dependencies = []
for pyproject_file in Path(".").rglob("pyproject.toml"):
    try:
        with open(pyproject_file, "rb") as f:
            data = tomllib.load(f)
            # Extract project.dependencies
            if "project" in data and "dependencies" in data["project"]:
                deps = data["project"]["dependencies"]
            if isinstance(deps, list):
                dependencies.extend(deps)
            # Extract optional dependencies if present
            if "project" in data and "optional-dependencies" in data["project"]:
                for group, deps in data["project"]["optional-dependencies"].items():
                    if isinstance(deps, list):
                        dependencies.extend(deps)
    except Exception as e:
        # Skip files that can't be parsed
        print(f"# Skipping {pyproject_file}: {e}", file=__import__('sys').stderr)
        continue

# Print unique dependencies
for dep in sorted(set(dependencies)):
    # Skip invalid git URLs that aren't PEP 508 compliant
    if dep.startswith("git+"):
        continue
    print(dep)
PYEOF

# Combine requirements.txt and pyproject.toml dependencies
RUN cat /pyproject-dependencies.txt > /combined-build-requirements.txt && \
    find . -name "requirements.txt" -type f -exec cat {} \; >> /combined-build-requirements.txt && \
    cat /combined-build-requirements.txt | \
    grep -vE 'facebookresearch/sam2(torch|matplotlib)' | \
    sort -u | \
    sed -E 's/^jax([^a-zA-Z0-9_-].*|$)/jax[cuda13]/' \
    > /combined-build-requirements-final.txt && \
    mv /combined-build-requirements-final.txt /combined-build-requirements.txt && \
    echo "=== Combined build requirements ===" && \
    cat /combined-build-requirements.txt

# Install all build dependencies at once with NVIDIA constraints
# Single installation pass prevents pip from flip-flopping package versions
RUN pip install --constraint /etc/pip/constraint.txt --no-cache-dir -r /combined-build-requirements.txt

# ============================================================================
# Cleanup: Remove unnecessary files to reduce image size
# ============================================================================
RUN echo "" >> /build.log && \
    echo "=== Cleanup Phase ===" >> /build.log && \
    cd /app/ComfyUI && \
    # Remove pytest cache
    (find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>&1 | tee -a /build.log || true) && \
    # Remove CI/CD configuration files
    (find . -name ".github" -type d -exec rm -rf {} + 2>&1 | tee -a /build.log || true) && \
    (find . -name ".gitlab-ci.yml" -delete 2>&1 | tee -a /build.log || true) && \
    (find . -name ".travis.yml" -delete 2>&1 | tee -a /build.log || true) && \
    # Remove editor configurations
    (find . -name ".vscode" -type d -exec rm -rf {} + 2>&1 | tee -a /build.log || true) && \
    (find . -name ".idea" -type d -exec rm -rf {} + 2>&1 | tee -a /build.log || true) && \
    # Remove linting configurations
    (find . -name ".pylintrc" -delete 2>&1 | tee -a /build.log || true) && \
    (find . -name ".flake8" -delete 2>&1 | tee -a /build.log || true) && \
    (find . -name ".mypy_cache" -type d -exec rm -rf {} + 2>&1 | tee -a /build.log || true) && \
    # Remove any leftover temporary files
    (find . -name "*.tmp" -delete 2>&1 | tee -a /build.log || true) && \
    # Remove .log files but preserve our build log
    (find . -name "*.log" ! -name "build.log" -delete 2>&1 | tee -a /build.log || true) && \
    echo "Cleanup completed" >> /build.log

# Finalize build log
RUN echo "" >> /build.log && \
    echo "Build completed: $(date)" >> /build.log

# ============================================================================
# Stage 3: Test Install - Validate working state with full dependency resolution
# ============================================================================
FROM nvcr.io/nvidia/pytorch:25.10-py3 AS validator

# Copy ComfyUI application and wheels from builder
COPY --from=builder /app/ComfyUI /app/ComfyUI

# Install system dependencies needed for some packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Install all packages from Stage 2 and let pip do FULL dependency resolution
# This replicates the complete Stage 2 environment with full dependency resolution
WORKDIR /app/ComfyUI

# Extract dependencies from pyproject.toml files using Python's tomllib
RUN python3 << 'PYEOF' > /pyproject-dependencies.txt
import tomllib
from pathlib import Path

dependencies = []
for pyproject_file in Path(".").rglob("pyproject.toml"):
    try:
        with open(pyproject_file, "rb") as f:
            data = tomllib.load(f)
            # Extract project.dependencies
            if "project" in data and "dependencies" in data["project"]:
                deps = data["project"]["dependencies"]
            if isinstance(deps, list):
                dependencies.extend(deps)
            # Extract optional dependencies if present
            if "project" in data and "optional-dependencies" in data["project"]:
                for group, deps in data["project"]["optional-dependencies"].items():
                    if isinstance(deps, list):
                        dependencies.extend(deps)
    except Exception as e:
        # Skip files that can't be parsed
        print(f"# Skipping {pyproject_file}: {e}", file=__import__('sys').stderr)
        continue

# Print unique dependencies
for dep in sorted(set(dependencies)):
    # Skip invalid git URLs that aren't PEP 508 compliant
    if dep.startswith("git+"):
        continue
    print(dep)
PYEOF

# Combine requirements.txt and pyproject.toml dependencies for complete dependency resolution
# This ensures pip resolves all dependencies together in one pass
RUN cat /pyproject-dependencies.txt > /combined-all-requirements.txt && \
    find . -name "requirements.txt" -type f -exec cat {} \; >> /combined-all-requirements.txt && \
    cat /combined-all-requirements.txt | \
    grep -vE 'facebookresearch/sam2(torch|matplotlib)' | \
    sort -u | \
    sed -E 's/^jax([^a-zA-Z0-9_-].*|$)/jax[cuda13]/' \
    > /combined-all-requirements-final.txt && \
    mv /combined-all-requirements-final.txt /combined-all-requirements.txt && \
    echo "=== Combined all requirements ===" && \
    cat /combined-all-requirements.txt

# Install all requirements at once WITHOUT constraints
# Single installation pass prevents version conflicts and allows full dependency resolution
RUN pip install --no-cache-dir -r /combined-all-requirements.txt

# Install any successfully built wheels
# This includes comfyui_controlnet_aux which has proper packaging
RUN pip install --no-cache-dir /wheels/*.whl 2>/dev/null || true

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

# Note: ComfyUI will be cloned at runtime via entrypoint.sh
# This allows the repository to be fully RW and persistent via volume mount

# Install runtime system dependencies (including git for entrypoint cloning)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
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

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set working directory
WORKDIR /app/ComfyUI

# Note: Directories will be created by entrypoint.sh at runtime
# The entire /app/ComfyUI will be a volume mount

# Expose ComfyUI port
EXPOSE 8188

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl -f http://localhost:8188/ || exit 1

# Environment variables
ENV COMFYUI_PATH=/app/ComfyUI \
    PYTHONPATH=/app/ComfyUI \
    PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:512

# Entrypoint: Initialize ComfyUI and start server
# The entrypoint script handles:
# - Cloning ComfyUI repo if not present
# - Creating symlinks to persistent volumes
# - Installing custom nodes on first run
# - Starting ComfyUI server
ENTRYPOINT ["/entrypoint.sh"]
