# Testing nginx Self-Healing (v3.2.5-refined)

## Quick Test Checklist

### 1. Check Startup Logs
SSH into pod and verify nginx self-healing worked:
```bash
ssh root@[pod-id]-ssh.proxy.runpod.net
tail -100 /tmp/ignition_startup.log | grep -A 20 "Starting nginx"
```

**Expected output:**
```
[INFO] 🚀 Starting nginx reverse proxy on port 8081...
[INFO]   → Serves pre-compressed frontend (80%+ size reduction)
[INFO]   → Backend API on port 8188 (still accessible)
[INFO]   • Detecting frontend path...
[INFO]   • Frontend: /opt/conda/lib/python3.XX/site-packages/comfyui_frontend_package/static
[INFO]   • Creating pre-compressed files... (or already exist)
[INFO]   • Generating nginx configuration...
[INFO] ✅ nginx started successfully
[INFO]   → Access ComfyUI: http://[pod-id]-8081.proxy.runpod.net
[INFO]   → Performance: ~15-25s load (was ~167s)
```

### 2. Verify nginx Config Generated Correctly
```bash
cat /etc/nginx/sites-available/comfyui | head -5
```

**Should show:**
- Dynamically detected path (NOT hardcoded `/opt/conda/lib/python3.11/...`)
- Correct Python version for your container

### 3. Test Port 8081 (Optimized)
```bash
# Test health endpoint
curl -v http://127.0.0.1:8081/nginx-health

# Test main page
curl -I http://127.0.0.1:8081/

# Check response time (should be fast)
time curl -s http://127.0.0.1:8081/ > /dev/null
```

**Expected:**
- Health endpoint returns: `nginx operational`
- Main page returns: HTTP 200
- Load time: < 30 seconds first load, < 3 seconds cached

### 4. Browser Test - Port 8081
Open in browser: `http://[pod-id]-8081.proxy.runpod.net`

**Verify:**
- ✅ Page loads in 15-25 seconds (first load)
- ✅ Subsequent loads are instant (< 2s)
- ✅ Check browser DevTools → Network:
  - Assets should show `200 (from disk cache)` on reload
  - Compressed files (`.gz`) being served
  - Total size should be ~3MB, not 49MB

### 5. Browser Test - Port 8188 (Fallback)
Open in browser: `http://[pod-id]-8188.proxy.runpod.net`

**Verify:**
- ✅ Works (slower, but functional)
- ✅ Load time: 90-167 seconds
- ✅ Total size: ~49MB uncompressed

### 6. Verify .gz Files Created
```bash
# Find frontend path
FRONTEND_PATH=$(python3 -c "import comfyui_frontend_package; import importlib.resources; print(importlib.resources.files(comfyui_frontend_package) / 'static')")

# Count compressed files
find "$FRONTEND_PATH" -name "*.gz" | wc -l

# Should show 50+ .gz files
```

### 7. Test Self-Healing (Advanced)
Simulate missing config and restart:
```bash
# Remove nginx config
rm /etc/nginx/sites-available/comfyui

# Restart container or re-run startup
bash /workspace/scripts/startup.sh

# Should auto-regenerate config and work
```

## Success Criteria

✅ **Pass if ALL true:**
1. Startup logs show "Detecting frontend path" and correct path
2. nginx config generated with dynamic path (not hardcoded python3.11)
3. Port 8081 health endpoint works
4. Port 8081 loads in < 30 seconds
5. Browser DevTools shows compressed assets
6. 50+ .gz files exist in frontend path
7. Port 8188 still works as fallback

❌ **Fail if ANY true:**
1. nginx fails to start
2. Port 8081 not accessible
3. Hardcoded python3.11 path in config
4. No .gz files created
5. Load time not improved

## Quick One-Liner Test
```bash
ssh root@[pod-id]-ssh.proxy.runpod.net "
  echo '=== Nginx Status ===' && 
  pgrep nginx && 
  echo '=== Frontend Path ===' && 
  grep 'root' /etc/nginx/sites-available/comfyui | head -1 &&
  echo '=== Health Check ===' && 
  curl -s http://127.0.0.1:8081/nginx-health &&
  echo '=== .gz Count ===' &&
  find \$(python3 -c 'import comfyui_frontend_package; import importlib.resources; print(importlib.resources.files(comfyui_frontend_package) / \"static\")') -name '*.gz' 2>/dev/null | wc -l
"
```

## Troubleshooting

**If nginx didn't start:**
```bash
# Check what went wrong
tail -50 /tmp/ignition_startup.log | grep -A 10 "nginx"
nginx -t  # Test config
/var/log/nginx/comfyui_error.log  # Check errors
```

**If wrong path detected:**
```bash
# Manually check Python version
python3 --version
python3 -c "import comfyui_frontend_package; import importlib.resources; print(importlib.resources.files(comfyui_frontend_package) / 'static')"
```
