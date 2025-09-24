#!/bin/bash
# Privacy Update Window - Temporary Allowlist for Updates
# Manages PRIV_ALLOW_UPDATES=1 functionality with proper tooling configuration

set -euo pipefail

# Configuration
PROXY_PORT="${PROXY_PORT:-8888}"
ALLOWLIST_FILE="/workspace/privacy/allowlist.txt"
TEMP_ALLOWLIST="/tmp/update-allowlist.txt"
GIT_CONFIG_BACKUP="/tmp/git-config-backup"

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
    echo -e "[$timestamp] [UPDATE-$level] $message"
}

# Add temporary domains to allowlist
add_update_domains() {
    log "INFO" "Adding temporary update domains to allowlist"

    # Create temporary allowlist with update domains
    cat > "$TEMP_ALLOWLIST" << 'EOF'
# Temporary Update Domains (PRIV_ALLOW_UPDATES=1)
github.com
api.github.com
objects.githubusercontent.com
raw.githubusercontent.com
codeload.github.com

# PyPI domains for package updates
pypi.org
*.pypi.org
files.pythonhosted.org
*.pythonhosted.org

EOF

    # If proxy is using privoxy, regenerate configuration with update domains
    if pgrep -f privoxy >/dev/null 2>&1; then
        log "INFO" "Regenerating privoxy configuration with update domains"
        # Kill and restart proxy with updated config
        if [[ -x "/workspace/scripts/minimal-proxy.sh" ]]; then
            PRIV_ALLOW_UPDATES=1 /workspace/scripts/minimal-proxy.sh stop
            sleep 1
            PRIV_ALLOW_UPDATES=1 /workspace/scripts/minimal-proxy.sh start
        fi
    fi

    log "INFO" "Update domains added successfully"
}

# Remove temporary domains from allowlist
remove_update_domains() {
    log "INFO" "Removing temporary update domains from allowlist"

    # Clean up temporary files
    rm -f "$TEMP_ALLOWLIST"

    # If proxy is using privoxy, regenerate configuration without update domains
    if pgrep -f privoxy >/dev/null 2>&1; then
        log "INFO" "Regenerating privoxy configuration without update domains"
        # Kill and restart proxy with standard config
        if [[ -x "/workspace/scripts/minimal-proxy.sh" ]]; then
            /workspace/scripts/minimal-proxy.sh stop
            sleep 1
            /workspace/scripts/minimal-proxy.sh start
        fi
    fi

    log "INFO" "Update domains removed successfully"
}

# Configure git to use proxy
configure_git_proxy() {
    log "INFO" "Configuring git to use proxy"

    # Backup existing git config
    mkdir -p "$(dirname "$GIT_CONFIG_BACKUP")"
    git config --global --list > "$GIT_CONFIG_BACKUP" 2>/dev/null || touch "$GIT_CONFIG_BACKUP"

    # Set proxy configuration
    git config --global http.proxy "http://127.0.0.1:$PROXY_PORT"
    git config --global https.proxy "http://127.0.0.1:$PROXY_PORT"

    log "INFO" "Git proxy configured: 127.0.0.1:$PROXY_PORT"
}

# Remove git proxy configuration
remove_git_proxy() {
    log "INFO" "Removing git proxy configuration"

    # Remove proxy settings
    git config --global --unset http.proxy 2>/dev/null || true
    git config --global --unset https.proxy 2>/dev/null || true

    # Note: We don't restore the full backup to avoid overwriting other changes
    log "INFO" "Git proxy configuration removed"
}

# Configure environment for pip and aria2
configure_update_env() {
    log "INFO" "Configuring update environment"

    # Set proxy environment variables
    export HTTP_PROXY="http://127.0.0.1:$PROXY_PORT"
    export HTTPS_PROXY="http://127.0.0.1:$PROXY_PORT"
    export ALL_PROXY="http://127.0.0.1:$PROXY_PORT"
    export NO_PROXY="127.0.0.1,localhost,::1"

    # pip configuration
    export PIP_DISABLE_PIP_VERSION_CHECK=1

    log "INFO" "Update environment configured"
    log "INFO" "  • HTTP_PROXY: $HTTP_PROXY"
    log "INFO" "  • HTTPS_PROXY: $HTTPS_PROXY"
    log "INFO" "  • ALL_PROXY: $ALL_PROXY"
    log "INFO" "  • PIP_DISABLE_PIP_VERSION_CHECK: $PIP_DISABLE_PIP_VERSION_CHECK"
}

