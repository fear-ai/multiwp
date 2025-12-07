# WordPress Multisite Tools

WordPress multisite tooling and templates to host many client domains on shared infrastructure with per-domain SSL via Cloudflare and Apache.

## Overview

This project implements a WordPress multisite network in subdirectory mode with apex domain mapping. Each client site uses its own domain (e.g., example.com) while sharing WordPress core, themes, and plugins for operational efficiency. Cloudflare provides DNS, CDN, and edge security.

**For strategic decisions and architecture rationale:** See [MULTI.md](MULTI.md)

---

## Current Environment

**Validated Configuration** (as of December 2, 2025):
- **Server**: Ubuntu 24.04 on Vultr (laz24)
- **Web**: Apache 2.4.58
- **PHP**: 8.3.11
- **Database**: MySQL 8.0.43
- **WordPress**: 6.8.3 multisite (subdirectory mode)
- **Primary Domain**: alphaeos.net
- **Live Production Sites**: avtranscript.com, recomp.one
- **Testing Domain**: talkdao.org

---

## Quick Start: Administrator

### Adding a New Site to the Network

**Prerequisites:** Domain registered, DNS pointed to Cloudflare, Cloudflare zone configured.

```bash
# 1. Issue Cloudflare Origin certificate (via Cloudflare UI)
#    SSL/TLS → Origin Server → Create Certificate
#    Download cert and key

# 2. Install certificate on origin
sudo ./scripts/install-cert.sh example.com
# Paste cert and key when prompted

# 3. Create Apache vhosts
sudo ./scripts/apache-vhost.sh example.com

# 4. Add site to WordPress multisite
./scripts/install-site.sh example.com "Site Title" admin@example.com

# 5. Configure Cloudflare (via UI)
#    - SSL/TLS → Overview → Set "Full (strict)"
#    - SSL/TLS → Edge Certificates → "Always Use HTTPS" ON
#    - Rules → Transform Rules → Managed Transforms → "Add security headers"

# 6. Verify
curl -I https://example.com
```

**Detailed guides:**
- Cloudflare configuration: [CloudflareSettings.md](CloudflareSettings.md)
- Server/Apache/WordPress: [ConfigServers.md](ConfigServers.md)
- DNS terminology: [DNSTerms.md](DNSTerms.md)

### Querying Current State

```bash
# List all sites in multisite network
sudo -u www-data wp --path=/var/www/html/wordpress site list

# Check Apache vhosts
ls /etc/apache2/sites-enabled/

# List installed certificates
ls /etc/ssl/cloudflare-origin/certs/

# Check DNS resolution
dig +short example.com
```

---

## Quick Start: Developer

### Repository Structure

```
multiwp/
├── docs/
│   └── INSTALL_SITE_NOTES.md      # Detailed WordPress site installation notes
├── scripts/
│   ├── apache-vhost.sh            # Create Apache vhosts from templates
│   ├── install-site.sh            # Add site to WordPress multisite
│   ├── install-cert.sh            # Install Cloudflare Origin certificates
│   ├── cloud-dns.sh               # Cloudflare DNS via API (not yet exercised)
│   ├── cloud-cert.sh              # Cloudflare certs via API (not yet exercised)
│   ├── common.sh                  # Shared library functions
│   └── archive/
│       └── setup-wp.sh            # Obsolete initial setup script
├── templates/
│   ├── apache-http.conf           # Apache HTTP vhost template
│   ├── apache-ssl.conf            # Apache HTTPS vhost template
│   ├── wp-config-multisite.php    # WordPress config template
│   └── .htaccess                  # WordPress multisite rewrite rules
├── MULTI.md                       # Architecture & strategic decisions
├── README.md                      # This file
├── CloudflareSettings.md          # Cloudflare operational guide
├── ConfigServers.md               # Server/Apache/WordPress operations
├── DNSTerms.md                    # DNS & Cloudflare terminology
├── AGENTS.md                      # AI assistant guidelines
└── CONF.md                        # Current system snapshot (outdated quickly)
```

### Scripts Reference

| Script | Purpose | Status |
|--------|---------|--------|
| `apache-vhost.sh` | Create Apache HTTP + SSL vhosts for domain | ✅ Exercised |
| `install-site.sh` | Add site to WordPress multisite, map to apex domain | ✅ Exercised |
| `install-cert.sh` | Validate or install Cloudflare Origin cert/key | ✅ Exercised |
| `cloud-dns.sh` | Create Cloudflare zone + DNS records via API | ⚠️ Not exercised |
| `cloud-cert.sh` | Issue Cloudflare Origin cert via API | ⚠️ Not exercised |
| `common.sh` | Shared library functions (sourced by other scripts) | Library |

**All scripts located in:** `scripts/`

**Script conventions:**
- Run as `ubuntu` user with sudo (not as root)
- Use `--help` flag for usage information
- Source `common.sh` for shared functions
- See [AGENTS.md](AGENTS.md) for coding style

### Development Environment Setup

