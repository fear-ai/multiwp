# Operations Runbook
Date: January 10, 2026

## Introduction
This runbook consolidates the operational steps for Cloudflare edge configuration, origin TLS/Apache setup, and WordPress multisite operations. It is organized in dependency order so each layer is configured and validated before the next layer relies on it. Use this document as the canonical operational guide, and reference `scripts/Scripts.md` for exact option and environment variable interfaces when running scripts.

The dependency chain is explicit: Cloudflare edge behavior depends on correct DNS and SSL/TLS configuration, origin TLS and Apache vhosts depend on valid certificates and permissions, and WordPress routing depends on the origin layer being correct. This ordering avoids diagnosing downstream symptoms before the upstream cause is resolved.

## Cloudflare Edge
Cloudflare edge configuration defines how traffic reaches the origin and how HTTPS, redirects, and security headers are enforced. The UI is authoritative for edge policy, while scripts can assist with repeatable provisioning tasks such as DNS or origin certificate issuance.

### Overview
Configure Cloudflare so client traffic is encrypted end-to-end (Full strict), HTTP is redirected to HTTPS at the edge, and security headers are applied consistently. Origin servers use per-domain Cloudflare Origin certificates; Cloudflare presents edge certificates to visitors. Use the UI for clarity; layer scripts where it saves time. For terminology, see `DNSTerms.md`.

These settings reflect the current tested configuration for this repository and will be updated as validation continues and platform behavior changes.

### Proxy Model
Cloudflare’s orange cloud behaves as a reverse proxy: clients connect to Cloudflare; Cloudflare connects to our origin. This provides origin address shielding and enables caching, WAF, and edge TLS features. Our usage proxies apex and `www`, issues origin certs per apex+www pair, and lets Cloudflare enforce HTTPS and headers at the edge.

Reverse proxy background: [Cloudflare reverse proxy] https://www.cloudflare.com/learning/cdn/glossary/reverse-proxy/ [MDN reverse proxy] https://developer.mozilla.org/en-US/docs/Glossary/Reverse_proxy

### HTTPS Responsibility
Edge HTTPS and headers belong at Cloudflare; do not add redundant Apache redirects to avoid loops and extra hops. Use Force HTTPS via Edge Certificates because “Always Use HTTPS” is simple and avoids custom rule errors.

Redirect Rules give more control but carry more risk. Use Redirect Rules only when you need custom logic. When used, configure `Rules` → `Redirect Rules` with a condition that matches apex or `www` and a 301 to `https://{host}{uri}`. Turn “Always Use HTTPS” off if using Rules to avoid overlapping redirects.

Warning: misconfigured Rules or overlapping redirects can create loops. Use Redirect Rules only when needed and have a tested plan to recover.

### HTTPS Flow
The UI flow below provides a reliable baseline for new domains. The steps are written in the order they should be performed.

#### DNS Proxy
Use the DNS screen to set the apex A record, proxy it, and then point `www` at the apex so there is one source of truth for the origin address.

- Path: `DNS`.
- Add A for apex (`@`) pointing to the origin; enable proxy (orange cloud).
- Add CNAME for `www` pointing to apex when proxying.
- Add wildcard `*` CNAME to apex to catch stray hosts, while keeping explicit apex/www records when proxying.
- If origin IP changes, update DNS before enforcing strict TLS to avoid downtime.
- Assumes nameservers already point to Cloudflare; DNSSEC is not required for this flow.

#### SSL Mode
Set SSL mode to Full (strict) after origin certificates are in place.

- Path: `SSL/TLS` → `Overview`.
- Setting: “SSL/TLS encryption mode” → select `Full (strict)`.

#### TLS Settings
Enable HTTPS enforcement and modern TLS at the edge. These are Free-tier options; verify each setting because some are enabled by default.

- Path: `SSL/TLS` → `Edge Certificates`.
- Enable “Always Use HTTPS.”
- Set Minimum TLS to TLS 1.2 (from default 1.0).
- Enable Opportunistic Encryption.
- Enable TLS 1.3 (though Apache does not support it as of December 2025).
- Enable Automatic HTTPS Rewrites.

HSTS is documented in a dedicated section below.

#### Origin Cert
Use a separate origin certificate per domain (apex+www pair) to avoid exposing tenant lists and to keep trust scoped. These certificates are used between Cloudflare and the origin and are not publicly trusted.

