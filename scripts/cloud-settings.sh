#!/bin/bash
# cloud-settings.sh - Apply Cloudflare HTTPS and security settings to zones.
# For options, environment variables, defaults see usage().
#
# Example: cloud-settings.sh --site-types redirect,multisite

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/auth.sh"
. "$SCRIPTS_DIR/cli.sh"

DOMAINS=()
DOMAINS_FILE="${DOMAINS_FILE:-$ROOT_DIR/domains.csv}"
SITE_TYPES_RAW="${SITE_TYPES_RAW:-redirect,multisite}"
DRY_RUN=false

SSL_MODE="${CF_SSL_MODE:-strict}"
ALWAYS_USE_HTTPS="${CF_ALWAYS_USE_HTTPS:-on}"
MIN_TLS_VERSION="${CF_MIN_TLS_VERSION:-1.2}"
MANAGED_ADD_SECURITY_HEADERS="${CF_MANAGED_ADD_SECURITY_HEADERS:-true}"

usage() {
    cat <<EOF
cloud-settings.sh - Apply Cloudflare HTTPS and security settings to zones.
Example: cloud-settings.sh --site-types redirect,multisite

Options:
$(cli_usage_domain)
  --domains-file PATH [DOMAINS_FILE] (default: ./domains.csv)  Inventory CSV path
  --site-types LIST [SITE_TYPES_RAW] (default: redirect,multisite)  Comma list of site_type values
  --ssl MODE [CF_SSL_MODE] (default: strict)  off|flexible|full|strict
  --always-use-https MODE [CF_ALWAYS_USE_HTTPS] (default: on)  on|off
  --min-tls-version VER [CF_MIN_TLS_VERSION] (default: 1.2)  1.0|1.1|1.2|1.3
  --managed-add-security-headers BOOL [CF_MANAGED_ADD_SECURITY_HEADERS] (default: true)  true|false
  --dry-run  Show planned changes without API writes

Auth options:
  --auth token|key|auto [CF_AUTH]  Select which credential to use (default: auto)
  --auth-file PATH [CF_AUTH_FILE] (default: ~/.config/cloudflare/default.auth)  Auth file to load
  --token TOKEN [CF_API_TOKEN]  Set CF_API_TOKEN (account API token)
  --key KEY [CF_API_KEY]  Set CF_API_KEY (global API key)
  --email EMAIL [CF_API_EMAIL]  Set CF_API_EMAIL (global API key email)
  --account ID [CF_ACCOUNT_ID]  Cloudflare account ID (optional)
  --account-name NAME [CF_ACCOUNT_NAME]  Cloudflare account name (optional)
  --help  Show this help

Notes:
  - If no domains are provided, this script selects domains by site_type from domains.csv.
  - Domains with site_type none, ignore, or worker are skipped.
EOF
}

normalize_ssl_mode() {
    local val
    val=$(trim_spaces "$1")
    val=$(tolower "$val")
    case "$val" in
        off|flexible|full|strict) echo "$val" ;;
        *) err "--ssl must be off, flexible, full, or strict" ;;
    esac
}

normalize_switch() {
    local val
    val=$(trim_spaces "$1")
    val=$(tolower "$val")
    case "$val" in
        on|true|yes|y) echo "on" ;;
        off|false|no|n) echo "off" ;;
        *) err "--always-use-https must be on or off" ;;
    esac
}

normalize_tls_version() {
    local val
    val=$(trim_spaces "$1")
    case "$val" in
        1.0|1.1|1.2|1.3) echo "$val" ;;
        *) err "--min-tls-version must be 1.0, 1.1, 1.2, or 1.3" ;;
    esac
}

normalize_bool_strict() {
    local val
    val=$(trim_spaces "$1")
    val=$(tolower "$val")
    case "$val" in
        true|yes|y|on) echo "true" ;;
        false|no|n|off) echo "false" ;;
        *) err "--managed-add-security-headers must be true or false" ;;
    esac
}

