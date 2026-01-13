#!/bin/bash
# mcp-cf.sh - Verify Cloudflare MCP readiness and portal reachability.
# For options, environment variables, defaults see usage().
#
# Example: mcp-cf.sh [OPTIONS]

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"

. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/auth.sh"
. "$SCRIPTS_DIR/cli.sh"
. "$SCRIPTS_DIR/mcp.sh"

CATALOG=false
APPLY=false
PORTAL_URL=""
MCP_BEARER_TOKEN="${MCP_BEARER_TOKEN-}"
CF_AUTH_CLI=""

usage() {
    cat <<'USAGE'
mcp-cf.sh - Verify Cloudflare MCP readiness and portal reachability.
Example: mcp-cf.sh [OPTIONS]

Options:
  --portal-url URL [MCP_PORTAL_URL]  MCP portal endpoint (defaults to /mcp)
  --bearer TOKEN [MCP_BEARER_TOKEN]  Bearer token for MCP portal auth
  --catalog  Print the managed MCP server catalog reference list
  --apply  Enable write operations (not implemented)
  --auth-file PATH [CF_AUTH_FILE]  Auth file to load
  --auth token|key|auto [CF_AUTH]  Select which credential to use (default: auto)
  --token TOKEN [CF_API_TOKEN]  Set CF_API_TOKEN (account API token)
  --key KEY [CF_API_KEY]  Set CF_API_KEY (global API key)
  --email EMAIL [CF_API_EMAIL]  Set CF_API_EMAIL (global API key email)
  --account ID [CF_ACCOUNT_ID]  Set CF_ACCOUNT_ID
  --help  Show this help

Notes:
  - Uses POST with streamable HTTP headers; 401/403 indicates auth is required.
  - Write operations are not implemented and will fail even if --apply is provided.
USAGE
}

print_catalog() {
    cat <<'CATALOG'
Managed MCP servers (reference list):
- Documentation
- Workers bindings
- Builds
- Observability
- Radar
- Container
- Browser rendering
- Logpush
- AI Gateway
- AI Search
- Audit Logs
- DNS Analytics
- DEX
- CASB
- GraphQL
CATALOG
}

manual_steps() {
    cat <<'MANUAL'
Manual action required:
- Zero Trust → Access → Applications → AI controls
- Verify MCP Servers and MCP Portals are visible
- Create a test portal and verify it is reachable at https://<subdomain>.<domain>/mcp
- Apply an Access policy and confirm OAuth-based access works as expected
MANUAL
}

mcp_emit() {
    local level="$1"
    shift
    echo "${level}: $*"
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                catalog) CATALOG=true ;;
                apply) APPLY=true ;;
                portal-url=*) PORTAL_URL="${OPTARG#*=}" ;;
                portal-url)
                    [ -n "${!OPTIND-}" ] || err "--portal-url requires a value"
                    PORTAL_URL="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                bearer=*) MCP_BEARER_TOKEN="${OPTARG#*=}" ;;
                bearer)
                    [ -n "${!OPTIND-}" ] || err "--bearer requires a value"
                    MCP_BEARER_TOKEN="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
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

if [ -n "${MCP_PORTAL_URL-}" ] && [ -z "$PORTAL_URL" ]; then
    PORTAL_URL="$MCP_PORTAL_URL"
fi

cf_init_auth "${CF_AUTH_FILE-}"

if [ "$APPLY" = true ]; then
    err "Write operations are not implemented yet"
fi

if [ "$CATALOG" = true ]; then
    print_catalog
fi

overall_ok=true

if [ -n "$PORTAL_URL" ]; then
    require_cmds curl
    if ! PORTAL_URL="$(mcp_normalize_portal_url "$PORTAL_URL")"; then
        err "Invalid portal URL"
    fi

    payload='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"mcp-cf","version":"0"},"protocolVersion":"2024-11-05","capabilities":{}}}'
    auth_header=()
    if [ -n "$MCP_BEARER_TOKEN" ]; then
        auth_header=(-H "Authorization: Bearer $MCP_BEARER_TOKEN")
    fi

    headers_file=$(mktemp)
    body_file=$(mktemp)
    curl_status=0
    if ! curl -sS -m 5 -D "$headers_file" -o "$body_file" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json, text/event-stream" \
        "${auth_header[@]}" \
        -d "$payload" \
        "$PORTAL_URL"; then
        curl_status=$?
    fi

    status=$(awk 'NR==1{print $2}' "$headers_file")
    [ -n "$status" ] || status="000"

    class=$(mcp_portal_status_class "$status" || true)
    message=$(mcp_portal_status_message "$status")
    if [ "$curl_status" -eq 28 ] && [ "$status" = "200" ]; then
        message="Portal reachable (stream open)"
    fi
    case "$class" in
        pass) mcp_emit "PASS" "$message" ;;
        warn) mcp_emit "WARN" "$message" ;;
        *)
            mcp_emit "FAIL" "$message"
            overall_ok=false
            ;;
    esac
    rm -f "$headers_file" "$body_file"
else
    mcp_emit "INFO" "Portal URL not provided; skipping portal probe"
fi

manual_steps

if [ "$overall_ok" = true ]; then
    exit 0
fi
exit 1
