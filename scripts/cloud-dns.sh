#!/bin/bash
# cloud-dns.sh - Create a Cloudflare zone via the API and add basic DNS records.
# For options, environment variables, defaults see usage().
#
# Example: cloud-dns.sh <domain> <ip>

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/auth.sh"
. "$SCRIPTS_DIR/cli.sh"

CF_ACCOUNT_ID_CLI=""
CF_API_TOKEN_CLI=""
CF_API_EMAIL_CLI=""
CF_API_KEY_CLI=""
CF_AUTH_CLI=""
DOMAINS=()
CREATE_ONLY=false
UPDATE_ONLY=false

usage() {
  cat <<'EOF'
cloud-dns.sh - Create a Cloudflare zone via the API and add basic DNS records.
Example: cloud-dns.sh <domain> <ip>

Creates a Cloudflare zone (full) and adds:
  - A record for the apex
  - CNAME for www → apex
  - CNAME for * → apex

Options:
  --domain NAME  Domain to provision (required if not given positionally)
  --create  Only create DNS records; error if a record already exists
  --update  Only update existing DNS records; error if a record is missing
  --account ACCOUNT_ID [CF_ACCOUNT_ID]  Cloudflare account ID
  --token TOKEN [CF_API_TOKEN]  Cloudflare account API token
  --key KEY [CF_API_KEY]  Cloudflare global API key
  --email EMAIL [CF_API_EMAIL]  Cloudflare API key email
  --auth token|key|auto [CF_AUTH]  Select which credential to use (default: auto)
  --auth-file PATH [CF_AUTH_FILE] (default: ~/.config/cloudflare/default.auth)  Auth file to load
  --help  Show this help

Notes:
  - Account API Token (recommended): CF_API_TOKEN=... [--token TOKEN]
  - Global API Key + email (user): CF_API_KEY=... CF_API_EMAIL=...
  - IPv4 must be publicly routable (RFC1918, link-local, loopback, and multicast are rejected).
EOF
}

while getopts ":-:" opt; do
  case "$opt" in
    -)
      case "${OPTARG}" in
        help) usage; exit 0 ;;
        create) CREATE_ONLY=true ;;
        update) UPDATE_ONLY=true ;;
        *)
          if cli_domain_opt "${OPTARG}" DOMAINS "${!OPTIND-}"; then
            :
          elif cli_cf_auth_opt "${OPTARG}" "${!OPTIND-}"; then
            :
          else
            usage; exit 1
          fi
          ;;
        *) usage; exit 1 ;;
      esac
      ;;
    \?) usage; exit 1 ;;
  esac
done
shift $((OPTIND-1))

if [ "$CREATE_ONLY" = true ] && [ "$UPDATE_ONLY" = true ]; then
  err "Use either --create or --update, not both."
fi

if [ ${#DOMAINS[@]} -eq 0 ]; then
  if [ $# -lt 2 ]; then usage; exit 1; fi
  DOMAINS+=("$1")
  shift
else
  if [ $# -lt 1 ]; then usage; exit 1; fi
fi
if [ $# -gt 1 ]; then
  err "Too many arguments. Provide <ip> only."
fi
finalize_domains DOMAINS || { usage; exit 1; }
if [ ${#DOMAINS[@]} -ne 1 ]; then
  err "Provide exactly one domain via --domain or a single positional domain"
fi

DOMAIN="${DOMAINS[0]}"
IP="$1"
validate_ip "$IP" || exit 1

load_cloudflare_auth
cf_init_auth

[ -n "${CF_ACCOUNT_ID:-}" ] || err "CF_ACCOUNT_ID required (env or --account)"
cf_require_auth
require_cmds curl jq

log "Ensuring zone exists: $DOMAIN"
zone_resp=$(cf_api_request GET "/zones?name=${DOMAIN}")
if [ "$(cf_api_success "$zone_resp")" != "true" ]; then
  err "Failed to query zones: $(cf_api_error_messages "$zone_resp")"
fi
zone_id=$(echo "$zone_resp" | jq -r '.result[0].id // empty')

if [ -z "$zone_id" ]; then
  log "Creating zone $DOMAIN"
  create_resp=$(cf_api_request POST "/zones" "{\"name\":\"$DOMAIN\",\"account\":{\"id\":\"$CF_ACCOUNT_ID\"},\"type\":\"full\"}")
  if [ "$(cf_api_success "$create_resp")" != "true" ]; then
    err "Zone creation failed: $(cf_api_error_messages "$create_resp")"
  fi
  zone_id=$(echo "$create_resp" | jq -r '.result.id')
  log "Zone created: $zone_id"
else
  log "Zone exists: $zone_id"
fi

add_dns() {
  local type="$1"
  local name="$2"
  local content="$3"
  local existing
  existing=$(cf_api_request GET "/zones/${zone_id}/dns_records?type=${type}&name=${name}")
  if [ "$(cf_api_success "$existing")" != "true" ]; then
    err "Failed to query DNS ${type} ${name}: $(cf_api_error_messages "$existing")"
  fi
  local existing_content existing_id
  existing_content=$(echo "$existing" | jq -r '.result[0].content // empty')
  existing_id=$(echo "$existing" | jq -r '.result[0].id // empty')
  local existing_count
  existing_count=$(echo "$existing" | jq -r '.result | length')
  if [ "$existing_count" -gt 1 ]; then
    if [ "$type" = "A" ]; then
      err "Multiple DNS ${type} ${name} records found; resolve duplicates before running"
    fi
    warn "Multiple DNS ${type} ${name} records found; using the first"
  fi
  local payload
  payload="{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$content\",\"ttl\":120,\"proxied\":true}"
  if [ -n "$existing_id" ]; then
    if [ "$CREATE_ONLY" = true ]; then
      err "DNS ${type} ${name} already exists; --create forbids updates"
    fi
    if [ "$existing_content" = "$content" ]; then
      log "DNS ${type} ${name} already set to ${content}"
      return
    fi
    log "Updating DNS ${type} ${name} -> ${content}"
    local update
    update=$(cf_api_request PUT "/zones/${zone_id}/dns_records/${existing_id}" "$payload")
    if [ "$(cf_api_success "$update")" != "true" ]; then
      err "Failed to update DNS record: $(cf_api_error_messages "$update")"
    fi
    return
  fi
  if [ "$UPDATE_ONLY" = true ]; then
    err "DNS ${type} ${name} missing; --update forbids create"
  fi
  log "Creating DNS ${type} ${name} -> ${content}"
  local create
  create=$(cf_api_request POST "/zones/${zone_id}/dns_records" "$payload")
  if [ "$(cf_api_success "$create")" != "true" ]; then
    err "Failed to create DNS record: $(cf_api_error_messages "$create")"
  fi
}

add_dns "A" "$DOMAIN" "$IP"
add_dns "CNAME" "www.${DOMAIN}" "$DOMAIN"
add_dns "CNAME" "*.${DOMAIN}" "$DOMAIN"

log "Done. Set nameservers at registrar to the ones Cloudflare assigned for this zone."
