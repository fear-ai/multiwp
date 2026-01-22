#!/bin/bash
# check-server.sh - Validate host-level Ubuntu/Apache/PHP/MySQL baseline settings.
# For options, environment variables, defaults see usage().
#
# Example: check-server.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/cli.sh"

ALLOW_ROOT=false

usage() {
    cat <<'EOF'
check-server.sh - Validate host-level Ubuntu/Apache/PHP/MySQL baseline settings.
Example: check-server.sh

Options:
  --allow-root  Allow running as root (not recommended)
  --no-sudo [SUDO_BIN] (default: sudo)  Disable sudo usage
  --help  Show this help

Notes:
  - This script is read-only; it reports current settings and configuration.
  - It does not change sysctl, UFW, Apache, PHP, or MySQL values.
EOF
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                allow-root) ALLOW_ROOT=true ;;
                no-sudo) SUDO_BIN=""; export SUDO_BIN ;;
                *) usage; exit 1 ;;
            esac
            ;;
        \?) usage; exit 1 ;;
    esac
done
shift $((OPTIND-1))

cli_require_non_root
require_cmds awk grep

section() {
    echo ""
    log "$1"
}

show_cmd() {
    local label="$1"
    shift
    echo "${label}:"
    "$@" || warn "Command failed: ${label}"
}

show_file_lines() {
    local label="$1"
    local file="$2"
    local pattern="$3"
    echo "${label}:"
    if [ ! -f "$file" ]; then
        warn "File not found: $file"
        return 0
    fi
    if ! grep -nE "$pattern" "$file" || true; then
        warn "No matches for ${pattern} in $file"
    fi
}

section "OS"
if command -v lsb_release >/dev/null 2>&1; then
    show_cmd "Release" lsb_release -ds
else
    show_cmd "Release" cat /etc/os-release
fi
show_cmd "Kernel" uname -r

section "IPv6"
show_file_lines "sysctl overrides" /etc/sysctl.d/99-disable-ipv6.conf "^net\\.ipv6\\.conf"
for key in net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6 net.ipv6.conf.lo.disable_ipv6 net.ipv6.conf.all.accept_ra net.ipv6.conf.default.accept_ra; do
    value=$(sysctl -n "$key" 2>/dev/null || true)
    echo "$key = ${value:-<unknown>}"
done
if ls /etc/netplan/*.yaml >/dev/null 2>&1; then
    echo "netplan IPv6 entries:"
    if ! grep -nE "accept-ra|dhcp6|ipv6|addresses" /etc/netplan/*.yaml 2>/dev/null || true; then
        warn "No IPv6 directives found in netplan files"
    fi
else
    warn "No netplan files found"
fi

section "UFW"
if command -v ufw >/dev/null 2>&1; then
    show_cmd "ufw status" priv ufw status
    show_cmd "ufw status verbose" priv ufw status verbose
    show_file_lines "/etc/default/ufw" /etc/default/ufw "^IPV6=|^DEFAULT_"
else
    warn "ufw is not installed"
fi

section "Apache"
if command -v apache2ctl >/dev/null 2>&1; then
    show_cmd "apache2ctl -V" priv apache2ctl -V
    show_cmd "apache2ctl -S" priv apache2ctl -S
    show_cmd "apache2ctl -M" priv apache2ctl -M
else
    warn "apache2ctl is not installed"
fi

section "PHP"
if command -v php >/dev/null 2>&1; then
    show_cmd "php -v" php -v
    php -i 2>/dev/null | grep -E '^(opcache\\.|realpath_cache_|memory_limit|upload_max_filesize|post_max_size)' || true
else
    warn "php is not installed"
fi

section "MySQL"
if command -v mysql >/dev/null 2>&1; then
    if ! priv mysql -N -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size'; SHOW VARIABLES LIKE 'slow_query_log'; SHOW VARIABLES LIKE 'slow_query_log_file'; SHOW VARIABLES LIKE 'long_query_time';"; then
        warn "MySQL queries failed; check socket auth or root access"
    fi
else
    warn "mysql client is not installed"
fi
