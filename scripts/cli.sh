#!/bin/bash
# cli.sh - Shared CLI helpers for option parsing and guards

set -euo pipefail

cli_handle_common_opt() {
    local opt="$1"
    case "$opt" in
        allow-root) ALLOW_ROOT=true; return 0 ;;
        no-sudo) SUDO_BIN=""; export SUDO_BIN; return 0 ;;
    esac
    return 1
}

cli_handle_root_opt() {
    local opt="$1"
    local var="$2"
    local next="${3-}"
    local val=""
    case "$opt" in
        root=*) val="${opt#*=}" ;;
        root)
            val="$next"
            OPTIND=$((OPTIND+1))
            ;;
        *) return 1 ;;
    esac
    [ -n "$val" ] || err "--root requires a value"
    printf -v "$var" '%s' "$val"
    return 0
}

cli_handle_ssl_dir_opt() {
    local opt="$1"
    local base_var="$2"
    local cert_var="${3-}"
    local key_var="${4-}"
    local next="${5-}"
    local base=""
    case "$opt" in
        ssl-dir=*) base="${opt#*=}" ;;
        ssl-dir)
            base="$next"
            OPTIND=$((OPTIND+1))
            ;;
        *) return 1 ;;
    esac
    [ -n "$base" ] || err "--ssl-dir requires a value"
    printf -v "$base_var" '%s' "$base"
    if [ -n "$cert_var" ]; then
        printf -v "$cert_var" '%s' "$base/certs"
    fi
    if [ -n "$key_var" ]; then
        printf -v "$key_var" '%s' "$base/keys"
    fi
    return 0
}

cli_usage_root() {
    echo "  --root PATH [WORDPRESS_ROOT] (default: $WORDPRESS_ROOT)  WordPress root"
}

cli_usage_ssl_dir() {
    echo "  --ssl-dir DIR [SSL_BASE] (default: $SSL_BASE)  Base SSL dir"
}

cli_usage_common_priv() {
    echo "  --allow-root  Allow running as root (not recommended)"
    echo "  --no-sudo [SUDO_BIN] (default: sudo)  Disable sudo usage (run commands as current user)"
}

cli_require_non_root() {
    if [ "${USER:-}" = "root" ] && [ "${ALLOW_ROOT:-false}" != true ]; then
        err "Do not run as root. Run as a user with sudo privileges."
    fi
}

cli_handle_cf_auth_opt() {
    local opt="$1"
    local next="${2-}"
    case "$opt" in
        auth-file)
            cf_auth_file "$opt" "$next"
            OPTIND=$((OPTIND+1))
            return 0
            ;;
        account|token|email|key|ca-key)
            cf_auth_opt "$opt" "$next"
            OPTIND=$((OPTIND+1))
            return 0
            ;;
    esac
    if command -v cf_auth_file >/dev/null 2>&1; then
        if cf_auth_file "$opt"; then
            return 0
        fi
    fi
    if command -v cf_auth_opt >/dev/null 2>&1; then
        if cf_auth_opt "$opt"; then
            return 0
        fi
    fi
    return 1
}
