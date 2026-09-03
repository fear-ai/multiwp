#!/bin/bash
# perf-load.sh - Run init or load tests with optional telemetry collection.
# For options, environment variables, defaults see usage().
#
# Example: perf-load.sh --load --domain zero.directory

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/cli.sh"
. "$SCRIPTS_DIR/cmd.sh"

DOMAINS=()
RUN_ID=""
OUT_DIR=""
DURATION=""
THREADS=""
CONNECTIONS=""
RATE=""
CACHE_BUST_PARAM="cache_bust"
CACHE_MODE="both"
INTERVAL=5
MYSQL_INTERVAL="${MYSQL_INTERVAL:-5}"
LOG_PAD_SEC="${LOG_PAD_SEC:-5}"
MODE="init"
TELEMETRY_DEFAULT="sar"
TELEMETRY_LIST="$TELEMETRY_DEFAULT"
TELEMETRY_SELECTED=()
TELEMETRY_ORDER=(sar pidstat vmstat cgtop mysql)
declare -A TELEMETRY_KIND=(
    [sar]=cmd
    [pidstat]=cmd
    [vmstat]=cmd
    [iostat]=cmd
    [cgtop]=cmd
    [mysql]=mysql
)
declare -A TELEMETRY_CMD_MAP=(
    [sar]=TELEMETRY_CMD_SAR
    [pidstat]=TELEMETRY_CMD_PIDSTAT
    [vmstat]=TELEMETRY_CMD_VMSTAT
    [iostat]=TELEMETRY_CMD_IOSTAT
    [cgtop]=TELEMETRY_CMD_CGTOP
)
declare -A TELEMETRY_REQ=(
    [sar]=sar
    [pidstat]=pidstat
    [vmstat]=vmstat
    [iostat]=iostat
    [cgtop]=/usr/bin/systemd-cgtop
    [mysql]=mysql
)
declare -A TELEMETRY_SUFFIX=(
    [sar]=sar
    [pidstat]=pidstat
    [vmstat]=vmstat
    [iostat]=iostat
    [cgtop]=cgtop
)
TELEMETRY_CMD_SAR=(sar -u -r)
TELEMETRY_CMD_PIDSTAT=(pidstat -ru -C 'apache2|mysqld|wrk')
TELEMETRY_CMD_VMSTAT=(vmstat -n)
TELEMETRY_CMD_IOSTAT=(iostat -xz)
TELEMETRY_CMD_CGTOP=(/usr/bin/systemd-cgtop -b -n 0 -d)
USE_SAR=false
USE_PIDSTAT=false
USE_VMSTAT=false
USE_IOSTAT=false
USE_CGTOP=false
USE_MYSQL_PERF=false
MODE_SET=false
SET_DURATION=false
SET_THREADS=false
SET_CONNECTIONS=false
SET_RATE=false
SET_MYSQL_INTERVAL=false
HEAD_MODE="false"
REPORT_MODE="true"
ERR_MODE="false"
SLICE_MODE="false"
ALLOW_ROOT=false

usage() {
    cat <<'EOF'
perf-load.sh - Run init, load, or telemetry-only checks with optional telemetry collection.
Example: perf-load.sh --load --domain zero.directory

Options:
  --domain NAME  Domain to test (repeatable; positional also accepted)
  --init  Run init-mode tests (default)
  --load  Run load-mode tests
  --none  Run telemetry and optional HEAD requests only (no wrk2)
  --duration DURATION  Duration per run (wrk duration for init/load; telemetry window for --none)
  --threads N  wrk threads (default: 1 init, 2 load)
  --connections N  wrk connections (default: 1 init, 4 load)
  --rate N  wrk2 fixed request rate N req/sec (default: 10 init, 20 load)
  --run-id ID  Override the run identifier used in filenames (default: YYYYmmdd_HHMMSS)
  --out-dir DIR  Output directory (default: /var/tmp/multiwp/perf_<run-id>)
  --cache-bust PARAM  Cache-bust query parameter name (default: cache_bust)
  --cache MODE  Run cached, bust, or both (default: both; values: both|cached|bust)
  --interval N  Telemetry interval in seconds (default: 5)
  --mysql-interval N  MySQL perf sampling interval in seconds (default: 5)
  --telemetry LIST  Telemetry tools (default: sar; values: sar,pidstat,vmstat,iostat,cgtop,mysql,all,none)
  --head  Write response headers for cached and cache-busted requests
  --report  Emit summary metrics after each wrk run (default)
  --no-report  Disable summary metrics output
  --err  Write stderr for wrk, curl, and telemetry tools to .err files
  --slice  Run slice-logs.sh after each domain run (writes *_logs.txt and log slices)
  --help  Show this help

Notes:
  - wrk2 is used for init/load modes only; --none skips wrk2 entirely.
  - Telemetry defaults to sar; override with --telemetry=none or a comma list.
  - When running through an external command runner, use a timeout of at least 60 seconds.
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
                        err "--init, --load, and --none are mutually exclusive"
                    fi
                    MODE="init"
                    MODE_SET=true
                    ;;
                load)
                    if $MODE_SET && [ "$MODE" != "load" ]; then
                        err "--init, --load, and --none are mutually exclusive"
                    fi
                    MODE="load"
                    MODE_SET=true
                    ;;
                none)
                    if $MODE_SET && [ "$MODE" != "none" ]; then
                        err "--init, --load, and --none are mutually exclusive"
                    fi
                    MODE="none"
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
                rate=*)
                    RATE="${OPTARG#*=}"
                    SET_RATE=true
                    ;;
                rate)
                    [ -n "${!OPTIND-}" ] || err "--rate requires a value"
                    RATE="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    SET_RATE=true
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
                cache=*) CACHE_MODE="${OPTARG#*=}" ;;
                cache)
                    [ -n "${!OPTIND-}" ] || err "--cache requires a value"
                    CACHE_MODE="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                interval=*) INTERVAL="${OPTARG#*=}" ;;
                interval)
                    [ -n "${!OPTIND-}" ] || err "--interval requires a value"
                    INTERVAL="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                mysql-interval=*)
                    MYSQL_INTERVAL="${OPTARG#*=}"
                    SET_MYSQL_INTERVAL=true
                    ;;
                mysql-interval)
                    [ -n "${!OPTIND-}" ] || err "--mysql-interval requires a value"
                    MYSQL_INTERVAL="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    SET_MYSQL_INTERVAL=true
                    ;;
                telemetry=*) TELEMETRY_LIST="${OPTARG#*=}" ;;
                telemetry)
                    [ -n "${!OPTIND-}" ] || err "--telemetry requires a value"
                    TELEMETRY_LIST="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                head) HEAD_MODE="true" ;;
                report) REPORT_MODE="true" ;;
                no-report) REPORT_MODE="false" ;;
                err) ERR_MODE="true" ;;
                slice) SLICE_MODE="true" ;;
                no-telemetry|telemetry-full|pidstat)
                    err "--${OPTARG} removed; use --telemetry=none or --telemetry=all"
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

