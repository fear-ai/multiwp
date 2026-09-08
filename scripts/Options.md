# Script Options and Environment Reference

Authoritative definitions for every option and environment variable exposed by the
scripts in `scripts/`. Entries must match the script's own `usage()` text exactly.

Companion documents:

- `scripts/Scripts.md` — script catalog, roles, and conventions.
- `scripts/Generated.md` — which script implements which option (generated).
- `scripts/Shell.md` — Bash conventions and shared helper usage.

---

## Shared Conventions

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

### Domain arguments

Unless a script's own entry says otherwise, domain-taking scripts accept **one or
more domain names, positionally or via `--domain` (repeatable)**. Per-script
entries below do not restate this; they list only what differs.

### Zone resolution and site-type filtering

These apply wherever the relevant option exists; per-script entries do not restate them.

- Zone IDs are resolved in priority order: auth file match (by zone name), then `domains.csv` (`zone_id`), then API lookup.
- Domains with `site_type=none`, `site_type=ignore`, or `site_type=worker` are skipped entirely.
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
The `site_type` column captures intent rather than validation. Empty values normalize to `none`, and `site_type=none`, `site_type=ignore`, and `site_type=worker` are explicit skip markers in `check-verify.sh` and `test-record.sh`. If a domain needs validation or provisioning, set `site_type` to an explicit intent such as `--singlesite`, `--multisite`, or `redirect`.
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
- Onboarding option: `onboard-zone.sh` uses `--ip` (and env `IP`) as the canonical interface. With no CLI, env, or CSV value, redirect-only zones default to `192.0.2.1` (IANA TEST-NET-1, non-routable) and other site types require an explicit address. The origin address is not hardcoded in the scripts.

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

Common auth arguments: --auth, --auth-file, --account, --account-name, --token, --key, --email, --ca-key, --token-file, --key-file, --ca-key-file.

Secret handling:
- `--token-file PATH`, `--key-file PATH` and `--ca-key-file PATH` read the secret
  from a file and are the preferred form. The file must be mode 600 or 400; any
  other mode is refused.
- `--token`, `--key` and `--ca-key` take the secret as an option value. They
  still work, but the value lands in the process's argv (readable by other local
  users through `ps auxww`) and in shell history, so each use emits a warning
  once per run. If one must be used interactively, type the command with a
  leading space so it is kept out of history — this relies on `HISTCONTROL`
  containing `ignorespace`, which is Ubuntu's `~/.bashrc` default.
- Credentials are never passed to `curl` on the command line: `auth.sh` writes
  them to a `curl -K` config file created under `umask 077` and removed by a trap.

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

The following scripts are read-only by design and do not modify DNS, certificates, Apache configuration, or WordPress data. Read-only scripts: `check-edge.sh`, `check-cf.sh`, `verify-cf-auth.sh`, `check-auth.sh`, `check-server.sh`, `check-origin.sh`, `check-wp.sh`, `perf-load.sh`, `check-domain.sh`. Unit tests: `test_common.sh`, `test_cli.sh`, `test_cmd.sh`, `test_cf.sh`.

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

#### rules-cf.sh (production/installation)

Purpose:
- Gets, puts, or copies Cloudflare rulesets (firewall, cache, rate) between zones using a portable JSON file.

Arguments:
- None. Domains are supplied via `--src` (get/copy) and `--dest` (put/copy).

Options (script-specific):
 - `--get` selects get mode (default).
 - `--put` applies rules from a JSON file to target zones.
 - `--copy` gets rules from `--src` then puts them to `--dest`.
 - `--type TYPE` selects rule type: `firewall`, `cache`, or `rate` (default: `cache`).
 - `--src NAME` sets the source zone apex for get/copy.
 - `--dest NAME` adds a target zone (repeatable; put/copy).
 - `--file PATH` sets the rules file path (default: `<src>_<phase>.json`, phase derived from `--type`).
 - `--all` includes disabled rules in the export.
 - `--allow-redirects` allows put operations for redirect-only domains.

