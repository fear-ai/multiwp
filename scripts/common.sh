#!/bin/bash
set -euo pipefail

# These scripts use namerefs (local -n), declare -gA, and expansion of possibly
# empty arrays under set -u. Those need bash 4.3+, 4.2+ and 4.4+ respectively.
# Fail with a clear message rather than an obscure syntax error on macOS's
# bash 3.2 or RHEL 7's 4.2.
if [ -z "${BASH_VERSINFO:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ] ||
   { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; }; then
    echo "ERROR: bash 4.4 or newer is required (found ${BASH_VERSION:-unknown})" >&2
    exit 1
fi

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$ROOT_DIR/scripts}"

COMMON_LOADED=1

SSL_DIR="${SSL_DIR:-/etc/ssl/cloudflare-origin}"
SSL_CERT_DIR="${SSL_CERT_DIR:-$SSL_DIR/certs}"
SSL_KEY_DIR="${SSL_KEY_DIR:-$SSL_DIR/keys}"
APACHE_DIR="${APACHE_DIR:-/etc/apache2/sites-available}"
WORDPRESS_ROOT="${WORDPRESS_ROOT:-/var/www/html/wordpress}"
TEMPLATE_DIR="${TEMPLATE_DIR:-$ROOT_DIR/templates}"

log() { echo "[$(date +%H:%M:%S)] $*"; }
err() { echo "[$(date +%H:%M:%S)] ERROR: $*" >&2; status_error "$*"; exit 1; }
warn() { echo "[$(date +%H:%M:%S)] Warning: $*" >&2; }
fail() { echo "[$(date +%H:%M:%S)] FAIL: $*" >&2; status_error "$*"; }

section() {
    local section="$1"
    local topic="$2"
    echo "== ${section}:${topic}"
}

kv() {
    local key="$1"
    local value="${2-}"
    echo "${key}=${value}"
}

status_pass() { echo "PASS $*"; }
status_info() { echo "INFO $*"; }
status_error() { echo "ERROR $*"; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || err "Missing command: $1"; }
require_cmds() { for cmd in "$@"; do require_cmd "$cmd"; done; }

# priv() is a thin wrapper for running commands with sudo.
# Set SUDO_BIN to an empty string to disable sudo while keeping the call pattern.
SUDO_BIN="${SUDO_BIN-sudo}"
#SUDO_BIN=""
priv() {
    if [ -n "$SUDO_BIN" ]; then
        $SUDO_BIN "$@"
        return
    fi
    if [ "${1:-}" = "-u" ]; then
        shift 2
    fi
    "$@"
}

tolower() { echo "$1" | tr '[:upper:]' '[:lower:]'; }
safe_name() { echo "$1" | sed 's/[.-]//g'; }
trim_spaces() {
    local val="${1-}"
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    echo "$val"
}
normalize_site_type() {
    local raw="${1-}"
    raw=$(trim_spaces "$raw")
    raw=$(tolower "$raw")
    if [ -z "$raw" ]; then
        echo "none"
        return 0
    fi
    echo "$raw"
}
site_type_is_skip() {
    local site_type
    site_type=$(normalize_site_type "$1")
    case "$site_type" in
        none|ignore|worker) return 0 ;;
    esac
    return 1
}
parse_comma_list() {
    local raw="${1-}"
    local -n out="$2"
    local label="${3:-list}"
    out=()
    # Must be local and oddly named: an undeclared `parts` here collides with a
    # caller that passes an array literally named `parts` (check-cf.sh -s), in
    # which case the nameref and this array are the same variable and every
    # value is appended twice.
    local -a __pcl_parts=()
    IFS=',' read -r -a __pcl_parts <<<"$raw"
    local ok=true
    local part trimmed
    for part in "${__pcl_parts[@]}"; do
        trimmed="${part#"${part%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        if [ -z "$trimmed" ]; then
            fail "${label} contains an empty value"
            ok=false
            continue
        fi
        out+=("$trimmed")
    done
    $ok || return 1
    return 0
}
parse_bool() {
    local raw="${1:-}"
    local val
    val=$(printf "%s" "$raw" | tr '[:upper:]' '[:lower:]' | xargs)
    case "$val" in
        true|yes|y) echo "true" ;;
        false|no|n) echo "false" ;;
        *) return 1 ;;
    esac
}

