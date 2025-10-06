#!/bin/bash
# Performance Optimization: Plugin Installation Script
# Installs curated ComfyUI plugins with dependencies

set -euo pipefail

# Central paths
COMFY="${COMFY:-/workspace/ComfyUI}"
CNODES="$COMFY/custom_nodes"
MANAGER_DIR="$COMFY/user/default/ComfyUI-Manager"
mkdir -p "$CNODES" "$MANAGER_DIR"

# Smart dependency installer
install_reqs_if_any () {
  [ -f "$1/requirements.txt" ] && python3 -m pip install -r "$1/requirements.txt" || true
}

echo "🔧 Installing curated ComfyUI plugins..."

# Core plugins (idempotent shallow clones)
cd "$CNODES"

if [ ! -d "ComfyUI-eSuite" ]; then
  git clone --depth 1 https://github.com/pythongosssss/ComfyUI-eSuite.git
  echo "✅ Cloned ComfyUI-eSuite"
fi
install_reqs_if_any "ComfyUI-eSuite"

if [ ! -d "ComfyUI-Crystools" ]; then
  git clone --depth 1 https://github.com/crystian/ComfyUI-Crystools.git
  echo "✅ Cloned ComfyUI-Crystools"
fi
install_reqs_if_any "ComfyUI-Crystools"

if [ ! -d "ComfyUI-Various" ]; then
  git clone --depth 1 https://github.com/Various-UI-Extensions/ComfyUI-Various.git
  echo "✅ Cloned ComfyUI-Various"
fi
install_reqs_if_any "ComfyUI-Various"

# Optional plugins (env-gated)
if [ "${ENABLE_IMPACT_PACK:-0}" = "1" ]; then
  if [ ! -d "ComfyUI-Impact-Pack" ]; then
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Impact-Pack.git
    echo "✅ Cloned ComfyUI-Impact-Pack (optional)"
  fi
  install_reqs_if_any "ComfyUI-Impact-Pack"
fi

if [ "${ENABLE_CONTROLNET_AUX:-0}" = "1" ]; then
  if [ ! -d "comfyui_controlnet_aux" ]; then
    git clone --depth 1 https://github.com/Fannovel16/comfyui_controlnet_aux.git
    echo "✅ Cloned comfyui_controlnet_aux (optional)"
  fi
  install_reqs_if_any "comfyui_controlnet_aux"
fi

echo ""
echo "📌 Pinning plugin versions..."

# Pin plugin versions for reproducibility
lock_plugins () {
  (
    cd "$CNODES"
    for d in ComfyUI-eSuite ComfyUI-Crystools ComfyUI-Various ComfyUI-Impact-Pack comfyui_controlnet_aux; do
      [ -d "$d" ] && echo "$d $(git -C "$d" rev-parse --short HEAD)"
    done
  ) | tee "$COMFY/plugins.lock"
}
lock_plugins

# Copy to repo for deterministic builds
if [ -f "$COMFY/plugins.lock" ]; then
  cp "$COMFY/plugins.lock" ./plugins.lock
  echo "✅ Plugin versions locked in plugins.lock"
fi

echo ""
echo "⚙️  Configuring ComfyUI-Manager..."

# Disable Manager network mode (instant boot)
cat > "$MANAGER_DIR/config.ini" << 'EOF'
[default]
preview_method = none
network_mode = disable
git_exe =
use_uv = True
channel_url = https://raw.githubusercontent.com/ltdrdata/ComfyUI-Manager/main
share_option = all
bypass_ssl = False
EOF

echo "✅ ComfyUI-Manager network mode disabled"
echo ""
echo "🎉 Performance plugins installation complete!"
