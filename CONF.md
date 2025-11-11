# WordPress Multisite Setup and Configuration

*Technical configuration reference documenting current system state. For project vision and strategic overview see MULTI.md.*

## Infrastructure Setup
- **Server**: Ubuntu 24.04 on Vultr VPS (laz24)  
- **Primary IP**: 104.238.140.248
- **WordPress**: Version 6.8.2 at `/var/www/html/wordpress/`
- **Database**: MySQL 8.0.43, database `wordpress_multisite`, user `wp_user`
- **Web Server**: Apache 2.4

## WordPress Configuration
- **Type**: Multisite network with subdirectories
- **Primary Domain**: alphaeos.net
- **Network Admin Email**: alphaeosnet@gmail.com
- **Config**: `/var/www/html/wordpress/wp-config.php` (multisite enabled)
- **Rewrite Rules**: `/var/www/html/wordpress/.htaccess`

## Virtual Host Strategy
- **Domains**: Individual Apache virtual host per domain, not wildcard catch-all
- **HTTP Virtual Host**: Port 80 - `/etc/apache2/sites-available/alphaeosnet.conf`
- **HTTPS Virtual Host**: Port 443 - `/etc/apache2/sites-available/alphaeosnet-ssl.conf`

## SSL/HTTPS Configuration  
- **Cloudflare Settings**: 
  - Always Use HTTPS: OFF
  - Automatic HTTPS Rewrites: OFF  
  - SSL/TLS Mode: Flexible (sufficient for current setup)
- **SSL Certificates**: Cloudflare Origin certificates installed and working
  - `/etc/ssl/certs/cloudflare-origin.crt`
  - `/etc/ssl/private/cloudflare-origin.key`
- **Apache SSL Module**: Enabled

## Routing and DNS
- **Traffic Routing**: Browser → Cloudflare (HTTPS) → Server (HTTP/HTTPS) via Cloudflare IPs
- **DNS Provider**: Cloudflare (proxy enabled - orange cloud)
- **Local DNS**: Static configuration in /etc/resolv.conf
  - nameserver 8.8.8.8
  - nameserver 1.1.1.1

## Automation Scripts

### setup-wp.sh
WordPress multisite base installation following official documentation
- MySQL database and user creation with proper permissions
- WordPress download and configuration
- Multisite network activation

### add-domains.sh  
Enhanced domain addition with RFC-compliant validation, template processing, and Apache integration

## Documentation Structure
- **MULTI.md**: Project vision, requirements, and strategic decisions
- **CONF.md**: Current technical configuration and system state  
- **templates/**: Configuration file templates
- **scripts/**: Automation and setup scripts

