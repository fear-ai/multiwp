#!/bin/bash
# check-wp.sh - Validate WordPress site URLs and multisite mappings.
# For options, environment variables, defaults see usage().
#
# Example: check-wp.sh [OPTIONS] domain1 [domain2...]

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/cli.sh"

WORDPRESS_ROOT_LOCAL="$WORDPRESS_ROOT"
MODE="auto"
ALLOW_ROOT=false
DOMAINS=()

usage() {
    cat <<EOF
check-wp.sh - Validate WordPress site URLs for domains.
Example: check-wp.sh [OPTIONS] domain1 [domain2...]

Options:
  --singlesite  Validate a single-site WordPress install (no multisite tables)
  --multisite  Validate a multisite network
  --autosite (default)  Auto-detect single-site vs multisite
$(cli_usage_domain)
$(cli_usage_wp_root)
$(cli_usage_common_priv)
  --help  Show this help

Notes:
  - Redirect-only domains (from domains.csv) are skipped.
  - Set DOMAINS_CSV to change the default domains.csv location.
EOF
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
                singlesite) MODE="single" ;;
                multisite) MODE="multisite" ;;
                autosite) MODE="auto" ;;
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

require_cmds wp awk

if [ "$MODE" = "auto" ]; then
    if priv -u www-data wp --path="$WORDPRESS_ROOT_LOCAL" core is-installed --network 2>/dev/null; then
        MODE="multisite"
    elif priv -u www-data wp --path="$WORDPRESS_ROOT_LOCAL" core is-installed 2>/dev/null; then
        MODE="single"
    else
        err "WordPress not installed at $WORDPRESS_ROOT_LOCAL"
    fi
fi

if [ "$MODE" = "multisite" ]; then
    if ! priv -u www-data wp --path="$WORDPRESS_ROOT_LOCAL" core is-installed --network 2>/dev/null; then
        err "WordPress multisite not found or not installed at $WORDPRESS_ROOT_LOCAL"
    fi
else
    if ! priv -u www-data wp --path="$WORDPRESS_ROOT_LOCAL" core is-installed 2>/dev/null; then
        err "WordPress not installed at $WORDPRESS_ROOT_LOCAL"
    fi
fi

TABLE_PREFIX=$(priv -u www-data wp --path="$WORDPRESS_ROOT_LOCAL" config get table_prefix 2>/dev/null || true)
if [ -z "$TABLE_PREFIX" ]; then
    TABLE_PREFIX="wp_"
fi

check_domain_multisite() {
    local domain
    domain=$(tolower "$1")
    local ok=true

    if is_redirect_domain "$domain"; then
        log "Redirect-only domain; WordPress checks skipped: $domain"
        return 0
    fi

    echo ""
    log "WordPress checks for: $domain"

    local expected_siteurl expected_home
    expected_siteurl="https://$domain"
    expected_home="$expected_siteurl"

    local site_csv
    site_csv=$(priv -u www-data wp --path="$WORDPRESS_ROOT_LOCAL" site list --fields=blog_id,url,domain,path --format=csv)
    local site_line
    site_line=$(echo "$site_csv" | awk -F, -v domain="$domain" 'NR>1 && $3==domain {print $0; exit}')

    if [ -z "$site_line" ]; then
        fail "Domain not found in wp site list"
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
        fail "Expected path '/' in wp_blogs, found '$path'"
        ok=false
    fi

    if [[ "$url" != "$expected_siteurl" && "$url" != "${expected_siteurl%/}/" ]]; then
        fail "Site URL does not match $expected_siteurl"
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
        fail "wp_blogs mismatch (domain='$db_domain', path='$db_path')"
        ok=false
    else
        echo "wp_blogs mapping ok"
    fi

    local options_table
    if [ "$blog_id" = "1" ]; then
        options_table="${TABLE_PREFIX}options"
    else
        options_table="${TABLE_PREFIX}${blog_id}_options"
    fi

    local options
    options=$(priv -u www-data wp --path="$WORDPRESS_ROOT_LOCAL" db query \
        "SELECT option_name, option_value FROM ${options_table} WHERE option_name IN ('siteurl','home');" \
        --skip-column-names)

    local siteurl home
    siteurl=$(echo "$options" | awk '$1=="siteurl" {print $2}')
    home=$(echo "$options" | awk '$1=="home" {print $2}')

    if [ "$siteurl" != "$expected_siteurl" ]; then
        fail "siteurl is '$siteurl' (expected '$expected_siteurl')"
        ok=false
    else
        echo "siteurl ok"
    fi

    if [ "$home" != "$expected_home" ]; then
        fail "home is '$home' (expected '$expected_home')"
        ok=false
    else
        echo "home ok"
    fi

    local wp_config="$WORDPRESS_ROOT_LOCAL/wp-config.php"
    if priv test -r "$wp_config"; then
        if priv grep -q "define( *'MULTISITE'" "$wp_config"; then
            echo "wp-config.php multisite constants detected"
        else
            warn "MULTISITE constant not found in wp-config.php"
        fi
    else
        warn "wp-config.php not readable at $wp_config"
    fi

    local htaccess="$WORDPRESS_ROOT_LOCAL/.htaccess"
    if priv test -r "$htaccess"; then
        if priv grep -q "RewriteRule" "$htaccess"; then
            echo ".htaccess rewrite rules detected"
        else
            warn ".htaccess rewrite rules not detected"
        fi
    else
        warn ".htaccess not readable at $htaccess"
    fi

    if [ "$ok" = true ]; then
        echo "WordPress checks passed for $domain"
        return 0
    fi

    echo "WordPress checks failed for $domain"
    return 1
}

check_domain_single() {
    local domain
    domain=$(tolower "$1")
    local ok=true

    if is_redirect_domain "$domain"; then
        log "Redirect-only domain; WordPress checks skipped: $domain"
        return 0
    fi

    echo ""
    log "WordPress checks for: $domain"

    local expected_siteurl expected_home
    expected_siteurl="https://$domain"
    expected_home="$expected_siteurl"

    local siteurl home
    siteurl=$(priv -u www-data wp --path="$WORDPRESS_ROOT_LOCAL" option get siteurl 2>/dev/null || true)
    home=$(priv -u www-data wp --path="$WORDPRESS_ROOT_LOCAL" option get home 2>/dev/null || true)

    if [ -z "$siteurl" ] || [ -z "$home" ]; then
        fail "Unable to read siteurl/home options"
        ok=false
    else
        echo "siteurl: $siteurl"
        echo "home: $home"
    fi

    if [ "$siteurl" != "$expected_siteurl" ] && [ "$siteurl" != "${expected_siteurl%/}/" ]; then
        fail "siteurl is '$siteurl' (expected '$expected_siteurl')"
        ok=false
    else
        echo "siteurl ok"
    fi

    if [ "$home" != "$expected_home" ] && [ "$home" != "${expected_home%/}/" ]; then
        fail "home is '$home' (expected '$expected_home')"
        ok=false
    else
        echo "home ok"
    fi

    if [ "$ok" = true ]; then
        echo "WordPress checks passed for $domain"
        return 0
    fi

    echo "WordPress checks failed for $domain"
    return 1
}

overall_ok=true
for domain in "${DOMAINS[@]}"; do
    if [ "$MODE" = "multisite" ]; then
        if ! check_domain_multisite "$domain"; then
            overall_ok=false
        fi
    else
        if ! check_domain_single "$domain"; then
            overall_ok=false
        fi
    fi
done

if [ "$overall_ok" != true ]; then
    exit 1
fi
