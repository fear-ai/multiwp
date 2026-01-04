# WordPress Multisite Tools

## Introduction
This project implements a WordPress multisite network in subdirectory mode with apex domain mapping. Each client site uses its own domain while sharing WordPress core, themes, and plugins for operational efficiency. Cloudflare provides DNS, CDN, and edge security.
Included are shared VPS server and WordPress multisite installation instructions, tooling, and templates to host many domains via Cloudflare and Apache, with per-domain SSL. Operators and developers will find strategy in MULTI.md, with authoritative runbooks CloudflareSettings.md for edge policy and ConfigServers.md for origin/server steps.

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
- **WordPress**: 6.8.3 multisite (subdirectory mode)

---

## Quick Start: Administrator

For the canonical, step-by-step onboarding workflow and troubleshooting guidance, reference the "Site Onboarding Workflow" section in ConfigServers.md; this is a condensed starter.

### Add Site to the Network

**Access** sudo on the origin Ubuntu host; Cloudflare account for the domains.
**Completed:** Domain registered, DNS pointed to Cloudflare, Cloudflare zone created.

#### Configure Zone on Cloudflare (via UI)
- SSL/TLS → Overview → Set "Full (strict)"
- SSL/TLS → Edge Certificates → "Always Use HTTPS" ON
- Rules → Transform Rules → Managed Transforms → "Add security headers"

#### Issue Cloudflare origin certificate
- SSL/TLS → Origin Server → Create Certificate
  [Download of Copy cert and key]

#### Install certificate on origin server
`sudo ./scripts/install-cert.sh domain.com`
  [Paste cert and key when prompted]

#### Create Apache vhosts
`sudo ./scripts/apache-vhost.sh domain.com`

#### Add to WordPress multisite
`./scripts/install-site.sh domain.com "Site Title" email@domain.com

#### Verify
`curl -I https://domain.com`

### Query Multisite Setup

#### List sites in multisite network
`sudo -u www-data wp --path={HTTP_PATH} site list`

#### Check Apache vhosts
`ls /etc/apache2/sites-enabled/`

#### List installed certificates
ls /etc/ssl/cloudflare-origin/certs/`

#### Check DNS resolution
`dig +short domain.com`
  [Look for `cf-ray` header]

#### Test URL
`curl -I https://domain.com`

---

## Quick Start: Developer

### Repository Structure

```
multiwp/
├── AGENTS.md                      # AI assistant guidelines
├── README.md                      # This file
├── MULTI.md                       # Architecture & strategic decisions
├── CloudflareSettings.md          # Cloudflare operational guide
├── ConfigServers.md               # Server/Apache/WordPress operations
├── DNSTerms.md                    # DNS & Cloudflare terminology
├── scripts/
│   [list below]
├── templates/
│   ├── apache-http.conf           # Apache HTTP vhost template
│   ├── apache-ssl.conf            # Apache HTTPS vhost template
│   ├── wp-config-multisite.php    # WordPress config template
│   └── .htaccess                  # WordPress multisite rewrite rules
```

### Scripts

| Script | Purpose | Status |
|--------|---------|--------|
| `apache-vhost.sh` | Create Apache HTTP + SSL vhosts for domain | Exercised |
| `install-site.sh` | Add site to WordPress multisite, map to apex domain | Exercised |
| `install-cert.sh` | Validate or install Cloudflare Origin cert/key | Exercised |
| `cloud-dns.sh` | Create Cloudflare zone + DNS records via API | Not exercised |
| `get-cert.sh` | Issue or install Cloudflare Origin cert/key (API or manual) | Not exercised |
| `common.sh` | Shared library functions (sourced by other scripts) | Library |
| `check-edge.sh` | Validate Cloudflare edge behavior and headers | Exercised |
| `check-origin.sh` | Validate origin certs, vhosts, and Apache health | Exercised |
| `check-wp.sh` | Validate multisite mappings and site URLs | Exercised |
| `verify-domain.sh` | End-to-end validation (edge, origin, WP) | Exercised |
| `verify-cf-auth.sh` | Validate Cloudflare credentials (token/key) | Exercised |

#### Test scripts syntax
`bash -n scripts/*.sh`

#### Permissions
- Run as user with sudo permissions and in ssl-cert group, not as root
`sudo usermod -aG ssl-cert {user} && sudo newgrp ssl-cert

#### Verify commands
WP-CLI, JSON processor, HTTP client
`command -v wp`
`command -v jq`
`command -v curl`

### Contributing

See [AGENTS.md](AGENTS.md) for:
- Coding conventions
- Commit message format
- Documentation guidelines

---

### Troubleshooting

**Site shows primary domain content:**
- Verify domain mapping in wp_blogs table
- Check siteurl/home in wp_<blog_id>_options table
- Verify Apache vhost ServerName matches domain

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
- [WordPress Multisite Guide](https://developer.wordpress.org/advanced-administration/multisite/create-network)
- [WP-CLI Handbook](https://make.wordpress.org/cli/handbook/)
- [Cloudflare SSL Modes](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/)
- [Cloudflare Origin Certificates](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/)

---

## Target Audience
This document is for system administrators and for developers. Likely system configuration scenarios include onboarding a new client domain, validating TLS/vhost health after changes, adapting scripts to the local environment.
Recommended skills: Bash scripting, WP-CLI, Apache vhost, Cloudflare dashboard (SSL/TLS, DNS).

Date: December 5, 2025
