#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"
. "$SCRIPT_DIR/cli.sh"

EDGE_ARGS=()
ORIGIN_ARGS=()
WP_ARGS=()
ALLOW_ROOT=false

usage() {
    cat <<'USAGE'
Usage: verify-domain.sh [OPTIONS] domain1 [domain2...]
Runs edge, origin, and WordPress validation for each domain.
Options:
  --help                Show this help
  --api                 Enable Cloudflare API checks in check-edge.sh
  --apache-dir DIR      Apache sites-available dir (default: /etc/apache2/sites-available)
  --timeout SECONDS     HTTP timeout for edge checks
USAGE
    cli_usage_common_priv
    cli_usage_ssl_dir
    cli_usage_root
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                api) EDGE_ARGS+=("--api") ;;
                ssl-dir|ssl-dir=*)
                    if cli_handle_ssl_dir_opt "${OPTARG}" SSL_DIR_OVERRIDE "" "" "${!OPTIND-}"; then
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
                root|root=*)
                    if cli_handle_root_opt "${OPTARG}" ROOT_OVERRIDE "${!OPTIND-}"; then
                        WP_ARGS+=("--root=${ROOT_OVERRIDE}")
                        ORIGIN_ARGS+=("--root=${ROOT_OVERRIDE}")
                    else
                        usage; exit 1
                    fi
                    ;;
                timeout=*) EDGE_ARGS+=("--timeout=${OPTARG#*=}") ;;
                *)
                    if cli_handle_common_opt "${OPTARG}"; then
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

[ $# -ge 1 ] || { usage; exit 1; }

if [ "$ALLOW_ROOT" = true ]; then
    ORIGIN_ARGS+=("--allow-root")
    WP_ARGS+=("--allow-root")
fi

cli_require_non_root

EDGE_SCRIPT="$SCRIPT_DIR/check-edge.sh"
ORIGIN_SCRIPT="$SCRIPT_DIR/check-origin.sh"
WP_SCRIPT="$SCRIPT_DIR/check-wp.sh"

if [ ! -x "$EDGE_SCRIPT" ] || [ ! -x "$ORIGIN_SCRIPT" ] || [ ! -x "$WP_SCRIPT" ]; then
    err "Missing validation scripts in $SCRIPT_DIR"
fi

overall_ok=true
for domain in "$@"; do
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
