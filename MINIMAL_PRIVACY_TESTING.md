# Minimal Privacy System Testing Guide

## Overview
This guide provides comprehensive testing commands for the "Big Red Switch" minimal privacy system implementation in Ignition v2.2.

## Test Environment Setup

```bash
# SSH into your container
ssh root@your-pod-ip

# Verify minimal privacy system is installed
ls -la /workspace/scripts/minimal-*
ls -la /workspace/privacy/
```

## Default Mode Testing (STRICT_MODE=0)

### Basic Functionality
```bash
# Check privacy system status
/workspace/scripts/minimal-proxy.sh status
/workspace/scripts/minimal-firewall.sh status
/workspace/scripts/privacy-logs.sh status

# Test that proxy is running but not enforcing
curl -I https://civitai.com
curl -I https://google.com

# Both should work, check logs for entries
tail -10 /workspace/logs/privacy/proxy.log
```

### Proxy Visibility Testing
```bash
# Test with explicit proxy environment (to see logs)
HTTP_PROXY=http://127.0.0.1:8888 HTTPS_PROXY=http://127.0.0.1:8888 curl -I https://civitai.com
HTTP_PROXY=http://127.0.0.1:8888 HTTPS_PROXY=http://127.0.0.1:8888 curl -I https://google.com

# Check that connections are logged
grep CONNECT /workspace/logs/privacy/proxy.log | tail -5
```

### Expected Results - Default Mode
- ✅ All connections work (civitai.com, google.com)
- ✅ Proxy logs show ALLOW entries when using proxy environment
- ✅ No firewall blocking (STRICT_MODE=0)
- ✅ HuggingFace/CivitAI downloads work normally

## Strict Mode Testing (STRICT_MODE=1)

### Setup Strict Mode
```bash
# Restart container with STRICT_MODE enabled
export STRICT_MODE=1

# Or test without restart (requires root)
STRICT_MODE=1 /workspace/scripts/minimal-firewall.sh start
STRICT_MODE=1 /workspace/scripts/minimal-proxy.sh stop && STRICT_MODE=1 /workspace/scripts/minimal-proxy.sh start
```

### Allowlist Testing
```bash
# These should work (in allowlist)
curl -I https://civitai.com
curl -I https://huggingface.co
curl -I https://files.civitai.com

# These should fail (not in allowlist)
curl -I https://google.com
curl -I https://facebook.com
curl -I https://twitter.com
```

### DNS Resolution Testing
```bash
# DNS should still work
nslookup google.com
dig civitai.com

# Check DNS resolver detection
/workspace/scripts/minimal-firewall.sh dns
```

### IPv6 Bypass Testing
```bash
# Verify IPv6 is disabled
cat /proc/sys/net/ipv6/conf/all/disable_ipv6
# Should output: 1

# Test IPv6 connection (should fail)
curl -6 -I https://google.com --connect-timeout 5 || echo "IPv6 blocked ✓"
```

### Expected Results - Strict Mode
- ✅ Allowlisted domains work (civitai.com, huggingface.co)
- ❌ Non-allowlisted domains fail (google.com, facebook.com)
- ✅ DNS resolution works
- ❌ IPv6 connections blocked
- ✅ Proxy logs show DENY entries for blocked domains

## Update Window Testing (PRIV_ALLOW_UPDATES=1)

### Basic Update Window
```bash
# Start update window
/workspace/scripts/privacy-update-window.sh start

# Test GitHub access (should work now)
curl -I https://github.com
curl -I https://api.github.com

# Test PyPI access (should work now)
curl -I https://pypi.org

# Check git configuration
git config --global --get http.proxy

# Stop update window
/workspace/scripts/privacy-update-window.sh stop

# Test that GitHub is blocked again
curl -I https://github.com --connect-timeout 5 || echo "GitHub blocked after update window ✓"
```

### Update Window Commands
```bash
# Run git commands in update window
/workspace/scripts/privacy-update-window.sh git --version
/workspace/scripts/privacy-update-window.sh git ls-remote https://github.com/octocat/Hello-World.git

# Run pip commands in update window
/workspace/scripts/privacy-update-window.sh pip --version
/workspace/scripts/privacy-update-window.sh pip list

# Run custom commands
/workspace/scripts/privacy-update-window.sh run "curl -I https://github.com"
```

### Expected Results - Update Window
- ✅ GitHub/PyPI accessible during update window
- ✅ Git commands work with proxy
- ✅ Pip commands work with proxy
- ❌ GitHub/PyPI blocked after window closes
- ✅ All update activity logged

## Break-Glass Testing (PRIVACY_BYPASS=1)

### Bypass Activation
```bash
# Restart container with bypass
export PRIVACY_BYPASS=1

# Or test bypass behavior
PRIVACY_BYPASS=1 /workspace/scripts/minimal-proxy.sh start
```

### Bypass Verification
```bash
# All connections should work without proxy
curl -I https://google.com
curl -I https://facebook.com
curl -I https://analytics.google.com

# Check that bypass warning is logged
grep "PRIVACY BYPASS ACTIVE" /tmp/ignition_startup.log
```

### Expected Results - Bypass Mode
- ✅ All connections work (no blocking)
- ✅ No proxy enforcement
- ✅ Loud warning in logs
- ⚠️ No network monitoring

## Log Analysis Testing

### Proxy Log Format
```bash
# Check proxy log format
head -10 /workspace/logs/privacy/proxy.log

# Expected format:
# 2025-09-23 10:15:23 [INFO] CONNECT huggingface.co:443 - ALLOW (allowlist)
# 2025-09-23 10:15:24 [DENY] CONNECT analytics.google.com:443 - BLOCK (strict_mode)
```

