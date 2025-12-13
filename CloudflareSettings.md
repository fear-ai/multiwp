# Cloudflare Settings & Certs For Multi WordPress

## Introduction
Cloudflare edge configuration for the multisite network, covering the preferred UI-driven workflow and optional automation helpers. Pair with ConfigServers.md for origin/vhost steps.

## Table of Contents
1. [Introduction](#introduction)
2. [Overview](#overview)
3. [Proxy Model (Cloudflare Edge)](#proxy-model-cloudflare-edge)
4. [UI Flow: HTTPS & Certs](#ui-flow-https--certs)
   4.1. [DNS & Proxy](#21-dns--proxy)
   4.2. [Issue Origin Certificate](#22-issue-origin-certificate)
   4.3. [Enforce Full (Strict)](#23-enforce-full-strict)
   4.4. [Force HTTPS (Edge Certificates vs Redirect Rules)](#24-force-https-edge-certificates-vs-redirect-rules)
   4.5. [Add Security Headers](#25-add-security-headers)
5. [Automation Aids](#automation-aids)
   5.1. [Create Zone + DNS](#31-create-zone--dns)
   5.2. [Origin Cert Placement](#32-origin-cert-placement)
   5.3. [Vhost Generation](#33-vhost-generation)
6. [Hybrid Execution (UI + Automation)](#hybrid-execution-ui--automation)
7. [Domain Registration & Transfer to Cloudflare](#domain-registration--transfer-to-cloudflare)
   7.1. [Manual Transfer Steps (Namecheap, NameSilo)](#51-manual-transfer-steps-namecheap-namesilo)
   7.2. [Automation Outline for Transfers](#52-automation-outline-for-transfers)
8. [Notes & Rationale](#notes--rationale)
   - [HSTS](#hsts)
9. [Target Audience](#target-audience)

## Overview
Configure Cloudflare so client traffic is encrypted end-to-end (Full strict), HTTP is redirected to HTTPS at the edge, and security headers are applied consistently. Origin servers use per-domain Cloudflare Origin certificates; Cloudflare presents edge certificates to visitors. Use the UI for clarity; layer scripts where it saves time. For terminology, see `DNSTerms.md`.

## Proxy Model (Cloudflare Edge)
- Cloudflare’s orange cloud behaves as a reverse proxy: clients connect to Cloudflare; Cloudflare connects to our origin. References: [Cloudflare reverse proxy overview](https://www.cloudflare.com/learning/cdn/glossary/reverse-proxy/), [MDN reverse proxy](https://developer.mozilla.org/en-US/docs/Glossary/Reverse_proxy).
- Benefits: hides origin addresses, offloads TLS, enables caching and WAF features.
- Our usage: proxy apex and `www`, issue origin certs per apex+www pair, and let Cloudflare enforce HTTPS and headers at the edge.

## UI Flow: HTTPS & Certs

### 2.1. DNS & Proxy
- Path: `DNS`.
- Add A for apex (`@`) pointing to the origin; enable proxy (orange cloud).
- Add CNAME for `www` pointing to apex when proxying; this keeps a single source of truth for the origin address.
- Optional: wildcard `*` CNAME to apex to catch stray hosts, but keep explicit apex/www records when proxying.
- If origin IP changes, update DNS before enforcing strict TLS to avoid downtime.
- Assumes nameservers already point to Cloudflare; DNSSEC is not required for this flow.

### Enforce Full (Strict) SSL Encryption
- Path: `SSL/TLS` → `Overview`.
- Setting: “SSL/TLS encryption mode” → select `Full (strict)`.

### Issue Origin Certificate
Use separate origin cert per domain (apex+www pair) to avoid exposing tenant lists and to keep trust scoped. The certs are used between Cloudflare and origin, not publicly trusted.
- Path: `SSL/TLS` → `Origin Server` → `Create Certificate`.
- Options: “Let Cloudflare generate a private key and CSR”; Hostnames: apex + www; Key type: RSA; Validity: default.
- Download cert/key in PEM format; install on origin at `/etc/ssl/cloudflare-origin/certs|keys/<safe>.{crt,key}` (safe = domain without dots/hyphens).

### Use HTTPS and TLS 1.2
- Path: `SSL/TLS` → `Edge Certificates`.
- Minimum TLS: TLS 1.2 (from 1.0 default).
- “Always Use HTTPS” ON.

### Security Headers
- Path: `Rules` → `Settings` → `Managed Transforms` → `HTTP Response Headers` → “Add security headers.” [Cloudflare add security headers](https://developers.cloudflare.com/rules/transform/managed-transforms/reference/#add-security-headers).
- Configures:
  - `Strict-Transport-Security: max-age=31536000; includeSubDomains`
  - `X-Content-Type-Options: nosniff`
  - `X-XSS-Protection: 1; mode=block`
  - `X-Frame-Options: SAMEORIGIN`
  - `Referrer-Policy: same-origin`
  - `Expect-CT: max-age=86400, enforce`

## Automation
Cloudflare UI is authoritative for SSL mode, redirects, and headers. Automation scripts can help with DNS, origin cert placement, and vhost generation.

### Create Zone + DNS
- Script: `scripts/cloud-dns.sh <domain> <ipv4> [ipv6]`
- Fit: use when onboarding a new domain; interacts with the Cloudflare API instead of the UI.
- Does: creates the zone (full setup) and adds proxied A/AAAA for apex+www. Env or flags: `CF_API_TOKEN`, `CF_ACCOUNT_ID`, `--token`, `--account`.

### Origin Cert Placement
- Script: `scripts/install-cert.sh <domain>`
- Does: validate/install Cloudflare Origin cert/key into `/etc/ssl/cloudflare-origin/{certs,keys}/<safe>.{crt,key}` with perms root:ssl-cert 640; prints SANs.
- Paths: defaults align with the origin cert locations defined in `ConfigServers.md`; update that runbook first if you need non-default storage and keep templates/scripts in sync.

### Vhost Generation
- Script: `scripts/apache-vhost.sh <domain>`
- Uses templates pointing at origin cert paths; enables HTTP/SSL vhosts. Add origin certs first, then run; script runs `apache2ctl configtest`.

## Hybrid Execution (UI + Automation)
- Sequence (per domain):
  1) UI/API: Create/verify zone and DNS (apex + www), proxy on.
  2) UI: Issue origin cert, download cert/key.
  3) Automation: Run `install-cert.sh` to place cert/key on origin with correct perms.
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
  - Cloudflare: `POST /zones/:zone_identifier/registrar/domains/:name/transfer` with `{"auth_code":"..."}`
  - Poll: `GET /zones/:zone_identifier/registrar/domains/:name/transfer`
- Script ideas:
  - `get-auth-codes.sh`: input CSV (domain, registrar); outputs domain,auth_code.
  - `transfer-to-cloudflare.sh`: unlock (API), submit transfer to CF, poll status, log outcomes.
- Safeguards: verify 60-day window, confirm zone exists and nameservers point to Cloudflare, rate-limit calls, and handle registrant approval emails manually.

## Notes & Rationale
- Edge HTTPS and headers belong at Cloudflare; do not add [redundant] Apache redirects to prevent loops and extra hops.
- IPv6 is optional; if you later add AAAA records, proxy them and keep apex/www explicit.

###  Force HTTPS via Edge Certificates vs Redirect Rules
“Always Use HTTPS” ON is simple and avoids custom rule errors.
- Redirect Rules on Cloudflare give more control but at a higher risk: `Rules` → `Redirect Rules`; Condition `Hostname equals apex OR www`; Action: 301 to `https://{host}{uri}`. Turn “Always Use HTTPS” OFF if using Rules.
 **Warning:** misconfigured Rules or overlapping redirects can create loops; only use when needed and with a solid test plan.

### HSTS
- HSTS pros: enforces HTTPS at the browser; prevents downgrade/mixed-mode requests after first load.
- HSTS cons: can lock you out if HTTPS breaks; preload is a long-term commitment.
- Validate first: confirm apex and www redirect to HTTPS, no mixed content, certs valid (Full strict), admin/login works over HTTPS.
- Rollout: start with short max-age (e.g., 300) if testing; then raise to 31536000 with includeSubDomains when confident. Preload only when you are sure HTTPS is permanent.

## Target Audience
For operators managing Cloudflare zones and edge security for this multisite network. Common scenarios: onboarding a new domain (proxy, origin cert, HTTPS enforcement), validating TLS after origin changes, and tuning headers without creating redirect loops. Expected skills: navigating Cloudflare DNS/SSL/RULES, reading certificate SANs, and coordinating with origin changes in ConfigServers.md. Additional resources: ConfigServers.md (origin), MULTI.md (architecture), DNSTerms.md (terminology).
