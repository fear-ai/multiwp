#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"

EDGE_ARGS=()
ORIGIN_ARGS=()
WP_ARGS=()

usage() {
    cat <<'USAGE'
Usage: verify-domain.sh [OPTIONS] domain1 [domain2...]
Runs edge, origin, and WordPress validation for each domain.
Options:
  --help                Show this help
  --api                 Enable Cloudflare API checks in check-edge.sh
  --ssl-dir DIR         Base SSL dir (default: /etc/ssl/cloudflare-origin)
  --apache-dir DIR      Apache sites-available dir (default: /etc/apache2/sites-available)
  --root PATH           WordPress root (default: /var/www/html/wordpress)
  --timeout SECONDS     HTTP timeout for edge checks
USAGE
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                api) EDGE_ARGS+=("--api") ;;
                ssl-dir=*) ORIGIN_ARGS+=("--ssl-dir=${OPTARG#*=}") ;;
                apache-dir=*) ORIGIN_ARGS+=("--apache-dir=${OPTARG#*=}") ;;
                root=*) WP_ARGS+=("--root=${OPTARG#*=}") ORIGIN_ARGS+=("--root=${OPTARG#*=}") ;;
                timeout=*) EDGE_ARGS+=("--timeout=${OPTARG#*=}") ;;
                *) usage; exit 1 ;;
            esac
            ;;
        \?) usage; exit 1 ;;
    esac
done
shift $((OPTIND-1))

[ $# -ge 1 ] || { usage; exit 1; }

if [ "${USER:-}" = "root" ]; then
    err "Do not run as root. Run as an Ubuntu user with sudo privileges."
fi

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
