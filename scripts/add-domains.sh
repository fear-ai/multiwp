#!/bin/bash
# add-domains.sh - Add domains to WordPress multisite
# Creates Apache virtual hosts using templates with enhanced validation and flexibility
#
# Usage: ./add-domains.sh [OPTIONS] domain1.com domain2.com ...
# Options:
#   --http            Create only HTTP virtual hosts
#   --ssl             Create only SSL virtual hosts (requires certificates)
#   --root PATH       Set WordPress root directory (default: /var/www/html/wordpress)
#   --temp PATH       Set templates directory (default: ../templates)
#   --help            Show this help message
#
# Examples:
#   ./add-domains.sh client1.com client2.com client3.com
#   ./add-domains.sh --http test-domain.org
#   ./add-domains.sh --ssl secure-site.com
#   ./add-domains.sh --root /opt/wordpress --temp /etc/multiwp/templates client.com

set -e

# Configuration
TEMPLATE_DIR="../templates"
APACHE_SITES_DIR="/etc/apache2/sites-available"
SSL_CERT_DIR="/etc/ssl/cloudflare-origin/certs"
SSL_KEY_DIR="/etc/ssl/cloudflare-origin/keys"
WORDPRESS_ROOT="/var/www/html/wordpress"

# Default behavior
HTTP_ONLY=false
SSL_ONLY=false
DOMAINS=()

# Function to display help
show_help() {
    echo "add-domains.sh - Add domains to WordPress multisite"
    echo ""
    echo "Usage: $0 [OPTIONS] domain1.com domain2.com ..."
    echo ""
    echo "Options:"
    echo "  --http            Create only HTTP virtual hosts"
    echo "  --ssl             Create only SSL virtual hosts"
    echo "  --root PATH       Set WordPress root directory"
    echo "  --temp PATH       Set templates directory"
    echo "  --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 client1.com client2.com client3.com"
    echo "  $0 --http test-domain.org"
    echo "  $0 --ssl secure-site.com"
    echo "  $0 --root /opt/wordpress --temp /etc/multiwp/templates client.com"
    echo ""
    exit 0
}

# Function to convert domain name to lower case
tolower() {
    local domain="$1"
    
    # Convert to lowercase
    domain=$(echo "$domain" | tr '[:upper:]' '[:lower:]')
    echo "$domain"
}