CPU_CORES=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)

if [ "$MODE" = "init" ]; then
    $SET_DURATION || DURATION="20s"
    $SET_THREADS || THREADS=1
    $SET_CONNECTIONS || CONNECTIONS=1
    $SET_RATE || RATE=10
elif [ "$MODE" = "load" ]; then
    $SET_DURATION || DURATION="20s"
    $SET_THREADS || THREADS=2
    $SET_CONNECTIONS || CONNECTIONS=4
    $SET_RATE || RATE=20
else
    $SET_DURATION || DURATION="20s"
    $SET_THREADS || THREADS="na"
    $SET_CONNECTIONS || CONNECTIONS="na"
    $SET_RATE || RATE="na"
fi

WRK_BIN="${WRK_BIN:-}"
if [ -z "$WRK_BIN" ]; then
    if [ -x "/home/ubuntu/WP/wrk2/wrk" ]; then
        WRK_BIN="/home/ubuntu/WP/wrk2/wrk"
    else
        WRK_BIN="wrk2"
    fi
fi
LOAD_TOOL="$WRK_BIN"
if [ "$MODE" = "none" ]; then
    LOAD_TOOL="none"
fi

telemetry_has() {
    local needle="$1"
    local item
    for item in "${TELEMETRY_SELECTED[@]}"; do
        if [ "$item" = "$needle" ]; then
            return 0
        fi
    done
    return 1
}

telemetry_selected_string() {
    local out=""
    local item
    for item in "${TELEMETRY_SELECTED[@]}"; do
        out+="${item},"
    done
    echo "${out%,}"
}

telemetry_cmd_for() {
    local tool="$1"
    local -n out="$2"
    local name="${TELEMETRY_CMD_MAP[$tool]-}"
    [ -n "$name" ] || return 1
    local -n base="$name"
    case "$tool" in
        vmstat)
            out=("vmstat" "-n" "$INTERVAL")
            ;;
        *)
            out=("${base[@]}" "$INTERVAL")
            ;;
    esac
}

telemetry_cmd_string() {
    local tool="$1"
    local -a cmd=()
    telemetry_cmd_for "$tool" cmd || return 1
    cmd_join "${cmd[@]}"
}

parse_telemetry_list() {
    local list="${1-}"
    local items=()
    local use_all=false
    local item
    declare -A seen=()

    TELEMETRY_SELECTED=()

    if [ -z "$list" ]; then
        list="$TELEMETRY_DEFAULT"
    fi

    case "$list" in
        none)
            USE_SAR=false
            USE_PIDSTAT=false
            USE_VMSTAT=false
            USE_IOSTAT=false
            USE_CGTOP=false
            USE_MYSQL_PERF=false
            TELEMETRY_LIST="none"
            return
            ;;
    esac

    parse_comma_list "$list" items "telemetry"

    for item in "${items[@]}"; do
        case "$item" in
            all)
                use_all=true
                ;;
            none)
                err "--telemetry=none cannot be combined with other values"
                ;;
            *)
                if [ -z "${TELEMETRY_KIND[$item]-}" ]; then
                    err "--telemetry invalid value: $item"
                fi
                ;;
        esac
    done

    if $use_all; then
        TELEMETRY_SELECTED=("${TELEMETRY_ORDER[@]}")
    else
        for item in "${items[@]}"; do
            if [ "$item" = "all" ]; then
                continue
            fi
            if [ -z "${seen[$item]-}" ]; then
                TELEMETRY_SELECTED+=("$item")
                seen[$item]=1
            fi
        done
    fi

    USE_SAR=false
    USE_PIDSTAT=false
    USE_VMSTAT=false
    USE_IOSTAT=false
    USE_CGTOP=false
    USE_MYSQL_PERF=false
    for item in "${TELEMETRY_SELECTED[@]}"; do
        case "$item" in
            sar) USE_SAR=true ;;
            pidstat) USE_PIDSTAT=true ;;
            vmstat) USE_VMSTAT=true ;;
            iostat) USE_IOSTAT=true ;;
            cgtop) USE_CGTOP=true ;;
            mysql) USE_MYSQL_PERF=true ;;
        esac
    done

    TELEMETRY_LIST="$(telemetry_selected_string)"
}

parse_telemetry_list "$TELEMETRY_LIST"

if [ "$MODE" != "none" ]; then
    require_cmds "$WRK_BIN"
fi
for item in "${TELEMETRY_SELECTED[@]}"; do
    req="${TELEMETRY_REQ[$item]-}"
    if [ -n "$req" ]; then
        require_cmds "$req"
    fi
done
if $USE_SAR; then
    require_cmds sadf
fi
if [ "$REPORT_MODE" = "true" ] && { $USE_SAR || $USE_PIDSTAT; }; then
    require_cmds python3
fi

if [ "$HEAD_MODE" = "true" ]; then
    require_cmds curl
fi

case "$CACHE_MODE" in
    both|cached|bust) ;;
    *) err "--cache must be one of: both, cached, bust" ;;
esac

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
    kv "RATE" "${RATE:-na}"
    kv "WRK_BIN" "$WRK_BIN"
kv "CACHE" "$CACHE_MODE"
kv "INTERVAL" "$INTERVAL"
kv "MYSQL_INTERVAL" "$MYSQL_INTERVAL"
kv "TELEMETRY" "$TELEMETRY_LIST"
kv "HEAD" "$HEAD_MODE"
kv "REPORT" "$REPORT_MODE"
kv "ERR" "$ERR_MODE"

HOSTNAME_VAL=$(hostname 2>/dev/null || echo "unknown")
ORIGIN_IPV4_VAL=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
START_LOCAL=$(date +%Y-%m-%dT%H:%M:%S)
LOCAL_TZ=$(date +%Z)
LOCAL_OFFSET=$(date +%z)

check_expected_file() {
    local path="$1"
    local label="$2"
    if [ ! -s "$path" ]; then
        warn "Missing or empty ${label}: $path"
    fi
}

