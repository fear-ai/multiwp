# Validation and Deployment Plan
Date: January 12, 2026

This plan sequences validation and deployment of the automation scripts for configuring dozens of domains. Each step introduces dependencies before they are referenced and separates provisioning from verification to reduce risk. The plan reflects the current script set and documentation structure; future changes are tracked separately so active work is not mixed with pending decisions.

## Current State
The script interfaces and documentation structure have been stabilized and aligned across the current toolset. `scripts/Scripts.md` and `scripts/Shell.md` now define the authoritative CLI conventions, and the script suite includes unit tests for shared helpers and Cloudflare-specific logic. The runbooks (README and Operations) have been updated to align with the current operational flow. MCP-related tooling exists (`mcp-cf.sh` and `CloudflareMCP.md`) but remains early-stage and is not part of the core production flow yet.

## Active Plan
The steps below are ordered so dependencies are resolved before downstream automation relies on them.

1) Scope and prerequisites
Gather the domain inventory, map each domain to the correct Cloudflare account/zone, and classify domains as full origin-backed sites or redirect-only domains (via `site_type` and `redirect_url`). Confirm credentials and auth files are consistent, and decide which credential types (token, key, CA key) are allowed per account so subsequent automation is deterministic.

2) Interface confirmation
Confirm CLI options, usage format, and helper behavior are aligned with current scripts. Ensure `scripts/Scripts.md`, `scripts/Options.csv`, `scripts/Helpers.csv`, `scripts/Prompt.md`, and `scripts/example.auth` are consistent so automation tooling relies on a clear contract.

3) Read-only validation pipeline
Run linting and unit tests, then execute read-only verification scripts (`verify-cf-auth.sh`, `check-cf.sh`, `check-edge.sh`, `check-origin.sh`, `check-wp.sh`, `verify-domain.sh`) on a small pilot set. Use the domain inventory format (Pending 1) to pull a representative sample: at least one domain per Cloudflare account, one redirect-only domain (non-empty `redirect_url`), one fully provisioned multisite domain, and one intentionally incomplete/test domain. Define pass/fail criteria and stop if any credential or API mismatch appears.

4) Batch automation runner
Implement a runner that reads the domain inventory format (Pending 1), separates provisioning steps (DNS, cert issuance, vhosts) from verification steps, and logs per-domain outcomes with retries and idempotent behavior. Treat non-empty `redirect_url` as redirect-only so origin/WP checks are skipped.

5) Rollout and operations
Run a pilot batch, then expand to larger batches before full deployment. Collect error patterns, refine scripts, and schedule periodic verification to catch drift in settings, certs, and WordPress mappings.

## Pending
The items below are active but not yet completed.

1) Domain inventory file format
Define and document the input format for batch runs, including Cloudflare account mapping, redirect-only markers, and per-domain overrides. The current working header is stored in `domains.csv` at the repo root and is the format to build around.

Current header (CSV):
`domain,registrar,dns_provider,ip,auth_file,zone_id,zone_name,account_id,account_email,site_type,multisite_domain,redirect_url,wp_blog_id,vhost,db_name,db_user,wp_root,wp_admin,wp_config,status_cf,status_origin,status_wp,notes`

Field notes:
- `account_id` and `account_email`: cached account identifiers for auditing. These must match the `.auth` file referenced by `auth_file` and should be treated as optional caches rather than authoritative data.
- `site_type`: classify each domain as `multisite`, `standalone`, or `redirect` to drive which checks and provisioning steps are applied.
- `multisite_domain`: the primary network domain for multisite mapping (for example, `alphaeos.net`).
- `redirect_url`: non-empty means redirect-only; use this to drive DNS redirect lists and to skip origin/WP checks.
- `wp_blog_id`: optional cached blog ID from `wp_blogs` for mapped multisite domains.
- `status_cf`: track the latest confirmed Cloudflare state. Use `none` before any tests pass, `redirect` for redirect-only domains with passing edge behavior, `worker` for Cloudflare Pages/Workers sites, `https` for standard sites with passing edge checks, and `ignore` for excluded domains.
- `status_origin`: track the latest confirmed origin state. Use `none` before any tests pass and `apache` once `check-origin.sh` succeeds for the domain.
- `status_wp`: track the latest confirmed WordPress state. Use `none` before any tests pass, `install` after WordPress is detected as installed, `config` after `check-wp.sh` validations pass, and `load` once the home page is verified via WP-CLI and via curl.
- `notes`: free-form operational notes per domain.