Common arguments: --auth, --auth-file, --token, --key, --email, --help.

Environment variables:
Cloudflare auth variables listed in `auth.sh`.

Notes:
- `--get` writes the export to the current working directory unless `--file` supplies a path. Use `--file conf/<zone>_<phase>.json` to keep exports alongside the other ruleset files.
- A preset `CF_ZONE_ID` is reused only when `CF_ZONE` matches the destination domain; otherwise the zone ID is resolved per `--dest`. Without that guard an auth file's `CF_ZONE_ID` sends every destination's rules to the auth file's own zone while still logging success.
- Free plans reject rate-limit periods other than 10 seconds. A rule using `period: 60` fails with `not entitled to use the period 60, can only use a period among [10]`.

Notes:
- Get strips rule IDs and zone-specific metadata so files remain portable.
- Get exits with a clear error if the phase has no rules, or if only disabled rules exist and `--all` is not set.
- Put replaces the entire ruleset for the target zone; there is no merge behavior.
- The rules file may retain a `phase` value; if missing, the script uses the phase implied by `--type`.
- Applying rules to redirect-only domains requires `--allow-redirects` so the intent is explicit.

#### cloud-settings.sh (production/installation)

Purpose: Applies the Cloudflare HTTPS and security baseline (SSL mode, HTTPS enforcement, minimum TLS version, and managed headers) across one or more zones.

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
- DNS records and redirect rules are not modified; use `cloud-dns.sh` and `cloud-redirect.sh` for those changes.

#### onboard-zone.sh (production/installation)

Purpose: Creates or ensures a Cloudflare zone exists, provisions the baseline DNS records, and records the zone metadata back into `domains.csv` for inventory tracking.

Arguments:
- `<ip>` is accepted positionally if `--ip` is not supplied.

Options (script-specific):
 - `--domain NAME`
 - `--ip IP [IP]` sets the IPv4 address for the apex A record. Redirect-only zones default to `192.0.2.1`; other site types require an explicit value.
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

#### get-cert.sh (production/installation)

Purpose:
- Issues or installs Cloudflare Origin certificates and keys for domains.

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
  6. Security headers require `x-content-type-options`, `x-frame-options`, and `referrer-policy`. `strict-transport-security` is evaluated separately based on `HSTS_REQUIRED`. `x-xss-protection` and `expect-ct` are treated as optional and reported.
  7. WordPress asset marker verification in the canonical HTTPS response, requiring `/wp-content/` or `/wp-includes/` in the HTML body.
  8. Cloudflare API checks (only when `--api` is provided).

### Host Layer Interfaces

#### check-server.sh (verification/investigation)

Purpose:
- Reports host-level Ubuntu, networking, and data service settings aligned to `HardenUbuntu.md`, including Apache module and listener baselines.

Arguments:
- None.

Options (script-specific):
`--help`.

Common arguments: --allow-root, --no-sudo.

Notes:
- The script is read-only and reports the current state only.
- Use the output alongside `HardenUbuntu.md` to validate baseline configuration.
- Apache module surface, listeners, and tuning values are reported here so per-domain origin checks remain focused on vhost wiring.

### Origin Layer Interfaces

#### apache-vhost.sh (production/installation)

Purpose:
- Adds Apache vhosts for one or more WordPress domains and enables the sites.

Options (script-specific):
 - `--http` creates HTTP vhosts only.
 - `--ssl` creates SSL vhosts only.
 - `--domain NAME`
 - `--template PATH [TEMPLATE_DIR]` sets the templates directory.

Common arguments: --wp-root, --ssl-dir, --help.

Environment variables:
`TEMPLATE_DIR`, `WORDPRESS_ROOT`, `SSL_DIR`, `SSL_CERT_DIR`, `SSL_KEY_DIR`, `APACHE_DIR`.

