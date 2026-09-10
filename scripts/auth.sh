#!/bin/bash
# auth.sh - Cloudflare auth helpers and API request utilities

set -euo pipefail

: "${COMMON_LOADED:?${BASH_SOURCE[0]##*/} requires common.sh to be sourced first.}"

AUTH_LOADED=1

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

auth_var() {
    kv_file_var "$@"
}

auth_values() {
    kv_file_values "$@"
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
        all_zone_ids=$(auth_values "$auth_file" CF_ZONE_ID || true)

        set -a
        # shellcheck disable=SC1090
        . "$auth_file"
        set +a
    else
        return 0
    fi

    # An auth file that sets CF_API_BASE="" (the shipped example did) would
    # otherwise leave every request pointed at a bare path.
    CF_API_BASE="${CF_API_BASE:-https://api.cloudflare.com/client/v4}"
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
    csv_split_row "$row" csv_auth_file csv_zone_id csv_account_id
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
    zone_id=$(python3 - "$auth_file" "$normalized" <<'PY'
import sys

path = sys.argv[1]
target = sys.argv[2].lower()
match = False
id_found = False

def clean(value: str) -> str:
    value = value.strip()
    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
        value = value[1:-1]
    return value.strip()

with open(path, "r") as fh:
    for line in fh:
        raw = line.strip()
        if not raw or raw.startswith("#"):
            continue
        if raw.startswith("CF_ZONE="):
            if match and not id_found:
                sys.exit(3)
            zone = clean(raw.split("=", 1)[1])
            match = (zone.lower() == target)
            id_found = False
            continue
        if raw.startswith("CF_ZONE_ID="):
            if match:
                zid = clean(raw.split("=", 1)[1])
                if not zid:
                    sys.exit(3)
                print(zid)
                sys.exit(0)
            continue

if match and not id_found:
    sys.exit(3)
sys.exit(1)
PY
)
    case "$?" in
        0)
            # A status-0 result with no zone id means the parser produced nothing
            # useful; treat it as a miss so the CSV and API fallbacks still run.
            [ -n "$zone_id" ] || return 1
            printf '%s' "$zone_id"; return 0 ;;
        1) return 1 ;;
        2) return 2 ;;
        3) return 3 ;;
        # Without this arm a case with no match returns 0, so python3 missing
        # (127), an IO error (2) or SIGINT (130) looked like success with an
        # empty zone id, and the caller skipped its fallbacks.
        *) return 1 ;;
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

# Look up a zone once and publish everything callers need about it.
#
# Four call sites each ran their own /zones?name= query and pulled different
# fields out of the response; two of them filtered status=active, which silently
# hides a zone that exists but is not yet delegated. A freshly created zone is
# "pending" until the registrar points at Cloudflare, so those callers reported a
# real zone as missing. This queries without a status filter and lets the caller
# decide what a non-active status means.
#
# Sets CF_LOOKUP_ZONE_ID, CF_LOOKUP_ZONE_NAME, CF_LOOKUP_ZONE_STATUS,
# CF_LOOKUP_ZONE_NS (space-separated FQDNs), and CF_LOOKUP_ZONE_ERROR.
#
# Returns 0 on a match, 1 when the zone does not exist, and 2 when the API call
# itself failed. Diagnostic callers need to tell "no such zone" apart from "could
# not ask", and must not be killed by one domain's transient API error, so this
# reports the failure instead of calling err.
CF_LOOKUP_ZONE_ID=""
CF_LOOKUP_ZONE_NAME=""
CF_LOOKUP_ZONE_STATUS=""
CF_LOOKUP_ZONE_NS=""
CF_LOOKUP_ZONE_ERROR=""

