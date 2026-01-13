# Script Interfaces and Configuration
Date: January 9, 2026

This document centralizes the script interfaces, configuration expectations, environment variables, and defaults used by the scripts in `scripts/`. It is the authoritative interface contract for operators and automation, and it complements `scripts/Shell.md` (Bash conventions and helper usage).

## Source of Truth

Every program script prints its authoritative help via `usage()`. Headers only point to `usage()` to avoid duplication; when this document conflicts with `usage()`, update this document to match the script output.

This document is authoritative for script interfaces, configuration, environment variables, and defaults. `scripts/Shell.md` is authoritative for Bash conventions and shared helper usage. `scripts/Prompt.md` encodes the Codex prompt format for applying header and `usage()` updates without altering behavior.

## Part A: Script Catalog (by layer)

This catalog groups scripts by operational layer and labels each script as provisioning or verification/investigation. Full option and environment-variable details live in Part B.

### Cloudflare Layer

Cloudflare scripts manage credentials, DNS records, certificates, and edge validation. A typical flow starts with credential checks, provisions DNS inside an existing zone, then issues certificates, and ends with settings and edge validation. Zone creation itself is out of scope for the current scripts and must be completed before DNS provisioning begins.

- `verify-cf-auth.sh` — verification (read-only)
- `cloud-dns.sh` — provisioning
- `onboard-zone.sh` — provisioning
- `get-cert.sh` — provisioning
- `check-cf.sh` — verification (read-only)
- `check-edge.sh` — verification (read-only)

### Origin Layer (Apache and TLS)

Origin scripts configure or validate Apache vhosts and TLS wiring. Provisioning typically precedes verification.

- `apache-vhost.sh` — provisioning
- `check-origin.sh` — verification (read-only)

### WordPress Layer

WordPress scripts bootstrap or validate multisite configuration and mapping. Provisioning typically precedes verification.

- `setup-wp.sh` — provisioning
- `install-site.sh` — provisioning
- `check-wp.sh` — verification (read-only)

### Orchestration Layer

Orchestration scripts combine multiple checks in a single run.

- `verify-domain.sh` — verification (read-only)

### Smoke

The `smoke.sh` wrapper provides a light-weight entry point for read-only validation across multiple domains. It is intended to standardize how we run syntax checks, unit tests, edge/DNS checks, and origin/WordPress checks without requiring operators to remember the underlying script order or domain selection details.

Needs and requirements are grouped below so that future changes can be evaluated against the same constraints.

Needs:
- A single entry point that can run `syn`, `unit`, `edge`, `dns`, `origin`, `wp`, and `mysql` in a predictable order.
- Domain selection driven by `domains.csv` or an explicit list of domains provided on the command line.
- Support for filtering by `status_cf` and `site_type` while avoiding `status_cf=ignore` and `status_cf=worker` by default.

Requirements:
- Read-only behavior only; no API writes and no origin or WordPress mutations.
- Clear exit codes: syntax/unit failures should cause a non-zero exit, while edge/DNS checks should continue across domains.
- Consistent selection rules across all commands so a single invocation can be trusted as a “smoke run.”

Design notes:
- `smoke.sh` reads `domains.csv` once and applies filters only when explicit domains are not supplied.
- If no command list is provided, `smoke.sh` runs all commands in the order listed, so a default run is a full smoke pass.
- `edge` uses `check-edge.sh` (with `--api` when requested) and `dns` uses `check-cf.sh`.
- `origin` uses `check-origin.sh`, `wp` uses `check-wp.sh`, and `mysql` uses WP-CLI `db check` against selected roots.
- `--auth-file` overrides the per-domain auth file from `domains.csv` for edge/DNS API calls.
- Origin, WordPress, and MySQL checks are read-only and depend on local filesystem access.

Implementation plan:
1) Parse commands and options; when no commands are supplied, run the full command set in order.
2) Load domain metadata when needed and select the domain set (explicit list or filtered list).
3) Execute each command in the requested order, collecting failures without aborting domain loops.
4) Return a non-zero status if any syntax or unit test fails.

### Support and Tests

The test scripts and helper libraries are intentionally minimal. They do not parse options and should be run directly from the `scripts/` directory.

- `test_common.sh`, `test_cli.sh`, `test_cf.sh` run unit checks for shared helpers.
- `common.sh`, `cli.sh`, `auth.sh` provide shared logic and should not be executed directly.

