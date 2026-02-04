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
    if [ -r "$file" ]; then
        if ! grep -nE "$pattern" "$file"; then
            warn "No matches for ${pattern} in $file"
        fi
        return 0
    fi
    if ! priv grep -nE "$pattern" "$file"; then
        warn "No matches for ${pattern} in $file (read via sudo)"
    fi
}

overall_ok=true

note_ok() {
    status_info "$*"
}

note_warn() {
    warn "$*"
}

note_fail() {
    fail "$*"
    overall_ok=false
}

section "SERVER" "Os"
if command -v lsb_release >/dev/null 2>&1; then
    show_cmd "Release" lsb_release -ds
else
    show_cmd "Release" cat /etc/os-release
fi
show_cmd "Kernel" uname -r

section "SERVER" "Updates"
echo "# Policy"
for config in /etc/apt/apt.conf.d/20auto-upgrades /etc/apt/apt.conf.d/50unattended-upgrades; do
    if [ -f "$config" ]; then
        note_ok "unattended-upgrades config present: $config"
    else
        note_warn "Missing unattended-upgrades config: $config"
    fi
done
if [ -L /etc/systemd/system/multi-user.target.wants/unattended-upgrades.service ]; then
    note_ok "unattended-upgrades link present: /etc/systemd/system/multi-user.target.wants/unattended-upgrades.service"
else
    note_warn "Missing unattended-upgrades link: /etc/systemd/system/multi-user.target.wants/unattended-upgrades.service"
fi
if command -v systemctl >/dev/null 2>&1; then
    echo "# Values"
    if val=$(systemctl is-enabled unattended-upgrades 2>/dev/null); then
        kv "UNATTENDED_UPGRADES_ENABLED" "$val"
    else
        note_warn "Unable to read unattended-upgrades enabled state"
    fi
    if val=$(systemctl is-active unattended-upgrades 2>/dev/null); then
        kv "UNATTENDED_UPGRADES_ACTIVE" "$val"
    else
        note_warn "Unable to read unattended-upgrades active state"
    fi
else
    warn "systemctl is not available"
fi

section "SERVER" "Ssh"
echo "# Policy"
ssh_ports=()
if [ -f /etc/ssh/sshd_config ]; then
    while read -r port; do
        [ -n "$port" ] || continue
        ssh_ports+=("$port")
    done < <(awk '/^[[:space:]]*Port[[:space:]]+/ {print $2}' /etc/ssh/sshd_config)
