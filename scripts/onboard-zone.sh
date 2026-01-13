#!/bin/bash
# onboard-zone.sh - Create or ensure a Cloudflare zone, add baseline DNS, and update domains.csv.
# For options, environment variables, defaults see usage().
#
# Example: onboard-zone.sh --domain example.com --ip 203.0.113.10

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/auth.sh"
. "$SCRIPTS_DIR/cli.sh"

DOMAINS=()
DEFAULT_IP="104.238.140.248"
IP="${IP-}"
DOMAINS_FILE="${DOMAINS_FILE:-$ROOT_DIR/domains.csv}"
CSV_UPDATE=true
SITE_TYPE=""
MULTISITE_DOMAIN=""
REDIRECT_URL=""
REGISTRAR="Unknown"
DNS_PROVIDER="Cloudflare"

SITE_TYPE_SET=false
MULTISITE_SET=false
REDIRECT_SET=false
REGISTRAR_SET=false
DNS_PROVIDER_SET=false

usage() {
    cat <<'EOF'
onboard-zone.sh - Create or ensure a Cloudflare zone, add baseline DNS, and update domains.csv.
Example: onboard-zone.sh --domain example.com --ip 203.0.113.10

Options:
  --domain NAME  Domain to provision (repeatable; positional also accepted)
  --ip IP [IP]  IPv4 address for the apex A record (default: 104.238.140.248)
  --site-type TYPE  Inventory site_type (standalone, multisite, redirect; default: standalone)
  --multisite-domain NAME  Inventory multisite domain (used when site_type=multisite)
  --redirect-url URL  Inventory redirect target (used when site_type=redirect)
  --registrar NAME  Inventory registrar (default: Unknown)
  --dns-provider NAME  Inventory DNS provider (default: Cloudflare)
  --domains-file PATH [DOMAINS_FILE] (default: ./domains.csv)  Inventory CSV path
  --no-csv  Skip domains.csv updates (Cloudflare provisioning only)

Auth options (choose one):
  - Account API Token (recommended): CF_API_TOKEN=... [--token TOKEN]
  - Global API Key + email (user): CF_API_KEY=... CF_API_EMAIL=... [--key KEY --email EMAIL]
  --auth token|key|auto [CF_AUTH]  Select which credential to use (default: auto)
  --auth-file PATH [CF_AUTH_FILE] (default: ~/.config/cloudflare/default.auth)  Auth file to load
  --account ID [CF_ACCOUNT_ID]  Cloudflare account ID
  --account-name NAME [CF_ACCOUNT_NAME]  Cloudflare account name (used to look up ID)
  --token TOKEN [CF_API_TOKEN]  Set CF_API_TOKEN (account API token)
  --key KEY [CF_API_KEY]  Set CF_API_KEY (global API key)
  --email EMAIL [CF_API_EMAIL]  Set CF_API_EMAIL (global API key email)
  --help  Show this help

Notes:
  - This script wraps cloud-dns.sh and then records zone details back into domains.csv.
  - If IP is not supplied, the script uses ip from domains.csv; if still empty, it defaults to 104.238.140.248.
  - Zone creation requires a Global API Key; the script defaults to --auth key unless you override it.
EOF
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                no-csv) CSV_UPDATE=false ;;
                domains-file=*) DOMAINS_FILE="${OPTARG#*=}" ;;
                domains-file)
                    [ -n "${!OPTIND-}" ] || err "--domains-file requires a path"
                    DOMAINS_FILE="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                ip=*) IP="${OPTARG#*=}" ;;
                ip)
                    [ -n "${!OPTIND-}" ] || err "--ip requires a value"
                    IP="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                site-type=*) SITE_TYPE="${OPTARG#*=}"; SITE_TYPE_SET=true ;;
                site-type)
                    [ -n "${!OPTIND-}" ] || err "--site-type requires a value"
                    SITE_TYPE="${!OPTIND}"
                    SITE_TYPE_SET=true
                    OPTIND=$((OPTIND+1))
                    ;;
                multisite-domain=*) MULTISITE_DOMAIN="${OPTARG#*=}"; MULTISITE_SET=true ;;
                multisite-domain)
                    [ -n "${!OPTIND-}" ] || err "--multisite-domain requires a value"
                    MULTISITE_DOMAIN="${!OPTIND}"
                    MULTISITE_SET=true
                    OPTIND=$((OPTIND+1))
                    ;;
                redirect-url=*) REDIRECT_URL="${OPTARG#*=}"; REDIRECT_SET=true ;;
                redirect-url)
                    [ -n "${!OPTIND-}" ] || err "--redirect-url requires a value"
                    REDIRECT_URL="${!OPTIND}"
                    REDIRECT_SET=true
                    OPTIND=$((OPTIND+1))
                    ;;
                registrar=*) REGISTRAR="${OPTARG#*=}"; REGISTRAR_SET=true ;;
                registrar)
                    [ -n "${!OPTIND-}" ] || err "--registrar requires a value"
                    REGISTRAR="${!OPTIND}"
                    REGISTRAR_SET=true
                    OPTIND=$((OPTIND+1))
                    ;;
                dns-provider=*) DNS_PROVIDER="${OPTARG#*=}"; DNS_PROVIDER_SET=true ;;
                dns-provider)
                    [ -n "${!OPTIND-}" ] || err "--dns-provider requires a value"
                    DNS_PROVIDER="${!OPTIND}"
                    DNS_PROVIDER_SET=true
                    OPTIND=$((OPTIND+1))
                    ;;
                *)
                    if cli_domain_opt "${OPTARG}" DOMAINS "${!OPTIND-}"; then
                        :
                    elif cli_cf_auth_opt "${OPTARG}" "${!OPTIND-}"; then
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

