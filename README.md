# WordPress Multisite Tools

WordPress multisite tooling and templates to host many client domains on shared infrastructure with per-domain SSL via Cloudflare and Apache.

## What’s Included
- Docs: `MULTI.md` (strategy/architecture), `ConfigServers.md` (origin/server runbook), `CloudflareSettings.md` (edge/Cloudflare setup).
- Scripts: `setup-wp.sh` (multisite bootstrap), `apache-vhost.sh` (per-domain vhosts), `install-cert.sh` (place Cloudflare origin certs), `cloud-dns.sh` (create zone + DNS via Cloudflare API; no UI).
- Templates: `apache-*.conf`, `wp-config-multisite*.php`, `.htaccess`.
- Glossary: `DNSTerms.md` (DNS/Cloudflare terminology).

## Prerequisites
- Apache 2.4 with `rewrite`, `ssl`, `headers`.
- PHP 8.x, MySQL 8.x.
- WP-CLI installed.
- Cloudflare account/token if using automation.

## Quick Start (placeholders)
```bash
# Bootstrap multisite on a fresh host
bash scripts/setup-wp.sh

# Add a domain vhost (expects certs at /etc/ssl/cloudflare-origin/{certs,keys}/<safe>.{crt,key})
bash scripts/apache-vhost.sh example.com

# Install/validate a Cloudflare origin cert on the server
bash scripts/install-cert.sh example.com

# Create zone and DNS (apex + www) via Cloudflare API
CF_API_TOKEN=... CF_ACCOUNT_ID=... bash scripts/cloud-dns.sh example.com 203.0.113.10
```

## Usage Notes
- Vhosts are per-domain; templates assume Cloudflare origin cert paths. Use `apache-vhost.sh` after certs are in place.
- Cloudflare configuration (Full strict, HTTPS redirects, headers) is documented in `CloudflareSettings.md`; keep HTTPS redirects at the edge to avoid loops.
- Multisite model: subdirectory network with mapped apex domains to keep one core install while preserving client-brand URLs.
