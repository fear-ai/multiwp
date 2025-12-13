#!/bin/bash
# install-cert.sh - Validate or install Cloudflare Origin cert/key for a domain
#
# Usage:
#   ./install-cert.sh [--ssl-dir DIR] example.com [www.example.com ...]
#
# Behavior:
# - Expects cert/key files in /etc/ssl/cloudflare-origin/{certs,keys}/<safe>.{crt,key} by default
#   where <safe> is the domain with dots/hyphens removed (same convention as apache-vhost.sh).
# - If files exist, validates readability and prints subject/SAN info.
# - If files are missing, prompts to paste cert/key blocks and writes them with safe permissions.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"
require_cmd openssl

usage() {
    cat <<'EOF'
Usage: install-cert.sh [--ssl-dir DIR] domain1 [domain2...]
Validates or installs Cloudflare Origin cert/key files. If missing, prompts to paste cert/key.
Options:
  -h, --help         Show this help
  --ssl-dir DIR      Base SSL dir (default: /etc/ssl/cloudflare-origin)
EOF
}

while getopts ":h-:" opt; do
    case "$opt" in
        h) usage; exit 0 ;;
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                ssl-dir=*) SSL_BASE="${OPTARG#*=}"; SSL_CERT_DIR="$SSL_BASE/certs"; SSL_KEY_DIR="$SSL_BASE/keys" ;;
                *) usage; exit 1 ;;
            esac
            ;;
        \?) usage; exit 1 ;;
    esac
done
shift $((OPTIND-1))

[ $# -ge 1 ] || { usage; exit 1; }

priv mkdir -p "$SSL_CERT_DIR" "$SSL_KEY_DIR"
priv chmod 755 "$SSL_CERT_DIR" || true
priv chmod 710 "$SSL_KEY_DIR" || true

ensure_perms() {
    priv chown root:ssl-cert "$1" || true
    priv chmod 640 "$1"
}

validate_cert() {
    local cert_file="$1"
    log "Cert info ($cert_file):"
    priv openssl x509 -in "$cert_file" -noout -subject -issuer -dates -ext subjectAltName || true
}

for domain in "$@"; do
    safe=$(safe_name "$domain")
    cert_file="$SSL_CERT_DIR/${safe}.crt"
    key_file="$SSL_KEY_DIR/${safe}.key"

    log "== $domain =="
    if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
        log "Found existing origin cert/key:"
        ls -l "$cert_file" "$key_file"
        validate_cert "$cert_file"
        continue
    fi

    log "Origin cert/key not found for $domain"
    tmp_cert=$(mktemp)
    tmp_key=$(mktemp)

    echo "Enter certificate block (terminate with Ctrl+D):"
    cat > "$tmp_cert"
    echo "Enter private key block (terminate with Ctrl+D):"
    cat > "$tmp_key"

    priv mv "$tmp_cert" "$cert_file"
    priv mv "$tmp_key" "$key_file"
    ensure_perms "$cert_file"
    ensure_perms "$key_file"
    validate_cert "$cert_file"
done

log "Done. Point Apache SSL vhosts to $SSL_CERT_DIR|$SSL_KEY_DIR/<safe>.{crt,key}."
