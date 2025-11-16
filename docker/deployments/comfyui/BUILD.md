# Building the ComfyUI Docker Image for DGX Spark

This guide explains how to build the ComfyUI Docker image for aarch64/arm64 architecture on the DGX Spark.

## Prerequisites

### On DGX Spark

- Docker Engine installed and running
- NVIDIA Container Toolkit installed
- Access to NVIDIA GPUs
- Sufficient disk space (~25GB for build, base image ~8GB)
- Internet connection for downloading dependencies
- CUDA 13.0-compatible GPU drivers

### Verify Prerequisites

```bash
# Check Docker
docker --version
docker info

# Check NVIDIA Docker runtime with CUDA 13.0
docker run --rm --gpus all nvcr.io/nvidia/cuda:13.0.2-base-ubuntu22.04 nvidia-smi

# Check disk space (need ~25GB)
df -h
```

## Build Process

### 1. Clone/Copy the Project

```bash
# Clone the repository
git clone <repository-url>
cd sparksjoy/docker/comfyui

# OR copy files to DGX Spark via scp/rsync
```

### 2. Run the Build Script

The simplest way to build is using the provided build script:

```bash
./scripts/build-image.sh
```

#### Build Script Options

```bash
# Build with default settings
./scripts/build-image.sh

# Build with custom tag
./scripts/build-image.sh --tag comfyui:v1.0.0-arm64

# Build without cache (clean build)
./scripts/build-image.sh --no-cache

# Build with verbose output
./scripts/build-image.sh --verbose

# Build with custom build arguments
./scripts/build-image.sh --build-arg PYTORCH_VERSION=2.5.0
```

### 3. Manual Build (Alternative)

If you prefer to build manually:

```bash
# Set platform explicitly
export DOCKER_BUILDKIT=1

# Build for arm64
docker build \
  --platform linux/arm64 \
  --tag comfyui:latest-arm64 \
  --file Dockerfile \
  .
```

## Build Details

### Image Layers

The Dockerfile uses a multi-stage build:

1. **Builder Stage**: NVIDIA PyTorch 25.10 + ComfyUI + custom nodes
2. **Final Stage**: Minimal runtime with application

### What's Included

**Base Components (from NVIDIA PyTorch 25.10):**
- Python 3.12
- PyTorch 2.9.0a0 (NVIDIA-optimized)
- CUDA 13.0.2
- TensorRT, DALI, MAGMA (NVIDIA ML libraries)
- System dependencies (OpenGL, etc.)

**Added Components:**
- ComfyUI (latest from GitHub)
- All dependencies pinned to MAX supported versions

**Pre-installed Custom Nodes:**
- ComfyUI-Manager (web-based node management)
- comfyui_controlnet_aux (ControlNet preprocessors)
- ComfyUI_IPAdapter_plus (IPAdapter integration)
- ComfyUI-Impact-Pack (image processing)
- ComfyUI-Inspire-Pack (utility nodes)
- was-node-suite-comfyui (extensive collection)

**Not Included:**
- Model checkpoints (too large, must be downloaded separately)
- User-specific custom nodes (installed at runtime)

### Build Time

- **First build**: 15-30 minutes (NVIDIA PyTorch base pulled, ~8GB)
- **Subsequent builds**: 5-10 minutes (using cache)
- **Clean build** (--no-cache): 20-40 minutes

**Note**: First pull of `nvcr.io/nvidia/pytorch:25.10-py3` (~8GB) takes time but is cached for future builds.

## Verification

### Test the Image Locally

```bash
# Run interactive test
docker run --rm --gpus all -p 8188:8188 comfyui:latest-arm64

# Access in browser
# http://localhost:8188
```

### Check Image Details

```bash
# List images
docker images comfyui:latest-arm64

# Inspect image
docker inspect comfyui:latest-arm64

# Check size
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep comfyui
```

## Troubleshooting

### Build Fails: Out of Memory

```bash
# Check available memory
free -h

# Reduce Docker build parallelism
export DOCKER_BUILDKIT=1
docker build --cpus=2 --memory=8g ...
```

### Build Fails: Network Timeout

```bash
# Increase timeout
export DOCKER_BUILD_TIMEOUT=3600

# Or use HTTP mirrors for PyTorch
docker build --build-arg PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple ...
```

### Build Fails: CUDA Not Found

```bash
# Verify NVIDIA runtime
docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu22.04 nvidia-smi

# Check /etc/docker/daemon.json
cat /etc/docker/daemon.json
# Should include:
# {
#   "runtimes": {
#     "nvidia": {
#       "path": "nvidia-container-runtime",
#       "runtimeArgs": []
#     }
#   }
# }
```

### Custom Node Installation Fails

Some custom nodes may fail to install dependencies. This is non-fatal:
- Image will still build
- Install manually after deployment via ComfyUI Manager
- Or fork and customize Dockerfile

## Updating the Image

### Update ComfyUI

```bash
# Rebuild with --no-cache to get latest ComfyUI
./scripts/build-image.sh --no-cache
```

### Update Custom Nodes

Edit `Dockerfile` and modify the custom nodes section:

```dockerfile
# Add new custom node
RUN git clone https://github.com/user/custom-node.git && \
    cd custom-node && \
    pip install --no-cache-dir -r requirements.txt || true
```

## Next Steps

After building the image:

1. **Update .env** (if needed):
   ```bash
   nano .env
   # Set: COMFYUI_IMAGE=comfyui:latest-arm64
   ```

2. **Deploy with Docker Compose**:
   ```bash
   docker compose up -d
   ```

3. **Verify deployment**:
   ```bash
   docker compose ps
   docker compose logs -f comfyui
   ```

4. **Access ComfyUI**:
   ```
   https://your-domain:8444
   ```

## Additional Resources

- [ComfyUI GitHub](https://github.com/comfyanonymous/ComfyUI)
- [ComfyUI Manager](https://github.com/ltdrdata/ComfyUI-Manager)
- [Docker BuildKit Documentation](https://docs.docker.com/build/buildkit/)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/)

## Support

For build issues specific to this deployment:
1. Check logs: `docker build ... 2>&1 | tee build.log`
2. Review Dockerfile for customization
3. See TROUBLESHOOTING.md for common issues
