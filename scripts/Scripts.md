# Script Interfaces and Configuration
Date: January 9, 2026

This document centralizes script interfaces, configuration expectations, environment variables, and defaults for `scripts/`. It is the interface contract for operators and automation. Each script prints authoritative help via `usage()`; when this document conflicts, update it to match script output. `scripts/Shell.md` covers Bash conventions and shared helpers.

## Structure and Audience

Audience: operators running scripts, automation authors relying on stable interfaces, and maintainers updating shared helpers. The layout supports quick entry without re-reading foundational material.

Operators start with Part A and Settings to see what to run and what to expect. Automation authors jump to Part B for interface guarantees. Maintainers use the cross-references to audit changes.

- **Conventions** define shared terminology, data sources, and structured output markers so later sections stay concise.
- **Part A: Script catalog** provides a high-level index by layer, grouped by purpose and sorted for quick discovery.
- **Settings** captures edge expectations that affect how check scripts interpret results.
- **Part B: Option and environment reference** documents shared conventions and the per-script interfaces.
- **Cross-references** list options and helper inclusion so changes can be audited quickly.
- **TODO** records deferred interface and behavior questions.

## Conventions
### Terminology alignment (domain, host, zone)

Terminology follows `DNSTerms.md`, and usage follows `Operations.md`. This keeps script output, CSV inventory fields, and Cloudflare API lookups unambiguous.

- **Domain**: The apex/registrable domain (`example.com`). In Cloudflare terms this is the **zone name** and is used for `--domain`, `zone_name`, and `CF_ZONE`.
- **Zone**: The Cloudflare zone object (identified by `zone_id`). When a script needs the zone identifier, it should use `zone_id`/`CF_ZONE_ID`.
- **Host**: A fully-qualified hostname (apex or subdomain), e.g., `www.example.com`. Use `HOST` only when the value is not necessarily the apex.

When outputting key/value pairs, use `DOMAIN` for the apex domain, `ZONE` for the Cloudflare zone name, `ZONE_ID` for the Cloudflare zone identifier, and `HOST` for FQDNs. Only use `DOMAINS` when the value is a list of apex domains.

### Interface and data format locations

Inputs and outputs live in a few focused places so updates stay consistent:

- **Command-line interfaces**: `scripts/Scripts.md` (this document) plus each script’s `usage()` output. `scripts/Options.csv` cross-references options by script.
- **Domain inventory (`domains.csv`)**: The header row in `domains.csv` is the schema, and `Record.md` is the authoritative policy for values and status transitions. `Plan.md` captures the design rationale for the schema and any planned expansions.
- **Cloudflare auth files (`.auth`)**: `scripts/example.auth` is the reference format; `scripts/Scripts.md` documents expected variables, defaults, and precedence rules.
- **Script output formats**: `scripts/Scripts.md` documents the unified output conventions for new and updated scripts. `scripts/Shell.md` documents the underlying log/error helpers.

### Output format (planned for structured scripts)

Unified output format supports human scanning and machine parsing. Each section begins with a strict marker, followed by `KEY=VALUE` lines and optional status lines. This allows easy parsing with `awk`, `rg`, or CSV/JSON post-processing without losing human readability.

Section marker:
```
== SECTION:Topic
```

Rules:
- `SECTION` is uppercase (`AUTH`, `CF`, `DNS`, `EDGE`, `SETTINGS`, `RULES`, `ZONE`, `CERT`, `FIREWALL`, `ORIGIN`, `SERVER`, `WP`, `ORCH`, `MCP`, `TEST`).
- `Topic` is UpperCamelCase without spaces (`Tls`, `DnsProxy`, `RedirectRule`).
- Section markers appear on their own line and are always prefixed with `==`.

Key/value lines:
```
DOMAIN=example.com
ZONE_ID=5e8ac20272ea8909c5d9be6e6f4fb7ac
```

Status lines (planned):
```
PASS key=value
INFO key=value
ERROR key=value
```

`ERROR` is reserved for failures; the distinction between fatal and non-fatal errors is handled by `err()` (exit) versus `fail()` (continue), as described in `scripts/Shell.md`.

Tables below list the **complete** set of `SECTION` values and expected `Topic` values for the current script arsenal. Helper libraries (`common.sh`, `cli.sh`, `auth.sh`) do not emit section markers.

#### SECTION values, scripts, and Topics

| SECTION | Scripts | Topics (expected values) |
| --- | --- | --- |
| `AUTH` | `verify-cf-auth.sh`, `check-auth.sh` | `AuthFile`, `Env`, `Token`, `Key`, `OriginCa`, `Domains`, `ZoneIds`, `Mismatches` |
| `CF` | `check-cf.sh` | `Zone`, `Dns`, `Settings`, `Api` |
| `DNS` | `cloud-dns.sh` | `Zone`, `Records`, `Proxy`, `Create` |
| `EDGE` | `check-edge.sh`, `cloud-redirect.sh` | `Dns`, `Https`, `RedirectRule`, `Headers` |
| `SETTINGS` | `cloud-settings.sh` | `ZoneSettings`, `Baseline` |
| `RULES` | `rules-cf.sh` | `Ruleset`, `Rule`, `Apply`, `Export` |
| `ZONE` | `onboard-zone.sh` | `Create`, `Dns`, `Record` |
| `CERT` | `get-cert.sh` | `OriginCa`, `Install`, `Verify` |
| `FIREWALL` | `cloudflare-ips.sh` | `IpList`, `UfwRules` |
| `ORIGIN` | `apache-vhost.sh`, `check-origin.sh` | `Apache`, `Modules`, `Vhosts`, `Tls`, `Php`, `Enable` |
| `SERVER` | `check-server.sh` | `Os`, `Updates`, `Ssh`, `Network`, `Ufw`, `Mysql`, `Redis`, `Cron` |
| `WP` | `setup-wp.sh`, `install-site.sh`, `check-wp.sh` | `Install`, `Site`, `Mapping`, `Root`, `Config`, `Routing`, `Security`, `Templates` |
| `ORCH` | `check-read.sh`, `test-record.sh`, `check-domain.sh` | `Selection`, `Run`, `Record`, `Results` |
| `MCP` | `mcp.sh`, `mcp-cf.sh` | `Server`, `Request`, `Response` |
| `INIT` | `perf-load.sh` | `Run`, `Domain` |
| `LOAD` | `perf-load.sh` | `Run`, `Domain` |
| `TEST` | `test_common.sh`, `test_cli.sh`, `test_cf.sh`, `test_mcp.sh` | `Setup`, `Cases`, `Results` |

#### Script-to-section mapping

Use this mapping when implementing or refactoring output so every script emits the expected section markers.

| Script | SECTION | Topics |
| --- | --- | --- |
| `verify-cf-auth.sh` | `AUTH` | `AuthFile`, `Env`, `Token`, `Key`, `OriginCa` |
| `check-auth.sh` | `AUTH` | `Domains`, `ZoneIds`, `Mismatches` |
| `check-cf.sh` | `CF` | `Zone`, `Dns`, `Settings`, `Api` |
| `cloud-dns.sh` | `DNS` | `Zone`, `Records`, `Proxy`, `Create` |
| `check-edge.sh` | `EDGE` | `Dns`, `Https`, `RedirectRule`, `Headers` |
| `cloud-redirect.sh` | `EDGE` | `RedirectRule` |
| `cloud-settings.sh` | `SETTINGS` | `ZoneSettings`, `Baseline` |
| `rules-cf.sh` | `RULES` | `Ruleset`, `Rule`, `Apply`, `Export` |
| `onboard-zone.sh` | `ZONE` | `Create`, `Dns`, `Record` |
| `get-cert.sh` | `CERT` | `OriginCa`, `Install`, `Verify` |
| `cloudflare-ips.sh` | `FIREWALL` | `IpList`, `UfwRules` |
| `apache-vhost.sh` | `ORIGIN` | `Vhosts`, `Enable`, `Tls` |
| `check-origin.sh` | `ORIGIN` | `Apache`, `Modules`, `Vhosts`, `Tls`, `Php` |
| `check-server.sh` | `SERVER` | `Os`, `Updates`, `Ssh`, `Network`, `Ufw`, `Mysql`, `Redis`, `Cron` |
| `setup-wp.sh` | `WP` | `Install`, `Config`, `Templates` |
| `install-site.sh` | `WP` | `Site`, `Mapping` |
| `check-wp.sh` | `WP` | `Root`, `Config`, `Routing`, `Security`, `Templates` |
| `check-read.sh` | `ORCH` | `Selection`, `Run`, `Results` |
| `test-record.sh` | `ORCH` | `Selection`, `Record`, `Results` |
| `check-domain.sh` | `ORCH` | `Selection`, `Run`, `Results` |
| `mcp.sh` | `MCP` | `Server`, `Request`, `Response` |
| `mcp-cf.sh` | `MCP` | `Server`, `Request`, `Response` |
| `perf-load.sh` | `INIT`, `LOAD` | `Run`, `Domain` |
| `test_common.sh` | `TEST` | `Setup`, `Cases`, `Results` |
| `test_cli.sh` | `TEST` | `Setup`, `Cases`, `Results` |
| `test_cf.sh` | `TEST` | `Setup`, `Cases`, `Results` |
| `test_mcp.sh` | `TEST` | `Setup`, `Cases`, `Results` |

