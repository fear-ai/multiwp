#!/bin/bash
# orch.sh - Shared orchestration helpers for check runners.
# Requires common.sh and caller-provided script paths/args.

run_domain_checks() {
    local domain="$1"
    local ok=true

    if [ -z "${ORIGIN_SCRIPT-}" ] || [ -z "${WP_SCRIPT-}" ] || [ -z "${EDGE_SCRIPT-}" ]; then
        err "ORIGIN_SCRIPT, WP_SCRIPT, and EDGE_SCRIPT must be set before calling run_domain_checks"
    fi

    if ! "$ORIGIN_SCRIPT" "${ORIGIN_ARGS[@]}" "$domain"; then
        ok=false
    fi

    if ! "$WP_SCRIPT" "${WP_ARGS[@]}" "$domain"; then
        ok=false
    fi

    if ! "$EDGE_SCRIPT" "${EDGE_ARGS[@]}" "$domain"; then
        ok=false
    fi

    $ok || return 1
    return 0
}
