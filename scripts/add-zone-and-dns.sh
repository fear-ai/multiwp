#!/bin/bash
# add-zone-and-dns.sh - Create a Cloudflare zone and add basic DNS records
#
# Usage:
#   CF_API_TOKEN=... CF_ACCOUNT_ID=... ./add-zone-and-dns.sh example.com 203.0.113.10 [2001:db8::1]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"

usage() {
  cat <<'EOF'
Usage: CF_API_TOKEN=... CF_ACCOUNT_ID=... add-zone-and-dns.sh <domain> <ipv4> [ipv6]
Creates a Cloudflare zone (full) and adds proxied A/AAAA for apex and www.
Options:
  -h, --help             Show this help
  --token TOKEN          Cloudflare API token (overrides CF_API_TOKEN env)
  --account ACCOUNT_ID   Cloudflare account ID (overrides CF_ACCOUNT_ID env)
EOF
}

CF_API_TOKEN_VAL="${CF_API_TOKEN:-}"
CF_ACCOUNT_ID_VAL="${CF_ACCOUNT_ID:-}"

while getopts ":h-:" opt; do
  case "$opt" in
    h) usage; exit 0 ;;
    -)
      case "${OPTARG}" in
        help) usage; exit 0 ;;
        token=*) CF_API_TOKEN_VAL="${OPTARG#*=}" ;;
        account=*) CF_ACCOUNT_ID_VAL="${OPTARG#*=}" ;;
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
IPV6="${3:-}"

[ -n "$CF_API_TOKEN_VAL" ] || err "CF_API_TOKEN required (env or --token)"
[ -n "$CF_ACCOUNT_ID_VAL" ] || err "CF_ACCOUNT_ID required (env or --account)"
require_cmd curl
require_cmd jq

api() {
  local method="$1"
  local path="$2"
  shift 2
  curl -sS -X "$method" "$CF_API_BASE${path}" \
    -H "Authorization: Bearer $CF_API_TOKEN_VAL" \
    -H "Content-Type: application/json" \
    "$@"
}

log "Ensuring zone exists: $DOMAIN"
zone_resp=$(api GET "/zones?name=${DOMAIN}")
zone_id=$(echo "$zone_resp" | jq -r '.result[0].id // empty')

if [ -z "$zone_id" ]; then
  log "Creating zone $DOMAIN"
  create_resp=$(api POST "/zones" --data "{\"name\":\"$DOMAIN\",\"account\":{\"id\":\"$CF_ACCOUNT_ID_VAL\"},\"type\":\"full\"}")
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
  existing=$(api GET "/zones/${zone_id}/dns_records?type=${type}&name=${name}")
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
  create=$(api POST "/zones/${zone_id}/dns_records" --data "$payload")
  [ "$(echo "$create" | jq -r '.success')" = "true" ] || err "Failed to create DNS record: $create"
}

add_dns "A" "$DOMAIN" "$IPV4"
add_dns "A" "www.${DOMAIN}" "$IPV4"

if [ -n "$IPV6" ]; then
  add_dns "AAAA" "$DOMAIN" "$IPV6"
  add_dns "AAAA" "www.${DOMAIN}" "$IPV6"
fi

log "Done. Set nameservers at registrar to the ones Cloudflare assigned for this zone."
