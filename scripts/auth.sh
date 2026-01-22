#!/bin/bash
# auth.sh - Cloudflare auth helpers and API request utilities

set -euo pipefail

CF_API_BASE="${CF_API_BASE:-https://api.cloudflare.com/client/v4}"

cf_log_once() {
    local flag="$1"
    shift
    if [ -z "${!flag-}" ]; then
        log "$@"
        printf -v "$flag" '1'
    fi
}

cf_has_env() {
    local var="$1"
    [ -n "${!var:-}" ]
}

cf_has_all() {
    local var
    for var in "$@"; do
        cf_has_env "$var" || return 1
    done
    return 0
}

cf_has_token() { cf_has_env CF_API_TOKEN; }
cf_has_key() { cf_has_all CF_API_KEY CF_API_EMAIL; }
cf_has_ca_key() { cf_has_env CF_CA_KEY; }
cf_has_account_id() { cf_has_env CF_ACCOUNT_ID; }
cf_has_zone_id() { cf_has_env CF_ZONE_ID; }

cf_reset_auth_vars() {
    unset CF_API_TOKEN CF_API_KEY CF_API_EMAIL CF_CA_KEY
    unset CF_ACCOUNT_ID CF_ACCOUNT_NAME CF_ZONE_ID CF_ZONE CF_ZONE_IDS CF_AUTH CF_ZONE_ID_SOURCE
}

cf_require_token() {
    local context="${1:-}"
    if ! cf_has_token; then
        if [ -n "$context" ]; then
            err "CF_API_TOKEN required $context"
        fi
        err "CF_API_TOKEN required"
    fi
}

cf_require_key() {
    local context="${1:-}"
    if ! cf_has_key; then
        if [ -n "$context" ]; then
            err "CF_API_KEY+CF_API_EMAIL required $context"
        fi
        err "CF_API_KEY+CF_API_EMAIL required"
    fi
}

cf_require_ca_key() {
    local context="${1:-}"
    if ! cf_has_ca_key; then
        if [ -n "$context" ]; then
            err "CF_CA_KEY required $context"
        fi
        err "CF_CA_KEY required"
    fi
}

load_cloudflare_auth() {
    local auth_file="${1:-${CF_AUTH_FILE:-$HOME/.config/cloudflare/default.auth}}"
    local prev_account_id="${CF_ACCOUNT_ID-}"
    local prev_account_name="${CF_ACCOUNT_NAME-}"
    local prev_api_token="${CF_API_TOKEN-}"
    local prev_api_email="${CF_API_EMAIL-}"
    local prev_api_key="${CF_API_KEY-}"
    local prev_auth="${CF_AUTH-}"
    local prev_zone_id="${CF_ZONE_ID-}"
    local prev_zone="${CF_ZONE-}"
    local prev_ca_key="${CF_CA_KEY-}"
    local prev_zone_ids="${CF_ZONE_IDS-}"

    local all_zone_ids=""

    if [ -f "$auth_file" ]; then
        all_zone_ids=$(awk -F= '/^[[:space:]]*CF_ZONE_ID=/{gsub(/^[[:space:]]*CF_ZONE_ID=|["'\'']/, "", $0); print $0}' "$auth_file")

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
    if [ -n "$prev_account_name" ]; then
        CF_ACCOUNT_NAME="$prev_account_name"
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
    else
        unset CF_ZONE_ID
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
    else
        unset CF_ZONE
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
    local has_token=false
    local has_key=false
    if cf_has_token; then
        has_token=true
    fi
    if cf_has_key; then
        has_key=true
    fi
    case "$mode" in
        ""|auto)
            if [ "$has_token" = true ] && [ "$has_key" = true ]; then
                cf_log_once CF_AUTH_NOTICE_AUTO_BOTH "CF_AUTH=auto with both token and key; using key"
            fi
            if [ "$has_key" = true ]; then
                CF_AUTH_MODE="key"
                return 0
            fi
            if [ "$has_token" = true ]; then
                CF_AUTH_MODE="token"
                return 0
            fi
            return 1
            ;;
        token)
            if [ "$has_key" = true ]; then
                cf_log_once CF_AUTH_NOTICE_TOKEN_IGNORED "CF_AUTH=token set; ignoring CF_API_KEY/CF_API_EMAIL"
            fi
            cf_require_token "when --auth token is set"
            CF_AUTH_MODE="token"
            return 0
            ;;
        key)
            if [ "$has_token" = true ]; then
                cf_log_once CF_AUTH_NOTICE_KEY_IGNORED "CF_AUTH=key set; ignoring CF_API_TOKEN"
            fi
            cf_require_key "when --auth key is set"
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