## Part A: Script Catalog (by layer)

This catalog groups scripts by operational layer and marks each script as provisioning or verification/investigation. Full option and environment-variable details live in Part B.

### Cloudflare Layer

Cloudflare scripts handle credentials, DNS records, certificates, and edge validation. A typical flow starts with credential checks, provisions DNS inside an existing zone, then issues certificates, and ends with settings and edge validation. Zone creation is out of scope for these scripts and must be completed before DNS provisioning begins.

Verification (read-only), alphabetical:
- `check-auth.sh`
- `check-cf.sh`
- `check-edge.sh`
- `verify-cf-auth.sh`

Provisioning, alphabetical:
- `cloud-dns.sh`
- `cloud-redirect.sh`
- `cloud-settings.sh`
- `cloudflare-ips.sh` (firewall allowlist helper)
- `get-cert.sh`
- `onboard-zone.sh`
- `rules-cf.sh`

### Host Layer (Ubuntu and Base Services)

Host-level scripts report Ubuntu, Apache, PHP, and MySQL baselines. These checks are read-only and validate the hardening guidance in `HardenUbuntu.md` before or after origin configuration changes.

- `check-server.sh` — verification (read-only)

### Origin Layer (Apache and TLS)

Origin scripts configure or validate Apache vhosts and TLS wiring. Provisioning precedes verification.

- `apache-vhost.sh` — provisioning
- `check-origin.sh` — verification (read-only)

### WordPress Layer

WordPress scripts bootstrap or validate multisite configuration and mapping. Provisioning precedes verification.

- `setup-wp.sh` — provisioning
- `install-site.sh` — provisioning
- `check-wp.sh` — verification (read-only)

### Orchestration Layer

Orchestration scripts combine multiple checks in a single run.

- `test-record.sh` — verification + recording
- `check-domain.sh` — verification (read-only)

### Performance and Benchmarking

Performance scripts generate load or collect baseline measurements. They are read-only with respect to configuration but should be used carefully because they can saturate the origin.

- `perf-load.sh` — verification (read-only)

### Check Read

`check-read.sh` is a lightweight entry point for read-only validation across multiple domains. It standardizes syntax checks, unit tests, edge/DNS checks, server checks, and origin/WordPress checks without requiring operators to remember the underlying script order or domain selection details.

Needs and requirements follow so future changes can be evaluated against the same constraints.

Needs:
- A single entry point that can run `syn`, `unit`, `edge`, `dns`, `server`, `origin`, and `wp` in a predictable order.
- Domain selection driven by `domains.csv` or an explicit list of domains provided on the command line.
- Support for filtering by `status_cf` and `site_type` while avoiding `status_cf=ignore` and `status_cf=worker` plus `site_type=none`, `site_type=ignore`, and `site_type=worker` by default.

Requirements:
- Read-only behavior only; no API writes and no origin or WordPress mutations.
- Clear exit codes: syntax/unit failures should cause a non-zero exit, while edge/DNS checks should continue across domains.
- Consistent selection rules across all commands so a single invocation is trustworthy as a full read-only run.

Design notes:
- `check-read.sh` reads `domains.csv` once and applies filters only when explicit domains are not supplied.
- If no command list is provided, `check-read.sh` runs all commands in the order listed, so a default run is a full read-only pass.
- `edge` uses `check-edge.sh` (with `--api` when requested) and `dns` uses `check-cf.sh`.
- `server` uses `check-server.sh`, `origin` uses `check-origin.sh`, and `wp` uses `check-wp.sh`.
- `--auth-file` overrides the per-domain auth file from `domains.csv` for edge/DNS API calls.
- Server, Origin, and WordPress checks are read-only and depend on local filesystem access.
- Empty `site_type` values are normalized to `none`, and `site_type=none`, `site_type=ignore`, and `site_type=worker` are always skipped.

Implementation plan:
1) Parse commands and options; when no commands are supplied, run the full command set in order.
2) Load domain metadata when needed and select the domain set (explicit list or filtered list).
3) Execute each command in the requested order, collecting failures without aborting domain loops.
4) Return a non-zero status if any syntax or unit test fails.

### Support and Tests

Test scripts and helper libraries are intentionally minimal. They do not parse options and run directly from the `scripts/` directory.

- `test_common.sh`, `test_cli.sh`, `test_cf.sh` run unit checks for shared helpers.
- `common.sh`, `cli.sh`, `auth.sh` provide shared logic and should not be executed directly.

## Settings

This section lists the Cloudflare and edge behaviors validated by read-only checks. Use it to interpret script output while keeping `usage()` authoritative.

Prereqs: the zone is active in Cloudflare, nameservers point to Cloudflare, and scripts can read a valid auth file with the required credentials and `CF_ZONE_ID` or `CF_ZONE`.

### DNS and Proxy

Edge checks assume Cloudflare proxies the apex and `www` hostnames. DNS must exist and be proxied before HTTPS or header checks behave as expected.

- Apex: an **A** record for `@` pointing to the origin IPv4 address, with the proxy (orange cloud) enabled.
- `www`: a **CNAME** to the apex. If CNAME flattening hides the CNAME, an **A** record for `www` is acceptable and will be treated as valid by `check-edge.sh`.
- Optional: a wildcard `*` CNAME to the apex when you want Cloudflare to catch stray hostnames.

### Redirect Behavior

`check-edge.sh` validates canonical redirects and will fail if the redirect targets do not match the expected behavior. Redirect-only domains use `redirect_url` from `domains.csv` and skip HTTPS and API checks.

- Standard sites: `http://apex` should 301 to `https://apex`, and `https://www` should 301 to `https://apex`.
- Redirect-only sites: use a Cloudflare Redirect Rule that applies to all incoming requests and points to the configured `redirect_url`.

### SSL/TLS Mode

`check-edge.sh --api` requires SSL mode **Full (strict)**. This is a Cloudflare zone setting and is validated via the API.

- Path: `SSL/TLS` → `Overview` → set “SSL/TLS encryption mode” to **Full (strict)**.

Redirect-only zones skip HTTPS and API checks, so they can remain on Cloudflare’s default **Flexible** mode when a Redirect Rule is the only intended behavior. If you want redirect zones to fail closed when a rule is removed or misconfigured, use **Full (strict)** with a valid origin certificate so the fallback path stays protected.

### Edge HTTPS Features

The redirect expectations rely on Always Use HTTPS being enabled for standard WordPress sites.

- Path: `SSL/TLS` → `Edge Certificates` → enable “Always Use HTTPS”.
- HSTS is optional by default; if `--hsts=true` is supplied to `check-edge.sh`, the script will require the `strict-transport-security` header.

### Response Headers

`check-edge.sh` requires several security headers on the HTTPS apex response. Provide them at the origin or via Cloudflare managed headers.

- Required headers: `x-content-type-options`, `x-frame-options`, `referrer-policy`.
- Optional headers (warn only): `x-xss-protection`, `expect-ct`.
- Path (Cloudflare managed headers): `Rules` → `Settings` → `Managed Transforms` → `HTTP Response Headers` → “Add security headers”.

### WordPress Markers

For non-redirect domains, `check-edge.sh` fetches HTML and expects WordPress markers (`/wp-content` or `/wp-includes`). Cloudflare Pages or Workers sites will not satisfy this check; set `site_type=worker` (and `status_cf=worker` once validated) so they are skipped unless explicitly included.

### API-Visible Settings (check-cf)

`check-cf.sh` prints the full Cloudflare settings map and DNS records. It only enforces values when `-e key=value` is supplied. The settings most commonly enforced alongside edge checks include:

