#!/bin/bash
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$ROOT_DIR/scripts}"

SSL_DIR="${SSL_DIR:-/etc/ssl/cloudflare-origin}"
SSL_CERT_DIR="${SSL_CERT_DIR:-$SSL_DIR/certs}"
SSL_KEY_DIR="${SSL_KEY_DIR:-$SSL_DIR/keys}"
APACHE_DIR="${APACHE_DIR:-/etc/apache2/sites-available}"
WORDPRESS_ROOT="${WORDPRESS_ROOT:-/var/www/html/wordpress}"
TEMPLATE_DIR="${TEMPLATE_DIR:-$ROOT_DIR/templates}"

log() { echo "[$(date +%H:%M:%S)] $*"; }
err() { echo "[$(date +%H:%M:%S)] ERROR: $*" >&2; exit 1; }
warn() { echo "[$(date +%H:%M:%S)] Warning: $*" >&2; }
fail() { echo "[$(date +%H:%M:%S)] FAIL: $*" >&2; }
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
parse_comma_list() {
    local raw="${1-}"
    local -n out="$2"
    local label="${3:-list}"
    out=()
    IFS=',' read -r -a parts <<<"$raw"
    local ok=true
    local part trimmed
    for part in "${parts[@]}"; do
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

auth_file_var() {
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

load_dns_redirects() {
    DNS_REDIRECT_LIST=()
    declare -gA DNS_REDIRECT_TARGETS=()
    local csv="${DOMAINS_FILE:-$ROOT_DIR/domains.csv}"
    [ -f "$csv" ] || return 0
    local redirect_list=""
    if command -v python3 >/dev/null 2>&1; then
        redirect_list=$(python3 - "$csv" <<'PY'
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
PY
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
        echo "Error: domain is empty"
        return 1
    fi
    if [ ${#domain} -gt 253 ]; then
        echo "Error: domain exceeds 253 characters"
        return 1
    fi
    if [[ "$domain" == .* || "$domain" == *. ]]; then
        echo "Error: domain cannot start or end with a dot"
        return 1
    fi
    if [[ "$domain" == *..* ]]; then
        echo "Error: domain contains empty labels"
        return 1
    fi
    if [[ "$domain" != *.* ]]; then
        echo "Error: domain must include a dot"
        return 1
    fi
    IFS='.' read -r -a labels <<<"$domain"
    for label in "${labels[@]}"; do
        if [ -z "$label" ]; then
            echo "Error: domain contains empty labels"
            return 1
        fi
        if [ ${#label} -gt 63 ]; then
            echo "Error: label '$label' exceeds 63 characters"
            return 1
        fi
        if ! [[ "$label" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
            echo "Error: label '$label' contains invalid characters"
            return 1
        fi
    done
    return 0
}

validate_ip() {
    local ip="$1"
    if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "Error: IPv4 address has invalid format"
        return 1
    fi
    if [ "$ip" = "0.0.0.0" ]; then
        echo "Error: IPv4 address cannot be 0.0.0.0"
        return 1
    fi
    if [ "$ip" = "255.255.255.255" ]; then
        echo "Error: IPv4 address cannot be 255.255.255.255"
        return 1
    fi
    IFS='.' read -r -a octets <<<"$ip"
    for octet in "${octets[@]}"; do
        if [ "$octet" -lt 0 ] || [ "$octet" -gt 255 ]; then
            echo "Error: IPv4 octet out of range: $octet"
            return 1
        fi
    done
    if [ "${octets[0]}" -eq 10 ]; then
        echo "Error: IPv4 address in RFC1918 private range (10.0.0.0/8) not allowed"
        return 1
    fi
    if [ "${octets[0]}" -eq 172 ] && [ "${octets[1]}" -ge 16 ] && [ "${octets[1]}" -le 31 ]; then
        echo "Error: IPv4 address in RFC1918 private range (172.16.0.0/12) not allowed"
        return 1
    fi
    if [ "${octets[0]}" -eq 192 ] && [ "${octets[1]}" -eq 168 ]; then
        echo "Error: IPv4 address in RFC1918 private range (192.168.0.0/16) not allowed"
        return 1
    fi
    if [ "${octets[0]}" -eq 169 ] && [ "${octets[1]}" -eq 254 ]; then
        echo "Error: IPv4 address in link-local range (169.254.0.0/16) not allowed"
        return 1
    fi
    if [ "${octets[0]}" -eq 127 ]; then
        echo "Error: IPv4 address in loopback range (127.0.0.0/8) not allowed"
        return 1
    fi
    if [ "${octets[3]}" -eq 0 ] || [ "${octets[3]}" -eq 255 ]; then
        warn "IPv4 address ends in .0 or .255; verify it is not a network or broadcast address"
    fi
    if [ "${octets[0]}" -ge 224 ]; then
        echo "Error: IPv4 address in multicast/experimental range not allowed"
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
