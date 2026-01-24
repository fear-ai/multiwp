#!/bin/bash
# check-server.sh - Validate host-level Ubuntu, networking, and data service baselines.
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
check-server.sh - Validate host-level Ubuntu, networking, and data service baselines.
Example: check-server.sh

Options:
  --allow-root  Allow running as root (not recommended)
  --no-sudo [SUDO_BIN] (default: sudo)  Disable sudo usage
  --help  Show this help

Notes:
  - This script is read-only; it reports current settings and configuration.
  - It does not change sysctl, UFW, MySQL, Redis, or cron values.
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

section "SERVER" "Os"
if command -v lsb_release >/dev/null 2>&1; then
    show_cmd "Release" lsb_release -ds
else
    show_cmd "Release" cat /etc/os-release
fi
show_cmd "Kernel" uname -r

section "SERVER" "Updates"
if command -v systemctl >/dev/null 2>&1; then
    show_cmd "unattended-upgrades enabled" systemctl is-enabled unattended-upgrades
    show_cmd "unattended-upgrades active" systemctl is-active unattended-upgrades
else
    warn "systemctl is not available"
fi

section "SERVER" "Ssh"
if command -v systemctl >/dev/null 2>&1; then
    show_cmd "sshd active" systemctl is-active ssh
    show_cmd "sshd enabled" systemctl is-enabled ssh
fi
show_file_lines "sshd_config ports" /etc/ssh/sshd_config "^[[:space:]]*Port[[:space:]]+"

section "SERVER" "Network"
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

section "SERVER" "Ufw"
if command -v ufw >/dev/null 2>&1; then
    show_cmd "ufw status" priv ufw status
    show_cmd "ufw status verbose" priv ufw status verbose
    show_file_lines "/etc/default/ufw" /etc/default/ufw "^IPV6=|^DEFAULT_"
else
    warn "ufw is not installed"
fi

section "SERVER" "Mysql"
if command -v mysql >/dev/null 2>&1; then
    if ! priv mysql -N -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size'; SHOW VARIABLES LIKE 'slow_query_log'; SHOW VARIABLES LIKE 'slow_query_log_file'; SHOW VARIABLES LIKE 'long_query_time';"; then
        warn "MySQL queries failed; check socket auth or root access"
    fi
else
    warn "mysql client is not installed"
fi

section "SERVER" "Redis"
if command -v redis-cli >/dev/null 2>&1; then
    show_cmd "redis ping" redis-cli ping
else
    warn "redis-cli is not installed"
fi

section "SERVER" "Cron"
if command -v systemctl >/dev/null 2>&1; then
    show_cmd "cron active" systemctl is-active cron
    show_cmd "cron enabled" systemctl is-enabled cron
else
    warn "systemctl is not available"
fi
