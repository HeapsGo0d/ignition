#!/bin/bash
# Privacy Lite - Telemetry Blocklist Setup
# Blocks known telemetry endpoints via /etc/hosts

set -euo pipefail

# Check if we can modify /etc/hosts (graceful failure)
if [[ ! -w /etc/hosts ]]; then
    echo "⚠️  Cannot modify /etc/hosts - skipping blocklist"
    exit 0
fi

echo "🔒 Setting up telemetry blocklist..."

# Backup original hosts file if not already backed up
if [[ ! -f /etc/hosts.backup ]]; then
    cp /etc/hosts /etc/hosts.backup
    echo "  • Backed up /etc/hosts"
fi

# Blocklist - telemetry and tracking domains
BLOCKLIST=(
    # CivitAI Analytics
    "analytics.civitai.com"
    "track.civitai.com"
    "telemetry.civitai.com"

    # Stability AI
    "api.stability.ai"
    "telemetry.stability.ai"

    # Replicate
    "replicate.com"
    "api.replicate.com"

    # Common Analytics
    "google-analytics.com"
    "googletagmanager.com"
    "segment.io"
    "segment.com"
    "amplitude.com"
    "mixpanel.com"
    "sentry.io"

    # Additional tracking services
    "hotjar.com"
    "fullstory.com"
    "logrocket.com"
)

# Add blocklist entries (IPv4 + IPv6)
for domain in "${BLOCKLIST[@]}"; do
    # Check IPv4 separately
    if ! grep -q "127.0.0.1 $domain" /etc/hosts 2>/dev/null; then
        echo "127.0.0.1 $domain" >> /etc/hosts
        echo "  • Added IPv4: $domain"
    fi

    # Check IPv6 separately (ensures upgrades work)
    if ! grep -q "::1 $domain" /etc/hosts 2>/dev/null; then
        echo "::1 $domain" >> /etc/hosts
        echo "  • Added IPv6: $domain"
    fi
done

echo "✅ Telemetry blocklist active (${#BLOCKLIST[@]} domains, IPv4 + IPv6)"