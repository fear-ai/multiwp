# Cloudflare Workflow for Multisite Domains

Cloudflare-only steps to put each mapped domain (apex + www) on HTTPS with origin encryption, redirects, and security headers. Repeat per domain.

1) Issue an Origin Certificate (covers apex + www)
- Path: Zone → `SSL/TLS` → `Origin Server` → `Create Certificate`.
- Options: “Let Cloudflare generate a private key and CSR”; Hostnames: add apex and www (e.g., `example.com`, `www.example.com`); Key type: RSA; Validity: default.
- Download the Origin Certificate and Private Key (keep secure). Install on origin at `/etc/ssl/cloudflare-origin/certs|keys/<safe>.{crt,key}` (safe = domain with dots/hyphens removed); point your SSL vhost to these files. Origin certs are only used between Cloudflare and your server; they are not publicly trusted.

2) Enforce origin verification
- Path: `SSL/TLS` → `Overview`.
- Set “SSL/TLS encryption mode” to `Full (strict)` so Cloudflare validates the origin cert when proxying.

3) Force HTTPS
- Path: `Rules` → `Redirect Rules` (preferred) or `Page Rules`.
- Create rule: Condition `Hostname equals apex OR www`; Action: `301` redirect to `https://{host}{uri}`.
- This keeps HTTP→HTTPS at the edge, avoiding extra origin hops.

4) Add security headers at the edge
- Path: `Rules` → `Transform Rules` → `HTTP Response Header Modification`.
- Condition: `Hostname equals apex OR www`.
- Add headers:
  - `Strict-Transport-Security: max-age=31536000; includeSubDomains`
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: DENY`
  - `Referrer-Policy: no-referrer-when-downgrade`

5) DNS and proxy status
- Path: `DNS`.
- Ensure A/AAAA records for apex and www point to the origin IP and are proxied (orange cloud).
- If you update origin IPs, refresh these records before switching to Full (strict) to avoid downtime.

6) WordPress multisite alignment (edge-only steps here; origin changes elsewhere)
- After DNS/proxy and cert are in place, update per-site URLs in WordPress to `https://apex` (or `https://www` if canonical).
- Keep `wp_blogs.domain` at the apex with `path` `/` for mapped domains; use one pair per site.

7) Origin file layout (for reference; create on the origin host)
- Certs: `/etc/ssl/cloudflare-origin/certs/<safe>.crt`
- Keys: `/etc/ssl/cloudflare-origin/keys/<safe>.key`
- Permissions: root:ssl-cert, mode 640 (usable by Apache).

7) Validate
- Browse `http://` → confirm edge redirect to `https://`.
- Check response headers for HSTS and other security headers.
- Confirm Cloudflare “SSL/TLS” shows Full (strict) and edge certificates active; ensure “Always Use HTTPS” is redundant if using redirect rules.

Notes
- Perform all HTTPS redirects and headers at Cloudflare when proxied; avoid duplicate Apache rules to reduce loop risk.
- Use separate origin certs per domain (or multi-host entries) rather than sharing SANs across tenants if privacy is a concern.
