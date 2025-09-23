#!/bin/bash
# Ignition RunPod Template Creator
# Creates a RunPod template with pre-configured settings for Ignition
# Supports both local file generation and direct RunPod API deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
DOCKER_IMAGE="heapsgo0d/ignition-comfyui:latest"  # Update with your actual Docker Hub username
TEMPLATE_NAME="Ignition ComfyUI v2.2 - Minimal Privacy"
TEMPLATE_DESCRIPTION="Dynamic ComfyUI with runtime model downloads, minimal privacy system with Big Red Switch, and clean architecture"

# Disk defaults (can be overridden interactively or via env)
CONTAINER_DISK_GB="${CONTAINER_DISK_GB:-200}"
VOLUME_GB="${VOLUME_GB:-0}"

# Check for command line arguments
DEPLOY_MODE="local"  # Default to local file generation
if [[ "$1" == "--deploy" || "$1" == "-d" ]]; then
    DEPLOY_MODE="api"
fi

# Print banner
print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════╗"
    echo "║           🚀 IGNITION TEMPLATE           ║"
    echo "║      RunPod Template Creator v2.0         ║"
    echo "╚═══════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Print usage information
print_usage() {
    echo -e "${YELLOW}📋 Ignition RunPod Template Creator${NC}"
    echo ""
    
    if [[ "$DEPLOY_MODE" == "api" ]]; then
        echo -e "${GREEN}🚀 API Deployment Mode${NC} - Will create template directly in RunPod"
        echo -e "${BLUE}Requirements:${NC}"
        echo "  • RunPod API key (set RUNPOD_API_KEY environment variable)"
        echo "  • curl command available"
        echo ""
    else
        echo -e "${BLUE}📁 Local File Mode${NC} - Will generate files for manual upload"
        echo -e "${YELLOW}💡 Tip: Use './template.sh --deploy' for automatic deployment${NC}"
        echo ""
    fi
    
    echo -e "${BLUE}What you'll configure:${NC}"
    echo "  • CivitAI model version IDs (optional)"
    echo "  • HuggingFace repository names (optional)"
    echo "  • API tokens for faster downloads (optional)"
    echo "  • Storage and security settings"
    echo ""
    echo -e "${GREEN}Template will include:${NC}"
    echo "  ✅ Pre-configured Docker image"
    echo "  ✅ Exposed ports (8188 for ComfyUI, 8080 for file browser)"
    echo "  ✅ Environment variables for model configuration"
    echo "  ✅ GPU support enabled"
    echo "  ✅ Network volume support"
    echo ""
}

# Check API key if in deploy mode
check_api_requirements() {
    if [[ "$DEPLOY_MODE" == "api" ]]; then
        if [[ -z "$RUNPOD_API_KEY" ]]; then
            echo -e "${RED}❌ Error: RUNPOD_API_KEY environment variable not set${NC}"
            echo ""
            echo -e "${YELLOW}To use API deployment mode:${NC}"
            echo "1. Get your API key from RunPod → Settings → API Keys"
            echo "2. Export it: export RUNPOD_API_KEY=\"your_key_here\""
            echo "3. Run the script again: ./template.sh --deploy"
            echo ""
            echo -e "${BLUE}Or use local file mode: ./template.sh${NC}"
            exit 1
        fi
        
        # curl must exist
        if ! command -v curl &> /dev/null; then
            echo -e "${RED}❌ Error: curl command not found${NC}"
            echo "Please install curl to use API deployment mode"
            exit 1
        fi

        # jq is optional
        if ! command -v jq &> /dev/null; then
            echo -e "${YELLOW}⚠️  jq not found — will show raw JSON and use a basic parser fallback${NC}"
        else
            echo -e "${GREEN}✅ jq detected — pretty JSON parsing enabled${NC}"
        fi

        echo -e "${GREEN}✅ API key found, deployment mode ready${NC}"
        echo ""
    fi
}

