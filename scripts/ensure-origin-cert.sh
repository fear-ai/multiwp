#!/bin/bash
# ensure-origin-cert.sh - Validate or install Cloudflare Origin cert/key for a domain
#
# Usage:
#   ./ensure-origin-cert.sh example.com [www.example.com ...]
#
# Behavior:
# - Expects cert/key files in /etc/ssl/cloudflare-origin/{certs,keys}/<safe>.{crt,key}
#   where <safe> is the domain with dots/hyphens removed (same convention as add-domains.sh).
# - If files exist, validates readability and prints subject/SAN info.
# - If files are missing, prompts to paste cert/key blocks and writes them with safe permissions.

set -euo pipefail

SSL_CERT_DIR="/etc/ssl/cloudflare-origin/certs"
SSL_KEY_DIR="/etc/ssl/cloudflare-origin/keys"

mkdir -p "$SSL_CERT_DIR" "$SSL_KEY_DIR"

safe_name() {
    echo "$1" | tr 'A-Z' 'a-z' | sed 's/[.-]//g'
}

ensure_perms() {
    sudo chown root:ssl-cert "$1"
    sudo chmod 640 "$1"
}

validate_cert() {
    local cert_file="$1"
    echo "Cert info ($cert_file):"
    sudo openssl x509 -in "$cert_file" -noout -subject -issuer -dates -ext subjectAltName || true
}

for domain in "$@"; do
    safe=$(safe_name "$domain")
    cert_file="$SSL_CERT_DIR/${safe}.crt"
    key_file="$SSL_KEY_DIR/${safe}.key"

    echo "== $domain =="
    if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
        echo "Found existing origin cert/key:"
        ls -l "$cert_file" "$key_file"
        validate_cert "$cert_file"
        continue
    fi

    echo "Origin cert/key not found for $domain"
    read -p "Paste Cloudflare Origin CERT (END with EOF on its own line): " -r
    tmp_cert=$(mktemp)
    tmp_key=$(mktemp)

    echo "Enter certificate block:"
    cat > "$tmp_cert"
    echo "Enter private key block:"
    cat > "$tmp_key"

    sudo mv "$tmp_cert" "$cert_file"
    sudo mv "$tmp_key" "$key_file"
    ensure_perms "$cert_file"
    ensure_perms "$key_file"
    validate_cert "$cert_file"
done

echo "Done. Point Apache SSL vhosts to /etc/ssl/cloudflare-origin/certs|keys/<safe>.{crt,key}."