# Test update connectivity
test_update_connectivity() {
    log "INFO" "Testing update connectivity"

    # Test GitHub
    if curl -s --proxy "127.0.0.1:$PROXY_PORT" --connect-timeout 5 https://api.github.com >/dev/null 2>&1; then
        log "INFO" "GitHub connectivity: ✓ WORKING"
    else
        log "WARN" "GitHub connectivity: ✗ FAILED"
    fi

    # Test PyPI
    if curl -s --proxy "127.0.0.1:$PROXY_PORT" --connect-timeout 5 https://pypi.org >/dev/null 2>&1; then
        log "INFO" "PyPI connectivity: ✓ WORKING"
    else
        log "WARN" "PyPI connectivity: ✗ FAILED"
    fi

    # Test git command
    if git ls-remote https://github.com/octocat/Hello-World.git >/dev/null 2>&1; then
        log "INFO" "Git command: ✓ WORKING"
    else
        log "WARN" "Git command: ✗ FAILED"
    fi
}

# Run a command in update window context
run_with_updates() {
    log "INFO" "Running command in update window: $@"

    # Check if we're already in an update window
    if [[ "${PRIV_ALLOW_UPDATES:-0}" == "1" ]]; then
        log "INFO" "Already in update window, executing command directly"
        exec "$@"
    fi

    # Start update window
    log "INFO" "Opening update window..."
    add_update_domains
    configure_git_proxy
    configure_update_env

    # Execute the command
    local exit_code=0
    "$@" || exit_code=$?

    # Clean up update window
    log "INFO" "Closing update window..."
    remove_git_proxy
    remove_update_domains

    return $exit_code
}

# Show update window status
show_status() {
    echo "=== Privacy Update Window Status ==="

    if [[ "${PRIV_ALLOW_UPDATES:-0}" == "1" ]]; then
        echo "Update window: ACTIVE"
    else
        echo "Update window: INACTIVE"
    fi

    echo ""
    echo "Git proxy configuration:"
    local git_proxy=$(git config --global --get http.proxy 2>/dev/null || echo "Not configured")
    echo "  http.proxy: $git_proxy"

    echo ""
    echo "Environment variables:"
    echo "  HTTP_PROXY: ${HTTP_PROXY:-Not set}"
    echo "  HTTPS_PROXY: ${HTTPS_PROXY:-Not set}"
    echo "  ALL_PROXY: ${ALL_PROXY:-Not set}"

    echo ""
    echo "Temporary allowlist:"
    if [[ -f "$TEMP_ALLOWLIST" ]]; then
        echo "  Status: EXISTS"
        echo "  Domains: $(wc -l < "$TEMP_ALLOWLIST") entries"
    else
        echo "  Status: NOT FOUND"
    fi

    echo ""
    echo "Proxy process:"
    if pgrep -f "privoxy\|tinyproxy" >/dev/null 2>&1; then
        echo "  Proxy: RUNNING"
        local proxy_pid=$(pgrep -f "privoxy\|tinyproxy" | head -1)
        echo "  PID: $proxy_pid"
    else
        echo "  Proxy: NOT RUNNING"
    fi
}

# Main update window management
case "${1:-status}" in
    "start")
        if [[ "${PRIVACY_BYPASS:-0}" == "1" ]]; then
            echo "⚠️⚠️⚠️ PRIVACY BYPASS ACTIVE - NO NETWORK PROTECTION ⚠️⚠️⚠️" | tee /dev/stderr
            echo "⚠️⚠️⚠️ ALL TELEMETRY AND TRACKING ENABLED ⚠️⚠️⚠️" | tee /dev/stderr
            log "WARN" "Privacy bypass active - update window not needed"
            exit 0
        fi

        add_update_domains
        configure_git_proxy
        configure_update_env
        test_update_connectivity
        log "INFO" "Update window opened - use 'stop' to close"
        ;;

    "stop")
        remove_git_proxy
        remove_update_domains
        log "INFO" "Update window closed"
        ;;

    "run")
        shift
        if [[ $# -eq 0 ]]; then
            log "ERROR" "No command specified for 'run'"
            exit 1
        fi
        run_with_updates "$@"
        ;;

    "test")
        test_update_connectivity
        ;;

    "status")
        show_status
        ;;

    "git")
        shift
        log "INFO" "Running git command in update window"
        run_with_updates git "$@"
        ;;

    "pip")
        shift
        log "INFO" "Running pip command in update window"
        run_with_updates python3 -m pip "$@"
        ;;

    *)
        echo "Usage: $0 {start|stop|run|test|status|git|pip}"
        echo "  start     - Open update window (add domains, configure tools)"
        echo "  stop      - Close update window (remove domains, clean config)"
        echo "  run CMD   - Run command in temporary update window"
        echo "  test      - Test update connectivity"
        echo "  status    - Show update window status"
        echo "  git ARGS  - Run git command in update window"
        echo "  pip ARGS  - Run pip command in update window"
        echo ""
        echo "Examples:"
        echo "  $0 git pull"
        echo "  $0 pip install requests"
        echo "  $0 run 'git clone https://github.com/user/repo.git'"
        exit 1
        ;;
esac