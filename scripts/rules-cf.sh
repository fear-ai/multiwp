#!/bin/bash
# rules-cf.sh - Get, put, or copy Cloudflare rulesets (Rulesets API).
# For options, environment variables, defaults see usage().
#
# Example: rules-cf.sh --get --type firewall --src example.com

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/auth.sh"
. "$SCRIPTS_DIR/cli.sh"

MODE="get"
MODE_SET=false
TYPE="cache"
PHASE=""
SRC=""
FILE=""
ALL=false
DESTS=()
CF_AUTH_CLI=""
ALLOW_REDIRECTS=false

usage() {
    cat <<'EOF'
rules-cf.sh - Get, put, or copy Cloudflare rulesets (Rulesets API).
Example: rules-cf.sh --get --type firewall --src example.com

Options:
  --get  Fetch rules from a source zone (default)
  --put  Apply rules from a JSON file to target zones
  --copy  Fetch rules from a source zone, then apply to target zones
  --type TYPE  Rule type: firewall|cache|rate (default: cache)
  --src DOMAIN  Source zone apex for get/copy (required for get/copy)
  --dest DOMAIN  Target zone apex for put/copy (repeatable)
  --file PATH  Ruleset file path (default: <src>_<phase>.json; phase derived from --type)
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
                get)
                    if $MODE_SET && [ "$MODE" != "get" ]; then
                        err "--get, --put, and --copy are mutually exclusive"
                    fi
                    MODE="get"
                    MODE_SET=true
                    ;;
                put)
                    if $MODE_SET && [ "$MODE" != "put" ]; then
                        err "--get, --put, and --copy are mutually exclusive"
                    fi
                    MODE="put"
                    MODE_SET=true
                    ;;
                copy)
                    if $MODE_SET && [ "$MODE" != "copy" ]; then
                        err "--get, --put, and --copy are mutually exclusive"
                    fi
                    MODE="copy"
                    MODE_SET=true
                    ;;
                type=*) TYPE="${OPTARG#*=}" ;;
                type)
                    [ -n "${!OPTIND-}" ] || err "--type requires a value"
                    TYPE="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                src=*) SRC="${OPTARG#*=}" ;;
                src)
                    [ -n "${!OPTIND-}" ] || err "--src requires a value"
                    SRC="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                dest=*) DESTS+=("${OPTARG#*=}") ;;
                dest)
                    [ -n "${!OPTIND-}" ] || err "--dest requires a value"
                    DESTS+=("${!OPTIND}")
                    OPTIND=$((OPTIND+1))
                    ;;
                file=*) FILE="${OPTARG#*=}" ;;
                file)
                    [ -n "${!OPTIND-}" ] || err "--file requires a value"
                    FILE="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                all) ALL=true ;;
                allow-redirects) ALLOW_REDIRECTS=true ;;
                *)
                    if cli_cf_auth_opt "${OPTARG}" "${!OPTIND-}"; then
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
    echo "${domain}_${PHASE}.json"
}

resolve_phase() {
    local raw="${1-}"
    raw=$(printf "%s" "$raw" | tr '[:upper:]' '[:lower:]' | xargs)
    case "$raw" in
        firewall) PHASE="http_request_firewall_custom" ;;
        cache) PHASE="http_request_cache_settings" ;;
        rate) PHASE="http_ratelimit" ;;
        *) err "--type must be one of: firewall, cache, rate" ;;
    esac
}

export_rules() {
    local source="$1"
    local include_disabled="$2"
    local output_path="$3"
    local zone_id
    init_auth_for_domain "$source"
    zone_id="${CF_ZONE_ID-}"
    if [ -z "$zone_id" ]; then
        if ! cf_zone_id_for_domain "$source"; then
            err "No zone ID resolved for $source"
        fi
        zone_id="$CF_ZONE_ID"
    fi
    local resp
    resp=$(cf_api_request GET "/zones/${zone_id}/rulesets/phases/${PHASE}/entrypoint")
    if [ "$(cf_api_success "$resp")" != "true" ]; then
        local msg
        msg="$(cf_api_error_messages "$resp")"
        if echo "$msg" | grep -qi "could not find entrypoint ruleset"; then
            err "No entrypoint ruleset for ${PHASE} in ${source}; create one before exporting"
        fi
        err "Failed to query ${PHASE} ruleset for $source: $msg"
    fi
    local total_rules enabled_rules
    total_rules=$(echo "$resp" | jq -r '(.result.rules // []) | length')
    enabled_rules=$(echo "$resp" | jq -r '(.result.rules // []) | map(select(.enabled != false)) | length')
    if [ "$include_disabled" = true ]; then
        if [ "$total_rules" -eq 0 ]; then
            err "No rules found for ${PHASE} in ${source}; export aborted"
        fi
    else
        if [ "$enabled_rules" -eq 0 ]; then
            err "No enabled rules to export for ${source} in ${PHASE}; use --all to include disabled rules"
        fi
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
              ratelimit: .ratelimit,
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
    log "Exported ${PHASE} rules from $source to $output_path"
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
        phase="$PHASE"
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
            if ! cf_zone_id_for_domain "$domain"; then
                err "No zone ID resolved for $domain"
            fi
            zone_id="$CF_ZONE_ID"
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
                err "Failed to update ${phase} ruleset for ${domain}: $(cf_api_error_messages "$update_resp")"
            fi
            log "Updated ${phase} rules for ${domain} (ruleset ${ruleset_id})"
        else
            create_resp=$(cf_api_request POST "/zones/${zone_id}/rulesets" "$payload")
            if [ "$(cf_api_success "$create_resp")" != "true" ]; then
                err "Failed to create ${phase} ruleset for ${domain}: $(cf_api_error_messages "$create_resp")"
            fi
            log "Created ${phase} ruleset for ${domain}"
        fi
    done
}