mysql_perf_sample() {
    local file="$1"
    local err_file="${2-}"
    local output
    local pool_data
    local pool_total
    local pool_pages_data
    local pool_pages_total
    local page_size
    local buffer_size
    local reads
    local requests
    local questions
    local pool_used_pct="na"
    local hit_rate="na"
    local now

    if [ -n "$err_file" ]; then
        output=$(priv mysql -N -e "SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_bytes_data'; SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_bytes_total'; SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_pages_data'; SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_pages_total'; SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_reads'; SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_read_requests'; SHOW GLOBAL STATUS LIKE 'Questions'; SHOW VARIABLES LIKE 'innodb_buffer_pool_size'; SHOW VARIABLES LIKE 'innodb_page_size';" 2>>"$err_file" || true)
    else
        output=$(priv mysql -N -e "SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_bytes_data'; SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_bytes_total'; SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_pages_data'; SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_pages_total'; SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_reads'; SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_read_requests'; SHOW GLOBAL STATUS LIKE 'Questions'; SHOW VARIABLES LIKE 'innodb_buffer_pool_size'; SHOW VARIABLES LIKE 'innodb_page_size';" 2>/dev/null || true)
    fi
    if [ -z "$output" ]; then
        return 1
    fi

    pool_data=$(awk '$1=="Innodb_buffer_pool_bytes_data" {print $2}' <<<"$output")
    pool_total=$(awk '$1=="Innodb_buffer_pool_bytes_total" {print $2}' <<<"$output")
    pool_pages_data=$(awk '$1=="Innodb_buffer_pool_pages_data" {print $2}' <<<"$output")
    pool_pages_total=$(awk '$1=="Innodb_buffer_pool_pages_total" {print $2}' <<<"$output")
    reads=$(awk '$1=="Innodb_buffer_pool_reads" {print $2}' <<<"$output")
    requests=$(awk '$1=="Innodb_buffer_pool_read_requests" {print $2}' <<<"$output")
    questions=$(awk '$1=="Questions" {print $2}' <<<"$output")
    buffer_size=$(awk '$1=="innodb_buffer_pool_size" {print $2}' <<<"$output")
    page_size=$(awk '$1=="innodb_page_size" {print $2}' <<<"$output")

    if [ -z "$pool_data" ] && [ -n "$pool_pages_data" ] && [ -n "$page_size" ]; then
        pool_data=$((pool_pages_data * page_size))
    fi
    if [ -z "$pool_total" ]; then
        if [ -n "$buffer_size" ]; then
            pool_total="$buffer_size"
        elif [ -n "$pool_pages_total" ] && [ -n "$page_size" ]; then
            pool_total=$((pool_pages_total * page_size))
        fi
    fi

    if [ -n "$pool_total" ] && [ "$pool_total" -gt 0 ] 2>/dev/null; then
        pool_used_pct=$(awk -v d="$pool_data" -v t="$pool_total" 'BEGIN {printf "%.2f", (d/t)*100}')
    fi
    if [ -n "$requests" ] && [ "$requests" -gt 0 ] 2>/dev/null; then
        hit_rate=$(awk -v r="$reads" -v q="$requests" 'BEGIN {printf "%.4f", 1 - (r/q)}')
    fi

    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "$now pool_used_pct=${pool_used_pct} hit_rate=${hit_rate} queries=${questions:-na}" >> "$file"
}

start_mysql_perf() {
    local file="$1"
    local err_file="${2-}"
    MYSQL_PERF_PID=""
    if ! $USE_MYSQL_PERF; then
        return 0
    fi
    if ! mysql_perf_sample "$file" "$err_file"; then
        warn "Unable to collect MySQL perf sample; skipping mysql-perf log"
        USE_MYSQL_PERF=false
        return 0
    fi
    (
        local fail_count=0
        local max_fail=3
        while true; do
            sleep "$MYSQL_INTERVAL"
            if mysql_perf_sample "$file" "$err_file"; then
                fail_count=0
            else
                fail_count=$((fail_count + 1))
                if [ "$fail_count" -ge "$max_fail" ]; then
                    warn "MySQL perf sampling failed ${fail_count} times; stopping mysql-perf log"
                    break
                fi
            fi
        done
    ) &
    MYSQL_PERF_PID=$!
}

stop_mysql_perf() {
    if [ -n "${MYSQL_PERF_PID-}" ]; then
        kill "$MYSQL_PERF_PID" >/dev/null 2>&1 || true
    fi
}

summarize_wrk() {
    local domain="$1"
    local cache="$2"
    local file="$3"
    local latency_avg
    local latency_max
    local req_per_sec
    local total_requests
    local non_2xx
    local latency_avg_ms
    local latency_max_ms

    if [ ! -s "$file" ]; then
        warn "Missing or empty wrk output for ${domain} (${cache}): $file"
        return
    fi

    latency_avg=$(awk '/Latency/ {print $2; exit}' "$file")
    latency_max=$(awk '/Latency/ {print $4; exit}' "$file")
    req_per_sec=$(awk '/Requests\/sec:/ {print $2; exit}' "$file")
    total_requests=$(awk '/requests in/ {print $1; exit}' "$file")
    non_2xx=$(awk '/Non-2xx or 3xx responses:/ {print $5; exit}' "$file")
    non_2xx=${non_2xx:-0}

    case "$latency_avg" in
        *nan*|*NAN*) latency_avg="na" ;;
        0.00us) latency_avg="na" ;;
    esac
    case "$latency_max" in
        *nan*|*NAN*) latency_max="na" ;;
    esac
    if [ "$latency_avg" = "na" ]; then
        calib_latency=$(awk -F 'mean lat.: ' '/Thread calibration: mean lat.:/ {print $2}' "$file" | awk '{print $1}' | tr -d ',')
        if [ -n "$calib_latency" ]; then
            latency_avg="$calib_latency"
        fi
    fi
    if [ "$latency_max" = "0.00us" ]; then
        latency_max="na"
    fi

    latency_avg_ms=$(latency_to_ms "$latency_avg")
    latency_max_ms=$(latency_to_ms "$latency_max")

    if [ "$REPORT_MODE" = "true" ]; then
        report_section "PERF" "Summary"
        report_kv "DOMAIN" "$domain"
        report_kv "CACHE" "$cache"
        report_kv "REQ_PER_SEC" "${req_per_sec:-na}"
        report_kv "LATENCY_AVG" "${latency_avg_ms:-na}"
        report_kv "LATENCY_MAX" "${latency_max_ms:-na}"
        report_kv "TOTAL_REQUESTS" "${total_requests:-na}"
        report_kv "NON_200" "${non_2xx:-0}"
    fi
}

fmt_pct() {
    local raw="${1:-}"
    if [ -z "$raw" ] || [ "$raw" = "na" ]; then
        echo "na"
        return
    fi
    raw="${raw%%%}"
    awk -v v="$raw" 'BEGIN {printf "%.1f%%", v}'
}

