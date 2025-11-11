# WordPress Multisite Hosting Project

*Strategic overview documenting project vision, requirements, and architecture decisions. For current technical state see CONF.md.*

## Vision and Benefits

**Objective:** Host ~100 client websites using WordPress multisite architecture where each site appears as an independent domain while sharing underlying infrastructure.

**Key Benefits:**
- **Cost Efficiency:** Single server infrastructure supports multiple client sites
- **Maintenance Simplification:** WordPress core updates, security patches, and plugin management centralized
- **Client Independence:** Each domain appears completely unrelated to others
- **Scalability:** Add new client sites without additional server provisioning
- **Security Isolation:** Individual SSL certificates and domain separation prevent cross-client exposure

**Core Features:**
- Individual domain mapping (client1.com, client2.com, etc.)
- Separate SSL certificates per domain maintaining privacy
- Individual Apache virtual hosts for complete isolation
- Centralized WordPress administration with distributed client access
- CDN integration through Cloudflare for performance and security

**Pain Points Addressed:**
- **Expensive Individual Hosting:** Single server replaces multiple hosting accounts
- **Update Management Overhead:** One WordPress installation vs. 100 separate instances  
- **SSL Certificate Complexity:** Automated certificate management per domain
- **Client Isolation Requirements:** Complete domain separation prevents business relationship exposure

## Formal Requirements

### Phase 1: Foundation and Operation
**Primary Focus:** Smooth setup and transparent operation

#### Core Infrastructure
- Ubuntu 24.04 server with Apache 2.4, PHP 8.3, MySQL 8.0
- WordPress multisite network using subdirectory structure
- Individual Apache virtual hosts per client domain (no wildcard configurations)
- Cloudflare DNS and CDN integration for all domains

#### Domain Management
- Each client receives unique domain (no subdomain sharing)
- Individual SSL certificates per domain (Cloudflare Origin certificates)
- Separate Apache virtual host configurations (HTTP port 80, HTTPS port 443)
- Complete DNS management through Cloudflare

#### Client Experience
- Full WordPress admin access for their specific site
- Custom domain appearance with no shared branding
- Standard WordPress functionality (themes, plugins, content management)
- Email integration through domain-specific configurations

#### Administrative Control
- Network-wide WordPress management (themes, plugins, users)
- Centralized security monitoring and updates
- Automated backup procedures for all sites
- Individual site performance monitoring

### Phase 2: Security Hardening (Future)
- Attack mitigation and IP blocking systems
- Enhanced file permission management
- Security monitoring and alerting
- Vulnerability scanning automation

### Phase 3: Performance Optimization (Future)
- Caching layer implementation
- Database query optimization
- Static asset optimization
- Load balancing considerations

### Phase 4: Maintenance Automation (Future)
- Automated client site provisioning
- Backup and restoration procedures
- Update management workflows
- Monitoring and alerting systems

## Architecture Overview

**Traffic Flow:** Browser → Cloudflare CDN → Apache Virtual Hosts → WordPress Multisite → MySQL Database

**Key Components:**
- **Apache Virtual Hosts:** Individual configurations per domain enabling SSL and domain isolation
- **WordPress Multisite:** Central administration with distributed site management
- **MySQL Database:** Shared database with site-specific table prefixes
- **Cloudflare Integration:** DNS management, CDN services, and SSL certificate provisioning
- **SSL Certificates:** Individual Cloudflare Origin certificates per domain

## System Change Impact Analysis

### Domain Addition/Removal
**Affects:**
- Apache virtual host configurations (new .conf files)
- SSL certificate provisioning
- DNS configuration in Cloudflare
- WordPress site creation in network admin

### WordPress Core Updates
**Affects:**
- All sites simultaneously (benefit of multisite)
- Requires staging and testing procedures
- Potential theme/plugin compatibility verification

### Server Configuration Changes
**Affects:**
- All client sites immediately
- Requires comprehensive testing before implementation
- May need maintenance windows for major changes

### SSL Certificate Management
**Affects:**
- Individual domains only
- Certificate renewal automation required
- Cloudflare API integration for scaling

### Theme/Plugin Updates
**Affects:**
- Can be deployed network-wide or per-site
- Requires compatibility testing across client sites
- Version management for client-specific customizations

## Discarded Ideas

**Apache Rewrite Rules in Virtual Host Files:** Rejected due to WordPress multisite requirements for .htaccess-based URL routing. WordPress documentation specifies .htaccess placement for proper multisite functionality.

**Wildcard Virtual Host (ServerAlias *):** Abandoned after implementation failures. WordPress multisite domain mapping requires individual virtual host configurations for proper SSL certificate handling and domain isolation.

**WordPress Domain Mapping Plugin:** Eliminated in favor of Apache-level domain handling. Individual virtual hosts provide better SSL certificate management and complete domain isolation without plugin dependencies.

## Documentation Roadmap

### Project Structure
```
multiwp/
├── MULTI.md                          # Project vision and strategic overview
├── CONF.md                           # Current technical configuration reference
├── templates/                        # Configuration templates
├── scripts/                          # Automation scripts
└── [future: TEST.md, OPS.md, etc.]  # Operational documentation
```

### Specialized Documentation (Future Phases)
- **SCALE.md** - Performance optimization for 100+ domain hosting
- **SEC.md** - Security hardening procedures and attack mitigation
- **TROUBLESHOOT.md** - Diagnostic procedures and common issue resolution

### Implementation Sequence
1. **Foundation Phase:** Complete CONF.md, create basic templates and scripts ✓
2. **Domain Management:** Enhanced add-domains.sh with RFC-compliant validation ✓
3. **Validation Phase:** Develop TEST.md and comprehensive validation procedures
4. **Operational Phase:** Create OPS.md and maintenance automation
5. **Advanced Phases:** Security, performance, and scaling documentation as project matures

## Current Status

### Completed Components
- **Templates:** All required Apache and WordPress configuration templates created
- **Base Scripts:** setup-wp.sh and add-domains.sh operational with enhanced validation
- **Domain Validation:** RFC-compliant validation including length limits and pattern checking
- **Documentation:** MULTI.md and CONF.md provide comprehensive project foundation