resolve_phase "$TYPE"

if [ -n "$SRC" ]; then
    SRC="$(normalize_source "$SRC")"
fi
if [ ${#DESTS[@]} -gt 0 ]; then
    finalize_domains DESTS || { usage; exit 1; }
fi

if [ "$MODE" = "get" ]; then
    [ -n "$SRC" ] || err "--src is required for --get"
    if [ -z "$FILE" ]; then
        FILE="$(default_rules_path "$SRC")"
    fi
    section "RULES" "Get"
    kv "TYPE" "$TYPE"
    kv "PHASE" "$PHASE"
    kv "SRC" "$SRC"
    kv "FILE" "$FILE"
    export_rules "$SRC" "$ALL" "$FILE"
    exit 0
fi

if [ "$MODE" = "put" ]; then
    if [ ${#DESTS[@]} -eq 0 ]; then
        err "--dest is required for --put"
    fi
    if [ -z "$FILE" ]; then
        [ -n "$SRC" ] || err "--src is required when --file is not provided"
        FILE="$(default_rules_path "$SRC")"
    fi
    DNS_REDIRECT_LIST=()
    load_dns_redirects || { usage; exit 1; }
    if [ ${#DNS_REDIRECT_LIST[@]} -gt 0 ]; then
        redirect_targets=()
        for domain in "${DESTS[@]}"; do
            if is_redirect_domain "$domain"; then
                redirect_targets+=("$domain")
            fi
        done
        if [ ${#redirect_targets[@]} -gt 0 ]; then
            if [ "$ALLOW_REDIRECTS" != true ]; then
                err "Refusing to apply rules to redirect-only domains without --allow-redirects: ${redirect_targets[*]}"
            fi
            warn "Applying rules to redirect-only domains: ${redirect_targets[*]}"
        fi
    fi
    section "RULES" "Put"
    kv "TYPE" "$TYPE"
    kv "PHASE" "$PHASE"
    kv "FILE" "$FILE"
    kv "DESTS" "${DESTS[*]}"
    apply_rules "$FILE" "${DESTS[@]}"
    exit 0
fi

if [ "$MODE" = "copy" ]; then
    [ -n "$SRC" ] || err "--src is required for --copy"
    if [ ${#DESTS[@]} -eq 0 ]; then
        err "--dest is required for --copy"
    fi
    if [ -z "$FILE" ]; then
        FILE="$(default_rules_path "$SRC")"
    fi
    section "RULES" "Copy"
    kv "TYPE" "$TYPE"
    kv "PHASE" "$PHASE"
    kv "SRC" "$SRC"
    kv "FILE" "$FILE"
    kv "DESTS" "${DESTS[*]}"
    export_rules "$SRC" "$ALL" "$FILE"
    DNS_REDIRECT_LIST=()
    load_dns_redirects || { usage; exit 1; }
    if [ ${#DNS_REDIRECT_LIST[@]} -gt 0 ]; then
        redirect_targets=()
        for domain in "${DESTS[@]}"; do
            if is_redirect_domain "$domain"; then
                redirect_targets+=("$domain")
            fi
        done
        if [ ${#redirect_targets[@]} -gt 0 ]; then
            if [ "$ALLOW_REDIRECTS" != true ]; then
                err "Refusing to apply rules to redirect-only domains without --allow-redirects: ${redirect_targets[*]}"
            fi
            warn "Applying rules to redirect-only domains: ${redirect_targets[*]}"
        fi
    fi
    apply_rules "$FILE" "${DESTS[@]}"
    exit 0
fi

err "Unknown mode: $MODE"