cf_lookup_zone() {
    local name="$1"
    [ -n "$name" ] || err "zone name is empty"
    cf_require_auth "to look up zone"

    CF_LOOKUP_ZONE_ID=""
    CF_LOOKUP_ZONE_NAME=""
    CF_LOOKUP_ZONE_STATUS=""
    CF_LOOKUP_ZONE_NS=""
    CF_LOOKUP_ZONE_ERROR=""

    local resp
    resp=$(cf_api_request GET "/zones?name=${name}")
    if [ "$(cf_api_success "$resp")" != "true" ]; then
        CF_LOOKUP_ZONE_ERROR=$(cf_api_error_messages "$resp")
        return 2
    fi

    CF_LOOKUP_ZONE_ID=$(echo "$resp" | jq -r '.result[0].id // empty')
    [ -n "$CF_LOOKUP_ZONE_ID" ] || return 1
    CF_LOOKUP_ZONE_NAME=$(echo "$resp" | jq -r '.result[0].name // empty')
    CF_LOOKUP_ZONE_STATUS=$(echo "$resp" | jq -r '.result[0].status // empty')
    CF_LOOKUP_ZONE_NS=$(echo "$resp" | jq -r '.result[0].name_servers[]?' | paste -sd ' ' -)
    return 0
}

# Report delegation for a zone already looked up by cf_lookup_zone, combining the
# Cloudflare-side status with what the public DNS actually answers. A zone can be
# "pending" only because Cloudflare has not rechecked yet, so the parent NS
# lookup is the authoritative signal.
#
# Echoes one of: delegated | pending | unknown
cf_zone_delegation_state() {
    local domain="$1"
    [ -n "$domain" ] || err "domain is required"
    local rc=0
    domain_delegated_ns "$domain" >/dev/null || rc=$?
    case "$rc" in
        0) echo "delegated" ;;
        2) echo "unknown" ;;
        *) echo "pending" ;;
    esac
}

cf_resolve_zone_id() {
    local name="$1"
    [ -n "$name" ] || err "zone name is empty"
    local __rc=0
    cf_lookup_zone "$name" || __rc=$?
    if [ "$__rc" -eq 2 ]; then
        err "Failed to query zones: $CF_LOOKUP_ZONE_ERROR"
    elif [ "$__rc" -ne 0 ]; then
        err "No zone found for name: $name"
    fi
    # Callers of this function act on a live zone, so a zone that exists but is
    # not yet active is still an error here -- but say which case it is. The old
    # status=active filter made a pending zone indistinguishable from a missing
    # one, sending operators to look for a zone that was already there.
    if [ "$CF_LOOKUP_ZONE_STATUS" != "active" ]; then
        err "Zone $name exists (${CF_LOOKUP_ZONE_ID}) but is ${CF_LOOKUP_ZONE_STATUS}, not active; set its nameservers at the registrar: ${CF_LOOKUP_ZONE_NS:-see Cloudflare dashboard}"
    fi
    if [ -n "$CF_LOOKUP_ZONE_NAME" ]; then
        CF_ZONE="$CF_LOOKUP_ZONE_NAME"
    fi
    echo "$CF_LOOKUP_ZONE_ID"
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
        token-file=*) CF_API_TOKEN_CLI=$(cf_read_secret_file "${opt#*=}" "API token"); return 0 ;;
        token-file)
            [ -n "$val" ] || err "token-file requires a path"
            CF_API_TOKEN_CLI=$(cf_read_secret_file "$val" "API token")
            return 0
            ;;
        token=*) cf_warn_secret_on_argv "token"; CF_API_TOKEN_CLI="${opt#*=}"; return 0 ;;
        token)
            [ -n "$val" ] || err "token requires a value"
            cf_warn_secret_on_argv "token"
            CF_API_TOKEN_CLI="$val"
            return 0
            ;;
        email=*) CF_API_EMAIL_CLI="${opt#*=}"; return 0 ;;
        email)
            [ -n "$val" ] || err "email requires a value"
            CF_API_EMAIL_CLI="$val"
            return 0
            ;;
        key-file=*) CF_API_KEY_CLI=$(cf_read_secret_file "${opt#*=}" "API key"); return 0 ;;
        key-file)
            [ -n "$val" ] || err "key-file requires a path"
            CF_API_KEY_CLI=$(cf_read_secret_file "$val" "API key")
            return 0
            ;;
        key=*) cf_warn_secret_on_argv "key"; CF_API_KEY_CLI="${opt#*=}"; return 0 ;;
        key)
            [ -n "$val" ] || err "key requires a value"
            cf_warn_secret_on_argv "key"
            CF_API_KEY_CLI="$val"
            return 0
            ;;
        ca-key-file=*) CF_CA_KEY_CLI=$(cf_read_secret_file "${opt#*=}" "Origin CA key"); return 0 ;;
        ca-key-file)
            [ -n "$val" ] || err "ca-key-file requires a path"
            CF_CA_KEY_CLI=$(cf_read_secret_file "$val" "Origin CA key")
            return 0
            ;;
        ca-key=*) cf_warn_secret_on_argv "ca-key"; CF_CA_KEY_CLI="${opt#*=}"; return 0 ;;
        ca-key)
            [ -n "$val" ] || err "ca-key requires a value"
            cf_warn_secret_on_argv "ca-key"
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

