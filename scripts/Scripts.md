# Script Interfaces and Configuration
Date: January 9, 2026

This document centralizes the script interfaces, configuration expectations, environment variables, and defaults used by the scripts in `scripts/`. It is the authoritative interface contract for operators and automation, and it complements `scripts/Shell.md` (Bash conventions and helper usage).

## Source of Truth

Every program script prints its authoritative help via `usage()`. Headers only point to `usage()` to avoid duplication; when this document conflicts with `usage()`, update this document to match the script output.

This document is authoritative for script interfaces, configuration, environment variables, and defaults. `scripts/Shell.md` is authoritative for Bash conventions and shared helper usage. `scripts/Prompt.md` encodes the Codex prompt format for applying header and `usage()` updates without altering behavior.

## Part A: Script Catalog (by layer)

This catalog groups scripts by operational layer and labels each script as provisioning or verification/investigation. Full option and environment-variable details live in Part B.

### Cloudflare Layer

Cloudflare scripts manage credentials, DNS, certificates, and edge validation. A typical flow starts with credential checks, provisions DNS, then issues certificates, and ends with settings and edge validation.

- `verify-cf-auth.sh` — verification (read-only)
- `cloud-dns.sh` — provisioning
- `get-cert.sh` — provisioning
- `cf-check.sh` — verification (read-only)
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

### Support and Tests

The test scripts and helper libraries are intentionally minimal. They do not parse options and should be run directly from the `scripts/` directory.

- `test_common.sh`, `test_cli.sh`, `test_cf.sh` run unit checks for shared helpers.
- `common.sh`, `cli.sh`, `auth.sh` provide shared logic and should not be executed directly.

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
- `DNS_REDIRECT` (env or auth file referenced by `CF_AUTH_FILE`) lists domains that should not have origin or WordPress presence.
- `check-origin.sh` and `check-wp.sh` skip origin/WP checks for domains listed in `DNS_REDIRECT` and treat absence as expected.
- `check-edge.sh` continues to validate redirects and security headers for all domains, including redirect-only entries.

Next steps:
- Skip edge header checks for domains listed in `DNS_REDIRECT` while still validating HTTP→HTTPS redirects and Cloudflare proxy signals.
- Add redirect-focused provisioning support to `cloud-dns.sh` (for example, record patterns or options suitable for edge-only redirect zones).

Examples:
- `check-edge.sh --domain example.com --domain www.example.com`
- `check-edge.sh example.com www.example.com`
- `cloud-dns.sh --domain example.com 203.0.113.10`
- `cloud-dns.sh example.com 203.0.113.10`

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

- `--auth-file PATH [CF_AUTH_FILE] (default: ~/.config/cloudflare/default.auth)` points to the auth file to load.
- `--account ID [CF_ACCOUNT_ID]` sets the account ID with highest priority for account-scoped calls.
- `--token TOKEN [CF_API_TOKEN]` sets the account API token.
- `--key KEY [CF_API_KEY]` sets the global API key.
- `--email EMAIL [CF_API_EMAIL]` sets the email for the global API key.
- `--ca-key KEY [CF_CA_KEY]` sets the Origin CA User Service Key.

Cloudflare zone selection:
- `--zone name [CF_ZONE]` sets the target zone name (used by `cf-check.sh`).
- `--zone-id id [CF_ZONE_ID]` sets the target zone ID (used by `cf-check.sh` and `verify-cf-auth.sh`).
- `CF_ZONE_MAIN` (env) is preferred when multiple zones exist in the auth file.
- `CF_ZONE` and `CF_ZONE_ID` (env) are read from the auth file, with the first `CF_ZONE_ID` chosen by default.
Notes:
- `CF_ZONE` must be an apex (for example, `example.com`, not `www.example.com`); auth files may list multiple `CF_ZONE_ID` values—scripts use the first by default and retain the list in `CF_ZONE_IDS`.
TODO:
- Consider adding a per-domain zone mapping for `check-edge.sh` and `verify-domain.sh` to support multi-zone runs without relying on a single `CF_ZONE_ID`.
- Allow `cf-check.sh` to iterate `CF_ZONE_IDS` when no `--zone` or `--zone-id` is supplied.

### Read-Only Scripts and Safe Options

