# DNS & Cloudflare Glossary
Date: January 5, 2026

## Subjects by Operational Order

### Names and Delegation
- **Zone**: Authoritative slice of DNS (e.g., `example.com`) served by specific NS records. It contains SOA, NS, and all records for that domain unless further delegated.
- **Zone apex**: Root of the zone (e.g., `example.com`). Cannot be a CNAME; use A/AAAA at the apex. When proxied in Cloudflare, apex A/AAAA answers map to Cloudflare anycast IPs (orange cloud) instead of the origin, keeping the origin hidden while remaining compliant with the no-CNAME-at-apex rule.
- **Subdomain**: Name beneath the apex (e.g., `www.example.com`, `api.example.com`). Can be CNAME or A/AAAA, depending on need.
- **Delegation**: Parent directs queries for a child zone to its nameservers via NS records. At the registrar, you set NS to Cloudflare’s values to delegate the entire domain to Cloudflare.
- **NS record**: Lists authoritative nameservers for a zone or delegated subdomain (e.g., `ns1.cloudflare.com`, `ns2.cloudflare.com`).
- **SOA (Start of Authority)**: Zone record defining primary NS, admin contact, and timing (refresh/retry/expire); usually managed by the DNS provider.
- **DNSSEC**: DNS Security Extensions sign RRsets with zone-signing keys so resolvers can validate authenticity. At Cloudflare, enable per zone; the registrar publishes DS (delegation signer) records that contain key digests pointing to the zone keys. Disable only with a clear rollback plan because removing DS without coordinating can break validation.
- **DS record**: Delegation signer published at the parent zone (registrar side). It advertises the digest of the child zone’s DNSSEC key, enabling validators to build a chain of trust. Update DS any time you roll DNSSEC keys.

### Addressing
- **A record**: Maps a hostname to an IPv4 address (e.g., `example.com -> 203.0.113.10`). Use at the apex; proxy if using Cloudflare.
- **AAAA record**: Maps a hostname to an IPv6 address. Optional; add if you serve IPv6.
- **CNAME**: Alias from one hostname to another (e.g., `www.example.com -> example.com`). Use for `www` pointing to apex; not allowed at the apex.
- **Wildcard `*`**: Catch-all for unmatched subdomains (e.g., `*.example.com`). Use cautiously; keep explicit apex/www records.
- **Stray host / subdomain coverage**: Using a wildcard (or explicit catch-all) ensures unplanned hostnames or subdomains still resolve and proxy through Cloudflare—e.g., someone types `blog.example.com` or `typo.example.com` when only `www.example.com` is published. This reduces origin exposure from typos or unpublished paths. Balance this against the risk of masking misconfigurations; monitor logs so unexpected hostnames are noticed and pruned when appropriate.