Notes:
- Uses templates in the templates directory and requires write access to `APACHE_DIR`.
- SSL vhosts use origin cert/key files in directories from `SSL_DIR`.
- If both `--http` and `--ssl` are supplied, the script logs a warning and generates both vhosts (the default behavior).

#### check-origin.sh (verification/investigation)

Purpose:
- Validates per-domain origin wiring: origin certificates, vhost wiring, and document root alignment.

Options (script-specific):
 - `--domain NAME`

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
- Host-wide Apache module, listener, and service checks belong to `check-server.sh` rather than this per-domain script.
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

Common arguments: --auth-file, --domains-file, --http-timeout, --hsts, --wp-root, --apache-dir, --ssl-dir, --allow-root, --no-sudo, --help.

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

These scripts support repeatable benchmarking and related maintenance tasks. Some steps generate load and others temporarily modify WordPress state, so they should be run with care on production systems.

#### back-wp.sh (maintenance/backup)

Purpose:
- Freezes WordPress file changes, enables maintenance mode, exports the database, and archives `wp-content` for a specified domain.

Options (script-specific):
 - `--domain NAME`
 - `--backup-directory DIR` (default: `/var/backups/html/<wp-root-basename>`)
 - `--run-id ID`

Common arguments: --allow-root, --no-sudo, --help.

Environment variables:
`WORDPRESS_ROOT` (used when the domain is not singlesite and `wp_root` is empty in `domains.csv`).

Notes:
- `back-wp.sh` sets `DISALLOW_FILE_MODS=true` only when it is not already true, and restores the prior value after the backup.
- Maintenance mode is activated during the backup and deactivated afterward.
- Backup outputs are written as `<domain>_<run-id>.sql` and `<domain>_wp-content_<run-id>.tgz` under the backup directory.

#### perf-load.sh (verification/investigation)

Purpose:
- Runs init or sustained load checks with `wrk2` and an explicit rate (default per mode), or runs telemetry-only checks with `--none`, with optional telemetry collection for CPU, memory, IO, and network.

Options (script-specific):
 - `--init`, `--load`, or `--none`
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
 - `--mysql-interval N`
 - `--telemetry LIST`
 - `--head`
 - `--report`
 - `--no-report`
 - `--err`
 - `--slice`

Common arguments: --help.

Environment variables:
None.

