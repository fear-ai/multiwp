#!/bin/bash
# rules-cf.sh - Export or apply Cloudflare firewall rules (Rulesets API).
# For options, environment variables, defaults see usage().
#
# Example: rules-cf.sh --export --source example.com

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/auth.sh"
. "$SCRIPTS_DIR/cli.sh"

MODE="export"
SOURCE=""
OUTPUT=""
INPUT=""
ALL=false
DOMAINS=()
CF_AUTH_CLI=""
ALLOW_REDIRECTS=false

usage() {
    cat <<'EOF'
rules-cf.sh - Export or apply Cloudflare firewall rules (Rulesets API).
Example: rules-cf.sh --export --source example.com

Options:
  --export  Export rules from a source zone (default)
  --apply  Apply rules from a JSON file to target zones
  --source DOMAIN  Source zone apex for export
  --output PATH  Export output path (default: rules.<domain>.json)
  --input PATH  Input file for apply (default: rules.<domain>.json)
  --domain DOMAIN  Target zone apex for apply (repeatable)
  --all  Include disabled rules in export
  --allow-redirects  Allow apply operations for redirect-only domains

Auth options (choose one):
  - Account API Token (recommended): CF_API_TOKEN=... [--token TOKEN]
  - Global API Key + email (user): CF_API_KEY=... CF_API_EMAIL=... [--key KEY --email EMAIL]
  --auth token|key|auto [CF_AUTH]  Select which credential to use (default: auto)
  --auth-file PATH [CF_AUTH_FILE] (default: ~/.config/cloudflare/default.auth)  Auth file to load
  --token TOKEN [CF_API_TOKEN]  Set CF_API_TOKEN (account API token)
  --key KEY [CF_API_KEY]  Set CF_API_KEY (global API key)
  --email EMAIL [CF_API_EMAIL]  Set CF_API_EMAIL (global API key email)
  --help  Show this help
EOF
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                export) MODE="export" ;;
                apply) MODE="apply" ;;
                source=*) SOURCE="${OPTARG#*=}" ;;
                source)
                    [ -n "${!OPTIND-}" ] || err "--source requires a value"
                    SOURCE="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                output=*) OUTPUT="${OPTARG#*=}" ;;
                output)
                    [ -n "${!OPTIND-}" ] || err "--output requires a value"
                    OUTPUT="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                input=*) INPUT="${OPTARG#*=}" ;;
                input)
                    [ -n "${!OPTIND-}" ] || err "--input requires a value"
                    INPUT="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                all) ALL=true ;;
                allow-redirects) ALLOW_REDIRECTS=true ;;
                *)
                    if cli_domain_opt "${OPTARG}" DOMAINS "${!OPTIND-}"; then
                        :
                    elif cli_cf_auth_opt "${OPTARG}" "${!OPTIND-}"; then
                        :
                    else
                        usage
                        exit 1
                    fi
                    ;;
            esac
            ;;
        \?) usage; exit 1 ;;
    esac
done
shift $((OPTIND-1))

if [ "$MODE" = "export" ] && [ "${#DOMAINS[@]}" -gt 0 ]; then
    err "--domain is only valid with --apply"
fi
if [ "$MODE" = "apply" ] && [ -n "$SOURCE" ]; then
    err "--source is only valid with --export"
