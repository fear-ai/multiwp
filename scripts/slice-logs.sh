#!/bin/bash
# slice-logs.sh - Extract log slices for a perf run based on run.param metadata.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/cli.sh"

RUN_PARAM=""
OUT_DIR=""
PAD_OVERRIDE=""
REPORT_MODE="true"
DURATION_RAW=""
DOMAIN_OVERRIDE=""
DURATION_MODE="false"

usage() {
    cat <<'EOF'
slice-logs.sh - Extract log slices for a perf run based on run.param metadata.

Usage:
  slice-logs.sh --run-param PATH [--out-dir DIR] [--pad SEC]
  slice-logs.sh --duration WINDOW --domain NAME [--out-dir DIR] [--pad SEC]

Options:
  --run-param PATH  Path to run.param file (required)
  --duration WINDOW  Slice logs for the last WINDOW (default minutes; suffix: s|m|h|d)
  --domain NAME  Domain to slice (required with --duration)
  --out-dir DIR  Output directory for sliced logs (default: run.param directory)
  --pad SEC  Override LOG_PAD_SEC from run.param
  --report  Write a log summary file (default)
  --no-report  Disable log summary output
  --help  Show this help

Notes:
  - This script does not alter any source logs.
  - Log slices are written with the run.param prefix or a generated prefix in --duration mode.
  - When report output is enabled, the summary log is written to ${prefix}_logs.txt.
  - Apache log selection is best-effort and may warn if a matching file is not found.
  - When using --duration, the slice window is UTC now back WINDOW, plus any pad.
  - When a PERF report and Apache access slice exist, this script appends summary
    rows to perf_runs.csv and perf_segments.csv in the output directory.
EOF
}

log_msg() {
    local msg="$1"
    if [ "$REPORT_MODE" = "true" ]; then
        echo "$msg" | tee -a "$SLICE_LOG"
    else
        echo "$msg"
    fi
}

param_var() {
    local path="$1"
    local key="$2"
    [ -n "$path" ] && [ -n "$key" ] || return 1
    [ -f "$path" ] || return 1
    awk -v k="$key" '
        $0 ~ "^[[:space:]]*"k":[[:space:]]*" {
            sub("^[[:space:]]*"k":[[:space:]]*", "", $0);
            print $0;
            exit
        }' "$path"
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                run-param=*) RUN_PARAM="${OPTARG#*=}" ;;
                run-param)
                    [ -n "${!OPTIND-}" ] || err "--run-param requires a value"
                    RUN_PARAM="${!OPTIND}"; OPTIND=$((OPTIND + 1)) ;;
                duration=*) DURATION_RAW="${OPTARG#*=}" ;;
                duration)
                    [ -n "${!OPTIND-}" ] || err "--duration requires a value"
                    DURATION_RAW="${!OPTIND}"; OPTIND=$((OPTIND + 1)) ;;
                domain=*) DOMAIN_OVERRIDE="${OPTARG#*=}" ;;
                domain)
                    [ -n "${!OPTIND-}" ] || err "--domain requires a value"
                    DOMAIN_OVERRIDE="${!OPTIND}"; OPTIND=$((OPTIND + 1)) ;;
                out-dir=*) OUT_DIR="${OPTARG#*=}" ;;
                out-dir)
                    [ -n "${!OPTIND-}" ] || err "--out-dir requires a value"
                    OUT_DIR="${!OPTIND}"; OPTIND=$((OPTIND + 1)) ;;
                pad=*) PAD_OVERRIDE="${OPTARG#*=}" ;;
                pad)
                    [ -n "${!OPTIND-}" ] || err "--pad requires a value"
                    PAD_OVERRIDE="${!OPTIND}"; OPTIND=$((OPTIND + 1)) ;;
                report) REPORT_MODE="true" ;;
                no-report) REPORT_MODE="false" ;;
                *) err "Unknown option --${OPTARG}" ;;
            esac
            ;;
        *) err "Unknown option -${opt}" ;;
    esac
done

if [ -n "$RUN_PARAM" ] && [ -n "$DURATION_RAW" ]; then
    err "--run-param and --duration cannot be used together"
fi
if [ -z "$RUN_PARAM" ] && [ -z "$DURATION_RAW" ]; then
    err "Use --run-param or --duration/--domain"