# Get user input for configuration
get_configuration() {
    echo -e "${YELLOW}🔧 Configuration Setup${NC}"
    echo ""
    
    # Version input (easy mode)
    echo -e "${BLUE}Version:${NC}"
    read -p "Enter version tag (e.g., v1.0.12) [latest]: " version_input
    VERSION_TAG=${version_input:-latest}
    
    # Auto-generate image and template names based on version
    if [[ "$VERSION_TAG" == "latest" ]]; then
        DOCKER_IMAGE="heapsgo0d/ignition-comfyui:latest"
        TEMPLATE_NAME="Ignition ComfyUI Latest"
    else
        DOCKER_IMAGE="heapsgo0d/ignition-comfyui:$VERSION_TAG"
        TEMPLATE_NAME="Ignition ComfyUI $VERSION_TAG"
    fi
    
    echo "  → Docker Image: $DOCKER_IMAGE"
    echo "  → Template Name: $TEMPLATE_NAME"
    echo ""
    
    # CivitAI Models with default
    echo -e "${BLUE}CivitAI Models:${NC}"
    read -p "CivitAI model IDs [1569593,919063,450105]: " input_civitai
    CIVITAI_MODELS=${input_civitai:-"1569593,919063,450105"}
    echo ""
    
    # CivitAI LoRAs with default
    echo -e "${BLUE}CivitAI LoRAs:${NC}"
    read -p "CivitAI LoRA IDs [182404,445135,86788,565308]: " input_loras
    CIVITAI_LORAS=${input_loras:-"182404,445135,86788,565308"}
    echo ""
    
    # CivitAI VAEs with default
    echo -e "${BLUE}CivitAI VAEs:${NC}"
    read -p "CivitAI VAE IDs [1674314]: " input_vaes
    CIVITAI_VAES=${input_vaes:-"1674314"}
    echo ""
    
    # CivitAI FLUX with default
    echo -e "${BLUE}CivitAI FLUX Models:${NC}"
    read -p "CivitAI FLUX model IDs [153568]: " input_flux
    CIVITAI_FLUX=${input_flux:-"153568"}
    echo ""
    
    # HuggingFace Models with default
    echo -e "${BLUE}HuggingFace Models:${NC}"
    read -p "HuggingFace repositories [flux1-dev,clip_l,t5xxl_fp16,ae,flux1-krea-dev]: " input_hf
    HUGGINGFACE_MODELS=${input_hf:-"flux1-dev,clip_l,t5xxl_fp16,ae,flux1-krea-dev"}
    echo ""
    
    # Security settings with default
    echo -e "${BLUE}Security Settings:${NC}"
    read -p "File browser password [runpod]: " input_password
    FILEBROWSER_PASSWORD=${input_password:-runpod}
    echo ""

    # Minimal Privacy settings with defaults
    echo -e "${BLUE}Minimal Privacy Settings:${NC}"
    read -p "Enable minimal privacy system [true]: " input_privacy
    PRIVACY_ENABLED=${input_privacy:-true}

    if [[ "$PRIVACY_ENABLED" == "true" ]]; then
        read -p "Enable strict mode (deny-by-default networking) [0]: " input_strict
        local strict_input=${input_strict:-0}
        STRICT_MODE=$([[ "$strict_input" =~ ^(1|true|yes)$ ]] && echo "1" || echo "0")

        read -p "Allow updates window (GitHub/PyPI access) [0]: " input_updates
        local updates_input=${input_updates:-0}
        PRIV_ALLOW_UPDATES=$([[ "$updates_input" =~ ^(1|true|yes)$ ]] && echo "1" || echo "0")

        # Ask about capabilities for STRICT_MODE enforcement
        if [[ "$STRICT_MODE" == "1" ]]; then
            read -p "Request NET_ADMIN capability for iptables enforcement [true]: " input_netadmin
            REQUEST_NET_ADMIN=${input_netadmin:-true}
            echo "  → STRICT_MODE enforcement: $([[ "$REQUEST_NET_ADMIN" == "true" ]] && echo "iptables (with NET_ADMIN)" || echo "monitoring-only")"
        else
            REQUEST_NET_ADMIN="false"
        fi

        echo "  → Minimal privacy enabled - STRICT_MODE: $STRICT_MODE, Updates: $PRIV_ALLOW_UPDATES"
    else
        STRICT_MODE="0"
        PRIV_ALLOW_UPDATES="0"
        echo "  → Minimal privacy disabled"
    fi
    echo ""

    # Note about storage
    echo -e "${BLUE}Storage Note:${NC}"
    echo "Persistence handled by RunPod volume settings:"
    echo "  • Volume 0GB = Ephemeral (models download each time)"  
    echo "  • Volume >0GB = Persistent (models survive restarts)"
    echo ""

    # Disk settings
    echo -e "${BLUE}Disk Settings:${NC}"
    read -p "Container disk size in GB [${CONTAINER_DISK_GB}]: " tmp_disk
    CONTAINER_DISK_GB=${tmp_disk:-$CONTAINER_DISK_GB}
    read -p "Default volume size in GB (0 = ephemeral) [${VOLUME_GB}]: " tmp_vol
    VOLUME_GB=${tmp_vol:-$VOLUME_GB}
    echo ""
}

