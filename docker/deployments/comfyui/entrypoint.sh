#!/bin/bash
set -e

echo "=== ComfyUI Container Startup ==="
echo "Timestamp: $(date)"

# ============================================================================
# Step 1: Initialize ComfyUI Repository
# ============================================================================
if [ ! -d "/app/ComfyUI/.git" ]; then
    echo "ComfyUI repository not found. Cloning fresh copy..."
    rm -rf /app/ComfyUI/*
    git clone https://github.com/comfyanonymous/ComfyUI.git /app/ComfyUI
    echo "ComfyUI cloned successfully."
else
    echo "ComfyUI repository already exists. Skipping clone."
fi

cd /app/ComfyUI

# ============================================================================
# Step 2: Create Symlinks to Persistent Volumes
# ============================================================================
echo "Creating symlinks to persistent volumes..."

# Remove existing directories/links if they exist
for dir in models custom_nodes input output temp; do
    if [ -e "$dir" ]; then
        echo "  Removing existing $dir..."
        rm -rf "$dir"
    fi
done

# Create symlinks
ln -sf /comfyvolumes/models /app/ComfyUI/models
ln -sf /comfyvolumes/custom_nodes /app/ComfyUI/custom_nodes
ln -sf /comfyvolumes/input /app/ComfyUI/input
ln -sf /comfyvolumes/output /app/ComfyUI/output
ln -sf /comfyvolumes/temp /app/ComfyUI/temp

echo "Symlinks created successfully:"
ls -la /app/ComfyUI/ | grep -E "(models|custom_nodes|input|output|temp)"

# ============================================================================
# Step 3: Initialize Custom Nodes
# ============================================================================
echo "Checking custom nodes..."

# Ensure custom_nodes directory exists in comfyvolumes
mkdir -p /comfyvolumes/custom_nodes

# ComfyUI Manager
if [ ! -d "/comfyvolumes/custom_nodes/ComfyUI-Manager/.git" ]; then
    echo "  Installing ComfyUI-Manager..."
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git /comfyvolumes/custom_nodes/ComfyUI-Manager
else
    echo "  ComfyUI-Manager already installed."
fi

# ComfyUI_IPAdapter_plus
if [ ! -d "/comfyvolumes/custom_nodes/ComfyUI_IPAdapter_plus/.git" ]; then
    echo "  Installing ComfyUI_IPAdapter_plus..."
    git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git /comfyvolumes/custom_nodes/ComfyUI_IPAdapter_plus || echo "  Warning: Failed to clone ComfyUI_IPAdapter_plus"
else
    echo "  ComfyUI_IPAdapter_plus already installed."
fi

# Civitai ComfyUI nodes
if [ ! -d "/comfyvolumes/custom_nodes/civitai_comfy_nodes/.git" ]; then
    echo "  Installing civitai_comfy_nodes..."
    git clone https://github.com/civitai/civitai_comfy_nodes.git /comfyvolumes/custom_nodes/civitai_comfy_nodes || echo "  Warning: Failed to clone civitai_comfy_nodes"
else
    echo "  civitai_comfy_nodes already installed."
fi

# ============================================================================
# Step 4: Ensure Model Directories Exist
# ============================================================================
echo "Ensuring model directories exist..."
mkdir -p /comfyvolumes/models/{checkpoints,vae,vae_approx,loras,upscale_models,embeddings,controlnet,ipadapter,clip,clip_vision}
mkdir -p /comfyvolumes/input/3d
mkdir -p /comfyvolumes/output
mkdir -p /comfyvolumes/temp

# ============================================================================
# Step 5: Start ComfyUI
# ============================================================================
echo "=== Starting ComfyUI ==="
echo "Listening on 0.0.0.0:8188"
echo ""

exec python main.py --listen 0.0.0.0 --port 8188 --preview-method auto
