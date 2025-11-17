# Cloudflare Settings & Certs (UI and Automation)

## Table of Contents
1. [Overview](#overview)
2. [UI Flow: HTTPS & Certs](#ui-flow-https--certs)
   2.1. [DNS & Proxy](#21-dns--proxy)
   2.2. [Issue Origin Certificate](#22-issue-origin-certificate)
   2.3. [Enforce Full (Strict)](#23-enforce-full-strict)
   2.4. [Force HTTPS](#24-force-https)
   2.5. [Add Security Headers](#25-add-security-headers)
3. [Automation Aids](#automation-aids)
   3.1. [Create Zone + DNS](#31-create-zone--dns)
   3.2. [Origin Cert Placement](#32-origin-cert-placement)
   3.3. [Vhost Generation](#33-vhost-generation)
4. [Hybrid Execution (UI + Automation)](#hybrid-execution-ui--automation)
5. [Domain Registration & Transfer to Cloudflare](#domain-registration--transfer-to-cloudflare)
   5.1. [Manual Transfer Steps (Namecheap, NameSilo)](#51-manual-transfer-steps-namecheap-namesilo)
   5.2. [Automation Outline for Transfers](#52-automation-outline-for-transfers)
6. [Notes & Rationale](#notes--rationale)

## Overview
Configure Cloudflare so client traffic is encrypted end-to-end (Full strict), HTTP is redirected to HTTPS at the edge, and security headers are applied consistently. Origin servers use per-domain Cloudflare Origin certificates; Cloudflare presents edge certificates to visitors. Use the UI for clarity; layer scripts where it saves time.

## UI Flow: HTTPS & Certs

### 2.1. DNS & Proxy
- Path: `DNS`.
- Add A/AAAA for apex and www pointing to the origin; enable proxy (orange cloud).
- If origin IP changes, update DNS before enforcing strict TLS to avoid downtime.

### 2.2. Issue Origin Certificate
- Path: Zone → `SSL/TLS` → `Origin Server` → `Create Certificate`.
- Options: “Let Cloudflare generate a private key and CSR”; Hostnames: apex + www; Key type: RSA; Validity: default.
- Download cert/key; install on origin at `/etc/ssl/cloudflare-origin/certs|keys/<safe>.{crt,key}` (safe = domain minus dots/hyphens). These certs are used only between Cloudflare and origin (not publicly trusted).
- Use separate origin certs per domain (or per apex+www pair) to avoid exposing tenant lists and to keep trust scoped.

### 2.3. Enforce Full (Strict)
- Path: `SSL/TLS` → `Overview`.
- Set “SSL/TLS encryption mode” to `Full (strict)` so Cloudflare validates your origin cert on proxied requests.

### 2.4. Force HTTPS
- Path: `Rules` → `Redirect Rules` (preferred).
- Create rule: Condition `Hostname equals apex OR www`; Action: 301 to `https://{host}{uri}`.
- This keeps HTTP→HTTPS at the edge. Redundant Apache redirects can cause loops when proxied or add extra hops; prefer a single redirect at Cloudflare.

### 2.5. Add Security Headers
- Path: `Rules` → `Transform Rules` → `HTTP Response Header Modification`.
- Condition: `Hostname equals apex OR www`.
- Add headers:
  - `Strict-Transport-Security: max-age=31536000; includeSubDomains`
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: DENY`
  - `Referrer-Policy: no-referrer-when-downgrade`

## Automation Aids

### 4.1. Create Zone + DNS
- Script: `scripts/add-zone-and-dns.sh <domain> <ipv4> [ipv6]`
- Does: creates zone (full), adds proxied A/AAAA for apex+www. Env: `CF_API_TOKEN`, `CF_ACCOUNT_ID`.

### 4.2. Origin Cert Placement
- Script: `scripts/ensure-origin-cert.sh <domain>`
- Does: validate/install Cloudflare Origin cert/key into `/etc/ssl/cloudflare-origin/{certs,keys}/<safe>.{crt,key}` with perms root:ssl-cert 640; prints SANs.

### 4.3. Vhost Generation
- Script: `scripts/add-domains.sh <domain>`
- Uses templates pointing at origin cert paths; enables HTTP/SSL vhosts. Add origin certs first, then run; script runs `apache2ctl configtest`.

## Hybrid Execution (UI + Automation)
- Sequence (per domain):
  1) UI/API: Create/verify zone and DNS (apex + www), proxy on.
  2) UI: Issue origin cert, download cert/key.
  3) Automation: Run `ensure-origin-cert.sh` to place cert/key on origin with correct perms.
  4) Automation: Run `add-domains.sh` to generate/enable vhosts referencing the origin certs; script runs configtest.
  5) UI: Set SSL mode to Full (strict); add Redirect Rule for HTTPS; add Transform Rule for headers.
  6) Verify: Browse HTTP→HTTPS redirect, check headers, confirm Full (strict) active.
- Dependencies:
  - Cert placement must precede enabling SSL vhosts and setting Full (strict), or strict mode will fail.
  - DNS/proxy must be set before forcing HTTPS to avoid downtime.
  - Avoid Apache-level HTTPS redirects when Cloudflare proxy is on; use edge redirects to prevent loops.
- Interaction model:
  - UI controls edge behavior (strict TLS, redirects, headers).
  - Scripts configure origin (cert files, vhosts). Treat UI settings as source of truth for TLS mode and redirects; scripts should not duplicate them.

## Domain Registration & Transfer to Cloudflare

### 5.1. Manual Transfer Steps (Namecheap, NameSilo)
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

### 5.2. Automation Outline for Transfers
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
- Edge HTTPS and headers belong at Cloudflare when proxied; avoid redundant Apache redirects to prevent loops and extra hops.
- Separate origin certs per domain (or per apex+www pair) keep tenant lists private and scope trust; avoid multi-tenant SANs.
- UI is authoritative for SSL mode, redirects, and headers; scripts help with DNS, origin cert placement, and vhost generation. Use both to reduce errors and speed onboarding.