fi
if [ $# -gt 0 ]; then
    err "Unexpected arguments: $*"
fi

require_cmds curl jq
AUTH_FILE_OVERRIDE="${CF_AUTH_FILE-}"

init_auth_for_domain() {
    local domain="$1"
    if [ -n "$AUTH_FILE_OVERRIDE" ]; then
        CF_AUTH_FILE="$AUTH_FILE_OVERRIDE"
    else
        cf_reset_auth_vars
        CF_AUTH_FILE=""
        cf_auth_from_csv "$domain" || true
    fi
    cf_init_auth "${CF_AUTH_FILE-}"
    cf_require_auth "for firewall rules"
}

normalize_source() {
    local value="$1"
    local normalized
    normalized=$(normalize_domain "$value")
    validate_domain "$normalized" || exit 1
    echo "$normalized"
}

default_rules_path() {
    local domain="$1"
    echo "rules.${domain}.json"
}

export_rules() {
    local source="$1"
    local include_disabled="$2"
    local output_path="$3"
    local zone_id
    init_auth_for_domain "$source"
    zone_id="${CF_ZONE_ID-}"
    if [ -z "$zone_id" ]; then
        zone_id=$(cf_resolve_zone_id "$source")
    fi
    local resp
    resp=$(cf_api_request GET "/zones/${zone_id}/rulesets/phases/http_request_firewall_custom/entrypoint")
    if [ "$(cf_api_success "$resp")" != "true" ]; then
        err "Failed to query firewall ruleset for $source: $(cf_api_error_messages "$resp")"
    fi
    local filter
    filter='
      .result as $r
      | {
          name: ($r.name // "default"),
          description: ($r.description // ""),
          phase: $r.phase,
          rules: ($r.rules // [])
        }
      | .rules = (
          .rules
          | map({
              action: .action,
              expression: .expression,
              description: .description,
              enabled: .enabled,
              action_parameters: .action_parameters,
              logging: .logging
            } | with_entries(select(.value != null)))
        )
      | if $include_disabled == true then . else .rules = (.rules | map(select(.enabled != false))) end
      | if (.phase == null or .phase == "") then del(.phase) else . end
    '
    if ! echo "$resp" | jq --argjson include_disabled "$include_disabled" "$filter" > "$output_path"; then
        err "Failed to write export file: $output_path"
    fi
    log "Exported firewall rules from $source to $output_path"
}

apply_rules() {
    local input_path="$1"
    shift
    local domains=("$@")
    if [ ! -f "$input_path" ]; then
        err "Input file not found: $input_path"
    fi
    if ! jq -e '.rules and (.rules | type=="array")' "$input_path" >/dev/null 2>&1; then
        err "Input file does not contain a valid rules array: $input_path"
    fi
    local phase
    phase=$(jq -r '.phase // empty' "$input_path")
    if [ -z "$phase" ]; then
        phase="http_request_firewall_custom"
    fi
    local name
    name=$(jq -r '.name // "default"' "$input_path")
    local desc
    desc=$(jq -r '.description // ""' "$input_path")
    local rules_json
    rules_json=$(jq -c '.rules' "$input_path")
    for domain in "${domains[@]}"; do
        local zone_id
        init_auth_for_domain "$domain"
        zone_id="${CF_ZONE_ID-}"
        if [ -z "$zone_id" ]; then
            zone_id=$(cf_resolve_zone_id "$domain")
        fi
        local entry_resp
        entry_resp=$(cf_api_request GET "/zones/${zone_id}/rulesets/phases/${phase}/entrypoint")
        local ruleset_id=""
        if [ "$(cf_api_success "$entry_resp")" = "true" ]; then
            ruleset_id=$(echo "$entry_resp" | jq -r '.result.id // empty')
        fi
        local payload
        payload=$(jq -n -c --arg name "$name" --arg desc "$desc" --arg phase "$phase" --argjson rules "$rules_json" \
            '{name:$name, description:$desc, kind:"zone", phase:$phase, rules:$rules}')
        if [ -n "$ruleset_id" ]; then
            update_resp=$(cf_api_request PUT "/zones/${zone_id}/rulesets/${ruleset_id}" "$payload")
            if [ "$(cf_api_success "$update_resp")" != "true" ]; then
                err "Failed to update ruleset for ${domain}: $(cf_api_error_messages "$update_resp")"
            fi
            log "Updated firewall rules for ${domain} (ruleset ${ruleset_id})"
        else
            create_resp=$(cf_api_request POST "/zones/${zone_id}/rulesets" "$payload")
            if [ "$(cf_api_success "$create_resp")" != "true" ]; then
                err "Failed to create ruleset for ${domain}: $(cf_api_error_messages "$create_resp")"
            fi
            log "Created firewall ruleset for ${domain}"
        fi
    done
}

if [ "$MODE" = "export" ]; then
    [ -n "$SOURCE" ] || err "--source is required for export"
    SOURCE="$(normalize_source "$SOURCE")"
    if [ -z "$OUTPUT" ]; then
        OUTPUT="$(default_rules_path "$SOURCE")"
    fi
    export_rules "$SOURCE" "$ALL" "$OUTPUT"
    exit 0
fi

if [ "$MODE" = "apply" ]; then
    if [ ${#DOMAINS[@]} -eq 0 ]; then
        err "--domain is required for apply"
    fi
    finalize_domains DOMAINS || { usage; exit 1; }
    if [ -z "$INPUT" ]; then
        INPUT="$(default_rules_path "${DOMAINS[0]}")"
    fi
    load_dns_redirects || { usage; exit 1; }
    if [ ${#DNS_REDIRECT_LIST[@]:-0} -gt 0 ]; then
        redirect_targets=()
        for domain in "${DOMAINS[@]}"; do
            if is_redirect_domain "$domain"; then
                redirect_targets+=("$domain")
            fi
        done
        if [ ${#redirect_targets[@]} -gt 0 ]; then
            if [ "$ALLOW_REDIRECTS" != true ]; then
                err "Refusing to apply rules to redirect-only domains without --allow-redirects: ${redirect_targets[*]}"
            fi
            warn "Applying firewall rules to redirect-only domains: ${redirect_targets[*]}"
        fi
    fi
    apply_rules "$INPUT" "${DOMAINS[@]}"
    exit 0
fi

err "Unknown mode: $MODE"
