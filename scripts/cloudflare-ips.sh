#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$ROOT_DIR/scripts}"

# shellcheck source=scripts/common.sh
# shellcheck source=scripts/cli.sh
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/cli.sh"

CF_IPS_URL="https://www.cloudflare.com/ips-v4"
OUTPUT_FILE="${OUTPUT_FILE:-$ROOT_DIR/templates/ufw/ufw.cloudflare}"
CF_COMMENT="${CF_COMMENT:-cloudflare-ipv4}"
PORTS=(80 443)
UPDATE_UFW=false
UFW_RULES_FILE="${UFW_RULES_FILE:-}"

usage() {
    cat <<'EOF'
cloudflare-ips.sh - generate Cloudflare IPv4 UFW allowlist entries

Usage:
  scripts/cloudflare-ips.sh [--output PATH] [--ufw[=PATH]] [--allow-root] [--no-sudo] [--help]

Options:
  --output PATH  Write UFW entries to PATH (default: ./templates/ufw/ufw.cloudflare)
  --ufw[=PATH]   Update the Cloudflare allowlist block inside a UFW user.rules file
                (default: user.rules in the same directory as --output)
  --allow-root   Allow running as root (not recommended)
  --no-sudo      Disable sudo usage (run commands as current user)
  --help         Show this help message
EOF
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "$OPTARG" in
                output=*)
                    OUTPUT_FILE="${OPTARG#*=}"
                    ;;
                output)
                    OUTPUT_FILE="${!OPTIND-}"
                    OPTIND=$((OPTIND+1))
                    ;;
                ufw)
                    UPDATE_UFW=true
                    ;;
                ufw=*)
                    UPDATE_UFW=true
                    UFW_RULES_FILE="${OPTARG#*=}"
                    ;;
                help)
                    usage
                    exit 0
                    ;;
                *)
                    if cli_common_opt "$OPTARG"; then
                        :
                    else
                        err "Unknown option --$OPTARG"
                    fi
                    ;;
            esac
            ;;
        *)
            err "Unknown option"
            ;;
    esac
done
shift $((OPTIND-1))
if [ "$#" -gt 0 ]; then
    err "Unknown argument: $1"
fi

cli_require_non_root
require_cmds curl

if [ -z "$OUTPUT_FILE" ]; then
    err "--output requires a path"
fi

mapfile -t cf_ips < <(curl -fsS "$CF_IPS_URL" | tr ' ' '\n' | sed '/^$/d')
if [ "${#cf_ips[@]}" -eq 0 ]; then
    err "No Cloudflare IP ranges returned from $CF_IPS_URL"
fi

section "FIREWALL" "IpList"
kv "OUTPUT_FILE" "$OUTPUT_FILE"
now_utc=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
{
    echo "# Cloudflare IPv4 UFW allowlist"
    echo "# Source: $CF_IPS_URL"
    echo "# Generated: $now_utc"
    echo "# Ports: ${PORTS[*]}"
    echo "# Comment: $CF_COMMENT"
    echo "#"
    echo "# This file is generated. Re-run scripts/cloudflare-ips.sh to refresh."
    echo ""
    for ip in "${cf_ips[@]}"; do
        for port in "${PORTS[@]}"; do
            echo "ufw allow from $ip to any port $port proto tcp comment \"$CF_COMMENT\""
        done
    done
} >"$OUTPUT_FILE"

log "Wrote UFW entries to $OUTPUT_FILE"

if [ "$UPDATE_UFW" = true ]; then
    require_cmds python3
    if [ -z "$UFW_RULES_FILE" ]; then
        UFW_RULES_FILE="$(dirname "$OUTPUT_FILE")/user.rules"
    fi
    section "FIREWALL" "UfwRules"
    kv "UFW_RULES_FILE" "$UFW_RULES_FILE"
    python3 - "$OUTPUT_FILE" "$UFW_RULES_FILE" "$CF_COMMENT" <<'EOF'
import os
import re
import sys

ufw_cloudflare = sys.argv[1]
ufw_rules = sys.argv[2]
comment = sys.argv[3]

start_marker = "# allow Cloudflare IPv4 ranges to HTTP/HTTPS"
end_marker = "### END RULES ###"

