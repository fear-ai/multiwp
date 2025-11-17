# WordPress Multisite Setup and Configuration

*Technical configuration reference documenting current system state. For strategy and decisions see MULTI.md. For origin/server details see ConfigServers.md. For Cloudflare UI steps see CloudflareSettings.md.*

## Environment Snapshot
- **Server**: Ubuntu 24.04 on Vultr (laz24), IP `104.238.140.248`
- **Web**: Apache 2.4 with SSL module enabled
- **PHP**: 8.3
- **Database**: MySQL 8.0.43, `wordpress_multisite` with user `wp_user`
- **WordPress**: 6.8.3 installed at `/var/www/html/wordpress/`
- **Primary Domain**: `alphaeos.net`
- **Network Admin Email**: `alphaeosnet@gmail.com`
- **Config Files**: `/var/www/html/wordpress/wp-config.php`, `.htaccess`

## WordPress Network Settings
- Multisite enabled with subdirectory structure.
- Site routing handled via `.htaccess` in the WordPress root.
- Network admin reachable through WordPress dashboard (per-domain login).

## Current Sites (from DB)
- `https://alphaeos.net/` (primary)
- `http://alphaeos.net/demo/` (uses HTTP; GUI-created subdirectory)
- `https://alphaeos.net/avtranscript.com/` (subdirectory; not mapped)
- `https://recomp.one/` (mapped apex)

## Setup Steps (fresh host)
- Follow ConfigServers.md for service setup, validation, vhost/cert layout, and CLI commands.
- Follow CloudflareSettings.md for Cloudflare UI (Full strict, redirects, headers, DNS/proxy).

## Operational Checks
- See ConfigServers.md for service validation and CloudflareSettings.md for edge validation; verify sites in WordPress Network Admin after each addition.
