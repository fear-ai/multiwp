#!/bin/bash
# cf-check.sh - Inspect Cloudflare zone settings via API
#
# Usage:
#   CF_API_TOKEN=... cf-check.sh [OPTIONS] <zone>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"
. "$SCRIPT_DIR/auth.sh"

CF_ZONE_NAME_OVERRIDE=""
CF_ZONE_ID_OVERRIDE=""

expects=()
show_keys=()
raw=false

usage() {
    cat <<'EOF'
Usage: cf-check.sh [OPTIONS] <zone>
Inspect Cloudflare zone settings via the API and optionally validate expected values.

Auth options (choose one):
  - API Token (recommended): CF_API_TOKEN=... [--token TOKEN]
  - Global API Key + email : CF_API_KEY=... CF_API_EMAIL=... [--key KEY --email EMAIL]

Options:
  --help                 Show this help
  -e key=val             Check that a setting matches the expected value (repeatable)
  -s key[,key]           Show only selected settings (repeatable)
  --raw                  Print raw settings JSON
  --zone name            Override CF_ZONE_NAME
  --zone-id id           Override CF_ZONE_ID
  --auth-file PATH       Auth file to load (default: ~/.config/cloudflare/default.auth)
  --token TOKEN          Override CF_API_TOKEN
  --key KEY              Override CF_API_KEY
  --email EMAIL          Override CF_API_EMAIL
EOF
}

while getopts ":e:s-:" opt; do
    case "$opt" in
        e) expects+=("$OPTARG") ;;
        s)
            IFS=',' read -r -a parts <<<"$OPTARG"
            for p in "${parts[@]}"; do
                p="${p#"${p%%[![:space:]]*}"}"
                p="${p%"${p##*[![:space:]]}"}"
                [ -n "$p" ] && show_keys+=("$p")
            done
            ;;
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                raw) raw=true ;;
                zone=*) CF_ZONE_NAME_OVERRIDE="${OPTARG#*=}" ;;
                zone)
                    [ -n "${!OPTIND-}" ] || err "--zone requires a value"
                    CF_ZONE_NAME_OVERRIDE="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                zone-id=*) CF_ZONE_ID_OVERRIDE="${OPTARG#*=}" ;;
                zone-id)
                    [ -n "${!OPTIND-}" ] || err "--zone-id requires a value"
                    CF_ZONE_ID_OVERRIDE="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                *)
                    if cf_auth_file "${OPTARG}"; then
                        :
                    elif cf_auth_opt "${OPTARG}"; then
                        :
                    else
                        usage; exit 1
                    fi
                    ;;
            esac
            ;;
        \?) usage; exit 1 ;;
        :) err "Option -$OPTARG requires an argument" ;;
    esac
done
shift $((OPTIND-1))

if [ $# -gt 1 ]; then
    err "Too many arguments. Provide a single zone name, or use --zone/--zone-id."
fi
if [ $# -eq 1 ]; then
    CF_ZONE_NAME_OVERRIDE="$1"
fi

require_cmd curl
require_cmd jq

load_cloudflare_auth

if [ -n "${CF_API_TOKEN_OVERRIDE:-}" ]; then
    CF_API_TOKEN="$CF_API_TOKEN_OVERRIDE"
fi
if [ -n "${CF_API_EMAIL_OVERRIDE:-}" ]; then
    CF_API_EMAIL="$CF_API_EMAIL_OVERRIDE"
fi
if [ -n "${CF_API_KEY_OVERRIDE:-}" ]; then
    CF_API_KEY="$CF_API_KEY_OVERRIDE"
fi
if [ -n "$CF_ZONE_ID_OVERRIDE" ]; then
    CF_ZONE_ID="$CF_ZONE_ID_OVERRIDE"
fi
if [ -n "$CF_ZONE_NAME_OVERRIDE" ]; then
    CF_ZONE_NAME="$CF_ZONE_NAME_OVERRIDE"
fi

cf_require_auth "for Cloudflare settings check"

if [ -z "${CF_ZONE_ID:-}" ]; then
    [ -n "${CF_ZONE_NAME:-}" ] || err "CF_ZONE_NAME or CF_ZONE_ID is required"
    zone_resp=$(cf_api_request GET "/zones?name=${CF_ZONE_NAME}&status=active")
    if [ "$(cf_api_success "$zone_resp")" != "true" ]; then
        err "Failed to query zones: $(cf_api_error_messages "$zone_resp")"
    fi
    CF_ZONE_ID=$(echo "$zone_resp" | jq -r '.result[0].id // empty')
    [ -n "$CF_ZONE_ID" ] || err "No active zone found for name: $CF_ZONE_NAME"
fi

if [ -z "${CF_ZONE_NAME:-}" ]; then
    zone_detail=$(cf_api_request GET "/zones/${CF_ZONE_ID}")
    if [ "$(cf_api_success "$zone_detail")" = "true" ]; then
        CF_ZONE_NAME=$(echo "$zone_detail" | jq -r '.result.name // empty')
    fi
fi

settings_json=$(cf_api_request GET "/zones/${CF_ZONE_ID}/settings")
if [ "$(cf_api_success "$settings_json")" != "true" ]; then
    err "Failed to query zone settings: $(cf_api_error_messages "$settings_json")"
fi

if [ "$raw" = true ]; then
    echo "$settings_json"
    exit 0
fi

settings_map=$(echo "$settings_json" | jq -c '.result | map({(.id): .value}) | add')

printf "Zone: %s (%s)\n" "${CF_ZONE_NAME:-unknown}" "$CF_ZONE_ID"

if [ "${#show_keys[@]}" -eq 0 ]; then
    if command -v sort >/dev/null 2>&1; then
        echo "$settings_map" | jq -r 'to_entries[] | "\(.key)=\(.value)"' | sort
    else
        echo "$settings_map" | jq -r 'to_entries[] | "\(.key)=\(.value)"'
    fi
else
    for key in "${show_keys[@]}"; do
        val=$(echo "$settings_map" | jq -r --arg k "$key" '.[$k] // empty')
        if [ -z "$val" ]; then
            echo "${key}=<missing>"
        else
            echo "${key}=${val}"
        fi
    done
fi

if [ "${#expects[@]}" -gt 0 ]; then
    failures=0
    for exp in "${expects[@]}"; do
        key="${exp%%=*}"
        want="${exp#*=}"
        got=$(echo "$settings_map" | jq -r --arg k "$key" '.[$k] // empty')
        if [ -z "$got" ]; then
            echo "FAIL: ${key} missing (expected ${want})" >&2
            failures=$((failures + 1))
        elif [ "$got" != "$want" ]; then
            echo "FAIL: ${key}=${got} (expected ${want})" >&2
            failures=$((failures + 1))
        else
            echo "PASS: ${key}=${got}"
        fi
    done
    if [ "$failures" -gt 0 ]; then
        exit 2
    fi
fi
