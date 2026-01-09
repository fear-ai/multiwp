#!/bin/bash
# verify-domain.sh - Run edge, origin, and WordPress checks for domains.
# For options, environment variables, defaults see usage().
#
# Example: verify-domain.sh [OPTIONS] domain1 [domain2...]

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/cli.sh"

EDGE_ARGS=()
ORIGIN_ARGS=()
WP_ARGS=()
ALLOW_ROOT=false
DOMAINS=()

usage() {
    cat <<EOF
verify-domain.sh - Run edge, origin, and WordPress checks for domains.
Example: verify-domain.sh [OPTIONS] domain1 [domain2...]

Options:
  --api  Enable Cloudflare API checks in check-edge.sh
  --hsts  Require Strict-Transport-Security header in check-edge.sh
$(cli_usage_domain)
  --apache-dir DIR [APACHE_DIR] (default: /etc/apache2/sites-available)  Apache sites-available dir
  --http-timeout SECONDS [HTTP_TIMEOUT] (default: 10)  HTTP timeout for edge checks
$(cli_usage_wp_root)
$(cli_usage_ssl_dir)
$(cli_usage_common_priv)
  --help  Show this help
EOF
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                api) EDGE_ARGS+=("--api") ;;
                hsts) EDGE_ARGS+=("--hsts") ;;
                ssl-dir|ssl-dir=*)
                    if cli_ssl_dir_opt "${OPTARG}" SSL_DIR_OVERRIDE "" "" "${!OPTIND-}"; then
                        ORIGIN_ARGS+=("--ssl-dir=${SSL_DIR_OVERRIDE}")
                    else
                        usage; exit 1
                    fi
                    ;;
                apache-dir|apache-dir=*)
                    if [ "${OPTARG}" = "apache-dir" ]; then
                        [ -n "${!OPTIND-}" ] || err "--apache-dir requires a value"
                        APACHE_DIR_OVERRIDE="${!OPTIND}"
                        OPTIND=$((OPTIND+1))
                    else
                        APACHE_DIR_OVERRIDE="${OPTARG#*=}"
                    fi
                    ORIGIN_ARGS+=("--apache-dir=${APACHE_DIR_OVERRIDE}")
                    ;;
                wp-root|wp-root=*)
                    if cli_wp_root_opt "${OPTARG}" WORDPRESS_ROOT_OVERRIDE "${!OPTIND-}"; then
                        WP_ARGS+=("--wp-root=${WORDPRESS_ROOT_OVERRIDE}")
                        ORIGIN_ARGS+=("--wp-root=${WORDPRESS_ROOT_OVERRIDE}")
                    else
                        usage; exit 1
                    fi
                    ;;
                http-timeout=*) EDGE_ARGS+=("--http-timeout=${OPTARG#*=}") ;;
                http-timeout)
                    [ -n "${!OPTIND-}" ] || err "--http-timeout requires a value"
                    EDGE_ARGS+=("--http-timeout=${!OPTIND}")
                    OPTIND=$((OPTIND+1))
                    ;;
                *)
                    if cli_domain_opt "${OPTARG}" DOMAINS "${!OPTIND-}"; then
                        :
                    elif cli_common_opt "${OPTARG}"; then
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

if [ "$ALLOW_ROOT" = true ]; then
    ORIGIN_ARGS+=("--allow-root")
    WP_ARGS+=("--allow-root")
fi

cli_require_non_root

EDGE_SCRIPT="$SCRIPTS_DIR/check-edge.sh"
ORIGIN_SCRIPT="$SCRIPTS_DIR/check-origin.sh"
WP_SCRIPT="$SCRIPTS_DIR/check-wp.sh"

if [ ! -x "$EDGE_SCRIPT" ] || [ ! -x "$ORIGIN_SCRIPT" ] || [ ! -x "$WP_SCRIPT" ]; then
    err "Missing validation scripts in $SCRIPTS_DIR"
fi

overall_ok=true
for domain in "${DOMAINS[@]}"; do
    echo ""
    log "=============================="
    log "Verifying domain: $domain"
    log "=============================="

    if ! "$ORIGIN_SCRIPT" "${ORIGIN_ARGS[@]}" "$domain"; then
        overall_ok=false
    fi

    if ! "$WP_SCRIPT" "${WP_ARGS[@]}" "$domain"; then
        overall_ok=false
    fi

    if ! "$EDGE_SCRIPT" "${EDGE_ARGS[@]}" "$domain"; then
        overall_ok=false
    fi

done

if [ "$overall_ok" = true ]; then
    log "All domain checks completed successfully"
    exit 0
fi

err "One or more domains failed verification"