- Path: `SSL/TLS` → `Origin Server` → `Create Certificate`.
- Options: “Let Cloudflare generate a private key and CSR”; Hostnames: apex + www; Key type: RSA; Validity: default.
- Download cert/key in PEM format; install on origin at `/etc/ssl/cloudflare-origin/certs|keys/<safe>.{crt,key}` (safe = domain without dots/hyphens).

#### Security Settings
Use the Security Settings page to enable baseline protections. These settings are expected to be consistent across domains.

- Path: `Security` → `Settings`.
- Enable Browser integrity check.
- Enable Replace insecure JavaScript libraries.
- Schema validation is currently OFF, pending further investigation.
- Leaked credentials detection is not enabled in this runbook; evaluate separately before enabling.

#### Security Headers
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

### Automation
Cloudflare UI is authoritative for SSL mode, redirects, and headers. Automation scripts help with DNS, origin certificate placement, and vhost generation when repeatability is needed.

#### Zone DNS
Use the zone/DNS script when onboarding a new domain and you want API-driven provisioning.

- Script: `scripts/cloud-dns.sh <domain> <ip>`.
- Fit: onboarding a new domain; uses the Cloudflare API instead of the UI.
- Does: creates the zone and adds proxied A records for apex+www. Env or options: `CF_API_TOKEN`, `CF_ACCOUNT_ID`, `--token`, `--account`.

#### Cert Placement
Use the unified cert helper so the same command supports manual paste, API issuance, and validation in a single workflow. This keeps the operational steps consistent across environments while preserving the default filesystem layout and permissions documented below.

- Script: `scripts/get-cert.sh <domain>` (supports `--api`, `--manual`, or `--auto`).
- Does: validate/install Cloudflare Origin cert/key into `/etc/ssl/cloudflare-origin/{certs,keys}/<safe>.{crt,key}` with perms root:ssl-cert 640; prints SANs.

#### Vhost Generation
Use the vhost helper to generate HTTP/SSL vhosts that reference the origin certificate paths.

- Script: `scripts/apache-vhost.sh <domain>`.
- Uses templates pointing at origin cert paths; enables HTTP/SSL vhosts. Add origin certs first, then run; the script runs `apache2ctl configtest`.

#### API Auth
Cloudflare API access is needed only when you run API-backed scripts or optional API checks. Keep authentication configuration centralized and local to the operator’s host to avoid hardcoding secrets into the repository. Prefer scoped API tokens over the Global API Key whenever the required permissions are available.

Credential terminology and where to find it in the Cloudflare UI:
- Account API token (`CF_API_TOKEN`): created under **Manage Account** → **API Tokens** (account-scoped tokens). Use this for most API scripts.
- Global API Key (`CF_API_KEY`) + email (`CF_API_EMAIL`): user-level key found under **My Profile** → **API Tokens**.
- Origin CA Key (`CF_CA_KEY`): user-level **Origin CA User Service Key** found under **My Profile** → **API Tokens**. This is used by `scripts/get-cert.sh --api`.

These keys and tokens are not per-zone; access is controlled by account membership and permissions. If you track scope hints in the auth file (for example, `CF_TOKEN_SCOPE="account"` or `CF_KEY_SCOPE="user"`), treat them as operator notes only; scripts do not enforce or parse those hints.

Recommended approach:
- Store credentials in a local auth file and away from code repo or the execution environment.
- Scripts look up `CF_AUTH_FILE` (default: `~/.config/cloudflare/default.auth`). Keep the auth file permissions tight (`chmod 700 ~/.config/cloudflare` and `chmod 600 ~/.config/cloudflare/default.auth`). A template is available at `scripts/example.auth`. We use .auth extension for easy identification, though it is not required.
- Store the raw key values only. Do not include UI prefixes such as `200~` that appear in the Cloudflare display.

Expected variables in the auth file or environment:
- `CF_API_TOKEN` (account API token; preferred) or `CF_API_KEY` + `CF_API_EMAIL` (global API key + user email).
- `CF_CA_KEY` (Origin CA User Service Key; required for `get-cert.sh --api` unless an API token with Origin CA permission is used).
- `CF_ACCOUNT_ID` (required for zone creation).
- `CF_ZONE_ID` (required for optional API validation checks).

Optional variables:
- `CF_ACCOUNT` (human-readable account name).
- `CF_ZONE` (zone [domain] for the account).
- `CF_ZONE_MAIN` (primary zone/domain when multiple zones exist).
- `CF_KEY_SCOPE` (scope hint for the global API key, for example `user`).
- `CF_TOKEN_SCOPE` (scope hint for the account API token, for example `account`).
- `CF_CA_SCOPE` (scope hint for the Origin CA key, for example `user`).

