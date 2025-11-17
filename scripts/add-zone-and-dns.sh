#!/bin/bash
# add-zone-and-dns.sh - Create a Cloudflare zone and add basic DNS records
#
# Usage:
#   CF_API_TOKEN=... CF_ACCOUNT_ID=... ./add-zone-and-dns.sh example.com 203.0.113.10
#
# Requirements:
# - Cloudflare API token with permissions: Zone:Edit, Zone:DNS:Edit
# - curl, jq installed
#
# Behavior:
# - Creates the zone if it does not exist (in full mode).
# - Adds A records for apex and www pointing to the provided IP, proxied.
# - Adds an AAAA record if a third arg is provided.
# - Idempotent: skips creating records that already exist with matching content.

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: CF_API_TOKEN=... CF_ACCOUNT_ID=... $0 <domain> <ipv4> [ipv6]"
  exit 1
fi

DOMAIN="$1"
IPV4="$2"
IPV6="${3:-}"

CF_API_TOKEN="${CF_API_TOKEN:-}"
CF_ACCOUNT_ID="${CF_ACCOUNT_ID:-}"

if [ -z "$CF_API_TOKEN" ] || [ -z "$CF_ACCOUNT_ID" ]; then
  echo "Error: CF_API_TOKEN and CF_ACCOUNT_ID must be set in the environment"
  exit 1
fi

api() {
  local method="$1"
  local path="$2"
  shift 2
  curl -sS -X "$method" "https://api.cloudflare.com/client/v4${path}" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    "$@"
}

# Create zone if missing
echo "Ensuring zone exists: $DOMAIN"
zone_resp=$(api GET "/zones?name=${DOMAIN}")
zone_id=$(echo "$zone_resp" | jq -r '.result[0].id // empty')

if [ -z "$zone_id" ]; then
  echo "Creating zone $DOMAIN"
  create_resp=$(api POST "/zones" --data "{\"name\":\"$DOMAIN\",\"account\":{\"id\":\"$CF_ACCOUNT_ID\"},\"type\":\"full\"}")
  if [ "$(echo "$create_resp" | jq -r '.success')" != "true" ]; then
    echo "Zone creation failed: $create_resp"
    exit 1
  fi
  zone_id=$(echo "$create_resp" | jq -r '.result.id')
  echo "Zone created: $zone_id"
else
  echo "Zone exists: $zone_id"
fi

add_dns() {
  local type="$1"
  local name="$2"
  local content="$3"
  # Check existing
  existing=$(api GET "/zones/${zone_id}/dns_records?type=${type}&name=${name}")
  existing_content=$(echo "$existing" | jq -r '.result[0].content // empty')
  existing_id=$(echo "$existing" | jq -r '.result[0].id // empty')
  if [ "$existing_content" = "$content" ] && [ -n "$existing_id" ]; then
    echo "DNS ${type} ${name} already set to ${content}"
    return
  fi
  echo "Creating DNS ${type} ${name} -> ${content}"
  payload="{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$content\",\"ttl\":120,\"proxied\":true}"
  create=$(api POST "/zones/${zone_id}/dns_records" --data "$payload")
  if [ "$(echo "$create" | jq -r '.success')" != "true" ]; then
    echo "Failed to create DNS record: $create"
    exit 1
  fi
}

add_dns "A" "$DOMAIN" "$IPV4"
add_dns "A" "www.${DOMAIN}" "$IPV4"

if [ -n "$IPV6" ]; then
  add_dns "AAAA" "$DOMAIN" "$IPV6"
  add_dns "AAAA" "www.${DOMAIN}" "$IPV6"
fi

echo "Done. Set nameservers at registrar to the ones Cloudflare assigned for this zone."
