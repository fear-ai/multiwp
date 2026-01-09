#!/bin/bash
# cloud-dns.sh - Create a Cloudflare zone via the API and add basic DNS records.
# For options, environment variables, defaults see usage().
#
# Example: cloud-dns.sh <domain> <ipv4>

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/auth.sh"
. "$SCRIPTS_DIR/cli.sh"

CF_ACCOUNT_ID_OVERRIDE=""
CF_API_TOKEN_OVERRIDE=""
CF_API_EMAIL_OVERRIDE=""
CF_API_KEY_OVERRIDE=""
DOMAINS=()

usage() {
  cat <<'EOF'
cloud-dns.sh - Create a Cloudflare zone via the API and add basic DNS records.
Example: cloud-dns.sh <domain> <ipv4>

Creates a Cloudflare zone (full) and adds:
  - A record for the apex
  - CNAME for www → apex
  - CNAME for * → apex

Options:
  --domain NAME  Domain to provision (required if not given positionally)
  --account ACCOUNT_ID [CF_ACCOUNT_ID]  Cloudflare account ID
  --token TOKEN [CF_API_TOKEN]  Cloudflare account API token
  --key KEY [CF_API_KEY]  Cloudflare global API key
  --email EMAIL [CF_API_EMAIL]  Cloudflare API key email
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


if [ ${#DOMAINS[@]} -eq 0 ]; then
  if [ $# -lt 2 ]; then usage; exit 1; fi
  DOMAINS+=("$1")
  shift
else
  if [ $# -lt 1 ]; then usage; exit 1; fi
fi
if [ $# -gt 1 ]; then
  err "Too many arguments. Provide <ipv4> only."
fi
finalize_domains DOMAINS || { usage; exit 1; }
if [ ${#DOMAINS[@]} -ne 1 ]; then
  err "Provide exactly one domain via --domain or a single positional domain"
fi

DOMAIN="${DOMAINS[0]}"
IPV4="$1"
validate_ipv4 "$IPV4" || exit 1

load_cloudflare_auth

if [ -n "${CF_ACCOUNT_ID_OVERRIDE:-}" ]; then
  CF_ACCOUNT_ID="$CF_ACCOUNT_ID_OVERRIDE"
fi
if [ -n "${CF_API_TOKEN_OVERRIDE:-}" ]; then
  CF_API_TOKEN="$CF_API_TOKEN_OVERRIDE"
fi
if [ -n "${CF_API_EMAIL_OVERRIDE:-}" ]; then
  CF_API_EMAIL="$CF_API_EMAIL_OVERRIDE"
fi
if [ -n "${CF_API_KEY_OVERRIDE:-}" ]; then
  CF_API_KEY="$CF_API_KEY_OVERRIDE"
fi

[ -n "${CF_ACCOUNT_ID:-}" ] || err "CF_ACCOUNT_ID required (env or --account)"
cf_require_auth
require_cmd curl
require_cmd jq

log "Ensuring zone exists: $DOMAIN"
zone_resp=$(cf_api_request GET "/zones?name=${DOMAIN}")
zone_id=$(echo "$zone_resp" | jq -r '.result[0].id // empty')

if [ -z "$zone_id" ]; then
  log "Creating zone $DOMAIN"
  create_resp=$(cf_api_request POST "/zones" "{\"name\":\"$DOMAIN\",\"account\":{\"id\":\"$CF_ACCOUNT_ID\"},\"type\":\"full\"}")
  [ "$(echo "$create_resp" | jq -r '.success')" = "true" ] || err "Zone creation failed: $create_resp"
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
  local existing_content existing_id
  existing_content=$(echo "$existing" | jq -r '.result[0].content // empty')
  existing_id=$(echo "$existing" | jq -r '.result[0].id // empty')
  if [ "$existing_content" = "$content" ] && [ -n "$existing_id" ]; then
    log "DNS ${type} ${name} already set to ${content}"
    return
  fi
  log "Creating DNS ${type} ${name} -> ${content}"
  local payload
  payload="{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$content\",\"ttl\":120,\"proxied\":true}"
  local create
  create=$(cf_api_request POST "/zones/${zone_id}/dns_records" "$payload")
  [ "$(echo "$create" | jq -r '.success')" = "true" ] || err "Failed to create DNS record: $create"
}

add_dns "A" "$DOMAIN" "$IPV4"
add_dns "CNAME" "www.${DOMAIN}" "$DOMAIN"
add_dns "CNAME" "*.${DOMAIN}" "$DOMAIN"

log "Done. Set nameservers at registrar to the ones Cloudflare assigned for this zone."
