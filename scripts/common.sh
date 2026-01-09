#!/bin/bash
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$ROOT_DIR/scripts}"

SSL_DIR="${SSL_DIR:-/etc/ssl/cloudflare-origin}"
SSL_CERT_DIR="${SSL_CERT_DIR:-$SSL_DIR/certs}"
SSL_KEY_DIR="${SSL_KEY_DIR:-$SSL_DIR/keys}"
APACHE_DIR="${APACHE_DIR:-/etc/apache2/sites-available}"
WORDPRESS_ROOT="${WORDPRESS_ROOT:-/var/www/html/wordpress}"
TEMPLATE_DIR="${TEMPLATE_DIR:-$ROOT_DIR/templates}"

log() { echo "[$(date +%H:%M:%S)] $*"; }
err() { echo "[$(date +%H:%M:%S)] ERROR: $*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || err "Missing command: $1"; }

# priv() is a thin wrapper for running commands with sudo.
# Set SUDO_BIN to an empty string to disable sudo while keeping the call pattern.
SUDO_BIN="${SUDO_BIN-sudo}"
#SUDO_BIN=""
priv() {
    if [ -n "$SUDO_BIN" ]; then
        $SUDO_BIN "$@"
        return
    fi
    if [ "${1:-}" = "-u" ]; then
        shift 2
    fi
    "$@"
}

tolower() { echo "$1" | tr '[:upper:]' '[:lower:]'; }
safe_name() { echo "$1" | sed 's/[.-]//g'; }

normalize_domain() {
    local domain="$1"
    domain=$(tolower "$domain")
    domain="${domain#"${domain%%[![:space:]]*}"}"
    domain="${domain%"${domain##*[![:space:]]}"}"
    echo "$domain"
}

validate_domain() {
    local domain="$1"
    if [ -z "$domain" ]; then
        echo "Error: domain is empty"
        return 1
    fi
    if [ ${#domain} -gt 253 ]; then
        echo "Error: domain exceeds 253 characters"
        return 1
    fi
    if [[ "$domain" == .* || "$domain" == *. ]]; then
        echo "Error: domain cannot start or end with a dot"
        return 1
    fi
    if [[ "$domain" == *..* ]]; then
        echo "Error: domain contains empty labels"
        return 1
    fi
    if [[ "$domain" != *.* ]]; then
        echo "Error: domain must include a dot"
        return 1
    fi
    IFS='.' read -r -a labels <<<"$domain"
    for label in "${labels[@]}"; do
        if [ -z "$label" ]; then
            echo "Error: domain contains empty labels"
            return 1
        fi
        if [ ${#label} -gt 63 ]; then
            echo "Error: label '$label' exceeds 63 characters"
            return 1
        fi
        if ! [[ "$label" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
            echo "Error: label '$label' contains invalid characters"
            return 1
        fi
    done
    return 0
}

validate_ipv4() {
    local ip="$1"
    if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "Error: IPv4 address has invalid format"
        return 1
    fi
    if [ "$ip" = "0.0.0.0" ]; then
        echo "Error: IPv4 address cannot be 0.0.0.0"
        return 1
    fi
    if [ "$ip" = "255.255.255.255" ]; then
        echo "Error: IPv4 address cannot be 255.255.255.255"
        return 1
    fi
    IFS='.' read -r -a octets <<<"$ip"
    for octet in "${octets[@]}"; do
        if [ "$octet" -lt 0 ] || [ "$octet" -gt 255 ]; then
            echo "Error: IPv4 octet out of range: $octet"
            return 1
        fi
    done
    if [ "${octets[0]}" -eq 10 ]; then
        echo "Error: IPv4 address in RFC1918 private range (10.0.0.0/8) not allowed"
        return 1
    fi
    if [ "${octets[0]}" -eq 172 ] && [ "${octets[1]}" -ge 16 ] && [ "${octets[1]}" -le 31 ]; then
        echo "Error: IPv4 address in RFC1918 private range (172.16.0.0/12) not allowed"
        return 1
    fi
    if [ "${octets[0]}" -eq 192 ] && [ "${octets[1]}" -eq 168 ]; then
        echo "Error: IPv4 address in RFC1918 private range (192.168.0.0/16) not allowed"
        return 1
    fi
    if [ "${octets[0]}" -eq 169 ] && [ "${octets[1]}" -eq 254 ]; then
        echo "Error: IPv4 address in link-local range (169.254.0.0/16) not allowed"
        return 1
    fi
    if [ "${octets[0]}" -eq 127 ]; then
        echo "Error: IPv4 address in loopback range (127.0.0.0/8) not allowed"
        return 1
    fi
    if [ "${octets[3]}" -eq 0 ] || [ "${octets[3]}" -eq 255 ]; then
        echo "Warning: IPv4 address ends in .0 or .255; verify it is not a network or broadcast address" >&2
    fi
    if [ "${octets[0]}" -ge 224 ]; then
        echo "Error: IPv4 address in multicast/experimental range not allowed"
        return 1
    fi
    return 0
}

finalize_domains() {
    local -n domains_ref="$1"
    local -A seen=()
    local -a unique=()
    local -a dupes=()
    local domain normalized

    for domain in "${domains_ref[@]}"; do
        normalized=$(normalize_domain "$domain")
        if ! validate_domain "$normalized"; then
            return 1
        fi
        if [ -z "${seen[$normalized]+x}" ]; then
            unique+=("$normalized")
            seen["$normalized"]=1
        else
            dupes+=("$normalized")
        fi
    done

    domains_ref=("${unique[@]}")
    if [ "${#dupes[@]}" -gt 0 ]; then
        log "Warning: duplicate domains ignored: ${dupes[*]}"
    fi
}
