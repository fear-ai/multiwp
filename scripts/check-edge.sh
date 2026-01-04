#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"
. "$SCRIPT_DIR/auth.sh"

HTTP_TIMEOUT="${HTTP_TIMEOUT:-10}"
API_CHECKS=false
AUTH_MODE=""

usage() {
    cat <<'USAGE'
Usage: check-edge.sh [OPTIONS] domain1 [domain2...]
Validates Cloudflare edge behavior (redirects, proxy headers, security headers).
Options:
  -h, --help         Show this help
  --timeout SECONDS  HTTP timeout for curl (default: 10)
  --api              Enable optional Cloudflare API checks (requires CF_ZONE_ID and either CF_API_TOKEN or CF_API_KEY+CF_API_EMAIL)
  --auth-file PATH   Auth file to load (default: ~/.config/cloudflare/auth)
USAGE
}

while getopts ":h-:" opt; do
    case "$opt" in
        h) usage; exit 0 ;;
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                api) API_CHECKS=true ;;
                timeout=*) HTTP_TIMEOUT="${OPTARG#*=}" ;;
                *)
                    if cf_auth_file "${OPTARG}"; then
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

[ $# -ge 1 ] || { usage; exit 1; }

require_cmd curl
require_cmd dig

if [ "$API_CHECKS" = true ]; then
    load_cloudflare_auth
    cf_require_auth "for --api"
    [ -n "${CF_ZONE_ID:-}" ] || err "CF_ZONE_ID required for --api"
    require_cmd jq
fi

if [ "$API_CHECKS" = true ] && [ $# -gt 1 ]; then
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
            "strict-transport-security"
            "x-content-type-options"
            "x-frame-options"
            "referrer-policy"
        )
        local optional_headers=(
            "x-xss-protection"
            "expect-ct"
        )

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
for domain in "$@"; do
    if ! check_domain "$domain"; then
        overall_ok=false
    fi
done

if [ "$overall_ok" != true ]; then
    exit 1
fi
