#!/bin/bash
# test-record.sh - Run validation checks and record status results in domains.csv.
# For options, environment variables, defaults see usage().
#
# Example: test-record.sh edge --domain example.com

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/auth.sh"
. "$SCRIPTS_DIR/cli.sh"

DOMAINS=()
COMMANDS=()
ALL_COMMANDS=(edge origin wp)
COMMAND_ALL=false
STATE_FILTER=""
SITE_TYPE_FILTER=""
DOMAINS_FILE="${DOMAINS_FILE:-$ROOT_DIR/domains.csv}"
AUTH_FILE_OVERRIDE=""
INCLUDE_IGNORE=false
USE_API=false
HTTP_TIMEOUT_LOCAL=""
HSTS_REQUIRED=""
DATASTORE_DATE="${DATASTORE_DATE-}"
RECORD_UPDATES=true
RECORD_DOWNGRADE=false

WORDPRESS_ROOT_LOCAL="$WORDPRESS_ROOT"
WP_ROOT_FROM_CLI=false
APACHE_DIR_LOCAL="$APACHE_DIR"
SSL_DIR_LOCAL="$SSL_DIR"
SSL_CERT_DIR_LOCAL="$SSL_CERT_DIR"
SSL_KEY_DIR_LOCAL="$SSL_KEY_DIR"
WP_MODE="auto"
WP_MODE_FROM_CLI=false
COMMON_PRIV_OPTS=()