latency_to_ms() {
    local raw="${1:-}"
    if [ -z "$raw" ] || [ "$raw" = "na" ]; then
        echo "na"
        return
    fi
    local val unit
    val="${raw%%[a-z]*}"
    unit="${raw#"$val"}"
    case "$unit" in
        us) val=$(awk -v v="$val" 'BEGIN {printf "%.0f", v/1000.0}') ;;
        ms) val=$(awk -v v="$val" 'BEGIN {printf "%.0f", v}') ;;
        s)  val=$(awk -v v="$val" 'BEGIN {printf "%.0f", v*1000.0}') ;;
        *) echo "na"; return ;;
    esac
    format_commas "$val"
}

format_commas() {
    local num="${1:-0}"
    echo "$num" | awk '{
        s=$0
        n=length(s)
        out=""
        while (n > 3) {
            out="," substr(s, n-2, 3) out
            n-=3
        }
        out=substr(s,1,n) out
        print out
    }'
}

bin5_trend_pidstat_cmd() {
    local file="$1"
    local cmd="$2"
    python3 - "$file" "$cmd" <<'EOF'
import re
import sys

path = sys.argv[1]
cmd = sys.argv[2] if len(sys.argv) > 2 else "apache2"
mode = None
ts_sum = {}

def to_seconds(t, ampm):
    h, m, s = map(int, t.split(":"))
    if ampm == "PM" and h != 12:
        h += 12
    if ampm == "AM" and h == 12:
        h = 0
    return h * 3600 + m * 60 + s

with open(path, "r", encoding="utf-8", errors="replace") as fh:
    for line in fh:
        if re.search(r"%usr\s+%system", line):
            mode = "cpu"
            continue
        if "minflt/s" in line:
            mode = "mem"
            continue
        if mode != "cpu":
            continue
        parts = line.split()
        if len(parts) < 10 or parts[-1] != cmd:
            continue
        cpu = parts[-3]
        if not re.match(r"^[0-9.]+$", cpu):
            continue
        ts = to_seconds(parts[0], parts[1])
        ts_sum[ts] = ts_sum.get(ts, 0.0) + float(cpu)

series = [ts_sum[k] for k in sorted(ts_sum)]

if not series:
    print("BIN5_AVG=na")
    print("SLOPE_PCT=na")
    raise SystemExit(0)

n = len(series)
size = max(1, n // 5)
bins = []
i = 0
for b in range(5):
    j = n if b == 4 else min(n, i + size)
    chunk = series[i:j]
    if chunk:
        bins.append(sum(chunk) / len(chunk))
    i = j

bin_str = ",".join(f"{v:.1f}%" for v in bins)
if len(bins) < 2:
    slope_pct = "na"
elif sum(bins) == 0:
    slope_pct = "na"
else:
    mean = sum(bins) / len(bins)
    x = list(range(len(bins)))
    x_mean = (len(bins) - 1) / 2.0
    cov = sum((xi - x_mean) * (yi - mean) for xi, yi in zip(x, bins))
    var = sum((xi - x_mean) ** 2 for xi in x)
    slope = cov / var if var else 0.0
    pct = (slope * (len(bins) - 1)) / mean * 100.0
    slope_pct = f"{pct:.1f}"

print(f"BIN5_AVG={bin_str}")
print(f"SLOPE_PCT={slope_pct}%" if slope_pct != "na" else "SLOPE_PCT=na")
EOF
}

pidstat_summary_for_cmd() {
    local file="$1"
    local cmd="$2"
    awk -v cmd="$cmd" '
        /%usr +%system/ {mode="cpu"; next}
        /minflt\/s/ {mode="mem"; next}
        mode=="cpu" && $NF==cmd && $9 ~ /^[0-9.]+$/ {
            ts=$1" "$2
            sum[ts]+=$9
        }
        END {
            max=-1
            count=0
            total=0
            for (t in sum) {
                total+=sum[t]
                count++
                if (sum[t]>max) {
                    max=sum[t]
                }
            }
            if (count>0) {
                printf "%.2f %.2f %d\n", total/count, max, count
            }
        }
    ' "$file"
}

summarize_sar() {
    local domain="$1"
    local cache="$2"
    local file="$3"
    local run_window_sec="${4:-}"
    local mem_avail_mb_min
    local mem_avail_mb_avg
    local mem_used_mb_max
    local mem_used_mb_avg
    local cpu_total_max
    local cpu_total_avg
    local cpu_idle_min
    local cpu_idle_avg
    local cpu_busy_cores_max
    local cpu_bin5
    local cpu_slope_pct

    if [ ! -s "$file" ]; then
        warn "Missing or empty sar output for ${domain} (${cache}): $file"
        return
    fi
    local summary
    summary=$(python3 - "$file" "$CPU_CORES" <<'PYCODE'
import sys
from datetime import datetime

path = sys.argv[1]
cores = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0

cpu_records = []
mem_avail = []
mem_used_kb = []

mode = None
idx = {}

def parse_ts(ts):
    try:
        return datetime.strptime(ts, "%Y-%m-%d %H:%M:%S %Z")
    except Exception:
        return None

with open(path, "r", encoding="utf-8", errors="replace") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        if line.startswith("#"):
            header = line.lstrip("#").strip()
            cols = [c.strip() for c in header.split(";")]
            if "CPU" in cols and "%user" in cols:
                mode = "cpu"
                idx = {name: i for i, name in enumerate(cols)}
            elif "kbmemfree" in cols and "kbavail" in cols:
                mode = "mem"
                idx = {name: i for i, name in enumerate(cols)}
            elif "runq-sz" in cols and "ldavg-1" in cols:
                mode = "load"
                idx = {name: i for i, name in enumerate(cols)}
            else:
                mode = None
                idx = {}
            continue
        parts = [p.strip() for p in line.split(";")]
        if mode == "cpu":
            cpu_id = parts[idx.get("CPU", 3)]
            if cpu_id not in ("-1", "all"):
                continue
            idle = float(parts[idx["%idle"]])
            user = float(parts[idx["%user"]])
            system = float(parts[idx["%system"]])
            iowait = float(parts[idx["%iowait"]])
            steal = float(parts[idx["%steal"]])
            ts = parse_ts(parts[idx["timestamp"]])
            total = 100.0 - idle
            cpu_records.append((ts, total, user, system, iowait, steal))
        elif mode == "mem":
            mem_avail.append(float(parts[idx["kbavail"]]))
            mem_used_kb.append(float(parts[idx["kbmemused"]]))
def safe_min(vals):
    return min(vals) if vals else None

def safe_max(vals):
    return max(vals) if vals else None

def safe_avg(vals):
    return sum(vals) / len(vals) if vals else None

cpu_total = [r[1] for r in cpu_records]
cpu_idle = [100.0 - r[1] for r in cpu_records]
cpu_user = [r[2] for r in cpu_records]
cpu_system = [r[3] for r in cpu_records]
cpu_iowait = [r[4] for r in cpu_records]
cpu_steal = [r[5] for r in cpu_records]

cpu_total_max = safe_max(cpu_total)
cpu_total_avg = safe_avg(cpu_total)
cpu_busy_cores = (cpu_total_max / 100.0) * cores if cpu_total_max is not None else None

mem_avail_mb_min = safe_min(mem_avail)
mem_avail_mb_avg = safe_avg(mem_avail)
mem_used_mb_max = safe_max(mem_used_kb)
mem_used_mb_avg = safe_avg(mem_used_kb)
if mem_avail_mb_min is not None:
    mem_avail_mb_min = int(mem_avail_mb_min / 1024)
if mem_avail_mb_avg is not None:
    mem_avail_mb_avg = int(mem_avail_mb_avg / 1024)
if mem_used_mb_max is not None:
    mem_used_mb_max = int(mem_used_mb_max / 1024)
if mem_used_mb_avg is not None:
    mem_used_mb_avg = int(mem_used_mb_avg / 1024)

def bin5(series):
    if not series:
        return "na", "na"
    series = sorted(series, key=lambda x: x[0] or datetime.min)
    vals = [v for _, v, *_ in series]
    n = len(vals)
    size = max(1, n // 5)
    bins = []
    i = 0
    for b in range(5):
        j = n if b == 4 else min(n, i + size)
        chunk = vals[i:j]
        if chunk:
            bins.append(sum(chunk) / len(chunk))
        i = j
    bin_str = ",".join(f"{v:.1f}%" for v in bins)
    if len(bins) < 2:
        slope_pct = "na"
        return bin_str, slope_pct
    mean = sum(bins) / len(bins)
    if mean == 0:
        slope_pct = "na"
        return bin_str, slope_pct
    x = list(range(len(bins)))
    x_mean = (len(bins) - 1) / 2.0
    cov = sum((xi - x_mean) * (yi - mean) for xi, yi in zip(x, bins))
    var = sum((xi - x_mean) ** 2 for xi in x)
    slope = cov / var if var else 0.0
    pct = (slope * (len(bins) - 1)) / mean * 100.0
    slope_pct = pct
    return bin_str, slope_pct

bin_str, slope_pct = bin5(cpu_records)

def emit(name, val, fmt=None):
    if val is None:
        print(f"{name}=na")
    else:
        if fmt:
            print(f"{name}={fmt.format(val)}")
        else:
            print(f"{name}={val}")

emit("MEM_AVAIL_MB_MIN", mem_avail_mb_min)
emit("MEM_AVAIL_MB_AVG", mem_avail_mb_avg)
emit("MEM_USED_MB_MAX", mem_used_mb_max)
emit("MEM_USED_MB_AVG", mem_used_mb_avg)
emit("CPU_TOTAL_PCT_MAX", cpu_total_max, "{:.1f}%")
emit("CPU_TOTAL_PCT_AVG", cpu_total_avg, "{:.1f}%")
emit("CPU_IDLE_PCT_MIN", safe_min(cpu_idle), "{:.1f}%")
emit("CPU_IDLE_PCT_AVG", safe_avg(cpu_idle), "{:.1f}%")
emit("CPU_BUSY_CORES_MAX", cpu_busy_cores, "{:.2f}")
print(f"CPU_TOTAL_BIN5_AVG={bin_str}")
if slope_pct == "na":
    print("CPU_TOTAL_TREND=na")
else:
    print(f"CPU_TOTAL_TREND={slope_pct:.1f}%")
PYCODE
)
    while IFS='=' read -r k v; do
        case "$k" in
            MEM_AVAIL_MB_MIN) mem_avail_mb_min="$v" ;;
            MEM_AVAIL_MB_AVG) mem_avail_mb_avg="$v" ;;
            MEM_USED_MB_MAX) mem_used_mb_max="$v" ;;
            MEM_USED_MB_AVG) mem_used_mb_avg="$v" ;;
            CPU_TOTAL_PCT_MAX) cpu_total_max="$v" ;;
            CPU_TOTAL_PCT_AVG) cpu_total_avg="$v" ;;
            CPU_IDLE_PCT_MIN) cpu_idle_min="$v" ;;
            CPU_IDLE_PCT_AVG) cpu_idle_avg="$v" ;;
            CPU_BUSY_CORES_MAX) cpu_busy_cores_max="$v" ;;
            CPU_TOTAL_BIN5_AVG) cpu_bin5="$v" ;;
            CPU_TOTAL_TREND) cpu_slope_pct="$v" ;;
        esac
    done <<<"$summary"

    report_section "PERF" "Telemetry"
    report_kv "DOMAIN" "$domain"
    if [ "$cache" != "telemetry" ]; then
        report_kv "CACHE" "$cache"
    fi
    if [ -n "$run_window_sec" ]; then
        report_kv "RUN_WINDOW_SEC" "$run_window_sec"
    fi
    report_kv "MEM_AVAIL_MB_MIN" "${mem_avail_mb_min:-na}"
    report_kv "MEM_AVAIL_MB_AVG" "${mem_avail_mb_avg:-na}"
    report_kv "MEM_USED_MB_MAX" "${mem_used_mb_max:-na}"
    report_kv "MEM_USED_MB_AVG" "${mem_used_mb_avg:-na}"
    report_kv "CPU_BUSY_CORES_MAX" "${cpu_busy_cores_max:-na}"
    report_kv "CPU_TOTAL_PCT_MAX" "${cpu_total_max:-na}"
    report_kv "CPU_TOTAL_PCT_AVG" "${cpu_total_avg:-na}"
    report_kv "CPU_IDLE_PCT_MIN" "${cpu_idle_min:-na}"
    report_kv "CPU_IDLE_PCT_AVG" "${cpu_idle_avg:-na}"
    report_kv "CPU_TOTAL_BIN5_AVG" "$cpu_bin5"
    report_kv "CPU_TOTAL_TREND" "${cpu_slope_pct:-na}"
}