This format supports both step 3 (read-only validation) and step 4 (batch provisioning) without additional sidecar files.

Comparison to the plan proposal:
The plan’s inventory requirement focuses on three dependencies: account and zone mapping, redirect-only classification, and credential consistency. The CSV header supports account and zone mapping by pairing each domain with its `auth_file` (account binding) and the zone identifiers (`zone_id`, `zone_name`). Redirect-only classification is handled by `site_type` and `redirect_url`. The additional origin and WordPress fields (`vhost`, `db_name`, `db_user`, `wp_root`, `wp_admin`, `wp_config`) go beyond the minimal requirements, but they allow the batch runner to gate provisioning steps with explicit, per-domain context instead of relying on global defaults.

The only gap relative to the plan proposal is the credential policy itself: the plan calls for deciding which credential types are allowed per account, but that policy is not expressed in the CSV header. If we want the inventory file to encode it explicitly, we should add a column such as `cred_policy` or `auth_types` (for example, `token,key,ca_key`) or rely on the auth file conventions and document the policy there. Until that decision is made, the CSV header remains sufficient for validation and batch orchestration, but credential governance must be tracked elsewhere.

Format notes:
- Cloudflare account IDs (stored in the `.auth` files) are 32-character lowercase hex strings (examples: `c791ff55a5b07193bdf7faa929a70bc5`, `97268914ae96e741200e074c613bb6d2`).
- Origin CA keys observed so far use the pattern `v1.0-` + 24 lowercase hex + `-` + 146 lowercase hex (total length 176). The hyphens appear after the `v1.0` prefix and after the first 24-hex segment.
- Account API tokens are URL-safe strings that may include hyphens. Observed samples are 40 characters and use only letters, digits, and `-`; hyphens appear optionally. Treat this as a sanity-check format only, not a hard validator.

2) Redirect-only handling
Confirm which domains are permanently redirect-only and ensure `redirect_url` values are authoritative for batch runs.

3) MCP validation scope
Decide whether `mcp-cf.sh` should be included in any operational checks or remain a separate exploratory tool until access workflows are fully stabilized.

4) Install output capture
Define and document the install-time output fields that are recorded for later CSV updates and verification. Capture values that are visible during or immediately after install:
- WordPress: `blog_id` (from site create or `wp_blogs`), `wp_blogs` row (domain/path), `siteurl` and `home` values, and the affected `wp_<blog_id>_options` table name.
- Origin: vhost filenames created/enabled, origin cert/key paths, and Apache config test status.
- Cloudflare: resolved zone ID, DNS record creation results (A + CNAME), and edge setting status after changes.
- Operational summary: whether the domain is multisite, standalone, or redirect-only, plus a short success/failure summary.

5) Cloudflare interface enhancements
Evaluate whether to add redirect validation options to `check-edge.sh` (expected status and Location) once the current redirect-only behavior is stable.

6) Cloudflare zone selection improvements
Decide whether `check-edge.sh` and `verify-domain.sh` should support per-domain zone mappings rather than relying on a single `CF_ZONE_ID` per run, and document the chosen approach.

7) Cloudflare settings hygiene
Consider adding explicit handling for clearing CF_* variables on the CLI, and whether `check-cf.sh` should iterate `CF_ZONE_IDS` when no zone is supplied. These are candidates for a future hardening pass, not active behavior.

## Open Questions
These items require investigation or a policy decision before they can be closed.

1) WordPress roots
Document single-domain WordPress roots (for example, `/var/www/html/zero.directory`) in Operations.md so operators know when to set `--wp-root` or `WORDPRESS_ROOT` for standalone installs.

2) Origin CA key format guidance
Decide whether to add a warn-only validator for Origin CA keys based on the current observed format (`v1.0-` prefix with hex segments) and document where that warning should appear in script output.
