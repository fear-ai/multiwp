# Boolean Handling Prompt
Date: January 9, 2026

This prompt standardizes boolean parsing in scripts that read external configuration (environment variables, auth files, or CLI options). It focuses on consistent parsing and precedence without changing functional behavior.

```text
Rules:
- Parse any boolean values from environment or auth files with parse_bool (from common.sh) and normalize to true|false.
- Accept true/false and yes/no/y/n (case-insensitive). Reject anything else.
- Treat empty or unset values as “use default.” Do not treat empty as implicit true or false.
- For boolean CLI options, use value-style syntax: --flag=true|false. Do not rely on bare --flag toggles for boolean settings tied to env/auth.
- Do not enumerate accepted tokens in usage(); only show the priority and default, for example: --hsts=true [HSTS_REQUIRED] (default: false).
- Preserve existing behavior and outputs. Change only boolean parsing or validation code.
- Apply the standard parameter precedence: code defaults (lowest), then auth files, then environment, then command-line options (highest).
- If parse_bool fails, emit a concise error and exit non-zero.
- Do not add new dependencies to scripts that are intentionally self-contained.
```

## Script Targets

Apply this prompt to all scripts that process external configuration (environment variables, auth files, or CLI options). This includes:

- `scripts/apache-vhost.sh`
- `scripts/cf-check.sh`
- `scripts/check-edge.sh`
- `scripts/check-origin.sh`
- `scripts/check-wp.sh`
- `scripts/cloud-dns.sh`
- `scripts/get-cert.sh`
- `scripts/install-site.sh`
- `scripts/setup-wp.sh`
- `scripts/verify-cf-auth.sh`
- `scripts/verify-domain.sh`

`scripts/common.sh` is a helper and is only in scope for adding or maintaining `parse_bool`.

## Verification

- `bash -n scripts/*.sh`
- `./scripts/test_common.sh`

Run additional script-specific tests if they exist.
