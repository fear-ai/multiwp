#!/bin/bash
# test-load.sh - Run init or load tests with optional telemetry collection.
# For options, environment variables, defaults see usage().
#
# Example: test-load.sh --load --domain zero.directory --duration 30s --threads 4 --connections 64

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/cli.sh"

DOMAINS=()
RUN_ID=""
OUT_DIR=""
DURATION=""
THREADS=""
CONNECTIONS=""
CACHE_BUST_PARAM="cache_bust"
INTERVAL=1
MODE="init"
TELEMETRY_MODE="true"
MODE_SET=false
SET_DURATION=false
SET_THREADS=false
SET_CONNECTIONS=false
HEAD_MODE="false"
ALLOW_ROOT=false

usage() {
    cat <<'EOF'
test-load.sh - Run init or load tests with optional telemetry collection.
Example: test-load.sh --load --domain zero.directory --duration 30s --threads 4 --connections 64

Options:
  --domain NAME  Domain to test (repeatable; positional also accepted)
  --init  Run init-mode tests (default)
  --load  Run load-mode tests
  --duration DURATION  wrk duration per run (default: 10s init, 30s load)
  --threads N  wrk threads (default: 2 init, 4 load)
  --connections N  wrk connections (default: 16 init, 64 load)
  --run-id ID  Override the run identifier used in filenames (default: YYYYmmdd_HHMMSS)
  --out-dir DIR  Output directory (default: /var/tmp/multiwp/perf_<run-id>)
  --cache-bust PARAM  Cache-bust query parameter name (default: cache_bust)
  --interval N  Telemetry interval in seconds (default: 1)
  --no-telemetry  Disable system telemetry for this run
  --head  Write response headers for cached and cache-busted requests
  --help  Show this help

Notes:
  - Telemetry is enabled by default; disable it with --no-telemetry.
  - Output files include the domain and run ID for easy correlation.
EOF
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                init)
                    if $MODE_SET && [ "$MODE" != "init" ]; then
                        err "--init and --load are mutually exclusive"
                    fi
                    MODE="init"
                    MODE_SET=true
                    ;;
                load)
                    if $MODE_SET && [ "$MODE" != "load" ]; then
                        err "--init and --load are mutually exclusive"
                    fi
                    MODE="load"
                    MODE_SET=true
                    ;;
                duration=*)
                    DURATION="${OPTARG#*=}"
                    SET_DURATION=true
                    ;;
                duration)
                    [ -n "${!OPTIND-}" ] || err "--duration requires a value"
                    DURATION="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    SET_DURATION=true
                    ;;
                threads=*)
                    THREADS="${OPTARG#*=}"
                    SET_THREADS=true
                    ;;
                threads)
                    [ -n "${!OPTIND-}" ] || err "--threads requires a value"
                    THREADS="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    SET_THREADS=true
                    ;;
                connections=*)
                    CONNECTIONS="${OPTARG#*=}"
                    SET_CONNECTIONS=true
                    ;;
                connections)
                    [ -n "${!OPTIND-}" ] || err "--connections requires a value"
                    CONNECTIONS="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    SET_CONNECTIONS=true
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
                no-telemetry) TELEMETRY_MODE="false" ;;
                head) HEAD_MODE="true" ;;
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

if [ "$MODE" = "init" ]; then
    $SET_DURATION || DURATION="10s"
    $SET_THREADS || THREADS=2
    $SET_CONNECTIONS || CONNECTIONS=16
else
    $SET_DURATION || DURATION="30s"
    $SET_THREADS || THREADS=4
    $SET_CONNECTIONS || CONNECTIONS=64
fi

if [ "$TELEMETRY_MODE" = "true" ]; then
    require_cmds wrk vmstat pidstat iostat sar pgrep
else
    require_cmds wrk
fi

if [ "$HEAD_MODE" = "true" ]; then
    require_cmds curl
fi

RUN_ID="${RUN_ID:-$(date +%Y%m%d_%H%M%S)}"
OUT_DIR="${OUT_DIR:-/var/tmp/multiwp/perf_${RUN_ID}}"
mkdir -p "$OUT_DIR"

MODE_UPPER=$(echo "$MODE" | tr '[:lower:]' '[:upper:]')
section "$MODE_UPPER" "Run"
kv "RUN_ID" "$RUN_ID"
kv "OUT_DIR" "$OUT_DIR"
kv "MODE" "$MODE"
kv "DURATION" "$DURATION"
kv "THREADS" "$THREADS"
kv "CONNECTIONS" "$CONNECTIONS"
kv "INTERVAL" "$INTERVAL"
kv "TELEMETRY" "$TELEMETRY_MODE"
kv "HEAD" "$HEAD_MODE"

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
    section "$MODE_UPPER" "Domain"
    kv "DOMAIN" "$domain"

    label=$(echo "$domain" | tr '.-' '__')
    prefix="${label}_${RUN_ID}"
    if [ "$TELEMETRY_MODE" = "true" ]; then
        start_telemetry "$prefix"
    fi

    base_url="https://${domain}/"
    bust_url="https://${domain}/?${CACHE_BUST_PARAM}=${RUN_ID}"

    if [ "$HEAD_MODE" = "true" ]; then
        curl -I "$base_url" > "$OUT_DIR/${prefix}_head.txt"
        curl -I "$bust_url" > "$OUT_DIR/${prefix}_head_bust.txt"
    fi

    wrk -t"$THREADS" -c"$CONNECTIONS" -d"$DURATION" "$base_url" > "$OUT_DIR/${prefix}_wrk.txt"
    wrk -t"$THREADS" -c"$CONNECTIONS" -d"$DURATION" "$bust_url" > "$OUT_DIR/${prefix}_wrk_bust.txt"

    if [ "$TELEMETRY_MODE" = "true" ]; then
        stop_telemetry
    fi
done

status_pass "run=ok"