# Credentials are passed to curl through a -K config file, never on the command
# line. Anything in argv is readable by any local user via `ps auxww` for the
# lifetime of the request. The file is created under umask 077 and removed by the
# caller's trap.
#
# CF_API_CONFIG holds the path; CF_API_HEADERS carries only non-secret headers.
CF_API_CONFIG="${CF_API_CONFIG:-}"

cf_api_config_cleanup() {
    if [ -n "${CF_API_CONFIG:-}" ] && [ -f "$CF_API_CONFIG" ]; then
        rm -f "$CF_API_CONFIG"
    fi
    CF_API_CONFIG=""
}

# Read a secret from a file instead of the command line. A value passed as an
# option lands in the invoking script's argv (readable via `ps auxww`) and in
# shell history; a file does neither. The mode check refuses anything group- or
# world-readable.
cf_read_secret_file() {
    local path="$1"
    local label="$2"
    [ -f "$path" ] || err "${label} file not found: $path"
    local mode
    mode=$(stat -c '%a' "$path" 2>/dev/null) || err "Cannot stat ${label} file: $path"
    case "$mode" in
        600|400) ;;
        *) err "${label} file $path is mode ${mode}; use 600 so it is not readable by other users" ;;
    esac
    tr -d '\r\n' < "$path"
}

# Warn once per run when a secret is supplied as an option value.
CF_SECRET_ARGV_WARNED="${CF_SECRET_ARGV_WARNED:-false}"
cf_warn_secret_on_argv() {
    [ "$CF_SECRET_ARGV_WARNED" = true ] && return 0
    CF_SECRET_ARGV_WARNED=true
    warn "--$1 puts a secret in this process's argv (visible to other users via ps) and in shell history. Prefer --$1-file PATH, an auth file, or the environment. If you must type it, start the command with a leading space so it is kept out of history."
}

cf_api_headers_mode() {
    local mode="$1"
    CF_API_HEADERS=("-H" "Content-Type: application/json")

    cf_api_config_cleanup
    local old_umask
    old_umask=$(umask)
    umask 077
    CF_API_CONFIG=$(mktemp "${TMPDIR:-/tmp}/cf-api.XXXXXXXX") || err "Cannot create curl config"
    umask "$old_umask"
    trap cf_api_config_cleanup EXIT INT TERM

    if [ "$mode" = "token" ]; then
        cf_require_token "for token auth"
        printf 'header = "Authorization: Bearer %s"\n' "$CF_API_TOKEN" >"$CF_API_CONFIG"
        return 0
    fi
    if [ "$mode" = "key" ]; then
        cf_require_key "for key auth"
        printf 'header = "X-Auth-Key: %s"\nheader = "X-Auth-Email: %s"\n' \
            "$CF_API_KEY" "$CF_API_EMAIL" >"$CF_API_CONFIG"
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
        curl -sS -K "$CF_API_CONFIG" -X "$method" "${CF_API_HEADERS[@]}" --data "$data" "$CF_API_BASE$path"
        return
    fi
    curl -sS -K "$CF_API_CONFIG" -X "$method" "${CF_API_HEADERS[@]}" "$CF_API_BASE$path"
}

