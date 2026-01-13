#!/bin/bash
# smoke.sh - Run syntax checks, unit tests, and read-only edge/dns checks.
# For options, environment variables, defaults see usage().
#
# Example: smoke.sh syn unit

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/cli.sh"

DOMAINS=()
COMMANDS=()
ALL_COMMANDS=(syn unit edge dns origin wp mysql)
COMMAND_ALL=false
STATE_FILTER=""
SITE_TYPE_FILTER=""
DOMAINS_FILE="${DOMAINS_FILE:-$ROOT_DIR/domains.csv}"
AUTH_FILE_OVERRIDE=""
INCLUDE_IGNORE=false
USE_API=false
WORDPRESS_ROOT_LOCAL="$WORDPRESS_ROOT"
WP_ROOT_FROM_CLI=false
APACHE_DIR_LOCAL="$APACHE_DIR"
SSL_DIR_LOCAL="$SSL_DIR"
SSL_CERT_DIR_LOCAL="$SSL_CERT_DIR"
SSL_KEY_DIR_LOCAL="$SSL_KEY_DIR"
WP_MODE="auto"
WP_MODE_FROM_CLI=false

usage() {
    cat <<'EOF'
smoke.sh - Run syntax checks, unit tests, and read-only edge/dns checks.
Example: smoke.sh syn unit

Commands:
  syn   Run bash -n on scripts
  unit  Run unit tests (test_common, test_cli, test_cf, test_mcp)
  edge  Run edge checks (HTTP/DNS) for selected domains
  dns   Run Cloudflare settings/DNS checks for selected domains
  origin  Run Apache/vhost/cert checks for selected domains
  wp   Run WordPress checks for selected domains
  mysql  Run WordPress DB checks for selected domains
  all  Run all commands (syn, unit, edge, dns, origin, wp, mysql)

Options:
  --domain NAME  Domain to test (repeatable; positional also accepted)
  --domains-file PATH [DOMAINS_FILE] (default: ./domains.csv)  Domain metadata source
  --state STATE  Filter domains by status_cf when using domains.csv (none, redirect, https, worker, ignore)
  --site-type TYPE  Filter domains by site_type when using domains.csv
  --include-ignore  Include status_cf=ignore or status_cf=worker domains when using domains.csv
  --api  Enable Cloudflare API checks for edge (requires zone_id)
  --auth-file PATH [CF_AUTH_FILE]  Auth file to use for API calls
$(cli_usage_wp_root)
$(cli_usage_apache_dir)
$(cli_usage_ssl_dir)
  --multisite  Force multisite mode for WordPress checks
  --singlesite  Force single-site mode for WordPress checks
  --autosite (default)  Auto-detect WordPress mode
  --help  Show this help

Notes:
  - If explicit domains are provided, status and site_type filters are not applied.
  - When no commands are supplied, all commands are executed in the order shown above.
  - Edge checks are always read-only; DNS checks use the Cloudflare API for settings.
  - Origin/WP/MySQL checks are read-only and depend on WP-CLI and local filesystem access.
EOF
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                api) USE_API=true ;;
                include-ignore) INCLUDE_IGNORE=true ;;
                domains-file=*) DOMAINS_FILE="${OPTARG#*=}" ;;
                domains-file)
                    [ -n "${!OPTIND-}" ] || err "--domains-file requires a path"
                    DOMAINS_FILE="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
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
                    WP_MODE="single"
                    WP_MODE_FROM_CLI=true
                    ;;
                autosite)
                    WP_MODE="auto"
                    WP_MODE_FROM_CLI=true
                    ;;
                *)
                    if cli_domain_opt "${OPTARG}" DOMAINS "${!OPTIND-}"; then
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
        syn|unit|edge|dns|origin|wp|mysql)
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

declare -A DOMAIN_STATUS=()
declare -A DOMAIN_SITE_TYPE=()
declare -A DOMAIN_AUTH_FILE=()
declare -A DOMAIN_ZONE_ID=()
declare -A DOMAIN_WP_ROOT=()
DOMAIN_ORDER=()