- `--ssl=strict`
- `always_use_https=on`
- `min_tls_version=1.2`
- `managed_add_security_headers=true`
- `leaked_credential_checks=false`

When you need to apply the baseline across many zones, use `cloud-settings.sh`. It reads `domains.csv` to select domains, queries current values before writing, and applies settings through the Cloudflare API. This keeps the baseline consistent without modifying DNS records or redirect rules, but it still requires edit-capable credentials and an active zone for each domain.

## Part B: Option and Environment Reference

This section documents shared conventions and per-script interfaces. It is the authoritative reference for option and environment variable behavior; helper implementation details live in `scripts/Shell.md`.

### Shared Option and Environment Conventions

Shared options are expressed as long options only. Scripts use `--help` for help; the short `-h` option is intentionally not supported to keep parsing consistent across scripts. Standard names are `SSL_DIR`, `APACHE_DIR`, and `WORDPRESS_ROOT`, and the template option is `--template` (avoid legacy names such as `--temp`). Option lists below include the leading `--` to mirror the CLI syntax.

Configuration priority (lowest to highest):
- Code defaults
- Auth file values
- Environment variables
- CLI options

When `usage()` lists an option, it follows a consistent format:

```
--http-timeout SECONDS [HTTP_TIMEOUT] (default: 10)  HTTP timeout for curl
```

This format shows option, related environment variable, and default on one line. Option lists follow a consistent order to reduce scanning time.

Option ordering:
- Script-specific options first.
- Auth options second (when present).
- Root and SSL path options next.
- Common privilege options next.
- `--help` always last.
If a script does not use a category, omit it but preserve the relative order of the remaining categories.

List handling:
- Comma-separated lists are split on commas, whitespace is trimmed around each token, and empty tokens are treated as failures.

### Boolean handling

Boolean settings are parsed and normalized to keep behavior consistent across scripts.

- Parse boolean values from environment or auth files with `parse_bool` (from `common.sh`) and normalize to `true|false`.
- Accept `true|false` and `yes|no|y|n` (case-insensitive). Reject anything else.
- Treat empty or unset values as “use default.” Do not treat empty as implicit true or false.
- For boolean CLI options that mirror env/auth settings, prefer value-style `name=true|false` instead of bare toggles.
- Do not enumerate accepted tokens in `usage()`; only show priority and default (for example: `--hsts=true|false [HSTS_REQUIRED] (default: false)`).
- Apply standard precedence: code defaults (lowest), then auth files, then environment, then CLI options (highest).
- If `parse_bool` fails, emit a concise error and exit non-zero.
- Do not add new dependencies to scripts that are intentionally self-contained.

### Shared Options and Environment Variables

The following options and environment variables are shared across multiple scripts. This section documents each option once, then the per-script sections below reference the applicable subset.

#### Privilege and execution controls

These options influence how scripts invoke privileged commands. They do not change functional behavior, but they can affect whether a script can read or write protected files.

- `--allow-root` bypasses the root guard for scripts that call `cli_require_non_root`. It should only be used for constrained environments where running as root is unavoidable.
- `--no-sudo [SUDO_BIN] (default: sudo)` sets `SUDO_BIN` to an empty string. The `priv()` helper will run commands directly as the current user instead of invoking `sudo`.
- `SUDO_BIN` (env) controls the privilege wrapper globally. Use an empty value to disable `sudo` while keeping the `priv()` call pattern intact.

#### WordPress root

These options and environment variables control where WordPress is located on disk.

- `--wp-root PATH [WORDPRESS_ROOT] (default: /var/www/html/wordpress)` sets the WordPress root path for scripts that operate on the WordPress filesystem or run WP-CLI.
- `WORDPRESS_ROOT` (env) provides the default WordPress root if the `--wp-root` option is not supplied.
For singlesite domains with an empty `wp_root` in `domains.csv`, the read-only and recording orchestrators default to `/var/www/html/<domain>` unless `--wp-root` is explicitly supplied.

#### Templates

WordPress configuration and `.htaccess` templates are selected by site type (`--singlesite` or `--multisite`). The templates in `templates/` are the authoritative baseline for deployments and checks.

- `TEMPLATE_DIR` (env) sets the template directory for WordPress and Apache templates; the default is `templates/` under the repository root.
- `--template-dir DIR [TEMPLATE_DIR]` overrides the template directory for scripts that read WordPress templates.
Naming conventions:
- `templates/wp-config-<site_type>.php` is the base template.
- `templates/htaccess-<site_type>` is the base `.htaccess` template.

#### Domain selection

Domain-oriented scripts accept domains via `--domain` (repeatable). Positional domains are still accepted for compatibility, and scripts normalize, validate, and de-duplicate the final list before execution.

- `--domain NAME` adds a domain to the list of domains to process.
Notes:
- Option parsing consumes known options only; any remaining arguments are treated as positional domains. A literal `--` is treated as a domain token and will fail validation.
- Domains are normalized (lowercased and trimmed) before validation and de-duplication.

#### Inventory file path

Scripts that operate on the domain inventory allow the CSV path to be overridden for testing, staging, or alternate inventories.

- `--domains-file PATH [DOMAINS_FILE]` sets the inventory CSV path (default: `domains.csv` in the repo root).
- `DOMAINS_FILE` (env) provides the default inventory path when `--domains-file` is not supplied.

Redirect-only domains:
Redirect-only domains are managed with a single source of truth so validation scripts can distinguish “edge-only” domains from full origin-backed sites. Even though redirect domains are now configured with the same HTTPS and security baseline as singlesite and multisite zones, the current edge validation still skips HTTPS and API checks for redirect-only domains, so use `check-cf.sh` when you need to confirm zone settings.

Status (current behavior):
- Redirect-only domains are derived from `domains.csv` (`site_type=redirect`) and loaded by `load_dns_redirects`.
- `check-origin.sh` and `check-wp.sh` skip origin/WP checks for redirect-only domains and treat absence as expected.
- `check-edge.sh` validates DNS and HTTP redirect behavior for redirect-only domains but skips HTTPS and Cloudflare API checks.
 - `redirect_url` alone does not imply redirect intent; `site_type=redirect` must be set explicitly.

Next steps:
- Add redirect-focused provisioning support to `cloud-dns.sh` (for example, record patterns or options suitable for edge-only redirect zones).

Examples:
- `check-edge.sh example.com www.example.com`
- `cloud-dns.sh example.com 203.0.113.10`

Status columns:
The `status_*` columns in `domains.csv` record the latest confirmed stage for each layer. The value `none` means no tests for that layer have passed yet, and `status_cf=added` means the zone exists but is not yet active. These values are for filtering and reporting, not authoritative configuration, and `status_cf=worker` is skipped by default filters unless explicitly included. In practice, `status_cf=https` confirms the standard edge checks for a full HTTPS site, while `status_cf=redirect` confirms redirect-only edge behavior. For the origin layer, the implemented check group maps to `status_origin=apache` when `check-origin.sh` succeeds. For WordPress, `check-wp.sh` validates installation and configuration; a separate load test is required before recording `status_wp=load`, so that value should remain unused until such a test exists.

Site type handling:
The `site_type` column captures intent rather than validation. Empty values normalize to `none`, and `site_type=none`, `site_type=ignore`, and `site_type=worker` are explicit skip markers in `check-read.sh` and `test-record.sh`. If a domain needs validation or provisioning, set `site_type` to an explicit intent such as `--singlesite`, `--multisite`, or `redirect`.
WordPress mode selection is separate from `site_type` and uses the `--singlesite`, `--multisite`, and `--autosite` options; there is no `site` option.

Alignment between intent and status:
When a redirect or worker configuration is fully in place, `status_cf` should mirror the intent (`status_cf=redirect` for `site_type=redirect`, and `status_cf=worker` for `site_type=worker`). When `site_type=ignore` is set, `status_cf` can retain the last confirmed value or remain at `added` without affecting automation, because the ignore intent is treated as a global skip.

#### Record controls

Scripts that update `domains.csv` support consistent controls so automation can choose whether to write or preserve existing status values. The design and open questions are documented in `Record.md`.

- `--norecord` skips updating `domains.csv` without changing the operational checks or provisioning actions.
- `--downgrade` allows status updates that would normally be blocked by the default “no downgrade” policy (for example, switching between redirect and https status for a domain).
- `--date TS [DATASTORE_DATE]` overrides the backup timestamp used when snapshotting `domains.csv` (format: `YYYYmmdd_HHMMSS`).

#### IP address inputs

