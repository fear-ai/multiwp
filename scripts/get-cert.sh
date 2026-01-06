#!/bin/bash
# get-cert.sh - Issue or install Cloudflare Origin cert/key for domain(s)
#
# Usage:
#   ./get-cert.sh [OPTIONS] domain1 [domain2...]
#
# Modes:
#   --api      Issue certs via Cloudflare API
#   --manual   Paste cert/key blocks manually
#   --auto     Use API if credentials exist, otherwise manual (default)
#
# Options:
#   --ssl-dir DIR     Base SSL dir (default: /etc/ssl/cloudflare-origin)
#   --auth-file PATH  Auth file to load (default: ~/.config/cloudflare/default.auth)
#   --token TOKEN     Override CF_API_TOKEN
#   --key KEY         Override CF_API_KEY
#   --email EMAIL     Override CF_API_EMAIL
#   --force           Overwrite existing files without prompt
#   --help            Show help

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"
. "$SCRIPT_DIR/auth.sh"
. "$SCRIPT_DIR/cli.sh"

MODE="auto"
FORCE=false

usage() {
    cat <<'EOF'
Usage: get-cert.sh [OPTIONS] domain1 [domain2...]
Issues or installs Cloudflare Origin cert/key files for one or more domains.

Modes:
  --api       Issue certs via Cloudflare API
  --manual    Paste cert/key blocks manually
  --auto      Use API if credentials exist, otherwise manual (default)

Options:
  --auth-file PATH Auth file to load (default: ~/.config/cloudflare/default.auth)
  --token TOKEN      Override CF_API_TOKEN
  --key KEY          Override CF_API_KEY
  --email EMAIL      Override CF_API_EMAIL
  --force         Overwrite existing files without prompt
  --help          Show this help
EOF
    cli_usage_ssl_dir
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                api) MODE="api" ;;
                manual) MODE="manual" ;;
                auto) MODE="auto" ;;
                ssl-dir|ssl-dir=*)
                    if cli_handle_ssl_dir_opt "${OPTARG}" SSL_BASE SSL_CERT_DIR SSL_KEY_DIR "${!OPTIND-}"; then
                        :
                    else
                        usage; exit 1
                    fi
                    ;;
                force) FORCE=true ;;
                *)
                    if cli_handle_cf_auth_opt "${OPTARG}" "${!OPTIND-}"; then
                        :
                    else
                        usage; exit 1
                    fi
                    ;;
            esac
            ;;
        \?) usage; exit 1 ;;
    esac
done
shift $((OPTIND-1))

[ $# -ge 1 ] || { usage; exit 1; }

require_cmd openssl

load_cloudflare_auth

AUTH_MODE=""
if [ "$MODE" = "auto" ] || [ "$MODE" = "api" ]; then
    if cf_auth_mode; then
        AUTH_MODE="$CF_AUTH_MODE"
    fi
fi

if [ "$MODE" = "auto" ]; then
    if [ -n "$AUTH_MODE" ]; then
        MODE="api"
    else
        MODE="manual"
    fi
fi

if [ "$MODE" = "api" ]; then
    [ -n "$AUTH_MODE" ] || err "API auth required: CF_API_TOKEN or CF_API_KEY+CF_API_EMAIL"
    require_cmd curl
    require_cmd jq
fi

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

issue_cert() {
    local domain="$1"
    local safe
    safe=$(safe_name "$domain")
    local cert_file="$SSL_CERT_DIR/${safe}.crt"
    local key_file="$SSL_KEY_DIR/${safe}.key"

    log "Requesting Cloudflare Origin certificate for: $domain"
    log "Certificate file: $cert_file"
    log "Private key file: $key_file"

    local payload
    payload=$(jq -n \
        --arg domain "$domain" \
        --arg www_domain "www.$domain" \
        '{
            type: "origin-rsa",
            hostnames: [$domain, $www_domain],
            requested_validity: 5475
        }')

    local response
    response=$(cf_api_request POST "/certificates" "$payload")

    if [ "$(echo "$response" | jq -r '.success')" != "true" ]; then
        err "API request failed: $(echo "$response" | jq -r '.errors[].message' | tr '\n' ' ')"
    fi

    local certificate private_key
    certificate=$(echo "$response" | jq -r '.result.certificate')
    private_key=$(echo "$response" | jq -r '.result.private_key')
    [ "$certificate" != "null" ] && [ "$private_key" != "null" ] || err "Failed to extract certificate or private key"

    echo "$certificate" | priv tee "$cert_file" >/dev/null
    echo "$private_key" | priv tee "$key_file" >/dev/null
    ensure_perms "$cert_file"
    ensure_perms "$key_file"
    validate_cert "$cert_file"
}

install_manual() {
    local domain="$1"
    local safe
    safe=$(safe_name "$domain")
    local cert_file="$SSL_CERT_DIR/${safe}.crt"
    local key_file="$SSL_KEY_DIR/${safe}.key"

    log "Manual install for: $domain"
    local tmp_cert tmp_key
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
}

for domain in "$@"; do
    domain=$(tolower "$domain")
    safe=$(safe_name "$domain")
    cert_file="$SSL_CERT_DIR/${safe}.crt"
    key_file="$SSL_KEY_DIR/${safe}.key"

    log "== $domain =="
    if [ -f "$cert_file" ] && [ -f "$key_file" ] && [ "$FORCE" = false ]; then
        log "Found existing origin cert/key:"
        ls -l "$cert_file" "$key_file"
        validate_cert "$cert_file"
        continue
    fi

    if [ "$MODE" = "api" ]; then
        if [ -f "$cert_file" ] || [ -f "$key_file" ]; then
            if [ "$FORCE" = true ]; then
                log "Overwriting existing files for $domain (--force)"
            else
                err "Files exist for $domain; use --force to overwrite"
            fi
        fi
        issue_cert "$domain"
    else
        if [ -f "$cert_file" ] || [ -f "$key_file" ]; then
            if [ "$FORCE" = true ]; then
                log "Overwriting existing files for $domain (--force)"
            else
                err "Files exist for $domain; use --force to overwrite"
            fi
        fi
        install_manual "$domain"
    fi
done

log "Done. Origin certs are in $SSL_CERT_DIR and keys in $SSL_KEY_DIR."