if [ ${#DOMAINS[@]} -eq 0 ]; then
    [ $# -ge 1 ] || { usage; exit 1; }
    DOMAINS+=("$1")
    shift
fi

if [ $# -gt 1 ]; then
    err "Too many arguments. Provide at most one positional IPv4 value."
fi
if [ $# -eq 1 ] && [ -z "$IP" ]; then
    IP="$1"
fi

finalize_domains DOMAINS || { usage; exit 1; }

if [ -z "${CF_AUTH_CLI:-}" ]; then
    CF_AUTH_CLI="key"
fi

require_cmds curl jq python3

resolve_account_id() {
    local name="$1"
    [ -n "$name" ] || err "account name is empty"
    cf_require_auth "to resolve account name"
    local encoded
    encoded=$(python3 - <<'PY' "$name"
import sys
import urllib.parse
print(urllib.parse.quote(sys.argv[1]))
PY
)
    local resp
    resp=$(cf_api_request GET "/accounts?name=${encoded}")
    if [ "$(cf_api_success "$resp")" != "true" ]; then
        err "Failed to query accounts: $(cf_api_error_messages "$resp")"
    fi
    local acct_id
    acct_id=$(echo "$resp" | jq -r '.result[0].id // empty')
    [ -n "$acct_id" ] || err "No account found for name: $name"
    echo "$acct_id"
}

csv_lookup() {
    local domain="$1"
    [ -f "$DOMAINS_FILE" ] || return 1
    python3 - "$DOMAINS_FILE" "$domain" <<'PY'
import csv
import sys

path, domain = sys.argv[1], sys.argv[2].strip().lower()
with open(path, newline="") as fh:
    reader = csv.DictReader(fh)
    for row in reader:
        if (row.get("domain") or "").strip().lower() == domain:
            fields = [
                row.get("auth_file", ""),
                row.get("account_id", ""),
                row.get("ip", ""),
                row.get("site_type", ""),
                row.get("multisite_domain", ""),
                row.get("redirect_url", ""),
                row.get("registrar", ""),
                row.get("dns_provider", ""),
                row.get("account_email", ""),
            ]
            print("|".join([f.strip() for f in fields]))
            sys.exit(0)
sys.exit(1)
PY
}

update_csv() {
    local domain="$1"
    local zone_id="$2"
    local zone_status="$3"
    local name_servers="$4"
    local ip_addr="$5"
    local auth_file="$6"
    local account_id="$7"
    local account_email="$8"
    local site_type="$9"
    local multisite_domain="${10}"
    local redirect_url="${11}"
    local registrar="${12}"
    local dns_provider="${13}"

    local notes_append=""
    if [ -n "$zone_status" ] && [ "$zone_status" != "active" ]; then
        if [ -n "$name_servers" ]; then
            notes_append="zone pending; ns: $name_servers"
        else
            notes_append="zone pending"
        fi
    elif [ -n "$name_servers" ]; then
        notes_append="ns: $name_servers"
    fi

    DOMAIN_ORIG="$domain" \
    DOMAIN="$domain" \
    ZONE_ID="$zone_id" \
    ZONE_NAME="$domain" \
    IP="$ip_addr" \
    AUTH_FILE="$auth_file" \
    ACCOUNT_ID="$account_id" \
    ACCOUNT_EMAIL="$account_email" \
    SITE_TYPE="$site_type" \
    MULTISITE_DOMAIN="$multisite_domain" \
    REDIRECT_URL="$redirect_url" \
    REGISTRAR="$registrar" \
    DNS_PROVIDER="$dns_provider" \
    NOTES_APPEND="$notes_append" \
    python3 - "$DOMAINS_FILE" <<'PY'
import csv
import os
import sys

path = sys.argv[1]
domain = os.environ.get("DOMAIN", "").strip().lower()
domain_orig = os.environ.get("DOMAIN_ORIG", domain)

updates = {
    "domain": domain_orig,
    "registrar": os.environ.get("REGISTRAR", ""),
    "dns_provider": os.environ.get("DNS_PROVIDER", ""),
    "ip": os.environ.get("IP", ""),
    "auth_file": os.environ.get("AUTH_FILE", ""),
    "zone_id": os.environ.get("ZONE_ID", ""),
    "zone_name": os.environ.get("ZONE_NAME", ""),
    "account_id": os.environ.get("ACCOUNT_ID", ""),
    "account_email": os.environ.get("ACCOUNT_EMAIL", ""),
    "site_type": os.environ.get("SITE_TYPE", ""),
    "multisite_domain": os.environ.get("MULTISITE_DOMAIN", ""),
    "redirect_url": os.environ.get("REDIRECT_URL", ""),
}
notes_append = (os.environ.get("NOTES_APPEND", "") or "").strip()

if not os.path.exists(path):
    raise SystemExit(f"domains.csv not found at {path}")

with open(path, newline="") as fh:
    reader = csv.DictReader(fh)
    fieldnames = reader.fieldnames or []
    rows = list(reader)

if not fieldnames:
    raise SystemExit("domains.csv is missing a header row")

found = False
for row in rows:
    if (row.get("domain") or "").strip().lower() == domain:
        found = True
        for key, val in updates.items():
            if val:
                row[key] = val
        if notes_append:
            existing = (row.get("notes") or "").strip()
            if notes_append not in existing:
                row["notes"] = f"{existing}; {notes_append}" if existing else notes_append
        break

if not found:
    new_row = {k: "" for k in fieldnames}
    for key, val in updates.items():
        if key in new_row and val:
            new_row[key] = val
    if notes_append and "notes" in new_row:
        new_row["notes"] = notes_append
    rows.append(new_row)

with open(path, "w", newline="") as fh:
    writer = csv.DictWriter(fh, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)
PY
}

for domain in "${DOMAINS[@]}"; do
    csv_found=false
    csv_auth_file=""
    csv_account_id=""
    csv_ip=""
    csv_site_type=""
    csv_multisite_domain=""
    csv_redirect_url=""
    csv_registrar=""
    csv_dns_provider=""
    csv_account_email=""

    if csv_row=$(csv_lookup "$domain"); then
        csv_found=true
        IFS='|' read -r csv_auth_file csv_account_id csv_ip csv_site_type csv_multisite_domain csv_redirect_url csv_registrar csv_dns_provider csv_account_email <<<"$csv_row"
    fi

    auth_file="${CF_AUTH_FILE:-}"
    if [ -z "$auth_file" ]; then
        auth_file="$csv_auth_file"
    fi
    if [ -z "$auth_file" ]; then
        auth_file="$HOME/.config/cloudflare/default.auth"
    fi

    cf_init_auth "$auth_file"
    [ -n "${CF_AUTH_CLI:-}" ] && CF_AUTH="$CF_AUTH_CLI"

    account_id="${CF_ACCOUNT_ID:-}"
    if [ -n "${CF_ACCOUNT_ID_CLI:-}" ]; then
        account_id="$CF_ACCOUNT_ID_CLI"
    fi
    if [ -z "$account_id" ]; then
        account_id="$csv_account_id"
    fi
    if [ -z "$account_id" ] && [ -n "${CF_ACCOUNT_NAME:-}" ]; then
        account_id=$(resolve_account_id "$CF_ACCOUNT_NAME")
    fi
    [ -n "$account_id" ] || err "CF_ACCOUNT_ID required (env, --account, or domains.csv)"

    ip_addr="$IP"
    if [ -z "$ip_addr" ]; then
        ip_addr="$csv_ip"
    fi
    if [ -z "$ip_addr" ]; then
        ip_addr="$DEFAULT_IP"
    fi
    [ -n "$ip_addr" ] || err "IPv4 required via --ip, IP env, domains.csv, or default"
    validate_ip "$ip_addr" || exit 1

    site_type="$SITE_TYPE"
    if [ -z "$site_type" ]; then
        site_type="$csv_site_type"
    fi
    if [ -z "$site_type" ]; then
        site_type="standalone"
    fi
    site_type="$(tolower "$site_type")"
    case "$site_type" in
        standalone|multisite|redirect) ;;
        *) err "Invalid --site-type: $site_type (expected standalone, multisite, redirect)" ;;
    esac

    multisite_domain="$MULTISITE_DOMAIN"
    if [ -z "$multisite_domain" ]; then
        multisite_domain="$csv_multisite_domain"
    fi

    redirect_url="$REDIRECT_URL"
    if [ -z "$redirect_url" ]; then
        redirect_url="$csv_redirect_url"
    fi

    registrar="$REGISTRAR"
    if [ "$REGISTRAR_SET" = false ] && [ -n "$csv_registrar" ]; then
        registrar="$csv_registrar"
    fi

    dns_provider="$DNS_PROVIDER"
    if [ "$DNS_PROVIDER_SET" = false ] && [ -n "$csv_dns_provider" ]; then
        dns_provider="$csv_dns_provider"
    fi

    if [ "$site_type" = "multisite" ] && [ -z "$multisite_domain" ]; then
        warn "site_type=multisite but multisite_domain is empty for $domain"
    fi
    if [ "$site_type" = "redirect" ] && [ -z "$redirect_url" ]; then
        warn "site_type=redirect but redirect_url is empty for $domain"
    fi

    log "Provisioning Cloudflare zone and DNS for $domain"
    auth_args=()
    if [ -n "${CF_AUTH_CLI:-}" ]; then
        auth_args=(--auth "$CF_AUTH_CLI")
    fi
    "$SCRIPTS_DIR/cloud-dns.sh" --auth-file "$auth_file" --account "$account_id" "${auth_args[@]}" "$domain" "$ip_addr"

    cf_init_auth "$auth_file"
    [ -n "${CF_AUTH_CLI:-}" ] && CF_AUTH="$CF_AUTH_CLI"
    [ -n "${CF_ACCOUNT_ID_CLI:-}" ] && CF_ACCOUNT_ID="$CF_ACCOUNT_ID_CLI"
    cf_require_auth "for zone lookup"

    zone_resp=$(cf_api_request GET "/zones?name=${domain}")
    if [ "$(cf_api_success "$zone_resp")" != "true" ]; then
        err "Failed to query zone for $domain: $(cf_api_error_messages "$zone_resp")"
    fi
    zone_id=$(echo "$zone_resp" | jq -r '.result[0].id // empty')
    zone_status=$(echo "$zone_resp" | jq -r '.result[0].status // empty')
    name_servers=$(echo "$zone_resp" | jq -r '.result[0].name_servers[]?')
    name_servers=$(echo "$name_servers" | paste -sd ' ' -)

    account_email="$csv_account_email"
    if [ -n "${CF_API_EMAIL:-}" ]; then
        account_email="$CF_API_EMAIL"
    fi

    if [ "$CSV_UPDATE" = true ]; then
        update_site_type=""
        update_registrar=""
        update_dns_provider=""
        update_multisite_domain=""
        update_redirect_url=""

        if [ "$SITE_TYPE_SET" = true ] || [ -z "$csv_site_type" ]; then
            update_site_type="$site_type"
        fi
        if [ "$REGISTRAR_SET" = true ] || [ -z "$csv_registrar" ]; then
            update_registrar="$registrar"
        fi
        if [ "$DNS_PROVIDER_SET" = true ] || [ -z "$csv_dns_provider" ]; then
            update_dns_provider="$dns_provider"
        fi
        if [ "$MULTISITE_SET" = true ]; then
            update_multisite_domain="$multisite_domain"
        fi
        if [ "$REDIRECT_SET" = true ]; then
            update_redirect_url="$redirect_url"
        fi

        update_csv "$domain" "$zone_id" "$zone_status" "$name_servers" "$ip_addr" "$auth_file" "$account_id" "$account_email" \
            "$update_site_type" "$update_multisite_domain" "$update_redirect_url" "$update_registrar" "$update_dns_provider"
    fi

    log "Zone ready: $domain ($zone_id, status=$zone_status)"
    if [ -n "$name_servers" ]; then
        log "Nameservers: $name_servers"
    fi
done
