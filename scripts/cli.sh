#!/bin/bash
# cli.sh - Shared CLI helpers for option parsing and guards

set -euo pipefail

cli_common_opt() {
    local opt="$1"
    case "$opt" in
        allow-root) ALLOW_ROOT=true; return 0 ;;
        no-sudo) SUDO_BIN=""; export SUDO_BIN; return 0 ;;
    esac
    return 1
}

cli_wp_root_opt() {
    local opt="$1"
    local var="$2"
    local next="${3-}"
    local val=""
    case "$opt" in
        wp-root=*) val="${opt#*=}" ;;
        wp-root)
            val="$next"
            OPTIND=$((OPTIND+1))
            ;;
        *) return 1 ;;
    esac
    [ -n "$val" ] || err "--wp-root requires a value"
    printf -v "$var" '%s' "$val"
    return 0
}

cli_apache_dir_opt() {
    local opt="$1"
    local var="$2"
    local next="${3-}"
    local val=""
    case "$opt" in
        apache-dir=*) val="${opt#*=}" ;;
        apache-dir)
            val="$next"
            OPTIND=$((OPTIND+1))
            ;;
        *) return 1 ;;
    esac
    [ -n "$val" ] || err "--apache-dir requires a value"
    printf -v "$var" '%s' "$val"
    return 0
}

cli_ssl_dir_opt() {
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

cli_hsts_opt() {
    local opt="$1"
    local var="$2"
    local next="${3-}"
    local val=""
    case "$opt" in
        hsts=*) val="${opt#*=}" ;;
        hsts)
            val="$next"
            OPTIND=$((OPTIND+1))
            ;;
        *) return 1 ;;
    esac
    [ -n "$val" ] || err "--hsts requires true or false"
    if ! val="$(parse_bool "$val")"; then
        err "--hsts must be true or false"
    fi
    printf -v "$var" '%s' "$val"
    return 0
}

cli_http_timeout_opt() {
    local opt="$1"
    local var="$2"
    local next="${3-}"
    local val=""
    case "$opt" in
        http-timeout=*) val="${opt#*=}" ;;
        http-timeout)
            val="$next"
            OPTIND=$((OPTIND+1))
            ;;
        *) return 1 ;;
    esac
    [ -n "$val" ] || err "--http-timeout requires a value"
    printf -v "$var" '%s' "$val"
    return 0
}

cli_domain_opt() {
    local opt="$1"
    local array_name="$2"
    local next="${3-}"
    local val=""
    case "$opt" in
        domain=*) val="${opt#*=}" ;;
        domain)
            val="$next"
            OPTIND=$((OPTIND+1))
            ;;
        *) return 1 ;;
    esac
    [ -n "$val" ] || err "--domain requires a value"
    local -n domain_list="$array_name"
    domain_list+=("$val")
    return 0
}

cli_usage_wp_root() {
    echo "  --wp-root PATH [WORDPRESS_ROOT] (default: $WORDPRESS_ROOT)  WordPress root"
}

cli_usage_apache_dir() {
    local def="${1:-${APACHE_DIR:-/etc/apache2/sites-available}}"
    echo "  --apache-dir DIR [APACHE_DIR] (default: $def)  Apache sites-available dir"
}

cli_usage_ssl_dir() {
    echo "  --ssl-dir DIR [SSL_DIR] (default: $SSL_DIR)  SSL directory"
}

cli_usage_domain() {
    echo "  --domain NAME  Domain to process (repeatable; positional also accepted)"
}

cli_usage_hsts() {
    echo "  --hsts=true|false  Require Strict-Transport-Security header"
}

cli_usage_http_timeout() {
    local def="${1:-${HTTP_TIMEOUT:-10}}"
    echo "  --http-timeout SECONDS [HTTP_TIMEOUT] (default: $def)  HTTP timeout for curl"
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

cli_cf_auth_opt() {
    local opt="$1"
    local next="${2-}"
    case "$opt" in
        auth-file)
            cf_auth_file "$opt" "$next"
            OPTIND=$((OPTIND+1))
            return 0
            ;;
        account|account-name|token|email|key|ca-key|auth)
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
