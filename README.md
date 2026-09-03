# WordPress Multisite Tools
Date: January 20, 2026

WordPress multisite (subdirectory mode, apex domain mapping) behind Cloudflare DNS/CDN/edge, on Apache with per-domain origin certificates. This repo holds the runbooks, scripts, and templates to host many domains this way.

**Validated environment**: Ubuntu 24.04 · Apache 2.4.58 · PHP 8.3.11 · MySQL 8.0.43 · WordPress 6.9 Multisite

---

## Quick Start: Administrator

Requires: `curl`, `dig`, `jq`, `wp`, `apache2ctl`, `openssl`, sudo on the origin host, and a Cloudflare account for the domains.

For the canonical onboarding and troubleshooting steps, start with `Operations.md` section 1 (`Operations.md#1-introduction`) and proceed through sections 3–6 (`Operations.md#3-cloudflare-edge`, `Operations.md#4-origin-tls`, `Operations.md#5-multisite-ops`, `Operations.md#6-verification`). Operations will call out when to pause and complete the host baseline in `HardenUbuntu.md` before continuing with origin TLS and multisite configuration.

### Add Site to the Network

**Goal:** Domain registered, nameservers pointed to Cloudflare, zone created in Cloudflare, and SSL/TLS configured.

1. **Configure zone on Cloudflare (UI)** — `Operations.md` section 3.4 (`Operations.md#34-https-flow`)
2. **Issue and install Cloudflare origin certificate** — `Operations.md` section 4.3 (`Operations.md#43-origin-certs`)
3. **Create Apache vhosts** — `./scripts/apache-vhost.sh domain.com`
4. **Add to WordPress multisite** — `./scripts/install-site.sh domain.com "Site Title" email@domain.com` (assumes multisite is already installed; see `Operations.md` section 5.1, `Operations.md#51-site-onboarding`, for setup)
5. **Verify** — `./scripts/check-domain.sh domain.com`

### Add a Redirect-Only Domain
1. **Create zone + DNS + inventory row** — `./scripts/onboard-zone.sh --domain domain.com --site-type redirect --redirect-url https://target.example/`
2. **Create the live Cloudflare Redirect Rule** — `./scripts/cloud-redirect.sh --domain domain.com --redirect-url https://target.example/`
3. **Point nameservers at the registrar** to the ones Cloudflare assigned (zone stays `pending` until then)

### Query Multisite Setup / Troubleshooting
Use `Operations.md` sections 5.2 and 6.1 (`Operations.md#52-site-troubleshooting`, `Operations.md#61-validation-checks`) for the authoritative validation checks and troubleshooting sequence.

---

## Documentation Map
Read in this order to keep operational dependencies clear:

- `README.md`: Entry point and quick start with the script index.
- `Operations.md`: Consolidated runbook for Cloudflare, origin, and WordPress operations in dependency order (see sections 3–6: `Operations.md#3-cloudflare-edge`, `Operations.md#4-origin-tls`, `Operations.md#5-multisite-ops`, `Operations.md#6-verification`).
- `HardenUbuntu.md`: Host hardening guidance focused on Ubuntu security baselines and verification.
- `Perf.md`: Performance strategy, tooling, and the execution runbook for benchmarking and tuning.
- `scripts/Shell.md`: Conventions for writing scripts in this repository and using shared helpers.
- `scripts/Scripts.md`: Authoritative script interfaces, options, and environment variables.
- `Record.md`: Recording policy for updating `domains.csv` across provisioning and validation steps.
- `CloudflareMCP.md` (optional, experimental): MCP portal access and validation notes; not part of the production flow.
- `MULTI.md` (optional): Strategic architecture decisions, tradeoffs, and future work (see sections 2–8: `MULTI.md#2-architecture--design-decisions`, `MULTI.md#3-network--domain-model`, `MULTI.md#4-infrastructure-layers`, `MULTI.md#5-operational-tradeoffs`, `MULTI.md#6-implementation-issues--lessons`, `MULTI.md#7-abandoned-approaches`, `MULTI.md#8-future-investigation`).
- `DNSTerms.md` (optional): DNS and Cloudflare terminology reference and vendor links.

