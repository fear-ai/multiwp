# Script Arguments and Environment Variables
Date: January 8, 2026

This document centralizes the arguments, environment variables, and defaults used by the scripts in `scripts/`. It emphasizes shared helpers and conventions while deferring to the scripts themselves for authoritative behavior.

## Source of Truth

Every program script prints its authoritative help via `usage()`. Headers only point to `usage()` to avoid duplication; when this document conflicts with `usage()`, update this document to match the script output.

This document is authoritative for script arguments, environment variables, and defaults. `scripts/Shell.md` is authoritative for Bash conventions and shared helper usage. `scripts/Prompt.md` encodes the Codex prompt format for applying header and `usage()` updates without altering behavior.

## Current Conventions to Preserve

Several conventions were updated recently and should not be regressed. These are summarized here so they remain visible without digging through script changes:

- Domain-oriented scripts accept `--domain` (repeatable) and positional domain arguments; domains are normalized, validated, and de-duplicated.
- A literal `--` is no longer treated specially; any arguments not consumed by option parsing are positional inputs.
- Cloudflare zone naming uses `CF_ZONE` (not `CF_ZONE_NAME`), and `cf-check.sh` validates zone names and warns if the case-sensitive input differs from the Cloudflare API response.
- `cloud-dns.sh` is IPv4-only and requires publicly routable IPv4 addresses; RFC1918, link-local, loopback, multicast/experimental, `0.0.0.0`, and `255.255.255.255` are rejected, and `.0`/`.255` addresses produce warnings.
- Standard path names are `SSL_DIR`, `APACHE_DIR`, and the template option is `--template` (not `--temp`).

## Shared Helpers and Defaults

Before listing script-specific arguments, it helps to understand the shared helpers that define defaults and common option behavior. These helpers are dependencies for many scripts, so they are introduced here before any per-script references.

### common.sh

`common.sh` defines shared defaults and utility functions. These defaults can be overridden by environment variables before invoking a script.

Defaults:
- `SSL_DIR` (default: `/etc/ssl/cloudflare-origin`)
- `SSL_CERT_DIR` (default: `${SSL_DIR}/certs`)
- `SSL_KEY_DIR` (default: `${SSL_DIR}/keys`)
- `APACHE_DIR` (default: `/etc/apache2/sites-available`)
- `WORDPRESS_ROOT` (default: `/var/www/html/wordpress`)
- `TEMPLATE_DIR` (default: `<repo>/templates`)

Privilege wrapper:
- `SUDO_BIN` (default: `sudo`) controls the `priv()` helper.
- `priv()` runs commands through `sudo` when `SUDO_BIN` is set, or runs directly when `SUDO_BIN` is empty.

Input helpers:
- `normalize_domain`, `validate_domain`, and `finalize_domains` normalize, validate, and de-duplicate domain lists.
- `validate_ipv4` enforces public IPv4 requirements for Cloudflare DNS provisioning.

### cli.sh

`cli.sh` provides shared option handlers and usage lines. Scripts that source `cli.sh` inherit a consistent set of shared options and usage lines, so the operator experience stays uniform across scripts.

Common options:
- `--allow-root` lets a script run even when `USER=root` (not recommended).
- `--no-sudo [SUDO_BIN] (default: sudo)` disables `sudo` usage inside `priv()`.
- `--wp-root PATH [WORDPRESS_ROOT] (default: /var/www/html/wordpress)` sets the WordPress root path.
- `--ssl-dir DIR [SSL_DIR] (default: /etc/ssl/cloudflare-origin)` sets the SSL directory and updates cert/key paths.

### auth.sh

`auth.sh` manages Cloudflare auth loading and API calls. Scripts that use Cloudflare APIs source this file directly; it is not loaded via `common.sh` so that non-API scripts stay lightweight.

Auth file:
- Default `CF_AUTH_FILE` is `~/.config/cloudflare/default.auth`.
- Example format: `scripts/example.auth` (values intentionally blank).
- The project expects `.auth` extensions for files under `~/.config/cloudflare/`.

Supported auth variables:
- `CF_API_TOKEN` (account API token, account-scoped)
- `CF_API_KEY` + `CF_API_EMAIL` (global API key, user-scoped)
- `CF_CA_KEY` (Origin CA User Service Key, user-scoped)
- `CF_ACCOUNT_ID` (account identifier)
- `CF_ZONE_ID` and `CF_ZONE` for zone-specific operations
- `CF_ZONE_MAIN` to prefer a “main” zone name when multiple zones exist

Auth options accepted by scripts that use Cloudflare APIs:
- `--auth-file PATH [CF_AUTH_FILE]`
- `--account ID [CF_ACCOUNT_ID]`
- `--token TOKEN [CF_API_TOKEN]`
- `--key KEY [CF_API_KEY]`
- `--email EMAIL [CF_API_EMAIL]`
- `--ca-key KEY [CF_CA_KEY]`