IP address inputs show up in three distinct places, and keeping their names and roles separate avoids confusing inventory data with runtime parameters.

- Inventory column: `domains.csv` uses `--ip` to record the origin IPv4 address as inventory data.
- Provisioning argument: `cloud-dns.sh` accepts a positional `<ip>` argument and does not provide an option flag for it.
- Onboarding option: `onboard-zone.sh` uses `--ip` (and env `IP`) as the canonical interface, defaulting to `104.238.140.248` when no CLI, env, or CSV value exists.

#### SSL directory and certificate paths

These options define where origin certificates and keys are stored. Scripts that read or write certificates use these paths.

- `--ssl-dir DIR [SSL_DIR] (default: /etc/ssl/cloudflare-origin)` sets the SSL directory and implicitly sets the cert/key subdirectories.
- `SSL_DIR` (env) defines the base directory for origin certificates.
- `SSL_CERT_DIR` (env) defaults to `${SSL_DIR}/certs`.
- `SSL_KEY_DIR` (env) defaults to `${SSL_DIR}/keys`.

Commentary:
- `SSL_DIR` is the single source of truth for where origin material is stored, and scripts derive `SSL_CERT_DIR` and `SSL_KEY_DIR` from it unless you explicitly override them. This keeps file layout consistent across `get-cert.sh`, `apache-vhost.sh`, and checks that read certificates.
- Use explicit `SSL_CERT_DIR` and `SSL_KEY_DIR` only when a host requires a nonstandard directory layout; otherwise keep them derived so scripts remain aligned.

#### Apache sites directory

Scripts that inspect or write vhost files use a shared Apache sites directory setting.

- `--apache-dir DIR [APACHE_DIR] (default: /etc/apache2/sites-available)` sets the Apache sites directory with highest priority.
- `APACHE_DIR` (env) defines the default Apache sites directory.

#### HTTP timeouts

HTTP-oriented scripts use a shared timeout for curl requests.

- `--http-timeout SECONDS [HTTP_TIMEOUT] (default: 10)` controls connect and total timeouts for curl in edge checks.
- `HTTP_TIMEOUT` (env) provides the default timeout value.

#### Cloudflare authentication

Cloudflare API scripts accept multiple credential types, each suited to a specific scope.

Auth file conventions:
- Default `CF_AUTH_FILE` is `~/.config/cloudflare/default.auth`.
- Example format: `scripts/example.auth` (values intentionally blank).
- The project expects `.auth` extensions for files under `~/.config/cloudflare/`.
- `CF_DOMAINS` is a comma-separated list of domains managed by the account in this auth file.

Auth variables:
- `CF_API_TOKEN` (account API token, account-scoped)
- `CF_API_KEY` + `CF_API_EMAIL` (global API key, user-scoped)
- `CF_CA_KEY` (Origin CA User Service Key, user-scoped)
- `CF_ACCOUNT_ID` (account identifier)
- `CF_ACCOUNT_NAME` (account name for name-to-ID lookup)
- `CF_DOMAINS` (comma-separated list of account domains; inventory alignment)
- `CF_AUTH` (`auto`, `token`, or `key`) selects the credential type (default: `auto`)
- CLI-supplied values are stored in `*_CLI` variables (for example, `CF_API_TOKEN_CLI`) before being applied as the highest-priority values.

Commentary:
- `CF_API_TOKEN`, `CF_API_KEY`, and `CF_CA_KEY` are secrets. They should only exist in local auth files or environment variables and must never be committed.
- `CF_ACCOUNT_ID`, `CF_ACCOUNT_NAME`, `CF_DOMAINS`, and `CF_ZONE` are metadata rather than secrets, but they still represent account structure and are sensitive operational data.

Common auth arguments: --auth, --auth-file, --account, --account-name, --token, --key, --email, --ca-key.

Cloudflare zone selection:
- `--zone name [CF_ZONE]` sets the target zone name (used by `check-cf.sh`, `check-edge.sh`).
- `--zone-id id [CF_ZONE_ID]` sets the target zone ID (used by `check-cf.sh`, `check-edge.sh`, `verify-cf-auth.sh`).
- `CF_ZONE_MAIN` (env) is informational only; scripts do not select a zone based on this value.
- `CF_ZONE` and `CF_ZONE_ID` (env) are read from the auth file when explicitly set; scripts do not choose a default when multiple zone pairs exist.
Notes:
- `CF_ZONE` must be an apex (for example, `example.com`, not `www.example.com`); auth files may list multiple `CF_ZONE_ID` values and retain the list in `CF_ZONE_IDS` (comma-separated).
- When both `CF_ZONE_ID` and `CF_ZONE` are set, scripts use `CF_ZONE_ID` and log a warning noting the choice.
- When both `CF_ACCOUNT_ID` and `CF_ACCOUNT_NAME` are set, scripts use `CF_ACCOUNT_ID` and log a warning noting the choice.
- When `CF_AUTH=auto` and both token and key credentials are present, scripts use the key and log a warning noting the choice.

Domain resolution priority (policy):
Resolution order is: auth file match by zone name, then `domains.csv` `zone_id`, then API lookup. This keeps ad-hoc overrides possible, but it also risks masking stale auth-file entries or cross-account drift if the `.auth` file lists zones not present in the inventory. The policy conclusion is: treat `domains.csv` as the canonical inventory for batch runs, allow auth-file overrides for ad-hoc checks, and treat API lookup as a last resort. Orchestrators should not auto-discover zones outside the inventory. Use `check-auth.sh check-ids` to surface mismatches early.

### Knowledge

This section summarizes Cloudflare APIs used for each operation and expected credential behavior. It reflects current scripts and observed repo behavior and reduces confusion when a token succeeds for one endpoint but fails for another.

Read-only checks:
- `check-cf.sh` and `check-edge.sh --api` call zone settings and DNS read endpoints. These work with an account API token (preferred) or the global API key + email. Use the least-privileged token that grants zone read for settings and DNS.
- `verify-cf-auth.sh` validates credentials against account or user endpoints. It can use either token or global key.

Provisioning and write operations:
- `cloud-dns.sh` creates or updates DNS records. It requires DNS edit access for the zone. An account token with Zone DNS Edit scope is preferred, but the global API key works when the token lacks permissions.
- Redirect Rules use the Rulesets API (`http_request_dynamic_redirect`). A token must include Rulesets Edit on the zone; otherwise use the global API key.
- Page Rules are a legacy API (`/pagerules`). Account tokens do not work on this endpoint; you must use the global API key + email for Page Rules read or write.
- Origin CA certificate requests (`get-cert.sh --api`) require `CF_CA_KEY` (Origin CA User Service Key). Token/key credentials do not apply to Origin CA requests in this tooling.
- The Origin CA key is not valid for standard zone endpoints (for example, `/zones`, `/settings`, or `/dns_records`) and will return auth errors; use token or global key for those APIs.

Practical guidance:
- Prefer account API tokens for regular read/write operations and scope them to the minimal required permissions.
- Use the global API key only for Page Rules or when a token is missing the required scope.
- When a call fails with “Authentication error,” verify the required scope for that endpoint before assuming the zone ID or account is wrong.

### Read-Only Scripts and Safe Options

The following scripts are read-only by design and do not modify DNS, certificates, Apache configuration, or WordPress data. Read-only scripts: `check-edge.sh`, `check-cf.sh`, `verify-cf-auth.sh`, `check-auth.sh`, `check-server.sh`, `check-origin.sh`, `check-wp.sh`, `perf-load.sh`, `check-domain.sh`. Unit tests: `test_common.sh`, `test_cli.sh`, `test_cf.sh`.

Safe options for read-only scripts:
- `--api` (enables Cloudflare API reads; no writes)
- `--hsts=true|false` (changes validation expectations only)
- `--http-timeout SECONDS`
- `--domain NAME` / positional domains
- `--zone-id ID`
- `--auth token|key|auto`, `--auth-file PATH`, `--token TOKEN`, `--key KEY`, `--email EMAIL`, `--ca-key KEY`
- `--allow-root`, `--no-sudo`

### Cloudflare Layer Interfaces

#### verify-cf-auth.sh (verification/investigation)

Purpose:
- Validates Cloudflare credentials and reports which credentials are valid.

Arguments:
- None.

Options (script-specific):
- `--zone-id ID [CF_ZONE_ID]` supplies a zone ID for Origin CA key validation.

Common arguments: --auth, --auth-file, --account, --token, --key, --email, --ca-key, --help.

Environment variables:
Cloudflare auth variables listed in `auth.sh`.