# Resolve the inventory file. Priority:
#   1. DOMAINS_FILE (explicit, from --domains-file or the environment)
#   2. the single domains-*.csv that is non-empty, when exactly one exists
#   3. $ROOT_DIR/domains.csv (legacy default; superseded, see Record.md)
#
# Rule 2 exists because the inventory is split one file per Cloudflare account
# and each domains-*.csv holds exactly one account_id. Falling back to the
# legacy combined file silently selects stale data, so when the split files are
# unambiguous we prefer them.
# Operator settings: non-public but not secrets — account names, contact
# addresses, the origin address, inventory and auth paths. These must not be
# committed, so they live in a config file outside the repository.
#
# Precedence: environment > config file > built-in default. An already-set
# environment variable always wins, so --option and one-off overrides work.
#
# Path: $MULTIWP_CONF, else ~/.config/multiwp/site.conf (XDG_CONFIG_HOME aware).
# Search order: MULTIWP_CONF, then a repo-local .config/multiwp/site.conf (so a
# checkout can carry its own settings), then the per-user XDG location. The
# repo-local path is gitignored; it must never be committed.
if [ -z "${MULTIWP_CONF:-}" ]; then
    if [ -f "$ROOT_DIR/.config/multiwp/site.conf" ]; then
        MULTIWP_CONF="$ROOT_DIR/.config/multiwp/site.conf"
    else
        MULTIWP_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/multiwp/site.conf"
    fi
fi

# shellcheck disable=SC2120  # optional path argument, used by tests
load_operator_conf() {
    local path="${1:-$MULTIWP_CONF}"
    [ -f "$path" ] || return 0
    local mode
    mode=$(stat -c '%a' "$path" 2>/dev/null) || return 0
    case "$mode" in
        600|400) ;;
        *) warn "operator config $path is mode ${mode}; expected 600" ;;
    esac
    local key
    for key in WP_ADMIN_EMAIL ORIGIN_IP INVENTORY_DIR AUTH_DIR; do
        # Environment wins; only fill what is unset or empty.
        [ -n "${!key:-}" ] && continue
        local val
        val=$(kv_file_var "$path" "$key") || true
        [ -n "$val" ] && printf -v "$key" '%s' "$val" && export "${key?}"
    done
    return 0
}

domains_csv_path() {
    if [ -n "${DOMAINS_FILE:-}" ]; then
        echo "$DOMAINS_FILE"
        return 0
    fi
    local -a candidates=()
    local f
    for f in "$ROOT_DIR"/domains-*.csv; do
        [ -f "$f" ] && [ -s "$f" ] && candidates+=("$f")
    done
    if [ "${#candidates[@]}" -eq 1 ]; then
        echo "${candidates[0]}"
        return 0
    fi
    echo "$ROOT_DIR/domains.csv"
}

# Report which inventory an account's auth file maps to, by matching
# account_id. Returns 1 when the mapping is not unique.
domains_csv_for_auth() {
    local auth_file="$1"
    [ -f "$auth_file" ] || return 1
    local acct
    acct=$(kv_file_var "$auth_file" "CF_ACCOUNT_ID")
    [ -n "$acct" ] || return 1
    require_cmd python3
    local f match=""
    for f in "$ROOT_DIR"/domains-*.csv; do
        [ -f "$f" ] && [ -s "$f" ] || continue
        if ACCT="$acct" python3 - "$f" <<'EOF'
import csv, os, sys
acct = os.environ["ACCT"].strip()
with open(sys.argv[1], newline="") as fh:
    for row in csv.DictReader(fh):
        if (row.get("account_id") or "").strip() == acct:
            sys.exit(0)
sys.exit(1)
EOF
        then
            [ -z "$match" ] || return 1   # ambiguous: more than one file matches
            match="$f"
        fi
    done
    [ -n "$match" ] || return 1
    echo "$match"
}