load_domain_meta() {
    [ -f "$DOMAINS_FILE" ] || return 0
    local rows
    if command -v python3 >/dev/null 2>&1; then
        rows=$(python3 - "$DOMAINS_FILE" <<'PY'
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
        if domain:
            print(f"{domain}\t{status}\t{site_type}\t{auth_file}\t{zone_id}\t{wp_root}")
PY
)
    else
        warn "python3 not available; reading $DOMAINS_FILE with awk"
        rows=$(awk -F, 'NR==1{for(i=1;i<=NF;i++){if($i=="domain")d=i;if($i=="status_cf")s=i;if($i=="site_type")t=i;if($i=="auth_file")a=i;if($i=="zone_id")z=i;if($i=="wp_root")w=i}next} {if($d!="") print $d "\t" $s "\t" $t "\t" $a "\t" $z "\t" $w}' "$DOMAINS_FILE")
    fi
    local domain status site_type auth_file zone_id wp_root key
    while IFS=$'\t' read -r domain status site_type auth_file zone_id wp_root; do
        [ -n "$domain" ] || continue
        key=$(normalize_domain "$domain")
        DOMAIN_ORDER+=("$key")
        DOMAIN_STATUS["$key"]="$status"
        DOMAIN_SITE_TYPE["$key"]="$site_type"
        DOMAIN_AUTH_FILE["$key"]="$auth_file"
        DOMAIN_ZONE_ID["$key"]="$zone_id"
        DOMAIN_WP_ROOT["$key"]="$wp_root"
    done <<<"$rows"
}

load_domain_meta

