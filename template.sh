#!/bin/bash
# Ignition RunPod Template Creator
# Creates a RunPod template with pre-configured settings for Ignition

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
DOCKER_IMAGE="heapsg00d/ignition-comfyui:latest"  # Update with your actual Docker Hub username
TEMPLATE_NAME="Ignition ComfyUI v1.0"
TEMPLATE_DESCRIPTION="Dynamic ComfyUI with runtime model downloads from CivitAI and HuggingFace"

# Print banner
print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════╗"
    echo "║           🚀 IGNITION TEMPLATE           ║"
    echo "║        RunPod Template Creator v1.0       ║"
    echo "╚═══════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Print usage information
print_usage() {
    echo -e "${YELLOW}📋 This script will create a RunPod template for Ignition${NC}"
    echo ""
    echo -e "${BLUE}What you'll need:${NC}"
    echo "  • RunPod account with API access"
    echo "  • CivitAI model version IDs (optional)"
    echo "  • HuggingFace repository names (optional)"
    echo "  • API tokens for faster downloads (optional)"
    echo ""
    echo -e "${GREEN}Template will include:${NC}"
    echo "  ✅ Pre-configured Docker image"
    echo "  ✅ Exposed ports (8188 for ComfyUI, 8080 for file browser)"
    echo "  ✅ Environment variables for model configuration"
    echo "  ✅ GPU support enabled"
    echo "  ✅ Network volume support"
    echo ""
}

# Get user input for configuration
get_configuration() {
    echo -e "${YELLOW}🔧 Configuration Setup${NC}"
    echo ""
    
    # Docker image
    echo -e "${BLUE}Docker Image:${NC}"
    read -p "Enter Docker image name [$DOCKER_IMAGE]: " input_image
    DOCKER_IMAGE=${input_image:-$DOCKER_IMAGE}
    echo ""
    
    # Template name
    echo -e "${BLUE}Template Name:${NC}"
    read -p "Enter template name [$TEMPLATE_NAME]: " input_name
    TEMPLATE_NAME=${input_name:-$TEMPLATE_NAME}
    echo ""
    
    # CivitAI Models
    echo -e "${BLUE}CivitAI Models (optional):${NC}"
    echo "Enter comma-separated version IDs (e.g., 128713,46846,5616)"
    echo "Leave blank to skip CivitAI downloads"
    read -p "CivitAI model IDs: " CIVITAI_MODELS
    echo ""
    
    # HuggingFace Models
    echo -e "${BLUE}HuggingFace Models (optional):${NC}"
    echo "Enter comma-separated repository names (e.g., black-forest-labs/FLUX.1-dev)"
    echo "Leave blank to skip HuggingFace downloads"
    read -p "HuggingFace repositories: " HUGGINGFACE_MODELS
    echo ""
    
    # Persistent Storage
    echo -e "${BLUE}Persistent Storage:${NC}"
    echo "Enable persistent storage for models? (saves download time on restarts)"
    read -p "Use persistent storage? (y/n) [y]: " use_persistent
    use_persistent=${use_persistent:-y}
    
    if [[ "$use_persistent" == "y" || "$use_persistent" == "Y" ]]; then
        PERSISTENT_STORAGE="/workspace/persistent_models"
    else
        PERSISTENT_STORAGE="none"
    fi
    echo ""
    
    # File Browser Password
    echo -e "${BLUE}File Browser Security:${NC}"
    read -p "Enter file browser password [runpod]: " fb_password
    FILEBROWSER_PASSWORD=${fb_password:-runpod}
    echo ""
}

# Generate template JSON
generate_template() {
    cat > ignition_template.json << EOF
{
  "name": "$TEMPLATE_NAME",
  "description": "$TEMPLATE_DESCRIPTION",
  "dockerImage": "$DOCKER_IMAGE",
  "ports": [
    {
      "privatePort": 8188,
      "publicPort": 8188,
      "type": "http",
      "description": "ComfyUI Web Interface"
    },
    {
      "privatePort": 8080,
      "publicPort": 8080,
      "type": "http",
      "description": "File Browser"
    }
  ],
  "volumeMounts": [
    {
      "containerPath": "/workspace",
      "name": "workspace"
    }
  ],
  "environmentVariables": [
    {
      "key": "CIVITAI_MODELS",
      "value": "$CIVITAI_MODELS",
      "description": "Comma-separated CivitAI model version IDs"
    },
    {
      "key": "HUGGINGFACE_MODELS", 
      "value": "$HUGGINGFACE_MODELS",
      "description": "Comma-separated HuggingFace repository names"
    },
    {
      "key": "CIVITAI_TOKEN",
      "value": "",
      "description": "CivitAI API token (optional, for faster downloads)"
    },
    {
      "key": "HF_TOKEN",
      "value": "",
      "description": "HuggingFace API token (optional, for private repos)"
    },
    {
      "key": "PERSISTENT_STORAGE",
      "value": "$PERSISTENT_STORAGE",
      "description": "Persistent storage path or 'none'"
    },
    {
      "key": "FILEBROWSER_PASSWORD",
      "value": "$FILEBROWSER_PASSWORD",
      "description": "Password for file browser access"
    },
    {
      "key": "COMFYUI_PORT",
      "value": "8188",
      "description": "ComfyUI web interface port"
    },
    {
      "key": "FILEBROWSER_PORT",
      "value": "8080", 
      "description": "File browser port"
    }
  ],
  "startScript": "bash /workspace/scripts/startup.sh"
}
EOF
}