fi
if [ ${#ssh_ports[@]} -eq 0 ]; then
    note_fail "sshd_config has no Port directive; defaults to 22 (not allowed)"
else
    for port in "${ssh_ports[@]}"; do
        if ! [[ "$port" =~ ^[0-9]+$ ]]; then
            note_warn "sshd_config Port is not numeric: $port"
            continue
        fi
        if [ "$port" -eq 22 ]; then
            note_fail "sshd_config Port must not be 22"
        elif [ "$port" -le 1023 ]; then
            note_fail "sshd_config Port must be > 1023 (found $port)"
        else
            note_ok "sshd_config Port ok: $port"
        fi
    done
fi
if command -v systemctl >/dev/null 2>&1; then
    echo "# Values"
    if val=$(systemctl is-active ssh 2>/dev/null); then
        kv "SSHD_ACTIVE" "$val"
    else
        note_warn "Unable to read sshd active state"
    fi
    if val=$(systemctl is-enabled ssh 2>/dev/null); then
        kv "SSHD_ENABLED" "$val"
    else
        note_warn "Unable to read sshd enabled state"
    fi
fi
echo "# Values"
show_file_lines "sshd_config ports" /etc/ssh/sshd_config "^[[:space:]]*Port[[:space:]]+"

section "SERVER" "Network"
echo "# Policy"
if [ -f /etc/sysctl.d/99-disable-ipv6-forward.conf ]; then
    sysctl_file="/etc/sysctl.d/99-disable-ipv6-forward.conf"
else
    sysctl_file="/etc/sysctl.d/99-disable-ipv6.conf"
fi
if [ "$sysctl_file" = "/etc/sysctl.d/99-disable-ipv6-forward.conf" ]; then
    required_sysctl=(
        "net.ipv4.ip_forward=0"
        "net.ipv6.conf.all.forwarding=0"
        "net.ipv6.conf.default.forwarding=0"
        "net.ipv6.conf.all.disable_ipv6=1"
        "net.ipv6.conf.default.disable_ipv6=1"
        "net.ipv6.conf.lo.disable_ipv6=1"
        "net.ipv6.conf.all.accept_ra=0"
        "net.ipv6.conf.default.accept_ra=0"
        "net.ipv6.conf.lo.accept_ra=0"
    )
    for entry in "${required_sysctl[@]}"; do
        key=${entry%%=*}
        val=${entry#*=}
        if grep -Eq "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*${val}[[:space:]]*$" "$sysctl_file"; then
            note_ok "sysctl file ok: ${key}=${val}"
        else
            note_fail "sysctl file missing or mismatched: ${key}=${val}"
        fi
    done
else
    note_warn "Expected sysctl file /etc/sysctl.d/99-disable-ipv6-forward.conf not present"
fi
for key in net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6 net.ipv6.conf.lo.disable_ipv6 net.ipv6.conf.all.accept_ra net.ipv6.conf.default.accept_ra; do
    value=$(sysctl -n "$key" 2>/dev/null || true)
    case "$key" in
        net.ipv6.conf.*.disable_ipv6)
            if [ "$value" = "1" ]; then
                note_ok "$key=1"
            else
                note_fail "$key should be 1 (found ${value:-<unknown>})"
            fi
            ;;
        net.ipv6.conf.*.accept_ra)
            if [ "$value" = "0" ]; then
                note_ok "$key=0"
            else
                note_fail "$key should be 0 (found ${value:-<unknown>})"
            fi
            ;;
    esac
done
if ls /etc/netplan/*.yaml >/dev/null 2>&1; then
    if ! priv grep -nE "accept-ra|dhcp6|ipv6|addresses" /etc/netplan/*.yaml 2>/dev/null; then
        note_warn "No IPv6 directives found in netplan files"
    else
        while IFS=: read -r file line content; do
            key=$(echo "$content" | awk -F: '{print $1}' | tr -d ' ')
            val=$(echo "$content" | awk -F: '{print $2}' | tr -d ' ')
            case "$key" in
                dhcp6|accept-ra)
                    case "$val" in
                        no|false) note_ok "netplan ${key}=${val} in ${file}" ;;
                        yes|true) note_fail "netplan ${key}=${val} (expected no/false) in ${file}" ;;
                        *) note_warn "netplan ${key}=${val} in ${file}" ;;
                    esac
                    ;;
            esac
        done < <(priv grep -nE "^[[:space:]]*(dhcp6|accept-ra)[[:space:]]*:" /etc/netplan/*.yaml 2>/dev/null || true)
    fi
else
    note_warn "No netplan files found"
fi
echo "# Values"
kv "SYSCTL_FILE" "$sysctl_file"
if [ -f "$sysctl_file" ]; then
    show_file_lines "sysctl overrides" "$sysctl_file" "^net\\.ipv6\\.conf"
fi
for key in net.ipv6.conf.all.disable_ipv6 net.ipv6.conf.default.disable_ipv6 net.ipv6.conf.lo.disable_ipv6 net.ipv6.conf.all.accept_ra net.ipv6.conf.default.accept_ra; do
    value=$(sysctl -n "$key" 2>/dev/null || true)
    kv "$key" "${value:-<unknown>}"
done
if ls /etc/netplan/*.yaml >/dev/null 2>&1; then
    echo "netplan IPv6 entries:"
    priv grep -nE "accept-ra|dhcp6|ipv6|addresses" /etc/netplan/*.yaml 2>/dev/null || true
fi

section "SERVER" "Ufw"
if command -v ufw >/dev/null 2>&1; then
    echo "# Policy"
    ufw_ipv6=$(awk -F= '/^IPV6=/{print $2}' /etc/default/ufw 2>/dev/null | tr -d '[:space:]')
    if [ "$ufw_ipv6" = "no" ]; then
        note_ok "ufw IPV6=no"
    else
        note_fail "ufw IPV6 should be no (found ${ufw_ipv6:-<missing>})"
    fi
    if [ -f /etc/ufw/user.rules ]; then
        if priv grep -q "cloudflare-ipv4" /etc/ufw/user.rules; then
            note_ok "ufw user.rules includes cloudflare-ipv4 allowlist"
        else
            note_info "ufw user.rules does not include cloudflare-ipv4 allowlist (postponed)"
        fi
    else
        note_info "ufw user.rules not found (postponed)"
    fi
    if [ -f /etc/ufw/ufw.conf ]; then
        ufw_enabled=$(awk -F= '/^ENABLED=/{print $2}' /etc/ufw/ufw.conf 2>/dev/null | tr -d '[:space:]')
        if [ "$ufw_enabled" = "yes" ]; then
            note_ok "ufw enabled via ufw.conf"
        else
            note_warn "ufw not enabled in ufw.conf (ENABLED=${ufw_enabled:-<missing>})"
        fi
    fi
    echo "# Values"
    show_cmd "ufw status" priv ufw status
    show_cmd "ufw status verbose" priv ufw status verbose
    show_file_lines "/etc/default/ufw" /etc/default/ufw "^IPV6=|^DEFAULT_"
else
    note_warn "ufw is not installed"
fi

section "SERVER" "Apache"
if command -v apache2ctl >/dev/null 2>&1; then
    show_cmd "Apache version" priv apache2ctl -V
    show_cmd "Apache modules" priv apache2ctl -M
    show_cmd "Apache vhost map" priv apache2ctl -S
    show_file_lines "ports.conf listen" /etc/apache2/ports.conf "^[[:space:]]*Listen"
    show_file_lines "mpm_prefork.conf" /etc/apache2/mods-available/mpm_prefork.conf "^[[:space:]]*(StartServers|MinSpareServers|MaxSpareServers|MaxRequestWorkers|MaxConnectionsPerChild)"
    show_file_lines "apache2.conf tuning" /etc/apache2/apache2.conf "^[[:space:]]*(Timeout|KeepAlive|MaxKeepAliveRequests|KeepAliveTimeout)"
    show_file_lines "security.conf posture" /etc/apache2/conf-available/security.conf "^[[:space:]]*(ServerTokens|ServerSignature|TraceEnable)"
    if command -v systemctl >/dev/null 2>&1; then
        show_cmd "apache2 active" systemctl is-active apache2
        show_cmd "apache2 enabled" systemctl is-enabled apache2
    fi
else
    warn "apache2ctl is not installed"
fi

section "SERVER" "Mysql"
if command -v mysql >/dev/null 2>&1; then
    if ! priv mysql -N -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size'; SHOW VARIABLES LIKE 'slow_query_log'; SHOW VARIABLES LIKE 'slow_query_log_file'; SHOW VARIABLES LIKE 'long_query_time'; SHOW VARIABLES LIKE 'max_connections'; SHOW VARIABLES LIKE 'table_open_cache'; SHOW VARIABLES LIKE 'tmp_table_size'; SHOW VARIABLES LIKE 'max_heap_table_size';"; then
        note_warn "MySQL queries failed; check socket auth or root access"
    fi
else
    note_warn "mysql client is not installed"
fi

section "SERVER" "Redis"
if command -v redis-cli >/dev/null 2>&1; then
    echo "redis ping:"
    if redis-cli ping >/dev/null 2>&1; then
        status_info "Redis responding"
    else
        status_info "Redis not running (expected if disabled)"
    fi
else
    warn "redis-cli is not installed"
fi

section "SERVER" "Cron"
if command -v systemctl >/dev/null 2>&1; then
    show_cmd "cron active" systemctl is-active cron
    show_cmd "cron enabled" systemctl is-enabled cron
else
    note_warn "systemctl is not available"
fi

if [ "$overall_ok" != true ]; then
    exit 1
fi
