# Ignition Clean Privacy Refactor - Testing Guide

## Overview

This document provides comprehensive testing instructions for the clean architecture refactor of Ignition ComfyUI, including the incremental network privacy system.

## Architecture Changes

### Before vs After

| Component | Original | Clean Refactor |
|-----------|----------|----------------|
| **Dockerfile** | 108 lines, multi-stage | 89 lines, single-stage |
| **Startup Script** | 318 lines, integrated privacy | 264 lines, core ComfyUI only |
| **Privacy System** | Complex integrated system | Modular, phase-based approach |

### Clean Architecture Benefits

- ✅ **Modular Design**: Privacy system separate from core functionality
- ✅ **Testable Components**: Each phase independently testable
- ✅ **Simpler Debugging**: Clear separation of concerns
- ✅ **Incremental Implementation**: Build privacy features progressively

## Phase 1 Testing: Basic Network Blocking

### Prerequisites

```bash
# Must run as root for iptables
sudo su

# Ensure you're on the clean-privacy-refactor branch
git branch --show-current  # Should show: clean-privacy-refactor
```

### Test 1: Privacy System Status

```bash
# Test status command
./scripts/privacy-init.sh status

# Expected output:
# === Privacy System Status ===
# Phase: 1
# Block Telemetry: true
# Monitoring Only: false
```

### Test 2: Baseline Connectivity

Test that legitimate domains work BEFORE privacy rules:

```bash
# Should all return HTTP 200
curl -s --head --connect-timeout 3 https://civitai.com | head -2
curl -s --head --connect-timeout 3 https://huggingface.co | head -2
curl -s --head --connect-timeout 3 https://github.com | head -2
```

### Test 3: Telemetry Blocking

Test that privacy system actually blocks telemetry:

```bash
# Run comprehensive Phase 1 tests
sudo ./scripts/test-privacy-phase1.sh

# Expected: All tests should pass
# Tests include:
# - Privacy toggle functionality
# - Baseline connectivity
# - Status command functionality
# - Monitoring only mode
# - Telemetry domain blocking
# - iptables cleanup
```

### Test 4: Manual Blocking Verification

```bash
# Start privacy system
sudo ./scripts/privacy-init.sh start &
PRIVACY_PID=$!

# Wait for initialization
sleep 3

# Test blocked domains (should fail/timeout)
timeout 3 curl -v google-analytics.com  # Should fail
timeout 3 curl -v mixpanel.com          # Should fail
timeout 3 curl -v segment.io            # Should fail

# Test allowed domains (should work)
curl -s --head https://civitai.com | head -1    # Should succeed
curl -s --head https://huggingface.co | head -1 # Should succeed

# Cleanup
kill $PRIVACY_PID
```

### Test 5: Monitoring Only Mode

```bash
# Test monitoring mode (no blocking)
export MONITORING_ONLY="true"
sudo ./scripts/privacy-init.sh start &
PRIVACY_PID=$!

sleep 2

# In monitoring mode, even telemetry should work
curl -s --head http://google-analytics.com | head -1  # Should work

kill $PRIVACY_PID
unset MONITORING_ONLY
```

## Clean Architecture Testing

### Test 6: Clean Startup Script

```bash
# Test clean startup initialization (without full system start)
export PRIVACY_ENABLED="false"
export COMFYUI_PORT="8999"  # Use different port to avoid conflicts

# Test startup phases individually
./scripts/startup-clean.sh --help || echo "Script doesn't support --help yet"

# Check that startup script exists and is executable
ls -la scripts/startup-clean.sh
```

### Test 7: Dockerfile Build Test

```bash
# Test that clean Dockerfile builds successfully
docker build -t ignition-clean:test .

# Check image size (should be reasonable)
docker images ignition-clean:test

# Verify entrypoint
docker inspect ignition-clean:test | grep -A5 "Entrypoint"
```

## Integration Testing

### Test 8: Full System Integration

```bash
# Test complete system with privacy enabled
export PRIVACY_ENABLED="true"
export MONITORING_ONLY="true"  # Start with monitoring mode

# This would start the full system (run in container)
# docker run -p 8188:8188 -p 8080:8080 ignition-clean:test
```

## Privacy Phase Progression Testing

### Phase 1: Basic Telemetry Blocking ✅

Current implementation blocks common telemetry domains:
- google-analytics.com
- mixpanel.com
- segment.io
- facebook tracking
- etc.

**Validation**: Run `sudo ./scripts/test-privacy-phase1.sh`

### Phase 2: Smart Allowlisting (Future)

Will implement:
- CivitAI domain allowlisting (*.civitai.com)
- HuggingFace allowlisting (*.huggingface.co, *.hf.co)
- Essential services (DNS, NTP)

**Testing**: TBD

### Phase 3: Transparency & Logging (Future)

Will implement:
- Clear logging of blocked vs allowed connections
- Activity detection integration
- User-friendly status reporting

**Testing**: TBD

## Debugging

### Common Issues

1. **"Privacy tests require root privileges"**
   - Solution: Run tests with `sudo`

2. **"iptables command not found"**
   - Solution: Install iptables: `apt-get install iptables`

3. **Network connectivity issues**
   - Check baseline connectivity first
   - Verify DNS resolution: `dig civitai.com`

4. **Privacy rules persist after testing**
   - Manual cleanup: `sudo iptables -F OUTPUT`

### Debug Commands

```bash
# Check current iptables rules
sudo iptables -L OUTPUT -n --line-numbers

# View privacy system logs
tail -f /tmp/ignition_privacy.log

# Check process status
ps aux | grep privacy-init

# Test individual privacy phases
sudo PRIVACY_PHASE=1 ./scripts/privacy-init.sh start
```

## Success Criteria

- ✅ **Dockerfile**: Single-stage, <90 lines, builds successfully
- ✅ **Startup Script**: <270 lines, modular design
- ✅ **Privacy System**: Testable, toggle-able, phase-based
- ✅ **Network Blocking**: Verifiable blocking of telemetry domains
- ✅ **Model Downloads**: CivitAI/HuggingFace domains accessible
- ✅ **No Backdoors**: All code transparent and testable

## Next Steps

1. **Complete Phase 2**: Implement smart allowlisting
2. **Add Phase 3**: Transparency and logging
3. **Container Testing**: Full integration tests in Docker
4. **Performance Testing**: Measure startup time and resource usage
5. **Documentation**: Update README with new architecture

## Reference

- **Original Complex Branch**: `activity-aware-privacy`
- **Clean Refactor Branch**: `clean-privacy-refactor`
- **Reference Architecture**: [kodxana/comfyui-base](https://github.com/kodxana/comfyui-base)