fi

if [ -n "$RUN_PARAM" ]; then
    [ -f "$RUN_PARAM" ] || err "run.param not found: $RUN_PARAM"
fi

if [ -n "$RUN_PARAM" ]; then
    OUT_DIR="${OUT_DIR:-$(cd "$(dirname "$RUN_PARAM")" && pwd)}"
else
    RUN_ID="$(date -u +%Y%m%d_%H%M%S)"
    OUT_DIR="${OUT_DIR:-/var/tmp/multiwp/slice_${RUN_ID}}"
fi
mkdir -p "$OUT_DIR"

if [ -n "$RUN_PARAM" ]; then
    PREFIX="$(basename "$RUN_PARAM")"
    PREFIX="${PREFIX%_run.param}"
else
    [ -n "$DOMAIN_OVERRIDE" ] || err "--domain is required with --duration"
    PREFIX="${DOMAIN_OVERRIDE//./_}_${RUN_ID}"
    DURATION_MODE="true"
fi

SLICE_LOG=""
if [ "$REPORT_MODE" = "true" ]; then
    SLICE_LOG="$OUT_DIR/${PREFIX}_logs.txt"
    : > "$SLICE_LOG"
fi

if [ -n "$RUN_PARAM" ]; then
    DOMAIN="$(param_var "$RUN_PARAM" "DOMAIN" || true)"
    UTC_START="$(param_var "$RUN_PARAM" "UTC_START" || true)"
    UTC_END="$(param_var "$RUN_PARAM" "UTC_END" || true)"
    LOG_PAD_SEC="$(param_var "$RUN_PARAM" "LOG_PAD_SEC" || true)"

    [ -n "$DOMAIN" ] || err "DOMAIN missing in run.param"
    [ -n "$UTC_START" ] || err "UTC_START missing in run.param"
    [ -n "$UTC_END" ] || err "UTC_END missing in run.param"
else
    DOMAIN="$DOMAIN_OVERRIDE"
    if ! [[ "$DURATION_RAW" =~ ^[0-9]+[smhdSMHD]?$ ]]; then
        err "--duration must be N, Ns, Nm, Nh, or Nd (default minutes)"
    fi
    duration_value="${DURATION_RAW%[smhdSMHD]}"
    duration_unit="${DURATION_RAW:${#duration_value}:1}"
    if [ -z "$duration_unit" ]; then
        duration_unit="m"
    fi
    case "$duration_unit" in
        s|S) duration_sec="$duration_value" ;;
        m|M) duration_sec=$((duration_value * 60)) ;;
        h|H) duration_sec=$((duration_value * 3600)) ;;
        d|D) duration_sec=$((duration_value * 86400)) ;;
        *) err "--duration must use s, m, h, or d suffix" ;;
    esac
    UTC_END="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    UTC_START=$(python3 - "$UTC_END" "$duration_sec" <<'PYCODE'
import sys
from datetime import datetime, timedelta, timezone

end = datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
duration = int(sys.argv[2])
start = end - timedelta(seconds=duration)
print(start.strftime("%Y-%m-%dT%H:%M:%SZ"))
PYCODE
)
    LOG_PAD_SEC="${LOG_PAD_SEC:-0}"
fi

PAD_SEC="${PAD_OVERRIDE:-$LOG_PAD_SEC}"
PAD_SEC="${PAD_SEC:-0}"

