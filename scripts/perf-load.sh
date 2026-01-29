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

DOMAINS=()
RUN_ID=""
OUT_DIR=""
DURATION=""
THREADS=""
CONNECTIONS=""
RATE=""
CACHE_BUST_PARAM="cache_bust"
CACHE_MODE="both"
INTERVAL=1
LOG_PAD_SEC="${LOG_PAD_SEC:-5}"
MODE="init"
TELEMETRY_LIST="sar"
USE_SAR=false
USE_PIDSTAT=false
USE_VMSTAT=false
USE_IOSTAT=false
USE_CGTOP=false
TELEMETRY_DETAIL=false
MODE_SET=false
SET_DURATION=false
SET_THREADS=false
SET_CONNECTIONS=false
SET_RATE=false
HEAD_MODE="false"
REPORT_MODE="false"
ALLOW_ROOT=false

usage() {
    cat <<'EOF'
perf-load.sh - Run init or load tests with optional telemetry collection.
Example: perf-load.sh --load --domain zero.directory

Options:
  --domain NAME  Domain to test (repeatable; positional also accepted)
  --init  Run init-mode tests (default)
  --load  Run load-mode tests
  --duration DURATION  wrk duration per run (default: 20s init and load)
  --threads N  wrk threads (default: 1 init, 2 load)
  --connections N  wrk connections (default: 1 init, 4 load)
  --rate N  wrk2 fixed request rate N req/sec (default: 10 init, 20 load)
  --run-id ID  Override the run identifier used in filenames (default: YYYYmmdd_HHMMSS)
  --out-dir DIR  Output directory (default: /var/tmp/multiwp/perf_<run-id>)
  --cache-bust PARAM  Cache-bust query parameter name (default: cache_bust)
  --cache MODE  Run cached, bust, or both (default: both; values: both|cached|bust)
  --interval N  Telemetry interval in seconds (default: 1)
  --telemetry LIST  Telemetry tools (default: sar; values: sar,pidstat,vmstat,iostat,cgtop,all,none)
  --head  Write response headers for cached and cache-busted requests
  --report  Emit summary metrics after each wrk run
  --help  Show this help

Notes:
  - wrk2 is always used; a rate is always applied (default per mode).
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
                telemetry=*) TELEMETRY_LIST="${OPTARG#*=}" ;;
                telemetry)
                    [ -n "${!OPTIND-}" ] || err "--telemetry requires a value"
                    TELEMETRY_LIST="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                head) HEAD_MODE="true" ;;
                report) REPORT_MODE="true" ;;
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
else
    $SET_DURATION || DURATION="20s"
    $SET_THREADS || THREADS=2
    $SET_CONNECTIONS || CONNECTIONS=4
    $SET_RATE || RATE=20
fi

WRK_BIN="${WRK_BIN:-}"
if [ -z "$WRK_BIN" ]; then
    if [ -x "/home/ubuntu/WP/wrk2/wrk" ]; then
        WRK_BIN="/home/ubuntu/WP/wrk2/wrk"
    else
        WRK_BIN="wrk2"
    fi
fi

parse_telemetry_list() {
    local list="$1"
    local expanded=""
    local item

    case "$list" in
        none)
            USE_SAR=false
            USE_PIDSTAT=false
            USE_VMSTAT=false
            USE_IOSTAT=false
            TELEMETRY_DETAIL=false
            return
            ;;
        all)
            expanded="sar,pidstat,vmstat,iostat,cgtop"
            ;;
        *)
            expanded="$list"
            ;;
    esac

    USE_SAR=false
    USE_PIDSTAT=false
    USE_VMSTAT=false
    USE_IOSTAT=false
    USE_CGTOP=false

    IFS=',' read -r -a items <<<"$expanded"
    for item in "${items[@]}"; do
        case "$item" in
            sar) USE_SAR=true ;;
            pidstat) USE_PIDSTAT=true ;;
            vmstat) USE_VMSTAT=true ;;
            iostat) USE_IOSTAT=true ;;
            cgtop) USE_CGTOP=true ;;
            none) err "--telemetry=none cannot be combined with other values" ;;
            *) err "--telemetry invalid value: $item" ;;
        esac
    done
    TELEMETRY_DETAIL=false
    if $USE_SAR && { $USE_PIDSTAT || $USE_VMSTAT || $USE_IOSTAT || $USE_CGTOP; }; then
        TELEMETRY_DETAIL=true
    fi
}