usage() {
    cat <<EOF
test-record.sh - Run validation checks and record status results in domains.csv.
Example: test-record.sh edge --domain example.com

Commands:
  edge   Run edge checks (HTTP/DNS) for selected domains
  origin  Run Apache/vhost/cert checks for selected domains
  wp   Run WordPress checks for selected domains
  all  Run all commands (edge, origin, wp)

Options:
$(cli_usage_domain)
  --domains-file PATH [DOMAINS_FILE] (default: ./domains.csv)  Domain metadata source
  --state STATE  Filter domains by status_cf when using domains.csv (none, redirect, https, worker, ignore)
  --site-type TYPE  Filter domains by site_type when using domains.csv
  --include-ignore  Include status_cf=ignore or status_cf=worker domains when using domains.csv
$(cli_usage_date)
  --norecord  Skip domains.csv updates
  --downgrade  Allow status downgrades in domains.csv (overrides default)
  --api  Enable Cloudflare API checks for edge (requires zone_id)
  --auth-file PATH [CF_AUTH_FILE]  Auth file to use for API calls
  --auth token|key|auto [CF_AUTH]  Select which credential to use (default: auto)
  --token TOKEN [CF_API_TOKEN]  Set CF_API_TOKEN (account API token)
  --key KEY [CF_API_KEY]  Set CF_API_KEY (global API key)
  --email EMAIL [CF_API_EMAIL]  Set CF_API_EMAIL (global API key email)
  --ca-key KEY [CF_CA_KEY]  Set CF_CA_KEY (Origin CA User Service Key)
$(cli_usage_http_timeout)
$(cli_usage_hsts)
$(cli_usage_wp_root)
$(cli_usage_apache_dir)
$(cli_usage_ssl_dir)
  --multisite  Force multisite mode for WordPress checks
  --singlesite  Force single-site mode for WordPress checks
  --autosite (default)  Auto-detect WordPress mode
$(cli_usage_common_priv)
  --help  Show this help

Notes:
  - If explicit domains are provided, status and site_type filters are not applied, but skip site_types still apply.
  - When no commands are supplied, all commands are executed in the order shown above.
  - Edge checks are always read-only; origin and WordPress checks are read-only and depend on local filesystem access.
  - Status updates only record successful validations; failures do not downgrade status unless --downgrade is used with a new status.
  - Empty site_type values are normalized to "none"; site_type values "none", "ignore", and "worker" are skipped.
EOF
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                norecord) RECORD_UPDATES=false ;;
                downgrade) RECORD_DOWNGRADE=true ;;
                api) USE_API=true ;;
                include-ignore) INCLUDE_IGNORE=true ;;
                domains-file=*) DOMAINS_FILE="${OPTARG#*=}" ;;
                domains-file)
                    [ -n "${!OPTIND-}" ] || err "--domains-file requires a path"
                    DOMAINS_FILE="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                date|date=*)
                    if cli_date_opt "${OPTARG}" DATASTORE_DATE "${!OPTIND-}"; then
                        :
                    else
                        usage; exit 1
                    fi
                    ;;
                state=*) STATE_FILTER="${OPTARG#*=}" ;;
                state)
                    [ -n "${!OPTIND-}" ] || err "--state requires a value"
                    STATE_FILTER="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                site-type=*) SITE_TYPE_FILTER="${OPTARG#*=}" ;;
                site-type)
                    [ -n "${!OPTIND-}" ] || err "--site-type requires a value"
                    SITE_TYPE_FILTER="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                auth-file=*) AUTH_FILE_OVERRIDE="${OPTARG#*=}" ;;
                auth-file)
                    [ -n "${!OPTIND-}" ] || err "--auth-file requires a path"
                    AUTH_FILE_OVERRIDE="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                http-timeout|http-timeout=*)
                    if cli_http_timeout_opt "${OPTARG}" HTTP_TIMEOUT_LOCAL "${!OPTIND-}"; then
                        :
                    else
                        usage; exit 1
                    fi
                    ;;
                hsts|hsts=*)
                    if cli_hsts_opt "${OPTARG}" HSTS_REQUIRED "${!OPTIND-}"; then
                        :
                    else
                        usage; exit 1
                    fi
                    ;;
                wp-root|wp-root=*)
                    if cli_wp_root_opt "${OPTARG}" WORDPRESS_ROOT_LOCAL "${!OPTIND-}"; then
                        WP_ROOT_FROM_CLI=true
                    else
                        usage; exit 1
                    fi
                    ;;
                apache-dir|apache-dir=*)
                    if cli_apache_dir_opt "${OPTARG}" APACHE_DIR_LOCAL "${!OPTIND-}"; then
                        :
                    else
                        usage; exit 1
                    fi
                    ;;
                ssl-dir|ssl-dir=*)
                    if cli_ssl_dir_opt "${OPTARG}" SSL_DIR_LOCAL SSL_CERT_DIR_LOCAL SSL_KEY_DIR_LOCAL "${!OPTIND-}"; then
                        :
                    else
                        usage; exit 1
                    fi
                    ;;
                multisite)
                    WP_MODE="multisite"
                    WP_MODE_FROM_CLI=true
                    ;;
                singlesite)
                    WP_MODE="singlesite"
                    WP_MODE_FROM_CLI=true
                    ;;
                autosite)
                    WP_MODE="auto"
                    WP_MODE_FROM_CLI=true
                    ;;
                allow-root)
                    COMMON_PRIV_OPTS+=("--allow-root")
                    ;;
                no-sudo)
                    COMMON_PRIV_OPTS+=("--no-sudo")
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

for arg in "$@"; do
    case "$arg" in
        all)
            COMMANDS=("${ALL_COMMANDS[@]}")
            COMMAND_ALL=true
            ;;
        edge|origin|wp)
            if [ "$COMMAND_ALL" != true ]; then
                COMMANDS+=("$arg")
            fi
            ;;
        *)
            DOMAINS+=("$arg")
            ;;
    esac
done

finalize_domains DOMAINS || { usage; exit 1; }

