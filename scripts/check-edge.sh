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
CF_AUTH_CLI=""

usage() {
    cat <<'USAGE'
check-edge.sh - Validate Cloudflare edge behavior for domains.
Example: check-edge.sh [OPTIONS] domain1 [domain2...]

Options:
  --domain NAME  Domain to process (repeatable; positional also accepted)
$(cli_usage_http_timeout)
$(cli_usage_hsts)
  --api  Enable Cloudflare API checks (optional; requires CF_ZONE_ID and either account API token CF_API_TOKEN or Global API Key + email CF_API_KEY+CF_API_EMAIL)
  --auth token|key|auto [CF_AUTH]  Select which credential to use (default: auto)
  --auth-file PATH [CF_AUTH_FILE] (default: ~/.config/cloudflare/default.auth)  Auth file to load
  --token TOKEN [CF_API_TOKEN]  Set CF_API_TOKEN (account API token)
  --key KEY [CF_API_KEY]  Set CF_API_KEY (global API key)
  --email EMAIL [CF_API_EMAIL]  Set CF_API_EMAIL (global API key email)
  --help  Show this help

Notes:
  - Assumes apex is canonical. Expected behavior: http://<apex> -> https://<apex> (301), http://www -> https://www or https://<apex> (301), and https://www -> https://<apex> (301).
  - Validates WordPress asset markers (/wp-content or /wp-includes) on the canonical HTTPS response.
  - Cloudflare API checks run only when --api is provided.
  - Accepts a www A record when Cloudflare CNAME flattening hides the CNAME.
  - Redirect-only domains (from domains.csv) skip HTTPS and Cloudflare API checks.
USAGE
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                api) API_CHECKS=true ;;
                hsts|hsts=*)
                    if cli_hsts_opt "${OPTARG}" HSTS_REQUIRED_CLI "${!OPTIND-}"; then
                        :
                    else
                        usage; exit 1
                    fi
                    ;;
                http-timeout|http-timeout=*)
                    if cli_http_timeout_opt "${OPTARG}" HTTP_TIMEOUT "${!OPTIND-}"; then
                        :
                    else
                        usage; exit 1
                    fi
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

if [ -n "${HSTS_REQUIRED_CLI-}" ]; then
    HSTS_REQUIRED="$HSTS_REQUIRED_CLI"
elif [ -z "${HSTS_REQUIRED-}" ] && [ -n "${CF_AUTH_FILE-}" ]; then
    cf_init_auth "$CF_AUTH_FILE"
    AUTH_LOADED=true
fi

if [ -n "${HSTS_REQUIRED-}" ]; then
    if ! HSTS_REQUIRED="$(parse_bool "$HSTS_REQUIRED")"; then
        err "HSTS_REQUIRED must be true or false"
    fi
else
    HSTS_REQUIRED=false
fi

require_cmds curl dig
load_dns_redirects || { usage; exit 1; }

if [ "$API_CHECKS" = true ]; then
    if [ "$AUTH_LOADED" = false ]; then
        if [ -n "${CF_AUTH_FILE-}" ]; then
            cf_init_auth "$CF_AUTH_FILE"
        else
            cf_init_auth
        fi
        AUTH_LOADED=true
    fi
    cf_require_auth "for --api"
    [ -n "${CF_ZONE_ID:-}" ] || err "CF_ZONE_ID required for --api"
    require_cmd jq
fi