ips = []
for line in open(ufw_cloudflare, "r", encoding="utf-8"):
    line = line.strip()
    if not line.startswith("ufw allow from "):
        continue
    m = re.match(r"ufw allow from (\S+) to any port (\d+) proto tcp", line)
    if not m:
        continue
    ips.append((m.group(1), m.group(2)))

if not ips:
    raise SystemExit(f"No Cloudflare IPs parsed from {ufw_cloudflare}")

comment_hex = comment.encode("utf-8").hex()

if not os.path.exists(ufw_rules):
    lines = [
        "*filter",
        ":ufw-user-input - [0:0]",
        ":ufw-user-output - [0:0]",
        ":ufw-user-forward - [0:0]",
        ":ufw-before-logging-input - [0:0]",
        ":ufw-before-logging-output - [0:0]",
        ":ufw-before-logging-forward - [0:0]",
        ":ufw-user-logging-input - [0:0]",
        ":ufw-user-logging-output - [0:0]",
        ":ufw-user-logging-forward - [0:0]",
        ":ufw-after-logging-input - [0:0]",
        ":ufw-after-logging-output - [0:0]",
        ":ufw-after-logging-forward - [0:0]",
        ":ufw-logging-deny - [0:0]",
        ":ufw-logging-allow - [0:0]",
        ":ufw-user-limit - [0:0]",
        ":ufw-user-limit-accept - [0:0]",
        "### RULES ###",
        "",
        start_marker,
        "",
    ]
    for ip, port in ips:
        lines.append(f"### tuple ### allow tcp {port} 0.0.0.0/0 any {ip} in comment={comment_hex}")
        lines.append(f"-A ufw-user-input -p tcp --dport {port} -s {ip} -j ACCEPT")
        lines.append("")
    lines.extend([
        end_marker,
        "",
        "### LOGGING ###",
        "-A ufw-after-logging-input -j LOG --log-prefix \"[UFW BLOCK] \" -m limit --limit 3/min --limit-burst 10",
        "-A ufw-after-logging-forward -j LOG --log-prefix \"[UFW BLOCK] \" -m limit --limit 3/min --limit-burst 10",
        "-I ufw-logging-deny -m conntrack --ctstate INVALID -j RETURN -m limit --limit 3/min --limit-burst 10",
        "-A ufw-logging-deny -j LOG --log-prefix \"[UFW BLOCK] \" -m limit --limit 3/min --limit-burst 10",
        "-A ufw-logging-allow -j LOG --log-prefix \"[UFW ALLOW] \" -m limit --limit 3/min --limit-burst 10",
        "### END LOGGING ###",
        "",
        "### RATE LIMITING ###",
        "-A ufw-user-limit -m limit --limit 3/minute -j LOG --log-prefix \"[UFW LIMIT BLOCK] \"",
        "-A ufw-user-limit -j REJECT",
        "-A ufw-user-limit-accept -j ACCEPT",
        "### END RATE LIMITING ###",
        "COMMIT",
    ])
    open(ufw_rules, "w", encoding="utf-8").write("\n".join(lines) + "\n")
else:
    lines = open(ufw_rules, "r", encoding="utf-8").read().splitlines()
    start_idx = None
    end_idx = None
    for idx, line in enumerate(lines):
        if line.strip() == start_marker:
            start_idx = idx
            break
    if start_idx is None:
        raise SystemExit(f"Start marker not found in {ufw_rules}: {start_marker}")
    for idx in range(start_idx + 1, len(lines)):
        if lines[idx].strip() == end_marker:
            end_idx = idx
            break
    if end_idx is None:
        raise SystemExit(f"End marker not found in {ufw_rules}: {end_marker}")
    new_lines = []
    new_lines.extend(lines[:start_idx + 1])
    new_lines.append("")
    for ip, port in ips:
        new_lines.append(f"### tuple ### allow tcp {port} 0.0.0.0/0 any {ip} in comment={comment_hex}")
        new_lines.append(f"-A ufw-user-input -p tcp --dport {port} -s {ip} -j ACCEPT")
        new_lines.append("")
    new_lines.extend(lines[end_idx:])
    open(ufw_rules, "w", encoding="utf-8").write("\n".join(new_lines) + "\n")
EOF
    log "Updated Cloudflare allowlist in $UFW_RULES_FILE"
fi