if [ ${#COMMANDS[@]} -eq 0 ]; then
    COMMANDS=("${ALL_COMMANDS[@]}")
fi

section "ORCH" "Selection"
kv "COMMANDS" "${COMMANDS[*]}"
if [ ${#DOMAINS[@]} -gt 0 ]; then
    kv "DOMAINS" "${DOMAINS[*]}"
fi
kv "DOMAINS_FILE" "$DOMAINS_FILE"

require_cmds python3

export DOMAINS_FILE

EDGE_AUTH_ARGS=()
[ -n "${CF_AUTH_CLI-}" ] && EDGE_AUTH_ARGS+=("--auth" "$CF_AUTH_CLI")
[ -n "${CF_API_TOKEN_CLI-}" ] && EDGE_AUTH_ARGS+=("--token" "$CF_API_TOKEN_CLI")
[ -n "${CF_API_KEY_CLI-}" ] && EDGE_AUTH_ARGS+=("--key" "$CF_API_KEY_CLI")
[ -n "${CF_API_EMAIL_CLI-}" ] && EDGE_AUTH_ARGS+=("--email" "$CF_API_EMAIL_CLI")
[ -n "${CF_CA_KEY_CLI-}" ] && EDGE_AUTH_ARGS+=("--ca-key" "$CF_CA_KEY_CLI")
[ -n "${CF_ACCOUNT_ID_CLI-}" ] && EDGE_AUTH_ARGS+=("--account" "$CF_ACCOUNT_ID_CLI")
[ -n "${CF_ACCOUNT_NAME_CLI-}" ] && EDGE_AUTH_ARGS+=("--account-name" "$CF_ACCOUNT_NAME_CLI")

declare -A DOMAIN_STATUS=()
declare -A DOMAIN_SITE_TYPE=()
declare -A DOMAIN_AUTH_FILE=()
declare -A DOMAIN_ZONE_ID=()
declare -A DOMAIN_WP_ROOT=()
declare -A DOMAIN_REDIRECT_URL=()
DOMAIN_ORDER=()

load_domain_meta() {
    [ -f "$DOMAINS_FILE" ] || return 0
    local rows
    if command -v python3 >/dev/null 2>&1; then
        rows=$(python3 - "$DOMAINS_FILE" <<'EOF'
import csv
import sys

path = sys.argv[1]
with open(path, newline="") as fh:
    reader = csv.DictReader(fh)
    for row in reader:
        domain = (row.get("domain") or "").strip()
        status = (row.get("status_cf") or "").strip()
        site_type = (row.get("site_type") or "").strip()
        auth_file = (row.get("auth_file") or "").strip()
        zone_id = (row.get("zone_id") or "").strip()
        wp_root = (row.get("wp_root") or "").strip()
        redirect_url = (row.get("redirect_url") or "").strip()
        if domain:
            print(f"{domain}\t{status}\t{site_type}\t{auth_file}\t{zone_id}\t{wp_root}\t{redirect_url}")
EOF
)
    else
        warn "python3 not available; reading $DOMAINS_FILE with awk"
        rows=$(awk -F, 'NR==1{for(i=1;i<=NF;i++){if($i=="domain")d=i;if($i=="status_cf")s=i;if($i=="site_type")t=i;if($i=="auth_file")a=i;if($i=="zone_id")z=i;if($i=="wp_root")w=i;if($i=="redirect_url")r=i}next} {if($d!="") print $d "\t" $s "\t" $t "\t" $a "\t" $z "\t" $w "\t" $r}' "$DOMAINS_FILE")
    fi
    local domain status site_type auth_file zone_id wp_root redirect_url key
    while IFS=$'\t' read -r domain status site_type auth_file zone_id wp_root redirect_url; do
        [ -n "$domain" ] || continue
        key=$(normalize_domain "$domain")
        DOMAIN_ORDER+=("$key")
        DOMAIN_STATUS["$key"]="$status"
        site_type=$(normalize_site_type "$site_type")
        DOMAIN_SITE_TYPE["$key"]="$site_type"
        DOMAIN_AUTH_FILE["$key"]="$auth_file"
        DOMAIN_ZONE_ID["$key"]="$zone_id"
        DOMAIN_WP_ROOT["$key"]="$wp_root"
        DOMAIN_REDIRECT_URL["$key"]="$redirect_url"
    done <<<"$rows"
}

load_domain_meta

select_domains() {
    local selected=()
    if [ ${#DOMAINS[@]} -gt 0 ]; then
        selected=("${DOMAINS[@]}")
    else
        local state_filter site_filter
        state_filter=$(tolower "$(trim_spaces "$STATE_FILTER")")
        site_filter=""
        if [ -n "${SITE_TYPE_FILTER-}" ]; then
            site_filter=$(normalize_site_type "$SITE_TYPE_FILTER")
        fi
        local domain status site_type
        for domain in "${DOMAIN_ORDER[@]}"; do
            status=$(tolower "${DOMAIN_STATUS[$domain]-}")
            site_type=$(normalize_site_type "${DOMAIN_SITE_TYPE[$domain]-}")
            if [ "$INCLUDE_IGNORE" != true ] && [ "$status" = "ignore" -o "$status" = "worker" ]; then
                continue
            fi
            if [ -n "$state_filter" ] && [ "$status" != "$state_filter" ]; then
                continue
            fi
            if [ -n "$site_filter" ]; then
                case "$site_type" in
                    "$site_filter"*) ;;
                    *) continue ;;
                esac
            fi
            if site_type_is_skip "$site_type"; then
                continue
            fi
            selected+=("$domain")
        done
    fi
    local filtered=()
    local domain key site_type
    for domain in "${selected[@]}"; do
        key=$(normalize_domain "$domain")
        if [ -z "${DOMAIN_STATUS[$key]+x}" ] && [ -z "${DOMAIN_SITE_TYPE[$key]+x}" ]; then
            warn "Domain not found in $DOMAINS_FILE; treating site_type=none"
        fi
        site_type=$(normalize_site_type "${DOMAIN_SITE_TYPE[$key]-}")
        if site_type_is_skip "$site_type"; then
            warn "Skipping $domain (site_type=$site_type)"
            continue
        fi
        filtered+=("$domain")
    done
    selected=("${filtered[@]}")
    if [ ${#selected[@]} -eq 0 ]; then
        err "No domains selected"
    fi
    echo "${selected[@]}"
}

is_redirect_intent() {
    local domain="$1"
    local key site_type redirect_url
    key=$(normalize_domain "$domain")
    site_type=$(normalize_site_type "${DOMAIN_SITE_TYPE[$key]-}")
    redirect_url="${DOMAIN_REDIRECT_URL[$key]-}"
    if site_type_is_skip "$site_type"; then
        return 1
    fi
    if [[ "$site_type" == redirect* ]]; then
        return 0
    fi
    if [ -n "$redirect_url" ]; then
        warn "redirect_url set for $domain but site_type is '$site_type'; treating as non-redirect"
    fi
    return 1
}

resolve_wp_root() {
    local domain="$1"
    local site_type="$2"
    local key root
    key=$(normalize_domain "$domain")
    root="${DOMAIN_WP_ROOT[$key]-}"
    if [ -n "$root" ]; then
        echo "$root"
        return 0
    fi
    if [ "$WP_ROOT_FROM_CLI" = true ]; then
        echo "$WORDPRESS_ROOT_LOCAL"
        return 0
    fi
    if [ "${site_type}" = "singlesite" ]; then
        local normalized
        normalized=$(normalize_domain "$domain")
        root="/var/www/html/$normalized"
        log "Singlesite domain $domain using default wp_root $root" >&2
        echo "$root"
        return 0
    fi
    echo "$WORDPRESS_ROOT_LOCAL"
    return 0
}

wp_mode_flag_for() {
    local site_type="$1"
    if [ "$WP_MODE_FROM_CLI" = true ]; then
        case "$WP_MODE" in
            multisite) echo "--multisite" ;;
            singlesite) echo "--singlesite" ;;
            auto) echo "--autosite" ;;
        esac
        return 0
    fi
    case "$site_type" in
        multisite) echo "--multisite" ;;
        singlesite) echo "--singlesite" ;;
        *) echo "--autosite" ;;
    esac
}

