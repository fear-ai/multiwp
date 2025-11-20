# WordPress Multisite Tools

WordPress multisite tooling and templates to host many client domains on shared infrastructure with per-domain SSL via Cloudflare and Apache.

## Overview
- Architecture: `MULTI.md`
- Origin runbook: `ConfigServers.md`
- Edge/Cloudflare: `CloudflareSettings.md`
- Apex/site mapping fixes: `ApexFixes.md`
- DNS terminology: `DNSTerms.md`

## Key Scripts (run from repo root)
```bash
# Bootstrap/convert a host (legacy; planned for rewrite)
bash scripts/setup-wp.sh

# Generate Apache vhosts (HTTP + SSL) for a domain
sudo scripts/apache-vhost.sh example.com

# Install or validate a Cloudflare origin cert/key
scripts/install-cert.sh example.com

# Create Cloudflare zone + DNS via API (no UI)
CF_API_TOKEN=... CF_ACCOUNT_ID=... scripts/cloud-dns.sh example.com 203.0.113.10

# Issue a new Cloudflare origin cert/key via API
CF_API_TOKEN=... scripts/cloud-cert.sh example.com
```

## Notes
- Templates `apache-*.conf` use `{{DOCROOT}}`; `apache-vhost.sh` substitutes based on `--root`.
- `install-cert.sh` installs pre-obtained certs (e.g., from the Cloudflare UI). `cloud-cert.sh` calls the Cloudflare Origin CA API to request a new cert/key pair.
- Cloudflare HTTPS/headers/HSTS configuration lives in `CloudflareSettings.md`.
- Cert and vhost paths follow the defaults documented in `ConfigServers.md`; adjust that runbook first if you need non-standard locations so templates and scripts stay aligned.
- Future work: rewrite `setup-wp.sh` using WP-CLI with thorough testing.