## Shared Option and Environment Conventions

Shared options are expressed as long options only. Scripts use `--help` for help; the short `-h` flag is intentionally not supported to keep parsing consistent across scripts.

When `usage()` lists an option, it follows a consistent format:

```
--http-timeout SECONDS [HTTP_TIMEOUT] (default: 10)  HTTP timeout for curl
```

This format makes the option, the related environment variable, and the default value visible in one line. In addition, the option lists follow a consistent order to reduce scanning time.

Option ordering:
- Script-specific flags first.
- Auth flags second (when present).
- Root and SSL path flags next.
- Common privilege flags next.
- `--help` always last.

## Shared Flags and Environment Variables

The following flags and environment variables are referenced by multiple scripts. This section documents each flag once, then the per-script sections below reference the applicable subset.

### Privilege and execution controls

These flags influence how scripts invoke privileged commands. They do not change functional behavior, but they can affect whether a script can read or write protected files.

- `--allow-root` bypasses the root guard for scripts that call `cli_require_non_root`. It should only be used for constrained environments where running as root is unavoidable.
- `--no-sudo [SUDO_BIN] (default: sudo)` sets `SUDO_BIN` to an empty string. The `priv()` helper will run commands directly as the current user instead of invoking `sudo`.
- `SUDO_BIN` (env) controls the privilege wrapper globally. Use an empty value to disable `sudo` while keeping the `priv()` call pattern intact.

### WordPress root

These flags and environment variables control where WordPress is located on disk.

- `--wp-root PATH [WORDPRESS_ROOT] (default: /var/www/html/wordpress)` sets the WordPress root path for scripts that operate on the WordPress filesystem or run WP-CLI.
- `WORDPRESS_ROOT` (env) provides the default WordPress root if the `--wp-root` flag is not supplied.

### Domain selection

Domain-oriented scripts accept domains via `--domain` (repeatable). Positional domains are still accepted for compatibility, and scripts normalize, validate, and de-duplicate the final list before execution.

- `--domain NAME` adds a domain to the list of domains to process.
Notes:
- Option parsing consumes known flags only; any remaining arguments are treated as positional domains. A literal `--` is treated as a domain token and will fail validation.
- Domains are normalized (lowercased and trimmed) before validation and de-duplication.

Examples:
- `check-edge.sh --domain example.com --domain www.example.com`
- `check-edge.sh example.com www.example.com`
- `cloud-dns.sh --domain example.com 203.0.113.10`
- `cloud-dns.sh example.com 203.0.113.10`

### SSL directory and certificate paths

These options define where origin certificates and keys are stored. Scripts that read or write certificates use these paths.

- `--ssl-dir DIR [SSL_DIR] (default: /etc/ssl/cloudflare-origin)` sets the SSL directory and implicitly sets the cert/key subdirectories.
- `SSL_DIR` (env) defines the base directory for origin certificates.
- `SSL_CERT_DIR` (env) defaults to `${SSL_DIR}/certs`.
- `SSL_KEY_DIR` (env) defaults to `${SSL_DIR}/keys`.

### Apache sites directory

Scripts that inspect or write vhost files use a shared Apache sites directory setting.

- `--apache-dir DIR [APACHE_DIR] (default: /etc/apache2/sites-available)` overrides the Apache sites directory.
- `APACHE_DIR` (env) defines the default Apache sites directory.

### HTTP timeouts

HTTP-oriented scripts use a shared timeout for curl requests.

- `--http-timeout SECONDS [HTTP_TIMEOUT] (default: 10)` controls connect and total timeouts for curl in edge checks.
- `HTTP_TIMEOUT` (env) provides the default timeout value.

### Cloudflare authentication

Cloudflare API scripts accept multiple credential types, each suited to a specific scope.

- `--auth-file PATH [CF_AUTH_FILE] (default: ~/.config/cloudflare/default.auth)` points to the auth file to load.
- `--account ID [CF_ACCOUNT_ID]` overrides the account ID for account-scoped calls.
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
- `CF_ZONE` should be the zone apex (for example, `example.com`), not a host like `www.example.com`.
TODO:
- Consider adding a per-domain zone mapping for `check-edge.sh` and `verify-domain.sh` to support multi-zone runs without relying on a single `CF_ZONE_ID`.

## Program Scripts by Topic and Workflow

Scripts are grouped by major topic and layer, starting with Cloudflare. Within each group, the order reflects a common operational flow. Each script is labeled as either a production/installation script or a verification/investigation script.

### Cloudflare: Authentication, Zones, Certificates, and Validation

Typical order:
1) `verify-cf-auth.sh` (validate credentials)
2) `cloud-dns.sh` (provision zone and DNS)
3) `get-cert.sh` (issue origin certs)
4) `cf-check.sh` (inspect settings)
5) `check-edge.sh` (verify edge behavior)

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
- `<domain> <ipv4>` where `domain` is the zone and `ipv4` is the origin address. Use `--domain` to provide the domain via a flag.

