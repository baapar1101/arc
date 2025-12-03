#!/usr/bin/env bash
# Script to configure DNS and resolve pub.dev access issues

set -euo pipefail

echo "Checking and configuring DNS..."

# Check access to different DNS servers
check_dns() {
  local dns_server="$1"
  echo "Checking access to DNS server: $dns_server"
  if dig @"$dns_server" pub.dev +short +timeout=3 >/dev/null 2>&1; then
    echo "✓ DNS server $dns_server is accessible"
    return 0
  else
    echo "✗ DNS server $dns_server is not accessible"
    return 1
  fi
}

# List of usable DNS servers
DNS_SERVERS=(
  "8.8.8.8"           # Google DNS
  "1.1.1.1"           # Cloudflare DNS
  "208.67.222.222"    # OpenDNS
  "8.8.4.4"           # Google DNS (backup)
)

WORKING_DNS=""

# Find first working DNS server
for dns in "${DNS_SERVERS[@]}"; do
  if check_dns "$dns"; then
    WORKING_DNS="$dns"
    break
  fi
done

if [ -z "$WORKING_DNS" ]; then
  echo "❌ No accessible DNS server found!"
  echo "Please check your internet connection."
  exit 1
fi

echo ""
echo "✓ Accessible DNS server found: $WORKING_DNS"
echo ""

# Check current systemd-resolved status
if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
  echo "systemd-resolved is active. Configuring DNS server..."
  
  # Add DNS server to systemd-resolved
  sudo resolvectl dns || true
  echo "For permanent configuration, run the following commands:"
  echo "  sudo mkdir -p /etc/systemd/resolved.conf.d"
  echo "  echo -e '[Resolve]\nDNS=$WORKING_DNS' | sudo tee /etc/systemd/resolved.conf.d/dns_servers.conf"
  echo "  sudo systemctl restart systemd-resolved"
else
  echo "systemd-resolved is inactive."
fi

# Create temporary resolv.conf backup file
RESOLV_CONF_BACKUP="/tmp/resolv.conf.backup.$$"
if [ -f /etc/resolv.conf ]; then
  sudo cp /etc/resolv.conf "$RESOLV_CONF_BACKUP"
  echo "Backup of /etc/resolv.conf created: $RESOLV_CONF_BACKUP"
fi

echo ""
echo "For temporary DNS configuration (this session only):"
echo "  export DNS_SERVER='$WORKING_DNS'"
echo ""
echo "For permanent DNS configuration, you can use one of the following methods:"
echo ""
echo "Method 1: Using systemd-resolved (recommended)"
echo "  sudo mkdir -p /etc/systemd/resolved.conf.d"
echo "  echo -e '[Resolve]\nDNS=$WORKING_DNS\nFallbackDNS=8.8.4.4' | sudo tee /etc/systemd/resolved.conf.d/dns_servers.conf"
echo "  sudo systemctl restart systemd-resolved"
echo ""
echo "Method 2: Direct modification of /etc/resolv.conf (temporary)"
echo "  echo 'nameserver $WORKING_DNS' | sudo tee /etc/resolv.conf"
echo ""
echo "After configuring DNS, run the following commands to test:"
echo "  nslookup pub.dev"
echo "  curl -I https://pub.dev"