load_domains_from_csv() {
    DOMAINS=()
    local domain_list=""
    domain_list=$(python3 - "$DOMAINS_FILE" "$SITE_TYPES_RAW" <<'EOF'
import csv
import sys

path = sys.argv[1]
raw_types = sys.argv[2]
wanted = {t.strip().lower() for t in raw_types.split(",") if t.strip()}
if not wanted:
    sys.exit(0)

def normalize_site_type(raw):
    raw = (raw or "").strip().lower()
    if not raw:
        return "none"
    if raw.startswith("redirect"):
        return "redirect"
    return raw

with open(path, newline="") as fh:
    reader = csv.DictReader(fh)
    for row in reader:
        domain = (row.get("domain") or "").strip()
        site_type = normalize_site_type(row.get("site_type"))
        if domain and site_type in wanted:
            print(domain)
EOF
)
    if [ -n "$domain_list" ]; then
        while IFS= read -r domain; do
            [ -n "$domain" ] || continue
            DOMAINS+=("$domain")
        done <<<"$domain_list"
    fi
}

apply_setting() {
    local domain="$1"
    local key="$2"
    local desired="$3"
    local current="$4"
    if [ -n "$current" ] && [ "$current" = "$desired" ]; then
        log "$domain: $key already $current"
        return 0
    fi
    if [ "$DRY_RUN" = true ]; then
        log "$domain: dry run would set $key=$desired (was ${current:-unknown})"
        return 0
    fi
    local payload response
    payload=$(jq -n --arg v "$desired" '{value:$v}')
    response=$(cf_api_request PATCH "/zones/${CF_ZONE_ID}/settings/${key}" "$payload")
    if [ "$(cf_api_success "$response")" != "true" ]; then
        err "Failed to update ${key} for ${domain}: $(cf_api_error_messages "$response")"
    fi
    log "$domain: set $key=$desired"
}

apply_managed_headers() {
    local domain="$1"
    local desired="$2"
    local current="$3"
    if [ -n "$current" ] && [ "$current" = "$desired" ]; then
        log "$domain: managed_add_security_headers already $current"
        return 0
    fi
    if [ "$DRY_RUN" = true ]; then
        log "$domain: dry run would set managed_add_security_headers=$desired (was ${current:-unknown})"
        return 0
    fi
    local payload response
    payload=$(jq -n --argjson enabled "$desired" \
        '{managed_response_headers:[{id:"add_security_headers", enabled:$enabled}] }')
    response=$(cf_api_request PATCH "/zones/${CF_ZONE_ID}/managed_headers" "$payload")
    if [ "$(cf_api_success "$response")" != "true" ]; then
        err "Failed to update managed headers for ${domain}: $(cf_api_error_messages "$response")"
    fi
    log "$domain: set managed_add_security_headers=$desired"
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                dry-run) DRY_RUN=true ;;
                domains-file=*) DOMAINS_FILE="${OPTARG#*=}" ;;
                domains-file)
                    [ -n "${!OPTIND-}" ] || err "--domains-file requires a path"
                    DOMAINS_FILE="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                site-types=*) SITE_TYPES_RAW="${OPTARG#*=}" ;;
                site-types)
                    [ -n "${!OPTIND-}" ] || err "--site-types requires a value"
                    SITE_TYPES_RAW="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                ssl=*) SSL_MODE="${OPTARG#*=}" ;;
                ssl)
                    [ -n "${!OPTIND-}" ] || err "--ssl requires a value"
                    SSL_MODE="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                always-use-https=*) ALWAYS_USE_HTTPS="${OPTARG#*=}" ;;
                always-use-https)
                    [ -n "${!OPTIND-}" ] || err "--always-use-https requires a value"
                    ALWAYS_USE_HTTPS="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                min-tls-version=*) MIN_TLS_VERSION="${OPTARG#*=}" ;;
                min-tls-version)
                    [ -n "${!OPTIND-}" ] || err "--min-tls-version requires a value"
                    MIN_TLS_VERSION="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                managed-add-security-headers=*) MANAGED_ADD_SECURITY_HEADERS="${OPTARG#*=}" ;;
                managed-add-security-headers)
                    [ -n "${!OPTIND-}" ] || err "--managed-add-security-headers requires a value"
                    MANAGED_ADD_SECURITY_HEADERS="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
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

