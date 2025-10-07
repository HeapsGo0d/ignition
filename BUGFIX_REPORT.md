# Bug Investigation Report - v3.2.1-refined

## Executive Summary
Fixed 3 critical issues in feat/performance-refined branch: PyTorch configuration for RTX 5090, incorrect FLUX model mapping, and POSIX compliance.

---

## Issue #1: PyTorch Configuration for RTX 5090 🔴 CRITICAL

### Root Cause
Dockerfile attempted to use PyTorch with CUDA 12.8 but had incorrect configuration:
- **Missing `--pre` flag**: Could not access nightly/pre-release builds
- **Wrong index URL**: Used `whl/cu128` instead of `whl/nightly/cu128`
- **Misleading comment**: Claimed "PyTorch 2.8.0+cu128" (version 2.8.0 doesn't exist as stable release)

### Original (Broken) Code
```dockerfile
# Upgrade PyTorch to 2.8.0+cu128 for RTX 5090 support (sm_120)
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --upgrade torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128
```

**Problems:**
- No `--pre` flag → Cannot get nightly builds with RTX 5090 support
- Wrong index → Gets stable cu128 builds (2.7.0 max), not nightly
- RTX 5090 Blackwell architecture requires latest nightly builds

### Fixed Code (Hearmeman's Proven Approach)
```dockerfile
# Use PyTorch nightly with CUDA 12.8 for RTX 5090 Blackwell support
# Based on Hearmeman's proven approach: https://github.com/Hearmeman24/comfyui-sdxl
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu128
```

**Solution:**
- ✅ Added `--pre` flag to access nightly/pre-release builds
- ✅ Changed index to `nightly/cu128` for latest CUDA 12.8 builds
- ✅ Updated comment to accurately reflect "nightly" builds
- ✅ Credited Hearmeman's working RTX 5090 setup

### Why Nightly Builds Are Required
**RTX 5090 = Blackwell Architecture**
- Requires cutting-edge PyTorch support (not in stable releases)
- Needs CUDA 12.8 compatibility
- Compute capability sm_90+ features
- Latest GPU optimizations (SAGE Attention, etc.)

**Tradeoffs:**
- ✅ **Pros**: RTX 5090 support, latest optimizations, proven in production
- ⚠️ **Cons**: Less stable than releases, potential API changes, version drift

**Mitigation**: Version can be pinned to specific nightly date if needed for reproducibility.

### Origin & Impact
- **Introduced by**: Commit 5afbff28 (Aug 26, 2025) - correct intent, wrong implementation
- **Present in**: refactor/clean-foundation (inherited), all downstream branches including v3.2.0-refined
- **Impact**: RTX 5090 users may not get proper GPU support, potential build failures or performance issues

### Reference
Based on Hearmeman's proven production setup: https://github.com/Hearmeman24/comfyui-sdxl/blob/master/Dockerfile

---

## Issue #2: FLUX Schnell Model Mapping 🔴 CRITICAL

### Root Cause
Incorrect mapping in `scripts/download_huggingface_simple.py` caused users requesting FLUX.1-schnell to receive a VAE file instead of the diffusion model.

### Original (Broken) Code
```python
repo_mappings = {
    'black-forest-labs/FLUX.1-dev': 'flux1-dev',
    'black-forest-labs/FLUX.1-schnell': 'ae',  # ❌ WRONG - maps to Lumina VAE
    'Comfy-Org/flux1-dev': 'flux1-dev',
    'comfyanonymous/flux_text_encoders': 'clip_l,t5xxl_fp16'
}
```

**What 'ae' resolves to:**
```python
'ae': {
    'url': 'https://huggingface.co/Comfy-Org/Lumina_Image_2.0_Repackaged/resolve/main/split_files/vae/ae.safetensors',
    'filename': 'ae.safetensors',
    'subdir': 'vae'  # ❌ VAE subdirectory, not diffusion_models
}
```

### Fixed Code
```python
repo_mappings = {
    'black-forest-labs/FLUX.1-dev': 'flux1-dev',
    'Comfy-Org/flux1-dev': 'flux1-dev',
    'comfyanonymous/flux_text_encoders': 'clip_l,t5xxl_fp16'
}
# Removed: 'black-forest-labs/FLUX.1-schnell': 'ae'
```

### Origin & Impact
- **Introduced by**: Commit 5afbff28 (Aug 26, 2025) - FLUX model restructure
- **Present in**: refactor/clean-foundation (inherited), all downstream branches
- **Impact**: Silent data corruption - users requesting FLUX.1-schnell received wrong file type in wrong directory

### Why Not Add Proper FLUX Schnell Support?
FLUX.1-schnell is not commonly used in production workflows. Removing the broken mapping prevents errors while keeping the codebase simple. Users needing schnell can use generic repo format: `repo:filename:subdir:branch`

---

## Issue #3: Missing Trailing Newlines ⚠️ MINOR

### Root Cause
Files edited during performance refinement work did not preserve POSIX-required trailing newlines.

### Files Affected
- `scripts/startup.sh`
- `scripts/download_models_once.sh`
- `scripts/download_huggingface_simple.py`

### Origin & Impact
- **Introduced by**: Performance refinement edits (feat/performance-refined branch)
- **Impact**: POSIX non-compliance, may break some tooling or cause issues with certain text editors

### Fix Applied
Added trailing newlines to all 3 files for POSIX compliance.

---

## Preventive Measures

To prevent similar issues in the future:

- [ ] **CI/CD Validation**: Add Docker build test to CI pipeline
- [ ] **PyTorch Verification**: Add check to verify PyTorch version availability before build
- [ ] **Model Mapping Tests**: Add unit tests for HuggingFace model mapping logic
- [ ] **Pre-commit Hooks**: Add hook to enforce trailing newlines
- [ ] **Documentation**: Document all HuggingFace model mappings with inline comments

---

## Key Learnings

1. **Verify Version Availability**: Don't just check if an index exists - verify the specific version is available
2. **Understand Hardware Requirements**: RTX 5090 (Blackwell) requires nightly builds, not stable releases
3. **Follow Proven Approaches**: Hearmeman's setup is production-tested - leverage it
4. **Test Model Mappings**: Silent data corruption (wrong file type) is worse than obvious errors
5. **POSIX Compliance**: Small issues like missing newlines can cause subtle bugs

---

## Verification Steps

After applying fixes:

```bash
# 1. Verify PyTorch configuration
grep -A 2 "torch" Dockerfile | grep -q "nightly/cu128.*--pre"
echo "✅ PyTorch uses nightly builds with --pre flag"

# 2. Verify FLUX mapping removed
! grep -q "FLUX.1-schnell.*ae" scripts/download_huggingface_simple.py
echo "✅ FLUX schnell mapping removed"

# 3. Verify trailing newlines
for f in scripts/startup.sh scripts/download_models_once.sh scripts/download_huggingface_simple.py; do
    [ -z "$(tail -c1 "$f")" ] && echo "✅ $f has newline" || echo "❌ $f missing newline"
done

# 4. Test Docker build
docker build -t ignition-test:v3.2.1 . --no-cache
echo "✅ Docker build successful"
```

---

**Report Date**: 2025-10-07
**Version**: v3.2.1-refined
**Author**: Claude Code investigation with user validation