parse_telemetry_list "$TELEMETRY_LIST"

require_cmds "$WRK_BIN"
if $USE_SAR; then
    require_cmds sar
fi
if $USE_PIDSTAT; then
    require_cmds pidstat
fi
if $USE_VMSTAT; then
    require_cmds vmstat
fi
if $USE_IOSTAT; then
    require_cmds iostat
fi
if $USE_CGTOP; then
    require_cmds /usr/bin/systemd-cgtop
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
kv "TELEMETRY" "$TELEMETRY_LIST"
kv "HEAD" "$HEAD_MODE"
kv "REPORT" "$REPORT_MODE"

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

summarize_wrk() {
    local domain="$1"
    local cache="$2"
    local file="$3"
    local latency_avg
    local latency_max
    local req_per_sec
    local total_requests
    local non_2xx
    local not_200_pct

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

    if [ -n "$total_requests" ] && [ "$total_requests" -gt 0 ] 2>/dev/null; then
        not_200_pct=$(awk -v n="$non_2xx" -v t="$total_requests" 'BEGIN {printf "%.2f", (n / t) * 100}')
    else
        not_200_pct="na"
    fi

    if [ "$REPORT_MODE" = "true" ]; then
        report_section "PERF" "Summary"
        report_kv "DOMAIN" "$domain"
        report_kv "CACHE" "$cache"
        report_kv "REQ_PER_SEC" "${req_per_sec:-na}"
        report_kv "LATENCY_AVG" "${latency_avg:-na}"
        report_kv "LATENCY_MAX" "${latency_max:-na}"
        report_kv "NOT_200_PCT" "$not_200_pct"
    fi
}

bin5_trend_sar_cpu() {
    local file="$1"
    python3 - "$file" <<'EOF'
import re
import sys

path = sys.argv[1]
vals = []
sec = None

def to_seconds(t, ampm):
    h, m, s = map(int, t.split(":"))
    if ampm == "PM" and h != 12:
        h += 12
    if ampm == "AM" and h == 12:
        h = 0
    return h * 3600 + m * 60 + s

with open(path, "r", encoding="utf-8", errors="replace") as fh:
    for line in fh:
        if re.match(r"^\d\d:\d\d:\d\d\s+[AP]M\s+CPU\s+%user", line):
            sec = "cpu"
            continue
        if re.match(r"^\d\d:\d\d:\d\d\s+[AP]M\s+(kbmemfree|runq-sz|IFACE)", line):
            sec = None
            continue
        if sec != "cpu":
            continue
        parts = line.split()
        if len(parts) < 9 or parts[2] != "all":
            continue
        if not re.match(r"^[0-9.]+$", parts[8]):
            continue
        ts = to_seconds(parts[0], parts[1])
        total = 100.0 - float(parts[8])
        vals.append((ts, total))

vals.sort(key=lambda x: x[0])
series = [v for _, v in vals]

if not series:
    print("BIN5_AVG=na")
    print("TREND=na")
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

bin_str = ",".join(f"{v:.2f}" for v in bins)

first = bins[0]
last = bins[-1]
if first == 0:
    trend = "na"
else:
    pct = (last - first) / first * 100.0
    if pct > 5:
        trend = f"rising ({pct:.1f}%)"
    elif pct < -5:
        trend = f"falling ({pct:.1f}%)"
    else:
        trend = f"flat ({pct:.1f}%)"

print(f"BIN5_AVG={bin_str}")
print(f"TREND={trend}")
EOF
}

