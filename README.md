# WordPress Multisite Tools
Date: January 12, 2026

## Introduction
This project implements a WordPress multisite network in subdirectory mode with apex domain mapping. Each client site uses its own domain while sharing WordPress core, themes, and plugins for operational efficiency. Cloudflare provides DNS, CDN, and edge security.
Included are shared VPS server and WordPress multisite installation instructions, tooling, and templates to host many domains via Cloudflare and Apache, with per-domain SSL. See the Documentation Map below for the consolidated runbook and strategic context. Cloudflare zones are created in the Cloudflare UI; the scripts assume the zone exists before DNS automation begins.

## Expected Audience
This documentation is written for several operator roles and is structured so each role can enter at the right layer without losing the dependency chain. System administrators responsible for Ubuntu, Apache, and Cloudflare should start with Operations.md and the verification scripts, while WordPress administrators focused on site mapping and content integrity should use Operations.md sections that cover multisite configuration and validation. Developers adapting or extending the scripts should begin with `scripts/Shell.md` and `scripts/Scripts.md`, then consult MULTI.md for architectural context.

This shared structure keeps operational dependencies clear: Cloudflare edge behavior must align before origin TLS and vhost wiring can be trusted, and WordPress routing depends on both layers being correct.

## Key Concepts

### Domain Model
- **Apex domain mapping**: Each client site uses their own domain (domain.com), not subdomains (sub.main.com)
- **Subdirectory multisite**: Internal WordPress structure uses subdirectories, mapped to apex domains via Apache vhosts
- **Per-domain SSL**: Individual Cloudflare Origin certificates per domain (no shared SAN certs)

### Infrastructure Layers
1. **Cloudflare Edge**: DNS, CDN, TLS termination, HTTPS redirects, security headers
2. **Origin TLS**: Cloudflare→Apache uses per-domain origin certificates, Full (strict) mode
3. **Apache**: One vhost per domain, all point to shared WordPress installation
4. **WordPress Multisite**: Shared core/plugins, per-site content/options

## Validated Environment
- **Server**: Ubuntu 24.04
- **Web**: Apache 2.4.58
- **PHP**: 8.3.11
- **Database**: MySQL 8.0.43
- **WordPress**: 6.9 multisite (subdirectory mode)

---

## Quick Start: Administrator

Scripts use commands: `curl`, `dig`, `jq`, `wp`, `apache2ctl`, `openssl`. Make sure these are installed and you can run them.

For the canonical, step-by-step onboarding and troubleshooting guidance, reference Operations.md; this is a condensed starter.

### Add Site to the Network

**Access** sudo on the origin Ubuntu host; Cloudflare account for the domains.
**Goal:** Domain registered, nameservers pointed to Cloudflare, zone created in Cloudflare, and SSL/TLS configured.

#### Configure Zone on Cloudflare (via UI)
- Add the domain to Cloudflare and confirm nameservers are delegated.
- SSL/TLS → Overview → Set "Full (strict)"
- SSL/TLS → Edge Certificates → "Always Use HTTPS" ON
- Rules → Transform Rules → Managed Transforms → "Add security headers"

#### Issue and install Cloudflare origin certificate
You can issue origin certificates via the Cloudflare UI or through the API, and in both cases the installation is handled by the same helper. The manual path uses the UI for issuance and then uses `get-cert.sh --manual` to install the certificate safely; the API path uses `get-cert.sh --api` and requires an Origin CA key (`CF_CA_KEY`).

UI issuance + manual install:
- SSL/TLS → Origin Server → Create Certificate
- `./scripts/get-cert.sh --manual domain.com`

API issuance + install:
- `./scripts/get-cert.sh --api domain.com`

#### Create Apache vhosts
`./scripts/apache-vhost.sh domain.com`

#### Add to WordPress multisite
`./scripts/install-site.sh domain.com "Site Title" email@domain.com`
  Assumes WordPress multisite is already installed; see Operations.md for the setup sequence.

#### Verify
`./scripts/verify-domain.sh domain.com`

### Query Multisite Setup

#### List sites in multisite network
`sudo -u www-data wp --path=<wp_root> site list`
Default example: `/var/www/html/wordpress` (Ubuntu default is `/var/www/html`, with `wordpress` as the chosen subdirectory).

#### Check Apache vhosts
`sudo ls /etc/apache2/sites-enabled/`

#### List installed certificates
`sudo ls /etc/ssl/cloudflare-origin/certs/`

#### Check DNS resolution
`dig +short domain.com`
`curl -I https://domain.com | grep -i cf-ray`

---

## Quick Start: Developer

### Documentation Map
The documents below describe different layers of the system and are intended to be read in this order so the operational dependencies remain clear.

