# DNS & Cloudflare Glossary (Workflow-Oriented)

## Subjects by Workflow Order

### Names and Delegation
- **Zone**: Authoritative slice of DNS (e.g., `example.com`) served by specific NS records. It contains SOA, NS, and all records for that domain unless further delegated.
- **Zone apex**: Root of the zone (e.g., `example.com`). Cannot be a CNAME; use A/AAAA at the apex.
- **Subdomain**: Name beneath the apex (e.g., `www.example.com`, `api.example.com`). Can be CNAME or A/AAAA, depending on need.
- **Delegation**: Parent directs queries for a child zone to its nameservers via NS records. At the registrar, you set NS to Cloudflare’s values to delegate the entire domain to Cloudflare.
- **NS record**: Lists authoritative nameservers for a zone or delegated subdomain (e.g., `ns1.cloudflare.com`, `ns2.cloudflare.com`).
- **SOA (Start of Authority)**: Zone record defining primary NS, admin contact, and timing (refresh/retry/expire); usually managed by the DNS provider.

### Addressing
- **A record**: Maps a hostname to an IPv4 address (e.g., `example.com -> 203.0.113.10`). Use at the apex; proxy if using Cloudflare.
- **AAAA record**: Maps a hostname to an IPv6 address. Optional; add if you serve IPv6.
- **CNAME**: Alias from one hostname to another (e.g., `www.example.com -> example.com`). Use for `www` pointing to apex; not allowed at the apex.
- **Wildcard `*`**: Catch-all for unmatched subdomains (e.g., `*.example.com`). Use cautiously; keep explicit apex/www records.

### Proxying and Origin
- **Proxy (edge/reverse proxy)**: A server that sits in front of your site, handling client requests and forwarding them to your origin. Benefits: hides origin IPs, offloads TLS, caching, and security filtering. Cloudflare’s “orange cloud” is a reverse proxy.
- **Reverse proxy**: Another term for an edge proxy that fronts origin servers (as opposed to a forward proxy used by clients). (Refs: Cloudflare reverse proxy overview: https://www.cloudflare.com/learning/cdn/glossary/reverse-proxy/ ; MDN reverse proxy: https://developer.mozilla.org/en-US/docs/Glossary/Reverse_proxy)
- **Origin**: The actual server hosting your site. In a proxied setup: client → Cloudflare → origin.
- **Cloudflare SSL/TLS mode (Full strict)**: Cloudflare validates your origin cert; requires a valid origin cert per domain.
- **Origin certificate**: Cloudflare-issued cert used only between Cloudflare and your origin (not publicly trusted). Store each domain’s cert/key securely on the origin with restricted permissions; reference those paths in the corresponding vhosts.

### HTTPS and Headers (Edge)
- **HTTPS redirect (edge)**: Rule at Cloudflare to force HTTP→HTTPS (e.g., Redirect Rule: Hostname equals apex/www → 301 to `https://{host}{uri}`).
- **Security headers (edge)**: Response header rules at Cloudflare for HSTS, X-Content-Type-Options, X-Frame-Options, Referrer-Policy.

## Index (A–Z)
- A record → Addressing
- AAAA record → Addressing
- Apex (Zone apex) → Names and Delegation
- CNAME → Addressing
- Cloudflare SSL/TLS (Full strict) → Proxying and Origin
- Delegation → Names and Delegation
- NS record → Names and Delegation
- Origin → Proxying and Origin
- Origin certificate → Proxying and Origin
- Proxy (orange cloud) → Proxying and Origin
- Reverse proxy → Proxying and Origin
- Security headers → HTTPS and Headers (Edge)
- SOA → Names and Delegation
- Subdomain → Names and Delegation
- TLS redirect (HTTPS redirect) → HTTPS and Headers (Edge)
- Zone → Names and Delegation
- Wildcard `*` → Addressing

## Reference Links
- DNS fundamentals: RFC 1034 (Domain Names), RFC 1035 (Domain Names Implementation).
- Cloudflare DNS record guide (A/AAAA/CNAME/proxy behavior): https://developers.cloudflare.com/dns/manage-dns-records/reference/dns-records/
- Cloudflare reverse proxy overview: https://www.cloudflare.com/learning/cdn/glossary/reverse-proxy/
- Cloudflare SSL/TLS encryption modes (Full strict): https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full-strict/
- Cloudflare Origin CA certificates: https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/
- Cloudflare Redirect Rules / Always Use HTTPS: https://developers.cloudflare.com/rules/url-forwarding/
- Cloudflare Managed Transforms / security headers: https://developers.cloudflare.com/rules/transform/managed-transforms/reference/
- MDN reverse proxy glossary entry: https://developer.mozilla.org/en-US/docs/Glossary/Reverse_proxy
