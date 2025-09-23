#!/bin/bash
# Minimal Privacy Proxy - "Big Red Switch" Implementation
# Provides observability by default, enforcement on-demand

set -euo pipefail

# Configuration
PROXY_PORT="${PROXY_PORT:-8888}"
ALLOWLIST_FILE="/workspace/privacy/allowlist.txt"
PROXY_LOG="/workspace/logs/privacy/proxy.log"
PROXY_CONFIG_DIR="/workspace/privacy/config"
PRIVOXY_CONFIG="$PROXY_CONFIG_DIR/privoxy.conf"
TINYPROXY_CONFIG="$PROXY_CONFIG_DIR/tinyproxy.conf"

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] [PROXY-$level] $message"
}

# Create proxy configuration directory
mkdir -p "$PROXY_CONFIG_DIR"

# Check if privacy is bypassed
check_bypass() {
    if [[ "${PRIVACY_BYPASS:-0}" == "1" ]]; then
        log "WARN" "⚠️ PRIVACY BYPASS ACTIVE - ALL NETWORK MONITORING DISABLED"
        return 0
    fi
    return 1
}

# Create privoxy configuration (preferred for reliable CONNECT logging)
create_privoxy_config() {
    log "INFO" "Creating privoxy configuration"

    cat > "$PRIVOXY_CONFIG" << EOF
# Minimal Privacy Privoxy Configuration
# Bind only to loopback for security
listen-address 127.0.0.1:$PROXY_PORT

# Enable logging for observability
logfile $PROXY_LOG
logdir /workspace/logs/privacy

# Log all requests (hostname logging for HTTPS CONNECT)
debug 1     # Log connections
debug 4     # Log I/O
debug 8     # Log headers

# No content filtering (logging only by default)
actionsfile /dev/null
filterfile /dev/null

# Trust all certificates (we're not doing MITM)
+set-image-blocker{blank}

EOF

    # Add STRICT_MODE enforcement if enabled
    if [[ "${STRICT_MODE:-0}" == "1" ]]; then
        log "INFO" "STRICT_MODE enabled - adding allowlist enforcement"
        cat >> "$PRIVOXY_CONFIG" << EOF

# STRICT_MODE: Allowlist enforcement
actionsfile /workspace/privacy/config/privoxy-actions.conf
EOF
        create_privoxy_actions
    fi
}

# Create privoxy actions file for STRICT_MODE
create_privoxy_actions() {
    local actions_file="$PROXY_CONFIG_DIR/privoxy-actions.conf"

    log "INFO" "Creating privoxy allowlist actions"

    cat > "$actions_file" << 'EOF'
# Privoxy Actions for STRICT_MODE Enforcement
#
# Default: DENY all connections
{ +block{DENIED: Not in allowlist} }
/

# Allow localhost and loopback
{ -block }
127.0.0.1
localhost
::1

EOF

    # Add allowlist domains
    if [[ -f "$ALLOWLIST_FILE" ]]; then
        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ "$line" =~ ^#.*$ ]] && continue
            [[ -z "$line" ]] && continue

            # Convert wildcards to privoxy format
            local domain=$(echo "$line" | sed 's/\*/.*/g')
            echo "{ -block }" >> "$actions_file"
            echo "$domain" >> "$actions_file"
            echo "" >> "$actions_file"
        done < "$ALLOWLIST_FILE"
    fi

    # Add update domains if PRIV_ALLOW_UPDATES is enabled
    if [[ "${PRIV_ALLOW_UPDATES:-0}" == "1" ]]; then
        log "INFO" "Adding temporary update domains to allowlist"
        cat >> "$actions_file" << 'EOF'
# Temporary update domains (PRIV_ALLOW_UPDATES=1)
{ -block }
github.com
api.github.com
objects.githubusercontent.com
pypi.org
.*pythonhosted.org

EOF
    fi
}

# Create tinyproxy configuration (fallback)
create_tinyproxy_config() {
    log "INFO" "Creating tinyproxy configuration"

    cat > "$TINYPROXY_CONFIG" << EOF
# Minimal Privacy Tinyproxy Configuration
Port $PROXY_PORT
Listen 127.0.0.1

# Logging configuration
LogFile $PROXY_LOG
LogLevel Info

# Security: No upstream, no filtering by default
PidFile /tmp/tinyproxy.pid
MaxClients 100
MinSpareServers 2
MaxSpareServers 8
StartServers 4

# No access restrictions by default (logging only)
# Allow 127.0.0.1 for local access
Allow 127.0.0.1

EOF

    # Add STRICT_MODE filtering if enabled
    if [[ "${STRICT_MODE:-0}" == "1" ]]; then
        log "WARN" "tinyproxy STRICT_MODE has limited allowlist support"
        log "INFO" "Consider using privoxy for better STRICT_MODE enforcement"

        # Basic filtering (limited compared to privoxy)
        cat >> "$TINYPROXY_CONFIG" << EOF

# STRICT_MODE: Basic filtering (limited capabilities)
FilterDefaultDeny Yes
FilterURLs On

EOF
    fi
}

