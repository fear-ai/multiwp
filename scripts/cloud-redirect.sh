#!/bin/bash
# cloud-redirect.sh - Ensure Cloudflare redirect rules for domains.
# For options, environment variables, defaults see usage().
#
# Example: cloud-redirect.sh --domain example.com --redirect-url https://alternat.info/

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/auth.sh"
. "$SCRIPTS_DIR/cli.sh"

DOMAINS=()
REDIRECT_URL="${REDIRECT_URL-}"
DOMAINS_FILE="${DOMAINS_FILE:-$ROOT_DIR/domains.csv}"
DRY_RUN=false
DATASTORE_DATE="${DATASTORE_DATE-}"
RECORD_UPDATES=true
RECORD_DOWNGRADE=false

usage() {
    cat <<EOF
cloud-redirect.sh - Ensure Cloudflare redirect rules for domains.
Example: cloud-redirect.sh --domain example.com --redirect-url https://alternat.info/

Options:
$(cli_usage_domain)
  --redirect-url URL [REDIRECT_URL]  Redirect target URL (defaults to domains.csv redirect_url)
  --domains-file PATH [DOMAINS_FILE] (default: ./domains.csv)  Inventory CSV path
  --dry-run  Show planned changes without API writes
$(cli_usage_date)
  --norecord  Skip domains.csv updates
  --downgrade  Allow status downgrades in domains.csv (overrides default)

Auth options:
  --auth token|key|auto [CF_AUTH]  Select which credential to use (default: auto)
  --auth-file PATH [CF_AUTH_FILE] (default: ~/.config/cloudflare/default.auth)  Auth file to load
  --token TOKEN [CF_API_TOKEN]  Set CF_API_TOKEN (account API token)
  --key KEY [CF_API_KEY]  Set CF_API_KEY (global API key)
  --email EMAIL [CF_API_EMAIL]  Set CF_API_EMAIL (global API key email)
  --account ID [CF_ACCOUNT_ID]  Cloudflare account ID (optional)
  --account-name NAME [CF_ACCOUNT_NAME]  Cloudflare account name (optional)
  --help  Show this help

Notes:
  - If no domains are provided, this script uses redirect domains from domains.csv.
  - Redirect rules are applied via the Cloudflare rulesets API (http_request_dynamic_redirect phase).
  - Existing redirect rules for the domain are updated; otherwise a new rule is appended.
  - Domains with site_type none, ignore, or worker are skipped entirely.
EOF
}

load_redirect_domains() {
    DOMAINS=()
    load_dns_redirects
    if [ ${#DNS_REDIRECT_LIST[@]} -eq 0 ]; then
        err "No redirect domains found in $DOMAINS_FILE"
    fi
    DOMAINS=("${DNS_REDIRECT_LIST[@]}")
}

ensure_redirect_rule() {
    local domain="$1"
    local target_url="$2"
    local ruleset_resp ruleset_id ruleset_name ruleset_desc ruleset_kind ruleset_phase
    local expr ref desc
    local updated_rules payload update_resp create_resp

    expr="(http.host eq \"$domain\") or (http.host eq \"www.$domain\")"
    ref="redirect_$(safe_name "$domain")"
    desc="Redirect $domain to $target_url"

    ruleset_resp=$(cf_api_request GET "/zones/$CF_ZONE_ID/rulesets/phases/http_request_dynamic_redirect/entrypoint")
    if [ "$(cf_api_success "$ruleset_resp")" != "true" ]; then
        log "No redirect ruleset found for $domain; creating new entrypoint ruleset"
        payload=$(jq -n --arg desc "$desc" --arg url "$target_url" '
            {
                name: "Redirect rules",
                description: "",
                kind: "zone",
                phase: "http_request_dynamic_redirect",
                rules: [
                    {
                        action: "redirect",
                        expression: "true",
                        description: $desc,
                        enabled: true,
                        action_parameters: {
                            from_value: {
                                preserve_query_string: true,
                                status_code: 301,
                                target_url: { value: $url }
                            }
                        }
                    }
                ]
            }')

        if [ "$DRY_RUN" = true ]; then
            log "Dry run: would create redirect ruleset for $domain"
            return 0
        fi

        create_resp=$(cf_api_request POST "/zones/$CF_ZONE_ID/rulesets" "$payload")
        if [ "$(cf_api_success "$create_resp")" != "true" ]; then
            err "Failed to create redirect ruleset: $(cf_api_error_messages "$create_resp")"
        fi
        return 0
    fi

    ruleset_id=$(echo "$ruleset_resp" | jq -r '.result.id // empty')
    ruleset_name=$(echo "$ruleset_resp" | jq -r '.result.name // "Redirect rules"')
    ruleset_desc=$(echo "$ruleset_resp" | jq -r '.result.description // ""')
    ruleset_kind=$(echo "$ruleset_resp" | jq -r '.result.kind // "zone"')
    ruleset_phase=$(echo "$ruleset_resp" | jq -r '.result.phase // "http_request_dynamic_redirect"')

    [ -n "$ruleset_id" ] || err "Missing redirect ruleset id for $domain"

    updated_rules=$(echo "$ruleset_resp" | jq -c \
        --arg expr "$expr" \
        --arg ref "$ref" \
        --arg desc "$desc" \
        --arg url "$target_url" '
        (.result.rules // []) as $rules
        | ($rules | map(
            if (.action == "redirect" and .expression == "true") then
                .action = "redirect"
                | .enabled = true
                | .description = $desc
                | .action_parameters = {
                    "from_value": {
                        "preserve_query_string": true,
                        "status_code": 301,
                        "target_url": { "value": $url }
                    }
                }
            else
                .
            end
        )) as $with_static_updated
        | ($with_static_updated | map(select((.ref != $ref) and (.expression != $expr)))) as $filtered
        | ($filtered | map(select(.action == "redirect" and .expression == "true"))) as $statics
        | if ($statics | length) == 0
          then ($filtered + [{
              "action": "redirect",
              "expression": "true",
              "description": $desc,
              "enabled": true,
              "action_parameters": {
                  "from_value": {
                      "preserve_query_string": true,
                      "status_code": 301,
                      "target_url": { "value": $url }
                  }
              }
          }])
          else $filtered
          end')
    [ -n "$updated_rules" ] || err "Failed to build redirect rules payload for $domain"

    payload=$(jq -n --arg name "$ruleset_name" --arg desc "$ruleset_desc" --arg kind "$ruleset_kind" \
        --arg phase "$ruleset_phase" --argjson rules "$updated_rules" \
        '{name:$name, description:$desc, kind:$kind, phase:$phase, rules:$rules}')

    if [ "$DRY_RUN" = true ]; then
        log "Dry run: would update redirect ruleset $ruleset_id for $domain"
        return 0
    fi

    update_resp=$(cf_api_request PUT "/zones/$CF_ZONE_ID/rulesets/$ruleset_id" "$payload")
    if [ "$(cf_api_success "$update_resp")" != "true" ]; then
        err "Failed to update redirect ruleset: $(cf_api_error_messages "$update_resp")"
    fi
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                norecord) RECORD_UPDATES=false ;;
                downgrade) RECORD_DOWNGRADE=true ;;
                date|date=*)
                    if cli_date_opt "${OPTARG}" DATASTORE_DATE "${!OPTIND-}"; then
                        :
                    else
                        usage; exit 1
                    fi
                    ;;
                redirect-url|redirect-url=*)
                    case "${OPTARG}" in
                        redirect-url=*) REDIRECT_URL="${OPTARG#*=}" ;;
                        redirect-url) REDIRECT_URL="${!OPTIND-}"; OPTIND=$((OPTIND+1)) ;;
                    esac
                    ;;
                domains-file|domains-file=*)
                    case "${OPTARG}" in
                        domains-file=*) DOMAINS_FILE="${OPTARG#*=}" ;;
                        domains-file) DOMAINS_FILE="${!OPTIND-}"; OPTIND=$((OPTIND+1)) ;;
                    esac
                    ;;
                dry-run) DRY_RUN=true ;;
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

