#!/bin/bash
# cloud-cert.sh - Download Cloudflare Origin certificates for domains
# Creates individual .crt and .key files using domain-based naming
#
# Usage: ./cloud-cert.sh domain.com
#
# Prerequisites:
# - Cloudflare API token with Zone:Zone:Read and SSL and Certificates:Edit permissions
# - jq installed for JSON processing
# - curl for API requests
#
# Environment variables:
# CF_API_TOKEN - Cloudflare API token (required)
# SSL_CERT_DIR - Certificate directory (default: /etc/ssl/certs)
# SSL_KEY_DIR - Private key directory (default: /etc/ssl/private)

set -e

# Configuration
SSL_CERT_DIR="/etc/ssl/certs"
SSL_KEY_DIR="/etc/ssl/private"
CF_API_BASE="https://api.cloudflare.com/client/v4"

# Function to display help
show_help() {
    echo "cloud-cert.sh - Download Cloudflare Origin certificates"
    echo ""
    echo "Usage: $0 domain.com"
    echo ""
    echo "Environment Variables:"
    echo "  CF_API_TOKEN    Cloudflare API token (required)"
    echo ""
    echo "Prerequisites:"
    echo "  - jq (JSON processor)"
    echo "  - curl"
    echo "  - Cloudflare API token with appropriate permissions"
    echo ""
    exit 0
}

# Validate prerequisites
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_help
fi

if [ -z "$1" ]; then
    echo "Error: Domain name required"
    echo "Usage: $0 domain.com"
    exit 1
fi

if [ -z "$CF_API_TOKEN" ]; then
    echo "Error: CF_API_TOKEN environment variable required"
    echo "Set with: export CF_API_TOKEN='your_api_token'"
    exit 1
fi

# Check required tools
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq not found. Install with: apt install jq"
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "Error: curl not found"
    exit 1
fi

# Check SSL directories exist
if [ ! -d "$SSL_CERT_DIR" ]; then
    echo "Error: SSL certificate directory not found: $SSL_CERT_DIR"
    exit 1
fi

if [ ! -d "$SSL_KEY_DIR" ]; then
    echo "Error: SSL private key directory not found: $SSL_KEY_DIR"
    exit 1
fi

# Function to convert domain name to lower case
tolower() {
    local domain="$1"
    
    # Convert to lowercase
    domain=$(echo "$domain" | tr '[:upper:]' '[:lower:]')
    echo "$domain"
}

# Function to create safe name from domain
create_safe_name() {
    local domain="$1"
    
    # Create safe name by removing dots and hyphens
    local safe_name=$(echo "$domain" | sed 's/[.-]//g')
    
    echo "$safe_name"
}

domain=$(tolower "$1")
safe_name=$(create_safe_name "$domain")
cert_file="$SSL_CERT_DIR/${safe_name}.crt"
key_file="$SSL_KEY_DIR/${safe_name}.key"

echo "Generating Cloudflare Origin certificate for: $domain"
echo "Certificate file: $cert_file"
echo "Private key file: $key_file"

# Check if certificates already exist
if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
    echo "Warning: Certificate files already exist"
    read -p "Overwrite existing certificates? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping certificate generation"
        exit 0
    fi
fi

# Create certificate request payload
payload=$(jq -n \
    --arg domain "$domain" \
    --arg www_domain "www.$DOMAIN" \
    '{
        type: "origin-rsa",
        hostnames: [$domain, $www_domain],
        requested_validity: 5475
    }')

echo "Requesting certificate from Cloudflare API..."

# Make API request
response=$(curl -s -X POST "$CF_API_BASE/certificates" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "$payload")

# Check API response success
success=$(echo "$response" | jq -r '.success')
if [ "$success" != "true" ]; then
    echo "Error: API request failed"
    echo "Errors:" $(echo "$response" | jq -r '.errors[].message' | tr '\n' ' ')
    exit 1
fi

# Extract certificate and private key
certificate=$(echo "$response" | jq -r '.result.certificate')
private_key=$(echo "$response" | jq -r '.result.private_key')

if [ "$certificate" = "null" ] || [ "$private_key" = "null" ]; then
    echo "Error: Failed to extract certificate or private key from response"
    exit 1
fi

# Write certificate file
echo "$certificate" | sudo tee "$cert_file" > /dev/null
echo "Certificate saved: $cert_file"

# Write private key file with secure permissions
echo "$private_key" | sudo tee "$key_file" > /dev/null
sudo chmod 600 "$key_file"
echo "Private key saved: $key_file (permissions: 600)"

# Verify certificate files
if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
    echo ""
    echo "Certificate generation completed successfully"
    echo "Files created:"
    echo "  Certificate: $cert_file"
    echo "  Private key: $key_file"
    
    # Display certificate info
    echo ""
    echo "Certificate details:"
    openssl x509 -in "$cert_file" -text -noout | grep -E "(Subject:|Issuer:|Not Before:|Not After:|DNS:)" || true
else
    echo "Error: Certificate files not created properly"
    exit 1
fi