## Settings

This section documents the Cloudflare and edge behaviors that the read-only checks validate today. It is intended to be a practical guide for operators so the script outputs can be interpreted consistently, while keeping the authoritative option behavior in the `usage()` output of each script.

Before applying the settings below, ensure the dependencies are met: the zone is active in Cloudflare, nameservers are pointed at Cloudflare, and the scripts have access to a valid auth file with the required credentials and `CF_ZONE_ID` or `CF_ZONE`.

### DNS and Proxy

The edge checks assume Cloudflare is proxying the apex and `www` hostnames. The DNS layer must exist and be proxied before HTTPS or header checks will behave as expected.

- Apex: an **A** record for `@` pointing to the origin IPv4 address, with the proxy (orange cloud) enabled.
- `www`: a **CNAME** to the apex. If CNAME flattening hides the CNAME, an **A** record for `www` is acceptable and will be treated as valid by `check-edge.sh`.
- Optional: a wildcard `*` CNAME to the apex when you want Cloudflare to catch stray hostnames.

### Redirect Behavior

`check-edge.sh` validates canonical redirects and will fail if the redirect targets do not match the expected behavior. Redirect-only domains use `redirect_url` from `domains.csv` and skip HTTPS and API checks.

- Standard sites: `http://apex` should 301 to `https://apex`, and `https://www` should 301 to `https://apex`.
- Redirect-only sites: use a Cloudflare Redirect Rule that applies to all incoming requests and points to the configured `redirect_url`.

### SSL/TLS Mode

When `check-edge.sh --api` runs, it requires the SSL mode to be **Full (strict)**. This is a Cloudflare zone setting and is validated via the API.

- Path: `SSL/TLS` → `Overview` → set “SSL/TLS encryption mode” to **Full (strict)**.

### Edge HTTPS Features

The redirect expectations rely on Always Use HTTPS being enabled for standard WordPress sites.

- Path: `SSL/TLS` → `Edge Certificates` → enable “Always Use HTTPS”.
- HSTS is optional by default; if `--hsts=true` is supplied to `check-edge.sh`, the script will require the `strict-transport-security` header.

### Response Headers

`check-edge.sh` requires several security headers on the HTTPS apex response. You can provide these either at the origin or by enabling Cloudflare’s managed headers.

- Required headers: `x-content-type-options`, `x-frame-options`, `referrer-policy`.
- Optional headers (warn only): `x-xss-protection`, `expect-ct`.
- Path (Cloudflare managed headers): `Rules` → `Settings` → `Managed Transforms` → `HTTP Response Headers` → “Add security headers”.

### WordPress Markers

For non-redirect domains, `check-edge.sh` fetches HTML and expects WordPress markers (`/wp-content` or `/wp-includes`). Cloudflare Pages or Workers sites will not satisfy this check; mark those zones as `status_cf=worker` so they are skipped unless explicitly included.

### API-Visible Settings (check-cf)

`check-cf.sh` prints the full Cloudflare settings map and DNS records. It only enforces values when `-e key=value` is supplied. The settings most commonly enforced alongside edge checks include:

- `ssl=strict`
- `always_use_https=on`
- `min_tls_version=1.2`
- `managed_add_security_headers=true`
- `leaked_credential_checks=false`

## Part B: Option and Environment Reference (canonical)

This section documents shared conventions and the full per-script interfaces. It is the authoritative reference for option and environment variable behavior; implementation details for helper usage and processing rationale live in `scripts/Shell.md`.

### Shared Option and Environment Conventions

Shared options are expressed as long options only. Scripts use `--help` for help; the short `-h` option is intentionally not supported to keep parsing consistent across scripts. Standard names are `SSL_DIR`, `APACHE_DIR`, and `WORDPRESS_ROOT`, and the template option is `--template` (avoid legacy names such as `--temp`).

Configuration priority (lowest to highest):
- Code defaults
- Auth file values
- Environment variables
- CLI options

When `usage()` lists an option, it follows a consistent format:

```
--http-timeout SECONDS [HTTP_TIMEOUT] (default: 10)  HTTP timeout for curl
```

This format makes the option, the related environment variable, and the default value visible in one line. In addition, the option lists follow a consistent order to reduce scanning time.