The following scripts are read-only by design and do not modify DNS, certificates, Apache configuration, or WordPress data. Read-only scripts: `check-edge.sh`, `cf-check.sh`, `verify-cf-auth.sh`, `check-origin.sh`, `check-wp.sh`, `verify-domain.sh`. Unit tests: `test_common.sh`, `test_cli.sh`, `test_cf.sh`.

Safe options for read-only scripts:
- `--api` (enables Cloudflare API reads; no writes)
- `--hsts=true|false` (changes validation expectations only)
- `--http-timeout SECONDS`
- `--domain NAME` / positional domains
- `--zone-id ID`
- `--auth-file PATH`, `--token TOKEN`, `--key KEY`, `--email EMAIL`, `--ca-key KEY`
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
- Origin CA keys are verified with a read-only GET to `/certificates?zone_id=...`.

#### cloud-dns.sh (production/installation)

Purpose:
- Creates a Cloudflare zone and adds an apex A record plus CNAMEs for `www` and `*` pointing to the apex.

Arguments:
- `<domain> <ipv4>` where `domain` is the zone and `ipv4` is the origin address. Use `--domain` to provide the domain via an option.

Options (script-specific):
- `--domain NAME` supplies the domain as an option.

Options (auth and shared):
- `--account ACCOUNT_ID [CF_ACCOUNT_ID]`
- `--token TOKEN [CF_API_TOKEN]`
- `--key KEY [CF_API_KEY]`
- `--email EMAIL [CF_API_EMAIL]`
- `--auth-file PATH [CF_AUTH_FILE]`
- `--help`

Environment variables:
- `CF_ACCOUNT_ID`, `CF_API_TOKEN`, `CF_API_KEY`, `CF_API_EMAIL`.

Notes:
- When `--domain` is provided, positional arguments supply `<ipv4>` only.
- IPv4 must be publicly routable; RFC1918, link-local, loopback, and multicast ranges are rejected.
- IPv4 addresses ending in `.0` or `.255` are accepted but produce a warning to prompt verification.
- Planned: support marking zones as redirect-only (for example, via `DNS_REDIRECT`) so cloud-dns can provision redirect-focused DNS without origin dependencies.

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
- API mode prefers `CF_CA_KEY` when available and falls back to `CF_API_TOKEN` or `CF_API_KEY` + `CF_API_EMAIL`.
- Manual mode writes to the SSL directories derived from `SSL_DIR`.

#### cf-check.sh (verification/investigation)

Purpose:
- Inspects Cloudflare zone settings and optionally validates expected values.

Arguments:
- A single zone name, or use `--zone` / `--zone-id`.

Options (script-specific):
- `-e key=val` asserts that a setting matches the expected value (repeatable).
- `-s key[,key]` prints only selected settings (repeatable).
- `--raw` prints the raw settings JSON.
- `--zone name [CF_ZONE]` selects a zone by name.
- `--zone-id id [CF_ZONE_ID]` selects a zone by ID.

Options (auth and shared):
- `--auth-file PATH [CF_AUTH_FILE]`
- `--token TOKEN [CF_API_TOKEN]`
- `--key KEY [CF_API_KEY]`
- `--email EMAIL [CF_API_EMAIL]`
- `--help`

Environment variables:
- `CF_ZONE`, `CF_ZONE_ID`, and Cloudflare auth variables.

Notes:
- Zone names are normalized and validated before lookup. `cf-check.sh` warns (case-sensitive) if the provided zone name differs from the Cloudflare API response.

#### check-edge.sh (verification/investigation)

Purpose:
- Validates edge behavior for domains (redirects, proxy headers, and security headers).

Arguments:
- One or more domain names, provided positionally or via `--domain` (repeatable).

Options (script-specific):
- `--http-timeout SECONDS [HTTP_TIMEOUT] (default: 10)` controls curl timeouts.
- `--api` enables Cloudflare API checks and requires `CF_ZONE_ID` plus valid credentials.
- `--domain NAME` adds a domain to the list (repeatable).
- `--hsts=true|false` requires the Strict-Transport-Security header.

Options (auth and shared):
- `--auth-file PATH [CF_AUTH_FILE]`
- `--token TOKEN [CF_API_TOKEN]`
- `--key KEY [CF_API_KEY]`
- `--email EMAIL [CF_API_EMAIL]`
- `--help`