summarize_pidstat() {
    local domain="$1"
    local cache="$2"
    local file="$3"
    local mode="${4:-}"
    local run_window_sec="${5:-}"
    local include_wrk="true"
    local apache_avg
    local apache_max
    local apache_samples
    local mysql_avg
    local mysql_max
    local mysql_samples
    local wrk_avg
    local wrk_max
    local wrk_samples
    local pidstat_summary
    local apache_bin5
    local apache_trend
    local mysql_bin5
    local mysql_trend
    local wrk_bin5
    local wrk_trend

    if [ ! -s "$file" ]; then
        warn "Missing or empty pidstat output for ${domain} (${cache}): $file"
        return
    fi

    pidstat_summary=$(pidstat_summary_for_cmd "$file" apache2 || true)
    read -r apache_avg apache_max apache_samples <<<"$pidstat_summary"
    pidstat_summary=$(pidstat_summary_for_cmd "$file" mysqld || true)
    read -r mysql_avg mysql_max mysql_samples <<<"$pidstat_summary"
    pidstat_summary=$(pidstat_summary_for_cmd "$file" wrk || true)
    read -r wrk_avg wrk_max wrk_samples <<<"$pidstat_summary"

    apache_bin5="na"
    apache_slope_pct="na"
    mysql_bin5="na"
    mysql_slope_pct="na"
    wrk_bin5="na"
    wrk_slope_pct="na"
    if [ "$mode" = "none" ]; then
        include_wrk="false"
    fi
    if [ "$REPORT_MODE" = "true" ]; then
        while IFS='=' read -r k v; do
            case "$k" in
                BIN5_AVG) apache_bin5="$v" ;;
                SLOPE_PCT) apache_slope_pct="$v" ;;
            esac
        done < <(bin5_trend_pidstat_cmd "$file" apache2)
        while IFS='=' read -r k v; do
            case "$k" in
                BIN5_AVG) mysql_bin5="$v" ;;
                SLOPE_PCT) mysql_slope_pct="$v" ;;
            esac
        done < <(bin5_trend_pidstat_cmd "$file" mysqld)
        while IFS='=' read -r k v; do
            case "$k" in
                BIN5_AVG) wrk_bin5="$v" ;;
                SLOPE_PCT) wrk_slope_pct="$v" ;;
            esac
        done < <(bin5_trend_pidstat_cmd "$file" wrk)
    fi

    report_section "PERF" "Process"
    report_kv "DOMAIN" "$domain"
    if [ -n "$run_window_sec" ]; then
        report_kv "RUN_WINDOW_SEC" "$run_window_sec"
    fi
    if [ "$cache" != "telemetry" ]; then
        report_kv "CACHE" "$cache"
    fi
    report_kv "APACHE_CPU_SUM_AVG" "$(fmt_pct "${apache_avg:-na}")"
    report_kv "APACHE_CPU_SUM_MAX" "$(fmt_pct "${apache_max:-na}")"
    report_kv "APACHE_CPU_SAMPLES" "${apache_samples:-0}"
    report_kv "APACHE_CPU_SUM_BIN5_AVG" "$apache_bin5"
    report_kv "APACHE_CPU_SUM_SLOPE_PCT" "$apache_slope_pct"
    report_kv "MYSQL_CPU_SUM_AVG" "$(fmt_pct "${mysql_avg:-na}")"
    report_kv "MYSQL_CPU_SUM_MAX" "$(fmt_pct "${mysql_max:-na}")"
    report_kv "MYSQL_CPU_SAMPLES" "${mysql_samples:-0}"
    report_kv "MYSQL_CPU_SUM_BIN5_AVG" "$mysql_bin5"
    report_kv "MYSQL_CPU_SUM_SLOPE_PCT" "$mysql_slope_pct"
    if [ "$include_wrk" = "true" ]; then
        report_kv "WRK_CPU_SUM_AVG" "$(fmt_pct "${wrk_avg:-na}")"
        report_kv "WRK_CPU_SUM_MAX" "$(fmt_pct "${wrk_max:-na}")"
        report_kv "WRK_CPU_SAMPLES" "${wrk_samples:-0}"
        report_kv "WRK_CPU_SUM_BIN5_AVG" "$wrk_bin5"
        report_kv "WRK_CPU_SUM_SLOPE_PCT" "$wrk_slope_pct"
    fi
}