### Proxying and Origin
- **Proxy (edge/reverse proxy)**: A server that sits in front of your site, handling client requests and forwarding them to your origin. Benefits: hides origin IPs, offloads TLS, caching, and security filtering. In Cloudflare, the “orange cloud” switch enables the reverse proxy: DNS replies shift to Cloudflare anycast addresses, traffic is inspected (WAF), and TLS terminates at the edge before Cloudflare re-encrypts to the origin.
- **Reverse proxy**: Another term for an edge proxy that fronts origin servers (as opposed to a forward proxy used by clients). (Refs: Cloudflare reverse proxy overview: https://www.cloudflare.com/learning/cdn/glossary/reverse-proxy/ ; MDN reverse proxy: https://developer.mozilla.org/en-US/docs/Glossary/Reverse_proxy)
- **Origin**: The actual server hosting your site. In a proxied setup: client → Cloudflare → origin.
- **Cloudflare SSL/TLS mode (Full strict)**: Cloudflare validates your origin cert; requires a valid origin cert per domain.
- **Origin certificate**: Cloudflare-issued cert used only between Cloudflare and your origin (not publicly trusted). Store each domain’s cert/key securely on the origin with restricted permissions; reference those paths in the corresponding vhosts.
- **Edge TLS (visitor → Cloudflare)**: Cloudflare presents its edge certificate to browsers. Configure minimum TLS version (recommend 1.2+) and enable TLS 1.3 and modern ciphers to align with security baselines; ALPN negotiates HTTP/2/3 when supported.
- **Origin TLS (Cloudflare → origin)**: Cloudflare connects to the origin over HTTPS using the origin certificate. SNI is sent with the host so the correct vhost answers; ensure vhost cert paths match the SANs on the origin certificate.
- **TLS policy hygiene**: Keep edge TLS minimums at 1.2 or higher, avoid disabling SNI, and renew origin certificates before expiry to keep Full strict uninterrupted.
- **SNI (Server Name Indication)**: TLS extension that carries the requested hostname so the server (or Cloudflare) can pick the matching certificate and vhost. Required for virtually hosted origins; proxied traffic from Cloudflare includes SNI.
- **CDN (Content Delivery Network)**: Caches content at edge locations to reduce latency and origin load. Cloudflare’s proxy doubles as a CDN; cacheability depends on headers and plan features.

### HTTPS and Headers (Edge)
- **HTTPS redirect (edge)**: Rule at Cloudflare to force HTTP→HTTPS (e.g., Redirect Rule: Hostname equals apex/www → 301 to `https://{host}{uri}`).
- **Security headers (edge)**: Response header rules at Cloudflare for HSTS, X-Content-Type-Options, X-Frame-Options, Referrer-Policy.
- **HSTS (HTTP Strict Transport Security)**: Response header that tells browsers to use HTTPS only for a host (optionally subdomains) for a set `max-age`. Mitigates downgrade/mixed-content after first visit; risky if HTTPS later breaks. Preload lists embed HSTS in browsers and should be used only when HTTPS is permanent.

### Security Services (Edge)
- **WAF (Web Application Firewall)**: Cloudflare’s managed rule engine that inspects HTTP traffic at the edge. Use proxying to route traffic through the WAF; enable relevant managed rulesets (OWASP, CMS-specific), tune sensitivity to reduce false positives, and log events for review. Pair with rate limiting for brute-force mitigation.

## Basics (Quick Reference)
- **Domain name basics**: A domain name is a set of dot-separated labels (e.g., `example.com`). Each label may contain letters, digits, and hyphens, cannot start/end with a hyphen, and is ≤63 characters; the whole name must be ≤253 characters.
- **Registration vs DNS hosting**: You register a domain with a registrar (ownership). DNS hosting serves records via authoritative nameservers (could be the registrar, Cloudflare, Route53, etc.). Updating nameservers at the registrar hands DNS serving to your chosen provider.
- **TLD and SLD variants**: The top-level domain (TLD) is the rightmost label (`.com`, `.org`, country codes like `.uk`). Many ccTLDs use a second-level structure (e.g., `.co.uk`, `.com.au`, `.gov.uk`), so the registrable name might be `example.co.uk` where `example` is the SLD beneath that second-level TLD. Internationalized domain names (IDNs) allow non-English characters; in DNS they appear in Punycode (e.g., `xn--mnchen-3ya.de` for `münchen.de`).
- **Registered domain vs host**: The registrable domain (`example.com`, `example.co.uk`, `münchen.de`) is what you buy. Hosts (subdomains you publish) live under it: `www.example.com`, `api.example.com`, `blog.eu.example.co.uk`, `cdn.xn--mnchen-3ya.de` (Punycode host for `cdn.münchen.de`).
- **Subdomain and host**: Any label to the left of the registrable domain (`app.example.com`, `stage.api.example.com`). “Subdomain” names the label; the machine or service answering is the host.
- **Direct IP vs name**: You can reach an origin by IP (`https://203.0.113.10`), but names are needed for virtual hosting and TLS SNI; most browsers require the host header/SNI to serve the correct site.
- **Ports and schemes**: A URL may specify a port (`:8080`). Defaults are 80 for `http` and 443 for `https`. Example: `https://app.example.com:8443/status`.
- **HTTP vs HTTPS; SSL vs TLS**: `http` is cleartext; `https` is HTTP over TLS. SSL is the legacy predecessor; modern traffic should use TLS 1.2+ with valid certificates. Browsers and UIs may still say “SSL,” but configure TLS options. With Cloudflare proxy, visitors terminate TLS at Cloudflare; Cloudflare re-encrypts to the origin in Full (strict) mode.
- **FQDN (fully-qualified domain name)**: A complete domain ending at the TLD, optionally with a trailing dot (`www.example.com.`) to signal an absolute DNS name.
- **URL and components**: A URL is a URI that locates a resource, e.g., `https://www.example.com:8443/blog/index.html?page=2#section`. Components: scheme (`https`), host (`www.example.com`), optional port (`8443`), path (`/blog/index.html`), query (`?page=2`), fragment (`#section`).
- **Paths and gotchas**: Paths are case-sensitive on most origins (`/App` ≠ `/app`); trailing slashes can map to different resources (`/docs` vs `/docs/`). Reserved characters must be percent-encoded when part of a path segment: space → `%20` (or `+` in many form submissions), `#` → `%23`, `%` → `%25`, `?` → `%3F`, non-English characters become UTF-8 bytes then percent-encoded (e.g., `кот` → `%D0%BA%D0%BE%D1%82`).
- **Query string**: Key/value pairs after `?` (`?page=2&lang=en`). Order can matter for caching; avoid leaking secrets in queries.
- **Fragment**: Client-side reference after `#` (`#section`); not sent to the server.
- **Examples**: `example.com`; `www.example.com`; `api.example.com:443/v1/status`; `assets.cdn.example.co.uk`; `cdn.xn--mnchen-3ya.de/photos/%D0%BA%D0%BE%D1%82.jpg`.
- **Cloudflare’s role**: Cloudflare can be DNS host (authoritative NS), proxy/WAF/TLS edge (“orange cloud”), CDN, and for some domains the registrar; other providers can bundle similar roles. When proxied, DNS answers return Cloudflare anycast IPs while Cloudflare forwards to your origin.
- **WHATWG and MDN**: WHATWG maintains the browser URL parsing standard; MDN provides developer-friendly explanations and examples. Refer to them when you need exact parsing or encoding rules.

## Index (A–Z)
- A record → Addressing
- AAAA record → Addressing
- Apex (Zone apex) → Names and Delegation
- CNAME → Addressing
- Cloudflare SSL/TLS (Full strict) → Proxying and Origin
- CDN → Proxying and Origin
- DNSSEC → Names and Delegation
- DS record → Names and Delegation
- Delegation → Names and Delegation
- Edge TLS (visitor → Cloudflare) → Proxying and Origin
- WAF → Security Services (Edge)
- Origin TLS (Cloudflare → origin) → Proxying and Origin
- NS record → Names and Delegation
- Origin → Proxying and Origin
- Origin certificate → Proxying and Origin
- Proxy (orange cloud) → Proxying and Origin
- Reverse proxy → Proxying and Origin
- SNI → Proxying and Origin
- Security headers → HTTPS and Headers (Edge)
- HSTS → HTTPS and Headers (Edge)
- SOA → Names and Delegation
- Subdomain → Names and Delegation
- SSL/TLS/HTTPS → Basics (Quick Reference)
- WHATWG URL → Basics (Quick Reference)
- MDN URL reference → Basics (Quick Reference)
- URI → Basics (Quick Reference)
- URL → Basics (Quick Reference)
- TLS redirect (HTTPS redirect) → HTTPS and Headers (Edge)
- Zone → Names and Delegation
- Wildcard `*` → Addressing

## Reference Links
- DNS fundamentals: RFC 1034 (Domain Names), RFC 1035 (Domain Names Implementation).
- URI syntax: RFC 3986 (Uniform Resource Identifier).
- WHATWG URL Living Standard (browser URL parsing model): https://url.spec.whatwg.org/
- MDN URL reference: https://developer.mozilla.org/en-US/docs/Learn/Common_questions/Web_mechanics/What_is_a_URL
- Cloudflare DNS record guide (A/AAAA/CNAME/proxy behavior): https://developers.cloudflare.com/dns/manage-dns-records/reference/dns-records/
- Cloudflare reverse proxy overview: https://www.cloudflare.com/learning/cdn/glossary/reverse-proxy/
- Cloudflare SSL/TLS encryption modes (Full strict): https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full-strict/
- Cloudflare Origin CA certificates: https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/
- Cloudflare Redirect Rules / Always Use HTTPS: https://developers.cloudflare.com/rules/url-forwarding/
- Cloudflare Managed Transforms / security headers: https://developers.cloudflare.com/rules/transform/managed-transforms/reference/
- MDN reverse proxy glossary entry: https://developer.mozilla.org/en-US/docs/Glossary/Reverse_proxy
