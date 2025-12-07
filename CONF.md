# WordPress Multisite Configuration

## Introduction
Current multisite environment. Procedures and rationale in ConfigServers.md (origin runbook), CloudflareSettings.md (edge policy), and MULTI.md (architecture).

## Environment Snapshot
- Server: Ubuntu 24.04 on Vultr (hostname: laz24), IP `104.238.140.248`
- Web: Apache 2.4 (SSL module enabled)
- PHP: 8.3
- Database: MySQL 8.0.43, `wordpress_multisite` (user `wp_user`)
- WordPress: 6.8.3 at `/var/www/html/wordpress/`
- Primary domain: `alphaeos.net`
- Network admin email: `alphaeosnet@gmail.com`

## Multisite domains by blog_id
1: `alphaeos.net` (primary)
5: `avtranscript.com` (LIVE)
6: `recomp.one` (LIVE)
7: `talkdao.org` (testing)

## Standalone Installations
`zero.directory`: independent WordPress at `/var/www/html/zero.directory/` with its own vhost and origin certificate; not part of multisite network.

## Target Audience
System administrator with access to the origin host and Cloudflare zones.

December 7, 2025
