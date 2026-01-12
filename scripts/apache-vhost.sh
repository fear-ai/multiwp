#!/bin/bash
# apache-vhost.sh - Add Apache vhosts for WordPress domains.
# For options, environment variables, defaults see usage().
#
# Example: apache-vhost.sh [OPTIONS] domain1 [domain2...]

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/cli.sh"
require_cmds a2ensite apache2ctl systemctl

# Configuration (overridable via args/env)
TEMPLATE_DIR="${TEMPLATE_DIR}"
APACHE_DIR="${APACHE_DIR}"
SSL_DIR="${SSL_DIR}"
SSL_CERT_DIR="$SSL_DIR/certs"
SSL_KEY_DIR="$SSL_DIR/keys"
WORDPRESS_ROOT="${WORDPRESS_ROOT}"

# Default behavior
HTTP_ONLY=false
SSL_ONLY=false
DOMAINS=()

usage() {
    cat <<EOF
apache-vhost.sh - Add Apache vhosts for WordPress domains.
Example: apache-vhost.sh [OPTIONS] domain1 [domain2...]

Options:
  --http  Create only HTTP virtual hosts
  --ssl  Create only SSL virtual hosts
$(cli_usage_domain)
  --template PATH [TEMPLATE_DIR] (default: $TEMPLATE_DIR)  Templates directory
$(cli_usage_apache_dir)
$(cli_usage_wp_root)
$(cli_usage_ssl_dir)
  --help  Show this help

Notes:
  - Uses templates in the templates directory and write access to APACHE_DIR.
  - SSL vhosts use origin cert/key files in directories from SSL_DIR.
EOF
}

# Function to check SSL certificates
check_certificates() {
    local domain="$1"
    local safe_name=$(safe_name "$domain")
    # Expect Cloudflare Origin cert/key named after the domain (apex + www)
    # Origin certs are used between Cloudflare and the origin, not publicly.
    local cert_file="$SSL_CERT_DIR/${safe_name}.crt"
    local key_file="$SSL_KEY_DIR/${safe_name}.key"
    
    if [ -f "$cert_file" ]; then
        echo "SSL certificate for $domain found: $cert_file"
    else
        echo "SSL certificate for $domain not found at: $cert_file"
	return 1
    fi

    if [ -f "$key_file" ]; then
        echo "SSL key for $domain found: $key_file"
    else
        echo "SSL key for $domain not found at: $key_file"
	return 1
    fi
}

# Function to process a single domain
process_domain() {
    local domain="$1"
    domain=$(tolower "$domain")
    local safe_name=$(safe_name "$domain")
    local http_done=false
    local ssl_done=false
    local success=true

    echo "Processing domain: $domain"
    
    # Validate domain
    if ! validate_domain "$domain"; then
# special case last domain?
        echo "Error: Domain $domain invalid"
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Skipping $domain"
            return 1
        fi
    fi
    
    local http_conf="$APACHE_DIR/${safe_name}.conf"
    local ssl_conf="$APACHE_DIR/${safe_name}-ssl.conf"

    local http_expected=true
    local ssl_expected=true

    if [ "$SSL_ONLY" = true ]; then
        http_expected=false
    fi
    if [ "$HTTP_ONLY" = true ]; then
        ssl_expected=false
    fi

    local http_existing=false
    local ssl_existing=false

    if test -f "$http_conf"; then
        http_existing=true
    fi
    if test -f "$ssl_conf"; then
        ssl_existing=true
    fi

    # Create HTTP virtual host
    if [ "$SSL_ONLY" != true ]; then
        if [ "$http_existing" = true ]; then
            echo "HTTP vhost already exists: $http_conf (skipping write)"
        else
            echo "Creating HTTP virtual host: $http_conf"
            sed \
                -e "s/{{DOMAIN}}/$domain/g" \
                -e "s/{{SAFE_NAME}}/$safe_name/g" \
                -e "s#{{DOCROOT}}#$WORDPRESS_ROOT#g" \
                "$TEMPLATE_DIR/apache-http.conf" | tee "$http_conf" > /dev/null
        fi
        a2ensite "${safe_name}.conf" >/dev/null
        echo "HTTP vhost enabled: ${safe_name}.conf"
        http_done=true
    fi
    
    # Check SSL certificate availability
    local cert_available=false
    if check_certificates "$domain"; then
        cert_available=true
    fi

    # Create SSL virtual host
    if [ "$HTTP_ONLY" != true ] && [ "$cert_available" = true ]; then
        if [ "$ssl_existing" = true ]; then
            echo "SSL vhost already exists: $ssl_conf (skipping write)"
        else
            echo "Creating SSL virtual host: $ssl_conf"
            sed \
                -e "s/{{DOMAIN}}/$domain/g" \
                -e "s/{{SAFE_NAME}}/$safe_name/g" \
                -e "s#{{DOCROOT}}#$WORDPRESS_ROOT#g" \
                "$TEMPLATE_DIR/apache-ssl.conf" | tee "$ssl_conf" > /dev/null
        fi
        a2ensite "${safe_name}-ssl.conf" >/dev/null
        echo "SSL vhost enabled: ${safe_name}-ssl.conf"
        ssl_done=true
    elif [ "$HTTP_ONLY" = true ]; then
        echo "Skipping SSL per --http option"
    else
        echo "Missing SSL certificate or key for $domain"
    fi
    
    if [ "$http_expected" = true ] && [ "$http_done" = false ]; then
        success=false
    fi
    if [ "$ssl_expected" = true ] && [ "$ssl_done" = false ]; then
        success=false
    fi

    if [ "$success" = true ]; then
        echo "Domain $domain processed successfully"
        return 0
    fi

    echo "Domain $domain encountered issues:"
    if [ "$http_expected" = true ] && [ "$http_done" = false ]; then
        echo "  - HTTP vhost not created (check permissions/template)."
    fi
    if [ "$ssl_expected" = true ] && [ "$ssl_done" = false ]; then
        echo "  - SSL vhost not created (missing cert/key or template)."
    fi
    return 1
}