Option ordering:
- Script-specific options first.
- Auth options second (when present).
- Root and SSL path options next.
- Common privilege options next.
- `--help` always last.

List handling:
- Comma-separated lists are split on commas, whitespace is trimmed around each token, and empty tokens are treated as failures.

### Boolean handling

Boolean settings are parsed and normalized to keep behavior consistent across scripts.

- Parse boolean values from environment or auth files with `parse_bool` (from `common.sh`) and normalize to `true|false`.
- Accept `true|false` and `yes|no|y|n` (case-insensitive). Reject anything else.
- Treat empty or unset values as “use default.” Do not treat empty as implicit true or false.
- For boolean CLI options that mirror env/auth settings, prefer value-style `--name=true|false` instead of bare toggles.
- Do not enumerate accepted tokens in `usage()`; only show priority and default (for example: `--hsts=true|false [HSTS_REQUIRED] (default: false)`).
- Apply standard precedence: code defaults (lowest), then auth files, then environment, then CLI options (highest).
- If `parse_bool` fails, emit a concise error and exit non-zero.
- Do not add new dependencies to scripts that are intentionally self-contained.

### Shared Options and Environment Variables

The following options and environment variables are referenced by multiple scripts. This section documents each option once, then the per-script sections below reference the applicable subset.

#### Privilege and execution controls

These options influence how scripts invoke privileged commands. They do not change functional behavior, but they can affect whether a script can read or write protected files.

- `--allow-root` bypasses the root guard for scripts that call `cli_require_non_root`. It should only be used for constrained environments where running as root is unavoidable.
- `--no-sudo [SUDO_BIN] (default: sudo)` sets `SUDO_BIN` to an empty string. The `priv()` helper will run commands directly as the current user instead of invoking `sudo`.
- `SUDO_BIN` (env) controls the privilege wrapper globally. Use an empty value to disable `sudo` while keeping the `priv()` call pattern intact.

#### WordPress root

These options and environment variables control where WordPress is located on disk.

- `--wp-root PATH [WORDPRESS_ROOT] (default: /var/www/html/wordpress)` sets the WordPress root path for scripts that operate on the WordPress filesystem or run WP-CLI.
- `WORDPRESS_ROOT` (env) provides the default WordPress root if the `--wp-root` option is not supplied.

#### Domain selection

Domain-oriented scripts accept domains via `--domain` (repeatable). Positional domains are still accepted for compatibility, and scripts normalize, validate, and de-duplicate the final list before execution.

- `--domain NAME` adds a domain to the list of domains to process.
Notes:
- Option parsing consumes known options only; any remaining arguments are treated as positional domains. A literal `--` is treated as a domain token and will fail validation.
- Domains are normalized (lowercased and trimmed) before validation and de-duplication.

Redirect-only domains:
Redirect-only domains are managed with a single source of truth so validation scripts can distinguish “edge-only” domains from full origin-backed sites.

Status (current behavior):
- Redirect-only domains are derived from `domains.csv` (`site_type=redirect`) and loaded by `load_dns_redirects`.
- `check-origin.sh` and `check-wp.sh` skip origin/WP checks for redirect-only domains and treat absence as expected.
- `check-edge.sh` validates DNS and HTTP redirect behavior for redirect-only domains but skips HTTPS and Cloudflare API checks.

Next steps:
- Add redirect-focused provisioning support to `cloud-dns.sh` (for example, record patterns or options suitable for edge-only redirect zones).

Examples:
- `check-edge.sh --domain example.com --domain www.example.com`
- `check-edge.sh example.com www.example.com`
- `cloud-dns.sh --domain example.com 203.0.113.10`
- `cloud-dns.sh example.com 203.0.113.10`

Status columns:
The `status_*` columns in `domains.csv` record the latest confirmed stage for each layer. The value `none` indicates that no tests for that layer have passed yet, and `status_cf=added` indicates the zone exists but is not yet active. These values are used for filtering and reporting rather than as authoritative configuration, and `status_cf=worker` is treated the same as `status_cf=ignore` unless explicitly included. In practice, `status_cf=https` means the standard edge checks for a full HTTPS site are confirmed, while `status_cf=redirect` means the redirect-only edge behavior is confirmed. For the origin layer, the implemented check group maps to `status_origin=apache` when `check-origin.sh` succeeds. For WordPress, `check-wp.sh` validates installation and configuration; a separate load test would be required before recording `status_wp=load`, so that value should remain unused until such a test is implemented.

