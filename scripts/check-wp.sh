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
TEMPLATE_DIR_LOCAL="$TEMPLATE_DIR"
WP_STAGE_LOCAL="${WP_STAGE-}"
MODE="auto"
ALLOW_ROOT=false
DOMAINS=()
TEMPLATE_CHECK=false
TEMPLATE_REPORTED=false
TEMPLATE_CHECK_DONE=false
WP_CONFIG_TEMPLATE=""
WP_CONFIG_TEMPLATE_CANDIDATE=""
WP_CONFIG_TEMPLATE_FALLBACK=""
WP_CONFIG_AMEND_STAGE=""
WP_CONFIG_AMEND_BASE=""
HTACCESS_TEMPLATE=""
HTACCESS_TEMPLATE_CANDIDATE=""
HTACCESS_TEMPLATE_FALLBACK=""
HTACCESS_AMEND_STAGE=""
HTACCESS_AMEND_BASE=""

usage() {
    cat <<EOF
check-wp.sh - Validate WordPress site URLs for domains.
Example: check-wp.sh [OPTIONS] domain1 [domain2...]

Options:
  --singlesite  Validate a single-site WordPress install (no multisite tables)
  --multisite  Validate a multisite network
  --autosite (default)  Auto-detect single-site vs multisite
  --template-dir DIR [TEMPLATE_DIR] (default: $TEMPLATE_DIR)  Templates directory
  --stage NAME [WP_STAGE] (default: current)  Template stage suffix (example: ssl, prod)
  --template-check  Compare wp-config.php and .htaccess against selected templates
$(cli_usage_domain)
$(cli_usage_wp_root)
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
                singlesite) MODE="singlesite" ;;
                multisite) MODE="multisite" ;;
                autosite) MODE="auto" ;;
                template-dir|template-dir=*)
                    if cli_template_dir_opt "${OPTARG}" TEMPLATE_DIR_LOCAL "${!OPTIND-}"; then
                        :
                    else
                        usage; exit 1
                    fi
                    ;;
                stage|stage=*)
                    if cli_stage_opt "${OPTARG}" WP_STAGE_LOCAL "${!OPTIND-}"; then
                        :
                    else
                        usage; exit 1
                    fi
                    ;;
                template-check) TEMPLATE_CHECK=true ;;
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

require_cmds wp awk sort

load_template_paths() {
    local site_type="$1"
    local stage="$2"
    local template_dir="$3"
    local line key val

    while IFS=: read -r key val; do
        case "$key" in
            selected) WP_CONFIG_TEMPLATE="$val" ;;
            candidate) WP_CONFIG_TEMPLATE_CANDIDATE="$val" ;;
            fallback) WP_CONFIG_TEMPLATE_FALLBACK="$val" ;;
            amend_stage) WP_CONFIG_AMEND_STAGE="$val" ;;
            amend_base) WP_CONFIG_AMEND_BASE="$val" ;;
        esac
    done < <(wp_template_list "wp-config" "$site_type" "$stage" "$template_dir")

    while IFS=: read -r key val; do
        case "$key" in
            selected) HTACCESS_TEMPLATE="$val" ;;
            candidate) HTACCESS_TEMPLATE_CANDIDATE="$val" ;;
            fallback) HTACCESS_TEMPLATE_FALLBACK="$val" ;;
            amend_stage) HTACCESS_AMEND_STAGE="$val" ;;
            amend_base) HTACCESS_AMEND_BASE="$val" ;;
        esac
    done < <(wp_template_list "htaccess" "$site_type" "$stage" "$template_dir")
}

report_templates() {
    if [ "$TEMPLATE_REPORTED" = true ]; then
        return 0
    fi
    TEMPLATE_REPORTED=true
    echo ""
    log "Template selection"
    echo "Template dir: $TEMPLATE_DIR_LOCAL"
    if [ -n "$WP_STAGE_LOCAL" ]; then
        echo "Template stage: $WP_STAGE_LOCAL"
    else
        echo "Template stage: current"
    fi
    echo "wp-config template: $WP_CONFIG_TEMPLATE"
    if [ "$WP_CONFIG_TEMPLATE_CANDIDATE" != "$WP_CONFIG_TEMPLATE_FALLBACK" ] && [ "$WP_CONFIG_TEMPLATE" = "$WP_CONFIG_TEMPLATE_FALLBACK" ]; then
        warn "wp-config stage template not found; using fallback $WP_CONFIG_TEMPLATE_FALLBACK"
    fi
    if [ -f "$WP_CONFIG_AMEND_BASE" ]; then
        echo "wp-config amend: $WP_CONFIG_AMEND_BASE"
    fi
    if [ -f "$WP_CONFIG_AMEND_STAGE" ]; then
        echo "wp-config amend (stage): $WP_CONFIG_AMEND_STAGE"
    fi
    echo ".htaccess template: $HTACCESS_TEMPLATE"
    if [ "$HTACCESS_TEMPLATE_CANDIDATE" != "$HTACCESS_TEMPLATE_FALLBACK" ] && [ "$HTACCESS_TEMPLATE" = "$HTACCESS_TEMPLATE_FALLBACK" ]; then
        warn ".htaccess stage template not found; using fallback $HTACCESS_TEMPLATE_FALLBACK"
    fi
    if [ -f "$HTACCESS_AMEND_BASE" ]; then
        echo ".htaccess amend: $HTACCESS_AMEND_BASE"
    fi
    if [ -f "$HTACCESS_AMEND_STAGE" ]; then
        echo ".htaccess amend (stage): $HTACCESS_AMEND_STAGE"
    fi
}