# Function to validate domain name
validate_domain() {
    local domain="$1"
    
    # Convert to lowercase
    domain=$(tolower $domain)
    
    # Check maximum total length (255 characters)
    if [ ${#domain} -gt 255 ]; then
        echo "Error: $domain exceeds maximum length (255 characters)"
        return 1
    fi
    
    # Extract and validate TLD length (63 characters max)
    local tld="${domain##*.}"
    if [ ${#tld} -gt 63 ]; then
        echo "Error: TLD '$tld' exceeds maximum length (63 characters)"
        return 1
    fi
    
    # Check for forbidden starting characters
    if [[ "$domain" =~ ^[.-] ]]; then
        echo "Error: $domain cannot start with dot or hyphen"
        return 1
    fi
    
    # Check for ..
    if [[ "$domain" =~ \.\. ]]; then
        echo "Error: $domain contains double dots"
        return 1
    fi
    
    # Basic validation: alphanumeric, dots, hyphens, must have TLD
    if [[ ! "$domain" =~ ^[a-z0-9.-]+\.[a-z]{2,}$ ]]; then
        echo "Error: $domain name not valid"
        return 1
    fi
    
    return 0
}

# Function to create safe name from domain
create_safe_name() {
    local domain="$1"
    
    # Create safe name by removing dots and hyphens
    local safe_name=$(echo "$domain" | sed 's/[.-]//g')
    
    echo "$safe_name"
}

# Function to check SSL certificates
check_certificates() {
    local domain="$1"
    local safe_name=$(create_safe_name "$domain")
    # Expect Cloudflare Origin cert/key named after the domain (apex + www covered by the same cert)
    # Origin certs are only validated between Cloudflare and the origin; they are not public-trust.
    local cert_file="$SSL_CERT_DIR/${safe_name}.crt"
    local key_file="$SSL_KEY_DIR/${safe_name}.key"
    
    if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
        echo "SSL certificates found for $domain"
        return 0
    else
        echo "SSL certificate or key file not found for $domain"
        echo "Expected: $cert_file"
        echo "Expected: $key_file"
        return 1
    fi
}

# Function to process a single domain
process_domain() {
    local domain="$1"
    domain=$(tolower "$domain")
    local safe_name=$(create_safe_name "$domain")
    
    echo "Processing domain: $domain"
    
    # Validate domain
    if ! validate_domain "$domain"; then
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Skipping $domain"
            return 1
        fi
    fi
    
    local http_conf="$APACHE_SITES_DIR/${safe_name}.conf"
    
    # Create HTTP virtual host
    if [ "$SSL_ONLY" != true ]; then
        echo "Creating HTTP virtual host: $http_conf"
        sed -e "s/{{DOMAIN}}/$domain/g" -e "s/{{SAFE_NAME}}/$safe_name/g" "$TEMPLATE_DIR/apache-http.conf" | sudo tee "$http_conf" > /dev/null
        
        # Enable HTTP virtual host
        sudo a2ensite "${safe_name}.conf"
        echo "HTTP virtual host enabled: $http_conf"
    fi
    
    local ssl_conf="$APACHE_SITES_DIR/${safe_name}-ssl.conf"

    # Check SSL certificate availability
    local cert_available=false
    if check_certificates "$domain"; then
        cert_available=true
    fi

    # Create SSL virtual host
    if [ "$HTTP_ONLY" != true ] && [ "$cert_available" = true ]; then
        echo "Creating SSL virtual host: $ssl_conf"
        sed -e "s/{{DOMAIN}}/$domain/g" -e "s/{{SAFE_NAME}}/$safe_name/g" "$TEMPLATE_DIR/apache-ssl.conf" | sudo tee "$ssl_conf" > /dev/null

        # Enable SSL virtual host
        sudo a2ensite "${safe_name}-ssl.conf"
        echo "SSL virtual host enabled: $ssl_conf"
    else
        echo "SSL certificates not available"
    fi
    
    echo "Domain $domain processed successfully"
    return 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --http)
            HTTP_ONLY=true
            shift
            ;;
        --ssl)
            SSL_ONLY=true
            shift
            ;;
        --root)
            if [ -z "$2" ]; then
                echo "Error: --root requires a path argument"
                exit 1
            fi
            WORDPRESS_ROOT="$2"
            shift 2
            ;;
        --temp)
            if [ -z "$2" ]; then
                echo "Error: --temp requires a path argument"
                exit 1
            fi
            TEMPLATE_DIR="$2"
            shift 2
            ;;
        --help)
            show_help
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            DOMAINS+=("$1")
            shift
            ;;
    esac
done

# Validate arguments
if [ ${#DOMAINS[@]} -eq 0 ]; then
    echo "Error: No domains specified"
    echo "Usage: $0 [OPTIONS] domain1.com domain2.com ..."
    echo "Use --help for more information"
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

# Display configuration
echo "Adding ${#DOMAINS[@]} domain(s) to WordPress multisite"
echo "WordPress root: $WORDPRESS_ROOT"
echo "Templates directory: $TEMPLATE_DIR"
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
if sudo apache2ctl configtest; then
    echo "Apache configuration valid, reloading"
    sudo systemctl reload apache2
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

if [ $processed_count -gt 0 ]; then
    echo "Next steps for each domain:"
    echo "1. Add DNS record pointing domain(s) to server IP"
    echo "2. Create WordPress sites in Network Admin"
    echo "3. Generate SSL certificates as needed"
    echo ""
fi