AUTH_FILE_OVERRIDE="${CF_AUTH_FILE-}"

if [ ${#DOMAINS[@]} -eq 0 ]; then
    load_domains_from_csv
fi

finalize_domains DOMAINS || { usage; exit 1; }

SSL_MODE=$(normalize_ssl_mode "$SSL_MODE")
ALWAYS_USE_HTTPS=$(normalize_switch "$ALWAYS_USE_HTTPS")
MIN_TLS_VERSION=$(normalize_tls_version "$MIN_TLS_VERSION")
MANAGED_ADD_SECURITY_HEADERS=$(normalize_bool_strict "$MANAGED_ADD_SECURITY_HEADERS")

require_cmds curl jq python3

for domain in "${DOMAINS[@]}"; do
    domain=$(normalize_domain "$domain")
    log "Configuring Cloudflare settings for: $domain"

    auth_file=""
    site_type=""
    meta=$(csv_get_domain_fields "$domain" auth_file site_type || true)
    if [ -n "$meta" ]; then
        IFS=$'\t' read -r auth_file site_type <<<"$meta"
    fi

    site_type_norm=$(normalize_site_type "$site_type")
    if site_type_is_skip "$site_type_norm"; then
        warn "Skipping $domain (site_type=$site_type_norm)"
        continue
    fi

    if [ -n "$AUTH_FILE_OVERRIDE" ]; then
        CF_AUTH_FILE="$AUTH_FILE_OVERRIDE"
    else
        cf_reset_auth_vars
        CF_AUTH_FILE=""
        if [ -n "$auth_file" ]; then
            CF_AUTH_FILE="$auth_file"
        fi
    fi

    CF_ZONE_ID=""
    CF_ZONE=""
    cf_init_auth "${CF_AUTH_FILE-}"
    CF_ZONE="$domain"
    cf_require_auth "for Cloudflare settings update"
    cf_require_zone_id "for Cloudflare settings update" "$domain"

    section "SETTINGS" "ZoneSettings"
    kv "DOMAIN" "$domain"
    kv "ZONE_ID" "$CF_ZONE_ID"

    settings_json=$(cf_api_request GET "/zones/${CF_ZONE_ID}/settings")
    if [ "$(cf_api_success "$settings_json")" != "true" ]; then
        err "Failed to query zone settings: $(cf_api_error_messages "$settings_json")"
    fi
    settings_map=$(echo "$settings_json" | jq -c '.result | map({(.id): .value}) | add')

    current_ssl=$(echo "$settings_map" | jq -r '.ssl // empty')
    current_always=$(echo "$settings_map" | jq -r '.always_use_https // empty')
    current_min_tls=$(echo "$settings_map" | jq -r '.min_tls_version // empty')

    managed_headers_json=$(cf_api_request GET "/zones/${CF_ZONE_ID}/managed_headers")
    if [ "$(cf_api_success "$managed_headers_json")" != "true" ]; then
        err "Failed to query managed headers: $(cf_api_error_messages "$managed_headers_json")"
    fi
    current_managed=$(echo "$managed_headers_json" | jq -r '.result.managed_response_headers[]? | select(.id=="add_security_headers") | .enabled' | head -n 1)
    current_managed="${current_managed:-}"

    section "SETTINGS" "Baseline"
    apply_setting "$domain" "ssl" "$SSL_MODE" "$current_ssl"
    apply_setting "$domain" "always_use_https" "$ALWAYS_USE_HTTPS" "$current_always"
    apply_setting "$domain" "min_tls_version" "$MIN_TLS_VERSION" "$current_min_tls"
    apply_managed_headers "$domain" "$MANAGED_ADD_SECURITY_HEADERS" "$current_managed"
done

log "Done."