# Start privoxy proxy
start_privoxy() {
    log "INFO" "Starting privoxy proxy on 127.0.0.1:$PROXY_PORT"

    # Test configuration
    if ! privoxy --config-test "$PRIVOXY_CONFIG" >/dev/null 2>&1; then
        log "ERROR" "privoxy configuration test failed"
        return 1
    fi

    # Start privoxy
    privoxy --no-daemon "$PRIVOXY_CONFIG" &
    local proxy_pid=$!

    # Wait for proxy to start
    sleep 2

    # Verify proxy is listening
    if ! netstat -tln | grep -q ":$PROXY_PORT "; then
        log "ERROR" "privoxy failed to bind to port $PROXY_PORT"
        kill $proxy_pid 2>/dev/null || true
        return 1
    fi

    log "INFO" "privoxy started successfully (PID: $proxy_pid)"
    echo $proxy_pid > /tmp/proxy.pid
    return 0
}

# Start tinyproxy proxy (fallback)
start_tinyproxy() {
    log "INFO" "Starting tinyproxy proxy on 127.0.0.1:$PROXY_PORT"

    # Start tinyproxy
    tinyproxy -c "$TINYPROXY_CONFIG" -d &
    local proxy_pid=$!

    # Wait for proxy to start
    sleep 2

    # Verify proxy is listening
    if ! netstat -tln | grep -q ":$PROXY_PORT "; then
        log "ERROR" "tinyproxy failed to bind to port $PROXY_PORT"
        kill $proxy_pid 2>/dev/null || true
        return 1
    fi

    log "INFO" "tinyproxy started successfully (PID: $proxy_pid)"
    echo $proxy_pid > /tmp/proxy.pid
    return 0
}

# Stop proxy
stop_proxy() {
    if [[ -f /tmp/proxy.pid ]]; then
        local proxy_pid=$(cat /tmp/proxy.pid)
        log "INFO" "Stopping proxy (PID: $proxy_pid)"
        kill $proxy_pid 2>/dev/null || true
        rm -f /tmp/proxy.pid
    fi
}

# Test proxy functionality
test_proxy() {
    log "INFO" "Testing proxy functionality"

    # Test that proxy is responding
    if ! curl -s --proxy "127.0.0.1:$PROXY_PORT" --connect-timeout 5 http://httpbin.org/ip >/dev/null 2>&1; then
        log "WARN" "Proxy connectivity test failed"
        return 1
    fi

    log "INFO" "Proxy connectivity test passed"
    return 0
}

# Main proxy management
case "${1:-start}" in
    "start")
        if check_bypass; then
            log "WARN" "Privacy bypass active - skipping proxy startup"
            exit 0
        fi

        log "INFO" "Starting minimal privacy proxy system"
        log "INFO" "STRICT_MODE: ${STRICT_MODE:-0}, PROXY_PORT: $PROXY_PORT"

        # Ensure log directory exists
        mkdir -p "$(dirname "$PROXY_LOG")"

        # Try privoxy first (preferred for reliable logging)
        if command -v privoxy >/dev/null 2>&1; then
            create_privoxy_config
            if start_privoxy; then
                log "INFO" "Using privoxy for proxy service"
                test_proxy || log "WARN" "Proxy test failed but continuing"
                exit 0
            else
                log "WARN" "privoxy startup failed, trying tinyproxy"
            fi
        else
            log "WARN" "privoxy not available, trying tinyproxy"
        fi

        # Fallback to tinyproxy
        if command -v tinyproxy >/dev/null 2>&1; then
            create_tinyproxy_config
            if start_tinyproxy; then
                log "INFO" "Using tinyproxy for proxy service"
                test_proxy || log "WARN" "Proxy test failed but continuing"
                exit 0
            else
                log "ERROR" "tinyproxy startup failed"
            fi
        else
            log "ERROR" "No proxy software available (privoxy/tinyproxy)"
        fi

        log "ERROR" "Failed to start any proxy service"
        exit 1
        ;;

    "stop")
        stop_proxy
        ;;

    "status")
        if [[ -f /tmp/proxy.pid ]]; then
            proxy_pid=$(cat /tmp/proxy.pid)
            if kill -0 $proxy_pid 2>/dev/null; then
                log "INFO" "Proxy is running (PID: $proxy_pid)"
                netstat -tln | grep ":$PROXY_PORT " || log "WARN" "Port not listening"
            else
                log "WARN" "Proxy PID file exists but process not running"
            fi
        else
            log "INFO" "Proxy is not running"
        fi
        ;;

    "test")
        test_proxy
        ;;

    *)
        echo "Usage: $0 {start|stop|status|test}"
        echo "  start  - Start the minimal privacy proxy"
        echo "  stop   - Stop the proxy"
        echo "  status - Check proxy status"
        echo "  test   - Test proxy connectivity"
        exit 1
        ;;
esac