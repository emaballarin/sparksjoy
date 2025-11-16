# syntax=docker/dockerfile:1

FROM nvcr.io/nvidia/cuda:13.0.2-devel-ubuntu24.04

LABEL maintainer="Emanuele Ballarin <emanuele@ballarin.cc>"
LABEL description="DL/RL development environment with pixi, PyTorch, JAX, and CUDA"

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PIXI_VERSION=latest \
    UV_HTTP_TIMEOUT=800 \
    PIXI_HOME=/opt/pixi \
    PATH=/opt/pixi/bin:$PATH

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    build-essential \
    sudo \
    && \
    rm -rf /var/lib/apt/lists/*

# Create non-root user with sudo access
RUN useradd -m -s /bin/bash user && \
    echo "user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/user && \
    chmod 0440 /etc/sudoers.d/user

# Create mount point for custom data
RUN mkdir -p /mnt/data && \
    chown user:user /mnt/data

# Install pixi
RUN curl -fsSL https://pixi.sh/install.sh | PIXI_HOME=/opt/pixi bash && \
    chmod -R 755 /opt/pixi

# Create working directory
WORKDIR /workspace

# Copy pixi project files
COPY pixi.toml pixi.lock* ./

# Install pixi environment
# This creates the environment and installs all dependencies
RUN pixi install

# Set ownership of workspace to user
RUN chown -R user:user /workspace

# Set up environment variables to use pixi environment
# Instead of using 'pixi shell', we manually configure the environment
ENV PATH="/workspace/.pixi/envs/default/bin:$PATH" \
    CONDA_PREFIX="/workspace/.pixi/envs/default"

# Switch to non-root user
USER user

# Verify installation
RUN python --version && \
    python -c "import torch; import jax; print(f'PyTorch: {torch.__version__}'); print(f'JAX: {jax.__version__}')"

# Remove build files to reduce image size
USER root
RUN rm -f /workspace/Dockerfile /workspace/.dockerignore /workspace/justfile
USER user

# Default command drops into bash with pixi environment activated
CMD ["/bin/bash"]