AUTH_FILE_OVERRIDE="${CF_AUTH_FILE-}"

if [ ${#DOMAINS[@]} -eq 0 ]; then
    load_redirect_domains
fi

finalize_domains DOMAINS || { usage; exit 1; }

require_cmds curl jq python3

for domain in "${DOMAINS[@]}"; do
    domain=$(normalize_domain "$domain")
    log "Configuring redirect for: $domain"

    meta=$(csv_get_domain_fields "$domain" zone_id auth_file redirect_url site_type status_cf || true)
    zone_id=""
    auth_file=""
    redirect_csv=""
    site_type=""
    status_cf=""

    if [ -n "$meta" ]; then
        IFS=$'\t' read -r zone_id auth_file redirect_csv site_type status_cf <<<"$meta"
    fi

    site_type_norm=$(normalize_site_type "$site_type")
    if site_type_is_skip "$site_type_norm"; then
        warn "Skipping $domain (site_type=$site_type_norm)"
        continue
    fi

    target_url="$REDIRECT_URL"
    if [ -z "$target_url" ]; then
        target_url="$redirect_csv"
    fi
    [ -n "$target_url" ] || err "redirect_url required for $domain (use --redirect-url or domains.csv)"

    if [ -n "$AUTH_FILE_OVERRIDE" ]; then
        CF_AUTH_FILE="$AUTH_FILE_OVERRIDE"
    else
        cf_reset_auth_vars
        CF_AUTH_FILE=""
        if [ -n "$auth_file" ]; then
            CF_AUTH_FILE="$auth_file"
        fi
    fi

    CF_ZONE_ID=""
    CF_ZONE="$domain"
    if [ -n "$zone_id" ]; then
        CF_ZONE_ID="$zone_id"
    fi

    cf_init_auth "${CF_AUTH_FILE-}"
    cf_require_auth
    cf_require_zone_id "for redirect rule" "$domain"

    ensure_redirect_rule "$domain" "$target_url"
    log "Redirect rule ready: $domain -> $target_url"

    if [ "$DRY_RUN" != true ] && [ "$RECORD_UPDATES" = true ]; then
        update_site_type=""
        update_status_cf=""
        if [[ "$site_type_norm" == redirect* ]]; then
            update_status_cf="redirect"
        fi
        updates=()
        if [ -z "$update_site_type" ] && [ -z "$update_status_cf" ]; then
            warn "site_type not redirect; skipping domains.csv updates for $domain"
        else
            updates+=("redirect_url=$target_url")
        fi
        [ -n "$update_site_type" ] && updates+=("site_type=$update_site_type")
        [ -n "$update_status_cf" ] && updates+=("status_cf=$update_status_cf")
        if [ ${#updates[@]} -gt 0 ]; then
            csv_put_fields "$DOMAINS_FILE" "$domain" "$RECORD_DOWNGRADE" "${updates[@]}"
        fi
    fi
done

log "Done."