# Print template summary
print_summary() {
    echo -e "${GREEN}📋 Template Configuration Summary:${NC}"
    echo ""
    echo -e "${BLUE}Template Details:${NC}"
    echo "  Name: $TEMPLATE_NAME"
    echo "  Docker Image: $DOCKER_IMAGE"
    echo "  Persistent Storage: $PERSISTENT_STORAGE"
    echo ""
    echo -e "${BLUE}Model Configuration:${NC}"
    echo "  CivitAI Models: ${CIVITAI_MODELS:-'None specified'}"
    echo "  HuggingFace Models: ${HUGGINGFACE_MODELS:-'None specified'}"
    echo ""
    echo -e "${BLUE}Access:${NC}"
    echo "  ComfyUI: http://[pod-id]-8188.proxy.runpod.net"
    echo "  File Browser: http://[pod-id]-8080.proxy.runpod.net"
    echo "  File Browser Login: admin / $FILEBROWSER_PASSWORD"
    echo ""
}

# Generate usage instructions
generate_instructions() {
    cat > RUNPOD_USAGE.md << EOF
# 🚀 Ignition RunPod Deployment Guide

## Quick Start

1. **Import Template**:
   - Go to RunPod Templates
   - Click "New Template"
   - Upload the \`ignition_template.json\` file

2. **Deploy Pod**:
   - Select Ignition template
   - Choose GPU (RTX 5090 recommended)
   - Add network volume if using persistent storage
   - Deploy!

## Access URLs

Once your pod is running:

- **ComfyUI**: \`http://[your-pod-id]-8188.proxy.runpod.net\`
- **File Browser**: \`http://[your-pod-id]-8080.proxy.runpod.net\`
  - Username: \`admin\`
  - Password: \`$FILEBROWSER_PASSWORD\`

## Environment Variables

### Required for Model Downloads
| Variable | Description | Example |
|----------|-------------|---------|
| \`CIVITAI_MODELS\` | CivitAI model version IDs | \`128713,46846,5616\` |
| \`HUGGINGFACE_MODELS\` | HuggingFace repo names | \`black-forest-labs/FLUX.1-dev\` |

### Optional Authentication  
| Variable | Description | Get Token From |
|----------|-------------|----------------|
| \`CIVITAI_TOKEN\` | CivitAI API token | https://civitai.com/user/account |
| \`HF_TOKEN\` | HuggingFace token | https://huggingface.co/settings/tokens |

### Storage Configuration
| Variable | Description | Options |
|----------|-------------|---------|
| \`PERSISTENT_STORAGE\` | Model storage path | \`/workspace/persistent_models\` or \`none\` |

## Finding Model IDs

### CivitAI Version IDs
1. Go to model page on CivitAI
2. Click the version you want
3. Copy the \`modelVersionId\` from URL
4. Example: \`civitai.com/models/4384?modelVersionId=128713\` → use \`128713\`

### HuggingFace Repository IDs  
1. Go to model repository
2. Copy the full path from URL
3. Example: \`huggingface.co/black-forest-labs/FLUX.1-dev\` → use \`black-forest-labs/FLUX.1-dev\`

## Startup Process

1. 🔍 System check
2. 💾 Storage setup  
3. 📥 Model downloads (parallel)
4. 📁 File browser start (port 8080)
5. 🎨 ComfyUI start (port 8188)

## Troubleshooting

### Logs
- SSH into pod: \`ssh root@[pod-id].proxy.runpod.net\`
- View logs: \`tail -f /tmp/ignition_startup.log\`

### Common Issues
- **No models downloading**: Check model IDs are correct
- **Out of space**: Use persistent storage or smaller models
- **Slow downloads**: Add API tokens for authentication

## Example Configurations

### Basic Setup
\`\`\`bash
CIVITAI_MODELS="128713,46846"
HUGGINGFACE_MODELS="runwayml/stable-diffusion-v1-5"
PERSISTENT_STORAGE="/workspace/persistent_models"
\`\`\`

### Flux-Focused
\`\`\`bash
HUGGINGFACE_MODELS="black-forest-labs/FLUX.1-dev,black-forest-labs/FLUX.1-schnell"
CIVITAI_MODELS="5616,12345"
PERSISTENT_STORAGE="/workspace/flux_models"
\`\`\`

### Production Setup
\`\`\`bash
CIVITAI_MODELS="128713,46846,5616"
HUGGINGFACE_MODELS="black-forest-labs/FLUX.1-dev"
CIVITAI_TOKEN="your_token_here"
HF_TOKEN="hf_your_token_here"
PERSISTENT_STORAGE="/workspace/persistent_models"
FILEBROWSER_PASSWORD="secure_password_123"
\`\`\`

---
**🚀 Ready to create amazing AI art with Ignition!**
EOF
}

# Main execution
main() {
    print_banner
    print_usage
    
    echo -e "${YELLOW}Press Enter to continue with template creation...${NC}"
    read
    
    get_configuration
    
    echo -e "${YELLOW}🔨 Generating template files...${NC}"
    generate_template
    generate_instructions
    print_summary
    
    echo -e "${GREEN}✅ Template files created successfully!${NC}"
    echo ""
    echo -e "${BLUE}Generated Files:${NC}"
    echo "  📄 ignition_template.json - RunPod template definition"
    echo "  📖 RUNPOD_USAGE.md - Deployment and usage guide"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. Upload ignition_template.json to RunPod Templates"
    echo "  2. Deploy a pod using your new template"
    echo "  3. Access ComfyUI at http://[pod-id]-8188.proxy.runpod.net"
    echo "  4. Manage files at http://[pod-id]-8080.proxy.runpod.net"
    echo ""
    echo -e "${GREEN}🚀 Happy creating with Ignition!${NC}"
}

# Run main function
main "$@"