Options (script-specific):
- `--domain NAME` supplies the domain as a flag.

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
- `--hsts` requires the Strict-Transport-Security header.

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
- `HSTS_REQUIRED` can be set to `true` or `false` in the environment or auth file to require Strict-Transport-Security without passing `--hsts`.
TODO:
- Consider adding redirect validation options (expected status/Location) for `check-edge.sh`.

### WordPress and Apache: Installation and Provisioning

Typical order:
1) `setup-wp.sh` (bootstrap base WordPress multisite)
2) `apache-vhost.sh` (create and enable vhosts)
3) `install-site.sh` (create a multisite site and map domain)

#### setup-wp.sh (production/installation)

Purpose:
- Bootstraps a WordPress multisite base configuration. It is intentionally self-contained for early-stage setup and does not expose CLI flags.

Arguments:
- None.

Options:
- `--help` shows help.

Environment variables:
- `WORDPRESS_ROOT` is hardcoded in the script today and should be edited in the script if a different path is required.

Notes:
- The header includes upstream reference links for MySQL, Apache, and PHP setup, and the script expects you to follow those instructions before enabling multisite.

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
- `--apache-dir DIR [APACHE_DIR]` overrides the Apache sites directory.

Options (shared):
- `--wp-root PATH [WORDPRESS_ROOT]`
- `--ssl-dir DIR [SSL_DIR]`
- `--help`

Environment variables:
- `TEMPLATE_DIR`, `WORDPRESS_ROOT`, `SSL_DIR`, `SSL_CERT_DIR`, `SSL_KEY_DIR`, `APACHE_DIR`.

Notes:
- Uses templates in the templates directory and requires write access to `APACHE_DIR`.
- SSL vhosts use origin cert/key files in directories from `SSL_DIR`.

#### install-site.sh (production/installation)

Purpose:
- Creates a new WordPress multisite site and maps it to an apex domain.

Arguments:
- `<domain> [title] [email]` where `domain` can also be supplied via `--domain`.

Options:
- `--domain NAME` supplies the domain as a flag.
- `--wp-root PATH [WORDPRESS_ROOT]` overrides the WordPress root used for WP-CLI.
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

### WordPress and Apache: Verification and Investigation

Typical order:
1) `check-origin.sh` (validate origin certs and vhosts)
2) `check-wp.sh` (validate WordPress mapping)
3) `verify-domain.sh` (combined checks)

#### check-origin.sh (verification/investigation)

Purpose:
- Validates origin certificates, Apache vhost wiring, and basic Apache health.

Arguments:
- One or more domain names, provided positionally or via `--domain` (repeatable).

Options (script-specific):
- `--domain NAME` adds a domain to the list (repeatable).
- `--apache-dir DIR [APACHE_DIR]` overrides the Apache sites directory.

Options (shared):
- `--wp-root PATH [WORDPRESS_ROOT]`
- `--ssl-dir DIR [SSL_DIR]`
- `--allow-root`, `--no-sudo`
- `--help`

Environment variables:
- `APACHE_DIR`, `WORDPRESS_ROOT`, `SSL_DIR`.

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

#### verify-domain.sh (verification/investigation)

Purpose:
- Runs `check-origin.sh`, `check-wp.sh`, and `check-edge.sh` in sequence for each domain.

Arguments:
- One or more domain names, provided positionally or via `--domain` (repeatable).

Options (script-specific):
- `--api` passes `--api` to `check-edge.sh`.
- `--hsts` passes `--hsts` to `check-edge.sh`.
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

## Test and Helper Scripts

The test scripts and helper libraries are intentionally minimal. They do not parse arguments and should be run directly from the `scripts/` directory.

- `test_common.sh`, `test_cli.sh`, `test_cf.sh` run unit checks for shared helpers.
- `common.sh`, `cli.sh`, `auth.sh` provide shared logic and should not be executed directly.

## Option Cross-Reference (Alphabetical)

This cross-reference lists options alphabetically and the scripts that implement them.

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

This cross-reference lists helper scripts and the programs or tests that source them.

- `common.sh`: apache-vhost.sh, cf-check.sh, check-edge.sh, check-origin.sh, check-wp.sh, cloud-dns.sh, get-cert.sh, install-site.sh, setup-wp.sh, verify-cf-auth.sh, verify-domain.sh, test_common.sh, test_cli.sh, test_cf.sh
- `cli.sh`: apache-vhost.sh, cf-check.sh, check-edge.sh, check-origin.sh, check-wp.sh, cloud-dns.sh, get-cert.sh, verify-cf-auth.sh, verify-domain.sh, test_cli.sh
- `auth.sh`: cf-check.sh, check-edge.sh, cloud-dns.sh, get-cert.sh, verify-cf-auth.sh, test_cli.sh, test_cf.sh
