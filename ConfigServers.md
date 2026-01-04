# Server & Web Configuration

## Introduction
Operational runbook for the origin layer: provisioning, permissions, Apache vhosts, certificates, multisite routing, and validation workflows. Use alongside CloudflareSettings.md for edge policy.

## Table of Contents
1. [Introduction](#introduction)
2. [Host & Services](#host--services)
3. [User Permissions](#user-permissions)
4. [Certificates](#cloudflare-origin-certificates)
5. [Web Server & Vhosts](#web-server--vhosts)
6. [PHP & Database](#php--database)
7. [WordPress Files & Permissions](#wordpress-files--permissions)
8. [wp-config.php & .htaccess](#wp-configphp--htaccess)
9. [Validation & Debug Workflows](#validation--debug-workflows)
10. [Site Onboarding Workflow & Troubleshooting](#site-onboarding-workflow--troubleshooting)
11. [Target Audience](#target-audience)

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
- Install: `sudo scripts/get-cert.sh --manual <domain>` for a paste-based workflow, or `sudo scripts/get-cert.sh --api <domain>` when Cloudflare API credentials are configured.

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

## Site Onboarding Workflow & Troubleshooting
Authoritative sequence for adding a mapped-apex site; mirrors `scripts/install-site.sh` and provides the full detail beyond the quick summary.

1) Create the site in subdirectory form to obtain a blog_id.
```bash
sudo -u www-data wp --path=/var/www/html/wordpress site create \
  --slug=<slug> --title="<Site Title>" --email=<admin@example.com>
```

2) Map the apex domain in `wp_blogs` so WordPress routes requests correctly.
```bash
sudo -u www-data wp --path=/var/www/html/wordpress db query \
  "UPDATE wp_blogs SET domain='<domain>', path='/' WHERE blog_id=<id>;"
```

3) Update site URLs in the per-site options table so generated links use HTTPS and the apex domain.
```bash
sudo -u www-data wp --path=/var/www/html/wordpress db query \
  "UPDATE wp_<id>_options SET option_value='https://<domain>' \
    WHERE option_name IN ('siteurl', 'home');"
```

4) Validate: `wp site list`, `curl -I https://<domain>`, Apache vhost present/enabled, Cloudflare proxy + Full (strict).

Pitfalls and expectations:
- WP-CLI has no `wp site update` subcommand; direct DB updates above are the supported method.
- Order matters: update `wp_blogs` before using `--url=https://<domain>` with wp-cli, otherwise the site is “not found.”
- `sh: 1: /usr/sbin/sendmail: not found` during site create is expected on hosts without an MTA; site creation still succeeds. Use an SMTP plugin later if email delivery is required.

Refer to CloudflareSettings.md for edge steps (proxy, certificates, HTTPS enforcement) that must precede public cutover.

## Target Audience
This runbook serves operators administering the origin (Apache, PHP, WordPress multisite) and developers maintaining automation scripts. Typical scenarios: provisioning a new domain, diagnosing routing or SSL issues, and validating changes after Cloudflare updates. Recommended skills: Bash with sudo, Apache vhost management, wp-cli, basic MySQL queries, and awareness of edge procedures in CloudflareSettings.md. Additional resources: MULTI.md for architectural rationale and DNSTerms.md for terminology.