#### IP address inputs

IP address inputs show up in three distinct places, and keeping their names and roles separate avoids confusing inventory data with runtime parameters.

- Inventory column: `domains.csv` uses `ip` to record the origin IPv4 address as inventory data.
- Provisioning argument: `cloud-dns.sh` accepts a positional `<ip>` argument and does not provide an option flag for it.
- Onboarding option: `onboard-zone.sh` uses `--ip` (and env `IP`) as the canonical interface, defaulting to `104.238.140.248` when no CLI, env, or CSV value exists.

#### SSL directory and certificate paths

These options define where origin certificates and keys are stored. Scripts that read or write certificates use these paths.

- `--ssl-dir DIR [SSL_DIR] (default: /etc/ssl/cloudflare-origin)` sets the SSL directory and implicitly sets the cert/key subdirectories.
- `SSL_DIR` (env) defines the base directory for origin certificates.
- `SSL_CERT_DIR` (env) defaults to `${SSL_DIR}/certs`.
- `SSL_KEY_DIR` (env) defaults to `${SSL_DIR}/keys`.

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

Auth variables:
- `CF_API_TOKEN` (account API token, account-scoped)
- `CF_API_KEY` + `CF_API_EMAIL` (global API key, user-scoped)
- `CF_CA_KEY` (Origin CA User Service Key, user-scoped)
- `CF_ACCOUNT_ID` (account identifier)
- `CF_ACCOUNT_NAME` (account name for name-to-ID lookup)
- `CF_AUTH` (`auto`, `token`, or `key`) selects the credential type (default: `auto`)
- CLI-supplied values are stored in `*_CLI` variables (for example, `CF_API_TOKEN_CLI`) before being applied as the highest-priority values.

- `--auth token|key|auto [CF_AUTH]` selects the credential type (default: `auto`).
- `--auth-file PATH [CF_AUTH_FILE] (default: ~/.config/cloudflare/default.auth)` points to the auth file to load.
- `--account ID [CF_ACCOUNT_ID]` sets the account ID with highest priority for account-scoped calls.
- `--token TOKEN [CF_API_TOKEN]` sets the account API token.
- `--key KEY [CF_API_KEY]` sets the global API key.
- `--email EMAIL [CF_API_EMAIL]` sets the email for the global API key.
- `--ca-key KEY [CF_CA_KEY]` sets the Origin CA User Service Key.

Cloudflare zone selection:
- `--zone name [CF_ZONE]` sets the target zone name (used by `check-cf.sh`).
- `--zone-id id [CF_ZONE_ID]` sets the target zone ID (used by `check-cf.sh` and `verify-cf-auth.sh`).
- `CF_ZONE_MAIN` (env) is preferred when multiple zones exist in the auth file.
- `CF_ZONE` and `CF_ZONE_ID` (env) are read from the auth file, with the first `CF_ZONE_ID` chosen by default.
Notes:
- `CF_ZONE` must be an apex (for example, `example.com`, not `www.example.com`); auth files may list multiple `CF_ZONE_ID` values—scripts use the first by default and retain the list in `CF_ZONE_IDS` (comma-separated).
- When both `CF_ZONE_ID` and `CF_ZONE` are set, scripts use `CF_ZONE_ID` and log a warning noting the choice.
- When both `CF_ACCOUNT_ID` and `CF_ACCOUNT_NAME` are set, scripts use `CF_ACCOUNT_ID` and log a warning noting the choice.
- When `CF_AUTH=auto` and both token and key credentials are present, scripts use the token and log a warning noting the choice.

### Knowledge

This section summarizes which Cloudflare APIs are used for which operations and which credentials are expected to work. It reflects the current scripts and observed behavior in this repo, and it is intended to reduce confusion when a token succeeds for one endpoint but fails for another.

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

The following scripts are read-only by design and do not modify DNS, certificates, Apache configuration, or WordPress data. Read-only scripts: `check-edge.sh`, `check-cf.sh`, `verify-cf-auth.sh`, `check-origin.sh`, `check-wp.sh`, `verify-domain.sh`. Unit tests: `test_common.sh`, `test_cli.sh`, `test_cf.sh`.

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

