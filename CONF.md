# WordPress Multisite Setup and Configuration

*Technical configuration reference documenting current system state. For strategy and decisions see MULTI.md.*

## Environment Snapshot
- **Server**: Ubuntu 24.04 on Vultr (laz24), IP `104.238.140.248`
- **Web**: Apache 2.4 with SSL module enabled
- **PHP**: 8.3
- **Database**: MySQL 8.0.43, `wordpress_multisite` with user `wp_user`
- **WordPress**: 6.8.3 installed at `/var/www/html/wordpress/`
- **Primary Domain**: `alphaeos.net`
- **Network Admin Email**: `alphaeosnet@gmail.com`
- **Config Files**: `/var/www/html/wordpress/wp-config.php`, `.htaccess`

## DNS & Cloudflare Settings (target)
- DNS hosted at Cloudflare; proxy (orange cloud) enabled.
- Origin reachability via Cloudflare IPs; Local resolvers: `8.8.8.8`, `1.1.1.1`.
- SSL/TLS mode: **Full (strict)** (edge to origin validates origin certs).
- HTTPS redirect + security headers applied at Cloudflare (see WPCloud.md); avoid duplicate Apache redirects to prevent loops.

## Web Server & SSL
- One Apache virtual host per domain (no wildcard): examples live at
  - HTTP: `/etc/apache2/sites-available/alphaeosnet.conf` (port 80)
  - HTTPS: `/etc/apache2/sites-available/alphaeosnet-ssl.conf` (port 443)
- Intended SSL: per-domain Cloudflare Origin certs (apex + www) installed on origin at `/etc/ssl/cloudflare-origin/{certs,keys}/<safe>.{crt,key}`; update vhosts to point at the issued cert/key paths (templates already use this layout).

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
1. Install Apache, PHP 8.3, MySQL 8.0; enable `rewrite`, `ssl`, `headers`.
2. Create MySQL DB/user (`wordpress_multisite` / `wp_user` with strong password).
3. Place WordPress in `/var/www/html/wordpress/`; ensure ownership for web user.
4. Enable multisite in `wp-config.php`; place rewrite rules in `.htaccess` (use templates/ for baseline patterns).
5. Create Apache vhosts per domain (HTTP + HTTPS) pointing to the WordPress root; enable sites and reload Apache.
6. Obtain and install Cloudflare Origin cert/key per domain; update vhost SSL paths.
7. Set Cloudflare DNS records to the server IP and confirm proxy status.

## WP-CLI (recommended)
- Install WP-CLI globally (per handbook) for repeatable operations.
- Example multisite install:  
  `wp core multisite-install --url=alphaeos.net --title="AlphaEos Network" --admin_user=admin --admin_password=<pw> --admin_email=alphaeosnet@gmail.com --skip-email`
- After adding vhosts/DNS, register a site per domain:  
  `wp site create --slug=<domain> --title="<Client Name>" --email=<admin@domain> --private=0`

## Operational Checks
- `apache2ctl configtest` and `systemctl status apache2` should be clean.
- Browser → domain: confirm HTTPS serves WordPress and admin login works.
- WordPress Network Admin: create a new site and verify it routes correctly.
- Check Cloudflare SSL mode and DNS records after each domain addition.