When multiple `CF_ZONE`/`CF_ZONE_ID` pairs are listed in an auth file, scripts default to the first `CF_ZONE_ID` and use `CF_ZONE_MAIN` (if set) as the default zone name. Pass `--zone-id` (or set `CF_ZONE_ID`) to target a specific zone explicitly.

Environment variables always take precedence over the auth file, so one-off overrides can be provided safely at runtime without editing the file. Account-scoped tokens are verified against the account endpoint rather than the user endpoint. For a quick sanity check, use `scripts/verify-cf-auth.sh`, which validates any available account API token, global API key, and Origin CA key; Origin CA verification requires a `CF_ZONE_ID`.

### Hybrid Execution
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

### Notes
The notes below explain the tradeoffs for security settings that require intentional commitment or operational discipline.

#### HSTS
HSTS instructs browsers that the site should only be accessed over HTTPS.

- Pros: enforces HTTPS at the browser; prevents downgrade/mixed-mode requests after first load.
- Cons: can lock you out if HTTPS breaks; preload is a long-term commitment. At this time we do NOT configure HSTS.
- If choosing HSTS, validate first: confirm apex and www redirect to HTTPS, no mixed content, certs valid (Full strict), admin/login works over HTTPS.
- Rollout: start with a short max-age (e.g., 300) if testing; raise to 31536000 with includeSubDomains when confident. Preload only when certain that HTTPS is permanent.
- Cloudflare configuration: SSL/TLS → Edge Certificates → HTTP Strict Transport Security (HSTS), after Always Use HTTPS.
- WordPress option: [Headers Security Advanced HSTS WP] https://wordpress.com/plugins/headers-security-advanced-hsts-wp.

#### Redirect Config
Some zones exist only to redirect to a canonical domain (for example, short or legacy domains that should always land on the primary site). These zones should be configured to redirect at the Cloudflare edge, keep the canonical security policies on the primary domain, and avoid extra hops or browser-level stickiness that is unnecessary for aliases.

Recommended approach:
- Use a Redirect Rule at `Rules` → `Redirect Rules` that matches the alias host and issues a 301 to the canonical host, preserving path and query. This keeps redirects consistent for both HTTP and HTTPS and does not depend on origin behavior.
- Keep “Always Use HTTPS” off for redirect-only zones when a Redirect Rule is present. The rule handles HTTP→HTTPS directly and avoids an extra redirect hop on the alias host.
- Keep HSTS off for redirect-only zones. HSTS is a browser-level commitment and should be reserved for the canonical domain, not for disposable or temporary aliases.
- Prefer Full (strict) SSL mode when a valid origin cert is present so the edge remains secure even if a redirect rule is accidentally disabled. If no valid origin cert exists and the redirect rule is the only intended behavior, use Full instead of Flexible to avoid silent downgrade.

Operational notes:
- Ensure alias DNS records are proxied (orange cloud) so Redirect Rules apply at the edge.
- Security headers should be enforced on the canonical domain. On redirect-only zones, they are secondary to the redirect response and can be absent.

## Origin TLS
The origin layer provides the TLS endpoint Cloudflare connects to and the Apache vhost routing that serves WordPress. This layer must be correct before Full (strict) can succeed at the edge.

### Host Services
Provision Ubuntu 24 with Apache 2.4, PHP 8.x, MySQL 8.x. Check CONF.md for the latest site-specific recommendations (versions, paths, domains).

### User Permissions
The deployment user (typically `ubuntu`) must be in the `ssl-cert` group to run scripts that read SSL certificates.

```bash
sudo usermod -aG ssl-cert ubuntu
```

After adding the group, log out and log back in, or run `newgrp ssl-cert` to activate. Verify with `groups ubuntu`.

### Origin Certs
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

### Web Vhosts
The web server uses one vhost per domain, driven by templates that reference the origin certificates.

- Enable Apache modules: `sudo a2enmod rewrite ssl headers && sudo systemctl reload apache2`.
- Model: one vhost per domain, no wildcards.
- Templates: `templates/apache-*.conf`.
- Script: `sudo scripts/apache-vhost.sh`.
- Runs: `sudo apache2ctl configtest && sudo systemctl reload apache2`.

### PHP Database
Database name/user configuration is tracked in CONF.md.

### WordPress Files
Ensure `www-data` can read/write uploads and keep code write-restricted.

### WP Config
Keep configuration and rewrite rules aligned with multisite requirements so routing remains stable.