report_section() {
    section "$1" "$2"
    if [ -n "${REPORT_FILE-}" ]; then
        echo "== $1:$2" >> "$REPORT_FILE"
    fi
}

report_kv() {
    kv "$1" "$2"
    if [ -n "${REPORT_FILE-}" ]; then
        echo "$1=$2" >> "$REPORT_FILE"
    fi
}

start_telemetry() {
    local prefix="$1"
    TELEMETRY_PIDS=()
    local tool
    for tool in "${TELEMETRY_SELECTED[@]}"; do
        case "${TELEMETRY_KIND[$tool]-}" in
            cmd)
                local -a cmd=()
                local suffix="${TELEMETRY_SUFFIX[$tool]}"
                local out_file="$OUT_DIR/${prefix}_${suffix}.log"
                local err_file="$OUT_DIR/${prefix}_${suffix}.err"
                local pid
                telemetry_cmd_for "$tool" cmd
                if [ "$tool" = "sar" ] && [ -n "${SAR_RAW-}" ]; then
                    out_file="$SAR_RAW"
                fi
                if [ "$ERR_MODE" = "true" ]; then
                    pid=$(start_cmd "telemetry:${tool}" "both" "$out_file" "$err_file" -- "${cmd[@]}")
                else
                    pid=$(start_cmd "telemetry:${tool}" "out" "$out_file" -- "${cmd[@]}")
                fi
                TELEMETRY_PIDS+=("$pid")
                ;;
        esac
    done
}

stop_telemetry() {
    local pid
    for pid in "${TELEMETRY_PIDS[@]-}"; do
        if [ -n "${pid-}" ]; then
            kill "$pid" >/dev/null 2>&1 || true
        fi
    done
}

finalize_sar_log() {
    if ! $USE_SAR; then
        return 0
    fi
    if [ -z "${SAR_BIN-}" ] || [ ! -f "$SAR_BIN" ]; then
        warn "Missing sar binary output; skip sadf conversion"
        return 0
    fi
    if [ -z "${SAR_LOG-}" ]; then
        warn "Missing sar log path; skip sadf conversion"
        return 0
    fi
    local err_file=""
    local cmd
    cmd="sadf -d \"$SAR_BIN\" -- -u -r | awk 'BEGIN {keep=0} /^# / {if (\$0 ~ /;CPU;%user/ || \$0 ~ /;kbmemfree;/) {keep=1; print; next} keep=0; next} keep {print}'"
    if [ "$ERR_MODE" = "true" ]; then
        err_file="${SAR_LOG%.log}.err"
        run_cmd "sadf:sar" "both" "$SAR_LOG" "$err_file" -- bash -c "$cmd"
    else
        run_cmd "sadf:sar" "out" "$SAR_LOG" -- bash -c "$cmd"
    fi
}

