#!/bin/bash
# cli.sh - Shared CLI helpers for option parsing and guards

set -euo pipefail

: "${COMMON_LOADED:?${BASH_SOURCE[0]##*/} requires common.sh to be sourced first.}"

CLI_LOADED=1

# Reorder "$@" so every option precedes every positional argument.
#
# getopts stops at the first non-option word, so `script domain.tld --flag`
# leaves OPTIND at 1: the flags after the positional are never parsed and are
# instead collected as domains, producing errors like "domain must include a
# dot" for `--domains-file`. Callers that accept positional domains run this
# before the getopts loop (`eval set -- "$(cli_reorder_args "$@")"`), which makes
# flag order irrelevant, matching the "positional also accepted" promise in the
# shared usage text.
#
# Options that take a separate value keep that value adjacent, so the value is
# not mistaken for a positional. `--` ends option processing: everything after it
# is positional, verbatim.
cli_reorder_args() {
    local -a opts=() pos=()
    local seen_ddash=false
    local a
    while [ "$#" -gt 0 ]; do
        a="$1"
        if [ "$seen_ddash" = true ]; then
            pos+=("$a"); shift; continue
        fi
        case "$a" in
            --) seen_ddash=true; shift ;;
            --*=*) opts+=("$a"); shift ;;
            --*)
                opts+=("$a"); shift
                # A following word that is not itself an option is this option's
                # value; keep them together.
                if [ "$#" -gt 0 ] && [ "${1#-}" = "$1" ]; then
                    opts+=("$1"); shift
                fi
                ;;
            -*) opts+=("$a"); shift ;;
            *) pos+=("$a"); shift ;;
        esac
    done
    local out=""
    for a in "${opts[@]}" "${pos[@]}"; do
        out+=" $(printf '%q' "$a")"
    done
    printf '%s' "${out# }"
}

# Parse --zone / --zone-id into the CLI override variables that cf_init_auth
# consumes. check-cf.sh and check-edge.sh each hand-rolled these four arms; this
# is the shared version.
#
# Scope note: --zone selects ONE zone, so it belongs on scripts that act on a
# single zone (rules-cf.sh, get-cert.sh, verify-cf-auth.sh, mcp-cf.sh). Scripts
# that iterate a domain list and resolve a zone per domain
# (cloud-redirect.sh, cloud-settings.sh, onboard-zone.sh, cloud-dns.sh) must not
# take it: a single CF_ZONE would override every domain in the loop, which is
# exactly the failure mode cf_setup_zone clears state to avoid.
#
# Usage: cli_cf_zone_opt "$OPTARG" "${!OPTIND-}" || <caller fallback>
cli_cf_zone_opt() {
    local opt="$1"
    local next="${2-}"
    case "$opt" in
        zone=*) CF_ZONE_CLI="${opt#*=}" ;;
        zone)
            [ -n "$next" ] || err "--zone requires a value"
            CF_ZONE_CLI="$next"
            OPTIND=$((OPTIND+1))
            ;;
        zone-id=*) CF_ZONE_ID_CLI="${opt#*=}" ;;
        zone-id)
            [ -n "$next" ] || err "--zone-id requires a value"
            CF_ZONE_ID_CLI="$next"
            OPTIND=$((OPTIND+1))
            ;;
        *) return 1 ;;
    esac
    return 0
}

cli_usage_cf_zone() {
    echo "  --zone NAME [CF_ZONE]  Zone apex (e.g., example.com)"
    echo "  --zone-id ID [CF_ZONE_ID]  Cloudflare zone ID"
}

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

cli_template_dir_opt() {
    local opt="$1"
    local var="$2"
    local next="${3-}"
    local val=""
    case "$opt" in
        template-dir=*) val="${opt#*=}" ;;
        template-dir)
            val="$next"
            OPTIND=$((OPTIND+1))
            ;;
        *) return 1 ;;
    esac
    [ -n "$val" ] || err "--template-dir requires a value"
    printf -v "$var" '%s' "$val"
    return 0
}

cli_stage_opt() {
    local opt="$1"
    local var="$2"
    local next="${3-}"
    local val=""
    case "$opt" in
        stage=*) val="${opt#*=}" ;;
        stage)
            val="$next"
            OPTIND=$((OPTIND+1))
            ;;
        *) return 1 ;;
    esac
    [ -n "$val" ] || err "--stage requires a value"
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

cli_date_opt() {
    local opt="$1"
    local var="$2"
    local next="${3-}"
    local val=""
    case "$opt" in
        date=*) val="${opt#*=}" ;;
        date)
            val="$next"
            OPTIND=$((OPTIND+1))
            ;;
        *) return 1 ;;
    esac
    [ -n "$val" ] || err "--date requires a value"
    printf -v "$var" '%s' "$val"
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

cli_usage_date() {
    echo "  --date TS [DATASTORE_DATE] (format: YYYYmmdd_HHMMSS)  Override datastore backup timestamp"
}

cli_usage_hsts() {
    echo "  --hsts=true|false  Require Strict-Transport-Security header"
}

cli_usage_http_timeout() {
    local def="${1:-${HTTP_TIMEOUT:-10}}"
    echo "  --http-timeout SECONDS [HTTP_TIMEOUT] (default: $def)  HTTP timeout for curl"
}

cli_usage_template_dir() {
    echo "  --template-dir DIR [TEMPLATE_DIR] (default: $TEMPLATE_DIR)  Templates directory"
}

cli_usage_stage() {
    echo "  --stage NAME [WP_STAGE] (default: current)  Template stage suffix (example: ssl, prod)"
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
        account|account-name|token|email|key|ca-key|auth|token-file|key-file|ca-key-file)
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
