# ComfyUI Production Deployment for DGX Spark

Production-ready ComfyUI deployment with Traefik reverse proxy, automatic HTTPS, Tailscale support, and automated updates. Optimized for NVIDIA DGX Spark (aarch64/arm64) with GPU acceleration.

## Features

- **HTTPS-Only Access**: Traefik reverse proxy with TLS termination
- **Tailscale Integration**: Automatic certificate generation for Tailscale networks
- **GPU Acceleration**: NVIDIA CUDA support for fast image generation
- **Automated Updates**: Watchtower for automatic container updates
- **Pre-installed Custom Nodes**: ComfyUI Manager, ControlNet, IPAdapter, and more
- **Backup & Restore**: Automated backup scripts with encryption support
- **Health Monitoring**: Built-in health checks and validation
- **Concurrent Deployment**: Safe to run alongside owui deployment

## Quick Start

See [QUICKSTART.md](QUICKSTART.md) for a 5-minute setup guide.

```bash
# 1. Setup
./scripts/setup.sh --domain your-device.ts.net --use-tailscale

# 2. Build image (on DGX Spark)
./scripts/build-image.sh

# 3. Deploy
docker compose up -d

# 4. Access
https://your-device.ts.net:8444
```

## Table of Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Model Management](#model-management)
- [Custom Nodes](#custom-nodes)
- [Backup & Restore](#backup--restore)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Security](#security)
- [Concurrent Deployment with owui](#concurrent-deployment-with-owui)

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────────┐
│                      DGX Spark Host                         │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐  │
│  │  Traefik Reverse Proxy (Port 8444)                  │  │
│  │  • HTTPS-only access                                │  │
│  │  • TLS termination (Tailscale/self-signed/Let's E.) │  │
│  │  • Rate limiting & security headers                 │  │
│  └──────────────┬──────────────────────────────────────┘  │
│                 │                                          │
│  ┌──────────────▼──────────────────────────────────────┐  │
│  │  ComfyUI Application (Internal Port 8188)          │  │
│  │  • PyTorch 2.9.0a0 with CUDA 13.0.2 support        │  │
│  │  • GPU acceleration (NVIDIA-optimized)             │  │
│  │  • Pre-installed custom nodes                       │  │
│  │  • ComfyUI Manager                                  │  │
│  │  • Volume-mounted models, outputs, custom nodes    │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐  │
│  │  Watchtower (Automatic Updates)                     │  │
│  │  • Daily at 4 AM UTC (configurable)                 │  │
│  │  • Label-based selective updates                    │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐  │
│  │  Persistent Volumes                                  │  │
│  │  • models/ - Checkpoints, LoRAs, VAEs, etc.        │  │
│  │  • custom_nodes/ - Custom node installations       │  │
│  │  • output/ - Generated images                       │  │
│  │  • input/ - Input images                            │  │
│  └─────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Network

- **Network**: `comfyui-network` (bridge, subnet: 172.30.0.0/16)
- **External Port**: 8444 (HTTPS)
- **Internal Port**: 8188 (ComfyUI)
- **No conflicts** with owui (172.29.0.0/16, port 8443)

## Prerequisites

### DGX Spark Requirements

- NVIDIA DGX Spark (aarch64/arm64 architecture)
- Docker Engine 20.10+
- Docker Compose v2.0+
- NVIDIA Container Toolkit
- NVIDIA GPU with CUDA 13.0+ support
- Minimum 25GB free disk space for image build (base image ~8GB)
- 50GB+ recommended for models and outputs

### Optional

- Tailscale installed (for automatic TLS certificates)
- GPG (for encrypted backups)

### Verify Prerequisites

```bash
# Docker
docker --version
docker compose version

# NVIDIA GPU
nvidia-smi

# NVIDIA Docker runtime (CUDA 13.0+)
docker run --rm --gpus all nvcr.io/nvidia/cuda:13.0.2-base-ubuntu22.04 nvidia-smi

# Disk space
df -h
```

## Installation

### 1. Clone Repository

```bash
cd ~/repositories/sparksjoy/docker/comfyui
```

### 2. Run Setup Script

The setup script creates directories, generates configuration, and creates TLS certificates:

```bash
# For Tailscale networks (recommended)
./scripts/setup.sh --domain your-device.ts.net --use-tailscale

# For localhost development
./scripts/setup.sh --domain localhost

# For custom domain (requires DNS)
./scripts/setup.sh --domain comfyui.yourdomain.com
```

Options:
- `--domain DOMAIN`: Domain for certificates and routing
- `--use-tailscale`: Generate Tailscale certificates
- `--skip-certs`: Skip certificate generation

### 3. Build Docker Image

**Important**: Must be built on DGX Spark (aarch64/arm64).

```bash
./scripts/build-image.sh
```

Build time: 15-30 minutes (first time, includes pulling ~8GB base image), 5-10 minutes (cached).

See [BUILD.md](BUILD.md) for detailed build documentation.

### 4. Review Configuration

```bash
# Edit environment variables
nano .env

# Validate configuration
./scripts/validate-config.sh
```

### 5. Deploy

```bash
# Start services
docker compose up -d

# Check status
docker compose ps

# View logs
docker compose logs -f
```

### 6. Access ComfyUI

```bash
# Browser
https://your-domain:8444

# Or
https://localhost:8444
```

**Note**: Accept browser security warning if using self-signed certificates (or import CA certificate).

## Configuration

### Environment Variables

Key settings in `.env`:

```bash
# Project
PROJECT_NAME=comfyui
DOMAIN=your-device.ts.net

# Ports
TRAEFIK_HTTPS_PORT=8444

# GPU
GPU_DEVICE_IDS=0

# Resources
COMFYUI_MEMORY_LIMIT=16G
COMFYUI_CPU_LIMIT=8

# Network
NETWORK_SUBNET=172.30.0.0/16

# Updates
WATCHTOWER_SCHEDULE=0 0 4 * * *

# TLS
USE_TAILSCALE_CERTS=true
```

See `.env.example` for all available options.

### Traefik Configuration

Static configuration: `config/traefik.yml`
- Entry points (HTTPS only)
- Certificate resolvers
- Logging

Dynamic configuration: `config/traefik-dynamic.yml`
- TLS settings (TLS 1.2/1.3, modern ciphers)
- Security headers (HSTS, CSP, etc.)
- Rate limiting (3 tiers: general, API, auth)
- Compression

### Resource Limits

Adjust in `.env`:

```bash
# CPU cores
COMFYUI_CPU_LIMIT=8
COMFYUI_CPU_RESERVATION=2

# Memory
COMFYUI_MEMORY_LIMIT=16G
COMFYUI_MEMORY_RESERVATION=4G

# GPU (comma-separated for multiple)
GPU_DEVICE_IDS=0
# Or: GPU_DEVICE_IDS=0,1
```

## Usage

### Basic Operations

```bash
# Start
docker compose up -d

# Stop
docker compose stop

# Restart
docker compose restart

# Stop and remove
docker compose down

# View logs
docker compose logs -f comfyui

# Update containers
docker compose pull && docker compose up -d
```

### Health Monitoring

```bash
# Quick health check
./scripts/health-check.sh

# Verbose (includes GPU, disk, containers)
./scripts/health-check.sh --verbose
```

### Access Container

```bash
# Shell access
docker exec -it comfyui-app bash

# Check GPU
docker exec comfyui-app nvidia-smi

# View Python packages
docker exec comfyui-app pip list
```

## Model Management

ComfyUI starts with **no models**. Download models before use.

### Model Directory Structure

```
volumes/models/
├── checkpoints/          # Stable Diffusion checkpoints (.safetensors, .ckpt)
├── vae/                  # VAE models
├── vae_approx/           # TAESD models (optional, for high-quality previews)
├── loras/                # LoRA models
├── upscale_models/       # Upscaling models (ESRGAN, RealESRGAN)
├── embeddings/           # Textual inversion embeddings
├── controlnet/           # ControlNet models
├── ipadapter/            # IPAdapter models
├── clip/                 # CLIP models
├── clip_vision/          # CLIP vision models
└── ...
```

### Download Models

#### Option 1: ComfyUI Manager (Recommended)

1. Open ComfyUI web interface
2. Click "Manager" button (bottom right)
3. Navigate to "Model Manager"
4. Search and download models
5. Automatic installation to correct directories

#### Option 2: Manual Download

```bash
cd volumes/models/checkpoints/

# Stable Diffusion 1.5 (~2GB)
wget https://huggingface.co/Comfy-Org/stable-diffusion-v1-5-archive/resolve/main/v1-5-pruned-emaonly-fp16.safetensors

# SDXL Base (~7GB)
wget https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors

# Restart to recognize new models
docker compose restart comfyui
```

#### Popular Model Sources

- [HuggingFace](https://huggingface.co/models?pipeline_tag=text-to-image)
- [Civitai](https://civitai.com/)
- [Stability AI](https://huggingface.co/stabilityai)

### Model Recommendations

**Beginners**:
- Stable Diffusion 1.5 (fast, efficient)
- DreamShaper (versatile)

**Advanced**:
- SDXL Base + Refiner (high quality)
- Realistic Vision (photorealistic)

**Specialized**:
- ControlNet models (pose control)
- IPAdapter models (style transfer)
- LoRAs (fine-tuning)

### High-Quality Previews (TAESD)

The Docker image includes TAESD decoder models pre-installed for high-quality previews during generation:
- SD 1.x/2.x: `taesd_decoder.pth`
- SDXL: `taesdxl_decoder.pth`
- SD3: `taesd3_decoder.pth`
- FLUX.1: `taef1_decoder.pth`

**Benefits:**
- High-quality previews instead of blocky latent previews
- Easier to monitor generation progress
- Automatically detected (configured with `--preview-method auto`)

## Custom Nodes

### Pre-installed Nodes

The Docker image includes:
- **ComfyUI-Manager**: Web-based node and model management
- **comfyui_controlnet_aux**: ControlNet preprocessors
- **ComfyUI_IPAdapter_plus**: IPAdapter integration
- **ComfyUI-Impact-Pack**: Image processing utilities
- **ComfyUI-Inspire-Pack**: Additional utility nodes
- **was-node-suite-comfyui**: Extensive node collection
- **civitai_comfy_nodes**: Load models directly from Civitai using AIR identifiers

### Using Civitai Model Loader

The [Civitai ComfyUI nodes](https://github.com/civitai/civitai_comfy_nodes) are pre-installed and allow you to load models directly from Civitai without manual downloading.

**What is AIR?**
AIR (AI Resource) is Civitai's universal naming for models:
- Model ID only: `{model_id}` (uses latest version)
- Specific version: `{model_id}@{version_id}`
- Example: `109395@84321`
- Enable AIR display in Civitai Account Settings → Early Access

**Usage:**
- Use "Civitai Checkpoint Loader" or "Civitai LoRA Loader" nodes in your workflow
- Enter the AIR (model ID or `model@version` format)
- Models download automatically to your models directory

**Benefits:**
- No manual downloading from Civitai website
- Automatic version management
- Workflow reproducibility (AIR embeds in workflow JSON)
- Saves time and disk space

### Install Additional Nodes

#### Via ComfyUI Manager (Easy)

1. Open ComfyUI web interface
2. Click "Manager"
3. "Install Custom Nodes"
4. Search and install
5. Restart: `docker compose restart comfyui`

#### Manual Installation

```bash
cd volumes/custom_nodes/
git clone https://github.com/user/custom-node.git
docker compose restart comfyui
```

### Popular Custom Nodes

- **ComfyUI-AnimateDiff**: Animation generation
- **ComfyUI-VideoHelperSuite**: Video processing
- **ComfyUI-Advanced-ControlNet**: Enhanced ControlNet
- **ComfyUI-Segment-Anything**: Image segmentation

## Backup & Restore

### Create Backup

```bash
# Basic backup
./scripts/backup.sh

# With encryption (recommended for production)
./scripts/backup.sh --encrypt

# Stop services during backup (safer)
./scripts/backup.sh --stop-services

# Custom compression
./scripts/backup.sh --compression bzip2
```

Backup includes:
- All models
- Custom nodes
- Generated outputs
- Configuration
- TLS certificates
- .env file

Backup location: `backups/comfyui_backup_YYYYMMDD_HHMMSS.tar.gz`

### Verify Backup

```bash
./scripts/verify-backup.sh backups/comfyui_backup_*.tar.gz
```

### Restore Backup

```bash
./scripts/restore.sh backups/comfyui_backup_YYYYMMDD_HHMMSS.tar.gz
```

**Warning**: Stops services, overwrites current data, creates safety backup.

### Automated Backups

```bash
# Add to crontab
crontab -e

# Daily backup at 2 AM
0 2 * * * cd /path/to/comfyui && ./scripts/backup.sh --encrypt

# Weekly backup with cleanup
0 3 * * 0 cd /path/to/comfyui && ./scripts/backup.sh --encrypt && find backups/ -mtime +30 -delete
```

## Monitoring

### Health Checks

```bash
# Basic health check
./scripts/health-check.sh

# Verbose (GPU, disk, containers)
./scripts/health-check.sh --verbose
```

### Docker Stats

```bash
# Real-time resource usage
docker stats comfyui-app

# All containers
docker compose stats
```

### GPU Monitoring

```bash
# Current usage
docker exec comfyui-app nvidia-smi

# Continuous monitoring
watch -n1 "docker exec comfyui-app nvidia-smi"
```

### Logs

```bash
# ComfyUI logs
docker compose logs -f comfyui

# Traefik logs
docker compose logs -f traefik

# All logs
docker compose logs -f

# Last 100 lines
docker compose logs --tail=100
```

### Log Rotation

```bash
# Install logrotate config
sudo ./scripts/setup-logrotate.sh

# Manual rotation
sudo logrotate -f /etc/logrotate.d/comfyui
```

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed solutions.

Common issues:
- GPU not detected
- Models not appearing
- HTTPS certificate warnings
- Out of memory errors
- Custom node failures
- Port conflicts

## Security

### HTTPS-Only Access

- No HTTP port exposed
- TLS 1.2/1.3 with modern cipher suites
- Automatic HTTPS redirect

### Security Headers

Configured in `config/traefik-dynamic.yml`:
- HSTS (1 year)
- Content Security Policy
- X-Frame-Options: DENY
- X-Content-Type-Options: nosniff
- Referrer Policy

### Rate Limiting

Three tiers:
- **General**: 100 req/s (50 burst)
- **API**: 20 req/s (10 burst)
- **Auth**: 5 req/min (3 burst)

### Container Security

- `no-new-privileges:true`
- Read-only Docker socket
- Minimal base images
- Non-root user (where applicable)

### Backup Encryption

```bash
# Enable GPG encryption
./scripts/backup.sh --encrypt

# Configure in .env
BACKUP_ENABLE_ENCRYPTION=true
BACKUP_GPG_RECIPIENT=your-email@example.com
```

## Concurrent Deployment with owui

This deployment is designed to run safely alongside the owui project.

### No Conflicts

| Component | owui | comfyui |
|-----------|------|---------|
| HTTPS Port | 8443 | 8444 |
| Network | 172.29.0.0/16 | 172.30.0.0/16 |
| Containers | owui-* | comfyui-* |
| GPU | 0 (or specified) | 0 (shared) |

### GPU Sharing

Both deployments can share GPU 0:
- CUDA handles concurrent access
- Memory is shared (monitor usage)
- For isolation, use different GPUs:
  - owui: `GPU_DEVICE_IDS=0`
  - comfyui: `GPU_DEVICE_IDS=1`

### Accessing Both

```bash
# owui (OpenWebUI)
https://your-device.ts.net:8443

# comfyui
https://your-device.ts.net:8444
```

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `setup.sh` | Initial deployment setup |
| `build-image.sh` | Build Docker image on DGX Spark |
| `generate-certs.sh` | Generate TLS certificates |
| `backup.sh` | Create encrypted backups |
| `restore.sh` | Restore from backup |
| `verify-backup.sh` | Verify backup integrity |
| `validate-config.sh` | Validate configuration |
| `health-check.sh` | Monitor deployment health |
| `setup-logrotate.sh` | Configure log rotation |

## Documentation

- [README.md](README.md) - This file (comprehensive guide)
- [QUICKSTART.md](QUICKSTART.md) - 5-minute setup
- [BUILD.md](BUILD.md) - Docker image build details
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues

## External Resources

- [ComfyUI GitHub](https://github.com/comfyanonymous/ComfyUI)
- [ComfyUI Wiki](https://github.com/comfyanonymous/ComfyUI/wiki)
- [ComfyUI Examples](https://comfyanonymous.github.io/ComfyUI_examples/)
- [ComfyUI Manager](https://github.com/ltdrdata/ComfyUI-Manager)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/)

## License

This deployment configuration is provided as-is for use with ComfyUI and related projects. Refer to individual components for their licenses:
- ComfyUI: GPLv3
- Traefik: MIT
- Other components: See respective licenses

## Support

For deployment issues:
1. Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
2. Run `./scripts/health-check.sh --verbose`
3. Review logs: `docker compose logs -f`

For ComfyUI issues:
- [ComfyUI GitHub Issues](https://github.com/comfyanonymous/ComfyUI/issues)
- [ComfyUI Discussions](https://github.com/comfyanonymous/ComfyUI/discussions)

---

**Happy generating!** 🎨✨