csv_get_domain_fields() {
    local domain="$1"
    shift || true
    [ -n "$domain" ] || err "Domain required for CSV lookup"
    [ "$#" -gt 0 ] || err "At least one CSV field is required"

    local csv
    csv=$(domains_csv_path)
    [ -f "$csv" ] || return 1
    require_cmd python3

    python3 - "$csv" "$domain" "$@" <<'EOF'
import csv
import sys

path = sys.argv[1]
needle = sys.argv[2].strip().lower()
fields = sys.argv[3:]

with open(path, newline="") as fh:
    reader = csv.DictReader(fh)
    for row in reader:
        if (row.get("domain") or "").strip().lower() == needle:
            values = [(row.get(field) or "").strip() for field in fields]
            print("\t".join(values))
            sys.exit(0)

sys.exit(1)
EOF
}

csv_get_domain_field() {
    local domain="$1"
    local field="$2"
    [ -n "$field" ] || err "CSV field required"
    csv_get_domain_fields "$domain" "$field"
}

DATASTORE_BACKUP_DONE="${DATASTORE_BACKUP_DONE:-false}"
DATASTORE_BACKUP_PATH="${DATASTORE_BACKUP_PATH:-}"

record_backup_datastore() {
    local path="$1"
    [ -n "$path" ] || err "Datastore path required"
    [ -f "$path" ] || err "Datastore not found: $path"
    if [ "$DATASTORE_BACKUP_DONE" = true ]; then
        DATASTORE_BACKUP_PATH="$path"
        export DATASTORE_BACKUP_PATH
        echo "$path"
        return 0
    fi

    local dir ts backup
    dir=$(dirname "$path")
    ts="${DATASTORE_DATE-}"
    if [ -n "$ts" ]; then
        if [[ "$ts" == *"/"* || "$ts" == *".."* ]]; then
            err "Invalid --date: path separators are not allowed"
        fi
        if ! [[ "$ts" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
            err "Invalid --date: expected YYYYmmdd_HHMMSS"
        fi
    else
        ts=$(date +%Y%m%d_%H%M%S)
    fi
    backup="$dir/datastore_${ts}.csv"
    # Copy, never move: the live datastore must exist at all times. If the
    # rewrite below fails, the inventory is still in place. -p preserves the
    # 0600 mode so backups are not world-readable.
    cp -p "$path" "$backup"
    DATASTORE_BACKUP_DONE=true
    export DATASTORE_BACKUP_DONE
    DATASTORE_BACKUP_PATH="$backup"
    export DATASTORE_BACKUP_PATH
    log "Backed up datastore to $backup" >&2
    echo "$backup"
}

csv_put_fields() {
    local dest_path="$1"
    local domain="$2"
    local allow_downgrade="${3:-false}"
    shift 3
    local updates=("$@")

    if [ "${RECORD_UPDATES:-true}" != true ]; then
        return 0
    fi
    [ -n "$dest_path" ] || err "Datastore path required"
    [ -n "$domain" ] || err "Domain required for datastore update"
    require_cmd python3

    # Serialize concurrent updates; without this two runs interleave and one
    # set of updates is lost. The lock is released when the shell exits or the
    # fd is closed.
    local lock_file="${dest_path}.lock"
    local csv_lock_fd
    if command -v flock >/dev/null 2>&1; then
        exec {csv_lock_fd}>>"$lock_file" || err "Cannot open datastore lock: $lock_file"
        flock -w 30 "$csv_lock_fd" || err "Timed out waiting for datastore lock: $lock_file"
    fi

    record_backup_datastore "$dest_path"
    local source_path="${DATASTORE_BACKUP_PATH:-$dest_path}"

    python3 - "$source_path" "$dest_path" "$domain" "$allow_downgrade" "${updates[@]}" <<'EOF'
import csv
import sys

source_path = sys.argv[1]
dest_path = sys.argv[2]
domain = (sys.argv[3] or "").strip().lower()
allow_downgrade = (sys.argv[4] or "").strip().lower() == "true"
updates = {}
for arg in sys.argv[5:]:
    if "=" not in arg:
        continue
    key, val = arg.split("=", 1)
    updates[key] = val

status_orders = {
    "status_cf": {"": 0, "none": 0, "added": 1, "redirect": 2, "https": 2, "worker": 3, "ignore": 3},
    "status_origin": {"": 0, "none": 0, "apache": 1},
    "status_wp": {"": 0, "none": 0, "install": 1, "config": 2, "load": 3},
}

def normalize(val):
    return (val or "").strip().lower()

def apply_status(existing, desired, field):
    desired = (desired or "").strip()
    if not desired:
        return existing, False
    if allow_downgrade:
        return desired, normalize(existing) != normalize(desired)
    existing_norm = normalize(existing)
    desired_norm = normalize(desired)
    order = status_orders.get(field, {})
    existing_rank = order.get(existing_norm)
    desired_rank = order.get(desired_norm)
    if existing_norm in ("worker", "ignore") and field == "status_cf" and existing_norm != desired_norm:
        return existing, False
    if existing_rank is None or desired_rank is None:
        if existing_norm in ("", "none"):
            return desired, True
        return existing, False
    if desired_rank < existing_rank:
        return existing, False
    if desired_rank == existing_rank and desired_norm != existing_norm:
        return existing, False
    if desired_norm != existing_norm:
        return desired, True
    return existing, False

with open(source_path, newline="") as fh:
    reader = csv.DictReader(fh)
    fieldnames = reader.fieldnames or []
    rows = list(reader)

if not fieldnames:
    raise SystemExit("datastore CSV is missing a header row")

found = False
changed = False
for row in rows:
    if normalize(row.get("domain")) == domain:
        found = True
        for key, val in updates.items():
            if key in ("status_cf", "status_origin", "status_wp"):
                new_val, updated = apply_status(row.get(key, ""), val, key)
                if updated:
                    row[key] = new_val
                    changed = True
            else:
                if val:
                    if row.get(key, "") != val:
                        row[key] = val
                        changed = True
        break

if not found:
    new_row = {k: "" for k in fieldnames}
    new_row["domain"] = domain
    for key, val in updates.items():
        if key in ("status_cf", "status_origin", "status_wp"):
            new_row[key] = normalize(val)
        elif key in new_row and val:
            new_row[key] = val
    rows.append(new_row)
    changed = True

if not changed and source_path == dest_path:
    sys.exit(0)

# Write to a temp file in the same directory, then rename over the target.
# rename() is atomic, so a reader never sees a partial datastore and a crash
# mid-write cannot destroy the original.
import os
import tempfile

dest_dir = os.path.dirname(os.path.abspath(dest_path)) or "."
try:
    mode = os.stat(dest_path).st_mode & 0o777
except OSError:
    mode = 0o600

fd, tmp_path = tempfile.mkstemp(dir=dest_dir, prefix=".datastore.", suffix=".tmp")
try:
    with os.fdopen(fd, "w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
        fh.flush()
        os.fsync(fh.fileno())
    # Preserve the inventory's restrictive mode; a fresh temp file would
    # otherwise land at the process umask (typically 0644).
    os.chmod(tmp_path, mode)
    os.replace(tmp_path, dest_path)
except BaseException:
    try:
        os.unlink(tmp_path)
    except OSError:
        pass
    raise
EOF
    local rc=$?
    if [ -n "${csv_lock_fd:-}" ]; then
        exec {csv_lock_fd}>&-
    fi
    return $rc
}


kv_file_var() {
    local path="$1"
    local key="$2"
    [ -n "$path" ] && [ -n "$key" ] || return 1
    [ -f "$path" ] || return 1
    awk -F= -v k="$key" '
        $0 ~ "^[[:space:]]*"k"[[:space:]]*=" {
            sub("^[[:space:]]*"k"[[:space:]]*=", "", $0);
            gsub(/["'\''"]/, "", $0);
            print $0;
            exit
        }' "$path"
}

kv_file_values() {
    local path="$1"
    local key="$2"
    [ -n "$path" ] && [ -n "$key" ] || return 1
    [ -f "$path" ] || return 1
    awk -F= -v k="$key" '
        $0 ~ "^[[:space:]]*"k"[[:space:]]*=" {
            sub("^[[:space:]]*"k"[[:space:]]*=", "", $0);
            gsub(/["'\''"]/, "", $0);
            if ($0 != "") {
                print $0;
            }
        }' "$path"
}

auth_file_var() {
    kv_file_var "$@"
}

load_dns_redirects() {
    DNS_REDIRECT_LIST=()
    declare -gA DNS_REDIRECT_TARGETS=()
    local csv="${DOMAINS_FILE:-$ROOT_DIR/domains.csv}"
    [ -f "$csv" ] || return 0
    local redirect_list=""
    if command -v python3 >/dev/null 2>&1; then
        redirect_list=$(python3 - "$csv" <<'EOF'
import csv
import sys

path = sys.argv[1]
with open(path, newline="") as fh:
    reader = csv.DictReader(fh)
    for row in reader:
        site_type = (row.get("site_type") or "").strip().lower()
        if site_type.startswith("redirect"):
            domain = (row.get("domain") or "").strip()
            target = (row.get("redirect_url") or "").strip()
            if domain:
                print(f"{domain}\t{target}")
EOF
)
    else
        warn "python3 not available; parsing redirects from $csv with awk"
        redirect_list=$(awk -F, 'NR==1{for(i=1;i<=NF;i++){if($i=="domain")d=i;if($i=="site_type")s=i;if($i=="redirect_url")r=i}next} {t=tolower($s); if(t ~ /^redirect/) print $d "\t" $r}' "$csv")
    fi
    if [ -n "$redirect_list" ]; then
        local domain target normalized
        while IFS=$'\t' read -r domain target; do
            [ -n "$domain" ] || continue
            DNS_REDIRECT_LIST+=("$domain")
            target="${target#"${target%%[![:space:]]*}"}"
            target="${target%"${target##*[![:space:]]}"}"
            if [ -n "$target" ]; then
                normalized=$(normalize_domain "$domain")
                DNS_REDIRECT_TARGETS["$normalized"]="$target"
            fi
        done <<<"$redirect_list"
        finalize_domains DNS_REDIRECT_LIST || return 1
    fi
}

# TODO: Consider per-domain WordPress URL expectations (siteurl/home) when needed.
# Common cases: WordPress core installed in a subdirectory (siteurl has /wp),
# or non-standard ports (siteurl/home include :8443).

is_redirect_domain() {
    local domain
    domain=$(normalize_domain "$1")
    local item
    for item in "${DNS_REDIRECT_LIST[@]:-}"; do
        if [ "$item" = "$domain" ]; then
            return 0
        fi
    done
    return 1
}

redirect_target() {
    local domain
    domain=$(normalize_domain "$1")
    echo "${DNS_REDIRECT_TARGETS[$domain]-}"
}

wp_template_list() {
    local kind="$1"
    local site_type="$2"
    local stage="${3-}"
    local template_dir="${4:-$TEMPLATE_DIR}"
    [ -n "$kind" ] || err "template kind is required"
    [ -n "$site_type" ] || err "site_type is required for template selection"
    local ext=""
    if [ "$kind" = "wp-config" ]; then
        ext=".php"
    fi
    local stage_norm
    stage_norm="$(tolower "${stage:-}")"
    local stage_suffix=""
    case "$stage_norm" in
        ""|current|live) stage_suffix="" ;;
        *) stage_suffix="-$stage_norm" ;;
    esac
    local base="${kind}-${site_type}"
    local candidate="${template_dir}/${base}${stage_suffix}${ext}"
    local fallback="${template_dir}/${base}${ext}"
    local selected="$candidate"
    if [ ! -f "$selected" ] && [ -f "$fallback" ]; then
        selected="$fallback"
    fi
    local amend_stage="${template_dir}/${base}${stage_suffix}.amend${ext}"
    local amend_base="${template_dir}/${base}.amend${ext}"
    echo "selected:${selected}"
    echo "candidate:${candidate}"
    echo "fallback:${fallback}"
    echo "amend_stage:${amend_stage}"
    echo "amend_base:${amend_base}"
}

normalize_domain() {
    local domain="$1"
    domain=$(tolower "$domain")
    domain="${domain#"${domain%%[![:space:]]*}"}"
    domain="${domain%"${domain##*[![:space:]]}"}"
    echo "$domain"
}

validate_domain() {
    local domain="$1"
    if [ -z "$domain" ]; then
        echo "Error: domain is empty" >&2
        return 1
    fi
    if [ ${#domain} -gt 253 ]; then
        echo "Error: domain exceeds 253 characters" >&2
        return 1
    fi
    if [[ "$domain" == .* || "$domain" == *. ]]; then
        echo "Error: domain cannot start or end with a dot" >&2
        return 1
    fi
    if [[ "$domain" == *..* ]]; then
        echo "Error: domain contains empty labels" >&2
        return 1
    fi
    if [[ "$domain" != *.* ]]; then
        echo "Error: domain must include a dot" >&2
        return 1
    fi
    IFS='.' read -r -a labels <<<"$domain"
    for label in "${labels[@]}"; do
        if [ -z "$label" ]; then
            echo "Error: domain contains empty labels" >&2
            return 1
        fi
        if [ ${#label} -gt 63 ]; then
            echo "Error: label '$label' exceeds 63 characters" >&2
            return 1
        fi
        if ! [[ "$label" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
            echo "Error: label '$label' contains invalid characters" >&2
            return 1
        fi
    done
    return 0
}

validate_ip() {
    local ip="$1"
    if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "Error: IPv4 address has invalid format" >&2
        return 1
    fi
    if [ "$ip" = "0.0.0.0" ]; then
        echo "Error: IPv4 address cannot be 0.0.0.0" >&2
        return 1
    fi
    if [ "$ip" = "255.255.255.255" ]; then
        echo "Error: IPv4 address cannot be 255.255.255.255" >&2
        return 1
    fi
    IFS='.' read -r -a octets <<<"$ip"
    for octet in "${octets[@]}"; do
        if [ "$octet" -lt 0 ] || [ "$octet" -gt 255 ]; then
            echo "Error: IPv4 octet out of range: $octet" >&2
            return 1
        fi
    done
    if [ "${octets[0]}" -eq 10 ]; then
        echo "Error: IPv4 address in RFC1918 private range (10.0.0.0/8) not allowed" >&2
        return 1
    fi
    if [ "${octets[0]}" -eq 172 ] && [ "${octets[1]}" -ge 16 ] && [ "${octets[1]}" -le 31 ]; then
        echo "Error: IPv4 address in RFC1918 private range (172.16.0.0/12) not allowed" >&2
        return 1
    fi
    if [ "${octets[0]}" -eq 192 ] && [ "${octets[1]}" -eq 168 ]; then
        echo "Error: IPv4 address in RFC1918 private range (192.168.0.0/16) not allowed" >&2
        return 1
    fi
    if [ "${octets[0]}" -eq 169 ] && [ "${octets[1]}" -eq 254 ]; then
        echo "Error: IPv4 address in link-local range (169.254.0.0/16) not allowed" >&2
        return 1
    fi
    if [ "${octets[0]}" -eq 127 ]; then
        echo "Error: IPv4 address in loopback range (127.0.0.0/8) not allowed" >&2
        return 1
    fi
    if [ "${octets[3]}" -eq 0 ] || [ "${octets[3]}" -eq 255 ]; then
        warn "IPv4 address ends in .0 or .255; verify it is not a network or broadcast address"
    fi
    if [ "${octets[0]}" -ge 224 ]; then
        echo "Error: IPv4 address in multicast/experimental range not allowed" >&2
        return 1
    fi
    return 0
}

finalize_domains() {
    local -n domains_ref="$1"
    local -A seen=()
    local -a unique=()
    local -a dupes=()
    local domain normalized

    for domain in "${domains_ref[@]}"; do
        normalized=$(normalize_domain "$domain")
        if ! validate_domain "$normalized"; then
            return 1
        fi
        if [ -z "${seen[$normalized]+x}" ]; then
            unique+=("$normalized")
            seen["$normalized"]=1
        else
            dupes+=("$normalized")
        fi
    done

    domains_ref=("${unique[@]}")
    if [ "${#dupes[@]}" -gt 0 ]; then
        warn "duplicate domains ignored: ${dupes[*]}"
    fi
}

# Load operator settings last: it uses kv_file_var, defined above.
load_operator_conf
