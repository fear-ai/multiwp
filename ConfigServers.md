# Server & Web Stack Configuration (Origin Runbook)

*Internal specifics (versions, IPs, paths, domains) live in CONF.md. This runbook stays generic; substitute values from CONF as needed.*

## Table of Contents
1. [Host & Services](#1-host--services)
2. [Web Server & Vhosts](#2-web-server--vhosts)
3. [PHP & Database](#3-php--database)
4. [WordPress Files & Permissions](#4-wordpress-files--permissions)
5. [wp-config.php & .htaccess](#5-wp-configphp--htaccess)
6. [Certificates (Origin)](#6-certificates-origin)
7. [Validation & Debug Workflows](#7-validation--debug-workflows)
8. [Automation Helpers](#8-automation-helpers)

## 1. Host & Services
- Provision Ubuntu (per CONF) with Apache 2.4, PHP 8.x, MySQL 8.x.
- Enable Apache modules: `sudo a2enmod rewrite ssl headers && sudo systemctl reload apache2`.

## 2. Web Server & Vhosts
- Model: one vhost per domain; no wildcards.
- Paths/templates: use `templates/apache-*.conf` and `scripts/add-domains.sh`; vhost destinations and active sites are in CONF.
- After edits: `sudo apache2ctl configtest && sudo systemctl reload apache2`.

## 3. PHP & Database
- DB name/user/collation: see CONF for actual values.
- PHP aligns with WordPress requirements; keep extensions minimal; use system package manager for PHP modules.

## 4. WordPress Files & Permissions
- Roots (multisite and any single-site) and ownership: see CONF. Ensure `www-data` can read/write uploads; keep code write-restricted.
- Multisite `.htaccess` should remain the standard subdirectory rules; single-site roots use standard single-site rules.

## 5. wp-config.php & .htaccess
- `wp-config.php`: keep out of webroot if practical; set DB creds, salts, multisite constants; perms 640, owner root/deployer, group `www-data` if Apache must read.
- Multisite `.htaccess`: standard subdirectory rules from WordPress docs; `AllowOverride All` on docroot; avoid custom rewrites that bypass multisite routing.
- Single-site `.htaccess` (e.g., standalone sites): standard single-site rules; perms typically 640/644 owned by deployer, readable by web server.

## 6. Certificates (Origin)
- Place Cloudflare Origin certs/keys at:
  - `/etc/ssl/cloudflare-origin/certs/<safe>.crt`
  - `/etc/ssl/cloudflare-origin/keys/<safe>.key`
  - Permissions: root:ssl-cert, mode 640.
- Vhosts reference these paths (templates already do). For edge mode/redirects/headers, see CloudflareSettings.md.

## 7. Validation & Debug Workflows
- Apache syntax/reload: `sudo apache2ctl configtest`; if ok, `sudo systemctl reload apache2`.
- Vhosts present/enabled: `ls /etc/apache2/sites-available`, `ls /etc/apache2/sites-enabled`.
- TLS cert sanity: `sudo openssl x509 -in /etc/ssl/cloudflare-origin/certs/<safe>.crt -noout -subject -issuer -dates -ext subjectAltName`.
- DNS reachability: `dig A <domain> +short`, `dig AAAA <domain> +short`.
- WordPress state: `sudo -u www-data wp --path=<wp_root> core version`, `wp site list`.
- DB routing tables: `mysql -u <db_user> -p -D <db_name> -e "SELECT blog_id, domain, path FROM wp_blogs;"`.
- Functional check: browse domain → confirm HTTPS and admin login; create a test site in Network Admin and verify routing; confirm Cloudflare Full (strict) and DNS after each addition (per CloudflareSettings.md).

## 8. Automation Helpers
- Zone/DNS creation: `scripts/add-zone-and-dns.sh <domain> <ipv4> [ipv6]` (Cloudflare API).
- Origin cert install/validate: `scripts/ensure-origin-cert.sh <domain>`.
- Vhost generation: `scripts/add-domains.sh <domain>` (uses origin cert paths; runs configtest).
- WordPress mapping: `wp site update --blog_id=<id> --domain=<domain> --path=/ --network`; update `siteurl/home` accordingly.
