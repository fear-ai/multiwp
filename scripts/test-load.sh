#!/bin/bash
# test-load.sh - Run sustained load tests with telemetry collection.
# For options, environment variables, defaults see usage().
#
# Example: test-load.sh --domain zero.directory --duration 30s --threads 4 --connections 64

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/cli.sh"

DOMAINS=()
RUN_ID=""
OUT_DIR=""
DURATION="30s"
THREADS=4
CONNECTIONS=64
CACHE_BUST_PARAM="cache_bust"
INTERVAL=1
ALLOW_ROOT=false

usage() {
    cat <<'EOF'
test-load.sh - Run sustained load tests with telemetry collection.
Example: test-load.sh --domain zero.directory --duration 30s --threads 4 --connections 64

Options:
  --domain NAME  Domain to test (repeatable; positional also accepted)
  --duration DURATION  wrk duration per run (default: 30s)
  --threads N  wrk threads (default: 4)
  --connections N  wrk connections (default: 64)
  --run-id ID  Override the run identifier used in filenames
  --out-dir DIR  Output directory (default: /var/tmp/perf-<run-id>-load)
  --cache-bust PARAM  Cache-bust query parameter name (default: cache_bust)
  --interval N  Telemetry interval in seconds (default: 1)
  --help  Show this help

Notes:
  - For each domain, telemetry is collected while cached and cache-busted wrk runs execute.
  - Output files include the domain and run ID for easy correlation.
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
                interval=*) INTERVAL="${OPTARG#*=}" ;;
                interval)
                    [ -n "${!OPTIND-}" ] || err "--interval requires a value"
                    INTERVAL="${!OPTIND}"
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
require_cmds wrk vmstat pidstat iostat sar pgrep

RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
OUT_DIR="${OUT_DIR:-/var/tmp/perf-${RUN_ID}-load}"
mkdir -p "$OUT_DIR"

section "LOAD" "Run"
kv "RUN_ID" "$RUN_ID"
kv "OUT_DIR" "$OUT_DIR"
kv "DURATION" "$DURATION"
kv "THREADS" "$THREADS"
kv "CONNECTIONS" "$CONNECTIONS"
kv "INTERVAL" "$INTERVAL"

start_telemetry() {
    local prefix="$1"
    local apache_pids
    apache_pids=$(pgrep -d, -x apache2 || true)

    vmstat "$INTERVAL" > "$OUT_DIR/${prefix}_vmstat.log" &
    VMSTAT_PID=$!
    if [ -n "$apache_pids" ]; then
        pidstat -ru -p "$apache_pids" "$INTERVAL" > "$OUT_DIR/${prefix}_pidstat.log" &
        PIDSTAT_PID=$!
    else
        PIDSTAT_PID=""
        warn "No apache2 PIDs found; skipping pidstat for $prefix"
    fi
    iostat -xz "$INTERVAL" > "$OUT_DIR/${prefix}_iostat.log" &
    IOSTAT_PID=$!
    sar -u -r -n DEV "$INTERVAL" > "$OUT_DIR/${prefix}_sar.log" &
    SAR_PID=$!
}

stop_telemetry() {
    local pid
    for pid in "${VMSTAT_PID-}" "${PIDSTAT_PID-}" "${IOSTAT_PID-}" "${SAR_PID-}"; do
        if [ -n "${pid-}" ]; then
            kill "$pid" >/dev/null 2>&1 || true
        fi
    done
}

for domain in "${DOMAINS[@]}"; do
    section "LOAD" "Domain"
    kv "DOMAIN" "$domain"

    prefix="load_${domain}_${RUN_ID}"
    start_telemetry "$prefix"

    base_url="https://${domain}/"
    bust_url="https://${domain}/?${CACHE_BUST_PARAM}=${RUN_ID}"

    wrk -t"$THREADS" -c"$CONNECTIONS" -d"$DURATION" "$base_url" > "$OUT_DIR/${prefix}_wrk_cached.txt"
    wrk -t"$THREADS" -c"$CONNECTIONS" -d"$DURATION" "$bust_url" > "$OUT_DIR/${prefix}_wrk_bust.txt"

    stop_telemetry
done

status_pass "run=ok"
