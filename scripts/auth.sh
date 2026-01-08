#!/bin/bash
# auth.sh - Cloudflare auth helpers and API request utilities

set -euo pipefail

CF_API_BASE="${CF_API_BASE:-https://api.cloudflare.com/client/v4}"

load_cloudflare_auth() {
    local auth_file="${1:-${CF_AUTH_FILE:-$HOME/.config/cloudflare/default.auth}}"
    local prev_account_id="${CF_ACCOUNT_ID-}"
    local prev_api_token="${CF_API_TOKEN-}"
    local prev_api_email="${CF_API_EMAIL-}"
    local prev_api_key="${CF_API_KEY-}"
    local prev_zone_id="${CF_ZONE_ID-}"
    local prev_zone="${CF_ZONE-}"
    local prev_ca_key="${CF_CA_KEY-}"

    local first_zone_id=""
    local first_zone=""

    if [ -f "$auth_file" ]; then
        first_zone_id=$(awk -F= '/^[[:space:]]*CF_ZONE_ID=/{gsub(/^[[:space:]]*CF_ZONE_ID=|["'\'']/, "", $0); print $0; exit}' "$auth_file")
        first_zone=$(awk -F= '/^[[:space:]]*CF_ZONE=/{gsub(/^[[:space:]]*CF_ZONE=|["'\'']/, "", $0); print $0; exit}' "$auth_file")

        set -a
        # shellcheck disable=SC1090
        . "$auth_file"
        set +a
    else
        return 0
    fi

    if [ -n "$prev_account_id" ]; then
        CF_ACCOUNT_ID="$prev_account_id"
    fi
    if [ -n "$prev_api_token" ]; then
        CF_API_TOKEN="$prev_api_token"
    fi
    if [ -n "$prev_api_email" ]; then
        CF_API_EMAIL="$prev_api_email"
    fi
    if [ -n "$prev_api_key" ]; then
        CF_API_KEY="$prev_api_key"
    fi
    if [ -n "$prev_zone_id" ]; then
        CF_ZONE_ID="$prev_zone_id"
    elif [ -n "$first_zone_id" ]; then
        CF_ZONE_ID="$first_zone_id"
    fi
    if [ -n "$prev_zone" ]; then
        CF_ZONE="$prev_zone"
    elif [ -n "${CF_ZONE_MAIN:-}" ]; then
        CF_ZONE="$CF_ZONE_MAIN"
    elif [ -n "$first_zone" ]; then
        CF_ZONE="$first_zone"
    fi
    if [ -n "$prev_ca_key" ]; then
        CF_CA_KEY="$prev_ca_key"
    fi
}

cf_auth_mode() {
    if [ -n "${CF_API_TOKEN:-}" ]; then
        CF_AUTH_MODE="token"
        return 0
    fi
    if [ -n "${CF_API_KEY:-}" ] && [ -n "${CF_API_EMAIL:-}" ]; then
        CF_AUTH_MODE="key"
        return 0
    fi
    return 1
}

cf_require_auth() {
    local context="${1:-}"
    if ! cf_auth_mode; then
        if [ -n "$context" ]; then
            err "Account API token (CF_API_TOKEN) or Global API Key + email (CF_API_KEY+CF_API_EMAIL) required $context"
        else
            err "Account API token (CF_API_TOKEN) or Global API Key + email (CF_API_KEY+CF_API_EMAIL) required"
        fi
    fi
}

cf_parse_auth_file() {
    local path="$1"
    [ -n "$path" ] || err "auth-file requires a path"
    CF_AUTH_FILE="$path"
}

cf_auth_file() {
    local opt="$1"
    local val="${2-}"
    case "$opt" in
        auth-file=*) cf_parse_auth_file "${opt#*=}"; return 0 ;;
        auth-file)
            [ -n "$val" ] || err "auth-file requires a path"
            cf_parse_auth_file "$val"
            return 0
            ;;
    esac
    return 1
}

