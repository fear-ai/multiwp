#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SSL_BASE="${SSL_BASE:-/etc/ssl/cloudflare-origin}"
SSL_CERT_DIR="${SSL_CERT_DIR:-$SSL_BASE/certs}"
SSL_KEY_DIR="${SSL_KEY_DIR:-$SSL_BASE/keys}"
APACHE_SITES_DIR="${APACHE_SITES_DIR:-/etc/apache2/sites-available}"
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
