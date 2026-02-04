#!/bin/bash
# install-site.sh - Add a new site to WordPress multisite and map to an apex domain.
# For options, environment variables, defaults see usage().
#
# Example: install-site.sh [OPTIONS] <domain> [title] [email]

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"
. "$SCRIPTS_DIR/cli.sh"

require_cmds wp

WORDPRESS_ROOT_LOCAL="$WORDPRESS_ROOT"
DOMAINS=()

usage() {
    cat <<EOF
install-site.sh - Add a new site to WordPress multisite and map to an apex domain.
Example: install-site.sh [OPTIONS] <domain> [title] [email]

Arguments: <domain> [title] [email]
  - domain is the apex domain (for example, example.com). Use --domain to supply it via an option.
  - title defaults to the domain name with the first letter capitalized.
  - email defaults to alphaeosnet@gmail.com.

Options:
  --domain NAME  Domain to add
$(cli_usage_wp_root)
  --help  Show this help

Prerequisites:
  The following dependencies must be in place before running this script.
  - WordPress multisite installed at $WORDPRESS_ROOT
  - Apache vhost configured for the domain
  - SSL certificate in place
  - DNS configured (proxied through Cloudflare)

What this script does:
  - Creates a new site in the multisite network with a subdirectory slug
  - Maps the site to the apex domain in wp_blogs
  - Updates siteurl and home URLs to use https://<domain>
  - Verifies the site appears in wp site list
EOF
}

# Parse options
while getopts ":-:" opt; do
    case "$opt" in
        -)
            case "${OPTARG}" in
                help) usage; exit 0 ;;
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

if [ ${#DOMAINS[@]} -eq 0 ]; then
    if [ $# -lt 1 ]; then
        usage
        exit 1
    fi
    DOMAINS+=("$1")
    shift
fi

finalize_domains DOMAINS || { usage; exit 1; }
if [ ${#DOMAINS[@]} -ne 1 ]; then
    err "Provide exactly one domain via --domain or a single positional domain"
fi
DOMAIN="${DOMAINS[0]}"
TITLE="${1:-$(echo "$DOMAIN" | sed 's/\..*//' | sed 's/^./\U&/')}"
EMAIL="${2:-alphaeosnet@gmail.com}"
if [ $# -gt 2 ]; then
    err "Too many arguments. Provide [title] [email] only."
fi

# Convert domain to safe slug (remove dots and hyphens)
SLUG=$(echo "$DOMAIN" | sed 's/[.-]//g')

log "Adding site to WordPress multisite: $DOMAIN"
log "  Slug: $SLUG"
log "  Title: $TITLE"
log "  Email: $EMAIL"
log "  WordPress root: $WORDPRESS_ROOT_LOCAL"
section "WP" "Site"
kv "DOMAIN" "$DOMAIN"
kv "SLUG" "$SLUG"
kv "WP_ROOT" "$WORDPRESS_ROOT_LOCAL"

# Verify WordPress multisite is installed
if ! priv -u www-data wp --path="$WORDPRESS_ROOT_LOCAL" core is-installed --network 2>/dev/null; then
    err "WordPress multisite not found or not installed at $WORDPRESS_ROOT_LOCAL"
fi

# Step 1: Create site with subdirectory slug
# Note: This creates the site at alphaeos.net/<slug>/ initially
# Warning: sendmail not found is expected (no mail server configured)
log "Step 1: Creating site with slug '$SLUG'"
CREATE_OUTPUT=$(priv -u www-data wp --path="$WORDPRESS_ROOT_LOCAL" site create \
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
section "WP" "Mapping"
log "Step 2: Mapping site to apex domain in wp_blogs"
priv -u www-data wp --path="$WORDPRESS_ROOT_LOCAL" db query \
    "UPDATE wp_blogs SET domain='$DOMAIN', path='/' WHERE blog_id=$BLOG_ID;" \
    || err "Failed to update wp_blogs table"

log "  Updated wp_blogs: domain='$DOMAIN', path='/'"

# Step 3: Update siteurl and home options
# Format: wp_<blog_id>_options table
log "Step 3: Updating siteurl and home URLs to https://$DOMAIN"
priv -u www-data wp --path="$WORDPRESS_ROOT_LOCAL" db query \
    "UPDATE wp_${BLOG_ID}_options SET option_value='https://$DOMAIN' WHERE option_name IN ('siteurl', 'home');" \
    || err "Failed to update site URLs"

log "  Updated wp_${BLOG_ID}_options: siteurl and home set to https://$DOMAIN"

# Step 4: Verify site configuration
log "Step 4: Verifying site configuration"
SITE_INFO=$(priv -u www-data wp --path="$WORDPRESS_ROOT_LOCAL" site list \
    --fields=blog_id,url,domain,path --format=csv | grep "$DOMAIN")

if [ -z "$SITE_INFO" ]; then
    err "Site verification failed - site not found in multisite network"
fi

log "  Verified: $SITE_INFO"

# Emit a stable key=value line for automation and CSV capture.
echo "BLOG_ID=$BLOG_ID"

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
