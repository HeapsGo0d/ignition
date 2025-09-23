# Privacy Log Analysis Commands

## Quick Reference Commands

### View Recent Outbound Attempts
```bash
# Show last 20 connection attempts
/workspace/scripts/privacy-logs.sh recent

# Show last 50 connection attempts
/workspace/scripts/privacy-logs.sh recent 50

# Show raw proxy log (last 20 lines)
tail -20 /workspace/logs/privacy/proxy.log
```

### Search for Specific Domains
```bash
# Find all attempts to a specific domain
grep "google.com" /workspace/logs/privacy/proxy.log

# Find all CONNECT attempts (HTTPS connections)
grep "CONNECT" /workspace/logs/privacy/proxy.log

# Find all GET/POST attempts (HTTP connections)
grep -E "(GET|POST)" /workspace/logs/privacy/proxy.log
```

### Analyze Connection Patterns
```bash
# Count unique domains contacted
grep "CONNECT\|GET\|POST" /workspace/logs/privacy/proxy.log | \
  awk '{print $4}' | cut -d: -f1 | sort | uniq -c | sort -nr

# Show most frequently contacted domains
grep "CONNECT" /workspace/logs/privacy/proxy.log | \
  awk '{print $4}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -10

# Find blocked/denied attempts
grep -i "deny\|block" /workspace/logs/privacy/proxy.log
```

### Daily/Historical Analysis
```bash
# Generate summary for today
/workspace/scripts/privacy-logs.sh summary

# View today's summary
/workspace/scripts/privacy-logs.sh show

# View specific date summary (YYYYMMDD format)
/workspace/scripts/privacy-logs.sh show 20250923

# List all available summary dates
ls /workspace/logs/privacy/summary-*.jsonl | sed 's/.*summary-//' | sed 's/.jsonl$//'
```

### Real-time Monitoring
```bash
# Watch live connection attempts
tail -f /workspace/logs/privacy/proxy.log

# Watch for specific domain attempts
tail -f /workspace/logs/privacy/proxy.log | grep "google.com"

# Watch for blocked attempts only
tail -f /workspace/logs/privacy/proxy.log | grep -i "deny\|block"
```

### System Status Commands
```bash
# Check proxy and log system status
/workspace/scripts/privacy-logs.sh status

# Check firewall status and enforcement mode
/workspace/scripts/minimal-firewall.sh status

# Check proxy status
/workspace/scripts/minimal-proxy.sh status

# Show current enforcement mode
cat /tmp/privacy_enforcement_mode 2>/dev/null || echo "Not set"
```

### Log File Locations
```bash
# Main proxy log (raw connection data)
/workspace/logs/privacy/proxy.log

# Daily summaries (JSONL format)
/workspace/logs/privacy/summary-YYYYMMDD.jsonl

# Startup logs (system initialization)
/tmp/ignition_startup.log

# Privacy system enforcement mode
/tmp/privacy_enforcement_mode
```

### Advanced Analysis Examples
```bash
# Find all unique IPs contacted
grep "CONNECT" /workspace/logs/privacy/proxy.log | \
  awk '{print $4}' | cut -d: -f1 | \
  xargs -I {} dig +short {} | grep -E '^[0-9]+\.' | sort -u

# Count connections per hour
grep "CONNECT" /workspace/logs/privacy/proxy.log | \
  cut -d' ' -f1-2 | cut -d: -f1-2 | sort | uniq -c

# Find suspicious or unexpected domains
grep "CONNECT" /workspace/logs/privacy/proxy.log | \
  awk '{print $4}' | cut -d: -f1 | \
  grep -v -E "(huggingface|civitai|github|pypi)" | sort -u
```

### JSON Summary Analysis
```bash
# View summary data with jq (if available)
cat /workspace/logs/privacy/summary-$(date +%Y%m%d).jsonl | jq .

# Count total connections by action
cat /workspace/logs/privacy/summary-$(date +%Y%m%d).jsonl | \
  jq -r '.action' | sort | uniq -c

# Show top domains by connection count
cat /workspace/logs/privacy/summary-$(date +%Y%m%d).jsonl | \
  jq -r '"\(.count) \(.dst_host)"' | sort -nr
```

### Troubleshooting Commands
```bash
# Check if proxy is logging properly
ls -la /workspace/logs/privacy/proxy.log
echo "test" | nc 127.0.0.1 8888 # Should show connection attempt

# Verify log rotation is working
/workspace/scripts/privacy-logs.sh rotate

# Check log disk usage
du -h /workspace/logs/privacy/

# Test summary generation
rm -f /workspace/logs/privacy/summary-$(date +%Y%m%d).jsonl
/workspace/scripts/privacy-logs.sh summary
cat /workspace/logs/privacy/summary-$(date +%Y%m%d).jsonl
```

## Log Format Reference

### Proxy Log Format
```
2025-09-23 10:15:23.456 THREAD_ID Header: scan: CONNECT domain.com:443 HTTP/1.1
2025-09-23 10:15:23.456 THREAD_ID Request: domain.com:443/
```

### Summary JSONL Format
```json
{"ts":"2025-09-23T00:00:00Z","dst_host":"huggingface.co","action":"ALLOW","count":15}
{"ts":"2025-09-23T00:00:00Z","dst_host":"analytics.google.com","action":"DENY","count":3}
```

### Startup Banner Format
```
🛡️ STRICT_MODE=1 ENFORCEMENT=kernel PROXY=127.0.0.1:8888 ALLOWLIST=5
```