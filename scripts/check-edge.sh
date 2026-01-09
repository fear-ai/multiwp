#!/bin/bash
# check-edge.sh - Validate Cloudflare edge behavior for domains.
# For options, environment variables, defaults see usage().
#
# Example: check-edge.sh [OPTIONS] domain1 [domain2...]

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/auth.sh"
. "$SCRIPTS_DIR/cli.sh"

HTTP_TIMEOUT="${HTTP_TIMEOUT:-10}"
API_CHECKS=false
AUTH_MODE=""
DOMAINS=()
HSTS_REQUIRED="${HSTS_REQUIRED-}"
HSTS_REQUIRED_CLI=""
AUTH_LOADED=false

usage() {
    cat <<'USAGE'
check-edge.sh - Validate Cloudflare edge behavior for domains.
Example: check-edge.sh [OPTIONS] domain1 [domain2...]

Options:
  --domain NAME  Domain to process (repeatable; positional also accepted)
  --http-timeout SECONDS [HTTP_TIMEOUT] (default: 10)  HTTP timeout for curl
  --hsts  Require Strict-Transport-Security header
  --api  Enable optional Cloudflare API checks (requires CF_ZONE_ID and either account API token CF_API_TOKEN or Global API Key + email CF_API_KEY+CF_API_EMAIL)
  --auth-file PATH [CF_AUTH_FILE] (default: ~/.config/cloudflare/default.auth)  Auth file to load
  --token TOKEN [CF_API_TOKEN]  Override CF_API_TOKEN (account API token)
  --key KEY [CF_API_KEY]  Override CF_API_KEY (global API key)
  --email EMAIL [CF_API_EMAIL]  Override CF_API_EMAIL (global API key email)
  --help  Show this help
USAGE
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                api) API_CHECKS=true ;;
                hsts) HSTS_REQUIRED_CLI=true ;;
                http-timeout=*) HTTP_TIMEOUT="${OPTARG#*=}" ;;
                http-timeout)
                    [ -n "${!OPTIND-}" ] || err "--http-timeout requires a value"
                    HTTP_TIMEOUT="${!OPTIND}"
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

for domain in "$@"; do
    DOMAINS+=("$domain")
done
finalize_domains DOMAINS || { usage; exit 1; }
[ ${#DOMAINS[@]} -ge 1 ] || { usage; exit 1; }

if [ -n "$HSTS_REQUIRED_CLI" ]; then
    HSTS_REQUIRED=true
elif [ -z "$HSTS_REQUIRED" ] && [ -n "${CF_AUTH_FILE-}" ]; then
    load_cloudflare_auth "$CF_AUTH_FILE"
    AUTH_LOADED=true
fi

case "${HSTS_REQUIRED-}" in
    '') HSTS_REQUIRED=false ;;
    true) HSTS_REQUIRED=true ;;
    false) HSTS_REQUIRED=false ;;
    *) err "HSTS_REQUIRED must be true or false" ;;
esac

require_cmd curl
require_cmd dig

if [ "$API_CHECKS" = true ]; then
    if [ "$AUTH_LOADED" = false ]; then
        load_cloudflare_auth
        AUTH_LOADED=true
    fi
    cf_require_auth "for --api"
    [ -n "${CF_ZONE_ID:-}" ] || err "CF_ZONE_ID required for --api"
    require_cmd jq
fi

