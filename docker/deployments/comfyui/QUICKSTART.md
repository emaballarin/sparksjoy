# ComfyUI Quick Start Guide

Get ComfyUI up and running on DGX Spark in 5 minutes.

## Prerequisites

- DGX Spark with Docker and NVIDIA Container Toolkit
- Tailscale installed (optional, for automatic TLS certificates)
- Basic familiarity with Docker Compose

## Quick Setup (5 Steps)

### 1. Clone/Copy Project to DGX Spark

```bash
# SSH into DGX Spark
ssh user@dgx-spark

# Clone repository
cd ~/repositories/sparksjoy/docker/comfyui
```

### 2. Run Setup Script

```bash
# For Tailscale (recommended)
./scripts/setup.sh --domain your-device.ts.net --use-tailscale

# OR for localhost development
./scripts/setup.sh --domain localhost
```

This creates directories, generates `.env`, and creates TLS certificates.

### 3. Build Docker Image

```bash
./scripts/build-image.sh
```

Wait 20-45 minutes for first build. ☕

### 4. Start Services

```bash
docker compose up -d
```

### 5. Access ComfyUI

```bash
# Tailscale
https://your-device.ts.net:8444

# Localhost
https://localhost:8444
```

**Accept browser security warning** (self-signed cert if not using Tailscale).

## Verify Deployment

```bash
# Check containers
docker compose ps

# View logs
docker compose logs -f comfyui

# Run health check
./scripts/health-check.sh
```

## Download Models

ComfyUI starts with no models. Download via:

### Option 1: ComfyUI Manager (Easy)

1. Open ComfyUI web interface
2. Click "Manager" button
3. Navigate to "Model Manager"
4. Search and download models

### Option 2: Manual Download (Fast)

```bash
cd volumes/models/checkpoints/

# Download SD 1.5 (recommended starter model)
wget https://huggingface.co/Comfy-Org/stable-diffusion-v1-5-archive/resolve/main/v1-5-pruned-emaonly-fp16.safetensors

# Restart to recognize model
docker compose restart comfyui
```

## Common Commands

```bash
# View logs
docker compose logs -f

# Restart service
docker compose restart comfyui

# Stop all services
docker compose down

# Update containers (Watchtower runs daily at 4 AM)
docker compose pull && docker compose up -d

# Backup data
./scripts/backup.sh --encrypt

# Check health
./scripts/health-check.sh --verbose
```

## Basic Workflow

1. **Load workflow**: Use default workflow or load from file
2. **Select model**: Choose checkpoint from dropdown
3. **Enter prompt**: Positive and negative prompts
4. **Set parameters**: Steps, sampler, CFG scale
5. **Queue prompt**: Click "Queue Prompt"
6. **View output**: Images appear in output panel

## Troubleshooting Quick Fixes

### Container won't start

```bash
# Check logs
docker compose logs comfyui

# Rebuild
docker compose down
./scripts/build-image.sh --no-cache
docker compose up -d
```

### GPU not detected

```bash
# Verify GPU access
docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu22.04 nvidia-smi

# Check compose file has GPU config
grep -A 5 "devices:" docker-compose.yml
```

### Out of memory

```bash
# Increase memory limit in .env
nano .env
# Change: COMFYUI_MEMORY_LIMIT=32G

# Restart
docker compose down && docker compose up -d
```

### Can't access HTTPS

```bash
# Check Traefik is running
docker compose ps traefik

# Check port is exposed
docker compose ps | grep 8444

# Test locally
curl -k https://localhost:8444
```

### Models not appearing

```bash
# Check model directory
ls -lh volumes/models/checkpoints/

# Ensure correct permissions
chmod -R 755 volumes/models/

# Restart ComfyUI
docker compose restart comfyui
```

## Next Steps

- **Install custom nodes**: Use ComfyUI Manager in web UI
- **Download more models**: Explore HuggingFace, Civitai
- **Setup backups**: Configure automated backups with `./scripts/backup.sh`
- **Monitor resources**: Use `./scripts/health-check.sh --verbose`
- **Learn workflows**: Check ComfyUI examples and community workflows

## Additional Resources

- [Full README](README.md) - Comprehensive deployment guide
- [BUILD.md](BUILD.md) - Image build documentation
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Detailed troubleshooting
- [ComfyUI Wiki](https://github.com/comfyanonymous/ComfyUI/wiki)
- [ComfyUI Examples](https://comfyanonymous.github.io/ComfyUI_examples/)

## Default Ports

- **8444**: HTTPS (Traefik proxy to ComfyUI)
- **8188**: ComfyUI internal (not exposed)

Note: owui uses port 8443, so no conflicts when running both.

## Security Notes

- HTTPS-only access (no HTTP)
- Traefik handles TLS termination
- Rate limiting enabled
- Security headers configured
- Tailscale certs trusted automatically on Tailscale network

---

**Ready to create!** 🎨
