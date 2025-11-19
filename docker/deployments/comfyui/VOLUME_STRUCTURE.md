# ComfyUI Volume Structure

This deployment uses a unique volume structure that allows ComfyUI to have full read-write access to its repository while keeping data (models, outputs, etc.) in separate persistent volumes.

## Directory Structure

```
docker/deployments/comfyui/
├── volumes/
│   └── ComfyUI/              # Full ComfyUI repository (RW, persistent)
│       ├── (cloned at first startup)
│       ├── models -> /comfyvolumes/models (symlink)
│       ├── custom_nodes -> /comfyvolumes/custom_nodes (symlink)
│       ├── input -> /comfyvolumes/input (symlink)
│       ├── output -> /comfyvolumes/output (symlink)
│       └── temp -> /comfyvolumes/temp (symlink)
│
├── comfyvolumes/             # Persistent data volumes
│   ├── models/
│   │   ├── checkpoints/
│   │   ├── vae/
│   │   ├── vae_approx/
│   │   ├── loras/
│   │   ├── upscale_models/
│   │   ├── embeddings/
│   │   ├── controlnet/
│   │   ├── ipadapter/
│   │   ├── clip/
│   │   └── clip_vision/
│   ├── custom_nodes/
│   │   ├── ComfyUI-Manager/
│   │   ├── ComfyUI_IPAdapter_plus/
│   │   └── civitai_comfy_nodes/
│   ├── input/
│   │   └── 3d/
│   ├── output/
│   └── temp/
│
└── logs/
    └── comfyui/
```

## How It Works

### First Startup

When the container starts for the first time:

1. **ComfyUI Repository Initialization**
   - If `volumes/ComfyUI` is empty or doesn't exist, the entrypoint script clones the official ComfyUI repository from GitHub
   - This gives you full read-write access to the entire ComfyUI codebase

2. **Symlink Creation**
   - The entrypoint creates symlinks inside `volumes/ComfyUI` pointing to `comfyvolumes/`:
     - `ComfyUI/models` → `/comfyvolumes/models`
     - `ComfyUI/custom_nodes` → `/comfyvolumes/custom_nodes`
     - `ComfyUI/input` → `/comfyvolumes/input`
     - `ComfyUI/output` → `/comfyvolumes/output`
     - `ComfyUI/temp` → `/comfyvolumes/temp`

3. **Custom Nodes Installation**
   - If not already present, the following custom nodes are automatically cloned:
     - **ComfyUI-Manager**: Web-based custom node management
     - **ComfyUI_IPAdapter_plus**: IP-Adapter support
     - **civitai_comfy_nodes**: Civitai model loader with AIR identifiers

### Subsequent Startups

On subsequent container startups:
- The existing ComfyUI repository in `volumes/ComfyUI` is used (no re-cloning)
- Symlinks are recreated (in case they were accidentally removed)
- Custom nodes are checked and cloned only if missing
- ComfyUI starts immediately

## Benefits of This Structure

1. **Full Repository Access**: You can modify any ComfyUI file directly, experiment with the codebase, or even check out different branches/versions

2. **Persistent Data Separation**: Models, outputs, and custom nodes are stored separately from the ComfyUI code, making it easy to:
   - Share models across different ComfyUI versions
   - Back up data independently from code
   - Migrate data to different deployments

3. **Easy Updates**: To update ComfyUI:
   ```bash
   cd volumes/ComfyUI
   git pull
   docker-compose restart comfyui
   ```

4. **Development-Friendly**: You can edit ComfyUI source code, add custom nodes manually, or test modifications without rebuilding the Docker image

## Initial Setup

Before first run, you may want to create the directory structure manually:

```bash
# Create comfyvolumes structure
mkdir -p comfyvolumes/{models,custom_nodes,input,output,temp}
mkdir -p comfyvolumes/models/{checkpoints,vae,vae_approx,loras,upscale_models,embeddings,controlnet,ipadapter,clip,clip_vision}
mkdir -p comfyvolumes/input/3d

# Create logs directory
mkdir -p logs/comfyui

# The volumes/ComfyUI directory will be created automatically on first startup
```

Alternatively, the entrypoint script will create all necessary directories automatically on first startup.

## Troubleshooting

### ComfyUI won't start / Repository issues
If there are issues with the cloned repository:
```bash
# Stop the container
docker-compose down

# Remove the ComfyUI volume (your data in comfyvolumes is safe!)
rm -rf volumes/ComfyUI

# Restart - it will re-clone
docker-compose up -d
```

### Symlinks are broken
The entrypoint script recreates symlinks on every startup, so simply restarting the container should fix any symlink issues:
```bash
docker-compose restart comfyui
```

### Custom node not installed
If a custom node failed to install, you can manually clone it:
```bash
cd comfyvolumes/custom_nodes
git clone <node-repository-url>
docker-compose restart comfyui
```

## Migration from Old Structure

If you're migrating from the old volume structure where individual directories were mounted:

1. **Move your data**:
   ```bash
   # Create new structure
   mkdir -p comfyvolumes

   # Move existing volumes
   mv volumes/models comfyvolumes/
   mv volumes/custom_nodes comfyvolumes/
   mv volumes/input comfyvolumes/
   mv volumes/output comfyvolumes/
   mv volumes/temp comfyvolumes/
   ```

2. **Rebuild the container**:
   ```bash
   docker-compose down
   docker-compose build --no-cache
   docker-compose up -d
   ```

3. The entrypoint will clone ComfyUI and create the necessary symlinks on first startup.
