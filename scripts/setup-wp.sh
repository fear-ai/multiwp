#!/bin/bash
# setup-wp.sh - WordPress multisite base configuration.
# For options, environment variables, defaults see usage().
#
# Example: setup-wp.sh

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
. "$SCRIPTS_DIR/common.sh"

# Usage and prerequisites summary.
usage() {
    cat <<'EOF'
setup-wp.sh - WordPress multisite base configuration.
Example: setup-wp.sh

Notes:
  - Run as a user with sudo privileges, never as root.
  - IMPORTANT: Record all database names, usernames, and passwords for WordPress configuration.

Official WordPress Documentation:
  https://developer.wordpress.org/advanced-administration/multisite/create-network
  https://learn.wordpress.org/lesson/setting-up-a-wordpress-multisite-network

Server prerequisites (configure before running this script):
  MySQL:
    https://ubuntu.com/server/docs/databases-mysql (Installation and basic setup)
    https://dev.mysql.com/doc/mysql-installation-excerpt/8.0/en/linux-installation-ubuntu.html
    https://developer.wordpress.org/advanced-administration/before-install/creating-database/

    WordPress Recommendations:
      - Use UTF-8 encoding (preferably "utf8mb4_general_ci")
      - Choose strong, complex passwords
      - Use unique database and username combinations
      - Write down credentials securely
    Run mysql_secure_installation first, then create WordPress database and user

    WordPress MySQL Setup, per WordPress.org:
      mysql -u adminusername -p
      CREATE DATABASE databasename;
      CREATE USER "wordpressusername"@"hostname" IDENTIFIED BY "password";
      GRANT ALL PRIVILEGES ON databasename.* TO "wordpressusername"@"hostname";
      FLUSH PRIVILEGES;
      EXIT

  Apache:
    https://ubuntu.com/tutorials/install-and-configure-apache (Basic installation)
    https://httpd.apache.org/docs/2.4/getting-started.html (Configuration basics)

  PHP:
    https://www.php.net/manual/en/install.unix.debian.php (PHP installation)
    https://developer.wordpress.org/advanced-administration/server/web-server/apache/ (WordPress-specific Apache config)
EOF
}

if [ "${1-}" = "--help" ]; then
    usage
    exit 0
fi

# Check if running as correct user
if [ "$USER" = "root" ]; then
    err "Do not run as root. Run as a user with sudo privileges."
fi

require_cmd grep
require_cmd tee
require_cmd a2enmod
require_cmd apache2ctl
require_cmd systemctl
require_cmd wget
require_cmd tar
require_cmd sed

## Apache Configuratione
echo "Step 2: Configuring Apache prerequisites"
if ! grep -q "ServerName localhost" /etc/apache2/apache2.conf; then
    echo "ServerName localhost" | priv tee -a /etc/apache2/apache2.conf >/dev/null
    echo "Added ServerName to Apache configuration"
fi

# Enable Apache modules
echo "Enabling required Apache modules"
priv a2enmod rewrite ssl headers
priv apache2ctl configtest
priv systemctl reload apache2


## WordPress Configuration
WORDPRESS_ROOT="/var/www/html/wordpress"
WP_CONFIG_PATH="$WORDPRESS_ROOT/wp-config.php"
HTACCESS_PATH="$WORDPRESS_ROOT/.htaccess"

echo "WordPress Multisite Base Setup"
echo "Following official WordPress documentation process"
echo "WordPress root: $WORDPRESS_ROOT"
echo ""

# Create WordPress root directory if it doesn't exist
if [ ! -d "$WORDPRESS_ROOT" ]; then
    echo "WordPress directory not found. Creating: $WORDPRESS_ROOT"
    priv mkdir -p "$WORDPRESS_ROOT"
    
    echo "Downloading and installing WordPress..."
    cd /tmp
    wget https://wordpress.org/latest.tar.gz
    tar -xzf latest.tar.gz
    priv cp -r wordpress/* "$WORDPRESS_ROOT/"
    priv chown -R www-data:www-data "$WORDPRESS_ROOT"
    echo "WordPress installed to $WORDPRESS_ROOT"
fi

# Create wp-config.php from sample if it doesn't exist
if [ ! -f "$WP_CONFIG_PATH" ]; then
    if [ -f "$WORDPRESS_ROOT/wp-config-sample.php" ]; then
        echo "Creating wp-config.php from sample"
        priv cp "$WORDPRESS_ROOT/wp-config-sample.php" "$WP_CONFIG_PATH"
        
        echo ""
        echo "wp-config.php created from sample."
        echo "You need to configure database settings and security keys."
        echo "  1. Set DB_NAME, DB_USER, DB_PASSWORD (use credentials from MySQL setup)"
        echo "  2. Generate security keys: https://api.wordpress.org/secret-key/1.1/salt/"
        echo ""
        echo "Or use a Template from ../templates/:"
        echo "  wp-config-multisite.php          - Terse template with {{VARIABLES}}"
        echo "  wp-config-multisite-deployed.php - Full template with WordPress comments"
        echo ""
        echo "REMINDER: Record database name, username, and password for future reference"
        echo ""
        read -p "Press Enter when wp-config.php is configured..."
    else
        echo "Error: Neither wp-config.php nor wp-config-sample.php found"
        exit 1
    fi
fi

# Check if already multisite enabled
if grep -q "define.*MULTISITE.*true" "$WP_CONFIG_PATH"; then
    echo "Multisite already enabled in wp-config.php"
else
    echo "Step 1: Enabling multisite in wp-config.php"
    # Add WP_ALLOW_MULTISITE before "That's all" comment or before "Absolute path" comment
    if grep -q "/\* That's all" "$WP_CONFIG_PATH"; then
        priv sed -i '/\/\* That'\''s all/i\\n/* Enable WordPress Multisite */\ndefine( '\''WP_ALLOW_MULTISITE'\'', true );' "$WP_CONFIG_PATH"
    elif grep -q "/\*\* Absolute path" "$WP_CONFIG_PATH"; then
        priv sed -i '/\/\*\* Absolute path/i\\n/* Enable WordPress Multisite */\ndefine( '\''WP_ALLOW_MULTISITE'\'', true );' "$WP_CONFIG_PATH"
    else
        # Fallback - add before wp-settings.php
        priv sed -i '/wp-settings.php/i\\n/* Enable WordPress Multisite */\ndefine( '\''WP_ALLOW_MULTISITE'\'', true );' "$WP_CONFIG_PATH"
    fi
    echo "Added WP_ALLOW_MULTISITE to wp-config.php"
fi


echo ""
echo "Multisite setup prepared"
echo ""
echo "Next steps:"
echo "1. Access WordPress Admin: http://DOMAIN/wp-admin"
echo "2. Go to Tools → Network Setup"
echo "3. Choose 'Sub-directories' and configure network"
echo "4. Update wp-config.php, if not already fully configured"
echo "5. Update .htaccess with provided rewrite rules"
echo "6. Run add-domain.sh to add individual client domains"
echo ""
