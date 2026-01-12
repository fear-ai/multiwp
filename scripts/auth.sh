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
    local prev_auth="${CF_AUTH-}"
    local prev_zone_id="${CF_ZONE_ID-}"
    local prev_zone="${CF_ZONE-}"
    local prev_ca_key="${CF_CA_KEY-}"
    local prev_zone_ids="${CF_ZONE_IDS-}"

    local first_zone_id=""
    local first_zone=""
    local all_zone_ids=""

    if [ -f "$auth_file" ]; then
        all_zone_ids=$(awk -F= '/^[[:space:]]*CF_ZONE_ID=/{gsub(/^[[:space:]]*CF_ZONE_ID=|["'\'']/, "", $0); print $0}' "$auth_file")
        first_zone_id=$(printf '%s\n' "$all_zone_ids" | awk 'NF{print; exit}')
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
    if [ -n "$prev_auth" ]; then
        CF_AUTH="$prev_auth"
    fi
    if [ -n "$prev_zone_id" ]; then
        CF_ZONE_ID="$prev_zone_id"
    elif [ -n "$first_zone_id" ]; then
        CF_ZONE_ID="$first_zone_id"
    fi
    if [ -n "$prev_zone_ids" ]; then
        CF_ZONE_IDS="$prev_zone_ids"
    elif [ -n "$all_zone_ids" ]; then
        CF_ZONE_IDS=$(printf '%s\n' "$all_zone_ids" | paste -sd ',' -)
    fi
    if [ -n "${CF_ZONE_IDS:-}" ] && [[ "$CF_ZONE_IDS" == *","* ]]; then
        if declare -f parse_comma_list >/dev/null 2>&1; then
            local zone_list=()
            if parse_comma_list "$CF_ZONE_IDS" zone_list "CF_ZONE_IDS"; then
                CF_ZONE_IDS=$(IFS=','; printf '%s' "${zone_list[*]}")
            else
                err "CF_ZONE_IDS contains empty values"
            fi
        else
            err "CF_ZONE_IDS uses commas but parse_comma_list is unavailable"
        fi
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

cf_parse_auth_mode() {
    local val="${1-}"
    val="$(tolower "$val")"
    case "$val" in
        auto|token|key) printf '%s' "$val"; return 0 ;;
        *) return 1 ;;
    esac
}

cf_auth_mode() {
    local mode="${CF_AUTH:-auto}"
    if [ -n "$mode" ]; then
        mode="$(tolower "$mode")"
    fi
    case "$mode" in
        ""|auto)
            if [ -n "${CF_API_TOKEN:-}" ]; then
                CF_AUTH_MODE="token"
                return 0
            fi
            if [ -n "${CF_API_KEY:-}" ] && [ -n "${CF_API_EMAIL:-}" ]; then
                CF_AUTH_MODE="key"
                return 0
            fi
            return 1
            ;;
        token)
            [ -n "${CF_API_TOKEN:-}" ] || err "CF_API_TOKEN required when --auth token is set"
            CF_AUTH_MODE="token"
            return 0
            ;;
        key)
            [ -n "${CF_API_KEY:-}" ] && [ -n "${CF_API_EMAIL:-}" ] || err "CF_API_KEY+CF_API_EMAIL required when --auth key is set"
            CF_AUTH_MODE="key"
            return 0
            ;;
        *)
            err "Invalid auth mode: $mode (expected token, key, or auto)"
            ;;
    esac
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
        auth=*)
            val="$(cf_parse_auth_mode "${opt#*=}")" || err "auth requires token, key, or auto"
            CF_AUTH_CLI="$val"
            return 0
            ;;
        auth)
            [ -n "$val" ] || err "auth requires token, key, or auto"
            val="$(cf_parse_auth_mode "$val")" || err "auth requires token, key, or auto"
            CF_AUTH_CLI="$val"
            return 0
            ;;
        account=*) CF_ACCOUNT_ID_CLI="${opt#*=}"; return 0 ;;
        account)
            [ -n "$val" ] || err "account requires a value"
            CF_ACCOUNT_ID_CLI="$val"
            return 0
            ;;
        token=*) CF_API_TOKEN_CLI="${opt#*=}"; return 0 ;;
        token)
            [ -n "$val" ] || err "token requires a value"
            CF_API_TOKEN_CLI="$val"
            return 0
            ;;
        email=*) CF_API_EMAIL_CLI="${opt#*=}"; return 0 ;;
        email)
            [ -n "$val" ] || err "email requires a value"
            CF_API_EMAIL_CLI="$val"
            return 0
            ;;
        key=*) CF_API_KEY_CLI="${opt#*=}"; return 0 ;;
        key)
            [ -n "$val" ] || err "key requires a value"
            CF_API_KEY_CLI="$val"
            return 0
            ;;
        ca-key=*) CF_CA_KEY_CLI="${opt#*=}"; return 0 ;;
        ca-key)
            [ -n "$val" ] || err "ca-key requires a value"
            CF_CA_KEY_CLI="$val"
            return 0
            ;;
    esac
    return 1
}