if [ "$API_CHECKS" = true ] && [ ${#DOMAINS[@]} -gt 1 ]; then
    warn "--api uses a single CF_ZONE_ID for all domains. Ensure it matches each domain."
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
    local canonical_domain="${domain#www.}"
    local www_domain="www.${canonical_domain}"
    local ok=true
    local redirect_only=false
    local redirect_target=""

    if is_redirect_domain "$domain" || is_redirect_domain "$canonical_domain"; then
        redirect_only=true
    fi

    echo ""
    log "Edge checks for: $domain (canonical: $canonical_domain)"
    if [ "$redirect_only" = true ]; then
        log "Redirect-only domain; skipping HTTPS and Cloudflare API checks"
        redirect_target=$(redirect_target "$domain")
        if [ -z "$redirect_target" ]; then
            redirect_target=$(redirect_target "$canonical_domain")
        fi
        if [ -z "$redirect_target" ]; then
            warn "Redirect target not set; using https://$canonical_domain"
            redirect_target="https://$canonical_domain"
        fi
    fi

    fetch_headers() {
        local url="$1"
        curl -sS --connect-timeout "$HTTP_TIMEOUT" --max-time "$HTTP_TIMEOUT" -I "$url"
    }

    check_redirect() {
        local url="$1"
        local expected_prefix="$2"
        local alt_prefix="${3-}"
        local label="$4"
        local headers
        if ! headers=$(fetch_headers "$url"); then
            fail "HTTP request failed for $url"
            ok=false
            return
        fi
        local status
        status=$(echo "$headers" | awk 'NR==1 {print $2}')
        local location
        location=$(echo "$headers" | awk -F': ' 'tolower($1)=="location" {print $2}' | tail -n 1 | tr -d '\r')
        if [ "$status" = "301" ]; then
            if [[ "$location" == "${expected_prefix}"* ]] || { [ -n "$alt_prefix" ] && [[ "$location" == "${alt_prefix}"* ]]; }; then
                echo "${label}: 301 -> ${location}"
            else
                fail "${label} redirect target mismatch (Location: $location)"
                ok=false
            fi
        else
            fail "${label} expected 301 (status: ${status})"
            ok=false
        fi
    }

    local a_records
    a_records=$(dig +short A "$canonical_domain" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    if [ -z "$a_records" ]; then
        fail "DNS A records not found for $canonical_domain"
        ok=false
    else
        echo "DNS A: $a_records"
    fi

    local cname_records
    cname_records=$(dig +short CNAME "$www_domain" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    if [ -n "$cname_records" ]; then
        echo "DNS CNAME (www): $cname_records"
    else
        local www_a_records
        www_a_records=$(dig +short A "$www_domain" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
        if [ -n "$www_a_records" ]; then
            echo "DNS A (www): $www_a_records"
        else
            fail "DNS CNAME or A record not found for $www_domain"
            ok=false
        fi
    fi

    local wildcard_cname
    wildcard_cname=$(dig +short CNAME "*.${canonical_domain}" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    if [ -n "$wildcard_cname" ]; then
        echo "DNS CNAME (*): $wildcard_cname"
    fi

    local aaaa_records
    aaaa_records=$(dig +short AAAA "$canonical_domain" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    if [ -n "$aaaa_records" ]; then
        echo "DNS AAAA: $aaaa_records"
    fi

    if [ "$redirect_only" = true ]; then
        check_redirect "http://$canonical_domain" "$redirect_target" "" "HTTP apex"
        check_redirect "http://$www_domain" "$redirect_target" "" "HTTP www"
    else
        check_redirect "http://$canonical_domain" "https://$canonical_domain" "" "HTTP apex"
        check_redirect "http://$www_domain" "https://$canonical_domain" "https://$www_domain" "HTTP www"
    fi
    if [ "$redirect_only" != true ]; then
        check_redirect "https://$www_domain" "https://$canonical_domain" "" "HTTPS www"
    fi

    if [ "$redirect_only" != true ]; then
        local https_headers
        if ! https_headers=$(fetch_headers "https://$canonical_domain"); then
            fail "HTTPS request failed for https://$canonical_domain"
            ok=false
        else
            local https_status
            https_status=$(echo "$https_headers" | awk 'NR==1 {print $2}')
            if [ "$https_status" = "200" ]; then
                echo "HTTPS apex status: 200"
            else
                fail "HTTPS apex expected 200 (status: ${https_status})"
                ok=false
            fi

            local cf_ray
            cf_ray=$(echo "$https_headers" | awk -F': ' 'tolower($1)=="cf-ray" {print $2}' | tail -n 1 | tr -d '\r')
            local server_header
            server_header=$(echo "$https_headers" | awk -F': ' 'tolower($1)=="server" {print $2}' | tail -n 1 | tr -d '\r')

            if [ -n "$cf_ray" ] || echo "$server_header" | grep -qi "cloudflare"; then
                echo "Cloudflare proxy detected"
            else
                warn "Cloudflare proxy headers not detected"
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
                    fail "Missing required header: ${header}"
                    ok=false
                fi
            done

            for header in "${optional_headers[@]}"; do
                if echo "$https_headers" | grep -qi "^${header}:"; then
                    echo "Header present: ${header}"
                else
                    warn "Optional header not found: ${header}"
                fi
            done

            if [ "$HSTS_REQUIRED" = false ] && echo "$https_headers" | grep -qi "^strict-transport-security:"; then
                echo "Header present: strict-transport-security"
            fi
        fi
    fi

    if [ "$redirect_only" != true ]; then
        local html_body
        if ! html_body=$(curl -sS --compressed --connect-timeout "$HTTP_TIMEOUT" --max-time "$HTTP_TIMEOUT" -L "https://$canonical_domain"); then
            fail "HTTPS body fetch failed for https://$canonical_domain"
            ok=false
        else
            if grep -qiE '/wp-(content|includes)/' <<<"$html_body"; then
                echo "WordPress asset markers present"
            else
                fail "WordPress asset markers not found"
                ok=false
            fi
        fi
    fi

    if [ "$API_CHECKS" = true ] && [ "$redirect_only" != true ]; then
        local ssl_mode
        if ssl_mode=$(cf_get_setting "ssl"); then
            if [ "$ssl_mode" = "strict" ]; then
                echo "Cloudflare SSL mode: strict"
            else
                fail "Cloudflare SSL mode is '$ssl_mode' (expected 'strict')"
                ok=false
            fi
        else
            fail "Cloudflare API check failed for SSL mode"
            ok=false
        fi

        local always_https
        if always_https=$(cf_get_setting "always_use_https"); then
            if [ "$always_https" = "on" ]; then
                echo "Cloudflare Always Use HTTPS: on"
            else
                fail "Cloudflare Always Use HTTPS is '$always_https' (expected 'on')"
                ok=false
            fi
        else
            fail "Cloudflare API check failed for Always Use HTTPS"
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
