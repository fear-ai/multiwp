#!/bin/bash
# mcp.sh - Helpers for Cloudflare MCP scripts

set -euo pipefail

: "${COMMON_LOADED:?${BASH_SOURCE[0]##*/} requires common.sh to be sourced first.}"

mcp_normalize_portal_url() {
    local raw="${1-}"
    raw=$(printf "%s" "$raw" | xargs)
    [ -n "$raw" ] || return 1

    local url="$raw"
    if [[ "$url" != *"://"* ]]; then
        url="https://$url"
    fi

    if [[ "$url" =~ ^https?://[^/]+/?$ ]]; then
        url="${url%/}/mcp"
    fi

    printf "%s" "$url"
}

mcp_portal_status_class() {
    local status="${1-}"
    if ! [[ "$status" =~ ^[0-9]{3}$ ]]; then
        echo "fail"
        return 1
    fi

    case "$status" in
        200) echo "pass" ;;
        401|403) echo "warn" ;;
        3??) echo "warn" ;;
        4??) echo "fail" ;;
        5??) echo "fail" ;;
        *) echo "fail" ;;
    esac
}

mcp_portal_status_message() {
    local status="${1-}"
    case "$status" in
        200) echo "Portal reachable (authorized)" ;;
        401|403) echo "Portal reachable; authorization required" ;;
        3??) echo "Portal returned redirect (status $status)" ;;
        4??) echo "Portal returned client error (status $status)" ;;
        5??) echo "Portal returned server error (status $status)" ;;
        *) echo "Portal probe failed" ;;
    esac
}
