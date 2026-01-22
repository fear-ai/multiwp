<?php
/**
 * WordPress Multisite Configuration Template
 * Replace {{VARIABLES}} with actual values
 *
 */

// Database settings
define('DB_NAME', '{{DB_NAME}}');
define('DB_USER', '{{DB_USER}}');
define('DB_PASSWORD', '{{DB_PASSWORD}}');
define('DB_HOST', 'localhost');
define('DB_CHARSET', 'utf8mb4');
define('DB_COLLATE', '');

// Authentication unique keys and salts
// Generate from: https://api.wordpress.org/secret-key/1.1/salt/
define('AUTH_KEY',         '{{AUTH_KEY}}');
define('SECURE_AUTH_KEY',  '{{SECURE_AUTH_KEY}}');
define('LOGGED_IN_KEY',    '{{LOGGED_IN_KEY}}');
define('NONCE_KEY',        '{{NONCE_KEY}}');
define('AUTH_SALT',        '{{AUTH_SALT}}');
define('SECURE_AUTH_SALT', '{{SECURE_AUTH_SALT}}');
define('LOGGED_IN_SALT',   '{{LOGGED_IN_SALT}}');
define('NONCE_SALT',       '{{NONCE_SALT}}');

// WordPress table prefix
$table_prefix = '{{TABLE_PREFIX}}';

// WordPress security and update controls
define('DISALLOW_FILE_EDIT', true);
// define('DISALLOW_FILE_MODS', true); // CLI-only installs/updates
define('AUTOMATIC_UPDATER_DISABLED', false);
define('WP_AUTO_UPDATE_CORE', true);
define('DISABLE_WP_CRON', true);
define('FORCE_SSL_ADMIN', true);

// Optional (documented in Operations.md):
// - WP_DEBUG defaults and related flags

// WordPress multisite configuration
define('WP_ALLOW_MULTISITE', true);
define('MULTISITE', true);
define('SUBDOMAIN_INSTALL', false);
define('DOMAIN_CURRENT_SITE', '{{PRIMARY_DOMAIN}}');
define('PATH_CURRENT_SITE', '/');
define('SITE_ID_CURRENT_SITE', 1);
define('BLOG_ID_CURRENT_SITE', 1);

// Absolute path to WordPress directory
if (!defined('ABSPATH')) {
    define('ABSPATH', dirname(__FILE__) . '/');
}

require_once(ABSPATH . 'wp-settings.php');
?>
