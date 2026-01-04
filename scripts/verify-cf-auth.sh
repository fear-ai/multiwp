#!/bin/bash
# verify-cf-auth.sh - Validate Cloudflare API credentials (token or global key)
#
# Usage:
#   verify-cf-auth.sh [--account ID] [--token TOKEN] [--email EMAIL] [--key KEY] [--auth-file PATH]
#
# Notes:
# - Account-scoped tokens should be verified with the account endpoint.
# - Global API keys are verified with X-Auth-Email + X-Auth-Key against /user.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"
. "$SCRIPT_DIR/auth.sh"

ACCOUNT_OVERRIDE=""
TOKEN_OVERRIDE=""
EMAIL_OVERRIDE=""
KEY_OVERRIDE=""
AUTH_FILE_OVERRIDE=""
CF_ACCOUNT_ID_OVERRIDE=""
CF_API_TOKEN_OVERRIDE=""
CF_API_EMAIL_OVERRIDE=""
CF_API_KEY_OVERRIDE=""

usage() {
    cat <<'EOF'
Usage: verify-cf-auth.sh [OPTIONS]
Validates Cloudflare API credentials (token and/or global API key).
Options:
  -h, --help         Show this help
  --auth-file PATH   Auth file to load (default: ~/.config/cloudflare/auth)
  --account ID       Override CF_ACCOUNT_ID for account-scoped token verification
  --token TOKEN      Override CF_API_TOKEN
  --email EMAIL      Override CF_API_EMAIL
  --key KEY          Override CF_API_KEY
EOF
}

while getopts ":h-:" opt; do
    case "$opt" in
        h) usage; exit 0 ;;
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                *)
                    if cf_auth_file "${OPTARG}"; then
                        AUTH_FILE_OVERRIDE="$CF_AUTH_FILE"
                    elif cf_auth_opt "${OPTARG}"; then
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

require_cmd curl

if [ -n "$AUTH_FILE_OVERRIDE" ]; then
    load_cloudflare_auth "$AUTH_FILE_OVERRIDE"
else
    load_cloudflare_auth
fi

CF_ACCOUNT_ID="${CF_ACCOUNT_ID_OVERRIDE:-${CF_ACCOUNT_ID:-}}"
CF_API_TOKEN="${CF_API_TOKEN_OVERRIDE:-${CF_API_TOKEN:-}}"
CF_API_EMAIL="${CF_API_EMAIL_OVERRIDE:-${CF_API_EMAIL:-}}"
CF_API_KEY="${CF_API_KEY_OVERRIDE:-${CF_API_KEY:-}}"

token_checked=false
key_checked=false
token_ok=false
key_ok=false

if [ -n "${CF_API_TOKEN:-}" ]; then
    token_checked=true
    if [ -n "${CF_ACCOUNT_ID:-}" ]; then
        log "Verifying account-scoped token against account $CF_ACCOUNT_ID"
        token_resp=$(cf_api_request_mode token GET "/accounts/$CF_ACCOUNT_ID/tokens/verify")
        token_success=$(cf_api_success "$token_resp")
    else
        log "Verifying token against user endpoint"
        token_resp=$(cf_api_request_mode token GET "/user/tokens/verify")
        token_success=$(cf_api_success "$token_resp")
    fi
    if [ "$token_success" = "true" ]; then
        log "Token valid"
        token_ok=true
    else
        if [ -n "${CF_ACCOUNT_ID:-}" ]; then
            log "Account token verify failed; attempting user token verify"
            token_resp=$(cf_api_request_mode token GET "/user/tokens/verify")
            token_success=$(cf_api_success "$token_resp")
            if [ "$token_success" = "true" ]; then
                log "Token valid (user-scoped)"
                token_ok=true
            else
                log "Token invalid"
            fi
        else
            log "Token invalid"
        fi
    fi
fi

if [ -n "${CF_API_KEY:-}" ] && [ -n "${CF_API_EMAIL:-}" ]; then
    key_checked=true
    log "Verifying global API key for $CF_API_EMAIL"
    key_resp=$(cf_api_request_mode key GET "/user")
    key_success=$(cf_api_success "$key_resp")
    if [ "$key_success" = "true" ]; then
        log "Global API key valid"
        key_ok=true
    else
        log "Global API key invalid"
    fi
fi

if [ "$token_checked" != true ] && [ "$key_checked" != true ]; then
    err "No credentials available. Provide CF_API_TOKEN or CF_API_KEY+CF_API_EMAIL."
fi

if [ "$token_ok" != true ] && [ "$key_ok" != true ]; then
    err "Credential verification failed"
fi

log "Credential verification succeeded"
