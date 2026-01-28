# Operations Runbook
Date: January 10, 2026

## 1. Introduction
This runbook consolidates the operational steps for Cloudflare edge configuration, origin TLS/Apache setup, and WordPress multisite operations. It is organized in dependency order so each layer is configured and validated before the next layer relies on it. Use this document as the canonical operational guide, and reference `scripts/Scripts.md` for exact option and environment variable interfaces when running scripts.

The dependency chain is explicit: Cloudflare edge behavior depends on correct DNS and SSL/TLS configuration, origin TLS and Apache vhosts depend on valid certificates and permissions, and WordPress routing depends on the origin layer being correct. This ordering avoids diagnosing downstream symptoms before the upstream cause is resolved.

## 2. Table of Contents
1. [1. Introduction](#1-introduction)
2. [3. Cloudflare Edge](#3-cloudflare-edge)
   1. [3.1 Overview](#31-overview)
   2. [3.2 Proxy Model (Summary)](#32-proxy-model-summary)
   3. [3.3 HTTPS Responsibility (Summary)](#33-https-responsibility-summary)
   4. [3.4 HTTPS Flow](#34-https-flow)
      1. [3.4.1 DNS Proxy](#341-dns-proxy)
      2. [3.4.2 SSL Mode](#342-ssl-mode)
      3. [3.4.3 TLS Settings](#343-tls-settings)
      4. [3.4.4 Origin Cert](#344-origin-cert)
      5. [3.4.5 Security Settings](#345-security-settings)
      6. [3.4.6 Security Headers](#346-security-headers)
   5. [3.5 Automation](#35-automation)
      1. [3.5.1 HTTPS and Security Baseline](#351-https-and-security-baseline)
      2. [3.5.2 Zone DNS](#352-zone-dns)
      3. [3.5.3 Cert Placement](#353-cert-placement)
      4. [3.5.4 Vhost Generation](#354-vhost-generation)
      5. [3.5.5 API Auth](#355-api-auth)
   6. [3.6 Hybrid Execution](#36-hybrid-execution)
   7. [3.7 Notes](#37-notes)
      1. [3.7.1 HSTS](#371-hsts)
      2. [3.7.2 Redirect Config](#372-redirect-config)
3. [4. Origin TLS](#4-origin-tls)
   1. [4.1 Host Services](#41-host-services)
   2. [4.2 Ubuntu updates](#42-ubuntu-updates)
   3. [4.3 User Permissions](#43-user-permissions)
   4. [4.4 Origin Certs](#44-origin-certs)
   5. [4.5 Web Vhosts](#45-web-vhosts)
   6. [4.6 PHP Database](#46-php-database)
   7. [4.7 WordPress Files and Permissions](#47-wordpress-files-and-permissions)
   8. [4.8 .htaccess Structure and Routing](#48-htaccess-structure-and-routing)
   9. [4.9 wp-config.php Settings](#49-wp-configphp-settings)
4. [5. Multisite Ops](#5-multisite-ops)
   1. [5.1 Site Onboarding](#51-site-onboarding)
   2. [5.2 Site Troubleshooting](#52-site-troubleshooting)
5. [6. Verification](#6-verification)
   1. [6.1 Validation Checks](#61-validation-checks)
   2. [6.2 Script Partitioning](#62-script-partitioning)
6. [7. Domain Transfer](#7-domain-transfer)
   1. [7.1 Manual Transfer](#71-manual-transfer)
   2. [7.2 Transfer Automation](#72-transfer-automation)
7. [8. Target Audience](#8-target-audience)

## 3. Cloudflare Edge
Cloudflare edge configuration defines how traffic reaches the origin and how HTTPS, redirects, and security headers are enforced. The UI is authoritative for edge policy, while scripts can assist with repeatable provisioning tasks such as DNS or origin certificate issuance.

### 3.1 Overview
Configure Cloudflare so client traffic is encrypted end-to-end (Full strict), HTTP is redirected to HTTPS at the edge, and security headers are applied consistently. Cloudflare generates these security headers at the edge for both site and redirect zones; do not add Apache-level header directives unless a future exception is explicitly justified. Origin servers use per-domain Cloudflare Origin certificates; Cloudflare presents edge certificates to visitors. Use the UI for clarity; layer scripts where it saves time. For terminology, see `DNSTerms.md` and `MULTI.md` section 3.1 (`MULTI.md#31-terminology-apex-zone-subdomain`).

These settings reflect the current tested configuration for this repository and will be updated as validation continues and platform behavior changes.

### 3.2 Proxy Model (Summary)
Cloudflare operates as a reverse proxy in front of the origin. This runbook focuses on the operational steps; architectural rationale and tradeoffs are documented in `MULTI.md` section 2.2 (`MULTI.md#22-edge-layer-cloudflare-proxy-dns-cdn-ssl`) and in its Glossary (`MULTI.md#10-glossary`).

### 3.3 HTTPS Responsibility (Summary)
HTTPS enforcement and security headers are applied at the Cloudflare edge. Avoid Apache-level HTTP→HTTPS redirects to prevent loops. For the rationale and design constraints, see `MULTI.md` section 2.2 (`MULTI.md#22-edge-layer-cloudflare-proxy-dns-cdn-ssl`); for stepwise UI actions, continue with the sections below.

### 3.4 HTTPS Flow
The UI flow below provides a reliable baseline for new domains. The steps are written in the order they should be performed.

#### 3.4.1 DNS Proxy
Use the DNS screen to set the apex A record, proxy it, and then point `www` at the apex so there is one source of truth for the origin address.

- Path: `DNS`.
- Add A for apex (`@`) pointing to the origin; enable proxy (orange cloud).
- Add CNAME for `www` pointing to apex when proxying.
- Add wildcard `*` CNAME to apex to catch stray hosts, while keeping explicit apex/www records when proxying.
- If origin IP changes, update DNS before enforcing strict TLS to avoid downtime.
- Assumes nameservers already point to Cloudflare; DNSSEC is not required for this flow.

#### 3.4.2 SSL Mode
Set SSL mode to Full (strict) after origin certificates are in place.

- Path: `SSL/TLS` → `Overview`.
- Setting: “SSL/TLS encryption mode” → select `Full (strict)`.

#### 3.4.3 TLS Settings
Enable HTTPS enforcement and modern TLS at the edge. These are Free-tier options; verify each setting because some are enabled by default.

- Path: `SSL/TLS` → `Edge Certificates`.
- Enable “Always Use HTTPS.”
- Set Minimum TLS to TLS 1.2 (from default 1.0).
- Enable Opportunistic Encryption.
- Enable TLS 1.3 (though Apache does not support it as of December 2025).
- Enable Automatic HTTPS Rewrites.

HSTS is documented in a dedicated section below.

#### 3.4.4 Origin Cert
Use a separate origin certificate per domain (apex+www pair) to avoid exposing tenant lists and to keep trust scoped. These certificates are used between Cloudflare and the origin and are not publicly trusted.

- Path: `SSL/TLS` → `Origin Server` → `Create Certificate`.
- Options: “Let Cloudflare generate a private key and CSR”; Hostnames: apex + www; Key type: RSA; Validity: default.
- Download cert/key in PEM format; install on origin at `/etc/ssl/cloudflare-origin/certs|keys/<safe>.{crt,key}` (safe = domain without dots/hyphens).

#### 3.4.5 Security Settings
Use the Security Settings page to enable baseline protections. These settings are expected to be consistent across domains.

- Path: `Security` → `Settings`.
- Enable Browser integrity check.
- Enable Replace insecure JavaScript libraries.
- Schema validation is currently OFF, pending further investigation. TODO: Revisit schema validation; it is not exposed by the standard zone settings API, so confirm where it can be read or set before automating.
- Leaked credentials detection is enabled for WordPress zones to reduce credential-stuffing risk and should be kept consistent across the multisite and single-site zones.

#### 3.4.6 Security Headers
Use Managed Transforms to add standard response headers at the edge.

- Path: `Rules` → `Settings` → `Managed Transforms` → `HTTP Response Headers` → “Add security headers.”
- Managed Transforms reference: [Add security headers] https://developers.cloudflare.com/rules/transform/managed-transforms/reference/#add-security-headers
- Expected headers:
  - `Strict-Transport-Security: max-age=31536000; includeSubDomains`.
  - `X-Content-Type-Options: nosniff`.
  - `X-XSS-Protection: 1; mode=block`.
  - `X-Frame-Options: SAMEORIGIN`.
  - `Expect-CT: max-age=86400, enforce`.
  - `Referrer-Policy: same-origin`.

### 3.5 Automation
Cloudflare UI is authoritative for SSL mode, redirects, and headers. Automation scripts help with DNS, origin certificate placement, and vhost generation when repeatability is needed.

#### 3.5.1 HTTPS and Security Baseline
Use the settings helper when you need to apply the HTTPS/security baseline across many zones with consistent values. This script reads `domains.csv`, resolves the zone ID per domain, and applies the baseline via the Cloudflare API, so it depends on active zones and valid credentials with edit access.

- Script: `scripts/cloud-settings.sh --site-types redirect,multisite`.
- Does: sets `ssl=strict`, enables Always Use HTTPS, raises minimum TLS to 1.2, and enables the managed “Add security headers” transform.
- Does not: modify DNS records or Redirect Rules; use `scripts/cloud-dns.sh` or `scripts/cloud-redirect.sh` for those.

#### 3.5.2 Zone DNS
Use the zone/DNS script when onboarding a new domain and you want API-driven provisioning.

- Script: `scripts/cloud-dns.sh <domain> <ip>`.
- Fit: onboarding a new domain; uses the Cloudflare API instead of the UI.
- Does: creates the zone and adds proxied A records for apex+www. Env or options: `CF_API_TOKEN`, `CF_ACCOUNT_ID`, `--token`, `--account`.

#### 3.5.3 Cert Placement
Use the unified cert helper so the same command supports manual paste, API issuance, and validation in a single workflow. This keeps the operational steps consistent across environments while preserving the default filesystem layout and permissions documented below.

- Script: `scripts/get-cert.sh <domain>` (supports `--api`, `--manual`, or `--auto`).
- Does: validate/install Cloudflare Origin cert/key into `/etc/ssl/cloudflare-origin/{certs,keys}/<safe>.{crt,key}` with perms root:ssl-cert 640; prints SANs.

#### 3.5.4 Vhost Generation
Use the vhost helper to generate HTTP/SSL vhosts that reference the origin certificate paths.

- Script: `scripts/apache-vhost.sh <domain>`.
- Uses templates pointing at origin cert paths; enables HTTP/SSL vhosts. Add origin certs first, then run; the script runs `apache2ctl configtest`.

#### 3.5.5 API Auth
Cloudflare API access is needed only when you run API-backed scripts or optional API checks. Keep authentication configuration centralized and local to the operator’s host to avoid hardcoding secrets into the repository. Prefer scoped API tokens over the Global API Key whenever the required permissions are available.

Credential terminology and where to find it in the Cloudflare UI:
- Account API token (`CF_API_TOKEN`): created under **Manage Account** → **API Tokens** (account-scoped tokens). Use this for most API scripts.
- Global API Key (`CF_API_KEY`) + email (`CF_API_EMAIL`): user-level key found under **My Profile** → **API Tokens**.
- Origin CA Key (`CF_CA_KEY`): user-level **Origin CA User Service Key** found under **My Profile** → **API Tokens**. This is required by `scripts/get-cert.sh --api`.
- Origin CA keys only authenticate Origin CA endpoints (for example `/certificates?zone_id=...`). They do not work for standard zone settings or DNS endpoints, which require an API token or global key.

These keys and tokens are not per-zone; access is controlled by account membership and permissions. If you track scope hints in the auth file (for example, `CF_TOKEN_SCOPE="account"` or `CF_KEY_SCOPE="user"`), treat them as operator notes only; scripts do not enforce or parse those hints.

Recommended approach:
- Store credentials in a local auth file and away from code repo or the execution environment.
- Scripts look up `CF_AUTH_FILE` (default: `~/.config/cloudflare/default.auth`). Keep the auth file permissions tight (`chmod 700 ~/.config/cloudflare` and `chmod 600 ~/.config/cloudflare/default.auth`). A template is available at `scripts/example.auth`. We use .auth extension for easy identification, though it is not required.
- Store the raw key values only. Do not include UI prefixes such as `200~` that appear in the Cloudflare display.

Expected variables in the auth file or environment:
- `CF_API_TOKEN` (account API token; preferred) or `CF_API_KEY` + `CF_API_EMAIL` (global API key + user email).
- `CF_CA_KEY` (Origin CA User Service Key; required for `get-cert.sh --api`).
- `CF_ACCOUNT_ID` (required for zone creation).
- `CF_ZONE_ID` (required for optional API validation checks).

Optional variables:
- `CF_ACCOUNT` (human-readable account name).
- `CF_ZONE` (zone [domain] for the account).
- `CF_ZONE_MAIN` (informational hint for the primary zone; scripts do not select a zone based on this value).
- `CF_KEY_SCOPE` (scope hint for the global API key, for example `user`).
- `CF_TOKEN_SCOPE` (scope hint for the account API token, for example `account`).
- `CF_CA_SCOPE` (scope hint for the Origin CA key, for example `user`).

When multiple `CF_ZONE`/`CF_ZONE_ID` pairs are listed in an auth file, scripts do not pick a default. For domain-scoped work they look up the matching pair for that domain, and otherwise require an explicit `--zone` or `--zone-id` (or an API lookup) to select a target.

Environment variables always take precedence over the auth file, so one-off overrides can be provided safely at runtime without editing the file. Account-scoped tokens are verified against the account endpoint rather than the user endpoint. For a quick sanity check, use `scripts/verify-cf-auth.sh`, which validates any available account API token, global API key, and Origin CA key; Origin CA verification requires a `CF_ZONE_ID`.

Domain and zone data sources:
- `domains.csv` stores the apex domain in `domain` and the Cloudflare zone identifier in `zone_id`. The `zone_name` column is informational and is recorded from the API.
- Auth files list zone pairs as `CF_ZONE=example.com` and `CF_ZONE_ID=<id>`; the zone name is the same apex domain used in `domains.csv`.
- Domain-scoped scripts resolve zone IDs by matching the domain name first and only use the zone ID for API calls.

### 3.6 Hybrid Execution
Use the mixed UI + script workflow below to keep edge policy in the UI while keeping origin actions repeatable and auditable.

Sequence per domain:
1) UI/API: create/verify zone and DNS (apex + www), proxy on.
2) UI: issue origin cert, download cert/key.
3) Automation: run `get-cert.sh` to place cert/key on origin with correct perms (manual or API-based issuance).
4) Automation: run `apache-vhost.sh` to generate/enable vhosts referencing the origin certs; the script runs `apache2ctl configtest`.
5) UI: set SSL mode to Full (strict); add HTTPS enforcement (Always Use HTTPS) and headers. Introduce Redirect Rules only if you have a tested need; otherwise leave them disabled to avoid loops.
6) Verify: browse HTTP→HTTPS redirect, check headers, confirm Full (strict) active.

Dependencies and rationale:
- Cert placement must precede enabling SSL vhosts and setting Full (strict), or strict mode will fail.
- DNS/proxy must be set before forcing HTTPS to avoid downtime.
- Avoid Apache-level HTTPS redirects when Cloudflare proxy is on; use edge redirects to prevent loops.

Interaction model:
- UI controls edge behavior (strict TLS, redirects, headers).
- Scripts configure origin (cert files, vhosts). Treat UI settings as source of truth for TLS mode and redirects; scripts should not duplicate them.

### 3.7 Notes
The notes below explain the tradeoffs for security settings that require intentional commitment or operational discipline.

#### 3.7.1 HSTS
HSTS instructs browsers that the site should only be accessed over HTTPS.

- Pros: enforces HTTPS at the browser; prevents downgrade/mixed-mode requests after first load.
- Cons: can lock you out if HTTPS breaks; preload is a long-term commitment. At this time we do NOT configure HSTS.
- If choosing HSTS, validate first: confirm apex and www redirect to HTTPS, no mixed content, certs valid (Full strict), admin/login works over HTTPS.
- Rollout: start with a short max-age (e.g., 300) if testing; raise to 31536000 with includeSubDomains when confident. Preload only when certain that HTTPS is permanent.
- Cloudflare configuration: SSL/TLS → Edge Certificates → HTTP Strict Transport Security (HSTS), after Always Use HTTPS.
- WordPress option: [Headers Security Advanced HSTS WP] https://wordpress.com/plugins/headers-security-advanced-hsts-wp.

#### 3.7.2 Redirect Config
Some zones exist only to redirect to a canonical domain (for example, short or legacy domains that should always land on the primary site). These zones should be configured to redirect at the Cloudflare edge and now follow the same HTTPS and Security baseline as singlesite and multisite domains. The intent is to eliminate drift and ensure aliases are not a weaker security posture, even if that introduces an extra redirect hop.

Recommended approach:
- Use a Redirect Rule at `Rules` → `Redirect Rules` that matches the alias host and issues a 301 to the canonical host, preserving path and query. This keeps redirects consistent for both HTTP and HTTPS and does not depend on origin behavior.
- Keep “Always Use HTTPS” enabled even when a Redirect Rule is present. This can introduce an extra hop, but the consistency across domains is preferred and reduces configuration exceptions.
- Apply the standard security headers (Managed Transforms → “Add security headers”) on redirect-only zones. This includes HSTS, so treat redirects as a long-lived commitment rather than disposable aliases.
- Require SSL mode `Full (strict)` for redirect-only zones so the edge-to-origin path remains protected if a rule is removed or misconfigured.

Operational notes:
- Ensure alias DNS records are proxied (orange cloud) so Redirect Rules apply at the edge.
- The baseline security headers now apply on both canonical and redirect zones; this trades a small redirect cost for consistent policy and simpler audits.
- Validation: confirm HTTP and HTTPS requests for both apex and `www` return 301 to the canonical host, preserve path/query, and do not loop. Use `curl -I` from a client or a browser test, and verify that the origin is not being hit directly (UFW logs should show only Cloudflare IPs if the allowlist is active).

## 4. Origin TLS
The origin layer provides the TLS endpoint Cloudflare connects to and the Apache vhost routing that serves WordPress. This layer must be correct before Full (strict) can succeed at the edge.

### 4.1 Host Services
Provision Ubuntu 24 with Apache 2.4, PHP 8.x, MySQL 8.x. Check CONF.md for the latest site-specific recommendations (versions, paths, domains).

### 4.2 Ubuntu updates
Keep the host patched with unattended security updates so origin services are not exposed to known vulnerabilities. This is a foundational dependency for the rest of the stack because Apache, PHP, OpenSSL, and kernel fixes arrive through Ubuntu security updates. Configure this before or alongside initial server provisioning.

Install and enable unattended upgrades:
```bash
sudo apt-get update && sudo apt-get install -y unattended-upgrades
sudo systemctl enable --now unattended-upgrades.service
```

Confirm the service state and recent activity:
```bash
systemctl status unattended-upgrades.service
systemctl is-enabled unattended-upgrades.service
journalctl -u unattended-upgrades.service --since "7 days ago"
```

Review and adjust configuration as needed:
```bash
sudo sed -n '1,200p' /etc/apt/apt.conf.d/20auto-upgrades
sudo sed -n '1,200p' /etc/apt/apt.conf.d/50unattended-upgrades
```

Use a dry run when validating changes:
```bash
sudo unattended-upgrades --dry-run --debug
```

If automatic reboots are allowed, set a window that matches maintenance expectations. If reboots are disabled, document the manual reboot cadence and ensure kernel updates are applied intentionally.

### 4.3 User Permissions
The deployment user (typically `ubuntu`) must be in the `ssl-cert` group to run scripts that read SSL certificates.

```bash
sudo usermod -aG ssl-cert ubuntu
```

After adding the group, log out and log back in, or run `newgrp ssl-cert` to activate. Verify with `groups ubuntu`.

### 4.4 Origin Certs
HTTPS vhosts reference these paths per template. The certificate and key must be readable by the `ssl-cert` group and owned by root.

- `/etc/ssl/cloudflare-origin/certs/<safe>.crt`
- `/etc/ssl/cloudflare-origin/keys/<safe>.key`
- Permissions: root:ssl-cert 640.

Install with the unified helper:

```bash
sudo scripts/get-cert.sh --manual <domain>
```

```bash
sudo scripts/get-cert.sh --api <domain>
```

### 4.5 Web Vhosts
The web server uses one vhost per domain, driven by templates that reference the origin certificates.

- Enable Apache modules: `sudo a2enmod rewrite ssl headers && sudo systemctl reload apache2`.
- Model: one vhost per domain, no wildcards.
- Templates: `templates/apache-*.conf`.
- Script: `sudo scripts/apache-vhost.sh`.
- Runs: `sudo apache2ctl configtest && sudo systemctl reload apache2`.

Host validation note: Apache’s `Require host` does **not** validate the `Host` header. It performs a reverse DNS lookup on the client IP and compares that name to the listed hostnames. This fails for Cloudflare origins because the client IP is a Cloudflare edge address, not the site’s hostname. If you need to validate the `Host` header explicitly, use an expression instead:
```apache
<Location />
    Require expr %{HTTP_HOST} == 'alphaeos.net' || %{HTTP_HOST} == 'www.alphaeos.net'
</Location>
```
If you do not require host header validation, omit the `Require host`/`Require expr` blocks entirely and rely on `ServerName`/`ServerAlias` plus the default vhost fallback.

### 4.6 PHP Database
Database name and user configuration should be tracked alongside the domain inventory so the origin and WordPress layers can be validated consistently.

### 4.7 WordPress Files and Permissions
Keep WordPress readable by the web server while keeping code write-restricted. The goal is to make uploads writable without granting write access to the core, plugins, themes, or configuration files.

Site roots and layout:
- Multisite root: `/var/www/html/wordpress`
- Single-site root: `/var/www/html/zero.directory`

Ownership and permissions model:
- Default WordPress tree: `www-data:www-data` with directories at 750 and files at 640. This keeps runtime ownership consistent for WordPress operations while avoiding world-readable files.
- Exceptions: keep the site root directory, `.htaccess`, and `wp-config.php` owned by root or the deployer account (group `www-data`) so these files remain write-restricted even when the rest of the tree is owned by `www-data`.
- Uploads and cache directories under `wp-content`: writable by `www-data` only. Prefer `www-data` ownership with 750/640 rather than making the entire tree group-writable.

Config and rewrite files:
- `wp-config.php`: keep out of webroot if practical; include DB creds, salts, and multisite constants; permissions 640, owner root/deployer, group `www-data` so Apache can read.
- Multisite `.htaccess`: standard subdirectory rules from WordPress docs (see `.htaccess` structure below).
- Single-site `.htaccess`: standard single-site rules (see `.htaccess` structure below).

When tracking or staging configuration variants, use explicit filenames alongside the live file so it is clear which version is active. Examples for multisite:
- Current: `/var/www/html/wordpress/wp-config.php`
- SSL configuration staging: `/var/www/html/wordpress/wp-config.php.ssl`
- Production-hardening snapshot: `/var/www/html/wordpress/wp-config.php.prod`

Template sources:
- Multisite templates: `templates/wp-config-multisite.php` and `templates/wp-config-multisite-deployed.php`.
- Single-site templates: `templates/wp-config-singlesite.php` and `templates/wp-config-singlesite-deployed.php`.
- `.htaccess` templates: `templates/htaccess-multisite` and `templates/htaccess-singlesite`.

### 4.8 .htaccess Structure and Routing
We keep WordPress rewrite rules in `.htaccess` rather than moving them into vhost files. This keeps per-site routing logic close to the WordPress install and avoids duplicating rules across vhosts. The tradeoff is that Apache must allow overrides and must permit symlink traversal so rewrite directives are honored.

Common structure (both templates):
- Preserve the Authorization header to support REST/auth flows behind proxies.
- Block PHP-family execution in writable paths under `wp-content`.
- Block direct PHP execution in `wp-includes`.
- Define a front controller that routes non-static requests to `index.php`.

Single-site routing:
- Uses the standard WordPress front controller: if the request is not a real file or directory, it routes to `/index.php`.
- This is sufficient because there is a single site and no subdirectory prefix handling is required.

Multisite routing:
- Adds a `wp-admin` trailing slash rule that preserves an optional site prefix:
  `^([_0-9a-zA-Z-]+/)?wp-admin$ -> $1wp-admin/`.
- Short-circuits rewriting for real files or directories, then normalizes requests with optional site prefixes so `wp-content`, `wp-admin`, `wp-includes`, and `.php` paths resolve correctly.
- Finishes with a front controller rule that sends the remaining requests to `index.php`.
- These extra rules are required for subdirectory networks with mapped apex domains; they keep multisite routing intact when the external host maps to an internal subdirectory.

Template sources and validation:
- `.htaccess` templates live in `templates/htaccess-multisite` and `templates/htaccess-singlesite`.
- `check-wp.sh --template-check` can be used to confirm the live `.htaccess` contains the required rules.

Apache requirements for `.htaccess`:
- Keep `AllowOverride All` on the WordPress docroot so `.htaccess` rewrite rules are honored.
- Keep `Options FollowSymLinks` unless you are prepared to validate `SymLinksIfOwnerMatch` as a tighter alternative.

If you choose to switch to `SymLinksIfOwnerMatch`, validate that permalinks and admin paths still resolve correctly:

1) Run `sudo apache2ctl configtest` and reload Apache.
2) For each site, test the front page, a known permalink, `/wp-login.php`, `/wp-admin/` (redirect to login), and `/wp-json/`.
3) Check per-site Apache error logs for rewrite or permission errors.

Do not remove both `FollowSymLinks` and `SymLinksIfOwnerMatch` while `.htaccess` remains the source of rewrite rules; Apache will refuse the rewrite directives and permalinks will break.

We have discussed honoring Cloudflare HTTPS signals at the multisite `.htaccess` layer as an additional safeguard. If that is ever implemented, keep it limited to the multisite `.htaccess` and do not add it to the `zero.directory` single-site `.htaccess`.

### 4.9 wp-config.php Settings
This section documents the baseline `wp-config.php` flags we expect in production, and it mirrors the template comments so configuration is consistent across environments.

Defaults and environment flags:
- `WP_DEBUG`, `WP_DEBUG_LOG`, `WP_DEBUG_DISPLAY`, and `SCRIPT_DEBUG` are set to `false` by default.
- `WP_ENVIRONMENT_TYPE` is set to `production`.
- Use a guard (`if ( ! defined( 'WP_DEBUG' ) )`) so these defaults can be overridden intentionally in a staging or debugging context.

Security and update controls:
- `DISALLOW_FILE_EDIT` is `true` to prevent theme/plugin edits in wp-admin.
- `DISALLOW_FILE_MODS` remains commented by default; enable only if updates must be CLI-only.
- `DISABLE_WP_CRON` is `true`, which requires a system cron entry (see the Scheduled Cron section) to run due events.

HTTPS and admin enforcement:
- `FORCE_SSL_ADMIN` is `true` to keep `/wp-admin` and login over HTTPS.
- When Cloudflare terminates TLS at the edge and connects to the origin over HTTP, honor Cloudflare HTTPS headers in `wp-config.php` so WordPress generates HTTPS URLs. This is safe only because the origin is restricted to Cloudflare IPv4 traffic.

Example baseline block:
```php
if ( ! defined( 'WP_DEBUG' ) ) {
    define( 'WP_DEBUG', false );
    define( 'WP_DEBUG_LOG', false );
    define( 'WP_DEBUG_DISPLAY', false );
    define( 'SCRIPT_DEBUG', false );
    define( 'WP_ENVIRONMENT_TYPE', 'production' );
}

define( 'DISALLOW_FILE_EDIT', true );
// define( 'DISALLOW_FILE_MODS', true ); // CLI-only installs/updates
define( 'DISABLE_WP_CRON', true );
define( 'FORCE_SSL_ADMIN', true );

if ( ( isset( $_SERVER['HTTP_X_FORWARDED_PROTO'] ) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https' ) ||
     ( isset( $_SERVER['HTTP_CF_VISITOR'] ) && stripos( $_SERVER['HTTP_CF_VISITOR'], 'https' ) !== false ) ) {
    $_SERVER['HTTPS'] = 'on';
    $_SERVER['SERVER_PORT'] = '443';
}
```

## 5. Multisite Ops
WordPress multisite routing depends on the origin layer. Configure multisite first, then map sites to apex domains using the steps below.

### 5.1 Site Onboarding
The sequence below mirrors the multisite mapping process and should be followed in order so WordPress routing is correct.

1) Create the site in subdirectory form to obtain a blog_id.

```bash
sudo -u www-data wp --path=/var/www/html/wordpress site create \
  --slug=<slug> --title="Site Title" --email=<admin@example.com>
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
- `scripts/install-site.sh` prints a `BLOG_ID=<id>` line after verification so the blog ID can be captured for inventory updates.

### 5.2 Site Troubleshooting
When a mapped apex domain serves the primary multisite site instead of the intended site, the cause is almost always a mismatch in routing data or vhost selection. In a multisite network, WordPress routes requests by matching the incoming host and path against `wp_blogs`, and Apache must first map the request to the correct vhost via `ServerName`. If any of these pieces are out of sync, the request falls back to the primary domain and appears as the main site.

Authoritative checks, in the order they affect routing:
- **WordPress mapping (`wp_blogs`)**: confirm the domain and path are correct for the target blog ID. The mapping must be the apex domain and `/`, otherwise WordPress will not route to the intended site. Example query: `SELECT blog_id, domain, path FROM wp_blogs;`.
- **Site URLs (`wp_<blog_id>_options`)**: confirm `siteurl` and `home` are set to `https://<domain>`. If they still point at the primary domain, generated links and canonical redirects will pull visitors back to the main site. Example query: `SELECT option_name, option_value FROM wp_<id>_options WHERE option_name IN ('siteurl','home');`.
- **Apache vhost (`ServerName`)**: confirm the SSL vhost for the domain has a matching `ServerName` and that the vhost is enabled. If the `ServerName` does not match the request, Apache selects a different vhost and WordPress never sees the correct host. Example check: `grep -R "ServerName <domain>" /etc/apache2/sites-available` and confirm the file is enabled in `/etc/apache2/sites-enabled`.

Use the mapping steps in this section to correct data first, then reload Apache if you update vhost files so the routing change takes effect. Ensure edge policy is already aligned in the Cloudflare section above before public cutover.

## 6. Verification
Use the checks in this section after provisioning to confirm the stack is healthy end to end. These checks are read-oriented and are designed to highlight the first failing layer.

Validation coverage is further along than early exploration: the check scripts are exercised and the baseline below is reliable for read-oriented confirmation. Monitoring and alerting remain under development, so treat these checks as the current operational baseline until a broader observability plan is formalized.

### 6.1 Validation Checks
The list below covers the standard checks by layer. Use them to confirm configuration state before diagnosing higher-level symptoms.

- Vhosts present/enabled: `sudo ls /etc/apache2/sites-available`, `sudo ls /etc/apache2/sites-enabled`.
- SSL/TLS cert validation: `sudo openssl x509 -in /etc/ssl/cloudflare-origin/certs/<safe>.crt -noout -subject -issuer -dates -ext subjectAltName`.
- DNS reachability: `dig A <domain> +short`, `dig AAAA <domain> +short`.
- WordPress state: `sudo -u www-data wp --path=<wp_root> core version`, `wp site list` (example: `/var/www/html/wordpress` on Ubuntu, with `wordpress` as the chosen subdirectory).
- DB routing tables: `mysql -u <db_user> -p -D <db_name> -e "SELECT blog_id, domain, path FROM wp_blogs;"`.
- Functional check: browse domain → confirm HTTPS and admin login; create a test site in Network Admin and verify routing; confirm Cloudflare Full (strict) and DNS after each addition.
- Zone/DNS creation: `scripts/cloud-dns.sh <domain> <ip>` (using Cloudflare API when onboarding domains).

### 6.2 Script Partitioning
The verification scripts are partitioned by layer so failures can be isolated quickly and so output stays focused on the responsibilities of each layer. This partitioning matches the dependency chain in the runbook: host-level services must be correct before origin services, and origin services must be correct before WordPress routing and application behavior.

Use the table below as the scope contract for the three core verification scripts. If a check falls outside the script’s scope, it should be implemented in the correct layer rather than duplicated across multiple scripts.

| Script | Scope | Examples of checks |
| --- | --- | --- |
| `check-server.sh` | Ubuntu host, networking, firewall, and shared services | OS/kernel, unattended updates, SSH policy, IPv6 state, UFW allowlist, MySQL and Redis availability, WordPress cron scheduling |
| `check-origin.sh` | Origin web stack only | Apache config, enabled modules, vhost wiring, origin cert paths, PHP runtime |
| `check-wp.sh` | WordPress-only configuration | WP roots, multisite routing data, `wp-config.php` settings, template alignment, WordPress-level security posture |

This partitioning keeps Cloudflare checks (`check-cf.sh`, `check-edge.sh`) in the edge layer and reserves origin/WP checks for local filesystem and service validation. It also prevents host-level concerns (for example, cron scheduling or MySQL settings) from being duplicated in WordPress-only scripts.


## 7. Domain Transfer
Domain registration does not need to happen at Cloudflare. The common model is to keep the registrar elsewhere and use Cloudflare as the authoritative nameserver and proxy. The steps below describe registrar transfers only for cases where Cloudflare is intended to be the registrar of record, and the UI/API flows are not verified at this time. The steps below focus on the manual process and the automation outline; they are written as procedures and ideas rather than prescriptive production automation.

### 7.1 Manual Transfer
Manual transfers require an unlocked domain, a valid auth code, and nameservers already pointed at Cloudflare. The process varies slightly by registrar.

Prerequisites:
- At least 60 days since registration or last transfer.
- Domain unlocked.
- No contact-change lock.
- Nameservers already on Cloudflare.

Namecheap:
1) Dashboard → Domain List → choose domain → turn off Registrar Lock.
2) Get EPP/auth code: Domain → Sharing & Transfer → Transfer Out.
3) Cloudflare: Registrar → Transfer → enter domain + auth code; approve emails if required.

NameSilo:
1) Domain Manager → unlock domain.
2) Get auth code: Domain Manager → getAuthCode.
3) Cloudflare: Registrar → Transfer → enter domain + auth code; approve emails if required.

Cloudflare bills and adds one-year renewal; monitor status in Registrar.

### 7.2 Transfer Automation
Automated transfers are possible but require careful safeguards. Use the outline below as a planning reference rather than a production procedure.

APIs:
- Namecheap: `namecheap.domains.transfer.getEPPCode`, `namecheap.domains.setRegistrarLock` (OFF).
- NameSilo: `getAuthCode`, `domainLock` (disable).
- Cloudflare: `POST /zones/:zone_identifier/registrar/domains/:name/transfer` with `{"auth_code":"..."}`.
  - Poll: `GET /zones/:zone_identifier/registrar/domains/:name/transfer`.

Script ideas:
- `get-auth-codes.sh`: input CSV (domain, registrar); outputs domain,auth_code.
- `transfer-to-cloudflare.sh`: unlock (API), submit transfer to CF, poll status, log outcomes.

Safeguards:
- Verify the 60-day window.
- Confirm the zone exists and nameservers point to Cloudflare.
- Rate-limit calls and handle registrant approval emails manually.


## 8. Target Audience
This runbook serves operators administering Cloudflare zones and edge security, origin services (Apache, PHP, and certificates), and WordPress multisite routing. Common scenarios include onboarding a new domain (proxy, origin cert, HTTPS enforcement), validating TLS after origin changes, diagnosing routing or SSL issues, and validating changes after Cloudflare updates. Recommended skills include navigating Cloudflare DNS/SSL/Rules, Bash with sudo, Apache vhost management, WP-CLI, and basic MySQL queries. Architectural rationale lives in `MULTI.md` sections 2–5 (`MULTI.md#2-architecture--design-decisions`, `MULTI.md#3-network--domain-model`, `MULTI.md#4-infrastructure-layers`, `MULTI.md#5-operational-tradeoffs`), and terminology is defined in `DNSTerms.md`.