select_domains() {
    local selected=()
    if [ ${#DOMAINS[@]} -gt 0 ]; then
        selected=("${DOMAINS[@]}")
    else
        local state_filter site_filter
        state_filter=$(tolower "$STATE_FILTER")
        site_filter=$(tolower "$SITE_TYPE_FILTER")
        local domain status site_type
        for domain in "${DOMAIN_ORDER[@]}"; do
            status=$(tolower "${DOMAIN_STATUS[$domain]-}")
            site_type=$(tolower "${DOMAIN_SITE_TYPE[$domain]-}")
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
            selected+=("$domain")
        done
    fi
    if [ ${#selected[@]} -eq 0 ]; then
        err "No domains selected"
    fi
    echo "${selected[@]}"
}

run_syn() {
    local ok=true
    local file
    for file in "$SCRIPTS_DIR"/*.sh; do
        if ! bash -n "$file"; then
            fail "Syntax check failed: $file"
            ok=false
        fi
    done
    [ "$ok" = true ] || return 1
}

run_unit() {
    "$SCRIPTS_DIR/test_common.sh"
    "$SCRIPTS_DIR/test_cli.sh"
    "$SCRIPTS_DIR/test_cf.sh"
    "$SCRIPTS_DIR/test_mcp.sh"
}

run_edge() {
    local domains
    read -r -a domains <<<"$(select_domains)"
    local domain key auth_file zone_id
    for domain in "${domains[@]}"; do
        key=$(normalize_domain "$domain")
        auth_file="${AUTH_FILE_OVERRIDE:-${DOMAIN_AUTH_FILE[$key]-}}"
        zone_id="${DOMAIN_ZONE_ID[$key]-}"
        if [ "$USE_API" = true ] && [ -n "$zone_id" ]; then
            if [ -n "$auth_file" ]; then
                CF_ZONE_ID="$zone_id" "$SCRIPTS_DIR/check-edge.sh" --api --auth-file "$auth_file" "$domain" || true
            else
                warn "Missing auth_file for $domain; running edge checks without --api"
                "$SCRIPTS_DIR/check-edge.sh" "$domain" || true
            fi
        else
            "$SCRIPTS_DIR/check-edge.sh" "$domain" || true
        fi
    done
}

run_dns() {
    local domains
    read -r -a domains <<<"$(select_domains)"
    local domain key auth_file zone_id
    for domain in "${domains[@]}"; do
        key=$(normalize_domain "$domain")
        auth_file="${AUTH_FILE_OVERRIDE:-${DOMAIN_AUTH_FILE[$key]-}}"
        zone_id="${DOMAIN_ZONE_ID[$key]-}"
        if [ -z "$zone_id" ]; then
            warn "Missing zone_id for $domain; skipping"
            continue
        fi
        if [ -n "$auth_file" ]; then
            "$SCRIPTS_DIR/check-cf.sh" --auth-file "$auth_file" --zone-id "$zone_id" "$domain" || true
        else
            warn "Missing auth_file for $domain; skipping"
        fi
    done
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
    if [ "${site_type}" = "standalone" ]; then
        warn "Standalone domain $domain missing wp_root; pass --wp-root to run checks"
        return 1
    fi
    echo "$WORDPRESS_ROOT_LOCAL"
    return 0
}

wp_mode_flag_for() {
    local site_type="$1"
    if [ "$WP_MODE_FROM_CLI" = true ]; then
        case "$WP_MODE" in
            multisite) echo "--multisite" ;;
            single) echo "--singlesite" ;;
            auto) echo "--autosite" ;;
        esac
        return 0
    fi
    case "$site_type" in
        multisite) echo "--multisite" ;;
        standalone) echo "--singlesite" ;;
        *) echo "--autosite" ;;
    esac
}

run_origin() {
    local domains
    read -r -a domains <<<"$(select_domains)"
    local domain key site_type root
    for domain in "${domains[@]}"; do
        key=$(normalize_domain "$domain")
        site_type=$(tolower "${DOMAIN_SITE_TYPE[$key]-}")
        if ! root=$(resolve_wp_root "$domain" "$site_type"); then
            continue
        fi
        "$SCRIPTS_DIR/check-origin.sh" --wp-root "$root" --apache-dir "$APACHE_DIR_LOCAL" --ssl-dir "$SSL_DIR_LOCAL" "$domain" || true
    done
}

run_wp() {
    local domains
    read -r -a domains <<<"$(select_domains)"
    local domain key site_type root mode_flag
    for domain in "${domains[@]}"; do
        key=$(normalize_domain "$domain")
        site_type=$(tolower "${DOMAIN_SITE_TYPE[$key]-}")
        if ! root=$(resolve_wp_root "$domain" "$site_type"); then
            continue
        fi
        mode_flag=$(wp_mode_flag_for "$site_type")
        "$SCRIPTS_DIR/check-wp.sh" "$mode_flag" --wp-root "$root" "$domain" || true
    done
}

run_mysql() {
    require_cmds wp
    local domains
    read -r -a domains <<<"$(select_domains)"
    local roots=()
    local domain key site_type root
    local -A seen
    for domain in "${domains[@]}"; do
        key=$(normalize_domain "$domain")
        site_type=$(tolower "${DOMAIN_SITE_TYPE[$key]-}")
        if ! root=$(resolve_wp_root "$domain" "$site_type"); then
            continue
        fi
        if [ -z "${seen[$root]-}" ]; then
            roots+=("$root")
            seen["$root"]=1
        fi
    done
    local root_path
    for root_path in "${roots[@]}"; do
        log "MySQL check via WP-CLI at $root_path"
        if ! priv -u www-data wp --path="$root_path" db check >/dev/null 2>&1; then
            fail "MySQL check failed for $root_path"
        else
            echo "MySQL check passed: $root_path"
        fi
    done
}

overall_ok=true
for cmd in "${COMMANDS[@]}"; do
    case "$cmd" in
        syn) run_syn || overall_ok=false ;;
        unit) run_unit || overall_ok=false ;;
        edge) run_edge ;;
        dns) run_dns ;;
        origin) run_origin ;;
        wp) run_wp ;;
        mysql) run_mysql ;;
        *) err "Unknown command: $cmd" ;;
    esac
done

if [ "$overall_ok" != true ]; then
    exit 1
fi
