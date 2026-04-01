#!/bin/bash
# init-firewall.sh - Network firewall for Claude Code container
# Based on official anthropics/claude-code devcontainer
# Whitelists only essential domains, blocks everything else

set -e

echo "🔥 Initializing firewall..."

# Check if iptables is available
if ! command -v iptables &>/dev/null; then
	echo "⚠️  iptables not found, skipping firewall setup"
	echo "   Container will have unrestricted network access"
	exit 0
fi

# Check if we have CAP_NET_ADMIN
if ! iptables -L &>/dev/null 2>&1; then
	echo "⚠️  No NET_ADMIN capability, skipping firewall setup"
	echo "   Container will have unrestricted network access"
	exit 0
fi

# Create ipset for allowed IPs
ipset create allowed_ips hash:ip -exist 2>/dev/null || true
ipset flush allowed_ips 2>/dev/null || true

# Allowed domains - Claude Code essentials
ALLOWED_DOMAINS=(
	"api.anthropic.com"
	"statsig.anthropic.com"
	"sentry.io"
	"statsig.com"
	"registry.npmjs.org"
	"github.com"
	"api.github.com"
	"objects.githubusercontent.com"
	"raw.githubusercontent.com"
	"pypi.org"
	"files.pythonhosted.org"
	"api.inhouse-flugel.freee.co.jp"
	# golang
	"proxy.golang.org"
	"storage.googleapis.com"
	"sum.golang.org"
	"rubygems.pkg.github.com"
)

# Resolve and add IPs
for domain in "${ALLOWED_DOMAINS[@]}"; do
	echo "  Resolving: $domain"
	ips=$(dig +short "$domain" A 2>/dev/null | grep -E '^[0-9]+\.' || true)
	for ip in $ips; do
		ipset add allowed_ips "$ip" -exist 2>/dev/null || true
	done
done

# Flush existing rules
iptables -F OUTPUT 2>/dev/null || true

# Allow loopback
iptables -A OUTPUT -o lo -j ACCEPT

# Allow established connections
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow DNS (UDP/TCP port 53)
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Allow SSH
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT

# Allow whitelisted IPs
iptables -A OUTPUT -m set --match-set allowed_ips dst -j ACCEPT

# Allow connections to host.containers.internal (Podman) / host.docker.internal (Docker)
# For MCP servers and local services
iptables -A OUTPUT -d 10.0.0.0/8 -j ACCEPT
iptables -A OUTPUT -d 172.16.0.0/12 -j ACCEPT
iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT
iptables -A OUTPUT -d 169.254.0.0/16 -j ACCEPT

# Default deny all other outbound
iptables -A OUTPUT -j DROP

# IPv6: block all outbound (best effort, may not be available)
if command -v ip6tables &>/dev/null; then
	ip6tables -F OUTPUT 2>/dev/null || true
	ip6tables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || true
	ip6tables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
	ip6tables -A OUTPUT -j DROP 2>/dev/null || true
fi

echo "✅ Firewall active - only whitelisted domains allowed"
echo "   Allowed: ${ALLOWED_DOMAINS[*]}"