Notes:
- Account API tokens are verified against the account endpoint when `CF_ACCOUNT_ID` is available.
- Global API keys are verified with X-Auth-Email + X-Auth-Key against `/user`.
- Origin CA keys are verified with a read-only GET to `/certificates?zone_id=...`. If `CF_ZONE_ID` is missing but `CF_ZONE` is present, the script will attempt to resolve the zone ID using available API credentials.

#### check-auth.sh (verification/investigation)

Purpose:
- Compares `CF_DOMAINS` from an auth file to the domains listed in `domains.csv`, highlighting mismatches.

Arguments:
- None.

Options (script-specific):
- `--check-ids` compares zone IDs across auth file, domains.csv, and API (requires credentials).

Common arguments: --auth-file, --domains-file, --help.

Environment variables:
`CF_AUTH_FILE`, `DOMAINS_FILE`.

Notes:
- If `domains.csv` contains multiple `auth_file` values, provide `--auth-file` so the comparison is scoped correctly.
- If `CF_DOMAINS` is empty, the script falls back to `CF_ZONE` entries in the auth file.
- The script exits non-zero when mismatches are found; with `--check-ids`, it still reports ID mismatches before exiting.

#### cloud-dns.sh (production/installation)

Purpose:
- Creates or updates DNS records inside an existing Cloudflare zone, including an apex A record plus CNAMEs for `www` and `*` pointing to the apex.

Arguments:
- `<domain> <ip>` where `--domain` is the zone and the IP address is the origin IPv4. Use `--domain` to provide the domain via an option.

Options (script-specific):
 - `--domain NAME`
 - `--create` only creates DNS records; errors if a record already exists.
 - `--update` only updates existing DNS records; errors if a record is missing.

Common arguments: --auth, --auth-file, --account, --token, --key, --email, --help.

Environment variables:
`CF_ACCOUNT_ID`, `CF_API_TOKEN`, `CF_API_KEY`, `CF_API_EMAIL`.

Notes:
- When `--domain` is provided, positional arguments supply `<ip>` only.
- By default, DNS records are created or updated to avoid duplicates.
- If the zone does not exist in the target account, the script creates it; otherwise it reuses the existing zone.
- IPv4 must be publicly routable; RFC1918, link-local, loopback, and multicast ranges are rejected.
- IPv4 addresses ending in `.0` or `.255` are accepted but produce a warning to prompt verification.
- `warn()` is used for non-fatal conditions; `fail()` reports a non-fatal check failure while allowing the script to continue; `err()` emits a fatal error and exits non-zero when a required condition fails. In `cloud-dns.sh`, duplicate A records are fatal while duplicate CNAME records emit a warning.
- Planned: support marking zones as redirect-only (from `domains.csv`) so cloud-dns can provision redirect-focused DNS without origin dependencies.

#### cloud-redirect.sh (production/installation)

Purpose:
- Ensures Cloudflare Redirect Rules exist for one or more domains using the Rulesets API (http_request_dynamic_redirect phase).

Arguments:
- One or more domain names, provided positionally or via `--domain` (repeatable).

Options (script-specific):
 - `--domain NAME`
 - `--redirect-url URL [REDIRECT_URL]` sets the redirect target (defaults to `redirect_url` in `domains.csv`).
 - `--domains-file PATH [DOMAINS_FILE]`
 - `--dry-run` prints planned changes without API writes.
 - `--date TS [DATASTORE_DATE]`
 - `--norecord`
 - `--downgrade`

Common arguments: --auth, --auth-file, --account, --account-name, --token, --key, --email, --help.

Environment variables:
`REDIRECT_URL`, `DOMAINS_FILE`, plus Cloudflare auth variables from `auth.sh`.

Notes:
- If no domains are provided, this script uses redirect domains from `domains.csv`.
- Redirect rules are updated to a single static redirect rule when needed, while removing custom per-domain rules.
- When recording is enabled, `status_cf=redirect` and `redirect_url` are updated for redirect-only domains.
- Domains with `site_type=none`, `site_type=ignore`, or `site_type=worker` are skipped entirely.
- Zone IDs are resolved in priority order: auth file match (by zone name), then `domains.csv` (`zone_id`), then API lookup.

#### rules-cf.sh (production/installation)

Purpose:
- Exports Cloudflare firewall rules from a single zone into a portable JSON file, or applies a rules file to explicitly selected zones.

Arguments:
- None. Domains are supplied via `--source` (export) or `--domain` (apply).

Options (script-specific):
 - `--export` selects export mode (default).
 - `--apply` applies rules from a JSON file to target zones.
 - `--source NAME` sets the export source zone apex.
 - `--output PATH` sets the export output path (default: `rules.<domain>.json`).
 - `--input PATH` sets the rules file to apply (default: `rules.<domain>.json`, using the first target domain).
 - `--domain NAME` adds a target zone (repeatable; apply mode).
 - `--all` includes disabled rules in the export.
 - `--allow-redirects` allows apply operations for redirect-only domains.

Common arguments: --auth, --auth-file, --token, --key, --email, --help.

Environment variables:
Cloudflare auth variables listed in `auth.sh`.

Notes:
- Export strips rule IDs and zone-specific metadata so files remain portable.
- Apply replaces the entire ruleset for the target zone; there is no merge behavior.
- The rules file may retain a `phase` value; if missing, the script uses `http_request_firewall_custom`.
- Applying rules to redirect-only domains requires `--allow-redirects` so the intent is explicit.
- Zone IDs are resolved in priority order: auth file match (by zone name), then `domains.csv` (`zone_id`), then API lookup.

#### cloud-settings.sh (production/installation)

Purpose: Applies the Cloudflare HTTPS and security baseline (SSL mode, HTTPS enforcement, minimum TLS version, and managed headers) across one or more zones.

Arguments:
- One or more domain names, provided positionally or via `--domain` (repeatable).

Options (script-specific):
 - `--domain NAME`
 - `--domains-file PATH [DOMAINS_FILE]`
 - `--site-types LIST [SITE_TYPES_RAW]` selects domains by `site_type` when no explicit domains are provided (default: `redirect,multisite`).
 - `--ssl MODE [CF_SSL_MODE]` sets the Cloudflare SSL mode (`off`, `flexible`, `full`, `strict`).
 - `--always-use-https MODE [CF_ALWAYS_USE_HTTPS]` toggles Always Use HTTPS (`on` or `off`).
 - `--min-tls-version VER [CF_MIN_TLS_VERSION]` sets the minimum TLS version (`1.0`, `1.1`, `1.2`, `1.3`).
 - `--managed-add-security-headers BOOL [CF_MANAGED_ADD_SECURITY_HEADERS]` toggles the managed “Add security headers” transform (`true` or `false`).
 - `--dry-run` prints planned changes without API writes.

Common arguments: --auth, --auth-file, --account, --account-name, --token, --key, --email, --help.

Environment variables:
`DOMAINS_FILE`, `SITE_TYPES_RAW`, `CF_SSL_MODE`, `CF_ALWAYS_USE_HTTPS`, `CF_MIN_TLS_VERSION`, `CF_MANAGED_ADD_SECURITY_HEADERS`, plus Cloudflare auth variables from `auth.sh`.

Notes:
- Zone IDs are resolved in priority order: auth file match (by zone name), then `domains.csv` (`zone_id`), then API lookup.
- DNS records and redirect rules are not modified; use `cloud-dns.sh` and `cloud-redirect.sh` for those changes.

#### onboard-zone.sh (production/installation)

Purpose: Creates or ensures a Cloudflare zone exists, provisions the baseline DNS records, and records the zone metadata back into `domains.csv` for inventory tracking.

Arguments:
- One or more domain names, provided positionally or via `--domain` (repeatable).
- `<ip>` is accepted positionally if `--ip` is not supplied.

Options (script-specific):
 - `--domain NAME`
 - `--ip IP [IP]` sets the IPv4 address for the apex A record (default: `104.238.140.248`).
 - `--site-type TYPE` sets the inventory `site_type` (`--singlesite`, `--multisite`, `redirect`, `worker`, `ignore`, or `none`); empty values are normalized to `none`.
 - `--multisite-domain NAME` sets the inventory multisite domain when `site_type=multisite`.
 - `--redirect-url URL` sets the inventory redirect target when `site_type=redirect`.
 - `--registrar NAME` sets the inventory registrar (default: `Unknown`).
 - `--dns-provider NAME` sets the inventory DNS provider (default: `Cloudflare`).
 - `--domains-file PATH [DOMAINS_FILE]`
 - `--date TS [DATASTORE_DATE]`
 - `--norecord`
 - `--downgrade`