extract_define_names() {
    local template="$1"
    awk '
        /^[[:space:]]*(\/\/|#|\/\*)/ { next }
        match($0, /define[[:space:]]*\\([[:space:]]*["'"'"']([A-Z0-9_]+)["'"'"']/, m) {
            print m[1]
        }
    ' "$template" | sort -u
}

extract_htaccess_rules() {
    local template="$1"
    awk '
        /^[[:space:]]*(#|$)/ { next }
        /^[[:space:]]*Rewrite(Engine|Cond|Rule|Base)/ {
            sub(/^[[:space:]]+/, "", $0);
            print
        }
    ' "$template"
}

template_check_wp_config() {
    local wp_config="$1"
    local template
    local -a templates=()
    if [ -f "$WP_CONFIG_TEMPLATE" ]; then
        templates+=("$WP_CONFIG_TEMPLATE")
    fi
    if [ -f "$WP_CONFIG_AMEND_BASE" ]; then
        templates+=("$WP_CONFIG_AMEND_BASE")
    fi
    if [ -f "$WP_CONFIG_AMEND_STAGE" ]; then
        templates+=("$WP_CONFIG_AMEND_STAGE")
    fi
    if [ ${#templates[@]} -eq 0 ]; then
        warn "No wp-config templates found for template check"
        return 0
    fi
    if ! priv test -r "$wp_config"; then
        warn "wp-config.php not readable for template check: $wp_config"
        return 0
    fi
    for template in "${templates[@]}"; do
        while read -r name; do
            [ -n "$name" ] || continue
            if ! priv grep -Eq "define[[:space:]]*\\([[:space:]]*['\"]${name}['\"]" "$wp_config"; then
                warn "wp-config.php missing define ${name} (template: $(basename "$template"))"
            fi
        done < <(extract_define_names "$template")
    done
}

template_check_htaccess() {
    local htaccess="$1"
    local template
    local -a templates=()
    if [ -f "$HTACCESS_TEMPLATE" ]; then
        templates+=("$HTACCESS_TEMPLATE")
    fi
    if [ -f "$HTACCESS_AMEND_BASE" ]; then
        templates+=("$HTACCESS_AMEND_BASE")
    fi
    if [ -f "$HTACCESS_AMEND_STAGE" ]; then
        templates+=("$HTACCESS_AMEND_STAGE")
    fi
    if [ ${#templates[@]} -eq 0 ]; then
        warn "No .htaccess templates found for template check"
        return 0
    fi
    if ! priv test -r "$htaccess"; then
        warn ".htaccess not readable for template check: $htaccess"
        return 0
    fi
    for template in "${templates[@]}"; do
        while read -r line; do
            [ -n "$line" ] || continue
            if ! priv grep -Fq "$line" "$htaccess"; then
                warn ".htaccess missing line '${line}' (template: $(basename "$template"))"
            fi
        done < <(extract_htaccess_rules "$template")
    done
}

maybe_check_templates() {
    if [ "$TEMPLATE_CHECK" != true ]; then
        return 0
    fi
    if [ "$TEMPLATE_CHECK_DONE" = true ]; then
        return 0
    fi
    TEMPLATE_CHECK_DONE=true
    template_check_wp_config "$WORDPRESS_ROOT_LOCAL/wp-config.php"
    template_check_htaccess "$WORDPRESS_ROOT_LOCAL/.htaccess"
}

if [ "$MODE" = "auto" ]; then
    if priv -u www-data wp --path="$WORDPRESS_ROOT_LOCAL" core is-installed --network 2>/dev/null; then
        MODE="multisite"
    elif priv -u www-data wp --path="$WORDPRESS_ROOT_LOCAL" core is-installed 2>/dev/null; then
        MODE="singlesite"
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

load_template_paths "$MODE" "$WP_STAGE_LOCAL" "$TEMPLATE_DIR_LOCAL"
report_templates

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
maybe_check_templates
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
