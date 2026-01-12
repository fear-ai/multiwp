#!/bin/bash
# verify-cf-auth.sh - Validate Cloudflare API credentials.
# For options, environment variables, defaults see usage().
#
# Example: verify-cf-auth.sh [OPTIONS]

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/auth.sh"
. "$SCRIPTS_DIR/cli.sh"

ACCOUNT_CLI=""
TOKEN_CLI=""
EMAIL_CLI=""
KEY_CLI=""
AUTH_FILE_CLI=""
CF_ACCOUNT_ID_CLI=""
CF_API_TOKEN_CLI=""
CF_API_EMAIL_CLI=""
CF_API_KEY_CLI=""
CF_CA_KEY_CLI=""
CF_ZONE_ID_CLI=""
CF_AUTH_CLI=""

usage() {
    cat <<'EOF'
verify-cf-auth.sh - Validate Cloudflare API credentials.
Example: verify-cf-auth.sh [OPTIONS]

Options:
  --zone-id ID [CF_ZONE_ID]  Set CF_ZONE_ID for Origin CA key verification
  --auth-file PATH [CF_AUTH_FILE] (default: ~/.config/cloudflare/default.auth)  Auth file to load
  --auth token|key|auto [CF_AUTH]  Select which credential to use (default: auto)
  --account ID [CF_ACCOUNT_ID]  Set CF_ACCOUNT_ID for account API token verification
  --token TOKEN [CF_API_TOKEN]  Set CF_API_TOKEN (account API token)
  --email EMAIL [CF_API_EMAIL]  Set CF_API_EMAIL (global API key email)
  --key KEY [CF_API_KEY]  Set CF_API_KEY (global API key)
  --ca-key KEY [CF_CA_KEY]  Set CF_CA_KEY (Origin CA User Service Key)
  --help  Show this help

Notes:
  - Account API tokens are verified against the account endpoint when CF_ACCOUNT_ID is set.
  - Global API keys are verified with X-Auth-Email + X-Auth-Key against /user.
  - Origin CA keys are verified with a read-only GET to /certificates?zone_id=...
EOF
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                zone-id=*) CF_ZONE_ID_CLI="${OPTARG#*=}" ;;
                zone-id)
                    [ -n "${!OPTIND-}" ] || err "--zone-id requires a value"
                    CF_ZONE_ID_CLI="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                *)
                    if cli_cf_auth_opt "${OPTARG}" "${!OPTIND-}"; then
                        if [ -n "${CF_AUTH_FILE:-}" ]; then
                            AUTH_FILE_CLI="$CF_AUTH_FILE"
                        fi
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

require_cmds curl

if [ -n "$AUTH_FILE_CLI" ]; then
    cf_init_auth "$AUTH_FILE_CLI"
else
    cf_init_auth
fi

AUTH_PREF="$(tolower "${CF_AUTH:-auto}")"
case "$AUTH_PREF" in
    ""|auto|token|key) ;;
    *) err "Invalid auth mode: $AUTH_PREF (expected token, key, or auto)" ;;
esac
if [ "$AUTH_PREF" = "token" ] && [ -z "${CF_API_TOKEN:-}" ]; then
    err "CF_API_TOKEN required when --auth token is set"
fi
if [ "$AUTH_PREF" = "key" ] && { [ -z "${CF_API_KEY:-}" ] || [ -z "${CF_API_EMAIL:-}" ]; }; then
    err "CF_API_KEY+CF_API_EMAIL required when --auth key is set"
fi

token_checked=false
key_checked=false
ca_checked=false
token_ok=false
key_ok=false
ca_ok=false

if [ -n "${CF_API_TOKEN:-}" ] && [ "$AUTH_PREF" != "key" ]; then
    token_checked=true
    if [ -n "${CF_ACCOUNT_ID:-}" ]; then
        log "Verifying account API token against account $CF_ACCOUNT_ID"
        token_resp=$(cf_api_request_mode token GET "/accounts/$CF_ACCOUNT_ID/tokens/verify")
        token_success=$(cf_api_success "$token_resp")
    else
        log "Verifying API token against user endpoint"
        token_resp=$(cf_api_request_mode token GET "/user/tokens/verify")
        token_success=$(cf_api_success "$token_resp")
    fi
    if [ "$token_success" = "true" ]; then
        log "API token valid"
        token_ok=true
    else
        if [ -n "${CF_ACCOUNT_ID:-}" ]; then
            log "Account API token verify failed; attempting user token verify"
            token_resp=$(cf_api_request_mode token GET "/user/tokens/verify")
            token_success=$(cf_api_success "$token_resp")
            if [ "$token_success" = "true" ]; then
                log "API token valid (user-scoped)"
                token_ok=true
            else
                log "API token invalid"
            fi
        else
            log "API token invalid"
        fi
    fi
fi

if [ -n "${CF_API_KEY:-}" ] && [ -n "${CF_API_EMAIL:-}" ] && [ "$AUTH_PREF" != "token" ]; then
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

if [ -n "${CF_CA_KEY:-}" ]; then
    ca_checked=true
    if [ -z "${CF_ZONE_ID:-}" ]; then
        log "Origin CA key present but CF_ZONE_ID missing; cannot verify CA key"
    else
        log "Verifying Origin CA key against zone $CF_ZONE_ID"
        ca_resp=$(cf_origin_ca_request GET "/certificates?zone_id=${CF_ZONE_ID}")
        ca_success=$(cf_api_success "$ca_resp")
        if [ "$ca_success" = "true" ]; then
            log "Origin CA key valid"
            ca_ok=true
        else
            log "Origin CA key invalid: $(cf_api_error_messages "$ca_resp")"
        fi
    fi
fi

if [ "$token_checked" != true ] && [ "$key_checked" != true ] && [ "$ca_checked" != true ]; then
    err "No credentials available. Provide CF_API_TOKEN, CF_API_KEY+CF_API_EMAIL, or CF_CA_KEY."
fi

if [ "$token_ok" != true ] && [ "$key_ok" != true ] && [ "$ca_ok" != true ]; then
    err "Credential verification failed"
fi

if [ "$token_checked" = true ] && [ "$token_ok" != true ]; then
    err "Account API token verification failed"
fi
if [ "$key_checked" = true ] && [ "$key_ok" != true ]; then
    err "Global API key verification failed"
fi
if [ "$ca_checked" = true ] && [ "$ca_ok" != true ]; then
    err "Origin CA key verification failed"
fi

log "Credential verification succeeded"