Common arguments: --auth, --auth-file, --account, --account-name, --token, --key, --email, --help.

Environment variables:
`IP`, `DOMAINS_FILE`, `CF_ACCOUNT_NAME`, plus Cloudflare auth variables from `auth.sh`.

Notes:
- `onboard-zone.sh` wraps `cloud-dns.sh` so zone creation and DNS provisioning stay aligned with existing validation logic.
- Zone creation requires a Global API Key; the script defaults to `--auth key` unless overridden.
- The script queries the zone API to record `zone_id`, `zone_name`, and nameserver details back into the inventory.
- Domains with `site_type=none`, `site_type=ignore`, or `site_type=worker` are skipped entirely.

#### get-cert.sh (production/installation)

Purpose:
- Issues or installs Cloudflare Origin certificates and keys for domains.

Arguments:
- One or more domain names, provided positionally or via `--domain` (repeatable).

Options (script-specific):
 - `--api` issues certificates via the Cloudflare API.
 - `--manual` prompts for certificate and key blocks and writes them to disk.
 - `--auto` uses API mode if credentials exist, otherwise falls back to manual mode (default).
 - `--force` overwrites existing files without prompting.
 - `--domain NAME`

Common arguments: --auth, --auth-file, --token, --key, --email, --ca-key, --ssl-dir, --help.

Environment variables:
`SSL_DIR` (and derived cert/key paths), plus Cloudflare auth variables.

Notes:
- API mode requires `CF_CA_KEY` for Origin CA issuance; token/key credentials are not used for that endpoint.
- Manual mode writes to the SSL directories derived from `SSL_DIR`.

#### check-cf.sh (verification/investigation)

Purpose:
- Inspects Cloudflare zone settings and optionally validates expected values.

Arguments:
- A single zone name, or use `--zone` / `--zone-id`.

Options (script-specific):
 - `-e key=val` asserts that a setting matches the expected value (repeatable).
 - `-s key[,key]` prints only selected settings (repeatable). Empty entries are rejected.
 - `--raw` prints the raw settings JSON.
 - `--zone name [CF_ZONE]` selects a zone by name.
 - `--zone-id id [CF_ZONE_ID]` selects a zone by ID.

Common arguments: --auth, --auth-file, --token, --key, --email, --help.

Environment variables:
`CF_ZONE`, `CF_ZONE_ID`, plus Cloudflare auth variables.

Notes:
- Zone names are normalized and validated before lookup. `check-cf.sh` warns (case-sensitive) if the provided zone name differs from the Cloudflare API response.
- DNS A and CNAME records are listed after the zone header to make edge-to-origin alignment visible alongside settings.
- Derived keys are added for assertion and filtering: `managed_add_security_headers` and `leaked_credential_checks`.
- Unknown keys are reported as `<unknown>`; validation of allowed keys is deferred.

#### check-edge.sh (verification/investigation)

Purpose:
- Validates edge behavior for domains (redirects, proxy headers, and security headers).

Arguments:
- One or more domain names, provided positionally or via `--domain` (repeatable).

Options (script-specific):
 - `--http-timeout SECONDS [HTTP_TIMEOUT] (default: 10)` controls curl timeouts.
 - `--api` enables Cloudflare API checks and requires `CF_ZONE_ID` or `CF_ZONE` plus valid credentials.
 - `--domain NAME`
 - `--hsts=true|false` requires the Strict-Transport-Security header.
 - `--zone name [CF_ZONE]` sets the target zone name for API checks.
 - `--zone-id id [CF_ZONE_ID]` sets the target zone ID for API checks.

Common arguments: --auth, --auth-file, --token, --key, --email, --help.

Environment variables:
`HTTP_TIMEOUT`, `CF_ZONE`, `CF_ZONE_ID`, plus Cloudflare auth variables when `--api` is used.

Notes:
- `--api` performs Cloudflare setting checks using a single zone ID; use separate runs if you need to validate multiple zones with different IDs.
- DNS checks report A records (required) and also report CNAME and AAAA records when present.
- Set `HSTS_REQUIRED` to `true` or `false` in the environment or auth file to require Strict-Transport-Security without passing `--hsts=true|false`.
- Behavioral checks assume apex is canonical, require 301 redirects for HTTP and www, and verify WordPress asset markers (`/wp-content` or `/wp-includes`) on the canonical HTTPS response.
  - If the www CNAME is flattened by Cloudflare, the script accepts an A record for www instead of a CNAME.
  - HTTP apex must redirect to https://<apex> with 301. HTTP www may redirect to https://www or https://<apex> (301), and HTTPS www must redirect to https://<apex> (301). HTTPS apex must return 200.
- The script runs checks in this order:
  1. DNS lookups (apex A, www A/CNAME, apex AAAA).
  2. HTTP redirect checks (apex and www).
  3. HTTPS redirect check for www.
  4. HTTPS apex status.
  5. Cloudflare proxy header detection.
  6. Security headers, requiring `x-content-type-options`, `x-frame-options`, and `referrer-policy`, and conditionally `strict-transport-security` when `HSTS_REQUIRED=true`; `x-xss-protection` and `expect-ct` are treated as optional and reported.
  7. WordPress asset marker verification in the canonical HTTPS response, requiring `/wp-content/` or `/wp-includes/` in the HTML body.
  8. Cloudflare API checks (only when `--api` is provided).

### Host Layer Interfaces

#### check-server.sh (verification/investigation)

Purpose:
- Reports host-level Ubuntu, networking, and data service settings aligned to `HardenUbuntu.md`.

Arguments:
- None.

Options (script-specific):
`--help`.

Common arguments: --allow-root, --no-sudo.

Notes:
- The script is read-only and reports the current state only.
- Use the output alongside `HardenUbuntu.md` to validate baseline configuration.

### Origin Layer Interfaces

#### apache-vhost.sh (production/installation)

Purpose:
- Adds Apache vhosts for one or more WordPress domains and enables the sites.

Arguments:
- One or more domain names, provided positionally or via `--domain` (repeatable).

Options (script-specific):
 - `--http` creates HTTP vhosts only.
 - `--ssl` creates SSL vhosts only.
 - `--domain NAME`
 - `--template PATH [TEMPLATE_DIR]` sets the templates directory.
 - `--apache-dir DIR [APACHE_DIR]` sets the Apache sites directory with highest priority.

Common arguments: --wp-root, --ssl-dir, --help.

Environment variables:
`TEMPLATE_DIR`, `WORDPRESS_ROOT`, `SSL_DIR`, `SSL_CERT_DIR`, `SSL_KEY_DIR`, `APACHE_DIR`.

Notes:
- Uses templates in the templates directory and requires write access to `APACHE_DIR`.
- SSL vhosts use origin cert/key files in directories from `SSL_DIR`.
- If both `--http` and `--ssl` are supplied, the script logs a warning and generates both vhosts (the default behavior).

#### check-origin.sh (verification/investigation)

Purpose:
- Validates origin certificates, Apache vhost wiring, and basic Apache health.

Arguments:
- One or more domain names, provided positionally or via `--domain` (repeatable).

Options (script-specific):
 - `--domain NAME`
 - `--apache-dir DIR [APACHE_DIR]` sets the Apache sites directory with highest priority.

Common arguments: --wp-root, --ssl-dir, --allow-root, --no-sudo, --help.

Environment variables:
`APACHE_DIR`, `WORDPRESS_ROOT`, `SSL_DIR`.

### WordPress Layer Interfaces

#### setup-wp.sh (production/installation)

Purpose:
- Bootstraps a WordPress multisite base configuration. It is intentionally self-contained for early-stage setup and does not expose CLI options.

Arguments:
- None.

Options:
`--help` shows help.

Common arguments: none.

Environment variables:
`WORDPRESS_ROOT` overrides the default WordPress root path, and `TEMPLATE_DIR` selects the base templates for `wp-config.php` and `.htaccess`.

Notes:
- The header includes upstream reference links for MySQL, Apache, and PHP setup, and the script expects you to follow those instructions before enabling multisite.
- The script reports the selected templates so configuration changes are explicit.

#### install-site.sh (production/installation)

Purpose:
- Creates a new WordPress multisite site and maps it to an apex domain.

Arguments:
- `<domain> [title] [email]` where `--domain` can also be supplied via `--domain`.

Options:
 - `--domain NAME`

Common arguments: --wp-root, --help.