# Generate template JSON (manual upload option; schema differs from API)
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
      "key": "CIVITAI_LORAS",
      "value": "$CIVITAI_LORAS",
      "description": "Comma-separated CivitAI LoRA model version IDs"
    },
    {
      "key": "CIVITAI_VAES",
      "value": "$CIVITAI_VAES",
      "description": "Comma-separated CivitAI VAE model version IDs"
    },
    {
      "key": "CIVITAI_FLUX",
      "value": "$CIVITAI_FLUX",
      "description": "Comma-separated CivitAI FLUX model version IDs"
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
      "key": "PRIVACY_ENABLED",
      "value": "$PRIVACY_ENABLED",
      "description": "Enable minimal privacy system (true/false)"
    },
    {
      "key": "STRICT_MODE",
      "value": "$STRICT_MODE",
      "description": "Enable strict mode deny-by-default networking (0/1)"
    },
    {
      "key": "PRIVACY_BYPASS",
      "value": "0",
      "description": "Break-glass privacy bypass - DANGER (0/1)"
    },
    {
      "key": "PRIV_ALLOW_UPDATES",
      "value": "$PRIV_ALLOW_UPDATES",
      "description": "Enable updates window for GitHub/PyPI (0/1)"
    },
    {
      "key": "PROXY_PORT",
      "value": "8888",
      "description": "Minimal proxy port"
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
  ],$(if [[ "$REQUEST_NET_ADMIN" == "true" ]]; then echo '
  "securityContext": {
    "capabilities": {
      "add": ["NET_ADMIN"]
    }
  },'; fi)
  "startScript": "bash /workspace/scripts/startup-clean.sh"
}
EOF
}

# Friendly human-readable storage note
make_storage_note() {
  if [[ "$VOLUME_GB" =~ ^[0-9]+$ ]] && (( VOLUME_GB > 0 )); then
    echo "Persistent volume ${VOLUME_GB}GB (models survive restarts)"
  else
    echo "Ephemeral volume (0GB; models redownload each start)"
  fi
}