Environment variables:
- `HTTP_TIMEOUT` for curl timeouts.
- Cloudflare auth variables when `--api` is used.

Notes:
- `--api` performs Cloudflare setting checks using the single `CF_ZONE_ID` value; use separate runs if you need to validate multiple zones with different IDs.
- DNS checks report A records (required) and also report CNAME and AAAA records when present.
- `HSTS_REQUIRED` can be set to `true` or `false` in the environment or auth file to require Strict-Transport-Security without passing `--hsts=true|false`.
TODO:
- Consider adding redirect validation options (expected status/Location) for `check-edge.sh`.

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
- `WORDPRESS_ROOT` is hardcoded in the script today and should be edited in the script if a different path is required.

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

- `-e` (cf-check.sh)
- `-s` (cf-check.sh)
- `--account` (cloud-dns.sh, verify-cf-auth.sh)
- `--allow-root` (check-origin.sh, check-wp.sh, verify-domain.sh)
- `--api` (check-edge.sh, get-cert.sh, verify-domain.sh)
- `--apache-dir` (apache-vhost.sh, check-origin.sh, verify-domain.sh)
- `--auth-file` (cf-check.sh, check-edge.sh, cloud-dns.sh, get-cert.sh, verify-cf-auth.sh)
- `--auto` (get-cert.sh)
- `--autosite` (check-wp.sh)
- `--ca-key` (get-cert.sh, verify-cf-auth.sh)
- `--domain` (apache-vhost.sh, check-edge.sh, check-origin.sh, check-wp.sh, cloud-dns.sh, get-cert.sh, install-site.sh, verify-domain.sh)
- `--email` (cf-check.sh, check-edge.sh, cloud-dns.sh, get-cert.sh, verify-cf-auth.sh)
- `--force` (get-cert.sh)
- `--help` (apache-vhost.sh, cf-check.sh, check-edge.sh, check-origin.sh, check-wp.sh, cloud-dns.sh, get-cert.sh, install-site.sh, setup-wp.sh, verify-cf-auth.sh, verify-domain.sh)
- `--http` (apache-vhost.sh)
- `--http-timeout` (check-edge.sh, verify-domain.sh)
- `--hsts=true|false` (check-edge.sh, verify-domain.sh)
- `--key` (cf-check.sh, check-edge.sh, cloud-dns.sh, get-cert.sh, verify-cf-auth.sh)
- `--manual` (get-cert.sh)
- `--multisite` (check-wp.sh)
- `--no-sudo` (check-origin.sh, check-wp.sh, verify-domain.sh)
- `--raw` (cf-check.sh)
- `--wp-root` (apache-vhost.sh, check-origin.sh, check-wp.sh, install-site.sh, verify-domain.sh)
- `--singlesite` (check-wp.sh)
- `--ssl` (apache-vhost.sh)
- `--ssl-dir` (apache-vhost.sh, check-origin.sh, get-cert.sh, verify-domain.sh)
- `--template` (apache-vhost.sh)
- `--token` (cf-check.sh, check-edge.sh, cloud-dns.sh, get-cert.sh, verify-cf-auth.sh)
- `--zone` (cf-check.sh)
- `--zone-id` (cf-check.sh, verify-cf-auth.sh)

## Helper Inclusion Cross-Reference

This cross-reference lists helper scripts and the programs or tests that source them. CSV files are exports for future processing; this list is the human-readable view.

- `common.sh`: apache-vhost.sh, cf-check.sh, check-edge.sh, check-origin.sh, check-wp.sh, cloud-dns.sh, get-cert.sh, install-site.sh, setup-wp.sh, verify-cf-auth.sh, verify-domain.sh, test_common.sh, test_cli.sh, test_cf.sh
- `cli.sh`: apache-vhost.sh, cf-check.sh, check-edge.sh, check-origin.sh, check-wp.sh, cloud-dns.sh, get-cert.sh, verify-cf-auth.sh, verify-domain.sh, test_cli.sh
- `auth.sh`: cf-check.sh, check-edge.sh, cloud-dns.sh, get-cert.sh, verify-cf-auth.sh, test_cli.sh, test_cf.sh
