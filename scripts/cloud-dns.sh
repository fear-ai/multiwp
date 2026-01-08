#!/bin/bash
# cloud-dns.sh - Create a Cloudflare zone via the API and add basic DNS records.
# For options, environment variables, defaults see usage().
#
# Example: cloud-dns.sh <domain> <ipv4> [ipv6]

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/auth.sh"
. "$SCRIPTS_DIR/cli.sh"

# Optional built-in defaults (use for non-sensitive test environments; prefer env/flags otherwise)
CF_ACCOUNT_ID_DEFAULT=""
CF_API_TOKEN_DEFAULT=""
CF_API_EMAIL_DEFAULT=""
CF_API_KEY_DEFAULT=""

CF_ACCOUNT_ID_OVERRIDE=""
CF_API_TOKEN_OVERRIDE=""

usage() {
  cat <<'EOF'
cloud-dns.sh - Create a Cloudflare zone via the API and add basic DNS records.
Example: cloud-dns.sh <domain> <ipv4> [ipv6]

Creates a Cloudflare zone (full) and adds proxied A/AAAA for apex and www.

Auth options (choose one):
  - Account API Token (recommended): CF_API_TOKEN=... [--token TOKEN]
  - Global API Key + email (user): CF_API_KEY=... CF_API_EMAIL=...

Options:
  --account ACCOUNT_ID [CF_ACCOUNT_ID]  Cloudflare account ID
  --token TOKEN [CF_API_TOKEN]  Cloudflare account API token
  --key KEY [CF_API_KEY]  Cloudflare global API key
  --email EMAIL [CF_API_EMAIL]  Cloudflare API key email
  --auth-file PATH [CF_AUTH_FILE] (default: ~/.config/cloudflare/default.auth)  Auth file to load
  --help  Show this help
Notes:
  You may hardcode defaults in CF_API_TOKEN_DEFAULT / CF_API_KEY_DEFAULT / CF_API_EMAIL_DEFAULT / CF_ACCOUNT_ID_DEFAULT near the top of the script; env vars or flags override them.
EOF
}

while getopts ":-:" opt; do
  case "$opt" in
    -)
      case "${OPTARG}" in
        help) usage; exit 0 ;;
        *)
          if cli_cf_auth_opt "${OPTARG}" "${!OPTIND-}"; then
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

if [ $# -lt 2 ]; then usage; exit 1; fi

DOMAIN="$1"
IPV4="$2"

load_cloudflare_auth

# Defer env resolution until after defaults/overrides are applied to avoid set -u errors.
CF_ACCOUNT_ID_VAL="${CF_ACCOUNT_ID_OVERRIDE:-${CF_ACCOUNT_ID:-$CF_ACCOUNT_ID_DEFAULT}}"
CF_API_TOKEN_VAL="${CF_API_TOKEN_OVERRIDE:-${CF_API_TOKEN:-$CF_API_TOKEN_DEFAULT}}"
CF_API_EMAIL_VAL="${CF_API_EMAIL:-$CF_API_EMAIL_DEFAULT}"
CF_API_KEY_VAL="${CF_API_KEY:-$CF_API_KEY_DEFAULT}"

[ -n "$CF_ACCOUNT_ID_VAL" ] || err "CF_ACCOUNT_ID required (env or --account)"
CF_ACCOUNT_ID="$CF_ACCOUNT_ID_VAL"
CF_API_TOKEN="$CF_API_TOKEN_VAL"
CF_API_EMAIL="$CF_API_EMAIL_VAL"
CF_API_KEY="$CF_API_KEY_VAL"
cf_require_auth
require_cmd curl
require_cmd jq

log "Ensuring zone exists: $DOMAIN"
zone_resp=$(cf_api_request GET "/zones?name=${DOMAIN}")
zone_id=$(echo "$zone_resp" | jq -r '.result[0].id // empty')

if [ -z "$zone_id" ]; then
  log "Creating zone $DOMAIN"
  create_resp=$(cf_api_request POST "/zones" "{\"name\":\"$DOMAIN\",\"account\":{\"id\":\"$CF_ACCOUNT_ID_VAL\"},\"type\":\"full\"}")
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
add_dns "A" "www.${DOMAIN}" "$IPV4"

log "Done. Set nameservers at registrar to the ones Cloudflare assigned for this zone."
