# Cloudflare Settings & Certs For Multi WordPress
Date: January 5, 2026

## Introduction
Cloudflare edge configuration for the multisite network, covering the preferred UI-driven workflow and optional automation helpers. Pair with ConfigServers.md for origin/vhost steps.

## Table of Contents
- [Introduction](#introduction)
- [Overview](#overview)
- [Proxy Model (Cloudflare Edge)](#proxy-model-cloudflare-edge)
- [HTTPS Responsiblity](#https-responsiblity)
- [UI Flow: HTTPS & Certs](#ui-flow-https--certs)
  - [DNS & Proxy](#dns--proxy)
  - [Enforce Full (Strict) SSL Encryption](#enforce-full-strict-ssl-encryption)
  - [Use HTTPS and TLS 1.2](#use-https-and-tls-12)
  - [Issue Origin Certificate](#issue-origin-certificate)
  - [Security Settings](#security-settings)
  - [Security Headers](#security-headers)
- [Configuration Automation](#configuration-automation)
  - [Create Zone + DNS](#create-zone--dns)
  - [Origin Cert Placement](#origin-cert-placement)
  - [Vhost Generation](#vhost-generation)
  - [API Authentication](#api-authentication)
- [Hybrid Execution (UI + Automation)](#hybrid-execution-ui--automation)
- [Domain Registration & Transfer to Cloudflare](#domain-registration--transfer-to-cloudflare)
  - [Manual Transfer Steps (Namecheap, NameSilo)](#manual-transfer-steps-namecheap-namesilo)
  - [Automation Outline for Transfers](#automation-outline-for-transfers)
- [Notes & Rationale](#notes--rationale)
  - [HSTS](#hsts)
  - [Redirect-only Configuration](#redirect-only-configuration)
- [Target Audience](#target-audience)

## Overview
Configure Cloudflare so client traffic is encrypted end-to-end (Full strict), HTTP is redirected to HTTPS at the edge, and security headers are applied consistently. Origin servers use per-domain Cloudflare Origin certificates; Cloudflare presents edge certificates to visitors. Use the UI for clarity; layer scripts where it saves time. For terminology, see `DNSTerms.md`.
NOTE: Listed settings reflect our best understanding of preferred configuration for our use case, based on tests of this specific setup. They are likely to evolve as we continue validation and tools or services mutate.

## Proxy Model (Cloudflare Edge)
- Cloudflare’s orange cloud behaves as a reverse proxy: clients connect to Cloudflare; Cloudflare connects to our origin. References: [Cloudflare reverse proxy overview](https://www.cloudflare.com/learning/cdn/glossary/reverse-proxy/), [MDN reverse proxy](https://developer.mozilla.org/en-US/docs/Glossary/Reverse_proxy).
- Benefits: hides origin addresses, offloads TLS, enables caching and WAF features.
- Our usage: proxy apex and `www`, issue origin certs per apex+www pair, and let Cloudflare enforce HTTPS and headers at the edge.

## HTTPS Responsiblity
- Edge HTTPS and headers belong at Cloudflare; do not add [redundant] Apache redirects to avoid loops and extra hops.
- On Cloudflare use Force HTTPS via Edge Certificates rather than Redirect Rules. “Always Use HTTPS” ON is simple and avoids custom rule errors.
- Redirect Rules give more control but at a higher risk: `Rules` → `Redirect Rules`; Condition `Hostname equals apex OR www`; Action: 301 to `https://{host}{uri}`. Turn “Always Use HTTPS” OFF if using Rules.
**Warning:** misconfigured Rules or overlapping redirects can create loops; use only when needed and have a solid test plan and a recovery procedure.

## UI Flow: HTTPS & Certs

### DNS & Proxy
- Path: `DNS`.
- Add A for apex (`@`) pointing to the origin; enable proxy (orange cloud).
- Add CNAME for `www` pointing to apex when proxying; this keeps a single source of truth for the origin address.
- Optional: wildcard `*` CNAME to apex to catch stray hosts, but keep explicit apex/www records when proxying.
- If origin IP changes, update DNS before enforcing strict TLS to avoid downtime.
- Assumes nameservers already point to Cloudflare; DNSSEC is not required for this flow.

### Enforce Full (Strict) SSL Encryption
- Path: `SSL/TLS` → `Overview`.
- Setting: “SSL/TLS encryption mode” → select `Full (strict)`.

### Use HTTPS and TLS 1.2
- Path: `SSL/TLS` → `Edge Certificates`.
We configure ON the following settings available under the Free tier. Several may be ON by default or always ON.
- Always Use HTTPS.
- Minimum TLS: TLS 1.2 (from default 1.0).
- Opportunistic Encryption.
- TLS 1.3 [though Apache does not support it as of December 2025].
- Automatic HTTPS Rewrites.
NOTE: For HSTS see a dedicated section below.

### Issue Origin Certificate
Use separate origin cert per domain (apex+www pair) to avoid exposing tenant lists and to keep trust scoped. The certs are used between Cloudflare and origin, not publicly trusted.
- Path: `SSL/TLS` → `Origin Server` → `Create Certificate`.
- Options: “Let Cloudflare generate a private key and CSR”; Hostnames: apex + www; Key type: RSA; Validity: default.
- Download cert/key in PEM format; install on origin at `/etc/ssl/cloudflare-origin/certs|keys/<safe>.{crt,key}` (safe = domain without dots/hyphens).

### Security Settings
- Path: `Security` → `Settings`.
In addition to the *always on* settings, the following are **ON**:
- Browser integrity check.
- Replace insecure JavaScript libraries.
- Schema validation **OFF**.
Under consideration for inclusion:
- Leaked credentials detection.

### Security Headers
- Path: `Rules` → `Settings` → `Managed Transforms` → `HTTP Response Headers` → “Add security headers.” [Cloudflare add security headers](https://developers.cloudflare.com/rules/transform/managed-transforms/reference/#add-security-headers).
- Configures:
  - `Strict-Transport-Security: max-age=31536000; includeSubDomains`.
  - `X-Content-Type-Options: nosniff`.
  - `X-XSS-Protection: 1; mode=block`.
  - `X-Frame-Options: SAMEORIGIN`.
  - `Expect-CT: max-age=86400, enforce`.
  - `Referrer-Policy: same-origin`.

## Configuration Automation
Cloudflare UI is authoritative for SSL mode, redirects, and headers. Automation scripts can help with DNS, origin cert placement, and vhost generation.

### Create Zone + DNS
- Script: `scripts/cloud-dns.sh <domain> <ipv4>`.
- Fit: use when onboarding a new domain; interacts with the Cloudflare API instead of the UI.
- Does: creates the zone (full setup) and adds proxied A records for apex+www. Env or flags: `CF_API_TOKEN`, `CF_ACCOUNT_ID`, `--token`, `--account`.

### Origin Cert Placement
Use the unified cert helper so the same command supports manual paste, API issuance, and validation in a single workflow. This keeps the operational steps consistent across environments while preserving the default filesystem layout and permissions documented in ConfigServers.md.

- Script: `scripts/get-cert.sh <domain>` (supports `--api`, `--manual`, or `--auto`).
- Does: validate/install Cloudflare Origin cert/key into `/etc/ssl/cloudflare-origin/{certs,keys}/<safe>.{crt,key}` with perms root:ssl-cert 640; prints SANs.
- Paths: defaults align with the origin cert locations defined in `ConfigServers.md`; update that runbook first if you need non-default storage and keep templates/scripts in sync.

### Vhost Generation
- Script: `scripts/apache-vhost.sh <domain>`.
- Uses templates pointing at origin cert paths; enables HTTP/SSL vhosts. Add origin certs first, then run; script runs `apache2ctl configtest`.

### API Authentication
Cloudflare API access is needed only when you run the API-backed scripts or optional API checks. Keep authentication configuration centralized and local to the operator’s host to avoid hardcoding secrets into the repository.
Prefer scoped API tokens over the Global API Key whenever the required permissions are available.

Credential terminology and where to find it in the Cloudflare UI:
- Account API token (`CF_API_TOKEN`): created under **Manage Account** → **API Tokens** (account-scoped tokens). Use this for most API scripts.
- Global API Key (`CF_API_KEY`) + email (`CF_API_EMAIL`): user-level key found under **My Profile** → **API Tokens**.
- Origin CA Key (`CF_CA_KEY`): user-level **Origin CA User Service Key** found under **My Profile** → **API Tokens**. This is used by `scripts/get-cert.sh --api`.

These keys and tokens are not per-zone; access is controlled by account membership and permissions. If you track scope hints in the auth file (for example, `CF_TOKEN_SCOPE="account"` or `CF_KEY_SCOPE="user"`), treat them as operator notes only; scripts do not enforce or parse those hints.

Recommended approach:
- Store credentials in a local auth file and away from code repo or the execution environment.
- Scripts look-up `CF_AUTH_FILE` (default: `~/.config/cloudflare/default.auth`). Keep the auth file permissions tight (`chmod 700 ~/.config/cloudflare` and `chmod 600 ~/.config/cloudflare/default.auth`). A template is available at `scripts/example.auth`. We use .auth extension for easy identification, though it is not required.
- Store the raw key values only. Do not include UI prefixes such as `200~` that may appear in the Cloudflare display.

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

## Hybrid Execution (UI + Automation)
- Sequence (per domain):
  1) UI/API: Create/verify zone and DNS (apex + www), proxy on.
  2) UI: Issue origin cert, download cert/key.
  3) Automation: Run `get-cert.sh` to place cert/key on origin with correct perms (manual or API-based issuance).
  4) Automation: Run `apache-vhost.sh` to generate/enable vhosts referencing the origin certs; script runs configtest.
  5) UI: Set SSL mode to Full (strict); add HTTPS enforcement (Always Use HTTPS) and headers. Introduce Redirect Rules only if you have a tested need; otherwise leave them disabled to avoid loops.
  6) Verify: Browse HTTP→HTTPS redirect, check headers, confirm Full (strict) active.
- Dependencies:
  - Cert placement must precede enabling SSL vhosts and setting Full (strict), or strict mode will fail.
  - DNS/proxy must be set before forcing HTTPS to avoid downtime.
  - Avoid Apache-level HTTPS redirects when Cloudflare proxy is on; use edge redirects to prevent loops.
- Interaction model:
  - UI controls edge behavior (strict TLS, redirects, headers).
  - Scripts configure origin (cert files, vhosts). Treat UI settings as source of truth for TLS mode and redirects; scripts should not duplicate them.

## Domain Registration & Transfer to Cloudflare

### Manual Transfer Steps (Namecheap, NameSilo)
- Prereqs: ≥60 days since registration/last transfer; domain unlocked; no contact-change lock; nameservers already on Cloudflare.
- Namecheap:
  1) Dashboard → Domain List → choose domain → turn off Registrar Lock.
  2) Get EPP/auth code: Domain → Sharing & Transfer → Transfer Out.
  3) Cloudflare: Registrar → Transfer → enter domain + auth code; approve emails if required.
- NameSilo:
  1) Domain Manager → unlock domain.
  2) Get auth code: Domain Manager → getAuthCode.
  3) Cloudflare: Registrar → Transfer → enter domain + auth code; approve emails if required.
- Cloudflare bills and adds one-year renewal; monitor status in Registrar.

### Automation Outline for Transfers
- APIs:
  - Namecheap: `namecheap.domains.transfer.getEPPCode`, `namecheap.domains.setRegistrarLock` (OFF).
  - NameSilo: `getAuthCode`, `domainLock` (disable).
  - Cloudflare: `POST /zones/:zone_identifier/registrar/domains/:name/transfer` with `{"auth_code":"..."}`.
    - Poll: `GET /zones/:zone_identifier/registrar/domains/:name/transfer`.
- Script ideas:
  - `get-auth-codes.sh`: input CSV (domain, registrar); outputs domain,auth_code.
  - `transfer-to-cloudflare.sh`: unlock (API), submit transfer to CF, poll status, log outcomes.
- Safeguards: verify 60-day window, confirm zone exists and nameservers point to Cloudflare, rate-limit calls, and handle registrant approval emails manually.

## Notes & Rationale

### HSTS
HSTS instructs browsers that the site should only be accessed over HTTPS. Reference: https://hstspreload.org.
- Pros: enforces HTTPS at the browser; prevents downgrade/mixed-mode requests after first load.
- Cons: can lock you out if HTTPS breaks; preload is a long-term commitment. At this time we do **NOT** configure HSTS.
- If choosing HSTS, validate first: confirm apex and www redirect to HTTPS, no mixed content, certs valid (Full strict), admin/login works over HTTPS.
- Rollout: start with a short max-age (e.g., 300) if testing; raise to 31536000 with includeSubDomains when confident. Preload only when certain that HTTPS is permanent.
- Cloudflare configuration: SSL/TLS → Edge Certificates → HTTP Strict Transport Security (HSTS), after Always Use HTTPS. [Cloudflare HSTS](https://developers.cloudflare.com/ssl/edge-certificates/additional-options/http-strict-transport-security/#configuration-settings).
- WordPress option: [HSTS plugin](https://wordpress.com/plugins/headers-security-advanced-hsts-wp).

### Redirect-only Configuration
Some zones exist only to redirect to a canonical domain (for example, short or legacy domains that should always land on the primary site). These zones should be configured to redirect at the Cloudflare edge, keep the canonical security policies on the primary domain, and avoid extra hops or browser-level stickiness that is unnecessary for aliases.

Recommended approach:
- Use a Redirect Rule at `Rules` → `Redirect Rules` that matches the alias host and issues a 301 to the canonical host, preserving path and query. This keeps redirects consistent for both HTTP and HTTPS and does not depend on origin behavior.
- Keep **Always Use HTTPS** off for redirect-only zones when a Redirect Rule is present. The rule handles HTTP→HTTPS directly and avoids an extra redirect hop on the alias host.
- Keep **HSTS** off for redirect-only zones. HSTS is a browser-level commitment and should be reserved for the canonical domain, not for disposable or temporary aliases.
- Prefer **Full (strict)** SSL mode when a valid origin cert is present so the edge remains secure even if a redirect rule is accidentally disabled. If no valid origin cert exists and the redirect rule is the only intended behavior, use **Full** instead of Flexible to avoid silent downgrade.

Operational notes:
- Ensure alias DNS records are proxied (orange cloud) so Redirect Rules apply at the edge.
- Security headers should be enforced on the canonical domain. On redirect-only zones, they are secondary to the redirect response and may be intentionally absent.


## Target Audience
For operators managing Cloudflare zones and edge security for this multisite network. Common scenarios: onboarding a new domain (proxy, origin cert, HTTPS enforcement), validating TLS after origin changes, and tuning headers without creating redirect loops. Expected skills: navigating Cloudflare DNS/SSL/RULES, reading certificate SANs.
Coordinating origin changes is covered inn ConfigServers.md, architecture in MULTI.md, terminology in DNSTerms.md.