while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                http) HTTP_ONLY=true ;;
                ssl) SSL_ONLY=true ;;
                domain|domain=*)
                    if cli_domain_opt "${OPTARG}" DOMAINS "${!OPTIND-}"; then
                        :
                    else
                        usage; exit 1
                    fi
                    ;;
                wp-root|wp-root=*)
                    if cli_wp_root_opt "${OPTARG}" WORDPRESS_ROOT "${!OPTIND-}"; then
                        :
                    else
                        usage; exit 1
                    fi
                    ;;
                template=*) TEMPLATE_DIR="${OPTARG#*=}" ;;
                template)
                    [ -n "${!OPTIND-}" ] || err "--template requires a value"
                    TEMPLATE_DIR="${!OPTIND}"
                    OPTIND=$((OPTIND+1))
                    ;;
                apache-dir|apache-dir=*)
                    if cli_apache_dir_opt "${OPTARG}" APACHE_DIR "${!OPTIND-}"; then
                        :
                    else
                        usage; exit 1
                    fi
                    ;;
                ssl-dir|ssl-dir=*)
                    if cli_ssl_dir_opt "${OPTARG}" SSL_DIR SSL_CERT_DIR SSL_KEY_DIR "${!OPTIND-}"; then
                        :
                    else
                        usage; exit 1
                    fi
                    ;;
                help) usage; exit 0 ;;
                *) usage; exit 1 ;;
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
if [ ${#DOMAINS[@]} -eq 0 ]; then
    echo "Error: No domains specified"
    usage
    exit 1
fi

if [ "$HTTP_ONLY" = true ] && [ "$SSL_ONLY" = true ]; then
    echo "Error: --http and --ssl are mutually exclusive"
    exit 1
fi

# Verify prerequisites
if [ ! -d "$TEMPLATE_DIR" ]; then
    echo "Error: Template directory not found: $TEMPLATE_DIR"
    exit 1
fi

if [ ! -f "$TEMPLATE_DIR/apache-http.conf" ]; then
    echo "Error: HTTP template not found: $TEMPLATE_DIR/apache-http.conf"
    exit 1
fi

if [ ! -f "$TEMPLATE_DIR/apache-ssl.conf" ] ; then
    echo "Error: SSL template not found: $TEMPLATE_DIR/apache-ssl.conf"
    exit 1
fi

# Verify we can write to Apache sites dir (requires sudo)
if ! test -w "$APACHE_DIR"; then
    echo "Error: Need write access to $APACHE_DIR."
    exit 1
fi
if ! test -r "$SSL_CERT_DIR" || ! test -r "$SSL_KEY_DIR"; then
    echo "Error: Need read to $SSL_CERT_DIR and $SSL_KEY_DIR."
fi

# Display configuration
# special case message for 1 domain?
echo "Adding ${#DOMAINS[@]} domain(s) to WordPress multisite"
echo "WordPress root: $WORDPRESS_ROOT"
echo "Templates: $TEMPLATE_DIR"
echo "SSL dir: $SSL_DIR"
echo "Apache sites: $APACHE_DIR"
echo ""

# Process each domain
processed_count=0
failed_count=0

for domain in "${DOMAINS[@]}"; do
    echo "----------------------------------------"
    if process_domain "$domain"; then
        ((processed_count++))
    else
        ((failed_count++))
    fi
    echo
done

# Test Apache configuration and reload
echo "Testing Apache configuration..."
if apache2ctl configtest; then
    echo "Apache configuration valid, reloading"
    systemctl reload apache2
else
    echo "Apache configuration failed"
    echo "Check the generated virtual host files and fix syntax errors"
    exit 1
fi

# Summary
echo "========================================="
echo "Domains Added"
echo "Success: $processed_count"
echo "Fail: $failed_count"
echo ""