cf_auth_from_csv() {
    local domain="${1-}"
    [ -n "$domain" ] || return 1
    if [ -n "${CF_AUTH_FILE-}" ] && [ -n "${CF_ZONE_ID-}" ] && [ -n "${CF_ACCOUNT_ID-}" ]; then
        return 0
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        return 1
    fi
    if ! command -v csv_get_domain_fields >/dev/null 2>&1; then
        return 1
    fi

    local normalized row csv_auth_file csv_zone_id csv_account_id
    if command -v normalize_domain >/dev/null 2>&1; then
        normalized=$(normalize_domain "$domain")
    else
        normalized="$domain"
    fi
    row=$(csv_get_domain_fields "$normalized" auth_file zone_id account_id 2>/dev/null || true)
    if [ -z "$row" ] && [[ "$normalized" == www.* ]]; then
        row=$(csv_get_domain_fields "${normalized#www.}" auth_file zone_id account_id 2>/dev/null || true)
    fi
    [ -n "$row" ] || return 1
    IFS=$'\t' read -r csv_auth_file csv_zone_id csv_account_id <<<"$row"
    if [ -z "${CF_AUTH_FILE-}" ] && [ -n "$csv_auth_file" ]; then
        CF_AUTH_FILE="$csv_auth_file"
    fi
    if [ -z "${CF_ACCOUNT_ID-}" ] && [ -z "${CF_ACCOUNT_ID_CLI-}" ] && [ -n "$csv_account_id" ]; then
        CF_ACCOUNT_ID="$csv_account_id"
    fi
    return 0
}

cf_normalize_domain() {
    local domain="${1-}"
    if command -v normalize_domain >/dev/null 2>&1; then
        normalize_domain "$domain"
    else
        printf '%s' "${domain,,}"
    fi
}

cf_zone_id_from_auth() {
    local domain="${1-}"
    local auth_file="${2:-${CF_AUTH_FILE:-$HOME/.config/cloudflare/default.auth}}"
    [ -n "$domain" ] || return 2
    [ -f "$auth_file" ] || return 2

    local normalized
    normalized=$(cf_normalize_domain "$domain")
    normalized="${normalized#www.}"

    local zone_id
    zone_id=$(awk -v target="$normalized" '
        function clean(s) {
            gsub(/^[ \t]*CF_ZONE(_ID)?=|["'\'' ]/, "", s)
            return s
        }
        BEGIN { match=0 }
        /^[[:space:]]*CF_ZONE=/ {
            if (match == 1) { exit 3 }
            zone=clean($0)
            match=(zone != "" && tolower(zone) == tolower(target)) ? 1 : 0
            next
        }
        /^[[:space:]]*CF_ZONE_ID=/ {
            if (match == 1) {
                id=clean($0)
                if (id == "") { exit 3 }
                print id
                exit 0
            }
            next
        }
        END {
            if (match == 1) { exit 3 }
            exit 1
        }
    ' "$auth_file")
    case "$?" in
        0) printf '%s' "$zone_id"; return 0 ;;
        1) return 1 ;;
        2) return 2 ;;
        3) return 3 ;;
    esac
}

cf_zone_id_from_csv() {
    local domain="${1-}"
    [ -n "$domain" ] || return 2
    if ! command -v csv_get_domain_fields >/dev/null 2>&1; then
        return 2
    fi
    local normalized row csv_zone_id
    normalized=$(cf_normalize_domain "$domain")
    row=$(csv_get_domain_fields "$normalized" zone_id 2>/dev/null || true)
    if [ -z "$row" ] && [[ "$normalized" == www.* ]]; then
        row=$(csv_get_domain_fields "${normalized#www.}" zone_id 2>/dev/null || true)
    fi
    [ -n "$row" ] || return 1
    csv_zone_id="$row"
    if [ -n "$csv_zone_id" ]; then
        printf '%s' "$csv_zone_id"
        return 0
    fi
    return 3
}

cf_zone_id_from_api() {
    local domain="${1-}"
    [ -n "$domain" ] || return 2
    local normalized
    normalized=$(cf_normalize_domain "$domain")
    normalized="${normalized#www.}"
    cf_resolve_zone_id "$normalized"
}

cf_zone_id_for_domain() {
    local domain="${1-}"
    [ -n "$domain" ] || return 1

    local zone_id status
    zone_id=$(cf_zone_id_from_auth "$domain")
    status=$?
    if [ "$status" -eq 0 ]; then
        CF_ZONE_ID="$zone_id"
        CF_ZONE_ID_SOURCE="auth-file"
        return 0
    fi
    if [ "$status" -eq 3 ]; then
        warn "Auth file has zone name without zone id for domain: $domain"
    fi

    zone_id=$(cf_zone_id_from_csv "$domain")
    status=$?
    if [ "$status" -eq 0 ]; then
        CF_ZONE_ID="$zone_id"
        CF_ZONE_ID_SOURCE="csv"
        return 0
    fi
    if [ "$status" -eq 3 ]; then
        warn "CSV entry missing zone id for domain: $domain"
    fi

    zone_id=$(cf_zone_id_from_api "$domain")
    status=$?
    if [ "$status" -eq 0 ]; then
        CF_ZONE_ID="$zone_id"
        CF_ZONE_ID_SOURCE="api"
        return 0
    fi

    return "$status"
}

