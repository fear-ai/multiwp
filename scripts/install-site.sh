#!/bin/bash
# install-site.sh - Add a new site to WordPress Multisite and map to apex domain
#
# Usage: ./install-site.sh <domain> [title] [email]
# Example: ./install-site.sh example.com "Example Site" admin@example.com
#
# Prerequisites:
# - WordPress multisite already configured and running
# - Apache vhost and SSL certificate already in place for the domain
# - DNS pointing to server (via Cloudflare proxy)
#
# This script:
# 1. Creates a new site in the multisite network with a subdirectory slug
# 2. Maps the site to the apex domain in wp_blogs table
# 3. Updates siteurl and home URLs to use HTTPS and the apex domain
# 4. Verifies the site was created successfully

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"

require_cmd wp

usage() {
    cat <<'EOF'
Usage: install-site.sh [OPTIONS] <domain> [title] [email]

Creates a new site in WordPress multisite and maps it to an apex domain.

Arguments:
  domain    The apex domain (e.g., example.com)
  title     Site title (default: domain name with capital first letter)
  email     Admin email (default: alphaeosnet@gmail.com)

Options:
  --help    Show this help message

Examples:
  ./install-site.sh example.com
  ./install-site.sh example.com "Example Site" admin@example.com

Prerequisites:
  - WordPress multisite installed at $WORDPRESS_ROOT
  - Apache vhost configured for the domain
  - SSL certificate in place
  - DNS configured (proxied through Cloudflare)
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            break
            ;;
    esac
    shift
done

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

DOMAIN="$1"
TITLE="${2:-$(echo "$DOMAIN" | sed 's/\..*//' | sed 's/^./\U&/')}"
EMAIL="${3:-alphaeosnet@gmail.com}"

# Convert domain to safe slug (remove dots and hyphens)
SLUG=$(echo "$DOMAIN" | sed 's/[.-]//g')

log "Adding site to WordPress multisite: $DOMAIN"
log "  Slug: $SLUG"
log "  Title: $TITLE"
log "  Email: $EMAIL"
log "  WordPress root: $WORDPRESS_ROOT"

# Verify WordPress multisite is installed
if ! priv -u www-data wp --path="$WORDPRESS_ROOT" core is-installed --network 2>/dev/null; then
    err "WordPress multisite not found or not installed at $WORDPRESS_ROOT"
fi

# Step 1: Create site with subdirectory slug
# Note: This creates the site at alphaeos.net/<slug>/ initially
# Warning: sendmail not found is expected (no mail server configured)
log "Step 1: Creating site with slug '$SLUG'"
CREATE_OUTPUT=$(priv -u www-data wp --path="$WORDPRESS_ROOT" site create \
    --slug="$SLUG" \
    --title="$TITLE" \
    --email="$EMAIL" 2>&1) || err "Failed to create site: $CREATE_OUTPUT"

echo "$CREATE_OUTPUT"

# Extract blog_id from output (format: "Success: Site 7 created: http://...")
BLOG_ID=$(echo "$CREATE_OUTPUT" | grep -oP 'Site \K[0-9]+' | head -1)

if [ -z "$BLOG_ID" ]; then
    err "Could not determine blog_id from wp site create output"
fi

log "  Created site with blog_id: $BLOG_ID"

# Step 2: Update domain mapping in wp_blogs table
# This maps the site from alphaeos.net/<slug>/ to <domain>/
log "Step 2: Mapping site to apex domain in wp_blogs"
priv -u www-data wp --path="$WORDPRESS_ROOT" db query \
    "UPDATE wp_blogs SET domain='$DOMAIN', path='/' WHERE blog_id=$BLOG_ID;" \
    || err "Failed to update wp_blogs table"

log "  Updated wp_blogs: domain='$DOMAIN', path='/'"

# Step 3: Update siteurl and home options
# Format: wp_<blog_id>_options table
log "Step 3: Updating siteurl and home URLs to https://$DOMAIN"
priv -u www-data wp --path="$WORDPRESS_ROOT" db query \
    "UPDATE wp_${BLOG_ID}_options SET option_value='https://$DOMAIN' WHERE option_name IN ('siteurl', 'home');" \
    || err "Failed to update site URLs"

log "  Updated wp_${BLOG_ID}_options: siteurl and home set to https://$DOMAIN"

# Step 4: Verify site configuration
log "Step 4: Verifying site configuration"
SITE_INFO=$(priv -u www-data wp --path="$WORDPRESS_ROOT" site list \
    --fields=blog_id,url,domain,path --format=csv | grep "$DOMAIN")

if [ -z "$SITE_INFO" ]; then
    err "Site verification failed - site not found in multisite network"
fi

log "  Verified: $SITE_INFO"

# Final summary
log ""
log "SUCCESS: Site added to multisite network"
log "  Domain: https://$DOMAIN"
log "  Blog ID: $BLOG_ID"
log "  Title: $TITLE"
log ""
log "Next steps:"
log "  1. Verify Apache vhost and SSL certificate are configured"
log "  2. Test HTTPS access: curl -I https://$DOMAIN"
log "  3. Verify Cloudflare Full (strict) mode is enabled"
log "  4. Log in to WordPress admin: https://$DOMAIN/wp-admin"
log ""
log "Common issues:"
log "  - 'sendmail not found' warning is expected (no mail server configured)"
log "  - If site shows alphaeos.net content, clear WordPress cache"
log "  - Verify DNS is proxied through Cloudflare (orange cloud)"
