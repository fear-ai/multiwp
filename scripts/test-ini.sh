#!/bin/bash
# test-ini.sh - Run initial low-load checks for performance testing.
# For options, environment variables, defaults see usage().
#
# Example: test-ini.sh --domain zero.directory --duration 10s --threads 2 --connections 16

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/cli.sh"

DOMAINS=()
RUN_ID=""
OUT_DIR=""
DURATION="10s"
THREADS=2
CONNECTIONS=16
CACHE_BUST_PARAM="cache_bust"
ALLOW_ROOT=false

usage() {
    cat <<'EOF'
test-ini.sh - Run initial low-load checks for performance testing.
Example: test-ini.sh --domain zero.directory --duration 10s --threads 2 --connections 16

Options:
  --domain NAME  Domain to test (repeatable; positional also accepted)
  --duration DURATION  wrk duration (default: 10s)
  --threads N  wrk threads (default: 2)
  --connections N  wrk connections (default: 16)
  --run-id ID  Override the run identifier used in filenames
  --out-dir DIR  Output directory (default: /var/tmp/perf-<run-id>-init)
  --cache-bust PARAM  Cache-bust query parameter name (default: cache_bust)
  --help  Show this help

Notes:
  - Writes headers and wrk output into the output directory.
  - Uses both cached and cache-busted URLs per domain.
EOF
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                duration=*) DURATION="${OPTARG#*=}" ;;
                duration)
                    [ -n "${!OPTIND-}" ] || err "--duration requires a value"
                    DURATION="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                threads=*) THREADS="${OPTARG#*=}" ;;
                threads)
                    [ -n "${!OPTIND-}" ] || err "--threads requires a value"
                    THREADS="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                connections=*) CONNECTIONS="${OPTARG#*=}" ;;
                connections)
                    [ -n "${!OPTIND-}" ] || err "--connections requires a value"
                    CONNECTIONS="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                run-id=*) RUN_ID="${OPTARG#*=}" ;;
                run-id)
                    [ -n "${!OPTIND-}" ] || err "--run-id requires a value"
                    RUN_ID="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                out-dir=*) OUT_DIR="${OPTARG#*=}" ;;
                out-dir)
                    [ -n "${!OPTIND-}" ] || err "--out-dir requires a path"
                    OUT_DIR="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                cache-bust=*) CACHE_BUST_PARAM="${OPTARG#*=}" ;;
                cache-bust)
                    [ -n "${!OPTIND-}" ] || err "--cache-bust requires a value"
                    CACHE_BUST_PARAM="${!OPTIND}"
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

cli_require_non_root
require_cmds curl wrk

RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
OUT_DIR="${OUT_DIR:-/var/tmp/perf-${RUN_ID}-init}"
mkdir -p "$OUT_DIR"

section "INIT" "Run"
kv "RUN_ID" "$RUN_ID"
kv "OUT_DIR" "$OUT_DIR"
kv "DURATION" "$DURATION"
kv "THREADS" "$THREADS"
kv "CONNECTIONS" "$CONNECTIONS"

for domain in "${DOMAINS[@]}"; do
    section "INIT" "Domain"
    kv "DOMAIN" "$domain"

    local_base="https://${domain}/"
    local_bust="https://${domain}/?${CACHE_BUST_PARAM}=${RUN_ID}"

    curl -I "$local_base" > "$OUT_DIR/init_headers_${domain}.txt"
    curl -I "$local_bust" > "$OUT_DIR/init_headers_${domain}_bust.txt"

    wrk -t"$THREADS" -c"$CONNECTIONS" -d"$DURATION" "$local_base" > "$OUT_DIR/init_wrk_${domain}_cached.txt"
    wrk -t"$THREADS" -c"$CONNECTIONS" -d"$DURATION" "$local_bust" > "$OUT_DIR/init_wrk_${domain}_bust.txt"
done

status_pass "run=ok"
