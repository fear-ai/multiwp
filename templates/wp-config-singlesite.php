<?php
/**
 * WordPress Single-Site Configuration Template
 * Replace {{VARIABLES}} with actual values
 *
 * Example file naming for single-site configuration tracking:
 * - /var/www/html/domain.tld/wp-config.php (current)
 * - /var/www/html/domain.tld/wp-config.php.ssl (SSL configuration staging)
 * - /var/www/html/domain.tld/wp-config.php.prod (production snapshot)
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

// Absolute path to WordPress directory
if (!defined('ABSPATH')) {
    define('ABSPATH', dirname(__FILE__) . '/');
}

require_once(ABSPATH . 'wp-settings.php');
?>