bin5_trend_pidstat_apache() {
    local file="$1"
    python3 - "$file" <<'EOF'
import re
import sys

path = sys.argv[1]
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
        if len(parts) < 10 or parts[-1] != "apache2":
            continue
        cpu = parts[-3]
        if not re.match(r"^[0-9.]+$", cpu):
            continue
        ts = to_seconds(parts[0], parts[1])
        ts_sum[ts] = ts_sum.get(ts, 0.0) + float(cpu)

series = [ts_sum[k] for k in sorted(ts_sum)]

if not series:
    print("BIN5_AVG=na")
    print("TREND=na")
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

bin_str = ",".join(f"{v:.2f}" for v in bins)

first = bins[0]
last = bins[-1]
if first == 0:
    trend = "na"
else:
    pct = (last - first) / first * 100.0
    if pct > 5:
        trend = f"rising ({pct:.1f}%)"
    elif pct < -5:
        trend = f"falling ({pct:.1f}%)"
    else:
        trend = f"flat ({pct:.1f}%)"

print(f"BIN5_AVG={bin_str}")
print(f"TREND={trend}")
EOF
}

summarize_sar() {
    local domain="$1"
    local cache="$2"
    local file="$3"
    local mem_avail_kb_min
    local mem_avail_mb_min
    local mem_avail_kb_avg
    local mem_avail_mb_avg
    local mem_used_pct_max
    local mem_used_pct_avg
    local cpu_idle_min
    local cpu_total_max
    local cpu_user_max
    local cpu_system_max
    local cpu_iowait_max
    local cpu_steal_max
    local cpu_busy_cores_max
    local load_1_max
    local load_1_avg
    local cpu_bin5
    local cpu_trend

    if [ ! -s "$file" ]; then
        warn "Missing or empty sar output for ${domain} (${cache}): $file"
        return
    fi

    mem_avail_kb_min=$(awk '
        /^..:..:.. [AP]M +kbmemfree/ {sec="mem"; next}
        /^..:..:.. [AP]M +(CPU|runq-sz|IFACE)/ {sec=""; next}
        /^..:..:.. [AP]M/ && sec=="mem" && $3 ~ /^[0-9]/ {print $4}
    ' "$file" | sort -n | head -n 1)

    mem_used_pct_max=$(awk '
        /^..:..:.. [AP]M +kbmemfree/ {sec="mem"; next}
        /^..:..:.. [AP]M +(CPU|runq-sz|IFACE)/ {sec=""; next}
        /^..:..:.. [AP]M/ && sec=="mem" && $3 ~ /^[0-9]/ {print $6}
    ' "$file" | sort -n | tail -n 1)
    mem_avail_kb_avg=$(awk '
        /^..:..:.. [AP]M +kbmemfree/ {sec="mem"; next}
        /^..:..:.. [AP]M +(CPU|runq-sz|IFACE)/ {sec=""; next}
        /^..:..:.. [AP]M/ && sec=="mem" && $3 ~ /^[0-9]/ {sum+=$4; n++}
        END {if (n>0) printf "%.0f", sum/n}
    ' "$file")
    mem_used_pct_avg=$(awk '
        /^..:..:.. [AP]M +kbmemfree/ {sec="mem"; next}
        /^..:..:.. [AP]M +(CPU|runq-sz|IFACE)/ {sec=""; next}
        /^..:..:.. [AP]M/ && sec=="mem" && $3 ~ /^[0-9]/ {sum+=$6; n++}
        END {if (n>0) printf "%.2f", sum/n}
    ' "$file")

    cpu_idle_min=$(awk '
        /^..:..:.. [AP]M +CPU +%user/ {sec="cpu"; next}
        /^..:..:.. [AP]M +(kbmemfree|runq-sz|IFACE)/ {sec=""; next}
        /^..:..:.. [AP]M/ && sec=="cpu" && $3=="all" {print $9}
    ' "$file" | sort -n | head -n 1)
    cpu_user_max=$(awk '
        /^..:..:.. [AP]M +CPU +%user/ {sec="cpu"; next}
        /^..:..:.. [AP]M +(kbmemfree|runq-sz|IFACE)/ {sec=""; next}
        /^..:..:.. [AP]M/ && sec=="cpu" && $3=="all" {print $4}
    ' "$file" | sort -n | tail -n 1)
    cpu_system_max=$(awk '
        /^..:..:.. [AP]M +CPU +%user/ {sec="cpu"; next}
        /^..:..:.. [AP]M +(kbmemfree|runq-sz|IFACE)/ {sec=""; next}
        /^..:..:.. [AP]M/ && sec=="cpu" && $3=="all" {print $6}
    ' "$file" | sort -n | tail -n 1)
    cpu_iowait_max=$(awk '
        /^..:..:.. [AP]M +CPU +%user/ {sec="cpu"; next}
        /^..:..:.. [AP]M +(kbmemfree|runq-sz|IFACE)/ {sec=""; next}
        /^..:..:.. [AP]M/ && sec=="cpu" && $3=="all" {print $7}
    ' "$file" | sort -n | tail -n 1)
    cpu_steal_max=$(awk '
        /^..:..:.. [AP]M +CPU +%user/ {sec="cpu"; next}
        /^..:..:.. [AP]M +(kbmemfree|runq-sz|IFACE)/ {sec=""; next}
        /^..:..:.. [AP]M/ && sec=="cpu" && $3=="all" {print $8}
    ' "$file" | sort -n | tail -n 1)
    if [ -n "$cpu_idle_min" ]; then
        cpu_total_max=$(awk -v idle="$cpu_idle_min" 'BEGIN {printf "%.2f", 100 - idle}')
    fi
    if [ -n "$cpu_total_max" ]; then
        cpu_busy_cores_max=$(awk -v total="$cpu_total_max" -v cores="$CPU_CORES" 'BEGIN {printf "%.2f", (total/100) * cores}')
    fi

    load_1_max=$(awk '
        /^..:..:.. [AP]M +runq-sz/ {sec="load"; next}
        /^..:..:.. [AP]M +(CPU|kbmemfree|IFACE)/ {sec=""; next}
        /^..:..:.. [AP]M/ && sec=="load" && $3 ~ /^[0-9]/ {print $5}
    ' "$file" | sort -n | tail -n 1)

    load_1_avg=$(awk '
        /^..:..:.. [AP]M +runq-sz/ {sec="load"; next}
        /^..:..:.. [AP]M +(CPU|kbmemfree|IFACE)/ {sec=""; next}
        /^..:..:.. [AP]M/ && sec=="load" && $3 ~ /^[0-9]/ {sum+=$5; n++}
        END {if (n>0) printf "%.2f", sum/n}
    ' "$file")

    if [ -n "$mem_avail_kb_min" ]; then
        mem_avail_mb_min=$((mem_avail_kb_min / 1024))
    fi
    if [ -n "$mem_avail_kb_avg" ]; then
        mem_avail_mb_avg=$((mem_avail_kb_avg / 1024))
    fi
    cpu_bin5="na"
    cpu_trend="na"
    if [ "$REPORT_MODE" = "true" ]; then
        while IFS='=' read -r k v; do
            case "$k" in
                BIN5_AVG) cpu_bin5="$v" ;;
                TREND) cpu_trend="$v" ;;
            esac
        done < <(bin5_trend_sar_cpu "$file")
    fi

    report_section "PERF" "Telemetry"
    report_kv "DOMAIN" "$domain"
    report_kv "CACHE" "$cache"
    if [ "$TELEMETRY_DETAIL" = "true" ]; then
        report_kv "MEM_AVAIL_MB_MIN" "${mem_avail_mb_min:-na}"
        report_kv "MEM_AVAIL_MB_AVG" "${mem_avail_mb_avg:-na}"
        report_kv "MEM_USED_PCT_MAX" "${mem_used_pct_max:-na}"
        report_kv "MEM_USED_PCT_AVG" "${mem_used_pct_avg:-na}"
        report_kv "CPU_TOTAL_PCT_MAX" "${cpu_total_max:-na}"
        report_kv "CPU_USER_PCT_MAX" "${cpu_user_max:-na}"
        report_kv "CPU_SYSTEM_PCT_MAX" "${cpu_system_max:-na}"
        report_kv "CPU_IOWAIT_PCT_MAX" "${cpu_iowait_max:-na}"
        report_kv "CPU_STEAL_PCT_MAX" "${cpu_steal_max:-na}"
        report_kv "CPU_BUSY_CORES_MAX" "${cpu_busy_cores_max:-na}"
        report_kv "CPU_TOTAL_BIN5_AVG" "$cpu_bin5"
        report_kv "CPU_TOTAL_TREND" "$cpu_trend"
        report_kv "LOAD_1_MAX" "${load_1_max:-na}"
        report_kv "LOAD_1_AVG" "${load_1_avg:-na}"
    else
        report_kv "CPU_TOTAL_PCT_MAX" "${cpu_total_max:-na}"
        report_kv "CPU_BUSY_CORES_MAX" "${cpu_busy_cores_max:-na}"
        report_kv "LOAD_1_MAX" "${load_1_max:-na}"
    fi
}

summarize_pidstat() {
    local domain="$1"
    local cache="$2"
    local file="$3"
    local cpu_sum_avg
    local cpu_sum_max
    local samples
    local pidstat_summary
    local cpu_bin5
    local cpu_trend

    if [ ! -s "$file" ]; then
        warn "Missing or empty pidstat output for ${domain} (${cache}): $file"
        return
    fi

    pidstat_summary=$(awk '
        /%usr +%system/ {mode="cpu"; next}
        /minflt\/s/ {mode="mem"; next}
        mode=="cpu" && $NF=="apache2" && $9 ~ /^[0-9.]+$/ {
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
    ' "$file")
    read -r cpu_sum_avg cpu_sum_max samples <<<"$pidstat_summary"
    cpu_bin5="na"
    cpu_trend="na"
    if [ "$REPORT_MODE" = "true" ]; then
        while IFS='=' read -r k v; do
            case "$k" in
                BIN5_AVG) cpu_bin5="$v" ;;
                TREND) cpu_trend="$v" ;;
            esac
        done < <(bin5_trend_pidstat_apache "$file")
    fi

    report_section "PERF" "Telemetry"
    report_kv "DOMAIN" "$domain"
    report_kv "CACHE" "$cache"
    report_kv "APACHE_CPU_SUM_AVG" "${cpu_sum_avg:-na}"
    report_kv "APACHE_CPU_SUM_MAX" "${cpu_sum_max:-na}"
    report_kv "APACHE_CPU_SAMPLES" "${samples:-0}"
    report_kv "APACHE_CPU_SUM_BIN5_AVG" "$cpu_bin5"
    report_kv "APACHE_CPU_SUM_TREND" "$cpu_trend"
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

    VMSTAT_PID=""
    PIDSTAT_PID=""
    IOSTAT_PID=""
    SAR_PID=""
    CGTOP_PID=""

    if $USE_VMSTAT; then
        vmstat "$INTERVAL" > "$OUT_DIR/${prefix}_vmstat.log" &
        VMSTAT_PID=$!
    fi
    if $USE_PIDSTAT; then
        pidstat -ru -C apache2 "$INTERVAL" > "$OUT_DIR/${prefix}_pidstat.log" &
        PIDSTAT_PID=$!
    fi
    if $USE_IOSTAT; then
        iostat -xz "$INTERVAL" > "$OUT_DIR/${prefix}_iostat.log" &
        IOSTAT_PID=$!
    fi
    if $USE_SAR; then
        sar -u -r -n DEV -q "$INTERVAL" > "$OUT_DIR/${prefix}_sar.log" &
        SAR_PID=$!
    fi
    if $USE_CGTOP; then
        /usr/bin/systemd-cgtop -b -d "$INTERVAL" > "$OUT_DIR/${prefix}_cgtop.log" &
        CGTOP_PID=$!
    fi
}

stop_telemetry() {
    local pid
    for pid in "${VMSTAT_PID-}" "${PIDSTAT_PID-}" "${IOSTAT_PID-}" "${SAR_PID-}" "${CGTOP_PID-}"; do
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
    REPORT_FILE=""
    if [ "$REPORT_MODE" = "true" ]; then
        REPORT_FILE="$OUT_DIR/${prefix}_report.txt"
        : > "$REPORT_FILE"
    fi

    DOMAIN_START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    DOMAIN_START_LOCAL=$(date +%Y-%m-%dT%H:%M:%S)
    HEAD_EXIT=""
    LOAD_EXIT=""
    HEAD_CMD=""
    HEAD_BUST_CMD=""
    LOAD_CMD=""
    LOAD_BUST_CMD=""
    SAR_CMD=""
    PIDSTAT_CMD=""
    VMSTAT_CMD=""
    IOSTAT_CMD=""
    CGTOP_CMD=""
    TELEMETRY_SCOPE="domain"
    if $USE_VMSTAT; then
        VMSTAT_CMD="vmstat ${INTERVAL}"
    fi
    if $USE_PIDSTAT; then
        PIDSTAT_CMD="pidstat -ru -C apache2 ${INTERVAL}"
    fi
    if $USE_IOSTAT; then
        IOSTAT_CMD="iostat -xz ${INTERVAL}"
    fi
    if $USE_SAR; then
        SAR_CMD="sar -u -r -n DEV -q ${INTERVAL}"
    fi
    if $USE_CGTOP; then
        CGTOP_CMD="/usr/bin/systemd-cgtop -b -d ${INTERVAL}"
    fi
    if $USE_SAR || $USE_PIDSTAT || $USE_VMSTAT || $USE_IOSTAT || $USE_CGTOP; then
        start_telemetry "$prefix"
    fi

    base_url="https://${domain}/"
    bust_url="https://${domain}/?${CACHE_BUST_PARAM}=${RUN_ID}"

    if [ "$HEAD_MODE" = "true" ]; then
        if [ "$CACHE_MODE" = "both" ] || [ "$CACHE_MODE" = "cached" ]; then
            HEAD_CMD="curl -I \"$base_url\""
            set +e
            curl -I "$base_url" > "$OUT_DIR/${prefix}_head.txt"
            head_status=$?
            set -e
            if [ -z "$HEAD_EXIT" ] || [ "$HEAD_EXIT" -eq 0 ] 2>/dev/null; then
                HEAD_EXIT="$head_status"
            fi
            check_expected_file "$OUT_DIR/${prefix}_head.txt" "head headers (cached)"
        fi
        if [ "$CACHE_MODE" = "both" ] || [ "$CACHE_MODE" = "bust" ]; then
            HEAD_BUST_CMD="curl -I \"$bust_url\""
            set +e
            curl -I "$bust_url" > "$OUT_DIR/${prefix}_head_bust.txt"
            head_status=$?
            set -e
            if [ -z "$HEAD_EXIT" ] || [ "$HEAD_EXIT" -eq 0 ] 2>/dev/null; then
                HEAD_EXIT="$head_status"
            fi
            check_expected_file "$OUT_DIR/${prefix}_head_bust.txt" "head headers (bust)"
        fi
    fi

    wrk_cmd_cached=("$WRK_BIN" -t"$THREADS" -c"$CONNECTIONS" -d"$DURATION" -R"$RATE")
    wrk_cmd_bust=("$WRK_BIN" -t"$THREADS" -c"$CONNECTIONS" -d"$DURATION" -R"$RATE")

    if [ "$CACHE_MODE" = "both" ] || [ "$CACHE_MODE" = "cached" ]; then
        LOAD_CMD="${wrk_cmd_cached[*]} \"$base_url\""
        set +e
        "${wrk_cmd_cached[@]}" "$base_url" > "$OUT_DIR/${prefix}_wrk.txt"
        wrk_status=$?
        set -e
        if [ -z "$LOAD_EXIT" ] || [ "$LOAD_EXIT" -eq 0 ] 2>/dev/null; then
            LOAD_EXIT="$wrk_status"
        fi
        check_expected_file "$OUT_DIR/${prefix}_wrk.txt" "wrk output (cached)"
        summarize_wrk "$domain" "cached" "$OUT_DIR/${prefix}_wrk.txt"
        if [ "$REPORT_MODE" = "true" ]; then
            if $USE_PIDSTAT; then
                summarize_pidstat "$domain" "cached" "$OUT_DIR/${prefix}_pidstat.log"
            fi
            if $USE_SAR; then
                summarize_sar "$domain" "cached" "$OUT_DIR/${prefix}_sar.log"
            fi
        fi
    fi
    if [ "$CACHE_MODE" = "both" ] || [ "$CACHE_MODE" = "bust" ]; then
        LOAD_BUST_CMD="${wrk_cmd_bust[*]} \"$bust_url\""
        set +e
        "${wrk_cmd_bust[@]}" "$bust_url" > "$OUT_DIR/${prefix}_wrk_bust.txt"
        wrk_status=$?
        set -e
        if [ -z "$LOAD_EXIT" ] || [ "$LOAD_EXIT" -eq 0 ] 2>/dev/null; then
            LOAD_EXIT="$wrk_status"
        fi
        check_expected_file "$OUT_DIR/${prefix}_wrk_bust.txt" "wrk output (bust)"
        summarize_wrk "$domain" "bust" "$OUT_DIR/${prefix}_wrk_bust.txt"
        if [ "$REPORT_MODE" = "true" ]; then
            if $USE_PIDSTAT; then
                summarize_pidstat "$domain" "bust" "$OUT_DIR/${prefix}_pidstat.log"
            fi
            if $USE_SAR; then
                summarize_sar "$domain" "bust" "$OUT_DIR/${prefix}_sar.log"
            fi
        fi
    fi

    if $USE_SAR || $USE_PIDSTAT || $USE_VMSTAT || $USE_IOSTAT || $USE_CGTOP; then
        stop_telemetry
    fi

    DOMAIN_END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    DOMAIN_END_LOCAL=$(date +%Y-%m-%dT%H:%M:%S)
    {
        echo "HOSTNAME: $HOSTNAME_VAL"
        echo "ORIGIN_IPV4: $ORIGIN_IPV4_VAL"
        echo "RUN_ID: $RUN_ID"
        echo "RUN_DIR: $OUT_DIR"
        echo "KIND: load"
        echo "DOMAIN: $domain"
        echo "MODE: $MODE"
        echo "CACHE_MODE: $CACHE_MODE"
        echo "UTC_START: $DOMAIN_START_UTC"
        echo "UTC_END: $DOMAIN_END_UTC"
        echo "LOCAL_TZ: $LOCAL_TZ"
        echo "LOCAL_OFFSET: $LOCAL_OFFSET"
        echo "LOCAL_START: $DOMAIN_START_LOCAL"
        echo "LOCAL_END: $DOMAIN_END_LOCAL"
        echo "LOG_PAD_SEC: $LOG_PAD_SEC"
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
        echo "LOAD_TOOL: $WRK_BIN"
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
        if $USE_SAR || $USE_PIDSTAT || $USE_VMSTAT || $USE_IOSTAT || $USE_CGTOP; then
            echo "TELEMETRY: $TELEMETRY_LIST"
            echo "TELEMETRY_SCOPE: $TELEMETRY_SCOPE"
            echo "TELEMETRY_INTERVAL_SEC: $INTERVAL"
        fi
        if $USE_SAR; then
            echo "SAR_CMD: $SAR_CMD"
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
    } > "$OUT_DIR/${prefix}_run.param"
done

status_pass "run=ok"