cf_init_auth() {
    local auth_file="${1-}"

    if [ -n "$auth_file" ]; then
        CF_AUTH_FILE="$auth_file"
        load_cloudflare_auth "$auth_file"
    else
        load_cloudflare_auth
    fi

    [ -n "${CF_AUTH_CLI:-}" ] && CF_AUTH="$CF_AUTH_CLI"
    [ -n "${CF_API_TOKEN_CLI:-}" ] && CF_API_TOKEN="$CF_API_TOKEN_CLI"
    [ -n "${CF_API_KEY_CLI:-}" ] && CF_API_KEY="$CF_API_KEY_CLI"
    [ -n "${CF_API_EMAIL_CLI:-}" ] && CF_API_EMAIL="$CF_API_EMAIL_CLI"
    [ -n "${CF_CA_KEY_CLI:-}" ] && CF_CA_KEY="$CF_CA_KEY_CLI"
    [ -n "${CF_ACCOUNT_ID_CLI:-}" ] && CF_ACCOUNT_ID="$CF_ACCOUNT_ID_CLI"
    [ -n "${CF_ZONE_ID_CLI:-}" ] && CF_ZONE_ID="$CF_ZONE_ID_CLI"
    [ -n "${CF_ZONE_CLI:-}" ] && CF_ZONE="$CF_ZONE_CLI"
    return 0
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

cf_api_request_mode_checked() {
    local mode="$1"
    local method="$2"
    local path="$3"
    local data="${4-}"
    local tmp status curl_status=0
    cf_api_headers_mode "$mode"
    tmp=$(mktemp)
    if [ -n "$data" ]; then
        if ! status=$(curl -sS -o "$tmp" -w '%{http_code}' -X "$method" "${CF_API_HEADERS[@]}" --data "$data" "$CF_API_BASE$path"); then
            curl_status=$?
        fi
    else
        if ! status=$(curl -sS -o "$tmp" -w '%{http_code}' -X "$method" "${CF_API_HEADERS[@]}" "$CF_API_BASE$path"); then
            curl_status=$?
        fi
    fi
    CF_API_LAST_STATUS="${status:-000}"
    CF_API_LAST_BODY=$(cat "$tmp")
    rm -f "$tmp"
    CF_API_LAST_SUCCESS="$(cf_api_success "$CF_API_LAST_BODY")"
    if [ "$curl_status" -ne 0 ]; then
        return 1
    fi
    if [ "$CF_API_LAST_STATUS" -lt 200 ] || [ "$CF_API_LAST_STATUS" -ge 300 ]; then
        return 1
    fi
    if [ "$CF_API_LAST_SUCCESS" != "true" ]; then
        return 1
    fi
    return 0
}

cf_api_request() {
    local method="$1"
    local path="$2"
    local data="${3-}"
    local checked="${4-}"
    cf_auth_mode || err "Account API token (CF_API_TOKEN) or Global API Key + email (CF_API_KEY+CF_API_EMAIL) required"
    if [ "$checked" = "checked" ]; then
        local body
        if ! cf_api_request_mode_checked "$CF_AUTH_MODE" "$method" "$path" "$data"; then
            body="${CF_API_LAST_BODY-}"
            local errors
            errors=$(cf_api_error_messages "$body")
            if [ -n "$errors" ]; then
                fail "Cloudflare API request failed: $errors"
            else
                fail "Cloudflare API request failed (status ${CF_API_LAST_STATUS:-unknown})"
            fi
            echo "$body"
            return 1
        fi
        body="${CF_API_LAST_BODY-}"
        echo "$body"
        return 0
    fi
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
