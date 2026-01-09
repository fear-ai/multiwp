#!/bin/bash
# cf-check.sh - Inspect Cloudflare zone settings via the API.
# For options, environment variables, defaults see usage().
#
# Example: cf-check.sh [OPTIONS] <zone>

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/auth.sh"
. "$SCRIPTS_DIR/cli.sh"

CF_ZONE_OVERRIDE=""
CF_ZONE_ID_OVERRIDE=""
CF_ZONE_INPUT_RAW=""
CF_ZONE_API=""

expects=()
show_keys=()
raw=false
note() { echo "Note: $*" >&2; }

usage() {
    cat <<'EOF'
cf-check.sh - Inspect Cloudflare zone settings via the API.
Example: cf-check.sh [OPTIONS] <zone>

Options:
  -e key=val  Check that a setting matches the expected value (repeatable)
  -s key[,key]  Show only selected settings (repeatable)
  --raw  Print raw settings JSON
  --zone name [CF_ZONE]  Override CF_ZONE (zone apex, e.g., example.com)
  --zone-id id [CF_ZONE_ID]  Override CF_ZONE_ID

Auth options (choose one):
  - Account API Token (recommended): CF_API_TOKEN=... [--token TOKEN]
  - Global API Key + email (user): CF_API_KEY=... CF_API_EMAIL=... [--key KEY --email EMAIL]
  --auth-file PATH [CF_AUTH_FILE] (default: ~/.config/cloudflare/default.auth)  Auth file to load
  --token TOKEN [CF_API_TOKEN]  Override CF_API_TOKEN (account API token)
  --key KEY [CF_API_KEY]  Override CF_API_KEY (global API key)
  --email EMAIL [CF_API_EMAIL]  Override CF_API_EMAIL (global API key email)
  --help  Show this help
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
                zone=*) CF_ZONE_OVERRIDE="${OPTARG#*=}" ;;
                zone)
                    [ -n "${!OPTIND-}" ] || err "--zone requires a value"
                    CF_ZONE_OVERRIDE="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                zone-id=*) CF_ZONE_ID_OVERRIDE="${OPTARG#*=}" ;;
                zone-id)
                    [ -n "${!OPTIND-}" ] || err "--zone-id requires a value"
                    CF_ZONE_ID_OVERRIDE="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                *)
                    if cli_cf_auth_opt "${OPTARG}" "${!OPTIND-}"; then
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
    CF_ZONE_OVERRIDE="$1"
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
if [ -n "$CF_ZONE_OVERRIDE" ]; then
    CF_ZONE="$CF_ZONE_OVERRIDE"
fi
if [ -n "${CF_ZONE:-}" ]; then
    CF_ZONE_INPUT_RAW="$CF_ZONE"
    CF_ZONE=$(normalize_domain "$CF_ZONE_INPUT_RAW")
    validate_domain "$CF_ZONE" || exit 1
fi

cf_require_auth "for Cloudflare settings check"

if [ -n "${CF_ZONE_ID:-}" ] && [ -n "${CF_ZONE:-}" ]; then
    note "Using CF_ZONE_ID and CF_ZONE; zone ID takes precedence for API calls"
fi
if [ -z "${CF_ZONE_ID:-}" ]; then
    [ -n "${CF_ZONE:-}" ] || err "CF_ZONE or CF_ZONE_ID is required"
    note "Resolving zone ID from zone name: $CF_ZONE"
    zone_resp=$(cf_api_request GET "/zones?name=${CF_ZONE}&status=active")
    if [ "$(cf_api_success "$zone_resp")" != "true" ]; then
        err "Failed to query zones: $(cf_api_error_messages "$zone_resp")"
    fi
    CF_ZONE_ID=$(echo "$zone_resp" | jq -r '.result[0].id // empty')
    [ -n "$CF_ZONE_ID" ] || err "No active zone found for name: $CF_ZONE"
    CF_ZONE_API=$(echo "$zone_resp" | jq -r '.result[0].name // empty')
    if [ -n "$CF_ZONE_API" ]; then
        CF_ZONE="$CF_ZONE_API"
    fi
fi

if [ -z "${CF_ZONE:-}" ]; then
    note "Resolving zone name from zone ID: $CF_ZONE_ID"
    zone_detail=$(cf_api_request GET "/zones/${CF_ZONE_ID}")
    if [ "$(cf_api_success "$zone_detail")" = "true" ]; then
        CF_ZONE_API=$(echo "$zone_detail" | jq -r '.result.name // empty')
        CF_ZONE="$CF_ZONE_API"
    fi
elif [ -z "$CF_ZONE_API" ]; then
    note "Confirming zone name for zone ID: $CF_ZONE_ID"
    zone_detail=$(cf_api_request GET "/zones/${CF_ZONE_ID}")
    if [ "$(cf_api_success "$zone_detail")" = "true" ]; then
        CF_ZONE_API=$(echo "$zone_detail" | jq -r '.result.name // empty')
    fi
fi

if [ -n "$CF_ZONE_INPUT_RAW" ] && [ -n "$CF_ZONE_API" ] && [ "$CF_ZONE_INPUT_RAW" != "$CF_ZONE_API" ]; then
    note "Zone name differs from Cloudflare: input='$CF_ZONE_INPUT_RAW' api='$CF_ZONE_API' (case-sensitive)"
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

printf "Zone: %s (%s)\n" "${CF_ZONE:-unknown}" "$CF_ZONE_ID"

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
