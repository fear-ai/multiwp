# WordPress Multisite Hosting Project

*Strategic overview documenting project vision, requirements, and architecture decisions. For current technical state see CONF.md.*

## Project Vision
Operate a WordPress multisite network that can host ~100 independent client domains on shared infrastructure while keeping each site private from the others.

## Network & Domain Model
- Each client uses a unique apex domain (no shared subdomains).
- Domain isolation via dedicated Apache virtual hosts per domain; no wildcard hosts.
- SSL per domain to avoid cross-tenant signals; Cloudflare used for DNS/CDN.

## Platform Stack
- WordPress multisite (subdirectory structure) on Apache, PHP, and MySQL.
- CDN/proxy at Cloudflare to handle DNS, TLS termination, and caching.
- Centralized WordPress admin with per-site admin access.

## Decisions & Non-Goals
- **Virtual host per domain:** Chosen for SSL separation and clean isolation. **Non-goal:** wildcard ServerAlias setups.
- **Apache + Cloudflare:** Selected for familiarity and CDN/security features. **Non-goal:** Nginx or plugin-based domain mapping.
- **Multisite over many single installs:** Simplifies updates. **Non-goal:** one-VM-per-client unless multisite constraints block a requirement.
- **Origin certificates per domain:** Keeps issuer separation. **Non-goal:** shared SAN certificates that expose tenant list.

## Implementation Ideas & Tradeoffs
- Domain onboarding: provision DNS at Cloudflare, apply origin cert, add vhost, register site in network admin (via WP-CLI where possible); automation expected but remains optional per client.
- Isolation model: Apache vhosts plus per-domain TLS give privacy; application-level separation still relies on WordPress user/role boundaries.
- Performance: start with CDN caching and basic PHP tuning; later consider object caching and DB optimizations if page volume grows.
- Backup and recovery: centralized backups ease restores but aggregate risk; consider per-domain restore paths to keep client blast radius small.

## Rollout Plan
- Foundation: stable multisite with working domain isolation and HTTPS per domain.
- Expansion: repeatable onboarding checklist per client domain.
- Hardening: add layered security controls (WAF rules, stricter TLS, permission reviews).
- Optimization: introduce caching and query tuning once traffic patterns are known.

## Open Questions & Issues
- Should onboarding be fully automated or keep a manual review step per domain?
- Is Cloudflare API access available for bulk certificate issuance at scale?
- What SLA/uptime target do client sites expect, and does it require HA?
- Are there compliance constraints that would disallow shared database storage?

## Implementation References
- WP-CLI commands cookbook: https://make.wordpress.org/cli/handbook/guides/commands-cookbook
- WP-CLI multisite install: https://developer.wordpress.org/cli/commands/core/multisite-install
- Multisite creation guide: https://developer.wordpress.org/advanced-administration/multisite/create-network
- Multisite database tables overview: https://codex.wordpress.org/Database_Description#Multisite_Table_Overview
