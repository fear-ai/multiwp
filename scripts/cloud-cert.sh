#!/bin/bash
# cloud-cert.sh - Download Cloudflare Origin certificates for domains (API)
# Creates individual .crt and .key files using domain-based naming.
#
# Usage: CF_API_TOKEN=... ./cloud-cert.sh [--cert-dir DIR] [--key-dir DIR] domain.com
#
# Prerequisites:
# - Cloudflare API token with SSL/Certificate permissions
# - jq installed for JSON processing
# - curl for API requests

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'EOF'
Usage: CF_API_TOKEN=... cloud-cert.sh [--ssl-dir DIR] domain.com
Downloads a Cloudflare Origin RSA certificate (apex + www) via API and saves it locally.
Options:
  -h, --help         Show this help
  --ssl-dir DIR      Base SSL dir (default: /etc/ssl/cloudflare-origin)
  --force            Overwrite existing files without prompt
EOF
}

FORCE=false

while getopts ":h-:" opt; do
    case "$opt" in
        h) usage; exit 0 ;;
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                ssl-dir=*) SSL_BASE="${OPTARG#*=}"; SSL_CERT_DIR="$SSL_BASE/certs"; SSL_KEY_DIR="$SSL_BASE/keys" ;;
                force) FORCE=true ;;
                *) usage; exit 1 ;;
            esac
            ;;
        \?) usage; exit 1 ;;
    esac
done
shift $((OPTIND-1))

[ $# -ge 1 ] || { usage; exit 1; }

[ -n "${CF_API_TOKEN:-}" ] || err "CF_API_TOKEN environment variable required"
require_cmd jq
require_cmd curl

domain=$(tolower "$1")
safe_name=$(safe_name "$domain")
cert_file="$SSL_CERT_DIR/${safe_name}.crt"
key_file="$SSL_KEY_DIR/${safe_name}.key"

log "Requesting Cloudflare Origin certificate for: $domain"
log "Certificate file: $cert_file"
log "Private key file: $key_file"

if [ -f "$cert_file" ] && [ -f "$key_file" ] && [ "$FORCE" = false ]; then
    read -p "Certificate files exist. Overwrite? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Skipping certificate generation"
        exit 0
    fi
fi

payload=$(jq -n \
    --arg domain "$domain" \
    --arg www_domain "www.$domain" \
    '{
        type: "origin-rsa",
        hostnames: [$domain, $www_domain],
        requested_validity: 5475
    }')

response=$(curl -sS -X POST "$CF_API_BASE/certificates" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "$payload")

if [ "$(echo "$response" | jq -r '.success')" != "true" ]; then
    err "API request failed: $(echo "$response" | jq -r '.errors[].message' | tr '\n' ' ')"
fi

certificate=$(echo "$response" | jq -r '.result.certificate')
private_key=$(echo "$response" | jq -r '.result.private_key')
[ "$certificate" != "null" ] && [ "$private_key" != "null" ] || err "Failed to extract certificate or private key"

priv mkdir -p "$SSL_CERT_DIR" "$SSL_KEY_DIR"
echo "$certificate" | priv tee "$cert_file" >/dev/null
echo "$private_key" | priv tee "$key_file" >/dev/null
priv chown root:ssl-cert "$key_file" || true
priv chmod 640 "$key_file"

log "Files created:"
log "  Certificate: $cert_file"
log "  Private key: $key_file (640, root:ssl-cert)"
log "Certificate details:"
openssl x509 -in "$cert_file" -text -noout | grep -E "(Subject:|Issuer:|Not Before:|Not After:|DNS:)" || true