```bash
# 1. Ensure user in ssl-cert group
sudo usermod -aG ssl-cert ubuntu
# Log out and back in, or: newgrp ssl-cert

# 2. Verify dependencies
command -v wp        # WP-CLI
command -v jq        # JSON processor (for API scripts)
command -v curl      # HTTP client

# 3. Test scripts syntax
bash -n scripts/*.sh

# 4. Review documentation
cat MULTI.md         # Understand architecture decisions
cat CloudflareSettings.md  # Cloudflare procedures
cat ConfigServers.md       # Server operations
```

### Testing Workflow

**Test domains designated for API automation testing:**
- `realdao.org` - Test HTTPS and cert generation via API
- `talkdao.net` - Test HTTPS and cert generation via API
- `recomp.top` - Test DNS configuration then cert via API

**Testing checklist:**
1. Verify prerequisites (DNS, Cloudflare zone, apache vhost)
2. Run script with test domain
3. Verify success in WordPress: `wp site list`
4. Test HTTPS: `curl -I https://testdomain.com`
5. Check Cloudflare proxy: Look for `cf-ray` header
6. Document any errors or warnings

### Contributing

See [AGENTS.md](AGENTS.md) for:
- Coding conventions (Bash style, naming)
- Commit message format
- Documentation guidelines
- How to work with this repository

---

## Documentation Guide

### For Operators

**Daily operations:**
- [CloudflareSettings.md](CloudflareSettings.md) - Cloudflare UI workflows, SSL configuration
- [ConfigServers.md](ConfigServers.md) - Server/Apache/WordPress procedures
- [docs/INSTALL_SITE_NOTES.md](docs/INSTALL_SITE_NOTES.md) - Detailed site installation notes

**Quick reference:**
- [DNSTerms.md](DNSTerms.md) - DNS and Cloudflare terminology lookup

### For Planning & Architecture

**Understanding the system:**
- [MULTI.md](MULTI.md) - Complete strategic overview including:
  - Architecture decisions and rationale
  - Tradeoffs and implications
  - Implementation lessons learned
  - Abandoned approaches
  - Future investigation areas

### For Developers

**Code and scripts:**
- This README - Script reference and quick start
- [AGENTS.md](AGENTS.md) - Coding conventions and repository guidelines
- [docs/INSTALL_SITE_NOTES.md](docs/INSTALL_SITE_NOTES.md) - WP-CLI command details

---

## Key Concepts

### Domain Model
- **Apex domain mapping**: Each client site uses their own domain (example.com), not subdomains
- **Subdirectory multisite**: Internal WordPress structure uses subdirectories, mapped to apex domains via Apache vhosts
- **Per-domain SSL**: Individual Cloudflare Origin certificates per domain (no shared SAN certs)

### Infrastructure Layers
1. **Cloudflare Edge**: DNS, CDN, TLS termination, HTTPS redirects, security headers
2. **Origin TLS**: Cloudflare→Apache uses per-domain origin certificates, Full (strict) mode
3. **Apache**: One vhost per domain, all point to shared WordPress installation
4. **WordPress Multisite**: Shared core/plugins, per-site content/options

### Onboarding Order
1. Register/configure domain at Cloudflare (DNS, proxy, origin cert)
2. Install cert and create vhosts on origin server
3. Add site to WordPress multisite (creates with subdirectory slug)
4. Map domain in wp_blogs and update site URLs
5. Configure Cloudflare SSL mode and security settings
6. Verify HTTPS access

---

## Common Tasks

### Check Site Status
```bash
# WordPress multisite sites
sudo -u www-data wp --path=/var/www/html/wordpress site list

# Test HTTPS response
curl -I https://example.com

# Check certificate details
sudo openssl x509 -in /etc/ssl/cloudflare-origin/certs/examplecom.crt \
  -noout -subject -dates -ext subjectAltName
```

### Troubleshooting

**Site shows primary domain content:**
- Verify domain mapping in wp_blogs table
- Check siteurl/home in wp_<blog_id>_options table
- Verify Apache vhost ServerName matches domain
- Clear WordPress cache if applicable

**Certificate errors:**
- Verify Cloudflare SSL mode is "Full (strict)"
- Check cert paths in Apache vhost config
- Verify cert SAN includes both apex and www
- Check cert file permissions: `root:ssl-cert 640`

**HTTP→HTTPS not working:**
- Verify Cloudflare "Always Use HTTPS" is ON
- Do NOT configure Apache-level HTTP→HTTPS redirect (causes loops)
- Check Cloudflare proxy (orange cloud) is enabled

**Permission errors in scripts:**
- Verify user in ssl-cert group: `groups ubuntu`
- If not: `sudo usermod -aG ssl-cert ubuntu` then log out/in
- Scripts should run as ubuntu with sudo, not as root

---

## Support & References

### External Documentation
- [WordPress Multisite Guide](https://developer.wordpress.org/advanced-administration/multisite/create-network)
- [WP-CLI Handbook](https://make.wordpress.org/cli/handbook/)
- [Cloudflare SSL Modes](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/)
- [Cloudflare Origin Certificates](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/)

### Internal Documentation
All files in this repository contain detailed procedures, decisions, and lessons learned. Start with MULTI.md for strategic context, then consult operational guides (CloudflareSettings.md, ConfigServers.md) for procedures.
