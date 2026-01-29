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

usage() {
    cat <<'EOF'
slice-logs.sh - Extract log slices for a perf run based on run.param metadata.

Usage:
  slice-logs.sh --run-param PATH [--out-dir DIR] [--pad SEC]

Options:
  --run-param PATH  Path to run.param file (required)
  --out-dir DIR  Output directory for sliced logs (default: run.param directory)
  --pad SEC  Override LOG_PAD_SEC from run.param
  --help  Show this help

Notes:
  - This script does not alter any source logs.
  - Log slices are written with the same prefix as run.param.
  - Apache log selection is best-effort and may warn if a matching file is not found.
  - When a PERF report and Apache access slice exist, this script appends summary
    rows to perf_runs.csv and perf_segments.csv in the output directory.
EOF
}

log_msg() {
    local msg="$1"
    echo "$msg" | tee -a "$SLICE_LOG"
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
                out-dir=*) OUT_DIR="${OPTARG#*=}" ;;
                out-dir)
                    [ -n "${!OPTIND-}" ] || err "--out-dir requires a value"
                    OUT_DIR="${!OPTIND}"; OPTIND=$((OPTIND + 1)) ;;
                pad=*) PAD_OVERRIDE="${OPTARG#*=}" ;;
                pad)
                    [ -n "${!OPTIND-}" ] || err "--pad requires a value"
                    PAD_OVERRIDE="${!OPTIND}"; OPTIND=$((OPTIND + 1)) ;;
                *) err "Unknown option --${OPTARG}" ;;
            esac
            ;;
        *) err "Unknown option -${opt}" ;;
    esac
done

[ -n "$RUN_PARAM" ] || err "--run-param is required"
[ -f "$RUN_PARAM" ] || err "run.param not found: $RUN_PARAM"

OUT_DIR="${OUT_DIR:-$(cd "$(dirname "$RUN_PARAM")" && pwd)}"
mkdir -p "$OUT_DIR"

PREFIX="$(basename "$RUN_PARAM")"
PREFIX="${PREFIX%_run.param}"

SLICE_LOG="$OUT_DIR/${PREFIX}_slice.log"
: > "$SLICE_LOG"

DOMAIN="$(param_var "$RUN_PARAM" "DOMAIN" || true)"
UTC_START="$(param_var "$RUN_PARAM" "UTC_START" || true)"
UTC_END="$(param_var "$RUN_PARAM" "UTC_END" || true)"
LOG_PAD_SEC="$(param_var "$RUN_PARAM" "LOG_PAD_SEC" || true)"

[ -n "$DOMAIN" ] || err "DOMAIN missing in run.param"
[ -n "$UTC_START" ] || err "UTC_START missing in run.param"
[ -n "$UTC_END" ] || err "UTC_END missing in run.param"

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
        sudo python3 - "$src" "$dest" "$PAD_START" "$PAD_END" <<'PYCODE'
import sys
from datetime import datetime

src, dest, start_s, end_s = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
start = datetime.fromisoformat(start_s)
end = datetime.fromisoformat(end_s)

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
        if start <= dt <= end:
            f_out.write(line)
PYCODE
    else
        python3 - "$src" "$dest" "$PAD_START" "$PAD_END" <<'PYCODE'
import sys
from datetime import datetime

src, dest, start_s, end_s = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
start = datetime.fromisoformat(start_s)
end = datetime.fromisoformat(end_s)

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
        if start <= dt <= end:
            f_out.write(line)
PYCODE
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
        sudo python3 - "$src" "$dest" "$PAD_START" "$PAD_END" "$YEAR" <<'PYCODE'
import sys
from datetime import datetime, timezone

src, dest, start_s, end_s, year_s = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
start = datetime.fromisoformat(start_s)
end = datetime.fromisoformat(end_s)
year = int(year_s)

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
        if start <= dt <= end:
            f_out.write(line)
PYCODE
    else
        python3 - "$src" "$dest" "$PAD_START" "$PAD_END" "$YEAR" <<'PYCODE'
import sys
from datetime import datetime, timezone

src, dest, start_s, end_s, year_s = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
start = datetime.fromisoformat(start_s)
end = datetime.fromisoformat(end_s)
year = int(year_s)

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
        if start <= dt <= end:
            f_out.write(line)
PYCODE
    fi
}

domain_nodot="${DOMAIN//./}"
domain_label="${DOMAIN%%.*}"

apache_candidates=(
    "/var/log/apache2/${DOMAIN}_ssl_access.log"
    "/var/log/apache2/${domain_nodot}_ssl_access.log"
    "/var/log/apache2/${domain_label}_ssl_access.log"
)
apache_error_candidates=(
    "/var/log/apache2/${DOMAIN}_ssl_error.log"
    "/var/log/apache2/${domain_nodot}_ssl_error.log"
    "/var/log/apache2/${domain_label}_ssl_error.log"
)
apache_access_candidates=(
    "/var/log/apache2/${DOMAIN}-access.log"
    "/var/log/apache2/${DOMAIN}_access.log"
    "/var/log/apache2/${domain_nodot}_access.log"
    "/var/log/apache2/${domain_label}_access.log"
    "/var/log/apache2/${DOMAIN}-access.log"
)
apache_error_plain_candidates=(
    "/var/log/apache2/${DOMAIN}-error.log"
    "/var/log/apache2/${DOMAIN}_error.log"
    "/var/log/apache2/${domain_nodot}_error.log"
    "/var/log/apache2/${domain_label}_error.log"
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

ssl_access_src="$(pick_first "${apache_candidates[@]}" || true)"
ssl_error_src="$(pick_first "${apache_error_candidates[@]}" || true)"
access_src="$(pick_first "${apache_access_candidates[@]}" || true)"
error_src="$(pick_first "${apache_error_plain_candidates[@]}" || true)"

if [ -n "$ssl_access_src" ]; then
    slice_apache "$ssl_access_src" "$OUT_DIR/${PREFIX}_apache_ssl_access.log"
else
    log_msg "WARN no matching ssl access log for domain"
fi

if [ -n "$ssl_error_src" ]; then
    slice_apache "$ssl_error_src" "$OUT_DIR/${PREFIX}_apache_ssl_error.log"
else
    log_msg "WARN no matching ssl error log for domain"
fi

if [ -n "$access_src" ]; then
    slice_apache "$access_src" "$OUT_DIR/${PREFIX}_apache_access.log"
else
    log_msg "WARN no matching access log for domain"
fi

if [ -n "$error_src" ]; then
    slice_apache "$error_src" "$OUT_DIR/${PREFIX}_apache_error.log"
else
    log_msg "WARN no matching error log for domain"
fi

slice_syslog "/var/log/syslog" "$OUT_DIR/${PREFIX}_syslog.log"
slice_syslog "/var/log/auth.log" "$OUT_DIR/${PREFIX}_auth.log"
slice_syslog "/var/log/kern.log" "$OUT_DIR/${PREFIX}_kern.log"
slice_syslog "/var/log/ufw.log" "$OUT_DIR/${PREFIX}_ufw.log"

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