pad_output=$(python3 - "$UTC_START" "$UTC_END" "$PAD_SEC" <<'PYCODE'
import sys
from datetime import datetime, timedelta, timezone

start = datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
end = datetime.strptime(sys.argv[2], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
pad = int(sys.argv[3])

start_p = start - timedelta(seconds=pad)
end_p = end + timedelta(seconds=pad)

print(start_p.isoformat(), end_p.isoformat(), start_p.year)
PYCODE
)
read -r PAD_START PAD_END YEAR <<<"$pad_output"

log_msg "DOMAIN=$DOMAIN"
log_msg "UTC_START=$UTC_START"
log_msg "UTC_END=$UTC_END"
log_msg "PAD_SEC=$PAD_SEC"
log_msg "PAD_START=$PAD_START"
log_msg "PAD_END=$PAD_END"

slice_apache() {
    local src="$1"
    local dest="$2"
    [ -f "$src" ] || { log_msg "WARN missing: $src"; return 0; }

    if [ ! -r "$src" ]; then
        sudo=true
    else
        sudo=false
    fi

    if $sudo; then
        log_start=$(sudo python3 - "$src" "$dest" "$PAD_START" "$PAD_END" <<'PYCODE'
import sys
from datetime import datetime

src, dest, start_s, end_s = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
start = datetime.fromisoformat(start_s)
end = datetime.fromisoformat(end_s)
first_dt = None

def parse_apache(ts):
    return datetime.strptime(ts, "%d/%b/%Y:%H:%M:%S %z")

with open(src, "r", errors="ignore") as f_in, open(dest, "w") as f_out:
    for line in f_in:
        if "[" not in line or "]" not in line:
            continue
        ts = line.split("[", 1)[1].split("]", 1)[0]
        try:
            dt = parse_apache(ts)
        except ValueError:
            continue
        if first_dt is None:
            first_dt = dt
        if start <= dt <= end:
            f_out.write(line)
if first_dt and start < first_dt:
    print(first_dt.isoformat())
PYCODE
)
    else
        log_start=$(python3 - "$src" "$dest" "$PAD_START" "$PAD_END" <<'PYCODE'
import sys
from datetime import datetime

src, dest, start_s, end_s = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
start = datetime.fromisoformat(start_s)
end = datetime.fromisoformat(end_s)
first_dt = None

def parse_apache(ts):
    return datetime.strptime(ts, "%d/%b/%Y:%H:%M:%S %z")

with open(src, "r", errors="ignore") as f_in, open(dest, "w") as f_out:
    for line in f_in:
        if "[" not in line or "]" not in line:
            continue
        ts = line.split("[", 1)[1].split("]", 1)[0]
        try:
            dt = parse_apache(ts)
        except ValueError:
            continue
        if first_dt is None:
            first_dt = dt
        if start <= dt <= end:
            f_out.write(line)
if first_dt and start < first_dt:
    print(first_dt.isoformat())
PYCODE
)
    fi
    if [ "$DURATION_MODE" = "true" ] && [ -n "$log_start" ]; then
        log_msg "WARN log ${src} starts at ${log_start}"
    fi
}

slice_syslog() {
    local src="$1"
    local dest="$2"
    [ -f "$src" ] || { log_msg "WARN missing: $src"; return 0; }

    if [ ! -r "$src" ]; then
        sudo=true
    else
        sudo=false
    fi

    if $sudo; then
        log_start=$(sudo python3 - "$src" "$dest" "$PAD_START" "$PAD_END" "$YEAR" <<'PYCODE'
import sys
from datetime import datetime, timezone

src, dest, start_s, end_s, year_s = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
start = datetime.fromisoformat(start_s)
end = datetime.fromisoformat(end_s)
year = int(year_s)
first_dt = None

def parse_syslog(ts):
    dt = datetime.strptime(f"{year} {ts}", "%Y %b %d %H:%M:%S")
    return dt.replace(tzinfo=timezone.utc)

with open(src, "r", errors="ignore") as f_in, open(dest, "w") as f_out:
    for line in f_in:
        parts = line.split()
        if len(parts) < 3:
            continue
        ts = " ".join(parts[0:3])
        try:
            dt = parse_syslog(ts)
        except ValueError:
            continue
        if first_dt is None:
            first_dt = dt
        if start <= dt <= end:
            f_out.write(line)
if first_dt and start < first_dt:
    print(first_dt.isoformat())
PYCODE
)
    else
        log_start=$(python3 - "$src" "$dest" "$PAD_START" "$PAD_END" "$YEAR" <<'PYCODE'
import sys
from datetime import datetime, timezone

src, dest, start_s, end_s, year_s = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
start = datetime.fromisoformat(start_s)
end = datetime.fromisoformat(end_s)
year = int(year_s)
first_dt = None

def parse_syslog(ts):
    dt = datetime.strptime(f"{year} {ts}", "%Y %b %d %H:%M:%S")
    return dt.replace(tzinfo=timezone.utc)

with open(src, "r", errors="ignore") as f_in, open(dest, "w") as f_out:
    for line in f_in:
        parts = line.split()
        if len(parts) < 3:
            continue
        ts = " ".join(parts[0:3])
        try:
            dt = parse_syslog(ts)
        except ValueError:
            continue
        if first_dt is None:
            first_dt = dt
        if start <= dt <= end:
            f_out.write(line)
if first_dt and start < first_dt:
    print(first_dt.isoformat())
PYCODE
)
    fi
    if [ "$DURATION_MODE" = "true" ] && [ -n "$log_start" ]; then
        log_msg "WARN log ${src} starts at ${log_start}"
    fi
}

domain_nodot="${DOMAIN//./}"
domain_label="${DOMAIN%%.*}"

LOG_IDS=(
    apache_ssl_access
    apache_ssl_error
    apache_admin_access
    apache_access
    apache_error
    syslog
    auth
    kern
    ufw
)
declare -A LOG_TYPE=(
    [apache_ssl_access]=apache
    [apache_ssl_error]=apache
    [apache_admin_access]=apache
    [apache_access]=apache
    [apache_error]=apache
    [syslog]=syslog
    [auth]=syslog
    [kern]=syslog
    [ufw]=syslog
)
declare -A LOG_DEST=(
    [apache_ssl_access]="${PREFIX}_apache_ssl_access.log"
    [apache_ssl_error]="${PREFIX}_apache_ssl_error.log"
    [apache_admin_access]="${PREFIX}_apache_admin_access.log"
    [apache_access]="${PREFIX}_apache_access.log"
    [apache_error]="${PREFIX}_apache_error.log"
    [syslog]="${PREFIX}_syslog.log"
    [auth]="${PREFIX}_auth.log"
    [kern]="${PREFIX}_kern.log"
    [ufw]="${PREFIX}_ufw.log"
)
declare -A LOG_SOURCES=(
    [apache_ssl_access]="/var/log/apache2/${DOMAIN}_ssl_access.log|/var/log/apache2/${domain_nodot}_ssl_access.log|/var/log/apache2/${domain_label}_ssl_access.log"
    [apache_ssl_error]="/var/log/apache2/${DOMAIN}_ssl_error.log|/var/log/apache2/${domain_nodot}_ssl_error.log|/var/log/apache2/${domain_label}_ssl_error.log"
    [apache_admin_access]="/var/log/apache2/${DOMAIN}_admin_access.log|/var/log/apache2/${domain_nodot}_admin_access.log|/var/log/apache2/${domain_label}_admin_access.log"
    [apache_access]="/var/log/apache2/${DOMAIN}-access.log|/var/log/apache2/${DOMAIN}_access.log|/var/log/apache2/${domain_nodot}_access.log|/var/log/apache2/${domain_label}_access.log"
    [apache_error]="/var/log/apache2/${DOMAIN}-error.log|/var/log/apache2/${DOMAIN}_error.log|/var/log/apache2/${domain_nodot}_error.log|/var/log/apache2/${domain_label}_error.log"
    [syslog]="/var/log/syslog"
    [auth]="/var/log/auth.log"
    [kern]="/var/log/kern.log"
    [ufw]="/var/log/ufw.log"
)
declare -A LOG_OPTIONAL=(
    [apache_admin_access]=true
)

pick_first() {
    local -a list=("$@")
    for f in "${list[@]}"; do
        if [ -f "$f" ]; then
            echo "$f"
            return 0
        fi
    done
    return 1
}

resolve_log_source() {
    local log_id="$1"
    local raw="${LOG_SOURCES[$log_id]-}"
    [ -n "$raw" ] || return 1
    local -a list=()
    IFS='|' read -r -a list <<<"$raw"
    pick_first "${list[@]}"
}

slice_registered_log() {
    local log_id="$1"
    local src
    src="$(resolve_log_source "$log_id" || true)"
    if [ -z "$src" ]; then
        if [ "${LOG_OPTIONAL[$log_id]-}" = "true" ]; then
            return 0
        fi
        log_msg "WARN no matching ${log_id} log"
        return 0
    fi
    local dest="$OUT_DIR/${LOG_DEST[$log_id]}"
    case "${LOG_TYPE[$log_id]-}" in
        apache) slice_apache "$src" "$dest" ;;
        syslog) slice_syslog "$src" "$dest" ;;
        *) log_msg "WARN unknown log type for ${log_id}" ;;
    esac
}

