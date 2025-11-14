# Building SageAttention3 for Blackwell GPUs

This guide explains how to build SageAttention3 wheels for Blackwell GPUs (RTX 5090) from source.

## Prerequisites

**Hardware:**
- NVIDIA Blackwell GPU (RTX 5090 or similar)
- Minimum 16GB RAM

**Software:**
- Python 3.13+
- CUDA 12.8+ toolkit
- PyTorch 2.8.0+ (nightly with cu128)
- Build tools (gcc, ninja, git)

## Quick Build (RunPod)

If you're building in a RunPod pod with RTX 5090:

### Step 1: Install Python 3.13

```bash
apt-get update
apt-get install -y software-properties-common wget
add-apt-repository -y ppa:deadsnakes/ppa
apt-get update
apt-get install -y python3.13 python3.13-dev python3.13-venv

# Install pip for Python 3.13
wget https://bootstrap.pypa.io/get-pip.py
python3.13 get-pip.py
rm get-pip.py
```

### Step 2: Install CUDA 12.8 Toolkit

```bash
# Add CUDA repository
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
apt-get update

# Install CUDA 12.8 toolkit
apt-get install -y cuda-toolkit-12-8

# Update PATH
export PATH=/usr/local/cuda-12.8/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64:$LD_LIBRARY_PATH

# Verify
nvcc --version  # Should show 12.8.x
```

### Step 3: Install PyTorch Nightly

```bash
python3.13 -m pip install --pre --upgrade \
  torch torchvision torchaudio \
  --index-url https://download.pytorch.org/whl/nightly/cu128

# Verify
python3.13 -c "import torch; print('PyTorch:', torch.__version__); print('CUDA:', torch.cuda.is_available())"
```

### Step 4: Install Build Dependencies

```bash
python3.13 -m pip install einops packaging ninja setuptools wheel
```

### Step 5: Build SageAttention3

```bash
# Clone repository
cd /workspace
git clone https://github.com/thu-ml/SageAttention.git
cd SageAttention/sageattention3_blackwell

# Build wheel with Blackwell-specific flags
FAHOPPER_FORCE_BUILD=1 \
TORCH_CUDA_ARCH_LIST="10.0a;12.0a" \
python3.13 setup.py bdist_wheel

# Wheel will be in dist/
ls -lh dist/
```

**Output:** `sageattn3-1.0.0-cp313-cp313-linux_x86_64.whl` (~1.6 MB)

### Step 6: Test the Wheel

```bash
# Install the wheel
python3.13 -m pip install dist/sageattn3-1.0.0-cp313-cp313-linux_x86_64.whl

# Test import
python3.13 -c "from sageattn3 import sageattn3_blackwell; print('Import successful!')"
```

## Environment Variables

Key environment variables for building:

- `FAHOPPER_FORCE_BUILD=1` - Forces fresh local build (required)
- `TORCH_CUDA_ARCH_LIST="10.0a;12.0a"` - Target Blackwell architectures:
  - `10.0a` = SM_100 (Blackwell)
  - `12.0a` = SM_120 (Blackwell)
- `MAX_JOBS=4` - Limit parallel compilation jobs (optional)

## Uploading to GitHub Releases

After building the wheel:

### Option 1: GitHub Web UI

1. Go to https://github.com/YOUR_USERNAME/ignition/releases
2. Click "Create a new release"
3. Tag: `v3.6.0-sageattention3` (or next version)
4. Title: `v3.6.0 - SageAttention3 for Blackwell`
5. Drag and drop the `.whl` file
6. Publish release

### Option 2: GitHub CLI

```bash
# Install gh if not available
apt install -y gh

# Authenticate
gh auth login

# Create release and upload wheel
gh release create v3.6.0-sageattention3 \
  dist/sageattn3-1.0.0-cp313-cp313-linux_x86_64.whl \
  --title "v3.6.0 - SageAttention3 for Blackwell" \
  --notes "Pre-built wheel for SageAttention3 on Blackwell GPUs

**Build Details:**
- Python: 3.13.8
- CUDA: 12.8.93
- PyTorch: 2.10.0 nightly cu128
- Architecture: SM_100a, SM_120a (Blackwell)

**Installation:**
\`\`\`bash
pip install https://github.com/YOUR_USERNAME/ignition/releases/download/v3.6.0-sageattention3/sageattn3-1.0.0-cp313-cp313-linux_x86_64.whl
\`\`\`"
```

## Using Your Custom Wheel

Update `Dockerfile.sa3` to use your wheel URL:

```dockerfile
# Install SageAttention3 from your GitHub Releases wheel
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install https://github.com/YOUR_USERNAME/ignition/releases/download/v3.6.0-sageattention3/sageattn3-1.0.0-cp313-cp313-linux_x86_64.whl || \
    (echo "⚠️  SageAttention3 wheel unavailable, falling back to SageAttention2" && \
     pip install sageattention==1.0.6)
```

## Troubleshooting

### Error: "Sage3 is only supported on CUDA 12.8 and above"

**Cause:** CUDA toolkit version too old

**Solution:**
```bash
# Check CUDA version
nvcc --version

# Should show 12.8.x or higher
# If not, install CUDA 12.8 toolkit (see Step 2 above)
```

### Error: "Unsupported GPU"

**Cause:** GPU is not Blackwell architecture

**Solution:** SageAttention3 only supports Blackwell GPUs (SM_100, SM_120). For other GPUs, use SageAttention2:
```bash
pip install sageattention==1.0.6
```

### Import Error: "No module named 'sageattn3'"

**Cause:** Wheel not installed or wrong Python version

**Solution:**
```bash
# Verify Python version
python3 --version  # Should be 3.13+

# Reinstall wheel
python3.13 -m pip install --force-reinstall dist/sageattn3*.whl

# Test import
python3.13 -c "from sageattn3 import sageattn3_blackwell"
```

### Build hangs or runs out of memory

**Cause:** Too many parallel compilation jobs

**Solution:**
```bash
# Limit parallel jobs
MAX_JOBS=2 FAHOPPER_FORCE_BUILD=1 TORCH_CUDA_ARCH_LIST="10.0a;12.0a" python3.13 setup.py bdist_wheel
```

## Verification Checklist

Before uploading your wheel, verify:

- ✅ Wheel file size is ~1.6 MB
- ✅ Filename contains `cp313` (Python 3.13)
- ✅ Filename contains `linux_x86_64`
- ✅ Import test passes: `python3.13 -c "from sageattn3 import sageattn3_blackwell"`
- ✅ CUDA is available: `python3.13 -c "import torch; print(torch.cuda.is_available())"`

## Build Time

Expected build time on RTX 5090:
- CUDA kernel compilation: 5-8 minutes
- Wheel packaging: 30 seconds
- **Total: ~8-10 minutes**

## Additional Resources

- SageAttention3 README: https://github.com/thu-ml/SageAttention/blob/main/sageattention3_blackwell/README.md
- Official GitHub: https://github.com/thu-ml/SageAttention
- Ignition repository: https://github.com/HeapsGo0d/ignition

## Need Help?

If you encounter issues:
1. Check the troubleshooting section above
2. Review build logs at `/tmp/sageattention3-install.log`
3. Open an issue at https://github.com/HeapsGo0d/ignition/issues
4. Include: Python version, CUDA version, GPU model, and error message