- `README.md`: Entry point and quick start with the script index.
- `Operations.md`: Consolidated runbook for Cloudflare, origin, and WordPress operations in dependency order; use the relevant sections as needed.
- `scripts/Shell.md`: Conventions for writing scripts in this repository and using shared helpers.
- `scripts/Scripts.md`: Authoritative script interfaces, options, and environment variables.
- `Record.md`: Recording policy for updating `domains.csv` across provisioning and validation steps.
- `CloudflareMCP.md` (optional, experimental): MCP portal access and validation notes; not part of the production flow.
- `MULTI.md` (optional): Strategic architecture decisions, tradeoffs, and future work.
- `DNSTerms.md` (optional): DNS and Cloudflare terminology reference.

### Repository Structure

```
multiwp/
├── AGENTS.md                      # AI assistant guardrails and repo-specific instructions
├── README.md                      # This file
├── MULTI.md                       # Architecture & strategic decisions
├── Operations.md                  # Consolidated operational runbook
├── Record.md                      # Recording policy for domains.csv updates
├── DNSTerms.md                    # DNS & Cloudflare terminology
├── CloudflareMCP.md               # Cloudflare MCP notes and validation steps
├── scripts/
│   [list below]
├── templates/
│   ├── apache-http.conf           # Apache HTTP vhost template
│   ├── apache-ssl.conf            # Apache HTTPS vhost template
│   └── .htaccess                  # WordPress multisite rewrite rules
```

### Scripts

Program scripts (alphabetical):
| Script | Purpose | Status |
|--------|---------|--------|
| `apache-vhost.sh` | Create Apache HTTP + SSL vhosts for domain | Exercised |
| `check-cf.sh` | Inspect Cloudflare zone settings via API | Exercised |
| `check-edge.sh` | Validate Cloudflare edge behavior and headers | Exercised |
| `check-origin.sh` | Validate origin certs, vhosts, and Apache health | Exercised |
| `check-read.sh` | Run syntax/unit tests and read-only edge/DNS/origin/WP checks | Exercised |
| `check-wp.sh` | Validate multisite mappings and site URLs | Exercised |
| `cloud-dns.sh` | Create/update DNS records in an existing Cloudflare zone | Exercised |
| `cloud-redirect.sh` | Ensure Cloudflare Redirect Rules for redirect-only domains | Exercised |
| `get-cert.sh` | Issue or install Cloudflare Origin cert/key (API or manual) | Not exercised |
| `install-site.sh` | Add site to WordPress multisite, map to apex domain | Exercised |
| `mcp-cf.sh` | Validate Cloudflare MCP portal access | Exercised |
| `onboard-zone.sh` | Create or ensure Cloudflare zone + DNS and update domains.csv | Not exercised |
| `setup-wp.sh` | Bootstrap WordPress multisite base configuration | Not exercised |
| `test-record.sh` | Run validation checks and record status updates in domains.csv | Not exercised |
| `verify-cf-auth.sh` | Validate Cloudflare credentials (token/key) | Exercised |
| `verify-domain.sh` | End-to-end validation (edge, origin, WP) | Exercised |

Helper scripts:
| Script | Purpose | Status |
|--------|---------|--------|
| `common.sh` | Shared library functions (sourced by other scripts) | Library |
| `auth.sh` | Cloudflare auth helpers and API request utilities | Library |
| `cli.sh` | Shared option parsing helpers | Library |
| `mcp.sh` | MCP helper functions | Library |

Test scripts:
| Script | Purpose | Status |
|--------|---------|--------|
| `test_common.sh` | Unit tests for shared helpers | Test |
| `test_cf.sh` | Unit tests for Cloudflare helpers | Test |
| `test_cli.sh` | Unit tests for CLI helpers | Test |
| `test_mcp.sh` | Unit tests for MCP helpers | Test |

#### Test scripts syntax
`bash -n scripts/*.sh`

#### Permissions
- Run as user with sudo permissions and in ssl-cert group, not as root
`sudo usermod -aG ssl-cert {user} && sudo newgrp ssl-cert`

### Contributing

See the following references for implementation details:
- `scripts/Shell.md` for scripting conventions and shared helpers
- `AGENTS.md` for AI assistant guidelines specific to this repository

---

### Troubleshooting

**Site shows primary domain content:**
See Operations.md for the authoritative mapping checks and troubleshooting flow.

**Certificate errors:**
- Check cert path in Apache vhost config
- Check cert file permissions: `root:ssl-cert 640`
`sudo openssl x509 -in /etc/ssl/cloudflare-origin/certs/domaincom.crt -noout -subject -dates -ext subjectAltName`

**HTTP→HTTPS not working:**
- Check Cloudflare proxy (orange cloud) is enabled
- Verify Cloudflare "Always Use HTTPS" is ON
- Do NOT configure Apache-level HTTP→HTTPS redirect (may causes loops)

---

## External Documentation
- [WordPress Multisite Guide] https://developer.wordpress.org/advanced-administration/multisite/create-network
- [WP-CLI Handbook] https://make.wordpress.org/cli/handbook/
- [Cloudflare SSL Modes] https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/
- [Cloudflare Origin Certificates] https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/

---
