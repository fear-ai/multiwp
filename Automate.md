# Automation for Evaluation and Compliance
Date: January 5, 2026

## Introduction
This document proposes automation to evaluate the multisite environment against the instructions and recommendations documented in this repository. The intent is verification, not provisioning, so each script is designed to read and validate state without changing production settings. This keeps automation aligned with the operational runbooks while reducing the time needed to confirm a domain is compliant.

## Scope and Assumptions
These checks are scoped to the layers documented in CloudflareSettings.md and ConfigServers.md, and they assume that onboarding steps have already been completed. In particular, the automation assumes Cloudflare proxying is enabled, origin certificates are installed, Apache vhosts exist, and WordPress multisite is configured. Where a step depends on privileged access (for example, reading origin certs or running wp-cli as www-data), the script will document the requirement and fail fast if it is not met.

## Dependency Order
The evaluation order mirrors the operational dependency chain so that each layer is validated before the next layer relies on it. Cloudflare edge behavior depends on correct DNS and zone configuration; the origin depends on valid certificates and vhost wiring; and WordPress routing depends on Apache and the database being aligned. This order ensures failures are explained at the layer they originate from, rather than surfacing downstream symptoms.

## Proposed Automation Suite
The evaluation helpers below are implemented in `scripts/`. Each script produces a clear pass/fail summary and an explanation of the dependency it validates, and each one uses `common.sh` for logging and privilege handling so that access requirements are explicit and consistent with the runbooks.

### `scripts/check-edge.sh`
This script evaluates public edge behavior so it matches the expectations in CloudflareSettings.md. It depends on DNS being resolvable and on the domain being proxied through Cloudflare.

The script should:
- Resolve apex and `www` records and fail if they do not resolve.
- Issue HTTP and HTTPS `HEAD` requests and confirm an HTTP→HTTPS redirect is in place.
- Confirm the response indicates Cloudflare proxying (for example, `cf-ray` and `server: cloudflare`).
- Verify expected security headers from Cloudflare Managed Transforms are present (HSTS, X-Content-Type-Options, X-Frame-Options, Referrer-Policy, and related headers).
- Optionally query Cloudflare APIs for SSL mode and related settings when a token and zone id are provided, while treating the UI as authoritative.

### `scripts/check-origin.sh`
This script validates the origin layer described in ConfigServers.md and should be run as the Ubuntu operator with sudo access and membership in the `ssl-cert` group. It confirms that the local system is prepared to serve the site as configured.

The script should:
- Verify origin cert and key files exist at `/etc/ssl/cloudflare-origin/{certs,keys}` and are readable by the `ssl-cert` group.
- Validate cert metadata (subject, issuer, dates, SANs) using `openssl` for the target domain.
- Confirm Apache is active and that `apache2ctl configtest` passes.
- Confirm required Apache modules (`rewrite`, `ssl`, `headers`) are enabled.
- Verify expected vhost files exist and point at the correct document root and certificate paths.

### `scripts/check-wp.sh`
This script validates multisite configuration and domain mapping as documented in ConfigServers.md. It should run `wp` as `www-data` and use the configured WordPress root path from `common.sh`.

The script should:
- Confirm multisite is installed and active (`wp core is-installed --network`).
- Verify that `wp_blogs` entries map the domain to `/`.
- Confirm `siteurl` and `home` for the site use `https://<domain>`.
- Verify the domain appears in `wp site list` with the expected URL.
- Optionally check that `wp-config.php` includes multisite constants and that `.htaccess` reflects the multisite rewrite rules.

### `scripts/verify-domain.sh`
This script orchestrates the other checks for a single domain, producing a single report with a failure reason and suggested remediation. It depends on the other scripts and should not perform actions that modify the system state.

The script should:
- Run `check-origin.sh` and `check-wp.sh` locally.
- Run `check-edge.sh` against the public domain.
- Summarize results in a single pass/fail statement with the first failure highlighted for faster triage.

### `scripts/verify-cf-auth.sh`
This script validates Cloudflare API credentials before you run API-backed checks or automation. It verifies account-scoped tokens against the account endpoint and falls back to the user endpoint when the token is user-scoped.

The script should:
- Confirm at least one credential is valid (token and/or global key).
- Use account verification when `CF_ACCOUNT_ID` is present and user verification as a fallback.

## Coverage Comparison by Layer
This comparison summarizes how the evaluation scripts in `scripts/` relate to the existing operational scripts in `scripts/`. To avoid repetition, the detailed checks remain in the section above, and this section focuses on intent and scope differences while keeping the dependency order consistent with the runbooks.

### Cloudflare Edge and Public Behavior
The edge layer is where HTTP→HTTPS redirects, proxying, and response headers are enforced, so validation focuses on observable behavior while operational scripts focus on provisioning assets for the edge.