Environment variables:
`WORDPRESS_ROOT`.

Prerequisites:
- WordPress multisite installed at `WORDPRESS_ROOT`.
- Apache vhost configured for the domain.
- SSL certificate in place.
- DNS configured (proxied through Cloudflare).

Notes:
- The script derives a slug by removing dots and hyphens from the domain and uses WP-CLI to create the initial site.

#### check-wp.sh (verification/investigation)

Purpose:
- Validates WordPress site URLs for a given domain and supports both single-site and multisite checks.

Arguments:
- One or more domain names, provided positionally or via `--domain` (repeatable).

Options (script-specific):
 - `--singlesite` forces single-site checks.
 - `--multisite` forces multisite checks.
 - `--autosite` auto-detects single-site vs multisite (default).
 - `--template-dir DIR [TEMPLATE_DIR]` overrides the templates directory used for template checks.
 - `--template-check` compares `wp-config.php` and `.htaccess` against selected templates.
 - `--domain NAME`

Common arguments: --wp-root, --allow-root, --no-sudo, --help.

Environment variables:
`WORDPRESS_ROOT`, `TEMPLATE_DIR`.

### Orchestration Layer Interfaces

#### test-record.sh (verification + recording)

Purpose:
- Runs selected validation checks (`check-edge.sh`, `check-origin.sh`, `check-wp.sh`) and records status updates back into `domains.csv`.

Arguments:
- One or more domain names, provided positionally or via `--domain` (repeatable).
- Commands: `edge`, `origin`, `wp`, or `--all` (default: `--all`).

Options (script-specific):
 - `--domain NAME`
 - `--domains-file PATH [DOMAINS_FILE]`
 - `--state STATE` filters domains by `status_cf` when using `domains.csv`.
 - `--site-type TYPE` filters domains by `site_type` when using `domains.csv`.
 - `--include-ignore` includes `status_cf=ignore` and `status_cf=worker` when using `domains.csv`.
 - `--api`
 - `--date TS [DATASTORE_DATE]`
 - `--norecord`
 - `--downgrade`
 - `--multisite`, `--singlesite`, `--autosite` control WordPress mode selection.

Common arguments: --auth-file, --http-timeout, --hsts, --wp-root, --apache-dir, --ssl-dir, --allow-root, --no-sudo, --help.

Environment variables:
`DOMAINS_FILE`, `HTTP_TIMEOUT`, `WORDPRESS_ROOT`, `APACHE_DIR`, `SSL_DIR`.

Notes:
- Successful edge checks record `status_cf=https` for standard domains or `status_cf=redirect` for redirect-only domains.
- Successful origin checks record `status_origin=apache`.
- Successful WordPress checks record `status_wp=config`.
- Empty `site_type` values are normalized to `none`; `site_type=none`, `site_type=ignore`, and `site_type=worker` are skipped regardless of status filters.

#### check-domain.sh (verification/investigation)

Purpose:
- Runs `check-origin.sh`, `check-wp.sh`, and `check-edge.sh` in sequence for each domain.

Arguments:
- One or more domain names, provided positionally or via `--domain` (repeatable).

Options (script-specific):
 - `--api` passes `--api` to `check-edge.sh`.
 - `--hsts=true|false` passes the HSTS requirement to `check-edge.sh`.
 - `--domain NAME`
 - `--apache-dir DIR [APACHE_DIR]` passes the Apache sites directory to `check-origin.sh`.
 - `--http-timeout SECONDS [HTTP_TIMEOUT]` passes the timeout to `check-edge.sh`.

Common arguments: --ssl-dir, --wp-root, --allow-root, --no-sudo, --help.

Environment variables:
`HTTP_TIMEOUT`, `WORDPRESS_ROOT`, `SSL_DIR`, `APACHE_DIR`.

### Performance and Benchmarking Interfaces

These scripts are intended for repeatable benchmarking and sanity checks. They are read-only with respect to configuration, but they generate load and should be run with care on production systems.

#### perf-load.sh (verification/investigation)

Purpose:
- Runs init or sustained load checks with `wrk2` and an explicit rate (default per mode), with optional telemetry collection for CPU, memory, IO, and network.

Arguments:
- One or more domain names, provided positionally or via `--domain` (repeatable).

Options (script-specific):
 - `--init` or `--load`
 - `--domain NAME`
 - `--duration DURATION`
 - `--threads N`
 - `--connections N`
 - `--rate N`
 - `--run-id ID`
 - `--out-dir DIR`
 - `--cache-bust PARAM`
 - `--cache MODE`
 - `--interval N`
 - `--telemetry LIST`
 - `--head`
 - `--report`

Common arguments: --help.

Environment variables:
None.

Notes:
- Defaults are mode-specific for concurrency and rate, but duration is 20s for both init and load unless overridden.
- Defaults are mode-specific and include a fixed rate: init defaults to `threads=1`, `connections=1`, `rate=10`; load defaults to `threads=2`, `connections=4`, `rate=20`.
- `perf-load.sh` prefers `/home/ubuntu/WP/wrk2/wrk` if present; set `WRK_BIN` to override the binary.
- The default output directory is `/var/tmp/multiwp/perf_<run-id>`, and output files use a per-domain prefix.
- Telemetry defaults to `sar`; use `--telemetry=none` or a comma list to change it.
- When `--head` is supplied, cached headers are saved as `${prefix}_head.txt` and cache-busted headers as `${prefix}_head_bust.txt`.
- `--cache` controls whether cached, cache-busted, or both runs are executed (`both`, `cached`, `bust`).
- `--telemetry` accepts `sar`, `pidstat`, `vmstat`, `iostat`, `cgtop`, `all`, or `none`, and it accepts comma lists (for example, `sar,pidstat`).
- `wrk2` is always used and always receives `-R <rate>`, either from `--rate` or from mode defaults.
- When running `perf-load.sh` through an external command runner, use a timeout of at least 60 seconds.
- Telemetry writes logs alongside `wrk` or `wrk2` output in the run directory. Command dependencies vary by telemetry scope.
- `--report` emits a per-run summary of `REQ_PER_SEC`, `LATENCY_AVG`, `LATENCY_MAX`, and `NOT_200_PCT`.
- When telemetry includes `sar`, `--report` emits `CPU_TOTAL_PCT_MAX`, `CPU_BUSY_CORES_MAX`, and `LOAD_1_MAX`. If telemetry includes `sar` plus any other tool, it also emits `MEM_AVAIL_MB_MIN`, `MEM_AVAIL_MB_AVG`, `MEM_USED_PCT_MAX`, `MEM_USED_PCT_AVG`, `CPU_USER_PCT_MAX`, `CPU_SYSTEM_PCT_MAX`, `CPU_IOWAIT_PCT_MAX`, `CPU_STEAL_PCT_MAX`, `CPU_TOTAL_BIN5_AVG`, `CPU_TOTAL_TREND`, and `LOAD_1_AVG`. When telemetry includes `pidstat`, `--report` emits `APACHE_CPU_SUM_AVG`, `APACHE_CPU_SUM_MAX`, `APACHE_CPU_SAMPLES`, `APACHE_CPU_SUM_BIN5_AVG`, and `APACHE_CPU_SUM_TREND`.

#### slice-logs.sh (verification/investigation)

Purpose:
- Extracts log slices for a perf run based on the `run.param` metadata file.

Arguments:
- None. All inputs are supplied as options.

Options (script-specific):
 - `--run-param PATH`
 - `--out-dir DIR`
 - `--pad SEC`

Common arguments: --help.

Environment variables:
None.

Notes:
- Reads `run.param` in `KEY: value` format and writes sliced logs using the same prefix.
- Apache log selection is best-effort and warns if a matching file is not found.
- Uses `sudo` for log reads if the file is not readable by the current user.
- When a `${prefix}_report.txt` and Apache access slice exist, the script appends
  summary rows to `perf_runs.csv` and `perf_segments.csv` in the output directory.

## Option Cross-Reference (Alphabetical)

This cross-reference lists options alphabetically and the scripts that implement them. CSV files are exports for future processing; this list is the human-readable view.