- `wp-config.php`: keep out of webroot if practical; include DB creds, salts, multisite constants; perms 640, owner root/deployer, group `www-data` if Apache must read.
- Multisite `.htaccess`: standard subdirectory rules from WordPress docs; `AllowOverride All` on docroot; avoid custom rewrites that bypass multisite routing.
- Single-site `.htaccess`: standard single-site rules; typically 640, owned by deployer, readable by web server.

## Multisite Ops
WordPress multisite routing depends on the origin layer. Configure multisite first, then map sites to apex domains using the steps below.

### Site Onboarding
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

### Site Troubleshooting
When a mapped apex domain serves the primary multisite site instead of the intended site, the cause is almost always a mismatch in routing data or vhost selection. In a multisite network, WordPress routes requests by matching the incoming host and path against `wp_blogs`, and Apache must first map the request to the correct vhost via `ServerName`. If any of these pieces are out of sync, the request falls back to the primary domain and appears as the main site.

Authoritative checks, in the order they affect routing:
- **WordPress mapping (`wp_blogs`)**: confirm the domain and path are correct for the target blog ID. The mapping must be the apex domain and `/`, otherwise WordPress will not route to the intended site. Example query: `SELECT blog_id, domain, path FROM wp_blogs;`.
- **Site URLs (`wp_<blog_id>_options`)**: confirm `siteurl` and `home` are set to `https://<domain>`. If they still point at the primary domain, generated links and canonical redirects will pull visitors back to the main site. Example query: `SELECT option_name, option_value FROM wp_<id>_options WHERE option_name IN ('siteurl','home');`.
- **Apache vhost (`ServerName`)**: confirm the SSL vhost for the domain has a matching `ServerName` and that the vhost is enabled. If the `ServerName` does not match the request, Apache selects a different vhost and WordPress never sees the correct host. Example check: `grep -R "ServerName <domain>" /etc/apache2/sites-available` and confirm the file is enabled in `/etc/apache2/sites-enabled`.

Use the mapping steps in this section to correct data first, then reload Apache if you update vhost files so the routing change takes effect. Ensure edge policy is already aligned in the Cloudflare section above before public cutover.

## Verification
Use the checks in this section after provisioning to confirm the stack is healthy end to end. These checks are read-oriented and are designed to highlight the first failing layer.

### Validation Checks
The list below covers the standard checks by layer. Use them to confirm configuration state before diagnosing higher-level symptoms.

- Vhosts present/enabled: `sudo ls /etc/apache2/sites-available`, `sudo ls /etc/apache2/sites-enabled`.
- SSL/TLS cert validation: `sudo openssl x509 -in /etc/ssl/cloudflare-origin/certs/<safe>.crt -noout -subject -issuer -dates -ext subjectAltName`.
- DNS reachability: `dig A <domain> +short`, `dig AAAA <domain> +short`.
- WordPress state: `sudo -u www-data wp --path=<wp_root> core version`, `wp site list` (example: `/var/www/html/wordpress` on Ubuntu, with `wordpress` as the chosen subdirectory).
- DB routing tables: `mysql -u <db_user> -p -D <db_name> -e "SELECT blog_id, domain, path FROM wp_blogs;"`.
- Functional check: browse domain → confirm HTTPS and admin login; create a test site in Network Admin and verify routing; confirm Cloudflare Full (strict) and DNS after each addition.
- Zone/DNS creation: `scripts/cloud-dns.sh <domain> <ip>` (using Cloudflare API when onboarding domains).


### Domain Transfer
Domain registration does not need to happen at Cloudflare. The common model is to keep the registrar elsewhere and use Cloudflare as the authoritative nameserver and proxy. The steps below describe registrar transfers only for cases where Cloudflare is intended to be the registrar of record, and the UI/API flows are not verified at this time. The steps below focus on the manual process and the automation outline; they are written as procedures and ideas rather than prescriptive production automation.

#### Manual Transfer
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

#### Transfer Automation
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


## Target Audience
This runbook serves operators administering Cloudflare zones and edge security, origin services (Apache, PHP, and certificates), and WordPress multisite routing. Common scenarios include onboarding a new domain (proxy, origin cert, HTTPS enforcement), validating TLS after origin changes, diagnosing routing or SSL issues, and validating changes after Cloudflare updates. Recommended skills include navigating Cloudflare DNS/SSL/Rules, Bash with sudo, Apache vhost management, WP-CLI, and basic MySQL queries. Architectural rationale lives in MULTI.md, and terminology is defined in DNSTerms.md.