Options (auth and shared):
- `--auth token|key|auto [CF_AUTH]`
- `--auth-file PATH [CF_AUTH_FILE]`
- `--account ID [CF_ACCOUNT_ID]`
- `--token TOKEN [CF_API_TOKEN]`
- `--key KEY [CF_API_KEY]`
- `--email EMAIL [CF_API_EMAIL]`
- `--ca-key KEY [CF_CA_KEY]`
- `--help`

Environment variables:
- All Cloudflare auth variables listed in `auth.sh`.

Notes:
- Account API tokens are verified against the account endpoint when `CF_ACCOUNT_ID` is available.
- Global API keys are verified with X-Auth-Email + X-Auth-Key against `/user`.
- Origin CA keys are verified with a read-only GET to `/certificates?zone_id=...`. If `CF_ZONE_ID` is missing but `CF_ZONE` is present, the script will attempt to resolve the zone ID using available API credentials.

#### cloud-dns.sh (production/installation)

Purpose:
- Creates or updates DNS records inside an existing Cloudflare zone, including an apex A record plus CNAMEs for `www` and `*` pointing to the apex.

Arguments:
- `<domain> <ip>` where `domain` is the zone and the IP address is the origin IPv4. Use `--domain` to provide the domain via an option.

Options (script-specific):
- `--domain NAME` supplies the domain as an option.
- `--create` only creates DNS records; errors if a record already exists.
- `--update` only updates existing DNS records; errors if a record is missing.

Options (auth and shared):
- `--auth token|key|auto [CF_AUTH]`
- `--account ACCOUNT_ID [CF_ACCOUNT_ID]`
- `--token TOKEN [CF_API_TOKEN]`
- `--key KEY [CF_API_KEY]`
- `--email EMAIL [CF_API_EMAIL]`
- `--auth-file PATH [CF_AUTH_FILE]`
- `--help`

Environment variables:
- `CF_ACCOUNT_ID`, `CF_API_TOKEN`, `CF_API_KEY`, `CF_API_EMAIL`.

Notes:
- When `--domain` is provided, positional arguments supply `<ip>` only.
- By default, DNS records are created or updated to avoid duplicates.
- If the zone does not exist in the target account, the script creates it; otherwise it reuses the existing zone.
- IPv4 must be publicly routable; RFC1918, link-local, loopback, and multicast ranges are rejected.
- IPv4 addresses ending in `.0` or `.255` are accepted but produce a warning to prompt verification.
- `warn()` is used for non-fatal conditions; `fail()` reports a non-fatal check failure while allowing the script to continue; `err()` emits a fatal error and exits non-zero when a required condition fails. In `cloud-dns.sh`, duplicate A records are fatal while duplicate CNAME records emit a warning.
- Planned: support marking zones as redirect-only (from `domains.csv`) so cloud-dns can provision redirect-focused DNS without origin dependencies.

#### onboard-zone.sh (production/installation)

Purpose:
- Creates or ensures a Cloudflare zone exists, provisions the baseline DNS records, and records the zone metadata back into `domains.csv` for inventory tracking.

Arguments:
- One or more domain names, provided positionally or via `--domain` (repeatable).
- `<ip>` can be provided positionally if `--ip` is not supplied.

Options (script-specific):
- `--domain NAME` adds a domain to the list (repeatable).
- `--ip IP [IP]` sets the IPv4 address for the apex A record (default: `104.238.140.248`).
- `--site-type TYPE` sets the inventory `site_type` (`singlesite`, `multisite`, or `redirect`); default is `singlesite` when no CSV value exists.
- `--multisite-domain NAME` sets the inventory multisite domain when `site_type=multisite`.
- `--redirect-url URL` sets the inventory redirect target when `site_type=redirect`.
- `--registrar NAME` sets the inventory registrar (default: `Unknown`).
- `--dns-provider NAME` sets the inventory DNS provider (default: `Cloudflare`).
- `--domains-file PATH [DOMAINS_FILE]` sets the inventory CSV path.
- `--no-csv` skips inventory updates; provisioning still runs.

Options (auth and shared):
- `--auth token|key|auto [CF_AUTH]`
- `--auth-file PATH [CF_AUTH_FILE]`
- `--account ID [CF_ACCOUNT_ID]`
- `--account-name NAME [CF_ACCOUNT_NAME]`
- `--token TOKEN [CF_API_TOKEN]`
- `--key KEY [CF_API_KEY]`
- `--email EMAIL [CF_API_EMAIL]`
- `--help`

