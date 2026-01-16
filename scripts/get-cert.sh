#!/bin/bash
# get-cert.sh - Issue or install Cloudflare Origin certs and keys for domains.
# For options, environment variables, defaults see usage().
#
# Example: get-cert.sh [OPTIONS] domain1 [domain2...]

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/auth.sh"
. "$SCRIPTS_DIR/cli.sh"

MODE="auto"
FORCE=false
DOMAINS=()
CF_AUTH_CLI=""

usage() {
    cat <<EOF
get-cert.sh - Issue or install Cloudflare Origin certs and keys for domains.
Example: get-cert.sh [OPTIONS] domain1 [domain2...]

Modes:
  --api  Issue certs via Cloudflare API
  --manual  Paste cert/key blocks manually
  --auto (default)  Use API if credentials exist, otherwise manual

Options:
$(cli_usage_domain)
  --force  Overwrite existing files without prompt
  --auth token|key|auto [CF_AUTH]  Select which credential to use (default: auto)
  --auth-file PATH [CF_AUTH_FILE] (default: ~/.config/cloudflare/default.auth)  Auth file to load
  --token TOKEN [CF_API_TOKEN]  Set CF_API_TOKEN (account API token)
  --key KEY [CF_API_KEY]  Set CF_API_KEY (global API key)
  --email EMAIL [CF_API_EMAIL]  Set CF_API_EMAIL (global API key email)
  --ca-key KEY [CF_CA_KEY]  Set CF_CA_KEY (Origin CA User Service Key)
$(cli_usage_ssl_dir)
  --help  Show this help

Notes:
  - API mode requires an Origin CA key (CF_CA_KEY).
  - Manual mode prompts for certificate and key blocks and writes into SSL_DIR.
EOF
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
                    if cli_ssl_dir_opt "${OPTARG}" SSL_DIR SSL_CERT_DIR SSL_KEY_DIR "${!OPTIND-}"; then
                        :
                    else
                        usage; exit 1
                    fi
                    ;;
                force) FORCE=true ;;
                *)
                    if cli_domain_opt "${OPTARG}" DOMAINS "${!OPTIND-}"; then
                        :
                    elif cli_cf_auth_opt "${OPTARG}" "${!OPTIND-}"; then
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

for domain in "$@"; do
    DOMAINS+=("$domain")
done
finalize_domains DOMAINS || { usage; exit 1; }
[ ${#DOMAINS[@]} -ge 1 ] || { usage; exit 1; }

require_cmds openssl

cf_init_auth

if [ "$MODE" = "auto" ]; then
    if cf_has_ca_key; then
        MODE="api"
    else
        MODE="manual"
    fi
fi

if [ "$MODE" = "api" ]; then
    cf_require_ca_key
    require_cmds curl jq
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
    local tmp_key tmp_csr
    local csr_payload

    log "Requesting Cloudflare Origin certificate for: $domain"
    log "Certificate file: $cert_file"
    log "Private key file: $key_file"

    tmp_key=$(mktemp)
    tmp_csr=$(mktemp)

    log "Generating private key and CSR for: $domain"
    if ! (umask 077 && openssl req -new -newkey rsa:2048 -nodes -keyout "$tmp_key" -out "$tmp_csr" -subj "/CN=$domain" >/dev/null 2>&1); then
        rm -f "$tmp_key" "$tmp_csr"
        err "Failed to generate key/CSR for $domain"
    fi

    csr_payload=$(awk 'NF {sub(/\r/, ""); printf "%s\n", $0;}' "$tmp_csr")

    local payload
    payload=$(jq -n \
        --arg domain "$domain" \
        --arg www_domain "www.$domain" \
        --arg csr "$csr_payload" \
        '{
            hostnames: [$domain, $www_domain],
            requested_validity: 5475,
            request_type: "origin-rsa",
            csr: $csr
        }')

    local response
    response=$(cf_origin_ca_request POST "/certificates" "$payload")

    if [ "$(echo "$response" | jq -r '.success')" != "true" ]; then
        rm -f "$tmp_key" "$tmp_csr"
        err "API request failed: $(echo "$response" | jq -r '.errors[].message' | tr '\n' ' ')"
    fi

    local certificate
    certificate=$(echo "$response" | jq -r '.result.certificate')
    if [ "$certificate" = "null" ] || [ -z "$certificate" ]; then
        rm -f "$tmp_key" "$tmp_csr"
        err "Failed to extract certificate"
    fi

    echo "$certificate" | priv tee "$cert_file" >/dev/null
    priv mv "$tmp_key" "$key_file"
    rm -f "$tmp_csr"
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

for domain in "${DOMAINS[@]}"; do
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
