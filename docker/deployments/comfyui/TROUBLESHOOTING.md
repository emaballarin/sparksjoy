# Troubleshooting Guide

Common issues and solutions for the ComfyUI deployment.

## Table of Contents

- [Build Issues](#build-issues)
- [Deployment Issues](#deployment-issues)
- [GPU Issues](#gpu-issues)
- [Network/HTTPS Issues](#networkhttps-issues)
- [Performance Issues](#performance-issues)
- [Model Issues](#model-issues)
- [Custom Node Issues](#custom-node-issues)

---

## Build Issues

### Build fails: "Cannot connect to Docker daemon"

**Problem**: Docker is not running or user lacks permissions.

**Solution**:
```bash
# Check Docker status
sudo systemctl status docker

# Start Docker
sudo systemctl start docker

# Add user to docker group (logout/login required)
sudo usermod -aG docker $USER
```

### Build fails: Out of memory

**Problem**: Insufficient RAM during build.

**Solution**:
```bash
# Limit build resources
docker build --cpus=2 --memory=8g --tag comfyui:latest-arm64 .

# Or increase swap space
sudo fallocate -l 16G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### Build fails: PyTorch installation timeout

**Problem**: Network timeout downloading PyTorch (~4GB).

**Solution**:
```bash
# Use mirror (Chinese users)
docker build --build-arg PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple .

# Or download PyTorch wheel manually and modify Dockerfile to use local file
```

### Custom node installation fails during build

**Problem**: Some custom nodes have broken dependencies.

**Solution**:
This is expected and non-fatal. The `|| true` in Dockerfile prevents build failure.
- Image will still build successfully
- Install problematic nodes manually later via ComfyUI Manager
- Or remove the node from Dockerfile if not needed

---

## Deployment Issues

### Container exits immediately after starting

**Problem**: Configuration error or missing files.

**Diagnosis**:
```bash
# Check logs
docker compose logs comfyui

# Common causes:
# - Missing .env file
# - Invalid configuration
# - Missing certificates
```

**Solution**:
```bash
# Run validation
./scripts/validate-config.sh

# Regenerate config
./scripts/setup.sh --domain your-domain

# Check Docker Compose syntax
docker compose config
```

### "Port 8444 already in use"

**Problem**: Another service using the port.

**Solution**:
```bash
# Find process using port
sudo lsof -i :8444

# Change port in .env
nano .env
# Set: TRAEFIK_HTTPS_PORT=8445

# Restart
docker compose down && docker compose up -d
```

### Containers start but health check fails

**Problem**: Service not responding correctly.

**Diagnosis**:
```bash
# Check container health
docker compose ps

# View detailed logs
docker compose logs -f comfyui

# Test direct access
docker exec comfyui-app curl -f http://localhost:8188/
```

**Solution**:
```bash
# Restart containers
docker compose restart

# If persistent, rebuild
docker compose down
docker compose up -d --force-recreate
```

### "Permission denied" errors in logs

**Problem**: Volume mount permission issues.

**Solution**:
```bash
# Fix permissions
sudo chown -R $USER:$USER volumes/
chmod -R 755 volumes/

# Restart
docker compose restart comfyui
```

---

## GPU Issues

### GPU not detected in ComfyUI

**Problem**: NVIDIA runtime not configured or GPU not accessible.

**Diagnosis**:
```bash
# Test GPU access in container
docker exec comfyui-app nvidia-smi

# Check NVIDIA runtime
docker info | grep nvidia
```

**Solution**:
```bash
# Install NVIDIA Container Toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
  sudo tee /etc/apt/sources.list.d/nvidia-docker.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker

# Or configure /etc/docker/daemon.json
sudo nano /etc/docker/daemon.json
# Add:
# {
#   "runtimes": {
#     "nvidia": {
#       "path": "nvidia-container-runtime",
#       "runtimeArgs": []
#     }
#   }
# }
```

### "CUDA out of memory" errors

**Problem**: GPU memory exhausted.

**Solution**:
```bash
# Reduce batch size in ComfyUI workflow
# Use smaller models (e.g., SD 1.5 instead of SDXL)
# Enable model offloading

# Check GPU memory
docker exec comfyui-app nvidia-smi

# Restart to clear VRAM
docker compose restart comfyui
```

### Multiple GPU conflicts (owui + comfyui)

**Problem**: Both services competing for GPU 0.

**Solution**:
```bash
# Option 1: Use different GPUs
# In comfyui/.env:
GPU_DEVICE_IDS=1

# Option 2: Share GPU (default)
# Both can share GPU 0, CUDA handles scheduling
# Monitor with: watch -n1 nvidia-smi
```

---

## Network/HTTPS Issues

### "Connection refused" when accessing ComfyUI

**Problem**: Traefik not routing correctly.

**Diagnosis**:
```bash
# Check Traefik is running
docker compose ps traefik

# Check Traefik logs
docker compose logs traefik

# Test direct container access
docker exec comfyui-app curl -f http://localhost:8188/
```

**Solution**:
```bash
# Verify Traefik labels
docker compose config | grep -A 20 "traefik.enable"

# Restart Traefik
docker compose restart traefik

# Check network connectivity
docker network inspect comfyui-network
```

### Browser shows "Certificate not trusted"

**Problem**: Self-signed certificate.

**Expected for self-signed certs**. Solutions:

1. **Use Tailscale certificates** (recommended):
   ```bash
   ./scripts/generate-certs.sh --use-tailscale --domain your-device.ts.net --force
   docker compose restart traefik
   ```

2. **Import CA certificate** (see generate-certs.sh output for instructions)

3. **Use Let's Encrypt** (requires public domain):
   - Update `config/traefik.yml` with email
   - Ensure ports 80/443 publicly accessible

### Tailscale certificate generation fails

**Problem**: Domain not reachable via Tailscale.

**Solution**:
```bash
# Verify Tailscale is running
tailscale status

# Check MagicDNS is enabled
# Must use .ts.net domain or MagicDNS name

# Test connectivity
ping your-device.ts.net

# Regenerate with correct domain
./scripts/generate-certs.sh --use-tailscale --domain $(tailscale status | grep $(hostname) | awk '{print $2}') --force
```

### Cannot access from outside Tailscale network

**Expected behavior**. Options:

1. **Join Tailscale network** (recommended)
2. **Use Let's Encrypt** for public access
3. **Use VPN/SSH tunnel**

---

## Performance Issues

### Slow image generation

**Causes**:
- Large model (SDXL vs SD 1.5)
- High resolution
- Many steps
- CPU fallback (GPU not working)

**Solution**:
```bash
# Verify GPU usage during generation
watch -n1 nvidia-smi

# If GPU not used, see "GPU Issues" section

# Optimize workflow:
# - Use SD 1.5 instead of SDXL for speed
# - Reduce steps (20-30 often sufficient)
# - Lower resolution (512x512 vs 1024x1024)
# - Use faster samplers (DPM++ 2M Karras)
```

### High memory usage

**Problem**: Docker container consuming excessive RAM.

**Solution**:
```bash
# Check current usage
docker stats comfyui-app

# Adjust limits in .env
nano .env
# Modify: COMFYUI_MEMORY_LIMIT=16G

# Restart
docker compose down && docker compose up -d

# Monitor
docker stats
```

### Disk space filling up

**Problem**: Output images and models consuming disk.

**Solution**:
```bash
# Check disk usage
du -sh volumes/*

# Clean old outputs
rm -rf volumes/output/old_images/

# Move models to external storage
# Update volume mount in docker-compose.yml

# Setup log rotation
sudo ./scripts/setup-logrotate.sh

# Enable backup retention
nano .env
# Set: BACKUP_RETENTION_DAYS=7
```

---

## Model Issues

### Models not appearing in ComfyUI

**Problem**: Models in wrong directory or wrong format.

**Solution**:
```bash
# Check model location
ls -lh volumes/models/checkpoints/

# Supported formats: .safetensors, .ckpt, .pt, .pth

# Verify permissions
chmod -R 755 volumes/models/

# Restart to refresh
docker compose restart comfyui

# Check ComfyUI logs for model loading
docker compose logs comfyui | grep -i "model\|checkpoint"
```

### Model download via Manager fails

**Problem**: Network issue or insufficient disk space.

**Solution**:
```bash
# Check disk space
df -h

# Check logs
docker compose logs comfyui

# Download manually
cd volumes/models/checkpoints/
wget <model_url>

# Or download on host and copy
scp model.safetensors dgx-spark:~/path/to/comfyui/volumes/models/checkpoints/
```

### "Model loading failed" error

**Problem**: Corrupted model or unsupported format.

**Solution**:
```bash
# Verify file integrity
sha256sum volumes/models/checkpoints/model.safetensors
# Compare with source checksum

# Re-download model
rm volumes/models/checkpoints/corrupted_model.safetensors
# Download again

# Check model compatibility
# Some models require specific ComfyUI versions or custom nodes
```

---

## Custom Node Issues

### Custom node not appearing

**Problem**: Node not installed or installation failed.

**Solution**:
```bash
# Check custom_nodes directory
ls -lh volumes/custom_nodes/

# Install via Manager:
# 1. Open ComfyUI web UI
# 2. Click "Manager"
# 3. "Install Custom Nodes"
# 4. Search and install

# Or manually:
cd volumes/custom_nodes/
git clone <node_repository_url>
docker compose restart comfyui
```

### Custom node installation fails

**Problem**: Dependency conflicts or missing system packages.

**Solution**:
```bash
# Check ComfyUI logs during restart
docker compose logs -f comfyui

# Install dependencies in container
docker exec -it comfyui-app bash
pip install <missing_package>
exit

# Or add to Dockerfile and rebuild
# (for persistent installation)
```

### Node causes ComfyUI to crash

**Problem**: Buggy or incompatible custom node.

**Solution**:
```bash
# Identify problematic node from logs
docker compose logs comfyui | grep -i error

# Disable node temporarily
mv volumes/custom_nodes/problematic_node volumes/custom_nodes/problematic_node.disabled

# Restart
docker compose restart comfyui

# Report issue to node developer or remove permanently
```

---

## General Debugging

### View all logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f comfyui
docker compose logs -f traefik

# Last 100 lines
docker compose logs --tail=100 comfyui
```

### Access container shell

```bash
# ComfyUI container
docker exec -it comfyui-app bash

# Explore filesystem
ls -la /app/ComfyUI/
cat /app/logs/comfyui.log

# Test GPU
nvidia-smi

# Exit
exit
```

### Reset everything

```bash
# Stop and remove containers
docker compose down -v

# Remove custom nodes and outputs (CAUTION: deletes data)
rm -rf volumes/custom_nodes/*
rm -rf volumes/output/*

# Keep models (large)
# ls volumes/models/

# Rebuild and restart
./scripts/build-image.sh --no-cache
docker compose up -d
```

### Check health status

```bash
# Run health check script
./scripts/health-check.sh --verbose

# Check container health
docker compose ps

# Inspect container
docker inspect comfyui-app | jq '.[0].State.Health'
```

---

## Getting Help

If issues persist:

1. **Check logs**: `docker compose logs -f comfyui`
2. **Validate config**: `./scripts/validate-config.sh`
3. **Run health check**: `./scripts/health-check.sh --verbose`
4. **Review documentation**:
   - [README.md](README.md)
   - [BUILD.md](BUILD.md)
   - [QUICKSTART.md](QUICKSTART.md)
5. **ComfyUI resources**:
   - [ComfyUI GitHub Issues](https://github.com/comfyanonymous/ComfyUI/issues)
   - [ComfyUI Community](https://github.com/comfyanonymous/ComfyUI/discussions)

---

**Still stuck?** Create a detailed issue report with:
- Error messages from logs
- Output of `./scripts/health-check.sh --verbose`
- System info: `docker info && nvidia-smi`
- Steps to reproduce