Environment variables:
- `IP` for the apex IPv4 if `--ip` is not supplied.
- `DOMAINS_FILE` to override the inventory path.
- `CF_ACCOUNT_NAME` to look up the account ID by name when `--account` is not provided.
- Cloudflare auth variables listed in `auth.sh`.

Notes:
- `onboard-zone.sh` wraps `cloud-dns.sh` so zone creation and DNS provisioning stay aligned with existing validation logic.
- Zone creation requires a Global API Key; the script defaults to `--auth key` unless overridden.
- The script queries the zone API to record `zone_id`, `zone_name`, and nameserver details back into the inventory.

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
- `--domain NAME` adds a domain to the list (repeatable).

Options (auth and shared):
- `--auth token|key|auto [CF_AUTH]`
- `--auth-file PATH [CF_AUTH_FILE]`
- `--token TOKEN [CF_API_TOKEN]`
- `--key KEY [CF_API_KEY]`
- `--email EMAIL [CF_API_EMAIL]`
- `--ca-key KEY [CF_CA_KEY]`
- `--ssl-dir DIR [SSL_DIR]`
- `--help`

Environment variables:
- `SSL_DIR` (and derived cert/key paths) and Cloudflare auth variables.

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

Options (auth and shared):
- `--auth token|key|auto [CF_AUTH]`
- `--auth-file PATH [CF_AUTH_FILE]`
- `--token TOKEN [CF_API_TOKEN]`
- `--key KEY [CF_API_KEY]`
- `--email EMAIL [CF_API_EMAIL]`
- `--help`

Environment variables:
- `CF_ZONE`, `CF_ZONE_ID`, and Cloudflare auth variables.

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
- `--domain NAME` adds a domain to the list (repeatable).
- `--hsts=true|false` requires the Strict-Transport-Security header.

Options (auth and shared):
- `--auth token|key|auto [CF_AUTH]`
- `--auth-file PATH [CF_AUTH_FILE]`
- `--token TOKEN [CF_API_TOKEN]`
- `--key KEY [CF_API_KEY]`
- `--email EMAIL [CF_API_EMAIL]`
- `--help`

Environment variables:
- `HTTP_TIMEOUT` for curl timeouts.
- Cloudflare auth variables when `--api` is used.

Notes:
- `--api` performs Cloudflare setting checks using the single `CF_ZONE_ID` value (resolved from `CF_ZONE` when needed); use separate runs if you need to validate multiple zones with different IDs.
- DNS checks report A records (required) and also report CNAME and AAAA records when present.
- `HSTS_REQUIRED` can be set to `true` or `false` in the environment or auth file to require Strict-Transport-Security without passing `--hsts=true|false`.
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

### Origin Layer Interfaces

#### apache-vhost.sh (production/installation)

Purpose:
- Adds Apache vhosts for one or more WordPress domains and enables the sites.

Arguments:
- One or more domain names, provided positionally or via `--domain` (repeatable).

Options (script-specific):
- `--http` creates HTTP vhosts only.
- `--ssl` creates SSL vhosts only.
- `--domain NAME` adds a domain to the list (repeatable).
- `--template PATH [TEMPLATE_DIR]` sets the templates directory.
- `--apache-dir DIR [APACHE_DIR]` sets the Apache sites directory with highest priority.

Options (shared):
- `--wp-root PATH [WORDPRESS_ROOT]`
- `--ssl-dir DIR [SSL_DIR]`
- `--help`

Environment variables:
- `TEMPLATE_DIR`, `WORDPRESS_ROOT`, `SSL_DIR`, `SSL_CERT_DIR`, `SSL_KEY_DIR`, `APACHE_DIR`.

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
- `--domain NAME` adds a domain to the list (repeatable).
- `--apache-dir DIR [APACHE_DIR]` sets the Apache sites directory with highest priority.

Options (shared):
- `--wp-root PATH [WORDPRESS_ROOT]`
- `--ssl-dir DIR [SSL_DIR]`
- `--allow-root`, `--no-sudo`
- `--help`

Environment variables:
- `APACHE_DIR`, `WORDPRESS_ROOT`, `SSL_DIR`.

### WordPress Layer Interfaces

#### setup-wp.sh (production/installation)