Notes:
- Defaults are mode-specific for concurrency and rate, but duration is 20s for both init and load unless overridden.
- Defaults are mode-specific and include a fixed rate: init defaults to `threads=1`, `connections=1`, `rate=10`; load defaults to `threads=2`, `connections=4`, `rate=20`.
- `perf-load.sh` prefers `/home/ubuntu/WP/wrk2/wrk` if present; set `WRK_BIN` to override the binary.
- The default output directory is `/var/tmp/multiwp/perf_<run-id>`, and output files use a per-domain prefix.
- Telemetry defaults to `sar`; use `--telemetry=none` or a comma list to change it. The default telemetry interval is 5 seconds unless overridden by `--interval`.
- When `--head` is supplied, cached headers are saved as `${prefix}_head.txt` and cache-busted headers as `${prefix}_head_bust.txt`.
- `--cache` controls whether cached, cache-busted, or both runs are executed (`both`, `cached`, `bust`).
- `--telemetry` accepts `sar`, `pidstat`, `vmstat`, `iostat`, `cgtop`, `mysql`, `all`, or `none`, and it accepts comma lists (for example, `sar,pidstat`). `all` expands to `sar,pidstat,vmstat,cgtop,mysql` (include `iostat` explicitly if desired).
- `wrk2` is used for init/load modes only and always receives `-R <rate>`, either from `--rate` or from mode defaults. `--none` skips `wrk2` and uses `--duration` as the telemetry window.
- When `--none` is used with `--report`, the report contains telemetry summaries (sar/pidstat) with `CACHE=none`.
- When running `perf-load.sh` through an external command runner, use a timeout of at least 60 seconds.
- Telemetry writes logs alongside `wrk` or `wrk2` output in the run directory. Command dependencies vary by telemetry scope.
- `sar` writes binary output (`${prefix}_sar.bin`) and uses `sadf -d` to generate `${prefix}_sar.log` for parsing; stdout from `sar` is captured in `${prefix}_sar.raw.log`. The script uses CPU and memory sections only (no run queue or device sections).
- `--report` (default) emits a per-run summary of `REQ_PER_SEC`, `LATENCY_AVG`, `LATENCY_MAX`, `TOTAL_REQUESTS`, and `NON_200`. Use `--no-report` to suppress it.
- Latency values in the report are normalized to milliseconds and formatted with comma-separated thousands and no decimals.
- `--err` writes stderr for `wrk2`, `curl`, and telemetry tools to per-run `.err` files alongside the `.txt` and `.log` outputs.
- `--slice` runs `slice-logs.sh` after each domain run using the generated `run.param` file.
- When telemetry includes `sar`, `--report` emits `CPU_TOTAL_PCT_MAX`, `CPU_TOTAL_PCT_AVG`, `CPU_BUSY_CORES_MAX`, `CPU_IDLE_PCT_MIN`, `CPU_IDLE_PCT_AVG`, `MEM_AVAIL_MB_MIN`, `MEM_AVAIL_MB_AVG`, `MEM_USED_MB_MAX`, `MEM_USED_MB_AVG`, `CPU_TOTAL_BIN5_AVG`, and `CPU_TOTAL_TREND`. `MEM_AVAIL_*` and `MEM_USED_*` are derived from `kbavail` and `kbmemused` in sar output. When telemetry includes `pidstat`, `--report` emits `APACHE_CPU_SUM_AVG`, `APACHE_CPU_SUM_MAX`, `APACHE_CPU_SAMPLES`, `APACHE_CPU_SUM_BIN5_AVG`, and `APACHE_CPU_SUM_SLOPE_PCT` under `PERF:Process` (and the same pattern for MySQL and wrk when present). Process CPU values (`*_CPU_SUM_*`) are reported as percentages representing summed per-process CPU. Telemetry sections are emitted once per domain without a cache designation, and slope values are percentages with one decimal and no descriptive labels.
- `LOAD_1_*` and the sar run queue section are postponed; only CPU and memory sections are kept in the sar log.
- When telemetry includes `mysql`, the run also writes `${prefix}_mysql-perf.log` using the MySQL sampling interval (default 5 seconds, override with `--mysql-interval`).

#### slice-logs.sh (verification/investigation)

Purpose:
- Extracts log slices for a perf run based on the `run.param` metadata file.

Arguments:
- None. All inputs are supplied as options.

Options (script-specific):
 - `--run-param PATH`
 - `--duration WINDOW`
 - `--domain NAME`
 - `--out-dir DIR`
 - `--pad SEC`
 - `--report`
 - `--no-report`

Common arguments: --help.

Environment variables:
None.

Notes:
- Reads `run.param` in `KEY: value` format and writes sliced logs using the same prefix.
- Apache log selection is best-effort and warns if a matching file is not found.
- Uses `sudo` for log reads if the file is not readable by the current user.
- If a `${domain}_admin_access.log` slice is present, the summary includes `ADMIN_*` timing values derived from the `%D` microsecond field; missing admin logs are reported as info and do not fail the run.
- When report output is enabled (default), the summary log is written to `${prefix}_logs.txt`. Use `--no-report` to suppress it.
- When a `${prefix}_report.txt` and Apache access slice exist, the script appends
  summary rows to `perf_runs.csv` and `perf_segments.csv` in the output directory.
- When `--duration WINDOW` is used (with `--domain NAME`), the script slices logs from the current UTC time back `WINDOW` and does not require a run.param file. The default unit is minutes; add `s`, `m`, `h`, or `d` for explicit units.
- When slicing by duration, the script warns if the window starts before the first timestamp found in a log file.
