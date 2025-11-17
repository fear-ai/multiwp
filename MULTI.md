# WordPress Multisite Hosting Project

*Strategic overview documenting vision, requirements, and architecture choices.*

## Introduction
We aim to host ~100 independent client sites on shared infrastructure while keeping each site private. WordPress multisite is the chosen approach because it centralizes updates while letting each site present as an unrelated brand. This document captures the strategic “why,” the model we use, and the implications of those choices.

## Objectives & Features
- Per-tenant apex domains (apex = root domain, e.g., example.com) so each client appears independent; SSL per domain to avoid cross-tenant signals.
- Reduce hosting/ops cost versus many single installs by sharing core, themes, and plugins while keeping per-site identities.
- Maintain a consistent admin experience with per-site access controls; make onboarding repeatable and quick.
- Use Cloudflare for DNS/CDN/performance to avoid extra application plugins for domain mapping or caching.

## Network & Domain Model
- Each client uses a unique apex domain; no shared subdomains. This prioritizes brand separation and reduces the chance of cross-tenant discovery.
- Domain isolation is enforced with dedicated Apache virtual hosts per domain (no wildcard hosts). This keeps certificate scope and logging segmented.
- SSL is per domain; Cloudflare provides DNS/CDN and transports traffic to the origin using per-domain origin certs.

## Architecture & Choices
- Multisite mode: subdirectory network with mapped apex domains.  
  *Why:* single core install simplifies updates; mapped apex preserves client branding without subdomains.  
  *Alternatives rejected:* subdomain multisite (brand/privacy); many single installs (patching sprawl).  
  *Implication:* routing depends on multisite path handling plus vhost Host headers; mixed subdir + mapped apex requires deliberate onboarding order.
- Web tier: Apache with one vhost per domain.  
  *Why:* keeps SSL scope and logging per tenant; aligns with per-domain origin certs.  
  *Non-goal:* wildcard ServerAlias that would mix cert scope and reduce isolation.
- Edge: Cloudflare for DNS/CDN/SSL offload.  
  *Why:* performance, DDoS protection, managed TLS; avoids domain-mapping plugins.  
  *Non-goal:* Nginx frontends or plugin-based domain mapping. (Cloudflare API specifics live in CloudflareSettings.md.)
- Certificates: per-domain Cloudflare Origin certs (apex + www).  
  *Why:* isolates trust per tenant; simplifies Full (strict) mode.  
  *Non-goal:* shared SAN certs that enumerate tenants.
- Ops tradeoffs (inherent to multisite):  
  *Isolation limits:* shared DB/core; tenants needing hard isolation need separate stacks or added controls.  
  *Upgrades:* coordinated testing needed because a core/plugin change affects all sites.  
  *Backups:* centralized backups are efficient but widen blast radius; prefer per-domain restore paths.

## References
- WP-CLI commands cookbook: https://make.wordpress.org/cli/handbook/guides/commands-cookbook
- WP-CLI multisite install: https://developer.wordpress.org/cli/commands/core/multisite-install
- Multisite creation guide: https://developer.wordpress.org/advanced-administration/multisite/create-network
- Multisite database tables overview: https://codex.wordpress.org/Database_Description#Multisite_Table_Overview