cf_auth_opt() {
    local opt="$1"
    local val="${2-}"
    case "$opt" in
        account=*) CF_ACCOUNT_ID_OVERRIDE="${opt#*=}"; return 0 ;;
        account)
            [ -n "$val" ] || err "account requires a value"
            CF_ACCOUNT_ID_OVERRIDE="$val"
            return 0
            ;;
        token=*) CF_API_TOKEN_OVERRIDE="${opt#*=}"; return 0 ;;
        token)
            [ -n "$val" ] || err "token requires a value"
            CF_API_TOKEN_OVERRIDE="$val"
            return 0
            ;;
        email=*) CF_API_EMAIL_OVERRIDE="${opt#*=}"; return 0 ;;
        email)
            [ -n "$val" ] || err "email requires a value"
            CF_API_EMAIL_OVERRIDE="$val"
            return 0
            ;;
        key=*) CF_API_KEY_OVERRIDE="${opt#*=}"; return 0 ;;
        key)
            [ -n "$val" ] || err "key requires a value"
            CF_API_KEY_OVERRIDE="$val"
            return 0
            ;;
        ca-key=*) CF_CA_KEY_OVERRIDE="${opt#*=}"; return 0 ;;
        ca-key)
            [ -n "$val" ] || err "ca-key requires a value"
            CF_CA_KEY_OVERRIDE="$val"
            return 0
            ;;
    esac
    return 1
}

cf_api_headers_mode() {
    local mode="$1"
    CF_API_HEADERS=("-H" "Content-Type: application/json")
    if [ "$mode" = "token" ]; then
        [ -n "${CF_API_TOKEN:-}" ] || err "Account API token (CF_API_TOKEN) required for token auth"
        CF_API_HEADERS+=("-H" "Authorization: Bearer $CF_API_TOKEN")
        return 0
    fi
    if [ "$mode" = "key" ]; then
        [ -n "${CF_API_KEY:-}" ] && [ -n "${CF_API_EMAIL:-}" ] || err "Global API Key + email (CF_API_KEY+CF_API_EMAIL) required for key auth"
        CF_API_HEADERS+=("-H" "X-Auth-Key: $CF_API_KEY" "-H" "X-Auth-Email: $CF_API_EMAIL")
        return 0
    fi
    err "Unknown auth mode: $mode"
}

cf_api_request_mode() {
    local mode="$1"
    local method="$2"
    local path="$3"
    local data="${4-}"
    cf_api_headers_mode "$mode"
    if [ -n "$data" ]; then
        curl -sS -X "$method" "${CF_API_HEADERS[@]}" --data "$data" "$CF_API_BASE$path"
        return
    fi
    curl -sS -X "$method" "${CF_API_HEADERS[@]}" "$CF_API_BASE$path"
}

cf_api_request() {
    local method="$1"
    local path="$2"
    local data="${3-}"
    cf_auth_mode || err "Account API token (CF_API_TOKEN) or Global API Key + email (CF_API_KEY+CF_API_EMAIL) required"
    cf_api_request_mode "$CF_AUTH_MODE" "$method" "$path" "$data"
}

cf_origin_ca_request() {
    local method="$1"
    local path="$2"
    local data="${3-}"
    CF_API_HEADERS=("-H" "Content-Type: application/json")
    if [ -n "${CF_CA_KEY:-}" ]; then
        CF_API_HEADERS+=("-H" "X-Auth-User-Service-Key: $CF_CA_KEY")
    else
        cf_auth_mode || err "Origin CA key (CF_CA_KEY), account API token (CF_API_TOKEN), or Global API Key + email (CF_API_KEY+CF_API_EMAIL) required"
        if [ "$CF_AUTH_MODE" = "token" ]; then
            CF_API_HEADERS+=("-H" "Authorization: Bearer $CF_API_TOKEN")
        else
            CF_API_HEADERS+=("-H" "X-Auth-Key: $CF_API_KEY" "-H" "X-Auth-Email: $CF_API_EMAIL")
        fi
    fi
    if [ -n "$data" ]; then
        curl -sS -X "$method" "${CF_API_HEADERS[@]}" --data "$data" "$CF_API_BASE$path"
        return
    fi
    curl -sS -X "$method" "${CF_API_HEADERS[@]}" "$CF_API_BASE$path"
}

cf_api_success() {
    local response="$1"
    if command -v jq >/dev/null 2>&1; then
        echo "$response" | jq -r 'if .success == true then "true" elif .success == false then "false" else "" end'
        return
    fi
    echo "$response" | tr -d '\n' | sed -n 's/.*"success":\(true\|false\).*/\1/p'
}

cf_api_error_messages() {
    local response="$1"
    if command -v jq >/dev/null 2>&1; then
        echo "$response" | jq -r '.errors[].message // empty' | tr '\n' ' '
        return
    fi
    echo ""
}
