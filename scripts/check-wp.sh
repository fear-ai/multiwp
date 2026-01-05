#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"

WORDPRESS_ROOT_LOCAL="$WORDPRESS_ROOT"

usage() {
    cat <<'USAGE'
Usage: check-wp.sh [OPTIONS] domain1 [domain2...]
Validates WordPress multisite mapping and site URLs for apex domains.
Options:
  --help         Show this help
  --root PATH    WordPress root (default: /var/www/html/wordpress)
USAGE
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                root=*) WORDPRESS_ROOT_LOCAL="${OPTARG#*=}" ;;
                *) usage; exit 1 ;;
            esac
            ;;
        \?) usage; exit 1 ;;
    esac
done
shift $((OPTIND-1))

[ $# -ge 1 ] || { usage; exit 1; }

if [ "${USER:-}" = "root" ]; then
    err "Do not run as root. Run as an Ubuntu user with sudo privileges."
fi

require_cmd wp
require_cmd awk

if ! priv -u www-data wp --path="$WORDPRESS_ROOT_LOCAL" core is-installed --network 2>/dev/null; then
    err "WordPress multisite not found or not installed at $WORDPRESS_ROOT_LOCAL"
fi

TABLE_PREFIX=$(priv -u www-data wp --path="$WORDPRESS_ROOT_LOCAL" config get table_prefix 2>/dev/null || true)
if [ -z "$TABLE_PREFIX" ]; then
    TABLE_PREFIX="wp_"
fi

check_domain() {
    local domain
    domain=$(tolower "$1")
    local ok=true

    echo ""
    log "WordPress checks for: $domain"

    local site_csv
    site_csv=$(priv -u www-data wp --path="$WORDPRESS_ROOT_LOCAL" site list --fields=blog_id,url,domain,path --format=csv)
    local site_line
    site_line=$(echo "$site_csv" | awk -F, -v domain="$domain" 'NR>1 && $3==domain {print $0; exit}')

    if [ -z "$site_line" ]; then
        echo "Error: Domain not found in wp site list"
        return 1
    fi

    local blog_id url path
    blog_id=$(echo "$site_line" | awk -F, '{print $1}')
    url=$(echo "$site_line" | awk -F, '{print $2}')
    path=$(echo "$site_line" | awk -F, '{print $4}')

    echo "Blog ID: $blog_id"
    echo "URL: $url"
    echo "Path: $path"

    if [ "$path" != "/" ]; then
        echo "Error: Expected path '/' in wp_blogs, found '$path'"
        ok=false
    fi

    if [[ "$url" != "https://$domain" && "$url" != "https://$domain/" ]]; then
        echo "Error: Site URL does not match https://$domain"
        ok=false
    fi

    local blog_row
    blog_row=$(priv -u www-data wp --path="$WORDPRESS_ROOT_LOCAL" db query \
        "SELECT domain, path FROM ${TABLE_PREFIX}blogs WHERE blog_id=${blog_id};" \
        --skip-column-names)
    local db_domain db_path
    db_domain=$(echo "$blog_row" | awk '{print $1}')
    db_path=$(echo "$blog_row" | awk '{print $2}')

    if [ "$db_domain" != "$domain" ] || [ "$db_path" != "/" ]; then
        echo "Error: wp_blogs mismatch (domain='$db_domain', path='$db_path')"
        ok=false
    else
        echo "wp_blogs mapping ok"
    fi

    local options
    options=$(priv -u www-data wp --path="$WORDPRESS_ROOT_LOCAL" db query \
        "SELECT option_name, option_value FROM ${TABLE_PREFIX}${blog_id}_options WHERE option_name IN ('siteurl','home');" \
        --skip-column-names)

    local siteurl home
    siteurl=$(echo "$options" | awk '$1=="siteurl" {print $2}')
    home=$(echo "$options" | awk '$1=="home" {print $2}')

    if [ "$siteurl" != "https://$domain" ]; then
        echo "Error: siteurl is '$siteurl' (expected 'https://$domain')"
        ok=false
    else
        echo "siteurl ok"
    fi

    if [ "$home" != "https://$domain" ]; then
        echo "Error: home is '$home' (expected 'https://$domain')"
        ok=false
    else
        echo "home ok"
    fi

    local wp_config="$WORDPRESS_ROOT_LOCAL/wp-config.php"
    if priv test -r "$wp_config"; then
        if priv grep -q "define( *'MULTISITE'" "$wp_config"; then
            echo "wp-config.php multisite constants detected"
        else
            echo "Warning: MULTISITE constant not found in wp-config.php"
        fi
    else
        echo "Warning: wp-config.php not readable at $wp_config"
    fi

    local htaccess="$WORDPRESS_ROOT_LOCAL/.htaccess"
    if priv test -r "$htaccess"; then
        if priv grep -q "RewriteRule" "$htaccess"; then
            echo ".htaccess rewrite rules detected"
        else
            echo "Warning: .htaccess rewrite rules not detected"
        fi
    else
        echo "Warning: .htaccess not readable at $htaccess"
    fi

    if [ "$ok" = true ]; then
        echo "WordPress checks passed for $domain"
        return 0
    fi

    echo "WordPress checks failed for $domain"
    return 1
}

overall_ok=true
for domain in "$@"; do
    if ! check_domain "$domain"; then
        overall_ok=false
    fi
done

if [ "$overall_ok" != true ]; then
    exit 1
fi
