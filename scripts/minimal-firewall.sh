#!/bin/bash
# Minimal Privacy Firewall - STRICT_MODE Network Controls
# Implements fail-closed networking with dynamic DNS resolver detection

set -euo pipefail

# Configuration
PROXY_PORT="${PROXY_PORT:-8888}"

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
    echo -e "[$timestamp] [FIREWALL-$level] $message"
}

# Disable IPv6 cleanly in container
disable_ipv6() {
    log "INFO" "Disabling IPv6 to prevent bypass"

    # Disable IPv6 via sysctl (cleanest approach)
    if [[ -w /proc/sys/net/ipv6/conf/all/disable_ipv6 ]]; then
        echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
        echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6
        log "INFO" "IPv6 disabled via sysctl"
    else
        log "WARN" "Cannot disable IPv6 via sysctl (not running as root?)"
    fi

    # Also disable IPv6 in lo interface specifically
    if [[ -w /proc/sys/net/ipv6/conf/lo/disable_ipv6 ]]; then
        echo 1 > /proc/sys/net/ipv6/conf/lo/disable_ipv6
    fi
}

# Get dynamic DNS resolver IP from /etc/resolv.conf
get_dns_resolver() {
    local resolver_ip=""

    # Extract first nameserver IP from resolv.conf
    if [[ -f /etc/resolv.conf ]]; then
        resolver_ip=$(grep -E '^nameserver' /etc/resolv.conf | head -1 | awk '{print $2}')
    fi

    # Fallback to common container DNS
    if [[ -z "$resolver_ip" ]]; then
        log "WARN" "No DNS resolver found in /etc/resolv.conf, using fallback"
        resolver_ip="8.8.8.8"  # Google DNS as fallback
    fi

    log "INFO" "Using DNS resolver: $resolver_ip"
    echo "$resolver_ip"
}

# Apply STRICT_MODE iptables rules
apply_strict_rules() {
    log "INFO" "Applying STRICT_MODE iptables rules (deny-by-default)"

    # Flush existing OUTPUT rules
    iptables -F OUTPUT 2>/dev/null || true

    # Default policy: DROP all outbound
    iptables -P OUTPUT DROP

    # Allow loopback traffic (essential for container operation)
    iptables -A OUTPUT -o lo -j ACCEPT

    # Get DNS resolver IP dynamically
    local dns_resolver=$(get_dns_resolver)

    # Allow DNS queries to resolver (UDP and TCP port 53)
    iptables -A OUTPUT -p udp -d "$dns_resolver" --dport 53 -j ACCEPT
    iptables -A OUTPUT -p tcp -d "$dns_resolver" --dport 53 -j ACCEPT
    log "INFO" "Allowed DNS queries to $dns_resolver"

    # Allow connections to proxy port on loopback (proxy communication)
    iptables -A OUTPUT -p tcp -d 127.0.0.1 --dport "$PROXY_PORT" -j ACCEPT
    log "INFO" "Allowed proxy connections to 127.0.0.1:$PROXY_PORT"

    # Allow established and related connections (return traffic)
    iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # In STRICT_MODE, all other traffic is denied by default policy
    log "INFO" "STRICT_MODE rules applied - deny-by-default active"
}

# Remove firewall rules (for cleanup or bypass)
remove_rules() {
    log "INFO" "Removing iptables rules"

    # Reset to default ACCEPT policy
    iptables -P OUTPUT ACCEPT 2>/dev/null || true

    # Flush OUTPUT chain
    iptables -F OUTPUT 2>/dev/null || true

    log "INFO" "Firewall rules removed"
}

# Show current firewall status
show_status() {
    log "INFO" "Current firewall status:"

    echo "IPv6 status:"
    if [[ -r /proc/sys/net/ipv6/conf/all/disable_ipv6 ]]; then
        local ipv6_disabled=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)
        if [[ "$ipv6_disabled" == "1" ]]; then
            echo "  IPv6: DISABLED ✓"
        else
            echo "  IPv6: ENABLED (potential bypass risk)"
        fi
    else
        echo "  IPv6: Status unknown"
    fi

    echo ""
    echo "Iptables OUTPUT policy:"
    iptables -L OUTPUT -n --line-numbers 2>/dev/null || echo "  Cannot read iptables rules"

    echo ""
    echo "DNS resolver:"
    local resolver=$(get_dns_resolver)
    echo "  Resolver IP: $resolver"

    echo ""
    echo "Proxy port status:"
    if netstat -tln 2>/dev/null | grep -q ":$PROXY_PORT "; then
        echo "  Proxy port $PROXY_PORT: LISTENING ✓"
    else
        echo "  Proxy port $PROXY_PORT: NOT LISTENING"
    fi
}

# Test network connectivity
test_connectivity() {
    log "INFO" "Testing network connectivity"

    # Test DNS resolution
    if nslookup google.com >/dev/null 2>&1; then
        log "INFO" "DNS resolution: WORKING"
    else
        log "WARN" "DNS resolution: FAILED"
    fi

    # Test proxy connectivity
    if curl -s --proxy "127.0.0.1:$PROXY_PORT" --connect-timeout 5 http://httpbin.org/ip >/dev/null 2>&1; then
        log "INFO" "Proxy connectivity: WORKING"
    else
        log "WARN" "Proxy connectivity: FAILED"
    fi

    # Test direct connectivity (should fail in STRICT_MODE)
    if [[ "${STRICT_MODE:-0}" == "1" ]]; then
        if curl -s --connect-timeout 3 http://google.com >/dev/null 2>&1; then
            log "WARN" "Direct connectivity: WORKING (bypass detected!)"
        else
            log "INFO" "Direct connectivity: BLOCKED (STRICT_MODE working)"
        fi
    fi
}

# Main firewall management
case "${1:-start}" in
    "start")
        if [[ "${PRIVACY_BYPASS:-0}" == "1" ]]; then
            log "WARN" "Privacy bypass active - skipping firewall rules"
            exit 0
        fi

        if [[ "${STRICT_MODE:-0}" != "1" ]]; then
            log "INFO" "STRICT_MODE disabled - no firewall rules applied"
            exit 0
        fi

        log "INFO" "Starting minimal privacy firewall (STRICT_MODE)"

        # Disable IPv6 first (before applying rules)
        disable_ipv6

        # Apply strict firewall rules
        apply_strict_rules

        log "INFO" "Firewall setup complete"
        ;;

    "stop")
        remove_rules
        ;;

    "status")
        show_status
        ;;

    "test")
        test_connectivity
        ;;

    "dns")
        get_dns_resolver
        ;;

    *)
        echo "Usage: $0 {start|stop|status|test|dns}"
        echo "  start  - Apply STRICT_MODE firewall rules"
        echo "  stop   - Remove firewall rules"
        echo "  status - Show current firewall status"
        echo "  test   - Test network connectivity"
        echo "  dns    - Show DNS resolver IP"
        exit 1
        ;;
esac