**Ownership** (so guidance doesn't drift or duplicate):
- `Operations.md`: end-to-end operational runbook — Cloudflare edge settings, redirects, origin TLS, vhost wiring, paths, WordPress onboarding and verification.
- `HardenUbuntu.md`: Ubuntu baseline and service install/config — Apache, PHP, MySQL, SSH, UFW, sysctl, netplan, unattended upgrades.
- `MULTI.md`: architecture, design decisions, domain model rationale.
- `Perf.md`: performance methodology, tooling, and test execution.
- `Rules.md`: Cloudflare ruleset workflows and file formats.
- `scripts/Scripts.md`: script interfaces, options, environment variables. Option registry work belongs here.
- `Record.md`: `domains.csv` recording policy and update rules.
- `DNSTerms.md`: industry terminology and external references.

WordPress security settings live in `Operations.md` section 4.7 (`Operations.md#47-wp-configphp-settings`), mirrored in `templates/wp-config-*.php` comments. Keep procedural/file-level guidance in Operations (and templates); keep architectural rationale in `MULTI.md`. `HardenUbuntu.md` should not duplicate WordPress-level settings.

---

## Scripts

Scripts are grouped by role so entrypoints, orchestration runners, and shared libraries stay clear. Status is a best-effort indicator of whether a script has been exercised in this repo; update it as scripts are run.

Program scripts (entrypoints, alphabetical):
| Script | Purpose | Status |
|--------|---------|--------|
| `apache-vhost.sh` | Create Apache HTTP + SSL vhosts for domain | Exercised |
| `back-wp.sh` | Freeze and back up a WordPress site | Not exercised |
| `check-auth.sh` | Compare CF_DOMAINS in auth files to domains.csv | Not exercised |
| `check-cf.sh` | Inspect Cloudflare zone settings via API | Exercised |
| `check-edge.sh` | Validate Cloudflare edge behavior and headers | Exercised |
| `check-origin.sh` | Validate origin certs, vhosts, and Apache health | Exercised |
| `check-server.sh` | Validate Ubuntu/Apache/PHP/MySQL baseline settings | Not exercised |
| `check-wp.sh` | Validate multisite mappings and site URLs | Exercised |
| `cloud-dns.sh` | Create/update DNS records in an existing Cloudflare zone | Exercised |
| `cloud-redirect.sh` | Ensure Cloudflare Redirect Rules for redirect-only domains | Exercised |
| `cloud-settings.sh` | Apply Cloudflare HTTPS/security settings | Not exercised |
| `cloudflare-ips.sh` | Generate Cloudflare allowlist rules for UFW | Not exercised |
| `get-cert.sh` | Issue or install Cloudflare Origin cert/key (API or manual) | Not exercised |
| `install-site.sh` | Add site to WordPress multisite, map to apex domain | Exercised |
| `mcp-cf.sh` | Validate Cloudflare MCP portal access | Exercised |
| `onboard-zone.sh` | Create or ensure Cloudflare zone + DNS and update domains.csv | Not exercised |
| `perf-load.sh` | Run load tests and capture telemetry for a WordPress site | Exercised |
| `rules-cf.sh` | Get, put, or copy Cloudflare rulesets (firewall, cache, rate) | Exercised |
| `setup-wp.sh` | Bootstrap WordPress multisite base configuration | Not exercised |
| `slice-logs.sh` | Extract log slices for review and correlation | Exercised |
| `verify-cf-auth.sh` | Validate Cloudflare credentials (token/key) | Exercised |

Orchestration scripts (entrypoints):
| Script | Purpose | Status |
|--------|---------|--------|
| `check-verify.sh` | Run syntax/unit tests and read-only edge/DNS/origin/WP checks | Exercised |
| `check-domain.sh` | End-to-end validation (edge, origin, WP) | Exercised |
| `test-record.sh` | Run validation checks and record status updates in domains.csv | Not exercised |

Helper and library scripts:
| Script | Purpose | Status |
|--------|---------|--------|
| `common.sh` | Shared library functions (sourced by other scripts) | Library |
| `auth.sh` | Cloudflare auth helpers and API request utilities | Library |
| `cli.sh` | Shared option parsing helpers | Library |
| `orch.sh` | Orchestration helper functions for check runners | Library |
| `mcp.sh` | MCP helper functions | Library |

Unit test scripts:
| Script | Purpose | Status |
|--------|---------|--------|
| `test_common.sh` | Unit tests for shared helpers | Test |
| `test_cf.sh` | Unit tests for Cloudflare helpers | Test |
| `test_cli.sh` | Unit tests for CLI helpers | Test |
| `test_mcp.sh` | Unit tests for MCP helpers | Test |

**Test scripts syntax**: `bash -n scripts/*.sh`

**Permissions**: documented in `Operations.md` section 4.5 (`Operations.md#45-wordpress-files-and-permissions`); not repeated here to avoid drift.

---

## Repository Structure

```
multiwp/
├── AGENTS.md                      # AI assistant guardrails and repo-specific instructions
├── README.md                      # This file
├── MULTI.md                       # Architecture & strategic decisions
├── Operations.md                  # Consolidated operational runbook
├── HardenUbuntu.md                # Host hardening guidance focused on Ubuntu baseline controls
├── Record.md                      # Recording policy for domains.csv updates
├── DNSTerms.md                    # DNS & Cloudflare terminology
├── CloudflareMCP.md               # Cloudflare MCP notes and validation steps
├── scripts/
│   [list above]
├── templates/
│   ├── apache-http.conf           # Apache HTTP vhost template
│   ├── apache-ssl.conf            # Apache HTTPS vhost template
│   ├── htaccess-multisite         # WordPress multisite rewrite rules
│   ├── htaccess-singlesite        # WordPress single-site rewrite rules
│   ├── wp-config-multisite.php    # Multisite wp-config template
│   ├── wp-config-multisite-deployed.php # Multisite wp-config (production-style)
│   ├── wp-config-singlesite.php   # Single-site wp-config template
│   ├── wp-config-singlesite-deployed.php # Single-site wp-config (production-style)
│   └── ...
```

---

## Introduction & Audience
This documentation is written for experienced system managers, administrators, operators, and network/system developers; each role can enter at the right layer without losing the dependency chain. Architecture, dependencies, and tradeoffs are defined in `MULTI.md` sections 2–5; operational steps, commands, and validation checks are defined in `Operations.md` sections 3–6. This README only summarizes how to navigate the documentation and scripts.

Recommended entry points by role:
- **System administrators** (network, Cloudflare, Ubuntu, Apache): start with `Operations.md#1-introduction`, then sections 3–6. Operations points you to `HardenUbuntu.md` for the full hardening sequence, then back to `Operations.md#43-origin-certs` to continue.
- **WordPress administrators** (site mapping, content integrity): jump to `Operations.md#5-multisite-ops`.
- **Developers** adapting or extending the scripts: begin with `scripts/Shell.md` and `scripts/Scripts.md`, then `MULTI.md` sections 2–3 for architectural context.

Cloudflare edge behavior must align before origin TLS and vhost wiring can be trusted, and WordPress routing depends on both layers being correct — hence this ordering.

---

## Open Questions, Gaps, and Pending Decisions
Outstanding questions, TODOs, and unresolved design points are tracked per-document rather than duplicated here:
- Documentation ownership/overlap — top of this file's Documentation Map section, and `Operations.md` / `HardenUbuntu.md` directly.
- Cloudflare edge/policy decisions — `Operations.md#345-security-settings`, `Operations.md#35-automation`, `MULTI.md#88-security-hardening`.
- Recording/inventory/automation — `Record.md#open-questions-and-todos`.
- Scripts and validation — `scripts/Scripts.md#todo-revisit`, `CloudflareMCP.md#open-items`.
- Architecture and scaling — `MULTI.md#82-database-isolation--security`, `MULTI.md#85-performance-optimization`, `MULTI.md#810-wordpress-core-update-strategy`, `MULTI.md#8-future-investigation`.
- Performance and telemetry — `Perf.md#mysql-runtime-vs-config-reconciliation`.

---

## References
- [WordPress Multisite Guide] https://developer.wordpress.org/advanced-administration/multisite/create-network
- [WP-CLI Handbook] https://make.wordpress.org/cli/handbook/
- [Cloudflare SSL Modes] https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/
- [Cloudflare Origin Certificates] https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/

---
