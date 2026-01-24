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
DATASTORE_DATE="${DATASTORE_DATE-}"
RECORD_UPDATES=true
RECORD_DOWNGRADE=false
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
  --site-type TYPE  Inventory site_type (singlesite, multisite, redirect, worker, ignore, none; default: none)
  --multisite-domain NAME  Inventory multisite domain (used when site_type=multisite)
  --redirect-url URL  Inventory redirect target (used when site_type=redirect)
  --registrar NAME  Inventory registrar (default: Unknown)
  --dns-provider NAME  Inventory DNS provider (default: Cloudflare)
  --domains-file PATH [DOMAINS_FILE] (default: ./domains.csv)  Inventory CSV path
$(cli_usage_date)
  --norecord  Skip domains.csv updates (Cloudflare provisioning only)
  --downgrade  Allow status downgrades in domains.csv (overrides default)

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
  - Domains with site_type none, ignore, or worker are skipped entirely.
EOF
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                norecord) RECORD_UPDATES=false ;;
                downgrade) RECORD_DOWNGRADE=true ;;
                date|date=*)
                    if cli_date_opt "${OPTARG}" DATASTORE_DATE "${!OPTIND-}"; then
                        :
                    else
                        usage; exit 1
                    fi
                    ;;
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
    local status_cf_update=""
    if [ -n "$zone_status" ] && [ "$zone_status" != "active" ]; then
        status_cf_update="added"
    fi

    updates=()
    [ -n "$zone_id" ] && updates+=("zone_id=$zone_id")
    [ -n "$domain" ] && updates+=("zone_name=$domain")
    [ -n "$ip_addr" ] && updates+=("ip=$ip_addr")
    [ -n "$auth_file" ] && updates+=("auth_file=$auth_file")
    [ -n "$account_id" ] && updates+=("account_id=$account_id")
    [ -n "$account_email" ] && updates+=("account_email=$account_email")
    [ -n "$site_type" ] && updates+=("site_type=$site_type")
    [ -n "$multisite_domain" ] && updates+=("multisite_domain=$multisite_domain")
    [ -n "$redirect_url" ] && updates+=("redirect_url=$redirect_url")
    [ -n "$registrar" ] && updates+=("registrar=$registrar")
    [ -n "$dns_provider" ] && updates+=("dns_provider=$dns_provider")
    [ -n "$name_servers" ] && updates+=("name_servers=$name_servers")
    [ -n "$status_cf_update" ] && updates+=("status_cf=$status_cf_update")

    csv_put_fields "$DOMAINS_FILE" "$domain" "$RECORD_DOWNGRADE" "${updates[@]}"
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

    if csv_row=$(csv_get_domain_fields "$domain" auth_file account_id ip site_type multisite_domain redirect_url registrar dns_provider account_email); then
        csv_found=true
        IFS=$'\t' read -r csv_auth_file csv_account_id csv_ip csv_site_type csv_multisite_domain csv_redirect_url csv_registrar csv_dns_provider csv_account_email <<<"$csv_row"
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
    if [ -n "${CF_ACCOUNT_ID_CLI:-}" ]; then
        CF_ACCOUNT_ID="$CF_ACCOUNT_ID_CLI"
    fi
    if [ -z "${CF_ACCOUNT_ID:-}" ] && [ -n "$csv_account_id" ]; then
        CF_ACCOUNT_ID="$csv_account_id"
    fi
    cf_require_account_id "for zone provisioning"
    account_id="$CF_ACCOUNT_ID"

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
    site_type="$(normalize_site_type "$site_type")"
    case "$site_type" in
        singlesite|multisite|redirect|worker|ignore|none) ;;
        *) err "Invalid --site-type: $site_type (expected singlesite, multisite, redirect, worker, ignore, none)" ;;
    esac
    if site_type_is_skip "$site_type"; then
        warn "Skipping $domain (site_type=$site_type)"
        continue
    fi

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
    name_servers_full=$(echo "$zone_resp" | jq -r '.result[0].name_servers[]?')
    name_servers_full=$(echo "$name_servers_full" | paste -sd ' ' -)
    name_servers=""
    if [ -n "$name_servers_full" ]; then
        name_servers_list=()
        for ns in $name_servers_full; do
            name_servers_list+=("${ns%%.*}")
        done
        name_servers=$(IFS=' '; printf '%s' "${name_servers_list[*]}")
    fi

    account_email="$csv_account_email"
    if [ -n "${CF_API_EMAIL:-}" ]; then
        account_email="$CF_API_EMAIL"
    fi

    if [ "$RECORD_UPDATES" = true ]; then
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
    if [ -n "$name_servers_full" ]; then
        log "Nameservers: $name_servers_full"
    fi
done