- **Validation (`scripts/check-edge.sh`)**: Validates public edge behavior as described above, including DNS resolution and proxy/header expectations.
- **Operational scripts (`scripts/cloud-dns.sh`, `scripts/get-cert.sh`)**: Create zones and DNS records or issue/install origin certificates; they configure inputs to the edge but do not validate edge behavior.

### Origin Certificates and Apache Vhosts
Origin configuration is a prerequisite for strict TLS and correct routing, so evaluation validates health and wiring while operational scripts create or install the required files.

- **Validation (`scripts/check-origin.sh`)**: Confirms origin health and configuration alignment as described above, including cert presence, vhost references, and Apache readiness.
- **Operational scripts (`scripts/get-cert.sh`, `scripts/apache-vhost.sh`)**: Install or issue origin certs and generate/enable vhosts; they are intended for setup, not compliance reporting.

### WordPress Multisite Mapping
WordPress routing depends on the origin layer, so validation inspects the multisite state and mapping data without updating them.

- **Validation (`scripts/check-wp.sh`)**: Confirms multisite state and mapping consistency as described above, using WP-CLI and direct database reads.
- **Operational scripts (`scripts/install-site.sh`)**: Creates a site and updates database mappings; it is an onboarding tool rather than a verification step.

### End-to-End Evaluation
The orchestrator script exists to chain the layered checks and provide a single pass/fail report.

- **Validation (`scripts/verify-domain.sh`)**: Runs edge, origin, and WordPress checks per domain and reports the first failure for faster triage.
- **Operational scripts**: No equivalent orchestration tool exists in `scripts/` today.

### Base System and Bootstrap
Bootstrap tooling initializes the host and WordPress core, and it is not part of the evaluation suite.

- **Validation**: None; the evaluation scripts assume the base system already exists.
- **Operational (`scripts/setup-wp.sh`)**: Performs initial server and WordPress setup, which should be completed before running evaluation checks.

## What Automation Does Not Cover
Some verification tasks cannot be fully automated because they rely on UI-only settings, external registrars, or behavior that is inherently timing- or client-dependent. These gaps should be explicitly documented in each script’s output so operators know what to check manually.

The main gaps include:
- Cloudflare features that are UI-only or account-policy controlled and not reliably exposed by API for the plan in use.
- Registrar-side status (transfers, locks, approvals), which lives outside Cloudflare and this repository.
- Browser-level issues such as mixed-content warnings, cookie scoping, or CSP interactions.
- DNS and configuration propagation delays, which can appear transiently incorrect depending on timing and cache state.
- WAF, cache, or rate-limiting behavior that requires traffic analysis rather than a single request.

## Other Methods to Verify the Gaps
When automation is insufficient, the following methods provide authoritative confirmation without deviating from the documented workflow.

Recommended manual checks include:
- Use the Cloudflare dashboard to verify SSL mode, HTTPS enforcement, and Managed Transforms, treating the UI as the source of truth.
- Use a browser with devtools open to inspect redirect chains, headers, and mixed-content errors.
- Inspect Apache access and error logs, and Cloudflare analytics, to confirm real traffic paths and error patterns.
- Validate DNS from multiple resolvers to reduce false negatives caused by propagation or cache.
- Use `openssl s_client` and `curl --resolve` for deeper TLS validation when necessary.

## Implementation Notes
These scripts are implemented as read-only validation helpers and should not modify production configurations, DNS, or database state. Any optional API usage is gated behind explicit environment variables and should fail gracefully when unavailable. This approach keeps the automation aligned with the documented workflows and minimizes operational risk.

Cloudflare API credentials can be loaded from a local auth file via `scripts/auth.sh`. The loader respects pre-existing environment variables, so a user can override values per run while still keeping a secure default file. Set `CF_AUTH_FILE` to point at the auth file path (for example, `~/.config/cloudflare/default.auth`) when you want the scripts to load credentials from disk instead of the current environment. The `~/.config/cloudflare` path is an example location; store auth files anywhere and rely on `CF_AUTH_FILE` to point at them.

## Placement Recommendations
Some topics in this document could be relocated or summarized in other files to keep the runbooks focused while avoiding duplication. The list below identifies where each topic naturally fits and why, without changing the existing sources of truth.

- **Cloudflare edge validation details** could be summarized in CloudflareSettings.md under the Automation section, because that runbook already owns edge policy and UI workflows. A brief pointer to `scripts/check-edge.sh` would keep readers in the same context while avoiding duplication of the full validation narrative.
- **Origin validation details** could be summarized in ConfigServers.md under Validation & Debug Checks, since it already enumerates command-line checks for certificates, Apache, and vhosts. A single paragraph referencing `scripts/check-origin.sh` and `scripts/check-wp.sh` would align with existing verification guidance.
- **High-level automation overview** could be referenced in README.md as a short “Validation Automation” subsection, because README.md is the entry point and should expose the existence of evaluation tooling without restating the full process.
- **Strategic rationale for read-only automation** belongs in MULTI.md if you want a durable explanation of tradeoffs; this would keep operational files focused on steps and keep strategic reasoning in the architecture document.