if [ "$API_CHECKS" = true ] && [ ${#DOMAINS[@]} -gt 1 ]; then
    log "Warning: --api uses a single CF_ZONE_ID for all domains. Ensure it matches each domain."
fi

cf_get_setting() {
    local setting="$1"
    local response
    response=$(cf_api_request GET "/zones/$CF_ZONE_ID/settings/$setting") || return 1

    if [ "$(cf_api_success "$response")" != "true" ]; then
        return 1
    fi

    echo "$response" | jq -r '.result.value // empty'
}

check_domain() {
    local domain
    domain=$(tolower "$1")
    local ok=true

    echo ""
    log "Edge checks for: $domain"

    local a_records
    a_records=$(dig +short A "$domain" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    if [ -z "$a_records" ]; then
        echo "Error: DNS A records not found for $domain"
        ok=false
    else
        echo "DNS A: $a_records"
    fi

    local cname_records
    cname_records=$(dig +short CNAME "$domain" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    if [ -n "$cname_records" ]; then
        echo "DNS CNAME: $cname_records"
    fi

    local aaaa_records
    aaaa_records=$(dig +short AAAA "$domain" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    if [ -n "$aaaa_records" ]; then
        echo "DNS AAAA: $aaaa_records"
    fi

    local http_headers
    if ! http_headers=$(curl -sS --connect-timeout "$HTTP_TIMEOUT" --max-time "$HTTP_TIMEOUT" -I "http://$domain"); then
        echo "Error: HTTP request failed for http://$domain"
        ok=false
    else
        local http_status
        http_status=$(echo "$http_headers" | awk 'NR==1 {print $2}')
        local http_location
        http_location=$(echo "$http_headers" | awk -F': ' 'tolower($1)=="location" {print $2}' | tail -n 1 | tr -d '\r')

        if [[ "$http_status" =~ ^30(1|2|7|8)$ ]]; then
            if [[ "$http_location" =~ ^https:// ]]; then
                echo "HTTP redirect: $http_status -> $http_location"
            else
                echo "Error: HTTP redirect does not point to HTTPS (Location: $http_location)"
                ok=false
            fi
        else
            echo "Error: HTTP did not redirect to HTTPS (status: $http_status)"
            ok=false
        fi
    fi

    local https_headers
    if ! https_headers=$(curl -sS --connect-timeout "$HTTP_TIMEOUT" --max-time "$HTTP_TIMEOUT" -I "https://$domain"); then
        echo "Error: HTTPS request failed for https://$domain"
        ok=false
    else
        local cf_ray
        cf_ray=$(echo "$https_headers" | awk -F': ' 'tolower($1)=="cf-ray" {print $2}' | tail -n 1 | tr -d '\r')
        local server_header
        server_header=$(echo "$https_headers" | awk -F': ' 'tolower($1)=="server" {print $2}' | tail -n 1 | tr -d '\r')

        if [ -n "$cf_ray" ] || echo "$server_header" | grep -qi "cloudflare"; then
            echo "Cloudflare proxy detected"
        else
            echo "Warning: Cloudflare proxy headers not detected"
        fi

        local required_headers=(
            "x-content-type-options"
            "x-frame-options"
            "referrer-policy"
        )
        local optional_headers=(
            "x-xss-protection"
            "expect-ct"
        )
        if [ "$HSTS_REQUIRED" = true ]; then
            required_headers+=("strict-transport-security")
        fi

        local header
        for header in "${required_headers[@]}"; do
            if echo "$https_headers" | grep -qi "^${header}:"; then
                echo "Header present: ${header}"
            else
                echo "Error: Missing required header: ${header}"
                ok=false
            fi
        done

        for header in "${optional_headers[@]}"; do
            if echo "$https_headers" | grep -qi "^${header}:"; then
                echo "Header present: ${header}"
            else
                echo "Warning: Optional header not found: ${header}"
            fi
        done

        if [ "$HSTS_REQUIRED" = false ] && echo "$https_headers" | grep -qi "^strict-transport-security:"; then
            echo "Header present: strict-transport-security"
        fi
    fi

    if [ "$API_CHECKS" = true ]; then
        local ssl_mode
        if ssl_mode=$(cf_get_setting "ssl"); then
            if [ "$ssl_mode" = "strict" ]; then
                echo "Cloudflare SSL mode: strict"
            else
                echo "Error: Cloudflare SSL mode is '$ssl_mode' (expected 'strict')"
                ok=false
            fi
        else
            echo "Error: Cloudflare API check failed for SSL mode"
            ok=false
        fi

        local always_https
        if always_https=$(cf_get_setting "always_use_https"); then
            if [ "$always_https" = "on" ]; then
                echo "Cloudflare Always Use HTTPS: on"
            else
                echo "Error: Cloudflare Always Use HTTPS is '$always_https' (expected 'on')"
                ok=false
            fi
        else
            echo "Error: Cloudflare API check failed for Always Use HTTPS"
            ok=false
        fi
    fi

    if [ "$ok" = true ]; then
        echo "Edge checks passed for $domain"
        return 0
    fi

    echo "Edge checks failed for $domain"
    return 1
}

overall_ok=true
for domain in "${DOMAINS[@]}"; do
    if ! check_domain "$domain"; then
        overall_ok=false
    fi
done

if [ "$overall_ok" != true ]; then
    exit 1
fi
