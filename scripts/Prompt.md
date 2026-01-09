# Program Script Prompts
Date: January 9, 2026

This file provides a copy/paste prompt for Codex to update script headers and usage blocks without changing behavior.

## Shared Prompt

```text
Header format (top of file):
#!/bin/bash
# <script>.sh - <Short description>.
# For options, environment variables, defaults see usage().
#
# Example: <script>.sh [OPTIONS] example.com www.example.com
#
# Notes:
# - <note 1>
# - <note 2>

usage() format, first lines only, no extra Usage or Examples blocks:
<script>.sh - <Short description>.
Example: <script>.sh [OPTIONS] example.com www.example.com

Rules:
- The short description must match exactly in the header and usage().
- The header should contain only the short description line, the “For options…” line, a single-line Example, and optional Notes.
- Move any Notes content from the header into usage() unless there is a specific reason to keep it inline.
- Any expanded explanations, requirements, or operational notes must be moved from the header into usage() under sections like Notes, Prerequisites, or What this script does.
- Do not add separate “Usage:” or “Examples:” blocks beyond the single-line Example.
- usage() must be a single heredoc ending at the end of the function. If helper output is needed (for example, cli_usage_wp_root), embed it via command substitution inside the heredoc so the EOF is last.
- Order options in usage() as: script-specific, auth, wp-root, ssl, common, then --help last.
- If the script accepts domains, include --domain in options and keep positional arguments valid. A literal -- is not treated specially, so do not use it in examples.
- Examples should use realistic placeholders like example.com and www.example.com, not domain1 or similar. Avoid bracketed optional domains and angle-bracket placeholders in examples.
- Cloudflare zone naming uses CF_ZONE, and cf-check.sh normalizes and validates zone names and warns if the case-sensitive input differs from the Cloudflare API response.
- cloud-dns.sh is IPv4-only and validates public IPv4 addresses. RFC1918, link-local, loopback, multicast/experimental, 0.0.0.0, and 255.255.255.255 are rejected; .0 and .255 addresses produce warnings.
- Boolean values from env/auth files must be parsed via a helper (for example, parse_bool in common.sh). Accept true/false and yes/no/y/n (case-insensitive), but do not enumerate accepted values in usage() beyond the priority and default.
- Boolean options that mirror env/auth settings use value-style `--name=true|false`, not bare toggles.
- Use long options only; --help is the only help option.
- Standard names are SSL_DIR, APACHE_DIR, and --template.
- Use WORDPRESS_ROOT with --wp-root; do not document or reference --root.
- Omit any category the script does not support; do not add placeholders.
- Preserve existing behavior; only adjust header and usage() formatting and ordering.
```

## Validation Checklist

Read-only checks:
- `bash -n scripts/*.sh`

Executable tests:
- `./scripts/test_common.sh`
- `./scripts/test_cli.sh`
- `./scripts/test_cf.sh`

## Script Targets

Apply the shared prompt to these scripts.

- `scripts/apache-vhost.sh` — Add Apache vhosts for WordPress domains. Example: `apache-vhost.sh [OPTIONS] example.com www.example.com`
- `scripts/cf-check.sh` — Inspect Cloudflare zone settings via the API. Example: `cf-check.sh [OPTIONS] example.com`
- `scripts/check-edge.sh` — Validate Cloudflare edge behavior for domains. Example: `check-edge.sh [OPTIONS] example.com www.example.com`
- `scripts/check-origin.sh` — Validate origin certificates, Apache configuration, and vhost wiring. Example: `check-origin.sh [OPTIONS] example.com www.example.com`
- `scripts/check-wp.sh` — Validate WordPress site URLs for domains. Example: `check-wp.sh [OPTIONS] example.com www.example.com`
- `scripts/cloud-dns.sh` — Create a Cloudflare zone via the API and add basic DNS records. Example: `cloud-dns.sh example.com 203.0.113.10`
- `scripts/get-cert.sh` — Issue or install Cloudflare Origin certs and keys for domains. Example: `get-cert.sh [OPTIONS] example.com www.example.com`
- `scripts/install-site.sh` — Add a new site to WordPress multisite and map to an apex domain. Example: `install-site.sh [OPTIONS] example.com "Example" admin@example.com`
- `scripts/setup-wp.sh` — WordPress multisite base configuration. Example: `setup-wp.sh`
- `scripts/verify-cf-auth.sh` — Validate Cloudflare API credentials. Example: `verify-cf-auth.sh [OPTIONS]`
- `scripts/verify-domain.sh` — Run edge, origin, and WordPress checks for domains. Example: `verify-domain.sh [OPTIONS] example.com www.example.com`