- -e,check-cf.sh
- -s,check-cf.sh
- --account,cloud-dns.sh;cloud-redirect.sh;cloud-settings.sh;mcp-cf.sh;onboard-zone.sh;verify-cf-auth.sh
- --account-name,cloud-redirect.sh;cloud-settings.sh;onboard-zone.sh
- --all,rules-cf.sh
- --allow-redirects,rules-cf.sh
- --allow-root,check-origin.sh;check-server.sh;check-wp.sh;cloudflare-ips.sh;test-record.sh;check-domain.sh
- --always-use-https,cloud-settings.sh
- --apache-dir,apache-vhost.sh;check-origin.sh;check-read.sh;test-record.sh;check-domain.sh
- --api,check-edge.sh;check-read.sh;get-cert.sh;test-record.sh;check-domain.sh
- --apply,mcp-cf.sh;rules-cf.sh
- --auth,check-cf.sh;check-edge.sh;cloud-dns.sh;cloud-redirect.sh;cloud-settings.sh;get-cert.sh;mcp-cf.sh;onboard-zone.sh;rules-cf.sh;test-record.sh;verify-cf-auth.sh
- --auth-file,check-auth.sh;check-cf.sh;check-edge.sh;check-read.sh;cloud-dns.sh;cloud-redirect.sh;cloud-settings.sh;get-cert.sh;mcp-cf.sh;onboard-zone.sh;rules-cf.sh;test-record.sh;verify-cf-auth.sh
- --auto,get-cert.sh
- --autosite,check-read.sh;check-wp.sh;test-record.sh
- --bearer,mcp-cf.sh
- --ca-key,get-cert.sh;test-record.sh;verify-cf-auth.sh
- --cache-bust,perf-load.sh
- --catalog,mcp-cf.sh
- --check-ids,check-auth.sh
- --connections,perf-load.sh
- --create,cloud-dns.sh
- --date,cloud-redirect.sh;onboard-zone.sh;test-record.sh
- --dns-provider,onboard-zone.sh
- --domain,apache-vhost.sh;check-edge.sh;check-origin.sh;check-read.sh;check-wp.sh;cloud-dns.sh;cloud-redirect.sh;cloud-settings.sh;get-cert.sh;install-site.sh;onboard-zone.sh;rules-cf.sh;perf-load.sh;test-record.sh;check-domain.sh
- --domains-file,check-auth.sh;check-read.sh;cloud-redirect.sh;cloud-settings.sh;onboard-zone.sh;test-record.sh
- --downgrade,cloud-redirect.sh;onboard-zone.sh;test-record.sh
- --dry-run,cloud-redirect.sh;cloud-settings.sh
- --duration,perf-load.sh
- --email,check-cf.sh;check-edge.sh;cloud-dns.sh;cloud-redirect.sh;cloud-settings.sh;get-cert.sh;mcp-cf.sh;onboard-zone.sh;rules-cf.sh;test-record.sh;verify-cf-auth.sh
- --export,rules-cf.sh
- --force,get-cert.sh
- --head,perf-load.sh
- --help,apache-vhost.sh;check-auth.sh;check-cf.sh;check-edge.sh;check-origin.sh;check-read.sh;check-server.sh;check-wp.sh;cloud-dns.sh;cloud-redirect.sh;cloud-settings.sh;cloudflare-ips.sh;get-cert.sh;install-site.sh;mcp-cf.sh;onboard-zone.sh;rules-cf.sh;perf-load.sh;test-record.sh;verify-cf-auth.sh;check-domain.sh
- --hsts,check-edge.sh;test-record.sh;check-domain.sh
- --http,apache-vhost.sh
- --http-timeout,check-edge.sh;test-record.sh;check-domain.sh
- --include-ignore,check-read.sh;test-record.sh
- --init,perf-load.sh
- --input,rules-cf.sh
- --interval,perf-load.sh
- --ip,onboard-zone.sh
- --key,check-cf.sh;check-edge.sh;cloud-dns.sh;cloud-redirect.sh;cloud-settings.sh;get-cert.sh;mcp-cf.sh;onboard-zone.sh;rules-cf.sh;test-record.sh;verify-cf-auth.sh
- --load,perf-load.sh
- --managed-add-security-headers,cloud-settings.sh
- --manual,get-cert.sh
- --min-tls-version,cloud-settings.sh
- --multisite,check-read.sh;check-wp.sh;test-record.sh
- --multisite-domain,onboard-zone.sh
- --no-sudo,check-origin.sh;check-server.sh;check-wp.sh;cloudflare-ips.sh;test-record.sh;check-domain.sh
- --norecord,cloud-redirect.sh;onboard-zone.sh;test-record.sh
- --out-dir,perf-load.sh;slice-logs.sh
- --output,cloudflare-ips.sh;rules-cf.sh
- --portal-url,mcp-cf.sh
- --raw,check-cf.sh
- --pad,slice-logs.sh
- --rate,perf-load.sh
- --redirect-url,cloud-redirect.sh;onboard-zone.sh
- --registrar,onboard-zone.sh
- --run-id,perf-load.sh
- --run-param,slice-logs.sh
- --singlesite,check-read.sh;check-wp.sh;test-record.sh
- --site-type,check-read.sh;onboard-zone.sh;test-record.sh
- --site-types,cloud-settings.sh
- --source,rules-cf.sh
- --ssl,apache-vhost.sh;cloud-settings.sh
- --ssl-dir,apache-vhost.sh;check-origin.sh;check-read.sh;get-cert.sh;test-record.sh;check-domain.sh
- --stage,check-wp.sh
- --state,check-read.sh;test-record.sh
- --template,apache-vhost.sh
- --template-check,check-wp.sh
- --template-dir,check-wp.sh
- --telemetry,perf-load.sh
- --threads,perf-load.sh
- --token,check-cf.sh;check-edge.sh;cloud-dns.sh;cloud-redirect.sh;cloud-settings.sh;get-cert.sh;mcp-cf.sh;onboard-zone.sh;rules-cf.sh;test-record.sh;verify-cf-auth.sh
- --ufw,cloudflare-ips.sh
- --update,cloud-dns.sh
- --wp-root,apache-vhost.sh;check-origin.sh;check-read.sh;check-wp.sh;install-site.sh;test-record.sh;check-domain.sh
- --zone,check-cf.sh;check-edge.sh
- --zone-id,check-cf.sh;check-edge.sh;verify-cf-auth.sh


## Helper Inclusion Cross-Reference

This cross-reference lists helper scripts and the programs or tests that source them. CSV files are exports for future processing; this list is the human-readable view.

- common.sh: apache-vhost.sh;check-auth.sh;check-cf.sh;check-edge.sh;check-origin.sh;check-read.sh;check-server.sh;check-wp.sh;cloud-dns.sh;cloud-redirect.sh;cloud-settings.sh;cloudflare-ips.sh;get-cert.sh;install-site.sh;mcp-cf.sh;onboard-zone.sh;rules-cf.sh;setup-wp.sh;perf-load.sh;test-record.sh;test_cf.sh;test_cli.sh;test_common.sh;verify-cf-auth.sh;check-domain.sh
- cli.sh: apache-vhost.sh;check-auth.sh;check-cf.sh;check-edge.sh;check-origin.sh;check-read.sh;check-server.sh;check-wp.sh;cloud-dns.sh;cloud-redirect.sh;cloud-settings.sh;cloudflare-ips.sh;get-cert.sh;install-site.sh;mcp-cf.sh;onboard-zone.sh;rules-cf.sh;perf-load.sh;test-record.sh;test_cli.sh;verify-cf-auth.sh;check-domain.sh
- auth.sh: check-auth.sh;check-cf.sh;check-edge.sh;cloud-dns.sh;cloud-redirect.sh;cloud-settings.sh;get-cert.sh;mcp-cf.sh;onboard-zone.sh;rules-cf.sh;test-record.sh;test_cf.sh;test_cli.sh;verify-cf-auth.sh
- mcp.sh: mcp-cf.sh;test_mcp.sh

## TODO (Revisit)

The items below capture small, implementation-focused follow-ups that keep helper behavior and option parsing consistent as the script surface grows.

- Helper predicates: document the shared `cf_has_env`/`cf_has_all` pattern used by `cf_has_*` helpers so future additions follow the same empty-vs-unset semantics and avoid divergent checks.
- Enum parsing: evaluate whether option values with limited sets (for example `--site-type`, `singlesite|multisite|autosite`, or `api|manual|auto`) should accept environment equivalents with explicit enum validation, and if so, keep CLI/env/auth error messaging aligned.
- Origin cert auth policy: revisit whether `get-cert.sh` should prefer the global API key for Origin CA issuance, with `CF_CA_KEY` as a fallback, and document the rationale and any security tradeoffs before changing the default.
- Review `test-record.sh` uses and `check-domain.sh` overlap to decide whether to consolidate or keep distinct.
