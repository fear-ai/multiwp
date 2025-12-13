# WordPress Multisite Hosting Project

*Strategic overview documenting vision, requirements, architecture choices, tradeoffs, and lessons learned.*

## Table of Contents
1. [Introduction & Objectives](#introduction--objectives)
2. [Architecture & Design Decisions](#architecture--design-decisions)
3. [Network & Domain Model](#network--domain-model)
4. [Infrastructure Layers](#infrastructure-layers)
5. [Operational Tradeoffs](#operational-tradeoffs)
6. [Implementation Issues & Lessons](#implementation-issues--lessons)
7. [Abandoned Approaches](#abandoned-approaches)
8. [Future Investigation](#future-investigation)

---

## Introduction & Objectives

### Vision
Host ~100 independent client sites on shared infrastructure while keeping each site appear completely separate. WordPress multisite is the chosen approach because it centralizes updates while letting each site present as an unrelated brand.

### Core Objectives
- **Per-tenant apex domains**: Each client uses their own root domain (e.g., example.com) so they appear independent. No shared subdomains or visible relationships between sites.
- **SSL per domain**: Dedicated certificates per domain to avoid cross-tenant enumeration or trust signals.
- **Cost efficiency**: Reduce hosting and operational cost versus many single WordPress installations by sharing core, themes, and plugins.
- **Operational consistency**: Maintain a uniform admin experience with per-site access controls. Make onboarding repeatable and quick.
- **Performance**: Use Cloudflare CDN/proxy for global performance without application-layer caching plugins.

### Non-Goals
- **Hard multi-tenancy**: Sites share database and WordPress core. Tenants requiring complete isolation need separate stacks.
- **Plugin-based domain mapping**: We use Apache vhosts and DNS, not WordPress domain-mapping plugins.
- **Wildcard SSL**: Each domain gets individual origin certificates to maintain tenant isolation.
- **Self-service onboarding**: Currently operator-driven; automation exists but not exercised in production.

---

## Architecture & Design Decisions

### Multisite Mode: Subdirectory with Mapped Apex Domains

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

### Web Tier: Apache with Per-Domain Virtual Hosts

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

### Edge Layer: Cloudflare Proxy, DNS, CDN, SSL

**Decision**: Cloudflare handles DNS, CDN, TLS termination, and security at the edge.

**Why:**
- **Performance**: Global CDN with edge caching reduces origin load
- **DDoS protection**: Cloudflare absorbs attacks before they reach origin
- **Managed TLS**: Edge certificates auto-renew, support TLS 1.3, HTTP/2/3
- **DNS management**: API-driven DNS updates (not yet exercised in production)
- **Avoids plugins**: No need for WordPress domain-mapping or caching plugins
- **Origin IP hiding**: Proxy mode prevents direct origin exposure

**Non-Goals:**
- Nginx reverse proxy in front of Apache (Cloudflare already proxies)
- WordPress domain-mapping plugins (DNS + vhosts handle this)
- WordPress caching plugins for Cloudflare (managed at edge with Page Rules)

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

### Certificates: Per-Domain Cloudflare Origin Certificates

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
- Certificates stored at `/etc/ssl/cloudflare-origin/{certs,keys}/<safe>.{crt,key}`
- Permissions must be `root:ssl-cert 640` for keys
- Apache vhost must reference correct cert paths
- Cloudflare SSL/TLS mode must be "Full (strict)" for origin validation

**Tradeoffs:**
- ✅ No tenant enumeration in certificates
- ✅ Per-domain trust isolation
- ✅ Long validity period reduces renewal burden
- ⚠️ Manual cert issuance per domain (API exists but not exercised)
- ⚠️ More certificate files to manage (scales with domains)

---

## Network & Domain Model

### Domain Isolation Model

**Each client uses a unique apex domain; no shared subdomains.**

**Why:**
- Prioritizes brand separation (clients appear completely unrelated)
- Reduces chance of cross-tenant discovery
- Clients own their domain (can transfer away if needed)
- Professional appearance (example.com vs client.ourhost.com)

**Implementation:**
- Cloudflare proxies each apex domain + www subdomain
- DNS A/AAAA records point to Cloudflare anycast IPs (not origin)
- Origin server has dedicated Apache vhost per domain
- WordPress multisite maps external domain to internal blog_id

**Isolation Enforcement:**
- Apache vhosts are domain-specific (no wildcard)
- Certificates are per-domain (no shared SAN)
- Logs are per-domain (separate files per vhost)
- WordPress sites have separate wp_<blog_id>_options tables

---

### DNS & Cloudflare Proxy

**Orange cloud (proxied)** for all apex and www records.

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

### HTTPS & Security Headers at Edge

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

## Infrastructure Layers

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

## Operational Tradeoffs

### Inherent Multisite Tradeoffs

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
- Consider separating high-traffic sites to standalone installs

---

### Permission & Security Model

**File System:**
- WordPress files owned by `www-data:www-data`
- Deployment user (ubuntu) in `ssl-cert` group to read certificates
- Scripts run as ubuntu with sudo, not as root
- Certificate keys are `root:ssl-cert 640`

**Why This Matters:**
- Scripts need to read certificates for validation
- Running as root is risky (one script bug = system compromise)
- ssl-cert group provides read access without full root
- Discovered during testing: ubuntu user initially not in ssl-cert group

**Database:**
- WordPress database user has full access to wordpress_multisite database
- No database-level isolation between sites
- All sites share wp_users table (network-level user accounts)

**Lessons Learned:**
- Always add deployment user to ssl-cert group during server setup
- Scripts should use `sudo` for privileged operations, not require root login
- Permission errors are often due to missing group membership, not sudo

---

## Implementation Issues & Lessons

### WordPress Multisite Domain Mapping Process

**Discovery**: WP-CLI has no `wp site update` command.

**Issue**: Documentation and examples suggested `wp site update --blog_id=X --domain=Y`, but this command doesn't exist in WP-CLI core.

**Solution**: Use direct database queries:
```
wp db query "UPDATE wp_blogs SET domain='example.com', path='/' WHERE blog_id=X;"
wp db query "UPDATE wp_X_options SET option_value='https://example.com' WHERE option_name IN ('siteurl', 'home');"
```

**Why Two Updates Are Needed:**
1. **wp_blogs**: Network-level routing (WordPress uses this to route requests to correct site)
2. **wp_<blog_id>_options**: Site-level URLs (used for generating links, permalinks)

If only wp_blogs is updated: site responds to domain but generates links with old URL.
If only options are updated: site thinks it's at new domain but WordPress routes requests wrong.

**Lesson**: Core WP-CLI doesn't support domain mapping for multisite. Database queries are the correct approach, not a workaround.

---

### Order-Dependent Operations

**Issue**: Cannot use `wp --url=https://newdomain.com option update` immediately after creating site.

**Why**: Site is created with subdirectory URL (http://primary.com/slug/). WordPress can't find site by apex domain until wp_blogs is updated with domain mapping.

**Correct Order:**
1. Create site (gets subdirectory URL)
2. Update wp_blogs domain mapping
3. Update wp_<blog_id>_options URLs
4. Verify site accessible at new domain

**Lesson**: Domain mapping must happen before using `--url` flag with new domain. Direct database queries bypass site detection issues.

---

### sendmail Warning is Expected

**Warning**: `sh: 1: /usr/sbin/sendmail: not found` appears when creating sites.

**Cause**: WP-CLI tries to send welcome email but no mail transfer agent installed.

**Impact**: Cosmetic only. Site creation succeeds. Admin doesn't receive email.

**Fix**: None needed for development/testing. For production, use SMTP plugin (more reliable than sendmail).

**Lesson**: Document in scripts that this warning is normal. Don't install sendmail just to suppress warning.

---

### Permission Errors Running Scripts

**Issue**: Scripts failed with permission errors even when run with sudo.

**Cause**: ubuntu user not in ssl-cert group, couldn't read certificate files.

**Fix**: `sudo usermod -aG ssl-cert ubuntu` then log out/in.

**Lesson**: Group membership is required for reading certificates. Sudo alone doesn't grant group access. Always verify group membership during server setup.

---

### Apache Redirect Loops with Cloudflare

**Issue**: Infinite redirect loop when Apache and Cloudflare both redirect HTTP→HTTPS.

**Cause**:
- Apache sees request from Cloudflare as HTTP (Cloudflare→origin connection)
- Apache redirects to HTTPS
- Cloudflare receives redirect, follows it
- Loop continues

**Fix**: Disable Apache HTTP→HTTPS redirects. Let Cloudflare handle this at edge with "Always Use HTTPS."

**Lesson**: When using Cloudflare proxy, HTTPS enforcement must be at edge, not origin. Origin sees Cloudflare IPs and Cloudflare→origin protocol, not client details.

---

## Abandoned Approaches

### 1. Plugin-Based Domain Mapping

**Considered**: WordPress Multisite Domain Mapping plugin or similar.

**Rejected Because:**
- Adds plugin dependency and update burden
- DNS + Apache vhosts already handle domain routing
- Plugin approach obscures routing logic
- Harder to troubleshoot (plugin vs core vs DNS vs Apache)
- We control DNS and Apache, so native approach is cleaner

**Lesson**: Use infrastructure-level solutions (DNS, vhosts) instead of application plugins when you control the infrastructure.

---

### 2. Subdomain Multisite Mode

**Considered**: Use subdomain network (client1.primary.com, client2.primary.com).

**Rejected Because:**
- Violates brand independence requirement
- Clients appear related (shared parent domain)
- Still requires SSL per subdomain
- DNS management more complex (wildcard or per-subdomain records)
- Harder to transfer client to their own infrastructure later

**Lesson**: Subdirectory mode with mapped apex domains provides better brand isolation than subdomain mode.

---

### 3. Wildcard Apache Virtual Hosts

**Considered**: Use wildcard ServerAlias to catch all domains with one vhost.

**Rejected Because:**
- Mixes SSL certificate scope across tenants
- Reduces logging isolation (all domains in same log)
- Makes accidental subdomain exposure easier
- Harder to troubleshoot per-domain issues
- Doesn't align with per-domain origin certificates

**Lesson**: Explicit vhost per domain maintains clean isolation even though it's more verbose.

---

### 4. Shared SAN Certificates

**Considered**: One Cloudflare Origin certificate with SAN listing all domains.

**Rejected Because:**
- Enumerates all tenant domains in certificate (privacy/security concern)
- Creates cross-tenant discovery vector
- Must reissue cert every time domain added/removed
- All domains must share certificate lifecycle

**Lesson**: Per-domain certificates maintain tenant isolation and simplify lifecycle management.

---

### 5. Let's Encrypt Certificates with Certbot

**Considered**: Use Let's Encrypt for origin certificates instead of Cloudflare Origin certs.

**Rejected Because:**
- 90-day validity requires renewal automation
- Certbot adds complexity and potential failure points
- Cloudflare Origin certs have 15-year validity
- Cloudflare Origin certs are purpose-built for Cloudflare→origin
- No benefit since Cloudflare already manages edge certificates

**Lesson**: Use Cloudflare Origin certificates for Cloudflare-proxied sites. Let's Encrypt is better for sites not behind Cloudflare.

---

### 6. Nginx Instead of Apache

**Considered**: Use Nginx as web server instead of Apache.

**Not Chosen Because:**
- Apache already familiar to team
- WordPress documentation emphasizes Apache
- `.htaccess` support simpler in Apache
- Multisite rewrite rules well-documented for Apache
- No compelling performance reason (Cloudflare caches at edge)

**Not Rejected**: Could revisit if Apache performance becomes bottleneck. Nginx would require translating `.htaccess` to nginx config.

---

### 7. API-Driven Onboarding (Not Yet Exercised)

**Implemented but Not Used**: Scripts exist for Cloudflare API automation (cloud-dns.sh, cloud-cert.sh).

**Why Not Used Yet:**
- Manual UI workflow is well-documented and tested
- API automation needs testing before production use
- Token/credential management not yet standardized
- Team still learning optimal onboarding workflow

**Status**: Scripts exist, syntax-validated, but not exercised in production. Planned for future testing with dedicated test domains.

---

## Future Investigation

### 1. Cloudflare API Automation

**Current State**: Scripts exist but not exercised. Manual UI workflow used for all domains.

**Investigation Needed:**
- Test cloud-dns.sh for zone creation and DNS record management
- Test cloud-cert.sh for automated origin certificate issuance
- Standardize API token management (environment variables vs credential store)
- Document failure modes and recovery procedures
- Compare reliability of API vs UI workflows

**Benefit**: Faster onboarding, less manual work, scriptable bulk operations.

**Risk**: API failures harder to debug than UI. Need solid error handling.

**Test Plan**: Use dedicated test domains (realdao.org, talkdao.net, recomp.top) to exercise API workflows.

---

### 2. Database Isolation & Security

**Current State**: All sites share wordpress_multisite database. No row-level or table-level isolation.

**Questions:**
- Can we use separate databases per site while keeping multisite benefits?
- Would HyperDB or LudicrousDB provide better isolation?
- What's the performance impact of per-site databases?
- How would backups/restores change?

**Benefit**: Better tenant isolation, easier per-site restoration, clearer blast radius.

**Tradeoff**: More complex, may lose some multisite benefits, higher resource usage.

---

### 3. Automated Backup & Restore Procedures

**Current State**: No documented backup strategy. Backups likely exist at infrastructure level but not tested.

**Investigation Needed:**
- Document current backup mechanism (Vultr snapshots? MySQL dumps?)
- Test full restore procedure
- Test per-site restore (extract one site from multisite)
- Automate database dumps with per-site extraction scripts
- Define RTO/RPO for each site type

**Benefit**: Confidence in recovery, faster incident response.

---

### 4. Monitoring & Alerting

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

### 5. Performance Optimization

**Questions:**
- Is database becoming bottleneck as site count grows?
- Should high-traffic sites move to dedicated installs?
- Would Redis/Memcached object caching help?
- Are Cloudflare Page Rules optimally configured?
- Should we implement rate limiting per site?

**Investigation:**
- Baseline current performance (response times, database queries)
- Monitor resource usage as sites are added
- Define thresholds for moving sites to standalone installs
- Test object caching impact on multisite

---

### 6. Staging Environment

**Current State**: All work done on production server.

**Investigation Needed:**
- Cost/benefit of separate staging server
- Could Docker/local environments suffice for testing?
- How to sync staging data with production?
- Testing workflow for WordPress core/plugin updates

**Benefit**: Safer testing, reduced production risk.

**Tradeoff**: Additional infrastructure cost, sync complexity.

---

### 7. Content Delivery & Asset Optimization

**Questions:**
- Are we fully utilizing Cloudflare's caching?
- Should we use Cloudflare Images for automatic optimization?
- Would a CDN for WordPress uploads (separate from Cloudflare) help?
- Are Page Rules configured optimally per site?

**Investigation:**
- Audit current cache hit rates in Cloudflare Analytics
- Review Page Rules for each domain
- Test cache purging workflows
- Consider Cloudflare Workers for advanced caching logic

---

### 8. Security Hardening

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

### 9. Scaling Strategy

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

### 10. WordPress Core Update Strategy

**Current State**: Centralized updates affect all sites.

**Investigation Needed:**
- Define testing procedure for core updates
- Identify test sites to update first
- Rollback procedure if update breaks sites
- Communication plan for maintenance windows
- Consider staging environment for update testing

**Benefit**: Safer updates, less risk of network-wide breakage.

---

## References

- WP-CLI Commands Cookbook: https://make.wordpress.org/cli/handbook/guides/commands-cookbook
- WP-CLI Multisite Install: https://developer.wordpress.org/cli/commands/core/multisite-install
- Multisite Creation Guide: https://developer.wordpress.org/advanced-administration/multisite/create-network
- Multisite Database Tables: https://codex.wordpress.org/Database_Description#Multisite_Table_Overview
- Cloudflare SSL Modes: https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/
- Cloudflare Origin Certificates: https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/