Purpose:
- Bootstraps a WordPress multisite base configuration. It is intentionally self-contained for early-stage setup and does not expose CLI options.

Arguments:
- None.

Options:
- `--help` shows help.

Environment variables:
- `WORDPRESS_ROOT` can be set to override the default WordPress root path; if unset, the script uses `/var/www/html/wordpress`.

Notes:
- The header includes upstream reference links for MySQL, Apache, and PHP setup, and the script expects you to follow those instructions before enabling multisite.

#### install-site.sh (production/installation)

Purpose:
- Creates a new WordPress multisite site and maps it to an apex domain.

Arguments:
- `<domain> [title] [email]` where `domain` can also be supplied via `--domain`.

Options:
- `--domain NAME` supplies the domain as an option.
- `--wp-root PATH [WORDPRESS_ROOT]` sets the WordPress root used for WP-CLI with highest priority.
- `--help`.

Environment variables:
- `WORDPRESS_ROOT`.

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
- `--domain NAME` adds a domain to the list (repeatable).

Options (shared):
- `--wp-root PATH [WORDPRESS_ROOT]`
- `--allow-root`, `--no-sudo`
- `--help`

Environment variables:
- `WORDPRESS_ROOT`.

### Orchestration Layer Interfaces

#### verify-domain.sh (verification/investigation)

Purpose:
- Runs `check-origin.sh`, `check-wp.sh`, and `check-edge.sh` in sequence for each domain.

Arguments:
- One or more domain names, provided positionally or via `--domain` (repeatable).

Options (script-specific):
- `--api` passes `--api` to `check-edge.sh`.
- `--hsts=true|false` passes `--hsts=true|false` to `check-edge.sh`.
- `--domain NAME` adds a domain to the list (repeatable).
- `--apache-dir DIR [APACHE_DIR]` passes the Apache sites directory to `check-origin.sh`.
- `--http-timeout SECONDS [HTTP_TIMEOUT]` passes the timeout to `check-edge.sh`.

Options (shared):
- `--ssl-dir DIR [SSL_DIR]` passes the SSL directory to `check-origin.sh`.
- `--wp-root PATH [WORDPRESS_ROOT]` passes the WordPress root to `check-origin.sh` and `check-wp.sh`.
- `--allow-root`, `--no-sudo` pass through to `check-origin.sh` and `check-wp.sh`.
- `--help`.

Environment variables:
- `HTTP_TIMEOUT`, `WORDPRESS_ROOT`, `SSL_DIR`, `APACHE_DIR`.

## Option Cross-Reference (Alphabetical)

This cross-reference lists options alphabetically and the scripts that implement them. CSV files are exports for future processing; this list is the human-readable view.

