# WordPress Multisite Hosting Project
Date: January 5, 2026

*Strategic overview documenting vision, requirements, architecture choices, tradeoffs, and lessons learned.*

## Table of Contents
1. [1. Introduction & Objectives](#1-introduction--objectives)
2. [2. Architecture & Design Decisions](#2-architecture--design-decisions)
   1. [2.1 Multisite Mode: Subdirectory with Mapped Apex Domains](#21-multisite-mode-subdirectory-with-mapped-apex-domains)
   2. [2.2 Edge Layer: Cloudflare Proxy, DNS, CDN, SSL](#22-edge-layer-cloudflare-proxy-dns-cdn-ssl)
   3. [2.3 Certificates: Per-Domain Cloudflare Origin Certificates](#23-certificates-per-domain-cloudflare-origin-certificates)
   4. [2.4 Web Tier: Apache with Per-Domain Virtual Hosts](#24-web-tier-apache-with-per-domain-virtual-hosts)
3. [3. Network & Domain Model](#3-network--domain-model)
   1. [3.1 Terminology (Apex, Zone, Subdomain)](#31-terminology-apex-zone-subdomain)
   2. [3.2 Domain Isolation Model](#32-domain-isolation-model)
   3. [3.3 DNS & Cloudflare Proxy](#33-dns--cloudflare-proxy)
   4. [3.4 HTTPS & Security Headers at Edge](#34-https--security-headers-at-edge)
4. [4. Infrastructure Layers](#4-infrastructure-layers)
5. [5. Operational Tradeoffs](#5-operational-tradeoffs)
6. [6. Implementation Issues & Lessons](#6-implementation-issues--lessons)
   1. [6.1 WordPress Multisite Domain Mapping Process](#61-wordpress-multisite-domain-mapping-process)
   2. [6.2 Order-Dependent Operations](#62-order-dependent-operations)
   3. [6.3 sendmail Warning is Expected](#63-sendmail-warning-is-expected)
   4. [6.4 Permission Errors Running Scripts](#64-permission-errors-running-scripts)
   5. [6.5 Apache Redirect Loops with Cloudflare](#65-apache-redirect-loops-with-cloudflare)
7. [7. Abandoned Approaches](#7-abandoned-approaches)
8. [8. Future Investigation](#8-future-investigation)
9. [9. References](#9-references)
10. [10. Glossary](#10-glossary)

---

## 1. Introduction & Objectives

### 1.1 Vision
Host ~100 independent client sites on shared infrastructure while keeping each site appear completely separate. WordPress multisite is the chosen approach because it centralizes updates while letting each site present as an unrelated brand.

### 1.2 Core Objectives
- **Per-tenant apex domains**: Each client uses their own root domain (e.g., example.com) so they appear independent. No shared subdomains or visible relationships between sites.
- **SSL per domain**: Dedicated certificates per domain to avoid cross-tenant enumeration or trust signals.
- **Cost efficiency**: Reduce hosting and operational cost versus many single WordPress installations by sharing core, themes, and plugins.
- **Operational consistency**: Maintain a uniform admin experience with per-site access controls. Make onboarding repeatable and quick.
- **Performance**: Use Cloudflare CDN/proxy for global performance without application-layer caching plugins.

### 1.3 Non-Goals
- **Hard multi-tenancy**: Sites share database and WordPress core. Tenants requiring complete isolation need separate stacks.
- **Plugin-based domain mapping**: We use Apache vhosts and DNS, not WordPress domain-mapping plugins.
- **Wildcard SSL**: Each domain gets individual origin certificates to maintain tenant isolation.
- **Self-service onboarding**: Currently operator-driven; automation exists but not exercised in production.

---

## 2. Architecture & Design Decisions

### 2.1 Multisite Mode: Subdirectory with Mapped Apex Domains

**Decision**: Subdirectory network mode, not subdomain mode.

**Why:**
- Single WordPress core installation simplifies updates and patching
- Subdirectories avoid DNS/SSL complexity during initial multisite setup
- Mapped apex domains preserve client branding without exposing the shared infrastructure
- Apache vhosts map external apex domains to internal subdirectory paths

**Alternatives Rejected:**
1. **Subdomain multisite** (e.g., client1.primary.com, client2.primary.com)
   - Exposes shared infrastructure in URLs
   - Clients appear related, violating brand independence requirement
   - Still requires SSL per subdomain
   - DNS management more complex

2. **Many single WordPress installations**
   - Complete isolation but patching sprawl
   - Each site needs individual updates for core/plugins/themes
   - Higher hosting costs (separate databases, file systems)
   - Operational burden grows linearly with site count

**Implications:**
- Routing depends on multisite path handling plus Apache vhost Host header matching
- Mixed subdirectory + mapped apex requires deliberate onboarding order: create subdirectory site first, then map to apex
- Apache must handle domain-to-path translation before WordPress sees the request
- `.htaccess` multisite rewrite rules must not be bypassed

**Tradeoffs:**
- ✅ Centralized updates (core, themes, plugins)
- ✅ Brand independence for clients
- ✅ Reduced infrastructure cost
- ⚠️ Shared database/core (not hard multi-tenancy)
- ⚠️ Coordinated testing needed for updates (one core change affects all sites)
- ⚠️ Requires Apache vhost per domain (can't use wildcard ServerAlias)

---

### 2.2 Edge Layer: Cloudflare Proxy, DNS, CDN, SSL

**Decision**: Cloudflare handles DNS, CDN, TLS termination, and security at the edge.

**Proxy Model:**
Cloudflare's orange cloud behaves as a reverse proxy: clients connect to Cloudflare, and Cloudflare connects to our origin. This provides origin address shielding and enables caching, WAF, and edge TLS features. Our usage proxies apex and `www`, issues origin certs per apex+www pair, and lets Cloudflare enforce HTTPS and headers at the edge. For normative definitions, see `DNSTerms.md` and the Glossary at the end of this document (section 10).

Reverse proxy background: [Cloudflare reverse proxy] https://www.cloudflare.com/learning/cdn/glossary/reverse-proxy/ [MDN reverse proxy] https://developer.mozilla.org/en-US/docs/Glossary/Reverse_proxy

**HTTPS Responsibility:**
Edge HTTPS and headers belong at Cloudflare; do not add redundant Apache redirects because Apache redirects plus Cloudflare redirects can create loops and extra hops. Use Cloudflare HTTPS enforcement as the canonical policy, and introduce Redirect Rules only when you need custom logic with a tested recovery plan.

**Why:**
- **Performance**: Global CDN with edge caching reduces origin load
- **DDoS protection**: Cloudflare absorbs attacks before they reach origin
- **Managed TLS**: Edge certificates auto-renew, support TLS 1.3, HTTP/2/3
- **DNS management**: API-driven DNS updates are supported and used selectively during onboarding and record changes.
- **Avoids plugins**: No need for WordPress domain-mapping or caching plugins
- **Origin IP hiding**: Proxy mode prevents direct origin exposure

**Non-Goals:**
- Nginx reverse proxy in front of Apache (Cloudflare already proxies)
- WordPress domain-mapping plugins (DNS + vhosts handle this)
- WordPress caching plugins for Cloudflare (managed at the edge with Cache/Redirect Rules and managed transforms)

**Implications:**
- DNS changes at Cloudflare registrar or zone management
- Origin servers see Cloudflare IPs in access logs (not client IPs)
- HTTPS redirect happens at edge, not Apache (prevents loops)
- Security headers applied via Cloudflare Managed Transforms
- Clients must proxy DNS (orange cloud) for WAF/CDN to work

**Tradeoffs:**
- ✅ Offloads TLS, caching, DDoS protection from origin
- ✅ Hides origin IP addresses
- ✅ Centralized edge policy (HTTPS redirects, security headers)
- ⚠️ Dependency on Cloudflare availability
- ⚠️ Debugging requires checking both edge and origin
- ⚠️ Cloudflare proxy must be enabled per domain (not automatic)

---

### 2.3 Certificates: Per-Domain Cloudflare Origin Certificates

**Decision**: Individual Cloudflare Origin certificate per domain (apex + www).

**Why:**
- **Isolates trust per tenant**: No shared SAN cert that enumerates all domains
- **Simplifies Full (strict) mode**: Each vhost references its own cert/key pair
- **15-year validity**: Cloudflare Origin certs valid for 15 years, rarely need renewal
- **Proper SNI**: Each domain presents the correct certificate via SNI

**Non-Goal:**
- Shared SAN certificate covering multiple domains:
  - Would enumerate all tenant domains in one cert
  - Creates cross-tenant discovery vector
  - Harder to manage as domains added/removed

**Implications:**
- Each new domain requires issuing Cloudflare Origin certificate (manual or API)
- Certificates are stored on the origin server with restricted permissions; see `Operations.md` section 4.7 for the exact paths and ownership rules.
- Apache vhost must reference the correct certificate and key for each domain
- Cloudflare SSL/TLS mode must be "Full (strict)" for origin validation

**Tradeoffs:**
- ✅ No tenant enumeration in certificates
- ✅ Per-domain trust isolation
- ✅ Long validity period reduces renewal burden
- ⚠️ Manual cert issuance per domain (API exists but not exercised)
- ⚠️ More certificate files to manage (scales with domains)

---

### 2.4 Web Tier: Apache with Per-Domain Virtual Hosts

**Decision**: One Apache vhost per domain, no wildcard ServerAlias.

**Why:**
- Keeps SSL certificate scope per tenant (one domain per cert)
- Isolates logging per tenant (separate access/error logs per domain)
- Aligns with per-domain origin certificates from Cloudflare
- Explicit vhost per domain prevents accidental cross-tenant exposure
- Simpler troubleshooting (grep logs by domain)

**Non-Goal:**
- Wildcard vhosts (e.g., ServerAlias *.example.com) would:
  - Mix certificate scope across tenants
  - Reduce isolation in logs
  - Make accidental subdomain exposure easier
  - Complicate per-domain cert management

**Implications:**
- Each new domain requires Apache vhost creation and enabling
- Template-based vhost generation standardizes configuration
- DocumentRoot points to shared WordPress installation
- ServerName must match exactly for SNI/TLS to work correctly

**Tradeoffs:**
- ✅ Clear tenant isolation in certificates and logs
- ✅ Explicit configuration prevents surprises
- ✅ Per-domain troubleshooting is straightforward
- ⚠️ Manual step for each new domain (scriptable but not automatic)
- ⚠️ More vhost files to manage (scales linearly with domains)

---

## 3. Network & Domain Model

### 3.1 Terminology (Apex, Zone, Subdomain)
Cloudflare, Apache, and WordPress use related but not identical terminology. Cloudflare’s official term is **zone** for the apex domain, Apache uses hostnames in `ServerName`/`ServerAlias`, and WordPress refers to the site address as a “domain.” To avoid ambiguity, we use the definitions below consistently in this project and cross-reference the broader, industry-standard definitions in `DNSTerms.md`. See the Glossary in section 10 for the canonical project terminology and its references.

- **Apex domain**: The root or “naked” domain (e.g., `example.com`). Also called *root domain*, *base domain*, or *primary domain* in common usage.  
- **Zone (Cloudflare)**: The apex domain as Cloudflare defines it. A Cloudflare “zone name” is the apex domain (`example.com`), not a subdomain.
- **Subdomain**: A child host under the apex (e.g., `blog.example.com`). In Cloudflare, subdomains are DNS records inside the zone.

For this project:
- We treat the **apex domain and the Cloudflare zone name as the same thing**.
- We do not operate distinct subdomain sites. The only subdomain records we maintain are `www` and `*` for canonicalization, and those always route to the apex.

### 3.2 Domain Isolation Model

**Each client uses a unique apex domain; no shared subdomains.**

**Why:**
- Prioritizes brand separation (clients appear completely unrelated)
- Reduces chance of cross-tenant discovery
- Clients own their domain (can transfer away if needed)
- Professional appearance (example.com vs client.ourhost.com)

**Implementation:**
- Cloudflare proxies each apex domain; `www` and `*` exist only to canonicalize to the apex via edge redirects.
- DNS A records point to the origin IPv4, but Cloudflare returns its anycast IPs to clients when the proxy is enabled.
- Origin server has dedicated Apache vhost per domain
- WordPress multisite maps external domain to internal blog_id

**Isolation Enforcement:**
- Apache vhosts are domain-specific (no wildcard)
- Certificates are per-domain (no shared SAN)
- Logs are per-domain (separate files per vhost)
- WordPress sites have separate wp_<blog_id>_options tables

---

### 3.3 DNS & Cloudflare Proxy

**Orange cloud (proxied)** for the apex, plus `www` and `*` for canonicalization. We do not create additional subdomain records beyond these; `www` and `*` exist only to route traffic to the apex and are redirected at the edge.

**Why:**
- Hides origin IP address from DNS lookups
- Enables Cloudflare WAF, CDN, rate limiting
- Provides DDoS protection
- Terminates TLS at edge with managed certificates

**Tradeoffs:**
- ✅ Security and performance benefits
- ✅ Origin IP not exposed in DNS
- ⚠️ DNS TTL controlled by Cloudflare (not registrar)
- ⚠️ Must configure Full (strict) mode per domain (not inherited)
- ⚠️ Debugging requires understanding edge vs origin behavior

---

### 3.4 HTTPS & Security Headers at Edge

**Decision**: HTTPS redirects and security headers managed at Cloudflare edge, not origin.

**Why:**
- **Prevents loops**: Apache redirects + Cloudflare redirects = redirect loop
- **Centralized policy**: All domains get consistent HTTPS enforcement
- **Performance**: Redirect happens at edge, saves origin request
- **Header consistency**: Managed Transforms apply headers uniformly

**Implementation:**
- Cloudflare "Always Use HTTPS" setting enabled per domain
- Security headers via Cloudflare Managed Transforms:
  - HSTS with 1-year max-age
  - X-Content-Type-Options: nosniff
  - X-Frame-Options: SAMEORIGIN
  - Referrer-Policy: same-origin
- Apache does NOT redirect HTTP→HTTPS (Cloudflare handles this)

**HSTS Considerations:**
- **Pros**: Enforces HTTPS at browser; prevents downgrade attacks
- **Cons**: Can lock you out if HTTPS breaks; preload is permanent
- **Rollout**: Start with short max-age (300s) for testing, then increase to 31536000 (1 year) when confident
- **Preload**: Only enable when HTTPS is guaranteed permanent

**Tradeoffs:**
- ✅ No redirect loops (edge handles redirects)
- ✅ Consistent security posture across all domains
- ✅ Reduced origin load (redirects at edge)
- ⚠️ Must configure per domain in Cloudflare UI (not inherited from zone)
- ⚠️ HSTS can cause access issues if HTTPS breaks
- ⚠️ Requires understanding Cloudflare's edge behavior

---

## 4. Infrastructure Layers

### Layer 1: DNS & Edge (Cloudflare)
- **DNS resolution**: Apex + www records proxied (orange cloud)
- **TLS termination**: Cloudflare edge certificates (auto-managed)
- **HTTPS enforcement**: "Always Use HTTPS" redirects HTTP→HTTPS
- **Security headers**: Managed Transforms apply HSTS, X-Frame-Options, etc.
- **WAF & rate limiting**: Cloudflare security features active
- **CDN**: Edge caching for static assets

### Layer 2: Origin TLS (Cloudflare → Apache)
- **Origin certificates**: Per-domain Cloudflare Origin certs (15-year validity)
- **Full (strict) mode**: Cloudflare validates origin cert
- **SNI**: Apache uses SNI to select correct vhost/cert
- **TLS 1.2+**: Minimum TLS version enforced

### Layer 3: Web Server (Apache)
- **Virtual hosts**: One per domain, no wildcards
- **DocumentRoot**: All vhosts point to shared WordPress installation
- **Rewrite rules**: WordPress multisite `.htaccess` handles routing
- **Logging**: Per-domain access and error logs

### Layer 4: Application (WordPress Multisite)
- **Core**: Single WordPress installation shared across all sites
- **Database**: Shared tables (wp_blogs, wp_users) plus per-site tables (wp_<id>_options, wp_<id>_posts)
- **Domain mapping**: wp_blogs table maps external domain to blog_id
- **Site isolation**: Per-site options, content, themes, but shared core/plugins

---

## 5. Operational Tradeoffs

### 5.1 Inherent Multisite Tradeoffs

**Isolation Limits:**
- Shared database and WordPress core
- Tenants requiring hard isolation (regulatory, security) need separate stacks
- One tenant's plugin can potentially affect others (though controlled by network admin)
- Database breach exposes all sites

**Update Coordination:**
- WordPress core/plugin updates affect all sites simultaneously
- Requires coordinated testing before applying updates
- One breaking change impacts entire network
- Rollback must be coordinated across all sites

**Backup & Recovery:**
- Centralized backups are efficient but widen blast radius
- Restoring one site requires database surgery (extracting specific tables)
- Prefer per-domain restore paths where possible
- Database dumps must handle multisite table structure

**Performance:**
- Shared resources (database connections, PHP workers)
- One site's traffic spike can affect others
- Requires careful resource monitoring
- Consider separating high-traffic sites to single-site installs

---

### 5.2 Permission & Security Model

**File System:**
- WordPress runtime needs a web server-owned tree for uploads and read access to code
- Automation should run under a privileged operator account rather than direct root login
- Certificate files must be readable by validation scripts without granting full root access
- See `Operations.md` section 4.7 for the exact ownership, permissions, and operator access model

**Why This Matters:**
- Scripts need to read certificates for validation
- Running as root is risky (one script bug = system compromise)
- Least-privilege access reduces the blast radius of automation
- Discovered during testing: missing certificate read access caused script failures

**Database:**
- WordPress database user has full access to wordpress_multisite database
- No database-level isolation between sites
- All sites share wp_users table (network-level user accounts)

**Lessons Learned:**
- Always grant the deployment user the documented certificate read access during server setup
- Automation should elevate only when required and avoid direct root sessions
- Permission errors are often due to missing certificate read access rather than privilege escalation itself

---

## 6. Implementation Issues & Lessons

### 6.1 WordPress Multisite Domain Mapping Process

**Discovery**: WP-CLI has no `wp site update` command.

**Issue**: Documentation and examples suggested `wp site update --blog_id=X --domain=Y`, but this command doesn't exist in WP-CLI core.

**Solution**: Use direct database queries:
The operational commands and the validated update sequence are documented in `Operations.md` section 5 so system operators have a single authoritative runbook for database updates.

**Why Two Updates Are Needed:**
1. **wp_blogs**: Network-level routing (WordPress uses this to route requests to correct site)
2. **wp_<blog_id>_options**: Site-level URLs (used for generating links, permalinks)

If only wp_blogs is updated: site responds to domain but generates links with old URL.
If only options are updated: site thinks it's at new domain but WordPress routes requests wrong.

**Lesson**: Core WP-CLI doesn't support domain mapping for multisite. Database queries are the correct approach, not a workaround.

---

### 6.2 Order-Dependent Operations

**Issue**: Cannot use `wp --url=https://newdomain.com option update` immediately after creating site.

**Why**: Site is created with subdirectory URL (http://primary.com/slug/). WordPress can't find site by apex domain until wp_blogs is updated with domain mapping.

**Correct Order:**
1. Create site (gets subdirectory URL)
2. Update wp_blogs domain mapping
3. Update wp_<blog_id>_options URLs
4. Verify site accessible at new domain

**Lesson**: Domain mapping must happen before using `--url` option with new domain. Direct database queries bypass site detection issues.

---

### 6.3 sendmail Warning is Expected

**Warning**: `sh: 1: /usr/sbin/sendmail: not found` appears when creating sites.

**Cause**: WP-CLI tries to send welcome email but no mail transfer agent installed.

**Impact**: Cosmetic only. Site creation succeeds. Admin doesn't receive email.

**Fix**: None needed for development/testing. For production, use SMTP plugin (more reliable than sendmail).

**Lesson**: Document in scripts that this warning is normal. Don't install sendmail just to suppress warning.

---

### 6.4 Permission Errors Running Scripts

**Issue**: Scripts failed with permission errors even when run with elevated privileges.

**Cause**: deployment user lacked the documented certificate read access, so cert files were unreadable.

**Fix**: grant access per `Operations.md` section 4.3 and log out/in to refresh group membership.

**Lesson**: Certificate read access is required for validation. Sudo alone doesn't grant group access. Always verify access during server setup.

---

### 6.5 Apache Redirect Loops with Cloudflare

**Issue**: Infinite redirect loop when Apache and Cloudflare both redirect HTTP→HTTPS.

**Cause**:
- Apache sees request from Cloudflare as HTTP (Cloudflare→origin connection)
- Apache redirects to HTTPS
- Cloudflare receives redirect, follows it
- Loop continues

**Fix**: Disable Apache HTTP→HTTPS redirects. Let Cloudflare handle this at edge with "Always Use HTTPS."

**Lesson**: When using Cloudflare proxy, HTTPS enforcement must be at edge, not origin. Origin sees Cloudflare IPs and Cloudflare→origin protocol, not client details.

---

## 7. Abandoned Approaches

### 7.1 Plugin-Based Domain Mapping

**Considered**: WordPress Multisite Domain Mapping plugin or similar.

**Rejected Because:**
- Adds plugin dependency and update burden
- DNS + Apache vhosts already handle domain routing
- Plugin approach obscures routing logic
- Harder to troubleshoot (plugin vs core vs DNS vs Apache)
- We control DNS and Apache, so native approach is cleaner

**Lesson**: Use infrastructure-level solutions (DNS, vhosts) instead of application plugins when you control the infrastructure.

---

### 7.2 Subdomain Multisite Mode

**Considered**: Use subdomain network (client1.primary.com, client2.primary.com).

**Rejected Because:**
- Violates brand independence requirement
- Clients appear related (shared parent domain)
- Still requires SSL per subdomain
- DNS management more complex (wildcard or per-subdomain records)
- Harder to transfer client to their own infrastructure later

**Lesson**: Subdirectory mode with mapped apex domains provides better brand isolation than subdomain mode.

---

### 7.3 Wildcard Apache Virtual Hosts

**Considered**: Use wildcard ServerAlias to catch all domains with one vhost.

**Rejected Because:**
- Mixes SSL certificate scope across tenants
- Reduces logging isolation (all domains in same log)
- Makes accidental subdomain exposure easier
- Harder to troubleshoot per-domain issues
- Doesn't align with per-domain origin certificates

**Lesson**: Explicit vhost per domain maintains clean isolation even though it's more verbose.

---

### 7.4 Shared SAN Certificates

**Considered**: One Cloudflare Origin certificate with SAN listing all domains.

**Rejected Because:**
- Enumerates all tenant domains in certificate (privacy/security concern)
- Creates cross-tenant discovery vector
- Must reissue cert every time domain added/removed
- All domains must share certificate lifecycle

**Lesson**: Per-domain certificates maintain tenant isolation and simplify lifecycle management.

---

### 7.5 Let's Encrypt Certificates with Certbot

**Considered**: Use Let's Encrypt for origin certificates instead of Cloudflare Origin certs.

**Rejected Because:**
- 90-day validity requires renewal automation
- Certbot adds complexity and potential failure points
- Cloudflare Origin certs have 15-year validity
- Cloudflare Origin certs are purpose-built for Cloudflare→origin
- No benefit since Cloudflare already manages edge certificates

**Lesson**: Use Cloudflare Origin certificates for Cloudflare-proxied sites. Let's Encrypt is better for sites not behind Cloudflare.

---

### 7.6 Nginx Instead of Apache

**Considered**: Use Nginx as web server instead of Apache.

**Not Chosen Because:**
- Apache already familiar to team
- WordPress documentation emphasizes Apache
- `.htaccess` support simpler in Apache
- Multisite rewrite rules well-documented for Apache
- No compelling performance reason (Cloudflare caches at edge)

**Not Rejected**: Could revisit if Apache performance becomes bottleneck. Nginx would require translating `.htaccess` to nginx config.

---

### 7.7 API-Driven Onboarding (Implemented and Used Selectively)

**Current State**: Scripts exist for Cloudflare API automation (cloud-dns.sh, get-cert.sh) and are used when repeatable onboarding or bulk changes are needed.

**Operational Considerations:**
- Manual UI workflow remains valid for one-off changes or when validation is required in the UI.
- API automation must be paired with clear credential scoping and post-run validation.
- Use the documented auth-file patterns in `Operations.md` section 3.5.5 so token/key selection is explicit.

**Status**: Scripts are available and used selectively; expand usage as testing coverage grows.

---

## 8. Future Investigation

### 8.1 Cloudflare API Automation

**Current State**: Scripts are available and used selectively, with manual UI steps still used for validation or edge-only changes.

**Investigation Needed:**
- Expand coverage for cloud-dns.sh and get-cert.sh with repeatable test runs.
- Clarify which steps remain UI-only vs scriptable for each onboarding phase.
- Continue refining token/key scoping and account separation as the domain count grows.
- Document failure modes and recovery procedures
- Compare reliability of API vs UI workflows

**Benefit**: Faster onboarding, less manual work, scriptable bulk operations.

**Risk**: API failures harder to debug than UI. Need solid error handling.

**Test Plan**: Use dedicated test domains (realdao.org, talkdao.net, recomp.top) to exercise API workflows.

---

### 8.2 Database Isolation & Security

**Current State**: All sites share wordpress_multisite database. No row-level or table-level isolation.

**Questions:**
- Can we use separate databases per site while keeping multisite benefits?
- Would HyperDB or LudicrousDB provide better isolation?
- What's the performance impact of per-site databases?
- How would backups/restores change?

**Benefit**: Better tenant isolation, easier per-site restoration, clearer blast radius.

**Tradeoff**: More complex, may lose some multisite benefits, higher resource usage.

---

### 8.3 Automated Backup & Restore Procedures

**Current State**: No documented backup strategy. Backups likely exist at infrastructure level but not tested.

**Investigation Needed:**
- Document current backup mechanism (Vultr snapshots? MySQL dumps?)
- Test full restore procedure
- Test per-site restore (extract one site from multisite)
- Automate database dumps with per-site extraction scripts
- Define RTO/RPO for each site type

**Benefit**: Confidence in recovery, faster incident response.

---

### 8.4 Monitoring & Alerting

**Current State**: No monitoring mentioned. Likely relying on manual checks.

**Investigation Needed:**
- WordPress uptime monitoring (per-domain checks)
- Certificate expiration alerts (15-year certs but good to track)
- Apache error rate monitoring
- Database performance metrics
- Cloudflare edge metrics integration

**Tools to Consider:**
- Uptime Robot or similar for HTTP monitoring
- Cloudflare Analytics for edge metrics
- WordPress plugin for internal health checks
- Custom script checking wp site list output

---

### 8.5 Performance Optimization

**Questions:**
- Is database becoming bottleneck as site count grows?
- Should high-traffic sites move to dedicated installs?
- Would Redis/Memcached object caching help?
- Are Cloudflare Cache and Redirect Rules optimally configured?
- Should we implement rate limiting per site?

**Investigation:**
- Baseline current performance (response times, database queries)
- Monitor resource usage as sites are added
- Define thresholds for moving sites to single-site installs
- Test object caching impact on multisite

---

### 8.6 Staging Environment

**Current State**: All work done on production server.

**Investigation Needed:**
- Cost/benefit of separate staging server
- Could Docker/local environments suffice for testing?
- How to sync staging data with production?
- Testing workflow for WordPress core/plugin updates

**Benefit**: Safer testing, reduced production risk.

**Tradeoff**: Additional infrastructure cost, sync complexity.

---

### 8.7 Content Delivery & Asset Optimization

**Questions:**
- Are we fully utilizing Cloudflare's caching?
- Should we use Cloudflare Images for automatic optimization?
- Would a CDN for WordPress uploads (separate from Cloudflare) help?
- Are Cache and Redirect Rules configured optimally per site?

**Investigation:**
- Audit current cache hit rates in Cloudflare Analytics
- Review Cache and Redirect Rules for each domain
- Test cache purging workflows
- Consider Cloudflare Workers for advanced caching logic

---

### 8.8 Security Hardening

**Current State**: Basic security (HTTPS, Cloudflare WAF, isolated certs).

**Investigation Needed:**
- Enable WordPress audit logging
- Implement fail2ban for login attempts
- Review WordPress file permissions
- Consider moving wp-config.php outside web root
- Enable Cloudflare Bot Fight Mode or challenge pages
- Review database user privileges (do we need GRANT ALL?)

**Benefit**: Reduced attack surface, better incident response.

---

### 8.9 Scaling Strategy

**Questions:**
- At what site count does this architecture become inefficient?
- When should we move to multiple WordPress multisite instances?
- How would we split sites across multiple origin servers?
- Load balancing strategy if we need multiple origins?

**Investigation:**
- Define scaling thresholds (number of sites, traffic, database size)
- Test multi-origin setup behind Cloudflare Load Balancer
- Plan for site migration between multisite instances

---

### 8.10 WordPress Core Update Strategy

**Current State**: Centralized updates affect all sites.

**Investigation Needed:**
- Define testing procedure for core updates
- Identify test sites to update first
- Rollback procedure if update breaks sites
- Communication plan for maintenance windows
- Consider staging environment for update testing

**Benefit**: Safer updates, less risk of network-wide breakage.

---

## 9. References

- WP-CLI Commands Cookbook: https://make.wordpress.org/cli/handbook/guides/commands-cookbook
- WP-CLI Multisite Install: https://developer.wordpress.org/cli/commands/core/multisite-install
- Multisite Creation Guide: https://developer.wordpress.org/advanced-administration/multisite/create-network
- Multisite Database Tables: https://codex.wordpress.org/Database_Description#Multisite_Table_Overview
- Cloudflare SSL Modes: https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/
- Cloudflare Origin Certificates: https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/

## 10. Glossary
This glossary captures project-specific terminology and conventions. It links to `DNSTerms.md` for industry-standard definitions and adds the project-level constraints and choices that drive this architecture.

- **Apex domain mapping (project)**: Each client site presents a distinct apex domain at the edge, while WordPress routes internally using the multisite subdirectory model. This blends industry-standard apex definitions with our multisite mapping approach. ([DNSTerms: Names and Delegation](DNSTerms.md#names-and-delegation))
- **Zone name == apex domain (project rule)**: We treat the Cloudflare zone name as the apex domain and do not create subdomain zones. This keeps configuration at the apex level and aligns with DNS delegation expectations. ([DNSTerms: Names and Delegation](DNSTerms.md#names-and-delegation); [DNSTerms ref 11](DNSTerms.md#ref-11))
- **Canonicalization subdomains (`www` and `*`)**: We publish only `www` and `*` subdomain records, and they exist to route traffic back to the apex. These are not independent sites; they are canonicalization targets. ([DNSTerms: Names and Delegation](DNSTerms.md#names-and-delegation))
- **Redirect-only zone**: A domain whose edge behavior is a permanent redirect to a canonical site. Redirect rules and HTTPS enforcement are applied at the edge, and the origin is treated as a fallback only. ([DNSTerms: HTTPS, TLS, and Security Headers](DNSTerms.md#https-tls-and-security-headers); [DNSTerms ref 21](DNSTerms.md#ref-21))
- **Site type values**: `singlesite`, `multisite`, `redirect`, and `ignore` define how the domain is expected to behave at the edge and origin. These values drive scripts, checks, and record updates, and they correspond to the intended operational lifecycle of the domain.
- **Edge vs origin responsibility (project rule)**: HTTPS redirects and security headers are enforced at Cloudflare, while Apache serves application content without redirecting HTTP to HTTPS. This avoids redirect loops and keeps edge policy uniform. ([DNSTerms: HTTPS, TLS, and Security Headers](DNSTerms.md#https-tls-and-security-headers); [DNSTerms ref 19](DNSTerms.md#ref-19); [DNSTerms ref 22](DNSTerms.md#ref-22))
- **Per-domain origin certificate**: Each domain uses a distinct Cloudflare Origin CA certificate for the origin connection, keeping trust scoped per tenant and avoiding SAN enumeration. ([DNSTerms: HTTPS, TLS, and Security Headers](DNSTerms.md#https-tls-and-security-headers); [DNSTerms ref 20](DNSTerms.md#ref-20))
- **Apache per-domain vhost**: Each domain has a dedicated Apache vhost and log files; no wildcard ServerAlias. This enforces tenant isolation and keeps certificate selection explicit. ([DNSTerms: Apache Virtual Host Terminology](DNSTerms.md#apache-virtual-host-terminology); [DNSTerms ref 23](DNSTerms.md#ref-23))
- **WordPress Address vs Site Address**: WordPress distinguishes the URL of the core files from the URL users type in the browser. This matters when the core lives in a subdirectory but the site presents an apex domain. ([WordPress General Settings](https://wordpress.org/documentation/article/settings-general-screen/))
- **IPv6 posture (current)**: We do not publish AAAA records for hosted domains and we treat IPv6 as disabled at the origin. If this posture changes, DNS, firewall, and listener configuration must be updated together. ([DNSTerms: Addressing](DNSTerms.md#addressing); [DNSTerms: Ubuntu Networking and Firewall Basics](DNSTerms.md#ubuntu-networking-and-firewall-basics); [DNSTerms ref 13](DNSTerms.md#ref-13))
