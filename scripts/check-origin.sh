#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"
. "$SCRIPT_DIR/cli.sh"

ALLOW_ROOT=false

SSL_BASE_LOCAL="$SSL_BASE"
SSL_CERT_DIR_LOCAL="$SSL_CERT_DIR"
SSL_KEY_DIR_LOCAL="$SSL_KEY_DIR"
APACHE_SITES_DIR_LOCAL="$APACHE_SITES_DIR"
WORDPRESS_ROOT_LOCAL="$WORDPRESS_ROOT"

usage() {
    cat <<'USAGE'
Usage: check-origin.sh [OPTIONS] domain1 [domain2...]
Validates origin certificates, Apache configuration, and vhost wiring.
Options:
  --help                Show this help
  --apache-dir DIR      Apache sites-available dir (default: /etc/apache2/sites-available)
USAGE
    cli_usage_common_priv
    cli_usage_ssl_dir
    cli_usage_root
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                ssl-dir|ssl-dir=*)
                    if cli_handle_ssl_dir_opt "${OPTARG}" SSL_BASE_LOCAL SSL_CERT_DIR_LOCAL SSL_KEY_DIR_LOCAL "${!OPTIND-}"; then
                        :
                    else
                        usage; exit 1
                    fi
                    ;;
                apache-dir|apache-dir=*)
                    if [ "${OPTARG}" = "apache-dir" ]; then
                        [ -n "${!OPTIND-}" ] || err "--apache-dir requires a value"
                        APACHE_SITES_DIR_LOCAL="${!OPTIND}"
                        OPTIND=$((OPTIND+1))
                    else
                        APACHE_SITES_DIR_LOCAL="${OPTARG#*=}"
                    fi
                    ;;
                root|root=*)
                    if cli_handle_root_opt "${OPTARG}" WORDPRESS_ROOT_LOCAL "${!OPTIND-}"; then
                        :
                    else
                        usage; exit 1
                    fi
                    ;;
                *)
                    if cli_handle_common_opt "${OPTARG}"; then
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

[ $# -ge 1 ] || { usage; exit 1; }

cli_require_non_root

require_cmd openssl
require_cmd apache2ctl
require_cmd systemctl
require_cmd stat
require_cmd grep

check_module() {
    local module="$1"
    if priv apache2ctl -M | grep -q "${module}_module"; then
        echo "Apache module enabled: ${module}"
    else
        echo "Error: Apache module missing: ${module}"
        return 1
    fi
}

check_file_perms() {
    local path="$1"
    local expected="$2"
    local actual
    actual=$(priv stat -c "%U:%G %a" "$path" 2>/dev/null || true)
    if [ -z "$actual" ]; then
        echo "Warning: Unable to read permissions for $path"
        return 0
    fi
    if [ "$actual" != "$expected" ]; then
        echo "Error: $path permissions are $actual (expected $expected)"
        return 1
    fi
    echo "Permissions ok: $path ($actual)"
}

check_domain() {
    local domain
    domain=$(tolower "$1")
    local ok=true

    echo ""
    log "Origin checks for: $domain"

    local safe
    safe=$(safe_name "$domain")
    local cert_file="$SSL_CERT_DIR_LOCAL/${safe}.crt"
    local key_file="$SSL_KEY_DIR_LOCAL/${safe}.key"

    if priv test -r "$cert_file"; then
        echo "Certificate found: $cert_file"
    else
        echo "Error: Certificate missing or unreadable: $cert_file"
        ok=false
    fi

    if priv test -r "$key_file"; then
        echo "Key found: $key_file"
    else
        echo "Error: Key missing or unreadable: $key_file"
        ok=false
    fi

    if priv test -r "$cert_file"; then
        check_file_perms "$cert_file" "root:ssl-cert 640" || ok=false
        priv openssl x509 -in "$cert_file" -noout -subject -issuer -dates -ext subjectAltName || true
    fi

    if priv test -r "$key_file"; then
        check_file_perms "$key_file" "root:ssl-cert 640" || ok=false
    fi

    local http_conf="$APACHE_SITES_DIR_LOCAL/${safe}.conf"
    local ssl_conf="$APACHE_SITES_DIR_LOCAL/${safe}-ssl.conf"

    if priv test -f "$http_conf"; then
        echo "HTTP vhost present: $http_conf"
        if ! priv grep -q "ServerName $domain" "$http_conf"; then
            echo "Error: HTTP vhost missing ServerName $domain"
            ok=false
        fi
        if ! priv grep -q "DocumentRoot $WORDPRESS_ROOT_LOCAL" "$http_conf"; then
            echo "Error: HTTP vhost DocumentRoot mismatch (expected $WORDPRESS_ROOT_LOCAL)"
            ok=false
        fi
    else
        echo "Error: HTTP vhost missing: $http_conf"
        ok=false
    fi

    if priv test -f "$ssl_conf"; then
        echo "SSL vhost present: $ssl_conf"
        if ! priv grep -q "ServerName $domain" "$ssl_conf"; then
            echo "Error: SSL vhost missing ServerName $domain"
            ok=false
        fi
        if ! priv grep -q "DocumentRoot $WORDPRESS_ROOT_LOCAL" "$ssl_conf"; then
            echo "Error: SSL vhost DocumentRoot mismatch (expected $WORDPRESS_ROOT_LOCAL)"
            ok=false
        fi
        if ! priv grep -q "SSLCertificateFile $cert_file" "$ssl_conf"; then
            echo "Error: SSL vhost missing SSLCertificateFile $cert_file"
            ok=false
        fi
        if ! priv grep -q "SSLCertificateKeyFile $key_file" "$ssl_conf"; then
            echo "Error: SSL vhost missing SSLCertificateKeyFile $key_file"
            ok=false
        fi
    else
        echo "Error: SSL vhost missing: $ssl_conf"
        ok=false
    fi

    if [ "$ok" = true ]; then
        echo "Origin checks passed for $domain"
        return 0
    fi

    echo "Origin checks failed for $domain"
    return 1
}

system_ok=true
if priv apache2ctl configtest; then
    echo "Apache configtest passed"
else
    echo "Error: Apache configtest failed"
    system_ok=false
fi

if systemctl is-active --quiet apache2; then
    echo "Apache service is active"
else
    echo "Error: Apache service is not active"
    system_ok=false
fi

if ! check_module "rewrite"; then
    system_ok=false
fi
if ! check_module "ssl"; then
    system_ok=false
fi
if ! check_module "headers"; then
    system_ok=false
fi

overall_ok=true
for domain in "$@"; do
    if ! check_domain "$domain"; then
        overall_ok=false
    fi
done

if [ "$system_ok" != true ] || [ "$overall_ok" != true ]; then
    exit 1
fi
