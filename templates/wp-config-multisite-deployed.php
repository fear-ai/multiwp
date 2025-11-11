<?php
/**
 * WordPress Multisite Configuration Template (Production Version)
 * Based on deployed wp-config.php with sensitive values masked
 * 
 * Replace {{VARIABLES}} with actual values
 */

// ** Database settings - You can get this info from your web host ** //
/** The name of the database for WordPress */
define( 'DB_NAME', '{{DB_NAME}}' );

/** Database username */
define( 'DB_USER', '{{DB_USER}}' );

/** Database password */
define( 'DB_PASSWORD', '{{DB_PASSWORD}}' );

/** Database hostname */
define( 'DB_HOST', 'localhost' );

/** Database charset to use in creating database tables. */
define( 'DB_CHARSET', 'utf8mb4' );

/** The database collate type. Don't change this if in doubt. */
define( 'DB_COLLATE', '' );

/**#@+
 * Authentication unique keys and salts.
 *
 * Change these to different unique phrases! You can generate these using
 * the {@link https://api.wordpress.org/secret-key/1.1/salt/ WordPress.org secret-key service}.
 *
 * You can change these at any point in time to invalidate all existing cookies.
 * This will force all users to have to log in again.
 *
 * @since 2.6.0
 */
define( 'AUTH_KEY',         '{{AUTH_KEY}}' );
define( 'SECURE_AUTH_KEY',  '{{SECURE_AUTH_KEY}}' );
define( 'LOGGED_IN_KEY',    '{{LOGGED_IN_KEY}}' );
define( 'NONCE_KEY',        '{{NONCE_KEY}}' );
define( 'AUTH_SALT',        '{{AUTH_SALT}}' );
define( 'SECURE_AUTH_SALT', '{{SECURE_AUTH_SALT}}' );
define( 'LOGGED_IN_SALT',   '{{LOGGED_IN_SALT}}' );
define( 'NONCE_SALT',       '{{NONCE_SALT}}' );

/**#@-*/

/**
 * WordPress database table prefix.
 *
 * You can have multiple installations in one database if you give each
 * a unique prefix. Only numbers, letters, and underscores please!
 */
$table_prefix = 'wp_';

/**
 * For developers: WordPress debugging mode.
 *
 * Change this to true to enable the display of notices during development.
 * It is strongly recommended that plugin and theme developers use WP_DEBUG
 * in their development environments.
 */
define( 'WP_DEBUG', false );  // Set to true for development
define('WP_DEBUG_LOG', false);
define('WP_DEBUG_DISPLAY', false);

/* Add any custom values between this line and the "stop editing" line. */

// Force HTTPS URL generation (optional - for mixed content issues)
// $_SERVER['HTTPS'] = 'on';
// $_SERVER['SERVER_PORT'] = '443';
// if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
//     $_SERVER['HTTPS'] = 'on';
// }

// Force WordPress to use HTTPS URLs (optional - for Cloudflare SSL Full mode)
// define('FORCE_SSL_ADMIN', true);

/* WordPress Multisite Configuration */
define( 'WP_ALLOW_MULTISITE', true );
define( 'MULTISITE', true );
define( 'SUBDOMAIN_INSTALL', false );
define( 'DOMAIN_CURRENT_SITE', '{{PRIMARY_DOMAIN}}' );
define( 'PATH_CURRENT_SITE', '/' );
define( 'SITE_ID_CURRENT_SITE', 1 );
define( 'BLOG_ID_CURRENT_SITE', 1 );

// WordPress security enhancements
define( 'DISALLOW_FILE_EDIT', true );           // Disable file editing
define( 'AUTOMATIC_UPDATER_DISABLED', false );  // Allow automatic updates
define( 'WP_AUTO_UPDATE_CORE', true );          // Auto-update WordPress core

/* That's all, stop editing! Happy publishing. */

/** Absolute path to the WordPress directory. */
if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}

/** Sets up WordPress vars and included files. */
require_once ABSPATH . 'wp-settings.php';
?>

