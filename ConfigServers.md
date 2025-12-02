# Server & Web Configuration

## Table of Contents
1. [Host & Services](#1-host--services)
2. [Web Server & Vhosts](#2-web-server--vhosts)
3. [PHP & Database](#3-php--database)
4. [WordPress Files & Permissions](#4-wordpress-files--permissions)
5. [wp-config.php & .htaccess](#5-wp-configphp--htaccess)
6. [Certificates](#6-certificates)
7. [Validation & Debug Workflows](#7-validation--debug-workflows)

## Host & Services
- Provision Ubuntu {24} with Apache 2.4, PHP 8.x, MySQL 8.x.
- Check CONF.md for the latest site-specific recommendations (versions, paths, domains)

## Cloudflare Origin Certificates
HTTPS vhosts reference these paths per template.
  - `/etc/ssl/cloudflare-origin/certs/<safe>.crt`
  - `/etc/ssl/cloudflare-origin/keys/<safe>.key`
  Permissions: root:ssl-cert 640.
- Install: `sudo scripts/install-cert.sh <domain>`.

## Web Server & Vhosts
- Enable Apache modules: `sudo a2enmod rewrite ssl headers && sudo systemctl reload apache2`.
- Model: one vhost per domain, no wildcards.
- Templates: `templates/apache-*.conf`
- Script: `sudo scripts/apache-vhost.sh`
- Runs: `sudo apache2ctl configtest && sudo systemctl reload apache2`

## PHP & Database
- Database name/user in CONF.md.

## WordPress Files & Permissions
- Ensure `www-data` can read/write uploads; keep code write-restricted.

## wp-config.php & .htaccess
- `wp-config.php`: keep out of +++webroot if practical; DB creds, salts, multisite constants; perms 640, owner root/deployer, group `www-data` if Apache must read.
- Multisite `.htaccess`: standard subdirectory rules from WordPress docs; `AllowOverride All` on docroot; avoid custom rewrites that bypass multisite routing.
- Single-site [standalone] `.htaccess`: standard single-site rules; typically 640, owned by deployer, readable by web server.

## Validation & Debug Workflows
- Vhosts present/enabled: `sudo ls /etc/apache2/sites-available`, `sudo ls /etc/apache2/sites-enabled`.
- SSL/TLS cert validation: `sudo openssl x509 -in /etc/ssl/cloudflare-origin/certs/<safe>.crt -noout -subject -issuer -dates -ext subjectAltName`.
- DNS reachability: `dig A <domain> +short`, `dig AAAA <domain> +short`.
- WordPress state: `sudo -u www-data wp --path=<wp_root> core version`, `wp site list`.
- DB routing tables: `mysql -u <db_user> -p -D <db_name> -e "SELECT blog_id, domain, path FROM wp_blogs;"`.
- Functional check: browse domain → confirm HTTPS and admin login; create a test site in Network Admin and verify routing; confirm Cloudflare Full (strict) and DNS after each addition (per CloudflareSettings.md).
- WordPress mapping: `wp site update --blog_id=<id> --domain=<domain> --path=/ --network`; update `siteurl/home` accordingly.

- Zone/DNS creation: `scripts/cloud-dns.sh <domain> <ipv4>` (Using Cloudflare API per CloudflareSettings.md, in development).

*Terminology in DNSTerms.md.*