cf_resolve_account_name() {
    local name="$1"
    [ -n "$name" ] || err "account name is empty"
    cf_require_auth "to resolve account name"
    local encoded
    encoded=$(jq -rn --arg name "$name" '$name|@uri')
    local resp
    resp=$(cf_api_request GET "/accounts?name=${encoded}")
    if [ "$(cf_api_success "$resp")" != "true" ]; then
        err "Failed to query accounts: $(cf_api_error_messages "$resp")"
    fi
    local acct_id
    acct_id=$(echo "$resp" | jq -r '.result[0].id // empty')
    [ -n "$acct_id" ] || err "No account found for name: $name"
    echo "$acct_id"
}

cf_require_account_id() {
    local context="${1:-}"
    if ! cf_has_account_id && [ -n "${CF_ACCOUNT_NAME:-}" ]; then
        CF_ACCOUNT_ID=$(cf_resolve_account_name "$CF_ACCOUNT_NAME")
    fi
    if ! cf_has_account_id; then
        if [ -n "$context" ]; then
            err "CF_ACCOUNT_ID required $context"
        fi
        err "CF_ACCOUNT_ID required"
    fi
}

cf_resolve_zone_id() {
    local name="$1"
    [ -n "$name" ] || err "zone name is empty"
    cf_require_auth "to resolve zone name"
    local resp
    resp=$(cf_api_request GET "/zones?name=${name}&status=active")
    if [ "$(cf_api_success "$resp")" != "true" ]; then
        err "Failed to query zones: $(cf_api_error_messages "$resp")"
    fi
    local zone_id
    zone_id=$(echo "$resp" | jq -r '.result[0].id // empty')
    [ -n "$zone_id" ] || err "No active zone found for name: $name"
    local zone_name
    zone_name=$(echo "$resp" | jq -r '.result[0].name // empty')
    if [ -n "$zone_name" ]; then
        CF_ZONE="$zone_name"
    fi
    echo "$zone_id"
}

cf_require_zone_id() {
    local context="${1:-}"
    local domain="${2:-}"
    if cf_has_zone_id; then
        return 0
    fi
    if [ -n "${CF_ZONE:-}" ]; then
        domain="$CF_ZONE"
    fi
    if [ -n "$domain" ]; then
        cf_zone_id_for_domain "$domain" || true
    fi
    if ! cf_has_zone_id; then
        if [ -n "$context" ]; then
            err "CF_ZONE_ID required $context"
        fi
        err "CF_ZONE_ID required"
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
        account-name=*) CF_ACCOUNT_NAME_CLI="${opt#*=}"; return 0 ;;
        account-name)
            [ -n "$val" ] || err "account-name requires a value"
            CF_ACCOUNT_NAME_CLI="$val"
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
    [ -n "${CF_ACCOUNT_NAME_CLI:-}" ] && CF_ACCOUNT_NAME="$CF_ACCOUNT_NAME_CLI"
    [ -n "${CF_ZONE_ID_CLI:-}" ] && CF_ZONE_ID="$CF_ZONE_ID_CLI"
    [ -n "${CF_ZONE_CLI:-}" ] && CF_ZONE="$CF_ZONE_CLI"
    if cf_has_account_id && [ -n "${CF_ACCOUNT_NAME:-}" ]; then
        cf_log_once CF_AUTH_NOTICE_ACCOUNT_BOTH "CF_ACCOUNT_ID and CF_ACCOUNT_NAME are both set; using CF_ACCOUNT_ID"
    fi
    if cf_has_zone_id && [ -n "${CF_ZONE:-}" ]; then
        cf_log_once CF_AUTH_NOTICE_ZONE_BOTH "CF_ZONE_ID and CF_ZONE are both set; using CF_ZONE_ID"
    fi
    return 0
}

cf_api_headers_mode() {
    local mode="$1"
    CF_API_HEADERS=("-H" "Content-Type: application/json")
    if [ "$mode" = "token" ]; then
        cf_require_token "for token auth"
        CF_API_HEADERS+=("-H" "Authorization: Bearer $CF_API_TOKEN")
        return 0
    fi
    if [ "$mode" = "key" ]; then
        cf_require_key "for key auth"
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
    cf_require_ca_key "for Origin CA requests"
    CF_API_HEADERS+=("-H" "X-Auth-User-Service-Key: $CF_CA_KEY")
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