# Print template summary
print_summary() {
    echo -e "${GREEN}📋 Template Configuration Summary:${NC}"
    echo ""
    echo -e "${BLUE}Template Details:${NC}"
    echo "  Name: $TEMPLATE_NAME"
    echo "  Docker Image: $DOCKER_IMAGE"
    echo "  Storage: $(make_storage_note)"
    echo ""
    echo -e "${BLUE}Model Configuration:${NC}"
    echo "  CivitAI Models: ${CIVITAI_MODELS:-'None specified'}"
    echo "  CivitAI LoRAs: ${CIVITAI_LORAS:-'None specified'}"
    echo "  CivitAI VAEs: ${CIVITAI_VAES:-'None specified'}"
    echo "  CivitAI FLUX: ${CIVITAI_FLUX:-'None specified'}"
    echo "  HuggingFace Models: ${HUGGINGFACE_MODELS:-'None specified'}"
    echo ""
    echo -e "${BLUE}Minimal Privacy Configuration:${NC}"
    echo "  • Privacy Protection: ${PRIVACY_ENABLED}"
    echo "  • Strict Mode: ${STRICT_MODE}"
    echo "  • Updates Window: ${PRIV_ALLOW_UPDATES}"
    if [[ "$STRICT_MODE" == "1" ]]; then
        echo "  • Capabilities: $([[ "$REQUEST_NET_ADMIN" == "true" ]] && echo "NET_ADMIN requested (iptables enforcement)" || echo "No capabilities (monitoring-only)")"
    fi
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
| \`CIVITAI_MODELS\` | CivitAI model version IDs | \`138977,46846,5616\` |
| \`HUGGINGFACE_MODELS\` | HuggingFace model keys | \`flux1-dev,clip_l,t5xxl_fp16,ae,flux1-krea-dev\` |

### Optional Authentication
| Variable | Description | Get Token From |
|----------|-------------|----------------|
| \`CIVITAI_TOKEN\` | CivitAI API token | https://civitai.com/user/account |
| \`HF_TOKEN\` | HuggingFace token | https://huggingface.co/settings/tokens |

### Minimal Privacy System (Big Red Switch)
| Variable | Description | Default |
|----------|-------------|---------|
| \`PRIVACY_ENABLED\` | Enable minimal privacy proxy system | \`true\` |
| \`STRICT_MODE\` | Deny-by-default networking (0/1) | \`0\` |
| \`PRIVACY_BYPASS\` | Break-glass bypass - DANGER (0/1) | \`0\` |
| \`PRIV_ALLOW_UPDATES\` | Enable GitHub/PyPI updates window (0/1) | \`0\` |
| \`PROXY_PORT\` | Minimal proxy port | \`8888\` |

### Storage Configuration
Storage: $(make_storage_note) (Container: ${CONTAINER_DISK_GB}GB disk, ${VOLUME_GB}GB volume)

## Finding Model IDs

### CivitAI Version IDs
1. Go to model page on CivitAI
2. Click the version you want
3. Copy the \`modelVersionId\` from URL
4. Example: \`civitai.com/models/4384?modelVersionId=128713\` → use \`128713\`

### HuggingFace Repository IDs  
1. Go to model repository
2. Copy the full path from URL
3. Example: For FLUX workflow use \`flux1-dev,clip_l,t5xxl_fp16,ae,flux1-krea-dev\` (complete set with KREA variant)

## Privacy System Operation

### Two-Mode Enforcement
The minimal privacy system operates in two modes:

**Kernel Mode (with NET_ADMIN capability)**:
- ✅ Full iptables enforcement
- ✅ Deny-by-default networking in STRICT_MODE
- ✅ Only allowlisted domains can connect

**User-Space Mode (without capabilities)**:
- ✅ Proxy logging of all connections
- ⚠️ Monitoring-only in STRICT_MODE
- ⚠️ Enforcement relies on proxy environment variables

### Startup Banner
Look for this line in startup logs:
\`\`\`
🛡️ STRICT_MODE=1 ENFORCEMENT=kernel PROXY=127.0.0.1:8888 ALLOWLIST=5
\`\`\`

### Requesting Capabilities
To enable kernel mode enforcement:
1. Template must include NET_ADMIN capability request
2. RunPod deployment will have full iptables enforcement
3. STRICT_MODE will block non-allowlisted domains

## Startup Process

1. 🔍 System check
2. 🛡️ Privacy system initialization
3. 💾 Storage setup
4. 📥 Model downloads (parallel)
5. 📁 File browser start (port 8080)
6. 🎨 ComfyUI start (port 8188)

## Troubleshooting

### Logs
- SSH into pod: \`ssh root@[pod-id]-ssh.proxy.runpod.net\`
- View logs: \`tail -f /tmp/ignition_startup.log\`

### Common Issues
- **No models downloading**: Check model IDs are correct
- **Out of space**: Use persistent storage or smaller models
- **Slow downloads**: Add API tokens for authentication

### Privacy System Issues
- **STRICT_MODE not enforcing**: Check startup banner for enforcement mode
- **Need iptables enforcement**: Request NET_ADMIN capability in template
- **Proxy not logging**: Check \`/workspace/logs/privacy/proxy.log\`
- **Update window not working**: Use \`/workspace/scripts/privacy-update-window.sh test\`

---
**🚀 Ready to create amazing AI art with Ignition!**
EOF
}

# Deploy template via RunPod API
deploy_template() {
    echo -e "${YELLOW}🚀 Deploying template to RunPod...${NC}"

    # jq optional detection
    HAS_JQ=true
    if ! command -v jq &>/dev/null; then
        HAS_JQ=false
        echo -e "${YELLOW}⚠️ jq not found — responses will be raw JSON with basic parsing${NC}"
        echo ""
    fi
    
    # Build a dynamic storage note for README
    local STORAGE_NOTE
    STORAGE_NOTE="$(make_storage_note)"

    # Create API payload (GraphQL expects string with escaped newlines)
    local api_payload=$(cat << EOF
{
  "name": "$TEMPLATE_NAME",
  "imageName": "$DOCKER_IMAGE",
  "containerDiskInGb": $CONTAINER_DISK_GB,
  "volumeInGb": $VOLUME_GB,
  "volumeMountPath": "/workspace",
  "dockerArgs": "",
  "ports": "8188/http,8080/http",
  "readme": "# $TEMPLATE_NAME\\n\\n$TEMPLATE_DESCRIPTION\\n\\n## Configuration\\n- CivitAI Models: $CIVITAI_MODELS\\n- CivitAI LoRAs: $CIVITAI_LORAS\\n- HuggingFace Models: $HUGGINGFACE_MODELS\\n- Storage: ${STORAGE_NOTE} (${CONTAINER_DISK_GB}GB container disk, ${VOLUME_GB}GB volume)",
  "env": [
    {"key": "CIVITAI_MODELS", "value": "$CIVITAI_MODELS"},
    {"key": "CIVITAI_LORAS", "value": "$CIVITAI_LORAS"},
    {"key": "CIVITAI_VAES", "value": "$CIVITAI_VAES"},
    {"key": "CIVITAI_FLUX", "value": "$CIVITAI_FLUX"},
    {"key": "HUGGINGFACE_MODELS", "value": "$HUGGINGFACE_MODELS"},
    {"key": "CIVITAI_TOKEN", "value": "{{ RUNPOD_SECRET_civitai.com }}"},
    {"key": "HF_TOKEN", "value": "{{ RUNPOD_SECRET_huggingface.co }}"},
    {"key": "FILEBROWSER_PASSWORD", "value": "$FILEBROWSER_PASSWORD"},
    {"key": "PRIVACY_ENABLED", "value": "$PRIVACY_ENABLED"},
    {"key": "STRICT_MODE", "value": "$STRICT_MODE"},
    {"key": "PRIVACY_BYPASS", "value": "0"},
    {"key": "PRIV_ALLOW_UPDATES", "value": "$PRIV_ALLOW_UPDATES"},
    {"key": "PROXY_PORT", "value": "8888"}
  ]$(if [[ "$REQUEST_NET_ADMIN" == "true" ]]; then echo ',
  "securityContext": {
    "capabilities": {
      "add": ["NET_ADMIN"]
    }
  }'; fi)
}
EOF
)
    
    echo -e "${BLUE}Sending request to RunPod API...${NC}"
    
    # Make API call
    local response=$(curl -s -X POST \
        "https://api.runpod.io/graphql" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $RUNPOD_API_KEY" \
        -d "$(cat << EOF
{
  "query": "mutation saveTemplate(\$input: SaveTemplateInput!) { saveTemplate(input: \$input) { id name imageName } }",
  "variables": {
    "input": $api_payload
  }
}
EOF
)")

    # Error detection
    if echo "$response" | grep -q '"errors"'; then
        echo -e "${RED}❌ API Error:${NC}"
        if $HAS_JQ; then
            echo "$response" | jq -r '.errors[0].message'
        else
            echo "$response"
        fi
        return 1
    fi
    
    # Extract template info
    local template_id
    local template_name
    if $HAS_JQ; then
        template_id=$(echo "$response" | jq -r '.data.saveTemplate.id')
        template_name=$(echo "$response" | jq -r '.data.saveTemplate.name')
    else
        # Fallback parsing (best-effort)
        template_id=$(echo "$response" | grep -o '"id":"[^"]*' | head -n1 | cut -d'"' -f4)
        template_name=$(echo "$response" | grep -o '"name":"[^"]*' | head -n1 | cut -d'"' -f4)
    fi
    
    if [[ -n "$template_id" && "$template_id" != "null" ]]; then
        echo -e "${GREEN}✅ Template deployed successfully!${NC}"
        echo -e "${BLUE}Template ID:${NC} $template_id"
        echo -e "${BLUE}Template Name:${NC} $template_name"
        echo -e "${BLUE}RunPod Console:${NC} https://runpod.io/console/user/templates"
        return 0
    else
        echo -e "${RED}❌ Failed to deploy template${NC}"
        echo -e "${YELLOW}Response:${NC} $response"
        return 1
    fi
}

# Main execution
main() {
    print_banner
    print_usage
    
    # Check API requirements if in deploy mode
    check_api_requirements
    
    echo -e "${YELLOW}Press Enter to continue with template creation...${NC}"
    read
    
    get_configuration
    
    echo -e "${YELLOW}🔨 Generating template files...${NC}"
    generate_template
    generate_instructions
    print_summary
    
    if [[ "$DEPLOY_MODE" == "api" ]]; then
        echo -e "${YELLOW}🚀 Deploying to RunPod...${NC}"
        if deploy_template; then
            echo ""
            echo -e "${GREEN}✅ Template deployed successfully!${NC}"
            echo ""
            echo -e "${YELLOW}Next Steps:${NC}"
            echo "  1. Go to RunPod Console → Templates"
            echo "  2. Find your '$TEMPLATE_NAME' template"
            echo "  3. Deploy a pod using your new template"
            echo "  4. Access ComfyUI at http://[pod-id]-8188.proxy.runpod.net"
            echo "  5. Manage files at http://[pod-id]-8080.proxy.runpod.net"
        else
            echo ""
            echo -e "${YELLOW}⚠️  API deployment failed, but local files were created${NC}"
            echo -e "${BLUE}You can still upload ignition_template.json manually${NC}"
        fi
    else
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
        echo -e "${BLUE}💡 Tip: Use './template.sh --deploy' for automatic deployment${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}🚀 Happy creating with Ignition!${NC}"
}

# Run main function
main "$@"