run_edge() {
    local domains
    read -r -a domains <<<"$(select_domains)"
    local domain key auth_file zone_id ok
    for domain in "${domains[@]}"; do
        key=$(normalize_domain "$domain")
        auth_file="${AUTH_FILE_OVERRIDE:-${DOMAIN_AUTH_FILE[$key]-}}"
        zone_id="${DOMAIN_ZONE_ID[$key]-}"
        local edge_args=("${EDGE_AUTH_ARGS[@]}")
        [ -n "$HTTP_TIMEOUT_LOCAL" ] && edge_args+=("--http-timeout" "$HTTP_TIMEOUT_LOCAL")
        [ -n "$HSTS_REQUIRED" ] && edge_args+=("--hsts=$HSTS_REQUIRED")

        ok=true
        if [ "$USE_API" = true ] && [ -n "$zone_id" ]; then
            if [ -n "$auth_file" ]; then
                if ! CF_ZONE_ID="$zone_id" "$SCRIPTS_DIR/check-edge.sh" --api --auth-file "$auth_file" "${edge_args[@]}" "$domain"; then
                    ok=false
                fi
            elif [ ${#EDGE_AUTH_ARGS[@]} -gt 0 ]; then
                if ! CF_ZONE_ID="$zone_id" "$SCRIPTS_DIR/check-edge.sh" --api "${edge_args[@]}" "$domain"; then
                    ok=false
                fi
            else
                warn "Missing auth_file for $domain; running edge checks without --api"
                if ! "$SCRIPTS_DIR/check-edge.sh" "${edge_args[@]}" "$domain"; then
                    ok=false
                fi
            fi
        else
            if ! "$SCRIPTS_DIR/check-edge.sh" "${edge_args[@]}" "$domain"; then
                ok=false
            fi
        fi

        if [ "$ok" = true ] && [ "$RECORD_UPDATES" = true ]; then
            if is_redirect_intent "$domain"; then
                csv_put_fields "$DOMAINS_FILE" "$domain" "$RECORD_DOWNGRADE" "status_cf=redirect"
            else
                csv_put_fields "$DOMAINS_FILE" "$domain" "$RECORD_DOWNGRADE" "status_cf=https"
            fi
        fi
        if [ "$ok" != true ]; then
            overall_ok=false
        fi
    done
}

run_origin() {
    local domains
    read -r -a domains <<<"$(select_domains)"
    local domain key site_type root ok
    for domain in "${domains[@]}"; do
        if is_redirect_intent "$domain"; then
            log "Redirect-only domain; origin checks skipped: $domain"
            continue
        fi
        key=$(normalize_domain "$domain")
        site_type=$(normalize_site_type "${DOMAIN_SITE_TYPE[$key]-}")
        if ! root=$(resolve_wp_root "$domain" "$site_type"); then
            overall_ok=false
            continue
        fi
        ok=true
        if ! "$SCRIPTS_DIR/check-origin.sh" "${COMMON_PRIV_OPTS[@]}" --wp-root "$root" --apache-dir "$APACHE_DIR_LOCAL" --ssl-dir "$SSL_DIR_LOCAL" "$domain"; then
            ok=false
        fi
        if [ "$ok" = true ] && [ "$RECORD_UPDATES" = true ]; then
            csv_put_fields "$DOMAINS_FILE" "$domain" "$RECORD_DOWNGRADE" "status_origin=apache"
        fi
        if [ "$ok" != true ]; then
            overall_ok=false
        fi
    done
}

run_wp() {
    local domains
    read -r -a domains <<<"$(select_domains)"
    local domain key site_type root mode_flag ok
    for domain in "${domains[@]}"; do
        if is_redirect_intent "$domain"; then
            log "Redirect-only domain; WordPress checks skipped: $domain"
            continue
        fi
        key=$(normalize_domain "$domain")
        site_type=$(normalize_site_type "${DOMAIN_SITE_TYPE[$key]-}")
        if ! root=$(resolve_wp_root "$domain" "$site_type"); then
            overall_ok=false
            continue
        fi
        mode_flag=$(wp_mode_flag_for "$site_type")
        ok=true
        if ! "$SCRIPTS_DIR/check-wp.sh" "$mode_flag" "${COMMON_PRIV_OPTS[@]}" --wp-root "$root" "$domain"; then
            ok=false
        fi
        if [ "$ok" = true ] && [ "$RECORD_UPDATES" = true ]; then
            csv_put_fields "$DOMAINS_FILE" "$domain" "$RECORD_DOWNGRADE" "status_wp=config"
        fi
        if [ "$ok" != true ]; then
            overall_ok=false
        fi
    done
}

overall_ok=true
for cmd in "${COMMANDS[@]}"; do
    section "ORCH" "Run"
    kv "COMMAND" "$cmd"
    case "$cmd" in
        edge) run_edge ;;
        origin) run_origin ;;
        wp) run_wp ;;
        *) err "Unknown command: $cmd" ;;
    esac
done

if [ "$overall_ok" != true ]; then
    exit 1
fi
section "ORCH" "Results"
status_pass "run=ok"