for log_id in "${LOG_IDS[@]}"; do
    slice_registered_log "$log_id"
done

analyze_admin_log() {
    local admin_log="$OUT_DIR/${LOG_DEST[apache_admin_access]}"
    if [ ! -f "$admin_log" ]; then
        log_msg "INFO admin access log missing; skip admin timing"
        return 0
    fi
    local summary
    summary=$(python3 - "$admin_log" <<'PYCODE'
import sys

path = sys.argv[1]
threshold_us = 1_000_000
total = 0
slow = 0
max_us = 0
max_path = ""
max_status = ""

with open(path, "r", errors="ignore") as f:
    for line in f:
        if not line.strip():
            continue
        parts = line.rsplit(" ", 1)
        if len(parts) != 2:
            continue
        try:
            us = int(parts[1])
        except ValueError:
            continue
        total += 1
        if us >= threshold_us:
            slow += 1
        if us > max_us:
            max_us = us
            req = ""
            status = ""
            chunks = line.split('"')
            if len(chunks) > 1:
                req = chunks[1]
            if len(chunks) > 2:
                status_part = chunks[2].strip().split()
                status = status_part[0] if status_part else ""
            req_parts = req.split()
            max_path = req_parts[1] if len(req_parts) >= 2 else ""
            max_status = status

max_ms = int(round(max_us / 1000.0)) if max_us else 0
print(f"ADMIN_LOG={path}")
print("ADMIN_SLOW_THRESHOLD_MS=1000")
print(f"ADMIN_TOTAL={total}")
print(f"ADMIN_SLOW_1S={slow}")
print(f"ADMIN_MAX_MS={max_ms}")
if max_path:
    print(f"ADMIN_MAX_PATH={max_path}")
if max_status:
    print(f"ADMIN_MAX_STATUS={max_status}")
PYCODE
)
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        log_msg "$line"
    done <<<"$summary"
}