### Summary Generation
```bash
# Generate daily summary
/workspace/scripts/privacy-logs.sh summary

# Check summary format
cat /workspace/logs/privacy/summary-$(date +%Y%m%d).jsonl

# Expected JSONL format:
# {"ts":"2025-09-23T00:00:00Z","dst_host":"huggingface.co","action":"ALLOW","count":15}
# {"ts":"2025-09-23T00:00:00Z","dst_host":"analytics.google.com","action":"DENY","count":3}
```

### Log Rotation Testing
```bash
# Check log rotation
/workspace/scripts/privacy-logs.sh status

# Force rotation test (if log is large)
/workspace/scripts/privacy-logs.sh rotate

# Check rotated files
ls -la /workspace/logs/privacy/proxy.log.*
```

## Security Validation

### Process Security
```bash
# Check proxy binding (should only be localhost)
netstat -tlnp | grep :8888
# Should show: 127.0.0.1:8888, NOT 0.0.0.0:8888

# Check process user (ComfyUI should not run as root)
ps aux | grep -E "(python|comfy)" | head -5
```

### Firewall Rules
```bash
# Check iptables rules in STRICT_MODE
iptables -L OUTPUT -n --line-numbers

# Should show:
# - Default policy: DROP
# - Allow loopback
# - Allow DNS to resolver IP
# - Allow proxy port
```

### NO_PROXY Healthcheck
```bash
# Verify healthcheck doesn't pollute logs
curl -f http://127.0.0.1:8188/

# Check that healthcheck doesn't appear in proxy logs
grep "127.0.0.1:8188" /workspace/logs/privacy/proxy.log || echo "Healthcheck not logged ✓"
```

## Performance Testing

### Connection Speed
```bash
# Test direct vs proxy speed
time curl -I https://civitai.com

# Test with explicit proxy
time HTTP_PROXY=http://127.0.0.1:8888 curl -I https://civitai.com

# Both should be similar (minimal proxy overhead)
```

### Log File Size
```bash
# Check log growth
ls -lah /workspace/logs/privacy/proxy.log

# Monitor log growth during testing
watch -n 5 "wc -l /workspace/logs/privacy/proxy.log"
```

## Troubleshooting Commands

### Debug Proxy Issues
```bash
# Check proxy process
ps aux | grep -E "(privoxy|tinyproxy)"

# Test proxy directly
curl --proxy 127.0.0.1:8888 -I http://httpbin.org/ip

# Check proxy configuration
cat /workspace/privacy/config/privoxy.conf 2>/dev/null || echo "Using tinyproxy"
```

### Debug Firewall Issues
```bash
# Check IPv6 status
cat /proc/sys/net/ipv6/conf/all/disable_ipv6

# Check DNS resolver
cat /etc/resolv.conf
/workspace/scripts/minimal-firewall.sh dns

# Test connectivity
/workspace/scripts/minimal-firewall.sh test
```

### Debug Log Issues
```bash
# Check log permissions
ls -la /workspace/logs/privacy/

# Test log writing
echo "test" >> /workspace/logs/privacy/proxy.log

# Check disk space
df -h /workspace
```

## Final Acceptance Checklist

Run this complete test sequence to verify all functionality:

```bash
#!/bin/bash
echo "=== Minimal Privacy System Acceptance Test ==="

# Test 1: Default Mode
echo "1. Testing default mode..."
curl -s -I https://civitai.com >/dev/null && echo "  ✅ CivitAI accessible"
curl -s -I https://google.com >/dev/null && echo "  ✅ Google accessible"

# Test 2: Strict Mode (if enabled)
if [[ "${STRICT_MODE:-0}" == "1" ]]; then
    echo "2. Testing strict mode..."
    curl -s -I https://civitai.com >/dev/null && echo "  ✅ CivitAI allowed" || echo "  ❌ CivitAI blocked"
    curl -s -I https://google.com --connect-timeout 3 >/dev/null && echo "  ❌ Google allowed" || echo "  ✅ Google blocked"
fi

# Test 3: Logs
echo "3. Testing logs..."
[[ -f /workspace/logs/privacy/proxy.log ]] && echo "  ✅ Proxy log exists" || echo "  ❌ Proxy log missing"

# Test 4: Security
echo "4. Testing security..."
netstat -tln | grep 127.0.0.1:8888 >/dev/null && echo "  ✅ Proxy bound to loopback" || echo "  ❌ Proxy binding issue"

# Test 5: IPv6
echo "5. Testing IPv6..."
[[ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)" == "1" ]] && echo "  ✅ IPv6 disabled" || echo "  ⚠️ IPv6 enabled"

echo "=== Test Complete ==="
```

## Common Issues & Solutions

### Issue: Proxy not starting
```bash
# Check available proxy software
which privoxy tinyproxy

# Check port conflicts
netstat -tln | grep :8888

# Check logs
tail /workspace/logs/privacy/proxy.log
```

### Issue: STRICT_MODE not blocking
```bash
# Check iptables rules
iptables -L OUTPUT

# Verify DNS resolver
/workspace/scripts/minimal-firewall.sh dns

# Test direct connection bypass
curl -s --interface eth0 -I https://google.com || echo "Properly blocked"
```

### Issue: Update window not working
```bash
# Check git configuration
git config --global --list | grep proxy

# Test proxy connectivity
curl --proxy 127.0.0.1:8888 -I https://github.com

# Check allowlist
cat /workspace/privacy/allowlist.txt
```

This testing guide ensures comprehensive validation of all minimal privacy system functionality.