# Server & Web Configuration

## Table of Contents
1. [Host & Services](#1-host--services)
2. [User Permissions](#2-user-permissions)
3. [Web Server & Vhosts](#3-web-server--vhosts)
4. [PHP & Database](#4-php--database)
5. [WordPress Files & Permissions](#5-wordpress-files--permissions)
6. [wp-config.php & .htaccess](#6-wp-configphp--htaccess)
7. [Certificates](#7-certificates)
8. [Validation & Debug Workflows](#8-validation--debug-workflows)

## Host & Services
- Provision Ubuntu {24} with Apache 2.4, PHP 8.x, MySQL 8.x.
- Check CONF.md for the latest site-specific recommendations (versions, paths, domains)

## User Permissions
The deployment user (typically `ubuntu`) must be in the `ssl-cert` group to run scripts that read SSL certificates:
```bash
sudo usermod -aG ssl-cert ubuntu
```
After adding the group, log out and log back in, or run `newgrp ssl-cert` to activate. Verify with `groups ubuntu`.

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
- WordPress domain mapping: Map a site to an apex domain using database updates:
  ```bash
  # Create site first
  sudo -u www-data wp --path=/var/www/html/wordpress site create --slug=<slug> --title="Site Title" --email=admin@example.com

  # Update domain mapping in wp_blogs (replace 7 with actual blog_id)
  sudo -u www-data wp --path=/var/www/html/wordpress db query "UPDATE wp_blogs SET domain='<domain>', path='/' WHERE blog_id=<id>;"

  # Update siteurl and home in site options (replace 7 with actual blog_id)
  sudo -u www-data wp --path=/var/www/html/wordpress db query "UPDATE wp_<id>_options SET option_value='https://<domain>' WHERE option_name IN ('siteurl', 'home');"
  ```

- Zone/DNS creation: `scripts/cloud-dns.sh <domain> <ipv4>` (Using Cloudflare API per CloudflareSettings.md, in development).

*Terminology in DNSTerms.md.*

