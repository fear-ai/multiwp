#!/bin/bash
# check-cf.sh - Inspect Cloudflare zone settings via the API.
# For options, environment variables, defaults see usage().
#
# Example: check-cf.sh [OPTIONS] <zone>

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/auth.sh"
. "$SCRIPTS_DIR/cli.sh"

CF_ZONE_CLI=""
CF_ZONE_ID_CLI=""
CF_ZONE_INPUT_RAW=""
CF_ZONE_API=""
CF_AUTH_CLI=""

expects=()
show_keys=()
raw=false
note() { echo "Note: $*" >&2; }

usage() {
    cat <<'EOF'
check-cf.sh - Inspect Cloudflare zone settings via the API.
Example: check-cf.sh [OPTIONS] <zone>

Options:
  -e key=val  Check that a setting matches the expected value (repeatable)
  -s key[,key]  Show only selected settings (repeatable)
  --raw  Print raw settings JSON
  --zone name [CF_ZONE]  Set CF_ZONE (zone apex, e.g., example.com)
  --zone-id id [CF_ZONE_ID]  Set CF_ZONE_ID

Auth options (choose one):
  - Account API Token (recommended): CF_API_TOKEN=... [--token TOKEN]
  - Global API Key + email (user): CF_API_KEY=... CF_API_EMAIL=... [--key KEY --email EMAIL]
  --auth token|key|auto [CF_AUTH]  Select which credential to use (default: auto)
  --auth-file PATH [CF_AUTH_FILE] (default: ~/.config/cloudflare/default.auth)  Auth file to load
  --token TOKEN [CF_API_TOKEN]  Set CF_API_TOKEN (account API token)
  --key KEY [CF_API_KEY]  Set CF_API_KEY (global API key)
  --email EMAIL [CF_API_EMAIL]  Set CF_API_EMAIL (global API key email)
  --help  Show this help

Notes:
  - Derived keys available for -s/-e: managed_add_security_headers, leaked_credential_checks.
EOF
}

while getopts ":e:s:-:" opt; do
    case "$opt" in
        e) expects+=("$OPTARG") ;;
        s)
            if ! parse_comma_list "${OPTARG-}" parts "-s list"; then
                usage; exit 1
            fi
            show_keys+=("${parts[@]}")
            ;;
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                raw) raw=true ;;
                zone=*) CF_ZONE_CLI="${OPTARG#*=}" ;;
                zone)
                    [ -n "${!OPTIND-}" ] || err "--zone requires a value"
                    CF_ZONE_CLI="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                zone-id=*) CF_ZONE_ID_CLI="${OPTARG#*=}" ;;
                zone-id)
                    [ -n "${!OPTIND-}" ] || err "--zone-id requires a value"
                    CF_ZONE_ID_CLI="${!OPTIND}"
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
    CF_ZONE_CLI="$1"
fi

require_cmds curl jq

if [ -z "${CF_AUTH_FILE-}" ]; then
    domain_lookup="${CF_ZONE_CLI:-${CF_ZONE-}}"
    if [ -n "$domain_lookup" ]; then
        cf_auth_from_csv "$domain_lookup" || true
    fi
fi

cf_init_auth
if [ -n "${CF_ZONE:-}" ]; then
    CF_ZONE_INPUT_RAW="$CF_ZONE"
    CF_ZONE=$(normalize_domain "$CF_ZONE_INPUT_RAW")
    validate_domain "$CF_ZONE" || exit 1
fi

cf_require_auth "for Cloudflare settings check"

if cf_has_zone_id && [ -n "${CF_ZONE:-}" ]; then
    note "Using CF_ZONE_ID and CF_ZONE; zone ID takes precedence for API calls"
fi
if ! cf_has_zone_id; then
    [ -n "${CF_ZONE:-}" ] || err "CF_ZONE or CF_ZONE_ID is required"
    cf_require_zone_id "for Cloudflare settings check" "$CF_ZONE"
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

# Managed headers (Cloudflare Managed Transforms)
managed_headers_json=$(cf_api_request GET "/zones/${CF_ZONE_ID}/managed_headers")
if [ "$(cf_api_success "$managed_headers_json")" != "true" ]; then
    warn "Failed to query managed headers: $(cf_api_error_messages "$managed_headers_json")"
else
    managed_headers_status=$(echo "$managed_headers_json" | jq -r '.result.managed_response_headers[]? | select(.id=="add_security_headers") | .enabled' | head -n 1)
    if [ -n "$managed_headers_status" ]; then
        settings_map=$(echo "$settings_map" | jq -c --arg v "$managed_headers_status" '. + {managed_add_security_headers: $v}')
    else
    warn "Managed headers response did not include expected key"
    fi
fi

# WAF leaked credential checks
leaked_json=$(cf_api_request GET "/zones/${CF_ZONE_ID}/leaked-credential-checks")
if [ "$(cf_api_success "$leaked_json")" != "true" ]; then
    warn "Failed to query leaked credential checks: $(cf_api_error_messages "$leaked_json")"
else
    leaked_status=$(echo "$leaked_json" | jq -r 'if .result.enabled == true then "true" elif .result.enabled == false then "false" else empty end')
    if [ -n "$leaked_status" ]; then
        settings_map=$(echo "$settings_map" | jq -c --arg v "$leaked_status" '. + {leaked_credential_checks: $v}')
    else
    warn "Leaked credential checks response did not include expected key"
    fi
fi

dns_types=("A" "CNAME")
for dns_type in "${dns_types[@]}"; do
    dns_json=$(cf_api_request GET "/zones/${CF_ZONE_ID}/dns_records?type=${dns_type}&per_page=100")
    if [ "$(cf_api_success "$dns_json")" != "true" ]; then
        warn "Failed to query DNS ${dns_type} records: $(cf_api_error_messages "$dns_json")"
        continue
    fi
    echo "DNS ${dns_type} records:"
    count=$(echo "$dns_json" | jq '.result | length')
    if [ "$count" -eq 0 ]; then
        echo "- <none>"
    else
        echo "$dns_json" | jq -r '.result[] | "- \(.name) -> \(.content) (proxied=\(.proxied), ttl=\(.ttl))"'
    fi
done

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
            echo "${key}=<unknown>"
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
            echo "FAIL: ${key} unknown (expected ${want})" >&2
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