cf_api_request_mode_checked() {
    local mode="$1"
    local method="$2"
    local path="$3"
    local data="${4-}"
    local tmp status curl_status=0
    cf_api_headers_mode "$mode"
    # Response bodies can carry account data; do not leave them in TMPDIR if the
    # request is interrupted.
    local old_umask
    old_umask=$(umask); umask 077
    tmp=$(mktemp) || err "Cannot create temp file for API response"
    umask "$old_umask"
    trap 'rm -f "${tmp:-}"' INT TERM
    if [ -n "$data" ]; then
        if ! status=$(curl -sS -K "$CF_API_CONFIG" -o "$tmp" -w '%{http_code}' -X "$method" "${CF_API_HEADERS[@]}" --data "$data" "$CF_API_BASE$path"); then
            curl_status=$?
        fi
    else
        if ! status=$(curl -sS -K "$CF_API_CONFIG" -o "$tmp" -w '%{http_code}' -X "$method" "${CF_API_HEADERS[@]}" "$CF_API_BASE$path"); then
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

# Every request now goes through the status-checked path, so a transport error
# or a non-2xx response is recorded in CF_API_LAST_STATUS / CF_API_LAST_BODY and
# reported instead of vanishing. Previously the unchecked path ran curl with no
# --fail and no status capture: a 429, 502 or HTML error body produced empty
# stdout, cf_api_success("") returned "", and the caller printed an error with no
# message and no status code.
#
# Return semantics are deliberately unchanged for the default caller. Callers
# test the body with cf_api_success themselves, and some treat a failed GET as a
# normal branch (cloud-redirect.sh: "no ruleset yet, create one"). Returning
# non-zero here would abort those callers under `set -e` before their own
# handling runs, so the default still returns 0 and lets the body speak.
#
# Pass "checked" as the 4th argument to also get a non-zero return, for callers
# that want the failure to propagate (check-edge.sh does this).
cf_api_request() {
    local method="$1"
    local path="$2"
    local data="${3-}"
    local checked="${4-}"
    cf_auth_mode || err "Account API token (CF_API_TOKEN) or Global API Key + email (CF_API_KEY+CF_API_EMAIL) required"

    local body rc=0
    cf_api_request_mode_checked "$CF_AUTH_MODE" "$method" "$path" "$data" || rc=$?
    body="${CF_API_LAST_BODY-}"

    if [ "$rc" -ne 0 ]; then
        # Surface the transport/status detail the body alone cannot carry: an
        # empty body from a 502 or a connection failure otherwise reaches the
        # caller as a silent empty string.
        local errors
        errors=$(cf_api_error_messages "$body")
        if [ -n "$errors" ]; then
            fail "Cloudflare API ${method} ${path} failed (status ${CF_API_LAST_STATUS:-unknown}): $errors"
        else
            fail "Cloudflare API ${method} ${path} failed (status ${CF_API_LAST_STATUS:-unknown})"
        fi
    fi

    echo "$body"
    if [ "$checked" = "checked" ]; then
        return "$rc"
    fi
    return 0
}

cf_origin_ca_request() {
    local method="$1"
    local path="$2"
    local data="${3-}"
    CF_API_HEADERS=("-H" "Content-Type: application/json")
    cf_require_ca_key "for Origin CA requests"

    # Same rule as cf_api_headers_mode: the Origin CA key goes in the -K config
    # file, not in argv.
    cf_api_config_cleanup
    local old_umask
    old_umask=$(umask)
    umask 077
    CF_API_CONFIG=$(mktemp "${TMPDIR:-/tmp}/cf-api.XXXXXXXX") || err "Cannot create curl config"
    umask "$old_umask"
    trap cf_api_config_cleanup EXIT INT TERM
    printf 'header = "X-Auth-User-Service-Key: %s"\n' "$CF_CA_KEY" >"$CF_API_CONFIG"
    if [ -n "$data" ]; then
        curl -sS -K "$CF_API_CONFIG" -X "$method" "${CF_API_HEADERS[@]}" --data "$data" "$CF_API_BASE$path"
        return
    fi
    curl -sS -K "$CF_API_CONFIG" -X "$method" "${CF_API_HEADERS[@]}" "$CF_API_BASE$path"
}

cf_api_success() {
    local response="$1"
    if command -v jq >/dev/null 2>&1; then
        # A non-JSON body (an HTML 502 page, an empty transport failure) must
        # yield "" rather than spraying jq parse errors onto stderr.
        echo "$response" | jq -r 'if .success == true then "true" elif .success == false then "false" else "" end' 2>/dev/null
        return
    fi
    echo "$response" | tr -d '\n' | sed -n 's/.*"success":\(true\|false\).*/\1/p'
}

cf_api_error_messages() {
    local response="$1"
    if command -v jq >/dev/null 2>&1; then
        echo "$response" | jq -r '.errors[].message // empty' 2>/dev/null | tr '\n' ' '
        return
    fi
    echo ""
}
