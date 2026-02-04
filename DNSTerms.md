# DNS & Cloudflare Glossary
Date: January 5, 2026

## Subjects by Operational Order

### Names and Delegation
This section defines DNS naming and delegation concepts and maps them to authoritative standards and Cloudflare terminology where that mapping matters.
- **Zone**: Authoritative slice of DNS (e.g., `example.com`) served by specific NS records. It contains SOA, NS, and all records for that domain unless further delegated. In Cloudflare's terminology, each domain added to an account is a zone, and many product settings are configured at the zone level. [1](#ref-1) [2](#ref-2) [11](#ref-11)
- **Apex domain (root/naked domain)**: The base registered name (for example `example.com`). This is also called root domain, naked domain, base domain, or primary domain in common usage. [1](#ref-1)
- **Zone apex**: Root of the zone (e.g., `example.com`). In Cloudflare terminology, the zone name is the apex domain. [11](#ref-11)
- **Zone apex record**: A DNS record at the zone apex. In Cloudflare, the record name is `@` for apex records. [12](#ref-12)
- **Subdomain**: Name beneath the apex (e.g., `www.example.com`, `api.example.com`). Can be CNAME or A/AAAA, depending on need; subdomains are not separate zones unless explicitly delegated. [2](#ref-2)
- **Delegation**: Parent directs queries for a child zone to its nameservers via NS records. At the registrar, you set NS to Cloudflare's values to delegate the entire domain to Cloudflare. [2](#ref-2)
- **NS record**: Lists authoritative nameservers for a zone or delegated subdomain (e.g., `ns1.cloudflare.com`, `ns2.cloudflare.com`). [2](#ref-2)
- **SOA (Start of Authority)**: Zone record defining primary NS, admin contact, and timing (refresh/retry/expire); usually managed by the DNS provider. [2](#ref-2)
- **DNSSEC**: DNS Security Extensions add data origin authentication and integrity to DNS data; they do not provide confidentiality. [3](#ref-3)
- **DS record**: Delegation signer published at the parent zone (registrar side). It advertises the digest of the child zone's DNSSEC key, enabling validators to build a chain of trust. [3](#ref-3)

### Addressing
These terms describe how DNS records map names to addresses and aliases.
- **A record**: Maps a hostname to an IPv4 address (e.g., `example.com -> 203.0.113.10`). Use at the apex; in Cloudflare, apex records use `@` as the record name; proxy if using Cloudflare. [13](#ref-13)
- **AAAA record**: Maps a hostname to an IPv6 address. Optional; add if you serve IPv6. [13](#ref-13)
- **CNAME**: Alias from one hostname to another (e.g., `www.example.com -> example.com`). Use for `www` pointing to apex; not allowed at the apex under standard DNS rules. [2](#ref-2) [13](#ref-13)
- **CNAME flattening (Cloudflare)**: Cloudflare can accept a CNAME at the zone apex and return the final IP address instead of a CNAME, which avoids the no-CNAME-at-apex limitation while remaining DNS-compatible at the resolver level. [14](#ref-14)
- **Wildcard `*`**: Catch-all for unmatched subdomains (e.g., `*.example.com`). Use cautiously; keep explicit apex/www records.
- **Stray host / subdomain coverage**: Using a wildcard (or explicit catch-all) ensures unplanned hostnames or subdomains still resolve and proxy through Cloudflare. Balance this against the risk of masking misconfigurations; monitor logs so unexpected hostnames are noticed and pruned when appropriate.

### DNS Privacy and Secure Transports
This section summarizes standards and vendor guidance for securing DNS transport between clients and resolvers.
- **DNS-over-TLS (DoT)**: DNS transported over TLS to protect queries and responses between client and resolver. [6](#ref-6) [27](#ref-27) [29](#ref-29)
- **DNS-over-HTTPS (DoH)**: DNS queries over HTTPS, mapping each DNS query-response pair into an HTTP exchange. [7](#ref-7) [27](#ref-27) [28](#ref-28)
- **Secure DNS transport guidance**: Google Public DNS documents DoT and DoH endpoints and operational considerations. Use these references as vendor examples of how secure DNS transport is deployed in practice. [27](#ref-27) [28](#ref-28) [29](#ref-29)

### Proxying and Origin
The terms below define how a reverse proxy fronts an origin and how Cloudflare's proxy status changes DNS behavior.
- **Proxy (edge/reverse proxy)**: A server that sits in front of your site, handling client requests and forwarding them to your origin. In Cloudflare, enabling the orange cloud turns on the reverse proxy so DNS replies shift to Cloudflare anycast addresses and the origin IP is not returned in DNS. [17](#ref-17) [24](#ref-24)
- **Reverse proxy**: Another term for an edge proxy that fronts origin servers (as opposed to a forward proxy used by clients). [24](#ref-24) [25](#ref-25)
- **Proxy status (Cloudflare)**: Only A, AAAA, and CNAME records can be proxied. Proxied (orange-clouded) records resolve to Cloudflare IPs; DNS-only records resolve to the origin IP and expose it. [15](#ref-15) [16](#ref-16) [17](#ref-17)
- **Origin**: The actual server hosting your site. In a proxied setup: client -> Cloudflare -> origin.
- **CDN (Content Delivery Network)**: Caches content at edge locations to reduce latency and origin load. Cloudflare's proxy doubles as a CDN; cacheability depends on headers and plan features.

### HTTPS, TLS, and Security Headers
These terms cover HTTPS, TLS versions, HSTS, and common security headers, with Cloudflare references where those controls are implemented at the edge.
- **HTTPS**: HTTP over TLS. HTTP semantics are standardized by the IETF, while TLS provides confidentiality and integrity for the transport. [8](#ref-8) [9](#ref-9)
- **TLS 1.3**: The current TLS protocol version, with improved security and performance compared to older versions. [8](#ref-8) [18](#ref-18)
- **SNI (Server Name Indication)**: TLS extension that carries the requested hostname so servers can select the correct certificate for name-based virtual hosts. [10](#ref-10)
- **Edge TLS (visitor to edge)**: TLS connection between the client and a proxy or CDN edge (for example, Cloudflare). [18](#ref-18)
- **Origin TLS (edge to origin)**: TLS connection between the proxy edge and the origin server, validated with the origin certificate when Full (strict) is enabled. [19](#ref-19) [20](#ref-20)
- **HSTS (HTTP Strict Transport Security)**: Response header that instructs clients to use HTTPS only for a host (optionally subdomains) for a set max-age. [5](#ref-5)
- **Security headers**: Headers such as HSTS, X-Content-Type-Options, X-Frame-Options, and Referrer-Policy that harden browser behavior. Cloudflare documents its managed security header transforms as a vendor reference. [22](#ref-22)
- **Cloudflare SSL/TLS mode (Full strict)**: Cloudflare validates the origin certificate; requires a valid origin cert per domain. [19](#ref-19)
- **Origin certificate**: Cloudflare-issued certificate used between Cloudflare and the origin (not publicly trusted). [20](#ref-20)
- **Redirect rules / URL forwarding**: Cloudflare URL forwarding rules can enforce HTTP to HTTPS or host canonicalization at the edge. [21](#ref-21)

### Apache Virtual Host Terminology
This section limits Apache terminology to domain and certificate routing concepts.
- **Apache `ServerName` / `ServerAlias`**: Apache uses hostnames in vhost configuration to decide which virtual host should answer a request. These names must exist in DNS and are matched against the Host header. [23](#ref-23)
- **Name-based virtual hosting**: Multiple sites share an IP and port; the Host header (and SNI for TLS) determines which vhost handles the request. [10](#ref-10) [23](#ref-23)

### Ubuntu Networking and Firewall Basics
These terms describe host-level networking and firewall controls for standard web traffic, including 80/443 exposure and access control.
- **Listener**: A local service bound to an IP and port that accepts inbound connections (for example, a web server listening on 80 or 443).
- **Ingress / egress**: Inbound traffic to the host vs outbound traffic from the host.
- **UFW (Uncomplicated Firewall)**: Ubuntu's default host firewall that manages netfilter rules with a simplified CLI. [26](#ref-26)
- **Stateful firewall**: A firewall that tracks connection state so return traffic for established connections is permitted without explicit rules.
- **Allowlist / denylist**: Rules that explicitly permit or block traffic by IP, port, or protocol; UFW exposes both patterns. [26](#ref-26)

## Basics (Quick Reference)
This section provides short definitions and reminders for frequent DNS and URL concepts.
- **Domain name basics**: A domain name is a set of dot-separated labels (e.g., `example.com`). In DNS wire format, each label is limited to 63 octets and the full name is limited to 255 octets. In presentation form, that limit is often expressed as 253 characters without the trailing dot; the trailing dot represents the root label and consumes one of the 255 octets. [2](#ref-2)
- **Registration vs DNS hosting**: You register a domain with a registrar (ownership). DNS hosting serves records via authoritative nameservers (could be the registrar, Cloudflare, Route53, etc.). Updating nameservers at the registrar hands DNS serving to your chosen provider.
- **TLD and SLD variants**: The top-level domain (TLD) is the rightmost label (`.com`, `.org`, country codes like `.uk`). Many ccTLDs use a second-level structure (e.g., `.co.uk`, `.com.au`, `.gov.uk`), so the registrable name might be `example.co.uk` where `example` is the SLD beneath that second-level TLD. Internationalized domain names (IDNs) allow non-English characters; in DNS they appear in Punycode (e.g., `xn--mnchen-3ya.de` for `muenchen.de`).
- **Registered domain vs host**: The registrable domain (`example.com`, `example.co.uk`) is what you buy. Hosts (subdomains you publish) live under it: `www.example.com`, `api.example.com`, `blog.eu.example.co.uk`.
- **Subdomain and host**: Any label to the left of the registrable domain (`app.example.com`, `stage.api.example.com`). Subdomain names the label; the host is the service answering that name.
- **Direct IP vs name**: You can reach an origin by IP (`https://203.0.113.10`), but names are needed for virtual hosting and TLS SNI; most browsers require the host header and SNI to serve the correct site.
- **Ports and schemes**: A URL may specify a port (`:8080`). Defaults are 80 for `http` and 443 for `https`.
- **HTTP vs HTTPS; SSL vs TLS**: `http` is cleartext; `https` is HTTP over TLS. SSL is the legacy predecessor; modern traffic should use TLS 1.2+ with valid certificates. Browsers and UIs may still say SSL, but configure TLS options. [8](#ref-8) [9](#ref-9)
- **FQDN (fully-qualified domain name)**: A complete domain ending at the TLD, optionally with a trailing dot (`www.example.com.`) to signal an absolute DNS name.
- **URL and components**: A URL is a URI that locates a resource, e.g., `https://www.example.com:8443/blog/index.html?page=2#section`. Components: scheme (`https`), host (`www.example.com`), optional port (`8443`), path (`/blog/index.html`), query (`?page=2`), fragment (`#section`). [4](#ref-4) [31](#ref-31)
- **Paths and gotchas**: Paths are case-sensitive on most origins (`/App` != `/app`); trailing slashes can map to different resources (`/docs` vs `/docs/`). Reserved characters must be percent-encoded when part of a path segment.
- **Query string**: Key/value pairs after `?` (`?page=2&lang=en`). Order can matter for caching; avoid leaking secrets in queries.
- **Fragment**: Client-side reference after `#` (`#section`); not sent to the server.
- **Examples**: `example.com`; `www.example.com`; `api.example.com:443/v1/status`; `assets.cdn.example.co.uk`.
- **Cloudflare's role**: Cloudflare can be DNS host (authoritative NS), proxy/WAF/TLS edge (orange cloud), CDN, and for some domains the registrar; other providers can bundle similar roles. When proxied, DNS answers return Cloudflare anycast IPs while Cloudflare forwards to your origin. [11](#ref-11) [17](#ref-17)
- **WHATWG and MDN**: WHATWG maintains the browser URL parsing standard; MDN provides developer-friendly explanations and examples. Refer to them when you need exact parsing or encoding rules. [30](#ref-30) [31](#ref-31)

## Index (A-Z)
Use the list below to jump from a term to the section where it is defined.
- A record -> Addressing
- AAAA record -> Addressing
- Apache ServerName / ServerAlias -> Apache Virtual Host Terminology
- Apex (Zone apex) -> Names and Delegation
- CNAME -> Addressing
- CNAME flattening -> Addressing
- Cloudflare SSL/TLS (Full strict) -> HTTPS, TLS, and Security Headers
- CDN -> Proxying and Origin
- Delegation -> Names and Delegation
- DNS-over-HTTPS (DoH) -> DNS Privacy and Secure Transports
- DNS-over-TLS (DoT) -> DNS Privacy and Secure Transports
- DNSSEC -> Names and Delegation
- DS record -> Names and Delegation
- Edge TLS -> HTTPS, TLS, and Security Headers
- HSTS -> HTTPS, TLS, and Security Headers
- HTTP/HTTPS -> HTTPS, TLS, and Security Headers
- NS record -> Names and Delegation
- Origin -> Proxying and Origin
- Origin certificate -> HTTPS, TLS, and Security Headers
- Origin TLS -> HTTPS, TLS, and Security Headers
- Proxy (orange cloud) -> Proxying and Origin
- Reverse proxy -> Proxying and Origin
- Security headers -> HTTPS, TLS, and Security Headers
- SNI -> HTTPS, TLS, and Security Headers
- SOA -> Names and Delegation
- Subdomain -> Names and Delegation
- TLS 1.3 -> HTTPS, TLS, and Security Headers
- UFW -> Ubuntu Networking and Firewall Basics
- URL -> Basics (Quick Reference)
- Zone -> Names and Delegation
- Wildcard `*` -> Addressing

## References
The references below provide authoritative definitions and product behavior details for the terms above. Inline citations in this file link back to these numbered entries.
1. <a id="ref-1"></a> [RFC 1034: Domain names - concepts and facilities](https://www.rfc-editor.org/rfc/rfc1034.html)
2. <a id="ref-2"></a> [RFC 1035: Domain names - implementation and specification](https://www.rfc-editor.org/rfc/rfc1035.html)
3. <a id="ref-3"></a> [RFC 4033: DNS Security Introduction and Requirements](https://www.rfc-editor.org/rfc/rfc4033.html)
4. <a id="ref-4"></a> [RFC 3986: Uniform Resource Identifier (URI)](https://www.rfc-editor.org/rfc/rfc3986.html)
5. <a id="ref-5"></a> [RFC 6797: HTTP Strict Transport Security (HSTS)](https://www.rfc-editor.org/rfc/rfc6797.html)
6. <a id="ref-6"></a> [RFC 7858: DNS over TLS](https://www.rfc-editor.org/rfc/rfc7858.html)
7. <a id="ref-7"></a> [RFC 8484: DNS Queries over HTTPS (DoH)](https://www.rfc-editor.org/rfc/rfc8484.html)
8. <a id="ref-8"></a> [RFC 8446: The Transport Layer Security (TLS) Protocol Version 1.3](https://www.rfc-editor.org/rfc/rfc8446.html)
9. <a id="ref-9"></a> [RFC 9110: HTTP Semantics](https://www.rfc-editor.org/rfc/rfc9110.html)
10. <a id="ref-10"></a> [RFC 6066: TLS Extensions (SNI)](https://www.rfc-editor.org/rfc/rfc6066.html)
11. <a id="ref-11"></a> [Cloudflare DNS concepts](https://developers.cloudflare.com/dns/concepts/)
12. <a id="ref-12"></a> [Cloudflare zone apex records (`@`)](https://developers.cloudflare.com/dns/manage-dns-records/how-to/create-zone-apex/)
13. <a id="ref-13"></a> [Cloudflare DNS record guide](https://developers.cloudflare.com/dns/manage-dns-records/reference/dns-records/)
14. <a id="ref-14"></a> [Cloudflare CNAME flattening](https://developers.cloudflare.com/dns/cname-flattening/)
15. <a id="ref-15"></a> [Cloudflare proxy status overview](https://developers.cloudflare.com/dns/proxy-status/)
16. <a id="ref-16"></a> [Cloudflare proxying limitations (proxy-eligible records)](https://developers.cloudflare.com/dns/proxy-status/limitations/)
17. <a id="ref-17"></a> [Cloudflare proxied vs DNS-only behavior](https://developers.cloudflare.com/dns/manage-dns-records/reference/proxied-dns-records/)
18. <a id="ref-18"></a> [Cloudflare TLS 1.3](https://developers.cloudflare.com/ssl/edge-certificates/additional-options/tls-13/)
19. <a id="ref-19"></a> [Cloudflare SSL/TLS Full (strict)](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full-strict/)
20. <a id="ref-20"></a> [Cloudflare Origin CA certificates](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/)
21. <a id="ref-21"></a> [Cloudflare URL forwarding / Redirect Rules](https://developers.cloudflare.com/rules/url-forwarding/)
22. <a id="ref-22"></a> [Cloudflare Managed Transforms: response security headers](https://developers.cloudflare.com/rules/transform/managed-transforms/reference/)
23. <a id="ref-23"></a> [Apache name-based virtual hosts](https://httpd.apache.org/docs/current/vhosts/name-based.html)
24. <a id="ref-24"></a> [Cloudflare reverse proxy overview](https://www.cloudflare.com/learning/cdn/glossary/reverse-proxy/)
25. <a id="ref-25"></a> [MDN reverse proxy glossary entry](https://developer.mozilla.org/en-US/docs/Glossary/Reverse_proxy)
26. <a id="ref-26"></a> [Ubuntu UFW documentation](https://help.ubuntu.com/community/UFW)
27. <a id="ref-27"></a> [Google Public DNS secure transports](https://developers.google.com/speed/public-dns/docs/secure-transports)
28. <a id="ref-28"></a> [Google Public DNS DNS-over-HTTPS (DoH)](https://developers.google.com/speed/public-dns/docs/doh/)
29. <a id="ref-29"></a> [Google Public DNS DNS-over-TLS (DoT)](https://developers.google.com/speed/public-dns/docs/dns-over-tls)
30. <a id="ref-30"></a> [WHATWG URL Living Standard](https://url.spec.whatwg.org/)
31. <a id="ref-31"></a> [MDN URL reference](https://developer.mozilla.org/en-US/docs/Learn/Common_questions/Web_mechanics/What_is_a_URL)
