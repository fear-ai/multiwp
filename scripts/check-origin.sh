#!/bin/bash
# check-origin.sh - Validate origin certificates, Apache configuration, and vhost wiring.
# For options, environment variables, defaults see usage().
#
# Example: check-origin.sh [OPTIONS] domain1 [domain2...]

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/cli.sh"

ALLOW_ROOT=false

SSL_DIR_LOCAL="$SSL_DIR"
SSL_CERT_DIR_LOCAL="$SSL_CERT_DIR"
SSL_KEY_DIR_LOCAL="$SSL_KEY_DIR"
APACHE_DIR_LOCAL="$APACHE_DIR"
WORDPRESS_ROOT_LOCAL="$WORDPRESS_ROOT"
DOMAINS=()

usage() {
    cat <<EOF
check-origin.sh - Validate origin certificates, Apache configuration, and vhost wiring.
Example: check-origin.sh [OPTIONS] domain1 [domain2...]

Options:
$(cli_usage_domain)
$(cli_usage_apache_dir)
$(cli_usage_wp_root)
$(cli_usage_ssl_dir)
$(cli_usage_common_priv)
  --help  Show this help

Notes:
  - Redirect-only domains (from domains.csv) are skipped.
  - Set DOMAINS_FILE to change the default domains.csv location.
EOF
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                ssl-dir|ssl-dir=*)
                    if cli_ssl_dir_opt "${OPTARG}" SSL_DIR_LOCAL SSL_CERT_DIR_LOCAL SSL_KEY_DIR_LOCAL "${!OPTIND-}"; then
                        :
                    else
                        usage; exit 1
                    fi
                    ;;
                apache-dir|apache-dir=*)
                    if cli_apache_dir_opt "${OPTARG}" APACHE_DIR_LOCAL "${!OPTIND-}"; then
                        :
                    else
                        usage; exit 1
                    fi
                    ;;
                wp-root|wp-root=*)
                    if cli_wp_root_opt "${OPTARG}" WORDPRESS_ROOT_LOCAL "${!OPTIND-}"; then
                        :
                    else
                        usage; exit 1
                    fi
                    ;;
                *)
                    if cli_domain_opt "${OPTARG}" DOMAINS "${!OPTIND-}"; then
                        :
                    elif cli_common_opt "${OPTARG}"; then
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
load_dns_redirects || { usage; exit 1; }

cli_require_non_root

require_cmds openssl stat grep

check_file_perms() {
    local path="$1"
    local expected="$2"
    local actual
    actual=$(priv stat -c "%U:%G %a" "$path" 2>/dev/null || true)
    if [ -z "$actual" ]; then
        warn "Unable to read permissions for $path"
        return 0
    fi
    if [ "$actual" != "$expected" ]; then
        fail "$path permissions are $actual (expected $expected)"
        return 1
    fi
    kv "PERMISSIONS_OK" "$path ($actual)"
}

check_domain() {
    local domain
    domain=$(tolower "$1")
    local ok=true

    if is_redirect_domain "$domain"; then
        log "Redirect-only domain; origin checks skipped: $domain"
        return 0
    fi

    echo ""
    log "Origin checks for: $domain"
    section "ORIGIN" "Tls"
    kv "DOMAIN" "$domain"

    local safe
    safe=$(safe_name "$domain")
    local cert_file="$SSL_CERT_DIR_LOCAL/${safe}.crt"
    local key_file="$SSL_KEY_DIR_LOCAL/${safe}.key"

    if priv test -r "$cert_file"; then
        kv "CERT_FILE" "$cert_file"
    else
        fail "Certificate missing or unreadable: $cert_file"
        ok=false
    fi

    if priv test -r "$key_file"; then
        kv "KEY_FILE" "$key_file"
    else
        fail "Key missing or unreadable: $key_file"
        ok=false
    fi

    if priv test -r "$cert_file"; then
        check_file_perms "$cert_file" "root:ssl-cert 640" || ok=false
        priv openssl x509 -in "$cert_file" -noout -subject -issuer -dates -ext subjectAltName || true
    fi

    if priv test -r "$key_file"; then
        check_file_perms "$key_file" "root:ssl-cert 640" || ok=false
    fi

    section "ORIGIN" "Vhosts"
    # TODO: allow per-domain vhost overrides (e.g., from domains.csv) when needed.
    local http_conf="$APACHE_DIR_LOCAL/${safe}.conf"
    local ssl_conf="$APACHE_DIR_LOCAL/${safe}-ssl.conf"

    if priv test -f "$http_conf"; then
        echo "HTTP vhost present: $http_conf"
        if ! priv grep -q "ServerName $domain" "$http_conf"; then
            fail "HTTP vhost missing ServerName $domain"
            ok=false
        fi
        if ! priv grep -q "DocumentRoot $WORDPRESS_ROOT_LOCAL" "$http_conf"; then
            fail "HTTP vhost DocumentRoot mismatch (expected $WORDPRESS_ROOT_LOCAL)"
            ok=false
        fi
    else
        fail "HTTP vhost missing: $http_conf"
        ok=false
    fi

    if priv test -f "$ssl_conf"; then
        echo "SSL vhost present: $ssl_conf"
        if ! priv grep -q "ServerName $domain" "$ssl_conf"; then
            fail "SSL vhost missing ServerName $domain"
            ok=false
        fi
        if ! priv grep -q "DocumentRoot $WORDPRESS_ROOT_LOCAL" "$ssl_conf"; then
            fail "SSL vhost DocumentRoot mismatch (expected $WORDPRESS_ROOT_LOCAL)"
            ok=false
        fi
        if ! priv grep -q "SSLCertificateFile $cert_file" "$ssl_conf"; then
            fail "SSL vhost missing SSLCertificateFile $cert_file"
            ok=false
        fi
        if ! priv grep -q "SSLCertificateKeyFile $key_file" "$ssl_conf"; then
            fail "SSL vhost missing SSLCertificateKeyFile $key_file"
            ok=false
        fi
    else
        fail "SSL vhost missing: $ssl_conf"
        ok=false
    fi

    if [ "$ok" = true ]; then
        status_pass "DOMAIN=$domain"
        return 0
    fi

    status_error "DOMAIN=$domain"
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