analyze_admin_log

generate_csv() {
    local report="$OUT_DIR/${PREFIX}_report.txt"
    local apache="$OUT_DIR/${PREFIX}_apache_ssl_access.log"
    local apache_alt="$OUT_DIR/${PREFIX}_apache_access.log"

    if [ ! -f "$report" ]; then
        log_msg "WARN no report file; skip perf CSV output"
        return 0
    fi

    if [ -f "$apache" ]; then
        :
    elif [ -f "$apache_alt" ]; then
        apache="$apache_alt"
    else
        apache=""
    fi

    python3 - "$RUN_PARAM" "$report" "$apache" "$OUT_DIR" <<'PYCODE'
import csv
import os
import re
import sys
from datetime import datetime

run_param, report_path, apache_path, out_dir = sys.argv[1:5]

def read_params(path):
    params = {}
    with open(path, "r", errors="ignore") as f:
        for line in f:
            if ":" not in line:
                continue
            key, val = line.split(":", 1)
            params[key.strip()] = val.strip()
    return params

params = read_params(run_param)

def parse_report(path):
    metrics = {}
    cache = None
    with open(path, "r", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith("== "):
                cache = None
                continue
            if "=" not in line:
                continue
            key, val = line.split("=", 1)
            key = key.strip()
            val = val.strip()
            if key == "CACHE":
                cache = val
                continue
            if cache:
                metrics[f"{cache}_{key.lower()}"] = val
    return metrics

metrics = parse_report(report_path)

def extract_cache_param(params):
    bust_cmd = params.get("LOAD_BUST_CMD", "")
    match = re.search(r"\?([^=]+)=", bust_cmd)
    if match:
        return match.group(1)
    return "cache_bust"

cache_param = extract_cache_param(params)

def parse_apache_line(line):
    if "[" not in line or "]" not in line:
        return None
    ts = line.split("[", 1)[1].split("]", 1)[0]
    try:
        dt = datetime.strptime(ts, "%d/%b/%Y:%H:%M:%S %z")
    except ValueError:
        return None
    parts = line.split('"')
    if len(parts) < 3:
        return None
    req = parts[1]
    status_part = parts[2].strip().split()
    status = status_part[0] if status_part else ""
    path = ""
    req_parts = req.split()
    if len(req_parts) >= 2:
        path = req_parts[1]
    return dt, path, status

def tally_requests(apache_path, cache_param):
    totals = {
        "total": 0,
        "total_503": 0,
        "cached_total": 0,
        "cached_503": 0,
        "bust_total": 0,
        "bust_503": 0,
    }
    per_second = {}
    if not apache_path or not os.path.isfile(apache_path):
        return totals, per_second
    with open(apache_path, "r", errors="ignore") as f:
        for line in f:
            parsed = parse_apache_line(line)
            if not parsed:
                continue
            dt, path, status = parsed
            sec = dt.replace(microsecond=0)
            bucket = per_second.setdefault(sec, {"total": 0, "s503": 0, "s200": 0})
            bucket["total"] += 1
            totals["total"] += 1
            if status == "503":
                bucket["s503"] += 1
                totals["total_503"] += 1
            elif status == "200":
                bucket["s200"] += 1
            is_bust = cache_param in path if path else False
            if is_bust:
                totals["bust_total"] += 1
                if status == "503":
                    totals["bust_503"] += 1
            else:
                totals["cached_total"] += 1
                if status == "503":
                    totals["cached_503"] += 1
    return totals, per_second

totals, per_second = tally_requests(apache_path, cache_param)

def build_segments(per_second):
    segments = []
    items = sorted(per_second.items(), key=lambda x: x[0])
    current = None
    for ts, counts in items:
        if counts["s503"] and counts["s200"]:
            label = "mix"
        elif counts["s503"] and not counts["s200"]:
            label = "503"
        elif counts["s200"] and not counts["s503"]:
            label = "200"
        else:
            label = "other"
        if current and current["label"] == label and ts == current["end"] + timedelta(seconds=1):
            current["end"] = ts
            current["total"] += counts["total"]
            current["s200"] += counts["s200"]
            current["s503"] += counts["s503"]
        else:
            if current:
                segments.append(current)
            current = {
                "label": label,
                "start": ts,
                "end": ts,
                "total": counts["total"],
                "s200": counts["s200"],
                "s503": counts["s503"],
            }
    if current:
        segments.append(current)
    return segments

from datetime import timedelta
segments = build_segments(per_second)

def iso(dt):
    return dt.isoformat()

first_503_ts = ""
first_503_label = ""
first_all_503_ts = ""
for seg in segments:
    if seg["s503"] > 0 and not first_503_ts:
        first_503_ts = iso(seg["start"])
        first_503_label = seg["label"]
    if seg["label"] == "503" and not first_all_503_ts:
        first_all_503_ts = iso(seg["start"])

def lower_param(key):
    return params.get(key, "")

row = {
    "run_id": lower_param("RUN_ID"),
    "domain": lower_param("DOMAIN"),
    "rate": lower_param("RATE"),
    "duration": lower_param("DURATION"),
    "threads": lower_param("THREADS"),
    "connections": lower_param("CONNECTIONS"),
    "mode": lower_param("MODE"),
    "cache_mode": lower_param("CACHE_MODE"),
    "run_dir": lower_param("RUN_DIR"),
    "bust_503": totals["bust_503"],
    "bust_total": totals["bust_total"],
    "cached_503": totals["cached_503"],
    "cached_total": totals["cached_total"],
    "total_503": totals["total_503"],
    "total_requests": totals["total"],
    "first_503_label": first_503_label,
    "first_503_ts": first_503_ts,
    "first_all_503_ts": first_all_503_ts,
    "hostname": lower_param("HOSTNAME"),
    "kind": lower_param("KIND"),
    "load_bust_cmd": lower_param("LOAD_BUST_CMD"),
    "load_cmd": lower_param("LOAD_CMD"),
    "load_exit": lower_param("LOAD_EXIT"),
    "load_tool": lower_param("LOAD_TOOL"),
    "local_end": lower_param("LOCAL_END"),
    "local_offset": lower_param("LOCAL_OFFSET"),
    "local_start": lower_param("LOCAL_START"),
    "local_tz": lower_param("LOCAL_TZ"),
    "log_pad_sec": lower_param("LOG_PAD_SEC"),
    "origin_ipv4": lower_param("ORIGIN_IPV4"),
    "pidstat_cmd": lower_param("PIDSTAT_CMD"),
    "sar_cmd": lower_param("SAR_CMD"),
    "script_exit": lower_param("SCRIPT_EXIT"),
    "telemetry": lower_param("TELEMETRY"),
    "telemetry_interval_sec": lower_param("TELEMETRY_INTERVAL_SEC"),
    "telemetry_scope": lower_param("TELEMETRY_SCOPE"),
    "utc_end": lower_param("UTC_END"),
    "utc_start": lower_param("UTC_START"),
    "vmstat_cmd": lower_param("VMSTAT_CMD"),
    "iostat_cmd": lower_param("IOSTAT_CMD"),
    "cgtop_cmd": lower_param("CGTOP_CMD"),
}

for key, val in metrics.items():
    row[key] = val

run_header = [
    "run_id","domain","rate","duration","threads","connections","mode","cache_mode","run_dir",
    "bust_503","bust_apache_cpu_samples","bust_apache_cpu_sum_avg","bust_apache_cpu_sum_bin5_avg",
    "bust_apache_cpu_sum_max","bust_apache_cpu_sum_trend","bust_cpu_busy_cores_max",
    "bust_cpu_iowait_pct_max","bust_cpu_steal_pct_max","bust_cpu_system_pct_max",
    "bust_cpu_total_bin5_avg","bust_cpu_total_pct_max","bust_cpu_total_trend","bust_cpu_user_pct_max",
    "bust_latency_avg","bust_latency_max","bust_load_1_avg","bust_load_1_max","bust_mem_avail_mb_avg",
    "bust_mem_avail_mb_min","bust_mem_used_pct_avg","bust_mem_used_pct_max","bust_not_200_pct",
    "bust_req_per_sec","bust_total","cached_503","cached_apache_cpu_samples","cached_apache_cpu_sum_avg",
    "cached_apache_cpu_sum_bin5_avg","cached_apache_cpu_sum_max","cached_apache_cpu_sum_trend",
    "cached_cpu_busy_cores_max","cached_cpu_iowait_pct_max","cached_cpu_steal_pct_max",
    "cached_cpu_system_pct_max","cached_cpu_total_bin5_avg","cached_cpu_total_pct_max",
    "cached_cpu_total_trend","cached_cpu_user_pct_max","cached_latency_avg","cached_latency_max",
    "cached_load_1_avg","cached_load_1_max","cached_mem_avail_mb_avg","cached_mem_avail_mb_min",
    "cached_mem_used_pct_avg","cached_mem_used_pct_max","cached_not_200_pct","cached_req_per_sec",
    "cached_total","cgtop_cmd","first_503_label","first_503_ts","first_all_503_ts","hostname",
    "iostat_cmd","kind","load_bust_cmd","load_cmd","load_exit","load_tool","local_end","local_offset",
    "local_start","local_tz","log_pad_sec","origin_ipv4","pidstat_cmd","sar_cmd","script_exit",
    "telemetry","telemetry_interval_sec","telemetry_scope","total_503","total_requests","utc_end",
    "utc_start","vmstat_cmd",
]

def write_csv(path, header, row):
    exists = os.path.isfile(path)
    with open(path, "a", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=header)
        if not exists:
            writer.writeheader()
        writer.writerow({k: row.get(k, "") for k in header})

run_csv = os.path.join(out_dir, "perf_runs.csv")
write_csv(run_csv, run_header, row)

seg_csv = os.path.join(out_dir, "perf_segments.csv")
seg_header = [
    "run_id","domain","rate","segment_index","segment_label","start_ts","end_ts",
    "duration_sec","segment_200","segment_503","segment_total",
]

seg_exists = os.path.isfile(seg_csv)
with open(seg_csv, "a", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=seg_header)
    if not seg_exists:
        writer.writeheader()
    for idx, seg in enumerate(segments):
        duration = int((seg["end"] - seg["start"]).total_seconds()) + 1
        writer.writerow({
            "run_id": row["run_id"],
            "domain": row["domain"],
            "rate": row["rate"],
            "segment_index": idx,
            "segment_label": seg["label"],
            "start_ts": iso(seg["start"]),
            "end_ts": iso(seg["end"]),
            "duration_sec": duration,
            "segment_200": seg["s200"],
            "segment_503": seg["s503"],
            "segment_total": seg["total"],
        })
PYCODE
}

generate_csv

log_msg "DONE slice-logs for $DOMAIN"
