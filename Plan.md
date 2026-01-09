# Validation and Deployment Plan
Date: January 9, 2026

This plan sequences validation and deployment of the automation scripts for configuring dozens of domains. Each step introduces dependencies before they are referenced and separates provisioning from verification to reduce risk. The plan reflects the current script set and documentation structure; future changes are tracked in a separate section to avoid mixing active work with pending decisions.

1) Establish scope and prerequisites
   Gather the domain inventory, map each domain to the correct Cloudflare account/zone, and classify domains as full origin-backed sites or redirect-only domains (for `DNS_REDIRECT`). Confirm credentials and auth files are consistent, and decide which credential types (token, key, CA key) are allowed per account so subsequent automation is deterministic.

2) Stabilize script interfaces and documentation
  Confirm CLI options, usage format, and helper behavior are aligned with current scripts. Ensure `scripts/Scripts.md`, `scripts/Options.csv`, `scripts/Helpers.csv`, `scripts/Prompt.md`, and `scripts/example.auth` are consistent so automation tooling relies on a clear contract.

3) Build a read-only validation pipeline
   Run linting and unit tests, then execute read-only verification scripts (`verify-cf-auth.sh`, `cf-check.sh`, `check-edge.sh`, `check-origin.sh`, `check-wp.sh`, `verify-domain.sh`) on a small pilot set. The pilot set should be representative: at least one domain per Cloudflare account, one redirect-only domain, one fully provisioned multisite domain, and one intentionally incomplete/test domain. Define pass/fail criteria and stop if any credential or API mismatch appears.

4) Create a batch automation runner
   Implement a runner that reads a domain inventory file, separates provisioning steps (DNS, cert issuance, vhosts) from verification steps, and logs per-domain outcomes with retries and idempotent behavior. Include redirect-only classification so origin/WP checks are skipped where `DNS_REDIRECT` applies.

5) Stage rollout and operationalize
   Run a pilot batch, then expand to larger batches before full deployment. Collect error patterns, refine scripts, and schedule periodic verification to catch drift in settings, certs, and WordPress mappings.

Futures:
Once the current interface changes settle, formalize a “locked interface” policy with change control and versioning guidance so automation tooling can depend on a stable CLI contract.

Investigations and decisions pending:
Document nonstandard WordPress roots (for example, `/var/www/html/zero.directory`) in ConfigServers.md so operators know when to set `--wp-root` or `WORDPRESS_ROOT` for standalone installs.