- `-e` (check-cf.sh)
- `-s` (check-cf.sh)
- `--account` (cloud-dns.sh, mcp-cf.sh, onboard-zone.sh, verify-cf-auth.sh)
- `--account-name` (onboard-zone.sh)
- `--allow-root` (check-origin.sh, check-wp.sh, verify-domain.sh)
- `--apache-dir` (apache-vhost.sh, check-origin.sh, smoke.sh, verify-domain.sh)
- `--api` (check-edge.sh, get-cert.sh, smoke.sh, verify-domain.sh)
- `--apply` (mcp-cf.sh)
- `--auth` (check-cf.sh, check-edge.sh, cloud-dns.sh, get-cert.sh, mcp-cf.sh, onboard-zone.sh, verify-cf-auth.sh)
- `--auth-file` (check-cf.sh, check-edge.sh, cloud-dns.sh, get-cert.sh, mcp-cf.sh, onboard-zone.sh, smoke.sh, verify-cf-auth.sh)
- `--auto` (get-cert.sh)
- `--autosite` (check-wp.sh, smoke.sh)
- `--bearer` (mcp-cf.sh)
- `--ca-key` (get-cert.sh, verify-cf-auth.sh)
- `--catalog` (mcp-cf.sh)
- `--create` (cloud-dns.sh)
- `--dns-provider` (onboard-zone.sh)
- `--domain` (apache-vhost.sh, check-edge.sh, check-origin.sh, check-wp.sh, cloud-dns.sh, get-cert.sh, install-site.sh, onboard-zone.sh, smoke.sh, verify-domain.sh)
- `--domains-file` (onboard-zone.sh, smoke.sh)
- `--email` (check-cf.sh, check-edge.sh, cloud-dns.sh, get-cert.sh, mcp-cf.sh, onboard-zone.sh, verify-cf-auth.sh)
- `--force` (get-cert.sh)
- `--help` (apache-vhost.sh, check-cf.sh, check-edge.sh, check-origin.sh, check-wp.sh, cloud-dns.sh, get-cert.sh, install-site.sh, mcp-cf.sh, onboard-zone.sh, smoke.sh, verify-cf-auth.sh, verify-domain.sh)
- `--hsts` (check-edge.sh, verify-domain.sh)
- `--http` (apache-vhost.sh)
- `--http-timeout` (check-edge.sh, verify-domain.sh)
- `--include-ignore` (smoke.sh)
- `--ip` (onboard-zone.sh)
- `--key` (check-cf.sh, check-edge.sh, cloud-dns.sh, get-cert.sh, mcp-cf.sh, onboard-zone.sh, verify-cf-auth.sh)
- `--manual` (get-cert.sh)
- `--multisite` (check-wp.sh, smoke.sh)
- `--multisite-domain` (onboard-zone.sh)
- `--no-csv` (onboard-zone.sh)
- `--no-sudo` (check-origin.sh, check-wp.sh, verify-domain.sh)
- `--portal-url` (mcp-cf.sh)
- `--raw` (check-cf.sh)
- `--redirect-url` (onboard-zone.sh)
- `--registrar` (onboard-zone.sh)
- `--singlesite` (check-wp.sh, smoke.sh)
- `--site-type` (onboard-zone.sh, smoke.sh)
- `--ssl` (apache-vhost.sh)
- `--ssl-dir` (apache-vhost.sh, check-origin.sh, get-cert.sh, smoke.sh, verify-domain.sh)
- `--state` (smoke.sh)
- `--template` (apache-vhost.sh)
- `--token` (check-cf.sh, check-edge.sh, cloud-dns.sh, get-cert.sh, mcp-cf.sh, onboard-zone.sh, verify-cf-auth.sh)
- `--update` (cloud-dns.sh)
- `--wp-root` (apache-vhost.sh, check-origin.sh, check-wp.sh, install-site.sh, smoke.sh, verify-domain.sh)
- `--zone` (check-cf.sh)
- `--zone-id` (check-cf.sh, verify-cf-auth.sh)

## Helper Inclusion Cross-Reference

This cross-reference lists helper scripts and the programs or tests that source them. CSV files are exports for future processing; this list is the human-readable view.

- `common.sh`: apache-vhost.sh, check-cf.sh, check-edge.sh, check-origin.sh, check-wp.sh, cloud-dns.sh, get-cert.sh, install-site.sh, mcp-cf.sh, onboard-zone.sh, setup-wp.sh, smoke.sh, test_cf.sh, test_cli.sh, test_common.sh, verify-cf-auth.sh, verify-domain.sh
- `cli.sh`: apache-vhost.sh, check-cf.sh, check-edge.sh, check-origin.sh, check-wp.sh, cloud-dns.sh, get-cert.sh, install-site.sh, mcp-cf.sh, onboard-zone.sh, smoke.sh, test_cli.sh, verify-cf-auth.sh, verify-domain.sh
- `auth.sh`: check-cf.sh, check-edge.sh, cloud-dns.sh, get-cert.sh, mcp-cf.sh, onboard-zone.sh, test_cf.sh, test_cli.sh, verify-cf-auth.sh
- `mcp.sh`: mcp-cf.sh, test_mcp.sh

## TODO (Revisit)

The items below capture small, implementation-focused follow-ups that keep helper behavior and option parsing consistent as the script surface grows.

- Helper predicates: document the shared `cf_has_env`/`cf_has_all` pattern used by `cf_has_*` helpers so future additions follow the same empty-vs-unset semantics and avoid divergent checks.
- Enum parsing: evaluate whether option values with limited sets (for example `--site-type`, `--singlesite|--multisite|--autosite`, or `--api|--manual|--auto`) should accept environment equivalents with explicit enum validation, and if so, keep CLI/env/auth error messaging aligned.
- Origin cert auth policy: revisit whether `get-cert.sh` should prefer the global API key for Origin CA issuance, with `CF_CA_KEY` as a fallback, and document the rationale and any security tradeoffs before changing the default.