for domain in "${DOMAINS[@]}"; do
    section "$MODE_UPPER" "Domain"
    kv "DOMAIN" "$domain"

    label=$(echo "$domain" | tr '.-' '__')
    prefix="${label}_${RUN_ID}"
    REPORT_FILE=""
    if [ "$REPORT_MODE" = "true" ]; then
        REPORT_FILE="$OUT_DIR/${prefix}_report.txt"
        : > "$REPORT_FILE"
    fi

    DOMAIN_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    DOMAIN_START_LOCAL=$(date +%Y-%m-%dT%H:%M:%S)
    DOMAIN_START_EPOCH=$(date -u +%s)
    HEAD_EXIT=""
    LOAD_EXIT=""
    HEAD_CMD=""
    HEAD_BUST_CMD=""
    LOAD_CMD=""
    LOAD_BUST_CMD=""
    DID_CACHED=false
    DID_BUST=false
    SAR_CMD=""
    SAR_BIN=""
    SAR_RAW=""
    SAR_LOG=""
    SADF_CMD=""
    PIDSTAT_CMD=""
    VMSTAT_CMD=""
    IOSTAT_CMD=""
    CGTOP_CMD=""
    TELEMETRY_SCOPE="domain"
    MYSQL_PERF_LOG=""
    MYSQL_PERF_ERR=""
    if $USE_SAR; then
        SAR_BIN="$OUT_DIR/${prefix}_sar.bin"
        SAR_RAW="$OUT_DIR/${prefix}_sar.raw.log"
        SAR_LOG="$OUT_DIR/${prefix}_sar.log"
        TELEMETRY_CMD_SAR=(sar -o "$SAR_BIN" -u -r)
        SAR_CMD="$(telemetry_cmd_string sar)"
        SADF_CMD="sadf -d $SAR_BIN -- -u -r | awk 'BEGIN {keep=0} /^# / {if ($0 ~ /;CPU;%user/ || $0 ~ /;kbmemfree;/) {keep=1; print; next} keep=0; next} keep {print}'"
    fi
    if $USE_PIDSTAT; then
        PIDSTAT_CMD="$(telemetry_cmd_string pidstat)"
    fi
    if $USE_VMSTAT; then
        VMSTAT_CMD="$(telemetry_cmd_string vmstat)"
    fi
    if $USE_IOSTAT; then
        IOSTAT_CMD="$(telemetry_cmd_string iostat)"
    fi
    if $USE_CGTOP; then
        CGTOP_CMD="$(telemetry_cmd_string cgtop)"
    fi
    if [ "${#TELEMETRY_SELECTED[@]}" -gt 0 ]; then
        start_telemetry "$prefix"
    fi
    if $USE_MYSQL_PERF; then
        MYSQL_PERF_LOG="$OUT_DIR/${prefix}_mysql-perf.log"
        if $ERR_MODE; then
            MYSQL_PERF_ERR="$OUT_DIR/${prefix}_mysql-perf.err"
        fi
        start_mysql_perf "$MYSQL_PERF_LOG" "${MYSQL_PERF_ERR-}"
    fi

    base_url="https://${domain}/"
    bust_url="https://${domain}/?${CACHE_BUST_PARAM}=${RUN_ID}"

    if [ "$HEAD_MODE" = "true" ]; then
        if [ "$CACHE_MODE" = "both" ] || [ "$CACHE_MODE" = "cached" ]; then
            HEAD_CMD="$(cmd_join curl -I "$base_url")"
            set +e
            if $ERR_MODE; then
                run_cmd "head:cached" "both" "$OUT_DIR/${prefix}_head.txt" "$OUT_DIR/${prefix}_head.err" -- curl -I "$base_url"
            else
                run_cmd "head:cached" "out" "$OUT_DIR/${prefix}_head.txt" -- curl -I "$base_url"
            fi
            head_status=$?
            set -e
            if [ -z "$HEAD_EXIT" ] || [ "$HEAD_EXIT" -eq 0 ] 2>/dev/null; then
                HEAD_EXIT="$head_status"
            fi
            check_expected_file "$OUT_DIR/${prefix}_head.txt" "head headers (cached)"
        fi
        if [ "$CACHE_MODE" = "both" ] || [ "$CACHE_MODE" = "bust" ]; then
            HEAD_BUST_CMD="$(cmd_join curl -I "$bust_url")"
            set +e
            if $ERR_MODE; then
                run_cmd "head:bust" "both" "$OUT_DIR/${prefix}_head_bust.txt" "$OUT_DIR/${prefix}_head_bust.err" -- curl -I "$bust_url"
            else
                run_cmd "head:bust" "out" "$OUT_DIR/${prefix}_head_bust.txt" -- curl -I "$bust_url"
            fi
            head_status=$?
            set -e
            if [ -z "$HEAD_EXIT" ] || [ "$HEAD_EXIT" -eq 0 ] 2>/dev/null; then
                HEAD_EXIT="$head_status"
            fi
            check_expected_file "$OUT_DIR/${prefix}_head_bust.txt" "head headers (bust)"
        fi
    fi

    if [ "$MODE" = "none" ]; then
        sleep "$DURATION"
    else
        wrk_cmd_cached=("$WRK_BIN" -t"$THREADS" -c"$CONNECTIONS" -d"$DURATION" -R"$RATE")
        wrk_cmd_bust=("$WRK_BIN" -t"$THREADS" -c"$CONNECTIONS" -d"$DURATION" -R"$RATE")

        if [ "$CACHE_MODE" = "both" ] || [ "$CACHE_MODE" = "cached" ]; then
            DID_CACHED=true
            LOAD_CMD="$(cmd_join "${wrk_cmd_cached[@]}" "$base_url")"
            set +e
            if $ERR_MODE; then
                run_cmd "wrk:cached" "both" "$OUT_DIR/${prefix}_wrk.txt" "$OUT_DIR/${prefix}_wrk.err" -- "${wrk_cmd_cached[@]}" "$base_url"
            else
                run_cmd "wrk:cached" "out" "$OUT_DIR/${prefix}_wrk.txt" -- "${wrk_cmd_cached[@]}" "$base_url"
            fi
            wrk_status=$?
            set -e
            if [ -z "$LOAD_EXIT" ] || [ "$LOAD_EXIT" -eq 0 ] 2>/dev/null; then
                LOAD_EXIT="$wrk_status"
            fi
            check_expected_file "$OUT_DIR/${prefix}_wrk.txt" "wrk output (cached)"
            summarize_wrk "$domain" "cached" "$OUT_DIR/${prefix}_wrk.txt"
        fi

        if [ "$CACHE_MODE" = "both" ] || [ "$CACHE_MODE" = "bust" ]; then
            DID_BUST=true
            LOAD_BUST_CMD="$(cmd_join "${wrk_cmd_bust[@]}" "$bust_url")"
            set +e
            if $ERR_MODE; then
                run_cmd "wrk:bust" "both" "$OUT_DIR/${prefix}_wrk_bust.txt" "$OUT_DIR/${prefix}_wrk_bust.err" -- "${wrk_cmd_bust[@]}" "$bust_url"
            else
                run_cmd "wrk:bust" "out" "$OUT_DIR/${prefix}_wrk_bust.txt" -- "${wrk_cmd_bust[@]}" "$bust_url"
            fi
            wrk_status=$?
            set -e
            if [ -z "$LOAD_EXIT" ] || [ "$LOAD_EXIT" -eq 0 ] 2>/dev/null; then
                LOAD_EXIT="$wrk_status"
            fi
            check_expected_file "$OUT_DIR/${prefix}_wrk_bust.txt" "wrk output (bust)"
            summarize_wrk "$domain" "bust" "$OUT_DIR/${prefix}_wrk_bust.txt"
        fi
    fi

    if $USE_SAR || $USE_PIDSTAT || $USE_VMSTAT || $USE_IOSTAT || $USE_CGTOP; then
        stop_telemetry
        stop_mysql_perf
        finalize_sar_log
        if [ -n "$MYSQL_PERF_LOG" ]; then
            check_expected_file "$MYSQL_PERF_LOG" "mysql perf log"
        fi
    fi
    DOMAIN_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    DOMAIN_END_LOCAL=$(date +%Y-%m-%dT%H:%M:%S)
    DOMAIN_END_EPOCH=$(date -u +%s)
    RUN_WINDOW_SEC=$((DOMAIN_END_EPOCH - DOMAIN_START_EPOCH))

    if [ "$REPORT_MODE" = "true" ]; then
        if $USE_PIDSTAT; then
            summarize_pidstat "$domain" "telemetry" "$OUT_DIR/${prefix}_pidstat.log" "$MODE" "$RUN_WINDOW_SEC"
        fi
        if $USE_SAR; then
            summarize_sar "$domain" "telemetry" "$OUT_DIR/${prefix}_sar.log" "$RUN_WINDOW_SEC"
        fi
    fi
    RUN_PARAM="$OUT_DIR/${prefix}_run.param"
    {
        echo "HOSTNAME: $HOSTNAME_VAL"
        echo "CPU_CORES: $CPU_CORES"
        echo "ORIGIN_IPV4: $ORIGIN_IPV4_VAL"
        echo "RUN_ID: $RUN_ID"
        echo "RUN_DIR: $OUT_DIR"
        if [ "$MODE" = "none" ]; then
            echo "KIND: idle"
        else
            echo "KIND: load"
        fi
        echo "DOMAIN: $domain"
        echo "MODE: $MODE"
        echo "CACHE_MODE: $CACHE_MODE"
        echo "UTC_START: $DOMAIN_START_UTC"
        echo "UTC_END: $DOMAIN_END_UTC"
        echo "LOCAL_TZ: $LOCAL_TZ"
        echo "LOCAL_OFFSET: $LOCAL_OFFSET"
        echo "LOCAL_START: $DOMAIN_START_LOCAL"
        echo "LOCAL_END: $DOMAIN_END_LOCAL"
        echo "RUN_WINDOW_SEC: $RUN_WINDOW_SEC"
        echo "LOG_PAD_SEC: $LOG_PAD_SEC"
        echo "REPORT_MODE: $REPORT_MODE"
        echo "ERR_MODE: $ERR_MODE"
        echo "SCRIPT_EXIT: 0"
        if [ -n "$HEAD_EXIT" ]; then
            echo "HEAD_EXIT: $HEAD_EXIT"
        fi
        if [ -n "$LOAD_EXIT" ]; then
            echo "LOAD_EXIT: $LOAD_EXIT"
        fi
        echo "RATE: $RATE"
        echo "THREADS: $THREADS"
        echo "CONNECTIONS: $CONNECTIONS"
        echo "DURATION: $DURATION"
        echo "LOAD_TOOL: $LOAD_TOOL"
        if [ -n "$LOAD_CMD" ]; then
            echo "LOAD_CMD: $LOAD_CMD"
        fi
        if [ -n "$LOAD_BUST_CMD" ]; then
            echo "LOAD_BUST_CMD: $LOAD_BUST_CMD"
        fi
        if [ -n "$HEAD_CMD" ]; then
            echo "HEAD_CMD: $HEAD_CMD"
        fi
        if [ -n "$HEAD_BUST_CMD" ]; then
            echo "HEAD_BUST_CMD: $HEAD_BUST_CMD"
        fi
        if [ "${#TELEMETRY_SELECTED[@]}" -gt 0 ]; then
            echo "TELEMETRY: $TELEMETRY_LIST"
            echo "TELEMETRY_SCOPE: $TELEMETRY_SCOPE"
            echo "TELEMETRY_INTERVAL_SEC: $INTERVAL"
        fi
        if $USE_SAR; then
            echo "SAR_CMD: $SAR_CMD"
            if [ -n "$SAR_BIN" ]; then
                echo "SAR_BIN: $SAR_BIN"
            fi
            if [ -n "$SAR_LOG" ]; then
                echo "SAR_LOG: $SAR_LOG"
            fi
            if [ -n "$SADF_CMD" ]; then
                echo "SADF_CMD: $SADF_CMD"
            fi
        fi
        if $USE_PIDSTAT; then
            echo "PIDSTAT_CMD: $PIDSTAT_CMD"
        fi
        if $USE_VMSTAT; then
            echo "VMSTAT_CMD: $VMSTAT_CMD"
        fi
        if $USE_IOSTAT; then
            echo "IOSTAT_CMD: $IOSTAT_CMD"
        fi
        if $USE_CGTOP; then
            echo "CGTOP_CMD: $CGTOP_CMD"
        fi
        if $USE_MYSQL_PERF; then
            echo "MYSQL_PERF_LOG: $MYSQL_PERF_LOG"
            if [ -n "$MYSQL_PERF_ERR" ]; then
                echo "MYSQL_PERF_ERR: $MYSQL_PERF_ERR"
            fi
            echo "MYSQL_PERF_CMD: mysql -N -e SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_bytes_data'; SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_bytes_total'; SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_pages_data'; SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_pages_total'; SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_reads'; SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_read_requests'; SHOW GLOBAL STATUS LIKE 'Questions'; SHOW VARIABLES LIKE 'innodb_buffer_pool_size'; SHOW VARIABLES LIKE 'innodb_page_size';"
            echo "MYSQL_PERF_INTERVAL_SEC: $MYSQL_INTERVAL"
        fi
    } > "$RUN_PARAM"

    if [ "$SLICE_MODE" = "true" ]; then
        if [ -x "$SCRIPTS_DIR/slice-logs.sh" ]; then
            if ! "$SCRIPTS_DIR/slice-logs.sh" --run-param "$RUN_PARAM"; then
                warn "slice-logs failed for ${domain}"
            fi
        else
            warn "slice-logs.sh not found; skipping slice for ${domain}"
        fi
    fi
done

status_pass "run=ok"
