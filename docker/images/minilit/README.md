# MiniLit - Deep Learning Development Environment

CUDA-enabled containerized environment for deep learning and reinforcement learning development.

## Purpose

Provides a reproducible development environment with:

- PyTorch, JAX, TensorFlow
- CUDA 13.0.1 support
- Comprehensive ML/RL libraries (Optax, Equinox, etc.)
- Jupyter Lab interface
- Pixi package management

## Quick Start

**Build the container:**

```bash
just build
```

**Run interactive shell:**

```bash
just run
```

**Start Jupyter Lab:**

```bash
just jupyter
```

**Verify CUDA:**

```bash
just cuda-check
```

## Requirements

- Docker or Podman
- NVIDIA GPU with compatible drivers
- Just command runner (optional, but recommended)
